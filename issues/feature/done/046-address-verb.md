# FEAT-046: `bitcoin address` — address validation and type detection

**Status**: done (1.32.0)

## Summary

Add a top-level `bitcoin address` verb for Bitcoin address introspection.
Useful in scripts, watch-only wallet setup, and anywhere that needs to
validate or classify an address without parsing raw scriptPubKey bytes.

## Acceptance criteria

AC#1  `bitcoin address validate <addr>` exits 0 for any valid mainnet or
       testnet address (P2PKH / P2SH / P2WPKH / P2WSH / P2TR).
       Exits 1 with an error message for invalid input.

AC#2  `bitcoin address type <addr>` prints one of:
       `p2pkh` | `p2sh` | `p2wpkh` | `p2wsh` | `p2tr`

AC#3  `bitcoin address decode <addr>` prints the underlying hash or witness
       program as lowercase hex.

AC#4  `bitcoin address help` lists all subcommands.

AC#5  `bitcoin help` mentions `address`.

AC#6  Man page `bitcoin-address.1` with STANDARDS section citing
       BIP-13, BIP-141/173, BIP-341/350.

## Implementation notes

- `address:_base58_decode` — decodes base58check; checks 50-char hex output
- `address:_bech32_decode` — tries bip173 (v0) then bip350 (v1); reuses
  `convertbits` helper already present in bin/bitcoin
- Version byte mapping: 0x00 / 0x6f → p2pkh; 0x05 / 0xc4 → p2sh
- Witness program length: 20B → p2wpkh; 32B → p2wsh (v0) or p2tr (v1)
- No new external dependencies (uses bip13 / bip173 / bip350 plugins)
