---
id: BUG-032
type: bug
priority: high
status: open
---

# lightning daemon (system-mode): hardcoded Intel `/usr/local/var/clightning`
breaks Apple Silicon; service account/unit renamed `clightning` → `lightning`
for consistency

## Severity

**High.** In the default `--system` mode (the 3.1.0 lightning enable
default, FEAT-264/265), the macOS install and monitor paths hardcode
the Intel Homebrew prefix `/usr/local/var/clightning`. On Apple
Silicon (`/opt/homebrew`, and in general any host that does not use
`/usr/local`) the daemon is installed under a path the operator never
expects, and `lightning daemon monitor --system` tails a log that does
not exist there — the user is left with no observability and a state
dir in the wrong place. Separately, the service account/unit/paths are
named `clightning`/`clightningd` while the sibling `bitcoin` and
`fulcrum` daemons use the bare product name (`bitcoin`/`_bitcoin`,
`bitcoind.service`); the inconsistency is a UX and operability defect
for anyone running the combined stack.

## Observed

On macOS Apple Silicon, system mode, `install_macos_system` and
`cmd_monitor` resolve the wrong, Intel-only path:

```
$ lightning daemon enable          # --system is the 3.1.0 default
daemon: info - installed system-mode at /usr/local/var/clightning

$ lightning daemon monitor
daemon: error - system log not found at /usr/local/var/clightning/log
```

`/usr/local/var` is the Intel Homebrew `var`; on Apple Silicon Homebrew
lives at `/opt/homebrew`, and the sibling daemons (bitcoin/fulcrum)
already standardised the system state dir at `/var/lib/<product>` on
*both* OSes. The lightning daemon never followed.

## Root Cause

Two independent but co-located defects in `libexec/lightning/daemon`:

1. **Hardcoded Intel path.** `install_macos_system` (line ~1714) and
   `cmd_monitor` (line ~680) both literally write
   `/usr/local/var/clightning`. There is no OS/arch detection; the
   path is wrong on any host that is not Intel Homebrew. The fix is to
   use `/var/lib/lightning` — the same `/var/lib/<product>` system
   state dir the refactored `libexec/bitcoin/daemon` uses on both
   Linux and macOS (`daemon:_datadir`, BUG-030).

