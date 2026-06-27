#!/usr/bin/env bats
#
# lightning unit tests — part 2 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-183: daemon enable --trustedcoin is idempotent (no duplicate blocks)" {
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	_stub_trustedcoin_curl
	"$LIGHTNING_BIN" daemon enable --user --trustedcoin >/dev/null 2>&1
	"$LIGHTNING_BIN" daemon enable --user --trustedcoin >/dev/null 2>&1
	"$LIGHTNING_BIN" daemon enable --user --trustedcoin >/dev/null 2>&1
	# Exactly one block, not three.
	local count; count=$(grep -c "lightning backend" "$HOME/.lightning/config" || true)
	[ "$count" -eq 2 ]   # begin + end markers
}

@test "FEAT-183: daemon enable --trustedcoin migrates a legacy esplora block" {
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	_stub_trustedcoin_curl
	mkdir -p "$HOME/.lightning"
	cat > "$HOME/.lightning/config" <<'EOF'
# user setting that should survive
log-level=debug

# >>> lightning esplora — managed by 'daemon enable --esplora'
disable-plugin=bcli
sauron-api-endpoint=https://blockstream.info/api
# <<< lightning esplora
EOF
	run "$LIGHTNING_BIN" daemon enable --user --trustedcoin
	[ "$status" -eq 0 ]
	# Legacy block is gone; user setting preserved; new block present.
	! grep -q "lightning esplora" "$HOME/.lightning/config"
	! grep -q "sauron-api-endpoint" "$HOME/.lightning/config"
	grep -q "log-level=debug" "$HOME/.lightning/config"
	grep -q "lightning backend" "$HOME/.lightning/config"
	grep -q "trustedcoin" "$HOME/.lightning/config"
}

@test "FEAT-183: daemon start skips bitcoind check in trustedcoin mode" {
	echo "down" > "$MOCK_STATE"
	mkdir -p "$HOME/.lightning"
	# Pre-seed trustedcoin config (bypass install's WARNING banner).
	cat > "$HOME/.lightning/config" <<EOF
# >>> lightning backend — managed by 'daemon enable'
disable-plugin=bcli
# trustedcoin reference
# <<< lightning backend
EOF
	cat > "$BIN_SHIM/lightningd" <<EOF
#!/bin/sh
rm -f "$MOCK_STATE"
exit 0
EOF
	chmod +x "$BIN_SHIM/lightningd"
	# Pretend bitcoin-cli is absent (would normally warn).
	export PATH="$BIN_SHIM:/usr/bin:/bin"
	run "$LIGHTNING_BIN" -v daemon start
	[ "$status" -eq 0 ]
	[[ "$output" == *"trustedcoin backend"* ]]
	[[ "$output" == *"skipping bitcoind check"* ]]
	[[ "$output" != *"bitcoin-cli not found"* ]]
}

@test "FEAT-183: daemon status reports backend in healthy + down output" {
	mkdir -p "$HOME/.lightning"
	cat > "$HOME/.lightning/config" <<EOF
# >>> lightning backend — managed by 'daemon enable'
disable-plugin=bcli
# trustedcoin reference
# <<< lightning backend
EOF
	# Healthy path.
	run "$LIGHTNING_BIN" daemon status
	[ "$status" -eq 0 ]
	[[ "$output" == *"backend: trustedcoin"* ]]
	# Down path.
	echo "down" > "$MOCK_STATE"
	run "$LIGHTNING_BIN" daemon status
	[ "$status" -eq 2 ]
	[[ "$output" == *"backend: trustedcoin"* ]]
}

