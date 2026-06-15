#!/bin/bash
# SIT container entrypoint (FEAT-182): bring up the full regtest stack —
# bitcoind + lightningd (both as the `alice` operator so lightningd's bcli
# plugin, which shells `bitcoin-cli` with alice's ~/.bitcoin, reaches the
# same node) + apache for the CGI account API — then idle.
#
# Runs as the `bitcoin` user (image USER); uses passwordless sudo to drop
# into alice and to start apache. Regtest only; never for production.
set -e

sudo -u alice -i bash -s <<'ALICE'
set -e
export LIGHTNING_NETWORK=regtest  # match the bitcoind backend (default is mainnet)
export LIGHTNING_NO_BOOTSTRAP=1   # no mainnet peer bootstrap in regtest

mkdir -p ~/.bitcoin
cat > ~/.bitcoin/bitcoin.conf <<EOF
regtest=1
server=1
txindex=1
rpcuser=test
rpcpassword=test
fallbackfee=0.0001
EOF

bitcoind -regtest -daemon
for _ in $(seq 1 30); do
	bitcoin-cli -regtest getblockchaininfo >/dev/null 2>&1 && break
	sleep 1
done
bitcoin-cli -regtest createwallet test 2>/dev/null \
	|| bitcoin-cli -regtest loadwallet test 2>/dev/null || true
# Mature some coins so the node is actually usable.
bitcoin-cli -regtest generatetoaddress 101 "$(bitcoin-cli -regtest getnewaddress)" >/dev/null

# Fast bitcoind polling so the SIT suites don't wait ~30s per confirmation
# (CLN's default poll cadence). Written to alice's config before bring-up so
# `lightning daemon start` picks it up. Dev-only; SIT container (BUG-041).
mkdir -p ~/.lightning
printf 'developer\ndev-bitcoind-poll=1\n' > ~/.lightning/config

lightning daemon start
lightning version
# Wait until lightningd has caught up to bitcoind. Channel opens and funding
# need a synced node; exec'ing the bats suites while getinfo still reports a
# sync warning makes the channel/pay suites flake (BUG-038 SIT harness).
for _ in $(seq 1 30); do
	gi=$(lightning-cli --lightning-dir="$HOME/.lightning" --network=regtest getinfo 2>/dev/null) || { sleep 1; continue; }
	echo "$gi" | jq -e '(.warning_lightningd_sync // .warning_bitcoind_sync) | not' >/dev/null 2>&1 && break
	sleep 1
done
echo "alice: lightningd up — $(lightning daemon status 2>/dev/null | head -1)"
ALICE

sudo apache2ctl start
echo "SIT stack up: bitcoind + lightningd (alice) + apache (CGI)"

# If a command was passed (the check-sit bats run), exec it now that the
# stack is up — the suites assume alice's lightningd is already running
# (helpers.bash spins up bob as the second node). With no command, idle so
# `podman run` keeps the stack alive for interactive use (BUG-038).
if [ "$#" -gt 0 ]; then
	exec "$@"
else
	exec tail -F /dev/null
fi
