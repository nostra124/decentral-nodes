# Roadmap — 1.5.0 (minor)

Backend abstraction + read path. With FEAT-009's descriptors in
place (1.4.0), 1.5.0 lets the wallet actually query the chain:
pluggable backends (bitcoind / mempool.space / blockstream.info),
balance, address derivation, and the gap-limit scanner.

**Re-scoped from the original 1.5.0 draft.** The first 1.5.0
bundled FEAT-008 (PSBT) + FEAT-014 (tx builder) — that work is now
ROADMAP-1.6.0. FEAT-012 + FEAT-013 moved here from the original
1.4.0 (which kept just FEAT-009).

Depends on 1.4.0 (FEAT-009 descriptors).

---

## FEAT-012 — Backend abstraction (bitcoind / mempool / blockstream)
**File:** `issues/feature/012-backend-abstraction.md`
**Effort:** ~2 days
A thin verb layer (`backend_chain_height`, `backend_get_tx`,
`backend_get_utxos`, `backend_estimate_fee`, `backend_broadcast`)
with three implementations. Per-wallet selection stored in the
wallet repo.

## FEAT-013 — Balance, address derivation, gap-limit scanner
**File:** `issues/feature/013-balance-derive-scan.md`
**Effort:** ~1–2 days on top of 010 + 012
`bitcoin wallet balance / addresses / derive / scan / label`.
Implements BIP-44 gap-limit recovery.

---

## Recommended order

```
FEAT-012  (backend layer first — FEAT-013 depends on it)
FEAT-013  (queries via the backend)
```

## Release gate

- `bitcoin wallet balance <name>` returns a numeric satoshi balance
  on at least one backend (mempool.space, since the cloud sandbox
  has no bitcoind).
- `bitcoin wallet derive <name>` returns a fresh address each call;
  the wallet repo gains one commit per call.
- `bitcoin wallet scan <name>` walks the gap-limit and updates the
  address ledger.
- Backend selection: `bitcoin backend bitcoind|mempool|blockstream`
  switches, `bitcoin backend auto` falls back to mempool with a
  one-time `warn` line per `skills/logging.md` §4.
- Every backend HTTP/RPC failure emits an `error` line that names
  the host, URL, and status code.
- bats coverage: at least 6 new tests with the backends stubbed via
  a local HTTP test server.
- Pre-push hook + CI green on the milestone PR.

## Out of scope (future roadmaps)

- PSBT + tx builder (FEAT-008 + FEAT-014, ROADMAP-1.6.0)
- Push/pull (FEAT-011, ROADMAP-1.7.0+)
- Tx index + labels (FEAT-018, ROADMAP-1.7.0+)
