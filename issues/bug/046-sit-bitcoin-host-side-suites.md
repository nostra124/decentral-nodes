---
id: BUG-046
type: bug
priority: medium
status: open
---

# SIT — the bitcoin host-side suites are unverified (separate check-sit leg)

## Severity

**Medium.** `check-sit` has a second leg (Makefile `check-sit`, the
`@bats tests/sit/suites/*wallet* *derive* *send* *psbt* *push_pull*` line) that
runs the **bitcoin** wallet SIT suites on the host, each self-managing a bitcoind
container via `tests/sit/helpers.bash` (`sit:start_bitcoind`). This leg is
currently `|| true` (never fails the target) and has not been verified end-to-end
since the packaging/harness work.

## Scope (host-side suites)

- `01_wallet_new`, `02_derive_and_receive`, `03_send_and_broadcast`,
  `04_psbt_roundtrip`, `05_push_pull_between_accounts`.

## Observed

When these suites are (mis)run **inside** the clightning container they fail with
`podman: command not found` (`sit:start_bitcoind`, helpers.bash:17) — they expect
to run on the host and spawn their own bitcoind container. Their real host-side
behaviour under the current harness is unconfirmed; the `|| true` masks it.

## Tasks

- Run the host-side leg explicitly and capture pass/fail.
- Confirm `sit:start_bitcoind` (the host-side bitcoind container) still works with
  the current images / bitcoind release-binary layout.
- Once green, drop the `|| true` so regressions are caught, or document why it
  stays soft (e.g. cloud-sandbox skip).

## Acceptance

The host-side bitcoin SIT suites run and pass under `make check-sit`, and the leg
reports failures instead of swallowing them.

Independent of the lightning-container tickets ([[BUG-041]]..[[BUG-045]]).
