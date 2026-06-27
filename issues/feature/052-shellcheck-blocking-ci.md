# FEAT-052 — promote shellcheck to a blocking CI lint step

**Status:** open
**Milestone:** unscheduled

## Summary

FEAT-049 added `shellcheck -S warning` to the `tests` workflow as an
**advisory** step (`continue-on-error: true`) because the tree is not
clean at that level. Known findings include `libexec/bitcoin/bip350`
(SC2178/SC2128 array-vs-string, SC2206/SC2207 unquoted split). Once
`bin/` and `libexec/bitcoin/*` pass `shellcheck -S warning` with zero
findings, drop `continue-on-error` so lint regressions block the gate
(and, via BUG-023, block releases).

## Scope (measured 2026-06-27)

`shellcheck -S warning bin/* $(find libexec/bitcoin-node -type f)` reports
**138 findings** — far more than the original "small" estimate. Breakdown:
SC2034 ×40 (unused — mostly the dispatcher template's `flag`/`SELF_TEST`),
SC2145 ×37, SC2242 ×12, SC2155 ×11, SC2128 ×11, SC2120 ×8, SC2207 ×6,
SC2206 ×6, SC2046 ×4, SC2284 ×4, SC2068 ×3, plus SC2205/2178/2091/1007/
2209/2125. A few (SC2242 invalid exit status, SC2091 run-output,
SC2178 array→string) may be **real bugs** worth filing separately; most
are style/false-positives in working crypto code.

This is **not a small flip** — it's a careful per-finding triage across the
core bitcoin verbs with real regression risk. Deferred from an autonomous
sweep; treat as its own focused effort.

## Proposal

1. Add a repo `.shellcheckrc` disabling the agreed false-positive/style
   codes for this template (e.g. SC2034 for the `flag`/`SELF_TEST`
   dispatcher idiom) with a documented rationale.
2. Triage the remaining findings: fix genuine ones (file BUGs for any
   real defects like SC2242/SC2091/SC2178), or justify with scoped
   `# shellcheck disable=<code>  # reason`.
3. Only once `shellcheck -S warning` is clean: remove
   `continue-on-error: true` from the `shellcheck (advisory)` step in
   `test.yml` and rename it `shellcheck`.

## Acceptance Criteria

- [ ] `shellcheck -S warning bin/* $(find libexec/bitcoin -type f)`
      exits 0 on master.
- [ ] The CI `shellcheck` step is blocking (no `continue-on-error`).
