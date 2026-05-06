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

## WIF — Wallet Import Format

Pre-BIP encoding of private keys (Base58Check).
Implemented by `bitcoin wif` / `libexec/bitcoin/wif`.

## Citation policy

In code or man pages:

    BIP NNN §X.Y (paragraph title) — <one-line behaviour>
