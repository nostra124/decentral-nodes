# Roadmap — 1.2.0 (minor)

Vector test polish: dynamic plan counts, strict TAP compliance for
`bip-0085.t`, and deduplication of bech32 vectors shared across
`bip-0173.t` and `bip-0350.t`. Minor release because the vector suite
becomes maintainable enough that adding a vector is a one-edit change.

Depends on 1.1.0 (vector suite must actually run before its quality
issues are observable).

---

## FEAT-022 — Replace hard-coded TAP plan counts
**File:** `issues/feature/022-vector-tap-plan-counts-dynamic.md`
**Effort:** ~10 lines across 5 files
`base58.t`, `basics.t`, `bip-0084.t`, `bip-0350.t`, `secp256k1.t` all
use literal counts (`echo 1..28`, `1..58`, …). Adding a vector
silently drifts the plan.

## FEAT-023 — Fix `bip-0085.t` TAP compliance
**File:** `issues/feature/023-bip0085-tap-compliance.md`
**Effort:** ~15 lines
Tests lack sequential numbers; the plan count is derived from
`grep "^if"` which breaks on any new `if`; mnemonic assertions use
`grep -q` (substring) instead of equality.

## FEAT-024 — Deduplicate `bip-0173.t` / `bip-0350.t` vectors
**File:** `issues/feature/024-deduplicate-bip173-bip350-vectors.md`
**Effort:** ~20 lines (extract + source)
Seven correct and eight incorrect bech32 vectors are duplicated across
both files. One edit point diverges silently from the other.

---

## Recommended order

```
FEAT-022  (dynamic plan counts — polish, low risk)
FEAT-023  (bip-0085 TAP compliance — polish, low risk)
FEAT-024  (vector deduplication — polish, low risk)
```

## Release gate

- No file in `tests/vectors/` uses a numeric literal in its `echo 1..`
  line.
- Every assertion in `bip-0085.t` starts with `ok N` or `not ok N`.
- The seven correct-bech32 and eight incorrect-bech32 vectors appear
  in exactly one source location.
- `prove tests/vectors/` passes all suites unchanged from 1.1.0.
