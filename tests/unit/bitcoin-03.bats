#!/usr/bin/env bats
#
# bitcoin unit tests — part 3 of 5 (FEAT-053 split of tests/unit/bitcoin.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/bitcoin.bash.

bats_require_minimum_version 1.5.0
load lib/bitcoin


# ---------------------------------------------------------------------------
# FEAT-008 (partial, 1.10.0) — psbt encode. Reverse of decode: read TSV
# records on stdin and emit a hex PSBT. Empty trailing sections aren't
# representable (decoded TSV doesn't record them); see the help text
# for the limitation.
# ---------------------------------------------------------------------------

@test "FEAT-008 — psbt encode emits the BIP-174 magic + final terminator for empty input" {
	run bash -c "echo '' | '$BITCOIN_BIN' bip174 encode"
	[ "$status" -eq 0 ]
	[ "$output" = "70736274ff00" ]
}

@test "FEAT-008 — psbt encode emits the expected wire format for a single-record global section" {
	# Global section, type=00, key=00, value=deadbeef.
	# Expected: magic(70736274ff) + varint(1)=01 + key(00)
	#                            + varint(4)=04 + value(deadbeef)
	#                            + section-close 00.
	run bash -c "printf 'section=0\ttype=00\tkey=00\tvalue=deadbeef\n' | '$BITCOIN_BIN' bip174 encode"
	[ "$status" -eq 0 ]
	[ "$output" = "70736274ff010004deadbeef00" ]
}

@test "FEAT-008 — psbt encode bumps sections with 0x00 terminators" {
	# Two records in different sections.
	run bash -c "printf 'section=0\ttype=00\tkey=00\tvalue=aa\nsection=1\ttype=00\tkey=00\tvalue=bb\n' \
		| '$BITCOIN_BIN' bip174 encode"
	[ "$status" -eq 0 ]
	# magic + (01 00 01 aa) + 00(close 0) + (01 00 01 bb) + 00(close 1)
	[ "$output" = "70736274ff010001aa00010001bb00" ]
}

@test "FEAT-008 — psbt encode | psbt decode round-trips a TSV with records in every section" {
	tsv=$(printf 'section=0\ttype=00\tkey=00\tvalue=aa\nsection=1\ttype=00\tkey=00\tvalue=bb\nsection=2\ttype=00\tkey=00\tvalue=cc\n')
	encoded=$(printf '%s\n' "$tsv" | "$BITCOIN_BIN" bip174 encode)
	decoded=$(echo "$encoded" | "$BITCOIN_BIN" bip174 decode)
	# Decode emits trailing newline; tsv has none. Compare after
	# trimming.
	[ "$(printf '%s\n' "$tsv")" = "$(printf '%s\n' "$decoded")" ]
}

@test "FEAT-008 — psbt encode rejects non-hex values" {
	run bash -c "printf 'section=0\ttype=00\tkey=00\tvalue=notHex!\n' | '$BITCOIN_BIN' bip174 encode"
	[ "$status" -ne 0 ]
}

@test "FEAT-008 — psbt encode rejects a section field that goes backwards" {
	run bash -c "printf 'section=1\ttype=00\tkey=00\tvalue=aa\nsection=0\ttype=00\tkey=00\tvalue=bb\n' \
		| '$BITCOIN_BIN' bip174 encode"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-014 (extend, 1.13.0) — wallet build now emits a
# PSBT_IN_WITNESS_UTXO record (type 0x01) per input so that the
# 1.13.0 psbt-sign primitive has the prev-output's amount and
# scriptPubKey on hand for BIP-143 sighash construction.
# ---------------------------------------------------------------------------

@test "FEAT-014 — wallet build emits a PSBT_IN_WITNESS_UTXO record per input" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	# Decode and look for a section=1 type=01 record carrying the
	# UTXO's value (a086010000000000 = 100000 sats LE) followed by
	# the 22-byte P2WPKH scriptPubKey for alice's index-0 address.
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	[[ "$output" == *"section=1	type=01	key=01	value=a086010000000000160014c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2"* ]]
}

