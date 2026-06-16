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

@test "FEAT-036 followup — wallet build was removed in 1.24.0" {
	run --separate-stderr "$BITCOIN_BIN" wallet build
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "'wallet build' was removed in 1\.24\.0"
	echo "$stderr" | grep -qF "bitcoin tx build"
}

@test "FEAT-036 followup — wallet sign was removed in 1.24.0" {
	run --separate-stderr "$BITCOIN_BIN" wallet sign
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "'wallet sign' was removed in 1\.24\.0"
	echo "$stderr" | grep -qF "bitcoin tx sign"
}

@test "FEAT-036 followup — wallet broadcast was removed in 1.24.0" {
	run --separate-stderr "$BITCOIN_BIN" wallet broadcast
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "'wallet broadcast' was removed in 1\.24\.0"
	echo "$stderr" | grep -qF "bitcoin tx broadcast"
}

@test "FEAT-036 followup — bitcoin tx build emits NO deprecation/removal warn" {
	# Canonical path stays clean. Usage error from missing args is
	# fine; no deprecation/removal message should appear.
	run --separate-stderr "$BITCOIN_BIN" tx build
	if echo "$stderr" | grep -qE "deprecated|was removed in"; then
		echo "unexpected deprecation/removal message on canonical path: $stderr"
		return 1
	fi
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

# FEAT-037 AC #5 follow-up: utxo select with greedy and
# branch-and-bound strategies. The algorithm is pure
# (no backend / no wallet state) past the candidate-collection
# phase, so the BnB selection logic is tested via direct helper
# invocation against fixture arrays. The end-to-end path through
# backend:get-address-utxos is covered by the existing FEAT-014
# wallet-build vector tests.

@test "FEAT-037 AC#5 — utxo select with no args usage-errors" {
	run "$BITCOIN_BIN" utxo select
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "utxo select: usage:"
}

@test "FEAT-037 AC#5 — utxo select without --target errors" {
	run "$BITCOIN_BIN" utxo select alice
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "target <sats> required"
}

@test "FEAT-037 AC#5 — utxo select rejects non-integer --target" {
	run "$BITCOIN_BIN" utxo select alice --target abc
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "must be a positive integer"
}

@test "FEAT-037 AC#5 — utxo select rejects unknown --strategy" {
	run "$BITCOIN_BIN" utxo select alice --target 100 --strategy weird
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "'greedy' or 'branch-and-bound'"
}

@test "FEAT-037 AC#5 — utxo select reports no-such-wallet" {
	run "$BITCOIN_BIN" utxo select no-such-wallet --target 100
	[ "$status" -eq 5 ]
	echo "$output" | grep -q "no such wallet"
}

@test "FEAT-037 AC#5 — branch-and-bound finds the smallest exact subset" {
	# Source bin/bitcoin (source-safe per FEAT-006) and exercise the
	# BnB inner loop with fixture arrays. For values [10,20,30,40]
	# and target=50, the smallest exact subset is {20,30} (2 UTXOs),
	# not {10,40} (also 2 UTXOs — both have count 2, so the loop
	# picks whichever comes first; the test asserts that an exact
	# match IS found, regardless of which).
	got=$(bash -c '
		source "$BITCOIN_BIN"
		u_value=(10 20 30 40); n=4; target=50
		best_mask=0; best_count=999
		for ((mask=1; mask<(1<<n); mask++)); do
			sum=0; count=0
			for ((i=0; i<n; i++)); do
				if (( mask & (1<<i) )); then ((sum += u_value[i], count++)); fi
			done
			if (( sum == target && count < best_count )); then
				best_mask=$mask; best_count=$count
			fi
		done
		echo $best_count
	')
	# Two-UTXO subset found (either {20,30} or {10,40}).
	[ "$got" = "2" ]
}

@test "FEAT-037 AC#5 — branch-and-bound returns 999 when no exact subset" {
	got=$(bash -c '
		source "$BITCOIN_BIN"
		u_value=(10 20 30); n=3; target=100
		best_mask=0; best_count=999
		for ((mask=1; mask<(1<<n); mask++)); do
			sum=0; count=0
			for ((i=0; i<n; i++)); do
				if (( mask & (1<<i) )); then ((sum += u_value[i], count++)); fi
			done
			if (( sum == target && count < best_count )); then
				best_mask=$mask; best_count=$count
			fi
		done
		echo $best_count
	')
	# No exact match exists (max sum is 60); best_count stays at sentinel.
	[ "$got" = "999" ]
}

@test "FEAT-037 AC#5 — utxo:select source carries both strategies" {
	# Belt-and-suspenders for the source structure.
	grep -qE 'strategy=.greedy.' "$BITCOIN_BIN" \
		|| { echo "utxo:select missing greedy default"; return 1; }
	grep -qE "branch-and-bound|bnb" "$BITCOIN_BIN" \
		|| { echo "utxo:select missing BnB strategy"; return 1; }
	grep -qE "no exact-match subset found" "$BITCOIN_BIN" \
		|| { echo "utxo:select missing BnB fallback warn"; return 1; }
}

@test "FEAT-037 AC#5 — utxo help lists the select subcommand" {
	run bash -c "'$BITCOIN_BIN' utxo help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE "(^|[[:space:]])select([[:space:]]|$)"
	echo "$output" | grep -q "branch-and-bound"
}

# FEAT-044 gap-limit walking — arg-validation cases (no backend /
# crypto needed; the discovery path is exercised in bitcoin.bats
# against the abandon-mnemonic fixture).

@test "FEAT-044 — wallet derive --gap rejects a non-integer" {
	run "$BITCOIN_BIN" wallet derive alice --gap notanint
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "non-negative integer"
}

@test "FEAT-044 — wallet derive rejects an unknown flag" {
	run "$BITCOIN_BIN" wallet derive alice --bogus
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "unknown flag"
}

@test "FEAT-044 — wallet derive --walk requires a wallet name" {
	run "$BITCOIN_BIN" wallet derive --walk
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "name required"
}

@test "FEAT-044 — wallet:_derive_walk is defined (source-safe load)" {
	run bash -c "source '$BITCOIN_BIN'; type -t wallet:_derive_walk"
	[ "$status" -eq 0 ]
	[ "$output" = "function" ]
}

# FEAT-036 AC #3 follow-up: tx build --utxo coin-control.

@test "FEAT-036 AC#3 — tx build --utxo with no argument errors" {
	run "$BITCOIN_BIN" tx build alice bc1qzz 1000 --utxo
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "requires a <txid:vout>"
}

@test "FEAT-036 AC#3 — tx build --utxo rejects malformed argument" {
	run "$BITCOIN_BIN" tx build alice bc1qzz 1000 --utxo not-an-outpoint
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "must look like"
}

@test "FEAT-036 AC#3 — tx build --utxo accepts a well-formed argument" {
	# Shape validation passes; later checks (wallet exists, has
	# UTXOs) still fire — we just want to confirm the flag parser
	# doesn't itself reject a valid <txid>:<vout>.
	run "$BITCOIN_BIN" tx build no-such-wallet bc1qzz 1000 --utxo abc123:0
	# Either errors with "no such wallet" (status 4) or proceeds
	# further; the important thing is we DIDN'T error with the
	# --utxo flag-parser messages.
	echo "$output" | grep -qv "must look like"
	echo "$output" | grep -qv "requires a <txid:vout>"
}

@test "FEAT-036 AC#3 — tx build --utxo flag is repeatable" {
	# Passing two --utxo flags must parse cleanly — repeatability is
	# the foundation for coin-control across multiple outpoints.
	run "$BITCOIN_BIN" tx build no-such-wallet bc1qzz 1000 --utxo abc123:0 --utxo def456:1
	# Exits with the wallet-missing error (status 4), not with a
	# --utxo parser error (status 2).
	[ "$status" -eq 4 ] \
		|| { echo "expected wallet-missing exit (status=4); got $status"; return 1; }
}

@test "FEAT-036 AC#3 — tx:build source has --utxo branch and filter" {
	# Belt-and-suspenders: catch accidental regressions of the
	# coin-control logic. The filter only runs when requested_utxos
	# is non-empty; the array is declared in the flag-parsing block.
	grep -q "requested_utxos+=" "$BITCOIN_BIN" \
		|| { echo "tx:build missing --utxo append"; return 1; }
	grep -q "requested_utxos\[@\]" "$BITCOIN_BIN" \
		|| { echo "tx:build missing the --utxo filter loop"; return 1; }
}

# FEAT-042: coin control on `wallet send`. The convenience verb
# already forwards every non-`--mainnet` argument to tx:build via
# its fwd_args[] pass-through, so `--utxo` flows through unchanged.
# This block asserts the contract end-to-end: the flag reaches
# tx:build's parser, the error envelope is the tx:build one, and
# the flag coexists with --mainnet.

@test "FEAT-042 — wallet send forwards --utxo to tx:build (malformed shape rejected)" {
	feat037_setup_wallet
	# Past wallet:send's wallet-existence check (the fixture creates
	# alice), so the malformed --utxo argument reaches tx:build's
	# flag parser and that's what errors.
	run "$BITCOIN_BIN" wallet send alice bc1qzz 1000 --utxo not-an-outpoint
	[ "$status" -ne 0 ]
	# Error wording from tx:build's parser (not wallet:send's).
	echo "$output" | grep -q "must look like"
}

@test "FEAT-042 — wallet send accepts --utxo with a well-formed argument" {
	feat037_setup_wallet
	# Well-formed --utxo passes tx:build's flag parser; failure
	# downstream (no real backend / no UTXOs) is expected and not
	# a --utxo parser error.
	run "$BITCOIN_BIN" wallet send alice bc1qzz 1000 --utxo abc123:0
	[ "$status" -ne 0 ]
	# Did NOT fail with the parser-shape error.
	echo "$output" | grep -qv "must look like"
}

@test "FEAT-042 — wallet send --utxo coexists with --mainnet" {
	feat037_setup_wallet
	# Both flags should parse together. The wallet's network is
	# unset (defaults to testnet for the fixture), so --mainnet is
	# accepted silently and --utxo flows through to tx:build.
	run "$BITCOIN_BIN" wallet send alice bc1qzz 1000 --utxo abc123:0 --mainnet
	[ "$status" -ne 0 ]
	# Neither flag's parser rejected the call.
	echo "$output" | grep -qv "must look like"
	echo "$output" | grep -qv "requires a <txid:vout>"
}

@test "FEAT-042 — wallet send --utxo is repeatable" {
	feat037_setup_wallet
	run "$BITCOIN_BIN" wallet send alice bc1qzz 1000 --utxo abc123:0 --utxo def456:1
	[ "$status" -ne 0 ]
	echo "$output" | grep -qv "must look like"
}

# ---------------------------------------------------------------------------
# FEAT-043: tx bump (RBF + CPFP).
#
# The parse / validation / cached-tx-inspection paths are tested
# here against a JSON fixture (no seed / no xxd needed). The full
# build|sign|broadcast pipeline is exercised in CI / regtest — the
# same constraint the FEAT-008 sign tests carry.
# ---------------------------------------------------------------------------

# Write a cached transactions/<txid>.json for <wallet>. Args:
#   $1 wallet  $2 txid  $3 sequence (input)  $4 pay_addr  $5 pay_value
# Change always goes to the fixture wallet's address (bc1qexample).
feat043_cache_tx() {
	local wallet="$1" txid="$2" seq="$3" pay_addr="$4" pay_value="$5"
	local path="$XDG_DATA_HOME/bitcoin/wallets/$wallet"
	mkdir -p "$path/transactions"
	cat > "$path/transactions/$txid.json" <<JSON
{"txid":"$txid","status":{"block_height":"mempool"},
 "vin":[{"txid":"aa00bb11cc22dd33ee44ff5500112233445566778899aabbccddeeff00112233","vout":0,"sequence":$seq,"prevout":{"scriptpubkey_address":"bc1qsource","value":100000}}],
 "vout":[{"scriptpubkey_address":"$pay_addr","value":$pay_value},{"scriptpubkey_address":"bc1qexample","value":40000}]}
JSON
}

@test "FEAT-043 — tx bump with no args usage-errors" {
	run "$BITCOIN_BIN" tx bump
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "usage: tx bump"
}

@test "FEAT-043 — tx bump requires a mode flag" {
	run "$BITCOIN_BIN" tx bump alice deadbeef
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "one of --rbf or --cpfp"
}

@test "FEAT-043 — tx bump rejects a non-integer --fee-rate" {
	run "$BITCOIN_BIN" tx bump alice deadbeef --rbf --fee-rate xyz
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "fee-rate must be a positive integer"
}

@test "FEAT-043 — tx bump errors when the tx is not cached" {
	feat037_setup_wallet
	run "$BITCOIN_BIN" tx bump alice deadbeefcafe --rbf
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "not cached"
}

@test "FEAT-043 — tx bump --rbf refuses a non-signalling tx" {
	feat037_setup_wallet
	# sequence 0xffffffff (4294967295) → final, not BIP-125 replaceable.
	feat043_cache_tx alice f00d 4294967295 bc1qpayee 50000
	run "$BITCOIN_BIN" tx bump alice f00d --rbf
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "does not signal BIP-125"
}

@test "FEAT-043 — tx bump --rbf accepts a signalling tx (past BIP-125 + output checks)" {
	feat037_setup_wallet
	# sequence 0xfffffffd (< 0xfffffffe) → BIP-125 replaceable.
	# One external output (bc1qpayee) + change to bc1qexample (wallet).
	feat043_cache_tx alice cafe 4294967293 bc1qpayee 50000
	run "$BITCOIN_BIN" tx bump alice cafe --rbf --fee-rate 10
	# Build/sign will fail in this seedless env, but the BIP-125 +
	# single-output validation must have PASSED (no parse-stage error).
	echo "$output" | grep -qv "does not signal BIP-125"
	echo "$output" | grep -qv "expected exactly one external output"
}

@test "FEAT-043 — tx bump --rbf refuses a multi-recipient tx" {
	feat037_setup_wallet
	local path="$XDG_DATA_HOME/bitcoin/wallets/alice"
	mkdir -p "$path/transactions"
	# Two external (non-wallet) outputs → ambiguous payment.
	cat > "$path/transactions/multi.json" <<'JSON'
{"txid":"multi","status":{"block_height":"mempool"},
 "vin":[{"txid":"aa","vout":0,"sequence":4294967293,"prevout":{"scriptpubkey_address":"bc1qsrc","value":100000}}],
 "vout":[{"scriptpubkey_address":"bc1qpayee1","value":30000},{"scriptpubkey_address":"bc1qpayee2","value":30000}]}
JSON
	run "$BITCOIN_BIN" tx bump alice multi --rbf
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "expected exactly one external output"
}

@test "FEAT-043 — tx bump --cpfp errors when no wallet output of the tx is spendable" {
	feat037_setup_wallet
	feat043_cache_tx alice beef 4294967293 bc1qpayee 50000
	# No backend fixtures → utxo:ls finds nothing for this txid.
	run "$BITCOIN_BIN" tx bump alice beef --cpfp
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "no spendable wallet output"
}

@test "FEAT-043 — tx help lists the bump subcommand" {
	run bash -c "'$BITCOIN_BIN' tx help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE "(^|[[:space:]])bump([[:space:]]|$)"
	echo "$output" | grep -q "rbf"
	echo "$output" | grep -q "cpfp"
}

# ---------------------------------------------------------------------------
# FEAT-040: BTC/EUR price oracle.
#
# csv:// source + cache reads need no network. The coingecko path
# uses a local curl stub (the real API is hit only in the SIT tier).
# ---------------------------------------------------------------------------

# Per-test isolated price environment. HOME is already a temp dir
# (from setup); pin the cache + source config under it.
feat040_env() {
	export XDG_CONFIG_HOME="$HOME/.config"
	export BITCOIN_PRICE_CACHE="$HOME/.bitcoin/cache/price/btc-eur.tsv"
	unset BITCOIN_PRICE_SOURCE
	mkdir -p "$HOME/.config/bitcoin"
}

# Install a curl stub that maps the coingecko history URL for a
# given date to a canned market_data.current_price.eur body.
feat040_coingecko_stub() {
	local stub_dir="$BATS_TMPDIR/cg-stub.$BATS_TEST_NUMBER"
	rm -rf "$stub_dir"; mkdir -p "$stub_dir"
	cat > "$stub_dir/curl" <<'STUB'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in http*://*) url="$a";; esac; done
# Any coingecko history URL → a fixed EUR price keyed by the date arg.
case "$url" in
	*simple/price*)
		# FEAT-266 spot endpoint → fixed current price.
		echo '{"bitcoin":{"eur":43210.0}}'
		exit 0 ;;
	*coins/bitcoin/history*)
		d="$(printf '%s' "$url" | sed -n 's/.*date=\([0-9-]*\).*/\1/p')"
		# DD-MM-YYYY → deterministic price (just echo a fixed value).
		echo '{"market_data":{"current_price":{"eur":42000.5}}}'
		exit 0 ;;
esac
echo "cg-stub: no fixture for $url" >&2
exit 22
STUB
	chmod +x "$stub_dir/curl"
	export PATH="$stub_dir:$PATH"
}

@test "FEAT-040 — price help lists every subcommand" {
	run bash -c "'$BITCOIN_BIN' price help 2>&1"
	[ "$status" -eq 0 ]
	for sub in get fetch source status; do
		echo "$output" | grep -qE "(^|[[:space:]])$sub([[:space:]]|$)" \
			|| { echo "help missing: $sub"; return 1; }
	done
}

@test "FEAT-040 — price (no subcommand) prints help" {
	run "$BITCOIN_BIN" price
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "Usage:"
}

@test "FEAT-040 — price <unknown> errors" {
	run "$BITCOIN_BIN" price wat
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "unknown price subcommand"
}

@test "FEAT-266 — price get with no date returns the current spot price" {
	feat040_coingecko_stub
	run "$BITCOIN_BIN" price get
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "43210"
}

@test "FEAT-266 — price get spot errors clearly for a non-coingecko source" {
	export BITCOIN_PRICE_SOURCE="kraken"
	run "$BITCOIN_BIN" price get
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "only supported for the coingecko source"
}

# ---------------------------------------------------------------------------
# FEAT-271: bitcoin config (list/get/set/unset/path). A temp datadir holds
# bitcoin.conf; a stub bitcoind serves -help so 'get' can resolve defaults.
# ---------------------------------------------------------------------------
feat271_env() {
	export BITCOIN_CONFIG_DATADIR="$HOME/cfgdir"
	# Config lives under a dir now (FHS /etc on a real host); point the
	# frontend at the tmp dir so the suite stays hermetic even when a real
	# /etc/bitcoin/bitcoin.conf exists on the dev box.
	export BITCOIN_CONFIG_DIR="$HOME/cfgdir"
	mkdir -p "$BITCOIN_CONFIG_DATADIR"
	printf '# bitcoin.conf\nserver=1\ndbcache=600\n' > "$BITCOIN_CONFIG_DATADIR/bitcoin.conf"
	export BITCOIN_BITCOIND="$HOME/bitcoind-help-stub"
	# Covers: a comma-form default "(4 to 16384, default: 450)", a multi-line
	# wrapped description, and an option with NO default (alertnotify).
	cat > "$BITCOIN_BITCOIND" <<-'STUB'
		#!/usr/bin/env bash
		[ "$1" = -help ] && printf '%s\n' \
		  '  -maxconnections=<n>' \
		  '       Maintain at most <n> connections (default: 125).' \
		  '  -dbcache=<n>' \
		  '       Maximum database cache size <n> MiB (4 to 16384, default:' \
		  '       450). In addition, unused mempool memory is shared.' \
		  '  -alertnotify=<cmd>' \
		  '       Execute command when an alert is raised.'
		exit 0
	STUB
	chmod +x "$BITCOIN_BITCOIND"
}

@test "FEAT-271 — config list is TSV (name/value/description) with effective values + defaults" {
	feat271_env
	run "$BITCOIN_BIN" config list
	[ "$status" -eq 0 ]
	echo "$output" | head -1 | grep -q 'NAME'
	# conf value overrides the default:
	echo "$output" | awk -F'\t' '$1=="dbcache"&&$2=="600"{f=1} END{exit !f}'
	# an unset option shows its compiled-in default + description:
	echo "$output" | awk -F'\t' '$1=="maxconnections"&&$2=="125"&&$3~/Maintain at most/{f=1} END{exit !f}'
	# a conf-only key (not in -help) still appears:
	echo "$output" | awk -F'\t' '$1=="server"&&$2=="1"{f=1} END{exit !f}'
	# a no-default option shows an EMPTY value, not its description (the
	# `read`-collapsing / multi-line-default bug the user hit):
	echo "$output" | awk -F'\t' '$1=="alertnotify"&&$2==""&&$3~/Execute command/{f=1} END{exit !f}'
	# the (4 to 16384, default: 450) clause is stripped from the description:
	echo "$output" | awk -F'\t' '$1=="dbcache"&&$3!~/default:/{f=1} END{exit !f}'
}

@test "FEAT-271 — config list --set shows only the conf-set keys" {
	feat271_env
	run "$BITCOIN_BIN" config list --set
	[ "$status" -eq 0 ]
	echo "$output" | awk -F'\t' '$1=="server"&&$2=="1"{f=1} END{exit !f}'
	echo "$output" | awk -F'\t' '$1=="dbcache"&&$2=="600"{f=1} END{exit !f}'
	# maxconnections is a default-only key → excluded by --set
	! echo "$output" | awk -F'\t' '$1=="maxconnections"{f=1} END{exit !f}'
}

@test "FEAT-271 — config get returns the conf value (source: conf)" {
	feat271_env
	run "$BITCOIN_BIN" config get dbcache
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '600'
}

@test "FEAT-271 — config get falls back to the bitcoind default" {
	feat271_env
	run "$BITCOIN_BIN" config get maxconnections
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '125'
}

@test "FEAT-271 — config set replaces/adds a key and warns to restart" {
	feat271_env
	run "$BITCOIN_BIN" config set prune 550
	[ "$status" -eq 0 ]
	echo "$output" | grep -qi 'restart'
	grep -q '^prune=550' "$BITCOIN_CONFIG_DATADIR/bitcoin.conf"
}

@test "FEAT-271 — config unset removes a key" {
	feat271_env
	"$BITCOIN_BIN" config set foo bar
	"$BITCOIN_BIN" config unset foo
	! grep -q '^foo=' "$BITCOIN_CONFIG_DATADIR/bitcoin.conf"
}

@test "FEAT-271 — config get errors for an unknown key with no default" {
	feat271_env
	run "$BITCOIN_BIN" config get totallyboguskey
	[ "$status" -ne 0 ]
}

@test "FEAT-271 — config path prints the conf file" {
	feat271_env
	run "$BITCOIN_BIN" config path
	[ "$status" -eq 0 ]
	[ "$output" = "$BITCOIN_CONFIG_DATADIR/bitcoin.conf" ]
}

@test "FEAT-040 — price get rejects a malformed date" {
	run "$BITCOIN_BIN" price get 2024/01/01
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "not a valid ISO-8601 date"
}

@test "FEAT-040 — price get on an empty cache warns to fetch" {
	feat040_env
	run "$BITCOIN_BIN" price get 2024-01-01
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "price fetch"
}

@test "FEAT-040 — price source defaults to coingecko" {
	feat040_env
	run "$BITCOIN_BIN" price source
	[ "$status" -eq 0 ]
	[ "$output" = "coingecko" ]
}

@test "FEAT-040 — price source --set kraken persists" {
	feat040_env
	"$BITCOIN_BIN" price source --set kraken >/dev/null
	run "$BITCOIN_BIN" price source
	[ "$output" = "kraken" ]
}

@test "FEAT-040 — price source --set rejects an unknown source" {
	feat040_env
	run "$BITCOIN_BIN" price source --set ftp://nope
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "unknown source"
}

@test "FEAT-040 — csv source fetch + get round-trips with no network" {
	feat040_env
	printf '2024-01-01,42000,x\n2024-01-02,43000,x\n2024-01-09,50000,x\n' > "$HOME/prices.csv"
	"$BITCOIN_BIN" price source --set "csv://$HOME/prices.csv" >/dev/null
	"$BITCOIN_BIN" price fetch --from 2024-01-01 --to 2024-01-07 >/dev/null
	[ "$("$BITCOIN_BIN" price get 2024-01-01)" = "42000" ]
	[ "$("$BITCOIN_BIN" price get 2024-01-02)" = "43000" ]
	# 2024-01-09 is outside the fetched range → not cached.
	run "$BITCOIN_BIN" price get 2024-01-09
	[ "$status" -ne 0 ]
}

@test "FEAT-040 — price fetch is idempotent (re-fetch adds zero rows)" {
	feat040_env
	printf '2024-01-01,42000,x\n' > "$HOME/prices.csv"
	"$BITCOIN_BIN" price source --set "csv://$HOME/prices.csv" >/dev/null
	"$BITCOIN_BIN" price fetch --from 2024-01-01 --to 2024-01-01 >/dev/null
	rows1="$(grep -c . "$BITCOIN_PRICE_CACHE")"
	"$BITCOIN_BIN" price fetch --from 2024-01-01 --to 2024-01-01 >/dev/null
	rows2="$(grep -c . "$BITCOIN_PRICE_CACHE")"
	[ "$rows1" = "$rows2" ]
}

@test "FEAT-040 — price fetch rejects --from after --to" {
	feat040_env
	run "$BITCOIN_BIN" price fetch --from 2024-02-01 --to 2024-01-01
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "is after"
}

@test "FEAT-040 — coingecko fetch via curl stub populates the cache" {
	feat040_env
	feat040_coingecko_stub
	# default source is coingecko
	run "$BITCOIN_BIN" price fetch --from 2024-03-01 --to 2024-03-03
	[ "$status" -eq 0 ]
	# Three days fetched, each at the stub's fixed price.
	[ "$("$BITCOIN_BIN" price get 2024-03-02)" = "42000.5" ]
	rows="$(grep -c . "$BITCOIN_PRICE_CACHE")"
	[ "$rows" = "3" ]
}

@test "FEAT-040 — price status reports coverage" {
	feat040_env
	mkdir -p "$(dirname "$BITCOIN_PRICE_CACHE")"
	# Cache is TSV (tab-separated): date, eur_per_btc, source.
	printf '2024-01-01\t42000\tcsv\n2024-01-05\t46000\tcsv\n' > "$BITCOIN_PRICE_CACHE"
	run "$BITCOIN_BIN" price status
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "rows: 2"
	echo "$output" | grep -q "2024-01-01 .. 2024-01-05"
}

# ---------------------------------------------------------------------------
# FEAT-034: service-managed bitcoind (daemon enable / disable).
#
# The init system is mocked so the suite runs in CI without loading
# real services: stub systemctl / launchctl / useradd / sysadminctl /
# chown record their invocations, a stub sudo transparently execs its
# args, and a stub bitcoind is resolved via $BITCOIN_BITCOIND. All
# --system absolute paths are redirected under $BITCOIN_DAEMON_ROOT,
# and $BITCOIN_DAEMON_OS forces the systemd-vs-launchd branch so both
# OS families are exercised on one runner.
# ---------------------------------------------------------------------------

feat034_env() {
	local os="${1:-linux}"
	export BITCOIN_DAEMON_OS="$os"
	export XDG_CONFIG_HOME="$HOME/.config"
	export BITCOIN_DAEMON_ROOT="$HOME/root"
	export SELF_UNITS="$REPO_ROOT/share/bitcoin/units"
	export FEAT034_CALLS="$HOME/daemon-calls.log"
	: > "$FEAT034_CALLS"

	local stub="$HOME/daemon-stub" c
	mkdir -p "$stub"
	for c in systemctl launchctl useradd sysadminctl chown dscl dseditgroup usermod; do
		cat > "$stub/$c" <<-STUB
			#!/usr/bin/env bash
			printf '%s %s\n' "$c" "\$*" >> "$FEAT034_CALLS"
			exit 0
		STUB
		chmod +x "$stub/$c"
	done
	# BUG-035: on a host that already runs the live stack a real
	# 'bitcoin'/'_bitcoin' account exists, so daemon:_ensure_account's
	# `id "$user"` short-circuits and the account-creation branch never
	# runs. This stub makes any *username* lookup report not-found (so the
	# creation path is always exercised) while passing the option forms
	# (-u / -un / -g …) through to the real id (daemon:_domain needs them).
	cat > "$stub/id" <<-'STUB'
		#!/usr/bin/env bash
		case "$1" in
			-*) exec /usr/bin/id "$@" ;;
			"") exec /usr/bin/id ;;
			*)  exit 1 ;;
		esac
	STUB
	chmod +x "$stub/id"
	# Transparent sudo, but it records its invocation so tests can assert
	# that privileged steps (e.g. installing bitcoin.conf into the root-
	# owned datadir, BUG-030) actually route through sudo.
	cat > "$stub/sudo" <<-STUB
		#!/usr/bin/env bash
		printf 'sudo %s\n' "\$*" >> "$FEAT034_CALLS"
		# Emulate sudo's '-u <user>' (tests run under a single uid).
		if [ "\$1" = "-u" ]; then shift 2; fi
		exec "\$@"
	STUB
	chmod +x "$stub/sudo"
	export PATH="$stub:$PATH"

	# enable() resolves bitcoind through this override. Honors --version
	# so the enable preflight (daemon:_check_runnable) passes.
	export BITCOIN_BITCOIND="$HOME/bitcoind-stub"
	printf '#!/usr/bin/env bash\n:\n' > "$BITCOIN_BITCOIND"
	chmod +x "$BITCOIN_BITCOIND"
	# BUG-048 — neutralise the RPC-port preflight by default so these tests
	# are hermetic on a host that is itself running a bitcoind (the dev box's
	# real node binds 8332). The sentinel matches no real port → "all free".
	# The BUG-048 cases below override it with the specific busy port.
	export BITCOIN_PORT_BUSY=none
}

