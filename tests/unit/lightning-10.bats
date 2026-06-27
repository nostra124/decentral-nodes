#!/usr/bin/env bats
#
# lightning unit tests — part 10 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-215: autotune without target env var errors loudly" {
	_acct215_setup
	run "$LIGHTNING_BIN" channel fee-policy autotune run
	[ "$status" -eq 1 ]
	[[ "$output" == *"LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY"* ]]
	_acct215_teardown
}

@test "FEAT-215: autotune target must be a non-negative integer" {
	_acct215_setup
	LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY="abc" run "$LIGHTNING_BIN" channel fee-policy autotune run
	[ "$status" -eq 1 ]
	[[ "$output" == *"positive integer"* ]]
	_acct215_teardown
}

@test "FEAT-215: autotune dry-run with high target nudges rates up" {
	_acct215_setup
	# 1M msat/day = 30M msat/30days target; observed = 0; well below
	# the low_threshold, so direction=up.
	LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY=1000000 \
		run "$LIGHTNING_BIN" channel fee-policy autotune dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"direction=up"* ]]
	# fees.recfile should NOT have changed (dry-run).
	local pay_rate
	pay_rate=$(awk '/^operation: pay$/,/^$/' "$BATS_FEES" | awk '/^rate_ppm:/ {print $2}')
	[ "$pay_rate" = "5000" ]
	_acct215_teardown
}

@test "FEAT-215: autotune run nudges rates up + writes state file" {
	_acct215_setup
	LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY=1000000 \
		LIGHTNING_FEE_AUTOTUNE_MAX_STEP_PPM=500 \
		"$LIGHTNING_BIN" channel fee-policy autotune run >/dev/null 2>&1
	# pay rate should be 5500 (5000 + 500 step)
	local pay_rate
	pay_rate=$(awk '/^operation: pay$/,/^$/' "$BATS_FEES" | awk '/^rate_ppm:/ {print $2}')
	[ "$pay_rate" = "5500" ]
	# State file written
	[ -f "$LIGHTNING_DIR/fee-autotune.state.recfile" ]
	grep -q "last_direction: *up" "$LIGHTNING_DIR/fee-autotune.state.recfile"
	_acct215_teardown
}

@test "FEAT-215: autotune holds within hysteresis band" {
	_acct215_setup
	# Seed 30 sat of revenue
	sqlite3 "$BATS_DB" "INSERT OR IGNORE INTO accounts(name, description, overdraft) VALUES('house', 'operator fee revenue', 'allow');"
	for i in $(seq 1 30); do
		sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
			VALUES(datetime('now','-$((30 - i)) days'), 'house', 'in', 1000, 'h$i', 'fee:pay from rent');"
	done
	# 30 days × 1000 msat = 30000 msat total / 30 = 1000 msat/day observed
	# Target = 1000 → exact match → direction=hold (within 20% hysteresis)
	LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY=1000 \
		run "$LIGHTNING_BIN" channel fee-policy autotune dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"direction=hold"* ]]
	_acct215_teardown
}

@test "FEAT-215: autotune nudges down when revenue exceeds high threshold" {
	_acct215_setup
	# Seed 200 sat skim (200_000 msat) → observed ~6666 msat/day
	sqlite3 "$BATS_DB" "INSERT OR IGNORE INTO accounts(name, description, overdraft) VALUES('house', 'operator fee revenue', 'allow');"
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		VALUES(datetime('now'), 'house', 'in', 200000, 'deadbeef', 'fee:pay from rent');"
	# Target = 1000 msat/day; 1.2×target = 1200; observed 6666 >> 1200 → down
	LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY=1000 \
		run "$LIGHTNING_BIN" channel fee-policy autotune dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"direction=down"* ]]
	_acct215_teardown
}

@test "FEAT-215: autotune respects rate ceiling" {
	_acct215_setup
	# Set ceiling at 5500; pay rate currently 5000.  Single 500-step
	# nudge UP would hit 5500 exactly.  A second run shouldn't move it.
	LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY=1000000 \
		LIGHTNING_FEE_AUTOTUNE_MAX_STEP_PPM=500 \
		LIGHTNING_FEE_AUTOTUNE_CEILING_PPM=5500 \
		"$LIGHTNING_BIN" channel fee-policy autotune run >/dev/null 2>&1
	LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY=1000000 \
		LIGHTNING_FEE_AUTOTUNE_MAX_STEP_PPM=500 \
		LIGHTNING_FEE_AUTOTUNE_CEILING_PPM=5500 \
		"$LIGHTNING_BIN" channel fee-policy autotune run >/dev/null 2>&1
	local pay_rate
	pay_rate=$(awk '/^operation: pay$/,/^$/' "$BATS_FEES" | awk '/^rate_ppm:/ {print $2}')
	[ "$pay_rate" = "5500" ]
	_acct215_teardown
}

