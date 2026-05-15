---
id: FEAT-014
type: feature
priority: high
status: open
---

## Progress (1.13.0 shipped — `broadcast`, `build`, `build` emits WITNESS_UTXO; psbt sign paired)

`bitcoin wallet broadcast <name>` (1.8.0) reads raw transaction
hex from stdin, validates it as hex, and forwards to the active
backend's broadcast verb (FEAT-012). Returns the txid the backend
produced.

`bitcoin wallet build <name> <addr> <sats> [--fee-rate sat/vB]`
(1.11.0) walks the wallet's addresses ledger, queries the active
backend for UTXOs at each address, greedy-selects (largest-first)
until input total covers `<sats>` + estimated fee, serialises the
BIP-141 unsigned transaction, wraps it as a single-record PSBT
(global `PSBT_GLOBAL_UNSIGNED_TX` only) and prints the hex.

The fee estimate is the educational simple model: vsize ≈ 10 +
68·n_in + 31·n_out at the chosen sat/vB rate. **In 1.12.0** the
default rate stopped being a hard-coded 1 and instead reads
`backend estimate-fee 3` (half-hour bucket on mempool); on any
backend failure (network, JSON parse, stub backend) it falls back
to 1 sat/vB with a `warn` line per skills/logging.md §4. The
explicit `--fee-rate N` flag still wins when supplied.

If the computed change exceeds the 546-sat dust floor a new change
address is derived from the wallet (committed to the ledger like
any normal derivation) and a second output is added; otherwise
the dust is folded into the fee and a single output is emitted.

Only v0 segwit outputs are supported (P2WPKH 20-byte and P2WSH
32-byte witness programs). Bech32m / P2TR (v1+) is explicitly
rejected — signing those is FEAT-007 and not in scope here.

Seven bats tests cover: PSBT magic + decode round-trip, change-
output happy path, dust-absorbed single-output happy path,
insufficient-balance rejection, invalid-address rejection, no-
such-wallet rejection, and P2TR (v1) rejection. The 1.8.0
`wallet broadcast` tests (3) remain.

**1.12.0** adds three more `build` tests that pin the fee-source
resolution: backend estimate is read when `--fee-rate` is absent,
`--fee-rate` overrides the backend estimate, and a missing
estimate-fee response triggers the 1-sat/vB fallback with the
expected `warn` line on stderr. The pre-1.12.0 happy-path tests
were tightened to pass `--fee-rate 1` explicitly so the fee-math
comments inside them stay honest under the new default.

**1.13.0** teaches `wallet build` to emit a
`PSBT_IN_WITNESS_UTXO` record (BIP-174 type 0x01) per input,
serialised as 8-byte LE amount + varint-prefixed scriptPubKey
(recomputed from the input address via `wallet:_address_to_script`).
That gives FEAT-008's new `psbt sign` everything it needs for
BIP-143 sighash without re-querying the backend. One new bats
case asserts the record is present and matches the expected
witness-program bytes for the canonical abandon-mnemonic's
m/84h/0h/0h/0/0 address.

The `<name>` argument to `broadcast` is still a docs hint —
per-wallet backend selection is deferred from FEAT-012, so the
active backend is global. `wallet build` reads per-wallet ledger
state (addresses + git-committed change derivation) but uses the
global backend for UTXO queries; both verbs will resolve to the
wallet's chosen backend without an interface change once the
per-wallet backend lands.

### Deferred (ROADMAP-1.14.0 and beyond)

- `wallet sign <name>` — wallet integration that derives private
  keys from the seed and calls `psbt sign` per matched input. The
  primitive itself shipped in 1.13.0 as `bitcoin psbt sign`.
- `wallet send <name> <addr> <sats>` — composes build + sign +
  broadcast.
- Taproot signing (FEAT-007) and a v1+ address path for `build`.
- ~~Fee estimation via `backend estimate-fee`~~ — shipped in
  1.12.0.
- ~~PSBT_IN_WITNESS_UTXO emission in `wallet build`~~ — shipped
  in 1.13.0 (prerequisite for `psbt sign`).

# Transaction builder, signer, and broadcaster

## Description

**As a** wallet user
**I want** to spend bitcoin from the wallet
**So that** the wallet is actually a wallet.

Depends on FEAT-010 (store), FEAT-012 (backend), FEAT-013 (UTXOs and
addresses), FEAT-008 (PSBT for the cold-signing flow), and ideally
FEAT-007 (Taproot signing).

## Implementation

Subcommands:

- `bitcoin wallet send <wallet> <addr> <amount> [--fee-rate sat/vB]`
  — end-to-end happy path: select coins, build tx, sign via `secret
  get $(cat seed-ref)`, broadcast.
- `bitcoin wallet build <wallet> <addr> <amount>` — build only,
  emit a PSBT to stdout.
- `bitcoin wallet sign <wallet> <psbt>` — sign a PSBT against the
  wallet's keys (seed pulled from `secret`).
- `bitcoin wallet broadcast <wallet> <hex>` — broadcast a finalised
  raw transaction.

Coin selection: largest-first for v1 (simple, works, traceable in
tests). Branch-and-bound is a future ticket.

Fee estimation: `backend_estimate_fee 6` (target six blocks) by
default; `--fee-rate` overrides; user is shown estimated fee and
total before broadcast.

Change address: derived from the wallet's change descriptor (the
second output in BIP-44/49/84/86 setups). Committed to the addresses
ledger like any other derivation.

Signing covers every address type the wallet uses: P2PKH (legacy,
kept per the educational mandate), P2WPKH (BIP-143 sighash),
P2SH-P2WPKH, P2TR key-path (BIP-341, depends on FEAT-007).

Mainnet send requires `--mainnet`; absent the flag the wallet refuses
(testnet/regtest by default per FEAT-015).

Help and man page cite BIP-141 (segwit), BIP-143 (segwit sighash),
BIP-341 (Taproot signing), BIP-174 (PSBT), and link to the vendored
copies per FEAT-017.

## Acceptance Criteria

1. On regtest: `bitcoin wallet send alice <addr> 0.001` selects coins,
   broadcasts, and the resulting txid is found by the backend within
   one block.
2. The builder emits a balanced tx (inputs == outputs + fee) and the
   computed fee equals `vsize * fee-rate`.
3. Signing produces a transaction that `bitcoin-cli testmempoolaccept`
   accepts on regtest.
4. P2PKH, P2WPKH, P2SH-P2WPKH, and P2TR key-path all spend
   successfully on regtest (one bats case per type).
5. `bitcoin wallet send` without `--mainnet` against a
   mainnet-configured wallet aborts with a clear error.
