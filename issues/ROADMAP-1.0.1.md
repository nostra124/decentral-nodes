# Roadmap — 1.0.1 (patch)

Critical bug fixes that restore broken behavior surfaced by the
test-case review (2026-05-11). Patch release: no API change, no new
features; the test contract in `tests/unit/bitcoin.bats` continues to
hold and is extended only by the BUG regression tests below.

---

## BUG-009 — `bip-0039.t` broken TAP `else` branch
**File:** `issues/bug/009-bip0039-broken-tap-else-branch.md`
**Effort:** 1 line
When the extended-key assertion fails the else branch prints raw key
data instead of `not ok N - …`, producing an invalid TAP stream.

## BUG-010 — `bech32-verify-checksum` calls undefined functions
**File:** `issues/bug/010-bech32-verify-checksum-undefined-functions.md`
**Effort:** 2 lines + 1 bats regression test
`polymod` / `hrpExpand` do not exist; the real names are
`bech32-polymod` / `bech32-hrp-expand`. As a result `command:bech32-decode`
always exits 8. Flagged but not filed in BUG-008.

## BUG-011 — `command:bech32` rejects BIP-173-valid all-uppercase input
**File:** `issues/bug/011-command-bech32-rejects-uppercase.md`
**Effort:** 1 line + 2 bats regression tests
The case-mixing guard compares `$1$2` (original) against `[A-Z]` but
`$hrp$data` (lowercased) against `[a-z]`, so any uppercase in the input
triggers a rejection. BIP-173 only forbids *mixed* case.

---

## Recommended order

```
BUG-009   (1-line, unblocks accurate test reporting)
BUG-010   (2-line, unblocks bech32-decode path; covers BUG-008 follow-up)
BUG-011   (1-line, unblocks uppercase vectors once 1.1.0/FEAT-006 lands)
```

## Release gate

- `make check-unit` exits 0 with all three regression tests green.
- `bitcoin bech32-decode abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw`
  exits 0.
- `bitcoin bech32 A12 UEL5L` succeeds; `bitcoin bech32 aBc xyz` fails.
- `prove tests/vectors/bip-0039.t` (under 1.1.0 once FEAT-006 lands)
  produces a well-formed TAP stream on the failure path.
