---
id: FEAT-298
type: feature
priority: medium
status: open
---

# `config list` as TSV with defaults + `/etc` config across all three daemons

## Motivation

FEAT-271 reworked `bitcoin config list` from a hand-aligned `key = value`
dump into a machine-readable, default-aware TSV: one row per documented
option as `NAME<TAB>VALUE<TAB>DESCRIPTION`, where VALUE is the
`bitcoin.conf` value if set and otherwise bitcoind's compiled-in default
(parsed from `bitcoind -help`), plus a `--set` filter limiting output to
keys explicitly present in the conf. The other two config front ends
(`lightning config`, `fulcrum config`) still printed the old aligned
dump and had no notion of defaults. This brings them to the same
standard, and finishes the FHS config-location move for lightning.

Note on numbering: FEAT-275 (the next sequential id) is already taken by
the lightning `wallet-backup` feature, and FEAT-276..297 are likewise in
use; FEAT-298 is the next free id.

## Behavior

### `lightning config` (`libexec/lightning/config`)

- `config list` now prints TSV `NAME<TAB>VALUE<TAB>DESCRIPTION`, one row
  per documented `lightningd` option. VALUE is the config value if set,
  else lightningd's compiled-in default. `--set` limits output to
  conf-set keys. Pipeable through `column -t -s$'\t'`.
- Defaults come from a new `config:_dump_help` adapted to CLN's
  `lightningd --help` format: option headers sit in the **first column**
  (`--rpc-file <arg>`, `--name=<file>`, `--version|-V`, bare `--flag`),
  the description begins on the same line after the option token, and
  continuation lines are space-indented; `(default: X)` may be quoted
  (`"lightning-rpc"`). The parser also tolerates the indented
  bitcoind-style stub so the FEAT-272 stub keeps working.
- **Config moved under `/etc` (FHS).** The system config is now
  `/etc/lightning/config` instead of `/var/lib/lightning/config`. The
  resolver (`config:_confdir`) prefers `$LIGHTNING_CONFIG_DIR`, then
  `/etc/lightning`, then the state dir (user-mode/legacy). The system
  installers (`install_macos_system` / `install_system` in
  `libexec/lightning/daemon`) create `/etc/lightning` (0755, owned by the
  `_lightning`/`lightning` service account, traversable), write the
  config there at 0640 owned by the service account, and point the
  generated unit's `lightningd --conf=` at it. `$LIGHTNING_CONFIG_DIR`
  overrides for tests.

### `fulcrum config` (`libexec/fulcrum/config`)

- `config list` now prints TSV `NAME<TAB>VALUE<TAB>DESCRIPTION`. Fulcrum
  has **no `--help` default dump**, so there are no compiled-in defaults:
  VALUE is always the conf value, and DESCRIPTION comes from a small
  built-in map (`config:_descmap`) covering the curated `CONFIG_ALLOW`
  keys (db_mem, max_history, peering, announce, hostname, banner, tcp,
  ssl) plus the wiring keys `init` writes (datadir, bitcoind, rpccookie,
  rpcuser, rpcpassword, tcp, ssl, cert, key, admin); empty for unknown
  keys. `--set` is accepted for symmetry (Fulcrum has no defaults, so
  list is conf-only already). Fulcrum config already lives under
  `/etc/fulcrum` — no move needed.

## Acceptance Criteria

1. `lightning config list` is TSV `NAME<TAB>VALUE<TAB>DESCRIPTION`: a
   conf-set key shows its conf value, an unset option shows its
   `lightningd --help` default + description, and a conf-only key still
   appears. `--set` limits to conf-set keys. Proven by FEAT-298 tests in
   `tests/unit/lightning.bats` (stubbed lightningd --help, hermetic via
   `$LIGHTNING_CONFIG_DIR`).
2. The lightning system config is created at `/etc/lightning/config`
   (0755 dir owned by the service account, 0640 conf), and the generated
   unit's `--conf=` points there. Proven by the BUG-033 system-config
   tests (redirected via `$LIGHTNING_CONFIG_DIR`).
3. `fulcrum config list` is TSV with conf VALUE and a built-in
   DESCRIPTION map (empty for unknown keys); `--set` is accepted. Proven
   by FEAT-298 tests in `tests/unit/fulcrum.bats`.
4. Neither front end gains a shared-library dependency (CLAUDE.md §4).
