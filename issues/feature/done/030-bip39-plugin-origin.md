---
id: FEAT-030
type: feature
priority: low
status: done
---

# `bip39` plugin origin — mnemonic seed phrases

audit: 2026-05-13

## Description

**As a** maintainer auditing the surface
**I want** the `libexec/bitcoin/bip39` plugin documented as a
feature
**So that** the traceability invariant holds.

The plugin predates the issue tree. It ships `bip39 words`,
`bip39 create <bits|hex>`, `bip39 check`, `bip39 seed`. Reads the
wordlist from `$XDG_SHARE_HOME/bitcoin/bip39/<lang>.txt`. The
wordlists themselves (10 languages) were untracked / unreferenced
by any install rule until 1.3.0 (`make install` was extended to
copy `share/$(PACKAGE)/*`).

`share/doc/bitcoin/bips/bip-0039.mediawiki` is already vendored
(FEAT-017). Exercised by `bitcoin wallet new`'s mnemonic
generation and by FEAT-013's wallet derive (via the
`mnemonic-to-seed` companion plugin shipped in 1.5.0).

## Acceptance Criteria

1. This file is moved to `issues/feature/done/` with the
   resolution section pointing at the plugin and existing
   coverage.
2. No code change.
