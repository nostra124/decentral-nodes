#!/usr/bin/env bats
#
# streamline unit tests — part 3 of 4 (FEAT-053 split of tests/unit/streamline.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/streamline.bash.

bats_require_minimum_version 1.5.0
load lib/streamline


@test "FEAT-043 — tx bump rejects a non-integer --fee-rate" {
	run "$BITCOIN_BIN" tx bump alice deadbeef --rbf --fee-rate xyz
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "fee-rate must be a positive integer"
}

@test "FEAT-043 — tx bump errors when the tx is not cached" {
	feat037_setup_wallet
	run "$BITCOIN_BIN" tx bump alice deadbeefcafe --rbf
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "not cached"
}

@test "FEAT-043 — tx bump --rbf refuses a non-signalling tx" {
	feat037_setup_wallet
	# sequence 0xffffffff (4294967295) → final, not BIP-125 replaceable.
	feat043_cache_tx alice f00d 4294967295 bc1qpayee 50000
	run "$BITCOIN_BIN" tx bump alice f00d --rbf
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "does not signal BIP-125"
}

@test "FEAT-043 — tx bump --rbf accepts a signalling tx (past BIP-125 + output checks)" {
	feat037_setup_wallet
	# sequence 0xfffffffd (< 0xfffffffe) → BIP-125 replaceable.
	# One external output (bc1qpayee) + change to bc1qexample (wallet).
	feat043_cache_tx alice cafe 4294967293 bc1qpayee 50000
	run "$BITCOIN_BIN" tx bump alice cafe --rbf --fee-rate 10
	# Build/sign will fail in this seedless env, but the BIP-125 +
	# single-output validation must have PASSED (no parse-stage error).
	echo "$output" | grep -qv "does not signal BIP-125"
	echo "$output" | grep -qv "expected exactly one external output"
}

@test "FEAT-043 — tx bump --rbf refuses a multi-recipient tx" {
	feat037_setup_wallet
	local path="$XDG_DATA_HOME/bitcoin/wallets/alice"
	mkdir -p "$path/transactions"
	# Two external (non-wallet) outputs → ambiguous payment.
	cat > "$path/transactions/multi.json" <<'JSON'
{"txid":"multi","status":{"block_height":"mempool"},
 "vin":[{"txid":"aa","vout":0,"sequence":4294967293,"prevout":{"scriptpubkey_address":"bc1qsrc","value":100000}}],
 "vout":[{"scriptpubkey_address":"bc1qpayee1","value":30000},{"scriptpubkey_address":"bc1qpayee2","value":30000}]}
JSON
	run "$BITCOIN_BIN" tx bump alice multi --rbf
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "expected exactly one external output"
}

@test "FEAT-043 — tx bump --cpfp errors when no wallet output of the tx is spendable" {
	feat037_setup_wallet
	feat043_cache_tx alice beef 4294967293 bc1qpayee 50000
	# No backend fixtures → utxo:ls finds nothing for this txid.
	run "$BITCOIN_BIN" tx bump alice beef --cpfp
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "no spendable wallet output"
}

@test "FEAT-043 — tx help lists the bump subcommand" {
	run bash -c "'$BITCOIN_BIN' tx help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE "(^|[[:space:]])bump([[:space:]]|$)"
	echo "$output" | grep -q "rbf"
	echo "$output" | grep -q "cpfp"
}

@test "FEAT-040 — price help lists every subcommand" {
	run bash -c "'$BITCOIN_BIN' price help 2>&1"
	[ "$status" -eq 0 ]
	for sub in get fetch source status; do
		echo "$output" | grep -qE "(^|[[:space:]])$sub([[:space:]]|$)" \
			|| { echo "help missing: $sub"; return 1; }
	done
}

@test "FEAT-040 — price (no subcommand) prints help" {
	run "$BITCOIN_BIN" price
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "Usage:"
}

