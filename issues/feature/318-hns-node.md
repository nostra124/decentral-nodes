---
id: FEAT-318
type: feature
priority: low
status: draft
milestone: unscheduled
---

# hns-node — Handshake (HNS) node frontend

## Summary

A Tier 3 node for Handshake (https://handshake.org/), the decentralized
naming/root-zone blockchain — `hsd` full node + `hnsd` light client.
Already listed as planned in the README. Follows the storj/forgejo
dispatcher style.

## Acceptance criteria (draft)

1. `bin/hns-node` dispatcher + `libexec/hns-node/` (storj-style: no shared
   library, FEAT-195 boundary).
2. `daemon install` (hsd from the official release / npm), `enable`,
   `start/stop/restart/status/monitor` via systemd (Linux) / launchd
   (macOS); system-mode under a dedicated account with restricted RPC on
   localhost.
3. Optional light-client mode (`hnsd`) for resolve-only setups.
4. man pages, `Makefile`/`.rpk` registration, README entry, and a bats
   suite matching the shared dispatcher contract (and FEAT-314's parity
   guard).

## Notes

Scope/verbs to be firmed up before implementation. m2pd-node remains an
external package (github.com/nostra124/m2pd), not part of this repo.
