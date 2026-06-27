#!/usr/bin/env bash
# Shared unit-test helpers (FEAT-050).
#
# Fixture well-formedness checks for the hand-crafted PSBT/tx hex literals
# in the bats suite. BUG-021 shipped a PSBT whose global unsigned-tx record
# declared 82 bytes but carried 83 — the parser honoured the length prefix
# and the stray byte desynced every later section, so `sign` silently
# produced nothing. These helpers catch that class at authoring time by
# (a) walking the PSBT record structure and (b) parsing the embedded
# unsigned tx and checking its real length equals the declared one.

# Normalise a hex literal: drop whitespace, lowercase.
hex_clean() { printf '%s' "$1" | tr -d ' \t\n' | tr 'A-F' 'a-f'; }

# Byte length of a hex string (after cleaning).
hex_byte_len() { local h; h="$(hex_clean "$1")"; echo $(( ${#h} / 2 )); }
psbt_byte_len() { hex_byte_len "$1"; }

# _hx_cs <hex> <nibble-offset> <total-nibbles>
# Read a Bitcoin compactSize; sets _cs_val (value) and _cs_end (next
# nibble offset). Returns 1 on overrun or the unsupported 8-byte form.
_hx_cs() {
	local hex=$1 p=$2 n=$3 b
	(( p + 2 > n )) && return 1
	b=$(( 16#${hex:p:2} )); p=$(( p + 2 ))
	if   (( b < 0xfd )); then _cs_val=$b
	elif (( b == 0xfd )); then (( p + 4 > n )) && return 1; _cs_val=$(( 16#${hex:p+2:2}${hex:p:2} )); p=$(( p + 4 ))
	elif (( b == 0xfe )); then (( p + 8 > n )) && return 1; _cs_val=$(( 16#${hex:p+6:2}${hex:p+4:2}${hex:p+2:2}${hex:p:2} )); p=$(( p + 8 ))
	else return 1
	fi
	_cs_end=$p
}

# tx_byte_len <txhex>
# Parse one legacy (non-witness) Bitcoin transaction from the start and
# echo its exact serialized byte length. Echoes nothing and returns 1 if
# the bytes don't form a complete tx (overrun) — that mismatch is the
# BUG-021 signal when run against a length-bounded PSBT value.
tx_byte_len() {
	local hex; hex="$(hex_clean "$1")"
	local n=${#hex} p=0 i cnt slen
	(( p + 8 > n )) && return 1; p=$(( p + 8 ))          # version (4)
	_hx_cs "$hex" "$p" "$n" || return 1; cnt=$_cs_val; p=$_cs_end   # vin count
	for (( i = 0; i < cnt; i++ )); do
		(( p + 72 > n )) && return 1; p=$(( p + 72 ))   # prevout txid(32)+vout(4)
		_hx_cs "$hex" "$p" "$n" || return 1; slen=$_cs_val; p=$_cs_end
		(( p + slen*2 > n )) && return 1; p=$(( p + slen*2 ))   # scriptSig
		(( p + 8 > n )) && return 1; p=$(( p + 8 ))     # sequence (4)
	done
	_hx_cs "$hex" "$p" "$n" || return 1; cnt=$_cs_val; p=$_cs_end   # vout count
	for (( i = 0; i < cnt; i++ )); do
		(( p + 16 > n )) && return 1; p=$(( p + 16 ))   # value (8)
		_hx_cs "$hex" "$p" "$n" || return 1; slen=$_cs_val; p=$_cs_end
		(( p + slen*2 > n )) && return 1; p=$(( p + slen*2 ))   # scriptPubKey
	done
	(( p + 8 > n )) && return 1; p=$(( p + 8 ))         # locktime (4)
	echo $(( p / 2 ))
}

# assert_psbt_wellformed <hex>
#
# Walk a PSBT as magic (70736274ff) + a sequence of key/value records and
# 0x00 map separators (compactSize lengths). Additionally, the global
# unsigned-tx record (key type 0x00) must contain a transaction whose real
# serialized length equals the record's declared length — the exact
# off-by-one BUG-021 shipped. Fails on any overrun, unclean end, or
# declared-vs-actual tx-length mismatch.
assert_psbt_wellformed() {
	local hex; hex="$(hex_clean "$1")"
	local n=${#hex}

	case "$hex" in
		70736274ff*) ;;
		*) echo "assert_psbt_wellformed: missing PSBT magic (70736274ff)"; return 1 ;;
	esac
	(( n % 2 == 0 )) || { echo "assert_psbt_wellformed: odd hex length"; return 1; }

	local i=10 last_was_sep=0 map=0
	while (( i < n )); do
		local keylen
		_hx_cs "$hex" "$i" "$n" || { echo "keylen compactSize past end at $i"; return 1; }
		keylen=$_cs_val; i=$_cs_end
		if (( keylen == 0 )); then
			last_was_sep=1; map=$(( map + 1 )); continue   # map separator
		fi
		last_was_sep=0
		local keytype="${hex:i:2}"
		(( i + keylen*2 > n )) && { echo "key overruns end (keylen=$keylen at $i)"; return 1; }
		i=$(( i + keylen*2 ))
		local vallen
		_hx_cs "$hex" "$i" "$n" || { echo "vallen compactSize past end at $i"; return 1; }
		vallen=$_cs_val; i=$_cs_end
		(( i + vallen*2 > n )) && { echo "value overruns end (vallen=$vallen at $i)"; return 1; }
		# Global unsigned-tx record: declared length must equal the real tx length.
		if (( map == 0 )) && [ "$keytype" = "00" ]; then
			local txhex txlen
			txhex="${hex:i:vallen*2}"
			txlen="$(tx_byte_len "$txhex")" || { echo "global unsigned tx is malformed / longer than its declared $vallen bytes (BUG-021)"; return 1; }
			(( txlen == vallen )) || { echo "global unsigned tx length $txlen != declared $vallen (BUG-021)"; return 1; }
		fi
		i=$(( i + vallen*2 ))
	done

	(( i == n )) || { echo "did not land on a byte boundary ($i/$n)"; return 1; }
	(( last_was_sep == 1 )) || { echo "PSBT did not end on a 0x00 separator (truncated/stray byte)"; return 1; }
	return 0
}
