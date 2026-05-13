# Roadmap — 1.4.0 (minor)

The wallet learns to read the chain. With 1.3.0's git-backed
wallet repo in place, 1.4.0 wires up a pluggable backend (so the
educational walkthrough works against bitcoind, mempool.space, or
blockstream.info) and uses it to derive addresses, scan for
balances, and emit output descriptors.

After this release, you can `bitcoin wallet balance` and
`bitcoin wallet receive` without ever sending a transaction. The
wallet is real but read-only.

Depends on 1.3.0 (FEAT-010 wallet store).

---

## FEAT-012 — Backend abstraction
**File:** `issues/feature/012-backend-abstraction.md`
**Effort:** ~1–2 days
A thin verb layer (`backend_chain_height`, `backend_get_tx`, etc.)
with three implementations: `bitcoind` (RPC), `mempool` (REST),
`blockstream` (REST). The wallet talks to the layer, not the
backend.

## FEAT-013 — Balance, address derivation, gap-limit scanner
**File:** `issues/feature/013-balance-derive-scan.md`
**Effort:** ~1 day on top of 010+012
`bitcoin wallet balance`, `bitcoin wallet receive`,
`bitcoin wallet scan`. Implements the BIP-44 gap-limit logic so
imported wallets discover their full address range.

## FEAT-009 — Output descriptors (BIP-380 / 381 / 386)
**File:** `issues/feature/009-output-descriptors.md`
**Effort:** ~1 day
Lets the wallet's address policy be expressed in the
ecosystem-standard descriptor string. Required for the bitcoind
backend's `importdescriptors` path so we don't reimplement UTXO
scanning per BIP-44/49/84.

---

## Recommended order

```
FEAT-009  (descriptors — used by FEAT-012's bitcoind path)
FEAT-012  (backend abstraction — three implementations, chooses by config)
FEAT-013  (balance/derive/scan — uses FEAT-012 to query)
```

## Release gate

- `bitcoin wallet balance <name>` returns a numeric satoshi balance
  on each backend.
- `bitcoin wallet receive <name>` derives and prints the next
  unused receiving address; the wallet repo records the issuance.
- `bitcoin wallet scan <name>` walks the gap-limit and updates the
  wallet's address ledger.
- `bitcoin descriptor <name>` emits a valid BIP-380 string for
  every wallet in `wallet ls`.
- Backend selection works: `bitcoin wallet --backend=bitcoind …`,
  `--backend=mempool`, `--backend=blockstream`. Default chosen by
  config file per FEAT-012's spec.
- Every backend failure path (network down, RPC auth, 4xx/5xx)
  emits a `warn` or `error` line per `skills/logging.md` §4.
- bats coverage: at least 6 new tests covering happy paths +
  backend-missing fallback.
- Pre-push hook + CI green on the milestone PR.

## Out of scope (future roadmaps)

- PSBT or spend (FEAT-008 + FEAT-014, planned 1.5.0)
- Tx history with labels (FEAT-018, planned 1.7.0+)
- Push/pull (FEAT-011, planned 1.6.0+)
