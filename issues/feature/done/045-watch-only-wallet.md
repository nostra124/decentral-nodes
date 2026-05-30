# FEAT-045: Watch-only wallet (xpub import)

**Status**: done (1.31.0)

## Summary

Add the ability to create a wallet from an account-level extended
public key (xpub). A watch-only wallet can derive receive addresses
and build unsigned PSBTs without holding any seed phrase.

## Motivation

Cold-signing workflows and multi-device setups need a way to monitor
an address set and build transactions on one device while keeping the
private key on another (hardware wallet, air-gapped machine, cold
account). An xpub-based watch-only wallet is the standard mechanism.

## Acceptance criteria

AC#1  `bitcoin wallet watch <name> <xpub>` creates a wallet repo
       with `xpub` and `config` (contains `watch-only=1`) committed.
       Does not call `secret`.

AC#2  `wallet watch` rejects an xpub whose decoded version byte is
       not a BIP-32 public key version (0x0488B21E or 0x043587CF).
       Exit non-zero with a message containing "not a valid xpub".

AC#3  `wallet watch` rejects a duplicate wallet name with "already exists".

AC#4  `wallet derive` on a watch-only wallet derives addresses via
       BIP-32 from the stored xpub + relative path `/0/$idx`.
       Produces the same addresses as a regular wallet created from
       the same seed (round-trip verified).

AC#5  `tx sign` on a watch-only wallet exits non-zero with a message
       containing "watch-only".

AC#6  `bitcoin wallet xpub <name>` prints the account-level xpub
       (`m/84h/0h/0h`) for a regular wallet.

AC#7  `bitcoin wallet xpub <name>` on a watch-only wallet prints the
       stored xpub.

AC#8  `wallet watch` and `wallet xpub` appear in `wallet help`.

## Implementation notes

- `wallet:_is_watch_only()` — checks for `xpub` file in wallet dir
- `wallet:_derive_address()` — detects watch-only, uses relative path
  `/0/$idx` from stored xpub; no `secret` call
- `wallet:_derive_privkey_hex()` — returns error 4 for watch-only
- Man page: `bitcoin-wallet.1` updated with new subcommands
