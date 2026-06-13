---
id: FEAT-262
type: feature
priority: high
status: done
---

# `fulcrum` daemon defaults to `--system` (with `--user` as explicit opt-in)

## Description

**As an** operator running Fulcrum as an Electrum backend for other services
**I want** `fulcrum enable` to install/manage a *system* service by default
**So that** the indexer survives logout/reboot without remembering a flag

Mirrors FEAT-261 for the fulcrum command surface. Flip the default daemon
mode to `--system`; keep `--user` as an explicit rootless opt-in. No
capability removed.

## Implementation

`libexec/fulcrum/service`:
- `service:_mode()` — change `local mode=user` → `local mode=system`
  (used by `start`/`stop`/`monitor`/`space`).
- `command:enable()` — change `local mode=user` → `local mode=system`.
- `command:disable()` — change `local mode=user` → `local mode=system`.
- Inline help: `help:enable` describes `--system` as default, `--user` as
  the rootless opt-in; update the "default user" comments.

## Acceptance Criteria

1. `fulcrum enable` with no flag installs the **system** unit
   (`/etc/systemd/system/fulcrumd.service` with `User=fulcrum`, or the
   macOS LaunchDaemon) and does **not** touch the per-user bus. Proven by a
   new `fulcrum.bats` test.
2. `fulcrum enable --user` still installs the rootless per-user unit (no
   `User=`). Proven by the existing `--user` test, which stays green.
3. `fulcrum enable --system` is unchanged. Proven by the existing
   `--system` test.
4. `fulcrum disable` with no flag targets the **system** unit. Proven by a
   new test.
5. `help enable` names `--system` as the default. Proven by a grep test.
