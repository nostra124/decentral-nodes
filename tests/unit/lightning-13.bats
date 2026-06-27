#!/usr/bin/env bats
#
# lightning unit tests — part 13 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-228: capture cannot exceed the authorized amount" {
	_acct228_setup
	local id; id=$(_chg 10000)
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" authorize "$id" >/dev/null
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" capture "$id" 20000
	[ "$status" -eq 6 ]
	[[ "$output" == *"capture_exceeds_authorization"* ]]
	_acct228_teardown
}

@test "FEAT-228: void returns the full authorized amount to the customer" {
	_acct228_setup
	local id; id=$(_chg 10000)
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" authorize "$id" >/dev/null
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" void "$id"
	[[ "$output" == *'"state":"voided"'* ]]
	[ "$(_sat escrow)" = "0" ]
	[ "$(_sat buyer)" = "100000" ]
	[ "$(_sat shop)" = "0" ]
	_acct228_teardown
}

@test "FEAT-228: installments amortise to exactly the amount and reach paid" {
	_acct228_setup
	local id; id=$(_chg 9000)
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" installments "$id" 3 >/dev/null
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" pay-installment "$id" >/dev/null
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" pay-installment "$id" >/dev/null
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" pay-installment "$id"
	[[ "$output" == *'"state":"paid"'* ]]
	[ "$(_sat shop)" = "9000" ]
	[ "$(_sat buyer)" = "91000" ]
	# A 4th installment is rejected.
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" pay-installment "$id"
	[ "$status" -eq 6 ]
	_acct228_teardown
}

@test "FEAT-228: installments with a non-divisible amount still sum exactly" {
	_acct228_setup
	local id; id=$(_chg 10000)
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" installments "$id" 3 >/dev/null
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" pay-installment "$id" >/dev/null
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" pay-installment "$id" >/dev/null
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" pay-installment "$id" >/dev/null
	[ "$(_sat shop)" = "10000" ]
	_acct228_teardown
}

@test "FEAT-228: dunning advances stages on an overdue charge + reports late fee" {
	_acct228_setup
	local id; id=$(_chg 5000 --terms '{"late_fee":{"pct":5}}' --due-days 0)
	sqlite3 "$BATS_DB" "UPDATE commerce_charges SET due_at = strftime('%s','now')-100 WHERE id='$id';"
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" dun "$id"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"state":"overdue"'* ]]
	[[ "$output" == *'"late_fee_sat":250'* ]]
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" dun "$id"
	[[ "$output" == *'"state":"dunning_1"'* ]]
	_acct228_teardown
}

@test "FEAT-228: dun before the due date is rejected" {
	_acct228_setup
	local id; id=$(_chg 5000 --due-days 30)
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" dun "$id"
	[ "$status" -eq 6 ]
	[[ "$output" == *"not_yet_due"* ]]
	_acct228_teardown
}

@test "FEAT-228: show returns the charge + its event log" {
	_acct228_setup
	local id; id=$(_chg 20000)
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" hold "$id" >/dev/null
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" release "$id" >/dev/null
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" show "$id"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.events | length == 3' >/dev/null
	echo "$output" | jq -e '.events[0].event == "created"' >/dev/null
	_acct228_teardown
}

@test "FEAT-228: list + scoping to the merchant" {
	_acct228_setup
	_chg 1000 >/dev/null
	_chg 2000 >/dev/null
	run "$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" list
	echo "$output" | jq -e '.charges | length == 2' >/dev/null
	# buyer (as a merchant) sees none.
	local buyer_addr; buyer_addr=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='buyer';")
	run "$LIGHTNING_BIN" api-account-charge "$buyer_addr" list
	echo "$output" | jq -e '.charges | length == 0' >/dev/null
	_acct228_teardown
}

@test "FEAT-228: ledger stays balanced across a full lifecycle" {
	_acct228_setup
	local id; id=$(_chg 12000)
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" hold "$id" >/dev/null
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" release "$id" >/dev/null
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" refund "$id" --sat 4000 >/dev/null
	# Sum of all ledger rows tagged to this charge nets to zero.
	[ "$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE payment_hash='$id';")" = "0" ]
	_acct228_teardown
}

