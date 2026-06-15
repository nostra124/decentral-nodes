---
id: FEAT-304
type: feature
priority: medium
status: open
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
