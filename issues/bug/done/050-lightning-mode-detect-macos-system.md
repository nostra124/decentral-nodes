---
id: BUG-050
type: bug
priority: high
status: closed
---

# lightning operate verbs always auto-detect user mode on macOS (system_mode is systemd-only)

## Severity

**High.** On macOS, every lightning operate verb (`status`, `monitor`,
`start`, `stop`, `restart`) that is run without an explicit `--system` /
`--user` flag resolves to **user** mode — even when the daemon is installed
as a boot-persistent **system** LaunchDaemon (the 3.1.0 default). The
operator's `lightning daemon monitor` tails `~/.lightning/log` (a stale or
absent user log) instead of the running `/var/lib/lightning/log`, so the
node looks "wrong / in the user home" and the real system instance is
invisible to the operate verbs. No data loss; the workaround is to pass
`--system` on every invocation.

## Observed

Live macOS host, system LaunchDaemon `network.lightning.lightningd`
installed and loaded, no user-mode install:

```
$ lightning daemon monitor
lightning - error: no log file yet at /Users/rene/.lightning/log or
                   /Users/rene/.lightning/bitcoin/log
$ lightning daemon status
down (backend: bitcoind/bcli)
  log: /Users/rene/.lightning/log    # <-- user path, not /var/lib/lightning
```

`daemon:_mode` resolves mode from `system_mode`, which is systemd-only:

```sh
# libexec/lightning/daemon
system_mode() {
	command -v systemctl >/dev/null 2>&1 && \
		systemctl --quiet is-enabled "${LIGHTNING_SVC}.service" 2>/dev/null
}
```

On macOS `systemctl` does not exist, so `system_mode` always returns
false → `daemon:_mode` falls through to `user`.

## Root Cause

`daemon:_mode` (libexec/lightning/daemon:128) decides system-vs-user from
`system_mode`, but `system_mode` only knows how to detect a **systemd**
system unit. It never checks the macOS system LaunchDaemon plist
(`$LIGHTNING_LAUNCHD_DIR/${LAUNCHD_LABEL}.plist`) or the OpenRC init
script. So on macOS (and OpenRC) an installed *system* service is never
recognized by the auto-detect, and operate verbs default to user mode.

## Fix Plan

- `libexec/lightning/daemon`: add a cross-platform `system_installed()`
  helper that is true when a **system**-mode supervisor unit is installed
  on the current platform — macOS LaunchDaemon plist, OpenRC init script,
  or (Linux/systemd) the existing `system_mode` check.
- Point `daemon:_mode`'s auto-detect at `system_installed` instead of
  `system_mode`. Leave the three systemd-labeled `system_mode` call sites
  (start/stop/status, all already inside `is_macos`-guarded branches)
  untouched.

## Regression Protection

`tests/unit/lightning.bats` — force Darwin via the `uname` shim, install a
system LaunchDaemon plist (the seam dir is empty by default), leave no user
agent, and assert a **no-flag** `daemon monitor` resolves the *system*
state dir, never `~/.lightning`:

```bats
@test "BUG-050: macOS operate verbs auto-detect SYSTEM when the LaunchDaemon is installed (no flag)" {
	cat > "$BIN_SHIM/uname" <<'EOF'
#!/bin/sh
[ "$1" = "-s" ] && { echo Darwin; exit 0; }
exec /usr/bin/uname "$@"
EOF
	chmod +x "$BIN_SHIM/uname"
	# A system LaunchDaemon is installed (3.1.0 default); no user agent.
	mkdir -p "$LIGHTNING_LAUNCHD_DIR"
	: > "$LIGHTNING_LAUNCHD_DIR/network.lightning.lightningd.plist"
	rm -rf "$LIGHTNING_LAUNCHAGENTS_DIR"
	export LIGHTNING_SYSTEM_STATE="$BATS_TMPDIR/sysstate.$$"
	rm -rf "$LIGHTNING_SYSTEM_STATE"
	# No --system/--user: must auto-detect system, not fall back to user.
	run "$LIGHTNING_BIN" daemon monitor
	[ "$status" -eq 2 ]
	[[ "$output" == *"$LIGHTNING_SYSTEM_STATE/log"* ]]
	[[ "$output" != *"/.lightning/log"* ]]
}
```

Fails on the broken code (mode=user → tails `~/.lightning/log`), passes
after the fix.

## Acceptance Criteria

1. On macOS with a system LaunchDaemon installed and no user agent, a
   flag-less `daemon monitor` / `status` resolves **system** mode.
2. Pure user-mode installs (no system plist) still resolve **user**.
3. `system_mode`'s systemd-labeled call sites are unchanged; the full
   `lightning.bats` suite stays green.
