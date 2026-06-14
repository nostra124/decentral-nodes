---
id: BUG-034
type: bug
priority: high
status: open
---

# fulcrum enable/config: a fresh --system deployment needs five manual fixes before fulcrumd indexes

## Severity

**High.** On a fresh machine the documented happy path —
`fulcrum daemon enable` then `fulcrum config init --system` — does
**not** produce a working indexer. Five separate defects each required
a hand-edit during a real live `--system` deployment before fulcrumd
would start and stay up. Every fix below comes from a step that had to
be performed by hand on that deployment.

(Filed as `033-…` — the next free number under `issues/bug/` is 033,
not 034; the `id:` front-matter keeps the BUG-034 label the work was
tracked under.)

## Observed

```
$ fulcrum config init --system
# scaffolds:  datadir = /Users/rene/.fulcrum
#             rpccookie = /Users/rene/.bitcoin/.cookie     ← USER paths the
#                                                            svc account can't read
#             fast-sync = 1024                             ← removed in Fulcrum 2.x

$ fulcrum daemon enable
# /etc/fulcrum created 0750 root:wheel  → svc "Unable to open config file"
# preflight runs ~/.local/bin/Fulcrum (a symlink to THIS package's bash
#   dispatcher), not the real Electrum server
# svc not in bitcoind's group → can't read the node's group-readable cookie

$ # fulcrumd then refuses to start:
#   "the conf file option `fast-sync` has been removed"
```

## Root Cause / Fix (five parts)

1. **`config init --system` wrote USER paths.** `command:init`
   (`libexec/fulcrum/config`) resolved `datadir` and the cookie path
   unconditionally to `$HOME/.fulcrum` / `$HOME/.bitcoin/.cookie` even in
   `--system` mode, which the dedicated service account cannot reach.
   `config:_datadir` is now mode-aware (system → `/var/lib/fulcrum`,
   mirroring `daemon:_datadir`), and a new `config:_cookie` resolves the
   cookie (system → `/var/lib/bitcoin/.cookie`, the system bitcoind's
   group-readable cookie, FEAT-274). `$FULCRUM_ROOT` prefixes both;
   `$FULCRUM_DATADIR` / `$FULCRUM_NODE_DATADIR` still override.

2. **The scaffold carried the removed `fast-sync` option.** Fulcrum 2.x
   removed `fast-sync`; with it present fulcrumd refuses to start
   ("the conf file option `fast-sync` has been removed"). It is dropped
   from what `config init` writes and from the `CONFIG_ALLOW` edit
   allow-list. `db_mem` (the surviving memory tunable) stays.

3. **The system config dir was not traversable by the service account.**
   `/etc/fulcrum` was created `0750 root:wheel`, so the svc account got
   "Unable to open config file". `command:enable`
   (`libexec/fulcrum/daemon`) now `chown <svc>:<svc>` + `chmod 0755` the
   config dir in system mode, so both the daemon and the operator (a
   group member) can read the conf.

4. **Binary resolution picked the dispatcher over the real server.**
   `daemon:_fulcrumd` did `command -v Fulcrum || command -v fulcrum`,
   which finds `~/.local/bin/Fulcrum` — a symlink to this package's own
   `fulcrum` dispatcher (a bash script), not the Electrum server — so the
   preflight ran the wrong binary. It now prefers the real server in
   known install dirs first (`/usr/local/bin`, `/opt/local/bin`,
   `/opt/homebrew/bin`), then PATH; `$FULCRUM_FULCRUMD` remains the
   highest-priority override. (`$FULCRUM_SYSTEM_BINDIRS` overrides the
   known-dir list for tests.)

5. **The service account couldn't read bitcoind's cookie.**
   `command:enable` now best-effort-adds the svc account to bitcoind's
   service group (`_bitcoin` on macOS via `dseditgroup`, `bitcoin` on
   Linux via `usermod -aG`) so it can read the node's group-readable
   cookie (FEAT-274). Soft system-group op (not a call to the `bitcoin`
   command — allowed for the combined stack under §4). If the group is
   absent it `info`s a hint and continues; it never fails enable.

A `[ "${BASH_SOURCE[0]}" = "$0" ]` guard was added around the dispatch
tail of `libexec/fulcrum/daemon` so a test can source the file to exercise
a single helper (`daemon:_fulcrumd`) without running the lifecycle dispatch.
The dispatcher execs the file (`BASH_SOURCE[0] == $0`), so normal use is
unaffected.

No behavior change in `--user` mode (paths, cookie, and group joins all
stay per-user / no-op).

## Regression Protection

`tests/unit/fulcrum.bats`, eleven BUG-034 tests using the existing mock
harness:

- `config init --system` scaffolds `/var/lib/fulcrum` +
  `/var/lib/bitcoin/.cookie`, NOT user paths; `--user` still scaffolds the
  per-user paths.
- the scaffold contains NO `fast-sync` (keeps `db_mem`); `config set
  fast-sync` is rejected by the allow-list.
- `enable --system` chowns + `chmod 0755`es the config dir.
- `daemon:_fulcrumd` (sourced) resolves a real system Fulcrum ahead of a
  PATH dispatcher shim, falls back to PATH when no system binary exists,
  and honors `$FULCRUM_FULCRUMD` above all.
- `enable --system` best-effort-adds the svc to the bitcoin group
  (`usermod -aG bitcoin fulcrum` / `dseditgroup … _bitcoin`), and does NOT
  fail when the group is absent (still installs the unit).

## Acceptance Criteria

1. `fulcrum config init --system` writes `datadir = …/var/lib/fulcrum` and
   `rpccookie = …/var/lib/bitcoin/.cookie`; never the operator's
   `~/.fulcrum` / `~/.bitcoin/.cookie`.
2. The scaffold contains no `fast-sync`; `db_mem` remains.
3. `fulcrum daemon enable --system` makes the system config dir
   traversable + readable by the service account.
4. `daemon:_fulcrumd` prefers the real Fulcrum in a known system dir over
   a PATH name-collision; `$FULCRUM_FULCRUMD` overrides.
5. `enable --system` best-effort-adds the svc account to bitcoind's group;
   absence of the group does not fail enable.
6. `bats tests/unit/fulcrum.bats` is green except the known
   `_fulcrum`-already-exists / macOS-monitor env artifacts.
