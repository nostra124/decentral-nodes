#!/usr/bin/env bats
#
# FEAT-039 — `bitcoin tax report-de` acceptance criteria.
#
# Fixtures are materialised by tests/vectors/tax-report-de/build-fixtures.sh
# into a throwaway XDG data root; the BTC/EUR price cache is pointed at a
# fixture file via $BITCOIN_PRICE_CACHE so the report makes no network call.
# Each fixture's expected disposals.csv is checked in under
# tests/vectors/tax-report-de/expected/ and compared byte-for-byte (AC #8).

bats_require_minimum_version 1.5.0

setup() {
	BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
	HOME="$(mktemp -d "$BATS_TMPDIR/home.XXXXXX")"
	unset XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_SHARE_HOME
	unset XDG_SOURCE_HOME XDG_BACKUP_HOME XDG_RUNTIME_DIR
	export HOME
	export SELF_QUIET=1
	export BITCOIN_BIN="$BATS_TEST_DIRNAME/../../bin/bitcoin-node"
	export SELF_LIBEXEC="$BATS_TEST_DIRNAME/../../libexec"
	export XDG_DATA_HOME="$HOME/data"
	export BITCOIN_PRICE_CACHE="$HOME/price.tsv"
	FIXDIR="$BATS_TEST_DIRNAME/../vectors/tax-report-de"
	EXPECTED="$FIXDIR/expected"
	OUT="$HOME/out"
}

teardown() { rm -rf "$HOME"; }

gen() { bash "$FIXDIR/build-fixtures.sh" "$1" "$XDG_DATA_HOME/bitcoin/wallets" "$BITCOIN_PRICE_CACHE"; }

# byte-for-byte compare of a produced disposals.csv against the checked-in
# expected file; dumps a unified diff on mismatch.
assert_disposals() { # <expected-name> <out-subdir>
	run diff -u "$EXPECTED/$1.disposals.csv" "$OUT/$2/disposals.csv"
	[ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "FEAT-039 AC8 — buy-hold-sell: one tax-free disposal (held > 1 year)" {
	gen buy-hold-sell
	run "$BITCOIN_BIN" tax report-de bhs --year 2023 --out "$OUT"
	[ "$status" -eq 0 ]
	assert_disposals buy-hold-sell bhs-2023
}

@test "FEAT-039 AC3/AC8 — spend-within-year: one taxable disposal" {
	gen spend-within-year
	run "$BITCOIN_BIN" tax report-de swy --year 2022 --out "$OUT"
	[ "$status" -eq 0 ]
	assert_disposals spend-within-year swy-2022
}

@test "FEAT-039 AC2/AC8 — fifo-stacking: oldest lots popped first, partials carry" {
	gen fifo-stacking
	run "$BITCOIN_BIN" tax report-de fifo --year 2023 --out "$OUT"
	[ "$status" -eq 0 ]
	assert_disposals fifo-stacking fifo-2023
}

@test "FEAT-039 AC4/AC8 — self-transfer-chain: --all-wallets traces basis to origin" {
	gen self-transfer-chain
	run "$BITCOIN_BIN" tax report-de --all-wallets --year 2023 --out "$OUT"
	[ "$status" -eq 0 ]
	assert_disposals self-transfer-chain all-wallets-2023
}

@test "FEAT-039 AC5/AC8 — lending-roundtrip default: no disposal" {
	gen lending-roundtrip
	run "$BITCOIN_BIN" tax report-de lend --year 2023 --out "$OUT"
	[ "$status" -eq 0 ]
	assert_disposals lending-roundtrip lend-2023
}

@test "FEAT-039 AC5/AC8 — lending-roundtrip --strict-lending: lending-out is a disposal" {
	gen lending-roundtrip
	run "$BITCOIN_BIN" tax report-de lend --year 2023 --strict-lending --out "$OUT"
	[ "$status" -eq 0 ]
	assert_disposals lending-roundtrip-strict lend-2023
}

@test "FEAT-039 AC6/AC8 — loss-claim: proceeds 0, gain = -basis" {
	gen loss-claim
	run "$BITCOIN_BIN" tax report-de loss --year 2023 --out "$OUT"
	[ "$status" -eq 0 ]
	assert_disposals loss-claim loss-2023
}

@test "FEAT-039 AC8 — channel: one disposal on the spend output" {
	gen channel
	run "$BITCOIN_BIN" tax report-de chan --year 2023 --out "$OUT"
	[ "$status" -eq 0 ]
	assert_disposals channel chan-2023
}

@test "FEAT-039 AC1 — produces disposals.csv, income.csv, summary.md, narrative.md" {
	gen buy-hold-sell
	run "$BITCOIN_BIN" tax report-de bhs --year 2023 --out "$OUT"
	[ "$status" -eq 0 ]
	[ -f "$OUT/bhs-2023/disposals.csv" ]
	[ -f "$OUT/bhs-2023/income.csv" ]
	[ -f "$OUT/bhs-2023/summary.md" ]
	[ -f "$OUT/bhs-2023/narrative.md" ]
}

@test "FEAT-039 AC7 — non-removable disclaimer at the top of every output file" {
	gen buy-hold-sell
	run "$BITCOIN_BIN" tax report-de bhs --year 2023 --out "$OUT"
	[ "$status" -eq 0 ]
	local f
	for f in disposals.csv income.csv summary.md narrative.md; do
		head -n 1 "$OUT/bhs-2023/$f" | grep -qi 'DISCLAIMER' \
			|| { echo "no disclaimer in $f"; return 1; }
		grep -qi 'not tax advice' "$OUT/bhs-2023/$f" \
			|| { echo "disclaimer text missing in $f"; return 1; }
	done
}

@test "FEAT-039 AC5 — --strict-lending choice is recorded in narrative.md" {
	gen lending-roundtrip
	run "$BITCOIN_BIN" tax report-de lend --year 2023 --strict-lending --out "$OUT"
	[ "$status" -eq 0 ]
	grep -qi 'strict' "$OUT/lend-2023/narrative.md"
}

@test "FEAT-039 — summary.md reports the Freigrenze condition" {
	gen spend-within-year
	run "$BITCOIN_BIN" tax report-de swy --year 2022 --out "$OUT"
	[ "$status" -eq 0 ]
	grep -qi 'Freigrenze' "$OUT/swy-2022/summary.md"
}

@test "FEAT-039 — only the requested year's disposals appear" {
	gen fifo-stacking
	# s1 (2023-03-01) and s2 (2023-09-01) are 2023; none in 2024.
	run "$BITCOIN_BIN" tax report-de fifo --year 2024 --out "$OUT"
	[ "$status" -eq 0 ]
	# header + disclaimer only, no data rows
	run grep -c '^2022' "$OUT/fifo-2024/disposals.csv"
	[ "$output" = "0" ]
}

@test "FEAT-039 — missing wallet errors cleanly" {
	run "$BITCOIN_BIN" tax report-de nope --year 2023 --out "$OUT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"no such wallet"* ]] || [[ "$output" == *"nope"* ]]
}

@test "FEAT-039 — missing --year errors cleanly" {
	gen buy-hold-sell
	run "$BITCOIN_BIN" tax report-de bhs --out "$OUT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"year"* ]]
}

@test "FEAT-039 — help mentions report-de" {
	run "$BITCOIN_BIN" tax help
	[ "$status" -eq 0 ]
	[[ "$output" == *"report-de"* ]]
}
