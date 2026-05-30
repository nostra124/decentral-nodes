# Vendored Bitcoin Improvement Proposals

> Per FEAT-017. Each `bitcoin` operation cites the BIP
> it implements; this directory is the local copy of the
> spec text so `bitcoin help <verb>` is one step from
> the standard.

## BIP 13 — P2SH

Pay-to-Script-Hash address encoding.

Upstream:
<https://github.com/bitcoin/bips/blob/master/bip-0013.mediawiki>.

Implemented by `bitcoin bip13` /
`libexec/bitcoin/bip13`.

## BIP 32 — Hierarchical Deterministic Wallets

Tree-shaped key derivation: `m / purpose / coin /
account / change / address-index`.

Upstream:
<https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki>.

Implemented by `bitcoin bip32` /
`libexec/bitcoin/bip32`.

## BIP 39 — Mnemonic Seed Phrases

12/24-word seed phrases as a human-readable
representation of HD wallet entropy.

Upstream:
<https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki>.

Implemented by `bitcoin bip39` /
`libexec/bitcoin/bip39`.

The actual seed phrase is **stored in `secret`**, not
in `bitcoin`. `bitcoin wallet derive` reads it via
`secret get <wallet>/seed` on demand.

## BIP 173 — Bech32 / SegWit addresses

Native segregated-witness address format.

Upstream:
<https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki>.

Implemented as part of the address-derivation pipeline.

## BIP 340 — Schnorr signatures

Schnorr signatures over secp256k1 with x-only public keys
and deterministic nonces. Defines the `tagged_hash` helper
used throughout the Taproot stack.

Upstream:
<https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki>.

Implemented by `bitcoin bip340` / `libexec/bitcoin/bip340`.

## BIP 341 — Taproot

Output-key tweaking (`Q = P + tagged_hash("TapTweak", P) · G`)
and the P2TR address format (bech32m, witness version 1).
Key-path spends only here; script-path / tapscript is BIP 342
(stub).

Upstream:
<https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki>.

Implemented by `bitcoin bip341` / `libexec/bitcoin/bip341`.

## BIP 342 — Tapscript

Validation rules for Taproot script-path spends. Vendored for
reference; script-path spending is not yet implemented (key-path
spending via BIP-341 is).

Upstream:
<https://github.com/bitcoin/bips/blob/master/bip-0342.mediawiki>.

## WIF — Wallet Import Format

Pre-BIP encoding of private keys (Base58Check).
Implemented by `bitcoin wif` / `libexec/bitcoin/wif`.

## Citation policy

In code or man pages:

    BIP NNN §X.Y (paragraph title) — <one-line behaviour>
