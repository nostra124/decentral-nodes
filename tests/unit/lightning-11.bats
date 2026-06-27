#!/usr/bin/env bats
#
# lightning unit tests — part 11 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-223: transfer resolves recipient by address too" {
	_acct223_setup
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" "$BATS_B_ADDR" 7000
	[ "$status" -eq 0 ]
	local b
	b=$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='beta';")
	[ "$b" = "7000000" ]
	_acct223_teardown
}

@test "FEAT-223: zero / non-numeric amount rejected" {
	_acct223_setup
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" beta 0
	[ "$status" -ne 0 ]
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" beta abc
	[ "$status" -ne 0 ]
	_acct223_teardown
}

@test "FEAT-223: transfer skims an operator fee when configured" {
	_acct223_setup
	# Set transfer fee to 1% (10000 ppm).
	sed -i '/^operation: transfer$/,/^$/{s/^rate_ppm:.*$/rate_ppm:  10000/}' "$LIGHTNING_WALLETS_ROOT/alice/fees.recfile"
	"$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" beta 10000 >/dev/null
	# 10000-sat transfer at 1% = 100-sat fee → house.
	local house
	house=$(sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0) FROM ledger WHERE account='house' AND direction='in';")
	[ "$house" = "100000" ]
	# alpha debited amount + fee.
	local a
	a=$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE account='alpha';")
	# 100000000 - 10000000 (transfer) - 100000 (fee) = 89900000
	[ "$a" = "89900000" ]
	_acct223_teardown
}

@test "FEAT-223: redistribution (excluding the transfer pair) is balanced" {
	_acct223_setup
	sed -i '/^operation: transfer$/,/^$/{s/^rate_ppm:.*$/rate_ppm:  10000/}' "$LIGHTNING_WALLETS_ROOT/alice/fees.recfile"
	"$LIGHTNING_BIN" api-account-transfer "$BATS_A_ADDR" beta 10000 >/dev/null
	# All rows for this xfer sum to -fee (the transfer pair cancels;
	# the fee leaves alpha and lands split house/referrer).  With no
	# referrer, alpha -fee, house +fee → fee rows net zero; transfer
	# pair nets zero → grand total zero.
	local total
	total=$(sqlite3 "$BATS_DB" "SELECT SUM(amount_msat) FROM ledger WHERE payment_hash LIKE 'xfer:%';")
	[ "$total" = "0" ]
	_acct223_teardown
}

@test "FEAT-223: CLI account transfer works with handles" {
	_acct223_setup
	run "$LIGHTNING_BIN" account transfer alpha beta 5000 --note "via cli"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"status":"complete"'* ]]
	_acct223_teardown
}

@test "FEAT-223: account verb help lists transfer" {
	run "$LIGHTNING_BIN" account
	[[ "$output" == *"transfer <from> <to> <sat>"* ]]
}

@test "FEAT-223: default fees.recfile carries a transfer op" {
	_acct223_setup
	grep -q "^operation: transfer" "$LIGHTNING_WALLETS_ROOT/alice/fees.recfile"
	_acct223_teardown
}

@test "FEAT-223: sudoers fragment lists api-account-transfer" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
	grep -q "api-account-transfer" "$f"
}

@test "FEAT-225: invoice create returns bolt11 + payment_hash + face/effective" {
	_acct225_setup
	run "$LIGHTNING_BIN" api-account-invoice "$BATS_SHOP_ADDR" 100000
	[ "$status" -eq 0 ]
	[[ "$(echo "$output" | jq -r '.bolt11')" == lnbcrt* ]]
	[ "$(echo "$output" | jq -r '.face_sat')" = "100000" ]
	[ "$(echo "$output" | jq -r '.effective_sat')" = "100000" ]
	[ -n "$(echo "$output" | jq -r '.payment_hash')" ]
	_acct225_teardown
}

