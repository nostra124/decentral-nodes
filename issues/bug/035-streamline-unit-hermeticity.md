---
id: BUG-035
type: bug
priority: high
status: open
---

# bitcoin daemon unit tests are non-hermetic: `tests/unit/streamline.bats` fails on a host running the live stack

## Severity

**High.** `tests/unit/streamline.bats` is part of the unit contract for
the `bitcoin` command and runs on every push. On a host that has already
run a live `bitcoin daemon enable --system` deploy — or simply has a real
`bitcoind` installed (MacPorts/Homebrew) and a real `bitcoin`/`_bitcoin`
service account — several daemon tests fail deterministically even though
the code under test is correct. A unit test must not depend on the ambient
state of the host it runs on.

## Observed

On a developer box that runs the live stack (`id bitcoin` resolves, a real
`bitcoind` is at `/opt/local/bin` and `/opt/homebrew/bin`, real `brew` on
PATH), `bats tests/unit/streamline.bats` reports five failures:

```
not ok FEAT-034 — enable --system (linux) creates the bitcoin user and a privileged unit
not ok BUG-030 — enable (system) provisions a dedicated group and joins the operator
not ok FEAT-261 — enable defaults to --system when no mode is given
not ok FEAT-034 — enable errors clearly when bitcoind is absent
not ok FEAT-033 — install errors when the package manager is absent
not ok BUG-015 — space reports the data dir's disk usage
```

## Root Cause

Four independent host-state leaks, each a test-environment defect (the
production code is correct):

1. **Account short-circuit.** `daemon:_ensure_account` (`libexec/bitcoin/
   daemon`) gates account creation on `id "$user" >/dev/null 2>&1 &&
   return 0`. `feat034_env` mocks `useradd`/`usermod`/`dscl`/`chown`/… but
   not `id`, so `id bitcoin` resolves against the real host. With a live
   deploy the account exists, the creation branch is skipped, and the
   `useradd …`/`usermod …` assertions fail (FEAT-034 system, BUG-030 group,
   FEAT-261 default-system).

2. **Absolute bitcoind probe.** `daemon:_bitcoind_candidates` probed the
   hard-coded absolute paths `/opt/local/bin/bitcoind` and
   `/opt/homebrew/bin/bitcoind`, which exist on a host with a real
   install. The "enable errors clearly when bitcoind is absent" test only
   unset `$BITCOIN_BITCOIND`, so a real binary was still found and `enable`
   succeeded instead of erroring.

3. **Real brew on PATH.** `feat033_env` appended its stub dir to the
   inherited `$PATH`. The "install errors when the package manager is
   absent" test removed the stub `brew`, but the host's real `brew` (on the
   inherited PATH) was still found, so the not-found error never fired.

4. **macOS datadir mismatch.** The "space reports the data dir's disk
   usage" test creates `$HOME/.bitcoin` (the Linux user-mode datadir) but
   on a macOS host `daemon:_datadir user` resolves to
   `$HOME/Library/Application Support/Bitcoin`. The created dir is unseen,
   so `space` hits the absent-error path and the test fails.

## Fix

**Production seam (one):** add a `$BITCOIN_SYSTEM_BINDIRS` override to
`daemon:_bitcoind_candidates` in `libexec/bitcoin/daemon`, mirroring
fulcrum's `$FULCRUM_SYSTEM_BINDIRS`. It defaults to
`/opt/local/bin /opt/homebrew/bin`; setting it to the empty string skips
the absolute-dir probe so only PATH is consulted. `$BITCOIN_BITCOIND`
remains the top-priority override. (Mirror the edit into the installed
copy under `~/.local/pkg/bitcoin-*/libexec/bitcoin/daemon`.)

**Test-only fixes (four):**

1. Add an `id` stub to `feat034_env`'s PATH shims: `case "$1" in -*) exec
   /usr/bin/id "$@";; "") exec /usr/bin/id;; *) exit 1; esac`. Any username
   lookup reports not-found (creation branch always runs); flag forms
   (`id -u`, `id -un`) pass through so `daemon:_domain` and the operator
   lookups keep working.
2. In the "bitcoind absent" test, export `BITCOIN_SYSTEM_BINDIRS=""` and
   pin `PATH` to the stub dir plus the system bindirs (no bitcoind on any),
   so both the absolute-dir probe and the PATH probe find nothing. (Also
   align the assertion to the actual error text, `no 'bitcoind' found`.)
3. Pin `feat033_env`'s `PATH` to the stub dir plus the system bindirs only
   (not the inherited PATH), so removing the stub `brew` makes it genuinely
   not-found.
4. In the "space reports" test, export `BITCOIN_DAEMON_OS=linux` so the
   datadir resolves to the `$HOME/.bitcoin` path the test populates.

A `BUG-035 — daemon honors the $BITCOIN_SYSTEM_BINDIRS override` test is
added to lock the new seam: it points the seam at a temp dir holding a
runnable bitcoind, scrubs PATH, and asserts `enable` wires that binary into
the rendered unit's `ExecStart`.

## Acceptance criteria

1. `bats tests/unit/streamline.bats` is fully green (0 failures) on a host
   already running the live stack (real `bitcoin`/`_bitcoin` account, real
   `bitcoind` on `/opt/local` + `/opt/homebrew`, real `brew` on PATH).
2. The only production change is the additive `$BITCOIN_SYSTEM_BINDIRS`
   seam in `daemon:_bitcoind_candidates`; default behavior (MacPorts, then
   Homebrew, then PATH) is unchanged and `$BITCOIN_BITCOIND` stays the
   top-priority override.
3. The remaining fixes are test-only host-state isolation (`id` stub, PATH
   pinning, OS pinning).

## Regression test

The six tests listed under **Observed** are the regression: they failed
against the un-hardened suite on a host running the live stack and pass
once the seam + isolation fixes are in place. The new
`BUG-035 — daemon honors the $BITCOIN_SYSTEM_BINDIRS override` test
demonstrably exercises the new seam.
</content>
</invoke>
