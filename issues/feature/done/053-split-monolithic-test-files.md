# FEAT-053 — split the monolithic unit-test files

**Status:** done
**Milestone:** 3.4.0

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

- [x] No single unit `.bats` file exceeds ~60 tests.
      `bitcoin.bats` (235) → `bitcoin-01..05.bats` (47 each);
      `streamline.bats` (175) → `streamline-01..04.bats` (≤44 each);
      `lightning.bats` (887) → `lightning-01..18.bats` (≤50 each).
- [x] Shared fixtures live in a shared lib (one per family).
      Each family's `setup()`/`teardown()` + every fixture/helper function
      moved verbatim to `tests/unit/lib/<family>.bash`, loaded by each
      chunk via `load lib/<family>`. *Deviation from the literal "one
      `helpers.bash`":* the three families have mutually incompatible
      `setup()` bodies (different env, mocks, PATH shims) that cannot
      coexist in a single file, so each gets its own lib under the
      established `tests/unit/lib/` convention (cf. `node_contract.bash`).
      Fixtures are de-duplicated (defined once, shared by all chunks),
      which is the intent of the criterion.
- [x] Total `@test` count and pass set unchanged.
      Verified per family: the split suites produce a byte-identical TAP
      pass set (status + description) to the pre-split monolith
      (235 + 175 + 887 = 1297 tests, all `ok`).

## Implementation note

The split was mechanical (a heredoc-aware parser that lifts every
non-`@test` block into the family lib and groups the `@test` blocks into
numbered chunks). The `FEAT-314` "every `bin/*-node` has a unit suite"
guard in `dispatcher-paths.bats` was extended to recognise the new
`<base>-NN.bats` part naming.
