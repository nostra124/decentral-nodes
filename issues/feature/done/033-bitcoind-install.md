---
id: FEAT-033
type: feature
priority: medium
status: done
---

# `bitcoin daemon install` — install Bitcoin Core itself

## Description

**As a** new user setting up `bitcoin` on a clean host
**I want** one command that installs the `bitcoind` binary for me
**So that** I don't have to learn the host's package idioms (brew
vs. macports vs. apt vs. building from source) before I can use
the wallet against my own node.

The existing `libexec/bitcoin/daemon` plugin already manages a
running `bitcoind` (start / stop / monitor / space) but assumes it
is already installed. This feature closes that gap.

## Implementation

New verb on the `daemon` plugin (folded into the dispatcher per
BUG-015's branch (c)):

    bitcoin daemon install [--from <source>] [--tag <v>] [--prefix <path>]

`--from` sources, dispatched on `account platform` for the default:

| Source     | Default for           | Action |
|------------|------------------------|--------|
| `brew`     | macOS                  | `brew install bitcoin`. |
| `macports` | macOS (alt)            | `sudo port install bitcoin`. Existing daemon plugin already targets the macports plist on this path. |
| `apt`      | Debian, Ubuntu, PureOS | `sudo apt-get install -y bitcoind` from the Bitcoin Core PPA (`ppa:luke-jr/bitcoincore`). Adds the PPA first if missing. |
| `apk`      | Alpine                 | `sudo apk add bitcoin`. |
| `source`   | any                    | Clone `github.com/bitcoin/bitcoin`, check out `--tag <v>` (default: latest `v*` git tag), `./autogen.sh && ./configure --prefix <path> --disable-wallet --disable-tests && make && sudo make install`. The `--disable-wallet` matches the educational mandate (this repo IS the wallet). |
| `rpk`      | any                    | Defers to `rpk install bitcoind` against the separate `nostra124/bitcoind` rpk package. Until that package ships, this branch errors with a clear "not yet available; see docs/rpk-bitcoind.md" line. |

`--prefix` only affects `--from source`; the package-manager
sources install where the manager decides.

`--tag` only affects `--from source`; default is "the latest `v*`
tag reachable in `github.com/bitcoin/bitcoin`'s default branch".

Auto-detect default for `--from`:

    macos    → brew    (fallback: macports if brew not present)
    pureos   → apt
    ubuntu   → apt
    alpine   → apk
    other    → source

The verb errors with a clear `error` line per skills/logging.md if:

- The selected source's package manager is not installed.
- `--from source` and a build-time tool (autoconf, make, gcc/clang,
  libtool, pkg-config, boost, libdb) is missing.
- The build or install step fails (the verb propagates the
  underlying exit code).

After a successful install, the verb runs `bitcoind --version` and
prints the version to stdout for confirmation.

## Acceptance Criteria

1. `bitcoin daemon install` on a clean Debian/Ubuntu/PureOS host
   installs `bitcoind` via apt and `bitcoin daemon start` brings
   it up.
2. `bitcoin daemon install --from source --tag v27.0` against a
   clean host (with build tools) builds and installs `bitcoind
   v27.0` into the default prefix.
3. `bitcoin daemon install --from rpk` exits non-zero with the
   stub message until ROADMAP-rpk-bitcoind lands.
4. `bitcoin daemon install --from <unknown>` rejects the source
   with a list of accepted values.
5. bats coverage: at least 6 new tests (per-source dispatch with
   mocked package manager, auto-detect on a stubbed `account
   platform`, error path for missing package manager, error path
   for unknown source, stub-error for `--from rpk`, success message
   contains the `bitcoind --version` output).
6. Pre-push hook + CI green on the milestone PR.
7. Cited from `bitcoin help daemon` and from the man page.