@test "FEAT-228: sudoers fragment lists api-account-charge" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
	grep -q "api-account-charge" "$f"
}

@test "FEAT-228: schema declares commerce_charges + commerce_events + escrow" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/schema.sql"
	grep -q "CREATE TABLE IF NOT EXISTS commerce_charges" "$f"
	grep -q "CREATE TABLE IF NOT EXISTS commerce_events" "$f"
	grep -q "VALUES('escrow'" "$f"
}

@test "FEAT-230: FIFO disposal export computes the gain against the oldest lot" {
	_acct230_setup
	run "$LIGHTNING_BIN" wallet export tax-data trader --year 2024 --base EUR --format json
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.disposals | length == 1' >/dev/null
	[ "$(echo "$output" | jq -r '.disposals[0].acquisition_date')" = "2023-05-01" ]
	echo "$output" | jq -e '.disposals[0].fiat_in == 100' >/dev/null
	echo "$output" | jq -e '.disposals[0].fiat_out == 200' >/dev/null
	echo "$output" | jq -e '.disposals[0].gain == 100' >/dev/null
	echo "$output" | jq -e '.disposals[0].holding_days == 406' >/dev/null
	echo "$output" | jq -e '.summary.total_gain == 100' >/dev/null
	_acct230_teardown
}

@test "FEAT-230: output is labelled data-for-preparation, with a disclaimer" {
	_acct230_setup
	run "$LIGHTNING_BIN" wallet export tax-data trader --year 2024 --format json
	[ "$(echo "$output" | jq -r '.kind')" = "transaction_data_for_tax_preparation" ]
	[[ "$(echo "$output" | jq -r '.disclaimer')" == *"NOT a tax report"* ]]
	[ "$(echo "$output" | jq -r '.summary.freigrenze_eur')" = "600" ]
	_acct230_teardown
}

@test "FEAT-230: year filter excludes disposals from other years" {
	_acct230_setup
	run "$LIGHTNING_BIN" wallet export tax-data trader --year 2025 --format json
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.disposals | length == 0' >/dev/null
	_acct230_teardown
}

@test "FEAT-230: missing price surfaces an explicit gap, never 0" {
	_acct230_setup
	# A disposal far from any price tick.
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts,account,direction,amount_msat,message) VALUES('2024-09-01 12:00:00','trader','out',-100000000,'spend2');"
	run "$LIGHTNING_BIN" wallet export tax-data trader --year 2024 --format json
	echo "$output" | jq -e '[.disposals[] | select(.price_gap == true)] | length >= 1' >/dev/null
	# The gapped row has null gain (not 0).
	echo "$output" | jq -e '[.disposals[] | select(.price_gap == true) | .gain] | all(. == null)' >/dev/null
	_acct230_teardown
}

@test "FEAT-230: operator export values fee revenue at receipt" {
	_acct230_setup
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts,account,direction,amount_msat,message) VALUES('2024-01-10 12:05:00','house','in',2500000,'fee:transfer');"
	run "$LIGHTNING_BIN" wallet export tax-data --operator --year 2024 --format json
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -r '.kind')" = "operator_fee_income_data_for_tax_preparation" ]
	echo "$output" | jq -e '.income | length == 1' >/dev/null
	# 2500 sat * 40000 / 1e8 = 1.00 EUR
	echo "$output" | jq -e '.income[0].fiat_value == 1' >/dev/null
	_acct230_teardown
}

@test "FEAT-230: CSV format validates (header + 8 columns)" {
	_acct230_setup
	run "$LIGHTNING_BIN" wallet export tax-data trader --year 2024 --format csv
	[ "$status" -eq 0 ]
	[[ "$output" == *"disposal_date,disposal_sat,acquisition_date,holding_days,fiat_in,fiat_out,gain,price_gap"* ]]
	# The single data row has 8 comma-separated fields.
	local cols
	cols=$(echo "$output" | grep -v '^#' | grep '^2024-06-10' | awk -F, '{print NF}')
	[ "$cols" = "8" ]
	_acct230_teardown
}

