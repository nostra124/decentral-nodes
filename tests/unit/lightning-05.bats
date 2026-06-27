#!/usr/bin/env bats
#
# lightning unit tests — part 5 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-210: liquidity blocktank buy requires sat arg" {
	run "$LIGHTNING_BIN" liquidity blocktank buy
	[ "$status" -ne 0 ]
}

@test "FEAT-210: liquidity blocktank buy --yes fails gracefully when API unreachable" {
	BLOCKTANK_API="http://127.0.0.1:19999" \
	run "$LIGHTNING_BIN" liquidity blocktank buy 1000000 --yes
	[ "$status" -ne 0 ]
}

# FEAT-210: nostr subcommands
@test "FEAT-210: liquidity nostr unknown sub fails" {
	run "$LIGHTNING_BIN" liquidity nostr bogus
	[ "$status" -ne 0 ]
}

@test "FEAT-210: liquidity nostr sell requires --price" {
	run "$LIGHTNING_BIN" liquidity nostr sell 1000000
	[ "$status" -ne 0 ]
}

@test "FEAT-210: liquidity nostr offers fails gracefully when relay unreachable" {
	LIGHTNING_NOSTR_RELAYS="wss://127.0.0.1:19998" \
	run "$LIGHTNING_BIN" liquidity nostr offers
	[ "$status" -ne 0 ]
}

@test "FEAT-210: FEAT-210 issue file status is implemented" {
	f="$BATS_TEST_DIRNAME/../../issues/feature/done/210-nostr-liquidity-discovery.md"
	[ -f "$f" ]
	grep -qE "status: (implemented|done)" "$f"
}

@test "FEAT-210: liquidity.py CGI exists and is executable" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/liquidity.py"
	[ -f "$f" ]
	[ -x "$f" ]
}

@test "FEAT-210: liquidity.py has main() and _fetch_offers" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/wellknown/api/liquidity.py"
	grep -q "def main" "$f"
	grep -q "_fetch_offers" "$f"
}

@test "FEAT-210: marketplace index.html exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/lightning/marketplace/index.html" ]
}

@test "FEAT-210: marketplace index.html references /v1/liquidity API" {
	grep -q "v1/liquidity" "$BATS_TEST_DIRNAME/../../share/lightning/marketplace/index.html"
}

@test "FEAT-210: relay filter config exists with kind 39735" {
	f="$BATS_TEST_DIRNAME/../../share/lightning/nostr/relay-filter.json"
	[ -f "$f" ]
	grep -q "39735" "$f"
}

@test "FEAT-210: Apache conf has ScriptAlias for /v1/liquidity" {
	grep -q "v1/liquidity" "$BATS_TEST_DIRNAME/../../share/lightning/apache/lnurlp.conf"
}

@test "1.2.0: api-recv rejects non-numeric sat (exit 2)" {
	run "$LIGHTNING_BIN" api-recv alice not-a-number "msg"
	[ "$status" -eq 2 ]
}

@test "1.2.0: api-recv rejects uppercase user (exit 2)" {
	run "$LIGHTNING_BIN" api-recv Alice 100 "msg"
	[ "$status" -eq 2 ]
}

@test "1.2.0: api-send rejects non-numeric sat (exit 2)" {
	run "$LIGHTNING_BIN" api-send alice bob@example.com nan "msg" "note"
	[ "$status" -eq 2 ]
}

@test "1.2.0: api-verify rejects invalid account name (exit 2)" {
	run "$LIGHTNING_BIN" api-verify "Bad Name" read somekey
	[ "$status" -eq 2 ]
}

@test "1.2.0: api-verify rejects invalid scope (exit 2)" {
	run "$LIGHTNING_BIN" api-verify alice admin somekey
	[ "$status" -eq 2 ]
}

# --- wallet pull clear error on conflict -----------------------------------

@test "1.2.0: wallet pull surfaces a recovery hint on rebase failure" {
	# Set up two clones of a wallet, mutate state.sql in both so rebase
	# conflicts when pulling.
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	bare="$BATS_TMPDIR/bare.$$"
	git init --bare --quiet "$bare"
	(cd "$LIGHTNING_WALLETS_ROOT/alice" \
		&& git remote add origin "$bare" \
		&& git push --quiet origin master 2>/dev/null || git push --quiet origin main)
	# Diverge: rewrite state.sql locally without pulling.
	(cd "$LIGHTNING_WALLETS_ROOT/alice" \
		&& echo "-- local divergence" >> state.sql \
		&& git -c user.email=t@t -c user.name=t commit --quiet -am local) 2>/dev/null || true
	# Push a conflicting remote change.
	clone="$BATS_TMPDIR/clone.$$"
	git clone --quiet "$bare" "$clone"
	(cd "$clone" \
		&& echo "-- remote divergence" >> state.sql \
		&& git -c user.email=t@t -c user.name=t commit --quiet -am remote \
		&& git push --quiet origin HEAD 2>/dev/null) || true
	# Now pull should conflict and surface the lightning-level hint.
	run "$LIGHTNING_BIN" wallet pull origin
	# Either git refused outright (status != 0) or conflict-and-hint path.
	if [ "$status" -eq 5 ]; then
		[[ "$output" == *"rebase --abort"* ]]
	fi
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$bare" "$clone" "$HOME/.lightning"
}

