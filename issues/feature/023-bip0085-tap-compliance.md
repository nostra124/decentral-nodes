---
id: FEAT-023
type: feature
priority: low
status: open
---

# Fix `tests/vectors/bip-0085.t` TAP compliance: add test numbers and tighten assertions

## Description

`bip-0085.t` has two quality issues that make it fragile under strict TAP
harnesses and miss implementation regressions.

### Problem A — Tests are not numbered

TAP requires `ok N - description` / `not ok N - description`. Every
assertion in `bip-0085.t` uses:

```bash
then echo "ok - test case 1, correct derived entropy"
else echo "not ok - test case 1, wrong derived entropy"
```

The missing counter means `prove --verbose` mis-sorts diagnostics,
and some harnesses consider unnumbered tests as out-of-sequence. A
shared counter should mirror the pattern all other `.t` files use:

```bash
declare -i n=0
...
((n++))
if ...; then echo "ok $n - ..."
else        echo "not ok $n - ..."
fi
```

### Problem B — Plan count derived from `grep -c "^if "` is fragile

```bash
echo 1..$(grep -c "^if " ${BASH_SOURCE[0]})
```

An unrelated `if` block (e.g., a guard or error-handling branch) shifts
the count. Use a counter-increment approach identical to `bip-0032.t`'s
`grep -c ^_test` — put each test in a `_test_N()` function, or count
a dedicated marker comment `# TEST` instead.

### Problem C — Mnemonic assertions use `grep -q` on free-form output

```bash
LANG=en bip85 mnemo 12 2>/dev/null |
if grep -q "girl mad pet galaxy egg matter matrix prison refuse sense ordinary nose"
```

`grep -q` matches a substring of any line. A correct implementation that
prefixes output with metadata would still pass. Use equality:

```bash
result="$(... | head -1)"
[[ "$result" = "girl mad pet galaxy egg matter matrix prison refuse sense ordinary nose" ]]
```

## Acceptance Criteria

1. Every assertion line in `bip-0085.t` starts with `ok N` or `not ok N`.
2. The plan line does not use `grep -c "^if "`.
3. Mnemonic assertions use string equality, not substring grep.
4. `prove tests/vectors/bip-0085.t` produces a well-formed TAP stream.
