#!/usr/bin/env bats
#
# lightning unit tests — part 4 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-182: helpers.bash defines sit_setup_alice_bob + sit_teardown" {
	f="$BATS_TEST_DIRNAME/../../tests/sit/helpers.bash"
	grep -q "^sit_setup_alice_bob()" "$f"
	grep -q "^sit_teardown()" "$f"
	grep -q "^sit_mine()" "$f"
	grep -q "^sit_open_channel()" "$f"
}

@test "FEAT-182: Dockerfile.clightning installs apache2 + python3 + sqlite3" {
	f="$BATS_TEST_DIRNAME/../../tests/sit/podman/Dockerfile.clightning"
	grep -q "apache2" "$f"
	grep -q "python3" "$f"
	grep -q "sqlite3" "$f"
	grep -q "lightningd" "$f"
}

@test "FEAT-182: Makefile check-sit target invokes podman build + run" {
	f="$BATS_TEST_DIRNAME/../../Makefile.in"
	grep -q "podman build" "$f"
	grep -q "podman run" "$f"
}

# ---------------------------------------------------------------------------
# 1.0.0 graduation smokes
# ---------------------------------------------------------------------------

@test "1.0.0: every 0.x milestone-plan file is gone (graduation invariant)" {
	root="$BATS_TEST_DIRNAME/../../issues"
	# 1.0.0 graduation: every 0.x milestone has been consumed and
	# deleted. Later 1.x milestones may be open and unfinished.
	! ls "$root"/MILESTONE-0.*.md 2>/dev/null
}

@test "1.0.0: every initial FEAT (170..195) is in issues/feature/done/" {
	root="$BATS_TEST_DIRNAME/../../issues/feature/done"
	for n in 170 171 172 173 174 175 176 177 178 179 180 181 182 \
	         183 184 185 187 189 191 192 193 195 196; do
		# Single matching file per number.
		count=$(ls "$root"/${n}-*.md 2>/dev/null | wc -l)
		[ "$count" -eq 1 ] || { echo "FEAT-$n missing in done/"; return 1; }
	done
}

# ---------------------------------------------------------------------------
# 1.1.0 — routing-node features
# ---------------------------------------------------------------------------

@test "FEAT-186: lightning tower (no args) prints usage" {
	run "$LIGHTNING_BIN" node tower
	[ "$status" -ne 0 ]
	[[ "$output" == *"usage"* ]]
}

@test "FEAT-186: tower client-add exits 3 when plugin not loaded" {
	run "$LIGHTNING_BIN" node tower client-add 020000000000000000000000000000000000000000000000000000000000000002@127.0.0.1:9814
	[ "$status" -eq 3 ]
	[[ "$output" == *"altruistwatchtower"* ]]
}

@test "FEAT-186: tower client-add succeeds with plugin loaded" {
	export MOCK_HELP_INCLUDES='"addtower","listtowers"'
	run "$LIGHTNING_BIN" node tower client-add 020000000000000000000000000000000000000000000000000000000000000002@127.0.0.1:9814
	[ "$status" -eq 0 ]
}

@test "FEAT-186: tower client-list returns TSV header" {
	export MOCK_HELP_INCLUDES='"addtower","listtowers"'
	run "$LIGHTNING_BIN" node tower client-list
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "pubkey	host	port	sessions" ]]
}

@test "FEAT-188: lightning fee (no args) prints usage" {
	run "$LIGHTNING_BIN" channel fee
	[ "$status" -ne 0 ]
	[[ "$output" == *"usage"* ]]
}

@test "FEAT-188: fee get returns the TSV header" {
	run "$LIGHTNING_BIN" channel fee get
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "channel_id	base_msat	ppm" ]]
}

@test "FEAT-188: fee set with non-numeric base rejects" {
	run "$LIGHTNING_BIN" channel fee set chan-1 not-a-number 100
	[ "$status" -ne 0 ]
	[[ "$output" == *"integer required"* ]]
}

@test "FEAT-188: fee set with valid args round-trips" {
	run "$LIGHTNING_BIN" channel fee set 0000000000000000000000000000000000000000000000000000000000000001 1000 5
	[ "$status" -eq 0 ]
	[[ "$output" == *"fee_base_msat"* ]]
	[[ "$output" == *"1000"* ]]
}

@test "FEAT-188: fee policy rejects unknown name" {
	run "$LIGHTNING_BIN" channel fee policy bogus
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown"* ]]
}

@test "FEAT-188: forward (no args) prints usage" {
	run "$LIGHTNING_BIN" channel forward
	[ "$status" -ne 0 ]
	[[ "$output" == *"usage"* ]]
}

@test "FEAT-188: forward list returns TSV header" {
	run "$LIGHTNING_BIN" channel forward list
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "received_time	in_channel	out_channel	in_msat	out_msat	fee_msat	status" ]]
}

