---
id: FEAT-026
type: feature
priority: medium
status: open
---

# Descriptor derive + wallet-emit (FEAT-009 follow-up)

## Description

**As a** wallet user
**I want** `bitcoin descriptor derive` to instantiate a `*`
placeholder against an index and emit the resulting address, and
`bitcoin descriptor wallet <name>` to emit a checksummed `wpkh()`
descriptor for an existing wallet
**So that** descriptors are not just checksum strings but actually
drive address generation and wallet export.

FEAT-009 (1.4.0) shipped the BIP-380 checksum + verify subcommands.
The derive/wallet-emit subcommands were deferred because they
require `mnemonic-to-seed` (PBKDF2 over the BIP-39 mnemonic to
produce the BIP-32 seed) — a command this repo does not currently
ship. FEAT-025 (option 2) skip-and-detects it; this feature
unblocks once `mnemonic-to-seed` is vendored (FEAT-025 option 1) or
implemented in-tree.

## Implementation

Two subcommands to add to `command:descriptor` in `bin/bitcoin`:

1. `bitcoin descriptor derive <descriptor> <index>`
   Parse the descriptor (extract function name + key + child path
   suffix); instantiate `*` with `<index>`; derive the child public
   key via `bip32 derive` from the embedded xpub; compute the
   scriptPubKey + address per the descriptor function (`wpkh` →
   bech32 P2WPKH, `pkh` → base58 P2PKH, `tr` → bech32m P2TR via
   the BIP-386 tweak).

2. `bitcoin descriptor wallet <name>`
   Read seed via `secret get <name>/seed`; PBKDF2 to the BIP-32
   seed via `mnemonic-to-seed`; derive `m/84h/0h/0h` xpub via
   `bip84`; emit `wpkh(<xpub>/0/*)#<checksum>`.

## Dependencies

- FEAT-025 option 1 (vendor `mnemonic-to-seed`) OR an equivalent
  in-tree implementation under `libexec/bitcoin/bip39`.
- Existing FEAT-009 checksum machinery in `bin/bitcoin`.

## Acceptance Criteria

1. `bitcoin descriptor derive "wpkh(<xpub>/0/*)" 0` matches the
   address `bitcoin address` emits for the equivalent xpub+path.
2. `bitcoin descriptor wallet alice` emits a string passing
   `bitcoin descriptor verify`.
3. The five descriptor functions listed in FEAT-009
   (`pkh`/`wpkh`/`sh(wpkh)`/`tr`/`combo`) are supported by
   `derive`; others return a clear "not yet implemented" error.
4. bats coverage: at least 4 tests (one per supported function +
   the wallet-emit happy path).
