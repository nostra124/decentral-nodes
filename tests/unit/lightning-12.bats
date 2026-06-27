#!/usr/bin/env bats
#
# lightning unit tests — part 12 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-229: wallet new seeds price.recfile + schema has prices" {
	_price229_setup
	[ -f "$LIGHTNING_WALLETS_ROOT/alice/price.recfile" ]
	grep -q "^base:" "$LIGHTNING_WALLETS_ROOT/alice/price.recfile"
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='prices';")" = "1" ]
	_price229_teardown
}

@test "FEAT-229: price now with no data returns error + exit 4" {
	_price229_setup
	run "$LIGHTNING_BIN" price now
	[ "$status" -eq 4 ]
	[[ "$output" == *'"error":"no_price_data"'* ]]
	_price229_teardown
}

@test "FEAT-229: price poll stores a tick from the feed" {
	_price229_setup
	MOCK_PRICE_RESPONSE='{"USD":65000,"EUR":60000}' "$LIGHTNING_BIN" price poll >/dev/null 2>&1
	[ "$(sqlite3 "$BATS_DB" "SELECT btc_fiat FROM prices WHERE base='EUR';")" = "60000.0" ]
	_price229_teardown
}

@test "FEAT-229: price now returns the latest tick" {
	_price229_setup
	MOCK_PRICE_RESPONSE='{"EUR":60000}' "$LIGHTNING_BIN" price poll >/dev/null 2>&1
	run "$LIGHTNING_BIN" price now
	[ "$status" -eq 0 ]
	[[ "$output" == *'"base":"EUR"'* ]]
	[[ "$output" == *'"btc_fiat":60000'* ]]
	_price229_teardown
}

@test "FEAT-229: price value computes fiat = sat * btc_fiat / 1e8" {
	_price229_setup
	MOCK_PRICE_RESPONSE='{"EUR":60000}' "$LIGHTNING_BIN" price poll >/dev/null 2>&1
	# 100_000 sat at 60_000 EUR/BTC = 60.00 EUR.
	run "$LIGHTNING_BIN" price value 100000
	[ "$status" -eq 0 ]
	[[ "$output" == *'"fiat":60'* ]]
	# 1 BTC = full price.
	run "$LIGHTNING_BIN" price value 100000000
	[[ "$output" == *'"fiat":60000'* ]]
	_price229_teardown
}

@test "FEAT-229: price at returns the nearest stored tick" {
	_price229_setup
	MOCK_PRICE_RESPONSE='{"EUR":60000}' "$LIGHTNING_BIN" price poll >/dev/null 2>&1
	local ts
	ts=$(sqlite3 "$BATS_DB" "SELECT ts FROM prices WHERE base='EUR';")
	# Query a timestamp 1000s away — still the nearest (only) tick.
	run "$LIGHTNING_BIN" price at $(( ts + 1000 ))
	[ "$status" -eq 0 ]
	[[ "$output" == *"\"ts\":$ts"* ]]
	_price229_teardown
}

@test "FEAT-229: price poll rejects a non-numeric feed response" {
	_price229_setup
	MOCK_PRICE_RESPONSE='{"EUR":"not-a-number"}' run "$LIGHTNING_BIN" price poll
	[ "$status" -ne 0 ]
	[[ "$output" == *"no numeric price"* ]]
	_price229_teardown
}

@test "FEAT-229: price poll honours --base + per-base storage" {
	_price229_setup
	MOCK_PRICE_RESPONSE='{"USD":65000,"EUR":60000}' "$LIGHTNING_BIN" price poll --base USD >/dev/null 2>&1
	[ "$(sqlite3 "$BATS_DB" "SELECT btc_fiat FROM prices WHERE base='USD';")" = "65000.0" ]
	_price229_teardown
}

@test "FEAT-229: price with no subcommand prints usage" {
	run "$LIGHTNING_BIN" price
	[ "$status" -eq 1 ]
	[[ "$output" == *"usage: lightning price"* ]]
}

