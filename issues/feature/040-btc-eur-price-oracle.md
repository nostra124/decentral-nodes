---
id: FEAT-040
type: feature
priority: medium
status: open
milestone: 1.25.0
---

# BTC/EUR historical price oracle — local cache

## Description

**As** FEAT-039's FIFO engine
**I need** a deterministic source of historical BTC/EUR prices
**So that** the same wallet history produces the same tax
report every run — and so that the report works offline once
the cache is warm.

## Implementation

### CLI surface

    bitcoin price get <YYYY-MM-DD>            # one day, EUR per BTC
    bitcoin price fetch [--from <YYYY-MM-DD>] [--to <YYYY-MM-DD>]
    bitcoin price source [--set coingecko|kraken|csv://<path>]
    bitcoin price status                       # cache freshness + coverage

`price get` reads from the local cache; if missing for the
requested date, errors with a `warn` line pointing at `price
fetch`. (Tax reports must be reproducible — silent network
fetches during a report run break determinism.)

`price fetch` populates the cache from the configured source.
Idempotent: only fetches missing dates.

### Cache layout

One file: `~/.bitcoin/cache/price/btc-eur.tsv`. Three columns:
`date` (ISO 8601, UTC), `eur_per_btc`, `source`. One row per
day. Append-only — historical revisions are appended with a
later `source` tag; the report uses the most recent row per
date and notes revisions in `narrative.md`.

The cache is **not** in any wallet's git repo — it's global
per-machine. Multiple wallets share it.

### Price sources

| Source       | Endpoint                                                                   | Notes |
|---------------|----------------------------------------------------------------------------|-------|
| `coingecko`   | `https://api.coingecko.com/api/v3/coins/bitcoin/history?date=DD-MM-YYYY&localization=false` | Default. Free tier rate-limited (~30 req/min); `price fetch` paces requests. |
| `kraken`      | `https://api.kraken.com/0/public/OHLC?pair=XBTEUR&interval=1440&since=<unix>` | Alternative. One call returns many days. |
| `csv://<path>`| Local CSV, three columns: date, eur_per_btc, ignored.                       | For users with their own historical data or who want to use the ECB reference rate. |

The "price of the day" convention: **CoinGecko's documented
'historical' endpoint returns the snapshot at 00:00 UTC on the
requested date**. That's the convention recorded in the cache
and used by FEAT-039. Kraken-sourced rows snap to 00:00 UTC
daily close for consistency.

### Network policy

`price fetch` is the only verb that touches the network.
Tested in unit tier with a mock HTTP server (bats spawns a
local `nc`-based stub); SIT tier hits the real APIs against
known historical dates.

`bitcoin price get` and FEAT-039's `tax report-de` never make
network calls — only cache reads. This makes the report
auditable (the cache is the source of truth, with an explicit
fetch step the user runs before generating a report).

### Reproducibility guarantee

Given the same wallet history and the same cache file, `tax
report-de` produces byte-identical output. The cache is the
canonical input; users committing cache rows to a private repo
(or capturing them in CI fixtures) get fully reproducible
reports.

## Regression protection

New bats cases:
- `price fetch --from 2024-01-01 --to 2024-01-07` populates 7
  rows in the cache against a bats-spawned mock HTTP server.
- `price get 2024-01-01` reads back the cached row.
- `price get 2024-01-08` errors with a `warn` line citing
  `price fetch` (date not in cache).
- `price source --set kraken` then re-fetches and writes new
  rows tagged `kraken`; old `coingecko` rows remain; `price
  get` returns the kraken row (most recent for that date).
- `price fetch` is idempotent: re-running over an
  already-populated range makes zero network calls (cache hit
  on every date).
- `price source --set csv://<path>` reads a local CSV and
  populates the cache without any network call.

## Acceptance criteria

1. `bitcoin price get / fetch / source / status` exist as
   documented.
2. Cache lives at `~/.bitcoin/cache/price/btc-eur.tsv` and is
   shared across wallets.
3. `tax report-de` reads only from the cache; never makes
   network calls during a report.
4. Three sources supported: `coingecko` (default), `kraken`,
   `csv://`.
5. The "00:00 UTC snapshot" convention is documented in
   `bitcoin price source --help` and in
   `docs/command-surface.md`.
6. New bats coverage with a local HTTP mock so unit-tier
   tests don't hit real APIs.

## Out of scope

- BTC/USD or any other fiat pair. The repo's tax workflow is
  Germany-specific; other jurisdictions can add their pair
  when their `tax report-XX` verb lands.
- Price-feed signing / oracle attestations. The cache trusts
  the source; users wanting cryptographic guarantees should
  use a CSV they've validated themselves.
