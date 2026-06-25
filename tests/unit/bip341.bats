#!/usr/bin/env bats
#
# FEAT-007 — BIP-341 Taproot tweak and P2TR address plugin.
#
# Vectors: the abandon-mnemonic BIP-86 derivation
# (m/86h/0h/0h/0/0) is the canonical reference. Internal x-only key,
# tweaked output key, and address are all known and cross-checked.

bats_require_minimum_version 1.5.0

setup() {
	BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
	HOME="$(mktemp -d "$BATS_TMPDIR/home.XXXXXX")"
	unset XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME
	export HOME SELF_QUIET=1
	export BITCOIN_BIN="$BATS_TEST_DIRNAME/../../bin/bitcoin-node"
	export SELF_LIBEXEC="$BATS_TEST_DIRNAME/../../libexec"
	INTERNAL=CC8A4BC64D897BDDC5FBC2F670F7A8BA0B386779106CF1223C6FC5D7CD6FC115
	TWEAKED=A60869F0DBCF1DC659C9CECBAF8050135EA9E8CDC487053F1DC6880949DC684C
	ADDRESS=bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr
}
teardown() { rm -rf "$HOME"; }

@test "FEAT-007 bip341 tweak: BIP-86 internal → tweaked output key" {
	run "$BITCOIN_BIN" bip341 tweak "$INTERNAL"
	[ "$status" -eq 0 ]
	[ "$output" = "$TWEAKED" ]
}

@test "FEAT-007 bip341 address: BIP-86 internal → bc1p…" {
	run "$BITCOIN_BIN" bip341 address "$INTERNAL"
	[ "$status" -eq 0 ]
	[ "$output" = "$ADDRESS" ]
}

@test "FEAT-007 bip341 address: --testnet swaps the HRP" {
	run "$BITCOIN_BIN" bip341 address --testnet "$INTERNAL"
	[ "$status" -eq 0 ]
	[[ "$output" == tb1p* ]]
}

@test "FEAT-007 bip341 tweak: rejects an internal key off the curve" {
	# Not a valid x-coordinate of any secp256k1 point.
	run "$BITCOIN_BIN" bip341 tweak FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE
	[ "$status" -ne 0 ]
}

@test "FEAT-007 bip341 help: lists tweak and address; cites BIP-341" {
	run "$BITCOIN_BIN" bip341 help
	[ "$status" -eq 0 ]
	[[ "$output" == *tweak*   ]]
	[[ "$output" == *address* ]]
	[[ "$output" == *BIP-341* ]]
}
