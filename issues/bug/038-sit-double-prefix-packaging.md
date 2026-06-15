---
id: BUG-038
type: bug
priority: high
status: open
---

# `make install` double-prefixes the stow tree, so `make check-sit` never installs into `$PREFIX`

## Severity

**High.** `make check-sit` (the SIT tier, FEAT-182) builds a clightning +
bitcoind regtest container from the working tree, whose `Dockerfile.clightning`
does `./configure --prefix=/usr/local && make install` and then references the
installed files (e.g. `cp /usr/local/share/lightning/apache/lnurlp.conf …`).
The install silently puts every file at `$PREFIX$PREFIX/…` instead of
`$PREFIX/…`, so the image build fails at the first access of an installed file
and the entire SIT tier is unrunnable locally. Per CLAUDE.md §9 we must be able
to gate on local SIT, not depend on GitHub CI.

## Observed

`make install` stages the stow source tree with **absolute** paths:

```make
@mkdir -p $(BUILD_DIR)$(BINDIR) …      # BINDIR = $PREFIX/bin
```

so with `--prefix=/usr/local` the stow source becomes
`build/bitcoin/usr/local/bin/…`. The recipe then runs `stow -t $(PREFIX)`,
i.e. `stow -t /usr/local`, whose package tree's top entry is `usr`. Stow links
`/usr/local/usr → build/bitcoin/usr`, so the real files land at
`/usr/local/usr/local/share/lightning/apache/lnurlp.conf` and **nothing** is at
`/usr/local/share/…` or on `PATH`. Reproduced on the host:

```
$ ./configure --prefix=/tmp/sitpfx && make install
$ ls /tmp/sitpfx          # only a `tmp` symlink — no bin/, share/, libexec/
tmp -> …/build/bitcoin/tmp
```

The double-prefix bug was noted as "fixed" in `tests/sit/README.md` but never
actually was; the Makefile still double-prefixed, and `tests/unit/fulcrum.bats`
FEAT-055 AC1 pinned the broken absolute staging
(`build/bitcoin$prefix/bin/bitcoin`).

The real `~/.local` install is unaffected because it is produced by `rpk
install` (a `pkg/<name>-<ver>/` layout with symlinks), which does not use this
Makefile's stow path.

## Root cause

Broken hybrid: **absolute** staging paths (`$(BUILD_DIR)$(BINDIR)` = build tree +
`$PREFIX/bin`) combined with `stow -t $(PREFIX)`. The stow source must mirror
`$PREFIX` *relative* (`build/bitcoin/bin`) for `stow -t $(PREFIX)` to map it to
`$PREFIX/bin`.

## Fix

- `Makefile.in`: derive prefix-relative staging dirs
  (`REL_BINDIR = $(patsubst $(PREFIX)/%,%,$(BINDIR))`, etc.) and stage into
  `$(BUILD_DIR)/$(REL_BINDIR)` … so the stow source is `build/bitcoin/{bin,
  libexec,etc,share,share/man}`. `stow -t $(PREFIX)` then installs directly into
  `$PREFIX` (no stow-to-`/`, which is unsafe on a real host). Dirs configured
  outside `$PREFIX` keep their absolute path and are not stow-relocatable — that
  never worked anyway.
- `tests/unit/fulcrum.bats` FEAT-055 AC1: assert the corrected relative staging
  (`build/bitcoin/bin/bitcoin`) **and** the real post-stow contract
  (`$prefix/bin/bitcoin` is executable, `$prefix/share/lightning/apache/
  lnurlp.conf` resolves).
- `tests/sit/podman/Dockerfile.clightning`: add `stow` to the apt set (the
  in-container `make install` is stow-based).

## Further SIT-infra rot uncovered fixing this

Once the image built, the SIT suites still could not run; these were fixed in
the same pass so `make check-sit` actually exercises the stack:

1. **helpers not mounted.** `check-sit` mounted only `tests/sit/suites` at
   `/suites`, but every suite does `load ../helpers`, which resolved to
   `/suites/../helpers` = `/helpers.bash` (absent). Fix: mount the whole
   `tests/sit` tree at `/sit` and run `/sit/suites/*.bats` so `../helpers`
   resolves to `/sit/helpers.bash`.
2. **installed binaries not world-executable.** `make install` stows symlinks
   into `/usr/local` pointing at `/opt/lightning/build`, whose files inherit
   the dev tree's owner/group-only modes (0750/0640). The verbs run as the
   unprivileged `bitcoin`/`alice` users, so `/usr/local/bin/lightning` was
   "Permission denied" (126). Fix: `chmod -R a+rX /opt/lightning/build` after
   `make install` in the Dockerfile.