@test "FEAT-040 — price <unknown> errors" {
	run "$BITCOIN_BIN" price wat
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "unknown price subcommand"
}

@test "FEAT-266 — price get with no date returns the current spot price" {
	feat040_coingecko_stub
	run "$BITCOIN_BIN" price get
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "43210"
}

@test "FEAT-266 — price get spot errors clearly for a non-coingecko source" {
	export BITCOIN_PRICE_SOURCE="kraken"
	run "$BITCOIN_BIN" price get
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "only supported for the coingecko source"
}

@test "FEAT-271 — config list is TSV (name/value/description) with effective values + defaults" {
	feat271_env
	run "$BITCOIN_BIN" config list
	[ "$status" -eq 0 ]
	echo "$output" | head -1 | grep -q 'NAME'
	# conf value overrides the default:
	echo "$output" | awk -F'\t' '$1=="dbcache"&&$2=="600"{f=1} END{exit !f}'
	# an unset option shows its compiled-in default + description:
	echo "$output" | awk -F'\t' '$1=="maxconnections"&&$2=="125"&&$3~/Maintain at most/{f=1} END{exit !f}'
	# a conf-only key (not in -help) still appears:
	echo "$output" | awk -F'\t' '$1=="server"&&$2=="1"{f=1} END{exit !f}'
	# a no-default option shows an EMPTY value, not its description (the
	# `read`-collapsing / multi-line-default bug the user hit):
	echo "$output" | awk -F'\t' '$1=="alertnotify"&&$2==""&&$3~/Execute command/{f=1} END{exit !f}'
	# the (4 to 16384, default: 450) clause is stripped from the description:
	echo "$output" | awk -F'\t' '$1=="dbcache"&&$3!~/default:/{f=1} END{exit !f}'
}

@test "FEAT-271 — config list --set shows only the conf-set keys" {
	feat271_env
	run "$BITCOIN_BIN" config list --set
	[ "$status" -eq 0 ]
	echo "$output" | awk -F'\t' '$1=="server"&&$2=="1"{f=1} END{exit !f}'
	echo "$output" | awk -F'\t' '$1=="dbcache"&&$2=="600"{f=1} END{exit !f}'
	# maxconnections is a default-only key → excluded by --set
	! echo "$output" | awk -F'\t' '$1=="maxconnections"{f=1} END{exit !f}'
}

@test "FEAT-271 — config get returns the conf value (source: conf)" {
	feat271_env
	run "$BITCOIN_BIN" config get dbcache
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '600'
}

@test "FEAT-271 — config get falls back to the bitcoind default" {
	feat271_env
	run "$BITCOIN_BIN" config get maxconnections
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '125'
}

@test "FEAT-271 — config set replaces/adds a key and warns to restart" {
	feat271_env
	run "$BITCOIN_BIN" config set prune 550
	[ "$status" -eq 0 ]
	echo "$output" | grep -qi 'restart'
	grep -q '^prune=550' "$BITCOIN_CONFIG_DATADIR/bitcoin.conf"
}

@test "FEAT-271 — config unset removes a key" {
	feat271_env
	"$BITCOIN_BIN" config set foo bar
	"$BITCOIN_BIN" config unset foo
	! grep -q '^foo=' "$BITCOIN_CONFIG_DATADIR/bitcoin.conf"
}

@test "FEAT-271 — config get errors for an unknown key with no default" {
	feat271_env
	run "$BITCOIN_BIN" config get totallyboguskey
	[ "$status" -ne 0 ]
}

@test "FEAT-271 — config path prints the conf file" {
	feat271_env
	run "$BITCOIN_BIN" config path
	[ "$status" -eq 0 ]
	[ "$output" = "$BITCOIN_CONFIG_DATADIR/bitcoin.conf" ]
}

@test "FEAT-040 — price get rejects a malformed date" {
	run "$BITCOIN_BIN" price get 2024/01/01
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "not a valid ISO-8601 date"
}

