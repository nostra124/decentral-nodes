---
id: FEAT-306
type: feature
status: shipped
---

# `bitcoin daemon share-cookie` — make a running node's cookie group-readable

## Description

**As an** operator running lightning/fulcrum against an existing bitcoind
**I want** one command to make that node's RPC cookie group-readable
**So that** sibling daemons authenticate without their own credentials, with
no hand-editing of bitcoind's config — completing the zero-manual external
node bring-up (with BUG-051 group-join + BUG-052 datadir auto-detect)

The cookie-perms change is the one step `lightning` cannot do (§0: the
daemons never shell out to each other), and it applies even to an **external**
bitcoind (MacPorts/Homebrew) that `bitcoin daemon` does not otherwise manage.

## Implementation

`libexec/bitcoin/daemon`:
- `daemon:_running_arg conf|datadir` — the running bitcoind's `-conf` /
  `-datadir` from `ps` ($BITCOIN_PS authoritative seam).
- `daemon:_set_cookieperms` — set `rpccookieperms=group` in the conf
  (idempotent; portable temp-file + `install`, preserving owner via sudo —
  no BSD/GNU in-place sed, no bare redirect per BUG-030).
- `daemon:_restart_running_node` — restart via the detected supervisor
  (macOS launchd label / Linux systemd unit owning a bitcoind).
- `command:share-cookie [--no-restart]` — detect, set, restart, report the
  final cookie perms; errors when no bitcoind is running.
- `enable`'s BUG-048 port-busy refusal now hints at `share-cookie`.

## Acceptance Criteria

1. `share-cookie` sets `rpccookieperms=group` in the running node's conf and
   restarts it; idempotent when already set. Proven by `streamline.bats`.
2. `--no-restart` sets the option but leaves the restart to the operator.
3. Errors clearly when no bitcoind is running.
4. Listed in `daemon help`; the port-busy `enable` refusal points to it.