@test "FEAT-008 — psbt sign adds a PSBT_IN_PARTIAL_SIG record for the matching input" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$(build_alice_psbt)"
	run bash -c "echo '$psbt' | '$BITCOIN_BIN' bip174 sign '$ALICE_PRIV'"
	[ "$status" -eq 0 ]
	# Decode and check for the PARTIAL_SIG record. type=02, key includes
	# alice's compressed pubkey, value is a DER signature + sighash byte.
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	[[ "$output" == *"section=1	type=02"* ]]
	[[ "$output" == *"key=02${ALICE_PUB}"* ]]
	# Sig must end in 01 (SIGHASH_ALL) and start with 30 (DER SEQUENCE).
	psig="$(echo "$output" | awk -F'\t' '/type=02/ {sub("^value=","",$4); print $4; exit}')"
	[[ "$psig" =~ ^30[0-9a-f]+01$ ]]
}

@test "FEAT-008 — psbt sign produces a low-S signature (BIP-66 §Low S)" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$(build_alice_psbt)"
	signed="$(echo "$psbt" | "$BITCOIN_BIN" bip174 sign "$ALICE_PRIV")"
	psig="$(echo "$signed" | "$BITCOIN_BIN" bip174 decode | awk -F'\t' '/type=02/ {sub("^value=","",$4); print $4; exit}')"
	# Strip SIGHASH byte (last 2 hex chars). DER layout:
	#   30 <total> 02 <r-len> <r> 02 <s-len> <s>
	# r-len at offset 6; r at offset 8; s marker at offset 8+r_len*2;
	# s value at s_marker + 4. First byte of s must be < 0x80 for low-S
	# (canonical form drops the DER 0x00 padding when high bit is clear).
	der="${psig%01}"
	r_len_hex="${der:6:2}"
	r_len=$((16#$r_len_hex))
	s_off=$((8 + 2 * r_len + 4))
	first_s_byte=$((16#${der:s_off:2}))
	(( first_s_byte < 0x80 ))
}

@test "FEAT-008 — psbt sign signature verifies via openssl against the BIP-143 sighash" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$(build_alice_psbt)"
	signed="$(echo "$psbt" | "$BITCOIN_BIN" bip174 sign "$ALICE_PRIV")"
	# Pull unsigned tx + partial-sig out of the decoded PSBT.
	dec="$(echo "$signed" | "$BITCOIN_BIN" bip174 decode)"
	tx_hex="$(echo "$dec" | head -1 | sed 's/.*value=//')"
	psig="$(echo "$dec" | awk -F'\t' '/type=02/ {sub("^value=","",$4); print $4; exit}')"
	der_sig="${psig%01}"
	# Compute the same sighash the signer used and verify with openssl.
	# FEAT-035 Stream D: psbt:_bip143_sighash moved from bin/bitcoin
	# into the libexec/bitcoin-node/bip174 plugin (PR #36); source the
	# plugin to reach the private helper. bip174 is source-safe (it
	# checks BASH_SOURCE before running its dispatcher).
	sighash="$(BITCOIN_BIP174="$BATS_TEST_DIRNAME/../../libexec/bitcoin-node/bip174" bash -c '
		source "$BITCOIN_BIP174"
		psbt:_bip143_sighash "'"$tx_hex"'" 0 \
			"1976a914c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e288ac" \
			"a086010000000000" 01
	' 2>/dev/null)"
	pubder="$BATS_TMPDIR/pub.$BATS_TEST_NUMBER.der"
	sigfile="$BATS_TMPDIR/sig.$BATS_TEST_NUMBER.der"
	hashfile="$BATS_TMPDIR/hash.$BATS_TEST_NUMBER.bin"
	# SubjectPublicKeyInfo for a compressed secp256k1 pubkey:
	#   30 36 30 10 06 07 2a8648ce3d0201 06 05 2b8104000a 03 22 00 <33-byte pubkey>
	{
		printf '3036301006072a8648ce3d020106052b8104000a032200'
		printf '%s' "$ALICE_PUB"
	} | xxd -r -p > "$pubder"
	printf '%s' "$sighash" | xxd -r -p > "$hashfile"
	printf '%s' "$der_sig" | xxd -r -p > "$sigfile"
	run openssl pkeyutl -verify -pubin -inkey "$pubder" -keyform DER -in "$hashfile" -sigfile "$sigfile"
	[ "$status" -eq 0 ]
}

@test "FEAT-008 — psbt sign with a key not matching any input is a no-op" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$(build_alice_psbt)"
	wrong_key="1111111111111111111111111111111111111111111111111111111111111111"
	signed="$(echo "$psbt" | "$BITCOIN_BIN" bip174 sign "$wrong_key")"
	# Same input record, no PARTIAL_SIG added.
	dec="$(echo "$signed" | "$BITCOIN_BIN" bip174 decode)"
	! echo "$dec" | grep -q 'type=02'
	# Re-emitted PSBT byte-identical to the input (signer is a pure
	# re-emit on the no-match branch).
	[ "$signed" = "$psbt" ]
}

@test "FEAT-008 — psbt sign rejects a malformed private key" {
	run bash -c "echo '70736274ff00' | '$BITCOIN_BIN' bip174 sign not-a-hex-key"
	[ "$status" -ne 0 ]
	[[ "$output" == *"privkey-hex"* ]] || [[ "$stderr" == *"privkey-hex"* ]]
}

@test "FEAT-008 — psbt sign rejects empty stdin" {
	run bash -c "echo '' | '$BITCOIN_BIN' bip174 sign $ALICE_PRIV"
	[ "$status" -ne 0 ]
}

@test "FEAT-008 — psbt sign rejects non-hex stdin" {
	run bash -c "echo 'not a psbt' | '$BITCOIN_BIN' bip174 sign $ALICE_PRIV"
	[ "$status" -ne 0 ]
}

@test "FEAT-008 — psbt help mentions sign" {
	run "$BITCOIN_BIN" bip174 help
	[ "$status" -eq 0 ]
	[[ "$output" == *"sign"* ]]
}

@test "FEAT-008 — psbt finalize adds FINAL_SCRIPTWITNESS for a signed input" {
	signed="$(signed_alice_psbt)"
	run bash -c "echo '$signed' | '$BITCOIN_BIN' bip174 finalize"
	[ "$status" -eq 0 ]
	# Decode and check the input section now has type=08 (FINAL_SCRIPTWITNESS).
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	[[ "$output" == *"section=1	type=08	key=08"* ]]
	# The witness value starts with varint 0x02 (two stack items).
	wit="$(echo "$output" | awk -F'\t' '/type=08/ {sub("^value=","",$4); print $4; exit}')"
	[ "${wit:0:2}" = "02" ]
}

@test "FEAT-008 — psbt finalize strips PARTIAL_SIG (BIP-174 §Finalizer)" {
	signed="$(signed_alice_psbt)"
	finalised="$(echo "$signed" | "$BITCOIN_BIN" bip174 finalize)"
	dec="$(echo "$finalised" | "$BITCOIN_BIN" bip174 decode)"
	# After finalize, the input section keeps WITNESS_UTXO (01) and
	# FINAL_SCRIPTWITNESS (08), drops PARTIAL_SIG (02).
	! echo "$dec" | grep -q 'type=02'
	echo "$dec" | grep -q 'type=01'
	echo "$dec" | grep -q 'type=08'
}

@test "FEAT-008 — psbt extract emits a segwit raw tx with the marker+flag" {
	signed="$(signed_alice_psbt)"
	finalised="$(echo "$signed" | "$BITCOIN_BIN" bip174 finalize)"
	run bash -c "echo '$finalised' | '$BITCOIN_BIN' bip174 extract"
	[ "$status" -eq 0 ]
	# Version 02000000, then segwit marker (00) + flag (01) at hex offset 8.
	[ "${output:0:8}" = "02000000" ]
	[ "${output:8:4}" = "0001" ]
	# Locktime is the final 4 bytes.
	[ "${output: -8}" = "00000000" ]
	# Witness items: count=2, sig (~70 B), pubkey (33 B). The 33-byte
	# pubkey suffix matches alice's compressed pubkey ending in …91af3c.
	[[ "$output" == *"${ALICE_PUB}00000000" ]]
}

@test "FEAT-008 — psbt extract refuses an unfinalised PSBT" {
	signed="$(signed_alice_psbt)"
	# Skip the finalize step → input still has PARTIAL_SIG, no witness.
	run bash -c "echo '$signed' | '$BITCOIN_BIN' bip174 extract"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not finalised"* ]] || [[ "$stderr" == *"not finalised"* ]]
}

@test "FEAT-008 — psbt finalize is a no-op on an unsigned PSBT" {
	# wallet build with no subsequent sign → no PARTIAL_SIG anywhere.
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$("$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1)"
	run bash -c "echo '$psbt' | '$BITCOIN_BIN' bip174 finalize"
	[ "$status" -eq 0 ]
	# Same input record blob (no FINAL_SCRIPTWITNESS added).
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	! echo "$output" | grep -q 'type=08'
}

# ---------------------------------------------------------------------------
# FEAT-014 (partial, 1.14.0) — wallet sign + wallet send.
#
# wallet sign reads a PSBT and derives one private key per address in
# the wallet's ledger, piping the PSBT through psbt sign once each.
# wallet send composes build | sign | finalize | extract | broadcast.
# ---------------------------------------------------------------------------

@test "FEAT-014 — wallet sign produces a PARTIAL_SIG for the wallet's matching address" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$("$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1)"
	run bash -c "echo '$psbt' | '$BITCOIN_BIN' tx sign alice"
	[ "$status" -eq 0 ]
	# The signed PSBT carries a PARTIAL_SIG keyed by alice's compressed
	# pubkey — same shape as the FEAT-008 psbt-sign test, but reached
	# via the wallet's seed-derived key rather than a hardcoded hex.
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	[[ "$output" == *"section=1	type=02"* ]]
	[[ "$output" == *"key=02${ALICE_PUB}"* ]]
}

@test "FEAT-014 — wallet sign rejects a missing wallet" {
	setup_wallet_derive_env
	run bash -c "echo '70736274ff00' | '$BITCOIN_BIN' tx sign no-such-wallet"
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet sign rejects empty stdin" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	run bash -c "echo '' | '$BITCOIN_BIN' tx sign alice"
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet send composes the pipeline and returns the broadcast txid" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	# Stub the broadcast endpoint to return a known txid.
	curl_fixture "https://mempool.space/api/tx" \
		"f00df00df00df00df00df00df00df00df00df00df00df00df00df00df00df00d"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	[ "$output" = "f00df00df00df00df00df00df00df00df00df00df00df00df00df00df00df00d" ]
}

@test "FEAT-014 — wallet send rejects a missing wallet" {
	setup_wallet_derive_env
	run "$BITCOIN_BIN" wallet send no-such-wallet bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 1000
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet send on a testnet wallet proceeds without --mainnet" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	# Set the network explicitly. (setup_wallet_derive_env writes an
	# empty config; the helper defaults to testnet anyway, but pinning
	# this in the test keeps the intent visible.)
	wallet_set_network alice testnet
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	curl_fixture "https://mempool.space/api/tx" \
		"f00df00df00df00df00df00df00df00df00df00df00df00df00df00df00df00d"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	[ "$output" = "f00df00df00df00df00df00df00df00df00df00df00df00df00df00df00df00d" ]
}

@test "FEAT-014 — wallet send on an empty-config wallet defaults to testnet (no --mainnet needed)" {
	# Per wallet:_network's default-to-testnet fallback, a wallet
	# whose config has no network= line is treated as testnet — so
	# send proceeds without --mainnet. This is the pre-existing
	# setup_wallet_derive_env shape (config is empty).
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	curl_fixture "https://mempool.space/api/tx" \
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	# Confirm the config has no network= line.
	! grep -q '^network=' "$XDG_DATA_HOME/bitcoin/wallets/alice/config"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
}

@test "FEAT-014 — wallet send on a mainnet wallet refuses without --mainnet" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	wallet_set_network alice mainnet
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -ne 0 ]
	[[ "$output" == *"mainnet"* ]] || [[ "$stderr" == *"mainnet"* ]]
}