@test "FEAT-040 — price get on an empty cache warns to fetch" {
	feat040_env
	run "$BITCOIN_BIN" price get 2024-01-01
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "price fetch"
}

@test "FEAT-040 — price source defaults to coingecko" {
	feat040_env
	run "$BITCOIN_BIN" price source
	[ "$status" -eq 0 ]
	[ "$output" = "coingecko" ]
}

@test "FEAT-040 — price source --set kraken persists" {
	feat040_env
	"$BITCOIN_BIN" price source --set kraken >/dev/null
	run "$BITCOIN_BIN" price source
	[ "$output" = "kraken" ]
}

@test "FEAT-040 — price source --set rejects an unknown source" {
	feat040_env
	run "$BITCOIN_BIN" price source --set ftp://nope
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "unknown source"
}

@test "FEAT-040 — csv source fetch + get round-trips with no network" {
	feat040_env
	printf '2024-01-01,42000,x\n2024-01-02,43000,x\n2024-01-09,50000,x\n' > "$HOME/prices.csv"
	"$BITCOIN_BIN" price source --set "csv://$HOME/prices.csv" >/dev/null
	"$BITCOIN_BIN" price fetch --from 2024-01-01 --to 2024-01-07 >/dev/null
	[ "$("$BITCOIN_BIN" price get 2024-01-01)" = "42000" ]
	[ "$("$BITCOIN_BIN" price get 2024-01-02)" = "43000" ]
	# 2024-01-09 is outside the fetched range → not cached.
	run "$BITCOIN_BIN" price get 2024-01-09
	[ "$status" -ne 0 ]
}

@test "FEAT-040 — price fetch is idempotent (re-fetch adds zero rows)" {
	feat040_env
	printf '2024-01-01,42000,x\n' > "$HOME/prices.csv"
	"$BITCOIN_BIN" price source --set "csv://$HOME/prices.csv" >/dev/null
	"$BITCOIN_BIN" price fetch --from 2024-01-01 --to 2024-01-01 >/dev/null
	rows1="$(grep -c . "$BITCOIN_PRICE_CACHE")"
	"$BITCOIN_BIN" price fetch --from 2024-01-01 --to 2024-01-01 >/dev/null
	rows2="$(grep -c . "$BITCOIN_PRICE_CACHE")"
	[ "$rows1" = "$rows2" ]
}

@test "FEAT-040 — price fetch rejects --from after --to" {
	feat040_env
	run "$BITCOIN_BIN" price fetch --from 2024-02-01 --to 2024-01-01
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "is after"
}

@test "FEAT-040 — coingecko fetch via curl stub populates the cache" {
	feat040_env
	feat040_coingecko_stub
	# default source is coingecko
	run "$BITCOIN_BIN" price fetch --from 2024-03-01 --to 2024-03-03
	[ "$status" -eq 0 ]
	# Three days fetched, each at the stub's fixed price.
	[ "$("$BITCOIN_BIN" price get 2024-03-02)" = "42000.5" ]
	rows="$(grep -c . "$BITCOIN_PRICE_CACHE")"
	[ "$rows" = "3" ]
}

@test "FEAT-040 — price status reports coverage" {
	feat040_env
	mkdir -p "$(dirname "$BITCOIN_PRICE_CACHE")"
	# Cache is TSV (tab-separated): date, eur_per_btc, source.
	printf '2024-01-01\t42000\tcsv\n2024-01-05\t46000\tcsv\n' > "$BITCOIN_PRICE_CACHE"
	run "$BITCOIN_BIN" price status
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "rows: 2"
	echo "$output" | grep -q "2024-01-01 .. 2024-01-05"
}

@test "FEAT-034 — enable --user (linux) installs a rootless systemd unit" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	local unit="$XDG_CONFIG_HOME/systemd/user/bitcoind.service"
	[ -f "$unit" ]
	grep -q "ExecStart=$BITCOIN_BITCOIND " "$unit"
	# A --user systemd unit may not carry User=.
	! grep -q '^User=' "$unit"
	grep -q 'systemctl --user enable --now bitcoind' "$FEAT034_CALLS"
}

