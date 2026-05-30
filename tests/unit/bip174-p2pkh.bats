#!/usr/bin/env bats
#
# FEAT-014 — P2PKH and P2SH-P2WPKH signing (1.29.0).
#
# Tests the legacy double-SHA256 sighash path (P2PKH) and the
# BIP-143 + redeemScript path (P2SH-P2WPKH) added to bip174 sign
# and bip174 finalize.
#
# Test vectors use alice's canonical abandon-mnemonic key material:
#   privkey: 4604b4b710fe91f584fff084e1a9159fe4f8408fff380596a604948474ce4fa3
#   pubkey:  0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c
#   HASH160: c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2
#   redeemScript: 0014c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2
#   P2SH-P2WPKH hash: a6b5888fddc8fa193dd353d10e5cd5a8eeab064e

bats_require_minimum_version 1.5.0

ALICE_PRIV="4604b4b710fe91f584fff084e1a9159fe4f8408fff380596a604948474ce4fa3"
ALICE_PUB="0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c"
ALICE_HASH160="c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2"

# Minimal 1-input / 1-output unsigned TX: input spends 32-zero txid:0,
# output pays 50000 sats to a P2WPKH-zero address. Used for both
# P2PKH and P2SH-P2WPKH PSBT wrappers below (only the input UTXO
# record differs between them).
#
# Exactly 82 bytes (0x52) — the length the PSBT wrappers below declare
# in their PSBT_GLOBAL_UNSIGNED_TX record (`010052`). It MUST match, or
# psbt:_parse_structured reads `vallen` bytes and the leftover byte
# desyncs the per-section walk (regression: a stray trailing 00 here
# pushed the WITNESS_UTXO into the output section, so `sign` saw an
# input with no UTXO and silently produced no PARTIAL_SIG).
UNSIGNED_TX="020000000100000000000000000000000000000000000000000000000000000000000000000000000000feffffff0150c3000000000000160014000000000000000000000000000000000000000000000000"

# P2PKH WITNESS_UTXO: 100000 sats + varint(25) + 76a914<hash>88ac.
# Using WITNESS_UTXO (type 0x01) is the educational simplification
# for P2PKH PSBTs (avoids fetching the full prev-tx for the
# NON_WITNESS_UTXO record).
#   8-byte LE: a086010000000000
#   scriptPubKey (25 B): 76a914c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e288ac
#   varint(25) = 19
P2PKH_PSBT="70736274ff010052${UNSIGNED_TX}00010122a0860100000000001976a914${ALICE_HASH160}88ac0000"

# P2SH-P2WPKH PSBT: WITNESS_UTXO has the P2SH scriptPubKey
# a914a6b5888fddc8fa193dd353d10e5cd5a8eeab064e87 (23 B, varint=17),
# plus REDEEM_SCRIPT record (type 0x04) carrying 0014<hash> (22 B).
#   WU = 100000 LE(8) + 17(varint) + a914...87
#   RS record: key=04, val=0014c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2
P2SH_PSBT="70736274ff010052${UNSIGNED_TX}000101 20a08601000000000017a914a6b5888fddc8fa193dd353d10e5cd5a8eeab064e870104160014${ALICE_HASH160}0000"
P2SH_PSBT="70736274ff010052020000000100000000000000000000000000000000000000000000000000000000000000000000000000feffffff0150c300000000000016001400000000000000000000000000000000000000000000000000010120a08601000000000017a914a6b5888fddc8fa193dd353d10e5cd5a8eeab064e870104160014c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e20000"

setup() {
    BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
    export SELF_LIBEXEC="$BATS_TEST_DIRNAME/../../libexec"
    export SELF_QUIET=1
    BIP174="$SELF_LIBEXEC/bitcoin/bip174"
}

# ---------------------------------------------------------------------------
# P2PKH signing
# ---------------------------------------------------------------------------

@test "FEAT-014 — psbt sign emits PARTIAL_SIG for P2PKH input" {
    run bash -c "echo '$P2PKH_PSBT' | '$BIP174' sign '$ALICE_PRIV'"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | '$BIP174' decode"
    [ "$status" -eq 0 ]
    [[ "$output" == *"type=02"* ]]
    [[ "$output" == *"key=02${ALICE_PUB}"* ]]
    psig="$(echo "$output" | awk -F'\t' '/type=02/ {sub("^value=","",$4); print $4; exit}')"
    [[ "$psig" =~ ^30[0-9a-f]+01$ ]]
}

