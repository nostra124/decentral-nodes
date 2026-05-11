---
id: BUG-010
type: bug
priority: high
status: open
---

# `bech32-verify-checksum` calls undefined functions; `bech32-decode` always fails

## Severity

**High.** `command:bech32-decode` (and therefore anything that depends on
it) always returns exit code 8 because `bech32-verify-checksum` calls
`polymod` and `hrpExpand` — neither of which exists. The real functions
are `bech32-polymod` and `bech32-hrp-expand`.

## Observed

`bin/bitcoin` around line 354:

```bash
bech32-verify-checksum() {
    local hrp="$1"
    shift
    local -i pmod="$(polymod $(hrpExpand "$hrp") "$@")"
    (( pmod == ${BECH32_CONST:-1} ))
}
```

`polymod` → should be `bech32-polymod`.
`hrpExpand` → should be `bech32-hrp-expand`.

Because the command substitution `$(polymod …)` silently fails (the shell
emits "command not found" to stderr), `pmod` is set to 0, and the
equality check `(( 0 == 1 ))` is always false, so the function always
returns 1. `command:bech32-decode` catches this return and exits 8.

BUG-008 flagged this as a "follow-up ticket" (see `issues/bug/done/
008-bitcoin-bech32-broken.md`, last paragraph). No separate bug was filed.
No test covers the behaviour.

## Fix

```bash
bech32-verify-checksum() {
    local hrp="$1"
    shift
    local -i pmod="$(bech32-polymod $(bech32-hrp-expand "$hrp") "$@")"
    (( pmod == ${BECH32_CONST:-1} ))
}
```

## Regression Protection

Add a bats test:

```bash
@test "bech32-decode decodes a known BIP-173 vector" {
    run "$BITCOIN_BIN" bech32-decode "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"abcdef"* ]]
}
```

## Acceptance Criteria

1. `bin/bitcoin bech32-decode abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw`
   exits 0 and prints `abcdef` as the HRP.
2. `bin/bitcoin bech32-decode` of a tampered string exits non-zero.
3. The bats regression test passes.
