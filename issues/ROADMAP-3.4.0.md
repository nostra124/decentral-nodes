# Roadmap — 3.4.0 (minor)

Test-suite and CI hardening, plus the remaining bitcoind-backend wallet
plumbing. Backward-compatible additions only (semver minor). Depends on
**3.3.3** (green CI) — these features can't establish a clean baseline
while the unit gate is red.

> **Version-state note.** Much of the 3.x feature work tagged for earlier
> milestones is already implemented in the tree but was never cut as a
> release (`VERSION` is still `3.3.2`). Those items have been moved to
> `issues/feature/done/` (see the audit below); this roadmap lists only
> what remains genuinely open for the next minor. The shipped self-hosting
> nodes are tracked in `ROADMAP-3.5.0.md`; the atomic-swap work (FEAT-306)
> is at 3.6.0.

---

## FEAT-313 — installed-tree (post-`make install`) test tier ✅ DONE
**File:** `issues/feature/done/313-installed-tree-test-tier.md` (landed early with BUG-058)
**Effort:** small–medium
The unit tests only exercise the dev tree, which let BUG-058 ship
(installed nodes with no verbs). Add a tier that runs `make install` and
asserts every dispatcher resolves a real verb + prints the right VERSION
from the staged prefix. Depends on BUG-058 (3.3.4).

## FEAT-314 — unit-test parity: a suite for every node dispatcher
**File:** `issues/feature/314-unit-test-parity-all-nodes.md`
**Effort:** medium
Seven dispatchers ship with no unit tests (tor/ipfs/storj/joinmarket/
liquid/stacks/i2pd). Add the shared-contract suite for each + a guard so
no future `bin/*-node` ships untested.

## FEAT-315 — SIT smoke suites for the service nodes
**File:** `issues/feature/315-sit-smoke-service-nodes.md`
**Effort:** medium
Container suites that install + start + health-check forgejo/webmin/
usermin end-to-end, leveraging the now-permanent podman (FEAT-309).

## FEAT-052 — promote shellcheck to a blocking CI lint step
**File:** `issues/feature/052-shellcheck-blocking-ci.md`
**Effort:** small (flip `continue-on-error`, clear residual findings)
Shellcheck runs advisory (`continue-on-error: true`) today. Make it a
blocking gate at `-S warning` once the tree is clean. Sequence it after
BUG-056 so the `-node` test fixes don't surface as fresh findings mid-flip.

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
subcommand/feature into focused files. Do this *after* BUG-056 so the
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
FEAT-313   installed-tree tier — lock in the BUG-058 fix first
FEAT-314   per-node unit parity (+ the no-untested-node guard)
FEAT-052   cheap win once BUG-056 lands; locks the lint gate
FEAT-051   preflight makes the next two easier to develop
FEAT-050   fixture guard
FEAT-053   big mechanical split — do on a green, guarded suite
FEAT-315   SIT smoke for the service nodes (needs podman)
FEAT-304   backend feature; verify against the SIT derive/receive suite
```

## Release gate

- All unit tiers green; shellcheck blocking at `-S warning` (FEAT-052).
- Installed-tree tier (FEAT-313) green; every `bin/*-node` has a unit
  suite (FEAT-314).
- `tests/sit/suites/02_derive_and_receive.bats` runs without FEAT-304
  skips.
- `VERSION` bumped to `3.4.0`.
