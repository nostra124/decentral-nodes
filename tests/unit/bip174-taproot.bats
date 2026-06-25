#!/usr/bin/env bats
#
# FEAT-008 AC 4 — BIP-371 PSBT Taproot key-path signing.
#
# Composes the 1.26.0 BIP-340 / BIP-341 crypto onto the existing
# bip174 PSBT pipeline: detect 5120 scriptPubKey, compute TapSighash,
# tweak the privkey, schnorr-sign, emit PSBT_IN_TAP_KEY_SIG (0x13).
# Finalize collapses that to a single-element FINAL_SCRIPTWITNESS.
#
# These cases are slow on the affine engine (~1 minute per Taproot
# sign) — kept to one comprehensive end-to-end test plus a couple of
# fast decoder / finaliser checks.

bats_require_minimum_version 1.5.0

setup() {
	BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
	HOME="$(mktemp -d "$BATS_TMPDIR/home.XXXXXX")"
	unset XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME
	export HOME SELF_QUIET=1
	export BITCOIN_BIN="$BATS_TEST_DIRNAME/../../bin/bitcoin-node"
	export SELF_LIBEXEC="$BATS_TEST_DIRNAME/../../libexec"

	# Known test vector: sk = 3, internal x = 3G.x, output key = TapTweak(3G.x).
	SK=0000000000000000000000000000000000000000000000000000000000000003
	# These are cross-checked in tests/unit/bip340.bats and bip341.bats.
	INTERNAL_X=F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9
	OUTPUT_X=418C46636D9E1A683F58E35B42336E776FDCC3B2D4E39E7A0BF1AB0716E3C5FA

	# Build a minimal Taproot-spending PSBT by hand.
	# unsigned tx (version 2, 1 input → 1 P2WPKH output, locktime 0):
	#   02000000 01 <prev_txid:32 zeros><prev_vout:00000000><ss_len:00><seq:ffffffff>
	#     01 <amount:a086010000000000=100000> <spk_len:16> <0014 + 20 zeros> <locktime:00000000>
	UTX="02000000010000000000000000000000000000000000000000000000000000000000000000000000000000ffffffff01a0860100000000001600140000000000000000000000000000000000000000ffffffff" # invalid trailing? recompute
	# Compute fresh + correct
	UTX_HEX="$(
	  printf '02000000'        # version 2 LE
	  printf '01'              # 1 input
	  printf '0000000000000000000000000000000000000000000000000000000000000000'  # prev_txid
	  printf '00000000'        # prev_vout
	  printf '00'              # ss_len
	  printf 'ffffffff'        # sequence
	  printf '01'              # 1 output
	  printf 'a086010000000000'  # 100000 sats LE
	  printf '16'              # spk len = 22
	  printf '00140000000000000000000000000000000000000000'  # P2WPKH(zero hash)
	  printf '00000000'        # locktime
	)"

	# WITNESS_UTXO value = amount(8 LE) || varint(spk_len) || spk
	#   spk = 5120 || output_key (32 B) = 34 B → varint 22
	WU_VALUE="a086010000000000225120${OUTPUT_X,,}"

	# Global section: PSBT_GLOBAL_UNSIGNED_TX (type 0) with the tx above.
	#   record = varint(keylen=1) || key(00) || varint(vallen) || value
	UTX_LEN_BYTES=$(( ${#UTX_HEX} / 2 ))
	# varint for UTX_LEN_BYTES; this tx is ~85 bytes < 0xfd so single byte
	UTX_LEN_VINT="$(printf '%02x' "$UTX_LEN_BYTES")"
	GLOBAL_REC="0100${UTX_LEN_VINT}${UTX_HEX}"
	GLOBAL_SEC="${GLOBAL_REC}00"

	# Input section: one PSBT_IN_WITNESS_UTXO (type 0x01) record.
	WU_LEN_BYTES=$(( ${#WU_VALUE} / 2 ))    # = 43 → 2b
	WU_LEN_VINT="$(printf '%02x' "$WU_LEN_BYTES")"
	IN_REC="0101${WU_LEN_VINT}${WU_VALUE}"
	IN_SEC="${IN_REC}00"

	# Output section: just the terminator.
	OUT_SEC="00"

	PSBT="70736274ff${GLOBAL_SEC}${IN_SEC}${OUT_SEC}"
}
teardown() { rm -rf "$HOME"; }

@test "FEAT-008 AC4 — psbt sign on a Taproot input adds PSBT_IN_TAP_KEY_SIG (type 0x13)" {
	run bash -c "printf '%s' '$PSBT' | '$BITCOIN_BIN' bip174 sign '$SK'"
	[ "$status" -eq 0 ]
	signed="$output"
	run bash -c "printf '%s' '$signed' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	# A type=13 record must appear in section=1 (per-input section).
	[[ "$output" == *"section=1	type=13"* ]]
	# The value should be a 64-byte (128 hex) Schnorr sig.
	sig_val=$(echo "$output" | awk -F'\t' '/section=1\ttype=13/ {sub("^value=","",$4); print $4; exit}')
	[ "${#sig_val}" -eq 128 ]
}

@test "FEAT-008 AC4 — Taproot sig verifies under bip340 with the recomputed TapSighash" {
	signed="$(printf '%s' "$PSBT" | "$BITCOIN_BIN" bip174 sign "$SK")"
	dec="$(printf '%s' "$signed" | "$BITCOIN_BIN" bip174 decode)"
	sig=$(echo "$dec" | awk -F'\t' '/section=1\ttype=13/ {sub("^value=","",$4); print $4; exit}')
	tx_hex=$(echo "$dec" | head -1 | sed 's/.*value=//')
	# Recompute TapSighash via the plugin's internal helper (source-safe).
	export SELF_LIBEXEC
	export SELF_DEBUG=""
	sighash="$(bash -c '
		source "'"$SELF_LIBEXEC"'/bitcoin/bip174"
		psbt:_bip341_sighash "'"$tx_hex"'" 0 \
			"a086010000000000" \
			"225120'"${OUTPUT_X,,}"'" \
			"00"
	')"
	# The sig must verify under the OUTPUT (tweaked) x-only key.
	run "$BITCOIN_BIN" bip340 verify "$OUTPUT_X" "$sighash" "$sig"
	[ "$status" -eq 0 ]
	[ "$output" = "TRUE" ]
}

@test "FEAT-008 AC4 — finalize promotes TAP_KEY_SIG to FINAL_SCRIPTWITNESS (one-element stack)" {
	signed="$(printf '%s' "$PSBT" | "$BITCOIN_BIN" bip174 sign "$SK")"
	final="$(printf '%s' "$signed" | "$BITCOIN_BIN" bip174 finalize)"
	dec="$(printf '%s' "$final" | "$BITCOIN_BIN" bip174 decode)"
	# FINAL_SCRIPTWITNESS = type 0x08. PSBT_IN_TAP_KEY_SIG should be stripped.
	[[ "$dec" == *"section=1	type=08"* ]]
	! [[ "$dec" == *"section=1	type=13"* ]]
	# Witness stack: varint(1) || varint(64) || 64-byte sig → starts "0140"
	# then the sig. Total 130 hex characters.
	wsv=$(echo "$dec" | awk -F'\t' '/section=1\ttype=08/ {sub("^value=","",$4); print $4; exit}')
	[[ "$wsv" =~ ^0140[0-9a-fA-F]{128}$ ]]
}

@test "FEAT-008 AC4 — extract emits a segwit raw tx with the Taproot witness" {
	signed="$(printf '%s' "$PSBT" | "$BITCOIN_BIN" bip174 sign "$SK")"
	final="$(printf '%s' "$signed" | "$BITCOIN_BIN" bip174 finalize)"
	run bash -c "printf '%s' '$final' | '$BITCOIN_BIN' bip174 extract"
	[ "$status" -eq 0 ]
	raw="$output"
	# Marker+flag (00 01) after version, witness count 01, sig length 40, sig bytes,
	# locktime at the end. Easiest check: the produced output_key sig from the
	# decoded PSBT must appear inside the raw tx hex.
	dec="$(printf '%s' "$signed" | "$BITCOIN_BIN" bip174 decode)"
	sig=$(echo "$dec" | awk -F'\t' '/section=1\ttype=13/ {sub("^value=","",$4); print $4; exit}')
	[[ "${raw,,}" == *"${sig,,}"* ]]
}

@test "FEAT-008 AC4 — psbt sign with a key that doesn't match the Taproot output is a no-op" {
	# A different privkey (sk=2) should not match output_key for sk=3.
	wrong=0000000000000000000000000000000000000000000000000000000000000002
	run bash -c "printf '%s' '$PSBT' | '$BITCOIN_BIN' bip174 sign '$wrong'"
	[ "$status" -eq 0 ]
	# Output must be byte-identical to the input PSBT (no records added).
	[ "${output,,}" = "${PSBT,,}" ]
}
