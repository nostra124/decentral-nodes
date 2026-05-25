---
id: BUG-019
type: bug
priority: high
status: done
---

# daemon enable crash loop — tilde paths, daemon=1, and invalid rpcauth

audit: 2026-05-25

## Severity

**High.** `bitcoin daemon enable` registered the launchd service but
bitcoind immediately entered a crash loop, making the daemon
unusable. The log filled with repeated "Cannot obtain a lock" and
"Unable to start HTTP server" errors.

## Observed

```
$ cat ~/Library/LaunchAgents/org.bitcoin.bitcoind.plist
<string>-datadir=~/.local/var/bitcoin</string>   ← literal tilde

$ bitcoin daemon monitor
Error: Cannot obtain a lock on directory /Users/rene/.local/var/bitcoin
Error: Cannot obtain a lock on directory /Users/rene/.local/var/bitcoin
… (repeats indefinitely)

$ cat ~/.local/var/bitcoin/bitcoind.log
Invalid -rpcauth argument.                        ← malformed auth
Unable to start HTTP server. See debug log for details.
Shutdown in progress…
Shutdown done
Bitcoin Core starting…                            ← KeepAlive restart
Invalid -rpcauth argument.
… (loop)
```

## Root Cause

Three independent defects compounded into the crash loop:

1. **Unexpanded tilde in XDG defaults.** Both `bin/bitcoin` and
   `libexec/bitcoin/daemon` used `: ${XDG_DATA_HOME:="~/.local/var"}`.
   Bash stores the tilde literally when quoted, so `$datadir` was
   `~/.local/var/bitcoin`. The plist template substituted this
   literally, and `launchd` does not expand tilde.
2. **`daemon=1` in generated `bitcoin.conf`.** When bitcoind forks
   to the background, the original PID exits. `KeepAlive=true`
   treats the exit as a crash and spawns another instance. The two
   processes collide on the datadir lock file.
3. **Invalid `rpcauth=bitcoin` in generated config.** The `rpcauth`
   format requires `username:salt$hash`. A bare `rpcauth=bitcoin`
   is syntactically invalid, so the HTTP server fails to start.
   Combined with defect #2, launchd keeps restarting a process
   that immediately fails again.

## Fix Plan

1. Replaced `"~/"` with `"$HOME/"` in all XDG defaults in both
   `bin/bitcoin` and `libexec/bitcoin/daemon`. Also added tilde-
   expansion safety net in `daemon:_datadir()`.
2. Removed `daemon=1` from the generated `bitcoin.conf`. launchd
   and systemd already manage the process lifecycle — forking is
   actively harmful.
3. Removed `rpcauth` entirely from the generated config. `server=1`
   enables cookie auth (a `.cookie` file is auto-generated in the
   datadir), which is simpler and more secure.
4. Changed `command:start` from `launchctl kickstart -k` (which
   races with KeepAlive) to plain `launchctl kickstart`.
5. Added recording of the datadir path to
   `$XDG_CONFIG_HOME/bitcoin/bitcoind-datadir` so `backend:auto`
   can find bitcoind with the custom datadir.

## Regression Protection

- `bitcoin daemon enable` generates a valid plist with expanded paths.
- `bitcoin daemon monitor` shows only normal sync output.
- `bitcoin daemon space` reports actual disk usage.
- `bitcoin backend auto` detects the running bitcoind via the
   recorded datadir and switches to the bitcoind backend.

## Acceptance Criteria

- [x] `bitcoin daemon enable` creates a plist with real paths
      (`/Users/rene/…`, not `~/…`).
- [x] `bitcoin daemon monitor` shows sync progress, not lock errors.
- [x] `bitcoin daemon space` shows non-zero disk usage.
- [x] `bitcoin backend auto` sets the active backend to `bitcoind`.
