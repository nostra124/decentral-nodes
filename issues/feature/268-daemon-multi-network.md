---
id: FEAT-268
type: feature
priority: medium
status: open
---

# `bitcoin daemon` is network-aware: regtest/testnet/signet run in parallel to mainnet

## Motivation

The daemon was mainnet-only: `enable` installed a single
`org.bitcoin.bitcoind` unit. Running a regtest (or testnet/signet)
node required a hand-rolled launchd/systemd unit, and it would collide
with the mainnet one. Operators want a regtest node running *alongside*
mainnet for development.

## Behavior

`enable` / `disable` / `start` / `stop` / `monitor` take
`--network <net>` where `<net>` is `mainnet` (default) | `testnet` |
`signet` | `regtest`. They share the service account and datadir
(`/var/lib/bitcoin`); bitcoind's own `-chain=<net>` separates each
network's data (its own subdir) and ports, so instances coexist.

Per-network naming (mainnet stays bare for backward compatibility,
others get a `-<net>` suffix):

| | mainnet | regtest |
|---|---|---|
| launchd label | `org.bitcoin.bitcoind` | `org.bitcoin.bitcoind-regtest` |
| systemd unit | `bitcoind.service` | `bitcoind-regtest.service` |
| log | `bitcoind.log` | `bitcoind-regtest.log` |
| pidfile | `bitcoind.pid` | `bitcoind-regtest.pid` |
| ExecStart | (no `-chain`) | `… -chain=regtest` |

The unit templates gained `@LABEL@` / `@CHAIN@` / `@LOG@` / `@PIDFILE@`;
`daemon:_render` substitutes them and, for mainnet, *strips* the
`-chain` argument entirely (an empty launchd `ProgramArguments`
`<string>` would pass bitcoind a bogus `""`).

## Acceptance Criteria

1. `enable --network regtest` installs a parallel suffixed unit
   (`bitcoind-regtest.service` / `org.bitcoin.bitcoind-regtest.plist`)
   whose ExecStart/args carry `-chain=regtest` and a `bitcoind-regtest`
   pid/log. Proven by `tests/unit/streamline.bats` FEAT-268 (linux +
   macos).
2. The mainnet unit carries no `-chain` and the bare label, with no
   empty `<string></string>` arg. Proven by FEAT-268 (macos).
3. regtest and mainnet units coexist (both files present after enabling
   each). Proven by FEAT-268.
4. `enable`/`disable` reject an unknown network with a clear error.
5. `disable --network <net>` / `monitor --network <net>` target the
   suffixed unit/log.
6. Live (2026-06-13): with mainnet `running`, `enable --network
   regtest` installed a parallel unit and started `bitcoind
   -chain=regtest`; it reached RPC bind (failing only because a
   pre-existing dev regtest node held port 18443), and `disable
   --network regtest` removed it cleanly while mainnet kept running.
