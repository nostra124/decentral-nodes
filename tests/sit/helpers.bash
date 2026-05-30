#!/usr/bin/env bash
# SIT helpers for the bitcoin regtest suite.
#
# Sourced by every suite under tests/sit/suites/. Provides functions
# to start/stop a bitcoind container, run bitcoin-cli commands against
# it, and install the local bitcoin build into a clean HOME.

SIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SIT_DIR/../.." && pwd)"
SIT_CONTAINER_NAME="bitcoin-sit-$$"
SIT_RPC_PORT=18443
SIT_RPC_USER="regtest"
SIT_RPC_PASS="regtest"

# Start a fresh bitcoind regtest container. Sets SIT_CONTAINER_ID.
sit:start_bitcoind() {
    podman build -q -t bitcoin-sit-bitcoind \
        "$SIT_DIR/podman" -f "$SIT_DIR/podman/Dockerfile.bitcoind" >/dev/null
    SIT_CONTAINER_ID="$(podman run -d --rm \
        --name "$SIT_CONTAINER_NAME" \
        -p "127.0.0.1:${SIT_RPC_PORT}:18443" \
        bitcoin-sit-bitcoind)"
    # Wait until bitcoind is ready (up to 30 s).
    local tries=0
    while ! sit:cli getblockchaininfo >/dev/null 2>&1; do
        sleep 1
        (( tries++ ))
        if (( tries >= 30 )); then
            echo "SIT: bitcoind did not become ready in 30 s" >&2
            return 1
        fi
    done
}

# Stop and remove the bitcoind container.
sit:stop_bitcoind() {
    if [ -n "${SIT_CONTAINER_ID:-}" ]; then
        podman stop "$SIT_CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
    SIT_CONTAINER_ID=""
}

# Run a bitcoin-cli command against the regtest node.
sit:cli() {
    bitcoin-cli \
        -rpcconnect=127.0.0.1 \
        -rpcport="$SIT_RPC_PORT" \
        -rpcuser="$SIT_RPC_USER" \
        -rpcpassword="$SIT_RPC_PASS" \
        -regtest \
        "$@"
}

# Mine <n> blocks to a given address (or generate a new one).
sit:mine() {
    local n="${1:-1}"
    local addr="${2:-}"
    if [ -z "$addr" ]; then
        addr="$(sit:cli getnewaddress "" "bech32")"
    fi
    sit:cli generatetoaddress "$n" "$addr" >/dev/null
}

# Fund a bitcoin wallet address from the regtest coinbase and mine
# one confirmation. Returns the funded txid.
sit:fund_address() {
    local addr="$1" sats="${2:-1000000}"
    local btc; btc="$(echo "scale=8; $sats / 100000000" | bc)"
    # Mine 101 blocks first so coinbase is spendable.
    sit:mine 101
    local txid; txid="$(sit:cli sendtoaddress "$addr" "$btc")"
    sit:mine 1
    printf '%s\n' "$txid"
}

# Install the local bitcoin checkout into a test HOME. Expects the
# repo to have been configured (./configure run). Sets SIT_HOME and
# exports it.
sit:install_bitcoin() {
    SIT_HOME="$(mktemp -d)"
    export HOME="$SIT_HOME"
    export XDG_DATA_HOME="$SIT_HOME/.local/share"
    export XDG_CONFIG_HOME="$SIT_HOME/.config"
    export XDG_STATE_HOME="$SIT_HOME/.local/state"
    unset XDG_CACHE_HOME

    PREFIX="$SIT_HOME/.local" make -C "$REPO_ROOT" install >/dev/null 2>&1
    export PATH="$SIT_HOME/.local/bin:$PATH"
}

# Tear down the test HOME created by sit:install_bitcoin.
sit:teardown() {
    sit:stop_bitcoind
    if [ -n "${SIT_HOME:-}" ]; then
        rm -rf "$SIT_HOME"
        SIT_HOME=""
    fi
}

# Configure the local bitcoin tool to use the regtest bitcoind backend.
sit:configure_backend() {
    bitcoin backend set bitcoind
    bitcoin config set rpc.url "http://127.0.0.1:${SIT_RPC_PORT}"
    bitcoin config set rpc.user "$SIT_RPC_USER"
    bitcoin config set rpc.pass "$SIT_RPC_PASS"
}