@test "FEAT-229: top-level help lists the price verb" {
	run "$LIGHTNING_BIN" help
	[[ "$output" == *"price"*"oracle"* ]]
}

@test "FEAT-229: daemon enable --price-oracle is wired" {
	f="$BATS_TEST_DIRNAME/../../libexec/lightning-node/daemon"
	grep -q "\-\-price-oracle" "$f"
	grep -q "install_price_oracle_sidecar" "$f"
	grep -q "PRICE_ORACLE_LABEL" "$f"
}

@test "FEAT-229: apache vhost adds the public price endpoint" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/apache/lnurlp.conf"
	grep -q "ScriptAlias /.well-known/lightning/v1/price" "$f"
	grep -q "wellknown/api/price.py" "$f"
}

@test "FEAT-229: spec file present" {
	for cand in \
		"$BATS_TEST_DIRNAME/../../issues/feature/229-price-oracle.md" \
		"$BATS_TEST_DIRNAME/../../issues/feature/done/229-price-oracle.md"; do
		[ -f "$cand" ] && f="$cand" && break
	done
	[ -n "$f" ]
	grep -q "^id: FEAT-229" "$f"
}

@test "FEAT-226: create lands an active order with next_run in the future" {
	_acct226_setup
	run "$LIGHTNING_BIN" account standing-order create payer landlord 10000 monthly
	[ "$status" -eq 0 ]
	[[ "$output" == *'"status":"active"'* ]]
	local nr now
	nr=$(sqlite3 "$BATS_DB" "SELECT next_run FROM standing_orders WHERE account='payer';")
	now=$(date -u +%s)
	[ "$nr" -gt "$now" ]
	# Monthly is ~28-31 days out.
	[ "$nr" -gt "$(( now + 27*86400 ))" ]
	[ "$nr" -lt "$(( now + 32*86400 ))" ]
	_acct226_teardown
}

@test "FEAT-226: create rejects a bad cadence" {
	_acct226_setup
	run "$LIGHTNING_BIN" account standing-order create payer landlord 10000 hourly
	[ "$status" -ne 0 ]
	_acct226_teardown
}

@test "FEAT-226: create rejects a single-use BOLT-11 target" {
	_acct226_setup
	run "$LIGHTNING_BIN" account standing-order create payer lnbc10n1pmocktest 5000 daily
	[ "$status" -ne 0 ]
	[[ "$output" == *"re-payable"* ]]
	_acct226_teardown
}

@test "FEAT-226: create accepts a Lightning-address target" {
	_acct226_setup
	run "$LIGHTNING_BIN" account standing-order create payer alice@example.com 5000 weekly
	[ "$status" -eq 0 ]
	_acct226_teardown
}

@test "FEAT-226: run pays a due local-account order and advances next_run" {
	_acct226_setup
	"$LIGHTNING_BIN" account standing-order create payer landlord 10000 monthly >/dev/null
	# Force it due.
	sqlite3 "$BATS_DB" "UPDATE standing_orders SET next_run = strftime('%s','now') - 100;"
	run "$LIGHTNING_BIN" account standing-order run
	[ "$status" -eq 0 ]
	[[ "$output" == *'"paid":1'* ]]
	# Ledger moved 10000 sat payer -> landlord.
	[ "$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='landlord';")" = "10000000" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='payer';")" = "90000000" ]
	# next_run advanced back into the future, last_run + failures reset.
	local now nr lr
	now=$(date -u +%s)
	nr=$(sqlite3 "$BATS_DB" "SELECT next_run FROM standing_orders WHERE account='payer';")
	lr=$(sqlite3 "$BATS_DB" "SELECT COALESCE(last_run,0) FROM standing_orders WHERE account='payer';")
	[ "$nr" -gt "$now" ]
	[ "$lr" -gt "0" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT failures FROM standing_orders WHERE account='payer';")" = "0" ]
	_acct226_teardown
}

