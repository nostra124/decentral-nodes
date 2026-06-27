#!/usr/bin/env bats
#
# bitcoin unit tests — part 1 of 5 (FEAT-053 split of tests/unit/bitcoin.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/bitcoin.bash.

bats_require_minimum_version 1.5.0
load lib/bitcoin


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

@test "BUG-029 — newest .rpk/versions entry maps to a commit whose VERSION matches its label" {
	# BUG-029: the 2.2.0 ledger line recorded its parent merge
	# (3baeebc, VERSION=2.1.0) instead of the bump commit (f70209c,
	# VERSION=2.2.0). `rpk update` installs `command:versions | tail -1`
	# and resolves the SHA via `command:commit`, so a wrong SHA makes
	# `rpk install bitcoin:<latest>` package the wrong tree — the binary
	# then self-reports a stale version. Mirror rpk's own selection so
	# this guards exactly what an install would package.
	repo="$BATS_TEST_DIRNAME/../.."
	ledger="$repo/.rpk/versions"
	# command:versions → grep -v '^#' | cut -f1 | sort -u -V ; update picks tail -1
	label="$(grep -v '^#' "$ledger" | cut -f1 | grep -vE '^[[:space:]]*$' \
	         | sort -u -V | tail -1)"
	[ -n "$label" ]
	# command:commit → first exact label match, second (tab) field
	sha="$(awk -F'\t' -v v="$label" '$1==v{print $2; exit}' "$ledger")"
	[ -n "$sha" ]
	[ "$sha" != "TBD" ]
	# The recorded commit must exist in history and its VERSION must
	# equal the label (CI checks out fetch-depth:0 so the object is present).
	run git -C "$repo" show "$sha:VERSION"
	[ "$status" -eq 0 ]
	[ "$(printf '%s' "$output" | tr -d '[:space:]')" = "$label" ]
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
	# BUG-018 regrouped the flat "module related commands" section into
	# workflow sections; the BIP plugins now sit under "blockchain
	# primitives".
	[[ "$output" == *"blockchain primitives"* ]]
}

