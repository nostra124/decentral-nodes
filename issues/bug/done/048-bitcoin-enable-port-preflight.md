---
id: BUG-048
type: bug
priority: high
status: closed
---

# bitcoin daemon enable installs a second node that crash-loops on the RPC port (no preflight)

## Severity

**High.** `bitcoin daemon enable` checks only that a `bitcoind` binary
exists, not that the network's RPC port is free. On a host that already runs
a bitcoind (e.g. an existing MacPorts/Homebrew node on mainnet 8332),
`enable` installs a second service that can never bind the RPC port; under
launchd/systemd `KeepAlive`/`Restart` it crash-loops indefinitely. The
operator sees an endless "Unable to bind any endpoint for RPC server" loop
with no hint that the cause is a port collision.

## Observed

Live macOS host with a MacPorts mainnet bitcoind already on `127.0.0.1:8332`,
after `bitcoin daemon enable --system`:

```
$ bitcoin daemon monitor
2026-06-15T18:35:37Z Binding RPC on address 127.0.0.1 port 8332
2026-06-15T18:35:37Z Binding RPC on address 127.0.0.1 port 8332 failed.
2026-06-15T18:35:37Z Unable to bind any endpoint for RPC server
2026-06-15T18:35:37Z [error] Unable to start HTTP server. See debug log for details.
2026-06-15T18:35:37Z Shutdown: done
# ...launchd respawns; the same failure repeats every ~10s.
$ sudo launchctl print system/org.bitcoin.bitcoind | grep -E 'state|last exit'
	state = spawn scheduled
	last exit code = 1
```

`command:enable` (libexec/bitcoin/daemon) provisions the account, writes the
unit, and starts it without ever checking whether the RPC port is taken.

## Root Cause

`command:enable` has a binary-presence preflight
(`daemon:_bitcoind_candidates`) but no RPC-port preflight. Two mainnet
bitcoinds cannot share port 8332; the second one exits 1 on bind failure and
the supervisor restarts it forever.

## Fix Plan

- `libexec/bitcoin/daemon`: add `daemon:_rpc_port <net>` (network → default
  bitcoind RPC port: 8332/18332/38332/18443) and `daemon:_port_in_use <port>`
  (localhost `/dev/tcp` probe; test seam `$BITCOIN_PORT_BUSY`, authoritative
  when set so the suite is hermetic on a host running bitcoind).
- In `command:enable`, after the binary check, refuse with a clear error and
  non-zero exit when the network's RPC port is already in use — before any
  account/unit provisioning.

## Regression Protection

`tests/unit/streamline.bats` (the bitcoin daemon tier). `feat034_env` exports
`BITCOIN_PORT_BUSY=none` so existing enable tests stay hermetic; the BUG-048
cases set the specific busy port:

```bats
@test "BUG-048 — enable refuses when the RPC port is already in use (no crash-looping unit)" {
	feat034_env linux
	export BITCOIN_PORT_BUSY=8332
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"8332"* ]]
	[[ "$output" == *"in use"* ]]
	[ ! -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
}

@test "BUG-048 — enable proceeds when only a DIFFERENT network's port is busy" {
	feat034_env linux
	export BITCOIN_PORT_BUSY=18443
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	[ -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
}
```

The first fails on the broken code (enable succeeds and installs the unit),
passes after the fix.

## Acceptance Criteria

1. `enable` for a network whose RPC port is already bound exits non-zero,
   names the port, and installs **no** unit.
2. `enable` still proceeds when only a different network's port is busy.
3. The seam keeps the existing FEAT-034 enable tests hermetic on a host that
   is itself running bitcoind.
