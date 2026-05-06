---
id: BUG-008
type: bug
priority: medium
status: done
---

# `bin/bitcoin bech32`: implementation broken in three independent places

## Severity

**Medium.** `bitcoin bech32 <hrp> <data>` fails mid-pipeline and
produces no valid bech32 string. Same applies to
`bitcoin bech32-verify`. The bug doesn't corrupt data — the
script simply can't produce or verify any bech32 address. The
proper bech32 path (BIP-173) lands as part of FEAT-006/008
(bitcoin.sh module rewrite); this ticket documents the discrete
fixes needed *now* if a maintainer wants to take just that
slice.

## Observed

Three independent issues stack on the bech32 code path. Each
fails in turn, so fixing only the first surfaces the second.

### Issue A — `command:bech32-create-checksum` is undefined

`bin/bitcoin:241`:

    echo -n "${hrp}1$data"
    command:bech32-create-checksum "$hrp" $(
        echo -n "$data" | while read -n 1; do
            echo "${bech32_charset_reverse[REPLY]}"
        done)

The function is defined at line 326 as `bech32-create-checksum`
(no `command:` prefix). The sibling `command:bech32-encode` at
line 342 calls it correctly without the prefix at line 353.

Fix: drop the `command:` prefix on line 241.

### Issue B — `$((...))` used as a statement in `bech32-polymod`

`bin/bitcoin:300..311` (`bech32-polymod`):

    for value; do
        local -i top i
        $(( top = chk >> 25, chk = (chk & 0x1ffffff) << 5 ^ value ))
        for i in {0..4}; do
            $(( ((top >> i) & 1) && (chk^=${generator[i]}) ))
        done
    done

`$((...))` is **arithmetic command substitution** — it expands
to the numeric result and bash tries to execute that number as
a command. Outputs a flood of
`bash: line N: 35: command not found`-style errors on every
loop iteration; `chk` is never actually mutated.

Should be `((...))` (arithmetic command, no `$`):

    (( top = chk >> 25, chk = (chk & 0x1ffffff) << 5 ^ value ))
    for i in {0..4}; do
        (( ((top >> i) & 1) && (chk^=${generator[i]}) )) || true
    done

The `|| true` on the inner `((...))` is needed because under
`set -e`-like contexts a `((expr))` that evaluates to 0 returns
exit-status 1, which would abort the loop on iterations where
`(top >> i) & 1 == 0`.

### Issue C — `command:bech32` doesn't map checksum digits to chars

Even with A and B fixed, `command:bech32` (line 240..245) still
echoes the raw 5-bit checksum digits (one per line, e.g.
"3\n2\n8\n11\n21\n26") instead of mapping them through
`bech32_charset` and concatenating onto the previous output.
The sibling `command:bech32-encode` at line 354..356 has the
correct mapping loop:

    echo -n "${hrp}1"
    for i; do echo -n "${bech32_charset:i:1}"; done
    echo

`command:bech32` needs the same mapping pass over the checksum
digits before printing.

## Root Cause

Incomplete port of the BIP-173 reference implementation, copy-
pasted from a working `bech32-encode` source but with
incomplete edits. The three issues are independent typos /
omissions, not a single shape.

## Fix Plan

Land all three fixes in one commit (they have a single end-user
contract: `bitcoin bech32 <hrp> <data>` produces a valid
BIP-173 string).

1. Drop the `command:` prefix at line 241.
2. Replace `$((...))` with `((...))` (and append `|| true`)
   at lines 305 and 307.
3. Replace the bare `bech32-create-checksum` call at line 241
   with the same charset-mapping loop the sibling
   `command:bech32-encode` already uses, OR refactor
   `command:bech32` to delegate to `command:bech32-encode`
   after splitting `data` into 5-bit values.

A sibling latent issue lives at line 338
(`bech32-verify-checksum` calls `polymod` and `hrpExpand` —
neither defined; the actual functions are `bech32-polymod` and
`bech32-hrp-expand`). It's never reached today because no
`command:` calls `bech32-verify-checksum`. A separate ticket
should cover that once `command:bech32-verify` is rewired to
use it.

## Regression Protection

`tests/vectors/bip-0173.t` already encodes the BIP-173 spec's
test vectors; it gates on `bin/bitcoin.sh` (FEAT-006), which
doesn't yet exist. Once FEAT-006 lands the sourceable
`bitcoin.sh` module, vectors will run. Until then, a unit-test
guard in `tests/unit/bitcoin.bats` per the bug-replication
convention:

    @test "bech32 round-trips a known BIP-173 vector" {
        encoded="$($BITCOIN_BIN bech32 abc qpzry)"
        # BIP-173 vector: hrp=abc, data=qpzry → abc1qpzrylhvwcq
        [ "$encoded" = "abc1qpzrylhvwcq" ]
    }

This test will fail until all three fixes land. It should be
written and gated `skip "BUG-008: ..."` per the convention; the
gate is removed when the fix commits.

## Acceptance Criteria

1. `bin/bitcoin:241` calls `bech32-create-checksum` (no prefix).
2. `bin/bitcoin:305,307` use `((...))` arithmetic commands, not
   `$((...))` substitution.
3. `command:bech32` produces a complete bech32 string ending
   with a 6-char checksum mapped through `bech32_charset` (no
   raw digits in the output).
4. `bitcoin bech32 abc qpzry` outputs `abc1qpzrylhvwcq`.
5. `bitcoin bech32-verify "$(bitcoin bech32 abc qpzry)"` exits 0.
6. The sibling `bech32-verify-checksum` typo (`polymod` /
   `hrpExpand` instead of `bech32-polymod` / `bech32-hrp-expand`)
   is filed as a separate follow-up ticket.
