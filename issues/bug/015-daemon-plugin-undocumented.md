---
id: BUG-015
type: bug
priority: low
status: open
---

# `daemon` libexec plugin is undocumented, untested, and has no feature origin

audit: 2026-05-13

## Severity

**Low.** The `daemon` plugin exists at `libexec/bitcoin/daemon`
but:

- Has no `done/*.md` feature file documenting why it's here.
- Has no bats test exercising any of its verbs.
- Is not cited from anywhere in `bitcoin help` or the man-page-
  equivalents.
- `CLAUDE.md` §1 mentions "the daemon abstraction" in scope but
  doesn't reference this specific plugin.

The plugin exposes `daemon start / stop / monitor / space`
subcommands. Their behaviour is opaque to a maintainer reading
the repo today.

## Observed

```sh
$ libexec/bitcoin/daemon help
…  # lists subcommands, no behaviour spec
$ git log libexec/bitcoin/daemon
…  # only the initial-import commit
```

Three possibilities:

1. The plugin is genuine prior work the repo intends to keep. It
   needs a backfill feature describing what it does and tests
   pinning the contract.
2. The plugin is dead code from the pre-extraction parent repo
   and should be removed.
3. The plugin is a stub for FEAT-012's bitcoind backend (the
   start/stop verbs would manage a regtest node?) and should be
   merged into FEAT-012's resolution OR pulled forward.

## Root Cause

Pre-extraction transfer. No one has audited this plugin since
the bitcoin repo was carved out of the parent collection.

## Fix Plan

A maintainer decides which of the three branches above applies
and either:

- (a) Files a backfill feature documenting current behaviour and
  pinning it with bats tests.
- (b) Removes the plugin in a patch release with a clear commit
  message.
- (c) Folds the verbs into FEAT-012's backend layer (bitcoind
  start/stop are a natural fit for the `auto` selection logic).

This bug captures the gap; the resolution chooses the path.

## Regression Protection

Once the decision is made, bats tests cover whichever branch
lands.

## Acceptance Criteria

1. The plugin is either documented (with tests) or removed.
2. If documented: a new FEAT-NNN ships and this BUG closes.
3. If removed: the `modules` test in `bitcoin.bats` updates to
   match the four remaining plugins (`bip13`, `bip32`, `bip39`,
   `wif`).
