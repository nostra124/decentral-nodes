---
id: FEAT-027
type: feature
priority: low
status: open
---

# Dispatcher contract (help / version / modules)

audit: 2026-05-13

## Description

**As a** maintainer auditing the surface
**I want** the dispatcher's three core verbs (`help`, `version`,
`modules`) documented as an explicit feature
**So that** the traceability invariant in `skills/audit.md` §1
holds: every observable behaviour ties back to a closed feature
or bug file.

The dispatcher predates the issue tree. `bitcoin help`,
`bitcoin version`, and `bitcoin modules` have existed since the
extraction. This ticket backfills the origin documentation —
their behaviour is already locked down by bats tests 1–9 in
`tests/unit/bitcoin.bats`.

## Acceptance Criteria

1. This file is moved to `issues/feature/done/` with the
   resolution section pointing at the existing tests.
2. No code change.
