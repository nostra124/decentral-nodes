#!/usr/bin/env bats
#
# BUG-056 regression: the unit suites must reference the current `-node`
# dispatcher names, not the pre-rename `bin/<cmd>` paths removed by
# commit e732c2b. Invoking a removed path makes bats fail with exit 127
# ("command not found"), which is what reddened the merge gate.
#
# This guard fails while any test still hard-codes a bare pre-rename
# dispatcher path, and proves each renamed dispatcher actually runs.

setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# Bare pre-rename dispatcher references: `bin/<cmd>` NOT followed by '-'
# (which would be the new `-node` name) and NOT followed by an alnum
# (which would be `bitcoind` / `bitcoin-cli` / `lightningd`).
@test "BUG-056: no tests/unit suite references a pre-rename bin/<cmd> path" {
	# Functional references only — bats comment lines (e.g. historical
	# "moved from bin/bitcoin" notes) are not invocations and are exempt.
	local hits
	hits="$(grep -rnE 'bin/(bitcoin|lightning|monero|fulcrum|liquid|stacks)([^-a-zA-Z0-9]|$)' \
		--include='*.bats' "$BATS_TEST_DIRNAME" \
		| grep -vE ':[0-9]+:[[:space:]]*#' || true)"
	if [ -n "$hits" ]; then
		echo "stale pre-rename dispatcher paths still present:" >&2
		echo "$hits" >&2
		return 1
	fi
}

@test "BUG-056: no tests/unit suite sources a pre-rename libexec/<cmd>/ verb" {
	# Catches sibling/source refs like $SELF_LIBEXEC/bitcoin/bip174, including
	# the bash-quoting variant ($SELF_LIBEXEC"'/bitcoin/bip174). Data dirs
	# ($XDG_*/bitcoin/wallets, $LIGHTNING_DIR/bitcoin/config) are not libexec
	# and are matched by the LIBEXEC-prefixed anchor only.
	local hits
	hits="$(grep -rnE '(SELF_LIBEXEC|libexec)["'\''[:space:]]*/(bitcoin|lightning|monero|fulcrum|liquid|stacks)/' \
		--include='*.bats' "$BATS_TEST_DIRNAME" \
		| grep -vE '\-node/' | grep -vE ':[0-9]+:[[:space:]]*#' || true)"
	if [ -n "$hits" ]; then
		echo "stale pre-rename libexec verb refs still present:" >&2
		echo "$hits" >&2
		return 1
	fi
}

@test "FEAT-314: every bin/*-node has a unit suite" {
	# A node is covered by tests/unit/<node>.bats, by its base-name suite
	# (bitcoin-node -> bitcoin.bats, lightning-node -> lightning.bats,
	# fulcrum/monero likewise), or — since FEAT-053 split the monolithic
	# suites — by numbered parts <base>-NN.bats / <node>-NN.bats.
	local path node base fail=0
	shopt -s nullglob
	for path in "$REPO"/bin/*-node; do
		node="$(basename "$path")"
		base="${node%-node}"
		local -a suites=(
			"$BATS_TEST_DIRNAME/$node.bats"
			"$BATS_TEST_DIRNAME/$base.bats"
			"$BATS_TEST_DIRNAME/$base"-[0-9][0-9].bats
			"$BATS_TEST_DIRNAME/$node"-[0-9][0-9].bats
		)
		local found=0 s
		for s in "${suites[@]}"; do [ -f "$s" ] && found=1; done
		if [ "$found" -eq 0 ]; then
			echo "no unit suite for $node (expected $node.bats, $base.bats, or $base-NN.bats)"; fail=1
		fi
	done
	shopt -u nullglob
	[ "$fail" -eq 0 ]
}

@test "BUG-056: each -node dispatcher exists and 'version' prints VERSION" {
	local v; v="$(cat "$REPO/VERSION")"
	for cmd in bitcoin-node lightning-node fulcrum-node monero-node; do
		[ -x "$REPO/bin/$cmd" ] || { echo "missing $REPO/bin/$cmd"; return 1; }
		run env SELF_LIBEXEC="$REPO/libexec" "$REPO/bin/$cmd" version
		[ "$status" -eq 0 ] || { echo "$cmd version exited $status"; return 1; }
		[ "$output" = "$v" ] || { echo "$cmd version=$output want $v"; return 1; }
	done
}
