#!/usr/bin/env bats
#
# Unit tests for bin/bitcoin — the BIP-173/350 + bip32/39/49/84
# wallet frontend (FEAT-006..019). Pinned to semver per FEAT-005.
#
# Coverage scope: the dispatcher surface (version / help / modules)
# plus a bug-replicating test for BUG-008. The cryptographic
# primitives have separate test-vector coverage in
# tests/vectors/bip-*.t (gated on FEAT-006's bitcoin.sh module
# being sourceable).

setup() {
	BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
	HOME="$(mktemp -d "$BATS_TMPDIR/home.XXXXXX")"
	unset XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_SHARE_HOME
	unset XDG_SOURCE_HOME XDG_BACKUP_HOME XDG_RUNTIME_DIR
	export HOME
	export SELF_QUIET=1
	export BITCOIN_BIN="$BATS_TEST_DIRNAME/../../bin/bitcoin"
	# FEAT-020: pin SELF_LIBEXEC so a system-installed bitcoin
	# at /usr/local/libexec cannot pollute the in-tree test run.
	export SELF_LIBEXEC="$BATS_TEST_DIRNAME/../../libexec"
}

teardown() {
	rm -rf "$HOME"
}

# ---------------------------------------------------------------------------
# Smoke + semver contract (FEAT-005)
# ---------------------------------------------------------------------------

@test "bitcoin binary exists and is executable" {
	[ -x "$BITCOIN_BIN" ]
}

@test "bitcoin version matches VERSION file" {
	# FEAT-020: the bats literal used to pin a specific semver
	# string. Now we read VERSION at test time so a release bump
	# doesn't require editing the test.
	expected="$(cat "$BATS_TEST_DIRNAME/../../VERSION")"
	run "$BITCOIN_BIN" version
	[ "$status" -eq 0 ]
	[ "$output" = "$expected" ]
}

