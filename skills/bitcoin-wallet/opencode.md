---
description: |
  Operate the bitcoin(1) educational wallet. Reach for this
  command when the user wants to create/restore a wallet,
  derive an address, check balance, build/sign/send a tx,
  finalise or extract a PSBT, push/pull a wallet between
  machines, select a chain-data backend, or reason about how
  a specific BIP maps onto the wallet's design.
agent: build
---

# `/bitcoin-wallet`

This is the opencode entry point for the `bitcoin-wallet`
skill. The full reference lives in
[`SKILL.md`](./SKILL.md) — the Claude / generic manifest.
This file mirrors the structure for opencode's command form.

## Design principles

The wallet — and everything written about it — is anchored on
four words: **educational, functional, decentralized, simple**.
Use them as the yardstick when scoping a new operation or
trimming an old one. The fuller breakdown is in `SKILL.md` §1.

## The wallet model (capsule)

- Per-name git repo at
  `$XDG_DATA_HOME/bitcoin/wallets/<name>/`.
- Seed in `secret` at `<name>/seed`, not in the wallet repo.
  `wallet push` is safe because the seed never travels.
- Default derivation path `m/84h/0h/0h/0/<index>`
  (BIP-84 native segwit). `wallet derive` increments and
  commits.

## Workflow recipes

(One opencode invocation per shipped verb path. Each cites
the BIP it implements; the local copy is under
`share/doc/bitcoin/bips/`.)

| Recipe | Command | Spec |
|---|---|---|
| Create | `bitcoin wallet new <name>` | BIP-39 |
| Derive | `bitcoin wallet derive <name>` | BIP-32, BIP-84, BIP-173 |
| Balance | `bitcoin wallet balance <name>` | FEAT-012 backend |
| Label | `bitcoin wallet label <name> <addr> <text>` | — |
| Build | `bitcoin wallet build <name> <addr> <sats>` | BIP-141 + BIP-174 |
| Sign | `bitcoin wallet sign <name>` (PSBT on stdin) | BIP-143 + BIP-66 |
| Finalise | `bitcoin psbt finalize` (PSBT on stdin) | BIP-174 §Finalizer |
| Extract | `bitcoin psbt extract` (PSBT on stdin) | BIP-141 + BIP-144 |
| Broadcast | `bitcoin wallet broadcast <name>` (hex on stdin) | FEAT-012 backend |
| **Send** (composes all above) | `bitcoin wallet send <name> <addr> <sats>` | the pipeline |
| Cold-sign | `wallet push` / `wallet pull` between accounts | git |
| Backend | `bitcoin backend [set\|auto\|estimate-fee N]` | FEAT-012 |
| Descriptor | `bitcoin descriptor checksum\|verify <desc>` | BIP-380 |

The end-to-end walkthrough (with command output and stub
fixtures) lives in
[`docs/bitcoin-walkthrough.md`](../../docs/bitcoin-walkthrough.md).

## Guardrails (must hold)

1. **Never print the mnemonic.** The seed lives in `secret`.
   Reading it via `secret get` is fine; logging the result to
   a terminal, a file, or a commit message is not. Don't run
   `set -x` inside a block that reads the seed.
2. **Never bypass `secret` for the seed.** Writing the
   mnemonic into the wallet repo, into git, into a Makefile,
   or into a test fixture defeats the whole `wallet push`
   safety property.
3. **Default to testnet/regtest.** Mainnet operation is gated
   behind a conscious choice. Until the `--mainnet` flag
   ships (FEAT-014 deferred), treat any unconfigured network
   as "do not auto-broadcast".
4. **Cite the BIP.** When teaching a recipe, name the BIP and
   point at the local vendored copy.
5. **Don't auto-broadcast on mainnet.** Ask the user before
   composing `wallet send` against a mainnet endpoint, even
   if the previous message asked for a send.
6. **Pre-build is reversible; post-broadcast isn't.** Inspect
   the extracted hex with `psbt decode` or `wallet build`
   alone before pulling the trigger.

## Where to read more

- `man bitcoin` — the man-page form.
- `bitcoin help <subcommand>` — per-verb help with BIP
  citations.
- [`SKILL.md`](./SKILL.md) — fuller skill manifest.
- [`docs/bitcoin-walkthrough.md`](../../docs/bitcoin-walkthrough.md) — human walkthrough.
- `share/doc/bitcoin/bips/` — vendored specs.
- `CLAUDE.md` — package notes (no-shared-library policy, etc.).
