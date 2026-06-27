#!/usr/bin/env bats
# SIT suite 02 — derive an address, fund it, verify balance.
# Corresponds to docs/bitcoin-walkthrough.md §2 and §3.

bats_require_minimum_version 1.5.0

setup_file() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
    sit:start_bitcoind
    sit:install_bitcoin
    sit:configure_backend
    bitcoin wallet new alice
}

teardown_file() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
    sit:teardown
}

setup() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
}

@test "wallet derive returns a bech32 address" {
    run bitcoin wallet derive alice
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^(bc1q|tb1q)[0-9a-z]+$ ]]
}

@test "wallet derive adds an entry to the addresses ledger" {
    ledger="$XDG_DATA_HOME/bitcoin/wallets/alice/addresses"
    [ -f "$ledger" ]
    [ "$(wc -l < "$ledger")" -ge 1 ]
}

@test "wallet balance is zero before funding" {
    run bitcoin wallet balance alice
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^0$ ]]
}

@test "wallet balance reflects confirmed UTXOs after funding" {
    addr="$(bitcoin wallet derive alice)"
    sit:fund_address "$addr" 500000
    run bitcoin wallet balance alice
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[1-9][0-9]*$ ]]
}

@test "funded address appears in wallet utxos" {
    run bitcoin wallet utxos alice
    [ "$status" -eq 0 ]
    [[ "$output" != "" ]]
}
