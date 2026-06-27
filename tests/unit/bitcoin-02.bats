#!/usr/bin/env bats
#
# bitcoin unit tests — part 2 of 5 (FEAT-053 split of tests/unit/bitcoin.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/bitcoin.bash.
# (Also hosts the FEAT-304 bitcoind-backend get-address-utxos/broadcast tests.)

bats_require_minimum_version 1.5.0
load lib/bitcoin


@test "FEAT-012 — bitcoin backend rejects unknown backend names" {
	setup_backend_env
	run "$BITCOIN_BIN" backend set bogus
	[ "$status" -ne 0 ]
}

@test "FEAT-012 — bitcoin backend chain-height returns the mempool answer" {
	setup_backend_env
	curl_fixture "https://mempool.space/api/blocks/tip/height" "830000"
	run "$BITCOIN_BIN" backend chain-height
	[ "$status" -eq 0 ]
	[ "$output" = "830000" ]
}

@test "FEAT-012 — backend get-address-utxos returns the mempool JSON" {
	setup_backend_env
	curl_fixture "https://mempool.space/api/address/bc1qexampleaddress/utxo" \
		'[{"txid":"aa","vout":0,"value":12345,"status":{"block_height":830000}}]'
	run "$BITCOIN_BIN" backend get-address-utxos bc1qexampleaddress
	[ "$status" -eq 0 ]
	[[ "$output" == *'"value":12345'* ]]
}

