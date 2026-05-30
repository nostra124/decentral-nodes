#!/usr/bin/env bats
#
# FEAT-026 — descriptor derive: tr() and combo() functions.
#
# Cross-checks against the BIP-86 abandon-mnemonic vector — the same
# fixture used by tests/unit/bip341.bats — so the descriptor path and
# the direct bip341 path agree on the address byte-for-byte.

bats_require_minimum_version 1.5.0

setup() {
	BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
	HOME="$(mktemp -d "$BATS_TMPDIR/home.XXXXXX")"
	unset XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME
	export HOME SELF_QUIET=1
	export BITCOIN_BIN="$BATS_TEST_DIRNAME/../../bin/bitcoin"
	export SELF_LIBEXEC="$BATS_TEST_DIRNAME/../../libexec"
	XPUB=xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoGVky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ
	ADDRESS=bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr
}
teardown() { rm -rf "$HOME"; }

@test "FEAT-026 bip380 derive tr() at index 0: BIP-86 address" {
	run "$BITCOIN_BIN" bip380 derive "tr($XPUB/0/*)" 0
	[ "$status" -eq 0 ]
	[ "$output" = "$ADDRESS" ]
}

@test "FEAT-026 bip380 derive combo() at index 0: four addresses (pkh, wpkh, sh(wpkh), tr)" {
	run "$BITCOIN_BIN" bip380 derive "combo($XPUB/0/*)" 0
	[ "$status" -eq 0 ]
	# four lines, the last is the P2TR address
	[ "$(echo "$output" | wc -l)" -eq 4 ]
	[ "$(echo "$output" | tail -n 1)" = "$ADDRESS" ]
	# the first three are legacy/segwit prefixes
	[[ "$(echo "$output" | sed -n 1p)" == 1* ]]      # P2PKH starts with '1'
	[[ "$(echo "$output" | sed -n 2p)" == bc1q* ]]   # P2WPKH starts with 'bc1q'
	[[ "$(echo "$output" | sed -n 3p)" == 3* ]]      # P2SH-P2WPKH starts with '3'
}

@test "FEAT-026 bip380 derive tr() rejects malformed descriptor" {
	run "$BITCOIN_BIN" bip380 derive "tr($XPUB)" 0
	[ "$status" -ne 0 ]
}