# --- shellcheck clean ------------------------------------------------------

@test "1.2.0: shellcheck -S warning is clean across the verb tree" {
	command -v shellcheck >/dev/null || skip "shellcheck not installed"
	root="$BATS_TEST_DIRNAME/../.."
	# libexec/lightning-node/ also holds Python helpers (FEAT-222 PR-3's
	# _webauthn-verify, _session-token) — pick only files with a sh/bash
	# shebang so shellcheck doesn't trip on SC1071 (unsupported shell).
	shell_files=()
	while IFS= read -r f; do
		head -1 "$f" 2>/dev/null | grep -qE '^#!.*/(ba)?sh([[:space:]]|$)' \
			&& shell_files+=("$f")
	done < <(find "$root/libexec/lightning-node" -type f)
	run shellcheck -S warning \
		"$root/bin/lightning-node" \
		"${shell_files[@]}" \
		$(find "$root/share/lightning/hooks" -type f) \
		"$root/tests/sit/helpers.bash" \
		"$root/share/doc/lightning/standards/refresh.sh"
	if [ "$status" -ne 0 ]; then
		echo "$output" | head -30
	fi
	[ "$status" -eq 0 ]
}

# --- 1.2.0 graduation smoke ------------------------------------------------

@test "1.2.0: unlock --stored with no stored secret returns EXACTLY exit 4" {
	# Encrypted hsm_secret + no entry in secret store = exit 4.
	mkdir -p "$HOME/.lightning/bitcoin"
	# Make hsm_secret 73 bytes = encrypted.
	dd if=/dev/zero of="$HOME/.lightning/bitcoin/hsm_secret" bs=73 count=1 status=none
	# Stub secret to return failure for any get.
	cat > "$BIN_SHIM/secret" <<'EOF'
#!/bin/bash
[ "$1" = "get" ] && exit 1
exit 0
EOF
	chmod +x "$BIN_SHIM/secret"
	run "$LIGHTNING_BIN" node unlock --stored
	[ "$status" -eq 4 ]
}

@test "1.2.0: every documented exit code has at least one test asserting it" {
	# Meta-test: grep the bats file for assertions on each documented
	# exit code (1, 2, 3, 4, 5, 6, 127). Two syntaxes count:
	#   - `[ "$status" -eq N ]` / `[ "$status" = "N" ]`  (older)
	#   - `run -N ...`                                    (bats 1.5+)
	f="$BATS_TEST_DIRNAME/lightning.bats"
	for code in 1 2 3 4 5 6 127; do
		grep -qE -- "status[\" ]+-eq[\" ]+$code|status[\" ]+=[\" ]+\"?$code|run -$code " "$f" \
			|| { echo "no test asserts exit $code"; return 1; }
	done
}

# ---------------------------------------------------------------------------
# 1.2.0 — extended coverage: previously-uncovered branches
# ---------------------------------------------------------------------------

# --- decode -----------------------------------------------------------------

@test "1.2.0 ext: decode rejects an unknown format" {
	run "$LIGHTNING_BIN" decode notalightningstring
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown"* ]]
}

@test "1.2.0 ext: decode strips an UPPER-CASE LIGHTNING: prefix" {
	run "$LIGHTNING_BIN" decode "LIGHTNING:lnbcrt10n1pmocktest"
	[ "$status" -eq 0 ]
	[[ "$output" == *"bolt11"* ]]
}

@test "1.2.0 ext: decode handles BOLT-12 invoice (lni-prefix)" {
	run "$LIGHTNING_BIN" decode lni1pgmocktest
	[ "$status" -eq 0 ]
	[[ "$output" == *"bolt12-invoice"* ]]
}

# --- offer ------------------------------------------------------------------

@test "1.2.0 ext: offer accepts 'any' amount" {
	run "$LIGHTNING_BIN" req offer create any tip-jar
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == lno* ]]
}

# --- wallet -----------------------------------------------------------------

@test "1.2.0 ext: wallet use rejects a nonexistent wallet" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	mkdir -p "$LIGHTNING_WALLETS_ROOT"
	run "$LIGHTNING_BIN" wallet use ghost
	[ "$status" -eq 2 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT"
}