@test "FEAT-230: bad format / missing year / unknown account are rejected" {
	_acct230_setup
	run "$LIGHTNING_BIN" wallet export tax-data trader --year 2024 --format xml
	[ "$status" -ne 0 ]
	run "$LIGHTNING_BIN" wallet export tax-data trader
	[ "$status" -ne 0 ]
	run "$LIGHTNING_BIN" wallet export tax-data nobody --year 2024
	[ "$status" -ne 0 ]
	_acct230_teardown
}

@test "FEAT-230: export resolves an account by bech32 address too" {
	_acct230_setup
	local addr; addr=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='trader';")
	run "$LIGHTNING_BIN" wallet export tax-data "$addr" --year 2024 --format json
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -r '.account')" = "trader" ]
	_acct230_teardown
}

@test "FEAT-230: sudoers fragment lists export tax-data" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
	grep -q "export tax-data" "$f"
}

@test "FEAT-216: interest mode credits the user a yield on a deposit" {
	_acct216_setup
	# topup-onchain: interest on, rate -2000 ppm (-0.2%).
	sed -i '/^operation: topup-onchain$/,/^$/{s/^rate_ppm:.*/rate_ppm:  -2000/; s/^interest_mode:.*/interest_mode: on/}' "$BATS_FEES"
	_deposit_100k
	# 100 000-sat deposit + 200-sat interest = 100 200 sat.
	[ "$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='saver';")" = "100200000" ]
	_acct216_teardown
}

@test "FEAT-216: the interest subsidy is debited from house with the matching payment_hash" {
	_acct216_setup
	sed -i '/^operation: topup-onchain$/,/^$/{s/^rate_ppm:.*/rate_ppm:  -2000/; s/^interest_mode:.*/interest_mode: on/}' "$BATS_FEES"
	_deposit_100k
	[ "$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='house';")" = "-200000" ]
	# Same payment_hash links the user credit and the house debit.
	local ph
	ph=$(sqlite3 "$BATS_DB" "SELECT payment_hash FROM ledger WHERE account='house' AND message LIKE 'interest:%';")
	[ -n "$ph" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM ledger WHERE payment_hash='$ph' AND message LIKE 'interest:%';")" = "2" ]
	_acct216_teardown
}

@test "FEAT-216: a negative rate with interest_mode off pays NO subsidy (clamped)" {
	_acct216_setup
	# Negative rate but interest mode off -> skim clamps to 0.
	sed -i '/^operation: topup-onchain$/,/^$/{s/^rate_ppm:.*/rate_ppm:  -2000/; s/^interest_mode:.*/interest_mode: off/}' "$BATS_FEES"
	_deposit_100k
	# User gets exactly the deposit; house untouched.
	[ "$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='saver';")" = "100000000" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='house';")" = "0" ]
	_acct216_teardown
}

@test "FEAT-216: autotune refuses a negative rate when interest_mode is off" {
	_acct216_setup
	sed -i '/^operation: topup-onchain$/,/^$/{s/^rate_ppm:.*/rate_ppm:  -2000/; s/^interest_mode:.*/interest_mode: off/}' "$BATS_FEES"
	LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY=1000 run "$LIGHTNING_BIN" channel fee-policy autotune dry-run
	[ "$status" -eq 3 ]
	[[ "$output" == *"interest_mode is off"* ]]
	_acct216_teardown
}

@test "FEAT-216: autotune accepts a negative rate when interest_mode is on" {
	_acct216_setup
	sed -i '/^operation: topup-onchain$/,/^$/{s/^rate_ppm:.*/rate_ppm:  -1000/; s/^interest_mode:.*/interest_mode: on/}' "$BATS_FEES"
	LIGHTNING_FEE_AUTOTUNE_TARGET_MSAT_PER_DAY=1000 run "$LIGHTNING_BIN" channel fee-policy autotune dry-run
	[ "$status" -eq 0 ]
	_acct216_teardown
}

@test "FEAT-216: fee-policy status reports the cumulative interest subsidy" {
	_acct216_setup
	sed -i '/^operation: topup-onchain$/,/^$/{s/^rate_ppm:.*/rate_ppm:  -2000/; s/^interest_mode:.*/interest_mode: on/}' "$BATS_FEES"
	_deposit_100k
	run "$LIGHTNING_BIN" channel fee-policy status
	[ "$status" -eq 0 ]
	[[ "$output" == *"interest_subsidy_paid_sat: 200"* ]]
	[[ "$output" == *"interest_mode_ops:"* ]]
	[[ "$output" == *"topup-onchain"* ]]
	_acct216_teardown
}