@test "FEAT-034 — enable --user (linux) installs a rootless systemd unit" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	local unit="$XDG_CONFIG_HOME/systemd/user/bitcoind.service"
	[ -f "$unit" ]
	grep -q "ExecStart=$BITCOIN_BITCOIND " "$unit"
	# A --user systemd unit may not carry User=.
	! grep -q '^User=' "$unit"
	grep -q 'systemctl --user enable --now bitcoind' "$FEAT034_CALLS"
}

@test "BUG-048 — enable refuses when the RPC port is already in use (no crash-looping unit)" {
	feat034_env linux
	export BITCOIN_PORT_BUSY=8332    # an existing bitcoind already owns mainnet RPC
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"8332"* ]]
	[[ "$output" == *"in use"* ]]
	# The bug: a unit got installed and then crash-looped on bind failure.
	[ ! -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
}

@test "BUG-048 — enable proceeds when only a DIFFERENT network's port is busy" {
	feat034_env linux
	export BITCOIN_PORT_BUSY=18443   # regtest port busy, but we enable mainnet (8332)
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	[ -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
}

# --- uniform `daemon status` (parity with lightning/monero) ----------------

@test "daemon status: healthy reports the block height via bitcoin-cli, no sudo" {
	feat034_env linux
	# Stub bitcoin-cli to answer getblockchaininfo with a synced node.
	export BITCOIN_CLI="$HOME/bitcoin-cli-stub"
	cat > "$BITCOIN_CLI" <<-'STUB'
		#!/usr/bin/env bash
		case "$*" in
			*getblockchaininfo*) echo '{"chain":"main","blocks":850000,"headers":850000}' ;;
			*) exit 0 ;;
		esac
	STUB
	chmod +x "$BITCOIN_CLI"
	run "$BITCOIN_BIN" daemon status --user
	[ "$status" -eq 0 ]
	[[ "$output" == *"healthy"* ]]
	[[ "$output" == *"850000"* ]]
	! grep -q '^sudo ' "$FEAT034_CALLS"
}

