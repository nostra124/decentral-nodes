---
id: BUG-053
type: bug
priority: medium
status: done
---

# `lightning daemon status` fails to report errors for system-mode on macOS

## Severity

Medium. When lightningd crashes in system-mode on macOS, `lightning daemon status` reports "down (backend: ...)" without surfacing the actual error because `report_last_error` looks in the wrong log path.

## Observed

```
~ ❯ lightning daemon status
down (backend: bitcoind/bcli)

~ ❯ lightning daemon start
lightning - warn:  bitcoind isn't reachable — lightningd will likely crash on startup
...
Load failed: 5: Input/output error
```

The actual log is at `/var/lib/lightning/log` for system-mode on macOS, but `report_last_error` only checks `$LIGHTNING_DIR/log` (defaulting to `$HOME/.lightning/log`).

```
~ ❯ tail -5 /var/lib/lightning/log
2026-06-18T07:36:04.741Z **BROKEN** lightningd: FATAL SIGNAL 6 (version v26.04.1)
2026-06-18T07:36:04.742Z **BROKEN** lightningd: FATAL SIGNAL 11 (version v26.04.1)
```

## Root Cause

`report_last_error()` (line 596-607 in `libexec/lightning/daemon`) checks only:
- `$LIGHTNING_DIR/log`
- `$NETWORK_DIR/log`

But for system-mode on macOS, the log is at `/var/lib/lightning/log` (or `/var/lib/lightning/log-$network` for non-bitcoin networks), same as `cmd_monitor` uses.

`cmd_monitor` correctly resolves the system log path (lines 848-860), but `report_last_error` was never updated to match.

## Fix Plan

Update `report_last_error` to check system-mode log path on macOS, mirroring the logic in `cmd_monitor`:
1. If running in system-mode on macOS, check `${LIGHTNING_SYSTEM_STATE:-/var/lib/lightning}/log${sys_suffix}`
2. Otherwise fall back to current `$LIGHTNING_DIR/log` and `$NETWORK_DIR/log`

## Regression Protection

Add test in `tests/unit/lightning.bats`:
- Mock system-mode (`launchd_installed` returns true for `/Library/LaunchDaemons/...`)
- Create log at `/var/lib/lightning/log` with a "BROKEN" line
- Verify `report_last_error` surfaces the error

## Acceptance Criteria

1. `lightning daemon status --system` on macOS with lightningd in system-mode reports errors from `/var/lib/lightning/log`
2. `lightning daemon status` (user-mode) continues to work unchanged
3. Unit test passes