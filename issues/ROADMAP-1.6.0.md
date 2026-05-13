# Roadmap — 1.6.0 (minor)

The write path. With backends from 1.5.0 in place, 1.6.0 adds PSBT
(the cold-signing interchange format) and the end-to-end
builder/signer/broadcaster. After this release the wallet can
actually spend.

**Moved here from the original ROADMAP-1.5.0 draft** — that draft
was shifted forward when 1.4.0 was re-scoped per
`skills/milestones.md` §2.3.

Depends on 1.5.0 (FEAT-012 backend, FEAT-013 derive/scan).

---

## FEAT-008 — PSBT (BIP-174) encode, decode, sign
**File:** `issues/feature/008-psbt-bip174.md`
**Effort:** ~1–2 days
Read, write, and partially sign PSBTs. Required for the
cold-storage flow and the natural interchange format for FEAT-011
push/pull (commit a PSBT, push, sign cold, pull and broadcast).

## FEAT-014 — Tx builder / signer / broadcaster
**File:** `issues/feature/014-tx-builder-signer-broadcaster.md`
**Effort:** ~2 days
End-to-end `bitcoin wallet send` plus the PSBT-only paths
`wallet build`, `wallet sign`, `wallet broadcast`.

---

## Recommended order

```
FEAT-008  (PSBT — the interchange format)
FEAT-014  (builder/signer/broadcaster — uses PSBT internally)
```

## Release gate

- `bitcoin wallet send <name> <addr> <sats>` constructs, signs, and
  broadcasts a single-output spend; returns the txid.
- `bitcoin wallet build / sign / broadcast` work end-to-end across
  two wallet copies (the cold-storage flow).
- `bitcoin psbt decode < tx.psbt` summarises inputs/outputs/fee.
- bats coverage: at least 8 new tests covering encode/decode round
  trips and the cold-storage flow.
- Pre-push hook + CI green on the milestone PR.

## Out of scope (future roadmaps)

- Taproot / Schnorr signing (FEAT-007) — Taproot spends use the
  legacy ECDSA path until 1.7.0+
- Push/pull (FEAT-011), tx index (FEAT-018), docs (FEAT-015),
  agent skill (FEAT-019), SIT regtest (FEAT-016), foundation prep
  (FEAT-195) — all later
