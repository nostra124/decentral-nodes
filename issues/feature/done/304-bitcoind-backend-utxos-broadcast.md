---
id: FEAT-304
type: feature
priority: medium
status: done
milestone: 3.4.0
---

# Implement the bitcoind backend's `get-address-utxos` + `broadcast`

## Description

**As a** wallet user running my own `bitcoind` as the chain-data backend
**I want** `wallet balance` / `wallet utxos` / `wallet send` to work against it
**So that** I don't need an external indexer (mempool.space / fulcrum) for the
basic on-chain wallet flow

The `bitcoind` backend is currently stubbed — both verbs just return the chain
height:

```sh
backend:bitcoind:get-address-utxos() { backend:bitcoind:chain-height; }   # bin/bitcoin:725
backend:bitcoind:broadcast()         { backend:bitcoind:chain-height; }   # bin/bitcoin:726
```

So `wallet balance`/`utxos` always read empty (the height isn't a UTXO array)
and `wallet send` can't broadcast. The `mempool` and `fulcrum` backends are
fully implemented; only `bitcoind` is missing. Surfaced by the SIT host-side
`02_derive_and_receive` suite (BUG-046), whose balance/UTXO tests are skipped
pending this.

## Implementation

`bin/bitcoin`:
- `backend:bitcoind:get-address-utxos <addr>` — query via `scantxoutset start
  '[{"desc":"addr(<addr>)"}]'` and map the result to the backend-native UTXO
  JSON shape the wallet consumes (`[{txid, vout, value, …}]`). (Note
  `scantxoutset` is a full-UTXO-set scan; acceptable for the educational wallet,
  document the cost.)
- `backend:bitcoind:broadcast <rawhex>` — `sendrawtransaction <rawhex>`,
  returning the txid.
- Reuse the existing bitcoind RPC plumbing (rpc.url / rpc.user / rpc.pass).

## Acceptance Criteria

1. `wallet balance` against the bitcoind backend reports 0 before funding and
   the funded amount after (proven by SIT `02_derive_and_receive`, un-skipped).
2. `wallet utxos` lists the funded outpoint.
3. `wallet send` broadcasts via the bitcoind backend and returns a txid.
4. The `mempool`/`fulcrum` backends are unchanged.

## Resolution

`bin/bitcoin-node`:
- `backend:_bitcoind_rpc <method> <params>` — a JSON-RPC-over-HTTP client
  that reads `rpc.url` / `rpc.user` / `rpc.pass` via the `config` plugin
  (an allowed sibling per CLAUDE.md §4) and POSTs with `curl` + basic auth.
  Carries a `$BITCOIN_BITCOIND_RPC_FIXTURE` test seam mirroring the fulcrum
  backend, so the unit suite exercises the parsing without a node or curl.
- `backend:bitcoind:get-address-utxos <addr>` — `scantxoutset start
  '[{"desc":"addr(<addr>)"}]'`, reshaping the BTC-denominated `.result.unspents`
  into the sat-denominated `{txid,vout,value,status}` shape the wallet already
  consumes from the mempool/fulcrum backends.
- `backend:bitcoind:broadcast <hex>` — `sendrawtransaction <hex>`, surfacing
  the JSON-RPC error message on rejection and validating the returned txid.
- `chain-height`/`estimate-fee`/`get-address-txs` deliberately remain
  "not implemented" stubs (out of this feature's scope; `wallet send` already
  falls back to a default fee rate when `estimate-fee` is unavailable, and a
  full address-tx history needs an index bitcoind lacks by default).

AC coverage:
- [x] (4) `mempool`/`fulcrum` backends untouched.
- [x] (1–3) get-address-utxos + broadcast implemented and unit-tested
      (`tests/unit/bitcoin-02.bats`, FEAT-304 cases: shape mapping, empty set,
      arg validation, transport failure, RPC-error reply, txid round-trip,
      node rejection).
- [~] (1–3) SIT proof: the three `02_derive_and_receive` flows are
      **un-skipped**, but SIT needs podman + a regtest container, which the
      unit-only CI and this cloud sandbox don't provide. **Run
      `make check-sit` on a desktop with podman to confirm end-to-end.**
