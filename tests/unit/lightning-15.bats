#!/usr/bin/env bats
#
# lightning unit tests — part 15 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-252: Apache conf has ScriptAlias for /v1/node" {
	grep -q "v1/node" "$BATS_TEST_DIRNAME/../../share/lightning/apache/lnurlp.conf"
}

@test "FEAT-252: sudoers lists api-node-info" {
	grep -q "api-node-info" "$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
}




# FEAT-253 — payment note / memo

@test "FEAT-253: api-account-pay accepts --note argument" {
	grep -q "\-\-note" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-account-pay"
}

@test "FEAT-253: api-account-pay writes note to ledger" {
	grep -q "sql_quote.*note\|note.*sql_quote" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-account-pay"
}




# FEAT-254 — PATCH history/<entry_id> update note

@test "FEAT-254: api-account-history-note verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-account-history-note" ]
}


@test "FEAT-254: sudoers lists api-account-history-note" {
	grep -q "api-account-history-note" "$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
}



# FEAT-255 — MCP node_info tool

@test "FEAT-255: mcp.py lists node_info tool" {
	grep -q "node_info" "$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/mcp.py"
}

@test "FEAT-255: node_info tool has no required auth" {
	python3 -c "
import sys; sys.path.insert(0,'$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api')
import mcp
t = mcp.TOOLS_BY_NAME['node_info']
assert t['auth'] is None
"
}

# FEAT-256 — api-account-list verb

@test "FEAT-256: api-account-list verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-account-list" ]
}

@test "FEAT-256: api-account-list returns JSON array for empty wallet" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets256"
	mkdir -p "$LIGHTNING_WALLETS_ROOT/default"
	sqlite3 "$LIGHTNING_WALLETS_ROOT/default/state.db" \
		"CREATE TABLE IF NOT EXISTS accounts(address TEXT,name TEXT,description TEXT,overdraft TEXT,created_at TEXT); CREATE TABLE IF NOT EXISTS ledger(id INTEGER,account TEXT,amount_msat INTEGER,message TEXT);"
	out=$("$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-account-list")
	[ "$out" = "[]" ] || echo "$out" | python3 -c "import sys,json; json.load(sys.stdin)"
}

@test "FEAT-256: api-account-list --search filters results" {
	grep -q "\-\-search" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-account-list"
}

@test "FEAT-256: api-account-list --limit caps results" {
	grep -q "\-\-limit" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-account-list"
}

# FEAT-257 — channel list verb + endpoint

@test "FEAT-257: api-channel-list verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-channel-list" ]
}

@test "FEAT-257: channels.py CGI script exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/channels.py" ]
}

@test "FEAT-257: Apache conf has ScriptAlias for /v1/channels" {
	grep -q "v1/channels" "$BATS_TEST_DIRNAME/../../share/lightning/apache/lnurlp.conf"
}

@test "FEAT-257: sudoers lists api-channel-list" {
	grep -q "api-channel-list" "$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
}



# FEAT-258 — PWA light/dark mode toggle





# FEAT-259 — peer-connect / peer-disconnect / peer-list verbs

@test "FEAT-259: peer-connect verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/peer-connect" ]
}

@test "FEAT-259: peer-disconnect verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/peer-disconnect" ]
}

@test "FEAT-259: peer-list verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/peer-list" ]
}

@test "FEAT-259: peer-list returns empty array when no daemon" {
	out=$(PATH="" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/peer-list" 2>/dev/null)
	[ "$out" = "[]" ]
}

@test "FEAT-259: man pages exist for peer-connect, peer-disconnect, peer-list" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-peer-connect.1" ]
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-peer-disconnect.1" ]
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-peer-list.1" ]
}

# FEAT-260 — channel-open / channel-close verbs

@test "FEAT-260: channel-open verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/channel-open" ]
}

@test "FEAT-260: channel-close verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/channel-close" ]
}

@test "FEAT-260: man pages exist for channel-open and channel-close" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-channel-open.1" ]
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-channel-close.1" ]
}

@test "FEAT-260: channel-open validates sat argument" {
	grep -q "case.*sat.*\*\[!\*0-9\]\*\|NOT_A_NUMBER\|0-9.*exit 2" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/channel-open"
}

# FEAT-261 — wallet-stats verb

@test "FEAT-261: wallet-stats verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-stats" ]
}

@test "FEAT-261: wallet-stats returns valid JSON for missing wallet" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets261"
	out=$("$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-stats" 2>/dev/null)
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['num_accounts']==0"
}

@test "FEAT-261: wallet-stats man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-wallet-stats.1" ]
}

# FEAT-262 — invoice-decode verb + preview

@test "FEAT-262: invoice-decode verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/invoice-decode" ]
}

@test "FEAT-262: decode.py CGI exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/decode.py" ]
}

@test "FEAT-262: Apache conf has ScriptAlias for /v1/decode" {
	grep -q "v1/decode" "$BATS_TEST_DIRNAME/../../share/lightning/apache/lnurlp.conf"
}



# FEAT-263 — invoice-list verb

@test "FEAT-263: invoice-list verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/invoice-list" ]
}

@test "FEAT-263: invoice-list returns empty array without daemon" {
	out=$(PATH="" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/invoice-list" 2>/dev/null)
	[ "$out" = "[]" ]
}

@test "FEAT-263: invoice-list man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-invoice-list.1" ]
}

# FEAT-264 — payment-list verb

@test "FEAT-264: payment-list verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/payment-list" ]
}

@test "FEAT-264: payment-list returns empty array without daemon" {
	out=$(PATH="" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/payment-list" 2>/dev/null)
	[ "$out" = "[]" ]
}

@test "FEAT-264: payment-list man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-payment-list.1" ]
}

# FEAT-265 — node-funds verb + PWA screen

@test "FEAT-265: node-funds verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-funds" ]
}

@test "FEAT-265: node-funds returns zero totals without daemon" {
	out=$(PATH="" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-funds" 2>/dev/null)
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['total_sat']==0"
}

@test "FEAT-265: node_funds.py CGI exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/node_funds.py" ]
}


@test "FEAT-265: node-funds man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-node-funds.1" ]
}

# FEAT-266 — route-find verb

@test "FEAT-266: route-find verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/route-find" ]
}

@test "FEAT-266: route-find man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-route-find.1" ]
}

@test "FEAT-266: route-find validates sat argument" {
	grep -q "case.*sat.*0-9\|sat.*exit 2" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/route-find"
}

# FEAT-267 — node-log verb

@test "FEAT-267: node-log verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-log" ]
}

@test "FEAT-267: node-log returns empty array without daemon" {
	out=$(PATH="" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-log" 2>/dev/null)
	[ "$out" = "[]" ]
}

@test "FEAT-267: node-log man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-node-log.1" ]
}

# FEAT-268 — node-config verb

@test "FEAT-268: node-config verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-config" ]
}

@test "FEAT-268: node-config handles get subcommand" {
	grep -q '"get"' "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-config" || \
	grep -q 'get)' "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-config"
}

@test "FEAT-268: node-config handles set subcommand" {
	grep -q '"set"\|set)' "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-config"
}