@test "FEAT-215: autotune respects rate floor" {
	_acct215_setup
	# Drive direction=down, floor at 4500.  Pay starts at 5000 → 4500 →
	# stays at 4500 across further calls.
	sqlite3 "$BATS_DB" "INSERT OR IGNORE INTO accounts(name, description, overdraft) VALUES('house', 'operator fee revenue', 'allow');"
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		VALUES(datetime('now'), 'house', 'in', 1000000000, 'd1', 'fee:pay from rent');"
	for n in 1 2 3; do
		LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY=1000 \
			LIGHTNING_FEE_AUTOTUNE_MAX_STEP_PPM=500 \
			LIGHTNING_FEE_AUTOTUNE_FLOOR_PPM=4500 \
			"$LIGHTNING_BIN" channel fee-policy autotune run >/dev/null 2>&1
	done
	local pay_rate
	pay_rate=$(awk '/^operation: pay$/,/^$/' "$BATS_FEES" | awk '/^rate_ppm:/ {print $2}')
	[ "$pay_rate" = "4500" ]
	_acct215_teardown
}

@test "FEAT-215: autotune status before any run reports 'never run'" {
	_acct215_setup
	run "$LIGHTNING_BIN" channel fee-policy autotune status
	[ "$status" -eq 0 ]
	[[ "$output" == *"never run"* ]]
	_acct215_teardown
}

@test "FEAT-215: autotune status shows last decision" {
	_acct215_setup
	LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY=1000000 \
		"$LIGHTNING_BIN" channel fee-policy autotune run >/dev/null 2>&1
	run "$LIGHTNING_BIN" channel fee-policy autotune status
	[ "$status" -eq 0 ]
	[[ "$output" == *"last_direction:"* ]]
	[[ "$output" == *"changes:"* ]]
	_acct215_teardown
}

@test "FEAT-215: autotune reads routing income from listforwards" {
	_acct215_setup
	# Seed listforwards with 500_000 msat of recent settled fee revenue.
	cutoff_now=$(date -u +%s)
	export MOCK_LISTFORWARDS=$(jq -nc --argjson now "$cutoff_now" \
		'[{"status":"settled","fee_msat":500000,"received_time":$now}]')
	# Target = 1M msat/day = 30M/30d.  Observed = 500_000/30 = ~16666
	# msat/day from routing; skim is 0.  500_000/30=16666 → well below
	# low_threshold → direction=up + routing_msat_30d reported.
	LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY=1000000 \
		"$LIGHTNING_BIN" channel fee-policy autotune run 2>/dev/null
	grep -q "routing_msat_30d: *500000" "$LIGHTNING_DIR/fee-autotune.state.recfile"
	_acct215_teardown
}

@test "FEAT-215: daemon enable --fee-autotune accepts the flag" {
	f="$BATS_TEST_DIRNAME/../../libexec/lightning-node/daemon"
	grep -q "\-\-fee-autotune" "$f"
	grep -q "install_fee_autotune_sidecar" "$f"
	grep -q "FEE_AUTOTUNE_LABEL" "$f"
}

@test "FEAT-215: fee-policy help lists autotune" {
	run "$LIGHTNING_BIN" channel fee-policy
	[[ "$output" == *"autotune"* ]]
}

@test "FEAT-215: spec file exists with the expected id" {
	for cand in \
		"$BATS_TEST_DIRNAME/../../issues/feature/215-fee-autotuning-cron.md" \
		"$BATS_TEST_DIRNAME/../../issues/feature/done/215-fee-autotuning-cron.md"; do
		[ -f "$cand" ] && f="$cand" && break
	done
	[ -n "$f" ]
	grep -q "^id: FEAT-215" "$f"
	grep -q "autotune" "$f"
}

@test "FEAT-218: wallet new pre-seeds house account with FK-safe ordering" {
	_acct218_setup
	# Both house and `-` exist; their referrer defaults to 'house'.
	local row
	row=$(sqlite3 -separator '|' "$BATS_DB" "SELECT name, referrer FROM accounts WHERE name IN ('-','house') ORDER BY name;")
	[ "$row" = "$(printf '%s\n' '-|house' 'house|house')" ]
	_acct218_teardown
}

