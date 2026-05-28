# Roadmap — 1.29.0 (minor)

**Foundation.** With the wallet feature-complete and proven on regtest,
1.29.0 turns inward: tighten `bitcoin` into a clean foundation package
whose runtime dependency graph is exactly what `CLAUDE.md` §4 promises —
no more, no less.

A single architectural feature. No new user-facing verbs.

## Status

| Feature | Status | Notes |
|---------|--------|-------|
| FEAT-195 restrict runtime deps to `account` + `config` + `secret` + `crypt` | planned (high) | |

## What lands

1. **FEAT-195 — foundation prep.** Audit every runtime shell-out and
   bring the dependency surface in line with the no-shared-lib policy:
   at runtime `bitcoin` should call only `account`, `config`, `secret`,
   and `crypt` (plus each BIP plugin's own primitives — `openssl`,
   `awk`, `xxd`). Catalogue the current calls, remove or re-route any
   that fall outside that set, and pin the contract with a test so the
   boundary can't silently regress.

## Depends on

- The full command surface being stable (hence sequenced after the
  feature milestones) so the dependency audit covers the final shape.

## Notes

This is groundwork for `bitcoin` as a foundation package; it may
surface follow-up issues (any dependency that turns out to be load-
bearing and hard to drop gets its own ticket rather than being forced
into this milestone). High priority because every later milestone
inherits whatever dependency surface this one settles.