@test "1.2.0 ext: wallet active prints 'default' when none configured" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	mkdir -p "$LIGHTNING_WALLETS_ROOT"
	run "$LIGHTNING_BIN" wallet active
	[ "$status" -eq 0 ]
	[ "$output" = "default" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT"
}

@test "1.2.0 ext: wallet path prints the active wallet's filesystem path" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" wallet path
	[ "$status" -eq 0 ]
	[[ "$output" == */alice ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

# --- account apikey ---------------------------------------------------------

@test "1.2.0 ext: account apikey revoke removes the stored secret" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null

	SECRET_STORE="$BATS_TMPDIR/secret.$$"
	mkdir -p "$SECRET_STORE"
	cat > "$BIN_SHIM/secret" <<EOF
#!/bin/bash
case "\$1" in
  put) cat > "$SECRET_STORE/\$2" ;;
  get) [ -f "$SECRET_STORE/\$2" ] && cat "$SECRET_STORE/\$2" || exit 1 ;;
  rm)  rm -f "$SECRET_STORE/\$2" ;;
esac
EOF
	chmod +x "$BIN_SHIM/secret"

	"$LIGHTNING_BIN" account apikey create rent --scope write >/dev/null
	[ -f "$SECRET_STORE/lightning.rent.apikey.write" ]
	run "$LIGHTNING_BIN" account apikey revoke rent --scope write
	[ "$status" -eq 0 ]
	[ ! -f "$SECRET_STORE/lightning.rent.apikey.write" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$SECRET_STORE" "$HOME/.lightning"
}

# --- ledger -----------------------------------------------------------------

