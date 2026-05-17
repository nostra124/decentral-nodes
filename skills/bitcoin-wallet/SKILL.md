---
name: bitcoin-wallet
description: |
  Operate the `bitcoin(1)` educational Bitcoin wallet. Trigger
  when the user wants to create or restore a wallet, derive a
  receive address, check a balance, build / sign / send a
  transaction, finalise or extract a PSBT, push or pull a
  wallet between machines, select a chain-data backend, or
  reason about how a specific BIP maps onto the wallet's
  design.
---

# `bitcoin-wallet` skill

## 1. Design principles

`bitcoin` is anchored on four words. Use them as the yardstick
when scoping a new operation or trimming an old one:

| Principle | What it rules in | What it rules out |
|---|---|---|
| **Educational** | Every subcommand cites the BIP it implements. The local copy of that BIP is shipped under `share/doc/bitcoin/bips/`. | Magic primitives the documentation doesn't point at. |
| **Functional** | A real wallet: derive, build, sign, broadcast through one of three backends. | "Demo only" features that don't survive a regtest spend. |
| **Decentralized** | Wallet is a per-name git repo the user owns. Seed lives in `secret(1)` so the repo can be pushed without leaking key material. | Re-using a central server as the wallet store. |
| **Simple** | bash + standard Unix utilities. Per-plugin primitives (openssl, dc, basenc). | A shared crypto library. Each BIP plugin is self-contained. |

If a feature can't be justified against at least one of these,
it likely doesn't belong in `bitcoin`.

## 2. The wallet model

A **wallet** is identified by a name. The name selects:

- A per-wallet git repository at
  `$XDG_DATA_HOME/bitcoin/wallets/<name>/`
  (defaults to `~/.local/var/bitcoin/wallets/<name>/`).
  Holds the signing context: `config`, `descriptors`, the
  `addresses` ledger.
- A seed phrase in `secret`, stored under
  `<name>/seed`. The wallet repository itself never sees the
  mnemonic. `secret get <name>/seed` is called on demand
  whenever a derivation is needed.
- A default BIP-32 derivation path of `m/84h/0h/0h/0/<index>`
  (BIP-84 native segwit). `wallet derive` increments the index
  per call and commits the new address to the ledger.

**Backend selection** is global to the shell, not per-wallet:

- `BITCOIN_BACKEND` env var (if set)
- `$XDG_CONFIG_HOME/bitcoin/backend` (set by `backend set`)
- Default: `mempool`.

Only `mempool` is fully implemented in the current release;
`bitcoind` and `blockstream` are scaffolded with clear "not
implemented" errors.

## 3. Workflow recipes

Each recipe maps to one or more shipped verbs. Every BIP-
implementing step links to the vendored spec under
`share/doc/bitcoin/bips/`.

### 3.1 Create a new wallet

```sh
bitcoin wallet new alice
```

Generates a BIP-39 mnemonic, hands it to `secret put
alice/seed`, and initialises the wallet repo. The mnemonic is
**not** printed.

**Spec:** BIP-39 — `share/doc/bitcoin/bips/bip-0039.mediawiki`.

### 3.2 Restore a wallet from a known mnemonic

```sh
secret put alice/seed   # paste mnemonic via secret
mkdir -p ~/.local/var/bitcoin/wallets/alice && \
  cd $_ && git init -b main && \
  : > config && : > descriptors && : > addresses && \
  git -c commit.gpgsign=false -c user.email=t@t -c user.name=t \
      commit -qm "wallet new (restore)"
bitcoin wallet derive alice
```

Run `wallet derive` once per pre-known address index to
reconstruct the ledger. (A first-class `wallet restore` verb
is tracked but not shipped.)

### 3.3 Derive an address + check balance

```sh
bitcoin wallet derive alice
bitcoin wallet addresses alice
bitcoin wallet balance alice
```

`wallet derive` runs the BIP-39 → BIP-32 → BIP-84 → BIP-173
pipeline and appends to the ledger. `wallet balance` queries
the active backend for UTXOs at every ledger address and sums
the values.

**Specs:**
- BIP-32 — `share/doc/bitcoin/bips/bip-0032.mediawiki`
- BIP-39 — `share/doc/bitcoin/bips/bip-0039.mediawiki`
- BIP-173 — `share/doc/bitcoin/bips/bip-0173.mediawiki`

### 3.4 Label an address (or later: a tx, a UTXO)

```sh
bitcoin wallet label alice <addr> "faucet drop"
```

Labels are versioned alongside the address ledger; they
survive `wallet push/pull`.

### 3.5 End-to-end send

```sh
bitcoin wallet send alice <addr> 50000
# → txid printed by the backend
```

Composes:

```
wallet build  →  wallet sign  →  psbt finalize  →  psbt extract  →  wallet broadcast
```

