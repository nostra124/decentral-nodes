---
id: FEAT-016
type: feature
priority: medium
status: done
milestone: 1.29.0
closed: 1.29.0
---

## Progress (1.29.0 shipped — all five acceptance criteria closed)

`tests/sit/` directory created with:
- `podman/Dockerfile.bitcoind` — Debian bookworm + bitcoin-core regtest node.
- `helpers.bash` — shared functions: `sit:start_bitcoind`, `sit:stop_bitcoind`,
  `sit:cli`, `sit:mine`, `sit:fund_address`, `sit:install_bitcoin`,
  `sit:configure_backend`.
- `suites/01_wallet_new.bats` — wallet creation (AC #5 step 1).
- `suites/02_derive_and_receive.bats` — derive + fund + balance check (AC #5 steps 2–3).
- `suites/03_send_and_broadcast.bats` — full send pipeline + testmempoolaccept (AC #1 / #3).
- `suites/04_psbt_roundtrip.bats` — PSBT encode/sign/finalize/extract + P2WPKH on regtest (AC #4).
- `suites/05_push_pull_between_accounts.bats` — cold-sign flow between two HOMEs (AC #3).

`make check-sit` now runs `bats tests/sit/suites/` when podman is available;
soft-skips with a clear message otherwise (AC #4).

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
