---
id: FEAT-036
type: feature
priority: high
status: done
---

# `bitcoin tx` — transaction as a first-class object verb

## Description

**As a** wallet operator
**I want** to work with transactions as a noun (`tx build`, `tx
sign`, `tx decode`, `tx broadcast`) instead of as a wallet
subverb
**So that** I can compose flows Sparrow Wallet expects —
build-now-sign-later, sign-without-broadcasting, decode-an-unknown-hex,
broadcast-a-PSBT-someone-else-signed — without going through
`wallet send`'s opinions.

`wallet send` stays as the high-level convenience verb (it's
what most users want), but it calls the `tx` verbs underneath
rather than implementing the pipeline inline.

## Implementation

### New top-level command

    bitcoin tx build <wallet> <addr> <sats> [--fee-rate sat/vB] [--utxo <txid:vout>]...
    bitcoin tx sign <wallet>              # PSBT hex on stdin → signed PSBT on stdout
    bitcoin tx decode                     # PSBT hex on stdin → human-readable TSV
    bitcoin tx broadcast <wallet>         # raw tx hex on stdin → txid via active backend
    bitcoin tx finalize                   # PSBT hex on stdin → raw tx hex
    bitcoin tx extract                    # signed PSBT hex on stdin → raw tx hex

`tx build` defaults to greedy largest-first selection (matching
today's `wallet build`); `--utxo` repeated overrides selection
with explicit coins (foundation for FEAT-037 coin control).

`tx sign` reads the wallet's seed via `secret get <wallet>/seed`
(no change to the seed-storage policy in CLAUDE.md §2), derives
the relevant privkeys, and calls `bip174 sign` (post-FEAT-035
rename).

`tx decode` is operator-friendly: TSV columns are `field`,
`value`, `comment` — same shape that today's `psbt decode` emits
under the hood.

### What moves out of `wallet`

| Today                                | Tomorrow                                    |
|---------------------------------------|----------------------------------------------|
| `wallet:build` (bin/bitcoin)          | `tx:build` (bin/bitcoin); `wallet:build` becomes a deprecated alias for one release. |
| `wallet:sign`                         | `tx:sign`; `wallet:sign` deprecated alias. |
| `wallet:broadcast`                    | `tx:broadcast`; `wallet:broadcast` deprecated alias. |
| `wallet:send` (full pipeline)         | `wallet:send` stays — but its body becomes `tx build | tx sign | tx broadcast`. |

### What does NOT move

- `wallet new / ls / rm / push / pull / balance / history /
  derive / addresses / label / remote` all stay as `wallet:*`
  — they're wallet-lifecycle, not transaction operations.

### Logging

`tx build` warns if the selected UTXO set leaves change below
the dust threshold. `tx broadcast` errors with the backend's
RPC error verbatim plus a `error` line naming the failing
backend. Per `skills/logging.md` §4.

## Regression protection

`wallet send` round-trips a regtest payment end-to-end after
the refactor — the bats coverage that today exercises
`wallet build | wallet sign | wallet broadcast` must pass
unchanged after the names migrate.

New bats cases:
- `tx build` greedy selection produces identical bytes to
  pre-1.23.0 `wallet build` for a canned UTXO set.
- `tx sign` on a single-input v0 P2WPKH PSBT produces identical
  signed bytes to pre-1.23.0 `wallet sign`.
- `tx decode` of a multi-input PSBT lists all inputs in
  prev_txid:vout order.
- `tx build --utxo <txid:vout> --utxo <txid:vout>` honors the
  explicit selection (sum of supplied UTXOs ≥ sats + fee).
- Deprecated `wallet build` emits a `warn` line citing `tx
  build`; produces identical output.

## Acceptance criteria

1. `bitcoin tx build / sign / decode / broadcast / finalize /
   extract` exist as documented and produce the same outputs
   as their pre-1.23.0 `wallet *` and `psbt *` predecessors on
   the bats vector set.
2. `bitcoin wallet send` is implemented as a three-step
   composition of `tx build | tx sign | tx broadcast` and the
   end-to-end test passes.
3. `bitcoin tx build --utxo <txid:vout>` accepts repeated
   `--utxo` flags and uses only those UTXOs (errors if the sum
   is insufficient for `<sats>` + estimated fee).
4. `wallet build`, `wallet sign`, `wallet broadcast` continue
   to work as deprecated aliases that emit one `warn` line
   each and forward to the `tx` verb.
5. The dispatcher contract test (FEAT-027) is updated to
   include the `tx` namespace.
6. `tx sign` reads the seed via `secret get`, never reads any
   privkey from disk or args.
7. Ships `share/man/man1/bitcoin-tx.1` per the FEAT-041
   convention (10-section structure; SEE ALSO cross-refs
   `bitcoin-bip174(1)`, `bitcoin-utxo(1)`, `bitcoin-wallet(1)`).
   Deprecated `wallet build / sign / broadcast` aliases each
   get a `.so`-include alias page.
