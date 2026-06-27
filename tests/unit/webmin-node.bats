#!/usr/bin/env bats
#
# Unit tests for the `webmin-node` command.
#
# webmin-node installs and operates Webmin (https://www.webmin.com/), a
# browser-based system administration UI. Tier 3 self-hosting node,
# storj-node/forgejo-node dispatcher style: a thin bin/ dispatcher
# routing to libexec/webmin-node/<verb>, no shared library, and no calls
# to sibling commands (the FEAT-195 dependency boundary).

setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	WEBMIN="$REPO/bin/webmin-node"
	export SELF_LIBEXEC="$REPO/libexec"
	WROOT="$BATS_TEST_TMPDIR"
	export HOME="$WROOT/home"; mkdir -p "$HOME"
	# An empty PATH-prepended stub dir guards against lifecycle verbs ever
	# touching the host even if a test regresses.
	export PATH="$WROOT/stub:$PATH"; mkdir -p "$WROOT/stub"
}

# ---------------------------------------------------------------------------
# Dispatcher contract
# ---------------------------------------------------------------------------

@test "webmin-node version equals the package VERSION" {
	run "$WEBMIN" version
	[ "$status" -eq 0 ]
	[ "$output" = "$(cat "$REPO/VERSION")" ]
}

@test "webmin-node help lists the daemon surface + web UI port" {
	run "$WEBMIN" help
	[ "$status" -eq 0 ]
	[[ "$output" == *daemon* ]]
	[[ "$output" == *install* ]]
	[[ "$output" == *10000* ]]
}

@test "webmin-node with no args prints usage and exits non-zero" {
	run "$WEBMIN"
	[ "$status" -ne 0 ]
	[[ "$output" == *webmin-node* ]]
}

@test "webmin-node <unknown> exits non-zero naming the verb" {
	run "$WEBMIN" frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *frobnicate* ]]
}

# ---------------------------------------------------------------------------
# daemon verb (no host side effects: help + arg validation only)
# ---------------------------------------------------------------------------

@test "daemon help lists the lifecycle + setup subcommands" {
	run "$WEBMIN" daemon help
	[ "$status" -ne 0 ]   # usage() exits non-zero
	[[ "$output" == *install* ]]
	[[ "$output" == *enable* ]]
	[[ "$output" == *status* ]]
}

@test "daemon install rejects an unknown --from before doing any work" {
	# On Linux this reaches the --from validation; on macOS it is refused
	# earlier with a clear not-supported message. Either way: non-zero and
	# no package manager is invoked (the stub PATH has none).
	run "$WEBMIN" daemon install --from frobpkg
	[ "$status" -ne 0 ]
	[[ "$output" == *frobpkg* || "$output" == *macOS* || "$output" == *"not packaged"* ]]
}

@test "daemon status reports down when webmin is not running" {
	# pgrep finds nothing under the stubbed PATH/HOME; status must say down.
	run "$WEBMIN" daemon status
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

@test "bin/webmin-node + libexec/webmin-node/* call no forbidden siblings" {
	run _scan_forbidden "$REPO/bin/webmin-node"
	[ "$status" -eq 1 ]
	local f
	while IFS= read -r f; do
		run _scan_forbidden "$f"
		[ "$status" -eq 1 ] || { echo "forbidden sibling call in $f"; return 1; }
	done < <(find "$REPO/libexec/webmin-node" -type f 2>/dev/null)
}

# ---------------------------------------------------------------------------
# Packaging registration
# ---------------------------------------------------------------------------

@test "PACKAGES in Makefile.in includes webmin-node" {
	grep -qE '^PACKAGES = .*webmin-node' "$REPO/Makefile.in"
}

@test ".rpk/package COMMANDS includes webmin-node" {
	grep -qE '^COMMANDS=.*webmin-node' "$REPO/.rpk/package"
}

@test "make install stages the webmin-node tree" {
	command -v stow >/dev/null 2>&1 || skip "stow not installed"
	local prefix="$WROOT/prefix"; mkdir -p "$prefix"
	( cd "$REPO" && ./configure --prefix="$prefix" >/dev/null 2>&1 && make install >/dev/null 2>&1 )
	[ -f "$REPO/build/decentral-nodes/bin/webmin-node" ]
	[ -d "$REPO/build/decentral-nodes/libexec/webmin-node" ]
	[ -x "$prefix/bin/webmin-node" ]
	[ -f "$prefix/share/webmin-node/version" ]
	( cd "$REPO" && make uninstall >/dev/null 2>&1; rm -rf build Makefile )
}