3. **the stack was never started.** `check-sit` did `podman run … bats …`,
   which *overrides* the image `CMD` that brings up bitcoind + lightningd, so
   the live tests ran against a container with no daemons. Fix: make the
   bring-up script an `ENTRYPOINT` that execs the passed command after the
   stack is up (`exec "$@"` instead of `exec tail -F /dev/null`); the default
   `CMD` keeps the bare `podman run` interactive-idle.

### Harness fixes that followed (so the live suite actually runs)

With the packaging fix the image builds; getting the live suite to *run* then
needed four more harness fixes, all applied here:

1. **operator context.** The bats run executed as the container `bitcoin` user,
   but the daemon under test is `alice`'s, so `lightning daemon status`/`start`
   hit the wrong (absent) daemon. Fix: `check-sit` runs the suites as
   `sudo -u alice -i env LIGHTNING_NETWORK=regtest bash -lc 'bats …'`. The
   daemon-lifecycle "status reports healthy" test passes after this.
2. **sync timing.** The entrypoint exec'd bats as soon as `lightning daemon
   start` returned, while lightningd was still "loading latest blocks". Fix: the
   entrypoint now waits (up to 30 s) until `getinfo` clears its sync warnings;
   the bring-up banner now reads `lightningd up — healthy (… block 101 …)`
   instead of `syncing`.
3. **bob can't daemonize.** `sit_setup_alice_bob` started bob's lightningd with
   `--daemon` but no `--log-file`; CLN 24.11 rejects that (`--daemon needs
   --log-file`). Fix: pass `--log-file="$BOB_DIR/log"`. (The `clnrest`/`wss-proxy`
   "No module named …" lines are non-fatal self-disables, not the blocker.)
4. **bob shut down by cln-grpc.** bob's bundled `cln-grpc` plugin is marked
   "important" and exits (no grpc port configured), taking lightningd down with
   it. Fix: `--disable-plugin=cln-grpc` for bob (the same plugin alice's wiring
   disables, BUG-033).
5. **bootstrap hang.** `lightning daemon stop`→`start` (test 2) hung forever:
   the restart ran `auto_bootstrap_peers`, which `peer bootstrap`s to ~5
   mainnet nodes — unreachable in the container, so it blocked on TCP timeouts.
   Fix: `check-sit` exports `LIGHTNING_NO_BOOTSTRAP=1` (bootstrap is meaningless
   in regtest). The restart round-trip passes after this.
6. **block-sync race.** `sit_mine` mined blocks but returned immediately,
   despite its "returns once they're seen" contract, so `fundchannel`/`listfunds`
   ran before the nodes had followed the new tip and saw zero confirmed UTXOs
   (`Could not afford … 0 available UTXOs`). Fix: `sit_mine` now blocks until
   alice (and bob, if up) report the new blockheight.
7. **stale verbs in the suites.** `02_channel_open_close` / `14_fee_forward`
   called `lightning channels` (no such verb) instead of `lightning channel
   list`. Fixed.
8. **hang guard.** `check-sit` wraps the `podman run` in `timeout` (if present)
   so a hung live-flow test fails the target fast instead of blocking CI.

With 1–8, the bring-up + operator path is fully working and the channel
**open** flow is green end-to-end (alice funds, connects bob, opens + confirms
a real channel).

### Known residual (live-flow speed + per-suite bugs, tracked)

Two things keep the *full* two-node suite from green, both follow-ups:

- **CLN's 30 s bitcoind poll.** With no developer build available
  (`--dev-bitcoind-poll` is rejected by this image's lightningd), the only
  correct option is to wait for the nodes to follow each mined block — ~30 s per
  confirmation. That makes confirmation-heavy tests (channel close, multi-hop
  pay) slow enough to exceed the `timeout` guard. The real fix is a
  fast-polling lightningd (a developer build, or `--dev-bitcoind-poll=1`).
- **per-suite test bugs.** The suites were written but never run green, so they
  carry stale verbs / assumptions (the `channels` typo was one of several
  likely). Each wants a pass once polling is fast enough to iterate on.

## Regression test

`tests/unit/fulcrum.bats` "FEAT-055 AC1" now fails against the double-prefix
Makefile (the `$prefix/bin/bitcoin` / `lnurlp.conf` assertions) and passes with
the relative-staging fix. The SIT tier (`make check-sit`) builds the
clightning image past the `lnurlp.conf` copy and the suites load + execute.
