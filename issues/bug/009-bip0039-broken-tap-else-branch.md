---
id: BUG-009
type: bug
priority: high
status: open
---

# `tests/vectors/bip-0039.t`: failure case emits raw data instead of `not ok N`

## Severity

**High.** When the fourth assertion in the BIP-39 loop fails (extended-key
mismatch), the test file prints the raw key value instead of a `not ok N - …`
line. This breaks the TAP stream — the harness either counts the test as
missing or parses the key as a diagnostic, producing an incorrect pass/fail
summary.

## Observed

`tests/vectors/bip-0039.t:39–43`:

```bash
if declare generatedExtendedKey="$(basenc --base16 -d <<<"${seed^^}" |bip32 -s m |base58 -c)"
   [[ "$generatedExtendedKey" = "$addr" ]]
then echo "ok $n - good key generated from seed : $(shorten $seed) -> $(shorten $generatedExtendedKey)"
else echo "$generatedExtendedKey"
fi
```

The `else` branch outputs the key without any `not ok` prefix.

## Fix

```bash
then echo "ok $n - good key generated from seed : $(shorten $seed) -> $(shorten $generatedExtendedKey)"
else echo "not ok $n - wrong key for seed $(shorten $seed): got $(shorten $generatedExtendedKey), expected $(shorten $addr)"
fi
```

## Acceptance Criteria

1. When the extended-key assertion fails, the output line starts with
   `not ok N - `.
2. `prove tests/vectors/bip-0039.t` produces a well-formed TAP stream
   regardless of pass or fail.
3. No other test logic changes.
