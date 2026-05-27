# Roadmap — 1.25.0 (minor)

**Anlage SO.** The tax workflow has been arriving in pieces: 1.23.0
landed the label vocabulary (FEAT-038), and the BTC/EUR price oracle
(FEAT-040) shipped ahead of schedule in the 1.24.x series. 1.25.0 is
where those two halves meet the thing they were always for — a
FIFO-based German private-disposal report that a tax-resident can hand
to their Steuerberater, or file into Anlage SO themselves.

One feature, deliberately. FEAT-039 is large (a FIFO engine, eight
label treatments, Verlustverrechnung, a PDF backend, and seven
byte-exact fixtures); it earns a milestone of its own. No new
cryptographic primitives and no new BIP implementations — this is a
**reporting** milestone built entirely on shipped rails.

## Status

| Feature | Status | PRs |
|---------|--------|-----|
| FEAT-039 `bitcoin tax report-de` (FIFO + Spekulationsfrist + Verlustverrechnung + Anlage-SO output) | planned | — |
| FEAT-040 BTC/EUR price oracle (`price get/fetch/source/status`) | ✅ shipped ahead of milestone | #58 |
| FEAT-038 tax-label vocabulary (`wallet label --tax`, `tax label`) | ✅ shipped (1.23.0) | — |

## What lands

1. **FEAT-039 — `bitcoin tax report-de`.** The reporting half of the
   tax workflow. CLI:

       bitcoin tax report-de <wallet> --year <YYYY> [--format csv|md|pdf] [--out <dir>]
       bitcoin tax report-de --all-wallets --year <YYYY>

   **FIFO engine.** Walk every UTXO ever held, ordered by funding-tx
   block timestamp. For each disposal (`sale` / `spend` / `gift-out` /
   `loss-claim`), pop the oldest acquisitions needed to cover it and
   compute per lot: holding days, Spekulationsfrist (held > 365 days →
   tax-free per §23 (1) Nr. 2 EStG; ≤ 365 → taxable), cost basis EUR
   and proceeds EUR (both via the FEAT-040 cache — never a live fetch,
   so a report run is reproducible), and the gain.

   **Label treatments.** The eight non-trivial cases from the issue:
   `self-transfer` (basis passes through, deduped across wallets),
   `income` (§22 disposal-on-receipt + fresh acquisition),
   `gift-in` / `gift-out`, `lending-out` / `lending-in`
   (`--strict-lending` toggles the BFH-conservative reading),
   `loss-claim` (proceeds 0, feeds Verlustverrechnung per §23 (3)
   S. 7), `channel-open` / `channel-close`, and `fee` (reduces the
   parent disposal's proceeds).

   **Freigrenze.** The €600/yr threshold is *reported, not
   auto-applied* — the user may have other §23 gains outside the
   wallet, so the report states the BTC §23 total and the condition.

   **Output** under `<out>/<wallet>-<year>/`: `disposals.csv` (the
   record of data), `income.csv` (§22 events), `summary.md`
   (Anlage-SO-shaped, per-Zeile), `narrative.md` (assumptions made),
   and best-effort `anlage-so.pdf` (warn-and-skip if no
   `weasyprint` / `wkhtmltopdf`). Every file opens with the
   non-removable not-tax-advice disclaimer.

## PR sequence (smallest-first)

| PR | Contains | Notes |
|----|----------|-------|
| 1 | FIFO core + `disposals.csv` + simple fixtures | `fixture-buy-hold-sell`, `fixture-spend-within-year`, `fixture-fifo-stacking`. Proves Spekulationsfrist + oldest-first popping to the satoshi. |
| 2 | Label treatments + their fixtures | `lending-roundtrip` (+ `--strict-lending`), `loss-claim`, `channel`. Each fixture's expected CSV checked in. |
| 3 | `--all-wallets` aggregation | `fixture-self-transfer-chain`: A→B→C→external, one disposal traced to A's acquisition. |
| 4 | Rendering: `summary.md`, `narrative.md`, `income.csv`, disclaimer | The human-readable surface + §22 income section. |
| 5 | `anlage-so.pdf` (best-effort) + `bitcoin-tax(1)` report-de man page | PDF degrades to md when no backend; man page per the FEAT-041 convention (every flag, every output file, the legal references). |

## Depends on

- **FEAT-038** tax-label vocabulary — ✅ shipped (1.23.0). Disposals are
  classified off the labels this feature persists.
- **FEAT-040** BTC/EUR price oracle — ✅ shipped (#58). The FIFO engine
  reads cost basis and proceeds from its cache; the report makes **no**
  network calls, so a warm cache means reproducible, auditable output.
- Nothing external. No new sibling-tool calls, no new backend.

## Out of scope (later milestones)

| Item | Target |
|------|--------|
| Other jurisdictions — `tax report-at` (Austria), `report-ch` (Switzerland) | future |
| Lightning routing-fee income (a Lightning-side concern, CLAUDE.md §1) | n/a (`lightning`) |
| Automatic filing / ELSTER integration | out of scope — CSV/PDF are the deliverable |
| Schnorr / Taproot — `bip340` / `bip341` / `bip342` (FEAT-007) | 1.26.0 |
| Hardware-wallet PSBT round-trip (`tx export` / `tx import`) | 1.27.0+ |

## Release gate

- `bitcoin tax report-de <wallet> --year 2024` writes `disposals.csv`,
  `income.csv`, `summary.md`, `narrative.md` into `--out`.
- All **seven** fixtures' expected `disposals.csv` match byte-for-byte.
- Spekulationsfrist: held > 365 days → `taxable=no`; ≤ 365 → `taxable=yes`.
- `--all-wallets` dedupes `self-transfer` chains so basis flows through
  to the eventual external disposal.
- `--strict-lending` switches lending classification and records the
  choice in `narrative.md`.
- `loss-claim` produces a `proceeds_eur=0`, `gain_eur=-basis_eur` row.
- `anlage-so.pdf` renders when a PDF backend is present; absent (with a
  `warn` line) otherwise.
- The disclaimer is present at the top of every output file.
- `bitcoin-tax(1)` documents `report-de` in full.
- Pre-push hook + CI green on each milestone PR.

## Why this shape

The tax workflow was always a three-legged stool: a vocabulary to
classify history (FEAT-038), prices to value it (FEAT-040), and an
engine to turn both into a filing (FEAT-039). The first two legs are
already under the floor — FEAT-038 since 1.23.0, FEAT-040 shipped early
because its consumer needed a stable cache contract to test against.
1.25.0 sets the third leg. Because the report reads only the local
price cache and the on-disk label store, it stays true to the repo's
educational, auditable, offline-after-warm posture: the same wallet and
the same cache produce the same Anlage SO, every run.
