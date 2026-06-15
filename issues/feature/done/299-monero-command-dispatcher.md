---
id: FEAT-299
type: feature
priority: high
status: shipped
---

# `monero` command dispatcher + package wiring

## Description

**As an** operator of the combined educational stack
**I want** a `monero` command that dispatches to `libexec/monero/<verb>` plugins
**So that** the Monero node/wallet/mining surface coexists with `bitcoin`,
`lightning`, and `fulcrum` from the one rpk package

This is the skeleton the rest of the 3.2.0 milestone hangs off: the dispatcher,
the package wiring, and the test/lint scaffolding. No node logic yet.

## Implementation

- `bin/monero` — dispatcher mirroring `bin/fulcrum`: resolve `libexec/monero/`
  by binary name, exec `libexec/monero/<verb> "$@"`, `help`/`version` (version
  from `$DATADIR/monero/version` installed, `./VERSION` in-tree), per-script
  logging helpers (§10, four levels to stderr).
- `Makefile.in` / `.rpk/package` — add `monero` to `PACKAGES`; stage
  `libexec/monero/*`, `share/doc/monero/*`, `share/monero/*`,
  `share/man/man1/monero-*.1`, `etc/bash_completion.d` entry.
- `libexec/monero/help` (or inline) — verb index.
- `tests/unit/monero.bats` — joined into the combined contract: dispatch works,
  `version` equals the shared `VERSION` (one package), unknown verb errors
  non-zero, and the **no-forbidden-sibling** guard (the §4 boundary test from
  `bitcoin.bats`/FEAT-195 extended to `bin/monero` + `libexec/monero/*`:
  forbidden `cache`/`data`/`hosts`/`scripts`/`task` calls fail CI).

## Acceptance Criteria

1. `monero help` lists the verbs; `monero version` prints the shared `VERSION`.
   Proven by `monero.bats`.
2. `monero <unknown>` exits non-zero with a `warn`/`error` line naming the verb.
3. `.rpk/identity` is unchanged (`bitcoin`); no second package. Proven by a test
   mirroring fulcrum FEAT-055 AC6.
4. `make install` stages `bin/monero` + `libexec/monero/` into the prefix
   (proven by an install-staging test like fulcrum FEAT-055 AC1).
5. `bin/monero` + `libexec/monero/*` call no forbidden siblings; the scanner
   catches a planted forbidden call. Proven by `monero.bats`.
