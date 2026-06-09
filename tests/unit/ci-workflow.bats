#!/usr/bin/env bats
#
# CI-workflow hygiene regression tests.
#
# BUG-028: .github/workflows/test.yml shipped with no timeout-minutes
# and no concurrency group, so a slow/hanging `bats` job ran up to
# GitHub's 6-hour default and every push spawned an uncancelled run —
# draining the Actions budget and blocking merges/releases. These tests
# assert the guards stay in place.

setup() {
	export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
	export TEST_YML="$REPO_ROOT/.github/workflows/test.yml"
}

@test "BUG-028 — tests workflow caps job runtime (timeout-minutes)" {
	[ -f "$TEST_YML" ]
	# Both jobs (unit + lint) must declare a runtime cap so a hang
	# fails fast instead of running for the 6-hour default.
	local n
	n=$(grep -cE '^[[:space:]]+timeout-minutes:[[:space:]]*[0-9]+' "$TEST_YML")
	[ "$n" -ge 2 ]
}

@test "BUG-028 — tests workflow cancels superseded runs (concurrency)" {
	[ -f "$TEST_YML" ]
	grep -qE '^concurrency:' "$TEST_YML"
	grep -qE 'cancel-in-progress:[[:space:]]*true' "$TEST_YML"
}

@test "BUG-028 — bats step bounds individual tests (BATS_TEST_TIMEOUT)" {
	[ -f "$TEST_YML" ]
	grep -qE 'BATS_TEST_TIMEOUT:[[:space:]]*[0-9]+' "$TEST_YML"
}
