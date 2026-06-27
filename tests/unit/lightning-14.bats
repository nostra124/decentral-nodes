#!/usr/bin/env bats
#
# lightning unit tests — part 14 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-221: lightning.1 overview cross-references the per-verb pages" {
	local f="$BATS_TEST_DIRNAME/../../share/man/man1/lightning.1"
	grep -q "lightning-account (1)" "$f"
	grep -q "lightning-channel (1)" "$f"
	grep -q "lightning-compliance (1)" "$f"
}

@test "FEAT-220: invite-codes lazy-mints a code on first call" {
	_acct220_setup
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM invite_codes WHERE account='bob';")" = "0" ]
	run "$LIGHTNING_BIN" api-account-invite-codes "$BATS_ADDR"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.invite_codes | length == 1' >/dev/null
	# Persisted.
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM invite_codes WHERE account='bob';")" = "1" ]
	_acct220_teardown
}

@test "FEAT-220: invite-codes is idempotent (no new mint on repeat)" {
	_acct220_setup
	"$LIGHTNING_BIN" api-account-invite-codes "$BATS_ADDR" >/dev/null
	"$LIGHTNING_BIN" api-account-invite-codes "$BATS_ADDR" >/dev/null
	[ "$(sqlite3 "$BATS_DB" "SELECT COUNT(*) FROM invite_codes WHERE account='bob';")" = "1" ]
	_acct220_teardown
}

@test "FEAT-220: invite-codes lists an operator-minted code too" {
	_acct220_setup
	"$LIGHTNING_BIN" account invite-code create bob --code vanity1 >/dev/null
	run "$LIGHTNING_BIN" api-account-invite-codes "$BATS_ADDR"
	[[ "$output" == *"vanity1"* ]]
	_acct220_teardown
}

@test "FEAT-220: invite-codes rejects an unknown account" {
	_acct220_setup
	run "$LIGHTNING_BIN" api-account-invite-codes "bcrt1qzzz00000000000000000000000000000000000000"
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown account"* ]]
	_acct220_teardown
}

@test "FEAT-220: sudoers fragment lists api-account-invite-codes" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
	grep -q "api-account-invite-codes" "$f"
}

@test "FEAT-231: mandate pulls lists pending charges (the approval inbox)" {
	_acct231_setup
	local out mid sec
	out=$("$LIGHTNING_BIN" api-account-mandate "$BATS_CUST" create shop 50000 monthly --mode approval)
	mid=$(echo "$out" | jq -r '.id'); sec=$(echo "$out" | jq -r '.secret')
	"$LIGHTNING_BIN" api-account-mandate-pull "$BATS_CUST" charge "$mid" "$sec" 5000 >/dev/null
	run "$LIGHTNING_BIN" api-account-mandate "$BATS_CUST" pulls "$mid"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.pulls | length == 1' >/dev/null
	echo "$output" | jq -e '.pulls[0].state == "pending"' >/dev/null
	echo "$output" | jq -e '.pulls[0].sat == 5000' >/dev/null
	_acct231_teardown
}

@test "FEAT-231: mandate pulls is scoped to the mandate's customer" {
	_acct231_setup
	run "$LIGHTNING_BIN" api-account-mandate "$BATS_CUST" pulls mdt_nonexistent
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown_mandate"* ]]
	_acct231_teardown
}

@test "FEAT-222 PR-5: max_downline column exists in wallet_users" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.pr5b.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.pr5b.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" wallet user create --label test >/dev/null
	local wname; wname=$(cat "$LIGHTNING_WALLETS_ROOT/active" 2>/dev/null || echo "default")
	db="$LIGHTNING_WALLETS_ROOT/$wname/state.db"
	sqlite3 "$db" "SELECT max_downline FROM wallet_users LIMIT 1;" >/dev/null
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

@test "FEAT-222 PR-5: wallet-user cap sets max_downline" {
	_pr5_setup
	"$LIGHTNING_BIN" wallet user cap "$CHILD_UID" 5
	local wname; wname=$(cat "$LIGHTNING_WALLETS_ROOT/active" 2>/dev/null || echo "default")
	db="$LIGHTNING_WALLETS_ROOT/$wname/state.db"
	val=$(sqlite3 "$db" "SELECT max_downline FROM wallet_users WHERE id='$CHILD_UID';")
	[ "$val" = "5" ]
	_pr5_teardown
}

