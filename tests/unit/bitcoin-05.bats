#!/usr/bin/env bats
#
# bitcoin unit tests — part 5 of 5 (FEAT-053 split of tests/unit/bitcoin.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/bitcoin.bash.

bats_require_minimum_version 1.5.0
load lib/bitcoin


# ---------------------------------------------------------------------------
# BUG-016 regression — `command:bip49-create` and `command:bip84-create`
# were dispatcher entries calling undefined `command:bip32-create`.
# Removed in 1.7.1; the bash-function wrappers `bip49()` / `bip84()`
# remain as the user-facing path.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# FEAT-032 — lint-cmd-names catches the BUG-013/014/016 defect family.
# ---------------------------------------------------------------------------

@test "FEAT-032 — lint-cmd-names passes on the current project" {
	run "$BATS_TEST_DIRNAME/../../tools/lint-cmd-names"
	[ "$status" -eq 0 ]
}

@test "FEAT-032 — lint-cmd-names flags an undefined command:<name> call" {
	# Build a minimal fixture script that calls command:foo but
	# doesn't define it.
	bad="$BATS_TMPDIR/badscript-$BATS_TEST_NUMBER"
	cat > "$bad" <<'BAD'
#!/usr/bin/env bash
command:foo "$@"
BAD
	chmod +x "$bad"
	run "$BATS_TEST_DIRNAME/../../tools/lint-cmd-names" "$bad"
	[ "$status" -ne 0 ]
	[[ "$output" == *"command:foo"* ]]
}

@test "FEAT-032 — lint-cmd-names passes on a fixture where the call is defined" {
	good="$BATS_TMPDIR/goodscript-$BATS_TEST_NUMBER"
	cat > "$good" <<'GOOD'
#!/usr/bin/env bash
command:foo() { echo hi; }
command:foo "$@"
GOOD
	chmod +x "$good"
	run "$BATS_TEST_DIRNAME/../../tools/lint-cmd-names" "$good"
	[ "$status" -eq 0 ]
}

@test "FEAT-032 — lint-cmd-names doesn't false-positive on command:<name> inside a log string" {
	fix="$BATS_TMPDIR/logscript-$BATS_TEST_NUMBER"
	cat > "$fix" <<'STR'
#!/usr/bin/env bash
debug() { echo "$@" >&2; }
debug "executing command:undefined-but-only-in-a-log-string"
STR
	chmod +x "$fix"
	run "$BATS_TEST_DIRNAME/../../tools/lint-cmd-names" "$fix"
	[ "$status" -eq 0 ]
}

@test "BUG-016 — bitcoin bip49-create no longer exists as a broken dispatcher entry" {
	# After the fix, `bitcoin bip49-create` falls through to the
	# help fallback (unknown subcommand), NOT a fatal
	# "command:bip32-create: command not found".
	run "$BITCOIN_BIN" bip49-create
	[[ "$output" != *"command:bip32-create"* ]]
	[[ "$output" != *"command not found"* ]]
}

@test "BUG-016 — bitcoin bip84-create no longer exists as a broken dispatcher entry" {
	run "$BITCOIN_BIN" bip84-create
	[[ "$output" != *"command:bip32-create"* ]]
	[[ "$output" != *"command not found"* ]]
}

