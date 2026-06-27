#!/usr/bin/env bash
# Shared dispatcher contract for the *-node commands (FEAT-314).
#
# `load lib/node_contract` in a per-node suite, call node_contract_setup in
# setup(), then assert the contract with the helpers below. Keeps the seven
# storj/rich-style nodes' suites thin and uniform.

node_contract_setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export SELF_LIBEXEC="$REPO/libexec"
	export HOME="${BATS_TEST_TMPDIR:-/tmp}/home"; mkdir -p "$HOME"
	# Empty stub dir first on PATH so a regressing lifecycle verb can't
	# touch the host.
	export PATH="${BATS_TEST_TMPDIR:-/tmp}/stub:$PATH"; mkdir -p "${BATS_TEST_TMPDIR:-/tmp}/stub"
}

# `<node> help` resolves and prints something (storj-style via a libexec
# help verb; rich-style via command:help). Universal across all nodes.
nc_assert_help() {
	run "$REPO/bin/$1" help
	[ "$status" -eq 0 ] || { echo "$1 help exited $status"; return 1; }
	[ -n "$output" ] || { echo "$1 help printed nothing"; return 1; }
}

# An unknown verb fails and names the offending token (storj: "unknown
# verb: X"; rich: "unknown command X").
nc_assert_unknown_verb() {
	run "$REPO/bin/$1" zzqq-not-a-verb
	[ "$status" -ne 0 ] || { echo "$1 accepted a bogus verb"; return 1; }
	[[ "$output" == *zzqq-not-a-verb* ]] || { echo "$1 didn't name the bad verb: $output"; return 1; }
}

# Registered for install in both Makefile PACKAGES and .rpk COMMANDS.
nc_assert_registered() {
	local node="$1" pkgs cmds
	pkgs=" $(grep -m1 '^PACKAGES = ' "$REPO/Makefile.in" | sed 's/^PACKAGES = //') "
	cmds=" $(grep -m1 '^COMMANDS=' "$REPO/.rpk/package" | sed 's/^COMMANDS=//; s/\"//g') "
	[[ "$pkgs" == *" $node "* ]] || { echo "$node not in PACKAGES"; return 1; }
	[[ "$cmds" == *" $node "* ]] || { echo "$node not in COMMANDS"; return 1; }
}

# Version verb (rich-style nodes only) prints the package VERSION.
nc_assert_version() {
	run "$REPO/bin/$1" version
	[ "$status" -eq 0 ] || { echo "$1 version exited $status"; return 1; }
	[ "$output" = "$(cat "$REPO/VERSION")" ] || { echo "$1 version=$output"; return 1; }
}

# FEAT-195 dependency boundary: returns 0 if a forbidden sibling call is
# present in $1, 1 if clean.
_nc_scan_forbidden() {
	local f="$1" word
	for word in cache data hosts scripts task; do
		grep -qE "^[[:space:]]*${word}[[:space:]]" "$f" && return 0
		grep -qE "\\\$\\([[:space:]]*${word}[[:space:]]" "$f" && return 0
	done
	grep -qE "^[[:space:]]*bitcoin[[:space:]]" "$f" && return 0
	grep -qE "^[[:space:]]*lightning[[:space:]]" "$f" && return 0
	return 1
}

nc_assert_no_forbidden_siblings() {
	local node="$1" f
	_nc_scan_forbidden "$REPO/bin/$node" && { echo "forbidden sibling in bin/$node"; return 1; }
	while IFS= read -r f; do
		_nc_scan_forbidden "$f" && { echo "forbidden sibling in $f"; return 1; }
	done < <(find "$REPO/libexec/$node" -type f 2>/dev/null)
	return 0
}