@test "FEAT-014 — wallet send on a mainnet wallet succeeds with --mainnet" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	wallet_set_network alice mainnet
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	curl_fixture "https://mempool.space/api/tx" \
		"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1 --mainnet
	[ "$status" -eq 0 ]
	[ "$output" = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef" ]
}

@test "FEAT-014 — wallet send accepts --mainnet on non-mainnet wallets as a silent no-op" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	wallet_set_network alice regtest
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	curl_fixture "https://mempool.space/api/tx" \
		"00000000deadbeef00000000deadbeef00000000deadbeef00000000deadbeef"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1 --mainnet
	[ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-015 (partial, 1.15.0) — man page + bash completion + walkthrough.
# The man-page assertions read straight from the source roff so they
# are independent of whether mandoc/groff is installed on CI runners.
# The completion test sources the file under bash and calls the
# completion function with constructed COMP_WORDS — no need to spawn
# a real readline session.
# ---------------------------------------------------------------------------

@test "FEAT-015 — man page exists and has every required section" {
	man="$BATS_TEST_DIRNAME/../../share/man/man1/bitcoin.1"
	[ -s "$man" ]
	# Each section header is a top-level .SH directive in roff.
	# COMMANDS replaced SUBCOMMANDS in 1.23.0 per FEAT-041 (compact
	# cross-reference table pointing at bitcoin-<verb>(1) pages).
	for section in NAME SYNOPSIS DESCRIPTION OPTIONS COMMANDS \
		ENVIRONMENT FILES "EXIT STATUS" EXAMPLES STANDARDS "SEE ALSO"; do
		grep -q "^\\.SH $section\$" "$man"
	done
}

@test "FEAT-015 — man page STANDARDS section cites every implemented BIP" {
	man="$BATS_TEST_DIRNAME/../../share/man/man1/bitcoin.1"
	# Pin the canonical list of BIPs the wallet implements end-to-end
	# through 1.14.0. New BIPs should be added here as they ship.
	for bip in "BIP-13" "BIP-32" "BIP-39" "BIP-141" "BIP-143" \
		"BIP-173" "BIP-174" "BIP-350" "BIP-380"; do
		grep -q "$bip" "$man"
	done
}

@test "FEAT-015 — man page renders cleanly under mandoc lint" {
	# Skip the test if mandoc isn't installed — the man source is
	# still asserted to exist by the section test above, and CI
	# can opt into stricter lint by installing mandoc.
	command -v mandoc >/dev/null 2>&1 || skip "mandoc not installed"
	man="$BATS_TEST_DIRNAME/../../share/man/man1/bitcoin.1"
	# Suppress two harmless conventional warnings:
	#   - "empty block: UR"   — bare URL in .UR/.UE pair
	#   - "skipping paragraph macro: PP after SH"
	#     (common idiom for spacing after a section header)
	# Anything else fails the test.
	run bash -c "mandoc -T lint '$man' 2>&1 | grep -vE 'empty block: UR|skipping paragraph macro' || true"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "FEAT-015 — bash completion is source-able under bash" {
	completion="$BATS_TEST_DIRNAME/../../etc/bash_completion.d/bitcoin"
	[ -s "$completion" ]
	run bash -n "$completion"
	[ "$status" -eq 0 ]
}

@test "FEAT-015 — bash completion offers every wallet subcommand" {
	completion="$BATS_TEST_DIRNAME/../../etc/bash_completion.d/bitcoin"
	run bash -c "
		source '$completion'
		COMP_WORDS=(bitcoin wallet '')
		COMP_CWORD=2
		_bitcoin_complete_entries
		printf '%s ' \"\${COMPREPLY[@]}\"
	"
	[ "$status" -eq 0 ]
	# Every verb shipped through 1.14.0 must surface.
	for verb in new ls rm derive addresses label balance build sign send broadcast remote push pull help; do
		[[ "$output" == *"$verb"* ]]
	done
}

@test "FEAT-015 — bash completion is context-aware for psbt + backend + descriptor" {
	completion="$BATS_TEST_DIRNAME/../../etc/bash_completion.d/bitcoin"
	# psbt subtree
	run bash -c "
		source '$completion'
		COMP_WORDS=(bitcoin psbt '')
		COMP_CWORD=2
		_bitcoin_complete_entries
		printf '%s ' \"\${COMPREPLY[@]}\"
	"
	[ "$status" -eq 0 ]
	for verb in decode encode sign finalize extract; do
		[[ "$output" == *"$verb"* ]]
	done
	# backend subtree
	run bash -c "
		source '$completion'
		COMP_WORDS=(bitcoin backend '')
		COMP_CWORD=2
		_bitcoin_complete_entries
		printf '%s ' \"\${COMPREPLY[@]}\"
	"
	[ "$status" -eq 0 ]
	for verb in view set auto chain-height get-address-utxos broadcast estimate-fee; do
		[[ "$output" == *"$verb"* ]]
	done
	# `bitcoin backend set <TAB>` offers the three named backends.
	run bash -c "
		source '$completion'
		COMP_WORDS=(bitcoin backend set '')
		COMP_CWORD=3
		_bitcoin_complete_entries
		printf '%s ' \"\${COMPREPLY[@]}\"
	"
	[ "$status" -eq 0 ]
	for backend in mempool bitcoind blockstream; do
		[[ "$output" == *"$backend"* ]]
	done
}

@test "FEAT-015 — walkthrough exists and references the end-to-end pipeline" {
	wk="$BATS_TEST_DIRNAME/../../docs/bitcoin-walkthrough.md"
	[ -s "$wk" ]
	# The four design principles must appear (FEAT-015 §Design).
	for principle in Educational Functional Decentralized Simple; do
		grep -q -i "$principle" "$wk"
	done
	# Every wallet verb shipped through 1.14.0 must appear in the
	# walkthrough — readers should be able to grep for the verb and
	# find the section that demonstrates it.
	for verb in "wallet new" "wallet derive" "wallet balance" \
		"wallet label" "wallet send" "wallet remote" "wallet push" \
		"wallet pull" "wallet sign" "wallet build" "wallet broadcast" \
		"psbt finalize" "psbt extract"; do
		grep -q -F "$verb" "$wk"
	done
}

@test "FEAT-015 — walkthrough cites the standards table" {
	wk="$BATS_TEST_DIRNAME/../../docs/bitcoin-walkthrough.md"
	for bip in "BIP-32" "BIP-39" "BIP-141" "BIP-143" "BIP-173" "BIP-174"; do
		grep -q -F "$bip" "$wk"
	done
}

# ---------------------------------------------------------------------------
# FEAT-019 / FEAT-048 — bitcoin-wallet agent skill. The AI-facing
# companion to the FEAT-015 human walkthrough. FEAT-048 refreshed the
# content to the 1.33.0 verb set and added Raven as a third install
# target, per the rpk skill convention. BUG-025: the source was
# consolidated from the old split skills/bitcoin-wallet/{SKILL.md,
# opencode.md} into a single canonical manifest at
# .rpk/skills/bitcoin-wallet.md (master ad723c4), per the rpk
# PACKAGING contract; these tests assert that manifest's content and
# are installed by the Makefile into share/{claude,raven}/skills/ and
# share/opencode/commands/.
# ---------------------------------------------------------------------------

@test "FEAT-019 — SKILL.md exists with the required frontmatter" {
	skill="$BATS_TEST_DIRNAME/../../.rpk/skills/bitcoin-wallet.md"
	[ -s "$skill" ]
	# YAML frontmatter: --- ... name: bitcoin-wallet ... description: ... ---
	head -1 "$skill" | grep -q '^---$'
	grep -q '^name: bitcoin-wallet' "$skill"
	grep -q '^description:' "$skill"
}

@test "FEAT-019 — SKILL.md opens with the four design principles" {
	skill="$BATS_TEST_DIRNAME/../../.rpk/skills/bitcoin-wallet.md"
	# All four words must appear in the design-principles section.
	for word in Educational Functional Decentralized Simple; do
		grep -q -F "$word" "$skill"
	done
}

@test "FEAT-048 — SKILL.md references the canonical 1.33.0 verb set" {
	skill="$BATS_TEST_DIRNAME/../../.rpk/skills/bitcoin-wallet.md"
	# Canonical verbs after the FEAT-035 streamline: PSBT ops live
	# under `tx` (passing through to bip174), descriptor checksum
	# moved to bip380, and tx/utxo/address/price/tax are first-class.
	for recipe in "wallet new" "wallet derive" "wallet balance" \
		"wallet label" "wallet send" "wallet push" "wallet pull" \
		"wallet watch" \
		"tx build" "tx sign" "tx finalize" "tx extract" \
		"tx broadcast" "tx bump" "tx decode" \
		"utxo freeze" "utxo select" \
		"address validate" "address generate" \
		"backend set" "backend estimate-fee" \
		"price fetch" "tax report-de" \
		"bip380 checksum"; do
		grep -q -F "$recipe" "$skill"
	done
	# The deprecated standalone `psbt` command must not be taught as
	# a live recipe (removed in 1.24.0); it may only appear as a
	# "use tx instead" failure-mode note.
	! grep -qE '`?bitcoin psbt (decode|finalize|extract)' "$skill"
}

@test "FEAT-048 — SKILL.md corrects the --mainnet guardrail (now shipped)" {
	skill="$BATS_TEST_DIRNAME/../../.rpk/skills/bitcoin-wallet.md"
	# FEAT-014 shipped --mainnet; the old skill said it "isn't
	# shipped". The refreshed guardrail must describe the live flag
	# and must NOT claim it is unshipped.
	grep -q -i -- '--mainnet' "$skill"
	! grep -q -i "isn't shipped" "$skill"
	! grep -q -i "not yet shipped" "$skill"
	! grep -q -i "guard isn't" "$skill"
}

@test "FEAT-019 — SKILL.md spells out the guardrails an agent must hold" {
	skill="$BATS_TEST_DIRNAME/../../.rpk/skills/bitcoin-wallet.md"
	# The core guardrails the skill spec enumerates.
	grep -q -i 'never print.*mnemonic' "$skill"
	grep -q -i 'never bypass .secret' "$skill"
	grep -q -i 'testnet\|regtest' "$skill"
	grep -q -i 'mainnet' "$skill"
	grep -q -i 'cite the BIP' "$skill"
	grep -q -i 'auto-broadcast' "$skill"
}

@test "FEAT-019 — SKILL.md cites the vendored BIPs by local path" {
	skill="$BATS_TEST_DIRNAME/../../.rpk/skills/bitcoin-wallet.md"
	grep -q 'share/doc/bitcoin/bips/' "$skill"
	# At least one BIP from each major family the wallet implements.
	for bip in "BIP-32" "BIP-39" "BIP-141" "BIP-143" "BIP-173" "BIP-174" "BIP-380"; do
		grep -q -F "$bip" "$skill"
	done
}

@test "BUG-025 — .rpk/skills is the single canonical skill source (no stale split files)" {
	# The migration (master ad723c4 "register bitcoin-wallet skill
	# under .rpk/skills/") folded the old split source
	# skills/bitcoin-wallet/{SKILL.md,opencode.md} into one manifest at
	# .rpk/skills/bitcoin-wallet.md, per the rpk PACKAGING contract
	# (CLAUDE.md §2). Guard against a regression that re-introduces the
	# legacy split layout the SKILL.md tests above used to point at.
	canonical="$BATS_TEST_DIRNAME/../../.rpk/skills/bitcoin-wallet.md"
	[ -s "$canonical" ]
	[ ! -e "$BATS_TEST_DIRNAME/../../skills/bitcoin-wallet/SKILL.md" ]
	[ ! -e "$BATS_TEST_DIRNAME/../../skills/bitcoin-wallet/opencode.md" ]
}

@test "FEAT-019 — Makefile install stages .rpk/skills to claude/raven/opencode" {
	mk="$BATS_TEST_DIRNAME/../../Makefile.in"
	# Skills are sourced from the rpk-native flat files .rpk/skills/<name>.md
	# (BUG-040), installed as SKILL.md for Claude/Raven and as <name>.md for
	# opencode. install-skills-user only symlinks what install stages under
	# share/, so the install target is the gate.
	grep -q '.rpk/skills' "$mk"
	grep -q 'SKILL.md' "$mk"
	# Destination paths the agent dirs are symlinked from.
	grep -q 'share/claude/skills\|claude/skills' "$mk"
	grep -q 'opencode/commands' "$mk"
}

@test "FEAT-048 — Makefile + .rpk/package install the Raven SKILL.md too" {
	mk="$BATS_TEST_DIRNAME/../../Makefile.in"
	pkg="$BATS_TEST_DIRNAME/../../.rpk/package"
	# Raven reuses SKILL.md (no Raven-specific source file) and lands
	# under share/raven/skills/<name>/, in both build paths.
	grep -q 'raven/skills' "$mk"
	grep -q 'raven/skills' "$pkg"
	# install-skills-user must know the Raven user dir.
	grep -q '.raven/workspace/skills' "$mk"
	# And the opencode user symlink must be the .md command file, not
	# a (non-existent) share/opencode/skills dir. Fixed-string match:
	# the literal contains `$$`, which BRE mishandles.
	grep -qF 'opencode/commands/$$name.md' "$mk"
}
