---
id: FEAT-269
type: feature
priority: medium
status: open
---

# `lightning daemon` is network-aware: regtest/testnet/signet run in parallel to mainnet

## Motivation

The Lightning daemon was mainnet-only at the supervisor layer:
`enable` installed a single `lightningd.service`
(`network.lightning.lightningd`). Running a regtest (or
testnet/signet) node alongside mainnet required a hand-rolled
launchd/systemd unit, and it collided with the mainnet one (same unit
name, same config/log file). This mirrors the gap FEAT-268 closed for
`bitcoin daemon`; operators want a regtest Lightning node running
*alongside* mainnet for development.

Per-network state already worked via lightningd's own `--network`
(data under `lightning-dir/<net>`); what was missing was a parallel
*service* per network.

## Behavior

`enable` / `disable` / `start` / `stop` / `status` / `monitor` take
`--network <net>` where `<net>` is `mainnet` (default) | `testnet` |
`signet` | `regtest`. A `lightning:_apply_network` helper parses
`--network <net>` / `--network=<net>` from the args (default: the
current `$LIGHTNING_NETWORK`), normalizes it (`main|mainnet|bitcoin` →
`bitcoin` — CLN's name for mainnet), and resets the network-dependent
globals (`LIGHTNING_NETWORK`, `NETWORK_DIR`, `RPC_FILE`,
`LAUNCHD_LABEL`, `LIGHTNING_SVC`).

They share the service account (`lightning` / `_lightning`) and state
dir (`/var/lib/lightning`); lightningd's own `--network=<net>`
separates each network's data (its own subdir) and ports, so instances
coexist. The system config + log file are also per-network-suffixed so
a parallel regtest unit doesn't clobber mainnet's.

Per-network naming (mainnet stays bare for backward compatibility,
others get a `-<net>` suffix):

| | mainnet | regtest |
|---|---|---|
| launchd label | `network.lightning.lightningd` | `network.lightning.lightningd-regtest` |
| systemd unit | `lightningd.service` | `lightningd-regtest.service` |
| system config | `/var/lib/lightning/config` | `/var/lib/lightning/config-regtest` |
| system log | `/var/lib/lightning/log` | `/var/lib/lightning/log-regtest` |
| ExecStart `--network` | `bitcoin` | `regtest` |

The user-mode sidecars (keepalive/alert/autopilot/etc.) are unchanged
— this feature is only about the main lightningd service.

## Acceptance Criteria

1. `enable --network regtest` (system) installs a parallel suffixed
   unit (`lightningd-regtest.service` on Linux /
   `network.lightning.lightningd-regtest.plist` on macOS) whose
   config/ExecStart carry `network=regtest`. Proven by
   `tests/unit/lightning.bats` FEAT-269.
2. Mainnet `enable` still installs the bare `lightningd.service` /
   `network.lightning.lightningd` (byte-for-byte backward compatible).
   Proven by FEAT-269.
3. `enable`/`start` reject an unknown network with a clear
   "unknown network" error before touching the init system. Proven by
   FEAT-269.
4. regtest and mainnet units coexist (both files present after
   enabling each). Proven by FEAT-269.
5. `disable --network <net>` / `monitor --network <net>` /
   `start`/`stop` target the suffixed unit/log.
</content>
