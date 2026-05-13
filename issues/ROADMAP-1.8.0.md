# Roadmap — 1.8.0 (minor)

PSBT encode + sign + wallet send. With `bitcoin psbt decode` from
1.7.0 in place, 1.8.0 closes the cold-storage write path: build
PSBTs, sign them, and broadcast via the FEAT-012 backend.

**Was the previous ROADMAP-1.7.0 (which itself was once
ROADMAP-1.5.0).** Each forward shift kept the FEAT-008 + FEAT-014
pair together because they're meaningless without each other.

Depends on:
- 1.7.0 (FEAT-008 partial — psbt decode + wire-format helpers
  shipped)
- 1.6.0 (FEAT-013 wallet ledger)
- 1.5.0 (FEAT-012 `backend broadcast`)
- 1.5.1 / 1.5.2 (BUG-013 / BUG-014 fixes to bip32 derive)

---

## FEAT-008 (remainder) — PSBT encode + sign
**File:** `issues/feature/008-psbt-bip174.md`
**Effort:** ~2 days
`bitcoin psbt encode` constructs the BIP-174 wire format from a
small input description (inputs[], outputs[]). `bitcoin psbt sign`
applies ECDSA signatures via the secp256k1 dc-script already in
`bin/bitcoin`. Round-trip test: a wallet builds + decodes its own
PSBT and gets the same fields back.

## FEAT-014 — wallet send / build / sign / broadcast
**File:** `issues/feature/014-tx-builder-signer-broadcaster.md`
**Effort:** ~2 days
End-to-end `bitcoin wallet send <name> <addr> <sats>
[--fee-rate sat/vB]` plus the cold-flow verbs
`wallet build / sign / broadcast`. Reuses FEAT-008's PSBT
machinery internally.

---

## Recommended order

```
FEAT-008 encode   (PSBT wire-format reverse of 1.7.0's decode)
FEAT-008 sign     (SIGHASH + ECDSA via secp256k1 dc-script)
FEAT-014 build    (coin selection + change derivation + PSBT)
FEAT-014 sign     (wraps `psbt sign` over the wallet's seed)
FEAT-014 broadcast (wraps backend broadcast verb)
FEAT-014 send     (composes build + sign + broadcast)
```

## Release gate

- `bitcoin wallet send alice <addr> <sats>` returns a txid against
  the stubbed mempool backend in tests.
- `bitcoin wallet build / sign / broadcast` work end-to-end across
  two wallet copies (the cold-storage flow).
- `bitcoin psbt encode <description>` round-trips with
  `bitcoin psbt decode` against the BIP-174 test vectors.
- bats coverage: at least 8 new tests.
- Pre-push hook + CI green on the milestone PR.

## Out of scope (future roadmaps)

- Taproot / Schnorr signing (FEAT-007) — ROADMAP-1.9.0+
- Push/pull (FEAT-011), tx index (FEAT-018), docs (FEAT-015),
  agent skill (FEAT-019), SIT regtest (FEAT-016), foundation prep
  (FEAT-195) — all later
