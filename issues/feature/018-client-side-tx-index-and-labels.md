---
id: FEAT-018
type: feature
priority: medium
status: open
milestone: 1.27.0
---

## Progress (1.19.0 shipped — labels + history filter; AC 7 still deferred)

Six of seven acceptance criteria are closed; only AC 7
(push/pull conflict resolution for divergent labels) remains
open. That last item pairs with FEAT-011's deferred custom
merge resolvers and is its own session of work.

- **`bitcoin wallet label <kind> <name> <key> <text>`** with
  three kinds — `tx`, `utxo`, `addr`:
  - `tx <txid>` → row in `labels/tx` (TSV: `txid\ttext`)
  - `utxo <txid:vout>` → row in `labels/utxo`
  - `addr <addr>` → 3rd column of the `addresses` ledger
    (pre-1.19.0 storage; preserved for backward compatibility)
  Empty `<text>` clears the entry. Tabs and newlines in the
  text are rejected (storage is TSV). Each edit commits one
  line so push/pull conflict resolution stays line-granular.

- **Backward-compat:** `wallet label <name> <addr> <text>`
  (pre-1.19.0 3-arg form, no `<kind>` prefix) keeps working —
  the dispatcher routes it as `wallet label addr ...`. The
  pre-existing FEAT-013 bats test for the addr label passes
  unmodified, confirming compat.

- **`bitcoin wallet history <name> [--label <pattern>]`**
  learns a `--label` filter. The filter loads `labels/tx` into
  an awk map and keeps history rows whose tx-label contains
  `<pattern>` as a case-insensitive substring. Rows without a
  matching label are dropped. No labels file → empty output.

- **`bitcoin wallet tx <name> <txid>`** gains a third output
  section, `=== labels ===`, after the existing decoded + hex
  sections. Lists the tx label (if any) and every utxo label
  whose key has the same `txid:` prefix. The section is
  suppressed entirely when no labels match.

10 new bats tests for the label expansion + history filter +
tx labels section, all of which pass alongside the 7 pre-1.19.0
FEAT-018 tests (so the read path stays intact). Total bats now
164.

### 1.17.0 progress (read path)

Acceptance criteria 1, 2, 3, and 6 (the read path + idempotency)
are closed. Criteria 4, 5, and 7 (label expansion and push/pull
conflict resolution) remain open; they need a breaking restructure
of the existing `wallet label <name> <addr> <text>` signature and
pair naturally with FEAT-011's deferred custom merge resolvers.

- **`backend get-address-txs <addr>`** (extends FEAT-012) returns
  every tx touching `<addr>` as a JSON array. mempool
  implementation hits `/api/address/<addr>/txs`; bitcoind /
  blockstream stubs match the other-verb "not implemented"
  pattern. 3 new backend bats tests.

- **`bitcoin wallet index <name>`** walks the wallet's `addresses`
  ledger, asks the backend for every tx touching each address,
  and caches both forms under `<wallet>/transactions/`:
  - `<txid>.json` — the backend's decoded tx record (the entry
    from `get-address-txs` filtered by txid).
  - `<txid>.hex` — the raw tx, fetched from
    `$BITCOIN_MEMPOOL_URL/api/tx/<txid>/hex`.

  After all addresses are processed, the `history` ledger is
  rebuilt from the union of cached transactions as:
  `<txid>\t<height>\t<direction>\t<net_sats>`. Direction is
  `in` / `out` / `self` based on whether the tx's vin entries
  reference wallet-owned addresses and the net is computed via
  jq from `vout_to_us - vin_from_us`. The result is committed
  in one wallet git commit; re-runs are idempotent
  (per-`<txid>` cache files gate the download, and the history
  rebuild is content-stable, so the second commit is a no-op).

- **`bitcoin wallet tx <name> <txid>`** reads from the local
  cache only — works offline. Errors clearly if the txid is
  not yet indexed.

- **`bitcoin wallet history <name>`** cats the history ledger.

7 new bats tests for the wallet verbs: tx cache files present;
history line shape matches `<txid>\t<height>\t<dir>\t<net>`;
re-running index is a no-op git commit; `wallet tx` prints both
hex and json; `wallet tx` works without backend access (cache-
only); `wallet tx` rejects un-indexed txids; `wallet index`
rejects missing wallets. Total bats now 146.

### Deferred to ROADMAP-1.20.0+

- **AC 7** — push/pull conflict resolution for divergent
  labels. Pairs with FEAT-011's deferred custom merge
  resolvers (addresses-union, psbts-last-writer-wins,
  descriptors-conflict-as-error). One session by itself.
- bitcoind / blockstream backend implementations of
  `get-address-txs`. Stubs ship today.
- Multi-line labels. Storage is TSV; tabs and newlines in
  labels are rejected.
- ~~AC 4–5~~ — `wallet label tx|utxo` + `--label` filter.
  Shipped in 1.19.0.

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
