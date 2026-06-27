---
id: BUG-058
type: bug
priority: high
status: done
milestone: 3.3.4
---

## Resolution

Completed the rename in packaging without touching runtime data refs:
`Makefile.in` `PACKAGES` and `.rpk/package` `COMMANDS` now list all 14
`-node` command names; libexec verbs stage per command; the runtime data
namespaces (`share/bitcoin`, `share/lightning`, …) are copied wholesale
so `share/<cmd>-node/version` and the hardcoded data dir coexist; the
version file installs to `share/<cmd>/version` matching the dispatcher's
`$SELF` read. Regression: `tests/unit/install-tree.bats` (FEAT-313) —
failed against the old packaging, passes now. The `VERSION` bump to cut
3.3.4 remains a separate release step (systemic version drift; see the
audit).

# `make install` ships no verbs for the `-node` commands (rename incomplete)

## Severity

**High.** Every installed node except `forgejo-node`/`webmin-node`/
`usermin-node` is broken: the dispatcher installs but none of its verbs
do, so `bitcoin-node <verb>`, `lightning-node <verb>`, `tor-node <verb>`,
etc. fail on a real install. Dev-tree usage is unaffected, which is why
it went unnoticed.

## Root cause

The `e732c2b` `-node` rename renamed `bin/<cmd>` → `bin/<cmd>-node` and
`libexec/<cmd>/` → `libexec/<cmd>-node/`, but the packaging metadata was
never updated to match:

- `Makefile.in` `PACKAGES` and `.rpk/package` `COMMANDS` still list the
  pre-rename names (`bitcoin lightning fulcrum monero …`). `make install`
  does `cp -a libexec/$p/*` for `$p=bitcoin`, but `libexec/bitcoin` no
  longer exists (it is `libexec/bitcoin-node`), so the `mkdir`-created
  `libexec/bitcoin/` is staged **empty**.
- Seven dispatchers are **not in `PACKAGES` at all** — `tor-node`,
  `ipfs-node`, `storj-node`, `joinmarket-node`, `liquid-node`,
  `stacks-node`, `i2pd-node` — so none of their verbs are staged.
- The VERSION install writes `share/$p/version` (= `share/bitcoin/version`)
  but the dispatcher reads `share/$SELF/version` (= `share/bitcoin-node/
  version`), so an installed `… version` falls back to the hardcoded
  string. `share/` and `share/doc/` dirs are likewise non-`node`.

## Reproduction (verified 2026-06-26)

```
./configure --prefix=/tmp/pfx && make install
ls /tmp/pfx/libexec        # -> bitcoin (empty), …, forgejo-node (full)
SELF_LIBEXEC=/tmp/pfx/libexec /tmp/pfx/bin/bitcoin-node bip39
# -> prints usage; bip39 verb not found (libexec/bitcoin-node missing)
```

## Regression test (write first, per skills/bugs.md)

An **installed-tree** assertion (the dev-tree unit tests can't catch
this): after `./configure && make install` to a temp prefix, for every
dispatcher in `bin/`, assert that (a) `libexec/<cmd>` under the prefix
contains at least one verb and (b) `<cmd> version` prints `$(cat
VERSION)`. Must fail against the current packaging and pass after the
fix. (This overlaps FEAT-313, the broader installed-tree tier — land the
minimal regression here, generalise there.)

## Fix

1. `PACKAGES` (Makefile.in) and `COMMANDS` (.rpk/package) → the `-node`
   names, and include **all** 14 dispatchers.
2. Rename `share/<cmd>/` → `share/<cmd>-node/` and
   `share/doc/<cmd>/` → `share/doc/<cmd>-node/` for the renamed commands,
   updating any runtime path that reads them (e.g. bip39 wordlists under
   `share/bitcoin/bip39/`, the `version` fallback).
3. Audit the man-page install + any other `$p`-keyed path for the same
   assumption.
4. Land the installed-tree regression test (above) so it can't regress.

## Notes

The unit suites pass today because they run dispatchers from the dev tree
(`$BATS_TEST_DIRNAME/../../bin/<cmd>-node` with `SELF_LIBEXEC=…/libexec`)
and the `make install` tests only assert the (empty) staged dir exists,
never that a verb resolves. FEAT-313 closes that testing blind spot.
