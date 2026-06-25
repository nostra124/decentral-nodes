#!/usr/bin/env bats
#
# FEAT-011 (AC 3 / AC 4) + FEAT-018 (AC 7) — wallet repo merge drivers.
#
# `wallet new` configures three custom git merge drivers:
#   addresses     →  union by row, sorted by index
#   labels/{tx,utxo}  →  last-writer-wins per row (theirs wins on conflict; warn)
#   descriptors   →  hard-conflict (operator must resolve by hand)
# These cases exercise both the internal `_merge` driver (unit-level) and
# the real git merge inside a freshly-created wallet repo (integration).

bats_require_minimum_version 1.5.0

setup() {
	BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
	HOME="$(mktemp -d "$BATS_TMPDIR/home.XXXXXX")"
	unset XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_SHARE_HOME
	export HOME SELF_QUIET=1
	export BITCOIN_BIN="$BATS_TEST_DIRNAME/../../bin/bitcoin-node"
	export SELF_LIBEXEC="$BATS_TEST_DIRNAME/../../libexec"
	# stub `secret` that backs to a per-test store (mirrors setup_wallet_env)
	export SECRET_STORE="$HOME/secret-store"
	mkdir -p "$SECRET_STORE" "$HOME/bin"
	cat > "$HOME/bin/secret" <<-'STUB'
	#!/usr/bin/env bash
	verb="$1"; key="$2"
	store="$SECRET_STORE"
	case "$verb" in
		# wallet new now `secret init <name>` then `secret set <name>/seed`
		# (BUG-047); init is a no-op for the stub, set mirrors put.
		init)     exit 0 ;;
		set|put)  mkdir -p "$store/$(dirname "$key")"; cat > "$store/$key" ;;
		get)      cat "$store/$key" ;;
		*)        exit 1 ;;
	esac
	STUB
	chmod +x "$HOME/bin/secret"
	# bin/ on PATH so libexec plugins find the parent dispatcher;
	# stub secret right after for wallet:new
	export PATH="$BATS_TEST_DIRNAME/../../bin:$HOME/bin:$PATH"
	export XDG_DATA_HOME="$HOME/xdg-data"
	export XDG_SHARE_HOME="$BATS_TEST_DIRNAME/../../share"
	mkdir -p "$XDG_DATA_HOME"
	D="$HOME/merge"
	mkdir -p "$D"
	printf '' > "$D/base"
}
teardown() { rm -rf "$HOME"; }

@test "FEAT-011 AC3 — _merge addresses unions both branches by row, sorted by idx" {
	printf '0\tbc1qaaa\t\n1\tbc1qbbb\t\n' > "$D/A"
	printf '0\tbc1qaaa\t\n2\tbc1qccc\t\n' > "$D/B"
	run "$BITCOIN_BIN" _merge addresses "$D/A" "$D/base" "$D/B"
	[ "$status" -eq 0 ]
	# 3 rows, in idx order, no addresses dropped
	[ "$(wc -l < "$D/A")" -eq 3 ]
	[ "$(awk '{print $2}' "$D/A" | paste -sd,)" = "bc1qaaa,bc1qbbb,bc1qccc" ]
}

@test "FEAT-018 AC7 — _merge labels-lww keeps theirs on conflict and warns" {
	printf 'aaa:0\tfood\nbbb:1\trent\n' > "$D/A"
	printf 'aaa:0\tDINNER\nccc:2\tcoffee\n' > "$D/B"
	run "$BITCOIN_BIN" _merge labels-lww "$D/A" "$D/base" "$D/B"
	[ "$status" -eq 0 ]
	[[ "$output" == *"theirs wins"* ]] || [[ "$stderr" == *"theirs wins"* ]] || \
		run --separate-stderr "$BITCOIN_BIN" _merge labels-lww "$D/A" "$D/base" "$D/B"
	# theirs's DINNER must have won over ours's food
	grep -q '^aaa:0	DINNER' "$D/A"
	grep -q '^bbb:1	rent'    "$D/A"
	grep -q '^ccc:2	coffee'  "$D/A"
}

@test "FEAT-011 AC4 — _merge descriptors-conflict refuses (exit 1)" {
	printf 'wpkh(xpub.../0/*)#abcdefgh\n' > "$D/A"
	printf 'tr(xpub.../0/*)#qrstuvwx\n'   > "$D/B"
	run "$BITCOIN_BIN" _merge descriptors-conflict "$D/A" "$D/base" "$D/B"
	[ "$status" -eq 1 ]
	[[ "$output" == *"manual resolution required"* ]]
}

@test "FEAT-011 — wallet new installs .gitattributes with the three drivers" {
	run "$BITCOIN_BIN" wallet new alice
	[ "$status" -eq 0 ]
	wpath="$XDG_DATA_HOME/bitcoin/wallets/alice"
	[ -f "$wpath/.gitattributes" ]
	grep -q '^addresses\s*merge=bitcoin-addresses-union'      "$wpath/.gitattributes"
	grep -q '^labels/tx\s*merge=bitcoin-labels-lww'           "$wpath/.gitattributes"
	grep -q '^labels/utxo\s*merge=bitcoin-labels-lww'         "$wpath/.gitattributes"
	grep -q '^descriptors\s*merge=bitcoin-descriptors-conflict' "$wpath/.gitattributes"
	# the merge.* driver definitions live in the per-wallet git config
	(cd "$wpath" && git config --get merge.bitcoin-addresses-union.driver \
		| grep -q '_merge addresses %A %O %B')
}

@test "FEAT-011 AC3 — real git merge in a wallet repo unions diverging addresses" {
	# Fresh wallet, then two branches each appending different rows to addresses.
	run "$BITCOIN_BIN" wallet new alice
	[ "$status" -eq 0 ]
	wpath="$XDG_DATA_HOME/bitcoin/wallets/alice"
	cd "$wpath"
	gitw() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
	printf '0\tbc1qaaa\t\n' > addresses; gitw add addresses; gitw commit -q -m base
	gitw checkout -q -b hot
	printf '0\tbc1qaaa\t\n1\tbc1qbbb\t\n' > addresses; gitw add addresses; gitw commit -q -m hot
	gitw checkout -q main
	printf '0\tbc1qaaa\t\n2\tbc1qccc\t\n' > addresses; gitw add addresses; gitw commit -q -m cold
	# Merge — driver must produce a union without conflict markers.
	run gitw merge --no-edit hot
	[ "$status" -eq 0 ]
	! grep -q '<<<<<<<' addresses
	[ "$(wc -l < addresses)" -eq 3 ]
	awk '{print $2}' addresses | grep -q '^bc1qbbb$'
	awk '{print $2}' addresses | grep -q '^bc1qccc$'
}

@test "FEAT-011 AC4 — real git merge refuses on divergent descriptors" {
	run "$BITCOIN_BIN" wallet new alice
	[ "$status" -eq 0 ]
	wpath="$XDG_DATA_HOME/bitcoin/wallets/alice"
	cd "$wpath"
	gitw() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
	printf 'wpkh(xpub.../0/*)#aaaaaaaa\n' > descriptors; gitw add descriptors; gitw commit -q -m base
	gitw checkout -q -b hot
	printf 'wpkh(xpub.../0/*)#hothotho\n' > descriptors; gitw add descriptors; gitw commit -q -m hot
	gitw checkout -q main
	printf 'tr(xpub.../0/*)#coldcold\n'   > descriptors; gitw add descriptors; gitw commit -q -m cold
	run gitw merge --no-edit hot
	[ "$status" -ne 0 ]
}