@test "FEAT-226: run skips a not-yet-due order" {
	_acct226_setup
	"$LIGHTNING_BIN" account standing-order create payer landlord 10000 monthly >/dev/null
	run "$LIGHTNING_BIN" account standing-order run
	[ "$status" -eq 0 ]
	[[ "$output" == *'"paid":0'* ]]
	[ "$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='landlord';")" = "0" ]
	_acct226_teardown
}

@test "FEAT-226: run skips a paused order" {
	_acct226_setup
	"$LIGHTNING_BIN" account standing-order create payer landlord 10000 monthly >/dev/null
	local id
	id=$(sqlite3 "$BATS_DB" "SELECT id FROM standing_orders WHERE account='payer';")
	"$LIGHTNING_BIN" account standing-order pause "$id" >/dev/null
	sqlite3 "$BATS_DB" "UPDATE standing_orders SET next_run = strftime('%s','now') - 100;"
	run "$LIGHTNING_BIN" account standing-order run
	[[ "$output" == *'"paid":0'* ]]
	[ "$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='landlord';")" = "0" ]
	_acct226_teardown
}

@test "FEAT-226: pause/resume/cancel transition status" {
	_acct226_setup
	"$LIGHTNING_BIN" account standing-order create payer landlord 10000 monthly >/dev/null
	local id
	id=$(sqlite3 "$BATS_DB" "SELECT id FROM standing_orders WHERE account='payer';")
	"$LIGHTNING_BIN" account standing-order pause "$id" >/dev/null
	[ "$(sqlite3 "$BATS_DB" "SELECT status FROM standing_orders WHERE id='$id';")" = "paused" ]
	"$LIGHTNING_BIN" account standing-order resume "$id" >/dev/null
	[ "$(sqlite3 "$BATS_DB" "SELECT status FROM standing_orders WHERE id='$id';")" = "active" ]
	"$LIGHTNING_BIN" account standing-order cancel "$id" >/dev/null
	[ "$(sqlite3 "$BATS_DB" "SELECT status FROM standing_orders WHERE id='$id';")" = "cancelled" ]
	_acct226_teardown
}

@test "FEAT-226: a failed run auto-pauses after N failures" {
	_acct226_setup
	# `broke` has no balance + deny overdraft → transfer fails.
	"$LIGHTNING_BIN" account create broke >/dev/null
	"$LIGHTNING_BIN" account standing-order create broke landlord 5000 daily >/dev/null
	sqlite3 "$BATS_DB" "UPDATE standing_orders SET next_run = strftime('%s','now') - 100 WHERE account='broke';"
	LIGHTNING_STANDING_ORDER_MAX_FAILURES=1 run "$LIGHTNING_BIN" account standing-order run
	[[ "$output" == *'"paused":1'* ]]
	[ "$(sqlite3 "$BATS_DB" "SELECT status FROM standing_orders WHERE account='broke';")" = "paused" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT failures FROM standing_orders WHERE account='broke';")" = "1" ]
	_acct226_teardown
}

@test "FEAT-226: dry-run does not pay" {
	_acct226_setup
	"$LIGHTNING_BIN" account standing-order create payer landlord 10000 monthly >/dev/null
	sqlite3 "$BATS_DB" "UPDATE standing_orders SET next_run = strftime('%s','now') - 100;"
	run "$LIGHTNING_BIN" account standing-order dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"would-pay"* ]]
	[ "$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='landlord';")" = "0" ]
	_acct226_teardown
}

@test "FEAT-226: HTTP verb create/list/pause/cancel emit JSON" {
	_acct226_setup
	local out id
	out=$("$LIGHTNING_BIN" api-account-standing-order "$BATS_PAYER_ADDR" create landlord 5000 weekly)
	[[ "$out" == *'"status":"active"'* ]]
	id=$(echo "$out" | jq -r '.id')
	[[ "$id" == so_* ]]
	"$LIGHTNING_BIN" api-account-standing-order "$BATS_PAYER_ADDR" list | jq -e '.standing_orders | length == 1' >/dev/null
	out=$("$LIGHTNING_BIN" api-account-standing-order "$BATS_PAYER_ADDR" pause "$id")
	[[ "$out" == *'"status":"paused"'* ]]
	out=$("$LIGHTNING_BIN" api-account-standing-order "$BATS_PAYER_ADDR" cancel "$id")
	[[ "$out" == *'"status":"cancelled"'* ]]
	_acct226_teardown
}

