---
id: FEAT-037
type: feature
priority: high
status: open
---

# `bitcoin utxo` — UTXO as a first-class object verb

## Description

**As a** wallet operator practising coin control
**I want** to list, freeze, and select UTXOs by hand
**So that** I can spend the exact coins I mean to spend (avoid
linking unrelated UTXOs in a single transaction; segregate
mined / received / KYC'd coins; satisfy CoinJoin hygiene).

Sparrow Wallet exposes this as a checkbox list in its UTXOs
tab. `bitcoin` exposes it as a verb on a noun.

## Implementation

### New top-level command

    bitcoin utxo ls <wallet> [--include-frozen] [--min-confs N]
    bitcoin utxo freeze <wallet> <txid:vout> [--reason <text>]
    bitcoin utxo unfreeze <wallet> <txid:vout>
    bitcoin utxo select <wallet> --target <sats> [--strategy greedy|branch-and-bound]

`utxo ls` walks the wallet's ledger, queries the active backend
(per FEAT-012) for unspent outputs at each address, and prints
TSV: `txid`, `vout`, `address`, `amount_sat`, `confs`, `frozen`,
`label`, `tax_category`. `--include-frozen` keeps frozen rows
in the output; default excludes them.

`utxo freeze` records the outpoint in
`~/.bitcoin/wallets/<name>/frozen.tsv` with `--reason` and a
timestamp. `tx build` (FEAT-036) refuses to select frozen
UTXOs.

`utxo select` is the pure-computation half of `tx build`'s
selection: emits the chosen `txid:vout`s as TSV without
building a transaction. Useful for previewing selection,
plugging into `tx build --utxo`, or testing selection
strategies. `branch-and-bound` is the Bitcoin Core algorithm
documented in `src/wallet/coinselection.cpp`; greedy is the
existing largest-first.

### What moves out of `wallet`

| Today                            | Tomorrow                                          |
|-----------------------------------|----------------------------------------------------|
| `wallet:index` (UTXO state)       | `utxo:ls`; `wallet:index` becomes a deprecated alias. |
| (no equivalent)                   | `utxo:freeze` / `unfreeze` / `select` — new.       |

### Frozen-UTXO storage

One file per wallet: `~/.bitcoin/wallets/<name>/frozen.tsv`,
two-column TSV (`outpoint`, `reason`, `ts`). Pushed/pulled with
the wallet repo (per FEAT-011's git-as-wallet-store model). No
new infrastructure.

## Regression protection

Existing `wallet index` tests pass unchanged when run against
the `utxo ls` alias output.

New bats cases:
- `utxo ls` lists same UTXOs in same order as `wallet index`
  for an unfrozen wallet.
- `utxo freeze <outpoint>` makes that row disappear from
  `utxo ls` (without `--include-frozen`).
- `tx build` refuses to spend a frozen UTXO (errors with a
  message naming the outpoint and the reason).
- `utxo unfreeze` restores selectability.
- `utxo select --target 50000 --strategy greedy` picks the
  smallest set of largest UTXOs ≥ 50000 sat.
- `utxo select --target 50000 --strategy branch-and-bound`
  prefers an exact-match combination when one exists in the
  set.

## Acceptance criteria

1. `bitcoin utxo ls / freeze / unfreeze / select` exist as
   documented.
2. Frozen state persists across invocations in
   `~/.bitcoin/wallets/<name>/frozen.tsv` and survives `wallet
   push` / `pull`.
3. `tx build` (FEAT-036) refuses to spend frozen UTXOs and
   errors with the freeze reason.
4. `wallet index` continues to work as a deprecated alias to
   `utxo ls` (warn line, identical output).
5. `utxo select --strategy branch-and-bound` produces a
   selection whose sum equals `<sats>` exactly when an exact
   subset exists, falling back to greedy when none does.
6. New bats coverage; full vector suite + pre-push hook green.
