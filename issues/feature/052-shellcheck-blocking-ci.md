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

## Proposal

1. Run `make lint` locally; triage every `-S warning` finding (fix or
   justify with a scoped `# shellcheck disable=` + reason).
2. Remove `continue-on-error: true` from the `shellcheck (advisory)`
   step in `test.yml`; rename it `shellcheck`.

## Acceptance Criteria

- [ ] `shellcheck -S warning bin/* $(find libexec/bitcoin -type f)`
      exits 0 on master.
- [ ] The CI `shellcheck` step is blocking (no `continue-on-error`).
