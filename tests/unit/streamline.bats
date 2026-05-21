#!/usr/bin/env bats
#
# FEAT-035: command-surface streamline.
#
# As verbs migrate from their historical names (mnemonic-to-seed,
# psbt, descriptor, bech32) to the bipXXX canonical names, this
# file asserts the deprecation contract:
#
#   1. The new canonical name works and produces the canonical
#      output.
#   2. The old (deprecated) name continues to work as an alias —
#      same bytes on stdout, identical exit status.
#   3. The alias emits one warn line on stderr naming the
#      canonical replacement and the removal release.
#
# As each extraction lands, add a "Stream A/B/C/D" block here.

bats_require_minimum_version 1.5.0

setup() {
	export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
	export BITCOIN_BIN="$REPO_ROOT/bin/bitcoin"
	export SELF_LIBEXEC="$REPO_ROOT/libexec"
	export SELF_QUIET=1
	export BIP39_PASSPHRASE=TREZOR
	# The BIP-39 §From mnemonic to seed canonical test vector. The
	# abandon-... mnemonic with passphrase TREZOR yields a fixed
	# 64-byte seed; both the canonical and the deprecated paths
	# must produce these exact bytes.
	export ABANDON_MNEMONIC="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
	export EXPECTED_SEED_HEX="c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
}

# ---------------------------------------------------------------------------
# Stream A: mnemonic-to-seed → bitcoin bip39 mnemonic-to-seed
# ---------------------------------------------------------------------------

@test "FEAT-035 A — bitcoin bip39 mnemonic-to-seed matches the BIP-39 vector" {
	got=$("$BITCOIN_BIN" bip39 mnemonic-to-seed $ABANDON_MNEMONIC 2>/dev/null \
		| basenc --base16 -w0 | tr A-F a-f)
	[ "$got" = "$EXPECTED_SEED_HEX" ]
}

@test "FEAT-035 A — bitcoin mnemonic-to-seed alias produces identical bytes" {
	canonical=$("$BITCOIN_BIN" bip39 mnemonic-to-seed $ABANDON_MNEMONIC 2>/dev/null)
	# The alias path emits a warn on stderr; capture stdout only.
	alias_out=$("$BITCOIN_BIN" mnemonic-to-seed $ABANDON_MNEMONIC 2>/dev/null)
	[ "$canonical" = "$alias_out" ]
}

@test "FEAT-035 A — bitcoin mnemonic-to-seed alias emits one warn line" {
	run --separate-stderr "$BITCOIN_BIN" mnemonic-to-seed $ABANDON_MNEMONIC
	[ "$status" -eq 0 ]
	# One warn line on stderr, naming the canonical and the removal release.
	echo "$stderr" | grep -qE "warn .*mnemonic-to-seed.* deprecated.* 1\.23\.0"
	echo "$stderr" | grep -qF "bitcoin bip39 mnemonic-to-seed"
	echo "$stderr" | grep -qF "1.24.0"
}

@test "FEAT-035 A — bitcoin bip39 mnemonic-to-seed does NOT emit a warn line" {
	run --separate-stderr "$BITCOIN_BIN" bip39 mnemonic-to-seed $ABANDON_MNEMONIC
	[ "$status" -eq 0 ]
	# Canonical path is silent on stderr (modulo SELF_QUIET=1 from setup).
	[ -z "$stderr" ] \
		|| { echo "unexpected stderr on canonical path: $stderr"; return 1; }
}

@test "FEAT-035 A — bitcoin bip39 mnemonic-to-seed reads from stdin when argv is empty" {
	got=$(echo "$ABANDON_MNEMONIC" | "$BITCOIN_BIN" bip39 mnemonic-to-seed 2>/dev/null \
		| basenc --base16 -w0 | tr A-F a-f)
	[ "$got" = "$EXPECTED_SEED_HEX" ]
}

@test "FEAT-035 A — bitcoin bip39 mnemonic-to-seed rejects bad word counts" {
	run "$BITCOIN_BIN" bip39 mnemonic-to-seed only three words
	[ "$status" -ne 0 ]
}

@test "FEAT-035 A — bitcoin bip39 help lists mnemonic-to-seed" {
	run "$BITCOIN_BIN" bip39 help
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "mnemonic-to-seed"
}
