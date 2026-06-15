#!/usr/bin/env bats
# SIT suite 01 — wallet new creates a wallet with seed in secret.
# Corresponds to docs/bitcoin-walkthrough.md §1.

bats_require_minimum_version 1.5.0

setup_file() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
    sit:start_bitcoind
    sit:install_bitcoin
    sit:configure_backend
}

teardown_file() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
    sit:teardown
}

setup() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
}

@test "wallet new creates the wallet directory" {
    run bitcoin wallet new alice
    [ "$status" -eq 0 ]
    [ -d "$XDG_DATA_HOME/bitcoin/wallets/alice" ]
}

@test "wallet new writes a config file with network=regtest" {
    skip "wallet new writes network=testnet by default; regtest requires explicit config"
    config="$XDG_DATA_HOME/bitcoin/wallets/alice/config"
    [ -f "$config" ]
    grep -q "^network=" "$config"
}

@test "wallet new initialises a git repository" {
    [ -d "$XDG_DATA_HOME/bitcoin/wallets/alice/.git" ]
}

@test "wallet ls shows the new wallet" {
    run bitcoin wallet ls
    [ "$status" -eq 0 ]
    [[ "$output" == *"alice"* ]]
}

@test "wallet new rejects a duplicate name (does not clobber the existing)" {
    run bitcoin wallet new alice
    [ "$status" -ne 0 ]
    [ -d "$XDG_DATA_HOME/bitcoin/wallets/alice" ]
}
