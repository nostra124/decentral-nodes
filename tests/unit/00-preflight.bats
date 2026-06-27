#!/usr/bin/env bats
#
# FEAT-051 — required-tools preflight. Runs first (the `00-` prefix sorts
# ahead of every other suite under `bats tests/unit/*.bats`), so a missing
# external tool surfaces as one clear "missing: …" line at the top instead
# of a wall of opaque exit-127 errors buried mid-suite.
#
# REQUIRED: tools the unit suites invoke directly; their absence breaks
# tests in confusing ways. OPTIONAL tools (stow, podman, qrencode) are not
# checked here because the suites that use them soft-skip when they're gone.

@test "FEAT-051: required external tools are installed" {
	# tool:purpose pairs, for an actionable message.
	local -a need=(
		"dc:BIP arithmetic (bip32/bip340/…)"
		"xxd:hex I/O across the BIP plugins"
		"openssl:hashing + EC operations"
		"jq:JSON parsing (backend/price/lightning)"
		"basenc:base16/base64 encoding (coreutils)"
		"git:wallet-repo tests (FEAT-010/011)"
		"sqlite3:lightning account-store tests"
		"python3:pytest CGI suite + bip helpers"
	)
	local missing="" entry tool why
	for entry in "${need[@]}"; do
		tool="${entry%%:*}"; why="${entry#*:}"
		command -v "$tool" >/dev/null 2>&1 || missing="$missing
  - $tool ($why)"
	done
	if [ -n "$missing" ]; then
		echo "missing required test tools:$missing" >&2
		echo "install them, e.g.: sudo apt-get install -y dc xxd jq sqlite3 openssl coreutils git python3" >&2
		return 1
	fi
}
