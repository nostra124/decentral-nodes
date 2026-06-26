---
id: FEAT-311
type: feature
status: done
milestone: 3.5.0
---

# webmin-node — Webmin web administration service

## Summary

A Tier 3 self-hosting node for Webmin (https://www.webmin.com/), a
browser-based system administration UI (users, packages, services, cron,
firewall, module UIs) serving HTTPS on port 10000 via its own
`miniserv.pl`. Webmin runs as root by design (it administers the host),
so there is no dedicated service account. Storj/forgejo dispatcher style,
FEAT-195 boundary respected.

## Acceptance criteria

1. `daemon install [--from auto|apt|dnf]` — adds the official signed repo
   (upstream `setup-repos.sh`) and installs the `webmin` package;
   `--from` validated before any network/sudo side effect.
2. `daemon enable/disable/start/stop/restart/status/monitor` via the
   systemd `webmin` unit.
3. Linux only; macOS refused with a clear message (no launchd package
   upstream).
4. man pages (with a SECURITY note on the root/port-10000 exposure),
   `Makefile`/`.rpk` registration, README entry, bats suite.

## What shipped

- `bin/webmin-node`, `libexec/webmin-node/{daemon,help}`.
- man pages `webmin-node.1`, `webmin-node-daemon.1`.
- `tests/unit/webmin-node.bats` (11 tests; dispatcher, daemon arg
  validation, dependency-boundary scan, packaging, `make install`).

Landed in PR #128.