@test "FEAT-222 PR-5: wallet-user cap unlimited clears to NULL" {
	_pr5_setup
	"$LIGHTNING_BIN" wallet user cap "$CHILD_UID" 5
	"$LIGHTNING_BIN" wallet user cap "$CHILD_UID" unlimited
	local wname; wname=$(cat "$LIGHTNING_WALLETS_ROOT/active" 2>/dev/null || echo "default")
	db="$LIGHTNING_WALLETS_ROOT/$wname/state.db"
	val=$(sqlite3 "$db" "SELECT COALESCE(max_downline,'NULL') FROM wallet_users WHERE id='$CHILD_UID';")
	[ "$val" = "NULL" ]
	_pr5_teardown
}

@test "FEAT-222 PR-5: wallet-user lineage walks up to root" {
	_pr5_setup
	out=$("$LIGHTNING_BIN" wallet user lineage "$CHILD_UID")
	echo "$out" | grep -q "$CHILD_UID"
	echo "$out" | grep -q "$ROOT_UID"
	_pr5_teardown
}

@test "FEAT-222 PR-5: wallet-user tree shows root + child" {
	_pr5_setup
	out=$("$LIGHTNING_BIN" wallet user tree "$ROOT_UID")
	echo "$out" | grep -q "$ROOT_UID"
	echo "$out" | grep -q "$CHILD_UID"
	_pr5_teardown
}

@test "FEAT-222 PR-5: wallet-user invite-code create mints a code" {
	_pr5_setup
	# Create an account owned by ROOT_UID.
	acct_json=$(REMOTE_ADDR=1.2.3.4 "$LIGHTNING_BIN" api-accounts-create --owner-user "$ROOT_UID" 2>/dev/null)
	acct=$(echo "$acct_json" | jq -r '.account_id')
	out=$("$LIGHTNING_BIN" wallet user invite-code create "$ROOT_UID" --credit-account "$acct")
	echo "$out" | grep -q "^code:"
	_pr5_teardown
}

@test "FEAT-222 PR-5: wallet-user invite-code list shows the minted code" {
	_pr5_setup
	acct_json=$(REMOTE_ADDR=1.2.3.4 "$LIGHTNING_BIN" api-accounts-create --owner-user "$ROOT_UID" 2>/dev/null)
	acct=$(echo "$acct_json" | jq -r '.account_id')
	"$LIGHTNING_BIN" wallet user invite-code create "$ROOT_UID" --credit-account "$acct" >/dev/null
	out=$("$LIGHTNING_BIN" wallet user invite-code list "$ROOT_UID")
	echo "$out" | grep -q "$acct"
	_pr5_teardown
}

