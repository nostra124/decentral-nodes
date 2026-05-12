---
id: FEAT-006
type: feature
priority: high
status: done
---

# Make `bin/bitcoin` sourceable as `bitcoin.sh` so vector tests run

## Description

**As a** developer running the bitcoin BIP vector tests
**I want** the `t/*.t` files to find their `bitcoin.sh` source target
**So that** the test suite actually runs.

Every test in `t/` starts with `. bitcoin.sh` but no such file exists
in the repo. The vector tests have been broken since extraction.
Fixing this unblocks every other bitcoin feature ticket because we get
a regression net before changing anything.

## Implementation

Guard `bin/bitcoin`'s command-line dispatcher so that sourcing the
file defines all functions (`bitcoinAddress`, `bip32`, `bip39`, `wif`,
`hash160`, `secp256k1`, `segwitAddress`, …) without executing any
command:

    [[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

placed immediately above the `if [[ $# == 0 ]]; then command:help` block.

Install `bin/bitcoin` to `$PREFIX/bin/bitcoin` AND symlink (or install)
it as `$PREFIX/bin/bitcoin.sh` so that `. bitcoin.sh` resolves on
`$PATH`. Document the dual name.

No file split. No extracted library. The same file serves both modes.

## Acceptance Criteria

1. `prove tests/vectors/` passes all suites — **deferred to
   FEAT-025**. The original wording referenced "(post-FEAT-003)"
   for the prerequisite that vendors the external commands the
   .t files invoke (`base58`, `dc`, `wif -u`). FEAT-003 was
   never filed; FEAT-025 takes its place and is in the next
   roadmap.
2. `bitcoin help` continues to work as before. ✓
3. `bitcoin version` reports the same version as before. ✓
4. The `bitcoin.sh` install symlink is created by `make install`. ✓
   (Makefile.in `install` target now does
   `ln -sf bitcoin $BUILD_DIR$BINDIR/bitcoin.sh`.)
5. No new file is added to `bin/` in the source tree. ✓

## Resolution

Shipped in 1.1.0.

- `bin/bitcoin` gained the source guard
  `[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0` immediately
  before the command dispatcher.
- `Makefile.in install` creates `bitcoin.sh` symlink alongside
  the binary.
- `Makefile.in check-vectors` now assembles a temp PATH with
  `bitcoin.sh`, `bitcoin`, and every `libexec/bitcoin/*` plugin
  so `prove` finds the sourceable file and the plugins.
- `tests/unit/bitcoin.bats` gained two regression tests
  ("bin/bitcoin is sourceable without side effects" and
  "sourcing bin/bitcoin defines the BIP function library").

The follow-up FEAT-025 covers vendoring or detecting the
remaining external dependencies (`base58`, `dc`, `wif -u`) so
that `prove tests/vectors/` can actually pass end-to-end.
