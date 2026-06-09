---
id: FEAT-060
type: feature
priority: low
status: open
---

# `fulcrum` advanced admin tier (peers / ban / unban / kick / loglevel)

## Description

**As a** node operator running a public-facing Fulcrum server
**I want** `fulcrum peers`, `ban`, `unban`, `kick`, and `loglevel`
**So that** I can moderate clients and peers and adjust runtime log
verbosity from the same command.

These are the remaining `FulcrumAdmin` commands beyond the inspection
core (FEAT-058). They are genuinely supported by the admin RPC but are
operational moderation controls with limited educational value, so
they are kept at low priority. They are **scheduled for the 2.1.0
milestone** (see `issues/ROADMAP-2.1.0.md`) so the `fulcrum` admin
surface ships complete in one release. Builds on the `admin:_call`
client from FEAT-058.

## Implementation

Extend `libexec/fulcrum/admin` with thin wrappers over the admin RPC:
- `peers` / `addpeer <host>` / `rmpeer <host>` — peer list management.
- `ban <id|ip>` / `unban <ip>` / `banlist` — client/IP bans.
- `kick <id|ip>` — disconnect a client.
- `loglevel <normal|debug|trace>` — runtime verbosity.

Each wraps the corresponding `FulcrumAdmin` method and reports the
server's reply; unreachable admin port → `warn` + non-zero, as in
FEAT-058.

## Acceptance Criteria

1. Each verb sends the correct admin method with its arguments,
   asserted against a fixture admin responder. Proven by one bats case
   per verb.
2. `loglevel <bad-value>` is rejected with an `error` naming the value
   before any call is made. Proven by bats.
3. Unreachable admin port yields a `warn`/`error` naming the address
   and non-zero exit for every verb. Proven by a representative bats
   case.
