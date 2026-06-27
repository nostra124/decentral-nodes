# FEAT-051 — required-tools preflight for the test suites

**Status:** done
**Milestone:** unscheduled

## Summary

Unit tests shell out to external tools (`xxd`, `dc`, `openssl`, and the
rpk siblings for vector tests). When one is absent, tests fail in
*different* ways than a genuine logic bug — during BUG-021/BUG-022 local
repro, a missing `xxd`/`dc` masked the real failure (signing aborted at
pubkey derivation instead of at the assertion under test). CI declares
the deps in `test.yml`, but there is no fail-fast guard for other
environments (local dev, the cloud sandbox).

## Proposal

Add a `setup_suite` (bats 1.5+) that probes the tools each file needs and
either `skip`s the file with a clear message (matching the
`skip mandoc` / check-vectors convention) or aborts with one explicit
"missing dependency: X" line — never a wall of downstream errors.

## Acceptance Criteria

- [ ] Each unit `.bats` file declares its external-tool needs.
- [ ] A missing tool yields one clear skip/abort message, not a cascade.
- [ ] No change to behaviour when all tools are present.
