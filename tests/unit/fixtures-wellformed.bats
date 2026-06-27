#!/usr/bin/env bats
#
# FEAT-050 — fixture well-formedness guard.
#
# The PSBT/tx test vectors elsewhere in the suite are hand-typed hex
# literals. BUG-021 shipped a PSBT whose global unsigned-tx record declared
# 82 bytes but carried 83: the parser honoured the length prefix, the stray
# byte desynced every later section, and `sign` silently produced nothing —
# yet the literal *looked* fine to a human reviewer. This suite runs the
# `tests/unit/helpers.bash` well-formedness assertions over the canonical
# fixtures so that class of silent desync fails at authoring time, and
# pins the assertions themselves with positive + negative cases.

load helpers

# The canonical BIP-174 P2PKH/P2SH vectors, copied verbatim from
# bip174-p2pkh.bats. If those literals drift out of sync with these, the
# point of the guard is lost — so keep them identical.
UNSIGNED_TX="020000000100000000000000000000000000000000000000000000000000000000000000000000000000feffffff0150c3000000000000160014000000000000000000000000000000000000000000000000"
ALICE_HASH160=c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2
P2PKH_PSBT="70736274ff010052${UNSIGNED_TX}00010122a0860100000000001976a914${ALICE_HASH160}88ac0000"
P2SH_PSBT="70736274ff010052020000000100000000000000000000000000000000000000000000000000000000000000000000000000feffffff0150c300000000000016001400000000000000000000000000000000000000000000000000010120a08601000000000017a914a6b5888fddc8fa193dd353d10e5cd5a8eeab064e870104160014c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e20000"

@test "FEAT-050: tx_byte_len parses the canonical unsigned tx as 82 bytes" {
	run tx_byte_len "$UNSIGNED_TX"
	[ "$status" -eq 0 ]
	[ "$output" -eq 82 ]
}

@test "FEAT-050: tx_byte_len rejects a truncated tx (overrun)" {
	# Drop the last byte of the locktime — no longer a complete tx.
	run tx_byte_len "${UNSIGNED_TX%??}"
	[ "$status" -ne 0 ]
}

@test "FEAT-050: canonical P2PKH PSBT fixture is well-formed" {
	run assert_psbt_wellformed "$P2PKH_PSBT"
	[ "$status" -eq 0 ]
}

@test "FEAT-050: canonical P2SH PSBT fixture is well-formed" {
	run assert_psbt_wellformed "$P2SH_PSBT"
	[ "$status" -eq 0 ]
}

@test "FEAT-050: a non-PSBT blob is rejected (magic check)" {
	run assert_psbt_wellformed "deadbeef"
	[ "$status" -ne 0 ]
	[[ "$output" == *"magic"* ]]
}

@test "FEAT-050: BUG-021 reproduction — over-declared global tx length is caught" {
	# Declare 0x53 (83) for a real 82-byte tx — the exact desync that shipped.
	local bad="70736274ff010053${UNSIGNED_TX}00010122a0860100000000001976a914${ALICE_HASH160}88ac0000"
	run assert_psbt_wellformed "$bad"
	[ "$status" -ne 0 ]
	[[ "$output" == *"BUG-021"* ]]
}

@test "FEAT-050: BUG-021 reproduction — under-declared global tx length is caught" {
	# Declare 0x51 (81) for a real 82-byte tx: the value is one byte short,
	# the trailing byte bleeds into the next record and desyncs the walk.
	local bad="70736274ff010051${UNSIGNED_TX}00010122a0860100000000001976a914${ALICE_HASH160}88ac0000"
	run assert_psbt_wellformed "$bad"
	[ "$status" -ne 0 ]
}

@test "FEAT-050: a PSBT not ending on a 0x00 separator is rejected" {
	# Lop off both trailing map separators so the walk ends on a record value
	# instead of a terminating 0x00 — the truncated-tail signal.
	run assert_psbt_wellformed "${P2PKH_PSBT%????}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"separator"* ]]
}
