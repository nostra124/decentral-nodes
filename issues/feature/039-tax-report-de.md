---
id: FEAT-039
type: feature
priority: medium
status: open
milestone: 1.25.0
---

# `bitcoin tax report-de` — German tax report (§22 / §23 EStG)

## Description

**As a** German tax-resident Bitcoin user
**I want** to generate the FIFO-based private-disposal report
that goes into Anlage SO of my Einkommensteuererklärung
**So that** I can file accurately without paying a
Steuerberater to retype my wallet history.

This is the **reporting** half of the tax workflow. The
**labeling** half is FEAT-038 (lands in 1.23.0); the **price
oracle** is FEAT-040 (lands together with this in 1.25.0).

## Implementation

### CLI surface

    bitcoin tax report-de <wallet> --year <YYYY> [--format csv|md|pdf] [--out <dir>]
    bitcoin tax report-de --all-wallets --year <YYYY>      # aggregate across wallets

Default format: `md` (plus `csv` always — the CSV is the data
of record). `pdf` requires a system `weasyprint` or
`wkhtmltopdf` (warn-and-fall-back-to-md if neither present).

### FIFO engine

For each wallet (or all if `--all-wallets`):

1. Walk every UTXO ever held, ordered by **block timestamp** of
   the funding transaction.
2. For each disposal event (label `sale`, `spend`, `gift-out`,
   `loss-claim`), pop the oldest acquisition(s) needed to cover
   the disposed amount.
3. For each popped acquisition, compute:
   - **Holding days** = disposal date − acquisition date.
   - **Spekulationsfrist** = held > 365 days → tax-free; ≤ 365
     days → taxable (§23 (1) Nr. 2 EStG).
   - **Cost basis EUR** = acquisition amount BTC × historical
     BTC/EUR price on acquisition date (via FEAT-040 oracle).
   - **Proceeds EUR** = disposed amount BTC × historical
     BTC/EUR price on disposal date.
   - **Gain EUR** = proceeds − basis.
4. Aggregate: total taxable gain, total loss, total tax-free
   gain (held > 1 year), net for Anlage SO Zeile 41–44.

### Special handling

| Label              | Treatment                                                                                                                 |
|---------------------|---------------------------------------------------------------------------------------------------------------------------|
| `self-transfer`     | Not a disposal. Basis and acquisition date pass through to the receiving wallet. The aggregator dedupes across wallets.  |
| `income`            | Disposal-on-receipt for the giver (FMV at receipt); fresh acquisition for the receiver at FMV. Reported on a separate §22 EStG section of the output. |
| `gift-in`           | New acquisition; basis = giver's basis if known (via a `--giver-basis <eur>` flag), else 0.                              |
| `gift-out`          | Disposal at FMV; the receiver's basis problem is theirs.                                                                   |
| `lending-out`       | Default: not a disposal (collateral). `--strict-lending` treats it as a disposal at FMV (conservative reading of recent BFH guidance). User chooses; the choice is recorded in the report's narrative. |
| `lending-in`        | Restores basis at the matched `lending-out` basis. Mismatched amounts error and require user reconciliation.              |
| `loss-claim`        | Disposal at 0 EUR proceeds. Loss flows into Verlustverrechnung (§23 (3) S. 7 EStG: only against §23 gains, same year + carryforward). |
| `channel-open`      | `self-transfer` to the channel. No disposal.                                                                              |
| `channel-close`     | Each returned output classified per its label on re-entry. Lightning routing fees are NOT modelled here (out of scope).   |
| `fee`               | Subtracted from proceeds of the parent disposal (§23: incidental costs reduce proceeds).                                  |
| `purchase`          | New acquisition at the labeled EUR amount (if `--basis-eur` provided) or oracle price (default).                          |

### Freigrenze

The €600/yr Freigrenze (§23 (3) S. 5 EStG) is **reported but
not auto-applied across categories** — the user might have
other §23 gains (gold, art, …) outside this wallet, so the
report shows "total §23 gain from BTC: X EUR; Freigrenze
applies if total §23 gain across all sources ≤ 600 EUR".

### Output structure

`<out>/<wallet>-<year>/` contains:

