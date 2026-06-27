#!/usr/bin/env bats
#
# lightning unit tests — part 8 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-211: account withdraw errors clearly when boltzcli isn't installed" {
	_acct_setup
	# boltzcli isn't on the test PATH — the verb should report it.
	run "$LIGHTNING_BIN" account withdraw rent 5000 bc1qtestaddressxxxxxxxxxxxxxxxxxxxxxxxxxx
	[ "$status" -eq 127 ]
	[[ "$output" == *"boltzcli not installed"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account withdraw runs boltzcli reverse swap when installed" {
	_acct_setup
	# Stub boltzcli to succeed.
	cat > "$BIN_SHIM/boltzcli" <<'EOF2'
#!/bin/sh
echo "boltzcli $*" >> "$BIN_SHIM/boltzcli.calls"
echo '{"id":"swap-123","status":"created"}'
exit 0
EOF2
	chmod +x "$BIN_SHIM/boltzcli"
	export BIN_SHIM
	run "$LIGHTNING_BIN" account withdraw rent 5000 bc1qrecipientxxxxxxxxxxxxxxxxxxxxxxxxxx
	[ "$status" -eq 0 ]
	grep -q "createreverseswap" "$BIN_SHIM/boltzcli.calls"
	grep -q "\\--address bc1qrecipient" "$BIN_SHIM/boltzcli.calls"
	[[ "$output" == *"ok"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account pay dispatches lnbc* to invoice pay" {
	_acct_setup
	run "$LIGHTNING_BIN" account pay rent lnbcrt10n1pmocktest
	[ "$status" -eq 0 ]
	[[ "$output" == *"ok"* ]] || [[ "$output" == *"payment_hash"* ]] || [[ "$output" == *"complete"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account pay dispatches lno* to offer pay" {
	_acct_setup
	run "$LIGHTNING_BIN" account pay rent lno1pgmocktest
	[ "$status" -eq 0 ]
	# offer pay fetches an invoice then pays — output includes payment status.
	[[ "$output" == *"complete"* ]] || [[ "$output" == *"payment_hash"* ]] || [[ "$output" == *"ok"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account pay rejects 02xx node-pubkey without --sat" {
	_acct_setup
	# 66-char hex pubkey starting with 02.
	run "$LIGHTNING_BIN" account pay rent 020000000000000000000000000000000000000000000000000000000000000002
	[ "$status" -ne 0 ]
	[[ "$output" == *"keysend needs --sat"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account pay accepts 02xx node-pubkey + --sat (keysend)" {
	_acct_setup
	run "$LIGHTNING_BIN" account pay rent \
		020000000000000000000000000000000000000000000000000000000000000002 --sat 1000
	[ "$status" -eq 0 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account pay rejects unknown payment-string shape" {
	_acct_setup
	run "$LIGHTNING_BIN" account pay rent garbage-string-no-prefix
	[ "$status" -ne 0 ]
	[[ "$output" == *"couldn't identify payment-string type"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account pay rejects 02xx that isn't 66 chars" {
	_acct_setup
	run "$LIGHTNING_BIN" account pay rent 02deadbeef --sat 100
	[ "$status" -ne 0 ]
	[[ "$output" == *"isn't 66 chars"* ]] || [[ "$output" == *"couldn't identify"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account receive defaults to BOLT-11 + QR" {
	_acct_setup
	run "$LIGHTNING_BIN" account receive rent 7500 --desc "tip"
	[ "$status" -eq 0 ]
	[[ "$output" == *"lnbcrt"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account receive --reusable produces a BOLT-12 offer + QR" {
	_acct_setup
	run "$LIGHTNING_BIN" account receive rent 5000 --reusable --desc "monthly subscription"
	[ "$status" -eq 0 ]
	[[ "$output" == *"lno1"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account receive --reusable binds the offer to the account" {
	_acct_setup
	run "$LIGHTNING_BIN" account receive rent 5000 --reusable
	[ "$status" -eq 0 ]
	# offer create --account writes a binding recfile under wallet/offers/.
	[ -d "$LIGHTNING_WALLETS_ROOT/alice/offers" ]
	grep -q "^account: rent" "$LIGHTNING_WALLETS_ROOT/alice/offers/"*.recfile
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: offer create --account writes the binding (unit test for the gap-filler)" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create club "" >/dev/null
	run "$LIGHTNING_BIN" req offer create 1000 "test offer" --account club
	[ "$status" -eq 0 ]
	[ -d "$LIGHTNING_WALLETS_ROOT/alice/offers" ]
	grep -q "^account: club"  "$LIGHTNING_WALLETS_ROOT/alice/offers/"*.recfile
	grep -q "^offer_id:"      "$LIGHTNING_WALLETS_ROOT/alice/offers/"*.recfile
	grep -q "^bolt12: lno1"   "$LIGHTNING_WALLETS_ROOT/alice/offers/"*.recfile
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: spec file exists with the expected id" {
	# Shipped together with the implementation in this PR — same
	# cadence as FEAT-198 / FEAT-205 / FEAT-207.
	f="$BATS_TEST_DIRNAME/../../issues/feature/done/211-account-centric-verbs.md"
	[ -f "$f" ]
	grep -q "^id: FEAT-211" "$f"
	grep -q "^status: shipped" "$f"
	grep -q "topup" "$f"
	grep -q "withdraw" "$f"
	grep -q "receive" "$f"
}

@test "FEAT-212 PR-1: account create mints a bitcoin address" {
	_acct212_setup
	run "$LIGHTNING_BIN" account create rent
	[ "$status" -eq 0 ]
	[[ "$output" == *"created rent"* ]]
	[[ "$output" == *"address:"* ]]
	[[ "$output" == *"bcrt1qtestaddress"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account create mints an lt_ prefixed API key" {
	_acct212_setup
	run "$LIGHTNING_BIN" account create rent
	[ "$status" -eq 0 ]
	[[ "$output" == *"api_key:"* ]]
	[[ "$output" == *"lt_"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account create persists the address into the schema" {
	_acct212_setup
	run "$LIGHTNING_BIN" account create rent
	[ "$status" -eq 0 ]
	local db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	local stored
	stored=$(sqlite3 "$db" "SELECT address FROM accounts WHERE name = 'rent';")
	[[ "$stored" == bcrt1qtestaddress* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account create with LIGHTNING_ACCOUNT_NO_MINT=1 skips minting" {
	_acct212_setup
	LIGHTNING_ACCOUNT_NO_MINT=1 run "$LIGHTNING_BIN" account create legacy
	[ "$status" -eq 0 ]
	[[ "$output" != *"address:"* ]]
	[[ "$output" != *"api_key:"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account create writes nickname recfile" {
	_acct212_setup
	"$LIGHTNING_BIN" account create rent >/dev/null
	[ -f "$LIGHTNING_WALLETS_ROOT/alice/accounts/nicknames.recfile" ]
	grep -q "^nickname: rent" "$LIGHTNING_WALLETS_ROOT/alice/accounts/nicknames.recfile"
	grep -q "^address: bcrt1qtestaddress" "$LIGHTNING_WALLETS_ROOT/alice/accounts/nicknames.recfile"
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account create issues unique addresses across accounts" {
	_acct212_setup
	"$LIGHTNING_BIN" account create rent >/dev/null
	"$LIGHTNING_BIN" account create club >/dev/null
	local db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	local n_distinct
	n_distinct=$(sqlite3 "$db" "SELECT COUNT(DISTINCT address) FROM accounts WHERE name IN ('rent','club');")
	[ "$n_distinct" = "2" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account show resolves by legacy name" {
	_acct212_setup
	"$LIGHTNING_BIN" account create rent >/dev/null
	run "$LIGHTNING_BIN" account show rent
	[ "$status" -eq 0 ]
	[[ "$output" == *"name:"*"rent"* ]]
	[[ "$output" == *"address:"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account show resolves by bitcoin-address handle" {
	_acct212_setup
	"$LIGHTNING_BIN" account create rent >/dev/null
	local db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	local addr
	addr=$(sqlite3 "$db" "SELECT address FROM accounts WHERE name = 'rent';")
	run "$LIGHTNING_BIN" account show "$addr"
	[ "$status" -eq 0 ]
	[[ "$output" == *"name:"*"rent"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account close stamps closed_at" {
	_acct212_setup
	"$LIGHTNING_BIN" account create rent >/dev/null
	run "$LIGHTNING_BIN" account close rent
	[ "$status" -eq 0 ]
	[[ "$output" == *"closed rent"* ]]
	local db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	local closed_at
	closed_at=$(sqlite3 "$db" "SELECT closed_at FROM accounts WHERE name = 'rent';")
	[ -n "$closed_at" ]
	[ "$closed_at" != "0" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account close refuses the unassigned (-) account" {
	_acct212_setup
	run "$LIGHTNING_BIN" account close -
	[ "$status" -eq 2 ]
	[[ "$output" == *"cannot close"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account close on unknown handle errors clearly" {
	_acct212_setup
	run "$LIGHTNING_BIN" account close nosuchaccount
	[ "$status" -eq 2 ]
	[[ "$output" == *"no such account"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account nickname add stores the mapping" {
	_acct212_setup
	"$LIGHTNING_BIN" account create rent >/dev/null
	run "$LIGHTNING_BIN" account nickname add bcrt1qtestaddress000000000000000000000099xxxx my-alias
	[ "$status" -eq 0 ]
	[[ "$output" == *"my-alias -> bcrt1q"* ]]
	grep -q "^nickname: my-alias" "$LIGHTNING_WALLETS_ROOT/alice/accounts/nicknames.recfile"
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account nickname add rejects non-bitcoin handles" {
	_acct212_setup
	run "$LIGHTNING_BIN" account nickname add not-an-address my-alias
	[ "$status" -ne 0 ]
	[[ "$output" == *"must be a bitcoin address"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account nickname list returns TSV" {
	_acct212_setup
	"$LIGHTNING_BIN" account create rent >/dev/null
	run "$LIGHTNING_BIN" account nickname list
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "nickname	address" ]]
	[[ "$output" == *"rent"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account nickname remove drops the alias" {
	_acct212_setup
	"$LIGHTNING_BIN" account create rent >/dev/null
	"$LIGHTNING_BIN" account nickname add bcrt1qsome0000000000000000000000000000000000xxxx alias1 >/dev/null
	"$LIGHTNING_BIN" account nickname remove alias1
	! grep -q "^nickname: alias1" "$LIGHTNING_WALLETS_ROOT/alice/accounts/nicknames.recfile"
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account show resolves by operator-added nickname" {
	_acct212_setup
	"$LIGHTNING_BIN" account create rent >/dev/null
	local db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	local addr
	addr=$(sqlite3 "$db" "SELECT address FROM accounts WHERE name = 'rent';")
	"$LIGHTNING_BIN" account nickname add "$addr" cosy-corner >/dev/null
	run "$LIGHTNING_BIN" account show cosy-corner
	[ "$status" -eq 0 ]
	[[ "$output" == *"name:"*"rent"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: schema migration is idempotent + adds expected columns" {
	_acct212_setup
	local db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	# Trigger active_db twice via two distinct account commands.
	"$LIGHTNING_BIN" account list >/dev/null
	"$LIGHTNING_BIN" account list >/dev/null
	# Schema should now have the new columns.
	local cols
	cols=$(sqlite3 "$db" "PRAGMA table_info(accounts);" | awk -F'|' '{print $2}' | sort | paste -sd,)
	[[ "$cols" == *"address"* ]]
	[[ "$cols" == *"created_at"* ]]
	[[ "$cols" == *"closed_at"* ]]
	[[ "$cols" == *"last_api_call_at"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-212 PR-1: account verb's help lists close + nickname" {
	run "$LIGHTNING_BIN" account
	[ "$status" -ne 0 ]
	[[ "$output" == *"close <handle>"* ]]
	[[ "$output" == *"nickname add"* ]]
}

@test "FEAT-212 PR-1: spec file exists with the expected id" {
	# Pre-PR-5 the file lived at issues/feature/; PR-5 moved it to
	# issues/feature/done/ when the ticket completed.  Accept either.
	f=""
	for cand in \
		"$BATS_TEST_DIRNAME/../../issues/feature/212-account-centric-http-api.md" \
		"$BATS_TEST_DIRNAME/../../issues/feature/done/212-account-centric-http-api.md"; do
		[ -f "$cand" ] && f="$cand" && break
	done
	[ -n "$f" ]
	grep -q "^id: FEAT-212" "$f"
	grep -q "Bitcoin address" "$f"
	grep -q "MCP" "$f"
}

@test "FEAT-212 PR-2: api-account-balance returns JSON for known address" {
	_acct212pr2_setup
	run "$LIGHTNING_BIN" api-account-balance "$BATS_ADDR"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"balance_sat":0'* ]]
	[[ "$output" == *'"overdraft":"deny"'* ]]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-account-balance rejects non-bech32 input" {
	_acct212pr2_setup
	run "$LIGHTNING_BIN" api-account-balance "1AbCdEfGhIjKlMnOpQrStUvWxYz123"
	[ "$status" -ne 0 ]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-account-balance returns error JSON for unknown address" {
	_acct212pr2_setup
	run "$LIGHTNING_BIN" api-account-balance "bcrt1qaaa00000000000000000000000000000000000000"
	[[ "$output" == *'"error"'* ]]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-account-balance updates last_api_call_at" {
	_acct212pr2_setup
	local db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	"$LIGHTNING_BIN" api-account-balance "$BATS_ADDR" >/dev/null
	local seen
	seen=$(sqlite3 "$db" "SELECT last_api_call_at FROM accounts WHERE address = '$BATS_ADDR';")
	[ -n "$seen" ]
	[ "$seen" != "0" ]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-account-topup returns BIP-21 URI" {
	_acct212pr2_setup
	run "$LIGHTNING_BIN" api-account-topup "$BATS_ADDR"
	[ "$status" -eq 0 ]
	[[ "$output" == *"bitcoin:$BATS_ADDR"* ]]
	[[ "$output" == *'"address"'* ]]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-account-topup with sat encodes BTC amount" {
	_acct212pr2_setup
	run "$LIGHTNING_BIN" api-account-topup "$BATS_ADDR" 50000
	[ "$status" -eq 0 ]
	[[ "$output" == *"amount=0.00050000"* ]]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-account-topup rejects non-numeric sat" {
	_acct212pr2_setup
	run "$LIGHTNING_BIN" api-account-topup "$BATS_ADDR" five
	[ "$status" -ne 0 ]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-account-close stamps closed_at and emits status JSON" {
	_acct212pr2_setup
	run "$LIGHTNING_BIN" api-account-close "$BATS_ADDR"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"status":"closed"'* ]]
	[[ "$output" == *'"closed_at":'* ]]
	local db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	local c
	c=$(sqlite3 "$db" "SELECT closed_at FROM accounts WHERE address = '$BATS_ADDR';")
	[ -n "$c" ]
	[ "$c" != "0" ]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-accounts-create mints a fresh account and returns JSON" {
	_acct212pr2_setup
	REMOTE_ADDR=10.0.0.1 run "$LIGHTNING_BIN" api-accounts-create
	[ "$status" -eq 0 ]
	[[ "$output" == *'"account_id":"bcrt1q'* ]]
	[[ "$output" == *'"api_key":"lt_'* ]]
	[[ "$output" == *'"topup_uri":"bitcoin:bcrt1q'* ]]
	[[ "$output" == *'"endpoints"'* ]]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-accounts-create defaults limit_sat=100000 + overdraft=deny" {
	_acct212pr2_setup
	REMOTE_ADDR=10.0.0.2 run "$LIGHTNING_BIN" api-accounts-create
	[ "$status" -eq 0 ]
	[[ "$output" == *'"limit_sat":100000'* ]]
	[[ "$output" == *'"overdraft":"deny"'* ]]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-accounts-create rate-limit fires after threshold" {
	_acct212pr2_setup
	# Drop the limit to 1/min for this test.
	export LIGHTNING_ACCOUNT_CREATE_RATE=1
	REMOTE_ADDR=10.0.0.3 "$LIGHTNING_BIN" api-accounts-create >/dev/null
	REMOTE_ADDR=10.0.0.3 run "$LIGHTNING_BIN" api-accounts-create
	[ "$status" -eq 6 ]
	[[ "$output" == *'"rate_limited"'* ]]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-accounts-create respects per-IP isolation" {
	_acct212pr2_setup
	export LIGHTNING_ACCOUNT_CREATE_RATE=1
	REMOTE_ADDR=10.0.0.4 "$LIGHTNING_BIN" api-accounts-create >/dev/null
	REMOTE_ADDR=10.0.0.5 run "$LIGHTNING_BIN" api-accounts-create
	[ "$status" -eq 0 ]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-accounts-create accepts a hint and trims control chars" {
	_acct212pr2_setup
	REMOTE_ADDR=10.0.0.6 run "$LIGHTNING_BIN" api-accounts-create --hint "personal pocket"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"account_id":"bcrt1q'* ]]
	# Description was persisted in the DB.
	local db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	local got
	# Exclude the reserved system accounts: house (FEAT-218 fee revenue),
	# escrow (FEAT-228 holding), others (FEAT-244 reconciliation catch-all).
	got=$(sqlite3 "$db" "SELECT description FROM accounts WHERE description != '' AND name NOT IN ('-', 'house', 'escrow', 'others') LIMIT 1;")
	[ "$got" = "personal pocket" ]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-account-verify is reachable" {
	_acct212pr2_setup
	# Without a secret store available, verify returns 127 (configured
	# but not callable).  We just verify the verb's shape — no panic.
	run "$LIGHTNING_BIN" api-account-verify "$BATS_ADDR" "lt_something"
	# Either: 127 (no secret store), 1 (key mismatch), or 0 (matches).
	[ "$status" -eq 127 ] || [ "$status" -eq 1 ] || [ "$status" -eq 0 ]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-account-pay rejects non-BOLT-11 targets with 6/JSON" {
	_acct212pr2_setup
	run "$LIGHTNING_BIN" api-account-pay "$BATS_ADDR" "lnurl1abc"
	[ "$status" -eq 6 ]
	[[ "$output" == *'"target_shape_not_implemented"'* ]]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-account-withdraw rejects too-short destinations" {
	_acct212pr2_setup
	run "$LIGHTNING_BIN" api-account-withdraw "$BATS_ADDR" 5000 short
	[ "$status" -ne 0 ]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: api-account-withdraw without boltzcli returns 127/JSON" {
	_acct212pr2_setup
	# boltzcli is not in PATH inside the test sandbox — verb should
	# return its 127 error envelope rather than crashing.
	run "$LIGHTNING_BIN" api-account-withdraw "$BATS_ADDR" 5000 \
		"bc1qtestdestxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
	[ "$status" -eq 127 ]
	[[ "$output" == *'"boltzcli_not_installed"'* ]]
	_acct212pr2_teardown
}

@test "FEAT-212 PR-2: sudoers fragment lists the api-account-* verbs" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
	[ -f "$f" ]
	grep -q "api-accounts-create" "$f"
	grep -q "api-account-verify" "$f"
	grep -q "api-account-balance" "$f"
	grep -q "api-account-pay" "$f"
	grep -q "api-account-recv-reusable" "$f"
	grep -q "api-account-close" "$f"
}
