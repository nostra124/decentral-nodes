---
id: FEAT-305
type: feature
status: shipped
---

# Uniform `daemon status` across the stack (bitcoin + fulcrum)

## Description

**As an** operator of the combined stack
**I want** `<cmd> daemon status` on every daemon
**So that** I can check reachability/height the same way for bitcoin,
lightning, fulcrum, and monero

`lightning` and `monero` (FEAT-301) already had `daemon status`; `bitcoin`
and `fulcrum` did not. This adds them for parity, with the same group-read,
no-sudo posture.

## Implementation

- `libexec/bitcoin/daemon`: `command:status` + `help:status` + a
  `daemon:_bitcoin_cli` resolver ($BITCOIN_CLI seam). Runs
  `bitcoin-cli -datadir=<datadir> [chain] getblockchaininfo` (cookie auth in
  the group-readable datadir — no sudo) and prints
  `healthy (… block N)` / `syncing (… blocks/headers)` / `down` (exit
  non-zero, with a hint). Listed in `daemon help`.
- `libexec/fulcrum/daemon`: `command:status` + `help:status` + a small
  self-contained `daemon:_admin_getinfo` probe (§5 duplication of the admin
  reachability; $FULCRUM_ADMIN_FIXTURE / $FULCRUM_ADMIN_ADDR seams). Reports
  `healthy (… height N)` / `down`. Added a `libexec/fulcrum/status` symlink
  so both `fulcrum status` and `fulcrum daemon status` work.

## Acceptance Criteria

1. `bitcoin daemon status` reports healthy+height / syncing / down (non-zero),
   reading via bitcoin-cli with no sudo. Proven by `streamline.bats`.
2. `fulcrum daemon status` (and `fulcrum status`) report healthy+height /
   down via the admin RPC, no sudo. Proven by `fulcrum.bats`.
3. Each `daemon help` lists `status`; `daemon help status` describes it.
