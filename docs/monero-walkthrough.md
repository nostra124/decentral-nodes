# Monero node walkthrough

This walks the `monero` command from a clean machine to a running,
configured node, mirroring the `bitcoin` and `lightning` walkthroughs. The
3.2.0 milestone ships the **node** surface (install → daemon → config); the
wallet and decentralized-mining surfaces arrive in later releases.

`monero` is a peer command in the combined `bitcoin` rpk package — one
package, one version: `monero version` prints the same string as
`bitcoin version`.

## 1. Install monerod (verified)

```sh
monero install
```

This fetches the official getmonero.org release tarball for your
architecture and **authenticates it before staging anything**:

1. resolves the host arch to a release asset
   (`monero-linux-x64` / `-armv8`, `monero-mac-x64` / `-armv8`);
2. fetches the maintainer (binaryFate) signing key on first use and
   **rejects it unless its fingerprint matches the pinned one**
   (`81AC591F…2A0BDF92`), caching it thereafter;
3. `gpg --verify`s the clearsigned hashes file with that key;
4. checks the tarball SHA256 against the verified hashes;
5. extracts `monerod`, `monero-wallet-rpc`, `monero-wallet-cli`.

Any verification failure aborts with nothing installed (fail-closed). Pin a
specific release with `--version v0.18.3.4`, install into a custom dir with
`--prefix`, or re-install with `--force`.

## 2. Enable the node service

The default is a **boot-persistent `--system` service** under a dedicated
`_monero` (macOS) / `monero` (Linux) account, with a `/var/lib/monero` data
dir and `/etc/monero` config:

```sh
monero daemon enable            # --system is the default
```

Variations:

```sh
monero daemon enable --user            # rootless per-user service (~/.bitmonero)
monero daemon enable --prune           # pruned node (prune-blockchain)
monero daemon enable --stagenet        # parallel stagenet service
monero daemon enable --testnet         # parallel testnet service
```

`enable` provisions the account/group, makes the data dir group-readable so
the operator reaches it **without sudo**, generates a `monerod.conf` with
**restricted RPC bound to `127.0.0.1`**, installs the unit, and starts it.
It **refuses** if the restricted-RPC port is already in use (rather than
installing a unit that would crash-loop on bind).

`--system` is the substrate posture (CLAUDE.md §1); `--user` is the explicit
rootless opt-in for personal/educational, macOS, and CI use.

## 3. Watch it come up

```sh
monero daemon status            # reachable? height? (group-read, no sudo)
monero daemon monitor           # tail the daemon log (group-read, no sudo)
monero daemon space             # data-directory disk usage
```

`status` queries the restricted RPC `get_info`; `monitor` tails the log
directly via group membership — neither prompts for sudo.

## 4. Inspect and tune the config

The **effective** config is the value in `monerod.conf` if set, otherwise
monerod's compiled-in default:

```sh
monero config list                      # NAME<TAB>VALUE<TAB>DESCRIPTION
monero config list | column -t -s$'\t'  # aligned
monero config get rpc-bind-port         # 18081 (default) or the set value
monero config set out-peers 32          # sudo write, 0640, _monero group
monero config unset out-peers           # revert to default
monero config path                      # /etc/monero/monerod.conf
```

`set` writes through `sudo install -m 0640`, preserving the config's
owner:group (no bare redirection), and warns that a restart is needed:

```sh
monero daemon stop && monero daemon start
```

## 5. Networks and pruning at a glance

| Network    | enable flag   | restricted-RPC port | data dir suffix |
|------------|---------------|---------------------|-----------------|
| mainnet    | (default)     | 18081               | (bare)          |
| testnet    | `--testnet`   | 28081               | `/testnet`      |
| stagenet   | `--stagenet`  | 38081               | `/stagenet`     |

A pruned node (`--prune`) keeps roughly a third of the chain on disk while
remaining a fully-validating node — the right default when disk is tight.

## See also

- `monero(1)`, `monero-install(1)`, `monero-daemon(1)`, `monero-config(1)`
- `bitcoin(1)`, `lightning(1)` and their walkthroughs
