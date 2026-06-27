#!/usr/bin/env bats
#
# lightning unit tests — part 16 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-268: node-config man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-node-config.1" ]
}

# FEAT-270 — MCP channel_list and node_funds tools

@test "FEAT-270: MCP tools/list includes channel_list" {
	grep -q '"channel_list"\|channel_list' share/lightning/wellknown/api/mcp.py
}

@test "FEAT-270: MCP tools/list includes node_funds" {
	grep -q '"node_funds"\|node_funds' share/lightning/wellknown/api/mcp.py
}

@test "FEAT-270: channel_list tool has no auth" {
	python3 -c "
src = open('share/lightning/wellknown/api/mcp.py').read()
idx = src.index('\"channel_list\"')
snippet = src[idx:idx+600]
assert '\"auth\": None' in snippet or \"'auth': None\" in snippet, repr(snippet)
"
}

# FEAT-271 — MCP account_transfer tool

@test "FEAT-271: MCP tools/list includes account_transfer" {
	grep -q '"account_transfer"' share/lightning/wellknown/api/mcp.py
}

@test "FEAT-271: account_transfer tool requires account auth" {
	python3 -c "
src = open('share/lightning/wellknown/api/mcp.py').read()
idx = src.index('\"account_transfer\"')
snippet = src[idx:idx+900]
assert '\"auth\": \"account\"' in snippet or \"'auth': 'account'\" in snippet, repr(snippet)
"
}

# FEAT-272 — MCP invoice_decode tool

@test "FEAT-272: MCP tools/list includes invoice_decode" {
	grep -q '"invoice_decode"' share/lightning/wellknown/api/mcp.py
}

@test "FEAT-272: invoice_decode tool has no auth" {
	python3 -c "
src = open('share/lightning/wellknown/api/mcp.py').read()
idx = src.index('\"invoice_decode\"')
snippet = src[idx:idx+800]
assert '\"auth\": None' in snippet or \"'auth': None\" in snippet, repr(snippet)
"
}

# FEAT-273 — api-price verb + MCP price tool

@test "FEAT-273: api-price verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-price" ]
}

@test "FEAT-273: MCP tools/list includes price" {
	grep -q '"price"' share/lightning/wellknown/api/mcp.py
}

# FEAT-275 — wallet-backup verb

@test "FEAT-275: wallet-backup verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-backup" ]
}

@test "FEAT-275: wallet-backup returns valid JSON without a wallet" {
	out=$(LIGHTNING_WALLETS_ROOT=/tmp/no-such-wallet-dir "$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-backup" 2>/dev/null)
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'accounts' in d"
}

@test "FEAT-275: wallet-backup man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-wallet-backup.1" ]
}

# FEAT-276 — wallet-check verb

@test "FEAT-276: wallet-check verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-check" ]
}

@test "FEAT-276: wallet-check reports database_not_found without wallet" {
	out=$(LIGHTNING_WALLETS_ROOT=/tmp/no-such-wallet-276 "$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-check" 2>/dev/null) || true
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['ok'] is False"
}

@test "FEAT-276: wallet-check reports ok on a valid database" {
	tmpdir=$(mktemp -d)
	mkdir -p "$tmpdir/default"
	sqlite3 "$tmpdir/default/state.db" \
		"CREATE TABLE accounts (id INTEGER); CREATE TABLE ledger (id INTEGER);"
	out=$(LIGHTNING_WALLETS_ROOT="$tmpdir" \
		"$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-check" 2>/dev/null)
	rm -rf "$tmpdir"
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['ok'] is True"
}

@test "FEAT-276: wallet-check man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-wallet-check.1" ]
}

# FEAT-277 — api-fee-list verb + MCP fee_list tool

@test "FEAT-277: api-fee-list verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-fee-list" ]
}

@test "FEAT-277: api-fee-list returns empty array without daemon" {
	out=$(PATH="" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-fee-list" 2>/dev/null)
	[ "$out" = "[]" ]
}

@test "FEAT-277: MCP tools/list includes fee_list" {
	grep -q '"fee_list"' share/lightning/wellknown/api/mcp.py
}

# FEAT-278 — api-forward-stats verb + MCP forward_stats tool

@test "FEAT-278: api-forward-stats verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-forward-stats" ]
}

@test "FEAT-278: api-forward-stats returns zero totals without daemon" {
	out=$(PATH="" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-forward-stats" 2>/dev/null)
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['count']==0"
}

@test "FEAT-278: MCP tools/list includes forward_stats" {
	grep -q '"forward_stats"' share/lightning/wellknown/api/mcp.py
}

# FEAT-279 — wallet-export-csv verb

@test "FEAT-279: wallet-export-csv verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-export-csv" ]
}

