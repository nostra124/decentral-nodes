---
id: FEAT-042
type: feature
priority: high
status: done
---

# Coin control on `wallet send`

## Description

**As a** wallet operator who uses `bitcoin tx build --utxo` to
pick exact UTXOs for a payment
**I want** the same `--utxo` flag on the one-shot convenience
verb `bitcoin wallet send`
**So that** my coin-control selection doesn't get lost when I
take the build/sign/broadcast shortcut.

`bitcoin wallet send` is the high-level composition documented
in `bitcoin-wallet(1)`. After 1.23.0 it calls `tx:build | tx:sign
| tx:broadcast` internally. Passing `--utxo` through to the
inner `tx build` call is a one-arg-forwarding change.

## Implementation

`bitcoin wallet send <name> <addr> <sats> --utxo <txid:vout>`
(repeatable) — forwarded verbatim to `tx build` as part of the
existing `fwd_args` argv pass-through. No new code path; just
make sure `--utxo` joins `--fee-rate` in the wallet:send arg
accumulator.

The error envelope is whatever `tx build --utxo` already emits
(status 7 + "requested --utxo not found among wallet UTXOs"
from FEAT-036 AC #3).

## Regression protection

The FEAT-014 `wallet send` vector tests pass unchanged (they
don't use `--utxo`, so the default greedy path is exercised).
New bats: round-trips a regtest send that uses two non-largest
UTXOs (greedy would have picked others) — proves the override
sticks through the full pipeline.

## Acceptance criteria

1. `bitcoin wallet send <name> <addr> <sats> --utxo <txid:vout>
   --utxo <other>` builds a tx whose PSBT inputs match exactly
   the listed outpoints (in user-supplied order).
2. Insufficient `--utxo` sum errors with the same message
   shape as `tx build --utxo` (status 7).
3. `wallet send` documentation in `bitcoin-wallet(1)` mentions
   `--utxo` alongside `--fee-rate`.
4. Bats coverage: explicit-coin-control round-trip + the
   insufficient-sum error case.
