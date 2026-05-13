---
id: FEAT-008
type: feature
priority: medium
status: open
---

## Progress (1.7.0 shipped — decode only)

Decode landed; encode + sign still open.

- `bitcoin psbt decode` reads hex from stdin, validates the BIP-174
  magic + separator (`70736274ff`), and walks the wire format
  emitting one TSV line per key-value record:
    section=<n> type=<hex> key=<hex> value=<hex>
- Helpers (`psbt:_take`, `psbt:_take_varint`) use global state
  rather than command substitution so the per-byte position
  pointer survives the parse loop (subshells would silently lose
  it — a real bug found and fixed during implementation).
- 4 bats tests cover: known BIP-174 vector emits records; bad
  magic rejected; empty input rejected; help cites BIP-174.
- `share/doc/bitcoin/bips/bip-0174.mediawiki` vendored at the same
  pinned commit as the other BIPs.

### Deferred to ROADMAP-1.8.0

- `bitcoin psbt encode` — reverse of decode; build the wire format
  from a small inputs/outputs description.
- `bitcoin psbt sign` — SIGHASH preimage + ECDSA over secp256k1.
  The dc-script for EC math is already in `bin/bitcoin` (see
  `$secp256k1`); the missing piece is the SIGHASH algorithm + the
  signing-key plumbing.

# PSBT (BIP-174) encode, decode, and sign

## Description

**As a** user learning bitcoin transaction structure
**I want** the wallet to read, write, and partially sign PSBTs
**So that** the educational walkthrough can demonstrate the
cold-storage flow (online watch-only wallet builds a PSBT, offline
signer adds signatures, online wallet broadcasts).

PSBT is also the natural interchange format for the wallet's
push/pull-via-git feature (FEAT-011): an account on a hot machine
constructs an unsigned PSBT, commits it under `psbts/`, pushes, and a
cold account pulls and signs.

## Implementation

Add subcommands to `bin/bitcoin`:

- `bitcoin psbt new <inputs> <outputs>` — build an unsigned PSBT
  (magic bytes `psbt\xff` + global / per-input / per-output key-value
  maps).
- `bitcoin psbt decode <base64-or-hex>` — pretty-print structure.
- `bitcoin psbt sign <psbt> <wallet>` — fill in `PSBT_IN_PARTIAL_SIG`
  (and Taproot equivalents from BIP-371 once FEAT-007 lands) for
  inputs the wallet can sign.
- `bitcoin psbt finalize <psbt>` — promote partial sigs to final
  scriptSig/witness when threshold is met.
- `bitcoin psbt extract <psbt>` — emit final raw transaction.

Encoding is base64 by default, hex on `--hex`.

Add `tests/vectors/bip-0174.t` using the official vectors. Help and
man page cite BIP-174 and BIP-371 with the vendored-doc paths from
FEAT-017.

## Acceptance Criteria

1. Round-trip: `bitcoin psbt new … | bitcoin psbt decode` shows the
   expected inputs and outputs.
2. Signing a single-sig segwit PSBT produces a finalisable PSBT;
   `extract` gives a raw tx that `bitcoind` accepts via
   `testmempoolaccept` on regtest.
3. The official BIP-174 vectors round-trip through decode/encode
   without loss.
4. Taproot (BIP-371) PSBT fields are recognised and signed once
   FEAT-007 lands.
5. `bitcoin help psbt` cites BIP-174 / BIP-371 and shows the
   vendored-doc paths.