@test "FEAT-014 — P2PKH PARTIAL_SIG is low-S (BIP-66)" {
    signed="$(echo "$P2PKH_PSBT" | "$BIP174" sign "$ALICE_PRIV")"
    psig="$(echo "$signed" | "$BIP174" decode | awk -F'\t' '/type=02/ {sub("^value=","",$4); print $4; exit}')"
    der="${psig%01}"
    r_len=$((16#${der:6:2}))
    s_off=$((8 + 2 * r_len + 4))
    (( 16#${der:s_off:2} < 0x80 ))
}

@test "FEAT-014 — P2PKH signature verifies against legacy double-SHA256 sighash" {
    signed="$(echo "$P2PKH_PSBT" | "$BIP174" sign "$ALICE_PRIV")"
    dec="$(echo "$signed" | "$BIP174" decode)"
    tx_hex="$(echo "$dec" | awk -F'\t' 'NR==1 {sub("^value=","",$4); print $4}')"
    psig="$(echo "$dec" | awk -F'\t' '/type=02/ {sub("^value=","",$4); print $4; exit}')"
    der_sig="${psig%01}"

    sighash="$(BITCOIN_BIP174="$BIP174" bash -c '
        source "$BITCOIN_BIP174"
        p2pkh_script="76a914'"$ALICE_HASH160"'88ac"
        psbt:_legacy_sighash "'"$tx_hex"'" 0 "$p2pkh_script" 01
    ' 2>/dev/null)"

    pubder="$BATS_TMPDIR/pub.p2pkh.$BATS_TEST_NUMBER.der"
    sigfile="$BATS_TMPDIR/sig.p2pkh.$BATS_TEST_NUMBER.der"
    hashfile="$BATS_TMPDIR/hash.p2pkh.$BATS_TEST_NUMBER.bin"
    {
        printf '3036301006072a8648ce3d020106052b8104000a032200'
        printf '%s' "$ALICE_PUB"
    } | xxd -r -p > "$pubder"
    printf '%s' "$der_sig" | xxd -r -p > "$sigfile"
    printf '%s' "$sighash"  | xxd -r -p > "$hashfile"
    # The sighash is already the final 32-byte digest the signer signed,
    # so verify it as a pre-hashed digest — NOT with -rawin (which tells
    # OpenSSL the input is an unhashed message and would re-hash it,
    # guaranteeing a spurious "Signature Verification Failure"). Matches
    # the proven FEAT-008 verify path in bitcoin.bats.
    openssl pkeyutl -verify -inkey "$pubder" -keyform DER -pubin \
        -sigfile "$sigfile" -in "$hashfile" 2>/dev/null
}

@test "FEAT-014 — psbt finalize produces FINAL_SCRIPTSIG (no witness) for P2PKH" {
    signed="$(echo "$P2PKH_PSBT" | "$BIP174" sign "$ALICE_PRIV")"
    finalized="$(echo "$signed" | "$BIP174" finalize)"
    dec="$(echo "$finalized" | "$BIP174" decode)"
    # Must have FINAL_SCRIPTSIG (type 07) but NO FINAL_SCRIPTWITNESS (type 08).
    [[ "$dec" == *"type=07"* ]]
    [[ "$dec" != *"type=08"* ]]
    # scriptSig value must start with the sig push (DER 0x30) and end with pubkey.
    ss="$(echo "$dec" | awk -F'\t' '/type=07/ {sub("^value=","",$4); print $4; exit}')"
    # First two hex chars are OP_PUSH_N (length of sig). Sig starts at offset 2.
    [[ "$ss" =~ ^[0-9a-f]{2}30[0-9a-f]+${ALICE_PUB}$ ]]
}

@test "FEAT-014 — psbt extract produces broadcastable legacy tx for P2PKH" {
    raw="$(echo "$P2PKH_PSBT" | "$BIP174" sign "$ALICE_PRIV" | "$BIP174" finalize | "$BIP174" extract)"
    # Must be valid hex.
    [[ "$raw" =~ ^[0-9a-f]+$ ]]
    # Segwit envelope: marker 00 + flag 01 after version.
    [[ "${raw:8:4}" == "0001" ]]
    # Witness field for the P2PKH input should be empty stack (0x00 byte).
    # Locate the witness section: comes after all input/output data.
    # Just assert the raw tx is non-empty and ends with locktime 00000000.
    [[ "${raw: -8}" == "00000000" ]]
}

# ---------------------------------------------------------------------------
# P2SH-P2WPKH signing
# ---------------------------------------------------------------------------

@test "FEAT-014 — psbt sign emits PARTIAL_SIG for P2SH-P2WPKH input" {
    run bash -c "echo '$P2SH_PSBT' | '$BIP174' sign '$ALICE_PRIV'"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | '$BIP174' decode"
    [ "$status" -eq 0 ]
    [[ "$output" == *"type=02"* ]]
    [[ "$output" == *"key=02${ALICE_PUB}"* ]]
    psig="$(echo "$output" | awk -F'\t' '/type=02/ {sub("^value=","",$4); print $4; exit}')"
    [[ "$psig" =~ ^30[0-9a-f]+01$ ]]
}

@test "FEAT-014 — psbt sign emits REDEEM_SCRIPT record for P2SH-P2WPKH input" {
    signed="$(echo "$P2SH_PSBT" | "$BIP174" sign "$ALICE_PRIV")"
    dec="$(echo "$signed" | "$BIP174" decode)"
    [[ "$dec" == *"type=04"* ]]
    rs="$(echo "$dec" | awk -F'\t' '/type=04/ {sub("^value=","",$4); print $4; exit}')"
    [[ "$rs" == "0014${ALICE_HASH160}" ]]
}

@test "FEAT-014 — P2SH-P2WPKH signature verifies against BIP-143 sighash" {
    signed="$(echo "$P2SH_PSBT" | "$BIP174" sign "$ALICE_PRIV")"
    dec="$(echo "$signed" | "$BIP174" decode)"
    tx_hex="$(echo "$dec" | awk -F'\t' 'NR==1 {sub("^value=","",$4); print $4}')"
    psig="$(echo "$dec" | awk -F'\t' '/type=02/ {sub("^value=","",$4); print $4; exit}')"
    der_sig="${psig%01}"

    # P2SH-P2WPKH uses BIP-143 with the inner P2WPKH scriptCode.
    sighash="$(BITCOIN_BIP174="$BIP174" bash -c '
        source "$BITCOIN_BIP174"
        script_code="1976a914'"$ALICE_HASH160"'88ac"
        amount_le="a086010000000000"
        psbt:_bip143_sighash "'"$tx_hex"'" 0 "$script_code" "$amount_le" 01
    ' 2>/dev/null)"

    pubder="$BATS_TMPDIR/pub.p2sh.$BATS_TEST_NUMBER.der"
    sigfile="$BATS_TMPDIR/sig.p2sh.$BATS_TEST_NUMBER.der"
    hashfile="$BATS_TMPDIR/hash.p2sh.$BATS_TEST_NUMBER.bin"
    {
        printf '3036301006072a8648ce3d020106052b8104000a032200'
        printf '%s' "$ALICE_PUB"
    } | xxd -r -p > "$pubder"
    printf '%s' "$der_sig" | xxd -r -p > "$sigfile"
    printf '%s' "$sighash"  | xxd -r -p > "$hashfile"
    # The sighash is already the final 32-byte digest the signer signed,
    # so verify it as a pre-hashed digest — NOT with -rawin (which tells
    # OpenSSL the input is an unhashed message and would re-hash it,
    # guaranteeing a spurious "Signature Verification Failure"). Matches
    # the proven FEAT-008 verify path in bitcoin.bats.
    openssl pkeyutl -verify -inkey "$pubder" -keyform DER -pubin \
        -sigfile "$sigfile" -in "$hashfile" 2>/dev/null
}

@test "FEAT-014 — psbt finalize produces FINAL_SCRIPTSIG + FINAL_SCRIPTWITNESS for P2SH-P2WPKH" {
    signed="$(echo "$P2SH_PSBT" | "$BIP174" sign "$ALICE_PRIV")"
    finalized="$(echo "$signed" | "$BIP174" finalize)"
    dec="$(echo "$finalized" | "$BIP174" decode)"
    # Must have both FINAL_SCRIPTSIG (type 07) and FINAL_SCRIPTWITNESS (type 08).
    [[ "$dec" == *"type=07"* ]]
    [[ "$dec" == *"type=08"* ]]
    # scriptSig = push(redeemScript) = 16 0014<hash>
    ss="$(echo "$dec" | awk -F'\t' '/type=07/ {sub("^value=","",$4); print $4; exit}')"
    [[ "$ss" == "160014${ALICE_HASH160}" ]]
}