@test "FEAT-218: invite_codes table exists post-migration" {
	_acct218_setup
	local n
	n=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='invite_codes';")
	[ "$n" = "1" ]
	_acct218_teardown
}

@test "FEAT-218: account verb help mentions invite-code" {
	_acct218_setup
	run "$LIGHTNING_BIN" account
	[[ "$output" == *"invite-code create"* ]]
	[[ "$output" == *"invite-code list"* ]]
	[[ "$output" == *"invite-code revoke"* ]]
	_acct218_teardown
}

@test "FEAT-218: invite-code create mints a 7-char alpha-num code" {
	_acct218_setup
	run "$LIGHTNING_BIN" account invite-code create alice-acct
	[ "$status" -eq 0 ]
	[[ "$output" == *"code:"* ]]
	[[ "$output" == *"account: alice-acct"* ]]
	[[ "$output" == *"link:    ?invite="* ]]
	local code
	code=$(echo "$output" | awk '/^code:/{print $2}')
	[[ "$code" =~ ^[a-z0-9]{7}$ ]]
	_acct218_teardown
}

@test "FEAT-218: invite-code create with --code accepts a vanity string" {
	_acct218_setup
	run "$LIGHTNING_BIN" account invite-code create alice-acct --code mycode
	[ "$status" -eq 0 ]
	[[ "$output" == *"code:    mycode"* ]]
	_acct218_teardown
}

@test "FEAT-218: invite-code create rejects invalid vanity strings" {
	_acct218_setup
	run "$LIGHTNING_BIN" account invite-code create alice-acct --code "Inv ALID!"
	[ "$status" -eq 1 ]
	[[ "$output" == *"[a-z0-9]"* ]]
	_acct218_teardown
}

@test "FEAT-218: invite-code create rejects duplicate codes" {
	_acct218_setup
	"$LIGHTNING_BIN" account invite-code create alice-acct --code dup1 >/dev/null
	run "$LIGHTNING_BIN" account invite-code create alice-acct --code dup1
	[ "$status" -eq 3 ]
	[[ "$output" == *"already exists"* ]]
	_acct218_teardown
}

@test "FEAT-218: invite-code list shows minted codes" {
	_acct218_setup
	"$LIGHTNING_BIN" account invite-code create alice-acct --code abc >/dev/null
	"$LIGHTNING_BIN" account invite-code create alice-acct --code xyz >/dev/null
	run "$LIGHTNING_BIN" account invite-code list alice-acct
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "code	account	uses	created_at" ]]
	[[ "$output" == *"abc"*"alice-acct"* ]]
	[[ "$output" == *"xyz"*"alice-acct"* ]]
	_acct218_teardown
}

@test "FEAT-218: invite-code revoke removes the code" {
	_acct218_setup
	"$LIGHTNING_BIN" account invite-code create alice-acct --code foo >/dev/null
	"$LIGHTNING_BIN" account invite-code revoke foo
	local n
	n=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM invite_codes WHERE code='foo';")
	[ "$n" = "0" ]
	_acct218_teardown
}

@test "FEAT-218: invite-code revoke on unknown code errors clearly" {
	_acct218_setup
	run "$LIGHTNING_BIN" account invite-code revoke nope
	[ "$status" -eq 2 ]
	[[ "$output" == *"not found"* ]]
	_acct218_teardown
}

@test "FEAT-218: api-accounts-create with valid code stamps referrer" {
	_acct218_setup
	"$LIGHTNING_BIN" account invite-code create alice-acct --code abcd >/dev/null
	REMOTE_ADDR=10.0.0.1 "$LIGHTNING_BIN" api-accounts-create --invite-code abcd >/dev/null
	local ref
	ref=$(sqlite3 "$BATS_DB" "SELECT referrer FROM accounts WHERE name LIKE 'anon-%' ORDER BY name DESC LIMIT 1;")
	[ "$ref" = "alice-acct" ]
	_acct218_teardown
}

@test "FEAT-218: api-accounts-create with unknown code silently falls back to house" {
	_acct218_setup
	REMOTE_ADDR=10.0.0.2 run "$LIGHTNING_BIN" api-accounts-create --invite-code totally-bogus-code
	[ "$status" -eq 0 ]
	local ref
	ref=$(sqlite3 "$BATS_DB" "SELECT referrer FROM accounts WHERE name LIKE 'anon-%' ORDER BY name DESC LIMIT 1;")
	[ "$ref" = "house" ]
	_acct218_teardown
}

