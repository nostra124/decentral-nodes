# Roadmap — 1.29.0 (minor)

**Operator polish + regtest.** 1.28.0 closed the cryptographic
Taproot story (BIP-371 PSBT key-path signing on top of the 1.26.0
BIP-340 / BIP-341 plugins). 1.29.0 closes everything that pairs with
a running `bitcoind`: the SIT regtest harness, the legacy and
nested-segwit signing types that the harness then validates, the
docs surface that the walkthrough exercises, and the agent skill.

## Status

| Feature | Status | Notes |
|---------|--------|-------|
| FEAT-016 SIT: end-to-end receive→spend on regtest | planned | unblocks the regtest ACs of FEAT-008 / FEAT-014 / FEAT-015 |
| FEAT-014 tx builder — P2PKH + P2SH-P2WPKH signing | planned | P2WPKH shipped; P2TR landed in 1.26.0; BIP-371 PSBT in 1.28.0; regtest validates AC #1 / #3 / #4 here |
| FEAT-015 `bitcoin(1)` man page, bash completion, README walkthrough | planned | per-subcommand pages (FEAT-041) shipped; AC #5 (walkthrough exercised by SIT) closes once FEAT-016 lands |
| FEAT-019 `bitcoin-wallet` agent skill | planned | SKILL.md / opencode.md + install plumbing shipped in 1.16.0; only AC #3 (install-skills-user idempotency test) and AC #5 (live-agent trigger) remain |

## What lands

1. **FEAT-016 — SIT regtest harness.** A podman/regtest `bitcoind`
   container plus 5 SIT suites that fund an address, build → sign
   → broadcast a spend, and assert the backend sees the txid within a
   block. Soft-skip with a clear message when podman isn't available
   so CI (which runs unit only) stays green. This is the keystone:
   FEAT-008 AC #2 (`testmempoolaccept`), FEAT-014 AC #1/#3, and
   FEAT-015 AC #5 all retire here.

2. **FEAT-014 — P2PKH + P2SH-P2WPKH signing.** Legacy double-SHA-256
   sighash for P2PKH; BIP-143 reuse for P2SH-P2WPKH with the
   redeemScript wrapping in `wallet sign` / `tx sign`. With FEAT-016
   in the same milestone, AC #4 (one bats case per address type on
   regtest) finally closes.

3. **FEAT-015 — docs surface.** Closure of AC #5: the walkthrough is
   wired into the SIT harness so every documented step is asserted.

4. **FEAT-019 — agent-skill closure.** AC #3: a bats test that
   exercises `make install-skills-user` for idempotency. AC #5 stays
   documented (operationally tied to a live agent; can't be CI-tested).

## Depends on

- FEAT-008 BIP-371 (shipped, 1.28.0) — what FEAT-016 exercises on the
  Taproot path.
- FEAT-014 send pipeline (P2WPKH / P2TR shipped) — what FEAT-016
  exercises on the segwit paths.
- A container runtime (podman) on the SIT tier per `skills/testing.md`.

## Notes

FEAT-016 is sequenced first within the milestone: once the harness
exists, the trailing regtest ACs on FEAT-008 / FEAT-014 / FEAT-015 can
be ticked off instead of being carried as "needs the SIT harness."
