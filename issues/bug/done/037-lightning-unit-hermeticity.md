---
id: BUG-037
type: bug
priority: high
status: done
---

# lightning daemon unit tests are non-hermetic: `tests/unit/lightning.bats` fails on a host running the live stack

## Severity

**High.** `tests/unit/lightning.bats` is part of the unit contract for the
`lightning` command and runs on every push. On a host that has already run
a live `lightning daemon enable --system` deploy — a real `_lightning`
service account, an installed `/Library/LaunchDaemons/network.lightning.
lightningd.plist`, a real `lightningd` (and the rpk tools `rpk`/`secret`)
on PATH — roughly 42–44 daemon/install tests fail deterministically even
though the code under test is correct. A unit test must not depend on the
ambient state of the host it runs on. This is the lightning analog of
BUG-035 (bitcoin) and BUG-036 (fulcrum).

## Observed

On a developer box that runs the live stack (`dscl . -read /Users/_lightning`
resolves, real `/Library/LaunchDaemons/network.lightning.lightningd.plist`,
real `lightningd` at `/opt/homebrew/bin`, real `rpk`/`secret` at
`~/.local/bin`, `/var/lib/lightning` populated by the running daemon, and a
`de_DE.UTF-8` locale), `bats tests/unit/lightning.bats` fails in these
clusters:

```
# launchd / install-mode resolution pulled in the REAL system plist
FEAT-183 (LaunchAgent + daemon start variants), FEAT-269, FEAT-205,
FEAT-244, BUG-032 (macOS variants)
# install-core + OpenRC paths unreachable on macOS / blocked by a real lightningd
FEAT-207 (rpk / apk / source / podman / OpenRC), platform_id override
# locale-sensitive validator + real `secret`/`rpk` leaking into "clean" PATH
1.2.0 api-recv / api-verify (uppercase / "Bad Name") rejection tests
FEAT-183 daemon start "did not come up" probe
```

## Root Cause

Independent host-state leaks, each a test-environment defect except for two
small additive production seams (the shipping behavior is correct):

1. **launchd path resolution saw the real system plist.** `launchd_plist()`
   and the operate/disable verbs in `libexec/lightning/daemon` hard-coded
   `$HOME/Library/LaunchAgents/...` and `/Library/LaunchDaemons/...`. With a
   real `/Library/LaunchDaemons/network.lightning.lightningd.plist`
   installed, `launchd_installed` returned true even for user-mode tests, so
   installs/operate verbs routed at the real system plist.

2. **macOS system-mode monitor read the real `/var/lib/lightning/log`.**
   `cmd_monitor`'s macOS system branch hard-coded `/var/lib/lightning/log`.
   On a host with the daemon actually running, that log exists, so `monitor
   --system` tailed it (exit 0) instead of the expected "no log → exit 2".

3. **`platform_id`/`is_macos` short-circuit to darwin** before reading the
   faked `LIGHTNING_OS_RELEASE`, so the apk/source/OpenRC install paths were
   unreachable on a macOS host (they errored "not an Alpine/Ubuntu system"
   rather than exercising the Linux package-manager logic).

4. **A real `lightningd`/`rpk` on PATH** tripped `daemon install`'s
   idempotency guard ("already on PATH") and the rpk-on-PATH check, so the
   install-core tests that assume those tools are absent failed.

5. **A real `secret` on PATH** made `cmd_start`'s auto-unlock hook fire and
   `wallet unlock --stored` (a no-op success) return 0 from `cmd_start`
   BEFORE the post-start probe, so "daemon start surfaces the error" never
   reached its `exit 2`.

6. **UTF-8 locale.** Under `de_DE.UTF-8`, `case "$x" in [a-z]…` glob ranges
   collate uppercase letters into the lowercase range, so the api-recv /
   api-verify validators (`[a-z][a-z0-9_-]*`) wrongly accepted capitalised
   input. CI runs in C.

## Fix

**Production seams (two, both additive, in `libexec/lightning/daemon`):**

1. `LIGHTNING_LAUNCHAGENTS_DIR` (default `$HOME/Library/LaunchAgents`) and
   `LIGHTNING_LAUNCHD_DIR` (default `/Library/LaunchDaemons`) globals.
   `launchd_plist()`, every sidecar installer, the operate verbs, and
   `cmd_disable` now route their plist paths through these two vars; no
   function hard-codes the literal Apple paths. (`LIGHTNING_LAUNCHD_DIR` was
   already an install-only local; it is now a global honored everywhere.)
2. `cmd_monitor`'s macOS system branch resolves its log dir through
   `${LIGHTNING_SYSTEM_STATE:-/var/lib/lightning}` (the same seam the system
   installer already uses), so the default is unchanged but tests can
   redirect it.