@test "FEAT-216: default fees.recfile ships interest_mode off + a legal caution" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/defaults/fees.recfile"
	grep -q "interest_mode: off" "$f"
	grep -qi "CAUTION" "$f"
	grep -qi "deposit-taking" "$f"
}

@test "FEAT-217: paytarget-intel suggests the top paid destination" {
	_paytarget_history
	MOCK_LISTPEERCHANNELS='[]' run "$LIGHTNING_BIN" channel paytarget-intel
	[ "$status" -eq 0 ]
	local f="$HOME/.lightning/autopilot/paytarget.suggest.recfile"
	[ -f "$f" ]
	grep -q "kind: pay-target-channels" "$f"
	grep -q "node_id: $PT_A" "$f"
	# A (30000 sat) is the top entry, before B.
	[ "$(grep -n "node_id: $PT_A" "$f" | cut -d: -f1)" -lt "$(grep -n "node_id: $PT_B" "$f" | cut -d: -f1)" ]
}

@test "FEAT-217: a directly-connected destination is excluded" {
	_paytarget_history
	# We already have a channel to C.
	local peers; peers=$(jq -nc --arg c "$PT_C" '[{peer_id:$c}]')
	MOCK_LISTPEERCHANNELS="$peers" run "$LIGHTNING_BIN" channel paytarget-intel
	[ "$status" -eq 0 ]
	local f="$HOME/.lightning/autopilot/paytarget.suggest.recfile"
	! grep -q "node_id: $PT_C" "$f"
	grep -q "node_id: $PT_A" "$f"
}

@test "FEAT-217: empty pay history is a no-op (no file written)" {
	MOCK_LISTPAYS='[]' MOCK_LISTPEERCHANNELS='[]' run "$LIGHTNING_BIN" channel paytarget-intel
	[ "$status" -eq 0 ]
	[[ "$output" == *"no pay-target suggestions"* ]]
	[ ! -f "$HOME/.lightning/autopilot/paytarget.suggest.recfile" ]
}

@test "FEAT-217: pays outside the window are excluded" {
	local now; now=$(date -u +%s)
	local node=02dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
	# A single completed pay, but ~2 years ago.
	MOCK_LISTPAYS=$(jq -nc --arg d "$node" --argjson now "$now" \
		'[{status:"complete",destination:$d,amount_msat:10000000,created_at:($now-60000000)}]')
	MOCK_LISTPAYS="$MOCK_LISTPAYS" MOCK_LISTPEERCHANNELS='[]' run "$LIGHTNING_BIN" channel paytarget-intel
	[ "$status" -eq 0 ]
	[[ "$output" == *"no pay-target suggestions"* ]]
}

@test "FEAT-217: --dry-run prints but writes nothing" {
	_paytarget_history
	MOCK_LISTPEERCHANNELS='[]' run "$LIGHTNING_BIN" channel paytarget-intel --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"dry-run"* ]]
	[[ "$output" == *"$PT_A"* ]]
	[ ! -f "$HOME/.lightning/autopilot/paytarget.suggest.recfile" ]
}

@test "FEAT-217: --top caps the number of suggestions" {
	_paytarget_history
	# Exclude C (highest volume) so A is the top remaining target.
	local peers; peers=$(jq -nc --arg c "$PT_C" '[{peer_id:$c}]')
	MOCK_LISTPEERCHANNELS="$peers" run "$LIGHTNING_BIN" channel paytarget-intel --top 1
	[ "$status" -eq 0 ]
	local f="$HOME/.lightning/autopilot/paytarget.suggest.recfile"
	[ "$(grep -c '^node_id:' "$f")" = "1" ]
	grep -q "node_id: $PT_A" "$f"
}

@test "FEAT-217: autopilot run feeds the pay-target suggest queue" {
	_paytarget_history
	MOCK_LISTPEERCHANNELS='[]' run "$LIGHTNING_BIN" channel autopilot run --dry-run
	[ "$status" -eq 0 ]
	# autopilot run invokes paytarget-intel as a real write (not dry).
	[ -f "$HOME/.lightning/autopilot/paytarget.suggest.recfile" ]
	grep -q "node_id: $PT_A" "$HOME/.lightning/autopilot/paytarget.suggest.recfile"
}