@test "BUG-014 — bip32 derive m/.../N (neutering) resolves" {
	repo_root="$BATS_TEST_DIRNAME/../../"
	PATH="$repo_root/bin:$repo_root/libexec/bitcoin-node:$PATH" \
	XDG_SHARE_HOME="$repo_root/share" \
	SELF_LIBEXEC="$repo_root/libexec" \
	run bash -c '
		mnemonic-to-seed abandon abandon abandon abandon abandon abandon abandon \
		                 abandon abandon abandon abandon about \
		  | basenc --base16 -w0 \
		  | bip32 create -s 2>/dev/null \
		  | bitcoin-node bip13 base58-decode \
		  | bip32 derive m/84h/0h/0h/0/0/N
	'
	[ "$status" -eq 0 ]
	[[ "$output" != *"bip32-is-public"* ]]
	[[ "$output" != *"bip32-is-secret"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-195 (1.30.0) — runtime dependency boundary: bin/bitcoin-node must call
# only account / config / secret / crypt at runtime (plus BIP plugin
# primitives). Forbidden sibling scripts are cache, check, data, hosts,
# repo, scripts, task, user (as invoked commands, not variable names or
# comment text). This test guards against re-introduction.
# ---------------------------------------------------------------------------

@test "FEAT-195 — bin/bitcoin-node has no invocations of forbidden sibling scripts" {
	script="$BATS_TEST_DIRNAME/../../bin/bitcoin-node"
	# Pattern: forbidden word at the start of a statement (leading whitespace
	# allowed) but NOT as a variable name (preceded by $), not in a comment
	# (line starts with optional-space then #), and not as a git config key
	# (git -c user.*). The grep is intentionally strict — any match is a
	# violation that needs to be reviewed.
	forbidden_cmds=(cache data hosts scripts task)
	for word in "${forbidden_cmds[@]}"; do
		# Fail if the word appears as the first token of a non-comment shell
		# statement. Exclude lines where it appears only inside a string or
		# variable name.
		if grep -qE "^\s*${word}\s" "$script" 2>/dev/null; then
			echo "VIOLATION: '$word' appears as a command invocation in bin/bitcoin-node" >&2
			grep -nE "^\s*${word}\s" "$script" >&2
			return 1
		fi
		# Also catch subshell forms: $(<word> ...) or `<word> `
		if grep -qE "\$\(\s*${word}\s|\`\s*${word}\s" "$script" 2>/dev/null; then
			echo "VIOLATION: '$word' used in command substitution in bin/bitcoin-node" >&2
			grep -nE "\$\(\s*${word}\s|\`\s*${word}\s" "$script" >&2
			return 1
		fi
	done
}

@test "FEAT-195 — bin/bitcoin-node calls 'secret' only for seed operations" {
	script="$BATS_TEST_DIRNAME/../../bin/bitcoin-node"
	# Every 'secret' invocation must be 'secret get/put/rm' against a
	# <wallet>/seed path. No other secret operations are expected.
	while IFS=: read -r _lineno content; do
		# Strip leading whitespace.
		content="${content#"${content%%[! ]*}"}"
		if [[ "$content" =~ ^secret[[:space:]] ]]; then
			verb="$(echo "$content" | awk '{print $2}')"
			if [[ "$verb" != "get" && "$verb" != "put" && "$verb" != "rm" ]]; then
				echo "VIOLATION at $_lineno: unexpected 'secret $verb'" >&2
				return 1
			fi
			if ! echo "$content" | grep -q '/seed'; then
				echo "VIOLATION at $_lineno: secret call not targeting a /seed path" >&2
				return 1
			fi
		fi
	done < <(grep -n "^\s*secret\b" "$script" | grep -v "^\s*#")
}

# ---------------------------------------------------------------------------
# BUG-026 — wallet state-change verbs commit inside a subshell of the form
#   ( cd "$path"; git add …; git -c user.email=wallet@bitcoin … commit … )
# An UNGUARDED `cd "$path"` lets the subshell continue when cd fails (wallet
# dir removed mid-run, racing test, unwritable), so the git commands run in
# the INHERITED cwd — committing wallet state into whatever git repo the user
# is standing in, under the wallet@bitcoin identity. (Observed live: rogue
# commits 04d83d6 "wallet derive: …" / 08df1db "wallet index: …" landed in
# this project's checkout.) Every such cd must abort the subshell on failure
# (`cd "$path" || exit 1`). Structural guard, same category as the FEAT-195
# dependency-boundary tests: a permission/TOCTOU behavioural repro is
# non-deterministic under root (which ignores permission bits) and the real
# dir-removed-mid-run trigger is an unstageable race.
# ---------------------------------------------------------------------------
@test "BUG-026 — every wallet commit subshell guards 'cd \$path'" {
	script="$BATS_TEST_DIRNAME/../../bin/bitcoin-node"
	# A standalone, unguarded `cd "$path"` (no `|| exit`/`|| return`/`|| {`
	# on the same line) is the dangerous form. Safe forms are
	# `cd "$path" || exit 1` and `( cd "$path" && … )`.
	bad=0
	while IFS= read -r line; do
		bad=$((bad + 1))
		echo "UNGUARDED cd in bin/bitcoin-node: $line" >&2
	done < <(grep -nE '^[[:space:]]*cd "\$path"[[:space:]]*$' "$script")
	[ "$bad" -eq 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-045: watch-only wallets.
# ---------------------------------------------------------------------------

@test "FEAT-045 — wallet watch creates a watch-only wallet (no seed in secret)" {
	setup_wallet_env
	local name="watch045a_$$"
	# BIP-32 xpub for secp256k1 generator, depth=0, all-zero chain code (valid 111-char xpub)
	local xpub="xpub661MyMwAqRbcEYS8w7XLSVeEsBXy79zSzH1J8vCdxAZningWLdN3zgtU6QzvJsNBNF5QPBBBg1yVF2LKrcfGdJq86PeLWDMUCYatZPzQu8R"
	run "$BITCOIN_BIN" wallet watch "$name" "$xpub"
	[ "$status" -eq 0 ]
	local wpath="$XDG_DATA_HOME/bitcoin/wallets/$name"
	[ -d "$wpath" ]
	[ -f "$wpath/xpub" ]
	grep -q "watch-only=1" "$wpath/config"
	# No secret was stored.
	[ ! -f "$SECRET_STORE/$name/seed" ]
}

@test "FEAT-045 — wallet watch rejects an invalid xpub" {
	setup_wallet_env
	local name="watch045b_$$"
	run "$BITCOIN_BIN" wallet watch "$name" "notanxpub"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a valid xpub"* ]]
}

@test "FEAT-045 — wallet watch rejects a duplicate name" {
	setup_wallet_env
	local xpub="xpub661MyMwAqRbcEYS8w7XLSVeEsBXy79zSzH1J8vCdxAZningWLdN3zgtU6QzvJsNBNF5QPBBBg1yVF2LKrcfGdJq86PeLWDMUCYatZPzQu8R"
	local name="watch045c_$$"
	"$BITCOIN_BIN" wallet watch "$name" "$xpub"
	run "$BITCOIN_BIN" wallet watch "$name" "$xpub"
	[ "$status" -ne 0 ]
	[[ "$output" == *"already exists"* ]]
}

@test "FEAT-045 — wallet xpub rejects a missing wallet" {
	setup_wallet_env
	run "$BITCOIN_BIN" wallet xpub "nosuchwalletfeat045"
	[ "$status" -ne 0 ]
	[[ "$output" == *"no such wallet"* ]]
}

@test "FEAT-045 — wallet xpub on a watch-only wallet prints the stored xpub" {
	setup_wallet_env
	local xpub="xpub661MyMwAqRbcEYS8w7XLSVeEsBXy79zSzH1J8vCdxAZningWLdN3zgtU6QzvJsNBNF5QPBBBg1yVF2LKrcfGdJq86PeLWDMUCYatZPzQu8R"
	local name="watch045d_$$"
	"$BITCOIN_BIN" wallet watch "$name" "$xpub"
	run "$BITCOIN_BIN" wallet xpub "$name"
	[ "$status" -eq 0 ]
	[ "$output" = "$xpub" ]
}

@test "FEAT-045 — tx sign on a watch-only wallet exits non-zero with clear message" {
	setup_wallet_env
	local xpub="xpub661MyMwAqRbcEYS8w7XLSVeEsBXy79zSzH1J8vCdxAZningWLdN3zgtU6QzvJsNBNF5QPBBBg1yVF2LKrcfGdJq86PeLWDMUCYatZPzQu8R"
	local name="watch045e_$$"
	"$BITCOIN_BIN" wallet watch "$name" "$xpub"
	local wpath="$XDG_DATA_HOME/bitcoin/wallets/$name"
	printf '0\ttb1qfake000000000000000000000000000\t\n' > "$wpath/addresses"
	local psbt="70736274ff010052020000000100000000000000000000000000000000000000000000000000000000000000000000000000feffffff0150c300000000000016001400000000000000000000000000000000000000000000000000010122a0860100000000001976a914c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e288ac0000"
	run bash -c "printf '%s\n' '$psbt' | '$BITCOIN_BIN' tx sign '$name'"
	[ "$status" -ne 0 ]
	[[ "$output" == *"watch-only"* ]]
}

@test "FEAT-045 — wallet watch/xpub are listed in wallet help" {
	run "$BITCOIN_BIN" wallet help
	[ "$status" -eq 0 ]
	[[ "$output" == *"watch"* ]]
	[[ "$output" == *"xpub"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-046: bitcoin address — validate, type, decode.
# Known vectors (mainnet + testnet, all five types):
#   P2PKH mainnet:  1A1zP1eP5QGefi2DMPTfTL5SLmv7Divf (genesis coinbase)
#   P2SH  mainnet:  3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy
#   P2WPKH mainnet: bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4
#   P2WPKH testnet: tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx
#   P2TR  mainnet:  bc1p5cyxnux0n5y9wfpvjfm69xnf4p4e9l4s4y2r0z5c5kwjxnw7zy0sqwzhy4
# ---------------------------------------------------------------------------

@test "FEAT-046 — address validate accepts a P2PKH mainnet address" {
	# 1JaUQDVNRdhfNsVncGkXedaPSM5Gc54Hso = P2PKH for hash160 c0cebcd6c3...
	# (Alice's address from BIP-32 abandon-mnemonic vector)
	run "$BITCOIN_BIN" address validate "1JaUQDVNRdhfNsVncGkXedaPSM5Gc54Hso"
	[ "$status" -eq 0 ]
}

@test "FEAT-046 — address validate accepts a P2SH mainnet address" {
	run "$BITCOIN_BIN" address validate "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"
	[ "$status" -eq 0 ]
}

@test "FEAT-046 — address validate accepts a P2WPKH bech32 address" {
	run "$BITCOIN_BIN" address validate "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
	[ "$status" -eq 0 ]
}

@test "FEAT-046 — address validate accepts a testnet bech32 address" {
	run "$BITCOIN_BIN" address validate "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx"
	[ "$status" -eq 0 ]
}

@test "FEAT-046 — address validate rejects garbage" {
	run "$BITCOIN_BIN" address validate "notanaddress"
	[ "$status" -ne 0 ]
}

@test "FEAT-046 — address validate rejects empty input" {
	run "$BITCOIN_BIN" address validate
	[ "$status" -ne 0 ]
}

@test "FEAT-046 — address type: P2PKH → p2pkh" {
	run "$BITCOIN_BIN" address type "1JaUQDVNRdhfNsVncGkXedaPSM5Gc54Hso"
	[ "$status" -eq 0 ]
	[ "$output" = "p2pkh" ]
}

@test "FEAT-046 — address type: P2SH → p2sh" {
	run "$BITCOIN_BIN" address type "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"
	[ "$status" -eq 0 ]
	[ "$output" = "p2sh" ]
}

@test "FEAT-046 — address type: P2WPKH → p2wpkh" {
	run "$BITCOIN_BIN" address type "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
	[ "$status" -eq 0 ]
	[ "$output" = "p2wpkh" ]
}

@test "FEAT-046 — address decode: P2PKH returns 20-byte hash160 as hex" {
	run "$BITCOIN_BIN" address decode "1JaUQDVNRdhfNsVncGkXedaPSM5Gc54Hso"
	[ "$status" -eq 0 ]
	[ "$output" = "c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2" ]
}

@test "FEAT-046 — address decode: P2WPKH returns witness program as hex" {
	run "$BITCOIN_BIN" address decode "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
	[ "$status" -eq 0 ]
	[ "$output" = "751e76e8199196d454941c45d1b3a323f1433bd6" ]
}

@test "FEAT-046 — address help lists every subcommand" {
	run "$BITCOIN_BIN" address help
	[ "$status" -eq 0 ]
	[[ "$output" == *"validate"* ]]
	[[ "$output" == *"type"* ]]
	[[ "$output" == *"decode"* ]]
}

@test "FEAT-046 — bitcoin help mentions address" {
	run "$BITCOIN_BIN" help
	[[ "$output" == *"address"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-047 — address generate: derive addresses from a raw compressed pubkey
#
# Test vector: secp256k1 generator point G (compressed)
#   pubkey  = 0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798
#   hash160 = 751e76e8199196d454941c45d1b3a323f1433bd6
#
# Expected addresses (verified with BIP-173/350/341 reference implementations):
#   P2WPKH mainnet  = bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4
#   P2WPKH testnet  = tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx
#   P2PKH  mainnet  = 1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH
#   P2TR   mainnet  = bc1pmfr3p9j00pfxjh0zmgp99y8zftmd3s5pmedqhyptwy6lm87hf5sspknck9
# ---------------------------------------------------------------------------

FEAT047_PUBKEY="0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"

@test "FEAT-047 — address generate default (P2WPKH) from a known pubkey" {
	run "$BITCOIN_BIN" address generate "$FEAT047_PUBKEY"
	[ "$status" -eq 0 ]
	[ "$output" = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4" ]
}

@test "FEAT-047 — address generate --p2pkh from the same pubkey" {
	run "$BITCOIN_BIN" address generate --p2pkh "$FEAT047_PUBKEY"
	[ "$status" -eq 0 ]
	[ "$output" = "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH" ]
}

@test "FEAT-047 — address generate --p2wpkh --testnet uses tb1 HRP" {
	run "$BITCOIN_BIN" address generate --p2wpkh --testnet "$FEAT047_PUBKEY"
	[ "$status" -eq 0 ]
	[ "$output" = "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx" ]
}

@test "FEAT-047 — address generate --p2tr from the same pubkey" {
	run "$BITCOIN_BIN" address generate --p2tr "$FEAT047_PUBKEY"
	[ "$status" -eq 0 ]
	[ "$output" = "bc1pmfr3p9j00pfxjh0zmgp99y8zftmd3s5pmedqhyptwy6lm87hf5sspknck9" ]
}

@test "FEAT-047 — address generate rejects a malformed pubkey" {
	run "$BITCOIN_BIN" address generate "deadbeef"
	[ "$status" -eq 1 ]
	[[ "$output" == *"invalid pubkey"* ]]
}

@test "FEAT-047 — address generate rejects empty input" {
	run "$BITCOIN_BIN" address generate
	[ "$status" -eq 2 ]
}

@test "FEAT-047 — address help mentions generate" {
	run "$BITCOIN_BIN" address help
	[ "$status" -eq 0 ]
	[[ "$output" == *"generate"* ]]
}

@test "FEAT-059 AC1 — backend set fulcrum then backend reports fulcrum active" {
	setup_backend_env
	run "$BITCOIN_BIN" backend set fulcrum
	[ "$status" -eq 0 ]
	[ "$(cat "$XDG_CONFIG_HOME/bitcoin/backend")" = "fulcrum" ]
	run "$BITCOIN_BIN" backend
	[ "$output" = "fulcrum" ]
}

@test "FEAT-059 AC2 — get-address-utxos reshapes listunspent; summed .value matches" {
	setup_backend_env
	export BITCOIN_BACKEND=fulcrum
	fulcrum_fixture blockchain.scripthash.listunspent \
		'{"id":1,"result":[{"tx_hash":"aa","tx_pos":0,"value":50000,"height":800000},{"tx_hash":"bb","tx_pos":1,"value":25000,"height":0}]}'
	run "$BITCOIN_BIN" backend get-address-utxos bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4
	[ "$status" -eq 0 ]
	# Same shape the mempool backend emits (.value per utxo).
	[ "$(printf '%s' "$output" | jq '[.[].value] | add')" = "75000" ]
	[[ "$output" == *'"txid":"aa"'* ]]
}

@test "FEAT-059 AC3 — chain-height returns headers.subscribe height" {
	setup_backend_env
	export BITCOIN_BACKEND=fulcrum
	fulcrum_fixture blockchain.headers.subscribe '{"id":1,"result":{"height":800123}}'
	run "$BITCOIN_BIN" backend chain-height
	[ "$status" -eq 0 ]
	[ "$output" = "800123" ]
}

@test "FEAT-059 AC3 — get-address-txs returns get_history entries" {
	setup_backend_env
	export BITCOIN_BACKEND=fulcrum
	fulcrum_fixture blockchain.scripthash.get_history \
		'{"id":1,"result":[{"tx_hash":"cc","height":799000}]}'
	run "$BITCOIN_BIN" backend get-address-txs bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4
	[ "$status" -eq 0 ]
	[[ "$output" == *'"txid":"cc"'* ]]
}

@test "FEAT-059 AC3 — estimate-fee converts BTC/kvB to sat/vB" {
	setup_backend_env
	export BITCOIN_BACKEND=fulcrum
	fulcrum_fixture blockchain.estimatefee '{"id":1,"result":0.00002}'
	run "$BITCOIN_BIN" backend estimate-fee 3
	[ "$status" -eq 0 ]
	[ "$output" = "2" ]
}

@test "FEAT-059 AC4 — broadcast returns the txid from the reply" {
	setup_backend_env
	export BITCOIN_BACKEND=fulcrum
	fulcrum_fixture blockchain.transaction.broadcast '{"id":1,"result":"deadbeeftxid"}'
	run "$BITCOIN_BIN" backend broadcast 0200000001abcd
	[ "$status" -eq 0 ]
	[ "$output" = "deadbeeftxid" ]
}

@test "FEAT-059 AC4 — broadcast surfaces a server error as error + non-zero" {
	setup_backend_env
	export BITCOIN_BACKEND=fulcrum
	fulcrum_fixture blockchain.transaction.broadcast \
		'{"id":1,"error":{"message":"bad-txns-inputs-missingorspent"}}'
	run "$BITCOIN_BIN" backend broadcast 0200000001abcd
	[ "$status" -ne 0 ]
	[[ "$output" == *"bad-txns-inputs-missingorspent"* ]]
}

@test "FEAT-059 AC5 — a connection failure errors (naming the host) and exits non-zero" {
	setup_backend_env
	export BITCOIN_BACKEND=fulcrum
	unset BITCOIN_FULCRUM_FIXTURE
	export BITCOIN_FULCRUM_ADDR=127.0.0.1:65533    # closed port, no fixture
	run "$BITCOIN_BIN" backend chain-height
	[ "$status" -ne 0 ]
	[[ "$output" == *"65533"* ]]
	[ -z "$output" ] && { echo "expected non-empty error"; return 1; } || true
}

@test "FEAT-059 AC6 — wallet balance sums correctly with the fulcrum backend" {
	setup_wallet_derive_env
	export BITCOIN_BACKEND=fulcrum
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	# One queried address; listunspent totals 12345 + 6789 = 19134.
	fulcrum_fixture blockchain.scripthash.listunspent \
		'{"id":1,"result":[{"tx_hash":"aa","tx_pos":0,"value":12345,"height":800000},{"tx_hash":"bb","tx_pos":1,"value":6789,"height":800001}]}'
	run "$BITCOIN_BIN" wallet balance alice
	[ "$status" -eq 0 ]
	[ "$output" = "19134" ]
}

@test "FEAT-059 AC7 — the fulcrum backend never invokes the 'fulcrum' command" {
	# Boundary: bin/bitcoin-node must not shell out to the fulcrum/fulcrumd
	# command (the backend speaks Electrum directly). Function names like
	# backend:fulcrum:... are fine; a bare 'fulcrum '/'fulcrumd ' command
	# at statement start or in $(...) is the violation.
	script="$BITCOIN_BIN"
	! grep -qE "^[[:space:]]*fulcrumd?[[:space:]]" "$script"
	! grep -qE "\\\$\\([[:space:]]*fulcrumd?[[:space:]]" "$script"
}
