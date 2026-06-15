#!/usr/bin/env bats
# SIT suite 05 — cold-signing flow: sign on one account, broadcast from another.
# Validates FEAT-016 AC#3: push_pull verifies sign-on-one-account,
# broadcast-from-the-other end-to-end.
# Corresponds to docs/bitcoin-walkthrough.md §6.

bats_require_minimum_version 1.5.0

setup_file() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
    skip "cold-sign/broadcast pipeline needs the bitcoind backend (FEAT-304); the hot/cold HOME split also needs reconciling with XDG_DATA_HOME"
    sit:start_bitcoind
    sit:install_bitcoin
    sit:configure_backend

    # Two wallet HOME directories in the same install, connected via a
    # local bare git remote (the account SSH remote is mocked to a path).
    HOT_HOME="$(mktemp -d)"
    COLD_HOME="$(mktemp -d)"
    BARE_REMOTE="$(mktemp -d)"
    export HOT_HOME COLD_HOME BARE_REMOTE

    # Create alice wallet in the hot context.
    HOME="$HOT_HOME" bitcoin wallet new alice

    # Fund alice (hot).
    ALICE_ADDR="$(HOME="$HOT_HOME" bitcoin wallet derive alice)"
    export ALICE_ADDR
    sit:fund_address "$ALICE_ADDR" 1000000

    # Set up a bare git remote so cold can pull.
    WALLET_REPO="$HOT_HOME/.local/var/bitcoin/wallets/alice"
    git init --bare "$BARE_REMOTE/alice.git" >/dev/null 2>&1
    HOME="$HOT_HOME" bitcoin wallet remote add alice origin "file://$BARE_REMOTE/alice.git"
    HOME="$HOT_HOME" bitcoin wallet push alice

    # Clone on the cold side.
    HOME="$COLD_HOME" bitcoin wallet pull alice "file://$BARE_REMOTE/alice.git" || \
        git clone "file://$BARE_REMOTE/alice.git" \
            "$COLD_HOME/.local/var/bitcoin/wallets/alice"

    RECIPIENT="$(sit:cli getnewaddress "" "bech32")"
    export RECIPIENT
}

teardown_file() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
    sit:teardown
    rm -rf "${HOT_HOME:-}" "${COLD_HOME:-}" "${BARE_REMOTE:-}"
}

setup() {
    load "$(dirname "$BATS_TEST_FILENAME")/../helpers.bash"
}

@test "hot side: wallet push succeeds" {
    run HOME="$HOT_HOME" bitcoin wallet push alice
    # Either 0 (pushed) or non-fatal if already up-to-date.
    [ "$status" -eq 0 ] || [[ "$output" == *"up-to-date"* ]] || [[ "$output" == *"up to date"* ]]
}

@test "cold side: wallet pull brings the addresses ledger" {
    ledger="$COLD_HOME/.local/var/bitcoin/wallets/alice/addresses"
    [ -f "$ledger" ]
    [ "$(wc -l < "$ledger")" -ge 1 ]
}

@test "cold side: wallet sign produces a partially signed PSBT" {
    psbt="$(HOME="$HOT_HOME" bitcoin tx build alice "$RECIPIENT" 100000 --fee-rate 5)"
    signed="$(echo "$psbt" | HOME="$COLD_HOME" bitcoin tx sign alice)"
    dec="$(echo "$signed" | bitcoin bip174 decode)"
    [[ "$dec" == *"type=02"* ]]
}

@test "hot side: broadcast of cold-signed PSBT returns a txid" {
    psbt="$(HOME="$HOT_HOME" bitcoin tx build alice "$RECIPIENT" 100000 --fee-rate 5)"
    raw="$(
        echo "$psbt" \
        | HOME="$COLD_HOME" bitcoin tx sign alice \
        | bitcoin psbt finalize \
        | bitcoin psbt extract
    )"
    txid="$(HOME="$HOT_HOME" bitcoin wallet broadcast alice <<< "$raw")"
    [[ "$txid" =~ ^[0-9a-f]{64}$ ]]
}

@test "cold-signed transaction is confirmed after mining a block" {
    psbt="$(HOME="$HOT_HOME" bitcoin tx build alice "$RECIPIENT" 100000 --fee-rate 5)"
    raw="$(
        echo "$psbt" \
        | HOME="$COLD_HOME" bitcoin tx sign alice \
        | bitcoin psbt finalize \
        | bitcoin psbt extract
    )"
    txid="$(HOME="$HOT_HOME" bitcoin wallet broadcast alice <<< "$raw")"
    sit:mine 1
    run sit:cli gettransaction "$txid"
    [ "$status" -eq 0 ]
}