Both seams are mirrored into the installed copy under
`~/.local/pkg/bitcoin-*/libexec/lightning/daemon`.

**Test-only fixes (in `tests/unit/lightning.bats`):**

1. `setup()` exports `LC_ALL=C`/`LANG=C` (locale hermeticity), pins
   `LIGHTNING_LAUNCHAGENTS_DIR`/`LIGHTNING_LAUNCHD_DIR` under the per-test
   tmp tree so the real system plist is never seen, and hides a host
   `lightningd` by dropping the directories that carry it from PATH (first
   preserving `openssl`, the only external tool that lives only in that dir
   on macOS, by symlinking it into `$BIN_SHIM`). It also drops an `id`
   stub: bare-username lookups report not-found (account-creation branch
   always runs) while flag/no-arg forms pass through to `/usr/bin/id`.
2. `_fake_alpine_os_release` / `_fake_ubuntu_os_release` additionally stub
   `uname -s` → `Linux` (via a shared `_stub_uname_linux`), so
   `platform_id` honors the faked os-release and the apk/source install
   paths actually run; every package manager they touch is already stubbed
   in `$BIN_SHIM`.
3. `_openrc_common_setup` stubs `openrc` on PATH so `init_system` resolves
   to OpenRC on a macOS host (it otherwise has no `/etc/init.d`), making the
   Alpine/OpenRC enable path reachable.
4. The "daemon start surfaces the error", "monitor (system, macOS)", and
   "rpk not on PATH" tests pin `PATH`/`LIGHTNING_SYSTEM_STATE` so a real
   `secret`/`rpk` or the real `/var/lib/lightning` log cannot pollute the
   condition under test — matching the absent-on-CI baseline. The BUG-032
   test additionally asserts the production default is still
   `/var/lib/lightning` (and never the old Intel-Homebrew clightning prefix)
   by grepping the daemon source, so the seam can't mask a default
   regression.

## Acceptance criteria

1. `bats tests/unit/lightning.bats` is green for every daemon/install test
   that was failing on host-state pollution (skips for the genuinely
   Linux/container-only tiers are expected) on a host already running the
   live stack (real `_lightning` account, installed system plist, real
   `lightningd`/`rpk`/`secret` on PATH, populated `/var/lib/lightning`, UTF-8
   locale). The before/after for the BUG-037 clusters is 0 failures.
2. The only production changes are the additive `LIGHTNING_LAUNCHAGENTS_DIR`
   / `LIGHTNING_LAUNCHD_DIR` plist seams and the `LIGHTNING_SYSTEM_STATE`
   route in `cmd_monitor`; default behavior (the real Apple paths,
   `/var/lib/lightning`) is unchanged.
3. The remaining fixes are test-only host-state isolation (`LC_ALL=C`, plist
   seam wiring, `lightningd` hiding, `id` stub, `uname`/`openrc` stubs, PATH
   pinning). No test that genuinely exercises logic is weakened.

## Regression test

The clusters listed under **Observed** are the regression: they failed
against the un-hardened suite on a host running the live stack and pass once
the seam + isolation fixes are in place.

## Notes — genuinely cross-platform tests (skip, not weakened)

A handful of tests are correctly `skip`-guarded because they exercise a
Linux/container dependency that cannot be faithfully simulated on macOS
(e.g. systemd `--user` units, journalctl, a real `/etc/init.d`, or a
podman-free environment). These skip cleanly on macOS and run on the Linux
CI tier; they are not weakened.

## Out of scope — a separate pre-existing product bug surfaced (FEAT-272)

`FEAT-272 — config get falls back to the lightningd default` fails on this
host, and it fails identically against the *un-hardened* suite (verified
against `git show HEAD:tests/unit/lightning.bats`), so it is NOT a BUG-037
hermeticity regression and NOT host-state pollution. It is a real awk
portability bug in `libexec/lightning/config` (a different component, not
touched by BUG-037): `config:_default` ends its parse with
`awk '... print $2; exit } END { exit 1 }'`. Under the host's gawk 5.4.0 the
`END` block runs even after a mid-rule `exit`, so `END { exit 1 }` overrides
the success code — the default value is printed (`val=SILLY-NAME`) but
`config:_default` returns non-zero, so `command:get` takes the "no known
default" warn branch instead of printing it. On CI's awk (`exit` does not run
`END`) it returns 0. Fix belongs in its own bug against
`libexec/lightning/config` (e.g. track a `found` flag and `exit (found?0:1)`
once in `END`), test-driven per `skills/bugs.md`. Left untouched here to keep
BUG-037 scoped to daemon/launchd hermeticity.
