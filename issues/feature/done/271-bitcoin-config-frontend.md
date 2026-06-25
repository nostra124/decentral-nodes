---
id: FEAT-271
type: feature
priority: medium
status: done
---

# `bitcoin config` — view/edit the effective bitcoind configuration

## Motivation

There was no friendly way to see or change bitcoind's settings; you
edited `bitcoin.conf` by hand, and in `--system` mode that file is
owned by the `_bitcoin` service account (0640), so a hand edit needs
sudo and easily clobbers ownership. A `config` front end makes the
common operations safe and discoverable.

## Behavior

New plugin `libexec/bitcoin/config`:

- `config list` — keys explicitly set in `bitcoin.conf` (source: conf).
- `config get <key>` — the **effective** value: the conf value if set
  (source: conf), else bitcoind's compiled-in default parsed from
  `bitcoind -help` (source: default); errors if neither.
- `config set <key> <value>` — write `key=value` (replacing any
  existing top-level line). Routes through `install -m 0640` under
  `$SUDO` when the conf isn't writable, **preserving the conf's
  owner:group** (the daemon group model), then warns that a restart is
  needed.
- `config unset <key>` — remove a key (revert to default).
- `config path` — print the conf path.

It resolves the datadir from the `bitcoind-datadir` file `daemon
enable` records (`$BITCOIN_CONFIG_DATADIR` overrides) and never calls
the `daemon` plugin (CLAUDE.md §4 no-shared-lib). Owner detection uses
GNU `stat -c` then BSD `stat -f` (coreutils shadows BSD stat on macOS).

## Acceptance Criteria

1. `config list` prints the conf-set keys. Proven by FEAT-271 tests.
2. `config get <key>` returns the conf value when set, else the
   `bitcoind -help` default, else errors. Proven by FEAT-271 (stubbed
   bitcoind -help).
3. `config set` replaces/appends the key, writes at 0640 preserving
   owner:group, and warns to restart. Proven by FEAT-271 + live
   (system conf stayed `_bitcoin:_bitcoin 0640`).
4. `config unset` removes the key.
5. `config path` prints `<datadir>/bitcoin.conf`.
6. The plugin makes no call to `daemon` (no-shared-lib).
