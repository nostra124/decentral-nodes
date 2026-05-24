---
id: FEAT-043
type: feature
priority: high
status: done
---

# `bitcoin tx bump` — fee-bumping (RBF + CPFP)

## Description

**As a** wallet operator whose transaction is stuck in the
mempool below the median fee rate
**I want** to bump the fee via Replace-By-Fee (BIP-125) or
Child-Pays-For-Parent
**So that** my payment confirms without me having to hand-craft
a replacement tx in Sparrow Wallet.

## Implementation

### CLI

    bitcoin tx bump <wallet> <txid> --rbf  [--fee-rate sat/vB]
    bitcoin tx bump <wallet> <txid> --cpfp [--fee-rate sat/vB]

`<txid>` must be a tx the wallet originated (its cached PSBT or
final hex must live under `<wallet-repo>/transactions/`, per the
FEAT-018 cache). Errors with a clear "no cached tx" message if
not.

### `--rbf` (Replace-By-Fee per BIP-125)

1. Load the cached tx; verify it set the BIP-125 signal
   (`sequence < 0xfffffffe` on at least one input).
2. Re-emit the tx with:
   - Same inputs, same outputs (unless change runs below dust —
     then the change output shrinks first).
   - Higher fee — at least the bigger of: caller's `--fee-rate`,
     or the active backend's current `estimate-fee 3` plus the
     BIP-125 §3 minimum (replacement fee rate >= original).
3. Pipe through `tx:sign` and `tx:broadcast`. The replacement
   txid is printed on stdout. The wallet's history ledger
   records the replacement linked back to the original.

### `--cpfp` (Child-Pays-For-Parent)

1. Find an unspent output of `<txid>` that the wallet owns
   (walks `utxo ls --include-frozen` and filters by
   prev_txid == `<txid>`).
2. Build a child tx that spends that UTXO entirely into a new
   wallet address, with a fee high enough to lift the parent's
   *effective* fee rate over the target.
3. Pipe through `tx:sign | tx:broadcast`. Both txids are
   printed (parent + child).

If no spendable child UTXO exists (e.g. the original tx paid
out entirely without a change to us), `--cpfp` errors with a
clear message recommending `--rbf` instead.

### Selection of the bump fee

The bump fee defaults to `max(original_fee_rate * 1.5,
backend:estimate-fee 1)` — fast confirmation. `--fee-rate
<sat/vB>` overrides; the verb refuses values lower than the
original tx's effective fee rate (BIP-125 §3).

## Regression protection

- `tx build` / `tx sign` / `tx broadcast` continue to work
  unchanged — `tx bump` is additive.
- The cached-tx walk in `<wallet-repo>/transactions/` reuses
  the FEAT-018 cache format byte-for-byte.

New bats (regtest):
- `tx bump --rbf` on a BIP-125-signaling tx replaces it in
  the mempool; the new txid appears in `wallet history`.
- `tx bump --rbf` on a non-signaling tx errors with the
  signal-missing message.
- `tx bump --cpfp` on a tx with a wallet-owned child UTXO
  builds + broadcasts the child; both txids show up.
- `tx bump --cpfp` on a fully-paid-out tx errors with the
  RBF-recommendation message.
- `tx bump --rbf --fee-rate <too-low>` rejects the request.

## Acceptance criteria

1. `bitcoin tx bump <wallet> <txid> --rbf` replaces an
   RBF-signaling tx in the mempool with a higher-fee version
   and prints the replacement txid.
2. `bitcoin tx bump <wallet> <txid> --cpfp` builds a child
   spending a wallet-owned output of `<txid>` and broadcasts
   it; both parent and child txids land on stdout.
3. Both modes reuse `tx:sign` and `tx:broadcast` end-to-end
   (no PSBT-shaped duplicate code paths).
4. Bats coverage for the success and error cases listed above.
5. `bitcoin-tx(1)` documents the new subcommand per the
   FEAT-041 convention.

## Depends on

- FEAT-036 `tx` verb (✅ shipped 1.23.0)
- FEAT-018 transaction cache (`<wallet-repo>/transactions/`, ✅
  shipped earlier)
- FEAT-037 `utxo ls --include-frozen` for the CPFP child walk
  (✅ shipped 1.23.0)
