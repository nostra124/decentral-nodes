#!/usr/bin/env bats
#
# bitcoin unit tests — part 4 of 5 (FEAT-053 split of tests/unit/bitcoin.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/bitcoin.bash.

bats_require_minimum_version 1.5.0
load lib/bitcoin


@test "FEAT-019 AC#3 / FEAT-048 — make install-skills-user is idempotent across all three agents" {
	fake_home="$(mktemp -d)"
	mkdir -p "$fake_home/.claude/skills"
	mkdir -p "$fake_home/.raven/workspace/skills"
	mkdir -p "$fake_home/.config/opencode/commands"
	repo="$BATS_TEST_DIRNAME/../.."

	# install-skills-user lives in the *generated* Makefile (a build
	# artefact, .gitignored). The unit-CI job runs bats against an
	# unconfigured tree, so skip cleanly there — the same contract the
	# `skip mandoc` and check-vectors paths use (skills/testing.md: a
	# clean signal beats a noisy red). In any configured tree (local
	# dev, or CI that runs ./configure) the full check below runs.
	[ -f "$repo/Makefile" ] || skip "build not configured (no Makefile); run ./configure to exercise install-skills-user"

	dirs="$fake_home/.claude/skills $fake_home/.raven/workspace/skills $fake_home/.config/opencode/commands"

	HOME="$fake_home" make -C "$repo" install-skills-user >/dev/null
	count1="$(find $dirs -maxdepth 1 -type l | wc -l)"

	HOME="$fake_home" make -C "$repo" install-skills-user >/dev/null
	count2="$(find $dirs -maxdepth 1 -type l | wc -l)"

	# Skills are the rpk-native flat files .rpk/skills/<name>.md (BUG-040);
	# the combined stack ships several (bitcoin-* + lightning-*). Each is
	# installed to all three agents, so the expected link count is
	# 3 * (number of skills).
	nskills="$(ls "$repo"/.rpk/skills/*.md 2>/dev/null | wc -l)"

	# bitcoin-wallet specifically must land in each agent, named correctly
	# per agent layout.
	claude_link="$fake_home/.claude/skills/bitcoin-wallet"
	raven_link="$fake_home/.raven/workspace/skills/bitcoin-wallet"
	oc_link="$fake_home/.config/opencode/commands/bitcoin-wallet.md"
	have_links=1
	[ -L "$claude_link" ] || have_links=0
	[ -L "$raven_link" ]  || have_links=0
	[ -L "$oc_link" ]     || have_links=0

	rm -rf "$fake_home"

	[ "$count1" -eq "$count2" ]
	[ "$nskills" -ge 1 ]
	[ "$count1" -eq $((nskills * 3)) ]
	[ "$have_links" -eq 1 ]
}

# ---------------------------------------------------------------------------
# FEAT-012 (extend, 1.17.0) — backend get-address-txs. Fifth verb on
# the backend abstraction; consumed by `wallet index` (FEAT-018).
# ---------------------------------------------------------------------------

@test "FEAT-012 — backend get-address-txs returns the mempool JSON array" {
	setup_backend_env
	curl_fixture "https://mempool.space/api/address/bc1qexample/txs" \
		'[{"txid":"deadbeef","status":{"block_height":830000},"vin":[],"vout":[]}]'
	run "$BITCOIN_BIN" backend get-address-txs bc1qexample
	[ "$status" -eq 0 ]
	[[ "$output" == *'"txid":"deadbeef"'* ]]
}

@test "FEAT-012 — backend get-address-txs requires an address" {
	setup_backend_env
	run "$BITCOIN_BIN" backend get-address-txs
	[ "$status" -ne 0 ]
}

@test "FEAT-012 — backend get-address-txs bitcoind stub returns 'not implemented'" {
	setup_backend_env
	"$BITCOIN_BIN" backend set bitcoind >/dev/null
	run "$BITCOIN_BIN" backend get-address-txs bc1qexample
	[ "$status" -ne 0 ]
}

