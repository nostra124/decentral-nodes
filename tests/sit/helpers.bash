#!/usr/bin/env bash
# SIT helpers for the bitcoin regtest suite.
#
# Sourced by every suite under tests/sit/suites/. Provides functions
# to start/stop a bitcoind container, run bitcoin-cli commands against
# it, and install the local bitcoin build into a clean HOME.

SIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SIT_DIR/../.." && pwd)"
SIT_CONTAINER_NAME="bitcoin-sit-$$"
# Host-side RPC port. NOT 18443 (the regtest default) — that collides with any
# regtest bitcoind already running on the host (e.g. a `bitcoin daemon`), which
# made `sit:start_bitcoind` fail to bind and time out. Derive a per-run port
# from the PID; the container still listens on 18443 internally (BUG-046).
SIT_RPC_PORT="$(( 18500 + ($$ % 1000) ))"
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
    export SIT_HOME="$(mktemp -d)"
    export HOME="$SIT_HOME"
    export XDG_DATA_HOME="$SIT_HOME/.local/share"
    export XDG_CONFIG_HOME="$SIT_HOME/.config"
    export XDG_STATE_HOME="$SIT_HOME/.local/state"
    unset XDG_CACHE_HOME
    # Keep config in the throwaway HOME — config:_confdir otherwise prefers a
    # real /etc/bitcoin if one exists on the host, which both leaks test rpc
    # settings into it and hides the test's own backend config (BUG-046).
    export BITCOIN_CONFIG_DIR="$SIT_HOME/.config/bitcoin"
    mkdir -p "$BITCOIN_CONFIG_DIR"
    # `config set` won't create a fresh bitcoin.conf (it tells you to run
    # `daemon enable` first); seed an empty one so the backend can be set.
    : > "$BITCOIN_CONFIG_DIR/bitcoin.conf"

    # Reconfigure for the test prefix, then install. The Makefile hard-assigns
    # PREFIX/BINDIR/… at configure time, so `PREFIX=… make install` alone does
    # NOT relocate the install — it lands in the configured prefix, and the
    # suite then runs the host's *real* (possibly stale) bitcoin instead. So
    # configure explicitly here (BUG-046).
    ( cd "$REPO_ROOT" && rm -rf build \
        && ./configure --prefix="$SIT_HOME/.local" >/dev/null 2>&1 \
        && make install >/dev/null 2>&1 )
    export PATH="$SIT_HOME/.local/bin:$PATH"
    hash -r

    # `bitcoin wallet new` stores the seed in `secret`, which needs a
    # GPG-backed identity. Provision one non-interactively in the throwaway
    # HOME (account init does a batch, passphrase-less keygen) — BUG-046.
    export GNUPGHOME="$SIT_HOME/.gnupg"
    account init   >/dev/null 2>&1 || true
    secret  setup  >/dev/null 2>&1 || true
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


# ===========================================================================
# Lightning SIT helpers (merged from nostra124/lightning, FEAT-182).
# Bitcoin (sit:*) and Lightning (sit_*) helper namespaces are disjoint;
# bitcoin suites load the sit:* set, lightning suites the sit_* set.
# ===========================================================================
# Shared SIT helpers (FEAT-182).
#
# Sourced from every tests/sit/suites/*.bats file. Provides:
#   - sit_setup_alice_bob: spin up two lightningd instances
#     on the same regtest bitcoind, fund alice, connect them.
#   - sit_teardown: stop everything; remove temp dirs.
#   - sit_mine N: mine N blocks; returns once they're seen.

set -euo pipefail

: "${LIGHTNING_DIR:=/home/alice/.lightning}"
: "${LIGHTNING_NETWORK:=regtest}"

BTCCLI() {
	bitcoin-cli -regtest -rpcuser=test -rpcpassword=test "$@"
}

cli_alice() { lightning-cli --lightning-dir="$LIGHTNING_DIR" --network="$LIGHTNING_NETWORK" "$@"; }