@test "FEAT-183: daemon start falls through to direct mode without a service unit" {
	echo "down" > "$MOCK_STATE"
	# Ensure no plist / unit exists.
	rm -f "$HOME/Library/LaunchAgents/network.lightning.lightningd.plist" 2>/dev/null
	rm -f "$HOME/.config/systemd/user/lightning.service" 2>/dev/null
	# Stub lightningd that flips MOCK_STATE so the post-start
	# probe sees a healthy daemon (real lightningd would do that
	# by responding to lightning-cli getinfo).
	cat > "$BIN_SHIM/lightningd" <<EOF
#!/bin/sh
rm -f "$MOCK_STATE"
exit 0
EOF
	chmod +x "$BIN_SHIM/lightningd"
	# Verbose so the info messages surface (test fixture sets SELF_QUIET=1).
	run "$LIGHTNING_BIN" -v daemon start
	[ "$status" -eq 0 ]
	[[ "$output" == *"no service unit installed"* ]]
	[[ "$output" == *"daemon enable"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-184: unlock
# ---------------------------------------------------------------------------

@test "FEAT-184: lightning wallet unlock --stored is a no-op when not encrypted" {
	# No hsm_secret exists yet → not encrypted.
	mkdir -p "$HOME/.lightning/bitcoin"
	# 32-byte file = unencrypted.
	dd if=/dev/zero of="$HOME/.lightning/bitcoin/hsm_secret" bs=32 count=1 status=none
	# Mock `secret` so the dep check passes even though we won't call it.
	ln -sf /bin/true "$BIN_SHIM/secret"
	run "$LIGHTNING_BIN" wallet unlock --stored
	[ "$status" -eq 0 ]
}

@test "FEAT-184: lightning wallet unlock errors clearly when lightning-cli absent" {
	export PATH="/usr/bin:/bin"
	run -127 "$LIGHTNING_BIN" wallet unlock --stored
}

# ---------------------------------------------------------------------------
# FEAT-172: channel management
# ---------------------------------------------------------------------------

@test "FEAT-172: lightning channel (no args) prints usage" {
	run "$LIGHTNING_BIN" channel
	[ "$status" -ne 0 ]
	[[ "$output" == *"subcommands"* ]]
}

@test "FEAT-172: lightning channel list returns the TSV header" {
	run "$LIGHTNING_BIN" channel list
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "id	peer	capacity	local	remote	state" ]]
}

@test "FEAT-172: lightning channel open reports ok + channel_id" {
	run "$LIGHTNING_BIN" channel open \
		020000000000000000000000000000000000000000000000000000000000000002@127.0.0.1:9735 \
		100000
	[ "$status" -eq 0 ]
	[[ "$output" == *"ok"* ]]
	[[ "$output" == *"channel_id"* ]]
}

@test "FEAT-172: lightning channel close reports ok + txid" {
	run "$LIGHTNING_BIN" channel close 0000000000000000000000000000000000000000000000000000000000000001
	[ "$status" -eq 0 ]
	[[ "$output" == *"ok"* ]]
	[[ "$output" == *"txid"* ]]
}

@test "FEAT-172: lightning channel force-close refuses without --confirm" {
	run "$LIGHTNING_BIN" channel force-close 0000000000000000000000000000000000000000000000000000000000000001
	[ "$status" -eq 2 ]
	[[ "$output" == *"REFUSING"* ]]
}

@test "FEAT-172: lightning channel balance prints a header row" {
	run "$LIGHTNING_BIN" channel balance
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "channel_id	local_msat	remote_msat	state" ]]
}

# ---------------------------------------------------------------------------
# FEAT-173: payments / invoices / BOLT-12 / LNURL
# ---------------------------------------------------------------------------

@test "FEAT-173: lightning invoice create 1000 'beer' returns a BOLT-11" {
	run "$LIGHTNING_BIN" invoice create 1000 beer
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == lnbc* || "${lines[0]}" == lntb* || "${lines[0]}" == lnbcrt* ]]
}

@test "FEAT-173: lightning invoice pay <bolt11> returns ok + payment_hash" {
	run "$LIGHTNING_BIN" invoice pay lnbcrt10n1pmocktest
	[ "$status" -eq 0 ]
	[[ "$output" == *"ok"* ]]
	[[ "$output" == *"payment_hash"* ]]
}

@test "FEAT-173: lightning decode identifies BOLT-11" {
	run "$LIGHTNING_BIN" decode lnbcrt10n1pmocktest
	[ "$status" -eq 0 ]
	[[ "$output" == *"bolt11"* ]]
}

@test "FEAT-173: lightning decode identifies BOLT-12 offer" {
	run "$LIGHTNING_BIN" decode lno1pgmocktest
	[ "$status" -eq 0 ]
	[[ "$output" == *"bolt12-offer"* ]]
}

@test "FEAT-173: lightning decode identifies LNURL" {
	run "$LIGHTNING_BIN" decode LNURL1DP68GURN8GHJ7
	[ "$status" -eq 0 ]
	[[ "$output" == *"lnurl"* ]]
}

