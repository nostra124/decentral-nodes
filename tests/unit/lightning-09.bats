#!/usr/bin/env bats
#
# lightning unit tests — part 9 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "2.0.0 cutover: the account API is no longer served by this package" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/apache/lnurlp.conf"
	[ -f "$f" ]
	# FEAT-327/328/329: the account/commerce API was carved out into the
	# standalone `thunder` repo. This package's apache fragment must NOT
	# serve or proxy it — thunder owns that routing entirely.
	! grep -qE "(ScriptAlias|ProxyPass)\s+/.well-known/lightning/v1/accounts" "$f"
	# The legacy CGI dispatcher was retired.
	[ ! -e "$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/accounts.py" ]
	# No functional thunderd coupling (a doc comment pointing to the thunder
	# repo is fine; a Proxy/Script route or daemon address is not).
	! grep -qE "ProxyPass|127.0.0.1:9737|:9737" "$f"
}

# ---------------------------------------------------------------------------
# FEAT-212 PR-3: MCP endpoint + manifest
# ---------------------------------------------------------------------------

@test "FEAT-212 PR-3: MCP CGI script is executable Python" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/mcp.py"
	[ -x "$f" ]
	head -1 "$f" | grep -q python3
}

@test "FEAT-212 PR-3: static manifest at .well-known/lightning/mcp.json is valid JSON" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/lightning/mcp.json"
	[ -f "$f" ]
	# Validates JSON.
	jq -e '.' "$f" >/dev/null
	# All 8 tool names enumerated.
	for tool in account_create account_balance account_topup account_withdraw \
	            account_pay account_recv account_recv_reusable account_close; do
		jq -e --arg t "$tool" '.tools | index($t)' "$f" >/dev/null
	done
	# Resource URI templates (node://info added in FEAT-269/274).
	jq -e '.resources | length >= 3' "$f" >/dev/null
	# Protocol version.
	[ "$(jq -r '.protocolVersion' "$f")" = "2025-03-26" ]
}

@test "FEAT-212 PR-3: apache vhost maps MCP (FEAT-224 versioned) + mcp.json Alias" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/apache/lnurlp.conf"
	grep -q "ScriptAlias /.well-known/lightning/v1/mcp" "$f"
	grep -q "wellknown/api/mcp.py" "$f"
	grep -q "Alias /.well-known/lightning/mcp.json" "$f"
}

@test "FEAT-212 PR-4: topup-watcher status reports counts" {
	_acct212pr4_setup
	run "$LIGHTNING_BIN" account topup-watcher status
	[ "$status" -eq 0 ]
	[[ "$output" == *"watched_accounts: 1"* ]]
	[[ "$output" == *"total_credits:    0"* ]]
	[[ "$output" == *"last_credit:      (none yet)"* ]]
	_acct212pr4_teardown
}

@test "FEAT-212 PR-4: topup-watcher run with no UTXOs is a no-op" {
	_acct212pr4_setup
	MOCK_LISTFUNDS_OUTPUTS='[]' run "$LIGHTNING_BIN" account topup-watcher run
	[ "$status" -eq 0 ]
	local n
	n=$(sqlite3 "$LIGHTNING_WALLETS_ROOT/alice/state.db" "SELECT COUNT(*) FROM ledger WHERE message='topup-watcher';")
	[ "$n" = "0" ]
	_acct212pr4_teardown
}

