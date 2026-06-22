---
id: BUG-054
type: bug
priority: high
status: done
---

# `lightning daemon status` cannot reach system-mode lightningd RPC

## Severity

High. On a system-mode install, `lightning daemon status` returns "down" even when lightningd is healthy because it looks for the RPC socket at the wrong path.

## Observed

```
~ ❯ lightning daemon status
down (backend: bitcoind/bcli)

~ ❯ ps aux | grep lightningd
_lightning 19048 ... /opt/homebrew/.../lightningd --lightning-dir=/var/lib/lightning --conf=/etc/lightning/config

~ ❯ tail -5 /var/lib/lightning/log
2026-06-22T00:55:01.172Z INFO    plugin-bcli: bitcoin-cli initialized and connected to bitcoind.
2026-06-22T00:55:02.563Z INFO    lightningd: Server started with public key ...
```

The daemon IS running and healthy, but `daemon status` reports "down" because:

1. `cli()` uses `$LIGHTNING_DIR` (default `$HOME/.lightning`)
2. The RPC socket is at `/var/lib/lightning/bitcoin/lightning-rpc` for system-mode
3. `daemon_running()` calls `cli getinfo` which fails to connect

## Root Cause

`cmd_status` detects the mode correctly (`daemon:_mode`), but the `cli()` helper and `LIGHTNING_DIR` default don't adjust for system-mode:

- Line 21: `LIGHTNING_DIR="${LIGHTNING_DIR:-$HOME/.lightning}"`
- Line 65: `cli() { lightning-cli --lightning-dir="$LIGHTNING_DIR" --network="$LIGHTNING_NETWORK" "$@"; }`

The plist sets `--lightning-dir=/var/lib/lightning`, but when the operator runs `lightning daemon status` from their shell, `LIGHTNING_DIR` defaults to `$HOME/.lightning`.

`cmd_monitor` correctly resolves the system log path via `LIGHTNING_SYSTEM_STATE`, but there's no equivalent for the RPC socket.

## Fix Plan

In `cmd_status` (and other operate verbs), when running in system-mode on macOS:
1. Set `LIGHTNING_DIR=/var/lib/lightning` (or `LIGHTNING_SYSTEM_STATE`) before calling `cli()`
2. This matches what `cmd_monitor` does for log files

Alternative: Add a `daemon:_resolve_dir()` helper that mirrors `daemon:_resolve_bitcoin_datadir()` pattern.

## Regression Protection

Add test in `tests/unit/lightning.bats`:
- Mock system-mode plist exists at `$LIGHTNING_LAUNCHD_DIR/network.lightning.lightningd.plist`
- Create RPC socket at `/var/lib/lightning/bitcoin/lightning-rpc`
- Verify `daemon status` finds the daemon (not "down")

## Acceptance Criteria

1. `lightning daemon status` on macOS with system-mode lightningd reports "healthy" when daemon is running
2. `lightning daemon status --system` explicitly requests system-mode RPC socket
3. User-mode continues to work unchanged