---
id: BUG-020
type: bug
priority: high
status: done
---

# unit suite red — tests not updated after BUG-018 / BUG-019 behaviour changes

audit: 2026-05-26

## Severity

**High.** The bats unit suite (the CI gate, CLAUDE.md §9 / §11) has
been red on `master` since the 1.24.x patch series. Four tests assert
behaviour that BUG-018 (help rework) and BUG-019 (daemon crash-loop
fix) intentionally changed, but the tests were never updated. Because
`release-tag.yml` cuts the tag on any push to `master` and does **not**
gate on `tests.yml`, every version v1.24.1 … v1.24.7 was tagged on a
red suite — exactly the bypass §11 forbids.

## Observed

`bats tests/unit/*.bats` on `master` (and at the v1.24.7 tag) fails 4
tests; the same 4 pass at v1.24.0:

```
not ok 5   help mentions module related commands
not ok 6   help mentions bip173 (bech32) commands
not ok 10  bitcoin <unknown> falls back to help
not ok 353 BUG-015 — start --user kickstarts the LaunchAgent (macos)
```

## Root Cause

Two landed-but-untested behaviour changes:

1. **BUG-018 (help rework).** The top-level help was reorganised from a
   single `module related commands` section into workflow-grouped
   sections (`setup`, `wallet & transactions`, `blockchain primitives`,
   `advanced`) and the bech32 line now reads `Bech32` (capitalised).
   - Test 5 still greps the removed literal `module related commands`.
   - Test 6 still greps lowercase `bech32`; the help now says `Bech32`.
   - Test 10 (unknown → help fallback) also greps `module related
     commands`.
2. **BUG-019 (daemon crash loop).** Fix-plan item #4 changed
   `command:start` from `launchctl kickstart -k` to plain `launchctl
   kickstart` (the `-k` force-kill raced with `KeepAlive`). Test 353
   still greps for `kickstart -k`.

Separately, the `bip174` plugin shells out to `xxd` (hex→binary for DER
key encoding), an undeclared dependency. It is present on the
`ubuntu-latest` CI runner but not on every environment, so the suite is
non-reproducible where `xxd` is absent.

## Fix Plan

1. Update the three help assertions to the BUG-018 surface:
   - test 5 → assert the `blockchain primitives` section is listed.
   - test 6 → assert `Bech32` (matches the help's capitalisation).
   - test 10 → assert the help banner (`usage: bitcoin`) is shown.
2. Update test 353 to expect plain `launchctl kickstart` (no `-k`), per
   BUG-019 fix-plan #4.
3. Declare the `xxd` runtime dependency explicitly in `tests.yml`'s
   apt-get install step so the suite is reproducible.

No production code changes — the shipped behaviour is correct and
documented; only the stale tests and the CI dependency list move.

## Regression Protection

- `bats tests/unit/*.bats` is green (357/357) on a runner with `xxd`.
- The four updated assertions match the behaviour documented in
  BUG-018 and BUG-019.

## Acceptance Criteria

- [x] Tests 5, 6, 10 assert the reworked help surface.
- [x] Test 353 expects `launchctl kickstart` without `-k`.
- [x] `tests.yml` installs `xxd`.
- [x] Full unit suite passes.