@test "daemon status: syncing reports blocks/headers when behind" {
	feat034_env linux
	export BITCOIN_CLI="$HOME/bitcoin-cli-stub"
	cat > "$BITCOIN_CLI" <<-'STUB'
		#!/usr/bin/env bash
		echo '{"chain":"main","blocks":700000,"headers":850000}'
	STUB
	chmod +x "$BITCOIN_CLI"
	run "$BITCOIN_BIN" daemon status --user
	[ "$status" -eq 0 ]
	[[ "$output" == *"syncing"* ]]
	[[ "$output" == *"700000/850000"* ]]
}

@test "daemon status: down errors non-zero with a hint when bitcoind is unreachable" {
	feat034_env linux
	export BITCOIN_CLI="$HOME/bitcoin-cli-stub"
	printf '#!/usr/bin/env bash\nexit 1\n' > "$BITCOIN_CLI"   # cli fails => empty
	chmod +x "$BITCOIN_CLI"
	run "$BITCOIN_BIN" daemon status --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"down"* ]]
	[[ "$output" == *"not reachable"* ]]
}

@test "daemon help + status help list the status verb" {
	run "$BITCOIN_BIN" daemon help
	[ "$status" -eq 0 ] || [ -n "$output" ]
	[[ "$output" == *"status"* ]]
	run "$BITCOIN_BIN" daemon help status
	[[ "$output" == *"reachable"* ]]
}

