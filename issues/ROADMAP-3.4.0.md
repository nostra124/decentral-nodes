# Roadmap — 3.4.0 (minor)

Test-suite and CI hardening, plus the remaining bitcoind-backend wallet
plumbing. Backward-compatible additions only (semver minor). Depends on
**3.3.3** (green CI) — these features can't establish a clean baseline
while the unit gate is red.

> **Version-state note.** Much of the 3.x feature work tagged for earlier
> milestones is already implemented in the tree but was never cut as a
> release (`VERSION` is still `3.3.2`). Those items have been moved to
> `issues/feature/done/` (see the audit below); this roadmap lists only
> what remains genuinely open for the next minor. The atomic-swap work
> (FEAT-306) keeps its own draft plan at 3.5.0+ and is the milestone
> after this one.

---

## FEAT-052 — promote shellcheck to a blocking CI lint step
**File:** `issues/feature/052-shellcheck-blocking-ci.md`
**Effort:** small (flip `continue-on-error`, clear residual findings)
Shellcheck runs advisory (`continue-on-error: true`) today. Make it a
blocking gate at `-S warning` once the tree is clean. Sequence it after
BUG-044 so the `-node` test fixes don't surface as fresh findings mid-flip.

## FEAT-051 — required-tools preflight for the test suites
**File:** `issues/feature/051-test-required-tools-preflight.md`
**Effort:** small (a `setup_suite` probe per tier)
Fail fast with a clear message when a suite's external tools (`xxd`,
`dc`, `openssl`, …) are missing, instead of opaque mid-test errors.

## FEAT-050 — fixture well-formedness check for PSBT/tx vectors
**File:** `issues/feature/050-fixture-wellformedness-check.md`
**Effort:** small (a `tests/unit/helpers.bash` assertion)
Validate hand-crafted PSBT/tx hex fixtures' declared lengths against
their actual bytes at authoring time (the BUG-021 class of silent
desync).

## FEAT-053 — split the monolithic unit-test files
**File:** `issues/feature/053-split-monolithic-test-files.md`
**Effort:** medium (mechanical split; large diff, low risk)
`bitcoin.bats` (~235 tests), `streamline.bats` (~175), and
`lightning.bats` (~887) are far past a readable size. Split by
subcommand/feature into focused files. Do this *after* BUG-044 so the
split starts from a green suite.

## FEAT-304 — bitcoind backend `get-address-utxos` + `broadcast`
**File:** `issues/feature/304-bitcoind-backend-utxos-broadcast.md`
**Effort:** medium
Implement the two stubbed bitcoind-backend verbs (`bin/bitcoin-node`
currently errors "not implemented in this release"): address-UTXO scan
via `scantxoutset` and `broadcast` via `sendrawtransaction`. Unblocks the
`tests/sit/suites/02_derive_and_receive.bats` flows (`wallet
balance/utxos/send`) currently skipped on FEAT-304.

---

## Recommended order

```
FEAT-052   cheap win once BUG-044 lands; locks the lint gate
FEAT-051   preflight makes the next two easier to develop
FEAT-050   fixture guard
FEAT-053   big mechanical split — do on a green, guarded suite
FEAT-304   backend feature; verify against the SIT derive/receive suite
```

## Release gate

- All unit tiers green; shellcheck blocking at `-S warning` (FEAT-052).
- `tests/sit/suites/02_derive_and_receive.bats` runs without FEAT-304
  skips.
- `VERSION` bumped to `3.4.0`.
