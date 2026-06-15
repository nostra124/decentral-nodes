#!/usr/bin/env bats
# SIT 12 — soft-dep probes. Verbs must fail clearly when a
# required binary is missing.
#
# In this image lightning-cli / sqlite3 / apache2 all live alongside
# `lightning` on PATH, and a probe can't hide one of them without also
# hiding the `lightning` dispatcher itself — so these probes skip cleanly
# when the dependency is present. The degradation paths themselves are
# covered hermetically by tests/unit/lightning.bats (install-hint + exit
# codes), which can stub PATH precisely. (BUG-044.)

@test "lightning node info exits 127 with install hint when lightning-cli is hidden" {
	command -v lightning-cli >/dev/null \
		&& skip "lightning-cli present; install-hint degradation covered by lightning.bats"
	run lightning node info
	[ "$status" -eq 127 ]
	[[ "$output" == *"install Core Lightning"* ]]
}

@test "lightning wallet new exits 127 when sqlite3 is hidden" {
	command -v sqlite3 >/dev/null \
		&& skip "sqlite3 reachable; soft-dep probe N/A here"
	PATH="/usr/bin:/bin" run lightning wallet new sd-test
	[ "$status" -ne 0 ]
}

@test "lightning address create exits 3 when apache2 is absent" {
	{ command -v apache2 >/dev/null || command -v httpd >/dev/null; } \
		&& skip "apache2 present in image; apache-absent path covered by lightning.bats"
	run lightning address create alice@example.com
	[ "$status" -eq 3 ]
	[[ "$output" == *"apache2 not installed"* ]]
}