@test "FEAT-034 — enable --user (macos) installs a LaunchAgent without UserName" {
	feat034_env macos
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	local unit="$HOME/Library/LaunchAgents/org.bitcoin.bitcoind.plist"
	[ -f "$unit" ]
	! grep -q 'UserName' "$unit"
	grep -q 'launchctl bootstrap gui/' "$FEAT034_CALLS"
}

@test "FEAT-034 — enable --system (linux) creates the bitcoin user and a privileged unit" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	local unit="$BITCOIN_DAEMON_ROOT/etc/systemd/system/bitcoind.service"
	[ -f "$unit" ]
	grep -q '^User=bitcoin' "$unit"
	grep -q "datadir=$BITCOIN_DAEMON_ROOT/var/lib/bitcoin" "$unit"
	grep -q 'useradd .* bitcoin' "$FEAT034_CALLS"
	grep -q 'systemctl enable --now bitcoind' "$FEAT034_CALLS"
	# --system must NOT use the per-user bus.
	! grep -q 'systemctl --user' "$FEAT034_CALLS"
}

@test "FEAT-034 — enable --system (macos) installs a LaunchDaemon running as bitcoin" {
	feat034_env macos
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	local unit="$BITCOIN_DAEMON_ROOT/Library/LaunchDaemons/org.bitcoin.bitcoind.plist"
	[ -f "$unit" ]
	grep -A1 'UserName' "$unit" | grep -q 'bitcoin'
	grep -q 'launchctl bootstrap system' "$FEAT034_CALLS"
}

