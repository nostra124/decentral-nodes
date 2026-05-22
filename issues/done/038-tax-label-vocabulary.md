---
id: FEAT-038
type: feature
priority: medium
status: open
---

# Tax-label vocabulary — closed taxonomy on outpoints

## Description

**As a** German tax-resident user
**I want** to tag each UTXO and transaction with a fixed
taxonomy of tax-relevant categories
**So that** when FEAT-039 (`tax report-de`) runs in 1.25.0, the
labels already exist and the FIFO engine can classify each
disposal without me having to retro-tag two years of history.

The label store exists today (`wallet:label`, `wallet:_label_kv`)
and accepts free-text. This feature adds a **closed taxonomy**
of tax-relevant categories on top of it, while keeping the
free-text path as an escape hatch.

## Implementation

### Taxonomy

A fixed set of categories, persisted alongside the existing
label as a new TSV column:

| Category          | Meaning                                                                |
|-------------------|------------------------------------------------------------------------|
| `self-transfer`   | Move between own wallets/accounts. Not a disposal; basis preserved.    |
| `income`          | Mining, staking, airdrop. Taxable at receipt as Sonstige Einkünfte (§22 EStG). |
| `gift-in`         | Received as a gift. Not income; basis transfers from giver if known, else 0. |
| `gift-out`        | Sent as a gift. Disposal at FMV; Spekulationsfrist applies.            |
| `purchase`        | Buy of BTC for EUR. Establishes basis at receipt.                       |
| `sale`            | Sell of BTC for EUR. Disposal; gain/loss vs FIFO basis.                |
| `spend`           | Pay a merchant in BTC. Disposal at FMV; Spekulationsfrist applies.     |
| `fee`             | On-chain miner fee. Tracked separately; not a disposal of its own.     |
| `lending-out`     | Sent as collateral / loan to a counterparty. Not (always) a disposal — see Verlustverrechnung handling in FEAT-039. |
| `lending-in`      | Returned from lending. Restores basis.                                 |
| `loss-claim`      | Counterparty default / lost keys / theft. Disposal at 0 EUR proceeds; loss for Verlustverrechnung (§23 EStG). |
| `channel-open`    | Funding tx of a Lightning channel. Treated as self-transfer for §23 (no disposal yet). |
| `channel-close`   | Cooperative or force close. Each output classified separately on re-entry to the wallet. |

A `--free-text` escape hatch keeps the existing free-form label
working for non-tax annotations (counterparty names, invoice
IDs, etc.).

### CLI surface

Extends today's `wallet label` (no new top-level command):

    bitcoin wallet label <wallet> <outpoint> --tax <category> [--note <text>]
    bitcoin wallet label <wallet> <outpoint> --free-text <text>
    bitcoin wallet label <wallet> --show [<outpoint>]
    bitcoin wallet label <wallet> --validate

`--show` lists labels (optionally for one outpoint). `--validate`
walks every UTXO + tx-output in the wallet and reports
unlabeled ones — useful before running the 1.25.0 report.

`--tax <category>` errors if `<category>` is not in the closed
set above. The error message lists the valid categories.

### Storage

Existing label store extended with a `tax_category` column.
Backward-compatible: labels without the column read as
`(unlabeled)`. New `wallet label --tax` writes both columns
atomically.

### Convenience shorthand

    bitcoin tax label <wallet> <outpoint> --as <category>

is a synonym for `bitcoin wallet label <wallet> <outpoint>
--tax <category>`. Same backing code; just a more
discoverable entry point for the tax workflow.

## Regression protection

Existing label tests pass — the free-text path is unchanged.

New bats cases:
- `wallet label <outpoint> --tax self-transfer` persists; `wallet
  label --show <outpoint>` reads it back with `tax_category =
  self-transfer`.
- `wallet label --tax not-a-real-category` errors and lists the
  valid set.
- `wallet label --validate` reports a count of unlabeled
  outpoints and exits non-zero if any exist (so a release-time
  pre-report check can gate on it).
- `tax label --as income` is byte-identical to `wallet label
  --tax income`.
- `wallet push` round-trips the new column to a remote and
  `wallet pull` restores it.

## Acceptance criteria

1. The 13-category taxonomy above is encoded as a closed set
   in `bin/bitcoin` and enforced by `wallet label --tax`.
2. Labels are persisted in the wallet's git repo (per FEAT-011)
   so `push` / `pull` carry them across machines.
3. `wallet label --validate` reports unlabeled UTXOs and
   tx-outputs; exits 0 only when every outpoint has a
   category.
4. `tax label` shorthand works as documented.
5. The free-text label path continues to work unchanged.
6. New bats coverage; full suite green.
7. `bitcoin-wallet(1)` is updated to document `label --tax`
   with the full 13-category taxonomy in `.SH OPTIONS`, and
   `bitcoin-tax(1)` is created (initially documenting only the
   `label` shorthand; `report-de` is added in 1.25.0 with
   FEAT-039). Both per the FEAT-041 convention.

## Why now (1.23.0, not 1.25.0)

The taxonomy needs to be in place before the report can be
written — but more importantly, users need to be **labeling as
they go**. Landing this in 1.23.0 means anyone who labels
between 1.23.0 and 1.25.0 has a complete-or-nearly-complete
dataset when the report verb arrives, instead of having to
retro-tag a multi-year history.
