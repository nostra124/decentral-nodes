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

### 1.10.0 shipped — encode

`bitcoin psbt encode` is the reverse of decode. Reads TSV records
on stdin (same shape decode emits — `section=<n> type=<hex>
key=<hex> value=<hex>`), tracks section bumps and inserts the
BIP-174 0x00 terminators between sections, emits one final 0x00
to close the last section, and prints the result as hex.

`psbt:_emit_varint` writes BIP-174 compact-size varints
(1/3/5 bytes); decode's `_take_varint` is the reverse.

6 new bats tests: empty input → just magic + terminator;
single-record global → known hex; two-record two-section →
known hex with section terminator in the middle; round-trip
encode→decode→same-TSV; non-hex value rejected; backwards
section field rejected. Total now: 86 bats tests.

Known limitation: empty trailing sections aren't representable
(decode's TSV doesn't record them either, so round-trip is
asymmetric for PSBTs whose last record is followed by empty
maps — like the BIP-174 "outputs are empty" test vector). A
future `--sections N` flag (or explicit `section-end` markers
in the TSV format) would close the asymmetry; not in scope here.

### 1.13.0 shipped — sign (v0 P2WPKH only)

`bitcoin psbt sign <privkey-hex>` reads a PSBT (hex) on stdin and
a 32-byte private key on argv, then for each input whose
`PSBT_IN_WITNESS_UTXO` record's scriptPubKey is v0 P2WPKH of
HASH160(pubkey-of-key) it:

1. Builds the BIP-143 sighash preimage (`nVersion || hashPrevouts
   || hashSequence || outpoint || scriptCode || amount ||
   nSequence || hashOutputs || nLocktime || sighash_type`),
   where `scriptCode = 1976a914<hash160>88ac` per BIP-143 §P2WPKH.
2. Double-SHA-256's the preimage to get the sighash.
3. Signs the sighash via `openssl pkeyutl -sign` against a
   hand-built minimal-DER ECPrivateKey carrying the raw 32-byte
   secret (no precomputed PEM material).
4. BIP-66 low-S canonicalises the DER signature (if `s > n/2`,
   replaces `s` with `n - s` and re-encodes). dc handles the
   big-integer arithmetic; line-continuation backslashes are
   stripped before reuse.
5. Appends the SIGHASH_ALL byte (0x01) and inserts a
   `PSBT_IN_PARTIAL_SIG` record (type 0x02) into the input map,
   keyed by the 33-byte compressed pubkey.

Inputs without a matching scriptPubKey (or without WITNESS_UTXO)
pass through untouched, so a stray key on the wallet's repo can't
accidentally corrupt unrelated PSBTs.

`wallet build` (FEAT-014) was extended in the same release to
emit `PSBT_IN_WITNESS_UTXO` records (8-byte LE amount + varint-
prefixed scriptPubKey) per input, since BIP-143 sighash needs the
prev-output's amount + scriptPubKey and the unsigned tx alone
doesn't carry either.

9 new bats tests: WITNESS_UTXO emitted by build; PARTIAL_SIG
added on a matching input; low-S enforced (first byte of `s` <
0x80); signature verifies via `openssl pkeyutl -verify` against
the recomputed BIP-143 sighash; wrong-key is a byte-identical
no-op (passes the PSBT through); malformed key / empty / non-hex
inputs rejected; help mentions sign. Total bats now 111.

Known limitations (tracked as follow-ups):

- openssl ECDSA uses random k (not RFC 6979 deterministic),
  so signatures vary run-to-run; tests verify the structural
  invariant (verify + low-S) rather than pinning bytes.
- P2WPKH only. P2SH-P2WPKH, P2WSH multisig, and Taproot key-path
  are out of scope (FEAT-007 for the Taproot piece).
- SIGHASH_ALL only; other sighash flags are deferred.

### 1.14.0 shipped — finalize + extract

`bitcoin psbt finalize` reads a PSBT (hex) on stdin and, for each
input carrying a `PSBT_IN_PARTIAL_SIG` (type 0x02) plus a v0
P2WPKH `PSBT_IN_WITNESS_UTXO` (type 0x01):

1. Pulls the first PARTIAL_SIG (key = compressed pubkey, value =
   DER-sig + SIGHASH byte).
2. Builds the BIP-141 witness stack `[sig+sighash, pubkey]` and
   serialises it as `varint(2) || varint(sig_len) || sig ||
   varint(33) || pubkey`.
3. Replaces the input map with WITNESS_UTXO + the new
   `PSBT_IN_FINAL_SCRIPTWITNESS` record (type 0x08), stripping
   the other per-input fields per BIP-174 §Finalizer.

Inputs with no sig pass through unfinalised — `finalize` is a
clean no-op on an empty/partially-signed PSBT.

`bitcoin psbt extract` reads a finalised PSBT and emits the
broadcastable BIP-141 + BIP-144 segwit transaction as hex:
version || `0001` marker+flag || inputs (FINAL_SCRIPTSIG or
empty) || outputs || per-input witness (FINAL_SCRIPTWITNESS
verbatim, or `0x00` empty stack) || locktime. It refuses if any
input lacks both FINAL_SCRIPTSIG and FINAL_SCRIPTWITNESS.

5 new bats tests: finalize adds FINAL_SCRIPTWITNESS; finalize
strips PARTIAL_SIG per BIP-174 §Finalizer; extract emits a
segwit-marked raw tx ending with alice's pubkey; extract refuses
an unfinalised PSBT; finalize is a no-op on an unsigned PSBT.

### Deferred to ROADMAP-1.15.0+

- `bitcoin psbt combine` — merge two PSBTs that signed disjoint
  inputs (the canonical multi-sig flow).
- Taproot (BIP-371) PSBT fields — TR_KEY_SIG, TR_LEAF_SCRIPT,
  etc. Blocked on FEAT-007.
- `bitcoin psbt update` and full BIP-174 §Updater semantics —
  attaching BIP32 derivation paths, redeem scripts, etc.
- RFC 6979 deterministic k for `sign` — would unlock byte-pinned
  signature vector tests but isn't blocking the cold-signing
  flow.

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
