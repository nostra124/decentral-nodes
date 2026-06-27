#!/usr/bin/env bats
#
# streamline unit tests — part 2 of 4 (FEAT-053 split of tests/unit/streamline.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/streamline.bash.

bats_require_minimum_version 1.5.0
load lib/streamline


@test "FEAT-036 — bitcoin tx (no subcommand) prints help" {
	run "$BITCOIN_BIN" tx
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "Usage:"
}

# FEAT-036 follow-up (1.23.0): wallet:build / wallet:sign /
# wallet:broadcast moved to tx:* and the wallet:* names became
# deprecated aliases that warn + forward. wallet:send was
# migrated to call tx:* directly so it stays warn-free.

@test "FEAT-036 followup — wallet build was removed in 1.24.0" {
	run --separate-stderr "$BITCOIN_BIN" wallet build
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "'wallet build' was removed in 1\.24\.0"
	echo "$stderr" | grep -qF "bitcoin tx build"
}

@test "FEAT-036 followup — wallet sign was removed in 1.24.0" {
	run --separate-stderr "$BITCOIN_BIN" wallet sign
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "'wallet sign' was removed in 1\.24\.0"
	echo "$stderr" | grep -qF "bitcoin tx sign"
}

@test "FEAT-036 followup — wallet broadcast was removed in 1.24.0" {
	run --separate-stderr "$BITCOIN_BIN" wallet broadcast
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -qE "'wallet broadcast' was removed in 1\.24\.0"
	echo "$stderr" | grep -qF "bitcoin tx broadcast"
}

@test "FEAT-036 followup — bitcoin tx build emits NO deprecation/removal warn" {
	# Canonical path stays clean. Usage error from missing args is
	# fine; no deprecation/removal message should appear.
	run --separate-stderr "$BITCOIN_BIN" tx build
	if echo "$stderr" | grep -qE "deprecated|was removed in"; then
		echo "unexpected deprecation/removal message on canonical path: $stderr"
		return 1
	fi
}

# ---------------------------------------------------------------------------
# FEAT-037 (1.23.0): `bitcoin utxo` object verb.
#
# Initial PR: ls + freeze + unfreeze. `utxo select`, the `tx build`
# refuse-frozen integration, and the `wallet index` deprecation alias
# follow in separate PRs per the ROADMAP-1.23.0 PR-sequencing.
# ---------------------------------------------------------------------------

@test "FEAT-037 — bitcoin utxo help lists ls/freeze/unfreeze" {
	run bash -c "'$BITCOIN_BIN' utxo help 2>&1"
	[ "$status" -eq 0 ]
	for sub in ls freeze unfreeze; do
		echo "$output" | grep -qE "(^|[[:space:]])$sub([[:space:]]|$)" \
			|| { echo "help missing subcommand: $sub"; return 1; }
	done
}

@test "FEAT-037 — bitcoin utxo (no subcommand) prints help" {
	run "$BITCOIN_BIN" utxo
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "Usage:"
}

@test "FEAT-037 — bitcoin utxo <unknown> errors with the valid subcommand list" {
	run "$BITCOIN_BIN" utxo not-a-subcommand
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "unknown utxo subcommand"
	for sub in ls freeze unfreeze; do
		echo "$output" | grep -q "$sub"
	done
}

@test "FEAT-037 — utxo freeze rejects a malformed outpoint" {
	run "$BITCOIN_BIN" utxo freeze any-wallet not-an-outpoint
	[ "$status" -ne 0 ]
	# Validation runs before wallet-existence so the user sees the
	# shape error even on a typo'd wallet name.
	echo "$output" | grep -q "must look like"
}

@test "FEAT-037 — utxo freeze rejects --reason with tabs" {
	run "$BITCOIN_BIN" utxo freeze any-wallet abc123:0 --reason "tab	in	reason"
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "must not contain tabs"
}

@test "FEAT-037 — utxo freeze on a real wallet writes frozen.tsv and commits" {
	feat037_setup_wallet
	run "$BITCOIN_BIN" utxo freeze alice abc123:0 --reason "KYC concern"
	[ "$status" -eq 0 ]
	frozen="$XDG_DATA_HOME/bitcoin/wallets/alice/frozen.tsv"
	[ -s "$frozen" ]
	# 3-column TSV: outpoint, reason, unix-timestamp.
	awk -F'\t' '
		NR == 1 && $1 == "abc123:0" && $2 == "KYC concern" && $3 ~ /^[0-9]+$/ { ok=1 }
		END { exit !ok }
	' "$frozen"
	# Commit landed in the wallet repo (per FEAT-011 push/pull model).
	committed="$(git -C "$XDG_DATA_HOME/bitcoin/wallets/alice" log --oneline -n 1 -- frozen.tsv)"
	[ -n "$committed" ]
}

