---
id: FEAT-026
type: feature
priority: medium
status: open
---

## Progress (1.18.0 shipped — wpkh() only)

Three of the four acceptance criteria shipped; AC 3 (the full
five-function support — `pkh` / `wpkh` / `sh(wpkh)` / `tr` /
`combo`) remains partial because only `wpkh` is implemented in
this release.

- **`bitcoin descriptor wallet <name>`** reads the seed via
  `secret get`, derives the BIP-84 account xpub
  (`m/84h/0h/0h/N`) through the same pipeline `wallet derive`
  uses, applies BIP-32 base58check (sha256d 4-byte checksum +
  base58), and emits `wpkh(<xpub>/0/*)#<checksum>` with the
  BIP-380 polymod suffix.

- **`bitcoin descriptor derive <descriptor> <index>`** parses
  the descriptor body, strips and verifies any `#<checksum>`
  suffix, instantiates the `*` placeholder with `<index>`,
  base58-decodes the xpub (stripping the trailing 4-byte
  BIP-32 checksum), runs `bip32 derive /<path>` against the
  resulting 78-byte serialisation (bare relative path: not
  `m/...` which requires the private master, and not `M/...`
  which requires a depth-0 master), takes the last 33 bytes
  as the compressed pubkey, and emits the bech32 P2WPKH
  address via the same `p2wpkh()` helper `wallet derive` uses.

- The two are exact inverses on the BIP-84 receive branch:
  `descriptor wallet alice` then
  `descriptor derive <emitted> <i>` yields the same address
  `wallet derive alice` produces on the i-th call.

8 new bats tests: wpkh descriptor shape + checksum verifies;
`descriptor wallet` rejects missing wallets; derive reproduces
the abandon-mnemonic vector (`bc1qcr8te4kr...`); derive walks
indices 0/1/2 to match consecutive `wallet derive` calls;
non-wpkh functions return a "not yet implemented" error;
malformed descriptors and bad indices rejected; bad checksum
rejected; help mentions derive + wallet. Total bats now 154.

### Deferred to ROADMAP-1.19.0+

- **AC 3** — `pkh()`, `sh(wpkh())`, `tr()`, `combo()` support
  in `descriptor derive`. Needs the BIP-13 P2PKH address path
  (mostly available via `p2pkh-address` in the script) plus
  the BIP-86 / BIP-350 P2TR (bech32m) path. Stub returns
  "not yet implemented" today; the FEAT-007 Taproot work
  will paint that error away from `tr()` specifically.
- Multi-key descriptors (`multi(...)`, `sortedmulti(...)`).
- Wiring `descriptor wallet` to populate the wallet repo's
  `descriptors` file as a side effect — a useful follow-up
  but not yet shipped.

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
