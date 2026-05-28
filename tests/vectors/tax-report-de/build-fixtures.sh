#!/usr/bin/env bash
# FEAT-039 fixture builder. Materialises a canned wallet (or wallets)
# plus the shared BTC/EUR price cache so `bitcoin tax report-de` has a
# deterministic, offline input. Inputs mirror the real on-disk shapes a
# wallet produces: per-tx mempool-format JSON under <wallet>/transactions/,
# the FEAT-038 label stores under <wallet>/labels/, and the addresses
# ledger. No git repo is needed — the report reads plain files.
#
# Usage: build-fixtures.sh <fixture> <wallets-root> <price-cache-file>
#
#   <fixture>          one of: buy-hold-sell spend-within-year fifo-stacking
#                      self-transfer-chain lending-roundtrip loss-claim channel
#   <wallets-root>     becomes $XDG_DATA_HOME/bitcoin/wallets
#   <price-cache-file> becomes $BITCOIN_PRICE_CACHE
set -eu

FIXTURE="${1:?fixture name required}"
WROOT="${2:?wallets root required}"
PCACHE="${3:?price cache path required}"

# --- price cache (shared; one row per date, source 'test') ---------------
mkdir -p "$(dirname "$PCACHE")"
{
	printf '2022-01-10\t30000\ttest\n'
	printf '2022-02-01\t20000\ttest\n'
	printf '2022-03-01\t40000\ttest\n'
	printf '2022-04-01\t38000\ttest\n'
	printf '2022-06-10\t40000\ttest\n'
	printf '2022-07-01\t36000\ttest\n'
	printf '2022-08-01\t30000\ttest\n'
	printf '2022-09-01\t50000\ttest\n'
	printf '2022-11-10\t50000\ttest\n'
	printf '2023-02-01\t45000\ttest\n'
	printf '2023-03-01\t60000\ttest\n'
	printf '2023-04-01\t35000\ttest\n'
	printf '2023-05-01\t45000\ttest\n'
	printf '2023-06-01\t26000\ttest\n'
	printf '2023-08-01\t48000\ttest\n'
	printf '2023-09-01\t55000\ttest\n'
} > "$PCACHE"

# --- helpers -------------------------------------------------------------
_outs() { # "addr=sats,addr=sats" -> JSON vout array
	local spec="$1" out="[" first=1 pair a v
	IFS=',' read -ra _p <<< "$spec"
	for pair in "${_p[@]}"; do
		a="${pair%%=*}"; v="${pair#*=}"
		[ $first -eq 1 ] || out+=","
		out+="{\"scriptpubkey_address\":\"$a\",\"value\":$v}"
		first=0
	done
	printf '%s]' "$out"
}
_ins() { # "addr=sats,..." (empty -> []) -> JSON vin array
	local spec="$1" out="[" first=1 pair a v
	[ -z "$spec" ] && { printf '[]'; return; }
	IFS=',' read -ra _p <<< "$spec"
	for pair in "${_p[@]}"; do
		a="${pair%%=*}"; v="${pair#*=}"
		[ $first -eq 1 ] || out+=","
		out+="{\"prevout\":{\"scriptpubkey_address\":\"$a\",\"value\":$v}}"
		first=0
	done
	printf '%s]' "$out"
}
_wallet() { # name addr...
	local name="$1"; shift
	local dir="$WROOT/$name"
	mkdir -p "$dir/transactions" "$dir/labels"
	printf 'network=testnet\n' > "$dir/config"
	: > "$dir/addresses"
	local i=0 a
	for a in "$@"; do printf '%s\t%s\t\n' "$i" "$a" >> "$dir/addresses"; i=$((i+1)); done
}
_tx() { # wallet txid date ins_spec outs_spec
	local w="$1" id="$2" d="$3" ins="$4" outs="$5"
	local ts; ts="$(date -u -d "$d" +%s)"
	printf '{"txid":"%s","status":{"block_height":1,"block_time":%s},"vin":%s,"vout":%s}\n' \
		"$id" "$ts" "$(_ins "$ins")" "$(_outs "$outs")" > "$WROOT/$w/transactions/$id.json"
}
_lutxo() { printf '%s\t%s\t\n' "$2" "$3" >> "$WROOT/$1/labels/utxo"; }  # wallet outpoint cat
_ltx()   { printf '%s\t%s\t\n' "$2" "$3" >> "$WROOT/$1/labels/tx";   }  # wallet txid cat

