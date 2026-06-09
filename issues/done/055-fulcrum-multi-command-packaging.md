---
id: FEAT-055
type: feature
priority: high
status: done
---

# Ship a second command (`bin/fulcrum`) from the bitcoin package

## Description

**As a** node operator installing the bitcoin package
**I want** the package to install a second top-level command, `fulcrum`,
with its own `libexec/fulcrum/<verb>` plugin tree
**So that** Fulcrum (the Electrum server) can be managed as a peer
command to `bitcoin`, reflecting that it is an independent daemon
rather than a wallet sub-feature.

The packaging is currently hardwired to a single package name. The
install Makefile and `install` script both stage only
`libexec/$(PACKAGE)` (= `libexec/bitcoin`), and the shellcheck lint
target only walks `libexec/$(PACKAGE)`. `bin/*` is already copied
wholesale, so a new `bin/fulcrum` binary ships for free — but its
plugin tree would not. This feature generalises the three hardwired
spots so the one `bitcoin` rpk package can ship multiple commands,
and lands a skeleton `bin/fulcrum` dispatcher. The lifecycle, config,
and admin verbs are filed separately (FEAT-056/057/058).

`.rpk/identity` stays `bitcoin`: this is one package shipping two
commands, not a second package. Out of scope: any Fulcrum lifecycle
behaviour (FEAT-056) and the bitcoin-side Electrum backend (FEAT-059).

## Implementation

1. `bin/fulcrum` — new dispatcher reusing the FEAT-001 header verbatim
   from `bin/bitcoin` (the per-script copy is the sanctioned
   duplication per CLAUDE.md §4/§5). Because the resolver is
   `SELF`-keyed (`$SELF_LIBEXEC/$SELF/<verb>`, `SELF=$(basename $0)`),
   it auto-resolves `libexec/fulcrum/<verb>` with no further wiring.
   Skeleton ships `help`, `version`, and `modules` only.
2. `Makefile.in install` — replace the `libexec/$(PACKAGE)`-only copy
   (lines ~42, ~52–54) with a loop over every `libexec/*` subdir, so
   both `libexec/bitcoin/*` and `libexec/fulcrum/*` stage under their
   own `$(LIBEXECDIR)/<name>/`.
3. `Makefile.in lint` (line ~170) — extend the shellcheck target from
   `libexec/$(PACKAGE)` to `bin/* libexec/*` so `bin/fulcrum` and its
   plugins are linted.
4. `install` script (lines ~34, ~43) — same generalisation as the
   Makefile, staging every `libexec/*` subdir.
5. `tests/unit/fulcrum.bats` — new file. Add the dependency-boundary
   tests that mirror FEAT-195: `bin/fulcrum` and `libexec/fulcrum/*`
   may call only `config`, `secret`, `account` (plus `openssl` and the
   bitcoind RPC); referencing a forbidden sibling (`cache`, `data`,
   `hosts`, `scripts`, `task`, or any `bitcoin` BIP plugin) fails CI.

## Acceptance Criteria

1. `make install` into a staging prefix installs **both**
   `$BINDIR/bitcoin` and `$BINDIR/fulcrum`, and both
   `$LIBEXECDIR/bitcoin/` and `$LIBEXECDIR/fulcrum/` trees. Proven by
   a bats test that runs `make install DESTDIR=<tmp>` and asserts the
   two binaries and two libexec dirs exist.
2. `fulcrum version` prints the same `VERSION` string as `bitcoin
   version` (one package, one version). Proven by a bats test.
3. `fulcrum help` lists available libexec verbs via the shared
   `modules` machinery without error. Proven by a bats test.
4. `make lint` runs shellcheck over `bin/fulcrum` and every
   `libexec/fulcrum/*` file. Proven by confirming a deliberately
   broken `libexec/fulcrum` fixture fails the lint target.
5. The fulcrum dependency-boundary test rejects a planted forbidden
   sibling call and passes on the clean tree, mirroring the two
   FEAT-195 tests. Proven by `tests/unit/fulcrum.bats`.
6. `.rpk/identity` is unchanged (`bitcoin`); no second `.rpk/` package
   is introduced. Proven by inspection / a bats assertion.