@test "FEAT-226: HTTP verb scopes orders to the owning account" {
	_acct226_setup
	"$LIGHTNING_BIN" account standing-order create landlord payer 1000 daily >/dev/null
	# payer's list must NOT see landlord's order.
	"$LIGHTNING_BIN" api-account-standing-order "$BATS_PAYER_ADDR" list | jq -e '.standing_orders | length == 0' >/dev/null
	_acct226_teardown
}

@test "FEAT-226: daemon enable --standing-orders accepts the flag" {
	f="$BATS_TEST_DIRNAME/../../libexec/lightning-node/daemon"
	grep -q "\-\-standing-orders" "$f"
	grep -q "install_standing_orders_sidecar" "$f"
	grep -q "STANDING_ORDER_LABEL" "$f"
}

@test "FEAT-226: sudoers fragment lists api-account-standing-order" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
	grep -q "api-account-standing-order" "$f"
}

@test "FEAT-226: schema declares standing_orders" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/schema.sql"
	grep -q "CREATE TABLE IF NOT EXISTS standing_orders" "$f"
}

@test "FEAT-226: account verb usage lists standing-order" {
	run "$LIGHTNING_BIN" account
	[[ "$output" == *"standing-order"* ]]
}

@test "FEAT-227: create mandate returns a secret + active status" {
	_acct227_setup
	run "$LIGHTNING_BIN" api-account-mandate "$BATS_CUST_ADDR" create shop 50000 monthly
	[ "$status" -eq 0 ]
	[[ "$output" == *'"status":"active"'* ]]
	[ -n "$(echo "$output" | jq -r '.secret')" ]
	[[ "$(echo "$output" | jq -r '.id')" == mdt_* ]]
	_acct227_teardown
}

@test "FEAT-227: create rejects bad period / mode / non-positive max" {
	_acct227_setup
	run "$LIGHTNING_BIN" api-account-mandate "$BATS_CUST_ADDR" create shop 50000 hourly
	[ "$status" -ne 0 ]
	run "$LIGHTNING_BIN" api-account-mandate "$BATS_CUST_ADDR" create shop 50000 monthly --mode whenever
	[ "$status" -ne 0 ]
	run "$LIGHTNING_BIN" api-account-mandate "$BATS_CUST_ADDR" create shop 0 monthly
	[ "$status" -ne 0 ]
	_acct227_teardown
}

@test "FEAT-227: create rejects a single-use BOLT-11 merchant + self-mandate" {
	_acct227_setup
	run "$LIGHTNING_BIN" api-account-mandate "$BATS_CUST_ADDR" create lnbc10n1pmocktest 5000 daily
	[ "$status" -ne 0 ]
	run "$LIGHTNING_BIN" api-account-mandate "$BATS_CUST_ADDR" create cust 5000 daily
	[ "$status" -ne 0 ]
	[[ "$output" == *"merchant_is_customer"* ]]
	_acct227_teardown
}

@test "FEAT-227: auto-mode charge within cap executes an intra-node transfer" {
	_acct227_setup
	read -r mid secret <<<"$(_mk_mandate auto)"
	run "$LIGHTNING_BIN" api-account-mandate-pull "$BATS_CUST_ADDR" charge "$mid" "$secret" 10000
	[ "$status" -eq 0 ]
	[[ "$output" == *'"state":"executed"'* ]]
	[ "$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='shop';")" = "10000000" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='cust';")" = "90000000" ]
	_acct227_teardown
}