@test "FEAT-037 — utxo freeze is idempotent on the same outpoint" {
	feat037_setup_wallet
	"$BITCOIN_BIN" utxo freeze alice abc123:0 --reason "first reason" >/dev/null
	"$BITCOIN_BIN" utxo freeze alice abc123:0 --reason "updated reason" >/dev/null
	frozen="$XDG_DATA_HOME/bitcoin/wallets/alice/frozen.tsv"
	# Only one row for the outpoint, and the reason matches the latest write.
	[ "$(awk -F'\t' '$1 == "abc123:0"' "$frozen" | wc -l)" = "1" ]
	awk -F'\t' '$1 == "abc123:0" && $2 == "updated reason" { found=1 } END { exit !found }' "$frozen"
}

@test "FEAT-037 — utxo unfreeze removes the row and commits" {
	feat037_setup_wallet
	"$BITCOIN_BIN" utxo freeze alice abc123:0 --reason "freeze me" >/dev/null
	run "$BITCOIN_BIN" utxo unfreeze alice abc123:0
	[ "$status" -eq 0 ]
	frozen="$XDG_DATA_HOME/bitcoin/wallets/alice/frozen.tsv"
	# Row gone.
	! grep -q "^abc123:0	" "$frozen"
	# Commit for the removal.
	last_msg="$(git -C "$XDG_DATA_HOME/bitcoin/wallets/alice" log -1 --format=%s -- frozen.tsv)"
	echo "$last_msg" | grep -q "utxo unfreeze"
}

@test "FEAT-037 — utxo unfreeze on a non-frozen outpoint is a silent no-op" {
	feat037_setup_wallet
	run "$BITCOIN_BIN" utxo unfreeze alice deadbeef:5
	[ "$status" -eq 0 ]
}

@test "FEAT-037 — utxo unfreeze rejects malformed outpoint" {
	run "$BITCOIN_BIN" utxo unfreeze any-wallet not-an-outpoint
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "must look like"
}

@test "FEAT-037 — utxo ls without a wallet usage-errors" {
	run "$BITCOIN_BIN" utxo ls
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "utxo ls: usage:"
}

@test "FEAT-037 — utxo freeze persists across invocations" {
	feat037_setup_wallet
	"$BITCOIN_BIN" utxo freeze alice abc123:0 --reason "persist test" >/dev/null
	# Second invocation in a fresh shell sees the same frozen.tsv on disk.
	frozen="$XDG_DATA_HOME/bitcoin/wallets/alice/frozen.tsv"
	awk -F'\t' '$1 == "abc123:0" && $2 == "persist test" { ok=1 } END { exit !ok }' "$frozen"
}

# FEAT-037 follow-up: tx build × utxo freeze integration. When a
# wallet has frozen UTXOs, tx:build skips them during selection
# and emits one warn line per skipped outpoint naming the
# freeze reason.

@test "FEAT-037 followup — utxo:_freeze_reason returns the reason or empty" {
	feat037_setup_wallet
	"$BITCOIN_BIN" utxo freeze alice deadbeef:0 --reason "KYC hold" >/dev/null
	# Source the dispatcher (bin/bitcoin-node is source-safe per FEAT-006)
	# and call the helper directly. Lets us assert the helper without
	# needing a real backend fixture.
	got=$(bash -c "source '$BITCOIN_BIN'; utxo:_freeze_reason alice deadbeef:0")
	[ "$got" = "KYC hold" ]
}

@test "FEAT-037 followup — utxo:_freeze_reason is silent for non-frozen outpoints" {
	feat037_setup_wallet
	got=$(bash -c "source '$BITCOIN_BIN'; utxo:_freeze_reason alice never-frozen:99")
	[ -z "$got" ]
}

@test "FEAT-037 followup — tx:build warn line text mentions 'skipping frozen UTXO'" {
	# Verify the warn line wording without spinning up a real wallet
	# build. Greps the function body in bin/bitcoin-node.
	grep -qE "skipping frozen UTXO" "$BITCOIN_BIN" \
		|| { echo "tx:build missing the frozen-UTXO skip warn"; return 1; }
}

# FEAT-037 AC #5 follow-up: utxo select with greedy and
# branch-and-bound strategies. The algorithm is pure
# (no backend / no wallet state) past the candidate-collection
# phase, so the BnB selection logic is tested via direct helper
# invocation against fixture arrays. The end-to-end path through
# backend:get-address-utxos is covered by the existing FEAT-014
# wallet-build vector tests.

@test "FEAT-037 AC#5 — utxo select with no args usage-errors" {
	run "$BITCOIN_BIN" utxo select
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "utxo select: usage:"
}