@test "BUG-048 — enable refuses when the RPC port is already in use (no crash-looping unit)" {
	feat034_env linux
	export BITCOIN_PORT_BUSY=8332    # an existing bitcoind already owns mainnet RPC
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"8332"* ]]
	[[ "$output" == *"in use"* ]]
	# The bug: a unit got installed and then crash-looped on bind failure.
	[ ! -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
}

@test "BUG-048 — enable proceeds when only a DIFFERENT network's port is busy" {
	feat034_env linux
	export BITCOIN_PORT_BUSY=18443   # regtest port busy, but we enable mainnet (8332)
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	[ -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
}

# --- uniform `daemon status` (parity with lightning/monero) ----------------

@test "daemon status: healthy reports the block height via bitcoin-cli, no sudo" {
	feat034_env linux
	# Stub bitcoin-cli to answer getblockchaininfo with a synced node.
	export BITCOIN_CLI="$HOME/bitcoin-cli-stub"
	cat > "$BITCOIN_CLI" <<-'STUB'
		#!/usr/bin/env bash
		case "$*" in
			*getblockchaininfo*) echo '{"chain":"main","blocks":850000,"headers":850000}' ;;
			*) exit 0 ;;
		esac
	STUB
	chmod +x "$BITCOIN_CLI"
	run "$BITCOIN_BIN" daemon status --user
	[ "$status" -eq 0 ]
	[[ "$output" == *"healthy"* ]]
	[[ "$output" == *"850000"* ]]
	! grep -q '^sudo ' "$FEAT034_CALLS"
}

@test "daemon status: syncing reports blocks/headers when behind" {
	feat034_env linux
	export BITCOIN_CLI="$HOME/bitcoin-cli-stub"
	cat > "$BITCOIN_CLI" <<-'STUB'
		#!/usr/bin/env bash
		echo '{"chain":"main","blocks":700000,"headers":850000}'
	STUB
	chmod +x "$BITCOIN_CLI"
	run "$BITCOIN_BIN" daemon status --user
	[ "$status" -eq 0 ]
	[[ "$output" == *"syncing"* ]]
	[[ "$output" == *"700000/850000"* ]]
}

@test "daemon status: down errors non-zero with a hint when bitcoind is unreachable" {
	feat034_env linux
	export BITCOIN_CLI="$HOME/bitcoin-cli-stub"
	printf '#!/usr/bin/env bash\nexit 1\n' > "$BITCOIN_CLI"   # cli fails => empty
	chmod +x "$BITCOIN_CLI"
	run "$BITCOIN_BIN" daemon status --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"down"* ]]
	[[ "$output" == *"not reachable"* ]]
}

@test "daemon help + status help list the status verb" {
	run "$BITCOIN_BIN" daemon help
	[ "$status" -eq 0 ] || [ -n "$output" ]
	[[ "$output" == *"status"* ]]
	run "$BITCOIN_BIN" daemon help status
	[[ "$output" == *"reachable"* ]]
}

@test "FEAT-307: top-level 'bitcoin install' routes to the daemon installer (canonical) " {
	# Harmonized: install is a top-level verb on every command. The old
	# 'bitcoin daemon install' keeps working as an alias.
	run "$BITCOIN_BIN" install --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"install"* ]]
	run "$BITCOIN_BIN" daemon install --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"install"* ]]
}

