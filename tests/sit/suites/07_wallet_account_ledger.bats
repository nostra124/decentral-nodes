#!/usr/bin/env bats
# SIT 07 — multi-account tagging + ledger queries (FEAT-174 + FEAT-193).

setup() {
	rm -rf "$HOME/.lightning/wallet/acct-test"
	lightning wallet new acct-test >/dev/null
	lightning wallet use acct-test >/dev/null
	lightning account create rent --limit 100000 --overdraft deny >/dev/null
	lightning account create donations >/dev/null
}

@test "ledger add + balance round-trips through SQLite" {
	lightning wallet ledger add in  1000000 --account rent      --message "march"
	lightning wallet ledger add out -250000 --account rent      --message "coffee"
	lightning wallet ledger add in   500000 --account donations --message "tip"

	run lightning wallet ledger balance rent
	[ "$status" -eq 0 ]
	[ "$output" = "750000" ]

	run lightning wallet ledger balance donations
	[ "$status" -eq 0 ]
	[ "$output" = "500000" ]
}

@test "ledger sum --by account aggregates across all accounts" {
	lightning wallet ledger add in 1000000 --account rent
	run lightning wallet ledger sum --by account
	[ "$status" -eq 0 ]
	[[ "$output" == *"rent"* ]]
}

@test "account show prints balance + recent ledger" {
	lightning wallet ledger add in 42000 --account rent --message "test"
	run lightning account show rent
	[ "$status" -eq 0 ]
	[[ "$output" == *"balance_sat: 42"* ]]
	[[ "$output" == *"test"* ]]
}
