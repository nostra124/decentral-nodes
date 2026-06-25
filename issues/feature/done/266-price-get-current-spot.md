---
id: FEAT-266
type: feature
priority: low
status: done
---

# `bitcoin price get` (no date) returns the current spot price

## Motivation

`bitcoin price get` required a `<YYYY-MM-DD>` argument and errored
without one. The dated form is deliberately cache-only so tax/report
runs are reproducible (FEAT-040). But the common interactive question
is simply "what's the price right now?" — for which a live value is
the correct answer. The no-date form now answers that.

## Behavior

- `bitcoin price get <YYYY-MM-DD>` — unchanged: EUR/BTC for that date,
  read from the local cache; errors (pointing at `price fetch`) if the
  date isn't cached. No network.
- `bitcoin price get` (no date) — the **current spot price**, a live
  query to the active source's spot endpoint. For `coingecko` (the
  default) this is `/api/v3/simple/price?ids=bitcoin&vs_currencies=eur`
  → `.bitcoin.eur`. For other sources (kraken/csv) it errors clearly,
  directing the user to pass a date (cache read) instead.

The split keeps the reproducibility guarantee intact (an explicit date
never touches the network) while making "now" live, as a spot price
must be.

## Acceptance Criteria

1. `bitcoin price get` with no date prints the current EUR/BTC spot
   price (live source query). Proven by `tests/unit/streamline.bats`
   "FEAT-266 — price get with no date returns the current spot price"
   (curl-stubbed).
2. With a non-coingecko active source, the no-date form errors with a
   message naming the source and suggesting a date. Proven by
   "FEAT-266 — price get spot errors clearly for a non-coingecko
   source".
3. `bitcoin price get <date>` is unchanged (cache-only, no network).
4. `price help` documents the `get [<date>]` dual behavior.
