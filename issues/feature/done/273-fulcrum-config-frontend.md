---
id: FEAT-273
type: feature
priority: medium
status: done
---

# `fulcrum config` — list/get/set/unset/path over fulcrum.conf

## Motivation

`fulcrum config` already had `init`/`show`/`get`/`set`/`validate`, but
no friendly way to enumerate the explicitly-set keys, drop a key, or
print the config path. As with bitcoind (FEAT-271), in `--system` mode
`fulcrum.conf` is owned by the dedicated `_fulcrum`/`fulcrum` service
account at 0640, so a hand edit needs sudo and easily clobbers
ownership. Rounding out the front end (modeled on `bitcoin config`)
makes the common operations safe and discoverable.

## Behavior

Extends `libexec/fulcrum/config` (keeps `init`/`show`/`get`/`set`/
`validate`):

- `config list` — keys explicitly set in `fulcrum.conf` (source: conf),
  tolerant of both `key = value` and `key=value` lines.
- `config get <key>` — the conf value if set (source: conf), else an
  error. **No default fallback**: Fulcrum has no `--help`-style default
  dump and may not even be installed, so a key not in the conf errors
  with "not set ... (no default source for Fulcrum)". This is the one
  real difference from the `bitcoin config` template.
- `config set <key> <value>` — write `key = value` (replacing any
  existing top-level line, else append). Stays behind the curated
  allow-list. Routes through `install -m 0640` under `$SUDO` when the
  conf isn't writable, **preserving the conf's owner:group** (the daemon
  group model), then warns that a restart is needed
  (`fulcrum stop && fulcrum start`).
- `config unset <key>` — remove a key (same group-model write + restart
  warning).
- `config path` — print `<datadir>/fulcrum.conf`.

It resolves the config dir from `config:_dir`/`config:_file` (the same
resolution `init` uses; `$FULCRUM_CONFIG_DIR` overrides) and never
shells out to another command (CLAUDE.md §4/§5 no-shared-lib): the
path/owner helpers are this file's own copy. Owner detection uses GNU
`stat -c` then BSD `stat -f` (coreutils shadows BSD stat on macOS).

## Acceptance Criteria

1. `config list` prints the conf-set keys (both spaced and unspaced
   lines). Proven by FEAT-273 tests.
2. `config get <key>` returns the conf value when set, else errors with
   "no default source for Fulcrum" (no default fallback). Proven by
   FEAT-273.
3. `config set` replaces/appends the key, writes at 0640 preserving
   owner:group, and warns to restart. Proven by FEAT-273.
4. `config unset` removes the key. Proven by FEAT-273.
5. `config path` prints `<datadir>/fulcrum.conf`. Proven by FEAT-273.
6. `config init`/`show`/`validate` still work (existing FEAT-057 tests
   stay green).
7. The plugin makes no call to a sibling command (no-shared-lib).
