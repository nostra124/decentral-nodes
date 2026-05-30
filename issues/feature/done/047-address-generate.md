# FEAT-047 — `bitcoin address generate`

**Status:** closed (1.33.0)
**Milestone:** 1.33.0

## Summary

Add a `generate` subcommand to `bitcoin address` that derives a Bitcoin
address from a raw 33-byte compressed public key (66 hex characters).

## Command surface

```
bitcoin address generate [--p2wpkh] [--p2pkh] [--p2tr] [--testnet] <pubkey-hex>
```

- Default (no type flag): **P2WPKH** (native segwit v0, bech32, BIP-173)
- `--p2wpkh`: native segwit v0 — hash160 of pubkey, bech32-encoded with HRP `bc` / `tb`
- `--p2pkh`: legacy P2PKH — base58check with version byte `0x00` mainnet / `0x6f` testnet
- `--p2tr`: Taproot P2TR — bip341 key-path tweak of the x-only key, bech32m-encoded
- `--testnet`: testnet HRP (`tb`) / version bytes
- Exit 2 on usage error; exit 1 on invalid pubkey

## Implementation

All work in `bin/bitcoin` (`address:generate`, `address:generate:p2wpkh`,
`address:generate:p2pkh`, `address:generate:p2tr`). Delegates to existing
plugins:

- **bip173** `encode-values` for P2WPKH
- **bip13** `base58-encode` for P2PKH
- **bip341** `tweak` + **bip350** `encode-values` for P2TR

## Test vectors

Pubkey: `0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798`
(secp256k1 generator G, compressed)

| Type | Network | Address |
|------|---------|---------|
| P2WPKH | mainnet | `bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4` |
| P2WPKH | testnet | `tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx` |
| P2PKH  | mainnet | `1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH` |
| P2TR   | mainnet | `bc1pmfr3p9j00pfxjh0zmgp99y8zftmd3s5pmedqhyptwy6lm87hf5sspknck9` |

## Acceptance criteria

- [x] `address generate <pubkey>` → P2WPKH mainnet address
- [x] `address generate --p2pkh <pubkey>` → P2PKH mainnet address
- [x] `address generate --p2wpkh --testnet <pubkey>` → P2WPKH testnet address
- [x] `address generate --p2tr <pubkey>` → P2TR mainnet address
- [x] malformed pubkey → exit 1 with error message
- [x] missing pubkey → exit 2
- [x] `address help` mentions `generate`
- [x] man page updated
