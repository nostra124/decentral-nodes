---
id: FEAT-044
type: feature
priority: medium
status: done
---

# Gap-limit walking on `wallet derive`

## Description

**As a** wallet operator who funded an address Sparrow generated
but `bitcoin` never derived
**I want** `bitcoin wallet derive --walk` to find that address
by stepping forward through the derivation path until it sees
`gap` consecutive empty addresses
**So that** I don't lose track of UTXOs at addresses outside our
local ledger.

This is the BIP-44 §address gap-limit convention: when scanning
a wallet from a seed, look ahead by some fixed gap (default 20)
and stop when that many consecutive addresses have no on-chain
history.

## Implementation

### CLI

    bitcoin wallet derive <name> --walk [--gap 20]

Behaviour:

1. Read the highest index already in `<wallet-repo>/addresses`.
   That's the walk's start.
2. For each i from start+1 upward, derive the address at
   `m/84h/0h/0h/0/i` (same path `wallet derive` uses today),
   query `backend:get-address-txs <addr>`, and:
   - If the result is a non-empty JSON array → the address has
     history. Append the row to the addresses ledger, reset
     the empty-counter, continue.
   - If empty → increment the empty-counter; stop when it
     reaches `--gap`.
3. Commit the new ledger rows in one commit ("wallet derive
   --walk: discovered N new addresses").
4. Emit a summary line on stdout:
   `derived: <count_new>; gap-limit reached at index <i>`.

`--gap` defaults to 20 (BIP-44 standard); 0 disables the walk
(equivalent to plain `derive`).

### Idempotency

If the walk discovers no new addresses (i.e. the next 20
addresses are all empty), the verb is a no-op: no commit, no
ledger change, just the summary line.

### Performance

Each address is one `backend get-address-txs` call. For a fresh
wallet, the typical walk is `gap` calls. For a much-used
wallet, it can be hundreds. The mempool.space backend rate-
limits to ~1 req/sec — the walk is intentionally sequential
(no parallelism) so we don't trip it.

## Regression protection

- Existing `wallet derive` (without `--walk`) continues to
  derive one address and return.
- `wallet derive --walk` on an empty / fresh wallet with no
  funded addresses derives 0 addresses (gap satisfied
  immediately).

New bats (with backend mocks):
- Wallet with addresses at indexes 0, 1, 2 (funded), then
  `wallet derive --walk` finds 5 more (index 3..7 funded by a
  third party, index 8..27 empty) and stops at index 27.
- `--gap 5` smaller gap stops earlier.
- `--gap 0` disables the walk (acts like plain `derive`).

## Acceptance criteria

1. `wallet derive --walk` discovers funded addresses beyond
   the current ledger top and appends them to
   `<wallet-repo>/addresses`.
2. The walk stops after `--gap` consecutive empty addresses
   (default 20).
3. New rows commit to the wallet's git repo so push/pull
   carry the discovery.
4. `wallet derive --walk` on a wallet with no out-of-ledger
   discoveries is a no-op (no commit).
5. Bats coverage with mocked backend fixtures.
6. `bitcoin-wallet(1)` documents the new flag per FEAT-041.

## Depends on

- FEAT-013 wallet derive (✅ shipped earlier)
- FEAT-018 backend get-address-txs (✅ shipped 1.17.0)