@test "help mentions bip173 (bech32) commands" {
	run "$BITCOIN_BIN" help
	[ "$status" -eq 0 ]
	[[ "$output" == *"bip173"* ]]
	# BUG-018: the help describes bip173 as "Bech32 segwit address …".
	[[ "$output" == *"Bech32"* ]]
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
# modules — directory listing under $SELF_LIBEXEC/bitcoin-node/
# ---------------------------------------------------------------------------

@test "modules lists the modules shipped under libexec/bitcoin-node/" {
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
	# BUG-018 reworked the banner; assert the usage line it always emits.
	[[ "$output" == *"usage: bitcoin"* ]]
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
	encoded="$($BITCOIN_BIN bip173 encode abcdef qpzry9x8gf2tvdw0s3jn54khce6mua7l | tail -n 1)"
	[ "$encoded" = "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw" ]
}

@test "bech32 reproduces the help-doc example" {
	encoded="$($BITCOIN_BIN bip173 encode this-part-is-readable-by-a-human qpzry | tail -n 1)"
	[ "$encoded" = "this-part-is-readable-by-a-human1qpzrylhvwcq" ]
}

@test "bech32-verify accepts a value that bech32 just produced" {
	encoded="$($BITCOIN_BIN bip173 encode abcdef qpzry9x8gf2tvdw0s3jn54khce6mua7l | tail -n 1)"
	run "$BITCOIN_BIN" bip173 verify "$encoded"
	[ "$status" -eq 0 ]
}

@test "bech32-verify rejects a tampered checksum" {
	# Flip the last character of a known-good bech32 string.
	run "$BITCOIN_BIN" bip173 verify "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxq"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# BUG-010 regression — bech32-verify-checksum called undefined polymod /
# hrpExpand instead of bech32-polymod / bech32-hrp-expand, so
# command:bech32-decode always exited 8.
# ---------------------------------------------------------------------------

@test "bech32-decode decodes a known BIP-173 vector" {
	run "$BITCOIN_BIN" bip173 decode "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw"
	[ "$status" -eq 0 ]
	[[ "$output" == *"abcdef"* ]]
}

@test "bech32-decode rejects a tampered checksum" {
	run "$BITCOIN_BIN" bip173 decode "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxq"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# BUG-011 regression — command:bech32 case-mixing guard compared the
# lowercased copy against [a-z], so any uppercase letter triggered a
# rejection. BIP-173 only forbids *mixed* case.
# ---------------------------------------------------------------------------

@test "bech32 accepts all-uppercase input (BIP-173 allows)" {
	run "$BITCOIN_BIN" bip173 encode "ABCDEF" "QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L"
	[ "$status" -eq 0 ]
	# Output is normalised to lowercase per BIP-173.
	[ "$(echo "$output" | tail -n 1)" = "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw" ]
}

@test "bech32 rejects mixed-case input" {
	run "$BITCOIN_BIN" bip173 encode "aBc" "qpzry"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-021: bech32 boundary conditions. The command must reject inputs
# the BIP-173 spec disallows — over-long HRPs and data with non-charset
# characters — with a non-zero exit.
# ---------------------------------------------------------------------------

@test "bech32 rejects hrp longer than 83 characters" {
	long_hrp="$(printf 'a%.0s' {1..84})"
	run "$BITCOIN_BIN" bip173 encode "$long_hrp" "qpzry"
	[ "$status" -ne 0 ]
}

@test "bech32 rejects data with non-charset characters" {
	# 'b', 'i', 'o' are excluded from the bech32 charset.
	run "$BITCOIN_BIN" bip173 encode "test" "biox"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-006: bin/bitcoin-node is sourceable as a function library so the
# vector .t files can `. bitcoin.sh` without re-running the dispatcher.
# When sourced, the file defines all its functions and returns 0
# without producing output.
# ---------------------------------------------------------------------------

@test "bin/bitcoin-node is sourceable without side effects" {
	run bash -c "source '$BITCOIN_BIN'; echo SOURCED_OK"
	[ "$status" -eq 0 ]
	[[ "$output" == *"SOURCED_OK"* ]]
	# Sourcing must not have produced the dispatcher's help banner.
	[[ "$output" != *"module related commands"* ]]
}

@test "sourcing bin/bitcoin-node defines the BIP function library" {
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

# ---------------------------------------------------------------------------
# FEAT-017 — vendored BIPs + citation template in help output.
# ---------------------------------------------------------------------------

@test "FEAT-017 — vendored BIPs exist for implemented standards" {
	bips="$BATS_TEST_DIRNAME/../../share/doc/bitcoin/bips"
	for n in 0013 0032 0039 0173 0350; do
		[ -s "$bips/bip-$n.mediawiki" ] || {
			echo "missing or empty: bip-$n.mediawiki"; false
		}
	done
	[ -f "$bips/UPSTREAM.txt" ]
	grep -qE '^commit: +[0-9a-f]{40}$' "$bips/UPSTREAM.txt"
}

@test "FEAT-017 — bitcoin help bech32 cites BIP-173 with upstream URL and local path" {
	run "$BITCOIN_BIN" help bech32
	[ "$status" -eq 0 ]
	[[ "$output" == *"BIP-173"* ]]
	[[ "$output" == *"https://github.com/bitcoin/bips"* ]]
	[[ "$output" == *"local:"* ]]
	[[ "$output" == *"bip-0173.mediawiki"* ]]
}

@test "FEAT-017 — bitcoin help bech32 cites BIP-350 (bech32m)" {
	run "$BITCOIN_BIN" help bech32
	[ "$status" -eq 0 ]
	[[ "$output" == *"BIP-350"* ]]
	[[ "$output" == *"bip-0350.mediawiki"* ]]
}

@test "FEAT-010 — wallet new creates a git repo under XDG_DATA_HOME" {
	setup_wallet_env
	run "$BITCOIN_BIN" wallet new alice
	[ "$status" -eq 0 ]
	[ -d "$XDG_DATA_HOME/bitcoin/wallets/alice/.git" ]
	[ -f "$XDG_DATA_HOME/bitcoin/wallets/alice/config" ]
}

@test "FEAT-010 — wallet new stores the seed via secret, not in the repo" {
	setup_wallet_env
	run "$BITCOIN_BIN" wallet new alice
	[ "$status" -eq 0 ]
	# The seed was written to the secret store…
	[ -s "$SECRET_STORE/alice/seed" ]
	# …and NOT into the wallet repo.
	! grep -rqE '\b(abandon|legal|letter|zoo|gravity|hamster|scheme|horn|panda)\b' \
		"$XDG_DATA_HOME/bitcoin/wallets/alice" 2>/dev/null
}

@test "FEAT-010 — wallet new rejects a duplicate name" {
	setup_wallet_env
	"$BITCOIN_BIN" wallet new alice
	run "$BITCOIN_BIN" wallet new alice
	[ "$status" -ne 0 ]
}

@test "FEAT-010 — wallet new rejects an invalid name" {
	setup_wallet_env
	run "$BITCOIN_BIN" wallet new "../escape"
	[ "$status" -ne 0 ]
}

@test "FEAT-010 — wallet ls lists created wallets" {
	setup_wallet_env
	"$BITCOIN_BIN" wallet new alice
	"$BITCOIN_BIN" wallet new bob
	run "$BITCOIN_BIN" wallet ls
	[ "$status" -eq 0 ]
	[[ "$output" == *"alice"* ]]
	[[ "$output" == *"bob"* ]]
}

@test "FEAT-010 — wallet rm removes the wallet repo" {
	setup_wallet_env
	"$BITCOIN_BIN" wallet new alice
	[ -d "$XDG_DATA_HOME/bitcoin/wallets/alice" ]
	run "$BITCOIN_BIN" wallet rm alice
	[ "$status" -eq 0 ]
	[ ! -d "$XDG_DATA_HOME/bitcoin/wallets/alice" ]
}

@test "FEAT-010 — wallet rm <missing> exits non-zero with a clear error" {
	setup_wallet_env
	run "$BITCOIN_BIN" wallet rm no-such-wallet
	[ "$status" -ne 0 ]
	[[ "$output" == *"no-such-wallet"* ]] || [[ "$stderr" == *"no-such-wallet"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-009 — output descriptors. The checksum is BIP-380's polymod over
# the descriptor's INPUT_CHARSET; the test vector is from the spec.
# ---------------------------------------------------------------------------

@test "FEAT-009 — bitcoin help descriptor cites BIP-380/381/386" {
	run "$BITCOIN_BIN" help descriptor
	[ "$status" -eq 0 ]
	[[ "$output" == *"BIP-380"* ]]
	[[ "$output" == *"bip-0380.mediawiki"* ]]
}

@test "FEAT-009 — descriptor checksum matches BIP-380 test vector" {
	# Spec test vector: raw(deadbeef) → raw(deadbeef)#89f8spxm
	run "$BITCOIN_BIN" bip380 checksum "raw(deadbeef)"
	[ "$status" -eq 0 ]
	[ "$output" = "raw(deadbeef)#89f8spxm" ]
}

@test "FEAT-009 — descriptor checksum is idempotent on an already-checksummed string" {
	# Passing a string that already ends in `#<8 chars>` should
	# replace the suffix with the freshly-computed checksum.
	run "$BITCOIN_BIN" bip380 checksum "raw(deadbeef)#00000000"
	[ "$status" -eq 0 ]
	[ "$output" = "raw(deadbeef)#89f8spxm" ]
}

@test "FEAT-009 — descriptor verify accepts a valid checksum" {
	run "$BITCOIN_BIN" bip380 verify "raw(deadbeef)#89f8spxm"
	[ "$status" -eq 0 ]
}

@test "FEAT-009 — descriptor verify rejects a tampered checksum" {
	# Flip one char of a known-good checksum.
	run "$BITCOIN_BIN" bip380 verify "raw(deadbeef)#89f8spxq"
	[ "$status" -ne 0 ]
}

@test "FEAT-009 — descriptor verify rejects a missing checksum" {
	run "$BITCOIN_BIN" bip380 verify "raw(deadbeef)"
	[ "$status" -ne 0 ]
}

@test "FEAT-009 — descriptor checksum rejects a non-INPUT_CHARSET character" {
	# £ is outside BIP-380's INPUT_CHARSET (ASCII-only).
	run "$BITCOIN_BIN" bip380 checksum "raw(£)"
	[ "$status" -ne 0 ]
}

@test "FEAT-012 — bitcoin backend with no args prints the active backend" {
	setup_backend_env
	run "$BITCOIN_BIN" backend
	[ "$status" -eq 0 ]
	[ "$output" = "mempool" ]
}

@test "FEAT-012 — bitcoin backend mempool sets the active backend" {
	setup_backend_env
	run "$BITCOIN_BIN" backend set mempool
	[ "$status" -eq 0 ]
	[ "$(cat "$XDG_CONFIG_HOME/bitcoin/backend")" = "mempool" ]
}