2. **Inconsistent service-account naming.** The dedicated service
   account, group, systemd unit, OpenRC service, and launchd-adjacent
   state dir are all named `clightning`/`clightningd`, diverging from
   the `bitcoin`/`_bitcoin`/`bitcoind.service` convention the rest of
   the stack adopted in 3.0.0 (BUG-030). The clean three-user group
   model itself (dedicated service user + group, operator joins group,
   group-readable 0750 state dir, `sudo tee`/`install` for config) is
   correct and is **preserved unchanged**; only the *names* move:

   | old                              | new                            |
   |----------------------------------|--------------------------------|
   | Linux user+group `clightning`    | `lightning`                    |
   | macOS account `_clightning`      | `_lightning` (UID 297, hidden) |
   | `/var/lib/clightning`            | `/var/lib/lightning`           |
   | `/usr/local/var/clightning`      | `/var/lib/lightning`           |
   | `clightningd.service` (systemd)  | `lightningd.service`           |
   | `/etc/init.d/clightningd` (OpenRC)| `/etc/init.d/lightningd`      |

   The upstream **binary** names `lightningd` / `lightning-cli` are
   left untouched (they are Core Lightning's, not ours). "Core
   Lightning" stays as the human product name in prose / `RealName`.
   The podman *container* default name (`LIGHTNING_PODMAN_NAME`) is
   left as `clightning` — it names the containerized Core Lightning
   image, not our system service account.

## Fix Plan

In `libexec/lightning/daemon` (and the installed mirror at
`~/.local/libexec/lightning/daemon`):

1. **macOS system state dir** — `install_macos_system` and
   `cmd_monitor` use `/var/lib/lightning`, not
   `/usr/local/var/clightning`.
2. **macOS service account** — `_clightning` → `_lightning` (keep
   `IsHidden=1`, `/usr/bin/false`, pinned UID 297). `RealName` may
   stay "Core Lightning daemon".
3. **Linux service account** — `clightning` → `lightning`
   (`useradd --system --user-group lightning`); state dir
   `/var/lib/lightning`; operator joins group `lightning`.
4. **systemd unit** — `clightningd.service` → `lightningd.service`
   (the `system_mode()` is-enabled probe, start/stop/disable, and the
   `journalctl -u` monitor path all follow).
5. **OpenRC** — `/etc/init.d/clightningd` → `/etc/init.d/lightningd`;
   `clightning` user/group → `lightning`.
6. **Docs/templates** — update `docs/templates/CLAUDE.md.lightning`
   §5 three-user table and any man-page/usage strings that assert the
   old account/unit/path names.

No behavior change to the three-user group model or to `--user` mode.

## Regression Protection

`tests/unit/lightning.bats`. A failing-first test pins the macOS
system monitor (and install) to `/var/lib/lightning`:

```bash
@test "BUG-032 — monitor (system, macos) tails /var/lib/lightning, not the Intel path" {
	... stub is_macos true, write /var/lib/lightning/log ...
	run "$LIGHTNING_BIN" daemon monitor --system
	[ "$status" -eq 0 ]
	[[ "$output" != *"/usr/local/var/clightning"* ]]
}
```

This fails against the unmodified code (which resolves
`/usr/local/var/clightning/log`, not found → exit 2). The whole
existing suite pins the old `clightning`/`clightningd` strings; those
assertions are updated to the new names as part of the rename so the
suite stays green and continues to pin the contract.

## Acceptance Criteria

1. `lightning daemon enable --system` on macOS installs at
   `/var/lib/lightning` (no `/usr/local/var/clightning` anywhere).
2. macOS service account is `_lightning` (hidden, UID 297,
   `/usr/bin/false`); Linux account+group is `lightning`.
3. systemd unit is `lightningd.service`; OpenRC service is
   `/etc/init.d/lightningd`; both run as the `lightning` account.
4. `lightning daemon monitor --system` resolves `/var/lib/lightning`
   on macOS and `journalctl -u lightningd.service` on Linux, with no
   sudo (group access).
5. start/stop/status/disable all resolve the new account/unit/path.
6. Upstream binaries `lightningd`/`lightning-cli` and the podman
   container default name are unchanged.
7. `bats tests/unit/lightning.bats` is green, including the BUG-032
   test.

## Follow-up: service-account "can it run the binary" preflight

Extends BUG-032. The system daemon runs `lightningd` as the dedicated
service account (`_lightning` on macOS, `lightning` on Linux). If that
account cannot execute the binary — a bad exec bit, a non-traversable
parent directory, or an unreadable linked dylib (the usual cause is a
restrictive umask on a Homebrew keg under `/opt/homebrew`) — the
launchd/systemd/OpenRC service crash-loops silently with an empty log.

`libexec/lightning/daemon` now runs a preflight that mirrors the bitcoin
daemon's `daemon:_check_runnable`: a new helper `check_runnable
<svc_user> <runner>` runs `<runner> -u <svc_user> "$(command -v
lightningd)" --version >/dev/null 2>&1` and, on failure, `error`s with a
multi-line message naming the account + binary and the fix
(`sudo chmod -R o+rX "$(brew --prefix)"/{Cellar,opt,lib}`), then returns
non-zero. `lightningd --version` loads the main binary + its dylibs,
which catches the common umask/dyld problem (good enough for a
preflight, even though `lightningd` execs subdaemons from its libexec at
runtime).

It is called in all three system installers — `install_macos_system`,
`install_system` (Linux), and `install_openrc_system` — after the
service account is created and the operator joins the group, but BEFORE
the unit is written/loaded. On failure the installer aborts (exit
non-zero) without installing the unit, so no silent crash-loop is left
behind.

Regression test in `tests/unit/lightning.bats`: "BUG-032: enable
(system) refuses to install a unit the service account can't run" stubs
`lightningd` to exit 1 on `--version` and asserts a non-zero exit, a
"cannot run" message, and that no unit file was written. The enable-test
`sudo` stub now strips a leading `-u <user>` so the preflight's
`sudo -u <svc> lightningd --version` execs the stub directly. Verified
fail-before / pass-after.