@test "FEAT-225: reference is embedded recoverably in the BOLT-11 description" {
	_acct225_setup
	"$LIGHTNING_BIN" api-account-invoice "$BATS_SHOP_ADDR" 5000 \
		--ref '{"order_id":"A-42","delivery_note":"DN-7","memo":"widgets"}' >/dev/null
	local desc b64 pad json
	desc=$(cat "$MOCK_STATE.lastdesc")
	[[ "$desc" == *"widgets [ref:"* ]]
	# Pull the base64url payload back out and decode it.
	b64=$(echo "$desc" | sed -n 's/.*\[ref:\([A-Za-z0-9_-]*\)\].*/\1/p')
	[ -n "$b64" ]
	pad=$(( (4 - ${#b64} % 4) % 4 ))
	while [ "$pad" -gt 0 ]; do b64="${b64}="; pad=$((pad-1)); done
	json=$(echo "$b64" | tr '_-' '/+' | base64 -d)
	[ "$(echo "$json" | jq -r '.order_id')" = "A-42" ]
	[ "$(echo "$json" | jq -r '.delivery_note')" = "DN-7" ]
	_acct225_teardown
}

@test "FEAT-225: invoice create persists a commerce_invoices row + mirrors to invoices" {
	_acct225_setup
	local out hash
	out=$("$LIGHTNING_BIN" api-account-invoice "$BATS_SHOP_ADDR" 12345 --ref '{"order_id":"X1"}')
	hash=$(echo "$out" | jq -r '.payment_hash')
	[ "$(sqlite3 "$BATS_DB" "SELECT face_sat FROM commerce_invoices WHERE payment_hash='$hash';")" = "12345" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT account FROM commerce_invoices WHERE payment_hash='$hash';")" = "shop" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT state FROM commerce_invoices WHERE payment_hash='$hash';")" = "issued" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM invoices WHERE payment_hash='$hash';")" = "1" ]
	_acct225_teardown
}

@test "FEAT-225: Skonto discount applies at issue time" {
	_acct225_setup
	run "$LIGHTNING_BIN" api-account-invoice "$BATS_SHOP_ADDR" 100000 \
		--terms '{"due_days":14,"skonto":{"within_days":7,"discount_pct":2}}'
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -r '.effective_sat')" = "98000" ]
	_acct225_teardown
}

@test "FEAT-225: invoice-get returns the reference back + paid:false before settle" {
	_acct225_setup
	local hash
	hash=$("$LIGHTNING_BIN" api-account-invoice "$BATS_SHOP_ADDR" 5000 --ref '{"order_id":"A-42"}' | jq -r '.payment_hash')
	run "$LIGHTNING_BIN" api-account-invoice-get "$BATS_SHOP_ADDR" "$hash"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -r '.reference.order_id')" = "A-42" ]
	[ "$(echo "$output" | jq -r '.paid')" = "false" ]
	[ "$(echo "$output" | jq -r '.state')" = "issued" ]
	_acct225_teardown
}

@test "FEAT-225: invoice-get flips to paid:true after (mock) settlement" {
	_acct225_setup
	local hash
	hash=$("$LIGHTNING_BIN" api-account-invoice "$BATS_SHOP_ADDR" 5000 | jq -r '.payment_hash')
	MOCK_LISTINVOICES='[{"status":"paid"}]' run "$LIGHTNING_BIN" api-account-invoice-get "$BATS_SHOP_ADDR" "$hash"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -r '.paid')" = "true" ]
	[ "$(echo "$output" | jq -r '.state')" = "paid" ]
	# Persisted.
	[ "$(sqlite3 "$BATS_DB" "SELECT state FROM commerce_invoices WHERE payment_hash='$hash';")" = "paid" ]
	_acct225_teardown
}

@test "FEAT-225: invoice-get computes a late fee once past the grace period" {
	_acct225_setup
	local hash
	hash=$("$LIGHTNING_BIN" api-account-invoice "$BATS_SHOP_ADDR" 100000 \
		--terms '{"due_days":14,"skonto":{"within_days":7,"discount_pct":2},"late_fee":{"after_days":14,"pct":5}}' \
		| jq -r '.payment_hash')
	# Backdate issuance 30 days: past due(14)+grace(14)=28 → late fee.
	sqlite3 "$BATS_DB" "UPDATE commerce_invoices SET issued_at = issued_at - 30*86400 WHERE payment_hash='$hash';"
	run "$LIGHTNING_BIN" api-account-invoice-get "$BATS_SHOP_ADDR" "$hash"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -r '.effective_sat')" = "105000" ]
	_acct225_teardown
}

