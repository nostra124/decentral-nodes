---
id: FEAT-301
type: feature
priority: high
status: open
---

# `monero daemon {enable,start,stop,status,monitor}` — system-default monerod service

## Description

**As an** operator deploying a Monero node as a substrate
**I want** `monero daemon` to install/manage a boot-persistent monerod service
**So that** the node survives logout/reboot out of the box, under a dedicated
account, with the same posture as `bitcoin daemon`

This is the core deliverable of 3.2.0. It mirrors the `bitcoin daemon`
abstraction: `--system` default (a dedicated `_monero` account, `/var/lib/monero`
data dir, systemd unit / launchd LaunchDaemon), `--user` as the rootless opt-in,
multi-network, restricted RPC on localhost, optional pruning.

## Implementation

`libexec/monero/daemon` (modeled on `libexec/bitcoin/daemon`):
- **Account/group model** — `daemon:_ensure_account` / `daemon:_join_group`:
  `_monero` hidden account on macOS (`dscl`, IsHidden + pinned UID) /
  `monero:monero` on Linux (`useradd --user-group`); operator joins the group;
  0750 group-readable datadir, 0640 config.
- **Service render** — systemd `monerod.service` (`User=monero`,
  `ExecStart=monerod --non-interactive --config-file=@CONF@ --data-dir=@DATADIR@
  --pidfile=@PIDFILE@`) and a macOS `monerod.plist`, with `@LABEL@`/`@CHAIN@`/
  `@CONF@`/`@PIDFILE@`/`@DATADIR@` placeholders.
- **monerod config** — restricted RPC (`--rpc-restricted-bind-ip=127.0.0.1
  --rpc-restricted-bind-port=<net>`), `--no-igd`, `--prune-blockchain` when
  `--prune`, network flags (`--stagenet`/`--testnet` else mainnet), log file.
- **Multi-network** — `daemon:_network`/`_label`/`_svcname` so stagenet/testnet
  can run alongside mainnet (per-network unit labels), like bitcoin FEAT-268/269.
- **Verbs** — `enable` (install+start+persist), `start`/`stop` (drive the
  installed mode, auto-detected), `status`/`monitor` (group-read of the log/RPC,
  **no sudo fallback**), `space` (datadir usage).
- **Binary resolution** — `daemon:_monerod` preferring `/usr/local`,`/opt/local`,
  `/opt/homebrew` over the PATH dispatcher; `$MONERO_MONEROD` override.
- Test seams (`$MONERO_DAEMON_ROOT`, `$MONERO_SYSTEM_BINDIRS`, launchd dir seams)
  so `monero.bats` is hermetic on a host running the live stack.

## Acceptance Criteria

1. `monero daemon enable` (no flag) installs the **system** unit
   (`/etc/systemd/system/monerod.service` with `User=monero`, or the macOS
   LaunchDaemon running as `_monero`), creates the account/group + datadir, and
   starts it. Proven by `monero.bats`.
2. `monero daemon enable --user` installs the rootless per-user unit (no
   `User=`). Proven by `monero.bats`.
3. `--stagenet` / `--testnet` install a distinctly-labelled service that can
   coexist with the mainnet one. Proven by `monero.bats`.
4. `monero daemon status`/`monitor` read the daemon via group-read with no sudo
   prompt; every failure branch emits a `warn`/`error` naming the condition.
5. monerod runs with restricted RPC bound to localhost; `--prune` adds
   `--prune-blockchain`. Proven by asserting the rendered config/unit.
6. `help enable` names `--system` as the default and `--user` as the opt-in.
