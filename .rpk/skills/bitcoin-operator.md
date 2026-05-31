---
name: bitcoin-operator
description: Install and operate the bitcoind daemon and configure the chain-data backend for bitcoin(1)
long_description: Install and operate the bitcoind daemon and configure the chain-data backend for bitcoin(1). Trigger when the user wants to install Bitcoin Core, register bitcoind as a system or user service, start/stop/monitor the daemon, check its disk usage, or switch between the mempool.space, Blockstream, and local bitcoind backends.
role: [operator]
references: bitcoin-wallet
---

# bitcoin-operator

Operate the infrastructure layer of the `bitcoin(1)` educational
wallet: install the `bitcoind` binary, register it as a persistent
service (systemd on Linux, launchd on macOS), and choose which
chain-data backend the wallet queries.

This skill follows the rpk skill convention (see
<https://github.com/nostra124/rpk>, `docs/PACKAGING.md`).

## When to use

Trigger when the user says any of:

- "Install bitcoind", "install Bitcoin Core", "get bitcoind on this machine".
- "Run my own node", "set up a full node".
- "Register bitcoind as a service", "enable/disable the daemon".
- "Start / stop / restart bitcoind".
- "Watch the bitcoind log", "monitor the node".
- "How much disk space is my node using?".
- "Switch to the local node backend", "switch to mempool.space", "use Blockstream".
- "Which backend am I on?", "set the backend to bitcoind / mempool / blockstream".
- "Auto-detect the backend".
- "Set up public RPC", "allow lightning to reach my node", "open RPC to `<CIDR>`".

## The two-layer model

`bitcoin daemon` manages the **process** (install, enable, start, stop, monitor).
`bitcoin backend` manages the **query layer** the wallet uses (mempool, bitcoind, blockstream).

They are independent: the daemon can be running while the backend is set to
`mempool` (perhaps the node is still syncing), and the backend can be set to
`bitcoind` even when `daemon` was not used to install it (e.g., a bare `bitcoind`
started manually).

## Backends

| Name | What it queries | Privacy | Requires |
|---|---|---|---|
| `mempool` | mempool.space API | Low — third party sees your addresses | Internet |
| `blockstream` | blockstream.info API | Low — third party sees your addresses | Internet |
| `bitcoind` | Local node via `bitcoin-cli` | High — you control the node | Running `bitcoind` + `bitcoin-cli` on PATH |

Default resolution order: `$BITCOIN_BACKEND` env var → config file at
`$XDG_CONFIG_HOME/bitcoin/backend` → `mempool`.

`bitcoin backend auto` probes `bitcoin-cli getblockcount`; if it responds it
sets `bitcoind`, otherwise it warns and falls back to `mempool`.

## Workflow recipes

### Install bitcoind

```
bitcoin daemon install                    # platform default (brew on macOS, apt on Debian/Ubuntu)
bitcoin daemon install --from brew        # explicit brew
bitcoin daemon install --from apt         # explicit apt
bitcoin daemon install --from apk         # Alpine
bitcoin daemon install --from source      # clone + build from github.com/bitcoin/bitcoin
bitcoin daemon install --from source --tag v27.0 --prefix /usr/local
```

`--from source` builds from git. Takes ~10–30 min. Requires a C++ toolchain
(`build-essential` / Xcode CLT) and `libboost-dev`.

### Register the daemon as a service (enable)

After `install`, register as a persistent user-level service (no root):

```
bitcoin daemon enable                     # user service, cookie auth, localhost RPC
bitcoin daemon enable --user              # same, explicit
bitcoin daemon enable --system            # system service, dedicated 'bitcoin' account
```

**Enable with public RPC** (for lightning, cluster, or remote `bitcoin-cli`):

```
bitcoin daemon enable --system --public --allow 10.0.0.0/8
```

This generates a `bitcoin.conf` with `rpcauth`, stores the generated password in
`secret:bitcoin/rpc:bitcoin`, and writes `rpcbind=0.0.0.0` + `rpcallowip=<CIDR>`.
Only use `--public` with `--system` and a tightly scoped CIDR.

### Start / stop the daemon

```
bitcoin daemon start                      # user service
bitcoin daemon start --system             # system service
bitcoin daemon stop
bitcoin daemon stop --system
```

### Monitor the log

```
bitcoin daemon monitor                    # user: journalctl --user -u bitcoind -f (Linux)
bitcoin daemon monitor --system           #       journalctl -u bitcoind -f (Linux)
                                          # macOS: tail -f <datadir>/bitcoind.log
```

### Check disk usage

```
bitcoin daemon space                      # prints datadir size (du -sh)
bitcoin daemon space --system
```

A fully synced mainnet node is ~650 GB as of 2026. Pruned mode requires editing
`bitcoin.conf` before first start (`prune=<MiB>`).

### Disable the service

```
bitcoin daemon disable                    # removes unit, stops service
bitcoin daemon disable --system
```

### Choose the chain-data backend

```
bitcoin backend set mempool               # use mempool.space (default)
bitcoin backend set blockstream           # use Blockstream Esplora
bitcoin backend set bitcoind             # use local node (must be reachable)
bitcoin backend auto                      # probe bitcoin-cli; set bitcoind or mempool
```

Config file: `$XDG_CONFIG_HOME/bitcoin/backend` (one word, no newline).

### Typical new-machine sequence

```sh
bitcoin daemon install                    # 1. get bitcoind
bitcoin daemon enable                     # 2. register service (user, cookie auth)
bitcoin daemon start                      # 3. start syncing
bitcoin daemon monitor                    # 4. watch the log — wait for "progress=1.000000"
bitcoin backend set bitcoind              # 5. switch the wallet to the local node
bitcoin backend auto                      # or: auto-detect once in sync
```

## Guardrails

- **Never enable `--public` without `--allow`**: the code enforces this and errors
  out, but clarify the CIDR before running the command — a `0.0.0.0/0` opens RPC
  to the internet.
- **Cookie auth is the safe default** (`enable` without `--public`): `bitcoin-cli`
  in the same user context picks up `.cookie` automatically; no password is needed.
- **`--system` creates a `bitcoin` OS account** and requires `sudo` for several
  steps. Warn the user before running if they are on a shared machine.
- **Do not set `daemon=1` in `bitcoin.conf`** when using the service unit: bitcoind
  would fork, the original PID would exit, the init system would respawn it, and
  two instances would collide on the datadir lock.
- **Pruning cannot be turned on after IBD** without a full re-index. If disk is
  tight, ask the user before `enable`; add `prune=<MiB>` to `bitcoin.conf` first.
- The `secret` store is used to hold public-RPC passwords
  (`secret get bitcoin/rpc:bitcoin`). Do not print raw passwords to stdout.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| `enable: no 'bitcoind' on PATH` | Not installed yet | Run `bitcoin daemon install` first |
| `backend set bitcoind` but wallet still hits mempool | `bitcoin-cli` returns error (node not synced / not running) | Check `bitcoin daemon monitor`; wait for sync |
| `bitcoin-cli` can't connect after `enable --system` | Wrong datadir in `~/.config/bitcoin/bitcoind-datadir` | Run `bitcoin daemon enable --system` again to refresh the pointer |
| `enable --public` without `--system` | `--public` requires `--system` | Re-run with `--system` |
| macOS: service doesn't start after reboot | launchd bootstrap not re-run after OS update | `bitcoin daemon enable` is idempotent; re-run it |
| Source build fails | Missing C++ deps | Install `build-essential libboost-all-dev libssl-dev pkg-config` (Debian) or Xcode CLT + `brew install boost` (macOS) |

## Related skills

- [[bitcoin-wallet]] — wallet operations (derive addresses, send, PSBT, etc.); reads the backend set here.

## Where to read more

- `bitcoin daemon help` — inline help for each subcommand.
- `libexec/bitcoin/daemon` — implementation of all daemon verbs.
- `bin/bitcoin` — `backend:*` functions (lines ~387–600).
- `share/bitcoin/units/` — service unit templates (systemd `.service`, launchd `.plist`).
- Bitcoin Core docs: <https://github.com/bitcoin/bitcoin/blob/master/doc/init.md>
