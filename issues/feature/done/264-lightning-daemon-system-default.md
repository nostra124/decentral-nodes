---
id: FEAT-264
type: feature
priority: high
status: done
---

# `lightning daemon enable` defaults to `--system` (with `--user` as explicit opt-in)

## Description

**As an** operator running clightning as a substrate other software builds on
**I want** `lightning daemon enable` to install a *system* service by default
**So that** the node survives logout/reboot, matching bitcoin/fulcrum (3.0.0)

Completes the system-default rollout begun in 3.0.0. `--user` is retained
as the explicit rootless opt-in (the FEAT-183 user-mode unit, the default-on
keepalive/alert sidecars, the opt-in autopilot/reconcile/etc. sidecars).
Out of scope: operate-verb resolution (auto-detect is kept), auto-enabling
the unit, and removing `--user`.

## Implementation

`libexec/lightning/daemon` — `cmd_enable`:
- `local system=0` → `local system=1`; add `local user_explicit=0`.
- `--user` arm: `system=0; user_explicit=1`.
- OpenRC branch: emit the "no per-user mode" notice only when
  `user_explicit -eq 1` (OpenRC can't honor an explicit `--user`), then
  install system-wide as before.
- Leave `daemon:_mode` (operate verbs), the sidecar gates, and the install_*
  functions unchanged.
- Update the `daemon` usage banner so it reads "--system (default) or --user".

## Acceptance Criteria

1. `lightning daemon enable` with no flag resolves to **system** mode. Proven
   without root via the `$HOME/.lightning` migrate guard: with `~/.lightning`
   present, a bare enable exits 3 and prints the "--migrate" / "user-mode
   install detected" refusal (the guard lives only in the system installers;
   `install_user` has none). Cross-platform (macOS + Linux system paths share
   the guard).
2. `lightning daemon enable --user` still installs the user-mode unit /
   LaunchAgent and the user-mode sidecars exactly as before. Proven by the
   existing FEAT-183/205/244 tests, now passing `--user` explicitly.
3. Operate verbs (`start`/`stop`/`status`/`monitor`) behave identically —
   they auto-detect installed state. Proven by the unchanged operate-verb
   tests staying green.
4. On OpenRC, a bare enable installs system-wide **without** the "no per-user
   mode" notice; an explicit `--user` emits it (and still installs system).
   Proven by the rewritten FEAT-207 test.
