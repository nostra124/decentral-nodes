#!/usr/bin/env bats
#
# Unit tests for the `usermin-node` command.
#
# usermin-node installs and operates Usermin
# (https://www.webmin.com/usermin.html), Webmin's per-user sibling web
# interface. Tier 3 self-hosting node, storj-node/forgejo-node/webmin-node
# dispatcher style: a thin bin/ dispatcher routing to
# libexec/usermin-node/<verb>, no shared library, and no calls to sibling
# commands (the FEAT-195 dependency boundary).

setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	USERMIN="$REPO/bin/usermin-node"
	export SELF_LIBEXEC="$REPO/libexec"
	UROOT="$BATS_TEST_TMPDIR"
	export HOME="$UROOT/home"; mkdir -p "$HOME"
	export PATH="$UROOT/stub:$PATH"; mkdir -p "$UROOT/stub"
}

# ---------------------------------------------------------------------------
# Dispatcher contract
# ---------------------------------------------------------------------------

@test "usermin-node version equals the package VERSION" {
	run "$USERMIN" version
	[ "$status" -eq 0 ]
	[ "$output" = "$(cat "$REPO/VERSION")" ]
}

@test "usermin-node help lists the daemon surface + web UI port 20000" {
	run "$USERMIN" help
	[ "$status" -eq 0 ]
	[[ "$output" == *daemon* ]]
	[[ "$output" == *install* ]]
	[[ "$output" == *20000* ]]
}

@test "usermin-node with no args prints usage and exits non-zero" {
	run "$USERMIN"
	[ "$status" -ne 0 ]
	[[ "$output" == *usermin-node* ]]
}

@test "usermin-node <unknown> exits non-zero naming the verb" {
	run "$USERMIN" frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *frobnicate* ]]
}

# ---------------------------------------------------------------------------
# daemon verb (no host side effects: help + arg validation only)
# ---------------------------------------------------------------------------

@test "daemon help lists the lifecycle + setup subcommands" {
	run "$USERMIN" daemon help
	[ "$status" -ne 0 ]   # usage() exits non-zero
	[[ "$output" == *install* ]]
	[[ "$output" == *enable* ]]
	[[ "$output" == *status* ]]
}

@test "daemon install rejects an unknown --from before doing any work" {
	run "$USERMIN" daemon install --from frobpkg
	[ "$status" -ne 0 ]
	[[ "$output" == *frobpkg* || "$output" == *macOS* || "$output" == *"not packaged"* ]]
}

@test "daemon status reports down when usermin is not running" {
	run "$USERMIN" daemon status
	[ "$status" -eq 0 ]
	[[ "$output" == *down* || "$output" == *running* ]]
}

# ---------------------------------------------------------------------------
# FEAT-195 dependency boundary — no forbidden sibling calls.
# ---------------------------------------------------------------------------

# returns 0 if a violation is found, 1 if clean
_scan_forbidden() {
	local f="$1" word
	for word in cache data hosts scripts task; do
		grep -qE "^[[:space:]]*${word}[[:space:]]" "$f" && return 0
		grep -qE "\\\$\\([[:space:]]*${word}[[:space:]]" "$f" && return 0
	done
	grep -qE "^[[:space:]]*bitcoin[[:space:]]" "$f" && return 0
	grep -qE "^[[:space:]]*lightning[[:space:]]" "$f" && return 0
	return 1
}

@test "bin/usermin-node + libexec/usermin-node/* call no forbidden siblings" {
	run _scan_forbidden "$REPO/bin/usermin-node"
	[ "$status" -eq 1 ]
	local f
	while IFS= read -r f; do
		run _scan_forbidden "$f"
		[ "$status" -eq 1 ] || { echo "forbidden sibling call in $f"; return 1; }
	done < <(find "$REPO/libexec/usermin-node" -type f 2>/dev/null)
}

# ---------------------------------------------------------------------------
# Packaging registration
# ---------------------------------------------------------------------------

@test "PACKAGES in Makefile.in includes usermin-node" {
	grep -qE '^PACKAGES = .*usermin-node' "$REPO/Makefile.in"
}

@test ".rpk/package COMMANDS includes usermin-node" {
	grep -qE '^COMMANDS=.*usermin-node' "$REPO/.rpk/package"
}

@test "make install stages the usermin-node tree" {
	command -v stow >/dev/null 2>&1 || skip "stow not installed"
	local prefix="$UROOT/prefix"; mkdir -p "$prefix"
	( cd "$REPO" && ./configure --prefix="$prefix" >/dev/null 2>&1 && make install >/dev/null 2>&1 )
	[ -f "$REPO/build/decentral-nodes/bin/usermin-node" ]
	[ -d "$REPO/build/decentral-nodes/libexec/usermin-node" ]
	[ -x "$prefix/bin/usermin-node" ]
	[ -f "$prefix/share/usermin-node/version" ]
	( cd "$REPO" && make uninstall >/dev/null 2>&1; rm -rf build Makefile )
}