@test "FEAT-227: charge with the wrong secret is rejected (exit 7)" {
	_acct227_setup
	read -r mid secret <<<"$(_mk_mandate auto)"
	run "$LIGHTNING_BIN" api-account-mandate-pull "$BATS_CUST_ADDR" charge "$mid" "deadbeef" 1000
	[ "$status" -eq 7 ]
	[[ "$output" == *"unauthorized"* ]]
	# Nothing moved.
	[ "$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='shop';")" = "0" ]
	_acct227_teardown
}

@test "FEAT-227: a pull exceeding the per-period cap is rejected (exit 6)" {
	_acct227_setup
	read -r mid secret <<<"$(_mk_mandate auto)"
	"$LIGHTNING_BIN" api-account-mandate-pull "$BATS_CUST_ADDR" charge "$mid" "$secret" 40000 >/dev/null
	run "$LIGHTNING_BIN" api-account-mandate-pull "$BATS_CUST_ADDR" charge "$mid" "$secret" 20000
	[ "$status" -eq 6 ]
	[[ "$output" == *"cap_exceeded"* ]]
	_acct227_teardown
}

@test "FEAT-227: revoking a mandate blocks further pulls (exit 6)" {
	_acct227_setup
	read -r mid secret <<<"$(_mk_mandate auto)"
	"$LIGHTNING_BIN" api-account-mandate "$BATS_CUST_ADDR" patch "$mid" --status revoked >/dev/null
	run "$LIGHTNING_BIN" api-account-mandate-pull "$BATS_CUST_ADDR" charge "$mid" "$secret" 1000
	[ "$status" -eq 6 ]
	[[ "$output" == *"mandate_not_active"* ]]
	_acct227_teardown
}

@test "FEAT-227: approval-mode charge lands pending; approve executes" {
	_acct227_setup
	read -r mid secret <<<"$(_mk_mandate approval)"
	local out pid
	out=$("$LIGHTNING_BIN" api-account-mandate-pull "$BATS_CUST_ADDR" charge "$mid" "$secret" 5000)
	[[ "$out" == *'"state":"pending"'* ]]
	pid=$(echo "$out" | jq -r '.pull_id')
	# Not executed yet.
	[ "$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='shop';")" = "0" ]
	run "$LIGHTNING_BIN" api-account-mandate-pull "$BATS_CUST_ADDR" approve "$mid" "$pid"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"state":"executed"'* ]]
	[ "$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='shop';")" = "5000000" ]
	_acct227_teardown
}

@test "FEAT-227: approval-mode deny cancels the pull" {
	_acct227_setup
	read -r mid secret <<<"$(_mk_mandate approval)"
	local out pid
	out=$("$LIGHTNING_BIN" api-account-mandate-pull "$BATS_CUST_ADDR" charge "$mid" "$secret" 5000)
	pid=$(echo "$out" | jq -r '.pull_id')
	run "$LIGHTNING_BIN" api-account-mandate-pull "$BATS_CUST_ADDR" deny "$mid" "$pid"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"state":"denied"'* ]]
	[ "$(sqlite3 "$BATS_DB" "SELECT state FROM mandate_pulls WHERE id='$pid';")" = "denied" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='shop';")" = "0" ]
	_acct227_teardown
}

@test "FEAT-227: list does not leak the secret" {
	_acct227_setup
	_mk_mandate auto >/dev/null
	run "$LIGHTNING_BIN" api-account-mandate "$BATS_CUST_ADDR" list
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.mandates | length == 1' >/dev/null
	echo "$output" | jq -e '.mandates[0] | has("secret") | not' >/dev/null
	_acct227_teardown
}

@test "FEAT-227: patch switches the mode" {
	_acct227_setup
	read -r mid secret <<<"$(_mk_mandate auto)"
	run "$LIGHTNING_BIN" api-account-mandate "$BATS_CUST_ADDR" patch "$mid" --mode approval
	[ "$status" -eq 0 ]
	[[ "$output" == *'"mode":"approval"'* ]]
	[ "$(sqlite3 "$BATS_DB" "SELECT mode FROM mandates WHERE id='$mid';")" = "approval" ]
	_acct227_teardown
}

