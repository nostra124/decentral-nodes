#!/usr/bin/env bats
# SIT suite 03 — build → sign → finalize → extract → broadcast.
# Validates FEAT-014 AC#1 (wallet send end-to-end on regtest) and
# FEAT-014 AC#3 (testmempoolaccept passes).
# Corresponds to docs/bitcoin-walkthrough.md §5.

bats_require_minimum_version 1.5.0

setup_file() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
    skip "wallet send / PSBT build pipeline needs the bitcoind backend (get-address-utxos/broadcast) — FEAT-304"
    sit:start_bitcoind
    sit:install_bitcoin
    sit:configure_backend

    bitcoin wallet new alice

    # Fund alice with 1 000 000 sats and mine a confirmation.
    ALICE_ADDR="$(bitcoin wallet derive alice)"
    export ALICE_ADDR
    sit:fund_address "$ALICE_ADDR" 1000000

    # A recipient address (unused regtest address).
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

@test "wallet send returns a 64-hex txid" {
    run bitcoin wallet send alice "$RECIPIENT" 100000 --fee-rate 5
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
    SENT_TXID="$output"
}

@test "sent txid appears in the mempool immediately" {
    txid="$(bitcoin wallet send alice "$RECIPIENT" 50000 --fee-rate 5)"
    run sit:cli getmempoolentry "$txid"
    [ "$status" -eq 0 ]
}

@test "PSBT pipeline: build output is valid hex-encoded PSBT" {
    psbt="$(bitcoin tx build alice "$RECIPIENT" 50000 --fee-rate 5)"
    [[ "$psbt" =~ ^70736274ff[0-9a-f]+$ ]]
}

@test "PSBT pipeline: signed PSBT has PARTIAL_SIG record" {
    psbt="$(bitcoin tx build alice "$RECIPIENT" 50000 --fee-rate 5)"
    signed="$(echo "$psbt" | bitcoin tx sign alice)"
    dec="$(echo "$signed" | bitcoin bip174 decode)"
    [[ "$dec" == *"type=02"* ]]
}

@test "extracted raw tx passes testmempoolaccept (FEAT-014 AC#3)" {
    psbt="$(bitcoin tx build alice "$RECIPIENT" 50000 --fee-rate 5)"
    raw="$(echo "$psbt" | bitcoin tx sign alice | bitcoin psbt finalize | bitcoin psbt extract)"
    result="$(sit:cli testmempoolaccept "[\"$raw\"]")"
    allowed="$(echo "$result" | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["allowed"])')"
    [ "$allowed" = "True" ]
}

@test "mined block contains the sent transaction" {
    txid="$(bitcoin wallet send alice "$RECIPIENT" 50000 --fee-rate 5)"
    sit:mine 1
    run sit:cli gettransaction "$txid"
    [ "$status" -eq 0 ]
}