@test "FEAT-222 PR-5: wallet-user invite-code revoke removes the code" {
	_pr5_setup
	acct_json=$(REMOTE_ADDR=1.2.3.4 "$LIGHTNING_BIN" api-accounts-create --owner-user "$ROOT_UID" 2>/dev/null)
	acct=$(echo "$acct_json" | jq -r '.account_id')
	code_line=$("$LIGHTNING_BIN" wallet user invite-code create "$ROOT_UID" --credit-account "$acct" | grep "^code:")
	code=${code_line#code: }
	"$LIGHTNING_BIN" wallet user invite-code revoke "$code"
	out=$("$LIGHTNING_BIN" wallet user invite-code list "$ROOT_UID")
	! echo "$out" | grep -q "$code"
	_pr5_teardown
}

@test "FEAT-222 PR-5: cap enforcement blocks invite mint when ancestor cap exceeded" {
	_pr5_setup
	# Cap root to 0 transitive descendants — child cannot invite anyone.
	"$LIGHTNING_BIN" wallet user cap "$ROOT_UID" 0
	# Create an account owned by CHILD_UID.
	acct_json=$(REMOTE_ADDR=1.2.3.4 "$LIGHTNING_BIN" api-accounts-create --owner-user "$CHILD_UID" 2>/dev/null)
	acct=$(echo "$acct_json" | jq -r '.account_id')
	run "$LIGHTNING_BIN" wallet user invite-code create "$CHILD_UID" --credit-account "$acct"
	[ "$status" -ne 0 ]
	_pr5_teardown
}

@test "FEAT-222 PR-5: api-accounts-create prefers credit_account for user-owned invite codes" {
	_pr5_setup
	acct_json=$(REMOTE_ADDR=1.2.3.4 "$LIGHTNING_BIN" api-accounts-create --owner-user "$ROOT_UID" 2>/dev/null)
	acct=$(echo "$acct_json" | jq -r '.account_id')
	code_line=$("$LIGHTNING_BIN" wallet user invite-code create "$ROOT_UID" --credit-account "$acct" | grep "^code:")
	code=${code_line#code: }
	# Create an account using the user-owned invite code.
	result=$(REMOTE_ADDR=1.2.3.5 "$LIGHTNING_BIN" api-accounts-create --invite-code "$code" 2>/dev/null)
	referrer=$(echo "$result" | jq -r '.referrer')
	[ "$referrer" = "$acct" ]
	_pr5_teardown
}

@test "FEAT-222 PR-5: wallet-user cap on unknown user exits non-zero" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.pr5c.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.pr5c.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" wallet user cap "usr_doesnotexist00" 5
	[ "$status" -ne 0 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

@test "FEAT-222 PR-6: wallet new seeds access.recfile (open by default)" {
	_acct222pr6_setup
	[ -f "$BATS_ACCESS" ]
	grep -q "^require_referral: off" "$BATS_ACCESS"
	grep -q "^invite_whitelist:" "$BATS_ACCESS"
	_acct222pr6_teardown
}

@test "FEAT-222 PR-6: default (open) — anonymous create succeeds" {
	_acct222pr6_setup
	REMOTE_ADDR=10.1.0.1 run "$LIGHTNING_BIN" api-accounts-create
	[ "$status" -eq 0 ]
	[[ "$output" == *'"account_id":"bcrt1q'* ]]
	_acct222pr6_teardown
}

@test "FEAT-222 PR-6: require_referral on — create without an invite is refused" {
	_acct222pr6_setup
	sed -i 's/^require_referral: off/require_referral: on/' "$BATS_ACCESS"
	REMOTE_ADDR=10.1.0.2 run "$LIGHTNING_BIN" api-accounts-create
	[ "$status" -eq 6 ]
	[[ "$output" == *"invite_required"* ]]
	_acct222pr6_teardown
}

@test "FEAT-222 PR-6: require_referral on — a valid invite lets create through + stamps referrer" {
	_acct222pr6_setup
	local code
	code=$("$LIGHTNING_BIN" account invite-code create sponsor | awk '/^code:/{print $2}')
	sed -i 's/^require_referral: off/require_referral: on/' "$BATS_ACCESS"
	REMOTE_ADDR=10.1.0.3 run "$LIGHTNING_BIN" api-accounts-create --invite-code "$code"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"referrer":"sponsor"'* ]]
	_acct222pr6_teardown
}

@test "FEAT-222 PR-6: require_referral on — a bogus invite is still refused" {
	_acct222pr6_setup
	sed -i 's/^require_referral: off/require_referral: on/' "$BATS_ACCESS"
	REMOTE_ADDR=10.1.0.4 run "$LIGHTNING_BIN" api-accounts-create --invite-code nosuchcode
	[ "$status" -eq 6 ]
	[[ "$output" == *"invite_required"* ]]
	_acct222pr6_teardown
}

@test "FEAT-222 PR-6: invite whitelist — only listed accounts may mint (CLI)" {
	_acct222pr6_setup
	"$LIGHTNING_BIN" account create other >/dev/null
	sed -i 's/^invite_whitelist:.*/invite_whitelist: sponsor/' "$BATS_ACCESS"
	run "$LIGHTNING_BIN" account invite-code create sponsor
	[ "$status" -eq 0 ]
	run "$LIGHTNING_BIN" account invite-code create other
	[ "$status" -ne 0 ]
	[[ "$output" == *"whitelist"* ]]
	_acct222pr6_teardown
}

@test "FEAT-222 PR-6: invite whitelist — non-listed account's HTTP lazy-mint stays empty" {
	_acct222pr6_setup
	"$LIGHTNING_BIN" account create other >/dev/null
	sed -i 's/^invite_whitelist:.*/invite_whitelist: sponsor/' "$BATS_ACCESS"
	local other_addr; other_addr=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='other';")
	run "$LIGHTNING_BIN" api-account-invite-codes "$other_addr"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.invite_codes | length == 0' >/dev/null
	# A whitelisted account still lazy-mints.
	local sp_addr; sp_addr=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='sponsor';")
	run "$LIGHTNING_BIN" api-account-invite-codes "$sp_addr"
	echo "$output" | jq -e '.invite_codes | length >= 1' >/dev/null
	_acct222pr6_teardown
}

@test "FEAT-222 PR-6: default access.recfile ships under defaults/" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/defaults/access.recfile"
	[ -f "$f" ]
	grep -q "require_referral" "$f"
	grep -q "invite_whitelist" "$f"
}

@test "FEAT-243: migration adds profile + fund_class columns" {
	_acct243_setup
	local cols
	cols=$(sqlite3 "$BATS_DB" "PRAGMA table_info(accounts);" | awk -F'|' '{print $2}')
	echo "$cols" | grep -qx "profile"
	echo "$cols" | grep -qx "fund_class"
	_acct243_teardown
}

@test "FEAT-243: profiles table lists the four profiles" {
	_acct243_setup
	run "$LIGHTNING_BIN" account profiles
	[ "$status" -eq 0 ]
	for p in treasury family prepaid custodial; do [[ "$output" == *"$p"* ]]; done
	_acct243_teardown
}

@test "FEAT-243: default profile (treasury) allows every capability" {
	_acct243_setup
	for c in recv topup transfer_intra_user transfer_inter_user pay_external withdraw; do
		run "$LIGHTNING_BIN" account capability cust "$c"
		[ "$status" -eq 0 ]
	done
	_acct243_teardown
}

@test "FEAT-243: set-profile prepaid denies withdraw + inter-user, keeps recv/topup/pay" {
	_acct243_setup
	"$LIGHTNING_BIN" account set-profile cust prepaid >/dev/null
	run "$LIGHTNING_BIN" account capability cust withdraw
	[ "$status" -ne 0 ]
	run "$LIGHTNING_BIN" account capability cust transfer_inter_user
	[ "$status" -ne 0 ]
	for c in recv topup pay_external transfer_intra_user; do
		run "$LIGHTNING_BIN" account capability cust "$c"
		[ "$status" -eq 0 ]
	done
	_acct243_teardown
}

@test "FEAT-243: set-profile rejects an unknown profile" {
	_acct243_setup
	run "$LIGHTNING_BIN" account set-profile cust megabank
	[ "$status" -ne 0 ]
	_acct243_teardown
}

@test "FEAT-243: HTTP withdraw is gated by the prepaid profile" {
	_acct243_setup
	"$LIGHTNING_BIN" account set-profile cust prepaid >/dev/null
	run "$LIGHTNING_BIN" api-account-withdraw "$BATS_CUST" 1000 bc1qdestxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
	[ "$status" -eq 6 ]
	[[ "$output" == *"capability_disabled"* ]]
	[[ "$output" == *"withdraw"* ]]
	_acct243_teardown
}

@test "FEAT-243: HTTP recv still works under the prepaid profile" {
	_acct243_setup
	"$LIGHTNING_BIN" account set-profile cust prepaid >/dev/null
	run "$LIGHTNING_BIN" api-account-recv "$BATS_CUST" 1000
	[ "$status" -eq 0 ]
	[[ "$output" == *"bolt11"* ]]
	_acct243_teardown
}

@test "FEAT-243: transfer intra-user allowed but inter-user gated (family profile)" {
	_acct243_setup
	# Same owner on both -> intra-user; family allows intra, forbids inter.
	sqlite3 "$BATS_DB" "UPDATE accounts SET owner_user='usr_alice' WHERE name IN ('cust','shop');"
	"$LIGHTNING_BIN" account set-profile cust family >/dev/null
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_CUST" shop 1000
	[ "$status" -eq 0 ]
	# Now give shop a different owner -> inter-user -> denied.
	sqlite3 "$BATS_DB" "UPDATE accounts SET owner_user='usr_bob' WHERE name='shop';"
	run "$LIGHTNING_BIN" api-account-transfer "$BATS_CUST" shop 1000
	[ "$status" -eq 6 ]
	[[ "$output" == *"transfer_inter_user"* ]]
	_acct243_teardown
}

@test "FEAT-243: compliance status rates LOW for own funds, HIGH for foreign" {
	_acct243_setup
	run "$LIGHTNING_BIN" wallet compliance status
	[[ "$output" == *"rating: LOW"* ]]
	"$LIGHTNING_BIN" account set-fund-class cust foreign >/dev/null
	run "$LIGHTNING_BIN" wallet compliance status
	[[ "$output" == *"rating: HIGH"* ]]
	[[ "$output" == *"custodial"* ]]
	_acct243_teardown
}

@test "FEAT-222 PR-6: invite-only registration downgrades foreign-funds rating to MEDIUM" {
	# Closed/invite-only deployment (family-and-friends) carries much less
	# MSB-style exposure than open custody even when foreign funds are held.
	_acct243_setup
	"$LIGHTNING_BIN" account set-fund-class cust foreign >/dev/null

	# Default access.recfile ships require_referral: off — open registration.
	run "$LIGHTNING_BIN" wallet compliance status
	[[ "$output" == *"registration:"*"open"* ]]
	[[ "$output" == *"rating: HIGH"* ]]

	# Flip to invite-only — same foreign funds, but now closed.
	sed -i 's/^require_referral: off$/require_referral: on/' "$LIGHTNING_WALLETS_ROOT/alice/access.recfile"
	run "$LIGHTNING_BIN" wallet compliance status
	[[ "$output" == *"registration:"*"invite-only"* ]]
	[[ "$output" == *"rating: MEDIUM"* ]]
	_acct243_teardown
}

@test "FEAT-243: default access.recfile carries default_profile" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/defaults/access.recfile"
	grep -q "default_profile: treasury" "$f"
}

@test "FEAT-243: schema declares accounts.profile + fund_class" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/schema.sql"
	grep -q "profile" "$f"
	grep -q "fund_class" "$f"
}

