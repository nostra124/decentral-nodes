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

# ===========================================================================
# FEAT-300 — verified release-tarball install
#
# Build a real .tar.bz2 (real SHA256) and serve it + a clearsigned hashes
# file + the signing key through PATH-stubbed curl; uname forces the arch;
# gpg is stubbed (import show-only emits the pinned fingerprint, --verify
# honours $MONERO_TEST_GPG_BAD). The SHA256 leg is genuinely exercised.
# ===========================================================================

PINNED_FPR=81AC591FE9C4B65C5806AFC3F0AF4D462A0BDF92

# _mk_release_fixture <arch-machine> — set up stubs + seams for one install.
# Echoes nothing; exports MONERO_* seams and prepends the stub dir to PATH.
_mk_release_fixture() {
	local machine="${1:-x86_64}"
	local td="$MROOT/rel"; mkdir -p "$td/stub" "$td/pfx/bin" "$td/pkg"
	export MONERO_VERSION=v0.18.3.4
	local asset="monero-linux-x64-$MONERO_VERSION"
	[ "$machine" = aarch64 ] && asset="monero-linux-armv8-$MONERO_VERSION"
	# A real release tree -> real tarball -> real sha256.
	mkdir -p "$td/pkg/$asset"
	printf '#!/bin/sh\necho "Monero '\''Fluorine Fermi'\'' (%s-release)"\n' "$MONERO_VERSION" \
		> "$td/pkg/$asset/monerod"
	printf '#!/bin/sh\n:\n' > "$td/pkg/$asset/monero-wallet-rpc"
	printf '#!/bin/sh\n:\n' > "$td/pkg/$asset/monero-wallet-cli"
	chmod +x "$td/pkg/$asset/"*
	( cd "$td/pkg" && tar -cjf "$td/$asset.tar.bz2" "$asset" )
	local sum
	if command -v sha256sum >/dev/null 2>&1; then
		sum="$(sha256sum "$td/$asset.tar.bz2" | awk '{print $1}')"
	else
		sum="$(shasum -a 256 "$td/$asset.tar.bz2" | awk '{print $1}')"
	fi
	cat > "$td/hashes.txt" <<-EOF
		-----BEGIN PGP SIGNED MESSAGE-----
		Hash: SHA256

		$sum  $asset.tar.bz2
		-----BEGIN PGP SIGNATURE-----
		(stub signature)
		-----END PGP SIGNATURE-----
	EOF
	printf 'STUB KEY\n' > "$td/key.asc"
	# Stubs.
	cat > "$td/stub/uname" <<-STUB
		#!/usr/bin/env bash
		case "\$1" in -s) echo Linux ;; -m) echo $machine ;; *) echo Linux ;; esac
	STUB
	cat > "$td/stub/curl" <<-STUB
		#!/usr/bin/env bash
		out=""; url=""
		while [ \$# -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2 ;; -*) shift ;; *) url="\$1"; shift ;; esac; done
		case "\$url" in
		  *binaryfate.asc|*key*) cp "$td/key.asc" "\$out" ;;
		  *hashes.txt)           cp "$td/hashes.txt" "\$out" ;;
		  *.tar.bz2)             cp "$td/\$(basename "\$url")" "\$out" 2>/dev/null || exit 22 ;;
		  *) exit 22 ;;
		esac
	STUB
	cat > "$td/stub/gpg" <<-STUB
		#!/usr/bin/env bash
		args="\$*"
		case "\$args" in
		  *show-only*)
		    if [ -n "\$MONERO_TEST_KEY_BAD" ]; then
		      echo "fpr:::::::::DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF:"
		    else
		      echo "fpr:::::::::$PINNED_FPR:"
		    fi ;;
		  *--verify*) [ -n "\$MONERO_TEST_GPG_BAD" ] && exit 1; exit 0 ;;
		  *) exit 0 ;;
		esac
	STUB
	chmod +x "$td/stub/"*
	export PATH="$td/stub:$PATH"
	export MONERO_KEYCACHE="$td/keycache.asc"
	export MONERO_KEY_URL="http://stub/binaryfate.asc"
	export MONERO_HASHES_URL="http://stub/hashes.txt"
	export MONERO_RELEASE_BASEURL="http://stub"
	REL_PREFIX="$td/pfx/bin"
	REL_ASSET="$asset"
}

@test "FEAT-300 AC1: install downloads, GPG-verifies, SHA256-checks, and stages monerod" {
	_mk_release_fixture x86_64
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -eq 0 ]
	[ -x "$REL_PREFIX/monerod" ]
	[ -x "$REL_PREFIX/monero-wallet-rpc" ]
	[ -x "$REL_PREFIX/monero-wallet-cli" ]
	[[ "$output" == *"sha256 verified"* ]]
	[[ "$output" == *"signature verified"* ]]
	"$REL_PREFIX/monerod" --version | grep -q "$MONERO_VERSION"
}

@test "FEAT-300 AC2: a tampered tarball (bad SHA256) aborts and stages nothing" {
	_mk_release_fixture x86_64
	# Corrupt the served tarball AFTER the hashes were computed.
	printf 'tampered' >> "$MROOT/rel/$REL_ASSET.tar.bz2"
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -ne 0 ]
	[[ "$output" == *"SHA256 mismatch"* ]]
	[ ! -e "$REL_PREFIX/monerod" ]
}

@test "FEAT-300 AC2: a bad GPG signature aborts and stages nothing" {
	_mk_release_fixture x86_64
	export MONERO_TEST_GPG_BAD=1
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -ne 0 ]
	[[ "$output" == *"did NOT verify"* ]]
	[ ! -e "$REL_PREFIX/monerod" ]
}

@test "FEAT-300 AC2: a key whose fingerprint != the pinned one is refused" {
	_mk_release_fixture x86_64
	export MONERO_TEST_KEY_BAD=1
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -ne 0 ]
	[[ "$output" == *"fingerprint mismatch"* ]]
	[ ! -e "$REL_PREFIX/monerod" ]
}

@test "FEAT-300 AC3: arch detection picks the armv8 asset on aarch64" {
	_mk_release_fixture aarch64
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -eq 0 ]
	[[ "$output" == *"monero-linux-armv8"* ]]
	[ -x "$REL_PREFIX/monerod" ]
}

@test "FEAT-300 AC4: re-running is idempotent; --force re-installs" {
	_mk_release_fixture x86_64
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -eq 0 ]
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -eq 0 ]
	[[ "$output" == *"already installed"* ]]
	run "$MONERO" install --prefix "$REL_PREFIX" --force
	[ "$status" -eq 0 ]
	[[ "$output" == *"sha256 verified"* ]]
}

@test "FEAT-300 AC: install help lists release, version, prefix, force" {
	run "$MONERO" install --help
	[ "$status" -eq 0 ]
	for s in release version prefix force; do
		[[ "$output" == *"$s"* ]] || { echo "missing: $s"; return 1; }
	done
}
