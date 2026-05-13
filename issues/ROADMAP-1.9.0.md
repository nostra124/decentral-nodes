# Roadmap — 1.9.0 (minor)

`psbt encode` + `wallet build`. Mirror of 1.7.0's psbt decode plus
the unsigned-transaction builder. After this release the wallet
can construct a spend that's ready to be signed offline.

**Was bundled into the previous 1.8.0 draft.** Split out when
1.8.0 was tightened to `wallet broadcast` only.

Depends on:
- 1.5.0 (FEAT-012 backend — `get-address-utxos` for coin
  selection)
- 1.6.0 (FEAT-013 wallet ledger — knows the wallet's addresses)
- 1.7.0 (FEAT-008 partial — psbt decode + the wire-format
  helpers, which encode reverses)

---

## FEAT-008 (partial) — `psbt encode`
**File:** `issues/feature/008-psbt-bip174.md`
**Effort:** ~1 day
Reverse of `psbt decode`. Takes a small description (an unsigned
tx hex blob + a list of input UTXO records + a list of output
records) and emits the BIP-174 wire format. Round-trips with
`psbt decode` against the BIP-174 test vectors.

## FEAT-014 (partial) — `wallet build`
**File:** `issues/feature/014-tx-builder-signer-broadcaster.md`
**Effort:** ~2 days
`bitcoin wallet build <name> <addr> <sats> [--fee-rate sat/vB]`:
walk the wallet's address ledger, fetch UTXOs via the backend,
greedy-select coins until the input total covers `<sats>` + fee,
construct an unsigned transaction (raw varint serialisation),
wrap in a PSBT via `psbt encode`, print to stdout.

---

## Release gate

- `psbt encode` round-trips with `psbt decode` for the BIP-174
  test vectors (encode the parsed records, decode again, get
  identical output).
- `wallet build alice <addr> <sats>` emits a PSBT whose decoded
  transaction sends `<sats>` to `<addr>` and uses coins from
  alice's wallet UTXOs.
- bats coverage: at least 5 new tests.
- Pre-push hook + CI green on the milestone PR.

## Out of scope (now on ROADMAP-1.10.0+)

- `bitcoin psbt sign` — SIGHASH + ECDSA over secp256k1
- `bitcoin wallet sign` / `bitcoin wallet send`
- Taproot signing (FEAT-007)