@test "FEAT-188: forward stats returns JSON with success_rate" {
	run "$LIGHTNING_BIN" channel forward stats
	[ "$status" -eq 0 ]
	[[ "$output" == *"success_rate"* ]]
	[[ "$output" == *"forwarded_msat"* ]]
}

@test "1.1.0: help lists tower / fee / forward" {
	run "$LIGHTNING_BIN" help
	[[ "$output" == *"tower"* ]]
	[[ "$output" == *"fee"* ]]
	[[ "$output" == *"forward"* ]]
}

# ---------------------------------------------------------------------------
# 1.1.1 — maintenance pass
# ---------------------------------------------------------------------------

@test "1.1.1: .rpk/versions lists every released version with a SHA" {
	f="$BATS_TEST_DIRNAME/../../.rpk/versions"
	[ -s "$f" ]
	for v in 0.1.0 0.2.0 0.3.0 0.4.0 0.5.0 0.6.0 1.0.0 1.1.0; do
		grep -E "^$v	[0-9a-f]{7,}" "$f"
	done
}

@test "1.1.1: fee policy match-peer returns NOT IMPLEMENTED + exit 2" {
	run "$LIGHTNING_BIN" channel fee policy match-peer
	[ "$status" -eq 2 ]
	[[ "$output" == *"NOT IMPLEMENTED"* ]]
}

@test "1.1.1: help lists commands alphabetically with one-line descriptions" {
	run "$LIGHTNING_BIN" help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Commands:"* ]]
	[[ "$output" == *"help <command>"* ]]
	[[ "$output" == *"wallet"* ]]
	[[ "$output" == *"account"* ]]
	[[ "$output" == *"channel"* ]]
	# No subcommand details in top-level help
	[[ "$output" != *"channel open"* ]]
	[[ "$output" != *"account create"* ]]
}

@test "1.1.1: CI workflow explicitly installs sqlite3 + jq + python3" {
	f="$BATS_TEST_DIRNAME/../../.github/workflows/test.yml"
	[ -f "$f" ]
	grep -q "sqlite3" "$f"
	grep -q "jq" "$f"
	grep -q "python3" "$f"
	# shellcheck step.
	grep -q "shellcheck" "$f"
}

# ---------------------------------------------------------------------------
# 1.2.0 — coverage + correctness pass
# ---------------------------------------------------------------------------

# --- bin/lightning-node getopts fix ---------------------------------------------

@test "1.2.0: -q flag parses + version still prints" {
	run "$LIGHTNING_BIN" -q version
	[ "$status" -eq 0 ]
	[ "$output" = "$(cat "$BATS_TEST_DIRNAME/../../VERSION")" ]
}

@test "1.2.0: -q -d flags compose (getopts handles both)" {
	# Don't assert exact $output: -d enables `set -vx` which emits
	# trace to stderr that bats merges into $output. The regression
	# we're guarding against is the previous getopts bug where the
	# second flag was lost or the verb was treated as a flag.
	run "$LIGHTNING_BIN" -q -d version
	[ "$status" -eq 0 ]
	[[ "$output" == *"$(cat "$BATS_TEST_DIRNAME/../../VERSION")"* ]]
}

@test "1.2.0: unknown flag exits non-zero" {
	run "$LIGHTNING_BIN" -Z version
	[ "$status" -ne 0 ]
}

@test "1.2.0: flags before unknown command still surface the unknown error" {
	run "$LIGHTNING_BIN" -q definitely-not-a-real-subcommand
	[ "$status" -ne 0 ]
}

# --- decode pattern reorder -------------------------------------------------

@test "1.2.0: decode lnbcrt (regtest invoice) correctly identifies as BOLT-11" {
	run "$LIGHTNING_BIN" decode lnbcrt10n1pmocktest
	[ "$status" -eq 0 ]
	[[ "$output" == *"bolt11"* ]]
}

@test "1.2.0: decode lntb (testnet invoice) correctly identifies as BOLT-11" {
	run "$LIGHTNING_BIN" decode lntb10u1pmocktest
	[ "$status" -eq 0 ]
	[[ "$output" == *"bolt11"* ]]
}

# --- info: jq absence is a hard error, not silent fallback ------------------

@test "1.2.0: lightning info exits 127 when jq is absent (was silent fallback)" {
	# Place a stub PATH that has lightning-cli but no jq, then
	# invoke `lightning info` via a subshell that sets PATH for
	# the child only — so our teardown's rm / etc. still resolve.
	NOJQ_BIN="$BATS_TMPDIR/nojq.$$"
	mkdir -p "$NOJQ_BIN"
	ln -sf "$FIXTURES/lightning-cli-mock" "$NOJQ_BIN/lightning-cli"
	for tool in cat echo printf stat mktemp basename dirname date xxd openssl sed grep awk tr cut head tail rm sleep ls; do
		[ -x "/usr/bin/$tool" ] && ln -sf "/usr/bin/$tool" "$NOJQ_BIN/$tool"
		[ -x "/bin/$tool" ]     && ln -sf "/bin/$tool" "$NOJQ_BIN/$tool"
	done
	# Pass PATH inline to the run command; don't export.
	run -127 env -i HOME="$HOME" PATH="$NOJQ_BIN" SELF_QUIET=1 "$LIGHTNING_BIN" node info
	[[ "$output" == *"jq not found"* ]]
}

