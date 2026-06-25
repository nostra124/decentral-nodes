---
id: FEAT-274
type: feature
priority: high
status: open
---

# Cross-daemon RPC auth: bitcoind cookie is group-readable for sibling daemons

## Motivation

In the combined stack, `lightning` and `fulcrum` connect to the local
`bitcoind` for their on-chain leg (CLAUDE.md §0). Under the system
group model each daemon runs as its own dedicated account
(`_bitcoin` / `_lightning` / `_fulcrum`), and bitcoind's cookie is
`0600` by default — so a sibling daemon cannot authenticate. Deploying
the stack on a fresh machine required hand-editing the cookie perms and
group memberships. This wires it automatically.

## Behavior

- **bitcoin `daemon enable --system`** now writes `rpccookieperms=group`
  into the generated `bitcoin.conf` (guarded — only when the resolved
  bitcoind advertises `-rpccookieperms`, i.e. Bitcoin Core 28+). The
  `.cookie` is then created `0640`, group `<svc>`.
- **lightning / fulcrum `daemon enable`** (BUG-033 / BUG-034) add their
  service account to the bitcoin service group (`_bitcoin` on macOS,
  `bitcoin` on Linux) when it exists, and point their backend config at
  the system bitcoind's cookie (`/var/lib/bitcoin/.cookie` +
  `bitcoin-datadir` / `rpccookie`). A sibling then authenticates with
  no credentials of its own.

The result: `rpk install` → `bitcoin daemon install` → `bitcoin daemon
enable` → `lightning/fulcrum daemon enable` yields a cross-wired stack
with no manual steps. Validated live (2026-06-14): all three daemons
running, lightning's bcli and Fulcrum's BitcoinDMgr both authenticated
to the system bitcoind via the group-readable cookie.

## Acceptance Criteria

1. `bitcoin daemon enable --system` against a Core-28+ binary writes
   `rpccookieperms=group`; against an older binary it does not. Proven
   by `tests/unit/streamline.bats` FEAT-274 (stubbed `-help`).
2. The generated `.cookie` is group-readable in system mode.
3. lightning/fulcrum enable best-effort-join the bitcoin group and wire
   their bitcoind backend (see BUG-033 / BUG-034).
4. No manual cookie/group steps are needed to bring the stack up on a
   fresh host.