@test "FEAT-217: channel usage lists paytarget-intel" {
	run "$LIGHTNING_BIN" channel
	[[ "$output" == *"paytarget-intel"* ]]
}

@test "FEAT-233: with no compliance.recfile every hook is a no-op (transfer works)" {
	_cc_setup
	[ ! -f "$BATS_CF" ]
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" beta 10000
	[ "$status" -eq 0 ]
	[[ "$output" == *'"status":"complete"'* ]]
	# No audit rows written when the framework is off.
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM compliance_events;")" = "0" ]
	_cc_teardown
}

@test "FEAT-233: preset us-msb enables the expected module set" {
	_cc_setup
	run "$LIGHTNING_BIN" wallet compliance preset us-msb
	[ "$status" -eq 0 ]
	[ -f "$BATS_CF" ]
	run "$LIGHTNING_BIN" wallet compliance status
	[[ "$output" == *"kyc"*"on"* ]]
	# kyc / screening / travel_rule on; data_subject_rights off in this preset.
	"$LIGHTNING_BIN" wallet compliance status | grep -E "^  kyc " | grep -q on
	"$LIGHTNING_BIN" wallet compliance status | grep -E "^  travel_rule " | grep -q on
	"$LIGHTNING_BIN" wallet compliance status | grep -E "^  proof_of_reserves " | grep -q on
	_cc_teardown
}

@test "FEAT-233: a deny pre-hook blocks the transaction (exit 6 + error)" {
	_cc_setup
	"$LIGHTNING_BIN" wallet compliance preset off >/dev/null
	_cc_test_module deny
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" beta 5000
	[ "$status" -eq 6 ]
	[[ "$output" == *"compliance_denied"* ]]
	# The transfer did NOT move funds.
	[ "$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='beta';")" = "0" ]
	# The deny was recorded to the audit log.
	[ "$(sqlite3 "$BATS_DB" "SELECT decision FROM compliance_events WHERE hook='pre' AND op='transfer';")" = "deny" ]
	_cc_teardown
}

@test "FEAT-233: a post-hook records to compliance_events without blocking" {
	_cc_setup
	"$LIGHTNING_BIN" wallet compliance preset off >/dev/null
	_cc_test_module allow
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" beta 5000
	[ "$status" -eq 0 ]
	[[ "$output" == *'"status":"complete"'* ]]
	# Funds moved AND a post observe row exists.
	[ "$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='beta';")" = "5000000" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM compliance_events WHERE hook='post' AND op='transfer' AND decision='observe';")" -ge 1 ]
	_cc_teardown
}

@test "FEAT-233: pay + withdraw + create are wired to the hooks" {
	_cc_setup
	"$LIGHTNING_BIN" wallet compliance preset off >/dev/null
	_cc_test_module deny
	# pay denied
	run "$LIGHTNING_BIN" api-account-pay "$BATS_A_ADDR" lnbcrt10n1xxx
	[ "$status" -eq 6 ]
	[[ "$output" == *"compliance_denied"* ]]
	# create denied (anonymous self-service)
	REMOTE_ADDR=9.9.9.9 run "$LIGHTNING_BIN" api-accounts-create
	[ "$status" -ne 0 ]
	[[ "$output" == *"compliance_denied"* ]]
	_cc_teardown
}

@test "FEAT-233: compliance status reports modules + footers the disclaimer" {
	_cc_setup
	"$LIGHTNING_BIN" wallet compliance preset de-custodial >/dev/null
	run "$LIGHTNING_BIN" wallet compliance status
	[ "$status" -eq 0 ]
	[[ "$output" == *"DISCLAIMER"* ]]
	[[ "$output" == *"consult a qualified local lawyer"* ]]
	_cc_teardown
}

@test "FEAT-233: preset prints the disclaimer on application" {
	_cc_setup
	run "$LIGHTNING_BIN" wallet compliance preset uk-fca
	[ "$status" -eq 0 ]
	[[ "$output" == *"consult a qualified local lawyer"* ]]
	_cc_teardown
}