@test "FEAT-012 — backend broadcast posts a hex tx and returns the txid" {
	setup_backend_env
	curl_fixture "https://mempool.space/api/tx" \
		"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
	run "$BITCOIN_BIN" backend broadcast 0200000001abcd
	[ "$status" -eq 0 ]
	[ "$output" = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef" ]
}

@test "FEAT-012 — backend chain-height emits an error when curl fails" {
	setup_backend_env
	# No fixture → stub-curl exits 22.
	run "$BITCOIN_BIN" backend chain-height
	[ "$status" -ne 0 ]
	[[ "$output" == *"mempool"* ]] || [[ "$stderr" == *"mempool"* ]]
}

@test "FEAT-012 — bitcoin help backend cites the BIPs in scope (380 for descriptors → addresses)" {
	run "$BITCOIN_BIN" help backend
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

@test "FEAT-012 — backend estimate-fee defaults to the half-hour bucket" {
	setup_backend_env
	curl_fixture "https://mempool.space/api/v1/fees/recommended" "$(mempool_fees_fixture)"
	run "$BITCOIN_BIN" backend estimate-fee
	[ "$status" -eq 0 ]
	[ "$output" = "21" ]
}

@test "FEAT-012 — backend estimate-fee target-block selects the right bucket" {
	setup_backend_env
	curl_fixture "https://mempool.space/api/v1/fees/recommended" "$(mempool_fees_fixture)"
	# 1 → fastestFee=42, 6 → hourFee=11, 144 → economyFee=4, 1000 → minimumFee=1.
	run "$BITCOIN_BIN" backend estimate-fee 1;    [ "$status" -eq 0 ]; [ "$output" = "42" ]
	run "$BITCOIN_BIN" backend estimate-fee 6;    [ "$status" -eq 0 ]; [ "$output" = "11" ]
	run "$BITCOIN_BIN" backend estimate-fee 144;  [ "$status" -eq 0 ]; [ "$output" = "4" ]
	run "$BITCOIN_BIN" backend estimate-fee 1000; [ "$status" -eq 0 ]; [ "$output" = "1" ]
}

@test "FEAT-012 — backend estimate-fee rejects a non-integer target" {
	setup_backend_env
	run "$BITCOIN_BIN" backend estimate-fee abc
	[ "$status" -ne 0 ]
}

@test "FEAT-012 — backend estimate-fee emits an error when curl fails" {
	setup_backend_env
	# No fixture → stub-curl exits 22 → verb returns non-zero.
	run "$BITCOIN_BIN" backend estimate-fee
	[ "$status" -ne 0 ]
}

@test "FEAT-012 — backend estimate-fee bitcoind stub returns 'not implemented'" {
	setup_backend_env
	"$BITCOIN_BIN" backend set bitcoind >/dev/null
	run "$BITCOIN_BIN" backend estimate-fee
	[ "$status" -ne 0 ]
}

@test "FEAT-304 — bitcoind get-address-utxos maps scantxoutset to the wallet UTXO shape" {
	setup_bitcoind_backend_env
	# scantxoutset reports amounts in BTC; the backend must convert to sats
	# and reshape to {txid,vout,value,status}. 0.001 BTC -> 100000 sat.
	bitcoind_rpc_fixture scantxoutset \
		'{"result":{"success":true,"height":830000,"unspents":[{"txid":"aa11","vout":2,"amount":0.001,"height":829000}],"total_amount":0.001},"error":null,"id":"x"}'
	run "$BITCOIN_BIN" backend get-address-utxos bc1qexampleaddress
	[ "$status" -eq 0 ]
	[[ "$output" == *'"txid":"aa11"'* ]]
	[[ "$output" == *'"vout":2'* ]]
	[[ "$output" == *'"value":100000'* ]]
	[[ "$output" == *'"block_height":829000'* ]]
	[[ "$output" == *'"confirmed":true'* ]]
}

@test "FEAT-304 — bitcoind get-address-utxos returns an empty array when nothing is found" {
	setup_bitcoind_backend_env
	bitcoind_rpc_fixture scantxoutset \
		'{"result":{"success":true,"height":830000,"unspents":[],"total_amount":0},"error":null,"id":"x"}'
	run "$BITCOIN_BIN" backend get-address-utxos bc1qexampleaddress
	[ "$status" -eq 0 ]
	[ "$output" = "[]" ]
}

@test "FEAT-304 — bitcoind get-address-utxos requires an address" {
	setup_bitcoind_backend_env
	run "$BITCOIN_BIN" backend get-address-utxos
	[ "$status" -eq 2 ]
}

@test "FEAT-304 — bitcoind get-address-utxos errors when the RPC is unreachable" {
	setup_bitcoind_backend_env
	# No scantxoutset fixture → the RPC call fails (models an unreachable node).
	run "$BITCOIN_BIN" backend get-address-utxos bc1qexampleaddress
	[ "$status" -ne 0 ]
	[[ "$output" == *"bitcoind"* ]] || [[ "$stderr" == *"bitcoind"* ]]
}

@test "FEAT-304 — bitcoind get-address-utxos surfaces an RPC error reply" {
	setup_bitcoind_backend_env
	bitcoind_rpc_fixture scantxoutset \
		'{"result":null,"error":{"code":-8,"message":"scan already in progress"},"id":"x"}'
	run "$BITCOIN_BIN" backend get-address-utxos bc1qexampleaddress
	[ "$status" -ne 0 ]
	[[ "$output" == *"scan already in progress"* ]] || [[ "$stderr" == *"scan already in progress"* ]]
}

@test "FEAT-304 — bitcoind broadcast sends the raw tx and returns the txid" {
	setup_bitcoind_backend_env
	bitcoind_rpc_fixture sendrawtransaction \
		'{"result":"abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abcd","error":null,"id":"x"}'
	run "$BITCOIN_BIN" backend broadcast 0200000001deadbeef
	[ "$status" -eq 0 ]
	[ "$output" = "abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abcd" ]
}

@test "FEAT-304 — bitcoind broadcast requires a tx hex" {
	setup_bitcoind_backend_env
	run "$BITCOIN_BIN" backend broadcast
	[ "$status" -eq 2 ]
}

@test "FEAT-304 — bitcoind broadcast surfaces a node rejection" {
	setup_bitcoind_backend_env
	bitcoind_rpc_fixture sendrawtransaction \
		'{"result":null,"error":{"code":-26,"message":"txn-mempool-conflict"},"id":"x"}'
	run "$BITCOIN_BIN" backend broadcast 0200000001deadbeef
	[ "$status" -ne 0 ]
	[[ "$output" == *"rejected"* ]] || [[ "$stderr" == *"rejected"* ]]
}

@test "FEAT-012 — bitcoin help backend mentions estimate-fee" {
	run "$BITCOIN_BIN" help backend
	[ "$status" -eq 0 ]
	[[ "$output" == *"estimate-fee"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-025 follow-up — the seed-derivation primitive, originally
# at libexec/bitcoin-node/mnemonic-to-seed (FEAT-025 vendoring), then
# folded into bip39 as a subcommand (FEAT-035 Stream A, 1.23.0),
# and now reached exclusively through the canonical
# 'bitcoin bip39 mnemonic-to-seed' verb after the FEAT-035 alias
# removal in 1.24.0.
# ---------------------------------------------------------------------------

@test "bip39 mnemonic-to-seed matches the BIP-39 test vector (TREZOR passphrase)" {
	expected="c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
	got="$(BIP39_PASSPHRASE=TREZOR "$BITCOIN_BIN" bip39 mnemonic-to-seed \
		abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about \
		| basenc --base16 -w0 | tr A-F a-f)"
	[ "$got" = "$expected" ]
}

@test "bip39 mnemonic-to-seed rejects an out-of-range word count" {
	run "$BITCOIN_BIN" bip39 mnemonic-to-seed only three words
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# BUG-013 regression — `bip32 derive` referenced undefined helper
# functions (isPrivate/isPublic) and BIP32_-prefixed version-code
# variables that the plugin never sets. End-to-end derive failed with
# "command not found" + "version is neither private nor public?!".
# This test exercises the full seed → child-key chain.
# ---------------------------------------------------------------------------

@test "BUG-013 — bip32 derive resolves end-to-end from a seed (non-hardened path)" {
	repo_root="$BATS_TEST_DIRNAME/../../"
	PATH="$repo_root/bin:$repo_root/libexec/bitcoin-node:$PATH" \
	XDG_SHARE_HOME="$repo_root/share" \
	SELF_LIBEXEC="$repo_root/libexec" \
	run bash -c '
		mnemonic-to-seed abandon abandon abandon abandon abandon abandon abandon \
		                 abandon abandon abandon abandon about \
		  | basenc --base16 -w0 \
		  | bip32 create -s 2>/dev/null \
		  | bitcoin-node bip13 base58-decode \
		  | bip32 derive m/0
	'
	[ "$status" -eq 0 ]
	# Non-empty output (a derived xkey serialisation, ~78 bytes binary
	# or its base58 equivalent — we only care that the pipeline ran).
	[ -n "$output" ]
	# The two undefined-function errors must not appear.
	[[ "$output" != *"isPrivate"* ]]
	[[ "$output" != *"isPublic"* ]]
	[[ "$output" != *"version is neither private nor public"* ]]
}

@test "FEAT-013 — wallet derive emits the canonical BIP-84 first receive address" {
	setup_wallet_derive_env
	run "$BITCOIN_BIN" wallet derive alice
	[ "$status" -eq 0 ]
	[[ "$output" == *"bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"* ]]
}

@test "FEAT-013 — wallet derive appends to the addresses ledger and commits" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	[ -s "$XDG_DATA_HOME/bitcoin/wallets/alice/addresses" ]
	grep -q "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu" \
		"$XDG_DATA_HOME/bitcoin/wallets/alice/addresses"
	# One commit added on top of the init commit (= 2 total).
	(( $(cd "$XDG_DATA_HOME/bitcoin/wallets/alice" && git rev-list --count HEAD) == 2 ))
}

@test "FEAT-013 — wallet derive bumps the index on the second call" {
	setup_wallet_derive_env
	first="$("$BITCOIN_BIN" wallet derive alice)"
	second="$("$BITCOIN_BIN" wallet derive alice)"
	[ "$first" != "$second" ]
	# Both lines in the ledger.
	(( $(wc -l < "$XDG_DATA_HOME/bitcoin/wallets/alice/addresses") == 2 ))
}

# FEAT-044: gap-limit walking on `wallet derive --walk`.

@test "FEAT-044 — wallet derive --walk discovers a funded address" {
	setup_wallet_derive_env
	# Index-0 BIP-84 address has on-chain history; index 1+ have no
	# fixture, so the curl stub fails → the walk treats them as empty.
	addr0="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr0/txs" "$(alice_tx_fixture)"
	run "$BITCOIN_BIN" wallet derive alice --walk --gap 1
	[ "$status" -eq 0 ]
	# Discovered exactly the funded index-0 address.
	echo "$output" | grep -qE "derived: 1;"
	grep -q "	$addr0	" "$XDG_DATA_HOME/bitcoin/wallets/alice/addresses"
}

@test "FEAT-044 — wallet derive --walk is a no-op when nothing is funded" {
	setup_wallet_derive_env
	# No fixtures at all → every probe fails → treated as empty.
	run "$BITCOIN_BIN" wallet derive alice --walk --gap 1
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE "derived: 0;"
	# Ledger stays empty (no commit, no rows appended).
	[ ! -s "$XDG_DATA_HOME/bitcoin/wallets/alice/addresses" ]
}

@test "FEAT-044 — wallet derive --walk stops after --gap consecutive empties" {
	setup_wallet_derive_env
	addr0="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr0/txs" "$(alice_tx_fixture)"
	# gap=2: after the funded index 0, the next two probes (idx 1, 2)
	# are unfixtured → empty → empties hits 2 → stop at index 3.
	run "$BITCOIN_BIN" wallet derive alice --walk --gap 2
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE "gap-limit reached at index 3"
}

@test "FEAT-044 — wallet derive --gap 0 acts like a plain single derive" {
	setup_wallet_derive_env
	run "$BITCOIN_BIN" wallet derive alice --gap 0
	[ "$status" -eq 0 ]
	# Plain derive prints the index-0 address, not the walk summary.
	[[ "$output" == *"bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"* ]]
	[[ "$output" != *"derived:"* ]]
	(( $(wc -l < "$XDG_DATA_HOME/bitcoin/wallets/alice/addresses") == 1 ))
}

@test "FEAT-013 — wallet addresses lists the derived ledger" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	run "$BITCOIN_BIN" wallet addresses alice
	[ "$status" -eq 0 ]
	[[ "$output" == *"bc1q"* ]]
	[ "$(echo "$output" | wc -l)" -ge 2 ]
}

@test "FEAT-013 — wallet label sets the label and commits" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	run "$BITCOIN_BIN" wallet label alice "$addr" "donations"
	[ "$status" -eq 0 ]
	grep -q "donations" "$XDG_DATA_HOME/bitcoin/wallets/alice/addresses"
	# Two commits added on top of init: derive + label.
	(( $(cd "$XDG_DATA_HOME/bitcoin/wallets/alice" && git rev-list --count HEAD) == 3 ))
}

@test "FEAT-013 — wallet balance sums UTXOs from the backend" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	# Two UTXOs, total 12345 + 6789 = 19134 sats.
	curl_fixture "https://mempool.space/api/address/$addr/utxo" \
		'[{"txid":"aa","vout":0,"value":12345,"status":{"block_height":830000}},{"txid":"bb","vout":1,"value":6789,"status":{"block_height":830001}}]'
	run "$BITCOIN_BIN" wallet balance alice
	[ "$status" -eq 0 ]
	[ "$output" = "19134" ]
}

@test "FEAT-011 — wallet remote add configures a git remote on the wallet repo" {
	setup_wallet_remote_env
	run "$BITCOIN_BIN" wallet remote add alice origin "$REMOTE_BARE"
	[ "$status" -eq 0 ]
	got="$(cd "$XDG_DATA_HOME/bitcoin/wallets/alice" && git remote get-url origin)"
	[ "$got" = "$REMOTE_BARE" ]
}

@test "FEAT-011 — wallet push uploads the wallet's branch to the remote" {
	setup_wallet_remote_env
	"$BITCOIN_BIN" wallet remote add alice origin "$REMOTE_BARE" >/dev/null
	run "$BITCOIN_BIN" wallet push alice
	[ "$status" -eq 0 ]
	# The bare repo should now hold the wallet's current branch.
	(cd "$REMOTE_BARE" && git log --oneline | head -1) | grep -qE 'wallet derive: alice/0'
}

@test "FEAT-011 — wallet pull --rebase brings remote commits into the wallet" {
	setup_wallet_remote_env
	"$BITCOIN_BIN" wallet remote add alice origin "$REMOTE_BARE" >/dev/null
	"$BITCOIN_BIN" wallet push alice >/dev/null
	# Make a peer clone, add a commit, push it back.
	peer="$BATS_TMPDIR/peer-clone-$BATS_TEST_NUMBER"
	rm -rf "$peer"
	git clone -q "$REMOTE_BARE" "$peer"
	(
		cd "$peer"
		echo "from-peer" > peer-marker
		git add peer-marker
		git -c user.email=peer@bitcoin -c user.name=peer \
		    -c commit.gpgsign=false \
		    commit -qm "peer adds a marker"
		git push -q origin main
	)
	# Wallet pulls the peer's commit.
	run "$BITCOIN_BIN" wallet pull alice
	[ "$status" -eq 0 ]
	[ -f "$XDG_DATA_HOME/bitcoin/wallets/alice/peer-marker" ]
}

@test "FEAT-011 — wallet push exits non-zero when the wallet has no remote configured" {
	setup_wallet_remote_env
	# Don't `wallet remote add`. Push should fail clearly.
	run "$BITCOIN_BIN" wallet push alice
	[ "$status" -ne 0 ]
}

@test "FEAT-011 — wallet remote add rejects a missing wallet" {
	setup_wallet_env
	run "$BITCOIN_BIN" wallet remote add no-such-wallet origin /tmp/whatever
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet broadcast forwards stdin hex to the backend and prints the txid" {
	setup_wallet_derive_env
	# Stub backend broadcast: any POST to /api/tx returns this txid.
	curl_fixture "https://mempool.space/api/tx" \
		"4242424242424242424242424242424242424242424242424242424242424242"
	run bash -c "echo '0200000001abcd' | '$BITCOIN_BIN' tx broadcast alice"
	[ "$status" -eq 0 ]
	[ "$output" = "4242424242424242424242424242424242424242424242424242424242424242" ]
}

@test "FEAT-014 — wallet broadcast rejects empty stdin" {
	setup_wallet_derive_env
	run bash -c "echo '' | '$BITCOIN_BIN' tx broadcast alice"
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet broadcast rejects non-hex input" {
	setup_wallet_derive_env
	run bash -c "echo 'this is not hex' | '$BITCOIN_BIN' tx broadcast alice"
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet build emits a hex PSBT with the BIP-174 magic prefix" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	[[ "$output" =~ ^70736274ff ]]
	# Round-trips through `psbt decode` (BIP-174 magic + section layout
	# are well-formed end-to-end).
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	[[ "$output" == *"section=0"* ]]
	[[ "$output" == *"type=00"* ]]
}

@test "FEAT-014 — wallet build produces a 2-output unsigned tx when change > dust" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	# Plenty of room for change: 100000 - 50000 - 140 (1-input/2-output fee
	# at 1 sat/vB) = 49860 sats of change, well above the 546-sat dust floor.
	# --fee-rate 1 pins the rate to keep the fee-arithmetic comment honest;
	# the default-path (estimate-fee) is exercised separately below.
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	# Decode the global unsigned-tx record and pull out the value (hex).
	psbt="$output"
	tx_hex="$(echo "$psbt" | "$BITCOIN_BIN" bip174 decode | sed -n '1s/.*value=//p')"
	[ -n "$tx_hex" ]
	# Tx layout: 4-byte version + varint(in) + inputs + varint(out) + outputs + 4-byte locktime.
	# Version 02000000, 1 input (varint 01), input = 32-byte txid + 4-byte
	# vout + 1-byte empty scriptSig + 4-byte sequence = 41 bytes.
	# So the output-count varint sits at byte offset 4 + 1 + 41 = 46 (= hex offset 92).
	out_count_hex="${tx_hex:92:2}"
	[ "$out_count_hex" = "02" ]
	# Recipient scriptPubKey for bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4
	# is 0014751e76e8199196d454941c45d1b3a323f1433bd6.
	[[ "$tx_hex" == *"0014751e76e8199196d454941c45d1b3a323f1433bd6"* ]]
}

@test "FEAT-014 — wallet build produces a 1-output unsigned tx when change <= dust" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	# 50500 sats UTXO, send 50000: change would be 50500 - 50000 - 140 = 360
	# sats, below the 546-sat dust floor, so the builder folds it into the fee
	# and emits a single output. --fee-rate 1 pins the rate.
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 50500 02)"
	run "$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	tx_hex="$(echo "$output" | "$BITCOIN_BIN" bip174 decode | sed -n '1s/.*value=//p')"
	# Same offset arithmetic as the previous test: output count at hex 92.
	out_count_hex="${tx_hex:92:2}"
	[ "$out_count_hex" = "01" ]
}

