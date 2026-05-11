---
id: FEAT-021
type: feature
priority: medium
status: open
---

# Expand `tests/unit/bitcoin.bats` coverage: modules, exit codes, negative cases, bech32-decode

## Description

`bitcoin.bats` has twelve tests covering only the dispatcher smoke path
and `command:bech32` round-trips. The following gaps leave real bugs
uncatchable without the vector suite (which requires FEAT-006):

### Gap 1 — `modules` test only asserts two of four shipped modules

The comment at `bitcoin.bats:83` acknowledges four modules (`bip32`,
`bip39`, `daemon`, `wif`) but only two are asserted. Add:

```bash
[[ "$output" == *"daemon"* ]]
[[ "$output" == *"wif"* ]]
```

### Gap 2 — `help` tests don't assert exit code 0

`@test "bitcoin help prints usage"` checks `[ -n "$output" ]` but not
`[ "$status" -eq 0 ]`. A fatal error path that prints to stderr would
pass. Add `[ "$status" -eq 0 ]` to all help-surface tests.

### Gap 3 — No test for `bech32-decode` (currently broken per BUG-010)

```bash
@test "bech32-decode decodes a known BIP-173 vector" {
    run "$BITCOIN_BIN" bech32-decode \
        "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"abcdef"* ]]
}

@test "bech32-decode rejects a bad checksum" {
    run "$BITCOIN_BIN" bech32-decode \
        "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxq"
    [ "$status" -ne 0 ]
}
```

### Gap 4 — No negative / edge-case tests for `bech32`

```bash
@test "bech32 rejects mixed-case hrp" {
    run "$BITCOIN_BIN" bech32 "aBc" "qpzry"
    [ "$status" -ne 0 ]
}

@test "bech32 rejects hrp longer than 83 characters" {
    long_hrp="$(printf 'a%.0s' {1..84})"
    run "$BITCOIN_BIN" bech32 "$long_hrp" "qpzry"
    [ "$status" -ne 0 ]
}

@test "bech32 rejects data with non-charset characters" {
    run "$BITCOIN_BIN" bech32 "test" "BBBBB"
    [ "$status" -ne 0 ]
}
```

### Gap 5 — No test for libexec dispatch path

```bash
@test "bitcoin dispatches to bip13 libexec plugin" {
    run "$BITCOIN_BIN" bip13 help
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}
```

## Acceptance Criteria

1. All new tests pass on the current codebase (the `bech32-decode` tests
   will fail until BUG-010 is fixed — add a `skip` comment referencing
   BUG-010 until then).
2. `make check-unit` exits 0 with all tests green (modulo BUG-010 skips).
3. Total test count in `bitcoin.bats` reaches at least 22.
