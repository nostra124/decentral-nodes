---
id: FEAT-006
type: feature
priority: high
status: open
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

1. `prove tests/vectors/` (post-FEAT-003) passes all suites:
   `base58.t`, `basics.t`, `bip-0032.t`, `bip-0039.t`, `bip-0084.t`,
   `bip-0085.t`, `bip-0173.t`, `bip-0350.t`, `secp256k1.t`,
   `xkey-to-address.t`.
2. `bitcoin help` continues to work as before.
3. `bitcoin --version` reports the same version as before.
4. The `bitcoin.sh` install/symlink is captured in `.rpk/package`.
5. No new file is added to `bin/`.
