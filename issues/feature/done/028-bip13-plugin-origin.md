---
id: FEAT-028
type: feature
priority: low
status: done
---

# `bip13` plugin origin — Base58 / Base58Check encoding for P2SH addresses

audit: 2026-05-13

## Description

**As a** maintainer auditing the surface
**I want** the `libexec/bitcoin/bip13` plugin documented as a
feature
**So that** the traceability invariant holds.

The plugin predates the issue tree. It ships `bip13
base58-encode` / `bip13 base58-decode` / `bip13 base58-verify`
plus the help/version smoke verbs. Every BIP-32 round-trip in
this repo passes through `bip13 base58-encode` for the final
xprv/xpub string and through `bip13 base58-decode` to reverse it.

`share/doc/bitcoin/bips/bip-0013.mediawiki` is already vendored
(FEAT-017). The plugin is exercised indirectly by every wallet
test that ends in a `bc1q…` address.

## Acceptance Criteria

1. This file is moved to `issues/feature/done/` with the
   resolution section pointing at the plugin and at the existing
   coverage.
2. No code change.