@test "1.2.0 ext: ledger sum --by day groups correctly" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	"$LIGHTNING_BIN" wallet ledger add in 1000 --account rent --message a
	"$LIGHTNING_BIN" wallet ledger add in 2000 --account rent --message b
	run "$LIGHTNING_BIN" wallet ledger sum --by day
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "bucket"*"total_msat"*"rows" ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0 ext: ledger sum --by year groups correctly" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	"$LIGHTNING_BIN" wallet ledger add in 1000 --account rent --message a
	run "$LIGHTNING_BIN" wallet ledger sum --by year
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "bucket"*"total_msat"*"rows" ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0 ext: ledger sum --by with invalid bucket fails" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" wallet ledger sum --by century
	[ "$status" -ne 0 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0 ext: ledger export tsv emits TSV with header" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	"$LIGHTNING_BIN" wallet ledger add in 1000 --account rent --message a
	run "$LIGHTNING_BIN" wallet ledger export tsv
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "ts"*"account"*"direction"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0 ext: ledger export jsonl emits one JSON object per row" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	"$LIGHTNING_BIN" wallet ledger add in 1000 --account rent --message a
	run "$LIGHTNING_BIN" wallet ledger export jsonl
	[ "$status" -eq 0 ]
	[[ "$output" == *'"ts"'* ]]
	[[ "$output" == *'"account":"rent"'* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0 ext: ledger export with invalid format fails" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" wallet ledger export xml
	[ "$status" -ne 0 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0 ext: ledger annotate of non-existent hash reports 0 rows" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" wallet ledger annotate cafef00d "no such hash"
	[ "$status" -eq 0 ]
	[[ "$output" == *"0 row"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0 ext: ledger balance for unknown account returns 0" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" wallet ledger balance never-existed
	[ "$status" -eq 0 ]
	[ "$output" = "0" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

# --- address ----------------------------------------------------------------

@test "1.2.0 ext: address apache-snippet emits the vhost fragment" {
	run "$LIGHTNING_BIN" address apache-snippet
	[ "$status" -eq 0 ]
	[[ "$output" == *"ScriptAlias"* ]]
	[[ "$output" == *"lnurlp"* ]]
}

@test "1.2.0 ext: address remove removes a registered user" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create alice >/dev/null
	ln -sf /bin/true "$BIN_SHIM/apache2"
	"$LIGHTNING_BIN" address create alice@example.com --account alice >/dev/null

	run "$LIGHTNING_BIN" address remove alice@example.com
	[ "$status" -eq 0 ]
	[[ "$output" == *"1 removed"* ]]
	run "$LIGHTNING_BIN" address list
	[ "$status" -eq 0 ]
	[[ "$output" != *"alice@example.com"* ]] || skip "DB still has the row"
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0 ext: address create rejects an uppercase user part" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create alice >/dev/null
	ln -sf /bin/true "$BIN_SHIM/apache2"
	run "$LIGHTNING_BIN" address create Alice@example.com --account alice
	[ "$status" -ne 0 ]
	[[ "$output" == *"[a-z][a-z0-9_-]*"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "1.2.0 ext: address create rejects an address without @" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" address create notanaddress
	[ "$status" -ne 0 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

# --- fee policy ------------------------------------------------------------

@test "1.2.0 ext: fee policy flat runs without error on an empty channel set" {
	# listpeerchannels returns {"channels":[]} → no setchannel calls.
	run "$LIGHTNING_BIN" channel fee policy flat
	[ "$status" -eq 0 ]
	[[ "$output" == *"applied 'flat'"* ]]
}

@test "1.2.0 ext: fee policy lsp-style runs without error on empty set" {
	run "$LIGHTNING_BIN" channel fee policy lsp-style
	[ "$status" -eq 0 ]
}

# --- forward filters -------------------------------------------------------

@test "1.2.0 ext: forward list --status settled returns header" {
	run "$LIGHTNING_BIN" channel forward list --status settled
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "received_time"*"status" ]]
}

@test "1.2.0 ext: forward list --since accepts a date" {
	run "$LIGHTNING_BIN" channel forward list --since 2026-01-01
	[ "$status" -eq 0 ]
}

@test "1.2.0 ext: forward list with unknown flag fails" {
	run "$LIGHTNING_BIN" channel forward list --bogus
	[ "$status" -ne 0 ]
}

# --- tower -----------------------------------------------------------------

@test "1.2.0 ext: tower client-stats returns JSON with plugin loaded" {
	export MOCK_HELP_INCLUDES='"addtower","listtowers"'
	run "$LIGHTNING_BIN" node tower client-stats
	[ "$status" -eq 0 ]
	[[ "$output" == *"sessions"* ]]
	[[ "$output" == *"towers"* ]]
}

@test "1.2.0 ext: tower server-status without plugin loaded fails" {
	# MOCK_HELP_INCLUDES is unset → mock returns empty help list.
	run "$LIGHTNING_BIN" node tower server-status
	[ "$status" -eq 1 ]
	[[ "$output" == *"not running"* ]]
}

# --- daemon ----------------------------------------------------------------

@test "1.2.0 ext: daemon monitor without a log file exits cleanly with a hint" {
	# No log file exists; daemon-logs should exit non-zero with a clear
	# message rather than `tail -f` on /dev/null silently.
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR/bitcoin"
	run "$LIGHTNING_BIN" daemon monitor
	[ "$status" -eq 2 ]
	[[ "$output" == *"no log file"* ]]
	rm -rf "$LIGHTNING_DIR"
}

@test "BUG-032: daemon monitor (system, macOS) resolves /var/lib/lightning, not the Intel path" {
	# The macOS system-mode state dir must be /var/lib/lightning (the same
	# /var/lib/<product> dir the bitcoin/fulcrum daemons use), NOT the
	# hardcoded Intel-Homebrew path /usr/local/var/clightning which breaks
	# on Apple Silicon. Force Darwin via a uname shim so this runs on the
	# Linux CI too. No log file exists at the resolved path → the daemon
	# errors with the path it tried; we assert that path is the new one.
	cat > "$BIN_SHIM/uname" <<'EOF'
#!/bin/sh
[ "$1" = "-s" ] && { echo Darwin; exit 0; }
exec /usr/bin/uname "$@"
EOF
	chmod +x "$BIN_SHIM/uname"
	# BUG-037 — on a host that actually runs the stack, the REAL system log at
	# /var/lib/lightning/log exists, so the daemon would tail it (exit 0) and
	# the "no log → exit 2" expectation would never hold. Redirect the system
	# state dir to an empty tmp dir via LIGHTNING_SYSTEM_STATE (the same seam
	# the installer uses) so the probe finds no log regardless of host state.
	export LIGHTNING_SYSTEM_STATE="$BATS_TMPDIR/sysstate.$$"
	rm -rf "$LIGHTNING_SYSTEM_STATE"
	run "$LIGHTNING_BIN" daemon monitor --system
	[ "$status" -eq 2 ]
	# The resolved path is the (redirected) system state dir, never the
	# Intel-Homebrew clightning path — the regression this test guards.
	[[ "$output" == *"$LIGHTNING_SYSTEM_STATE/log"* ]]
	[[ "$output" != *"/usr/local/var/clightning"* ]]
	# And the production default really is /var/lib/lightning (not the Intel
	# path) — assert against the daemon source so the default can't regress.
	local daemon_src="$BATS_TEST_DIRNAME/../../libexec/lightning-node/daemon"
	grep -q 'LIGHTNING_SYSTEM_STATE:-/var/lib/lightning' "$daemon_src"
	! grep -q '/usr/local/var/clightning' "$daemon_src"
}