Each step is a callable verb; the composition is what `wallet
send` does in-shell. Fee rate defaults to
`backend estimate-fee 3` (half-hour bucket on mempool); falls
back to 1 sat/vB on backend failure. `--fee-rate N` overrides.

**Specs:**
- BIP-141 (segwit serialisation)
- BIP-143 (segwit sighash) — consumed by `psbt sign`
- BIP-174 (PSBT) — `share/doc/bitcoin/bips/bip-0174.mediawiki`
- BIP-66 (low-S signatures)

### 3.6 Cold-sign over `wallet push/pull`

Two machines: hot has the wallet repo; cold has both the repo
and the seed in `secret`.

```sh
# Hot machine: configure remote, push, build the unsigned PSBT.
bitcoin wallet remote add alice origin git@server:wallets/alice.git
bitcoin wallet push  alice
bitcoin wallet build alice <addr> 50000 > tx.psbt

# Cold machine: pull, sign, finalise.
bitcoin wallet pull  alice
bitcoin wallet sign  alice < tx.psbt | bitcoin psbt finalize > signed.psbt

# Hot machine: extract + broadcast.
bitcoin psbt extract < signed.psbt | bitcoin wallet broadcast alice
```

Because the seed lives in `secret` (not in the wallet repo),
the hot machine never has the mnemonic. The git push is safe
by construction.

### 3.7 Select the chain-data backend

```sh
bitcoin backend                       # view active
bitcoin backend set mempool           # or bitcoind / blockstream
bitcoin backend auto                  # pick bitcoind if reachable, else mempool
bitcoin backend chain-height          # smoke test
bitcoin backend estimate-fee 3        # sat/vB recommendation
```

`bitcoind` and `blockstream` are stubs in the current release.

### 3.8 Verify a descriptor checksum

```sh
bitcoin descriptor checksum "wpkh(<xpub>/0/*)"
bitcoin descriptor verify  "wpkh(<xpub>/0/*)#abcdefgh"
```

**Spec:** BIP-380 — `share/doc/bitcoin/bips/bip-0380.mediawiki`.

## 4. Guardrails

1. **Never print the mnemonic.** The wallet's seed lives in
   `secret`. Reading it back via `secret get` is fine; logging
   the result to a terminal, a file, or a commit message is
   not. Never run `set -x` inside a block that reads the seed.

2. **Never bypass `secret` for the seed.** If you find
   yourself writing the mnemonic into the wallet repo, into
   git, into a Makefile, or into a test fixture, stop. The
   single point where the seed lives is `secret`. That
   property is what makes `wallet push` safe.

3. **Default to testnet/regtest.** The educational walkthrough
   targets testnet. Mainnet operation is gated behind a
   conscious choice: the user has to set the backend to a
   mainnet endpoint and (per FEAT-014's deferred work) pass
   an explicit `--mainnet` flag for `wallet send` to spend on
   mainnet. As long as the `--mainnet` guard isn't shipped,
   treat any unconfigured network as "do not auto-broadcast".

4. **Cite the BIP.** Every subcommand that implements a BIP
   has it cited in `bitcoin help <subcommand>`. When teaching
   a recipe, name the BIP and point at the local copy under
   `share/doc/bitcoin/bips/`. The local path is what makes the
   citation verifiable offline.

5. **Don't auto-broadcast on mainnet without confirmation.**
   `wallet send` will happily broadcast whatever PSBT it
   produces. Before composing `wallet send` on a mainnet
   wallet, ask the user — even if the immediately preceding
   message asked for a send.

6. **Pre-build is reversible; post-broadcast isn't.** The
   build → sign → finalize → extract chain produces hex you
   can inspect (`psbt decode` walks any PSBT record by
   record) and discard. Only the final `wallet broadcast`
   step is irreversible. Default to showing the user the
   extracted hex before broadcasting if the destination is
   unfamiliar.

7. **Same-address reuse is not a hard error.** The wallet
   does not warn on it (per the user's decision). But if the
   recipe is "spend repeatedly to one party," prefer a
   per-tx-fresh derive over reusing one address.

## 5. Where to read more

- `man bitcoin` — the same surface in man-page form with the
  complete subcommand index and a STANDARDS section that
  enumerates every implemented BIP.
- `bitcoin help <subcommand>` — per-subcommand help. Every
  BIP-implementing subcommand cites both the upstream URL and
  the local vendored path.
- `docs/bitcoin-walkthrough.md` — the human walkthrough
  shipped in 1.15.0. Same content as this skill but
  end-user-shaped (no agent guardrails section).
- `share/doc/bitcoin/bips/` — every implemented BIP, vendored
  at the version `bitcoin` is built against.
- `CLAUDE.md` — the package-level notes, including the
  no-shared-library policy and the wallet model in §2.
- `issues/feature/done/` — institutional record of which
  features shipped in which release. When a recipe stops
  working, this is where to look for the relevant FEAT/BUG.