@test "FEAT-018 — wallet index caches transactions/<txid>.{hex,json}" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/txs" "$(alice_tx_fixture)"
	curl_fixture "https://mempool.space/api/tx/abc123/hex" "0200000001deadbeef"
	run "$BITCOIN_BIN" wallet index alice
	[ "$status" -eq 0 ]
	txdir="$XDG_DATA_HOME/bitcoin/wallets/alice/transactions"
	[ -s "$txdir/abc123.hex" ]
	[ -s "$txdir/abc123.json" ]
	grep -q '"txid": *"abc123"' "$txdir/abc123.json"
}

@test "FEAT-018 — wallet index appends to history with direction + net sats" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/txs" "$(alice_tx_fixture)"
	curl_fixture "https://mempool.space/api/tx/abc123/hex" "0200000001deadbeef"
	"$BITCOIN_BIN" wallet index alice >/dev/null
	run "$BITCOIN_BIN" wallet history alice
	[ "$status" -eq 0 ]
	# One line: txid \t height \t direction \t net_sats
	[ "$output" = $'abc123\t830000\tin\t12345' ]
}

@test "FEAT-018 — wallet index is idempotent (no second commit)" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/txs" "$(alice_tx_fixture)"
	curl_fixture "https://mempool.space/api/tx/abc123/hex" "0200000001deadbeef"
	"$BITCOIN_BIN" wallet index alice >/dev/null
	before="$(cd "$XDG_DATA_HOME/bitcoin/wallets/alice" && git rev-parse HEAD)"
	"$BITCOIN_BIN" wallet index alice >/dev/null
	after="$(cd "$XDG_DATA_HOME/bitcoin/wallets/alice" && git rev-parse HEAD)"
	[ "$before" = "$after" ]
}

@test "FEAT-018 — wallet tx prints the cached hex + json" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/txs" "$(alice_tx_fixture)"
	curl_fixture "https://mempool.space/api/tx/abc123/hex" "0200000001deadbeef"
	"$BITCOIN_BIN" wallet index alice >/dev/null
	run "$BITCOIN_BIN" wallet tx alice abc123
	[ "$status" -eq 0 ]
	[[ "$output" == *"0200000001deadbeef"* ]]
	[[ "$output" == *'"txid"'* ]]
}

@test "FEAT-018 — wallet tx reads from cache without backend access" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/txs" "$(alice_tx_fixture)"
	curl_fixture "https://mempool.space/api/tx/abc123/hex" "0200000001deadbeef"
	"$BITCOIN_BIN" wallet index alice >/dev/null
	# Wipe fixtures: backend would now fail. wallet tx must still work.
	rm -rf "$CURL_STUB_RESPONSES"
	mkdir -p "$CURL_STUB_RESPONSES"
	run "$BITCOIN_BIN" wallet tx alice abc123
	[ "$status" -eq 0 ]
	[[ "$output" == *"abc123"* ]]
}

@test "FEAT-018 — wallet tx rejects an un-indexed txid" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	run "$BITCOIN_BIN" wallet tx alice notindexed
	[ "$status" -ne 0 ]
}