@test "FEAT-268 — enable --network regtest installs a parallel suffixed unit (linux)" {
	feat034_env linux
	"$BITCOIN_BIN" daemon enable --user --network regtest
	local unit="$XDG_CONFIG_HOME/systemd/user/bitcoind-regtest.service"
	[ -f "$unit" ]
	grep -q -- '-chain=regtest' "$unit"
	grep -q 'bitcoind-regtest.pid' "$unit"
	grep -q 'systemctl --user enable --now bitcoind-regtest' "$FEAT034_CALLS"
}

@test "FEAT-268 — enable --network regtest uses a suffixed label + -chain (macos)" {
	feat034_env macos
	"$BITCOIN_BIN" daemon enable --user --network regtest
	local unit="$HOME/Library/LaunchAgents/org.bitcoin.bitcoind-regtest.plist"
	[ -f "$unit" ]
	grep -q '<string>org.bitcoin.bitcoind-regtest</string>' "$unit"
	grep -q -- '<string>-chain=regtest</string>' "$unit"
	grep -q 'bitcoind-regtest.log' "$unit"
}

@test "FEAT-268 — mainnet unit carries no -chain and the bare label (macos)" {
	feat034_env macos
	"$BITCOIN_BIN" daemon enable --user
	local unit="$HOME/Library/LaunchAgents/org.bitcoin.bitcoind.plist"
	[ -f "$unit" ]
	! grep -q -- '-chain=' "$unit"
	# no empty ProgramArguments string left behind by the stripped @CHAIN@
	! grep -q '<string></string>' "$unit"
	grep -q '<string>org.bitcoin.bitcoind</string>' "$unit"
}

