# FEAT-049 — CI lint job + test-suite hardening (audit follow-through)

**Status:** closed
**Milestone:** 1.34.1 (ships in the next patch release)

## Summary

Acts on the 2026-05-30 testing-surface audit. Adds a `lint` job to the
`tests` workflow and tracks the remaining audit items as their own
issues. Pairs with BUG-023 (gate releases on a green suite) and BUG-024
(remove dead assertions).

## Changes

- **`.github/workflows/test.yml` — new `lint` job:**
  - `tools/lint-cmd-names` (gating) — catches the BUG-013/014/016 family
    (`command:<name>` calls with no definition). Verified clean on the
    tree, so it is safe to block on.
  - `shellcheck -S warning bin/* libexec/bitcoin/*` (**advisory**,
    `continue-on-error: true`) — the tree is not yet clean at that level
    (e.g. `bip350` has array-quoting findings: SC2178/2128/2206/2207),
    so this surfaces findings without failing the gate. Promotion to
    blocking is FEAT-052.
  - Because BUG-023 now gates releases on the whole `tests` workflow,
    `lint-cmd-names` is part of the release gate too.

## Not done here (filed as follow-ups)

- **FEAT-050** — fixture well-formedness: a PSBT/tx self-check helper (or
  generate-don't-paste), so a malformed hex literal (BUG-021's 83-vs-82
  byte `UNSIGNED_TX`) fails at authoring time.
- **FEAT-051** — `setup_suite` required-tools preflight (`xxd`, `dc`,
  `openssl`, …) so a missing dependency aborts with a clear message
  instead of masquerading as a different per-test failure (which masked
  BUG-021/022 during local repro).
- **FEAT-052** — promote `shellcheck` to a blocking lint step after a
  one-time cleanliness sweep of `bin/` + `libexec/bitcoin/`.
- **FEAT-053** — split the monolithic `bitcoin.bats` (223 tests) and
  `streamline.bats` (138) into per-feature files.
- Vector `.t` tests in CI remain blocked by FEAT-025's decision to skip
  (not vendor) the rpk-toolchain deps; revisiting that is out of scope.

## Acceptance Criteria

- [x] `tests` workflow has a `lint` job running `tools/lint-cmd-names`.
- [x] `shellcheck` runs advisory (non-blocking) in the same job.
- [x] Follow-up items captured as FEAT-050..053.
