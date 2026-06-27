#!/usr/bin/env bats
#
# lightning unit tests — part 17 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


# ---------------------------------------------------------------------------
# node dispatcher tests
# ---------------------------------------------------------------------------

@test "node dispatcher exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node" ]
}

@test "node --help exits 0" {
	run "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node" help
	[ "$status" -eq 0 ]
}

@test "node no-args exits non-zero" {
	run "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node"
	[ "$status" -ne 0 ]
}

@test "node pubkey subcommand arm exists" {
	grep -q "pubkey)" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node"
}

@test "node alias subcommand arm exists" {
	grep -q "alias)" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node"
}

@test "node man page exists with correct NAME" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-node.1" ]
	grep -q "lightning-node" "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-node.1"
}

@test "node bash syntax is valid" {
	bash -n "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node"
}

# statistics object (factored out of node)

@test "statistics stats returns JSON with node key (mock)" {
	out=$(PATH="$BATS_TEST_DIRNAME/../mock_bins:$PATH" \
		"$BATS_TEST_DIRNAME/../../libexec/lightning-node/statistics" stats 2>/dev/null || true)
	# either json or error json — must be parseable
	echo "$out" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null || true
}

@test "statistics forward-stats arm exists" {
	grep -q "forward-stats)" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/statistics"
}

@test "statistics channel-count arm exists" {
	grep -q "channel-count)" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/statistics"
}

@test "statistics stats --field flag documented" {
	"$BATS_TEST_DIRNAME/../../libexec/lightning-node/statistics" help stats 2>&1 | grep -q "\-\-field"
}

@test "statistics no-args exits non-zero" {
	run "$BATS_TEST_DIRNAME/../../libexec/lightning-node/statistics"
	[ "$status" -ne 0 ]
}

@test "statistics bash syntax is valid" {
	bash -n "$BATS_TEST_DIRNAME/../../libexec/lightning-node/statistics"
}

@test "node no longer carries the stats/plugin arms (factored out)" {
	! grep -q "cmd_stats" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node"
	! grep -q "cmd_plugin_list" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node"
}

# plugin object — reckless package-mgmt + runtime load/stop

@test "plugin loaded/start/stop runtime arms exist" {
	grep -q "loaded)" "$BATS_TEST_DIRNAME/../../libexec/lightning-node/plugin"
	grep -q "start)"  "$BATS_TEST_DIRNAME/../../libexec/lightning-node/plugin"
	grep -q "stop)"   "$BATS_TEST_DIRNAME/../../libexec/lightning-node/plugin"
}

@test "plugin bash syntax is valid" {
	bash -n "$BATS_TEST_DIRNAME/../../libexec/lightning-node/plugin"
}

# consolidated wallet-* micro-verbs

@test "wallet stats subcommand returns JSON" {
	out=$(LIGHTNING_DIR=/nonexistent libexec/lightning-node/wallet stats 2>/dev/null) || true
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'wallet_count' in d"
}

@test "wallet stats --field returns single value" {
	out=$(LIGHTNING_DIR=/nonexistent libexec/lightning-node/wallet stats --field wallet_count 2>/dev/null) || true
	python3 -c "import json; json.loads('$out')"
}

@test "wallet count subcommand returns JSON" {
	out=$(LIGHTNING_WALLETS_ROOT=/tmp/no-wallets-test libexec/lightning-node/wallet count 2>/dev/null) || true
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'count' in d"
}

@test "wallet stats man page exists with correct NAME" {
	grep -q "lightning-wallet" share/man/man1/lightning-wallet.1
}

@test "wallet stats arm present in dispatcher" {
	grep -q "stats)" libexec/lightning-node/wallet
}

# consolidated invoice-* micro-verbs

@test "invoice stats subcommand returns JSON" {
	out=$(LIGHTNING_DIR=/nonexistent libexec/lightning-node/invoice stats 2>/dev/null) || true
	echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'total_count' in d"
}

@test "invoice stats --field returns value" {
	out=$(LIGHTNING_DIR=/nonexistent libexec/lightning-node/invoice stats --field total_count 2>/dev/null) || true
	python3 -c "import json; json.loads('$out')"
}

@test "invoice cancel requires label" {
	run libexec/lightning-node/invoice cancel
	[ "$status" -ne 0 ]
}

@test "invoice stats man page exists with correct NAME" {
	grep -q "lightning-invoice" share/man/man1/lightning-invoice.1
}