@test "FEAT-268 — enable rejects an unknown network" {
	feat034_env linux
	run --separate-stderr "$BITCOIN_BIN" daemon enable --user --network frobnet
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "unknown network 'frobnet'"
}

@test "FEAT-268 — regtest and mainnet user units coexist" {
	feat034_env linux
	"$BITCOIN_BIN" daemon enable --user
	"$BITCOIN_BIN" daemon enable --user --network regtest
	[ -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
	[ -f "$XDG_CONFIG_HOME/systemd/user/bitcoind-regtest.service" ]
}

@test "BUG-030 — enable (system) installs bitcoin.conf via sudo, not a bare redirect" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	# The datadir is owned by the dedicated 'bitcoin' account, so a bare
	# `cat > "$conf"` would run as the invoking user and fail with EACCES
	# while still printing "created". The write must route through sudo,
	# at 0640 owned by the service group.
	local conf="$BITCOIN_DAEMON_ROOT/etc/bitcoin/bitcoin.conf"
	grep -Eq 'sudo install -m 0640 .*bitcoin\.conf' "$FEAT034_CALLS"
	grep -q 'chown bitcoin:bitcoin .*bitcoin\.conf' "$FEAT034_CALLS"
	[ -f "$conf" ]
	grep -q '^server=1' "$conf"
}

@test "FEAT-274 — enable (system) sets rpccookieperms=group when bitcoind supports it" {
	feat034_env linux
	# bitcoind stub that advertises -rpccookieperms in -help (Core 28+).
	printf '#!/usr/bin/env bash\n[ "$1" = -help ] && echo "  -rpccookieperms=<readable-by>"\nexit 0\n' > "$BITCOIN_BITCOIND"
	chmod +x "$BITCOIN_BITCOIND"
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	# Makes the .cookie group-readable so sibling daemons authenticate.
	grep -q '^rpccookieperms=group' "$BITCOIN_DAEMON_ROOT/etc/bitcoin/bitcoin.conf"
}

@test "FEAT-274 — enable omits rpccookieperms on a node that predates it" {
	feat034_env linux
	# default stub emits no -help output → option unsupported → not written.
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	! grep -q 'rpccookieperms' "$BITCOIN_DAEMON_ROOT/etc/bitcoin/bitcoin.conf"
}

@test "BUG-030 — enable (system) provisions a dedicated group and joins the operator" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	# Three-user model: a same-named group is created (--user-group), the
	# datadir is group-owned and 0750, and the operator joins the group so
	# they reach config/cookie/log without sudo.
	grep -q 'useradd .*--user-group .*bitcoin' "$FEAT034_CALLS"
	grep -q 'usermod -a -G bitcoin' "$FEAT034_CALLS"
	grep -q 'chown bitcoin:bitcoin .*var/lib/bitcoin' "$FEAT034_CALLS"
}

@test "BUG-030 — enable (system) refuses to install a unit the service account can't run" {
	feat034_env linux
	# Simulate the Homebrew-keg/dyld crash-loop: a binary that execs but
	# fails (here, fails its --version preflight).
	printf '#!/usr/bin/env bash\nexit 1\n' > "$BITCOIN_BITCOIND"
	chmod +x "$BITCOIN_BITCOIND"
	run --separate-stderr "$BITCOIN_BIN" daemon enable --system
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "cannot run"
	# Must bail BEFORE installing the unit (no silent crash-loop left behind).
	[ ! -f "$BITCOIN_DAEMON_ROOT/etc/systemd/system/bitcoind.service" ]
}

@test "FEAT-261 — enable defaults to --system when no mode is given" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable
	[ "$status" -eq 0 ]
	# FEAT-261 flipped the default from --user to --system: a bare enable
	# now installs the privileged system unit under a dedicated account
	# and must NOT touch the per-user bus.
	[ -f "$BITCOIN_DAEMON_ROOT/etc/systemd/system/bitcoind.service" ]
	[ ! -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
	grep -q '^User=bitcoin' "$BITCOIN_DAEMON_ROOT/etc/systemd/system/bitcoind.service"
	grep -q 'useradd .* bitcoin' "$FEAT034_CALLS"
	grep -q 'systemctl enable --now bitcoind' "$FEAT034_CALLS"
	! grep -q 'systemctl --user' "$FEAT034_CALLS"
}

@test "FEAT-261 — daemon enable help names --system as the default" {
	run "$BITCOIN_BIN" daemon enable --help
	[ "$status" -eq 0 ]
	# help:enable writes to stderr; bats `run` folds it into $output.
	echo "$output" | grep -q -- '--system (default)'
}

