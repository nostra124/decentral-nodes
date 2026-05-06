# `bitcoin` — developer notes

> Mirrors `CLAUDE.md.foundation`, specialised for
> educational `bitcoin`.

## 1. Scope

`bitcoin` is the educational Bitcoin frontend. Its
scope is the BIP plugins (BIP 13/32/39/173, WIF, the
daemon abstraction) plus a wallet surface.

Out of scope: lightning (that's `lightning`); on-chain
transaction-history indexing for the whole network
(out of scope for an educational tool).

## 2. Repo conventions

Standard rpk per-package: `bin/bitcoin` dispatcher
plus libexec lookup for BIP plugins. Each plugin under
`libexec/bitcoin/<bip>` cites the BIP it implements.

Educational package: vendors BIP source documents
under `share/doc/bitcoin/standards/` (FEAT-017) and
ships a walkthrough at `docs/bitcoin-walkthrough.md`
(FEAT-015 partial).

The wallet model: **seed phrase lives in `secret`,
not in `bitcoin`**. Wallet verbs read the seed via
`secret get <wallet>/seed` on demand.

## 3. Issue authoring

Same as `CLAUDE.md.foundation`. **Bugs come before
features at the same priority level.**

## 4. The no-shared-lib policy

`bitcoin` calls only `account` and `secret` at
runtime. BIP plugins call only their primitives
(openssl for hashing, awk for encoding); never a
shared crypto-helpers library.

## 5. What is intentionally duplicated

- **Base58 / Bech32 encoding** could be shared with
  `crypt` but is reimplemented per plugin so each is
  self-contained.
- **HD-derivation logic** is in BIP-32 only; BIP-44/49/
  84 inherit by composition, not by importing
  helpers.

## 6. Consumers

End users running personal wallets;
.B lightning
for on-chain channel opens; cluster integrations that
need address derivation.

## 7. Build / install

`./configure && make install`. Stow-based.

## 8. Versioning

Semver. `tests/unit/bitcoin.bats` is the contract;
the BIP vector tests under `tests/vectors/` are the
deeper regression baseline.