@test "FEAT-225: invoice-get reports face == effective when no terms" {
	_acct225_setup
	local hash
	hash=$("$LIGHTNING_BIN" api-account-invoice "$BATS_SHOP_ADDR" 7777 | jq -r '.payment_hash')
	run "$LIGHTNING_BIN" api-account-invoice-get "$BATS_SHOP_ADDR" "$hash"
	[ "$(echo "$output" | jq -r '.face_sat')" = "7777" ]
	[ "$(echo "$output" | jq -r '.effective_sat')" = "7777" ]
	[ "$(echo "$output" | jq -r '.terms')" = "null" ]
	_acct225_teardown
}

@test "FEAT-225: invoice-get is scoped to the owning account" {
	_acct225_setup
	local hash
	hash=$("$LIGHTNING_BIN" api-account-invoice "$BATS_SHOP_ADDR" 5000 | jq -r '.payment_hash')
	# `other` must not be able to read shop's invoice.
	run "$LIGHTNING_BIN" api-account-invoice-get "$BATS_OTHER_ADDR" "$hash"
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown invoice"* ]]
	_acct225_teardown
}

@test "FEAT-225: invoice create rejects non-positive amount + bad JSON" {
	_acct225_setup
	run "$LIGHTNING_BIN" api-account-invoice "$BATS_SHOP_ADDR" 0
	[ "$status" -ne 0 ]
	run "$LIGHTNING_BIN" api-account-invoice "$BATS_SHOP_ADDR" 100 --ref 'not json'
	[ "$status" -ne 0 ]
	[[ "$output" == *"ref_not_json"* ]]
	_acct225_teardown
}

@test "FEAT-225: invoice verbs reject unknown account" {
	_acct225_setup
	run "$LIGHTNING_BIN" api-account-invoice "bcrt1qaaa00000000000000000000000000000000000000" 100
	[[ "$output" == *"unknown account"* ]]
	_acct225_teardown
}

@test "FEAT-225: sudoers fragment lists the invoice verbs" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
	grep -q "api-account-invoice " "$f"
	grep -q "api-account-invoice-get " "$f"
}

@test "FEAT-225: schema declares commerce_invoices" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/schema.sql"
	grep -q "CREATE TABLE IF NOT EXISTS commerce_invoices" "$f"
}

# ---------------------------------------------------------------------------
# FEAT-224 + FEAT-232: versioned .well-known move + API versioning.
# ---------------------------------------------------------------------------

@test "FEAT-224: apache vhost mounts MCP under .well-known/v1 (accounts moved to thunder)" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/apache/lnurlp.conf"
	# 2.0.0: the account API moved to the thunder repo; MCP stays local.
	grep -q "ScriptAlias /.well-known/lightning/v1/mcp" "$f"
	# Old unversioned aliases are gone.
	! grep -qE "ScriptAlias /api/accounts\b" "$f"
	! grep -qE "ScriptAlias /api/mcp\b" "$f"
}

