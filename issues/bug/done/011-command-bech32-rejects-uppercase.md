---
id: BUG-011
type: bug
priority: medium
status: done
---

# `command:bech32` rejects all-uppercase input that BIP-173 explicitly allows

## Severity

**Medium.** BIP-173 permits bech32 strings to be all-uppercase or all-
lowercase; only *mixed* case is invalid. `command:bech32` incorrectly
rejects any input that contains an uppercase letter, including valid
all-uppercase vectors such as `A12UEL5L`.

## Observed

`bin/bitcoin:224`:

```bash
local hrp="${1,,}" data="${2,,}"
if [[ "$1$2" =~ [A-Z] && "$hrp$data" =~ [a-z] ]]; then
    return 1
fi
```

`$hrp` and `$data` are already lowercased from `${1,,}` / `${2,,}`.
So `"$hrp$data" =~ [a-z]` is true whenever the input contains any
letter at all. The combined guard therefore fires as soon as the
original arguments contain *any* uppercase character — rejecting
`("A12", "UEL5L")`, which is a valid BIP-173 all-uppercase pair.

## Root Cause

The mixed-case check should compare the *original* args against both
character classes, not the lowercased copy against `[a-z]`:

```bash
if [[ "$1$2" =~ [A-Z] && "$1$2" =~ [a-z] ]]; then
    return 1
fi
```

`tests/unit/bitcoin.bats` already documents this as a known edge case
(the comment at line 91–93) but defers the fix. BIP-173 vector
`A12UEL5L` is listed as valid in both `tests/vectors/bip-0173.t:6` and
`tests/vectors/bip-0350.t:32`; once FEAT-006 lands (bitcoin.sh source
guard), those vectors will expose this bug.

## Acceptance Criteria

1. `bin/bitcoin bech32 A12UEL5 L` (all-uppercase HRP + data) succeeds.
2. `bin/bitcoin bech32 aBc xyz` (mixed-case HRP) returns exit code 1.
3. A bats test covers both all-uppercase success and mixed-case failure.
4. BIP-173 vector `A12UEL5L` passes `bip-0173.t` once FEAT-006 lands.