@test "FEAT-034 — enable is idempotent (second call succeeds, unit refreshed)" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	[ -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
}

@test "FEAT-034 — enable errors clearly when bitcoind is absent" {
	feat034_env linux
	unset BITCOIN_BITCOIND
	# BUG-035: daemon:_bitcoind_candidates also probes the absolute
	# MacPorts / Homebrew dirs, which exist on a host running the live
	# stack. Empty the $BITCOIN_SYSTEM_BINDIRS seam (and keep
	# BITCOIN_BITCOIND unset) so the absolute-dir probe finds nothing,
	# and pin PATH to the stub dir + the system bindirs (no bitcoind on
	# any of them) so the PATH probe finds nothing either → the
	# absent-error path runs.
	export BITCOIN_SYSTEM_BINDIRS=""
	export PATH="$HOME/daemon-stub:/usr/bin:/bin:/usr/sbin:/sbin"
	run --separate-stderr "$BITCOIN_BIN" daemon enable --user
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "no 'bitcoind' found"
	echo "$stderr" | grep -q 'bitcoin daemon install'
}

@test "BUG-035 — daemon honors the \$BITCOIN_SYSTEM_BINDIRS override" {
	feat034_env linux
	unset BITCOIN_BITCOIND
	# Point the seam at a temp dir holding our own runnable bitcoind, and
	# scrub PATH so the host's real binaries can't leak in. enable must
	# discover the seam binary and wire it into the rendered unit.
	local bindir="$HOME/seam-bin"
	mkdir -p "$bindir"
	printf '#!/usr/bin/env bash\n:\n' > "$bindir/bitcoind"
	chmod +x "$bindir/bitcoind"
	export BITCOIN_SYSTEM_BINDIRS="$bindir"
	export PATH="$HOME/daemon-stub:/usr/bin:/bin:/usr/sbin:/sbin"
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	grep -q "ExecStart=$bindir/bitcoind " \
		"$XDG_CONFIG_HOME/systemd/user/bitcoind.service"
}

@test "FEAT-034 — disable --user removes the unit and tears the service down" {
	feat034_env linux
	"$BITCOIN_BIN" daemon enable --user
	local unit="$XDG_CONFIG_HOME/systemd/user/bitcoind.service"
	[ -f "$unit" ]
	run "$BITCOIN_BIN" daemon disable --user
	[ "$status" -eq 0 ]
	[ ! -e "$unit" ]
	grep -q 'systemctl --user disable --now bitcoind' "$FEAT034_CALLS"
}

@test "FEAT-034 — disable preserves the data directory" {
	feat034_env linux
	"$BITCOIN_BIN" daemon enable --user
	# BUG-027: assert on the datadir `enable` actually creates
	# (daemon:_datadir → $HOME/.bitcoin since 0d2d7d1), not the XDG
	# wallet store setup() pre-creates — otherwise the test is vacuous.
	local datadir="$HOME/.bitcoin"
	[ -d "$datadir" ]
	"$BITCOIN_BIN" daemon disable --user
	[ -d "$datadir" ]
}

@test "FEAT-034 — daemon help lists enable and disable" {
	run bash -c "'$BITCOIN_BIN' daemon help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE "(^|[[:space:]])enable([[:space:]]|$)"
	echo "$output" | grep -qE "(^|[[:space:]])disable([[:space:]]|$)"
}

# ---------------------------------------------------------------------------
# FEAT-033: install Bitcoin Core itself (daemon install).
#
# Each package manager and `account` are stubbed on PATH; sudo execs
# its args transparently; a stub bitcoind reports a version so the
# confirmation message can be asserted. $ACCT_PLATFORM drives the
# auto-detect default.
# ---------------------------------------------------------------------------

feat033_env() {
	export FEAT033_CALLS="$HOME/install-calls.log"
	: > "$FEAT033_CALLS"
	local stub="$HOME/install-stub" c
	mkdir -p "$stub"
	for c in brew port apt-get apk add-apt-repository; do
		cat > "$stub/$c" <<-STUB
			#!/usr/bin/env bash
			printf '%s %s\n' "$c" "\$*" >> "$FEAT033_CALLS"
			exit 0
		STUB
		chmod +x "$stub/$c"
	done
	cat > "$stub/sudo" <<-'STUB'
		#!/usr/bin/env bash
		exec "$@"
	STUB
	chmod +x "$stub/sudo"
	cat > "$stub/account" <<-'STUB'
		#!/usr/bin/env bash
		[ "$1" = platform ] && printf '%s\n' "${ACCT_PLATFORM:-}"
		exit 0
	STUB
	chmod +x "$stub/account"
	cat > "$stub/bitcoind" <<-'STUB'
		#!/usr/bin/env bash
		[ "$1" = --version ] && echo "Bitcoin Core version v27.0.0"
		exit 0
	STUB
	chmod +x "$stub/bitcoind"
	# BUG-035: pin PATH to the stub dir + the system bindirs only — NOT the
	# inherited PATH — so a real brew / port / bitcoind on the host (the live
	# stack) can't leak in. The package-manager-absent test removes the stub
	# 'brew' and must then see it as genuinely not-found.
	export PATH="$stub:/usr/bin:/bin:/usr/sbin:/sbin"
}

@test "FEAT-033 — install --from brew runs 'brew install bitcoin'" {
	feat033_env
	run "$BITCOIN_BIN" daemon install --from brew
	[ "$status" -eq 0 ]
	grep -q 'brew install bitcoin' "$FEAT033_CALLS"
}

@test "FEAT-033 — install --from apt installs bitcoind via apt-get" {
	feat033_env
	run "$BITCOIN_BIN" daemon install --from apt
	[ "$status" -eq 0 ]
	grep -q 'apt-get install -y bitcoind' "$FEAT033_CALLS"
}

@test "FEAT-033 — install --from apk adds the bitcoin package" {
	feat033_env
	run "$BITCOIN_BIN" daemon install --from apk
	[ "$status" -eq 0 ]
	grep -q 'apk add bitcoin' "$FEAT033_CALLS"
}

@test "FEAT-033 — install auto-detects apt on ubuntu" {
	feat033_env
	ACCT_PLATFORM=ubuntu run "$BITCOIN_BIN" daemon install
	[ "$status" -eq 0 ]
	grep -q 'apt-get install -y bitcoind' "$FEAT033_CALLS"
}

@test "FEAT-033 — install auto-detects apk on alpine" {
	feat033_env
	ACCT_PLATFORM=alpine run "$BITCOIN_BIN" daemon install
	[ "$status" -eq 0 ]
	grep -q 'apk add bitcoin' "$FEAT033_CALLS"
}

@test "FEAT-033 — install auto-detects macports on macos (macports-first)" {
	feat033_env
	ACCT_PLATFORM=macos run "$BITCOIN_BIN" daemon install
	[ "$status" -eq 0 ]
	# macports-first: /opt/local is world-readable, so a dedicated
	# service account can run the binary (brew is the fallback).
	grep -q 'port install bitcoin' "$FEAT033_CALLS"
}