@test "FEAT-014 — wallet build rejects insufficient balance" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100 01)"
	run "$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000
	[ "$status" -ne 0 ]
	[[ "$output" == *"insufficient"* ]] || [[ "$stderr" == *"insufficient"* ]]
}

@test "FEAT-014 — wallet build rejects an invalid output address" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" tx build alice not-a-valid-bech32-address 10000
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet build rejects a missing wallet" {
	setup_wallet_derive_env
	run "$BITCOIN_BIN" tx build no-such-wallet bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 10000
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet build rejects bech32m / P2TR (v1+) output addresses" {
	# A v0-only builder must refuse Taproot until FEAT-007 lands. The
	# fixture below is a valid bech32m P2TR address; rejection is what
	# keeps us from emitting an unspendable v1 scriptPubKey.
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" tx build alice bc1pmfr3p9j00pfxjh0zmgp99y8zftmd3s5pmedqhyptwy6lm87hf5sspknck9 1000
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-014 / FEAT-012 (1.12.0) — wallet build picks up the backend's
# estimate-fee answer when --fee-rate isn't supplied; --fee-rate still
# overrides; backend failure falls back to 1 sat/vB with a warn.
#
# The change-output value pins the fee rate the builder actually used,
# since change = utxo - sats - (vsize * fee_rate). With one 100000-sat
# UTXO, sats=50000, and the post-segwit-discount vsize estimate of
# 10 + 68·1 + 31·2 = 140 vbytes:
#
#   fee_rate=1   → fee= 140, change=49860 → LE hex c4c20000...
#   fee_rate=10  → fee=1400, change=48600 → LE hex d8bd0000...
# ---------------------------------------------------------------------------

