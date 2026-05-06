---
name: bitcoin-wallet
description: |
  Operate the `bitcoin` educational wallet — create
  wallets, derive addresses (BIP 32 paths), check
  balances, sign transactions. The seed phrase lives in
  `secret` (not `bitcoin`); same address use is
  acceptable. Trigger when the user wants to manage a
  Bitcoin wallet, derive an address, look up a UTXO,
  or learn how the BIPs compose.
---

# `bitcoin-wallet` skill

## 1. Design principles

- **Educational.** Every subcommand cites the BIP it
  implements (BIP 13 / 32 / 39 / 173, WIF). Reading
  any plugin under `libexec/bitcoin/<bip>` teaches one
  spec.
- **Functional.** Each verb is a pure transformation
  over key/address/transaction representations.
- **Decentralized.** Address derivation is local and
  offline; balance/UTXO queries go to the configured
  daemon (bitcoind / mempool / blockstream).
- **Simple.** `bitcoin` calls only `account` and
  `secret` at runtime. Seed phrases are stored by
  `secret`, not by `bitcoin`.

## 2. The model

A **wallet** is identified by a name. The name selects:

- a seed phrase in `secret/<wallet>/seed` (BIP 39)
- a BIP-32 derivation root
- a default address kind (legacy / segwit / bech32)
- a default daemon backend

Address derivation:

    bitcoin wallet derive <name> <path>

reads the seed via `secret get <name>/seed`, applies
BIP 32 along `<path>` (e.g. `m/84'/0'/0'/0/0` for
native segwit), and produces an address per BIP 173.

Same address use is **acceptable**: no privacy-leak
warning is emitted (per the user's "same address use
is ok" decision).

## 3. Workflow recipes

(Some commands below are filed as FEAT-018; status:
pending implementation.)

1. **Inspect the BIPs.**

       bitcoin bip32 derive <xpriv> <path>
       bitcoin bip39 from-entropy <hex>
       bitcoin bip13 encode <script>

2. **Create a new wallet.**

       bitcoin wallet new mywallet
       # generates a BIP-39 seed; stores it via:
       #   secret pass-init               (one-time)
       #   secret set mywallet/seed       (the phrase)

3. **Derive an address.**

       bitcoin wallet derive mywallet "m/84'/0'/0'/0/0"

4. **Query balance via the configured daemon.**

       bitcoin wallet balance mywallet
       # backend selectable: bitcoind / mempool / blockstream

5. **Inspect a transaction.**

       bitcoin daemon getrawtransaction <txid>

## 4. Guardrails

1. **The seed phrase is in `secret`** — never log it,
   never `set -x` while reading it.
2. **`bitcoin wallet new` writes to `secret`** — make
   sure you've run `secret pass-init` (FEAT-041)
   first.
3. **Same address use is okay** — but be aware your
   on-chain footprint is observable; if you want
   per-tx fresh addresses, use a new derivation index
   per tx.
4. **Daemon backends differ.** `bitcoind` is most
   complete; mempool / blockstream APIs are read-only.
   Pick the one that matches your trust model.
5. **BIP 32 derivation paths matter.** `m/44'/0'/0'`
   is legacy P2PKH; `m/84'/0'/0'` is native segwit;
   wrong path = wrong wallet. Verify against the
   intended derivation scheme.

## 5. Where to read more

- `man bitcoin`
- `share/doc/bitcoin/standards/README.md` — citation
  map (BIP 13 / 32 / 39 / 173, WIF)
- `man secret` — seed-phrase storage
- `bitcoin-walkthrough.md` — guided wallet tour
  (FEAT-015, partial)
- This package's `CLAUDE.md`