- `disposals.csv` — one row per disposal, columns: `date_acquired`,
  `date_disposed`, `amount_btc`, `basis_eur`, `proceeds_eur`,
  `holding_days`, `gain_eur`, `taxable`, `category`,
  `acquisition_txid:vout`, `disposal_txid:vout`,
  `price_source_acq`, `price_source_disp`.
- `income.csv` — §22 income events (mining, staking, airdrop).
- `summary.md` — Anlage-SO-shaped human-readable summary with
  per-Zeile mapping.
- `anlage-so.pdf` — formatted to mirror Anlage SO §23 (one
  disposals table, signature line, Steuerberater-friendly
  layout). PDF is best-effort; absent if no PDF backend
  installed.
- `narrative.md` — explanation of what `tax report-de` did,
  what assumptions it made (FIFO, strict-lending or not,
  price-source choice), and what the user must check by hand.

### Disclaimer

The report opens with a non-removable disclaimer: this is
not tax advice; the wallet is open-source software with no
warranty; the user is responsible for filing accuracy. Tested
against the Anlage SO format for tax years 2023+; older years
require manual format adjustment.

## Regression protection

Test fixtures: three canned wallets covering different
scenarios:

- **`fixture-buy-hold-sell`** — one purchase, one sale after
  > 1 year. Report: 1 tax-free disposal, 0 taxable.
- **`fixture-spend-within-year`** — one purchase, one spend
  within 365 days. Report: 1 taxable disposal with computed
  gain.
- **`fixture-fifo-stacking`** — three purchases at different
  prices, two partial sales. Report: FIFO consumes oldest
  first; per-disposal basis correct to the satoshi.
- **`fixture-self-transfer-chain`** — wallet A → wallet B
  (self-transfer) → wallet C (self-transfer) → external sale.
  Report (`--all-wallets`): one disposal, basis traced to the
  original acquisition in A.
- **`fixture-lending-roundtrip`** — `lending-out` then
  `lending-in`. Default: no disposal. `--strict-lending`: two
  disposals (out and back in).
- **`fixture-loss-claim`** — `purchase` then `loss-claim`.
  Report: full basis as loss for Verlustverrechnung.
- **`fixture-channel`** — `channel-open` then `channel-close`
  with two outputs (one `spend`, one `self-transfer`).
  Report: one disposal on the `spend` output.

Each fixture has an expected `disposals.csv` checked into
`tests/vectors/tax-report-de/` and compared byte-for-byte.

## Acceptance criteria

1. `bitcoin tax report-de <wallet> --year 2024` produces
   `disposals.csv`, `income.csv`, `summary.md`, and
   `narrative.md` in `--out`'s directory.
2. FIFO is honored on every fixture (oldest acquisition
   popped first; partial pops carry remaining basis forward).
3. Spekulationsfrist: held > 365 days → `taxable=no`; ≤ 365
   days → `taxable=yes`.
4. `--all-wallets` aggregates across all wallets and dedupes
   `self-transfer` chains so the underlying acquisition flows
   through to the eventual external disposal.
5. `--strict-lending` switches lending classification; the
   choice is recorded in `narrative.md`.
6. `loss-claim` produces a row with `proceeds_eur=0` and
   `gain_eur=-basis_eur`.
7. `anlage-so.pdf` renders when a PDF backend is installed;
   absent (with `warn` line) otherwise.
8. The disclaimer paragraph is present at the top of every
   output file and is not configurable away.
9. All seven test fixtures' expected CSVs match
   byte-for-byte.
10. `bitcoin-tax(1)` is extended to document `report-de` in
    full per the FEAT-041 convention — every flag, every output
    file, every fixture's expected behavior, the
    Spekulationsfrist + Verlustverrechnung legal references,
    and the non-removable disclaimer.

## Depends on

- **FEAT-038** (tax-label vocabulary) — landed in 1.23.0.
- **FEAT-040** (BTC/EUR price oracle) — lands together with
  this in 1.25.0.

## Out of scope

- Tax jurisdictions other than DE. The `tax` namespace is open
  for `report-at` (Austria), `report-ch` (Switzerland) etc. in
  future milestones.
- Lightning routing-fee income (a Lightning-side concern, not
  a Bitcoin on-chain concern; see CLAUDE.md §1).
- Automatic filing / ELSTER integration. Out of scope; the
  CSV/PDF are the deliverable, the user files them.
