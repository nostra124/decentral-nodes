---
id: FEAT-012
type: feature
priority: high
status: open
---

# Backend abstraction: bitcoind, mempool.space, blockstream.info

## Description

**As a** user
**I want** the wallet to work whether or not I run my own bitcoind
**So that** the educational walkthrough is accessible on a fresh
laptop, while users who do run a node get the trustless experience.

## Implementation

A thin backend layer exposes a fixed verb set; each backend implements
the verbs against its respective transport.

Verbs:

    backend_chain_height                → integer
    backend_get_tx        <txid>        → raw hex
    backend_get_utxos     <descriptor>  → list of {txid, vout, value, height}
    backend_estimate_fee  <target>      → sat/vB
    backend_broadcast     <hex>         → txid

Backends:

- `bitcoind`: shells out to `bitcoin-cli` (path discoverable, RPC
  cookie auth assumed). Uses `scantxoutset` for UTXO discovery.
- `mempool`: REST against mempool.space (`/api/address/...`,
  `/api/tx/...`, `/api/v1/fees/recommended`, `POST /api/tx`).
- `blockstream`: REST against blockstream.info Esplora API (same
  shape as mempool, different host).

Selection:

- `bitcoin backend` prints the active backend.
- `bitcoin backend bitcoind|mempool|blockstream` switches.
- `bitcoin backend auto` (default): pick `bitcoind` if `bitcoin-cli`
  is reachable and accepting commands; else `mempool` with a one-time
  warning that chain state is being trusted to a third party.

Backend choice is per-wallet (stored in the wallet repo) so different
wallets can use different backends.

`bitcoin-cli` is an *optional* runtime dependency — detected at
runtime, not declared in `.rpk/depends/`.

## Acceptance Criteria

1. `bitcoin backend auto` picks `bitcoind` when `bitcoin-cli
   getblockcount` succeeds, `mempool` otherwise, and prints a warning
   in the latter case.
2. `backend_chain_height` returns the same integer (within one block)
   from all three backends against mainnet.
3. The remaining verbs return shape-equivalent data from all three
   backends; a unit test asserts the output shape.
4. Switching backends does not change the wallet's signing or address
   derivation behaviour — only chain queries.