# --- mock-cli failure injection --------------------------------------------

@test "1.2.0: MOCK_FAIL_GETINFO makes info exit 2 with daemon-down hint" {
	export MOCK_FAIL_GETINFO=1
	run "$LIGHTNING_BIN" node info
	[ "$status" -eq 2 ]
	[[ "$output" == *"daemon"* ]]
}

@test "1.2.0: MOCK_FAIL_LISTPEERCHANNELS makes channels exit non-zero" {
	export MOCK_FAIL_LISTPEERCHANNELS=1
	run "$LIGHTNING_BIN" channel list
	[ "$status" -ne 0 ]
}

@test "1.2.0: MOCK_FAIL_INVOICE makes invoice exit non-zero" {
	export MOCK_FAIL_INVOICE=1
	run "$LIGHTNING_BIN" invoice 1000 test
	[ "$status" -ne 0 ]
}

@test "1.2.0: MOCK_FAIL_PAY surfaces a 'pay returned failed' path" {
	# Mock returns error JSON; our pay verb tries to parse status and
	# exits with the failure code.
	export MOCK_FAIL_PAY=1
	run "$LIGHTNING_BIN" pay lnbcrt10n1pmocktest
	[ "$status" -ne 0 ]
}

@test "1.2.0: MOCK_FAIL_FUNDCHANNEL surfaces channel open failure" {
	export MOCK_FAIL_FUNDCHANNEL=1
	run "$LIGHTNING_BIN" channel open \
		020000000000000000000000000000000000000000000000000000000000000002@127.0.0.1:9735 \
		100000
	[ "$status" -ne 0 ]
}

@test "1.2.0: MOCK_FAIL_CLOSE surfaces channel close failure" {
	export MOCK_FAIL_CLOSE=1
	run "$LIGHTNING_BIN" channel close 0000000000000000000000000000000000000000000000000000000000000001
	[ "$status" -ne 0 ]
}

@test "1.2.0: MOCK_FAIL_OFFER surfaces BOLT-12 offer failure" {
	export MOCK_FAIL_OFFER=1
	run "$LIGHTNING_BIN" req offer 500 donations
	[ "$status" -ne 0 ]
}

@test "1.2.0: MOCK_FAIL_NEWADDR surfaces balance --on-chain failure" {
	export MOCK_FAIL_NEWADDR=1
	run "$LIGHTNING_BIN" wallet balance --on-chain
	[ "$status" -ne 0 ]
}

# --- exit-code contracts ---------------------------------------------------

@test "1.2.0: channel force-close without --confirm returns EXACTLY exit 2" {
	run "$LIGHTNING_BIN" channel force-close 0000000000000000000000000000000000000000000000000000000000000001
	[ "$status" -eq 2 ]
}

@test "1.2.0: wallet new on an existing wallet returns EXACTLY exit 2" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" wallet new alice
	[ "$status" -eq 2 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0: account create with invalid --overdraft returns exit 1" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" account create rent --overdraft bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"deny|warn|allow"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0: account create with non-integer --limit returns exit 1" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" account create rent --limit not-a-number
	[ "$status" -eq 1 ]
	[[ "$output" == *"integer required"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0: account delete of the unassigned account is refused" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" account delete -
	[ "$status" -eq 2 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0: ledger add rejects non-numeric amount" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" wallet ledger add in not-a-number
	[ "$status" -eq 1 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0: ledger add rejects unknown direction" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" wallet ledger add sideways 1000
	[ "$status" -eq 1 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0: ledger statement without --account fails" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" wallet ledger statement --period 2026-01
	[ "$status" -eq 1 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0: ledger statement with bad period format fails" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	run "$LIGHTNING_BIN" wallet ledger statement --account rent --period notadate
	[ "$status" -eq 1 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0: address remove on a non-existent user is a no-op (exit 0)" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" address remove ghost@example.com
	[ "$status" -eq 0 ]
	[[ "$output" == *"0 removed"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0: liquidity in with unknown provider fails clearly" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" liquidity in 100000 --provider bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown provider"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0: liquidity lsp with non-'buy' second arg fails" {
	run "$LIGHTNING_BIN" liquidity lsp myname maybe 100000
	[ "$status" -ne 0 ]
}

# FEAT-210: blocktank subcommands
@test "FEAT-210: liquidity blocktank unknown sub fails" {
	run "$LIGHTNING_BIN" liquidity blocktank bogus
	[ "$status" -ne 0 ]
}
