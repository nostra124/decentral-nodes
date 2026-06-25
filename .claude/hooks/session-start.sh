#!/bin/bash
# SessionStart hook — make `podman` permanently available for this
# project in Claude Code on the web sessions.
#
# The repo's container-based tests (SIT/PIT, see skills/testing.md and
# tests/sit/) and the `.githooks/pre-push` selection logic key off
# `command -v podman`. Cloud sandboxes start without podman, so those
# tiers are silently skipped. Installing podman here means a fresh web
# session can build and run the regtest containers just like a desktop
# checkout.
#
# Synchronous (no async): guarantees podman is present before the agent
# starts so it never races ahead of an unfinished install.
set -euo pipefail

# Only run in the Claude Code remote (web) environment — a local
# desktop checkout manages podman itself.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	exit 0
fi

# Idempotent: nothing to do if podman is already on PATH.
if command -v podman >/dev/null 2>&1; then
	echo "session-start: podman already installed ($(podman --version))" >&2
	exit 0
fi

echo "session-start: installing podman via apt-get…" >&2
export DEBIAN_FRONTEND=noninteractive

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
	SUDO="sudo"
fi

$SUDO apt-get update -qq
$SUDO apt-get install -y --no-install-recommends podman

echo "session-start: podman ready ($(podman --version))" >&2
