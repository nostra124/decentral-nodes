---
id: FEAT-022
type: feature
priority: low
status: open
---

# Replace hard-coded TAP plan counts with derived counts in vector test files

## Description

Several vector test files use hard-coded `echo 1..N` plan lines. When a
vector is added or removed the count drifts silently — the TAP harness
reports a plan mismatch ("expected N tests, got M") rather than a clear
test failure. Hard-coded counts also require an extra edit whenever
vectors are extended.

Files with hard-coded counts:

| File | Hard-coded plan |
|---|---|
| `tests/vectors/base58.t` | `echo 1..28` |
| `tests/vectors/basics.t` | `echo 1..5` |
| `tests/vectors/bip-0084.t` | `echo 1..13` |
| `tests/vectors/bip-0350.t` | `echo 1..79` |
| `tests/vectors/secp256k1.t` | `echo 1..58` |

Files that already use derived counts (reference implementations):

- `bip-0032.t`: `echo 1..$(grep -c ^_test $BASH_SOURCE)`
- `bip-0173.t`: arithmetic over array lengths

## Implementation

For files that loop over static arrays, compute the count from the array
sizes before the loop, matching the pattern `bip-0173.t` already uses:

```bash
echo 1..$(( ${#correct[@]} + ${#incorrect[@]} ))
```

For `secp256k1.t` the count is harder to derive automatically (random
prefix + two fixed EDGES + heredoc k-values). A helper that counts the
`k = ` lines in the heredoc works:

```bash
echo 1..$(( 10 + 3 + $(grep -c '^k = ' "$BASH_SOURCE") ))
```

## Acceptance Criteria

1. No file in `tests/vectors/` uses a numeric literal in its `echo 1..`
   line.
2. Adding one vector to any file requires no manual count update.
3. `prove tests/vectors/` plan lines match actual test counts.