@test "FEAT-279: wallet-export-csv outputs CSV header without wallet" {
	out=$(LIGHTNING_WALLETS_ROOT=/tmp/no-wallet-279 \
		"$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-export-csv" 2>/dev/null)
	echo "$out" | grep -q "id,account,ts,direction"
}

@test "FEAT-279: wallet-export-csv man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-wallet-export-csv.1" ]
}

# FEAT-280 — api-peer-summary verb + MCP peer_summary tool

@test "FEAT-280: api-peer-summary verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-peer-summary" ]
}

@test "FEAT-280: api-peer-summary returns empty array without daemon" {
	out=$(PATH="" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/api-peer-summary" 2>/dev/null)
	[ "$out" = "[]" ]
}

@test "FEAT-280: MCP tools/list includes peer_summary" {
	grep -q '"peer_summary"' share/lightning/wellknown/api/mcp.py
}

# FEAT-281 — node-health verb + MCP node_health tool

@test "FEAT-281: node-health verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-health" ]
}

@test "FEAT-281: node-health returns valid JSON without daemon" {
	out=$(PATH="" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-health" 2>/dev/null)
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'ok' in d"
}

@test "FEAT-281: node-health man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-node-health.1" ]
}

@test "FEAT-281: MCP tools/list includes node_health" {
	grep -q '"node_health"' share/lightning/wellknown/api/mcp.py
}

# FEAT-282 — node-version verb

@test "FEAT-282: node-version verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-version" ]
}

@test "FEAT-282: node-version returns valid JSON" {
	out=$("$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-version" 2>/dev/null)
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'lightning' in d"
}

@test "FEAT-282: node-version man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-node-version.1" ]
}

# FEAT-283 — node://health MCP resource

@test "FEAT-283: MCP resources/list includes node://health" {
	grep -q '"node://health"\|node://health' share/lightning/wellknown/api/mcp.py
}

@test "FEAT-283: mcp.json includes node://health resource" {
	grep -q 'node://health' share/lightning/wellknown/lightning/mcp.json
}

# FEAT-284 — GET /v1/health public endpoint

@test "FEAT-284: health.py CGI exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/health.py" ]
}

@test "FEAT-284: Apache conf has ScriptAlias for /v1/health" {
	grep -q "v1/health" share/lightning/apache/lnurlp.conf
}

# FEAT-285 — wallet-prune verb

@test "FEAT-285: wallet-prune verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-prune" ]
}

@test "FEAT-285: wallet-prune returns zero counts without wallet" {
	out=$(LIGHTNING_WALLETS_ROOT=/tmp/no-wallet-285 \
		"$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-prune" 2>/dev/null)
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('pruned_accounts',0)==0"
}

@test "FEAT-285: wallet-prune --dry-run reports would_prune keys" {
	tmpdir=$(mktemp -d); mkdir -p "$tmpdir/default"
	sqlite3 "$tmpdir/default/state.db" \
		"CREATE TABLE accounts (address TEXT, description TEXT, balance_msat INTEGER, created_at TEXT, closed_at TEXT);
		 CREATE TABLE ledger (id INTEGER, account TEXT);
		 INSERT INTO accounts VALUES('bc1qtest','test',0,'2020-01-01','2020-01-02');"
	out=$(LIGHTNING_WALLETS_ROOT="$tmpdir" \
		"$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-prune" --dry-run 2>/dev/null)
	rm -rf "$tmpdir"
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'would_prune_accounts' in d"
}

@test "FEAT-285: wallet-prune man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-wallet-prune.1" ]
}

# consolidated peer-* micro-verbs

@test "peer stats subcommand returns JSON" {
	out=$(LIGHTNING_DIR=/nonexistent libexec/lightning-node/peer stats 2>/dev/null) || true
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'peer_count' in d"
}

@test "peer stats --field returns single value" {
	out=$(LIGHTNING_DIR=/nonexistent libexec/lightning-node/peer stats --field peer_count 2>/dev/null) || true
	python3 -c "import sys,json; json.loads('$out')"
}

@test "peer connected requires peer_id" {
	run libexec/lightning-node/peer connected
	[ "$status" -ne 0 ]
}

@test "peer stats man page exists with correct NAME" {
	grep -q "lightning-peer" share/man/man1/lightning-peer.1
}

@test "peer stats subcommand in dispatcher" {
	grep -q "stats)" libexec/lightning-node/peer
}

@test "peer disconnect-all arm present" {
	grep -q "disconnect-all" libexec/lightning-node/peer
}
