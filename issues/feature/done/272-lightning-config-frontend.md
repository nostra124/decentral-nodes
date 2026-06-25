---
id: FEAT-272
type: feature
priority: medium
status: done
---

# `lightning config` — view/edit the effective lightningd configuration

## Motivation

There was no friendly way to see or change lightningd's settings; you
edited the Core Lightning `config` file by hand, and in `--system` mode
that file lives at `/var/lib/lightning/config` owned by the `lightning`
(`_lightning` on macOS) service account at 0640, so a hand edit needs
sudo and easily clobbers ownership. A `config` front end makes the
common operations safe and discoverable, mirroring `bitcoin config`
(FEAT-271).

## Behavior

New plugin `libexec/lightning/config`:

- `config list` — keys explicitly set in the config file (source: conf).
- `config get <key>` — the **effective** value: the conf value if set
  (source: conf), else lightningd's compiled-in default parsed from
  `lightningd --help` (source: default); errors if neither. When
  lightningd isn't installed, only conf values resolve (no default
  fallback).
- `config set <key> <value>` — write `key=value` (replacing any
  existing top-level line). Routes through `install -m 0640` under
  `$SUDO` when the conf isn't writable, **preserving the conf's
  owner:group** (the daemon group model), then warns that a restart is
  needed (`lightning daemon stop && lightning daemon start`).
- `config unset <key>` — remove a key (revert to default).
- `config path` — print the conf path.

The config file is the flat CLN `key=value` format (`#` comments,
key-only boolean flags, no INI `[sections]`). It resolves the state dir
the same way the `daemon` verb does — `/var/lib/lightning` by default,
`$LIGHTNING_DIR` for user-mode, `$LIGHTNING_CONFIG_DIR` to force (tests
use this) — and the config file is always `<dir>/config`. It never calls
the `daemon` plugin (CLAUDE.md §4 no-shared-lib). The lightningd binary
for `--help` defaults parsing prefers `/opt/local`, then
`/opt/homebrew`, then PATH (`$LIGHTNING_LIGHTNINGD` overrides). Owner
detection uses GNU `stat -c` then BSD `stat -f` (coreutils shadows BSD
stat on macOS).

## Acceptance Criteria

1. `config list` prints the conf-set keys. Proven by FEAT-272 tests.
2. `config get <key>` returns the conf value when set, else the
   `lightningd --help` default, else errors. Proven by FEAT-272 (stubbed
   lightningd --help).
3. `config set` replaces/appends the key, writes at 0640 preserving
   owner:group, and warns to restart. Proven by FEAT-272.
4. `config unset` removes the key. Proven by FEAT-272.
5. `config path` prints `<dir>/config`. Proven by FEAT-272.
6. The plugin makes no call to `daemon` (no-shared-lib).
7. Ships `share/man/man1/lightning-config.1` so the FEAT-221
   man-page contract (every dispatchable verb has a page naming it)
   stays green.
