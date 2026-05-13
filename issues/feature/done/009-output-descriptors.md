---
id: FEAT-009
type: feature
priority: low
status: done
---

# Output descriptors (BIP-380 / BIP-381 / BIP-386)

## Resolution (shipped in 1.4.0)

Partial — checksum + verify only.

- `bitcoin descriptor checksum <body>` appends the BIP-380 8-char
  polymod checksum (or replaces an existing one). Matches the spec
  test vector `raw(deadbeef)` → `raw(deadbeef)#89f8spxm`.
- `bitcoin descriptor verify <descriptor>` returns 0 on a valid
  body+checksum, non-zero otherwise. Every failure path emits a
  clear `error` line per `skills/logging.md` §4.
- `bitcoin help descriptor` cites BIP-380 / 381 / 386 via the
  FEAT-017 `cite` helper.
- All three BIPs vendored under `share/doc/bitcoin/bips/` from the
  pinned upstream commit.

7 bats tests cover the checksum vector, idempotence, invalid-
input rejection, verify-good / verify-tampered / verify-missing.

### Deferred to FEAT-026

- `bitcoin descriptor derive <descriptor> <index>` — instantiate `*`
  and emit the scriptPubKey + address.
- `bitcoin descriptor wallet <name>` — emit a wallet's `wpkh()`
  descriptor.

Both require `mnemonic-to-seed` (PBKDF2 over the BIP-39 mnemonic),
which is the same `FEAT-025 option 1` blocker that lives on
ROADMAP-1.2.0's vendor-vector-deps work. FEAT-026 picks them up
once that lands.

## Description

**As a** user importing or exporting a wallet
**I want** the wallet's address-generation policy expressed as a
descriptor string
**So that** the wallet's account can be backed up, shared, or imported
into other software (Bitcoin Core, Sparrow, Electrum) using the
ecosystem-standard format.

Descriptors are also what `bitcoin-cli importdescriptors` consumes —
required if we want the bitcoind backend (FEAT-012) to expose
watch-only wallet UTXOs without us reimplementing UTXO scanning from
scratch.

## Implementation

Add subcommands:

- `bitcoin descriptor parse <string>` — tokenise and validate,
  including the trailing checksum (BIP-380 §checksum).
- `bitcoin descriptor checksum <string>` — compute the 8-character
  polymod checksum.
- `bitcoin descriptor derive <string> <index>` — instantiate any `*`
  placeholder and emit the resulting scriptPubKey + address.

Supported descriptor functions for v1: `pkh()`, `wpkh()`,
`sh(wpkh())`, `tr()` (BIP-386 single-key Taproot), `combo()`. Multisig
(`multi`, `sortedmulti`, `wsh`) deferred to a later ticket.

Wallet store (FEAT-010) records the active descriptor(s) so receive
and gap-limit logic (FEAT-013) operate on them rather than on
hard-coded derivation paths.

Help and man page cite BIP-380/381/386 and link to the vendored copies
under `share/doc/bitcoin/bips/` per FEAT-017.

## Acceptance Criteria

1. `bitcoin descriptor checksum` matches the BIP-380 test vectors.
2. `bitcoin descriptor derive "wpkh(<xpub>/0/*)" 0` returns the same
   address as `bitcoin address` from the equivalent xpub+path.
3. Round-trip with Bitcoin Core: a descriptor produced by `bitcoin
   descriptor` imports via `bitcoin-cli importdescriptors` without
   error on regtest.
4. The five descriptor functions listed above are supported; others
   return a clear "not yet implemented" error.
5. `bitcoin help descriptor` cites BIP-380/381/386 and shows the
   vendored-doc paths.
