---
id: BUG-044
type: bug
priority: high
status: open
---

# Unit tests still invoke the pre-`-node` binary names (CI red)

## Severity

**High.** The `bats + pytest unit tests` workflow — the mandatory merge
gate (CLAUDE.md §11, skills/testing.md §2.3) — is red on `master` and on
every PR. No change can satisfy the gate until this is fixed.

## Root cause

Commit `e732c2b` ("refactor: rename all commands to use -node suffix")
renamed the dispatchers `bin/bitcoin` → `bin/bitcoin-node`,
`bin/lightning` → `bin/lightning-node`, etc. (and the matching
`libexec/<cmd>/` → `libexec/<cmd>-node/` directories), but the unit
tests still reference the old paths. They invoke e.g.
`$REPO_ROOT/bin/bitcoin` directly, which no longer exists, so bats
reports a wall of `exited with code 127` ("Command not found").

Confirmed offenders (non-exhaustive):

- `tests/unit/streamline.bats` — `export BITCOIN_BIN=".../bin/bitcoin"`
- `tests/unit/tax-report-de.bats`
- `tests/unit/wallet-merge.bats`
- `tests/unit/bitcoin.bats`, `tests/unit/lightning.bats`,
  `tests/unit/monero.bats`, `tests/unit/fulcrum.bats` — all point at the
  old `bin/<cmd>` / `SELF_LIBEXEC` paths.

## Regression test (write first, per skills/bugs.md)

Add a guard that fails while the breakage exists: assert that every
`bin/<cmd>` path referenced by a `tests/unit/*.bats` setup resolves to an
executable file in the tree. It must fail against the current suite
(paths point at the removed names) and pass once the references are
updated to the `-node` names.

## Fix

1. Update every `tests/unit/*.bats` setup to the `-node` dispatcher
   names and the `libexec/<cmd>-node/` layout.
2. Re-check assertions that hard-code the old command name in expected
   help / warn / usage output — when invoked as `bitcoin-node`, `$SELF`
   is now `bitcoin-node`, so any test asserting `"... is not a bitcoin
   command"` (or similar) must be updated to the new `$SELF`.
3. Run `bats tests/unit/*.bats` locally to a clean pass before pushing.

## Notes

This was deferred during the session that added the podman hook and
`forgejo-node` (the maintainer flagged it as a known, budget-related
breakage to ignore at the time). It is filed here so it is tracked and
scheduled rather than carried as undocumented red CI.
