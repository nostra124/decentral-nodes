---
name: bitcoin-wallet
description: Operate the bitcoin(1) educational Bitcoin wallet
long_description: Operate the bitcoin(1) educational Bitcoin wallet. Trigger when the user wants to create or restore a wallet, derive a receive address, check a balance, build / sign / send a transaction, fee-bump a stuck tx (RBF / CPFP), do coin control (freeze / select UTXOs), finalise or extract a PSBT, push or pull a wallet between machines, set up a watch-only wallet, validate / classify / generate an address, fetch a BTC/EUR price or a German FIFO tax report, select a chain-data backend, or reason about how a specific BIP maps onto the wallet's design.
role: [user]
references: secret/secret-user
---

# bitcoin-wallet

Operate the `bitcoin(1)` educational Bitcoin wallet — a bash
package that derives addresses, builds and signs transactions,
and broadcasts them through a chain-data backend. Every
subcommand cites the BIP it implements, and the seed phrase
never lives in the wallet repo: it lives in `secret(1)`.

This skill follows the rpk skill convention (see
<https://github.com/nostra124/rpk>, `docs/PACKAGING.md`): one
skill file consumed by Claude and Raven. Read it before
operating the wallet so you carry the model — and the
guardrails — into the session.

## When to use

Trigger this skill when the user says any of:

- "Create / restore a bitcoin wallet", "new wallet `<name>`".
- "Give me a receive address", "what's my balance?".
- "Send `<sats>` to `<addr>`", "build / sign / broadcast a tx".
- "My transaction is stuck — bump the fee" (RBF or CPFP).
- "Freeze that UTXO", "spend specific inputs", "coin control".
- "Sign this PSBT on the cold machine", "finalise / extract a PSBT".
- "Push / pull my wallet to the other machine".
- "Set up a watch-only wallet from this xpub".
- "Is this a valid address? what type is it?", "generate a P2WPKH / P2TR address".
- "What was BTC/EUR on `<date>`?", "give me a German tax report".
- "Which backend am I on?", "switch to bitcoind / blockstream".
- "How does BIP-32 / 39 / 84 / 173 / 174 map onto this wallet?".

## Design principles

`bitcoin` is anchored on four words. Use them as the yardstick
when scoping a new operation or trimming an old one:

| Principle | What it rules in | What it rules out |
|---|---|---|
| **Educational** | Every subcommand cites the BIP it implements. The local copy of that BIP is shipped under `share/doc/bitcoin/bips/`. | Magic primitives the documentation doesn't point at. |
| **Functional** | A real wallet: derive, build, sign, fee-bump, broadcast through a backend. | "Demo only" features that don't survive a regtest spend. |
| **Decentralized** | Wallet is a per-name git repo the user owns. Seed lives in `secret(1)` so the repo can be pushed without leaking key material. | Re-using a central server as the wallet store. |
| **Simple** | bash + standard Unix utilities. Per-plugin primitives (openssl, dc, basenc). | A shared crypto library. Each BIP plugin is self-contained. |

If a feature can't be justified against at least one of these,
it likely doesn't belong in `bitcoin`.

## The wallet model

A **wallet** is identified by a name. The name selects:

- A per-wallet git repository at
  `$XDG_DATA_HOME/bitcoin/wallets/<name>/`
  (defaults to `~/.local/var/bitcoin/wallets/<name>/`).
  Holds the signing context: `config`, `descriptors`, the
  `addresses` ledger, the `history` ledger, `frozen.tsv`, and
  the cached `transactions/<txid>.{hex,json}`.
- A seed phrase in `secret`, stored under `<name>/seed`. The
  wallet repository itself never sees the mnemonic.
  `secret get <name>/seed` is called on demand whenever a
  derivation is needed (and `secret put <name>/seed` is the only
  place a mnemonic is written).
- A default BIP-32 derivation path of `m/84h/0h/0h/0/<index>`
  (BIP-84 native segwit). `wallet derive` increments the index
  per call and commits the new address to the ledger.
- A `network` line in `config` (testnet by default). A wallet
  set to `network=mainnet` refuses to broadcast a `wallet send`
  unless the caller passes `--mainnet` (see Guardrails).

**Backend selection** is global to the shell, not per-wallet:

- `BITCOIN_BACKEND` env var (if set)
- `$XDG_CONFIG_HOME/bitcoin/backend` (set by `backend set`)
- Default: `mempool`.

Only `mempool` is fully implemented in the current release;
`bitcoind` and `blockstream` are scaffolded with clear "not
implemented" errors. `daemon install` can fetch and run a real
Bitcoin Core node, but the `bitcoind` *backend* (RPC plumbing)
is still a stub — don't promise on-node queries yet.

## Workflow recipes

Each recipe maps to one or more shipped verbs. Every BIP-
implementing step links to the vendored spec under
`share/doc/bitcoin/bips/`.

### Create a new wallet

```sh
bitcoin wallet new alice
```

Generates a BIP-39 mnemonic, hands it to `secret put
alice/seed`, and initialises the wallet repo. The mnemonic is
**not** printed.

**Spec:** BIP-39 — `share/doc/bitcoin/bips/bip-0039.mediawiki`.

### Restore a wallet from a known mnemonic

```sh
secret put alice/seed                 # paste mnemonic via secret
bitcoin wallet new alice --restore    # init repo around the existing seed
bitcoin wallet derive alice           # walk the gap limit to rebuild the ledger
```

`wallet derive` runs the BIP-39 → BIP-32 → BIP-84 → BIP-173
pipeline; the gap-limit walk (FEAT-044) re-discovers used
addresses. For a public-only wallet, see watch-only below.

### Watch-only wallet from an xpub

```sh
bitcoin wallet watch cold-view <xpub>
bitcoin wallet derive    cold-view     # public derivation only
bitcoin wallet balance   cold-view
```

No seed in `secret`; the wallet can derive and watch but cannot
sign. **Spec:** BIP-32 (neutered keys).

### Derive an address + check balance

```sh
bitcoin wallet derive    alice
bitcoin wallet addresses alice
bitcoin wallet balance   alice
```

`wallet derive` runs the BIP-39 → BIP-32 → BIP-84 → BIP-173
pipeline and appends to the ledger. `wallet balance` queries
the active backend for UTXOs at every ledger address and sums
the values.

**Specs:** BIP-32 (`bip-0032.mediawiki`), BIP-39
(`bip-0039.mediawiki`), BIP-173 (`bip-0173.mediawiki`).

### Inspect, classify, or generate an address

```sh
bitcoin address validate <addr>          # is it well-formed?
bitcoin address type     <addr>          # p2pkh | p2sh | p2wpkh | p2wsh | p2tr
bitcoin address decode   <addr>          # version + program
bitcoin address generate --p2wpkh <pubkey-hex>   # default; or --p2pkh / --p2tr
```

**Specs:** BIP-13 (P2SH), BIP-173 (bech32 v0), BIP-350
(bech32m / P2TR) — `bip-0173.mediawiki`, `bip-0350.mediawiki`.

### Label an address, tx, or UTXO

```sh
bitcoin wallet label alice <addr> "faucet drop"
bitcoin wallet history alice --label
```

Labels are versioned alongside the ledgers; they survive
`wallet push/pull`. Tax categories feed `tax report-de`.

### End-to-end send

```sh
bitcoin wallet send alice <addr> 50000
# → txid printed by the backend
```

`wallet send` composes the canonical transaction pipeline:

```
tx build  →  tx sign  →  tx finalize  →  tx extract  →  tx broadcast
```

Each step is a callable verb under `bitcoin tx` (the
transaction-as-noun surface, FEAT-036); `finalize` / `extract`
/ `decode` pass through to the `bip174` plugin. Fee rate
defaults to `backend estimate-fee 3` (half-hour bucket on
mempool); falls back to 1 sat/vB on backend failure.
`--fee-rate N` overrides. On a `network=mainnet` wallet,
`wallet send` refuses to broadcast without `--mainnet`.

**Specs:** BIP-141 (segwit serialisation), BIP-143 (segwit
sighash), BIP-174 (PSBT — `bip-0174.mediawiki`), BIP-66
(low-S signatures).

### Coin control (freeze / select UTXOs)

```sh
bitcoin utxo ls     alice [--include-frozen]
bitcoin utxo freeze alice <txid:vout> --reason "dust / do-not-spend"
bitcoin utxo select alice --target 50000 --strategy branch-and-bound
bitcoin wallet send alice <addr> 50000 --utxo <txid:vout>   # spend a chosen input
```

Frozen outpoints live in `frozen.tsv` and are hidden from
selection until `utxo unfreeze`.

### Fee-bump a stuck transaction

```sh
bitcoin tx bump alice <txid> --rbf  [--fee-rate 12]   # replace-by-fee
bitcoin tx bump alice <txid> --cpfp [--fee-rate 12]   # child-pays-for-parent
```

`--rbf` rebuilds the tx spending the same inputs at a higher
fee; `--cpfp` spends a wallet-owned output of the stuck tx into
a high-fee child. **Spec:** BIP-125 (opt-in RBF).

### Cold-sign over `wallet push/pull`

Two machines: hot has the wallet repo; cold has both the repo
and the seed in `secret`.

```sh
# Hot machine: configure remote, push, build the unsigned PSBT.
bitcoin wallet remote add alice origin git@server:wallets/alice.git
bitcoin wallet push  alice
bitcoin tx build     alice <addr> 50000 > tx.psbt

# Cold machine: pull, sign, finalise.
bitcoin wallet pull  alice
bitcoin tx sign      alice < tx.psbt | bitcoin tx finalize > signed.psbt

# Hot machine: extract + broadcast.
bitcoin tx extract < signed.psbt | bitcoin tx broadcast alice
```

Because the seed lives in `secret` (not in the wallet repo),
the hot machine never has the mnemonic. The git push is safe by
construction. Inspect any intermediate PSBT with
`bitcoin tx decode` (a thin pass-through to `bip174 decode`).

### Select the chain-data backend

```sh
bitcoin backend                  # view active
bitcoin backend set mempool      # or bitcoind / blockstream (stubs)
bitcoin backend auto             # pick bitcoind if reachable, else mempool
bitcoin backend chain-height     # smoke test
bitcoin backend estimate-fee 3   # sat/vB recommendation
```

`bitcoind` and `blockstream` backends are stubs in the current
release.

### Price + tax

```sh
bitcoin price source --set coingecko
bitcoin price fetch --from 2024-01-01 --to 2024-12-31   # the only networked price verb
bitcoin price get 2024-07-01                            # EUR/BTC, cache only
bitcoin tax  label alice <txid> acquisition
bitcoin tax  report-de alice --year 2024                # FIFO inventory, BTC/EUR
```

`price get` never fetches silently — it reads the
`btc-eur.tsv` cache that `price fetch` populates.

### Verify a descriptor checksum

```sh
bitcoin descriptor wallet alice              # emit a checksummed wpkh descriptor
bitcoin bip380 checksum "wpkh(<xpub>/0/*)"   # checksum / verify moved to bip380 in 1.23.0
bitcoin bip380 verify   "wpkh(<xpub>/0/*)#abcdefgh"
```

**Spec:** BIP-380 — `share/doc/bitcoin/bips/bip-0380.mediawiki`.

## Guardrails

1. **Never print the mnemonic.** The wallet's seed lives in
   `secret`. Reading it back via `secret get` is fine; logging
   the result to a terminal, a file, or a commit message is
   not. Never run `set -x` inside a block that reads the seed.

2. **Never bypass `secret` for the seed.** If you find yourself
   writing the mnemonic into the wallet repo, into git, into a
   Makefile, or into a test fixture, stop. The single point
   where the seed lives is `secret`. That property is what
   makes `wallet push` safe.

3. **Honour the mainnet guard.** A wallet whose `config` says
   `network=mainnet` refuses `wallet send` unless the caller
   passes `--mainnet` (shipped in FEAT-014). Do **not** add
   `--mainnet` on the user's behalf to silence the error — it is
   the one conscious confirmation gating an irreversible
   mainnet broadcast. Default new wallets to testnet/regtest;
   the educational walkthrough targets testnet.

4. **Cite the BIP.** Every subcommand that implements a BIP has
   it cited in `bitcoin help <subcommand>`. When teaching a
   recipe, name the BIP and point at the local copy under
   `share/doc/bitcoin/bips/`. The local path is what makes the
   citation verifiable offline.

5. **Don't auto-broadcast on mainnet without confirmation.**
   `wallet send` and `tx broadcast` will happily push whatever
   they produce. Before broadcasting on a mainnet wallet, show
   the user the extracted hex and ask — even if the immediately
   preceding message asked for a send.

6. **Pre-build is reversible; post-broadcast isn't.** The
   build → sign → finalize → extract chain produces hex you can
   inspect (`tx decode` / `bip174 decode` walks any PSBT record
   by record) and discard. Only `tx broadcast` is irreversible.
   Default to showing the user the extracted hex first when the
   destination is unfamiliar.

7. **Coin control before fee-bumping.** A frozen UTXO is frozen
   for a reason — never `utxo unfreeze` to make a send "just
   work" without telling the user why it was frozen.

8. **Same-address reuse is not a hard error.** The wallet does
   not warn on it. But if the recipe is "spend repeatedly to
   one party," prefer a per-tx-fresh `wallet derive` over
   reusing one address.

## Common failure modes

- **`secret get <name>/seed` fails** → the wallet is watch-only
  or the seed was never `put`. Signing verbs (`tx sign`,
  `wallet send`) can't run; derivation and balance still can.
- **`wallet send` exits non-zero with a mainnet message** →
  the wallet is `network=mainnet` and `--mainnet` was omitted.
  Surface the message; do not auto-retry with the flag.
- **`backend bitcoind/blockstream: not implemented`** → only
  `mempool` is wired. `backend set mempool` or `backend auto`.
- **`price get` returns nothing** → the date isn't cached. Run
  `price fetch` for the range first (the only networked verb).
- **`bitcoin psbt …` is missing** → the standalone `psbt`
  command was deprecated (1.23.0) and removed (1.24.0). Use
  `bitcoin tx {decode,finalize,extract}` or the `bip174` plugin.

## Related skills

- **rpk/bugs** — file and fix bugs the rpk way.
- **rpk/features** — design and ship new features.
- **secret/secret-user** — where the seed lives; `secret get/put <name>/seed`.

## Where to read more

- `man bitcoin` — the same surface in man-page form with the
  complete subcommand index and a STANDARDS section enumerating
  every implemented BIP (per-subcommand man pages: FEAT-041).
- `bitcoin help <subcommand>` — per-subcommand help. Every BIP-
  implementing subcommand cites both the upstream URL and the
  local vendored path.
- `docs/bitcoin-walkthrough.md` — the human walkthrough
  (FEAT-015). Same content as this skill but end-user-shaped
  (no agent guardrails section).
- `docs/command-surface.md` — the canonical verb map after the
  FEAT-035 streamline (which names are canonical vs deprecated).
- `share/doc/bitcoin/bips/` — every implemented BIP, vendored at
  the version `bitcoin` is built against.
- `CLAUDE.md` — package-level notes, including the no-shared-
  library policy (§4) and the wallet model (§2).
- `issues/done/` — institutional record of which features
  shipped in which release. When a recipe stops working, this
  is where to look for the relevant FEAT/BUG.
