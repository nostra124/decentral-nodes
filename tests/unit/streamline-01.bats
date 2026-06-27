#!/usr/bin/env bats
#
# streamline unit tests — part 1 of 4 (FEAT-053 split of tests/unit/streamline.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/streamline.bash.

bats_require_minimum_version 1.5.0
load lib/streamline


# ---------------------------------------------------------------------------
# Stream A: mnemonic-to-seed → bitcoin bip39 mnemonic-to-seed
# ---------------------------------------------------------------------------

@test "FEAT-035 A — bitcoin bip39 mnemonic-to-seed matches the BIP-39 vector" {
	got=$("$BITCOIN_BIN" bip39 mnemonic-to-seed $ABANDON_MNEMONIC 2>/dev/null \
		| basenc --base16 -w0 | tr A-F a-f)
	[ "$got" = "$EXPECTED_SEED_HEX" ]
}

@test "FEAT-035 A — bitcoin mnemonic-to-seed alias was removed in 1.24.0" {
	# The deprecated standalone shim is gone; the dispatcher's
	# command:mnemonic-to-seed stub errors with a clear removal
	# message pointing at the canonical bip39 subcommand.
	run --separate-stderr "$BITCOIN_BIN" mnemonic-to-seed $ABANDON_MNEMONIC
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "'mnemonic-to-seed' was removed in 1\.24\.0"
	echo "$stderr" | grep -qF "bitcoin bip39 mnemonic-to-seed"
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

# ---------------------------------------------------------------------------
# Stream C: bech32 → bitcoin bip173 (BIP-173) and bitcoin bip350 (BIP-350)
#
# Additive-only in this PR: the new plugins ship side-by-side with
# the existing `bitcoin bech32*` verbs. No deprecation aliases yet
# (the bech32 verbs are also called internally by segwitAddress /
# p2wpkh, so deprecation requires coordinated callsite updates that
# come in a follow-up).
# ---------------------------------------------------------------------------

@test "FEAT-035 C — bip173 encode matches the bech32 help-doc vector" {
	expected="this-part-is-readable-by-a-human1qpzrylhvwcq"
	run "$BITCOIN_BIN" bip173 encode this-part-is-readable-by-a-human qpzry
	[ "$status" -eq 0 ]
	[ "$output" = "$expected" ]
}

@test "FEAT-035 C — bip173 verify accepts a known-good bech32 vector" {
	run "$BITCOIN_BIN" bip173 verify this-part-is-readable-by-a-human1qpzrylhvwcq
	[ "$status" -eq 0 ]
}

@test "FEAT-035 C — bip173 verify rejects a tampered checksum" {
	run "$BITCOIN_BIN" bip173 verify this-part-is-readable-by-a-human1qpzrylhvwcz
	[ "$status" -ne 0 ]
}

@test "FEAT-035 C — bip173 verify rejects a bech32m (BIP-350) string" {
	run "$BITCOIN_BIN" bip173 verify this-part-is-readable-by-a-human1qpzry2tuzaz
	[ "$status" -ne 0 ]
}

@test "FEAT-035 C — bip173 decode round-trips a known-good vector" {
	run "$BITCOIN_BIN" bip173 decode this-part-is-readable-by-a-human1qpzrylhvwcq
	[ "$status" -eq 0 ]
	# HRP then five 5-bit values for "qpzry" (0, 1, 2, 3, 4).
	[ "$(echo "$output" | head -1)" = "this-part-is-readable-by-a-human" ]
	[ "$(echo "$output" | sed -n '2p')" = "0" ]
	[ "$(echo "$output" | sed -n '6p')" = "4" ]
}

@test "FEAT-035 C — bip350 encode matches the bech32m help-doc vector" {
	expected="this-part-is-readable-by-a-human1qpzry2tuzaz"
	run "$BITCOIN_BIN" bip350 encode this-part-is-readable-by-a-human qpzry
	[ "$status" -eq 0 ]
	[ "$output" = "$expected" ]
}

@test "FEAT-035 C — bip350 verify accepts a known-good bech32m vector" {
	run "$BITCOIN_BIN" bip350 verify this-part-is-readable-by-a-human1qpzry2tuzaz
	[ "$status" -eq 0 ]
}

@test "FEAT-035 C — bip350 verify rejects a bech32 (BIP-173) string" {
	run "$BITCOIN_BIN" bip350 verify this-part-is-readable-by-a-human1qpzrylhvwcq
	[ "$status" -ne 0 ]
}

@test "FEAT-035 C — bip173 encode rejects mixed-case input" {
	run "$BITCOIN_BIN" bip173 encode SomeHRP qpzry
	[ "$status" -ne 0 ]
}

@test "FEAT-035 C — bip173 encode rejects data outside the charset" {
	run "$BITCOIN_BIN" bip173 encode somehrp 'qpzryb'
	[ "$status" -ne 0 ]
}

@test "FEAT-035 C — bip173 help lists every subcommand" {
	run "$BITCOIN_BIN" bip173 help
	# Help is on stderr, so combine streams via 2>&1 in the run.
	run bash -c "'$BITCOIN_BIN' bip173 help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "encode"
	echo "$output" | grep -q "decode"
	echo "$output" | grep -q "verify"
}

@test "FEAT-035 C — bip350 help lists every subcommand" {
	run bash -c "'$BITCOIN_BIN' bip350 help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "encode"
	echo "$output" | grep -q "decode"
	echo "$output" | grep -q "verify"
}

# ---------------------------------------------------------------------------
# Stream D: psbt → bitcoin bip174 (BIP-174 PSBT).
#
# Full rename: psbt block moved verbatim from bin/bitcoin-node into
# libexec/bitcoin-node/bip174. command:psbt remains as a deprecated
# alias that emits one warn line and execs bip174. Internal callers
# in wallet:sign / wallet:send migrated to call bip174 directly
# (same pattern as Stream A's mnemonic-to-seed fix).
# ---------------------------------------------------------------------------

@test "FEAT-035 D — bitcoin bip174 help renders" {
	run bash -c "'$BITCOIN_BIN' bip174 help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "decode"
	echo "$output" | grep -q "encode"
	echo "$output" | grep -q "sign"
	echo "$output" | grep -q "finalize"
	echo "$output" | grep -q "extract"
}

@test "FEAT-035 D — bitcoin bip174 encode empty stdin produces magic + terminator" {
	got=$(printf '' | "$BITCOIN_BIN" bip174 encode 2>/dev/null)
	[ "$got" = "70736274ff00" ]
}

@test "FEAT-035 D — bitcoin bip174 decode + encode round-trip is identity" {
	# A single-record global-section PSBT: magic + 0x01 key 0x00 value
	# 0x00 (length-1 record) + 0x00 section terminator.
	original="70736274ff0100010000"
	tsv=$(printf '%s\n' "$original" | "$BITCOIN_BIN" bip174 decode 2>/dev/null)
	roundtrip=$(printf '%s\n' "$tsv" | "$BITCOIN_BIN" bip174 encode 2>/dev/null)
	[ "$roundtrip" = "$original" ]
}

@test "FEAT-035 D — bitcoin psbt alias was removed in 1.24.0" {
	# FEAT-035 alias-removal sweep: the warn-and-forward command:psbt
	# now errors out with a clear removal message pointing at the
	# canonical bip174 plugin.
	run --separate-stderr bash -c "echo '70736274ff00' | '$BITCOIN_BIN' psbt decode"
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "'psbt' was removed in 1\.24\.0"
	echo "$stderr" | grep -qF "bitcoin bip174"
}

@test "FEAT-035 D — bitcoin bip174 decode does NOT emit a warn line" {
	run --separate-stderr bash -c "echo '70736274ff00' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	# SELF_QUIET=1 from setup suppresses info; canonical path stays silent.
	[ -z "$stderr" ] \
		|| { echo "unexpected stderr on canonical path: $stderr"; return 1; }
}

@test "FEAT-035 D — bitcoin bip174 decode rejects bad magic" {
	run bash -c "echo 'ff00' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -ne 0 ]
}

@test "FEAT-035 D — bitcoin bip174 decode rejects empty input" {
	run bash -c ": | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Stream C2: bech32* command:* functions become deprecation aliases.
#
# Stream C (PR #35) added bip173 / bip350 plugins additively. Stream
# C2 (this PR) wires them into segwitAddress + wallet:_address_to_script
# and deprecates the legacy `bitcoin bech32` / `bech32-verify` /
# `bech32-encode` / `bech32-decode` verbs.
# ---------------------------------------------------------------------------

@test "FEAT-035 C2 — every bech32* verb was removed in 1.24.0" {
	# FEAT-035 alias-removal sweep: bech32 / bech32-verify /
	# bech32-encode / bech32-decode all error out pointing at the
	# canonical bip173 / bip350 plugins.
	for verb in bech32 bech32-verify bech32-encode bech32-decode; do
		run --separate-stderr "$BITCOIN_BIN" "$verb" hrp qpzry
		[ "$status" -ne 0 ] \
			|| { echo "'$verb' did not error after removal"; return 1; }
		echo "$stderr" | grep -qE "'$verb' was removed in 1\.24\.0" \
			|| { echo "'$verb' missing removal message"; return 1; }
		echo "$stderr" | grep -qE "bip173|bip350" \
			|| { echo "'$verb' removal message missing canonical pointer"; return 1; }
	done
}

@test "FEAT-035 C2 — bitcoin help bech32 still cites the BIPs (FEAT-017)" {
	# help:bech32 survives the verb removal so the educational BIP
	# citations remain reachable.
	run bash -c "'$BITCOIN_BIN' help bech32 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE "BIP-173|bip-0173"
	echo "$output" | grep -qE "BIP-350|bip-0350"
}

@test "FEAT-035 C2 — bitcoin bip173 / bip350 emit NO warn lines" {
	run --separate-stderr "$BITCOIN_BIN" bip173 encode this-part-is-readable-by-a-human qpzry
	[ "$status" -eq 0 ]; [ -z "$stderr" ]
	run --separate-stderr "$BITCOIN_BIN" bip350 encode this-part-is-readable-by-a-human qpzry
	[ "$status" -eq 0 ]; [ -z "$stderr" ]
}

@test "FEAT-035 C2 — wallet:_address_to_script (via wallet build) still parses bech32 addresses" {
	# Exercised end-to-end by FEAT-014 wallet build tests in bitcoin.bats
	# (which after Stream C2 reach bech32 decode through bip173 / bip350).
	# This assertion proves the dispatcher routing works from this test's
	# pure environment without spinning up a wallet.
	run "$BITCOIN_BIN" bip173 decode bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu
	[ "$status" -eq 0 ]
	# bip173 decode emits HRP on line 1.
	[ "$(echo "$output" | head -1)" = "bc" ]
}

# ---------------------------------------------------------------------------
# Stream B: descriptor → bitcoin bip380 (BIP-380 descriptors).
#
# Three pure verbs (checksum / verify / derive) move to libexec.
# `bitcoin descriptor wallet <name>` stays in bin/bitcoin-node because it
# reads `secret`-managed wallet state; not deprecated yet (re-home in
# a future PR under `wallet descriptor`).
# ---------------------------------------------------------------------------

@test "FEAT-035 B — bitcoin bip380 checksum matches BIP-380 test vector" {
	expected="raw(deadbeef)#89f8spxm"
	run "$BITCOIN_BIN" bip380 checksum 'raw(deadbeef)'
	[ "$status" -eq 0 ]
	[ "$output" = "$expected" ]
}

@test "FEAT-035 B — bitcoin descriptor checksum alias was removed in 1.24.0" {
	# FEAT-035 alias-removal sweep: the deprecated checksum alias now
	# errors out pointing at the canonical bip380 verb.
	run --separate-stderr "$BITCOIN_BIN" descriptor checksum 'raw(deadbeef)'
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "'descriptor checksum' was removed in 1\.24\.0"
	echo "$stderr" | grep -qF "bitcoin bip380 checksum"
}

@test "FEAT-035 B — bitcoin bip380 verify accepts a known-good checksum" {
	run "$BITCOIN_BIN" bip380 verify 'raw(deadbeef)#89f8spxm'
	[ "$status" -eq 0 ]
}

@test "FEAT-035 B — bitcoin bip380 verify rejects a tampered checksum" {
	run "$BITCOIN_BIN" bip380 verify 'raw(deadbeef)#00000000'
	[ "$status" -ne 0 ]
}

@test "FEAT-035 B — bitcoin descriptor verify alias was removed in 1.24.0" {
	run --separate-stderr "$BITCOIN_BIN" descriptor verify 'raw(deadbeef)#89f8spxm'
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "'descriptor verify' was removed in 1\.24\.0"
	echo "$stderr" | grep -qF "bitcoin bip380 verify"
}

@test "FEAT-035 B — bitcoin descriptor wallet (no warn — not deprecated)" {
	# wallet subcommand stays in bin/bitcoin-node and should NOT emit a
	# deprecation warn line. With no args it errors with a clear
	# "name required" message on stderr; that's not the warn line.
	run --separate-stderr "$BITCOIN_BIN" descriptor wallet
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qv "deprecated" \
		|| { echo "unexpected deprecation warn for non-deprecated subcommand"; return 1; }
}

@test "FEAT-035 B — bitcoin bip380 emits NO warn lines" {
	run --separate-stderr "$BITCOIN_BIN" bip380 checksum 'raw(deadbeef)'
	[ "$status" -eq 0 ]
	[ -z "$stderr" ] \
		|| { echo "unexpected stderr on canonical path: $stderr"; return 1; }
}

@test "FEAT-035 B — bitcoin bip380 help lists checksum, verify, derive" {
	run bash -c "'$BITCOIN_BIN' bip380 help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "checksum"
	echo "$output" | grep -q "verify"
	echo "$output" | grep -q "derive"
}

# ---------------------------------------------------------------------------
# FEAT-036 (1.23.0): `bitcoin tx` object verb.
#
# Initial PR: additive `tx` namespace. tx build / sign / broadcast
# delegate to wallet:* (no rename yet); tx decode / finalize /
# extract pass through to bip174. Deprecation of wallet:build /
# sign / broadcast and `--utxo` coin-control land in a follow-up.
# ---------------------------------------------------------------------------

@test "FEAT-036 — bitcoin tx help lists every subcommand" {
	run bash -c "'$BITCOIN_BIN' tx help 2>&1"
	[ "$status" -eq 0 ]
	for sub in build sign decode finalize extract broadcast; do
		echo "$output" | grep -qE "(^|[[:space:]])$sub([[:space:]]|$)" \
			|| { echo "help missing subcommand: $sub"; return 1; }
	done
}

@test "FEAT-036 — bitcoin tx decode passes through to bip174 decode" {
	# Single-record global PSBT.
	original="70736274ff0100010000"
	canonical=$(printf '%s\n' "$original" | "$BITCOIN_BIN" bip174 decode 2>/dev/null)
	via_tx=$(printf '%s\n' "$original" | "$BITCOIN_BIN" tx decode 2>/dev/null)
	[ "$canonical" = "$via_tx" ]
	# And the output is non-empty (proves the decode actually ran).
	[ -n "$via_tx" ]
}

@test "FEAT-036 — bitcoin tx finalize exit code matches bip174 finalize" {
	# Same input → same exit code through both surfaces. (Specific
	# PSBTs that successfully finalise are exercised in the FEAT-008
	# tests in bitcoin.bats; this assertion just proves the tx
	# dispatcher forwards stdin and exit status faithfully.)
	original="70736274ff0100010000"
	canonical_status=$(printf '%s\n' "$original" | "$BITCOIN_BIN" bip174 finalize 2>/dev/null; echo $?)
	via_tx_status=$(printf '%s\n' "$original" | "$BITCOIN_BIN" tx finalize 2>/dev/null; echo $?)
	[ "$canonical_status" = "$via_tx_status" ]
}

@test "FEAT-036 — bitcoin tx extract rejects unfinalised PSBTs (same as bip174)" {
	# extract refuses a PSBT lacking FINAL_SCRIPTWITNESS.
	run bash -c "echo '70736274ff0100010000' | '$BITCOIN_BIN' tx extract"
	[ "$status" -ne 0 ]
}

@test "FEAT-036 — bitcoin tx build with no args usage-errors like wallet build" {
	run "$BITCOIN_BIN" tx build
	[ "$status" -ne 0 ]
	# error message comes from wallet:build (delegation target).
	echo "$output" | grep -q "tx build:"
}

@test "FEAT-036 — bitcoin tx broadcast with no args usage-errors like wallet broadcast" {
	run "$BITCOIN_BIN" tx broadcast
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "tx broadcast:"
}

@test "FEAT-036 — bitcoin tx <unknown> errors with the valid subcommand list" {
	run "$BITCOIN_BIN" tx not-a-subcommand
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "unknown tx subcommand"
	for sub in build sign decode finalize extract broadcast; do
		echo "$output" | grep -q "$sub"
	done
}
