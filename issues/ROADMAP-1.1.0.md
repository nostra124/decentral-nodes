# Roadmap — 1.1.0 (minor)

Test infrastructure: unlock the dormant vector suite, harden the unit
test environment, and close the unit-test coverage gaps. Minor release
because the test contract surface grows (`tests/unit/bitcoin.bats`
gains assertions) but the runtime CLI contract is unchanged.

Depends on 1.0.1 (BUG-010 must be fixed before FEAT-021's
`bech32-decode` tests can pass without `skip`).

---

## FEAT-006 — Make `bin/bitcoin` sourceable as `bitcoin.sh`
**File:** `issues/feature/006-bitcoin-sourceable-as-library.md`
**Effort:** 1 guard line in `bin/bitcoin` + install symlink
All ten `.t` files open with `. bitcoin.sh`. Until this lands every
vector test is dead code and `make check-vectors` is a no-op.
**Highest-leverage item in this release.**

## FEAT-020 — Pin `SELF_LIBEXEC`; read version from `.rpk/version`
**File:** `issues/feature/020-bats-environment-isolation.md`
**Effort:** ~5 lines of bats
`setup()` does not export `SELF_LIBEXEC`, so a globally-installed
`bitcoin` can pollute the test run. The version test pins `1.0.0`
literally instead of reading `.rpk/version` (which is now stale
after 1.0.1).

## FEAT-021 — Expand `bitcoin.bats` coverage
**File:** `issues/feature/021-bats-coverage-expansion.md`
**Effort:** ~25 lines of bats
Covers: all four `modules` entries, `$status -eq 0` for help tests,
`bech32-decode` round-trip and rejection, mixed-case / length / charset
negative tests, libexec dispatch smoke test.
*Depends on: BUG-010 fixed in 1.0.1.*

---

## Recommended order

```
FEAT-006  (sourceable bitcoin.sh — unlocks entire vector suite)
FEAT-020  (test isolation — safe baseline for CI)
FEAT-021  (coverage expansion — requires BUG-010 from 1.0.1)
```

## Release gate

- `make check` (both `check-unit` and `check-vectors`) exits 0.
- `prove tests/vectors/` passes all ten suites listed in FEAT-006's
  acceptance criteria.
- `tests/unit/bitcoin.bats` contains at least 22 tests (up from 12).
- The version test in bats reads from `.rpk/version`; no hard-coded
  `1.0.0` or `1.0.1` literal remains.
