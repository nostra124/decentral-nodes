---
id: FEAT-267
type: feature
priority: medium
status: done
---

# macOS system daemons prefer MacPorts, with a service-account runnable arbiter

## Motivation

On macOS, `daemon enable --system` runs the binary as a dedicated
service account (`_bitcoin`). Homebrew installs under `/opt/homebrew`,
a user-owned tree that a restrictive umask can leave non-world-
readable — so the service account can't execute the binary or load its
dylibs, and launchd crash-loops with `EX_CONFIG` / a dyld `errno=13`
and an empty log. MacPorts installs under `/opt/local` as `root:wheel`
with standard world-readable perms — exactly what a boot-persistent
service account needs.

## Behavior

1. **Install default (macOS)** — `daemon:_default_source` prefers
   `port` (MacPorts) when present, then `brew`, then `source`.
2. **Binary resolution** — candidates in preference order:
   `/opt/local/bin/bitcoind` (MacPorts) → `/opt/homebrew/bin/bitcoind`
   (Homebrew) → `PATH`. `$BITCOIN_BITCOIND` overrides.
3. **Runnable arbiter** — in system mode, `daemon:_select_bitcoind`
   runs each candidate *as the service account* (`-datadir=<datadir>
   --version`, which also exercises every parent-dir traverse bit and
   the dylib load) and picks the first that works. A non-runnable
   Homebrew keg is skipped here instead of crash-looping under launchd;
   if none qualifies, `enable` errors with the candidates tried and the
   fix (`sudo chmod -R o+rX "$(brew --prefix)"/{Cellar,opt,lib}`, or
   prefer a MacPorts install).

This supersedes the earlier standalone `--version` preflight, which
false-negatived for bitcoind because, without `-datadir`, bitcoind
probes the operator's home (unreadable by the service account).

## Acceptance Criteria

1. On macOS, `daemon install` with no `--from` auto-detects `macports`
   when `port` is present. Proven by `tests/unit/streamline.bats`
   "FEAT-033 — install auto-detects macports on macos (macports-first)".
2. `enable --system` selects `/opt/local/bin/bitcoind` over a Homebrew
   one when both are present and the MacPorts one runs as the account.
3. `enable --system` errors (no unit installed) when no candidate runs
   as the service account. Proven by "BUG-030 — enable (system)
   refuses to install a unit the service account can't run".
4. Live: a fresh `bitcoin daemon enable` on a hardened-umask macOS host
   brings up a non-crash-looping system bitcoind from MacPorts.
   (Validated 2026-06-13: `state = running`, syncing.)