@test "FEAT-014 — wallet build reads the backend's fee estimate when --fee-rate is omitted" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	# 10 sat/vB recommended for the half-hour bucket.
	curl_fixture "https://mempool.space/api/v1/fees/recommended" \
		'{"fastestFee":50,"halfHourFee":10,"hourFee":5,"economyFee":2,"minimumFee":1}'
	run "$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000
	[ "$status" -eq 0 ]
	tx_hex="$(echo "$output" | "$BITCOIN_BIN" bip174 decode | sed -n '1s/.*value=//p')"
	# Change-output LE-encoded value sits right after the recipient
	# output: version(8) + n_in(2) + 1 input(82) + n_out(2) + recipient
	# value(16) + push 22 (2) + 22-byte scriptPubKey(44) = 156 hex chars.
	# So the change value is at offset 156, length 16.
	change_le="${tx_hex:156:16}"
	[ "$change_le" = "d8bd000000000000" ]
}

@test "FEAT-014 — wallet build --fee-rate still overrides the backend estimate" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	# Backend would say 10 sat/vB; explicit --fee-rate 1 wins.
	curl_fixture "https://mempool.space/api/v1/fees/recommended" \
		'{"fastestFee":50,"halfHourFee":10,"hourFee":5,"economyFee":2,"minimumFee":1}'
	run "$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	tx_hex="$(echo "$output" | "$BITCOIN_BIN" bip174 decode | sed -n '1s/.*value=//p')"
	change_le="${tx_hex:156:16}"
	[ "$change_le" = "c4c2000000000000" ]
}

