---
id: FEAT-059
type: feature
priority: high
status: open
---

# `bitcoin backend set fulcrum` — query the local Electrum server

## Description

**As a** wallet user running my own Fulcrum server
**I want** a `fulcrum` (Electrum-protocol) backend for `bitcoin
backend`
**So that** `wallet balance` / `wallet index` / `broadcast` query my
own node instead of the public mempool.space API.

This is the bitcoin-side half of the Fulcrum integration. The backend
abstraction (FEAT-012) already defines five verbs — `chain-height`,
`get-address-utxos`, `get-address-txs`, `broadcast`, `estimate-fee` —
with `mempool` implemented and `bitcoind`/`blockstream` as stubs. This
feature fills in a `fulcrum` backend that speaks the Electrum protocol
to the server's public `tcp`/`ssl` port (50001/50002).

Crucially, the **no-shared-lib boundary (CLAUDE.md §4)** forbids the
bitcoin backend from shelling out to the `fulcrum` command. So the
Electrum client lives entirely inside the bitcoin backend as its own
duplicated primitive (§5): `fulcrum` runs the server, `bitcoin`
queries it, neither imports the other. This also keeps Fulcrum's
whole-chain indexing external to bitcoin, consistent with the scope
note in CLAUDE.md §1 (bitcoin delegates to an indexer rather than
reimplementing one — exactly as it already does with mempool.space).

Depends on the 2.1.0 milestone (a runnable Fulcrum server). Targets
the 2.2.0 milestone.

## Implementation

Extend the existing `backend` plugin/dispatcher:
- Add `fulcrum` to the backend registry alongside `mempool`,
  `bitcoind`, `blockstream`; `bitcoin backend set fulcrum` writes it to
  `$XDG_CONFIG_HOME/bitcoin/backend`; `backend auto` prefers `fulcrum`
  when its port answers, before falling back to bitcoind/mempool.
- An Electrum-protocol client (newline-delimited JSON over TCP, or TLS
  to the ssl port). Address queries map an address → output script →
  `scripthash` (sha256, reversed) and call:
  - `chain-height` → `blockchain.headers.subscribe` (height field)
  - `get-address-utxos` → `blockchain.scripthash.listunspent`
  - `get-address-txs` → `blockchain.scripthash.get_history`
  - `broadcast` → `blockchain.transaction.broadcast`
  - `estimate-fee` → `blockchain.estimatefee` (→ sat/vB)
- Server address from `$BITCOIN_FULCRUM_ADDR` (default
  `127.0.0.1:50001`); TLS via the ssl port when configured. Every
  connect/parse failure emits an `error` naming the host and the
  failure, mirroring the mempool backend's curl-failure contract.
- Output shapes (JSON fields the wallet consumes: `.value`, the tx
  list) match the mempool backend so `wallet balance`/`index` need no
  changes.

## Acceptance Criteria

1. `bitcoin backend set fulcrum` then `bitcoin backend` reports
   `fulcrum` active. Proven by bats.
2. `get-address-utxos <addr>` against a stubbed Electrum server (canned
   `listunspent` JSON) returns UTXOs whose summed `.value` matches the
   fixture, in the same shape the mempool backend emits. Proven by bats
   stubbing the socket / a fixture responder.
3. `get-address-txs`, `chain-height`, and `estimate-fee` each return
   the fixture-derived value via the corresponding Electrum method.
   Proven by three bats cases.
4. `broadcast <hex>` sends `blockchain.transaction.broadcast` and
   returns the txid from the fixture; a server error reply surfaces as
   an `error` line and non-zero exit. Proven by bats.
5. Any connection/parse failure emits an `error` naming the host and
   the cause, and exits non-zero (no silent empty output). Proven by a
   bats case with no responder.
6. `wallet balance <name>` sums correctly when the active backend is
   `fulcrum` (stubbed), with no change to the wallet code path. Proven
   by a bats wiring test.
7. The backend does not invoke the `fulcrum` command or any forbidden
   sibling — the FEAT-195 boundary test still passes. Proven by the
   existing boundary tests remaining green.
