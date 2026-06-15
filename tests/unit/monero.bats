#!/usr/bin/env bats
#
# Unit tests for the `monero` command (3.2.0 milestone):
#   FEAT-299 multi-command packaging + dependency boundary (this file's
#            skeleton contract; FEAT-300/301/302 extend it with the
#            install / daemon / config verbs).
#
# monero is the fourth top-level command shipped by the one `bitcoin` rpk
# package (after bitcoin / lightning / fulcrum). The contract mirrors the
# fulcrum FEAT-055 acceptance tests one-for-one.

setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	MONERO="$REPO/bin/monero"
	BITCOIN="$REPO/bin/bitcoin"
	export SELF_LIBEXEC="$REPO/libexec"
	MROOT="$BATS_TEST_TMPDIR"
	export HOME="$MROOT/home"; mkdir -p "$HOME"
}

# ===========================================================================
# FEAT-299 — multi-command packaging + dependency boundary
# ===========================================================================

@test "FEAT-299 AC1: monero version equals bitcoin version (one package)" {
	run "$MONERO" version
	[ "$status" -eq 0 ]
	[ "$output" = "$(cat "$REPO/VERSION")" ]
	[ "$output" = "$("$BITCOIN" version)" ]
}

@test "FEAT-299 AC1: monero help lists the generic + node verbs" {
	run "$MONERO" help
	[ "$status" -eq 0 ] || [ -n "$output" ]
	[[ "$output" == *version* ]]
	[[ "$output" == *modules* ]]
	[[ "$output" == *install* ]]
	[[ "$output" == *daemon* ]]
	[[ "$output" == *config* ]]
}

@test "FEAT-299 AC1: monero modules exits 0 (lists libexec verbs, empty ok)" {
	run "$MONERO" modules
	[ "$status" -eq 0 ]
}

@test "FEAT-299 AC2: monero <unknown> exits non-zero naming the verb" {
	run "$MONERO" frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *frobnicate* ]]
	[[ "$output" == *"not a monero command"* ]]
}

@test "FEAT-299 AC3: .rpk/identity is unchanged (bitcoin); no second package" {
	[ "$(cat "$REPO/.rpk/identity")" = bitcoin ]
	grep -qE '^COMMANDS=.*monero' "$REPO/.rpk/package"
}

@test "FEAT-299 AC4: make install stages the monero tree alongside the others" {
	command -v stow >/dev/null 2>&1 || skip "stow not installed"
	local prefix="$MROOT/prefix"; mkdir -p "$prefix"
	( cd "$REPO" && ./configure --prefix="$prefix" >/dev/null 2>&1 && make install >/dev/null 2>&1 )
	# Staged build tree (stow source) mirrors $PREFIX *relative* (BUG-038).
	[ -f "$REPO/build/bitcoin/bin/monero" ]
	[ -d "$REPO/build/bitcoin/libexec/monero" ]
	# …and stow installs the dispatcher directly onto PATH under $PREFIX.
	[ -x "$prefix/bin/monero" ]
	[ -f "$prefix/share/monero/version" ]
	( cd "$REPO" && make uninstall >/dev/null 2>&1; rm -rf build Makefile )
}

@test "FEAT-299 AC4: lint covers monero (PACKAGES + bin/* shellcheck)" {
	grep -qE '^PACKAGES = .*monero' "$REPO/Makefile.in"
	grep -qE 'shellcheck .* bin/\*' "$REPO/Makefile.in"
}

# Forbidden-sibling scanner mirroring the two FEAT-195 / fulcrum FEAT-055 tests.
_scan_forbidden() {  # returns 0 if a violation is found, 1 if clean
	local f="$1" word
	for word in cache data hosts scripts task; do
		grep -qE "^[[:space:]]*${word}[[:space:]]" "$f" && return 0
		grep -qE "\\\$\\([[:space:]]*${word}[[:space:]]" "$f" && return 0
	done
	# bare `bitcoin` command (not bitcoin-cli / bitcoind, which have a
	# non-space char after 'bitcoin')
	grep -qE "^[[:space:]]*bitcoin[[:space:]]" "$f" && return 0
	return 1
}

@test "FEAT-299 AC5: bin/monero + libexec/monero/* call no forbidden siblings" {
	run _scan_forbidden "$REPO/bin/monero"
	[ "$status" -eq 1 ]
	local f
	# libexec/monero/ may be empty in the skeleton; find handles that.
	while IFS= read -r f; do
		run _scan_forbidden "$f"
		[ "$status" -eq 1 ] || { echo "forbidden call in $f"; return 1; }
	done < <(find "$REPO/libexec/monero" -type f 2>/dev/null)
}

@test "FEAT-299 AC5: the scanner catches a planted forbidden sibling call" {
	local planted="$MROOT/planted"
	printf '#!/usr/bin/env bash\ncache list\n' > "$planted"
	run _scan_forbidden "$planted"
	[ "$status" -eq 0 ]
}