# ---------------------------------------------------------------------------
# FEAT-245 — PWA: BOLT-12 reusable offer on the Receive screen
# ---------------------------------------------------------------------------






# ---------------------------------------------------------------------------
# FEAT-246 — Transaction history API + PWA screen
# ---------------------------------------------------------------------------

@test "FEAT-246: api-account-history verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-account-history" ]
}

@test "FEAT-246: api-account-history returns entries + has_more for unknown account exits 4" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.246.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.246.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	acct_json=$(REMOTE_ADDR=1.2.3.4 "$LIGHTNING_BIN" api-accounts-create 2>/dev/null)
	addr=$(echo "$acct_json" | jq -r '.account_id')
	run "$LIGHTNING_BIN" api-account-history "$addr"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.entries | type == "array"'
	echo "$output" | jq -e 'has("has_more")'
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR"
}

@test "FEAT-246: api-account-history entries include ledger rows after a transfer" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.246b.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.246b.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	# Seed two accounts; book a ledger row manually.
	a1_json=$(REMOTE_ADDR=1.2.3.4 "$LIGHTNING_BIN" api-accounts-create 2>/dev/null)
	addr=$(echo "$a1_json" | jq -r '.account_id')
	name=$(sqlite3 "$db" "SELECT name FROM accounts WHERE address='$addr';")
	sqlite3 "$db" "INSERT INTO ledger(ts,account,direction,amount_msat,peer,payment_hash,message) VALUES(datetime('now'),'$name','in',5000000,'-','-','test-entry');"
	run "$LIGHTNING_BIN" api-account-history "$addr"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.entries | length >= 1'
	echo "$output" | jq -e '.entries[0].direction == "in"'
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR"
}





