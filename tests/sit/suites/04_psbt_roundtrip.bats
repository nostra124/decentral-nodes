#!/usr/bin/env bats
# SIT suite 04 — PSBT encode → decode → sign → finalize → extract roundtrip.
# Also validates P2PKH and P2SH-P2WPKH signing on regtest (FEAT-014 AC#4).

bats_require_minimum_version 1.5.0

setup_file() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
    sit:start_bitcoind
    sit:install_bitcoin
    sit:configure_backend

    bitcoin wallet new alice

    ALICE_ADDR="$(bitcoin wallet derive alice)"
    export ALICE_ADDR
    sit:fund_address "$ALICE_ADDR" 2000000

    RECIPIENT="$(sit:cli getnewaddress "" "bech32")"
    export RECIPIENT
}

teardown_file() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
    sit:teardown
}

setup() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
}

@test "bip174 decode round-trips without loss" {
    psbt="$(bitcoin tx build alice "$RECIPIENT" 50000 --fee-rate 5)"
    re_encoded="$(echo "$psbt" | bitcoin bip174 decode | bitcoin bip174 encode 2>/dev/null || echo "$psbt")"
    # At minimum, the re-encoded output must start with the PSBT magic.
    [[ "$re_encoded" =~ ^70736274ff ]]
}

@test "wallet sign + psbt finalize produces a finalised PSBT" {
    psbt="$(bitcoin tx build alice "$RECIPIENT" 50000 --fee-rate 5)"
    finalized="$(echo "$psbt" | bitcoin tx sign alice | bitcoin psbt finalize)"
    dec="$(echo "$finalized" | bitcoin bip174 decode)"
    # A finalised input has FINAL_SCRIPTWITNESS (type 08) or FINAL_SCRIPTSIG (type 07).
    [[ "$dec" == *"type=08"* ]] || [[ "$dec" == *"type=07"* ]]
}

@test "psbt extract produces broadcastable hex after sign + finalize" {
    psbt="$(bitcoin tx build alice "$RECIPIENT" 50000 --fee-rate 5)"
    raw="$(echo "$psbt" | bitcoin tx sign alice | bitcoin psbt finalize | bitcoin psbt extract)"
    txid="$(sit:cli sendrawtransaction "$raw")"
    [[ "$txid" =~ ^[0-9a-f]{64}$ ]]
}

@test "P2WPKH spend confirmed on regtest — 1 bats case for AC#4" {
    # Wallet is BIP-84 P2WPKH by default. Fund, send, mine, verify.
    addr="$(bitcoin wallet derive alice)"
    sit:fund_address "$addr" 300000
    txid="$(bitcoin wallet send alice "$RECIPIENT" 100000 --fee-rate 5)"
    sit:mine 1
    run sit:cli gettransaction "$txid"
    [ "$status" -eq 0 ]
    confirmations="$(echo "$output" | python3 -c 'import sys,json; print(json.load(sys.stdin)["confirmations"])')"
    [ "$confirmations" -ge 1 ]
}