# sats shorthands
B1=100000000; B05=50000000; B06=60000000; B04=40000000; B15=150000000

case "$FIXTURE" in
buy-hold-sell)
	_wallet bhs O_bhs
	_tx bhs f1 2022-03-01 ""            "O_bhs=$B1"
	_lutxo bhs f1:0 purchase
	_tx bhs f2 2023-06-01 "O_bhs=$B1"   "EXT=$B1"
	_ltx bhs f2 sale
	;;
spend-within-year)
	_wallet swy O_swy
	_tx swy g1 2022-03-01 ""            "O_swy=$B05"
	_lutxo swy g1:0 purchase
	_tx swy g2 2022-09-01 "O_swy=$B05"  "EXT=$B05"
	_ltx swy g2 spend
	;;
fifo-stacking)
	_wallet fifo O_fifo
	_tx fifo h1 2022-01-10 ""           "O_fifo=$B1"; _lutxo fifo h1:0 purchase
	_tx fifo h2 2022-06-10 ""           "O_fifo=$B1"; _lutxo fifo h2:0 purchase
	_tx fifo h3 2022-11-10 ""           "O_fifo=$B1"; _lutxo fifo h3:0 purchase
	_tx fifo s1 2023-03-01 "O_fifo=$B1,O_fifo=$B1" "EXT=$B15,O_fifo=$B05"
	_ltx fifo s1 sale; _lutxo fifo s1:1 self-transfer
	_tx fifo s2 2023-09-01 "O_fifo=$B05,O_fifo=$B1" "EXT=$B1,O_fifo=$B05"
	_ltx fifo s2 sale; _lutxo fifo s2:1 self-transfer
	;;
self-transfer-chain)
	_wallet alice O_a
	_wallet bob   O_b
	_wallet carol O_c
	# p1: alice buys
	_tx alice p1 2022-02-01 ""          "O_a=$B1"; _lutxo alice p1:0 purchase
	# p2: alice -> bob (self-transfer); indexed by both
	_tx alice p2 2022-05-01 "O_a=$B1"   "O_b=$B1"; _ltx alice p2 self-transfer
	_tx bob   p2 2022-05-01 "O_a=$B1"   "O_b=$B1"; _lutxo bob p2:0 self-transfer
	# p3: bob -> carol (self-transfer)
	_tx bob   p3 2022-08-01 "O_b=$B1"   "O_c=$B1"; _ltx bob p3 self-transfer
	_tx carol p3 2022-08-01 "O_b=$B1"   "O_c=$B1"; _lutxo carol p3:0 self-transfer
	# p4: carol -> external sale
	_tx carol p4 2023-04-01 "O_c=$B1"   "EXT=$B1"; _ltx carol p4 sale
	;;
lending-roundtrip)
	_wallet lend O_lend
	_tx lend q1 2022-03-01 ""           "O_lend=$B1"; _lutxo lend q1:0 purchase
	_tx lend q2 2023-02-01 "O_lend=$B1" "CPTY=$B1";   _ltx lend q2 lending-out
	_tx lend q3 2023-08-01 ""           "O_lend=$B1"; _lutxo lend q3:0 lending-in
	;;
loss-claim)
	_wallet loss O_loss
	_tx loss r1 2022-08-01 ""            "O_loss=$B1"; _lutxo loss r1:0 purchase
	_tx loss r2 2023-05-01 "O_loss=$B1"  "THIEF=$B1";  _ltx loss r2 loss-claim
	;;
channel)
	_wallet chan O_chan1 O_chan2
	_tx chan t1 2022-04-01 ""              "O_chan1=$B1";  _lutxo chan t1:0 purchase
	_tx chan t2 2022-07-01 "O_chan1=$B1"   "CHANADDR=$B1"; _ltx chan t2 channel-open
	_tx chan t3 2023-03-01 "CHANADDR=$B1"  "EXT=$B06,O_chan2=$B04"
	_ltx chan t3 channel-close; _lutxo chan t3:1 self-transfer
	;;
*)
	echo "build-fixtures.sh: unknown fixture '$FIXTURE'" >&2
	exit 2
	;;
esac
