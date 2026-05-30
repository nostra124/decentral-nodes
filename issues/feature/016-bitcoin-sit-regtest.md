---
id: FEAT-016
type: feature
priority: medium
status: open
milestone: 1.29.0
---

# SIT: end-to-end receive→spend against regtest bitcoind

## Description

**As a** maintainer changing wallet code
**I want** an end-to-end test against a real `bitcoind` in regtest
mode
**So that** wallet regressions are caught before they reach a user's
real seed.

Mirrors rpk's per-distro SIT pattern, but the matrix dimension is
"backend" not "distro": one suite per backend (`bitcoind`, `mempool`
mocked or against a Esplora Docker image, `blockstream` mocked).

## Implementation

Under `tests/sit/`:

    tests/sit/
    ├── podman/
    │   ├── Dockerfile.bitcoind        (alpine + bitcoin-core regtest)
    │   └── Dockerfile.esplora         (mempool/Esplora Electrs + bitcoind)
    ├── helpers.bash
    └── suites/
        ├── 01_wallet_new.bats
        ├── 02_derive_and_receive.bats
        ├── 03_send_and_broadcast.bats
        ├── 04_psbt_roundtrip.bats
        └── 05_push_pull_between_accounts.bats

Each suite spins up a fresh container, executes the corresponding
walkthrough step, and asserts the outcome via the backend (e.g.
`bitcoin-cli getreceivedbyaddress`).

`make check-sit` runs the matrix; soft-skips if `podman` is not
installed (parity with FEAT-003).

The `push_pull` suite spins up two wallet HOMEs in the same
container, pushes between them via a local bare git remote (the
`account` SSH remote is mocked to a local path), and verifies sign
on one + broadcast on the other.

## Acceptance Criteria

1. `make check-sit` against `Dockerfile.bitcoind` runs all five
   suites to green on a clean regtest.
2. Suites are deterministic: the same git SHA produces the same test
   outcome over 5 runs.
3. The `push_pull` suite verifies sign-on-one-account, broadcast-from-
   the-other end-to-end.
4. Soft-skip with a clear message if `podman` is unavailable.
5. `docs/bitcoin-walkthrough.md` and the SIT suites stay in
   lockstep — every walkthrough step is asserted in a suite.
