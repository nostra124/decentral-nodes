---
id: FEAT-302
type: feature
priority: medium
status: shipped
---

# `monero config {list,get,set}` — effective-config frontend over monerod

## Description

**As an** operator tuning a Monero node
**I want** `monero config list/get/set` to show and change the effective monerod
config with its defaults
**So that** I can see what the node will actually use without hand-parsing
`monerod --help` or the config file

Mirrors `bitcoin config` (FEAT-298): effective config = the value in the config
file else the compiled-in default, presented as TSV `NAME⇥VALUE⇥DESCRIPTION`,
with the config file under `/etc` (FHS) for the system service.

## Implementation

`libexec/monero/config`:
- `config:_confdir` — `/etc/monero` for the system service (mirrors the daemon's
  `@CONF@`), per-user dir for `--user`.
- `config:_dump_help` — parse `monerod --help` into `NAME⇥DEFAULT⇥DESCRIPTION`
  (awk; portable, no gawk-only idioms — see BUG-039), extracting the
  compiled-in default from the help text.
- `command:list` — merge the parsed defaults with the on-disk config values in
  awk (NOT `read`, which collapses consecutive TSV tabs and drops empty VALUEs —
  the FEAT-298 lesson), emitting `NAME⇥VALUE⇥DESCRIPTION`.
- `command:get <key>` — effective value (config else default).
- `command:set <key> <value>` — write to the `/etc/monero` config via
  `$SUDO install -m 0640` under the `_monero` group (no bare redirection — the
  BUG-030 lesson).

## Acceptance Criteria

1. `monero config list` emits TSV `NAME⇥VALUE⇥DESCRIPTION` including options left
   at their compiled-in default (non-empty VALUE column). Proven by `monero.bats`
   with a stubbed `monerod --help`.
2. `monero config get <key>` returns the config value, or the default when unset.
3. `monero config set <key> <value>` persists to `/etc/monero` with 0640
   `_monero`-group perms and is read back by `get`/`list`.
4. The list/default parsing is tooling-portable (BSD awk + gawk) — no gawk-only
   constructs. Proven on this host.