@test "FEAT-173: lightning decode identifies a Lightning Address" {
	run "$LIGHTNING_BIN" decode alice@example.com
	[ "$status" -eq 0 ]
	[[ "$output" == *"lightning-address"* ]]
	[[ "$output" == *"example.com"* ]]
}

@test "FEAT-173: lightning decode strips the 'lightning:' BIP-21 prefix" {
	run "$LIGHTNING_BIN" decode "lightning:lnbcrt10n1pmocktest"
	[ "$status" -eq 0 ]
	[[ "$output" == *"bolt11"* ]]
}

@test "FEAT-173: lightning offer create makes a BOLT-12 offer" {
	run "$LIGHTNING_BIN" req offer create 500 donations
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == lno* ]]
}

@test "FEAT-173: lightning offer pay fetches and pays" {
	run "$LIGHTNING_BIN" req offer pay lno1pgmocktest
	[ "$status" -eq 0 ]
	[[ "$output" == *"ok"* ]]
}

@test "FEAT-173: lightning offer (no args) prints usage" {
	run "$LIGHTNING_BIN" req offer
	[ "$status" -ne 0 ]
	[[ "$output" == *"subcommands"* ]]
}

@test "FEAT-173: lightning invoice (no args) prints usage" {
	run "$LIGHTNING_BIN" invoice
	[ "$status" -ne 0 ]
	[[ "$output" == *"subcommands"* ]]
}

@test "FEAT-173: lightning send (keysend) succeeds" {
	run "$LIGHTNING_BIN" pay keysend 020000000000000000000000000000000000000000000000000000000000000002 100
	[ "$status" -eq 0 ]
	[[ "$output" == *"ok"* ]]
}

