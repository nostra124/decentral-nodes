---
id: BUG-024
type: bug
priority: medium
status: done
---

# dead unit-test assertions — trailing `|| true` neutralises error checks

audit: 2026-05-30 (testing-surface audit)

## Severity

**Medium.** Nine assertions in `tests/unit/bitcoin.bats` ended in
`|| true`:

```sh
[[ "$output" == *"privkey-hex"* ]] || [[ "$stderr" == *"privkey-hex"* ]] || true
```

The trailing `|| true` makes the whole compound command exit 0 **always**,
so the error-message contract was never enforced. Each test still
checked `[ "$status" -ne 0 ]`, but the *message* §10 requires ("name the
condition and the offending value") was untested — a wrong or missing
diagnostic would have passed CI silently.

## Observed

`grep -n ']] || true$' tests/unit/bitcoin.bats` → 9 hits. Messages:
`magic`, `no-such-wallet`, `mempool`, `insufficient`, `privkey-hex`,
`not finalised`, `mainnet`, `not yet implemented`, `command:foo`. A
legitimate `commit … 2>/dev/null || true` cleanup in the same file is
*not* an assertion and is left untouched. (`streamline.bats` had no such
dead assertions.)

## Root Cause

Defensive softening: under plain `run`, bats merges stderr into
`$output`, and the author hedged the stream (`|| [[ "$stderr" … ]]`) and
then added a blanket `|| true` so the line could never fail. The hedge
silently disabled the assertion.

## Fix

Strip only the `]] || true` tail (`sed 's/\]\] || true$/]]/'`), leaving
the `commit … || true` cleanup intact. Under plain `run` the merged
`$output` already contains the message, so `[[ "$output" == *msg* ]]` is
now a real, enforced check (any `|| [[ "$stderr" … ]]` clause is kept
and harmless). No assertion logic rewritten beyond the no-op tail.

## Regression Protection

- `grep -c ']] || true$' tests/unit/bitcoin.bats` → 0; the legitimate
  `|| true` cleanup remains (count 1).
- `bats tests/unit/bitcoin.bats` after the change: **210 ok / 13 notok**.
  None of the nine de-softened tests is among the failures (verified by
  grepping the failing-test names for each message); the 13 are
  pre-existing sandbox-environmental failures (absent `secret`/`base58`/
  `dc`/… in this runner). Every de-softened assertion holds against the
  real messages; in CI (full toolchain) all nine run live and green.

## Acceptance Criteria

- [x] No `]] || true$` remains in `tests/unit/*.bats`.
- [x] The legitimate `commit … || true` cleanup is preserved.
- [x] The error-message assertions are enforced (no blanket no-op tail).
- [x] No new failures vs. baseline.