@test "FEAT-212 PR-4: topup-watcher credits a new UTXO at a known address" {
	_acct212pr4_setup
	outs=$(jq -nc --arg a "$BATS_ADDR_RENT" \
		'[{"txid":"deadbeef","output":0,"status":"confirmed","address":$a,"amount_msat":"50000000msat"}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" run "$LIGHTNING_BIN" account topup-watcher run
	[ "$status" -eq 0 ]
	local row
	row=$(sqlite3 -separator '|' "$LIGHTNING_WALLETS_ROOT/alice/state.db" \
		"SELECT account, direction, amount_msat, payment_hash FROM ledger WHERE message='topup-watcher';")
	[ "$row" = "rent|in|50000000|deadbeef:0" ]
	_acct212pr4_teardown
}

@test "FEAT-212 PR-4: topup-watcher dry-run prints plan but writes nothing" {
	_acct212pr4_setup
	outs=$(jq -nc --arg a "$BATS_ADDR_RENT" \
		'[{"txid":"deadbeef","output":0,"status":"confirmed","address":$a,"amount_msat":"1000msat"}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" run "$LIGHTNING_BIN" account topup-watcher dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"would-credit"* ]]
	[[ "$output" == *"rent"* ]]
	local n
	n=$(sqlite3 "$LIGHTNING_WALLETS_ROOT/alice/state.db" "SELECT COUNT(*) FROM ledger WHERE message='topup-watcher';")
	[ "$n" = "0" ]
	_acct212pr4_teardown
}

@test "FEAT-212 PR-4: topup-watcher dedupes re-seen UTXOs" {
	_acct212pr4_setup
	outs=$(jq -nc --arg a "$BATS_ADDR_RENT" \
		'[{"txid":"deadbeef","output":0,"status":"confirmed","address":$a,"amount_msat":"1000msat"}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	local n
	n=$(sqlite3 "$LIGHTNING_WALLETS_ROOT/alice/state.db" "SELECT COUNT(*) FROM ledger WHERE message='topup-watcher';")
	[ "$n" = "1" ]
	_acct212pr4_teardown
}

@test "FEAT-212 PR-4: topup-watcher skips unconfirmed UTXOs" {
	_acct212pr4_setup
	outs=$(jq -nc --arg a "$BATS_ADDR_RENT" \
		'[{"txid":"deadbeef","output":0,"status":"unconfirmed","address":$a,"amount_msat":"1000msat"}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	local n
	n=$(sqlite3 "$LIGHTNING_WALLETS_ROOT/alice/state.db" "SELECT COUNT(*) FROM ledger WHERE message='topup-watcher';")
	[ "$n" = "0" ]
	_acct212pr4_teardown
}

@test "FEAT-212 PR-4: topup-watcher skips UTXOs at unknown addresses" {
	_acct212pr4_setup
	outs='[{"txid":"deadbeef","output":0,"status":"confirmed","address":"bcrt1qstrangerxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx","amount_msat":"1000msat"}]'
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	local n
	n=$(sqlite3 "$LIGHTNING_WALLETS_ROOT/alice/state.db" "SELECT COUNT(*) FROM ledger WHERE message='topup-watcher';")
	[ "$n" = "0" ]
	_acct212pr4_teardown
}

@test "FEAT-212 PR-4: topup-watcher does not credit closed accounts" {
	_acct212pr4_setup
	"$LIGHTNING_BIN" account close rent >/dev/null
	outs=$(jq -nc --arg a "$BATS_ADDR_RENT" \
		'[{"txid":"deadbeef","output":0,"status":"confirmed","address":$a,"amount_msat":"1000msat"}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" run "$LIGHTNING_BIN" account topup-watcher run
	[ "$status" -eq 0 ]
	[[ "$output" == *"skip"*"account closed"* ]]
	local n
	n=$(sqlite3 "$LIGHTNING_WALLETS_ROOT/alice/state.db" "SELECT COUNT(*) FROM ledger WHERE message='topup-watcher';")
	[ "$n" = "0" ]
	_acct212pr4_teardown
}

@test "FEAT-212 PR-4: topup-watcher handles amount_msat as a plain integer" {
	_acct212pr4_setup
	outs=$(jq -nc --arg a "$BATS_ADDR_RENT" \
		'[{"txid":"deadbeef","output":0,"status":"confirmed","address":$a,"amount_msat":2500}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	local amt
	amt=$(sqlite3 "$LIGHTNING_WALLETS_ROOT/alice/state.db" "SELECT amount_msat FROM ledger WHERE message='topup-watcher';")
	[ "$amt" = "2500" ]
	_acct212pr4_teardown
}

@test "FEAT-212 PR-4: account verb help lists topup-watcher" {
	run "$LIGHTNING_BIN" account
	[[ "$output" == *"topup-watcher run|dry-run|status"* ]]
}

@test "FEAT-212 PR-4: daemon enable --topup-watcher accepts the flag" {
	# We don't actually run the install (it tries to call systemctl);
	# we just verify the flag is recognised by parsing — and check
	# the verb source contains the sidecar function.
	f="$BATS_TEST_DIRNAME/../../libexec/lightning-node/daemon"
	grep -q "\-\-topup-watcher" "$f"
	grep -q "install_topup_watcher_sidecar" "$f"
	grep -q "TOPUP_WATCHER_LABEL" "$f"
}

@test "FEAT-244: daemon enable --reconcile writes a sidecar (Linux)" {
	if [ "$(uname -s)" = "Darwin" ]; then
		skip "Linux-only — checks the systemd timer files"
	fi
	run "$LIGHTNING_BIN" daemon enable --user --reconcile --no-keepalive --no-alert
	[ "$status" -eq 0 ]
	[ -f "$HOME/.config/systemd/user/lightning-reconcile.service" ]
	[ -f "$HOME/.config/systemd/user/lightning-reconcile.timer" ]
	grep -q "ledger reconcile run" "$HOME/.config/systemd/user/lightning-reconcile.service"
	grep -q "OnUnitActiveSec=5min" "$HOME/.config/systemd/user/lightning-reconcile.timer"
}

@test "FEAT-244: daemon enable (no --reconcile) does NOT write the sidecar" {
	# Opt-in, like the other watcher sidecars.
	run "$LIGHTNING_BIN" daemon enable --user --no-keepalive --no-alert
	[ "$status" -eq 0 ]
	[ ! -e "$HOME/.config/systemd/user/lightning-reconcile.timer" ]
}

@test "FEAT-212 PR-5: account gc status reports candidate counts" {
	_acct212pr5_setup
	run "$LIGHTNING_BIN" account gc status
	[ "$status" -eq 0 ]
	[[ "$output" == *"total_accounts:    3"* ]]
	[[ "$output" == *"would_close:       1"* ]]
	[[ "$output" == *"would_delete:      1"* ]]
	_acct212pr5_teardown
}

@test "FEAT-212 PR-5: account gc dry-run lists plan but writes nothing" {
	_acct212pr5_setup
	run "$LIGHTNING_BIN" account gc dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"would-close	stale"* ]]
	[[ "$output" == *"would-delete	closer"* ]]
	# State unchanged.
	local n_closed n_total
	n_total=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM accounts WHERE name NOT IN ('-', 'house', 'escrow', 'others');")
	n_closed=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM accounts WHERE closed_at IS NOT NULL;")
	[ "$n_total" = "3" ]
	[ "$n_closed" = "1" ]   # only the pre-existing 'closer'
	_acct212pr5_teardown
}

@test "FEAT-212 PR-5: account gc closes the stale account" {
	_acct212pr5_setup
	"$LIGHTNING_BIN" account gc run >/dev/null 2>&1
	local stale_closed_at
	stale_closed_at=$(sqlite3 "$BATS_DB" "SELECT closed_at FROM accounts WHERE name='stale';")
	[ -n "$stale_closed_at" ]
	[ "$stale_closed_at" != "0" ]
	_acct212pr5_teardown
}

@test "FEAT-212 PR-5: account gc deletes the long-closed account" {
	_acct212pr5_setup
	"$LIGHTNING_BIN" account gc run >/dev/null 2>&1
	local n
	n=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM accounts WHERE name='closer';")
	[ "$n" = "0" ]
	_acct212pr5_teardown
}

@test "FEAT-212 PR-5: account gc preserves fresh accounts" {
	_acct212pr5_setup
	"$LIGHTNING_BIN" account gc run >/dev/null 2>&1
	local row
	row=$(sqlite3 -separator '|' "$BATS_DB" "SELECT name, COALESCE(closed_at,0) FROM accounts WHERE name='fresh';")
	[ "$row" = "fresh|0" ]
	_acct212pr5_teardown
}

@test "FEAT-212 PR-5: account gc never touches the unassigned (-) account" {
	_acct212pr5_setup
	# Make '-' look very old to ensure the filter is not based on age alone.
	sqlite3 "$BATS_DB" "UPDATE accounts SET last_api_call_at = 0 WHERE name='-';"
	"$LIGHTNING_BIN" account gc run >/dev/null 2>&1
	local n
	n=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM accounts WHERE name='-';")
	[ "$n" = "1" ]
	_acct212pr5_teardown
}

@test "FEAT-212 PR-5: account gc skips stale accounts with non-zero balance" {
	_acct212pr5_setup
	# Park 1000 msat into stale.
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		VALUES(datetime('now'), 'stale', 'in', 1000, 'stake:0', 'test-fund');"
	"$LIGHTNING_BIN" account gc run >/dev/null 2>&1
	local closed_at
	closed_at=$(sqlite3 "$BATS_DB" "SELECT COALESCE(closed_at,'') FROM accounts WHERE name='stale';")
	[ -z "$closed_at" ]
	_acct212pr5_teardown
}

@test "FEAT-212 PR-5: account gc skips stale accounts with pending invoices" {
	_acct212pr5_setup
	sqlite3 "$BATS_DB" "INSERT INTO invoices(bolt11, payment_hash, account, amount_msat, expiry, state) \
		VALUES('lnbcrt-pending-1', 'hash-1', 'stale', 1000, '4102444800', 'pending');"
	"$LIGHTNING_BIN" account gc run >/dev/null 2>&1
	local closed_at
	closed_at=$(sqlite3 "$BATS_DB" "SELECT COALESCE(closed_at,'') FROM accounts WHERE name='stale';")
	[ -z "$closed_at" ]
	_acct212pr5_teardown
}

@test "FEAT-212 PR-5: LIGHTNING_ACCOUNT_GC_DAYS=1 closes one-day-stale accounts" {
	_acct212pr5_setup
	# 'fresh' was created moments ago — backdate it 2 days.
	sqlite3 "$BATS_DB" "UPDATE accounts SET last_api_call_at = strftime('%s','now')-2*86400, created_at = strftime('%s','now')-2*86400 WHERE name='fresh';"
	LIGHTNING_ACCOUNT_GC_DAYS=1 "$LIGHTNING_BIN" account gc run >/dev/null 2>&1
	local fresh_closed
	fresh_closed=$(sqlite3 "$BATS_DB" "SELECT closed_at FROM accounts WHERE name='fresh';")
	[ -n "$fresh_closed" ]
	[ "$fresh_closed" != "0" ]
	_acct212pr5_teardown
}

@test "FEAT-212 PR-5: account gc preserves ledger entries after deletion (FK SET DEFAULT)" {
	_acct212pr5_setup
	# Add a ledger entry against 'closer' BEFORE its balance is checked.
	# We want closer to have a net-zero balance so GC deletes it, but
	# the historical entries should survive via the FK SET DEFAULT.
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash) VALUES(datetime('now','-30 days'), 'closer', 'in', 1000, 'old:0');"
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash) VALUES(datetime('now','-30 days'), 'closer', 'out', -1000, 'old:1');"
	"$LIGHTNING_BIN" account gc run >/dev/null 2>&1
	# Account gone…
	local accs
	accs=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM accounts WHERE name='closer';")
	[ "$accs" = "0" ]
	# …ledger rows survive on the '-' bucket.
	local lentries
	lentries=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM ledger WHERE payment_hash IN ('old:0','old:1');")
	[ "$lentries" = "2" ]
	_acct212pr5_teardown
}

@test "FEAT-212 PR-5: account gc strips nicknames pointing at deleted address" {
	_acct212pr5_setup
	local addr
	addr=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='closer';")
	"$LIGHTNING_BIN" account nickname add "$addr" stale-nick >/dev/null
	"$LIGHTNING_BIN" account gc run >/dev/null 2>&1
	! grep -q "^address: $addr" "$LIGHTNING_WALLETS_ROOT/alice/accounts/nicknames.recfile"
	! grep -q "^nickname: stale-nick" "$LIGHTNING_WALLETS_ROOT/alice/accounts/nicknames.recfile"
	_acct212pr5_teardown
}

@test "FEAT-212 PR-5: account verb help lists gc" {
	run "$LIGHTNING_BIN" account
	[[ "$output" == *"gc run|dry-run|status"* ]]
}

@test "FEAT-212 PR-5: daemon enable --account-gc accepts the flag" {
	f="$BATS_TEST_DIRNAME/../../libexec/lightning-node/daemon"
	grep -q "\-\-account-gc" "$f"
	grep -q "install_account_gc_sidecar" "$f"
	grep -q "ACCOUNT_GC_LABEL" "$f"
}

@test "FEAT-212 PR-5: account gc on unknown subcommand exits 1" {
	_acct212pr5_setup
	run "$LIGHTNING_BIN" account gc whatever
	[ "$status" -eq 1 ]
	_acct212pr5_teardown
}

@test "FEAT-213: wallet new seeds the default fees.recfile" {
	_acct213_setup
	[ -f "$BATS_FEES" ]
	grep -q "^operation: pay" "$BATS_FEES"
	grep -q "^operation: withdraw" "$BATS_FEES"
	grep -q "^operation: topup-onchain" "$BATS_FEES"
	_acct213_teardown
}

@test "FEAT-213: wallet new commits fees.recfile to git" {
	_acct213_setup
	pushd "$LIGHTNING_WALLETS_ROOT/alice" >/dev/null
	git ls-files | grep -q "^fees.recfile$"
	popd >/dev/null
	_acct213_teardown
}

@test "FEAT-213: topup-watcher skims operator fee from on-chain deposit" {
	_acct213_setup
	# Default topup-onchain rate is 2000 ppm = 0.2%.  A 100 000-sat
	# deposit should skim 200 sat → house.
	outs=$(jq -nc --arg a "$BATS_ADDR" \
		'[{"txid":"deadbeef","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	local skim
	skim=$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='house';")
	[ "$skim" = "200000" ]
	# User balance = deposit - skim
	local user
	user=$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='rent';")
	[ "$user" = "99800000" ]
	_acct213_teardown
}

@test "FEAT-213: topup-watcher skims zero when rate_ppm is 0" {
	_acct213_setup
	# Override the default rate to 0 for topup-onchain.
	sed -i '/^operation: topup-onchain$/,/^$/{s/^rate_ppm:.*$/rate_ppm:  0/}' "$BATS_FEES"
	sed -i '/^operation: topup-onchain$/,/^$/{s/^base_sat:.*$/base_sat:  0/}' "$BATS_FEES"
	outs=$(jq -nc --arg a "$BATS_ADDR" \
		'[{"txid":"deadbeef","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	# FEAT-218 pre-seeds `house` so the referrer FK default has a
	# target.  House row exists from wallet new; with zero skim,
	# there should be no in-credit ledger entries against it.
	local house_credits
	house_credits=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='house' AND direction='in';")
	[ "$house_credits" = "0" ]
	_acct213_teardown
}

@test "FEAT-213: api-account-pay itemises into 4 ledger rows + creates house" {
	_acct213_setup
	"$LIGHTNING_BIN" api-account-pay "$BATS_ADDR" "lnbcrt10n1pmocktest" >/dev/null 2>&1
	local rows
	rows=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM ledger;")
	# 4 rows: payment, network fee, operator fee, house credit
	[ "$rows" = "4" ]
	# House account auto-created
	local house_exists
	house_exists=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM accounts WHERE name='house';")
	[ "$house_exists" = "1" ]
	# House description matches the bootstrap default
	local house_desc
	house_desc=$(sqlite3 "$BATS_DB" "SELECT description FROM accounts WHERE name='house';")
	[ "$house_desc" = "operator fee revenue" ]
	_acct213_teardown
}

@test "FEAT-213: api-account-pay JSON response includes operator_fee_sat" {
	_acct213_setup
	local body
	body=$("$LIGHTNING_BIN" api-account-pay "$BATS_ADDR" "lnbcrt10n1pmocktest" 2>/dev/null)
	echo "$body" | jq -e '.operator_fee_sat' >/dev/null
	# 1000-msat invoice at base_sat=1 + rate_ppm=5000 = 1*1000 + 1000*5000/1M
	# = 1005 msat = 1 sat (integer division).
	local got
	got=$(echo "$body" | jq -r '.operator_fee_sat')
	[ "$got" = "1" ]
	_acct213_teardown
}

@test "FEAT-213: api-account-pay double-entry — ledger sum = -sent_total" {
	_acct213_setup
	"$LIGHTNING_BIN" api-account-pay "$BATS_ADDR" "lnbcrt10n1pmocktest" >/dev/null 2>&1
	# Sum across user + house: -invoice - network_fee - operator_fee + operator_fee
	# = -invoice - network_fee.  Network fee is 1 msat; invoice is 1000 msat.
	# So total = -1001 msat.
	local total
	total=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger;")
	[ "$total" = "-1001" ]
	_acct213_teardown
}

@test "FEAT-213: missing fees.recfile = no skim, no house credits" {
	_acct213_setup
	rm "$BATS_FEES"
	outs=$(jq -nc --arg a "$BATS_ADDR" \
		'[{"txid":"deadbeef","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	local rows house_credits
	rows=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM ledger;")
	[ "$rows" = "1" ]   # just the credit, no skim entries
	# FEAT-218 pre-seeds house; with no fees.recfile the verbs skip the
	# skim, so there should be zero in-credit ledger entries on house.
	house_credits=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='house' AND direction='in';")
	[ "$house_credits" = "0" ]
	_acct213_teardown
}

@test "FEAT-213: house account is excluded from account list" {
	_acct213_setup
	"$LIGHTNING_BIN" api-account-pay "$BATS_ADDR" "lnbcrt10n1pmocktest" >/dev/null 2>&1
	run "$LIGHTNING_BIN" account list
	[ "$status" -eq 0 ]
	# `rent` appears; `house` does not.
	[[ "$output" == *"rent"* ]]
	[[ "$output" != *"house"* ]]
	_acct213_teardown
}

@test "FEAT-213: house account is excluded from GC" {
	_acct213_setup
	"$LIGHTNING_BIN" api-account-pay "$BATS_ADDR" "lnbcrt10n1pmocktest" >/dev/null 2>&1
	# Backdate house's last_api_call_at to 95 days ago so it would
	# otherwise qualify as stale, and rebalance its account to 0
	# (which it already isn't — but to be sure we cover the would-gc
	# trigger we also stamp closed_at far in the past).
	local now_minus_95; now_minus_95=$(( $(date -u +%s) - 95 * 86400 ))
	local long_ago=$(( $(date -u +%s) - 30 * 86400 ))
	sqlite3 "$BATS_DB" "UPDATE accounts SET last_api_call_at = $now_minus_95, created_at = $now_minus_95, closed_at = $long_ago WHERE name='house';"
	"$LIGHTNING_BIN" account gc run >/dev/null 2>&1
	# House should still exist.
	local count
	count=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM accounts WHERE name='house';")
	[ "$count" = "1" ]
	_acct213_teardown
}

@test "FEAT-214: fee-policy with no subcommand prints usage" {
	_acct214_setup
	run "$LIGHTNING_BIN" channel fee-policy
	[ "$status" -eq 1 ]
	[[ "$output" == *"usage: lightning fee-policy"* ]]
	_acct214_teardown
}

@test "FEAT-214: fee-policy show-rates reads fees.recfile" {
	_acct214_setup
	run "$LIGHTNING_BIN" channel fee-policy show-rates
	[ "$status" -eq 0 ]
	[[ "$output" == *"pay"* ]]
	[[ "$output" == *"5000"* ]]    # the default pay rate_ppm
	[[ "$output" == *"withdraw"* ]]
	[[ "$output" == *"topup-onchain"* ]]
	_acct214_teardown
}

@test "FEAT-214: fee-policy status reports empty state before any skim" {
	_acct214_setup
	run "$LIGHTNING_BIN" channel fee-policy status
	[ "$status" -eq 0 ]
	[[ "$output" == *"no revenue yet"* ]]
	_acct214_teardown
}

@test "FEAT-214: fee-policy status aggregates after activity" {
	_acct214_setup
	# Drive a topup skim (200-sat skim on 100k deposit).
	outs=$(jq -nc --arg a "$BATS_ADDR" \
		'[{"txid":"d1","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	# And a pay skim (1-sat skim on 1-sat mock-invoice).
	"$LIGHTNING_BIN" api-account-pay "$BATS_ADDR" "lnbcrt1n1pmocktest" >/dev/null 2>&1

	run "$LIGHTNING_BIN" channel fee-policy status
	[ "$status" -eq 0 ]
	# Total = 200 (topup) + 1 (pay) = 201 sat
	[[ "$output" == *"total_revenue_sat: 201"* ]]
	# Per-op breakdown lists both
	[[ "$output" == *"topup-onchain"* ]]
	[[ "$output" == *"200"* ]]
	[[ "$output" == *"pay"* ]]
	_acct214_teardown
}

@test "FEAT-214: fee-policy status --since filters out earlier rows" {
	_acct214_setup
	# Inject a historical skim 10 days ago.
	sqlite3 "$BATS_DB" "INSERT OR IGNORE INTO accounts(name, description, overdraft) VALUES('house', 'operator fee revenue', 'allow');"
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		VALUES(datetime('now','-10 days'), 'house', 'in', 50000, 'deadbeef', 'fee:pay from rent');"
	# And a fresh one today.
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		VALUES(datetime('now'), 'house', 'in', 25000, 'cafebabe', 'fee:pay from rent');"
	# --since yesterday should see only today's 25-sat row.
	local since; since=$(date -u -d "1 day ago" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)
	run "$LIGHTNING_BIN" channel fee-policy status --since "$since"
	[ "$status" -eq 0 ]
	[[ "$output" == *"total_revenue_sat: 25"* ]]
	_acct214_teardown
}

@test "FEAT-214: fee-policy status --since rejects malformed dates" {
	_acct214_setup
	run "$LIGHTNING_BIN" channel fee-policy status --since "yesterday"
	[ "$status" -eq 1 ]
	[[ "$output" == *"YYYY-MM-DD"* ]]
	_acct214_teardown
}

@test "FEAT-214: per-operation buckets correctly tag skim sources" {
	_acct214_setup
	# Topup skim
	outs=$(jq -nc --arg a "$BATS_ADDR" \
		'[{"txid":"d1","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	# Pay skim
	"$LIGHTNING_BIN" api-account-pay "$BATS_ADDR" "lnbcrt1n1pmocktest" >/dev/null 2>&1

	# Check ledger has the new fee:<op> tagging.
	local n_pay n_topup
	n_pay=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM ledger WHERE account='house' AND message LIKE 'fee:pay%';")
	n_topup=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM ledger WHERE account='house' AND message LIKE 'fee:topup-onchain%';")
	[ "$n_pay" = "1" ]
	[ "$n_topup" = "1" ]
	_acct214_teardown
}

@test "FEAT-214: top-level help mentions fee-policy" {
	run "$LIGHTNING_BIN" help
	[[ "$output" == *"fee-policy"* ]]
}

@test "FEAT-214: spec file exists with the expected id" {
	for cand in \
		"$BATS_TEST_DIRNAME/../../issues/feature/214-fee-revenue-dashboard.md" \
		"$BATS_TEST_DIRNAME/../../issues/feature/done/214-fee-revenue-dashboard.md"; do
		[ -f "$cand" ] && f="$cand" && break
	done
	[ -n "$f" ]
	grep -q "^id: FEAT-214" "$f"
	grep -q "fee-policy status" "$f"
}