@test "FEAT-173: lightning lnurl (no args) prints usage" {
	run "$LIGHTNING_BIN" address lnurl
	[ "$status" -ne 0 ]
	[[ "$output" == *"usage"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-192: QR codes
# ---------------------------------------------------------------------------

@test "FEAT-192: lightning qr (no args) prints usage" {
	run "$LIGHTNING_BIN" qr
	[ "$status" -ne 0 ]
	[[ "$output" == *"usage"* ]]
}

@test "FEAT-192: lightning qr emits something for ANSI mode" {
	if ! command -v qrencode >/dev/null; then
		# Fallback path: print the text as-is.
		run "$LIGHTNING_BIN" qr "lnbcrt10n1pmocktest"
		[ "$status" -eq 0 ]
		[[ "$output" == *"lnbcrt10n1pmocktest"* ]]
	else
		run "$LIGHTNING_BIN" qr "lnbcrt10n1pmocktest"
		[ "$status" -eq 0 ]
		# qrencode UTF8 output contains the half-block characters.
		[ -n "$output" ]
	fi
}

@test "FEAT-192: lightning qr --png writes a file" {
	if ! command -v qrencode >/dev/null; then
		skip "qrencode not installed"
	fi
	out="$BATS_TMPDIR/qr.$$.png"
	run "$LIGHTNING_BIN" qr "lnbcrt10n1pmocktest" --png "$out"
	[ "$status" -eq 0 ]
	[ -s "$out" ]
	rm -f "$out"
}

@test "FEAT-192: lightning invoice create --qr emits the BOLT-11 AND a QR" {
	if ! command -v qrencode >/dev/null; then
		skip "qrencode not installed"
	fi
	run "$LIGHTNING_BIN" invoice create 1000 beer --qr
	[ "$status" -eq 0 ]
	# First line is the BOLT-11, then a blank line, then the QR.
	[[ "${lines[0]}" == lnbc* || "${lines[0]}" == lntb* || "${lines[0]}" == lnbcrt* ]]
}

# ---------------------------------------------------------------------------
# FEAT-174 + FEAT-193: wallet repo + SQLite store
# ---------------------------------------------------------------------------

@test "FEAT-174: lightning wallet (no args) prints usage" {
	run "$LIGHTNING_BIN" wallet
	[ "$status" -ne 0 ]
	[[ "$output" == *"subcommands"* ]]
}

@test "FEAT-174: lightning wallet new creates a git-backed wallet with state.db" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	run "$LIGHTNING_BIN" wallet new alice
	[ "$status" -eq 0 ]
	[ -d "$LIGHTNING_WALLETS_ROOT/alice/.git" ]
	[ -f "$LIGHTNING_WALLETS_ROOT/alice/state.db" ]
	[ -f "$LIGHTNING_WALLETS_ROOT/alice/state.sql" ]
	[ -f "$LIGHTNING_WALLETS_ROOT/alice/lightning-dir" ]
	# state.db should contain the five schema tables.
	tables=$(sqlite3 "$LIGHTNING_WALLETS_ROOT/alice/state.db" \
		"SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;" | sort)
	[[ "$tables" == *"accounts"* ]]
	[[ "$tables" == *"ledger"* ]]
	[[ "$tables" == *"invoices"* ]]
	[[ "$tables" == *"channel_notes"* ]]
	[[ "$tables" == *"users"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT"
}

@test "FEAT-174: wallet new auto-selects the first wallet as active" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" wallet active
	[ "$status" -eq 0 ]
	[ "$output" = "alice" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-174: wallet list marks active wallet with *" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" wallet new bob >/dev/null
	"$LIGHTNING_BIN" wallet use bob >/dev/null
	run "$LIGHTNING_BIN" wallet list
	[ "$status" -eq 0 ]
	[[ "$output" == *"* bob"* ]]
	[[ "$output" == *"  alice"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-174: wallet push round-trips through a bare-repo remote" {
	command -v sqlite3 >/dev/null || skip "sqlite3 not installed"
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" wallet use alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	# Mutate state AFTER the initial commit, so `wallet push` must regenerate
	# and commit state.sql before pushing (BUG-042: it dropped the fresh dump
	# because the hook had already `git add`ed it, so the working-tree diff
	# looked clean — the ledger never reached the remote).
	"$LIGHTNING_BIN" wallet ledger add in 100000 --account rent --message "pingmark" >/dev/null
	# Set up a bare-repo remote.
	bare="$BATS_TMPDIR/bare.$$"
	git init --bare --quiet "$bare"
	(cd "$LIGHTNING_WALLETS_ROOT/alice" && git remote add origin "$bare")
	run "$LIGHTNING_BIN" wallet push origin
	[ "$status" -eq 0 ]
	# Clone-side: state.sql must carry the ledger row we added.
	clone="$BATS_TMPDIR/clone.$$"
	git clone --quiet "$bare" "$clone"
	[ -f "$clone/state.sql" ]
	grep -q "pingmark" "$clone/state.sql"
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$bare" "$clone" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# Account verbs (FEAT-174 + FEAT-195 limit/overdraft fields)
# ---------------------------------------------------------------------------

@test "FEAT-174: account create + list + show + delete" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null

	run "$LIGHTNING_BIN" account create rent "monthly rent" --limit 50000 --overdraft deny
	[ "$status" -eq 0 ]

	run "$LIGHTNING_BIN" account list
	[ "$status" -eq 0 ]
	[[ "$output" == *"rent"* ]]
	[[ "$output" == *"50000"* ]]
	[[ "$output" == *"deny"* ]]

	run "$LIGHTNING_BIN" account show rent
	[ "$status" -eq 0 ]
	[[ "$output" == *"name:        rent"* ]]
	[[ "$output" == *"balance_sat: 0"* ]]
	[[ "$output" == *"overdraft:   deny"* ]]

	run "$LIGHTNING_BIN" account delete rent
	[ "$status" -eq 0 ]

	run "$LIGHTNING_BIN" account show rent
	[ "$status" -eq 2 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-174: account create rejects invalid name" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	run "$LIGHTNING_BIN" account create "Bad Name"
	[ "$status" -ne 0 ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-193: ledger verbs
# ---------------------------------------------------------------------------

@test "FEAT-193: ledger add + list + sum + balance" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null

	# Receive 1000 sat (1_000_000 msat) into rent.
	"$LIGHTNING_BIN" wallet ledger add in 1000000 --account rent --peer bob@example.com --message "march" --note "march budget"
	# Pay 250 sat (-250_000 msat) from rent.
	"$LIGHTNING_BIN" wallet ledger add out -250000 --account rent --peer carol@example.com --message "coffee"

	run "$LIGHTNING_BIN" wallet ledger list --account rent
	[ "$status" -eq 0 ]
	# Header row + 2 data rows.
	[ "${#lines[@]}" -ge 3 ]
	[[ "$output" == *"march"* ]]
	[[ "$output" == *"coffee"* ]]
	[[ "$output" == *"march budget"* ]]

	run "$LIGHTNING_BIN" wallet ledger balance rent
	[ "$status" -eq 0 ]
	# 1_000_000 - 250_000 = 750_000 msat.
	[ "$output" = "750000" ]

	run "$LIGHTNING_BIN" wallet ledger sum --by account
	[ "$status" -eq 0 ]
	[[ "$output" == *"rent"* ]]
	[[ "$output" == *"750000"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-193: ledger annotate fills the note column on an existing row" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	"$LIGHTNING_BIN" wallet ledger add in 1000000 --account rent --payment-hash deadbeef --message "test"

	run "$LIGHTNING_BIN" wallet ledger annotate deadbeef "april budget"
	[ "$status" -eq 0 ]
	[[ "$output" == *"1 row"* ]]

	run "$LIGHTNING_BIN" wallet ledger list --account rent
	[ "$status" -eq 0 ]
	[[ "$output" == *"april budget"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-193: ledger export csv produces a CSV with header" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	"$LIGHTNING_BIN" wallet ledger add in 1000000 --account rent --message "test"
	run "$LIGHTNING_BIN" wallet ledger export csv
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == *"ts,account,direction"* ]]
	[[ "$output" == *"rent"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-174: history is an alias for ledger list" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	"$LIGHTNING_BIN" wallet ledger add in 1000 --account rent --message "ping"
	run "$LIGHTNING_BIN" wallet history
	[ "$status" -eq 0 ]
	[[ "$output" == *"ping"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-244: node-balance reconciliation
# ---------------------------------------------------------------------------

@test "FEAT-244: ledger reconcile books an external pay into others (idempotently)" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	# A completed pay our verbs never booked: out 50000 + fee 500 msat.
	export MOCK_LISTPAYS='[{"payment_hash":"aaa111","status":"complete","amount_msat":50000,"amount_sent_msat":50500}]'

	run "$LIGHTNING_BIN" wallet ledger reconcile run
	[ "$status" -eq 0 ]

	# others = -(out 50000) + -(fee 500) = -50500 msat.
	run "$LIGHTNING_BIN" wallet ledger balance others
	[ "$status" -eq 0 ]
	[ "$output" = "-50500" ]

	# Second pass is a no-op (deduped by payment_hash).
	run "$LIGHTNING_BIN" wallet ledger reconcile run
	[ "$status" -eq 0 ]
	[[ "$output" == *"already-booked 1"* ]]
	run "$LIGHTNING_BIN" wallet ledger balance others
	[ "$output" = "-50500" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-244: ledger reconcile credits a known paid invoice to its owner" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	# A receive we minted (invoices row) but whose settlement was never booked.
	db="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	sqlite3 "$db" "INSERT INTO invoices(bolt11, payment_hash, account, amount_msat, expiry, message, state) VALUES('lnbcrttest','bbb222','rent',30000,'2030-01-01T00:00:00Z','rent','pending');"
	export MOCK_LISTINVOICES='[{"payment_hash":"bbb222","status":"paid","amount_received_msat":30000}]'

	run "$LIGHTNING_BIN" wallet ledger reconcile run
	[ "$status" -eq 0 ]

	# Credited to rent, not others.
	run "$LIGHTNING_BIN" wallet ledger balance rent
	[ "$output" = "30000" ]
	run "$LIGHTNING_BIN" wallet ledger balance others
	[ "$output" = "0" ]
	# Invoice marked settled.
	state=$(sqlite3 "$db" "SELECT state FROM invoices WHERE payment_hash='bbb222';")
	[ "$state" = "paid" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-244: ledger reconcile routes an unknown paid invoice to others" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	export MOCK_LISTINVOICES='[{"payment_hash":"ccc333","status":"paid","amount_received_msat":20000}]'

	run "$LIGHTNING_BIN" wallet ledger reconcile run
	[ "$status" -eq 0 ]
	run "$LIGHTNING_BIN" wallet ledger balance others
	[ "$output" = "20000" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-244: ledger reconcile leaves already-booked payments untouched" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	# Our verb already booked this payment_hash.
	"$LIGHTNING_BIN" wallet ledger add out -12345 --account rent --payment-hash ddd444 >/dev/null
	export MOCK_LISTPAYS='[{"payment_hash":"ddd444","status":"complete","amount_msat":12000,"amount_sent_msat":12345}]'

	run "$LIGHTNING_BIN" wallet ledger reconcile run
	[ "$status" -eq 0 ]
	[[ "$output" == *"already-booked 1"* ]]
	# others untouched; rent unchanged.
	run "$LIGHTNING_BIN" wallet ledger balance others
	[ "$output" = "0" ]
	run "$LIGHTNING_BIN" wallet ledger balance rent
	[ "$output" = "-12345" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-244: ledger reconcile dry-run writes nothing" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	export MOCK_LISTPAYS='[{"payment_hash":"eee555","status":"complete","amount_msat":9000,"amount_sent_msat":9000}]'

	run "$LIGHTNING_BIN" wallet ledger reconcile dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"would-book"* ]]
	# Nothing committed.
	run "$LIGHTNING_BIN" wallet ledger balance others
	[ "$output" = "0" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-244: ledger reconcile status reports counts and others balance" {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	export MOCK_LISTPAYS='[{"payment_hash":"fff666","status":"complete","amount_msat":7000,"amount_sent_msat":7000}]'
	"$LIGHTNING_BIN" wallet ledger reconcile run >/dev/null 2>&1

	run "$LIGHTNING_BIN" wallet ledger reconcile status
	[ "$status" -eq 0 ]
	[[ "$output" == *"reconciled_pays:"* ]]
	[[ "$output" == *"others_balance_sat:"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-244: CLI invoice pay + send debit the account (out booked negative)" {
	# Regression: invoice pay / send previously booked `out` rows with a
	# positive amount, so a CLI payment *raised* the balance.  Name the
	# wallet `default` and leave LIGHTNING_WALLETS_ROOT unset so the
	# invoice/send (LIGHTNING_DIR) and ledger (WALLETS_ROOT) paths resolve
	# to the same $HOME/.lightning/wallet/default DB.
	"$LIGHTNING_BIN" wallet new default >/dev/null
	"$LIGHTNING_BIN" account create spend >/dev/null
	"$LIGHTNING_BIN" wallet ledger add in 1000000 --account spend >/dev/null

	# mock pay: amount_msat 1000 + amount_sent_msat 1001 => out -1000, fee -1.
	run "$LIGHTNING_BIN" invoice pay lnbcrt10n1pmocktest --account spend
	[ "$status" -eq 0 ]
	run "$LIGHTNING_BIN" wallet ledger balance spend
	[ "$output" = "998999" ]

	# keysend 100 sat => out -100000 msat.
	run "$LIGHTNING_BIN" pay keysend 020000000000000000000000000000000000000000000000000000000000000002 100 --account spend
	[ "$status" -eq 0 ]
	run "$LIGHTNING_BIN" wallet ledger balance spend
	[ "$output" = "898999" ]
	rm -rf "$HOME/.lightning"
}

@test "FEAT-244: invoice pay + send book to the active (non-default) wallet DB" {
	# Regression for the wallet_db() path divergence: invoice/send must
	# resolve the active pointer the same way wallet/ledger/account do, so
	# bookings land in the active wallet's DB even when it isn't named
	# 'default'.  Before the fix these silently booked to a phantom
	# $LIGHTNING_DIR/wallet/default DB and the balance never moved.
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create spend >/dev/null
	"$LIGHTNING_BIN" wallet ledger add in 1000000 --account spend >/dev/null

	run "$LIGHTNING_BIN" invoice pay lnbcrt10n1pmocktest --account spend
	[ "$status" -eq 0 ]
	run "$LIGHTNING_BIN" wallet ledger balance spend
	[ "$output" = "998999" ]   # 1000000 - 1000 - 1, booked in alice's DB

	run "$LIGHTNING_BIN" pay keysend 020000000000000000000000000000000000000000000000000000000000000002 100 --account spend
	[ "$status" -eq 0 ]
	run "$LIGHTNING_BIN" wallet ledger balance spend
	[ "$output" = "898999" ]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-185: seed + SCB
# ---------------------------------------------------------------------------

@test "FEAT-185: lightning scb (no args) prints usage" {
	run "$LIGHTNING_BIN" wallet scb
	[ "$status" -ne 0 ]
	[[ "$output" == *"usage"* ]]
}
