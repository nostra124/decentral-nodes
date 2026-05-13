# Roadmap — 1.5.0 (minor)

The wallet learns to spend. With 1.3.0's wallet repo and 1.4.0's
backend + read path in place, 1.5.0 adds PSBT (the cold-signing
interchange format) and the end-to-end builder/signer/broadcaster.

After this release, the wallet is actually a wallet: receive,
balance, send. From here on, further milestones are about
broadening (Taproot, descriptors-via-other-wallets, push/pull) and
polishing (docs, agent skill, SIT regtest), not about reaching
basic functionality.

Depends on 1.4.0 (FEAT-012 backend, FEAT-013 balance/derive,
FEAT-009 descriptors).

---

## FEAT-008 — PSBT (BIP-174) encode, decode, sign
**File:** `issues/feature/008-psbt-bip174.md`
**Effort:** ~1–2 days
Read, write, and partially sign PSBTs. Required for the
cold-storage flow: online wallet builds an unsigned PSBT, offline
signer adds signatures, online wallet broadcasts. Also the natural
interchange format for FEAT-011 push/pull (commit a PSBT under
`psbts/`, push, sign on the cold side, pull and broadcast).

## FEAT-014 — Transaction builder, signer, broadcaster
**File:** `issues/feature/014-tx-builder-signer-broadcaster.md`
**Effort:** ~2 days
End-to-end happy path: `bitcoin wallet send <name> <addr> <amount>
[--fee-rate sat/vB]`. Coin selection, change derivation,
signing-via-`secret`, broadcast via the backend. Also the
PSBT-only paths: `wallet build`, `wallet sign`, `wallet broadcast`
for the cold-storage workflow.

---

## Recommended order

```
FEAT-008  (PSBT — the interchange format builder/signer use)
FEAT-014  (builder/signer/broadcaster — uses PSBT internally)
```

Internally these can interleave: implement PSBT decode first
(needed by `wallet sign` and `wallet broadcast`); then PSBT encode
(needed by `wallet build`); then the high-level `wallet send`
verb that composes build + sign + broadcast.

## Release gate

- `bitcoin wallet send <name> <addr> <sats>` constructs, signs,
  and broadcasts a single-output spend; returns the txid.
- `bitcoin wallet build <name> <addr> <sats> > tx.psbt` writes an
  unsigned PSBT.
- `bitcoin wallet sign <name> < tx.psbt > tx.signed.psbt` adds
  signatures using the wallet's seed (via `secret`).
- `bitcoin wallet broadcast < tx.signed.psbt` posts the finalised
  transaction via the configured backend.
- `bitcoin psbt decode < tx.psbt` prints a human-readable summary
  (inputs, outputs, fee, sighash flags).
- Coin-selection emits a `warn` line when it falls back from BnB
  to single-random-draw, naming why (per `skills/logging.md`).
- Insufficient-funds, no-such-wallet, and broadcast-rejected paths
  exit non-zero with a clear `error` line.
- bats coverage: at least 8 new tests covering encode/decode round
  trips, sign-then-broadcast on regtest (skip if no bitcoind), the
  cold-flow end-to-end (build → sign → broadcast across two wallet
  copies).
- Pre-push hook + CI green on the milestone PR.

## Out of scope (future roadmaps)

- Taproot / Schnorr signing (FEAT-007, planned 1.6.0+ — Taproot
  spends still go through the legacy ecdsa path until then)
- Push/pull (FEAT-011, planned 1.6.0+)
- Tx index + labels (FEAT-018, planned 1.7.0+)
- SIT regtest harness (FEAT-016, planned 2.0.0)