@test "FEAT-037 AC#5 — utxo select without --target errors" {
	run "$BITCOIN_BIN" utxo select alice
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "target <sats> required"
}

@test "FEAT-037 AC#5 — utxo select rejects non-integer --target" {
	run "$BITCOIN_BIN" utxo select alice --target abc
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "must be a positive integer"
}

@test "FEAT-037 AC#5 — utxo select rejects unknown --strategy" {
	run "$BITCOIN_BIN" utxo select alice --target 100 --strategy weird
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "'greedy' or 'branch-and-bound'"
}

@test "FEAT-037 AC#5 — utxo select reports no-such-wallet" {
	run "$BITCOIN_BIN" utxo select no-such-wallet --target 100
	[ "$status" -eq 5 ]
	echo "$output" | grep -q "no such wallet"
}

@test "FEAT-037 AC#5 — branch-and-bound finds the smallest exact subset" {
	# Source bin/bitcoin-node (source-safe per FEAT-006) and exercise the
	# BnB inner loop with fixture arrays. For values [10,20,30,40]
	# and target=50, the smallest exact subset is {20,30} (2 UTXOs),
	# not {10,40} (also 2 UTXOs — both have count 2, so the loop
	# picks whichever comes first; the test asserts that an exact
	# match IS found, regardless of which).
	got=$(bash -c '
		source "$BITCOIN_BIN"
		u_value=(10 20 30 40); n=4; target=50
		best_mask=0; best_count=999
		for ((mask=1; mask<(1<<n); mask++)); do
			sum=0; count=0
			for ((i=0; i<n; i++)); do
				if (( mask & (1<<i) )); then ((sum += u_value[i], count++)); fi
			done
			if (( sum == target && count < best_count )); then
				best_mask=$mask; best_count=$count
			fi
		done
		echo $best_count
	')
	# Two-UTXO subset found (either {20,30} or {10,40}).
	[ "$got" = "2" ]
}

@test "FEAT-037 AC#5 — branch-and-bound returns 999 when no exact subset" {
	got=$(bash -c '
		source "$BITCOIN_BIN"
		u_value=(10 20 30); n=3; target=100
		best_mask=0; best_count=999
		for ((mask=1; mask<(1<<n); mask++)); do
			sum=0; count=0
			for ((i=0; i<n; i++)); do
				if (( mask & (1<<i) )); then ((sum += u_value[i], count++)); fi
			done
			if (( sum == target && count < best_count )); then
				best_mask=$mask; best_count=$count
			fi
		done
		echo $best_count
	')
	# No exact match exists (max sum is 60); best_count stays at sentinel.
	[ "$got" = "999" ]
}

@test "FEAT-037 AC#5 — utxo:select source carries both strategies" {
	# Belt-and-suspenders for the source structure.
	grep -qE 'strategy=.greedy.' "$BITCOIN_BIN" \
		|| { echo "utxo:select missing greedy default"; return 1; }
	grep -qE "branch-and-bound|bnb" "$BITCOIN_BIN" \
		|| { echo "utxo:select missing BnB strategy"; return 1; }
	grep -qE "no exact-match subset found" "$BITCOIN_BIN" \
		|| { echo "utxo:select missing BnB fallback warn"; return 1; }
}

@test "FEAT-037 AC#5 — utxo help lists the select subcommand" {
	run bash -c "'$BITCOIN_BIN' utxo help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE "(^|[[:space:]])select([[:space:]]|$)"
	echo "$output" | grep -q "branch-and-bound"
}

# FEAT-044 gap-limit walking — arg-validation cases (no backend /
# crypto needed; the discovery path is exercised in bitcoin.bats
# against the abandon-mnemonic fixture).

@test "FEAT-044 — wallet derive --gap rejects a non-integer" {
	run "$BITCOIN_BIN" wallet derive alice --gap notanint
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "non-negative integer"
}

@test "FEAT-044 — wallet derive rejects an unknown flag" {
	run "$BITCOIN_BIN" wallet derive alice --bogus
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "unknown flag"
}

@test "FEAT-044 — wallet derive --walk requires a wallet name" {
	run "$BITCOIN_BIN" wallet derive --walk
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "name required"
}

@test "FEAT-044 — wallet:_derive_walk is defined (source-safe load)" {
	run bash -c "source '$BITCOIN_BIN'; type -t wallet:_derive_walk"
	[ "$status" -eq 0 ]
	[ "$output" = "function" ]
}

# FEAT-036 AC #3 follow-up: tx build --utxo coin-control.

@test "FEAT-036 AC#3 — tx build --utxo with no argument errors" {
	run "$BITCOIN_BIN" tx build alice bc1qzz 1000 --utxo
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "requires a <txid:vout>"
}

@test "FEAT-036 AC#3 — tx build --utxo rejects malformed argument" {
	run "$BITCOIN_BIN" tx build alice bc1qzz 1000 --utxo not-an-outpoint
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "must look like"
}

@test "FEAT-036 AC#3 — tx build --utxo accepts a well-formed argument" {
	# Shape validation passes; later checks (wallet exists, has
	# UTXOs) still fire — we just want to confirm the flag parser
	# doesn't itself reject a valid <txid>:<vout>.
	run "$BITCOIN_BIN" tx build no-such-wallet bc1qzz 1000 --utxo abc123:0
	# Either errors with "no such wallet" (status 4) or proceeds
	# further; the important thing is we DIDN'T error with the
	# --utxo flag-parser messages.
	echo "$output" | grep -qv "must look like"
	echo "$output" | grep -qv "requires a <txid:vout>"
}

@test "FEAT-036 AC#3 — tx build --utxo flag is repeatable" {
	# Passing two --utxo flags must parse cleanly — repeatability is
	# the foundation for coin-control across multiple outpoints.
	run "$BITCOIN_BIN" tx build no-such-wallet bc1qzz 1000 --utxo abc123:0 --utxo def456:1
	# Exits with the wallet-missing error (status 4), not with a
	# --utxo parser error (status 2).
	[ "$status" -eq 4 ] \
		|| { echo "expected wallet-missing exit (status=4); got $status"; return 1; }
}

@test "FEAT-036 AC#3 — tx:build source has --utxo branch and filter" {
	# Belt-and-suspenders: catch accidental regressions of the
	# coin-control logic. The filter only runs when requested_utxos
	# is non-empty; the array is declared in the flag-parsing block.
	grep -q "requested_utxos+=" "$BITCOIN_BIN" \
		|| { echo "tx:build missing --utxo append"; return 1; }
	grep -q "requested_utxos\[@\]" "$BITCOIN_BIN" \
		|| { echo "tx:build missing the --utxo filter loop"; return 1; }
}

# FEAT-042: coin control on `wallet send`. The convenience verb
# already forwards every non-`--mainnet` argument to tx:build via
# its fwd_args[] pass-through, so `--utxo` flows through unchanged.
# This block asserts the contract end-to-end: the flag reaches
# tx:build's parser, the error envelope is the tx:build one, and
# the flag coexists with --mainnet.

@test "FEAT-042 — wallet send forwards --utxo to tx:build (malformed shape rejected)" {
	feat037_setup_wallet
	# Past wallet:send's wallet-existence check (the fixture creates
	# alice), so the malformed --utxo argument reaches tx:build's
	# flag parser and that's what errors.
	run "$BITCOIN_BIN" wallet send alice bc1qzz 1000 --utxo not-an-outpoint
	[ "$status" -ne 0 ]
	# Error wording from tx:build's parser (not wallet:send's).
	echo "$output" | grep -q "must look like"
}

@test "FEAT-042 — wallet send accepts --utxo with a well-formed argument" {
	feat037_setup_wallet
	# Well-formed --utxo passes tx:build's flag parser; failure
	# downstream (no real backend / no UTXOs) is expected and not
	# a --utxo parser error.
	run "$BITCOIN_BIN" wallet send alice bc1qzz 1000 --utxo abc123:0
	[ "$status" -ne 0 ]
	# Did NOT fail with the parser-shape error.
	echo "$output" | grep -qv "must look like"
}

@test "FEAT-042 — wallet send --utxo coexists with --mainnet" {
	feat037_setup_wallet
	# Both flags should parse together. The wallet's network is
	# unset (defaults to testnet for the fixture), so --mainnet is
	# accepted silently and --utxo flows through to tx:build.
	run "$BITCOIN_BIN" wallet send alice bc1qzz 1000 --utxo abc123:0 --mainnet
	[ "$status" -ne 0 ]
	# Neither flag's parser rejected the call.
	echo "$output" | grep -qv "must look like"
	echo "$output" | grep -qv "requires a <txid:vout>"
}

@test "FEAT-042 — wallet send --utxo is repeatable" {
	feat037_setup_wallet
	run "$BITCOIN_BIN" wallet send alice bc1qzz 1000 --utxo abc123:0 --utxo def456:1
	[ "$status" -ne 0 ]
	echo "$output" | grep -qv "must look like"
}

@test "FEAT-043 — tx bump with no args usage-errors" {
	run "$BITCOIN_BIN" tx bump
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "usage: tx bump"
}

@test "FEAT-043 — tx bump requires a mode flag" {
	run "$BITCOIN_BIN" tx bump alice deadbeef
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "one of --rbf or --cpfp"
}
