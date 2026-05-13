---
id: FEAT-014
type: feature
priority: high
status: open
---

## Progress (1.8.0 shipped — `wallet broadcast` only)

`bitcoin wallet broadcast <name>` reads raw transaction hex from
stdin, validates it as hex, and forwards to the active backend's
broadcast verb (FEAT-012). Returns the txid the backend
produced. Three bats tests cover happy path, empty stdin, and
non-hex rejection.

The `<name>` argument is currently a docs hint — per-wallet
backend selection is still deferred from FEAT-012, so the active
backend is global. Once per-wallet backend lands, this verb will
resolve to the wallet's chosen backend without an interface
change.

### Deferred (ROADMAP-1.9.0 and beyond)

- `wallet build <name> <addr> <sats>` — coin selection + tx
  serialisation + PSBT-wrap. ROADMAP-1.9.0.
- `wallet sign <name>` — SIGHASH preimage + ECDSA via the
  secp256k1 dc-script. ROADMAP-1.10.0+ (paired with FEAT-008
  `psbt sign`).
- `wallet send <name> <addr> <sats>` — composes build + sign +
  broadcast. ROADMAP-1.10.0+.

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