@test "FEAT-018 — wallet index rejects a missing wallet" {
	setup_wallet_derive_env
	run "$BITCOIN_BIN" wallet index no-such-wallet
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-026 — descriptor derive + descriptor wallet. wpkh() since 1.18.0;
# pkh + sh(wpkh) since 1.20.0; tr + combo since 1.26.0 (FEAT-026 closed
# alongside FEAT-007 Taproot). multi() / sortedmulti() remain deferred.
# ---------------------------------------------------------------------------

@test "FEAT-026 — descriptor wallet emits a checksummed wpkh() descriptor" {
	setup_wallet_derive_env
	run "$BITCOIN_BIN" descriptor wallet alice
	[ "$status" -eq 0 ]
	# Shape: wpkh(<xpub>/0/*)#<8-char checksum>
	[[ "$output" =~ ^wpkh\(xpub[0-9A-Za-z]+/0/\*\)#[a-z0-9]{8}$ ]]
	# And descriptor verify accepts what wallet emits.
	run "$BITCOIN_BIN" bip380 verify "$output"
	[ "$status" -eq 0 ]
}

@test "FEAT-026 — descriptor wallet rejects a missing wallet" {
	setup_wallet_derive_env
	run "$BITCOIN_BIN" descriptor wallet no-such-wallet
	[ "$status" -ne 0 ]
}

@test "FEAT-026 — descriptor derive reproduces wallet derive on the abandon-mnemonic vector" {
	setup_wallet_derive_env
	desc="$("$BITCOIN_BIN" descriptor wallet alice)"
	run "$BITCOIN_BIN" bip380 derive "$desc" 0
	[ "$status" -eq 0 ]
	# Canonical BIP-84 first-receive address for the abandon mnemonic.
	[ "$output" = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu" ]
}

@test "FEAT-026 — descriptor derive walks the index forward to match consecutive wallet derives" {
	setup_wallet_derive_env
	desc="$("$BITCOIN_BIN" descriptor wallet alice)"
	# Compare descriptor derive against wallet derive for indices 0, 1, 2.
	for i in 0 1 2; do
		expected="$("$BITCOIN_BIN" wallet derive alice)"
		got="$("$BITCOIN_BIN" bip380 derive "$desc" "$i")"
		[ "$got" = "$expected" ]
	done
}

@test "FEAT-026 — descriptor derive: tr() and combo() succeed (shipped in 1.26.0)" {
	# Replaces the 1.18.0 'tr/combo not-yet-implemented' assertion.
	# Positive coverage: bip-86 vector cross-checked in
	# tests/unit/descriptor-tr.bats.
	setup_wallet_derive_env
	body="$(alice_xpub_path)"
	for fn in tr combo; do
		run "$BITCOIN_BIN" bip380 derive "${fn}($body)" 0
		[ "$status" -eq 0 ]
		[ -n "$output" ]
	done
}

@test "FEAT-026 — descriptor derive rejects malformed input" {
	setup_wallet_derive_env
	# No '*' placeholder.
	desc="$("$BITCOIN_BIN" descriptor wallet alice)"
	# Strip the '/*' to leave a non-instantiable path.
	bad="${desc/\/\*/}"
	run "$BITCOIN_BIN" bip380 derive "$bad" 0
	[ "$status" -ne 0 ]
	# Empty descriptor.
	run "$BITCOIN_BIN" bip380 derive "" 0
	[ "$status" -ne 0 ]
	# Non-numeric index.
	run "$BITCOIN_BIN" bip380 derive "$desc" notanint
	[ "$status" -ne 0 ]
}

@test "FEAT-026 — descriptor derive rejects a descriptor with a bad checksum" {
	setup_wallet_derive_env
	desc="$("$BITCOIN_BIN" descriptor wallet alice)"
	# Flip one character of the checksum.
	bad="${desc:0: ${#desc}-1}q"
	run "$BITCOIN_BIN" bip380 derive "$bad" 0
	[ "$status" -ne 0 ]
}

@test "FEAT-026 — descriptor help mentions derive and wallet" {
	run "$BITCOIN_BIN" descriptor help
	[ "$status" -eq 0 ]
	[[ "$output" == *"derive"* ]]
	[[ "$output" == *"wallet"* ]]
}

@test "FEAT-026 — descriptor derive pkh() produces a legacy P2PKH '1...' address" {
	setup_wallet_derive_env
	body="$(alice_xpub_path)"
	run "$BITCOIN_BIN" bip380 derive "pkh($body)" 0
	[ "$status" -eq 0 ]
	# Cross-verified vector for the abandon mnemonic / BIP-84 idx 0.
	[ "$output" = "1JaUQDVNRdhfNsVncGkXedaPSM5Gc54Hso" ]
	# Structural: leading '1', base58 charset, sensible length.
	[[ "$output" =~ ^1[1-9A-HJ-NP-Za-km-z]{25,33}$ ]]
}

@test "FEAT-026 — descriptor derive sh(wpkh()) produces a P2SH '3...' nested-segwit address" {
	setup_wallet_derive_env
	body="$(alice_xpub_path)"
	run "$BITCOIN_BIN" bip380 derive "sh(wpkh($body))" 0
	[ "$status" -eq 0 ]
	# Cross-verified vector.
	[ "$output" = "3GtVZYzsKF6Feikdjd4bDyPdAiyeHANY9b" ]
	[[ "$output" =~ ^3[1-9A-HJ-NP-Za-km-z]{25,33}$ ]]
}

@test "FEAT-026 — descriptor derive walks indices forward for both new functions" {
	setup_wallet_derive_env
	body="$(alice_xpub_path)"
	# Distinct addresses across indices — the same pubkey can't appear
	# twice unless derivation is broken.
	pkh_0="$("$BITCOIN_BIN" bip380 derive "pkh($body)" 0)"
	pkh_1="$("$BITCOIN_BIN" bip380 derive "pkh($body)" 1)"
	[ "$pkh_0" != "$pkh_1" ]
	sh_0="$("$BITCOIN_BIN" bip380 derive "sh(wpkh($body))" 0)"
	sh_1="$("$BITCOIN_BIN" bip380 derive "sh(wpkh($body))" 1)"
	[ "$sh_0" != "$sh_1" ]
	# And the three function families never collide on the same index.
	wpkh_0="$("$BITCOIN_BIN" bip380 derive "wpkh($body)" 0)"
	[ "$pkh_0" != "$sh_0" ]
	[ "$pkh_0" != "$wpkh_0" ]
	[ "$sh_0"  != "$wpkh_0" ]
}

@test "FEAT-026 — sh(<non-wpkh>) returns 'not yet implemented'" {
	setup_wallet_derive_env
	body="$(alice_xpub_path)"
	# sh(pkh(...)) is a valid BIP-380 descriptor; we just don't ship it.
	run "$BITCOIN_BIN" bip380 derive "sh(pkh($body))" 0
	[ "$status" -ne 0 ]
	[[ "$output" == *"not yet implemented"* ]] || [[ "$stderr" == *"not yet implemented"* ]]
}

@test "FEAT-026 — pkh and sh(wpkh) round-trip through a verified checksum" {
	setup_wallet_derive_env
	body="$(alice_xpub_path)"
	# Slap a checksum on each new-style descriptor and confirm derive
	# accepts the checksummed form.
	for d in "pkh($body)" "sh(wpkh($body))"; do
		cs="$("$BITCOIN_BIN" bip380 checksum "$d")"
		run "$BITCOIN_BIN" bip380 verify "$cs"
		[ "$status" -eq 0 ]
		run "$BITCOIN_BIN" bip380 derive "$cs" 0
		[ "$status" -eq 0 ]
	done
}

@test "FEAT-026 — pkh / sh(wpkh) reject malformed input" {
	setup_wallet_derive_env
	# No '*' placeholder.
	body="$(alice_xpub_path)"
	bad="${body/\/\*/}"
	run "$BITCOIN_BIN" bip380 derive "pkh($bad)" 0
	[ "$status" -ne 0 ]
	run "$BITCOIN_BIN" bip380 derive "sh(wpkh($bad))" 0
	[ "$status" -ne 0 ]
	# Bare key (no '/path').
	run "$BITCOIN_BIN" bip380 derive "pkh(xpubBareKey)" 0
	[ "$status" -ne 0 ]
}

@test "FEAT-018 — wallet label tx writes to labels/tx and commits" {
	setup_indexed_alice
	run "$BITCOIN_BIN" wallet label tx alice abc123 "rent payment"
	[ "$status" -eq 0 ]
	labels="$XDG_DATA_HOME/bitcoin/wallets/alice/labels/tx"
	[ -s "$labels" ]
	grep -q $'^abc123\trent payment$' "$labels"
}

@test "FEAT-018 — wallet label utxo writes to labels/utxo" {
	setup_indexed_alice
	run "$BITCOIN_BIN" wallet label utxo alice abc123:0 "faucet money"
	[ "$status" -eq 0 ]
	labels="$XDG_DATA_HOME/bitcoin/wallets/alice/labels/utxo"
	[ -s "$labels" ]
	grep -q $'^abc123:0\tfaucet money$' "$labels"
}

@test "FEAT-018 — wallet label utxo rejects a malformed <txid:vout> key" {
	setup_indexed_alice
	run "$BITCOIN_BIN" wallet label utxo alice "not-a-utxo-key" "foo"
	[ "$status" -ne 0 ]
}

@test "FEAT-018 — empty <text> clears the label" {
	setup_indexed_alice
	"$BITCOIN_BIN" wallet label tx alice abc123 "rent payment" >/dev/null
	run "$BITCOIN_BIN" wallet label tx alice abc123 ""
	[ "$status" -eq 0 ]
	labels="$XDG_DATA_HOME/bitcoin/wallets/alice/labels/tx"
	# File still exists but is empty (no row for abc123).
	! grep -q '^abc123' "$labels"
}

@test "FEAT-018 — labels reject tabs and newlines in <text>" {
	setup_indexed_alice
	run "$BITCOIN_BIN" wallet label tx alice abc123 $'has\ttab'
	[ "$status" -ne 0 ]
}

@test "FEAT-018 — backward-compat: wallet label <name> <addr> <text> still works" {
	# Pre-1.19.0 callers don't pass a <kind>; the 3-arg form must
	# continue to write to the addresses ledger.
	setup_indexed_alice
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	run "$BITCOIN_BIN" wallet label alice "$addr" "compat label"
	[ "$status" -eq 0 ]
	grep -q "compat label" "$XDG_DATA_HOME/bitcoin/wallets/alice/addresses"
}

@test "FEAT-018 — wallet history --label filters by case-insensitive substring" {
	setup_indexed_alice
	"$BITCOIN_BIN" wallet label tx alice abc123 "Rent Payment" >/dev/null
	run "$BITCOIN_BIN" wallet history alice --label rent
	[ "$status" -eq 0 ]
	[[ "$output" == *"abc123"* ]]
	# A non-matching pattern returns nothing.
	run "$BITCOIN_BIN" wallet history alice --label groceries
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "FEAT-018 — wallet history --label requires a pattern argument" {
	setup_indexed_alice
	run "$BITCOIN_BIN" wallet history alice --label
	[ "$status" -ne 0 ]
}

@test "FEAT-018 — wallet tx emits a labels section when annotated" {
	setup_indexed_alice
	"$BITCOIN_BIN" wallet label tx   alice abc123   "rent payment" >/dev/null
	"$BITCOIN_BIN" wallet label utxo alice abc123:0 "faucet money" >/dev/null
	run "$BITCOIN_BIN" wallet tx alice abc123
	[ "$status" -eq 0 ]
	[[ "$output" == *"=== labels ==="* ]]
	[[ "$output" == *"rent payment"* ]]
	[[ "$output" == *"faucet money"* ]]
}

@test "FEAT-018 — wallet tx omits the labels section when there are none" {
	setup_indexed_alice
	run "$BITCOIN_BIN" wallet tx alice abc123
	[ "$status" -eq 0 ]
	[[ "$output" != *"=== labels ==="* ]]
}

# ---------------------------------------------------------------------------
# FEAT-038: tax-label vocabulary. Extends `wallet label` with a
# closed 13-category taxonomy and a `--free-text` escape hatch.
# Adds `wallet label --show` / `--validate` and the `tax label
# --as` shorthand.
# ---------------------------------------------------------------------------

@test "FEAT-038 — wallet label --tax persists the category" {
	setup_indexed_alice
	run "$BITCOIN_BIN" wallet label alice abc123:0 --tax income
	[ "$status" -eq 0 ]
	labels="$XDG_DATA_HOME/bitcoin/wallets/alice/labels/utxo"
	[ -s "$labels" ]
	# 3-column TSV: key TAB tax_category TAB note
	grep -qE $'^abc123:0\tincome\t' "$labels"
}

@test "FEAT-038 — wallet label --tax rejects a category not in the closed set" {
	setup_indexed_alice
	run "$BITCOIN_BIN" wallet label alice abc123:0 --tax not-a-real-category
	[ "$status" -ne 0 ]
	# Error message should list the valid set so users can see the closed taxonomy.
	[[ "$output" == *"income"* ]]
	[[ "$output" == *"self-transfer"* ]]
	[[ "$output" == *"channel-close"* ]]
}

@test "FEAT-038 — wallet label --tax with --note stores both" {
	setup_indexed_alice
	"$BITCOIN_BIN" wallet label alice abc123:0 --tax purchase --note "kraken Q1" >/dev/null
	labels="$XDG_DATA_HOME/bitcoin/wallets/alice/labels/utxo"
	grep -qE $'^abc123:0\tpurchase\tkraken Q1$' "$labels"
}

@test "FEAT-038 — wallet label --tax infers tx kind from a 64-hex-char outpoint" {
	setup_indexed_alice
	txid="abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
	"$BITCOIN_BIN" wallet label alice "$txid" --tax sale >/dev/null
	tx_labels="$XDG_DATA_HOME/bitcoin/wallets/alice/labels/tx"
	grep -qE "^${txid}"$'\tsale\t' "$tx_labels"
}

@test "FEAT-038 — wallet label --show <outpoint> reads back what --tax wrote" {
	setup_indexed_alice
	"$BITCOIN_BIN" wallet label alice abc123:0 --tax gift-in --note "from B" >/dev/null
	run "$BITCOIN_BIN" wallet label alice --show abc123:0
	[ "$status" -eq 0 ]
	[[ "$output" == *"utxo"*"abc123:0"*"gift-in"*"from B"* ]]
}

@test "FEAT-038 — wallet label --show with no outpoint dumps every row" {
	setup_indexed_alice
	"$BITCOIN_BIN" wallet label alice abc123:0 --tax income >/dev/null
	"$BITCOIN_BIN" wallet label alice abc123:1 --tax fee >/dev/null
	run "$BITCOIN_BIN" wallet label alice --show
	[ "$status" -eq 0 ]
	[[ "$output" == *"income"* ]]
	[[ "$output" == *"fee"* ]]
}

@test "FEAT-038 — wallet label --validate exits 0 when every row has a tax category" {
	setup_indexed_alice
	"$BITCOIN_BIN" wallet label alice abc123:0 --tax income >/dev/null
	run "$BITCOIN_BIN" wallet label alice --validate
	[ "$status" -eq 0 ]
}

@test "FEAT-038 — wallet label --validate exits non-zero when an unlabeled row exists" {
	setup_indexed_alice
	# Free-text label has no tax category → should fail validation.
	"$BITCOIN_BIN" wallet label alice abc123:0 --free-text "raw note" >/dev/null
	run "$BITCOIN_BIN" wallet label alice --validate
	[ "$status" -ne 0 ]
	[[ "$output" == *"abc123:0"* ]]
}

@test "FEAT-038 — wallet label --free-text behaves like the legacy free-text path" {
	setup_indexed_alice
	"$BITCOIN_BIN" wallet label alice abc123:0 --free-text "rent payment" >/dev/null
	labels="$XDG_DATA_HOME/bitcoin/wallets/alice/labels/utxo"
	# 2-column TSV: key TAB text. (FEAT-038 keeps the legacy storage
	# shape for the free-text path; only --tax callers emit 3 cols.)
	grep -qE $'^abc123:0\trent payment$' "$labels"
}

@test "FEAT-038 — tax label --as is byte-identical to wallet label --tax" {
	setup_indexed_alice
	"$BITCOIN_BIN" tax label alice abc123:0 --as income >/dev/null
	labels1="$(cat "$XDG_DATA_HOME/bitcoin/wallets/alice/labels/utxo")"
	"$BITCOIN_BIN" wallet label alice abc123:0 --tax income >/dev/null
	labels2="$(cat "$XDG_DATA_HOME/bitcoin/wallets/alice/labels/utxo")"
	[ "$labels1" = "$labels2" ]
}

@test "FEAT-038 — tax help mentions every category" {
	run "$BITCOIN_BIN" tax help
	[ "$status" -eq 0 ]
	for cat in self-transfer income gift-in gift-out purchase sale spend fee \
	           lending-out lending-in loss-claim channel-open channel-close; do
		[[ "$output" == *"$cat"* ]] || { echo "missing category: $cat"; return 1; }
	done
}

@test "FEAT-038 — push round-trips the new tax_category column" {
	setup_indexed_alice
	"$BITCOIN_BIN" wallet label alice abc123:0 --tax purchase >/dev/null
	# A label change commits to the wallet's git repo.
	committed=$(git -C "$XDG_DATA_HOME/bitcoin/wallets/alice" log --oneline -n 1 -- labels/utxo)
	[ -n "$committed" ]
	# And the committed file has the 3-col shape.
	git -C "$XDG_DATA_HOME/bitcoin/wallets/alice" show "HEAD:labels/utxo" \
		| grep -qE $'^abc123:0\tpurchase\t'
}