@test "FEAT-224: api-accounts-create emits versioned .well-known endpoint URLs" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	local body
	body=$(REMOTE_ADDR=1.2.3.4 "$LIGHTNING_BIN" api-accounts-create 2>/dev/null)
	[[ "$(echo "$body" | jq -r '.endpoints.balance')" == /.well-known/lightning/v1/accounts/*/balance ]]
	[[ "$(echo "$body" | jq -r '.endpoints.transfer')" == /.well-known/lightning/v1/accounts/*/transfer ]]
	[[ "$(echo "$body" | jq -r '.endpoints.referrals')" == /.well-known/lightning/v1/accounts/*/referrals ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

@test "FEAT-232: versions.json advertises v1 as default" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/lightning/versions.json"
	[ -f "$f" ]
	jq -e '.versions | index("v1")' "$f" >/dev/null
	[ "$(jq -r '.default' "$f")" = "v1" ]
	jq -e '.surfaces.accounts == "/.well-known/lightning/v1/accounts"' "$f" >/dev/null
	jq -e '.surfaces.mcp == "/.well-known/lightning/v1/mcp"' "$f" >/dev/null
}

@test "FEAT-224: mcp.json manifest carries the versioned endpoint" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/lightning/mcp.json"
	[ "$(jq -r '.transport.endpoint' "$f")" = "/.well-known/lightning/v1/mcp" ]
	[ "$(jq -r '.apiVersion' "$f")" = "v1" ]
	[ "$(jq -r '.links.rest' "$f")" = "/.well-known/lightning/v1/accounts" ]
}

@test "FEAT-232: apache vhost has the unknown-version catch-all + versions.json Alias" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/apache/lnurlp.conf"
	grep -q "version_gate.py" "$f"
	grep -q "Alias /.well-known/lightning/versions.json" "$f"
}

@test "FEAT-232: version_gate is executable Python" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/version_gate.py"
	[ -x "$f" ]
	head -1 "$f" | grep -q python3
}

@test "FEAT-222 PR-2: schema has wallet_users distinct from the FEAT-176 users table" {
	_user222_setup
	# Both tables exist + are different.
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='wallet_users';")" = "1" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='users';")" = "1" ]
	_user222_teardown
}

@test "FEAT-222 PR-2: accounts gains owner_user; invite_codes gains owner_user + credit_account" {
	_user222_setup
	sqlite3 "$BATS_DB" "PRAGMA table_info(accounts);" | awk -F'|' '{print $2}' | grep -qx owner_user
	sqlite3 "$BATS_DB" "PRAGMA table_info(invite_codes);" | awk -F'|' '{print $2}' | grep -qx owner_user
	sqlite3 "$BATS_DB" "PRAGMA table_info(invite_codes);" | awk -F'|' '{print $2}' | grep -qx credit_account
	_user222_teardown
}

@test "FEAT-222 PR-2: user create mints a usr_ id" {
	_user222_setup
	run "$LIGHTNING_BIN" wallet user create --label operator
	[ "$status" -eq 0 ]
	[[ "$output" == *"created usr_"* ]]
	[[ "$output" == *"label:    operator"* ]]
	local uid
	uid=$(echo "$output" | awk '/created/{print $4}')
	[[ "$uid" =~ ^usr_[a-z0-9]{16}$ ]]
	_user222_teardown
}

@test "FEAT-222 PR-2: user create --referrer requires an existing user" {
	_user222_setup
	run "$LIGHTNING_BIN" wallet user create --referrer usr_nope
	[ "$status" -eq 2 ]
	[[ "$output" == *"not found"* ]]
	_user222_teardown
}

@test "FEAT-222 PR-2: user create --referrer records the link" {
	_user222_setup
	local parent
	parent=$("$LIGHTNING_BIN" wallet user create --label parent | awk '/created/{print $4}')
	"$LIGHTNING_BIN" wallet user create --label child --referrer "$parent" >/dev/null
	local got
	got=$(sqlite3 "$BATS_DB" "SELECT referrer_user FROM wallet_users WHERE label='child';")
	[ "$got" = "$parent" ]
	_user222_teardown
}

@test "FEAT-222 PR-2: user list shows owned-account counts" {
	_user222_setup
	local uid
	uid=$("$LIGHTNING_BIN" wallet user create --label op | awk '/created/{print $4}')
	"$LIGHTNING_BIN" account create acct1 >/dev/null 2>&1
	sqlite3 "$BATS_DB" "UPDATE accounts SET owner_user='$uid' WHERE name='acct1';"
	run "$LIGHTNING_BIN" wallet user list
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "id	label	accounts	created_at" ]]
	[[ "$output" == *"$uid"*"op"*"1"* ]]
	_user222_teardown
}

@test "FEAT-222 PR-2: user show lists owned accounts" {
	_user222_setup
	local uid
	uid=$("$LIGHTNING_BIN" wallet user create --label op | awk '/created/{print $4}')
	"$LIGHTNING_BIN" account create acct1 >/dev/null 2>&1
	sqlite3 "$BATS_DB" "UPDATE accounts SET owner_user='$uid' WHERE name='acct1';"
	run "$LIGHTNING_BIN" wallet user show "$uid"
	[ "$status" -eq 0 ]
	[[ "$output" == *"id:           $uid"* ]]
	[[ "$output" == *"referrer:     (none)"* ]]
	[[ "$output" == *"acct1"* ]]
	_user222_teardown
}

@test "FEAT-222 PR-2: user show on unknown id errors" {
	_user222_setup
	run "$LIGHTNING_BIN" wallet user show usr_nope
	[ "$status" -eq 2 ]
	[[ "$output" == *"no such user"* ]]
	_user222_teardown
}

@test "FEAT-222 PR-2: user delete orphans owned accounts (does not delete them)" {
	_user222_setup
	local uid
	uid=$("$LIGHTNING_BIN" wallet user create --label op | awk '/created/{print $4}')
	"$LIGHTNING_BIN" account create acct1 >/dev/null 2>&1
	sqlite3 "$BATS_DB" "UPDATE accounts SET owner_user='$uid' WHERE name='acct1';"
	"$LIGHTNING_BIN" wallet user delete "$uid"
	# Account survives; owner cleared.
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM accounts WHERE name='acct1';")" = "1" ]
	[ "$(sqlite3 "$BATS_DB" "SELECT COALESCE(owner_user,'NULL') FROM accounts WHERE name='acct1';")" = "NULL" ]
	# User gone.
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM wallet_users WHERE id='$uid';")" = "0" ]
	_user222_teardown
}

@test "FEAT-222 PR-2: user delete on unknown id errors" {
	_user222_setup
	run "$LIGHTNING_BIN" wallet user delete usr_nope
	[ "$status" -eq 2 ]
	_user222_teardown
}

@test "FEAT-222 PR-2: user with no subcommand prints usage" {
	run "$LIGHTNING_BIN" wallet user
	[ "$status" -eq 1 ]
	[[ "$output" == *"usage: lightning wallet-user"* ]]
}

@test "FEAT-222 PR-2: top-level help lists the user verb" {
	run "$LIGHTNING_BIN" help
	[[ "$output" == *"wallet"* ]]
}

@test "FEAT-222 PR-2: account migration is idempotent for the new columns" {
	_user222_setup
	# Run an account verb twice → no error, columns stable.
	"$LIGHTNING_BIN" account list >/dev/null
	"$LIGHTNING_BIN" account list >/dev/null
	[ "$(sqlite3 "$BATS_DB" "PRAGMA table_info(accounts);" | awk -F'|' '$2=="owner_user"' | wc -l | tr -d ' ')" = "1" ]
	_user222_teardown
}

@test "FEAT-222 PR-2: spec file present + notes the wallet_users rename" {
	for cand in \
		"$BATS_TEST_DIRNAME/../../issues/feature/222-user-layer.md" \
		"$BATS_TEST_DIRNAME/../../issues/feature/done/222-user-layer.md"; do
		[ -f "$cand" ] && f="$cand" && break
	done
	[ -n "$f" ]
	grep -q "^id: FEAT-222" "$f"
	grep -q "wallet_users" "$f"
}

@test "FEAT-222 PR-3: schema declares user_passkeys + auth_challenges_user" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/schema.sql"
	grep -q "CREATE TABLE IF NOT EXISTS user_passkeys" "$f"
	grep -q "CREATE TABLE IF NOT EXISTS auth_challenges_user" "$f"
}

@test "FEAT-222 PR-3: migration creates the two passkey tables (idempotent)" {
	_acct222pr3_setup
	tables=$(sqlite3 "$BATS_DB" "SELECT name FROM sqlite_master WHERE type='table';")
	[[ "$tables" == *"user_passkeys"* ]]
	[[ "$tables" == *"auth_challenges_user"* ]]
	# Re-trigger the migration; must not error or duplicate.
	"$LIGHTNING_BIN" account list >/dev/null
	n_pk=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='user_passkeys';")
	n_ch=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='auth_challenges_user';")
	[ "$n_pk" = "1" ]
	[ "$n_ch" = "1" ]
}

@test "FEAT-222 PR-3: _webauthn-verify list with no passkeys returns just the header" {
	_acct222pr3_setup
	"$LIGHTNING_BIN" wallet user create --label operator >/dev/null
	uid=$(sqlite3 "$BATS_DB" "SELECT id FROM wallet_users LIMIT 1;")
	run "$LIGHTNING_BIN" _webauthn-verify list --user-id "$uid"
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "credential_id"$'\t'"label"$'\t'"created_at"$'\t'"last_used_at"$'\t'"sign_count" ]]
	[ "${#lines[@]}" -eq 1 ]
}

@test "FEAT-222 PR-3: _webauthn-verify list + revoke roundtrip on a manually-inserted passkey" {
	_acct222pr3_setup
	"$LIGHTNING_BIN" wallet user create --label operator >/dev/null
	uid=$(sqlite3 "$BATS_DB" "SELECT id FROM wallet_users LIMIT 1;")
	sqlite3 "$BATS_DB" "INSERT INTO user_passkeys(user, credential_id, public_key, sign_count, label, created_at) \
		VALUES('$uid', 'credabc', X'00', 0, 'phone', strftime('%s','now'));"

	run "$LIGHTNING_BIN" _webauthn-verify list --user-id "$uid"
	[ "$status" -eq 0 ]
	[[ "$output" == *"credabc"* ]]
	[[ "$output" == *"phone"* ]]

	run "$LIGHTNING_BIN" _webauthn-verify revoke --credential-id credabc --user-id "$uid"
	[ "$status" -eq 0 ]

	run "$LIGHTNING_BIN" _webauthn-verify list --user-id "$uid"
	[ "${#lines[@]}" -eq 1 ]
}

@test "FEAT-222 PR-3: _webauthn-verify revoke of a nonexistent credential exits 4" {
	_acct222pr3_setup
	run "$LIGHTNING_BIN" _webauthn-verify revoke --credential-id deadbeef
	[ "$status" -eq 4 ]
}

@test "FEAT-222 PR-3: _webauthn-verify register-begin mints + stores a challenge" {
	_acct222pr3_setup
	run "$LIGHTNING_BIN" _webauthn-verify register-begin \
		--user-id usr_alice --rp-id example.com --rp-name "Example"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"challenge"'* ]]
	[[ "$output" == *'"rp"'* ]]
	# Challenge persisted with purpose=register and user=NULL.
	n=$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM auth_challenges_user WHERE purpose='register' AND user IS NULL;")
	[ "$n" = "1" ]
}

@test "FEAT-222 PR-3: _session-token mint -> verify roundtrip" {
	_stub_secret
	run "$LIGHTNING_BIN" _session-token mint --user-id usr_alice --ttl 60
	[ "$status" -eq 0 ]
	[[ "$output" == sess_*.* ]]
	tok="$output"
	run "$LIGHTNING_BIN" _session-token verify --token "$tok"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"user_id"'* ]]
	[[ "$output" == *"usr_alice"* ]]
}

@test "FEAT-222 PR-3: _session-token verify of a tampered token fails (exit 6)" {
	_stub_secret
	"$LIGHTNING_BIN" _session-token mint --user-id usr_alice >/dev/null
	run "$LIGHTNING_BIN" _session-token verify --token "sess_BAD.PAYLOAD"
	[ "$status" -eq 6 ]
}

@test "FEAT-222 PR-3: _session-token refresh issues a fresh signed token" {
	_stub_secret
	run "$LIGHTNING_BIN" _session-token mint --user-id usr_alice --ttl 60
	tok="$output"
	run "$LIGHTNING_BIN" _session-token refresh --token "$tok" --ttl 120
	[ "$status" -eq 0 ]
	[[ "$output" == sess_*.* ]]
	# Refreshed token verifies cleanly.
	run "$LIGHTNING_BIN" _session-token verify --token "$output"
	[ "$status" -eq 0 ]
	[[ "$output" == *"usr_alice"* ]]
}
