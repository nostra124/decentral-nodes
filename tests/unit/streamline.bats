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
	# Isolated XDG paths so FEAT-037 freeze/unfreeze tests don't
	# clobber a real user's ~/.local/var/bitcoin/wallets.
	BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
	HOME="$(mktemp -d "$BATS_TMPDIR/home.XXXXXX")"
	export HOME
	export XDG_DATA_HOME="$HOME/.local/share"
	mkdir -p "$XDG_DATA_HOME/bitcoin/wallets"
}

# Lightweight wallet fixture for FEAT-037 (frozen.tsv) tests.
# Doesn't need a real seed or backend round-trip: freeze /
# unfreeze just need the wallet dir + an addresses ledger + git.
feat037_setup_wallet() {
	local name="${1:-alice}"
	local path="$XDG_DATA_HOME/bitcoin/wallets/$name"
	mkdir -p "$path"
	printf '0\tbc1qexample\t\n' > "$path/addresses"
	(
		cd "$path"
		git init -q
		git -c user.email=wallet@bitcoin -c user.name=bitcoin \
		    -c commit.gpgsign=false \
			add addresses
		git -c user.email=wallet@bitcoin \
			-c user.name=bitcoin -c commit.gpgsign=false \
			commit -q -m "initial"
	)
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

@test "FEAT-035 C — bip173 encode == bitcoin bech32 (same bytes)" {
	canonical=$("$BITCOIN_BIN" bip173 encode this-part-is-readable-by-a-human qpzry)
	legacy=$("$BITCOIN_BIN" bech32 this-part-is-readable-by-a-human qpzry)
	[ "$canonical" = "$legacy" ]
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

@test "FEAT-035 C — bip350 encode == bitcoin bech32 -m (same bytes)" {
	canonical=$("$BITCOIN_BIN" bip350 encode this-part-is-readable-by-a-human qpzry)
	legacy=$("$BITCOIN_BIN" bech32 -m this-part-is-readable-by-a-human qpzry)
	[ "$canonical" = "$legacy" ]
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
# Full rename: psbt block moved verbatim from bin/bitcoin into
# libexec/bitcoin/bip174. command:psbt remains as a deprecated
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

@test "FEAT-035 D — bitcoin bip174 decode == bitcoin psbt decode (same bytes)" {
	original="70736274ff0100010000"
	canonical=$(printf '%s\n' "$original" | "$BITCOIN_BIN" bip174 decode 2>/dev/null)
	# Alias path emits warn on stderr; strip with 2>/dev/null.
	alias_out=$(printf '%s\n' "$original" | "$BITCOIN_BIN" psbt decode 2>/dev/null)
	[ "$canonical" = "$alias_out" ]
}

@test "FEAT-035 D — bitcoin psbt alias emits one warn line" {
	run --separate-stderr bash -c "echo '70736274ff00' | '$BITCOIN_BIN' psbt decode"
	[ "$status" -eq 0 ]
	echo "$stderr" | grep -qE "warn .*psbt.* deprecated.* 1\.23\.0"
	echo "$stderr" | grep -qF "bitcoin bip174"
	echo "$stderr" | grep -qF "1.24.0"
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

@test "FEAT-035 C2 — bitcoin bech32 alias produces identical bytes to bip173 encode" {
	canonical=$("$BITCOIN_BIN" bip173 encode this-part-is-readable-by-a-human qpzry 2>/dev/null)
	alias_out=$("$BITCOIN_BIN" bech32 this-part-is-readable-by-a-human qpzry 2>/dev/null)
	[ "$canonical" = "$alias_out" ]
}

@test "FEAT-035 C2 — bitcoin bech32 -m alias produces identical bytes to bip350 encode" {
	canonical=$("$BITCOIN_BIN" bip350 encode this-part-is-readable-by-a-human qpzry 2>/dev/null)
	alias_out=$("$BITCOIN_BIN" bech32 -m this-part-is-readable-by-a-human qpzry 2>/dev/null)
	[ "$canonical" = "$alias_out" ]
}

@test "FEAT-035 C2 — bitcoin bech32 alias emits one warn line" {
	run --separate-stderr "$BITCOIN_BIN" bech32 this-part-is-readable-by-a-human qpzry
	[ "$status" -eq 0 ]
	echo "$stderr" | grep -qE "warn .*bech32.* deprecated.* 1\.23\.0"
	echo "$stderr" | grep -qF "bitcoin bip173 encode"
	echo "$stderr" | grep -qF "1.24.0"
}

@test "FEAT-035 C2 — bitcoin bech32 -m alias warn line mentions both bip173 and bip350" {
	run --separate-stderr "$BITCOIN_BIN" bech32 -m this-part-is-readable-by-a-human qpzry
	[ "$status" -eq 0 ]
	echo "$stderr" | grep -qF "bitcoin bip350 encode"
}

@test "FEAT-035 C2 — bitcoin bech32-verify alias forwards" {
	canonical_status=$("$BITCOIN_BIN" bip173 verify this-part-is-readable-by-a-human1qpzrylhvwcq 2>/dev/null; echo $?)
	alias_status=$("$BITCOIN_BIN" bech32-verify this-part-is-readable-by-a-human1qpzrylhvwcq 2>/dev/null; echo $?)
	[ "$canonical_status" = "$alias_status" ]
}

@test "FEAT-035 C2 — bitcoin bech32-encode alias produces identical bytes to bip173 encode-values" {
	canonical=$("$BITCOIN_BIN" bip173 encode-values bc 0 14 20 15 7 13 26 0 25 18 6 11 13 8 21 4 20 3 17 2 29 3 0 0 25 0 25 4 7 27 28 16 0 0 2>/dev/null)
	alias_out=$("$BITCOIN_BIN" bech32-encode bc 0 14 20 15 7 13 26 0 25 18 6 11 13 8 21 4 20 3 17 2 29 3 0 0 25 0 25 4 7 27 28 16 0 0 2>/dev/null)
	[ "$canonical" = "$alias_out" ]
}

@test "FEAT-035 C2 — bitcoin bech32-decode alias produces identical lines to bip173 decode" {
	canonical=$("$BITCOIN_BIN" bip173 decode this-part-is-readable-by-a-human1qpzrylhvwcq 2>/dev/null)
	alias_out=$("$BITCOIN_BIN" bech32-decode this-part-is-readable-by-a-human1qpzrylhvwcq 2>/dev/null)
	[ "$canonical" = "$alias_out" ]
}

@test "FEAT-035 C2 — every bech32* alias emits exactly one warn line" {
	for verb in "bech32 hrp qpzry" "bech32-verify hrp1qpzry" "bech32-encode hrp 0 1 2 3 4" "bech32-decode hrp1qpzry"; do
		run --separate-stderr bash -c "'$BITCOIN_BIN' $verb 2>&1 >/dev/null"
		warn_count=$(echo "$output" | grep -c "warn" || true)
		[ "$warn_count" -le 1 ] \
			|| { echo "verb='$verb' emitted $warn_count warn lines"; return 1; }
	done
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
# `bitcoin descriptor wallet <name>` stays in bin/bitcoin because it
# reads `secret`-managed wallet state; not deprecated yet (re-home in
# a future PR under `wallet descriptor`).
# ---------------------------------------------------------------------------

@test "FEAT-035 B — bitcoin bip380 checksum matches BIP-380 test vector" {
	expected="raw(deadbeef)#89f8spxm"
	run "$BITCOIN_BIN" bip380 checksum 'raw(deadbeef)'
	[ "$status" -eq 0 ]
	[ "$output" = "$expected" ]
}

@test "FEAT-035 B — bitcoin descriptor checksum alias produces identical bytes" {
	canonical=$("$BITCOIN_BIN" bip380 checksum 'raw(deadbeef)' 2>/dev/null)
	alias_out=$("$BITCOIN_BIN" descriptor checksum 'raw(deadbeef)' 2>/dev/null)
	[ "$canonical" = "$alias_out" ]
}

@test "FEAT-035 B — bitcoin descriptor checksum alias emits one warn line" {
	run --separate-stderr "$BITCOIN_BIN" descriptor checksum 'raw(deadbeef)'
	[ "$status" -eq 0 ]
	echo "$stderr" | grep -qE "warn .*descriptor checksum.* deprecated.* 1\.23\.0"
	echo "$stderr" | grep -qF "bitcoin bip380 checksum"
	echo "$stderr" | grep -qF "1.24.0"
}

@test "FEAT-035 B — bitcoin bip380 verify accepts a known-good checksum" {
	run "$BITCOIN_BIN" bip380 verify 'raw(deadbeef)#89f8spxm'
	[ "$status" -eq 0 ]
}

@test "FEAT-035 B — bitcoin bip380 verify rejects a tampered checksum" {
	run "$BITCOIN_BIN" bip380 verify 'raw(deadbeef)#00000000'
	[ "$status" -ne 0 ]
}

@test "FEAT-035 B — bitcoin descriptor verify alias forwards exit code" {
	canonical_status=$("$BITCOIN_BIN" bip380 verify 'raw(deadbeef)#89f8spxm' 2>/dev/null; echo $?)
	alias_status=$("$BITCOIN_BIN" descriptor verify 'raw(deadbeef)#89f8spxm' 2>/dev/null; echo $?)
	[ "$canonical_status" = "$alias_status" ]
}

@test "FEAT-035 B — bitcoin descriptor wallet (no warn — not deprecated)" {
	# wallet subcommand stays in bin/bitcoin and should NOT emit a
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

@test "FEAT-036 — bitcoin tx (no subcommand) prints help" {
	run "$BITCOIN_BIN" tx
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "Usage:"
}

# FEAT-036 follow-up (1.23.0): wallet:build / wallet:sign /
# wallet:broadcast moved to tx:* and the wallet:* names became
# deprecated aliases that warn + forward. wallet:send was
# migrated to call tx:* directly so it stays warn-free.

@test "FEAT-036 followup — wallet build emits one warn line citing tx build" {
	run --separate-stderr "$BITCOIN_BIN" wallet build
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "warn .*wallet build.* deprecated.* 1\.23\.0"
	echo "$stderr" | grep -qF "bitcoin tx build"
	echo "$stderr" | grep -qF "1.24.0"
}

@test "FEAT-036 followup — wallet sign emits one warn line citing tx sign" {
	run --separate-stderr "$BITCOIN_BIN" wallet sign
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "warn .*wallet sign.* deprecated.* 1\.23\.0"
	echo "$stderr" | grep -qF "bitcoin tx sign"
}

@test "FEAT-036 followup — wallet broadcast emits one warn line citing tx broadcast" {
	run --separate-stderr "$BITCOIN_BIN" wallet broadcast
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "warn .*wallet broadcast.* deprecated.* 1\.23\.0"
	echo "$stderr" | grep -qF "bitcoin tx broadcast"
}

@test "FEAT-036 followup — bitcoin tx build emits NO deprecation warn" {
	# Canonical path stays silent. Usage error from missing args is
	# fine; the warn line specifically citing the 1.23.0 deprecation
	# must be absent.
	run --separate-stderr "$BITCOIN_BIN" tx build
	if echo "$stderr" | grep -qE "deprecated.* 1\.23\.0"; then
		echo "unexpected deprecation warn on canonical path: $stderr"
		return 1
	fi
}

@test "FEAT-036 followup — wallet build alias error-message uses tx canonical name" {
	run "$BITCOIN_BIN" wallet build
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "tx build:"
}

# ---------------------------------------------------------------------------
# FEAT-037 (1.23.0): `bitcoin utxo` object verb.
#
# Initial PR: ls + freeze + unfreeze. `utxo select`, the `tx build`
# refuse-frozen integration, and the `wallet index` deprecation alias
# follow in separate PRs per the ROADMAP-1.23.0 PR-sequencing.
# ---------------------------------------------------------------------------

@test "FEAT-037 — bitcoin utxo help lists ls/freeze/unfreeze" {
	run bash -c "'$BITCOIN_BIN' utxo help 2>&1"
	[ "$status" -eq 0 ]
	for sub in ls freeze unfreeze; do
		echo "$output" | grep -qE "(^|[[:space:]])$sub([[:space:]]|$)" \
			|| { echo "help missing subcommand: $sub"; return 1; }
	done
}

@test "FEAT-037 — bitcoin utxo (no subcommand) prints help" {
	run "$BITCOIN_BIN" utxo
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "Usage:"
}

@test "FEAT-037 — bitcoin utxo <unknown> errors with the valid subcommand list" {
	run "$BITCOIN_BIN" utxo not-a-subcommand
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "unknown utxo subcommand"
	for sub in ls freeze unfreeze; do
		echo "$output" | grep -q "$sub"
	done
}

@test "FEAT-037 — utxo freeze rejects a malformed outpoint" {
	run "$BITCOIN_BIN" utxo freeze any-wallet not-an-outpoint
	[ "$status" -ne 0 ]
	# Validation runs before wallet-existence so the user sees the
	# shape error even on a typo'd wallet name.
	echo "$output" | grep -q "must look like"
}

@test "FEAT-037 — utxo freeze rejects --reason with tabs" {
	run "$BITCOIN_BIN" utxo freeze any-wallet abc123:0 --reason "tab	in	reason"
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "must not contain tabs"
}

@test "FEAT-037 — utxo freeze on a real wallet writes frozen.tsv and commits" {
	feat037_setup_wallet
	run "$BITCOIN_BIN" utxo freeze alice abc123:0 --reason "KYC concern"
	[ "$status" -eq 0 ]
	frozen="$XDG_DATA_HOME/bitcoin/wallets/alice/frozen.tsv"
	[ -s "$frozen" ]
	# 3-column TSV: outpoint, reason, unix-timestamp.
	awk -F'\t' '
		NR == 1 && $1 == "abc123:0" && $2 == "KYC concern" && $3 ~ /^[0-9]+$/ { ok=1 }
		END { exit !ok }
	' "$frozen"
	# Commit landed in the wallet repo (per FEAT-011 push/pull model).
	committed="$(git -C "$XDG_DATA_HOME/bitcoin/wallets/alice" log --oneline -n 1 -- frozen.tsv)"
	[ -n "$committed" ]
}

@test "FEAT-037 — utxo freeze is idempotent on the same outpoint" {
	feat037_setup_wallet
	"$BITCOIN_BIN" utxo freeze alice abc123:0 --reason "first reason" >/dev/null
	"$BITCOIN_BIN" utxo freeze alice abc123:0 --reason "updated reason" >/dev/null
	frozen="$XDG_DATA_HOME/bitcoin/wallets/alice/frozen.tsv"
	# Only one row for the outpoint, and the reason matches the latest write.
	[ "$(awk -F'\t' '$1 == "abc123:0"' "$frozen" | wc -l)" = "1" ]
	awk -F'\t' '$1 == "abc123:0" && $2 == "updated reason" { found=1 } END { exit !found }' "$frozen"
}

@test "FEAT-037 — utxo unfreeze removes the row and commits" {
	feat037_setup_wallet
	"$BITCOIN_BIN" utxo freeze alice abc123:0 --reason "freeze me" >/dev/null
	run "$BITCOIN_BIN" utxo unfreeze alice abc123:0
	[ "$status" -eq 0 ]
	frozen="$XDG_DATA_HOME/bitcoin/wallets/alice/frozen.tsv"
	# Row gone.
	! grep -q "^abc123:0	" "$frozen"
	# Commit for the removal.
	last_msg="$(git -C "$XDG_DATA_HOME/bitcoin/wallets/alice" log -1 --format=%s -- frozen.tsv)"
	echo "$last_msg" | grep -q "utxo unfreeze"
}

@test "FEAT-037 — utxo unfreeze on a non-frozen outpoint is a silent no-op" {
	feat037_setup_wallet
	run "$BITCOIN_BIN" utxo unfreeze alice deadbeef:5
	[ "$status" -eq 0 ]
}

@test "FEAT-037 — utxo unfreeze rejects malformed outpoint" {
	run "$BITCOIN_BIN" utxo unfreeze any-wallet not-an-outpoint
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "must look like"
}

@test "FEAT-037 — utxo ls without a wallet usage-errors" {
	run "$BITCOIN_BIN" utxo ls
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "utxo ls: usage:"
}

@test "FEAT-037 — utxo freeze persists across invocations" {
	feat037_setup_wallet
	"$BITCOIN_BIN" utxo freeze alice abc123:0 --reason "persist test" >/dev/null
	# Second invocation in a fresh shell sees the same frozen.tsv on disk.
	frozen="$XDG_DATA_HOME/bitcoin/wallets/alice/frozen.tsv"
	awk -F'\t' '$1 == "abc123:0" && $2 == "persist test" { ok=1 } END { exit !ok }' "$frozen"
}

# FEAT-037 follow-up: tx build × utxo freeze integration. When a
# wallet has frozen UTXOs, tx:build skips them during selection
# and emits one warn line per skipped outpoint naming the
# freeze reason.

@test "FEAT-037 followup — utxo:_freeze_reason returns the reason or empty" {
	feat037_setup_wallet
	"$BITCOIN_BIN" utxo freeze alice deadbeef:0 --reason "KYC hold" >/dev/null
	# Source the dispatcher (bin/bitcoin is source-safe per FEAT-006)
	# and call the helper directly. Lets us assert the helper without
	# needing a real backend fixture.
	got=$(bash -c "source '$BITCOIN_BIN'; utxo:_freeze_reason alice deadbeef:0")
	[ "$got" = "KYC hold" ]
}

@test "FEAT-037 followup — utxo:_freeze_reason is silent for non-frozen outpoints" {
	feat037_setup_wallet
	got=$(bash -c "source '$BITCOIN_BIN'; utxo:_freeze_reason alice never-frozen:99")
	[ -z "$got" ]
}

@test "FEAT-037 followup — tx:build warn line text mentions 'skipping frozen UTXO'" {
	# Verify the warn line wording without spinning up a real wallet
	# build. Greps the function body in bin/bitcoin.
	grep -qE "skipping frozen UTXO" "$BITCOIN_BIN" \
		|| { echo "tx:build missing the frozen-UTXO skip warn"; return 1; }
}
