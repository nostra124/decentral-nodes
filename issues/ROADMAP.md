# bitcoin — test-improvement backlog

Generated from the review of `tests/unit/bitcoin.bats` and
`tests/vectors/*.t` (2026-05-11). Issues are grouped by theme and
ordered by recommended sequencing within each group.

---

## 1. Fix broken tests (must fix before vectors mean anything)

### BUG-009 — `bip-0039.t` broken TAP `else` branch
**File:** `issues/bug/009-bip0039-broken-tap-else-branch.md`
**Effort:** 1 line
When the extended-key assertion fails the else branch prints raw key data
instead of `not ok N - …`, producing an invalid TAP stream.

### BUG-010 — `bech32-verify-checksum` calls undefined functions
**File:** `issues/bug/010-bech32-verify-checksum-undefined-functions.md`
**Effort:** 2 lines + 1 bats test
`polymod`/`hrpExpand` do not exist; the real names are
`bech32-polymod`/`bech32-hrp-expand`. As a result `command:bech32-decode`
always exits 8. Flagged but not filed in BUG-008.

### BUG-011 — `command:bech32` rejects BIP-173-valid all-uppercase input
**File:** `issues/bug/011-command-bech32-rejects-uppercase.md`
**Effort:** 1 line + 2 bats tests
The case-mixing guard compares `$1$2` (original) against `[A-Z]` but
`$hrp$data` (lowercased) against `[a-z]`, so any uppercase in the input
triggers a rejection. BIP-173 only forbids *mixed* case.

---

## 2. Unblock the vector suite (prerequisite for all below)

### FEAT-006 — Make `bin/bitcoin` sourceable as `bitcoin.sh`
**File:** `issues/feature/006-bitcoin-sourceable-as-library.md`
**Effort:** 1 guard line in `bin/bitcoin` + install symlink
All ten `.t` files open with `. bitcoin.sh`. Until this lands every
vector test is dead code and `make check-vectors` is a no-op.
**This is the single highest-leverage item in the backlog.**

---

## 3. Harden the unit test environment

### FEAT-020 — Pin `SELF_LIBEXEC` and read version from source
**File:** `issues/feature/020-bats-environment-isolation.md`
**Effort:** ~5 lines of bats
`setup()` does not export `SELF_LIBEXEC`, so a globally-installed
`bitcoin` can pollute the test run. The version test pins `1.0.0`
literally instead of reading `.rpk/version`.

---

## 4. Expand unit test coverage

### FEAT-021 — Expand `bitcoin.bats` coverage
**File:** `issues/feature/021-bats-coverage-expansion.md`
**Effort:** ~25 lines of bats
Covers: all four `modules` entries, `$status -eq 0` for help tests,
`bech32-decode` round-trip and rejection, mixed-case / length / charset
negative tests, libexec dispatch smoke test.
*Depends on: BUG-010 fixed (or skipped) for the `bech32-decode` tests.*

---

## 5. Fix vector test quality

### BUG-009 (already listed above — fix first)

### FEAT-022 — Replace hard-coded TAP plan counts
**File:** `issues/feature/022-vector-tap-plan-counts-dynamic.md`
**Effort:** ~10 lines across 5 files
`base58.t`, `basics.t`, `bip-0084.t`, `bip-0350.t`, `secp256k1.t` all
use literal counts. Adding a vector silently drifts the plan.

### FEAT-023 — Fix `bip-0085.t` TAP compliance
**File:** `issues/feature/023-bip0085-tap-compliance.md`
**Effort:** ~15 lines
Tests lack sequential numbers; the plan count is derived from `grep "^if"`
which breaks on any new `if`; mnemonic assertions use `grep -q` (substring)
instead of equality.

### FEAT-024 — Deduplicate `bip-0173.t` / `bip-0350.t` vectors
**File:** `issues/feature/024-deduplicate-bip173-bip350-vectors.md`
**Effort:** ~20 lines (extract + source)
Seven correct and eight incorrect bech32 vectors are duplicated across
both files. One edit point diverges silently from the other.

---

## Recommended implementation order

```
BUG-009   (1-line, unblocks accurate test reporting)
BUG-010   (2-line, unblocks bech32-decode path)
BUG-011   (1-line, unblocks uppercase vectors once FEAT-006 lands)
FEAT-006  (sourceable bitcoin.sh — unlocks entire vector suite)
FEAT-020  (test isolation — safe baseline for CI)
FEAT-021  (coverage expansion — requires BUG-010 fixed)
FEAT-022  (dynamic plan counts — polish, low risk)
FEAT-023  (bip-0085 TAP compliance — polish, low risk)
FEAT-024  (vector deduplication — polish, low risk)
```

## Open feature work (not test-related, pre-existing)

The following feature issues were pre-existing and are listed here for
completeness; they are out of scope for this test-improvement backlog:

| ID | Title |
|---|---|
| FEAT-007 | Schnorr and Taproot |
| FEAT-008 | PSBT (BIP-174) |
| FEAT-009 | Output descriptors |
| FEAT-010 | Wallet store as git repo |
| FEAT-011 | Wallet push/pull |
| FEAT-012 | Backend abstraction |
| FEAT-013 | Balance derive/scan |
| FEAT-014 | Tx builder / signer / broadcaster |
| FEAT-015 | Docs walkthrough |
| FEAT-016 | SIT regtest |
| FEAT-017 | Vendor and cite BIPs |
| FEAT-018 | Client-side tx index and labels |
| FEAT-019 | Wallet agent skill |
| FEAT-195 | Bitcoin foundation prep |
