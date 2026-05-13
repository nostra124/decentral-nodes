# Roadmap — 1.6.0 (minor)

Read path. With FEAT-012's backend abstraction in place (1.5.0),
1.6.0 wires the wallet to it: balance, address derivation, gap-
limit scan, address labels.

**Re-scoped (third pass).** Was ROADMAP-1.5.0 a moment ago.
FEAT-013 moved here when 1.5.0 was tightened to FEAT-012 only.
The previous 1.6.0 (write path) moves forward to ROADMAP-1.7.0.

Depends on:
- 1.3.0 (FEAT-010 wallet store, FEAT-017 BIP citations)
- 1.5.0 (FEAT-012 backend, `mnemonic-to-seed` plugin)
- 1.5.1 (BUG-013 — `bip32 derive` actually works end-to-end)

---

## FEAT-013 — Balance, address derivation, gap-limit scanner
**File:** `issues/feature/013-balance-derive-scan.md`
**Effort:** ~1–2 days
`bitcoin wallet balance / addresses / derive / scan / label`.
Uses `mnemonic-to-seed` (shipped 1.5.0) plus `bip32`/`bip84`
plus the backend layer.

---

## Recommended order

```
FEAT-013 (a) wallet derive  (writes addresses ledger; the prerequisite)
FEAT-013 (b) wallet addresses + label  (reads + edits the ledger)
FEAT-013 (c) wallet balance  (uses backend get-address-utxos)
FEAT-013 (d) wallet scan     (gap-limit recovery)
```

## Release gate

- `bitcoin wallet derive alice` returns a fresh BIP-84 address
  each call; the wallet repo gains one commit per call.
- `bitcoin wallet addresses alice` lists every derived address
  with its index, descriptor, and label.
- `bitcoin wallet label addr alice <addr> "donations"` updates the
  ledger; the repo gains one commit.
- `bitcoin wallet balance alice` queries the active backend for
  each derived address; sums confirmed and unconfirmed values.
- `bitcoin wallet scan alice` walks forward from index 0; stops
  after `--gap` consecutive empty addresses (default 20); commits
  any newly-discovered uses.
- Pre-push hook + CI green on the milestone PR.

## Out of scope (future roadmaps)

- PSBT + tx builder (FEAT-008 + FEAT-014, ROADMAP-1.7.0)
- bitcoind + blockstream backend implementations (follow-up FEAT)
- Push/pull (FEAT-011), tx index + labels (FEAT-018), docs
  (FEAT-015), agent skill (FEAT-019), SIT regtest (FEAT-016),
  foundation prep (FEAT-195)