@test "FEAT-218: api-accounts-create without code defaults referrer to house" {
	_acct218_setup
	REMOTE_ADDR=10.0.0.3 "$LIGHTNING_BIN" api-accounts-create >/dev/null
	local ref
	ref=$(sqlite3 "$BATS_DB" "SELECT referrer FROM accounts WHERE name LIKE 'anon-%' ORDER BY name DESC LIMIT 1;")
	[ "$ref" = "house" ]
	_acct218_teardown
}

@test "FEAT-218: api-accounts-create with code increments uses counter" {
	_acct218_setup
	"$LIGHTNING_BIN" account invite-code create alice-acct --code countme >/dev/null
	REMOTE_ADDR=10.0.0.4 "$LIGHTNING_BIN" api-accounts-create --invite-code countme >/dev/null
	REMOTE_ADDR=10.0.0.5 "$LIGHTNING_BIN" api-accounts-create --invite-code countme >/dev/null
	local uses
	uses=$(sqlite3 "$BATS_DB" "SELECT uses FROM invite_codes WHERE code='countme';")
	[ "$uses" = "2" ]
	_acct218_teardown
}

@test "FEAT-218: api-accounts-create JSON response includes referrer + referrals endpoint" {
	_acct218_setup
	"$LIGHTNING_BIN" account invite-code create alice-acct --code linktest >/dev/null
	local body
	body=$(REMOTE_ADDR=10.0.0.6 "$LIGHTNING_BIN" api-accounts-create --invite-code linktest 2>/dev/null)
	echo "$body" | jq -e '.referrer' >/dev/null
	echo "$body" | jq -e '.endpoints.referrals' >/dev/null
	local ref
	ref=$(echo "$body" | jq -r '.referrer')
	[ "$ref" = "alice-acct" ]
	_acct218_teardown
}

@test "FEAT-218: api-account-referrals returns the direct downline" {
	_acct218_setup
	"$LIGHTNING_BIN" account invite-code create alice-acct --code dl1 >/dev/null
	REMOTE_ADDR=10.0.0.7 "$LIGHTNING_BIN" api-accounts-create --invite-code dl1 >/dev/null
	REMOTE_ADDR=10.0.0.8 "$LIGHTNING_BIN" api-accounts-create --invite-code dl1 >/dev/null
	local body
	body=$("$LIGHTNING_BIN" api-account-referrals "$BATS_ADDR")
	local n
	n=$(echo "$body" | jq '.referrals | length')
	[ "$n" = "2" ]
	# Accrued credits stay 0 in FEAT-218; FEAT-219 fills them in.
	[ "$(echo "$body" | jq '.referrals[0].accrued_credits_sat')" = "0" ]
	_acct218_teardown
}

@test "FEAT-218: api-account-referrals on an account with no downline returns empty array" {
	_acct218_setup
	local body
	body=$("$LIGHTNING_BIN" api-account-referrals "$BATS_ADDR")
	[ "$body" = '{"referrals": []}' ]
	_acct218_teardown
}

@test "FEAT-218: api-account-referrals rejects non-bech32 input" {
	_acct218_setup
	run "$LIGHTNING_BIN" api-account-referrals "1AbCdEfGhIjKlMnOpQrStUvWxYz123"
	[ "$status" -ne 0 ]
	_acct218_teardown
}

@test "FEAT-218: api-account-referrals on unknown address returns error JSON" {
	_acct218_setup
	run "$LIGHTNING_BIN" api-account-referrals "bcrt1qaaa00000000000000000000000000000000000000"
	[[ "$output" == *'"error"'* ]]
	_acct218_teardown
}

@test "FEAT-218: sudoers fragment lists the new verbs" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
	grep -q "api-account-referrals" "$f"
	grep -q "api-accounts-create --invite-code" "$f"
}

@test "FEAT-218: spec file exists with the expected id" {
	for cand in \
		"$BATS_TEST_DIRNAME/../../issues/feature/218-referral-schema.md" \
		"$BATS_TEST_DIRNAME/../../issues/feature/done/218-referral-schema.md"; do
		[ -f "$cand" ] && f="$cand" && break
	done
	[ -n "$f" ]
	grep -q "^id: FEAT-218" "$f"
	grep -q "invite_codes" "$f"
}