@test "BUG-053: status detects the running node's datadir (external node)" {
	feat034_env linux
	# A running bitcoind at an external (MacPorts) datadir; cli reads it.
	export BITCOIN_PS="bitcoind -datadir=/opt/local/var/lib/bitcoind -conf=/opt/local/etc/bitcoin/bitcoin.conf"
	export BITCOIN_CLI="$HOME/bitcoin-cli-stub"
	cat > "$BITCOIN_CLI" <<-'STUB'
		#!/usr/bin/env bash
		# Echo the JSON only when pointed at the detected external datadir.
		case "$*" in
			*-datadir=/opt/local/var/lib/bitcoind*getblockchaininfo*)
				echo '{"chain":"main","blocks":850000,"headers":850000}' ;;
			*) exit 1 ;;
		esac
	STUB
	chmod +x "$BITCOIN_CLI"
	run "$BITCOIN_BIN" daemon status --system
	[ "$status" -eq 0 ]
	[[ "$output" == *"healthy"* ]]
	[[ "$output" == *"850000"* ]]
}

@test "BUG-053: status reports 'up but unauthorized' when the node listens but the cookie is unreadable" {
	feat034_env linux
	export BITCOIN_PS="bitcoind -datadir=/opt/local/var/lib/bitcoind"
	export BITCOIN_PORT_BUSY=8332          # a node IS listening on mainnet RPC
	export BITCOIN_CLI="$HOME/bitcoin-cli-stub"
	printf '#!/usr/bin/env bash\nexit 1\n' > "$BITCOIN_CLI"   # cookie unreadable
	chmod +x "$BITCOIN_CLI"
	run "$BITCOIN_BIN" daemon status --system
	[ "$status" -ne 0 ]
	[[ "$output" == *"up but unauthorized"* ]]
	[[ "$output" == *"share-cookie"* ]]
}

# --- FEAT-306: share-cookie (let siblings read the running node's cookie) ---

@test "FEAT-306: share-cookie sets rpccookieperms=group in the running node's conf + restarts" {
	feat034_env linux
	local conf="$HOME/ext-bitcoin.conf"
	printf 'server=1\nrest=1\n' > "$conf"
	export BITCOIN_PS="bitcoin 821 /opt/local/bin/bitcoind -datadir=/opt/local/var/lib/bitcoind -conf=$conf"
	run "$BITCOIN_BIN" daemon share-cookie
	[ "$status" -eq 0 ]
	grep -q '^rpccookieperms=group' "$conf"
	[ "$(grep -c '^rpccookieperms' "$conf")" -eq 1 ]   # no duplicate
	grep -q 'systemctl .*restart' "$FEAT034_CALLS"
}

@test "FEAT-306: share-cookie is idempotent when rpccookieperms=group is already set" {
	feat034_env linux
	local conf="$HOME/ext-bitcoin.conf"
	printf 'server=1\nrpccookieperms=group\n' > "$conf"
	export BITCOIN_PS="bitcoind -datadir=/opt/local/var/lib/bitcoind -conf=$conf"
	run "$BITCOIN_BIN" daemon share-cookie
	[ "$status" -eq 0 ]
	# Idempotent: the single existing line is untouched (the "already set"
	# info is suppressed by SELF_QUIET=1 in setup).
	[ "$(grep -c '^rpccookieperms' "$conf")" -eq 1 ]
	grep -q '^rpccookieperms=group' "$conf"
}

@test "FEAT-306: share-cookie --no-restart sets the option but does not restart" {
	feat034_env linux
	local conf="$HOME/ext-bitcoin.conf"
	printf 'server=1\n' > "$conf"
	export BITCOIN_PS="bitcoind -conf=$conf"
	run "$BITCOIN_BIN" daemon share-cookie --no-restart
	[ "$status" -eq 0 ]
	grep -q '^rpccookieperms=group' "$conf"
	[[ "$output" == *"restart bitcoind"* ]]
	[ ! -f "$FEAT034_CALLS" ] || ! grep -q 'restart' "$FEAT034_CALLS"
}

@test "FEAT-306: share-cookie errors when no bitcoind is running" {
	feat034_env linux
	export BITCOIN_PS=""   # nothing running
	run "$BITCOIN_BIN" daemon share-cookie
	[ "$status" -ne 0 ]
	[[ "$output" == *"no running bitcoind"* ]]
}