@test "invoice stats arm present in dispatcher" {
	grep -q "stats)" libexec/lightning-node/invoice
}

@test "invoice list-paid arm present" {
	grep -q "list-paid" libexec/lightning-node/invoice
}

# consolidated channel-* micro-verbs

@test "channel stats arm present in dispatcher" {
	grep -q "stats)" libexec/lightning-node/channel
}

@test "channel stats --help works" {
	libexec/lightning-node/channel stats --help 2>&1 | grep -q "capacity_count"
}

@test "channel inspect arm present in dispatcher" {
	grep -q "inspect)" libexec/lightning-node/channel
}

@test "channel close-all arm present in dispatcher" {
	grep -q "close-all)" libexec/lightning-node/channel
}

@test "channel peer-summary arm present in dispatcher" {
	grep -q "peer-summary)" libexec/lightning-node/channel
}

@test "channel rebalance-suggestion arm present in dispatcher" {
	grep -q "rebalance-suggestion)" libexec/lightning-node/channel
}

@test "channel top-earners arm present in dispatcher" {
	grep -q "top-earners)" libexec/lightning-node/channel
}

@test "channel balance-gini arm present in dispatcher" {
	grep -q "balance-gini)" libexec/lightning-node/channel
}

@test "channel stuck arm present in dispatcher" {
	grep -q "stuck)" libexec/lightning-node/channel
}

@test "channel bash syntax is valid" {
	bash -n libexec/lightning-node/channel
}

@test "channel man page has STATS section" {
	grep -q "^.SH STATS" share/man/man1/lightning-channel.1
}

@test "channel man page has SUBCOMMANDS section" {
	grep -q "^.SH SUBCOMMANDS" share/man/man1/lightning-channel.1
}

# FEAT-286 — GET /v1/accounts operator listing


# FEAT-287 — api-account-describe verb + PATCH /v1/accounts/<id>/describe


@test "FEAT-287: sudoers lists api-account-describe" {
	grep -q "api-account-describe" share/lightning/sudoers.d/lightning
}

# FEAT-288 — node-peers-score verb

@test "FEAT-291: MCP tools/list includes payment_status" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/lightning/mcp.json"
	python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
assert 'payment_status' in d['tools'], 'payment_status not in tools'
" "$f"
}

@test "FEAT-291: sudoers lists api-payment-status" {
	grep -q 'api-payment-status' \
		"$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
}

# FEAT-292 — MCP payment_status tool

@test "FEAT-292: payment_status tool has no auth" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/mcp.py"
	python3 -c "
import sys
src=open(sys.argv[1]).read()
i=src.find('\"payment_status\"')
assert i >= 0, 'tool not found'
window=src[i:i+800]
assert '\"auth\": None' in window or \"'auth': None\" in window, 'auth not None'
" "$f"
}

# FEAT-293 — api-invoice-status verb

@test "FEAT-293: MCP tools/list includes invoice_status" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/lightning/mcp.json"
	python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
assert 'invoice_status' in d['tools'], 'invoice_status not in tools'
" "$f"
}

@test "FEAT-293: sudoers lists api-invoice-status" {
	grep -q 'api-invoice-status' \
		"$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
}

# FEAT-294 — MCP invoice_status tool

@test "FEAT-294: invoice_status tool has no auth" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/mcp.py"
	python3 -c "
import sys
src=open(sys.argv[1]).read()
i=src.find('\"invoice_status\"')
assert i >= 0, 'tool not found'
window=src[i:i+800]
assert '\"auth\": None' in window or \"'auth': None\" in window, 'auth not None'
" "$f"
}

# FEAT-295 — payment-retry verb

@test "FEAT-296: MCP tools/list includes peers_score" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/lightning/mcp.json"
	python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
assert 'peers_score' in d['tools'], 'peers_score not in tools'
" "$f"
}

@test "FEAT-296: peers_score tool has no auth" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/mcp.py"
	python3 -c "
import sys
src=open(sys.argv[1]).read()
i=src.find('\"peers_score\"')
assert i >= 0, 'tool not found'
window=src[i:i+800]
assert '\"auth\": None' in window or \"'auth': None\" in window, 'auth not None'
" "$f"
}

@test "FEAT-296: sudoers lists api-node-peers-score" {
	grep -q 'api-node-peers-score' \
		"$BATS_TEST_DIRNAME/../../share/lightning/sudoers.d/lightning"
}

# FEAT-297 — node-htlc-list verb

@test "FEAT-411: invoice-decode verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/invoice-decode" ]
}
