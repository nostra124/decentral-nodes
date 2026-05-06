---
id: FEAT-018
type: feature
priority: medium
status: open
---

# Client-side transaction index and labels for tx / UTXO / address

## Description

**As a** wallet user
**I want** the wallet to download every transaction touching its
addresses, store them in the wallet repo, and let me label
transactions, UTXOs, and addresses
**So that** I have a self-contained, decentralised history I can
search, annotate, and carry between accounts via push/pull —
without depending on the backend remembering anything for me.

This extends FEAT-010 (wallet store) with a real transaction index
and FEAT-013 (address labels) with parallel labels for transactions
and UTXOs. The result is that the wallet repo is the user's full
ledger of activity: every tx pulled, every UTXO seen, every label
written down — all version-controlled and pushable.

## Implementation

Layout under the wallet repo (extends FEAT-010):

    transactions/
      <txid>.hex                     raw tx, hex-encoded
      <txid>.json                    decoded tx (txid, vsize, fee,
                                     vin/vout, height when confirmed)
    labels/
      tx                             tab-separated: txid, label
      utxo                           tab-separated: txid:vout, label
      addr                           tab-separated: address, label
                                     (mirrors the `label` column in
                                     `addresses`; this file is the
                                     source of truth, the column is
                                     the materialised join)

`history` (already in FEAT-010) becomes the index: one line per tx
seen, with `<txid>\t<height>\t<direction>\t<amount>` — the link
into `transactions/<txid>.{hex,json}` for full data.

Subcommands:

- `bitcoin wallet index <wallet>` — for every address in the wallet,
  ask the backend for its tx list, download any tx not already in
  `transactions/`, update `history`, and commit. Run after `scan`
  or any time the user wants a fresh pull.
- `bitcoin wallet tx <wallet> <txid>` — pretty-print the decoded tx
  with any associated labels.
- `bitcoin wallet history <wallet> [--label <pattern>]` — list
  transactions, optionally filtered by label match.
- `bitcoin wallet label tx <wallet> <txid> <label>` — set/update.
- `bitcoin wallet label utxo <wallet> <txid:vout> <label>` —
  set/update.

Labels are plain UTF-8, tab-forbidden (since the storage is TSV).
Empty `<label>` clears the entry. All label edits commit one line
each so push/pull conflict resolution is line-granular.

Conflict policy on push/pull (extends FEAT-011):

- `transactions/<txid>.{hex,json}`: identical-content always (txid is
  content hash); a conflict means corruption. Hard error.
- `labels/*`: union with last-writer-wins per row, warn if the same
  key has divergent labels on both sides.
- `history`: union, dedup by txid (already in FEAT-011).

## Acceptance Criteria

1. `bitcoin wallet index alice` after a `scan` downloads the raw and
   decoded form of every tx touching an alice address, into
   `transactions/<txid>.{hex,json}`, and updates `history`.
2. Re-running `index` is a no-op: no new commits, no re-downloads.
3. `bitcoin wallet tx alice <txid>` reads from the local repo, not
   the backend; works offline.
4. `bitcoin wallet label tx alice <txid> "rent payment"` writes to
   `labels/tx`, updates the working tree, and commits one line.
5. `bitcoin wallet history alice --label rent` filters to labelled
   rows.
6. After `wallet push`, the receiving account has every downloaded
   tx and every label.
7. A simulated divergent-label conflict warns, does not lose data,
   and resolves to last-writer-wins per row.
