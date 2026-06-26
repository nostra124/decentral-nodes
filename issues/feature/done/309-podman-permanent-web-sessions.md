---
id: FEAT-309
type: feature
status: done
milestone: 3.5.0
---

# Permanently install podman in Claude Code web sessions

## Summary

The container-based test tiers (SIT/PIT, `skills/testing.md`, `tests/sit/`)
and the `.githooks/pre-push` selection logic key off `command -v podman`.
Cloud sandboxes start without podman, so those tiers silently skip and a
web session can never run the regtest containers. Install podman on every
Claude Code on the web session so a fresh checkout behaves like a desktop
one.

## Acceptance criteria

1. A `SessionStart` hook installs `podman` via the system package manager
   on Claude Code web sessions.
2. Idempotent (no-op when podman is already present).
3. Remote-only: guarded by `$CLAUDE_CODE_REMOTE`, so desktop checkouts are
   untouched.
4. Synchronous, so podman is ready before the agent runs any tests.
5. The shared hook + settings are committed; per-user `.claude/` state
   stays git-ignored.

## What shipped

- `.claude/hooks/session-start.sh` — idempotent, remote-only, synchronous
  podman installer.
- `.claude/settings.json` — registers the hook on `SessionStart`.
- `.gitignore` — commit the shared hook + settings, ignore the rest of
  `.claude/`.

Verified on Ubuntu 24.04: installs podman 4.9.3, idempotent re-run is a
no-op, non-remote run exits silently. Merged in PR #124.