sit_mine() {
	local n="${1:-1}"
	local addr
	addr=$(BTCCLI getnewaddress)
	BTCCLI generatetoaddress "$n" "$addr" >/dev/null
	# Block until the lightning node(s) have followed the new tip. CLN's
	# bcli backend polls bitcoind only ~every 30 s, so without this wait
	# fundchannel/listfunds race ahead of the node's view of the chain and
	# see zero confirmed UTXOs. This honours sit_mine's documented contract
	# ("returns once they're seen"). BUG-038 SIT harness.
	local tip; tip=$(BTCCLI getblockcount)
	local _ h bh
	for _ in $(seq 1 45); do
		h=$(cli_alice getinfo 2>/dev/null | jq -r '.blockheight // 0')
		if [ "$h" = "$tip" ]; then
			[ -n "${BOB_DIR:-}" ] || return 0
			bh=$(lightning-cli --lightning-dir="$BOB_DIR" --network="$LIGHTNING_NETWORK" getinfo 2>/dev/null | jq -r '.blockheight // 0')
			[ "$bh" = "$tip" ] && return 0
		fi
		sleep 1
	done
}

# A second lightningd for the peer side of every test.
BOB_DIR=""
BOB_PORT=9836

sit_setup_alice_bob() {
	# alice is the operator's lightningd (already running via
	# the container CMD); bob is a fresh second instance.
	BOB_DIR=$(mktemp -d /tmp/bob.XXXXXX)
	# CLN 24.11 refuses `--daemon` without `--log-file` ("--daemon needs
	# --log-file"), so give bob an explicit log. Also disable cln-grpc: it is
	# marked "important", so when it exits (no grpc port configured) it takes
	# lightningd down with it — the same plugin alice's wiring disables
	# (BUG-033/BUG-038 SIT harness).
	# --developer + --dev-bitcoind-poll=1: poll bitcoind every 1s instead of
	# CLN's ~30s default, so the suites don't wait half a minute per
	# confirmation (BUG-041). alice gets the same via its config file.
	lightningd --lightning-dir="$BOB_DIR" --network="$LIGHTNING_NETWORK" \
	           --bitcoin-rpcuser=test --bitcoin-rpcpassword=test \
	           --addr="127.0.0.1:$BOB_PORT" --daemon \
	           --disable-plugin=cln-grpc \
	           --disable-plugin=clnrest --disable-plugin=wss-proxy \
	           --developer --dev-bitcoind-poll=1 \
	           --log-file="$BOB_DIR/log"
	# Wait for both nodes to reach getinfo.
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		cli_alice getinfo >/dev/null 2>&1 \
			&& lightning-cli --lightning-dir="$BOB_DIR" --network="$LIGHTNING_NETWORK" getinfo >/dev/null 2>&1 \
			&& break
		sleep 1
	done

	# Fund alice on-chain.
	local alice_addr
	alice_addr=$(cli_alice newaddr | jq -r '.bech32 // .p2tr // .p2wkh')
	BTCCLI sendtoaddress "$alice_addr" 1 >/dev/null
	sit_mine 6
}

sit_bob_id() {
	lightning-cli --lightning-dir="$BOB_DIR" --network="$LIGHTNING_NETWORK" getinfo | jq -r .id
}

sit_open_channel() {
	# Open a 100k sat channel alice -> bob.
	local bob_id; bob_id=$(sit_bob_id)
	lightning channel open "${bob_id}@127.0.0.1:${BOB_PORT}" 100000 >/dev/null
	sit_mine 6
	# Wait for the channel to be ACTIVE.
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		cli_alice listpeerchannels | jq -e '.channels[] | select(.state == "CHANNELD_NORMAL")' >/dev/null 2>&1 && return 0
		sit_mine 1
		sleep 1
	done
	return 1
}

sit_teardown() {
	if [ -n "$BOB_DIR" ] && [ -d "$BOB_DIR" ]; then
		lightning-cli --lightning-dir="$BOB_DIR" --network="$LIGHTNING_NETWORK" stop 2>/dev/null || true
		rm -rf "$BOB_DIR"
		BOB_DIR=""
	fi
}
