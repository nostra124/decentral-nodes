# Roadmap — 1.26.0 (minor)

**Taproot.** The `bipXXX` surface has had a `bip340` / `bip341` /
`bip342` slot reserved since the 1.23.0 streamline; 1.26.0 fills it.
Schnorr + Taproot is the one missing cryptographic primitive in the
tree, and several features have been parked waiting for it — this is
where they all close together.

A crypto-primitive milestone, not a product one: land the signatures
and the key-/script-path machinery, then sweep up every strand that's
been blocked on "FEAT-007 first".

## Status

| Feature | Status | Notes |
|---------|--------|-------|
| FEAT-007 Schnorr & Taproot (`bip340` / `bip341` / `bip342`) | planned | the primitive itself |
| FEAT-008 PSBT — BIP-371 Taproot fields | planned | decode/encode/sign/finalize/extract shipped; only the Taproot fields remain |
| FEAT-026 descriptor derive — `tr()` + `combo()` | planned | `pkh` / `wpkh` / `sh(wpkh)` shipped; `tr()` is the last function |

## What lands

1. **FEAT-007 — Schnorr & Taproot.** `bip340` (Schnorr sign / verify
   per BIP-340), `bip341` (Taproot output key tweak + key-path and
   script-path spends, BIP-341), `bip342` (tapscript signatures,
   BIP-342). Each plugin self-contained with its BIP-appendix vector
   companion under `tests/vectors/`. The `bip350` bech32m
   encoder/decoder that P2TR addresses need already shipped.

2. **FEAT-008 — BIP-371 PSBT Taproot fields.** Recognise and sign the
   Taproot PSBT key-value types (`PSBT_IN_TAP_KEY_SIG`,
   `PSBT_IN_TAP_INTERNAL_KEY`, …). Closes the issue's AC #4, which has
   been explicitly gated on FEAT-007 since the 1.13.0 sign work.

3. **FEAT-026 — `tr()` + `combo()` descriptors.** `tr()` derives the
   child key, applies the BIP-386 output-key tweak, and emits the
   bech32m P2TR address; `combo()` emits one address per supported
   script type. Closes the remainder of AC #3.

**Rides along (tracked elsewhere):** FEAT-014's P2TR key-path *signing*
strand (its milestone is 1.27.0, but the Taproot piece is unblocked
here and should land with `bip341`).

## Depends on

- Nothing external. `bip350` (bech32m addresses) shipped in 1.23.0; the
  PSBT and descriptor cores (FEAT-008 / FEAT-026) are already in place.

## Release gate (to flesh out when the milestone goes active)

- BIP-340 / BIP-341 / BIP-342 appendix vectors pass byte-for-byte.
- `descriptor derive "tr(<xpub>/0/*)" 0` emits the correct `bc1p…`
  P2TR address (cross-checked against an independent reference).
- A Taproot PSBT round-trips through decode → sign → finalize →
  extract.