@test "FEAT-233: unknown preset is rejected" {
	_cc_setup
	run "$LIGHTNING_BIN" wallet compliance preset narnia
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown preset"* ]]
	_cc_teardown
}

@test "FEAT-233: status with no config reports framework OFF" {
	_cc_setup
	run "$LIGHTNING_BIN" wallet compliance status
	[ "$status" -eq 0 ]
	[[ "$output" == *"framework OFF"* ]]
	_cc_teardown
}

@test "FEAT-233: GC retention veto holds a delete-eligible account" {
	_cc_setup
	# Make beta a long-closed, delete-eligible account.
	sqlite3 "$BATS_DB" "UPDATE accounts SET closed_at = strftime('%s','now') - 400*86400, created_at = strftime('%s','now') - 500*86400 WHERE name='beta';"
	"$LIGHTNING_BIN" wallet compliance preset off >/dev/null
	_cc_test_module deny
	run "$LIGHTNING_BIN" account gc run
	[ "$status" -eq 0 ]
	# beta retained (legal hold), not deleted.
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM accounts WHERE name='beta';")" = "1" ]
	[[ "$output" == *"retain"* ]]
	_cc_teardown
}

@test "FEAT-233: DISCLAIMER.txt ships under share/lightning/compliance" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/compliance/DISCLAIMER.txt"
	[ -f "$f" ]
	grep -qi "not legal advice" "$f"
	grep -qi "consult a qualified local lawyer" "$f"
}

@test "FEAT-233: schema declares compliance_events" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/schema.sql"
	grep -q "CREATE TABLE IF NOT EXISTS compliance_events" "$f"
}

# ---------------------------------------------------------------------------
# FEAT-221: per-verb man-page tree.
# ---------------------------------------------------------------------------

@test "FEAT-221: every dispatchable verb has a man page naming it" {
	local libexec="$BATS_TEST_DIRNAME/../../libexec/lightning-node"
	local man="$BATS_TEST_DIRNAME/../../share/man/man1"
	local missing=""
	local v page
	for path in "$libexec"/*; do
		v=$(basename "$path")
		# Skip internal helpers (_*) and the api-* HTTP-bridge verbs
		# (documented via the FEAT-209 inline docs, not man pages).
		case "$v" in _*|api-*) continue ;; esac
		page="$man/lightning-$v.1"
		if [ ! -f "$page" ]; then
			missing="$missing $v(no-page)"
			continue
		fi
		# The verb name must appear in the .SH NAME stanza.
		awk '/^\.SH NAME/{f=1; next} /^\.SH /{f=0} f' "$page" | grep -q "lightning-$v" \
			|| missing="$missing $v(no-name)"
	done
	[ -z "$missing" ] || { echo "missing/bad man pages:$missing"; false; }
}

@test "FEAT-221: lightning-account.1 covers the account subcommands" {
	local page="$BATS_TEST_DIRNAME/../../share/man/man1/lightning-account.1"
	[ -f "$page" ]
	local s
	for s in create show close nickname topup withdraw pay receive apikey topup-watcher gc; do
		grep -q "$s" "$page" || { echo "account man page missing: $s"; false; }
	done
}

@test "FEAT-221: every per-verb page has NAME + SYNOPSIS + DESCRIPTION + balanced nf/fi" {
	local man="$BATS_TEST_DIRNAME/../../share/man/man1"
	local f bad=""
	for f in "$man"/lightning-*.1; do
		grep -q '^\.TH ' "$f"        || bad="$bad $(basename "$f"):TH"
		grep -q '^\.SH NAME'      "$f" || bad="$bad $(basename "$f"):NAME"
		grep -q '^\.SH SYNOPSIS'  "$f" || bad="$bad $(basename "$f"):SYN"
		grep -q '^\.SH DESCRIPTION' "$f" || bad="$bad $(basename "$f"):DESC"
		[ "$(grep -c '^\.nf$' "$f")" = "$(grep -c '^\.fi$' "$f")" ] || bad="$bad $(basename "$f"):nf"
	done
	[ -z "$bad" ] || { echo "bad pages:$bad"; false; }
}
