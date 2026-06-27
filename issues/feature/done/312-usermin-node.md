---
id: FEAT-312
type: feature
status: done
milestone: 3.5.0
---

# usermin-node — Usermin per-user web interface service

## Summary

A Tier 3 self-hosting node for Usermin
(https://www.webmin.com/usermin.html), Webmin's sibling: a simplified
per-user web interface (mail, password change, SSH keys, home-dir file
manager, cron) on HTTPS port 20000 via the same `miniserv.pl`. Its
miniserv starts as root to authenticate local accounts and runs each
session as that user — no host administration (that stays in
webmin-node). Storj/forgejo dispatcher style, FEAT-195 boundary.

## Acceptance criteria

1. `daemon install [--from auto|apt|dnf]` — adds the official signed repo
   (shared with Webmin) and installs the `usermin` package; `--from`
   validated before any side effect.
2. `daemon enable/disable/start/stop/restart/status/monitor` via the
   systemd `usermin` unit.
3. Linux only; macOS refused with a clear message.
4. man pages (with a SECURITY note), `Makefile`/`.rpk` registration,
   README entry, bats suite.

## What shipped

- `bin/usermin-node`, `libexec/usermin-node/{daemon,help}`.
- man pages `usermin-node.1`, `usermin-node-daemon.1`.
- `tests/unit/usermin-node.bats` (11 tests).

Landed in PR #128. Pairs with FEAT-311 (webmin-node).
