# Roadmap — 1.11.0 (minor)

`wallet build`. The high-level unsigned-tx builder. With FEAT-013's
ledger, FEAT-012's backend, and FEAT-008 partial (psbt encode)
all in place, 1.11.0 walks the wallet's addresses, fetches UTXOs
via the backend, greedy-selects coins until input total covers
`<sats>` + fee, constructs the raw transaction, wraps it in a PSBT
via `psbt encode`, and prints to stdout.

**Was bundled into the previous ROADMAP-1.10.0.** Split out when
1.10.0 was tightened to `psbt encode` only — raw-tx serialisation
+ coin selection is its own session-worth of work.

Depends on:
- 1.5.0 (FEAT-012 backend `get-address-utxos`)
- 1.6.0 (FEAT-013 wallet ledger)
- 1.10.0 (FEAT-008 partial — `psbt encode`)

---

## FEAT-014 (partial) — `wallet build`
**File:** `issues/feature/014-tx-builder-signer-broadcaster.md`
**Effort:** ~2 days
`bitcoin wallet build <name> <addr> <sats> [--fee-rate sat/vB]`:
1. Walk the wallet's `addresses` ledger.
2. For each address, query `backend get-address-utxos`.
3. Greedy-select UTXOs until input total ≥ `<sats>` + estimated fee.
4. Construct the raw transaction in BIP-141 format:
   - version (4 B LE)
   - varint input count
   - per-input: 32-B prev_txid (LE) + 4-B prev_vout (LE)
              + 1-B empty scriptSig + 4-B sequence (0xfffffffe)
   - varint output count
   - per-output: 8-B value (LE) + varint scriptPubKey-len + scriptPubKey
   - 4-B locktime (0)
5. Wrap in a PSBT via `psbt encode` (just the global unsigned-tx
   record + empty maps for each input/output).
6. Print the PSBT as hex.

`scriptPubKey` construction for the output: parse `<addr>` as
either P2WPKH (`bc1q…`) or P2WSH (`bc1q…` long), emit the witness
program preamble (0x00 + length + program).

Change handling: if the input total exceeds `<sats>` + fee by
more than the dust threshold, derive a change address from the
wallet (via `wallet derive`) and add a second output.

---

## Release gate

- `bitcoin wallet build alice <addr> <sats>` returns a hex PSBT
  whose decoded transaction sends `<sats>` to `<addr>` (or `<sats>`
  + change to two outputs).
- The unsigned tx in the PSBT references only UTXOs that the
  wallet's ledger owns.
- Insufficient-balance, no-such-wallet, and no-UTXOs paths exit
  non-zero with clear `error` lines per `skills/logging.md` §4.
- bats coverage: at least 5 new tests (happy path with stubbed
  backend UTXOs, change-output happy path, insufficient-balance
  rejection, invalid-address rejection, no-such-wallet rejection).
- Pre-push hook + CI green on the milestone PR.

## Out of scope (future roadmaps)

- `bitcoin psbt sign` — SIGHASH + ECDSA over secp256k1; ROADMAP-1.12.0+.
- `bitcoin wallet sign` / `bitcoin wallet send` — ROADMAP-1.12.0+.
- Taproot signing (FEAT-007) — much later.
- Fee estimation via `backend estimate-fee` — currently `wallet build`
  takes a fixed `--fee-rate sat/vB` default; a future FEAT can wire
  the backend's fee estimate in.
