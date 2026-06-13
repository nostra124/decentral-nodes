---
id: FEAT-261
type: feature
priority: high
status: done
---

# `bitcoin daemon` defaults to `--system` (with `--user` as explicit opt-in)

## Description

**As an** operator deploying bitcoind as a substrate other software builds on
**I want** `bitcoin daemon` to install/manage a *system* service by default
**So that** the node survives logout/reboot without me remembering a flag

Today the daemon verbs default to `--user` (`systemctl --user` / launchd
`gui/$uid`), which only runs while a login session is active. Flipping the
default to `--system` makes the out-of-the-box posture deployment-ready.
`--user` stays as an explicit opt-in for personal/educational, macOS, and
rootless/CI use. No capability is removed. Lightning is out of scope (see
`ROADMAP-3.0.0.md`).

## Implementation

`libexec/bitcoin/daemon`:
- `daemon:_mode()` — change `local mode=user` → `local mode=system`
  (used by `start`/`stop`/`monitor`/`space`).
- `command:enable()` — change `local mode=user` → `local mode=system`.
- Inline help: `help:enable` and the verb-usage block now describe
  `--system` as the default and `--user` as the rootless opt-in; update the
  BUG-015 comment that says "--user (default)".

## Acceptance Criteria

1. `bitcoin daemon enable` with no flag installs the **system** unit
   (`/etc/systemd/system/bitcoind.service` with `User=bitcoin`, or the
   macOS LaunchDaemon running as `bitcoin`) and does **not** touch the
   per-user bus. Proven by an updated `streamline.bats` test.
2. `bitcoin daemon enable --user` still installs the rootless per-user unit
   (no `User=` line / no `UserName`). Proven by the existing `--user` tests,
   which remain green.
3. `bitcoin daemon enable --system` is unchanged. Proven by the existing
   `--system` tests.
4. `help enable` (and `--help`) name `--system` as the default and `--user`
   as the opt-in. Proven by a help-text grep test.
