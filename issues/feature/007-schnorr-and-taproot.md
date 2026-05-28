---
id: FEAT-007
type: feature
priority: medium
status: open
milestone: 1.26.0
---

# Schnorr signatures and Taproot (BIP-340 / BIP-341 / BIP-342)

## Description

**As a** user of an educational bitcoin CLI wallet
**I want** Taproot address derivation and Schnorr signing
**So that** the wallet can receive and spend modern P2TR outputs that
have been the consensus default since November 2021.

bech32m encoding is already in place (BIP-350, see `t/bip-0350.t`),
but the cryptographic and tweaking primitives that turn an xpub into
a Taproot address are not implemented.

## Implementation

Add to `bin/bitcoin`:

1. **BIP-340 Schnorr signatures**: deterministic nonce per the BIP,
   using the existing `dc`-based secp256k1 math. Add the BIP-340
   `tagged_hash` helper (SHA256 with a tagged 64-byte prefix).
2. **BIP-341 Taproot output key derivation**:
   - Compute `tweak = tagged_hash("TapTweak", internal_pubkey || merkle_root)`.
   - Add `tweak * G` to internal pubkey, x-only.
   - Encode as bech32m with witness version 1 → `bc1p…` address.
3. **BIP-342 tapscript signing**: enough to produce key-path spends.
   Script-path tapscript spends are a stretch goal; document the
   limitation in `bitcoin help sign` and the man page.
4. Extend `bitcoinAddress` dispatcher to recognise an x-only pubkey
   (32 bytes) and a `tprv`/`xprv` with a Taproot derivation hint, and
   route to the BIP-341 path.

Add `t/bip-0340.t`, `t/bip-0341.t` (under `tests/vectors/` per
FEAT-003) using the official test vectors from the BIPs.

Help and man page cite BIP-340/341/342 and link to the vendored copies
under `share/doc/bitcoin/bips/` per FEAT-017.

## Acceptance Criteria

1. `bitcoin address <xpub>` for an `xpub`/`tpub` at a BIP-86 derivation
   path produces the correct `bc1p…`/`tb1p…` address (BIP-86 vectors).
2. `bitcoin sign-schnorr <privkey> <msg>` produces a 64-byte signature
   verifiable against the BIP-340 vectors.
3. `prove tests/vectors/bip-0340.t tests/vectors/bip-0341.t` passes.
4. Key-path spend works end-to-end on regtest; script-path spend is
   documented as not yet supported.
5. `bitcoin help` for any taproot subcommand cites BIP-340/341/342 and
   shows the vendored-doc path.
