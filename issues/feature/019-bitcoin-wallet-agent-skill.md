---
id: FEAT-019
type: feature
priority: medium
status: open
---

# `bitcoin-wallet` agent skill — educate AI agents on the wallet

## Description

**As a** user delegating bitcoin tasks to an AI agent (Claude Code,
opencode, raven)
**I want** a packaged skill that teaches the agent how this wallet
works — the four design principles, the multi-wallet model, the
git-backed store, the seed-via-`secret` separation, the BIP citation
convention, and the safe-default rules (testnet, mainnet flag, push
without seed)
**So that** an agent can operate the wallet correctly without me
re-explaining the model in every session, and so that the wallet's
educational mission extends to the agents people increasingly use to
read, write, and reason about their tools.

Mirrors `nostra124/rpk`'s `skills/rpk-author/` pattern (one
`SKILL.md`, one `opencode.md`, installed under
`share/<agent>/skills/` and optionally activated by
`make install-skills-user`).

## Implementation

Layout:

    skills/
    └── bitcoin-wallet/
        ├── SKILL.md          Claude / generic skill manifest
        └── opencode.md       opencode-specific entry point

`SKILL.md` frontmatter (matches rpk-author convention):

    ---
    name: bitcoin-wallet
    description: Operate a bitcoin wallet built on the bitcoin(1)
      script. Trigger when the user wants to create, restore, fund,
      or spend from a wallet, build/sign/broadcast a PSBT, label a
      transaction, sync wallets between accounts, or learn how the
      wallet's design (educational, functional, decentralized,
      simple) maps onto a specific BIP.
    ---

`SKILL.md` body covers:

1. **Design principles.** Educational, functional, decentralized,
   simple — and what each one rules in or out.
2. **The multi-wallet model.** Each wallet is a named git repo under
   `~/.bitcoin/wallet/<name>/`; seed lives in `secret` at
   `bitcoin/<name>/seed`; pushing a wallet is safe (no seed travels).
3. **Workflow recipes.** New wallet, restore, derive + receive, send,
   PSBT cold-sign, push/pull between accounts, label a tx, scan for
   recovery.
4. **Guardrails.**
   - Never print or log the mnemonic.
   - Never commit anything that bypasses `secret` for the seed.
   - Default to testnet/regtest; require an explicit `--mainnet`.
   - Cite the BIP for any operation that implements one (point at the
     vendored `share/doc/bitcoin/bips/` per FEAT-017).
   - Don't auto-broadcast on mainnet without confirmation.
5. **Where to read more.** Pointers to `man bitcoin`, the walkthrough
   (FEAT-015), and `share/doc/bitcoin/bips/` for the spec text.

Installation, mirroring rpk's Makefile pattern:

    make install            installs share/claude/skills/bitcoin-wallet/,
                            share/opencode/commands/bitcoin-wallet.md, ...
    make install-skills-user
                            opt-in symlinks into ~/.claude/skills/,
                            ~/.config/opencode/commands/, etc.,
                            *only* if the matching user dir exists.

## Acceptance Criteria

1. `skills/bitcoin-wallet/SKILL.md` and `skills/bitcoin-wallet/opencode.md`
   exist and contain the sections listed above.
2. `make install` places the skill under
   `$INSTALL_SHARE/claude/skills/bitcoin-wallet/` and
   `$INSTALL_SHARE/opencode/commands/bitcoin-wallet.md`.
3. `make install-skills-user` symlinks into the user's agent dirs iff
   they exist; idempotent; documented in `docs/bitcoin.md`.
4. `make uninstall-skills-user` removes only the symlinks it would
   have created.
5. The skill description triggers on the operations it lists (verified
   manually with at least one supported agent).
6. Every BIP-implementing recipe in the skill cites the BIP and links
   to the vendored copy under `share/doc/bitcoin/bips/`.
