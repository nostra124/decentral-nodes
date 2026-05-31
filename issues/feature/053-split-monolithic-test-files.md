# FEAT-053 — split the monolithic unit-test files

**Status:** open
**Milestone:** unscheduled

## Summary

`tests/unit/bitcoin.bats` holds 223 `@test`s and `tests/unit/streamline.bats`
138 — together ~80% of the suite in two files spanning many features
(dispatcher, wallet, backend, psbt, descriptor, tx, utxo, tax, price,
address, …). The size makes navigation, review, and selective runs
harder, and concentrates merge conflicts.

## Proposal

Split by feature/verb into focused files mirroring the existing
convention (`bip340.bats`, `bip341.bats`, `bip174-p2pkh.bats`, …), e.g.
`wallet.bats`, `backend.bats`, `tx.bats`, `utxo.bats`, `address.bats`,
`price.bats`, sharing fixtures via a `tests/unit/helpers.bash`. Pure
move + helper-extraction; assertions unchanged so the suite stays green.

## Acceptance Criteria

- [ ] No single unit `.bats` file exceeds ~60 tests.
- [ ] Shared fixtures live in one `helpers.bash`.
- [ ] Total `@test` count and pass set unchanged.