@test "FEAT-227: sudoers fragment lists the mandate verbs" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
	grep -q "api-account-mandate " "$f"
	grep -q "api-account-mandate-pull" "$f"
}

@test "FEAT-227: schema declares mandates + mandate_pulls" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/schema.sql"
	grep -q "CREATE TABLE IF NOT EXISTS mandates" "$f"
	grep -q "CREATE TABLE IF NOT EXISTS mandate_pulls" "$f"
}

@test "FEAT-228: create issues a charge in state issued" {
	_acct228_setup
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" create buyer 20000 --ref '{"order_id":"O1"}'
	[ "$status" -eq 0 ]
	[[ "$output" == *'"state":"issued"'* ]]
	[[ "$(echo "$output" | jq -r '.id')" == chg_* ]]
	_acct228_teardown
}

@test "FEAT-228: create rejects bad amount / unknown customer / self" {
	_acct228_setup
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" create buyer 0
	[ "$status" -ne 0 ]
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" create nobody 1000
	[ "$status" -ne 0 ]
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" create shop 1000
	[ "$status" -ne 0 ]
	_acct228_teardown
}

@test "FEAT-228: escrow hold moves funds to escrow; release pays the merchant" {
	_acct228_setup
	local id; id=$(_chg 20000)
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" hold "$id" >/dev/null
	[ "$(_sat buyer)" = "80000" ]
	[ "$(_sat escrow)" = "20000" ]
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" release "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"state":"released"'* ]]
	[ "$(_sat escrow)" = "0" ]
	[ "$(_sat shop)" = "20000" ]
	_acct228_teardown
}

@test "FEAT-228: hold requires sufficient customer balance" {
	_acct228_setup
	local id; id=$(_chg 999999999)
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" hold "$id"
	[ "$status" -eq 6 ]
	[[ "$output" == *"insufficient_funds"* ]]
	_acct228_teardown
}

@test "FEAT-228: release only from held state" {
	_acct228_setup
	local id; id=$(_chg 20000)
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" release "$id"
	[ "$status" -eq 6 ]
	[[ "$output" == *"bad_state"* ]]
	_acct228_teardown
}

@test "FEAT-228: partial then full refund walks state + reverses funds" {
	_acct228_setup
	local id; id=$(_chg 20000)
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" hold "$id" >/dev/null
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" release "$id" >/dev/null
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" refund "$id" --sat 5000
	[[ "$output" == *'"state":"partially_refunded"'* ]]
	[ "$(_sat shop)" = "15000" ]
	[ "$(_sat buyer)" = "85000" ]
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" refund "$id"
	[[ "$output" == *'"state":"refunded"'* ]]
	[ "$(_sat shop)" = "0" ]
	[ "$(_sat buyer)" = "100000" ]
	_acct228_teardown
}

@test "FEAT-228: refund cannot exceed the amount the merchant received" {
	_acct228_setup
	local id; id=$(_chg 20000)
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" hold "$id" >/dev/null
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" release "$id" >/dev/null
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" refund "$id" --sat 30000
	[ "$status" -eq 6 ]
	[[ "$output" == *"refund_exceeds_refundable"* ]]
	_acct228_teardown
}

@test "FEAT-228: authorize then capture < amount returns the remainder" {
	_acct228_setup
	local id; id=$(_chg 10000)
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" authorize "$id" >/dev/null
	[ "$(_sat escrow)" = "10000" ]
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" capture "$id" 8000
	[ "$status" -eq 0 ]
	[[ "$output" == *'"state":"captured"'* ]]
	[ "$(_sat shop)" = "8000" ]
	[ "$(_sat escrow)" = "0" ]
	[ "$(_sat buyer)" = "92000" ]
	_acct228_teardown
}
