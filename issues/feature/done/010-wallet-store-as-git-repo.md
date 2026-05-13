---
id: FEAT-010
type: feature
priority: high
status: done
---

# Wallet store as a git repository, seed managed by `secret`

## Description

**As a** user of the bitcoin wallet
**I want** my wallet's persistent state kept as a git repository
**So that** I get history, atomic updates, and — via FEAT-011 —
push/pull sync between my accounts using the SSH remotes the `account`
script already manages.

The seed phrase itself does not live in the wallet repo. It is stored
and retrieved via the existing `secret` script. The wallet repo holds
only the *signing context* (descriptors, address ledger, history,
in-flight PSBTs); the *authority to sign* lives in `secret`. This
separation means the wallet repo can be pushed without leaking the
seed, and it lines up with how `secret` is already used elsewhere in
the collection.

**Multi-wallet by default.** A user holds N independent wallets, each
with its own name, its own seed in `secret` namespaced as
`bitcoin/<name>/seed`, its own descriptor set, its own address ledger,
its own history. Wallets are fully independent — operations on one
never read or write another. `bitcoin wallet list` enumerates them;
every other `bitcoin wallet *` subcommand takes the wallet name as
its first argument (or uses `$BITCOIN_WALLET` if set).

## Implementation

Layout under `~/.bitcoin/wallet/<name>/`:

    .git/
    seed-ref              identifier passed to `secret`, e.g. bitcoin/<name>/seed
    descriptors           one descriptor per line, with checksum
    addresses             tab-separated: index, descriptor-id, address, label
    history               tab-separated: txid, height, direction, amount, label
    psbts/                in-flight PSBTs awaiting signature or broadcast
    .gitignore            excludes the UTXO cache and any backend snapshots

Tracked: anything required to reconstruct or sign *given access to the
seed via `secret`*. Not tracked: anything recomputable from the chain
(UTXO set, mempool view, fee snapshots) — those live under
`~/.cache/bitcoin/<wallet>/` per XDG.

Subcommands:

- `bitcoin wallet new <name>` — generate a BIP-39 mnemonic, store it
  via `secret put bitcoin/<name>/seed`, write `seed-ref`, commit the
  initial descriptor set. Errors out if `<name>` already exists.
- `bitcoin wallet list` — list known wallets, one per line.
- `bitcoin wallet rm <name>` — remove the repo (with confirmation).
  Optionally `--purge-seed` to also call `secret rm` on the seed-ref.
- `bitcoin wallet import <name>` — create a wallet around an existing
  seed (mnemonic read interactively or from stdin), stored via
  `secret`. Useful for restoring from a backup or migrating from
  another wallet.

Signing operations look up the seed via `secret get $(cat seed-ref)`.

`secret` becomes a hard dependency declared in `.rpk/depends/`.

## Acceptance Criteria

1. `bitcoin wallet new alice` creates `~/.bitcoin/wallet/alice/` as a
   git repo with one initial commit and stores the seed via `secret`.
2. `bitcoin wallet new bob` after the above creates a second,
   independent wallet; operations on `alice` don't touch `bob`.
3. `bitcoin wallet list` enumerates both.
4. `bitcoin wallet import alice2` around a known mnemonic produces
   the same descriptors and (after `wallet scan`) the same addresses
   as the original wallet.
5. The wallet repo contains `seed-ref` (a short identifier) but
   no encrypted seed material.
6. `git log` inside the wallet shows the create-commit; subsequent
   `derive-next` (FEAT-013) operations produce one commit each.
7. `~/.cache/bitcoin/alice/` exists and holds the UTXO cache; nothing
   under it appears in `git status` of the wallet repo.
8. Signing operations succeed iff the seed is reachable via `secret
   get $(cat seed-ref)`.
9. `secret` is listed in `.rpk/depends/`.
