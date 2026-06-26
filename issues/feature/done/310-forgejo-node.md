---
id: FEAT-310
type: feature
status: done
milestone: 3.5.0
---

# forgejo-node — Forgejo Git forge + per-platform CI runners

## Summary

A Tier 3 self-hosting node for Forgejo (https://forgejo.org/), a
community fork of Gitea. Installs and operates the Forgejo server and,
crucially, sets up Forgejo Actions runners for specific platforms.
Follows the storj-node/tor-node dispatcher style (thin `bin/` dispatcher
→ `libexec/forgejo-node/<verb>`, no shared library, FEAT-195 dependency
boundary).

## Acceptance criteria

1. `daemon` verb: install (Codeberg release binary), enable/disable,
   start/stop/restart/status/monitor via systemd (Linux) / launchd
   (macOS); system-mode under a dedicated `git` account,
   `/var/lib/forgejo` + `/etc/forgejo/app.ini`.
2. `runner` verb: install the `forgejo-runner` binary; `platforms` lists
   label presets; `register --instance --token --platform` registers a
   runner with the matching labels; enable + lifecycle wire it as a
   service.
3. Platform presets emit correct Forgejo runner labels — `docker`
   (`docker://…`), `lxc` (`lxc://…`), `host`, plus `macos` / `windows`
   (host backend).
4. man pages, `Makefile`/`.rpk` registration, README entry, and a bats
   suite (`tests/unit/forgejo-node.bats`).

## What shipped

- `bin/forgejo-node`, `libexec/forgejo-node/{daemon,runner,help}`.
- man pages `forgejo-node.1`, `forgejo-node-daemon.1`,
  `forgejo-node-runner.1`.
- `contrib/Install-ForgejoRunner.ps1` — a Windows runner installer
  (the bash node can register a Windows runner but can't install a native
  Windows service; nssm or scheduled-task fallback). + `contrib/README.md`.
- `tests/unit/forgejo-node.bats` (incl. macOS/Windows preset coverage).

Merged in PR #124 (node) and PR #125 (Windows installer).
