#!/usr/bin/env bats
#
# Unit tests for the `forgejo-node` command.
#
# forgejo-node installs and operates a Forgejo Git forge (https://forgejo.org/)
# and, crucially, sets up Forgejo Actions runners for specific platforms
# (docker / lxc / host). It is a Tier 3 self-hosting node and follows the
# storj-node / tor-node dispatcher style: a thin bin/ dispatcher routing to
# libexec/forgejo-node/<verb>, with no shared crypto/helper library and no
# calls to sibling commands (the FEAT-195 dependency boundary).

setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	FORGEJO="$REPO/bin/forgejo-node"
	export SELF_LIBEXEC="$REPO/libexec"
	FROOT="$BATS_TEST_TMPDIR"
	export HOME="$FROOT/home"; mkdir -p "$HOME"
	# Keep the lifecycle verbs from ever touching the host even if a test
	# regresses: an empty PATH-prepended stub dir is available to override.
	export PATH="$FROOT/stub:$PATH"; mkdir -p "$FROOT/stub"
}

# ---------------------------------------------------------------------------
# Dispatcher contract
# ---------------------------------------------------------------------------

@test "forgejo-node version equals the package VERSION" {
	run "$FORGEJO" version
	[ "$status" -eq 0 ]
	[ "$output" = "$(cat "$REPO/VERSION")" ]
}

@test "forgejo-node help lists the daemon + runner surfaces" {
	run "$FORGEJO" help
	[ "$status" -eq 0 ]
	[[ "$output" == *daemon* ]]
	[[ "$output" == *runner* ]]
	[[ "$output" == *platforms* ]]
}

@test "forgejo-node with no args prints usage and exits non-zero" {
	run "$FORGEJO"
	[ "$status" -ne 0 ]
	[[ "$output" == *forgejo-node* ]]
}

@test "forgejo-node <unknown> exits non-zero naming the verb" {
	run "$FORGEJO" frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *frobnicate* ]]
}

# ---------------------------------------------------------------------------
# runner: platform presets (the headline feature)
# ---------------------------------------------------------------------------

@test "runner platforms lists docker, lxc and host presets" {
	run "$FORGEJO" runner platforms
	[ "$status" -eq 0 ]
	[[ "$output" == *docker* ]]
	[[ "$output" == *lxc* ]]
	[[ "$output" == *host* ]]
}

@test "runner platforms emits the runner label syntax (schema://image)" {
	run "$FORGEJO" runner platforms
	[ "$status" -eq 0 ]
	[[ "$output" == *"docker:docker://"* ]]
	[[ "$output" == *"lxc:lxc://"* ]]
	[[ "$output" == *"host:host"* ]]
}

@test "runner platforms honours FORGEJO_RUNNER_IMAGE override" {
	FORGEJO_RUNNER_IMAGE="alpine:3.20" run "$FORGEJO" runner platforms
	[ "$status" -eq 0 ]
	[[ "$output" == *"docker://alpine:3.20"* ]]
}

@test "runner platforms lists macos and windows (host-backend) presets" {
	run "$FORGEJO" runner platforms
	[ "$status" -eq 0 ]
	[[ "$output" == *macos* ]]
	[[ "$output" == *windows* ]]
	[[ "$output" == *"macos:host"* ]]
	[[ "$output" == *"windows:host"* ]]
}

@test "runner register accepts the macos platform preset" {
	# Missing binary aborts after preset resolution — proving 'macos' is
	# a known platform (an unknown one would be rejected earlier).
	run "$FORGEJO" runner register --instance http://127.0.0.1:3000 \
		--token T --platform macos
	[ "$status" -ne 0 ]
	[[ "$output" != *"unknown platform"* ]]
}

@test "runner register accepts the windows platform preset" {
	run "$FORGEJO" runner register --instance http://127.0.0.1:3000 \
		--token T --platform windows
	[ "$status" -ne 0 ]
	[[ "$output" != *"unknown platform"* ]]
}

# ---------------------------------------------------------------------------
# runner register: argument validation (no network, no side effects)
# ---------------------------------------------------------------------------

@test "runner register requires --instance" {
	run "$FORGEJO" runner register --token T --platform docker
	[ "$status" -ne 0 ]
	[[ "$output" == *instance* ]]
}

@test "runner register requires --token" {
	run "$FORGEJO" runner register --instance http://127.0.0.1:3000
	[ "$status" -ne 0 ]
	[[ "$output" == *token* ]]
}

@test "runner register rejects an unknown platform before doing any work" {
	run "$FORGEJO" runner register --instance http://127.0.0.1:3000 \
		--token T --platform frobnplatform
	[ "$status" -ne 0 ]
	[[ "$output" == *frobnplatform* ]]
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
	# bare sibling commands (a trailing space rules out e.g. bitcoin-cli)
	grep -qE "^[[:space:]]*bitcoin[[:space:]]" "$f" && return 0
	grep -qE "^[[:space:]]*lightning[[:space:]]" "$f" && return 0
	return 1
}

@test "bin/forgejo-node + libexec/forgejo-node/* call no forbidden siblings" {
	run _scan_forbidden "$REPO/bin/forgejo-node"
	[ "$status" -eq 1 ]
	local f
	while IFS= read -r f; do
		run _scan_forbidden "$f"
		[ "$status" -eq 1 ] || { echo "forbidden sibling call in $f"; return 1; }
	done < <(find "$REPO/libexec/forgejo-node" -type f 2>/dev/null)
}

@test "the forbidden-sibling scanner catches a planted violation" {
	local planted="$FROOT/planted"
	printf '#!/usr/bin/env bash\ncache list\n' > "$planted"
	run _scan_forbidden "$planted"
	[ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Packaging registration
# ---------------------------------------------------------------------------

@test "PACKAGES in Makefile.in includes forgejo-node" {
	grep -qE '^PACKAGES = .*forgejo-node' "$REPO/Makefile.in"
}

@test ".rpk/package COMMANDS includes forgejo-node" {
	grep -qE '^COMMANDS=.*forgejo-node' "$REPO/.rpk/package"
}

@test "make install stages the forgejo-node tree" {
	command -v stow >/dev/null 2>&1 || skip "stow not installed"
	local prefix="$FROOT/prefix"; mkdir -p "$prefix"
	( cd "$REPO" && ./configure --prefix="$prefix" >/dev/null 2>&1 && make install >/dev/null 2>&1 )
	[ -f "$REPO/build/decentral-nodes/bin/forgejo-node" ]
	[ -d "$REPO/build/decentral-nodes/libexec/forgejo-node" ]
	[ -x "$prefix/bin/forgejo-node" ]
	[ -f "$prefix/share/forgejo-node/version" ]
	( cd "$REPO" && make uninstall >/dev/null 2>&1; rm -rf build Makefile )
}