@test "FEAT-219: with DIRECT_PCT=0 (default), whole skim still goes to house" {
	_acct219_setup
	outs=$(jq -nc --arg a "$BATS_REF_ADDR" \
		'[{"txid":"d1","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	# No DIRECT_PCT → default 0 → no split.
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	local house ref
	house=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='house' AND direction='in';")
	ref=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='inv-acct' AND direction='in';")
	[ "$house" = "200000" ]
	[ "$ref" = "0" ]
	_acct219_teardown
}

@test "FEAT-219: brand-new referee fails min-activity sybil 1 → all to house" {
	_acct219_setup
	outs=$(jq -nc --arg a "$BATS_REF_ADDR" \
		'[{"txid":"d1","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	# Referee has zero prior activity; default min=10000 sat blocks split.
	LIGHTNING_REFERRAL_DIRECT_PCT=20 \
		MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	local ref
	ref=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='inv-acct' AND direction='in';")
	[ "$ref" = "0" ]
	_acct219_teardown
}

@test "FEAT-219: qualified referee splits skim 20/80 between referrer and house" {
	_acct219_setup
	# Seed referee activity past the default min via a synthetic ledger
	# entry (faster than running a real topup, which the previous test
	# already covers in isolation).
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		VALUES(datetime('now'), '$BATS_REF_NAME', 'in', 100000000, 'seed', 'topup-watcher');"
	outs=$(jq -nc --arg a "$BATS_REF_ADDR" \
		'[{"txid":"d2","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	LIGHTNING_REFERRAL_DIRECT_PCT=20 \
		MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	# Skim on this topup = 200_000 msat; 20% = 40_000 msat to inv-acct,
	# 160_000 msat to house.  (House also has the previous-test 200_000
	# from the seed? No, we didn't run the no-split path here.)
	local ref house
	ref=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='inv-acct' AND direction='in' AND message LIKE 'fee:referral%';")
	house=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='house' AND direction='in';")
	[ "$ref" = "40000" ]
	[ "$house" = "160000" ]
	_acct219_teardown
}

@test "FEAT-219: per-day cap on referrer credits routes overflow to house" {
	_acct219_setup
	# Seed activity to pass sybil 1.
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		VALUES(datetime('now'), '$BATS_REF_NAME', 'in', 100000000, 'seed', 'topup-watcher');"
	# Seed today's referral credit at exactly the cap.
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, message) \
		VALUES(datetime('now'), 'inv-acct', 'in', 10000000, 'fee:referral from prior');"
	outs=$(jq -nc --arg a "$BATS_REF_ADDR" \
		'[{"txid":"dx","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	# Default cap = 10000 sat = 10M msat; already there → next skim
	# routes referrer share to house.
	LIGHTNING_REFERRAL_DIRECT_PCT=20 \
		MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	local today_new
	today_new=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='inv-acct' AND direction='in' AND message LIKE 'fee:referral from $BATS_REF_NAME%';")
	[ "$today_new" = "0" ]
	_acct219_teardown
}

@test "FEAT-219: api-account-pay JSON response includes referral_fee_sat" {
	_acct219_setup
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		VALUES(datetime('now'), '$BATS_REF_NAME', 'in', 100000000, 'seed', 'topup-watcher');"
	local body
	body=$(LIGHTNING_REFERRAL_DIRECT_PCT=20 "$LIGHTNING_BIN" api-account-pay "$BATS_REF_ADDR" "lnbcrt100p1pmocktest" 2>/dev/null)
	echo "$body" | jq -e '.referral_fee_sat' >/dev/null
	_acct219_teardown
}

@test "FEAT-219: api-account-referrals reflects accrued credits" {
	_acct219_setup
	# Seed activity + a referral credit directly so we don't depend on
	# the topup-watcher path within this test.
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		VALUES(datetime('now'), '$BATS_REF_NAME', 'in', 100000000, 'seed', 'topup-watcher');"
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, peer, message) \
		VALUES(datetime('now'), 'inv-acct', 'in', 40000, 'referee:$BATS_REF_NAME', 'fee:referral from $BATS_REF_NAME');"
	local body
	body=$("$LIGHTNING_BIN" api-account-referrals "$BATS_INV_ADDR")
	local credit
	credit=$(echo "$body" | jq ".referrals[0].accrued_credits_sat")
	[ "$credit" = "40" ]
	_acct219_teardown
}

@test "FEAT-219: referee with referrer='house' never gets a split" {
	_acct219_setup
	# Create a second referee with referrer=house (no invite code used).
	REMOTE_ADDR=10.0.0.99 "$LIGHTNING_BIN" api-accounts-create >/dev/null
	local other
	other=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name LIKE 'anon-%' AND referrer='house' LIMIT 1;")
	# Seed activity past threshold.
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		SELECT datetime('now'), name, 'in', 100000000, 'seed', 'topup-watcher' FROM accounts WHERE address = '$other';"
	outs=$(jq -nc --arg a "$other" \
		'[{"txid":"dx","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	LIGHTNING_REFERRAL_DIRECT_PCT=20 \
		MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	# Nothing should hit inv-acct's ledger.
	local inv
	inv=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='inv-acct';")
	[ "$inv" = "0" ]
	_acct219_teardown
}

@test "FEAT-219: invalid DIRECT_PCT is clamped sensibly" {
	_acct219_setup
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		VALUES(datetime('now'), '$BATS_REF_NAME', 'in', 100000000, 'seed', 'topup-watcher');"
	# DIRECT_PCT=999 → clamped to 100 → whole skim goes to referrer.
	outs=$(jq -nc --arg a "$BATS_REF_ADDR" \
		'[{"txid":"d2","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	LIGHTNING_REFERRAL_DIRECT_PCT=999 \
		MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	local ref house
	ref=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='inv-acct' AND direction='in' AND message LIKE 'fee:referral from $BATS_REF_NAME%';")
	house=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='house' AND direction='in' AND message LIKE 'fee:topup-onchain from $BATS_REF_NAME%';")
	[ "$ref" = "200000" ]
	[ "$house" = "0" ]
	_acct219_teardown
}

@test "FEAT-219: skim + referral redistribution is double-entry-clean" {
	_acct219_setup
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts, account, direction, amount_msat, payment_hash, message) \
		VALUES(datetime('now'), '$BATS_REF_NAME', 'in', 100000000, 'seed', 'topup-watcher');"
	outs=$(jq -nc --arg a "$BATS_REF_ADDR" \
		'[{"txid":"d2","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	LIGHTNING_REFERRAL_DIRECT_PCT=20 \
		MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
	# The topup-watcher row is external on-chain money (non-zero on
	# purpose) — the rest of the rows on this payment_hash are
	# redistributions that must sum to zero.
	local redist
	redist=$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger \
		WHERE payment_hash='d2:0' AND message != 'topup-watcher';")
	[ "$redist" = "0" ]
	_acct219_teardown
}

@test "FEAT-219: spec file exists with the expected id" {
	for cand in \
		"$BATS_TEST_DIRNAME/../../issues/feature/219-referral-fee-distribution.md" \
		"$BATS_TEST_DIRNAME/../../issues/feature/done/219-referral-fee-distribution.md"; do
		[ -f "$cand" ] && f="$cand" && break
	done
	[ -n "$f" ]
	grep -q "^id: FEAT-219" "$f"
	grep -q "referral_split" "$f"
}

@test "FEAT-223: transfer moves sats between accounts atomically" {
	_acct223_setup
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" beta 10000 --note lunch
	[ "$status" -eq 0 ]
	[[ "$output" == *'"status":"complete"'* ]]
	local a b
	a=$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='alpha';")
	b=$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='beta';")
	[ "$a" = "90000000" ]
	[ "$b" = "10000000" ]
	_acct223_teardown
}

@test "FEAT-223: transfer ledger rows share a correlation id" {
	_acct223_setup
	"$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" beta 10000 >/dev/null
	local n distinct
	n=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM ledger WHERE payment_hash LIKE 'xfer:%';")
	distinct=$(sqlite3 "$BATS_DB" "SELECT COUNT(DISTINCT payment_hash) FROM ledger WHERE payment_hash LIKE 'xfer:%';")
	[ "$n" = "2" ]
	[ "$distinct" = "1" ]
	_acct223_teardown
}

@test "FEAT-223: transfer to self is rejected" {
	_acct223_setup
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" alpha 100
	[ "$status" -ne 0 ]
	[[ "$output" == *"cannot_transfer_to_self"* ]]
	_acct223_teardown
}

@test "FEAT-223: transfer to unknown recipient is rejected" {
	_acct223_setup
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" nosuchaccount 100
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown_recipient"* ]]
	_acct223_teardown
}

@test "FEAT-223: overdraft=deny blocks an over-balance transfer (exit 6)" {
	_acct223_setup
	# beta has zero balance + deny policy.
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_B_ADDR" alpha 999999
	[ "$status" -eq 6 ]
	[[ "$output" == *"balance_insufficient"* ]]
	# No rows written (rolled back).
	local n
	n=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM ledger WHERE payment_hash LIKE 'xfer:%';")
	[ "$n" = "0" ]
	_acct223_teardown
}
