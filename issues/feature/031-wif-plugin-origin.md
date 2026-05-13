---
id: FEAT-031
type: feature
priority: low
status: open
---

# `wif` plugin origin — Wallet Import Format

audit: 2026-05-13

## Description

**As a** maintainer auditing the surface
**I want** the `libexec/bitcoin/wif` plugin documented as a
feature
**So that** the traceability invariant holds.

The plugin predates the issue tree. It ships `wif encode [-t][-p]`
and `wif decode`. The vendored standards/README.md documents WIF
as pre-BIP (Base58Check of a private key).

Outstanding gap: `tests/vectors/basics.t` invokes `wif -u`, an
"uncompressed" flag that isn't implemented in this repo's plugin.
FEAT-025 documented this as a deferred dependency (it's a fork of
the vector-test missing-deps probe). This audit re-flags it so a
maintainer can decide whether to implement `wif -u` or to delete
the vector-test invocation that needs it.

## Acceptance Criteria

1. This file is moved to `issues/feature/done/` with the
   resolution section pointing at the plugin and existing tests.
2. The `wif -u` decision (implement vs delete from vectors) is
   either resolved in this PR or filed as a separate follow-up
   BUG against `tests/vectors/basics.t`.
