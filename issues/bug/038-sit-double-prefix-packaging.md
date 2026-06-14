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

### Known residual (SIT harness, not packaging)

With the above, the image builds, the suites load + execute, and the entrypoint
brings the stack up (log: `SIT stack up: bitcoind + lightningd (alice) +
apache`). The live two-node suite (`ok=3 notok=23 skip=3`) still fails, but on
genuine **harness** issues that are out of scope for a packaging repair and
want their own follow-up:

1. **operator context.** The bats run executes as the container `bitcoin`
   user, but the daemon under test is `alice`'s, so `lightning daemon
   status`/`start` operate on the wrong (absent) daemon. The suites need to run
   in alice's context (or the verbs need an operator selector).
2. **sync timing.** The entrypoint exec's bats as soon as `lightning daemon
   start` returns, while lightningd is still "Still loading latest blocks from
   bitcoind" — `daemon status` is not yet healthy. The bring-up should block
   until lightningd reports synced.
3. **bob's plugins.** `sit_setup_alice_bob` starts a second lightningd whose
   bundled `clnrest` plugin aborts with `No module named 'gevent'`; the image
   needs the plugin's python deps (or to disable clnrest) for the
   channel/pay/walkthrough suites.

These are tracked here but not fixed in this packaging change.

## Regression test

`tests/unit/fulcrum.bats` "FEAT-055 AC1" now fails against the double-prefix
Makefile (the `$prefix/bin/bitcoin` / `lnurlp.conf` assertions) and passes with
the relative-staging fix. The SIT tier (`make check-sit`) builds the
clightning image past the `lnurlp.conf` copy and the suites load + execute.
