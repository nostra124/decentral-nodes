---
id: FEAT-058
type: feature
priority: high
status: open
---

# `fulcrum` admin inspection (info / sync / stats / clients / logs)

## Description

**As a** node operator watching Fulcrum index the chain
**I want** `fulcrum info`, `sync`, `stats`, `clients`, `logs`, and
`version`
**So that** I can see sync progress (initial indexing takes hours),
server health, and who is connected — without installing the Python
`FulcrumAdmin` tool.

Fulcrum ships a line-based admin RPC on a localhost `admin` port
(configured by FEAT-057). These verbs speak that protocol directly
(newline-delimited JSON), so no extra dependency is needed. `sync` is
the headline educational verb: it derives progress from the synced
height vs. the node tip, both already returned by the admin `getinfo`
call. Depends on FEAT-055/056/057.

Out of scope: the moderation/advanced tier (`ban`/`unban`/`kick`/
`peers`/`loglevel`) — filed separately as FEAT-060, low priority. The
admin `query` command is deliberately **excluded**: address/history
queries belong to the bitcoin `backend` (FEAT-059), keeping the
fulcrum command to inspecting the *server* and bitcoin to querying
*chain data through it*.

## Implementation

`libexec/fulcrum/admin` — a thin client over the admin port
(`$FULCRUM_ADMIN_ADDR`, default `127.0.0.1:<admin port from config>`):
- `admin:_call <method> [args…]` — open the admin socket, send one
  JSON request, read one JSON reply. Tests stub this by pointing
  `$FULCRUM_ADMIN_ADDR` at a local fixture server (or by overriding
  `admin:_call` via a `$FULCRUM_ADMIN_FIXTURE` file of canned JSON).
- `info` — wraps `getinfo`; pretty-prints version, synced height,
  db size, client/address counts.
- `sync` — calls `getinfo`, computes `synced_height` vs the node tip
  it reports, prints a percentage and an "N blocks behind" line; exits
  non-zero (with a `warn`) if the admin port is unreachable.
- `stats` — wraps the admin `stats` call (or the HTTP `stats` port if
  configured), printing the JSON.
- `clients` — wraps `clients`/`sessions`, lists connected peers.
- `logs [-f]` — tail the service journal (`journalctl --user-unit` /
  `log show`) for the fulcrum unit.
- `version` — Fulcrum binary version (`getinfo`) alongside the command
  version.

## Acceptance Criteria

1. `fulcrum info` against a canned `getinfo` fixture prints version,
   synced height, and client count. Proven by bats with
   `$FULCRUM_ADMIN_FIXTURE`.
2. `fulcrum sync` against a fixture where synced height < node tip
   prints the blocks-behind count and a percentage < 100%. Proven by
   bats; a second fixture at tip prints 100% / fully synced.
3. `fulcrum sync` (and every admin verb) exits non-zero and emits a
   `warn`/`error` naming the admin address when the port is
   unreachable. Proven by bats with no fixture server.
4. `fulcrum clients` lists the entries from a multi-client fixture.
   Proven by bats.
5. `fulcrum stats` prints the stats JSON from a fixture. Proven by
   bats.
6. `fulcrum logs` invokes the correct journal command per os×mode
   (mocked). Proven by bats capturing the command line.
7. `fulcrum version` prints both the server version (from fixture) and
   the command's own `VERSION`. Proven by bats.
8. The admin `query` command is **not** exposed as a fulcrum verb.
   Proven by a bats assertion that `fulcrum query` is unknown.
