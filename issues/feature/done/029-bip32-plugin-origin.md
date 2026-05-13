---
id: FEAT-029
type: feature
priority: low
status: done
---

# `bip32` plugin origin — Hierarchical Deterministic Wallets

audit: 2026-05-13

## Description

**As a** maintainer auditing the surface
**I want** the `libexec/bitcoin/bip32` plugin documented as a
feature
**So that** the traceability invariant holds.

The plugin predates the issue tree. It ships `bip32 create`,
`bip32 derive`, `bip32 ser32`, `bip32 ser256`, `bip32 hash160`,
`bip32 is-secret`, `bip32 is-public`. Three bugs against it have
been fixed (BUG-013 and BUG-014 closed; the latent `bip32 create
-s` flag-not-implemented + `bip49/84()` env-var-override no-op
are still open audit follow-ups not blocking any user flow).

`share/doc/bitcoin/bips/bip-0032.mediawiki` is already vendored
(FEAT-017). The plugin's full derivation chain (master + child
non-hardened + child hardened + neutered) is exercised by the
BUG-013/014 regression tests and by FEAT-013's wallet derive
test (against the canonical BIP-39 abandon mnemonic).

## Acceptance Criteria

1. This file is moved to `issues/feature/done/` with the
   resolution section pointing at the plugin and existing
   regression coverage.
2. No code change.