@test "bitcoin help prints usage" {
	run "$BITCOIN_BIN" help
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

@test "bitcoin with no args prints help" {
	run "$BITCOIN_BIN"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

# ---------------------------------------------------------------------------
# Help surface
# ---------------------------------------------------------------------------

@test "help mentions module related commands" {
	run "$BITCOIN_BIN" help
	[ "$status" -eq 0 ]
	[[ "$output" == *"module related commands"* ]]
}

@test "help mentions bip173 (bech32) commands" {
	run "$BITCOIN_BIN" help
	[ "$status" -eq 0 ]
	[[ "$output" == *"bip173"* ]]
	[[ "$output" == *"bech32"* ]]
}

@test "help mentions bip350 (bech32m) commands" {
	run "$BITCOIN_BIN" help
	[ "$status" -eq 0 ]
	[[ "$output" == *"bip350"* ]]
}

@test "help <bech32> describes its purpose" {
	run "$BITCOIN_BIN" help bech32
	[ "$status" -eq 0 ]
	[ -n "$output" ]
	[[ "$output" == *"Bech32"* ]]
}

# ---------------------------------------------------------------------------
# modules — directory listing under $SELF_LIBEXEC/bitcoin/
# ---------------------------------------------------------------------------

@test "modules lists the modules shipped under libexec/bitcoin/" {
	run "$BITCOIN_BIN" modules
	[ "$status" -eq 0 ]
	# FEAT-021: assert all four shipped modules, not just the
	# two from the old smoke test.
	[[ "$output" == *"bip13"* ]]
	[[ "$output" == *"bip32"* ]]
	[[ "$output" == *"bip39"* ]]
	[[ "$output" == *"daemon"* ]]
	[[ "$output" == *"wif"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-021: libexec-dispatch smoke. When the dispatcher receives an
# unknown subcommand it falls back to the help banner. When it receives
# a known libexec plugin name, it exec()s that plugin — the dispatcher
# help is NOT shown.
# ---------------------------------------------------------------------------

@test "bitcoin <unknown> falls back to help" {
	run "$BITCOIN_BIN" __no_such_command__
	[[ "$output" == *"module related commands"* ]]
}

@test "bitcoin dispatches to a libexec plugin (bip13) instead of help" {
	# bip13's exit code is its own business; we only assert that
	# the dispatcher reached the plugin, i.e. did NOT print its
	# own help banner.
	run "$BITCOIN_BIN" bip13
	[[ "$output" != *"module related commands"* ]]
}

# ---------------------------------------------------------------------------
# BIP-173 vector round-trips — fixed in BUG-008 (PR #-).
# Pure-uppercase vectors (e.g. `A12UEL5L`) are rejected by the
# script's case-mixing guard at command:bech32:219 — that's a
# separate edge case, not BUG-008.
# ---------------------------------------------------------------------------

@test "bech32 round-trips a known BIP-173 vector" {
	encoded="$($BITCOIN_BIN bech32 abcdef qpzry9x8gf2tvdw0s3jn54khce6mua7l | tail -n 1)"
	[ "$encoded" = "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw" ]
}

@test "bech32 reproduces the help-doc example" {
	encoded="$($BITCOIN_BIN bech32 this-part-is-readable-by-a-human qpzry | tail -n 1)"
	[ "$encoded" = "this-part-is-readable-by-a-human1qpzrylhvwcq" ]
}

@test "bech32-verify accepts a value that bech32 just produced" {
	encoded="$($BITCOIN_BIN bech32 abcdef qpzry9x8gf2tvdw0s3jn54khce6mua7l | tail -n 1)"
	run "$BITCOIN_BIN" bech32-verify "$encoded"
	[ "$status" -eq 0 ]
}

@test "bech32-verify rejects a tampered checksum" {
	# Flip the last character of a known-good bech32 string.
	run "$BITCOIN_BIN" bech32-verify "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxq"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# BUG-010 regression — bech32-verify-checksum called undefined polymod /
# hrpExpand instead of bech32-polymod / bech32-hrp-expand, so
# command:bech32-decode always exited 8.
# ---------------------------------------------------------------------------

@test "bech32-decode decodes a known BIP-173 vector" {
	run "$BITCOIN_BIN" bech32-decode "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw"
	[ "$status" -eq 0 ]
	[[ "$output" == *"abcdef"* ]]
}

@test "bech32-decode rejects a tampered checksum" {
	run "$BITCOIN_BIN" bech32-decode "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxq"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# BUG-011 regression — command:bech32 case-mixing guard compared the
# lowercased copy against [a-z], so any uppercase letter triggered a
# rejection. BIP-173 only forbids *mixed* case.
# ---------------------------------------------------------------------------

@test "bech32 accepts all-uppercase input (BIP-173 allows)" {
	run "$BITCOIN_BIN" bech32 "ABCDEF" "QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L"
	[ "$status" -eq 0 ]
	# Output is normalised to lowercase per BIP-173.
	[ "$(echo "$output" | tail -n 1)" = "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw" ]
}

@test "bech32 rejects mixed-case input" {
	run "$BITCOIN_BIN" bech32 "aBc" "qpzry"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-021: bech32 boundary conditions. The command must reject inputs
# the BIP-173 spec disallows — over-long HRPs and data with non-charset
# characters — with a non-zero exit.
# ---------------------------------------------------------------------------

@test "bech32 rejects hrp longer than 83 characters" {
	long_hrp="$(printf 'a%.0s' {1..84})"
	run "$BITCOIN_BIN" bech32 "$long_hrp" "qpzry"
	[ "$status" -ne 0 ]
}

@test "bech32 rejects data with non-charset characters" {
	# 'b', 'i', 'o' are excluded from the bech32 charset.
	run "$BITCOIN_BIN" bech32 "test" "biox"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-006: bin/bitcoin is sourceable as a function library so the
# vector .t files can `. bitcoin.sh` without re-running the dispatcher.
# When sourced, the file defines all its functions and returns 0
# without producing output.
# ---------------------------------------------------------------------------

@test "bin/bitcoin is sourceable without side effects" {
	run bash -c "source '$BITCOIN_BIN'; echo SOURCED_OK"
	[ "$status" -eq 0 ]
	[[ "$output" == *"SOURCED_OK"* ]]
	# Sourcing must not have produced the dispatcher's help banner.
	[[ "$output" != *"module related commands"* ]]
}

@test "sourcing bin/bitcoin defines the BIP function library" {
	run bash -c "source '$BITCOIN_BIN'; \
		for f in bitcoinAddress segwitAddress segwit_decode segwit_verify convertbits bip49 bip84 bip85 p2pkh-address p2wpkh; do \
			declare -F \"\$f\" >/dev/null || { echo missing: \$f; exit 1; }; \
		done; echo ALL_DEFINED"
	[ "$status" -eq 0 ]
	[[ "$output" == *"ALL_DEFINED"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-022/023/024/025 meta-tests: structural assertions on the vector
# suite. The .t files themselves run under prove, but the invariants
# below (no literal plans, numbered TAP, deduplicated fixtures, probe
# for missing deps) are properties of the source code that we can check
# from bats without needing the external dependencies.
# ---------------------------------------------------------------------------

@test "FEAT-022 — no .t file uses a literal TAP plan" {
	failed=""
	for f in "$BATS_TEST_DIRNAME"/../../tests/vectors/*.t; do
		if grep -qE '^echo 1\.\.[0-9]+[[:space:]]*$' "$f"; then
			failed="$failed $f"
		fi
	done
	[ -z "$failed" ] || { echo "Files with literal TAP plan:$failed"; false; }
}

@test "FEAT-023 — bip-0085.t emits numbered ok/not-ok lines" {
	f="$BATS_TEST_DIRNAME/../../tests/vectors/bip-0085.t"
	# Every line that emits `ok ...` or `not ok ...` TAP output must
	# include the counter variable $n.
	un_numbered=""
	while IFS= read -r line; do
		[[ "$line" == *'$n'* ]] || un_numbered+="$line"$'\n'
	done < <(grep -nE 'echo[[:space:]]+"(ok|not ok)' "$f" || true)
	[ -z "$un_numbered" ] || { echo "Un-numbered TAP lines:"; printf "%s" "$un_numbered"; false; }
}

@test "FEAT-024 — bech32 vector A12UEL5L appears in exactly one source file" {
	base="$BATS_TEST_DIRNAME/../../tests/vectors"
	count="$(grep -l A12UEL5L "$base"/*.t "$base"/*.sh 2>/dev/null | wc -l)"
	[ "$count" -eq 1 ]
}

@test "FEAT-025 — Makefile.in check-vectors probes for missing external deps" {
	f="$BATS_TEST_DIRNAME/../../Makefile.in"
	grep -q 'missing dependencies:' "$f"
	grep -q 'base58' "$f"
	grep -q 'create-mnemonic' "$f"
}
