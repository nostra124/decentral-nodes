# `bitcoin` walkthrough

A first-time tour of the educational Bitcoin frontend, from
`bitcoin wallet new` to a broadcast txid.

This document is the human counterpart to the man page
(`man bitcoin`); each step here corresponds to a subcommand
documented there. Every BIP referenced has a vendored copy
under `share/doc/bitcoin/bips/`.

## Design principles

`bitcoin` is built around four words. They are the yardstick
for every feature in scope and every cleanup that lands:

1. **Educational** — every subcommand cites the BIP it
   implements. The local copy is the same revision you'd find
   upstream, pinned at install time. There is no "magic"
   primitive that the documentation doesn't point at.
2. **Functional** — the tool is a real wallet. It derives
   addresses, builds and signs transactions, and broadcasts
   through one of three configurable backends. It is not a
   demo.
3. **Decentralized** — the wallet is a git repository the user
   owns. Seed material is held outside `bitcoin` itself, in
   [`secret(1)`](https://github.com/nostra124/secret), so the
   repo can be pushed between machines without leaking key
   material. The cold-signing flow is the headline.
4. **Simple** — the tool is bash + standard Unix utilities. No
   shared cryptography library; each BIP plugin reaches for the
   primitives it needs (openssl, dc, basenc) and is otherwise
   self-contained. The whole thing reads top-to-bottom.

## Prerequisites

- A working `bitcoin` (`./configure && make install`).
- [`secret`](https://github.com/nostra124/secret) on `$PATH`.
  The wallet stores its seed via `secret put <name>/seed`; the
  wallet repo itself never touches the mnemonic.
- One of: a reachable `bitcoind` (`bitcoin backend bitcoind`),
  a chosen public backend (`bitcoin backend mempool` —
  trusted-third-party trade-off; the default), or
  `bitcoin backend blockstream`. Only `mempool` is fully
  implemented in this release; the others return a clear "not
  implemented" if invoked.
- The default network in this milestone is mainnet on the
  mempool.space backend; for the walkthrough switch to a
  testnet/signet faucet endpoint by exporting
  `BITCOIN_MEMPOOL_URL=https://mempool.space/signet` (or your
  preferred public endpoint) before any of the steps below.

## 1. Create a wallet

```sh
$ bitcoin wallet new alice
bitcoin: info - wallet 'alice' created at ~/.local/var/bitcoin/wallets/alice
```

What happened:

- A BIP-39 mnemonic was generated and handed to
  `secret put alice/seed`. The mnemonic itself is **not** in
  the wallet repository — only `secret` has it.
- `~/.local/var/bitcoin/wallets/alice/` was initialised as a git
  repository with a `config` (network selector) and an empty
  `descriptors` file.

**Standards:**
[BIP-39](https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki)
mnemonic seed phrases —
[local copy](../share/doc/bitcoin/bips/bip-0039.mediawiki).

## 2. Derive a receive address

```sh
$ bitcoin wallet derive alice
bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu
```

Internally this:

1. Reads the seed via `secret get alice/seed`.
2. Passes through `mnemonic-to-seed` (BIP-39 PBKDF2 → 64-byte
   seed).
3. `bip32 create` derives the BIP-32 master extended key.
4. `bip32 derive m/84h/0h/0h/0/<index>/N` walks the BIP-84
   P2WPKH branch and neuters to a public child key.
5. The resulting 33-byte compressed pubkey is HASH160'd and
   bech32-encoded (BIP-173) as the bc1q… address.
6. The address (with its index and an empty label) is appended
   to the wallet's `addresses` ledger and committed via git.

Run `bitcoin wallet derive alice` again to get the next
address (`m/84h/0h/0h/0/1/N`), and so on. The ledger is
plain TSV; `bitcoin wallet addresses alice` prints it.

**Standards:**
[BIP-32](https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki) (HD wallets) —
[local](../share/doc/bitcoin/bips/bip-0032.mediawiki),
[BIP-84](https://github.com/bitcoin/bips/blob/master/bip-0084.mediawiki) (native segwit derivation paths),
[BIP-173](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki) (bech32 addresses) —
[local](../share/doc/bitcoin/bips/bip-0173.mediawiki).

## 3. Fund the address and check the balance

Send some sats to `alice`'s first address from a faucet (or
from any wallet you control). Wait for one confirmation.

```sh
$ bitcoin wallet balance alice
100000
```

`bitcoin wallet balance` iterates every derived address, asks
the active backend `get-address-utxos`, sums the values, and
prints the total in satoshis.

## 4. Label addresses

```sh
$ bitcoin wallet label alice bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu "faucet drop"
bitcoin: info - label set for bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu
```

Labels are versioned alongside the address ledger. They survive
`wallet push`/`wallet pull` (see §6) so multiple machines see
the same annotations.

## 5. Send

The headline command. Goes from "I have UTXOs" to "txid from
backend" in one line:

```sh
$ bitcoin wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000
f00df00df00df00df00df00df00df00df00df00df00df00df00df00df00df00d
```

Internally `wallet send` composes five verbs in a pipe:

```
wallet build  →  wallet sign  →  psbt finalize  →  psbt extract  →  wallet broadcast
```

Each step is exposed as a standalone subcommand, so you can run
the pipeline by hand (useful when the signing key lives on a
different machine; see the cold-signing flow below).

What each step does:

- **`wallet build`** walks the ledger, asks the backend for
  UTXOs, greedy-selects largest-first until inputs cover
  `<sats> + estimated fee`, serialises a BIP-141 unsigned
  transaction, and wraps it as a PSBT with
  `PSBT_GLOBAL_UNSIGNED_TX` plus one `PSBT_IN_WITNESS_UTXO`
  per input. The fee rate comes from
  `bitcoin backend estimate-fee 3` unless `--fee-rate` is
  supplied; on backend failure it falls back to 1 sat/vB with
  a warn line.
- **`wallet sign`** iterates the wallet's address ledger,
  derives each index's raw private key, and pipes the PSBT
  through `psbt sign` once per key. The signer is a no-op on
  inputs the current key can't sign, so the pass is safe.
- **`psbt sign`** itself computes the BIP-143 sighash preimage,
  signs via openssl `pkeyutl` over secp256k1, BIP-66 low-S
  canonicalises the DER signature, and inserts a
  `PSBT_IN_PARTIAL_SIG` record (type 0x02) keyed by the
  compressed pubkey.
- **`psbt finalize`** promotes the first `PARTIAL_SIG` on each
  input to a `PSBT_IN_FINAL_SCRIPTWITNESS` record (BIP-141
  witness stack `[sig+sighash, pubkey]`), and strips the
  per-input fields BIP-174 §Finalizer says a finaliser must
  drop.
- **`psbt extract`** reassembles a BIP-141 + BIP-144 segwit
  raw tx: version + marker/flag + inputs + outputs + per-input
  witness + locktime. The output is broadcastable hex.
- **`wallet broadcast`** POSTs the hex to the active backend
  and prints the returned txid.

**Standards:**
[BIP-141](https://github.com/bitcoin/bips/blob/master/bip-0141.mediawiki) (segwit transaction serialization),
[BIP-143](https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki) (segwit sighash),
[BIP-174](https://github.com/bitcoin/bips/blob/master/bip-0174.mediawiki) (PSBT) —
[local](../share/doc/bitcoin/bips/bip-0174.mediawiki),
[BIP-66](https://github.com/bitcoin/bips/blob/master/bip-0066.mediawiki) (low-S signatures).

## 6. The cold-signing flow

The same trip, split across two accounts (`alice-hot` and
`alice-cold`). The hot machine has the wallet repo but the
seed lives only in `secret` on the cold side.

```sh
# Hot machine: build the unsigned PSBT.
hot$  bitcoin wallet remote add alice-hot origin git@server:wallets/alice.git
hot$  bitcoin wallet push   alice-hot
hot$  bitcoin wallet build  alice-hot bc1qrecipient 50000 > tx.psbt

# Cold machine: pull, sign, and finalize.
cold$ bitcoin wallet pull   alice-cold
cold$ bitcoin wallet sign   alice-cold < tx.psbt  \
        | bitcoin psbt finalize                   \
        > signed.psbt

# Hot machine: extract + broadcast.
hot$  bitcoin psbt extract  < signed.psbt | bitcoin wallet broadcast alice-hot
<txid>
```

The wallet repository is shared via git: `wallet remote add`
configures the URL, `wallet push` and `wallet pull` are thin
wrappers around `git push` / `git pull --rebase`. Because the
seed lives in `secret` (which is **not** in the repo), the
cold side can sign without the hot side ever seeing the
mnemonic.

**Standards:**
[BIP-174](https://github.com/bitcoin/bips/blob/master/bip-0174.mediawiki) (PSBT),
plus the wallet-repo conventions documented in `CLAUDE.md`.

## 7. Configure the backend

```sh
$ bitcoin backend
mempool
$ bitcoin backend set bitcoind
$ bitcoin backend
bitcoind
$ bitcoin backend chain-height
863412
$ bitcoin backend estimate-fee 3
21
```

The active backend is chosen by, in order:

1. `BITCOIN_BACKEND` env var.
2. `$XDG_CONFIG_HOME/bitcoin/backend` (set via `backend set`).
3. Default `mempool`.

The mempool implementation hits `mempool.space`'s REST API
(override the host with `BITCOIN_MEMPOOL_URL`). The bitcoind
and blockstream backends are scaffolded; calling their verbs
returns a clear "not implemented" until they are fleshed out.

## Where to go next

- `man bitcoin` — the same surface in conventional man-page
  form, with the complete subcommand index.
- `bitcoin help <subcommand>` — per-subcommand help. Every BIP-
  implementing subcommand cites its spec with both upstream URL
  and the local vendored path.
- `share/doc/bitcoin/bips/` — every implemented BIP, vendored
  at the version `bitcoin` is built against.
- `issues/feature/done/` — the institutional record of which
  features shipped in which release.
