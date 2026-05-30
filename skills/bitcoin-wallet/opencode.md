---
description: |
  Operate the bitcoin(1) educational wallet. Reach for this
  command when the user wants to create/restore a wallet, derive
  an address, check balance, build/sign/send a tx, fee-bump
  (RBF/CPFP) a stuck tx, do coin control (freeze/select UTXOs),
  finalise or extract a PSBT, push/pull a wallet between
  machines, set up a watch-only wallet, validate/classify/
  generate an address, fetch a BTC/EUR price or German tax
  report, select a chain-data backend, or reason about how a
  specific BIP maps onto the wallet's design.
agent: build
---

# `/bitcoin-wallet`

This is the opencode entry point for the `bitcoin-wallet`
skill. The full reference lives in
[`SKILL.md`](./SKILL.md) — the manifest Claude and Raven
consume. This file mirrors the structure for opencode's
command form. The skill follows the rpk skill convention
(<https://github.com/nostra124/rpk>, `docs/PACKAGING.md`).

## Design principles

The wallet — and everything written about it — is anchored on
four words: **educational, functional, decentralized, simple**.
Use them as the yardstick when scoping a new operation or
trimming an old one. The fuller breakdown is in `SKILL.md`.

## The wallet model (capsule)

- Per-name git repo at `$XDG_DATA_HOME/bitcoin/wallets/<name>/`.
- Seed in `secret` at `<name>/seed`, not in the wallet repo.
  `wallet push` is safe because the seed never travels.
- Default derivation path `m/84h/0h/0h/0/<index>` (BIP-84
  native segwit). `wallet derive` increments and commits.
- `config` carries a `network` line; `network=mainnet` gates
  `wallet send` behind an explicit `--mainnet`.

## Workflow recipes

Each cites the BIP it implements; the local copy is under
`share/doc/bitcoin/bips/`.

| Recipe | Command | Spec |
|---|---|---|
| Create | `bitcoin wallet new <name>` | BIP-39 |
| Restore | `bitcoin wallet new <name> --restore` + `wallet derive` | BIP-32/39 |
| Watch-only | `bitcoin wallet watch <name> <xpub>` | BIP-32 (neutered) |
| Derive | `bitcoin wallet derive <name>` | BIP-32, BIP-84, BIP-173 |
| Balance | `bitcoin wallet balance <name>` | FEAT-012 backend |
| Address tools | `bitcoin address validate\|type\|decode\|generate` | BIP-13/173/350 |
| Label | `bitcoin wallet label <name> <addr> <text>` | FEAT-018 |
| Build | `bitcoin tx build <name> <addr> <sats>` | BIP-141 + BIP-174 |
| Sign | `bitcoin tx sign <name>` (PSBT on stdin) | BIP-143 + BIP-66 |
| Finalise | `bitcoin tx finalize` (→ bip174) | BIP-174 §Finalizer |
| Extract | `bitcoin tx extract` (→ bip174) | BIP-141 + BIP-144 |
| Broadcast | `bitcoin tx broadcast <name>` (hex on stdin) | FEAT-012 backend |
| **Send** (composes all above) | `bitcoin wallet send <name> <addr> <sats> [--mainnet]` | the pipeline |
| Coin control | `bitcoin utxo ls\|freeze\|unfreeze\|select <name>` | FEAT-037 |
| Fee-bump | `bitcoin tx bump <name> <txid> --rbf\|--cpfp` | BIP-125 |
| Cold-sign | `wallet push` / `wallet pull` between machines | git |
| Backend | `bitcoin backend [set\|auto\|estimate-fee N]` | FEAT-012 |
| Price | `bitcoin price fetch\|get\|source\|status` | FEAT-040 |
| Tax (DE) | `bitcoin tax label\|report-de <name>` | FEAT-038/039 |
| Descriptor | `bitcoin descriptor wallet <name>` / `bitcoin bip380 checksum\|verify` | BIP-380 |

The end-to-end walkthrough (with command output and stub
fixtures) lives in
[`docs/bitcoin-walkthrough.md`](../../docs/bitcoin-walkthrough.md);
the canonical-vs-deprecated verb map is in
[`docs/command-surface.md`](../../docs/command-surface.md).

## Guardrails (must hold)

1. **Never print the mnemonic.** The seed lives in `secret`.
   Reading it via `secret get` is fine; logging the result to a
   terminal, a file, or a commit message is not. Don't run
   `set -x` inside a block that reads the seed.
2. **Never bypass `secret` for the seed.** Writing the mnemonic
   into the wallet repo, into git, into a Makefile, or into a
   test fixture defeats the whole `wallet push` safety property.
3. **Honour the mainnet guard.** `network=mainnet` wallets
   refuse `wallet send` without `--mainnet`. Don't add the flag
   on the user's behalf — it's the one conscious confirmation
   for an irreversible mainnet broadcast. Default to testnet.
4. **Cite the BIP.** When teaching a recipe, name the BIP and
   point at the local vendored copy.
5. **Don't auto-broadcast on mainnet.** Show the extracted hex
   and ask before broadcasting, even if the previous message
   asked for a send.
6. **Pre-build is reversible; post-broadcast isn't.** Inspect
   with `bitcoin tx decode` before pulling the trigger.

## Where to read more

- `man bitcoin` — the man-page form (per-subcommand: FEAT-041).
- `bitcoin help <subcommand>` — per-verb help with BIP citations.
- [`SKILL.md`](./SKILL.md) — fuller skill manifest.
- [`docs/bitcoin-walkthrough.md`](../../docs/bitcoin-walkthrough.md) — human walkthrough.
- [`docs/command-surface.md`](../../docs/command-surface.md) — canonical verb map.
- `share/doc/bitcoin/bips/` — vendored specs.
- `CLAUDE.md` — package notes (no-shared-library policy, etc.).
