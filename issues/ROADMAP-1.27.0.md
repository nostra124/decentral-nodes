# Roadmap — 1.27.0 (minor)

**Operator flows.** With Taproot in (1.26.0), 1.27.0 widens the
day-to-day wallet surface beyond the v0-P2WPKH happy path: spend from
the legacy and nested-segwit script types, move PSBTs between machines
the way the cold-signing story always promised, and give every tx /
UTXO / address a durable label and index.

## Status

| Feature | Status | Notes |
|---------|--------|-------|
| FEAT-011 `wallet push` / `pull` between accounts | planned | PSBT interchange over git |
| FEAT-014 tx builder — P2PKH + P2SH-P2WPKH signing | planned | P2WPKH shipped; P2TR landed in 1.26.0; regtest validation in 1.28.0 |
| FEAT-018 client-side tx index + labels | planned | the tax-label vocabulary (FEAT-038) already shipped |

## What lands

1. **FEAT-011 — `wallet push` / `pull`.** An account on a hot machine
   commits an unsigned PSBT under `psbts/`, pushes the wallet repo; a
   cold account pulls, signs, and pushes back. The git-backed wallet
   store (FEAT-010) and PSBT format (FEAT-008) are the rails; this is
   the verb that drives the cold-signing flow end to end.

2. **FEAT-014 — more signing script types.** Extend `wallet sign` /
   `tx sign` past v0 P2WPKH to **P2PKH** (legacy, per the educational
   mandate) and **P2SH-P2WPKH** (nested segwit). This is the
   non-Taproot half of the issue's AC #4; the P2TR key-path landed with
   FEAT-007 in 1.26.0, and the regtest `testmempoolaccept` validation
   (AC #1 / #3) follows in 1.28.0 once the SIT harness (FEAT-016) lands.

3. **FEAT-018 — client-side tx index + labels.** A per-wallet index
   over transactions / UTXOs / addresses with a durable label store,
   building on the FEAT-038 tax-label vocabulary. Gives `wallet
   history` and the tax report a stable, queryable backing.

## Depends on

- FEAT-008 PSBT (shipped) and FEAT-010 git store (shipped) for push/pull.
- FEAT-038 label vocabulary (shipped, 1.23.0) for the index.

## Notes

FEAT-014 is the connective feature here: its core pipeline shipped long
ago, Taproot signing rides 1.26.0, and only the legacy / nested-segwit
script types and the regtest proof remain — split across this milestone
and 1.28.0 by their dependencies.
