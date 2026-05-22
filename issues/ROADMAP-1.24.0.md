# Roadmap — 1.24.0 (minor)

**Sparrow-flex.** The 1.23.0 milestone landed the rails: a `tx`
verb that builds / signs / broadcasts, a `utxo` verb that lists /
freezes / selects, and the BIP-faithful `bipXXX` plugin surface
underneath. 1.24.0 stitches those into the flows real wallet
operators reach for: coin control on send, fee-bumping when the
mempool clears unfavourably, and a derivation walker that
behaves the same way Sparrow Wallet's "Discover Receive
Addresses" button does.

No new cryptographic primitives. No new BIP implementations.
This is **product polish** on top of the 1.23.0 platform.

## Status

| Feature | Status | PRs |
|---------|--------|-----|
| FEAT-042 coin control on `wallet send` | open | depends on FEAT-036 `tx build --utxo` (✅ shipped in 1.23.0) |
| FEAT-043 `bitcoin tx bump` (RBF + CPFP) | open | depends on FEAT-036 `tx` verb (✅) and FEAT-037 `utxo ls` (✅) |
| FEAT-044 gap-limit walking on derive | open | independent |
| FEAT-035 alias removal (psbt / descriptor / bech32 / mnemonic-to-seed → hard error) | open | 1.23.0 promised removal in 1.24.0 |
| FEAT-037 AC #4 — `wallet index` → `utxo ls` deprecation | on hold | spec mismatch (see ROADMAP-1.23.0 Status note) |

## What lands

1. **FEAT-042 — coin control on `wallet send`.**
   `wallet send <name> <addr> <sats>` learns `--utxo <txid:vout>`
   (repeatable, same shape as `tx build --utxo` from FEAT-036
   AC #3). Forwards to `tx build` unchanged; `wallet send` is
   already the convenience composition. Pair with
   `bitcoin utxo select --target <sats>` to preview a
   branch-and-bound selection, then plumb the chosen outpoints
   into `wallet send --utxo`.

   Acceptance: round-trips a regtest send that uses two
   non-largest UTXOs (greedy would have picked others), proving
   the override sticks all the way through the pipeline.

2. **FEAT-043 — `bitcoin tx bump` (RBF + CPFP).**
   New subcommand on `tx`:

       bitcoin tx bump <wallet> <txid> --rbf [--fee-rate sat/vB]
       bitcoin tx bump <wallet> <txid> --cpfp [--fee-rate sat/vB]

   `--rbf` walks the wallet's `transactions/` cache for the
   target tx, rebuilds it with a higher fee (BIP-125 sequence
   numbers respected; original outputs preserved unless the
   spent UTXO no longer covers the new fee, in which case the
   change output shrinks first), and broadcasts the replacement.

   `--cpfp` picks a confirmed-or-mempool child of the target
   that the wallet owns and rebuilds it spending more of itself
   into fees, effectively pinning the parent. Errors with a
   clear message when no child UTXO is available.

   Both modes pipe through `tx sign` and `tx broadcast` so the
   1.23.0 deprecation rails are exercised end-to-end.

3. **FEAT-044 — gap-limit walking on `wallet derive`.**
   `wallet derive <name>` today appends the *next* index to the
   ledger. Sparrow Wallet's gap-limit convention (BIP-44 §address
   gap-limit) is: when scanning a wallet from a seed, derive
   addresses ahead and probe the backend; stop after seeing
   `gap` consecutive empty addresses (default 20). Adds:

       bitcoin wallet derive <name> --walk [--gap 20]

   which derives forward, queries each address's backend
   history via `backend get-address-txs`, and stops when it has
   seen `--gap` consecutive empties. Used-but-never-derived
   addresses (i.e., addresses Sparrow generated, the user
   funded, and our ledger never knew about) end up in the
   ledger after the walk.

4. **FEAT-035 alias removal.** The 1.23.0 streamline promised
   removal of `psbt` / `descriptor` / `bech32` / `bech32-encode`
   / `bech32-decode` / `bech32-verify` / `mnemonic-to-seed` /
   `wallet build` / `wallet sign` / `wallet broadcast` in 1.24.0.
   Each is a tiny PR — delete the function, delete the `.so`
   man page, update `manpages.bats` to drop the deprecated-alias
   row, and migrate any stale callers in docs / examples.

## PR sequence (smallest-first)

| PR | Contains | Notes |
|----|----------|-------|
| 1  | FEAT-035 alias removal | Pure deletion; vector tests prove no consumer breaks. Builds confidence that the deprecation contract worked. |
| 2  | FEAT-042 coin-control on `wallet send` | One arg-forwarding line in `wallet:send` + bats + man-page update. |
| 3  | FEAT-044 gap-limit walking | Self-contained; doesn't touch `tx` / `utxo`. |
| 4  | FEAT-043 `tx bump --rbf` | Larger; needs BIP-125 sequence-number bookkeeping. |
| 5  | FEAT-043 `tx bump --cpfp` | Builds on PR 4's tx-cache walk. |

## Depends on

- 1.23.0 fully shipped (✅ `tx` / `utxo` verbs + the `bipXXX`
  surface they compose).
- Nothing external. Same backend / no new sibling-tool calls.

## Out of scope (later milestones)

| Item | Target |
|------|--------|
| `bitcoin tax report-de` — FIFO + Spekulationsfrist + Anlage-SO PDF + Verlustverrechnung (FEAT-039) | 1.25.0 |
| BTC/EUR historical price oracle (CoinGecko-cached) (FEAT-040) | 1.25.0 |
| Schnorr / Taproot — `bip340` / `bip341` / `bip342` plugins (FEAT-007) | 1.26.0 |
| Hardware-wallet PSBT round-trip (`tx export` / `tx import` over USB or SD) | 1.27.0+ |
| Windows support | not in any current scope |

## Release gate

- `bitcoin wallet send <name> <addr> <sats> --utxo <txid:vout>`
  builds a tx that spends exactly the listed outpoint(s); the
  resulting PSBT inputs match the user's selection byte-for-byte.
- `bitcoin tx bump <wallet> <txid> --rbf` produces a replacement
  tx with a higher fee, broadcasts it, and the backend's mempool
  reflects the swap on the next `wallet history` poll.
- `bitcoin wallet derive <name> --walk` discovers a previously-
  funded-but-never-derived address within `--gap` consecutive
  empties.
- The 1.23.0 deprecated names (`psbt`, `descriptor`, `bech32*`,
  `mnemonic-to-seed`, `wallet build/sign/broadcast`) now exit
  non-zero with a clear "removed in 1.24.0" message.
- Pre-push hook + CI green on each milestone PR.

## Why this shape

1.23.0 was *infrastructure* — verbs landed but the user-visible
flows still go through `wallet send` and `wallet derive`. 1.24.0
is where those flows pick up the new capabilities (coin control,
fee bumping, gap walking) and the historical names finally go
away. After 1.24.0, the command surface is *clean*: every verb
is at its canonical name, every deprecated alias has reached
end-of-life, and the BIP plugins underneath are still the same
shape they'll be when Schnorr / Taproot lands in 1.26.0.