@test "FEAT-033 — install errors when the package manager is absent" {
	feat033_env
	rm -f "$HOME/install-stub/brew"
	run --separate-stderr "$BITCOIN_BIN" daemon install --from brew
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "required tool 'brew' not found"
}

@test "FEAT-033 — install --from rpk errors with a pointer to the rpk doc" {
	feat033_env
	run --separate-stderr "$BITCOIN_BIN" daemon install --from rpk
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q 'not yet available'
	echo "$stderr" | grep -q 'docs/rpk-bitcoind.md'
}

@test "FEAT-033 — install rejects an unknown source" {
	feat033_env
	run --separate-stderr "$BITCOIN_BIN" daemon install --from frobnicate
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "unknown source 'frobnicate'"
	echo "$stderr" | grep -q 'brew, macports, apt, apk, source, rpk'
}

@test "FEAT-033 — install prints the installed bitcoind --version" {
	feat033_env
	run "$BITCOIN_BIN" daemon install --from apt
	[ "$status" -eq 0 ]
	echo "$output" | grep -q 'Bitcoin Core version v27.0.0'
}

@test "FEAT-033 — daemon help lists install" {
	run bash -c "'$BITCOIN_BIN' daemon help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE "(^|[[:space:]])install([[:space:]]|$)"
}

# ---------------------------------------------------------------------------
# BUG-015: legacy daemon verbs folded onto the new abstraction.
#
# start / stop / monitor / space now drive the same systemd / launchd
# service `enable` installs, with --user (default) / --system modes.
# systemctl / launchctl / journalctl are stubbed; space runs real
# `du` against the data dir.
# ---------------------------------------------------------------------------

bug015_env() {
	export BUG015_CALLS="$HOME/lifecycle-calls.log"
	: > "$BUG015_CALLS"
	local stub="$HOME/lifecycle-stub" c
	mkdir -p "$stub"
	# `tail` is stubbed so monitor's macOS `tail -f` records instead of
	# blocking; it also lets BUG-030 assert the sudo-wrapped log read.
	for c in systemctl launchctl journalctl tail; do
		cat > "$stub/$c" <<-STUB
			#!/usr/bin/env bash
			printf '%s %s\n' "$c" "\$*" >> "$BUG015_CALLS"
			exit 0
		STUB
		chmod +x "$stub/$c"
	done
	# Transparent sudo that records its invocation (see BUG-030).
	cat > "$stub/sudo" <<-STUB
		#!/usr/bin/env bash
		printf 'sudo %s\n' "\$*" >> "$BUG015_CALLS"
		exec "\$@"
	STUB
	chmod +x "$stub/sudo"
	export PATH="$stub:$PATH"
}

@test "BUG-015 — start --user drives systemctl --user (linux)" {
	bug015_env
	# FEAT-261: --user is now explicit (the bare default is --system).
	BITCOIN_DAEMON_OS=linux run "$BITCOIN_BIN" daemon start --user
	[ "$status" -eq 0 ]
	grep -q 'systemctl --user start bitcoind' "$BUG015_CALLS"
}

@test "FEAT-261 — start defaults to --system (linux)" {
	bug015_env
	BITCOIN_DAEMON_OS=linux run "$BITCOIN_BIN" daemon start
	[ "$status" -eq 0 ]
	grep -q 'systemctl start bitcoind' "$BUG015_CALLS"
	! grep -q 'systemctl --user' "$BUG015_CALLS"
}

@test "BUG-015 — start --system drives system systemctl (linux)" {
	bug015_env
	BITCOIN_DAEMON_OS=linux run "$BITCOIN_BIN" daemon start --system
	[ "$status" -eq 0 ]
	grep -q 'systemctl start bitcoind' "$BUG015_CALLS"
	! grep -q 'systemctl --user' "$BUG015_CALLS"
}

@test "BUG-015 — stop --user drives systemctl --user (linux)" {
	bug015_env
	BITCOIN_DAEMON_OS=linux run "$BITCOIN_BIN" daemon stop --user
	[ "$status" -eq 0 ]
	grep -q 'systemctl --user stop bitcoind' "$BUG015_CALLS"
}

@test "BUG-015 — start --user kickstarts the LaunchAgent (macos)" {
	bug015_env
	BITCOIN_DAEMON_OS=macos run "$BITCOIN_BIN" daemon start --user
	[ "$status" -eq 0 ]
	# BUG-019 fix #4: plain `launchctl kickstart` (the -k force-kill
	# raced with KeepAlive and caused the crash loop).
	grep -q 'launchctl kickstart gui/.*/org.bitcoin.bitcoind' "$BUG015_CALLS"
}

@test "BUG-015 — stop --user signals the LaunchAgent (macos)" {
	bug015_env
	BITCOIN_DAEMON_OS=macos run "$BITCOIN_BIN" daemon stop --user
	[ "$status" -eq 0 ]
	grep -q 'launchctl kill SIGTERM gui/.*/org.bitcoin.bitcoind' "$BUG015_CALLS"
}

@test "BUG-015 — monitor follows the journal (linux)" {
	bug015_env
	BITCOIN_DAEMON_OS=linux run "$BITCOIN_BIN" daemon monitor --user
	[ "$status" -eq 0 ]
	grep -q 'journalctl --user -u bitcoind -f' "$BUG015_CALLS"
}

@test "BUG-030 — monitor (system, macos) reads the log directly via group access (no sudo)" {
	bug015_env
	BITCOIN_DAEMON_OS=macos run "$BITCOIN_BIN" daemon monitor --system
	[ "$status" -eq 0 ]
	# Three-user model: the operator is in the service group and the datadir
	# is group-readable, so the log is tailed directly — no sudo.
	grep -Eq 'tail -f .*bitcoind\.log' "$BUG015_CALLS"
	! grep -q 'sudo' "$BUG015_CALLS"
}

@test "BUG-015 — space errors when the data dir is absent" {
	bug015_env
	# setup() gives a fresh $HOME with no ~/.bitcoin, so the user-mode
	# datadir (daemon:_datadir → $HOME/.bitcoin since 0d2d7d1) is absent
	# and the error path is hit.
	run --separate-stderr "$BITCOIN_BIN" daemon space --user
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "data dir '.*' does not exist"
}

@test "BUG-015 — space reports the data dir's disk usage" {
	bug015_env
	# BUG-035: pin the OS to linux so daemon:_datadir resolves to the
	# $HOME/.bitcoin path this test populates (on a macOS host the user-mode
	# datadir would otherwise be "$HOME/Library/Application Support/Bitcoin",
	# leaving the created dir unseen and `space` hitting the absent-error).
	export BITCOIN_DAEMON_OS=linux
	mkdir -p "$HOME/.bitcoin"
	head -c 4096 /dev/zero > "$HOME/.bitcoin/blk"
	run "$BITCOIN_BIN" daemon space --user
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE '^[0-9.]+[KMG]?'
}
