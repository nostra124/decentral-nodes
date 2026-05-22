# Roadmap — 1.23.0 (minor)

`bitcoin` adopts a **two-surface command model** — BIP-faithful
`bipXXX` plugins for the educational layer, object verbs (`tx`,
`utxo`, `wallet`, …) for the operational layer. See
`docs/command-surface.md` for the full architecture.

This is the **scaffolding milestone**: it lays the rails for
Sparrow-flex (1.24.0), German tax reporting (1.25.0), and
Schnorr/Taproot (1.26.0). No new cryptographic behavior; no new
BIP implementations; the existing vector suite must pass
byte-for-byte against both old and new verb names.

## Status

| Feature | Status | PRs |
|---------|--------|-----|
| FEAT-035 streamline (psbt→bip174, descriptor→bip380, bech32→bip173/bip350, mnemonic-to-seed fold) | ✅ shipped | #34 (A), #35 (C), #36 (D), #37 (C2), #38 (B) |
| FEAT-041 per-subcommand man-page convention | ✅ shipped | #33 |
| FEAT-038 tax-label vocabulary | ✅ shipped | #40 |
| FEAT-036 `bitcoin tx` object verb | ✅ shipped (all 6 ACs) | #41 (additive), #43 (deprecation + send refactor), #45 (`--utxo` coin-control) |
| FEAT-037 `bitcoin utxo` object verb | ✅ shipped (5 of 7 ACs; AC #4 on hold) | #42 (additive), #44 (`tx build` refuses frozen), #46 (`utxo select` greedy + BnB) |

**AC #4 of FEAT-037** (`wallet index` → `utxo ls` deprecation alias) is on hold pending spec revisit — `wallet:index` caches transactions and updates history; `utxo:ls` lists current unspent outputs. The 1:1 alias from the original spec wouldn't be semantically correct. Documented in `bitcoin-utxo(1)`'s DESCRIPTION.

## What lands

1. **FEAT-035 — command-surface streamline.** Rename `psbt` →
   `bip174`, `descriptor` → `bip380`. Move dispatcher-local
   bech32 helpers into `bip173` / `bip350` plugins. Fold
   `mnemonic-to-seed` under `bip39`. Old names continue to work
   as deprecated aliases that emit a `warn` line and route to
   the canonical verb; aliases removed in 1.24.0.

2. **FEAT-036 — `bitcoin tx` object verb.** Extract
   `wallet build / sign / broadcast` into a `tx`-noun surface:
   `tx build`, `tx sign`, `tx decode`, `tx broadcast`. `wallet
   send` stays as the high-level convenience verb that calls
   the `tx` verbs underneath.

3. **FEAT-037 — `bitcoin utxo` object verb.** Extract `wallet
   index` (the per-wallet UTXO state) into a `utxo`-noun surface:
   `utxo ls`, `utxo freeze`, `utxo unfreeze`, `utxo select`.
   Coin-control foundations for FEAT-014's send-with-selection
   work in 1.24.0.

4. **FEAT-038 — tax-label vocabulary.** Extends `wallet label`
   with a fixed taxonomy: `self-transfer`, `income`, `gift-in`,
   `gift-out`, `purchase`, `sale`, `spend`, `fee`,
   `lending-out`, `lending-in`, `loss-claim`,
   `channel-open` / `channel-close` (for the lightning
   boundary). The labels are persisted on UTXOs and on
   transaction outputs. **No reporting yet** — that's FEAT-039
   in 1.25.0.

5. **FEAT-041 — per-subcommand man-page convention.** Pins
   the format (`groff -man`, matching the existing
   `bitcoin.1`), the naming (`bitcoin-<verb>(1)`, like
   `git-status(1)`), the 10-section structure, and the
   `.so`-include strategy for deprecated aliases. Lands the
   first batch of per-subcommand pages alongside FEAT-035 in
   PR 1; FEAT-036 / 037 / 038 ship their own pages in their
   own PRs. Future verbs (1.24.0+) inherit the convention.

## PR sequence (smallest-first)

| PR | Contains                                          | Notes |
|----|---------------------------------------------------|-------|
| 1  | FEAT-035 streamline + FEAT-041 convention + first man-page batch | Mechanical rename; vector tests prove no behavior change. Ships `bitcoin-bipXXX(1)` for every plugin + `.so`-include alias pages for `psbt` / `descriptor` / `mnemonic-to-seed`. Updates `bitcoin(1)` with a `.SH COMMANDS` cross-reference section. |
| 2  | FEAT-038 tax-label vocabulary + `bitcoin-wallet(1)` / `bitcoin-tax(1)` updates | Pure addition to `wallet label`; no migration of existing labels needed (taxonomy is open-set today, becomes the closed-set going forward with a `--free-text` escape hatch for back-compat). |
| 3  | FEAT-036 `tx` object verb + `bitcoin-tx(1)` + alias pages | Largest extraction; touches build/sign/broadcast call paths. Depends on PR 1's `bip174` rename being in. |
| 4  | FEAT-037 `utxo` object verb + `bitcoin-utxo(1)` + alias page | Extracts `wallet index`; smaller than `tx` but lands after to keep PR 3's diff focused. |

## Depends on

- Nothing outside this repo. Touches existing code paths only;
  no new external services, no new sibling-tool calls.

## Out of scope (later milestones)

| Item | Target |
|------|--------|
| `bitcoin tax report-de` — FIFO + Spekulationsfrist + Anlage-SO PDF + Verlustverrechnung (loss-claim) (FEAT-039) | 1.25.0 |
| BTC/EUR historical price oracle (CoinGecko-cached) (FEAT-040) | 1.25.0 |
| Sparrow-flex: coin control on `wallet send`, fee-bumping (`tx bump` RBF/CPFP), address derivation gap-limit walking | 1.24.0 |
| Schnorr / Taproot — `bip340` / `bip341` / `bip342` plugins (FEAT-007) | 1.26.0 (after the streamline lands so the names slot in cleanly) |
| Hardware-wallet PSBT round-trip (`tx export` / `tx import` over USB or SD) | 1.27.0+ |
| Windows support | not in any current scope |

## Release gate

- `bitcoin bip174 decode` / `bip380 derive` / `bip173 encode` /
  `bip350 encode` / `bip39 mnemonic-to-seed` all work and emit
  identical output to their pre-1.23.0 counterparts on every
  vector in `tests/vectors/`.
- Old names (`psbt`, `descriptor`, `mnemonic-to-seed`) still
  work; each emits one `warn` line naming the canonical form.
- `bitcoin tx build/sign/broadcast` round-trips a regtest send
  end-to-end (uses the FEAT-016 regtest SIT if landed; manual
  walkthrough in the bats log otherwise).
- `bitcoin utxo ls --wallet <name>` lists what `bitcoin wallet
  index --wallet <name>` listed before, in the same order.
- `bitcoin wallet label <wallet> <txid:vout> --tax
  self-transfer` persists the tag and is readable back by
  `wallet label --show`.
- Every verb listed in `bitcoin modules` has a corresponding
  `bitcoin-<verb>(1)` that `man -w` resolves to after `make
  install`; `bitcoin(1)` `.SH COMMANDS` lists them all.
- `man bitcoin-psbt` / `bitcoin-descriptor` /
  `bitcoin-mnemonic-to-seed` render the canonical
  `bitcoin-bip174(1)` / `bitcoin-bip380(1)` / `bitcoin-bip39(1)`
  pages (via `.so` include).
- Pre-push hook + CI green on each milestone PR.

## Why this shape

The streamline isn't visible to end users on day one — the old
names still work. But it's the **only** way to keep the
`bipXXX` surface honest as we add Schnorr/Taproot,
post-quantum signature BIPs, and the BIP-380 descriptor
expansions over the next several releases. Without it, every
new BIP either ships under a contrived object name (today's
`descriptor`, `psbt`) or duplicates implementation. With it,
the dispatcher's job shrinks to routing, and each new BIP
slots in as `libexec/bitcoin/bipXXX` with its own vector file.

Tax reporting (1.25.0) and Sparrow-flex (1.24.0) both depend
on the `tx` and `utxo` verb extractions landing here — they
can't compose what doesn't exist as a noun yet.