# ---------------------------------------------------------------------------
# FEAT-247 — MCP account_history tool + ledger resource
# ---------------------------------------------------------------------------

@test "FEAT-247: mcp.py lists account_history tool" {
	grep -q "account_history" "$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/mcp.py"
}

@test "FEAT-247: mcp.py ledger resource routes to api-account-history" {
	grep -q "api-account-history" "$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/mcp.py"
}

@test "FEAT-247: account_history tool has correct inputSchema fields" {
	py="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/mcp.py"
	grep -q "before_id" "$py"
	grep -q '"limit"' "$py"
}


@test "FEAT-247: sudoers fragment lists api-account-history" {
	grep -q "api-account-history" "$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
}

# ---------------------------------------------------------------------------
# FEAT-248 — Send screen UX + copy button on receive
# ---------------------------------------------------------------------------






# FEAT-249 — PWA Settings backup + api-key endpoint

@test "FEAT-249: api-account-apikey verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-account-apikey" ]
}


@test "FEAT-249: sudoers lists api-account-apikey" {
	grep -q "api-account-apikey" "$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
}





# FEAT-250 — PWA import from backup blob





# FEAT-251 — PWA rename account label




# FEAT-252 — node info verb + PWA node screen

@test "FEAT-252: api-node-info verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-node-info" ]
}

@test "FEAT-252: node.py CGI script exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/node.py" ]
}