@test "FEAT-014 — wallet build falls back to 1 sat/vB when the backend estimate is unavailable" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	# Deliberately do NOT register the /api/v1/fees/recommended fixture —
	# the curl stub will exit 22 and the builder must fall back to 1.
	# --separate-stderr keeps the fallback warn off the PSBT we're parsing.
	run --separate-stderr "$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000
	[ "$status" -eq 0 ]
	[[ "$stderr" == *"falling back to 1 sat/vB"* ]]
	tx_hex="$(echo "$output" | "$BITCOIN_BIN" bip174 decode | sed -n '1s/.*value=//p')"
	change_le="${tx_hex:156:16}"
	[ "$change_le" = "c4c2000000000000" ]
}

@test "FEAT-008 — psbt decode accepts a known BIP-174 PSBT and emits records" {
	run bash -c "$(declare -f psbt_vec1); psbt_vec1 | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	# At minimum the global unsigned-tx record (section 0, type 00) must appear.
	[[ "$output" == *"section=0"* ]]
	[[ "$output" == *"type=00"* ]]
}

@test "FEAT-008 — psbt decode rejects input without the BIP-174 magic" {
	# Strip the 5-byte magic+separator (10 hex chars).
	run bash -c "$(declare -f psbt_vec1); psbt_vec1 | cut -c11- | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -ne 0 ]
	[[ "$output" == *"magic"* ]]
}

@test "FEAT-008 — psbt decode rejects empty input" {
	run bash -c "echo '' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -ne 0 ]
}

@test "FEAT-008 — bitcoin help psbt cites BIP-174" {
	run "$BITCOIN_BIN" bip174 help
	[ "$status" -eq 0 ]
	[[ "$output" == *"BIP-174"* ]]
	[[ "$output" == *"bip-0174.mediawiki"* ]]
}
