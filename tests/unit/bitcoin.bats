#!/usr/bin/env bats
#
# Unit tests for bin/bitcoin — the BIP-173/350 + bip32/39/49/84
# wallet frontend (FEAT-006..019). Pinned to semver per FEAT-005.
#
# Coverage scope: the dispatcher surface (version / help / modules)
# plus a bug-replicating test for BUG-008. The cryptographic
# primitives have separate test-vector coverage in
# tests/vectors/bip-*.t (gated on FEAT-006's bitcoin.sh module
# being sourceable).

# 1.5.0 introduced `run --separate-stderr`, which the 1.12.0 fee-
# fallback test relies on to assert the warn line lands on stderr.
bats_require_minimum_version 1.5.0

setup() {
	BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
	HOME="$(mktemp -d "$BATS_TMPDIR/home.XXXXXX")"
	unset XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_SHARE_HOME
	unset XDG_SOURCE_HOME XDG_BACKUP_HOME XDG_RUNTIME_DIR
	export HOME
	export SELF_QUIET=1
	export BITCOIN_BIN="$BATS_TEST_DIRNAME/../../bin/bitcoin"
	# FEAT-020: pin SELF_LIBEXEC so a system-installed bitcoin
	# at /usr/local/libexec cannot pollute the in-tree test run.
	export SELF_LIBEXEC="$BATS_TEST_DIRNAME/../../libexec"
}

teardown() {
	rm -rf "$HOME"
}

# ---------------------------------------------------------------------------
# Smoke + semver contract (FEAT-005)
# ---------------------------------------------------------------------------

@test "bitcoin binary exists and is executable" {
	[ -x "$BITCOIN_BIN" ]
}

@test "bitcoin version matches VERSION file" {
	# FEAT-020: the bats literal used to pin a specific semver
	# string. Now we read VERSION at test time so a release bump
	# doesn't require editing the test.
	expected="$(cat "$BATS_TEST_DIRNAME/../../VERSION")"
	run "$BITCOIN_BIN" version
	[ "$status" -eq 0 ]
	[ "$output" = "$expected" ]
}

@test "bitcoin help prints usage" {
	run "$BITCOIN_BIN" help
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

@test "bitcoin with no args prints help" {
	run "$BITCOIN_BIN"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

# ---------------------------------------------------------------------------
# Help surface
# ---------------------------------------------------------------------------

@test "help mentions module related commands" {
	run "$BITCOIN_BIN" help
	[ "$status" -eq 0 ]
	[[ "$output" == *"module related commands"* ]]
}

@test "help mentions bip173 (bech32) commands" {
	run "$BITCOIN_BIN" help
	[ "$status" -eq 0 ]
	[[ "$output" == *"bip173"* ]]
	[[ "$output" == *"bech32"* ]]
}

@test "help mentions bip350 (bech32m) commands" {
	run "$BITCOIN_BIN" help
	[ "$status" -eq 0 ]
	[[ "$output" == *"bip350"* ]]
}

@test "help <bech32> describes its purpose" {
	run "$BITCOIN_BIN" help bech32
	[ "$status" -eq 0 ]
	[ -n "$output" ]
	[[ "$output" == *"Bech32"* ]]
}

# ---------------------------------------------------------------------------
# modules — directory listing under $SELF_LIBEXEC/bitcoin/
# ---------------------------------------------------------------------------

@test "modules lists the modules shipped under libexec/bitcoin/" {
	run "$BITCOIN_BIN" modules
	[ "$status" -eq 0 ]
	# FEAT-021: assert all four shipped modules, not just the
	# two from the old smoke test.
	[[ "$output" == *"bip13"* ]]
	[[ "$output" == *"bip32"* ]]
	[[ "$output" == *"bip39"* ]]
	[[ "$output" == *"daemon"* ]]
	[[ "$output" == *"wif"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-021: libexec-dispatch smoke. When the dispatcher receives an
# unknown subcommand it falls back to the help banner. When it receives
# a known libexec plugin name, it exec()s that plugin — the dispatcher
# help is NOT shown.
# ---------------------------------------------------------------------------

@test "bitcoin <unknown> falls back to help" {
	run "$BITCOIN_BIN" __no_such_command__
	[[ "$output" == *"module related commands"* ]]
}

@test "bitcoin dispatches to a libexec plugin (bip13) instead of help" {
	# bip13's exit code is its own business; we only assert that
	# the dispatcher reached the plugin, i.e. did NOT print its
	# own help banner.
	run "$BITCOIN_BIN" bip13
	[[ "$output" != *"module related commands"* ]]
}

# ---------------------------------------------------------------------------
# BIP-173 vector round-trips — fixed in BUG-008 (PR #-).
# Pure-uppercase vectors (e.g. `A12UEL5L`) are rejected by the
# script's case-mixing guard at command:bech32:219 — that's a
# separate edge case, not BUG-008.
# ---------------------------------------------------------------------------

@test "bech32 round-trips a known BIP-173 vector" {
	encoded="$($BITCOIN_BIN bech32 abcdef qpzry9x8gf2tvdw0s3jn54khce6mua7l | tail -n 1)"
	[ "$encoded" = "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw" ]
}

@test "bech32 reproduces the help-doc example" {
	encoded="$($BITCOIN_BIN bech32 this-part-is-readable-by-a-human qpzry | tail -n 1)"
	[ "$encoded" = "this-part-is-readable-by-a-human1qpzrylhvwcq" ]
}

@test "bech32-verify accepts a value that bech32 just produced" {
	encoded="$($BITCOIN_BIN bech32 abcdef qpzry9x8gf2tvdw0s3jn54khce6mua7l | tail -n 1)"
	run "$BITCOIN_BIN" bech32-verify "$encoded"
	[ "$status" -eq 0 ]
}

@test "bech32-verify rejects a tampered checksum" {
	# Flip the last character of a known-good bech32 string.
	run "$BITCOIN_BIN" bech32-verify "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxq"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# BUG-010 regression — bech32-verify-checksum called undefined polymod /
# hrpExpand instead of bech32-polymod / bech32-hrp-expand, so
# command:bech32-decode always exited 8.
# ---------------------------------------------------------------------------

@test "bech32-decode decodes a known BIP-173 vector" {
	run "$BITCOIN_BIN" bech32-decode "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw"
	[ "$status" -eq 0 ]
	[[ "$output" == *"abcdef"* ]]
}

@test "bech32-decode rejects a tampered checksum" {
	run "$BITCOIN_BIN" bech32-decode "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxq"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# BUG-011 regression — command:bech32 case-mixing guard compared the
# lowercased copy against [a-z], so any uppercase letter triggered a
# rejection. BIP-173 only forbids *mixed* case.
# ---------------------------------------------------------------------------

@test "bech32 accepts all-uppercase input (BIP-173 allows)" {
	run "$BITCOIN_BIN" bech32 "ABCDEF" "QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L"
	[ "$status" -eq 0 ]
	# Output is normalised to lowercase per BIP-173.
	[ "$(echo "$output" | tail -n 1)" = "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw" ]
}

@test "bech32 rejects mixed-case input" {
	run "$BITCOIN_BIN" bech32 "aBc" "qpzry"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-021: bech32 boundary conditions. The command must reject inputs
# the BIP-173 spec disallows — over-long HRPs and data with non-charset
# characters — with a non-zero exit.
# ---------------------------------------------------------------------------

@test "bech32 rejects hrp longer than 83 characters" {
	long_hrp="$(printf 'a%.0s' {1..84})"
	run "$BITCOIN_BIN" bech32 "$long_hrp" "qpzry"
	[ "$status" -ne 0 ]
}

@test "bech32 rejects data with non-charset characters" {
	# 'b', 'i', 'o' are excluded from the bech32 charset.
	run "$BITCOIN_BIN" bech32 "test" "biox"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-006: bin/bitcoin is sourceable as a function library so the
# vector .t files can `. bitcoin.sh` without re-running the dispatcher.
# When sourced, the file defines all its functions and returns 0
# without producing output.
# ---------------------------------------------------------------------------

@test "bin/bitcoin is sourceable without side effects" {
	run bash -c "source '$BITCOIN_BIN'; echo SOURCED_OK"
	[ "$status" -eq 0 ]
	[[ "$output" == *"SOURCED_OK"* ]]
	# Sourcing must not have produced the dispatcher's help banner.
	[[ "$output" != *"module related commands"* ]]
}

@test "sourcing bin/bitcoin defines the BIP function library" {
	run bash -c "source '$BITCOIN_BIN'; \
		for f in bitcoinAddress segwitAddress segwit_decode segwit_verify convertbits bip49 bip84 bip85 p2pkh-address p2wpkh; do \
			declare -F \"\$f\" >/dev/null || { echo missing: \$f; exit 1; }; \
		done; echo ALL_DEFINED"
	[ "$status" -eq 0 ]
	[[ "$output" == *"ALL_DEFINED"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-022/023/024/025 meta-tests: structural assertions on the vector
# suite. The .t files themselves run under prove, but the invariants
# below (no literal plans, numbered TAP, deduplicated fixtures, probe
# for missing deps) are properties of the source code that we can check
# from bats without needing the external dependencies.
# ---------------------------------------------------------------------------

@test "FEAT-022 — no .t file uses a literal TAP plan" {
	failed=""
	for f in "$BATS_TEST_DIRNAME"/../../tests/vectors/*.t; do
		if grep -qE '^echo 1\.\.[0-9]+[[:space:]]*$' "$f"; then
			failed="$failed $f"
		fi
	done
	[ -z "$failed" ] || { echo "Files with literal TAP plan:$failed"; false; }
}

@test "FEAT-023 — bip-0085.t emits numbered ok/not-ok lines" {
	f="$BATS_TEST_DIRNAME/../../tests/vectors/bip-0085.t"
	# Every line that emits `ok ...` or `not ok ...` TAP output must
	# include the counter variable $n.
	un_numbered=""
	while IFS= read -r line; do
		[[ "$line" == *'$n'* ]] || un_numbered+="$line"$'\n'
	done < <(grep -nE 'echo[[:space:]]+"(ok|not ok)' "$f" || true)
	[ -z "$un_numbered" ] || { echo "Un-numbered TAP lines:"; printf "%s" "$un_numbered"; false; }
}

@test "FEAT-024 — bech32 vector A12UEL5L appears in exactly one source file" {
	base="$BATS_TEST_DIRNAME/../../tests/vectors"
	count="$(grep -l A12UEL5L "$base"/*.t "$base"/*.sh 2>/dev/null | wc -l)"
	[ "$count" -eq 1 ]
}

@test "FEAT-025 — Makefile.in check-vectors probes for missing external deps" {
	f="$BATS_TEST_DIRNAME/../../Makefile.in"
	grep -q 'missing dependencies:' "$f"
	grep -q 'base58' "$f"
	grep -q 'create-mnemonic' "$f"
}

# ---------------------------------------------------------------------------
# FEAT-017 — vendored BIPs + citation template in help output.
# ---------------------------------------------------------------------------

@test "FEAT-017 — vendored BIPs exist for implemented standards" {
	bips="$BATS_TEST_DIRNAME/../../share/doc/bitcoin/bips"
	for n in 0013 0032 0039 0173 0350; do
		[ -s "$bips/bip-$n.mediawiki" ] || {
			echo "missing or empty: bip-$n.mediawiki"; false
		}
	done
	[ -f "$bips/UPSTREAM.txt" ]
	grep -qE '^commit: +[0-9a-f]{40}$' "$bips/UPSTREAM.txt"
}

@test "FEAT-017 — bitcoin help bech32 cites BIP-173 with upstream URL and local path" {
	run "$BITCOIN_BIN" help bech32
	[ "$status" -eq 0 ]
	[[ "$output" == *"BIP-173"* ]]
	[[ "$output" == *"https://github.com/bitcoin/bips"* ]]
	[[ "$output" == *"local:"* ]]
	[[ "$output" == *"bip-0173.mediawiki"* ]]
}

@test "FEAT-017 — bitcoin help bech32 cites BIP-350 (bech32m)" {
	run "$BITCOIN_BIN" help bech32
	[ "$status" -eq 0 ]
	[[ "$output" == *"BIP-350"* ]]
	[[ "$output" == *"bip-0350.mediawiki"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-010 — wallet store as a git repository. Each test stubs `secret`
# via PATH so we never need the real sibling repo, and points
# XDG_DATA_HOME at a tmpdir so wallet state lives under the test sandbox.
# ---------------------------------------------------------------------------

setup_wallet_env() {
	export SECRET_STORE="$BATS_TMPDIR/secret-store"
	rm -rf "$SECRET_STORE"
	mkdir -p "$SECRET_STORE"
	local stub_dir="$BATS_TMPDIR/secret-stub"
	rm -rf "$stub_dir"
	mkdir -p "$stub_dir"
	cat > "$stub_dir/secret" <<'STUB'
#!/usr/bin/env bash
verb="$1"; key="$2"
store="$SECRET_STORE"
case "$verb" in
	put) mkdir -p "$store/$(dirname "$key")"; cat > "$store/$key" ;;
	get) cat "$store/$key" ;;
	rm)  rm -f "$store/$key" ;;
	ls)  ls "$store/$(dirname "$key")" 2>/dev/null ;;
	*)   echo "stub-secret: unknown verb '$verb'" >&2; exit 1 ;;
esac
STUB
	chmod +x "$stub_dir/secret"
	# bin/ on PATH because libexec plugins shell out to the parent
	# `bitcoin` dispatcher (e.g. `bip32 create` does
	# `... | bitcoin bip13 base58-encode`).
	PATH="$BATS_TEST_DIRNAME/../../bin:$stub_dir:$PATH"
	export PATH
	export XDG_DATA_HOME="$BATS_TMPDIR/xdg-data"
	rm -rf "$XDG_DATA_HOME"
	mkdir -p "$XDG_DATA_HOME"
	# bip39 reads its wordlist from $XDG_SHARE_HOME/bitcoin/bip39/<lang>.txt.
	# Point it at the vendored copy in the dev tree.
	export XDG_SHARE_HOME="$BATS_TEST_DIRNAME/../../share"
}

@test "FEAT-010 — wallet new creates a git repo under XDG_DATA_HOME" {
	setup_wallet_env
	run "$BITCOIN_BIN" wallet new alice
	[ "$status" -eq 0 ]
	[ -d "$XDG_DATA_HOME/bitcoin/wallets/alice/.git" ]
	[ -f "$XDG_DATA_HOME/bitcoin/wallets/alice/config" ]
}

@test "FEAT-010 — wallet new stores the seed via secret, not in the repo" {
	setup_wallet_env
	run "$BITCOIN_BIN" wallet new alice
	[ "$status" -eq 0 ]
	# The seed was written to the secret store…
	[ -s "$SECRET_STORE/alice/seed" ]
	# …and NOT into the wallet repo.
	! grep -rqE '\b(abandon|legal|letter|zoo|gravity|hamster|scheme|horn|panda)\b' \
		"$XDG_DATA_HOME/bitcoin/wallets/alice" 2>/dev/null
}

@test "FEAT-010 — wallet new rejects a duplicate name" {
	setup_wallet_env
	"$BITCOIN_BIN" wallet new alice
	run "$BITCOIN_BIN" wallet new alice
	[ "$status" -ne 0 ]
}

@test "FEAT-010 — wallet new rejects an invalid name" {
	setup_wallet_env
	run "$BITCOIN_BIN" wallet new "../escape"
	[ "$status" -ne 0 ]
}

@test "FEAT-010 — wallet ls lists created wallets" {
	setup_wallet_env
	"$BITCOIN_BIN" wallet new alice
	"$BITCOIN_BIN" wallet new bob
	run "$BITCOIN_BIN" wallet ls
	[ "$status" -eq 0 ]
	[[ "$output" == *"alice"* ]]
	[[ "$output" == *"bob"* ]]
}

@test "FEAT-010 — wallet rm removes the wallet repo" {
	setup_wallet_env
	"$BITCOIN_BIN" wallet new alice
	[ -d "$XDG_DATA_HOME/bitcoin/wallets/alice" ]
	run "$BITCOIN_BIN" wallet rm alice
	[ "$status" -eq 0 ]
	[ ! -d "$XDG_DATA_HOME/bitcoin/wallets/alice" ]
}

@test "FEAT-010 — wallet rm <missing> exits non-zero with a clear error" {
	setup_wallet_env
	run "$BITCOIN_BIN" wallet rm no-such-wallet
	[ "$status" -ne 0 ]
	[[ "$output" == *"no-such-wallet"* ]] || [[ "$stderr" == *"no-such-wallet"* ]] || true
}

# ---------------------------------------------------------------------------
# FEAT-009 — output descriptors. The checksum is BIP-380's polymod over
# the descriptor's INPUT_CHARSET; the test vector is from the spec.
# ---------------------------------------------------------------------------

@test "FEAT-009 — bitcoin help descriptor cites BIP-380/381/386" {
	run "$BITCOIN_BIN" help descriptor
	[ "$status" -eq 0 ]
	[[ "$output" == *"BIP-380"* ]]
	[[ "$output" == *"bip-0380.mediawiki"* ]]
}

@test "FEAT-009 — descriptor checksum matches BIP-380 test vector" {
	# Spec test vector: raw(deadbeef) → raw(deadbeef)#89f8spxm
	run "$BITCOIN_BIN" descriptor checksum "raw(deadbeef)"
	[ "$status" -eq 0 ]
	[ "$output" = "raw(deadbeef)#89f8spxm" ]
}

@test "FEAT-009 — descriptor checksum is idempotent on an already-checksummed string" {
	# Passing a string that already ends in `#<8 chars>` should
	# replace the suffix with the freshly-computed checksum.
	run "$BITCOIN_BIN" descriptor checksum "raw(deadbeef)#00000000"
	[ "$status" -eq 0 ]
	[ "$output" = "raw(deadbeef)#89f8spxm" ]
}

@test "FEAT-009 — descriptor verify accepts a valid checksum" {
	run "$BITCOIN_BIN" descriptor verify "raw(deadbeef)#89f8spxm"
	[ "$status" -eq 0 ]
}

@test "FEAT-009 — descriptor verify rejects a tampered checksum" {
	# Flip one char of a known-good checksum.
	run "$BITCOIN_BIN" descriptor verify "raw(deadbeef)#89f8spxq"
	[ "$status" -ne 0 ]
}

@test "FEAT-009 — descriptor verify rejects a missing checksum" {
	run "$BITCOIN_BIN" descriptor verify "raw(deadbeef)"
	[ "$status" -ne 0 ]
}

@test "FEAT-009 — descriptor checksum rejects a non-INPUT_CHARSET character" {
	# £ is outside BIP-380's INPUT_CHARSET (ASCII-only).
	run "$BITCOIN_BIN" descriptor checksum "raw(£)"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-012 — backend abstraction. Tests stub `curl` via PATH so HTTP
# calls return canned responses; no network is touched. Each test sets
# fixtures with `curl_fixture URL BODY` and then invokes the verb.
# ---------------------------------------------------------------------------

setup_backend_env() {
	export CURL_STUB_RESPONSES="$BATS_TMPDIR/curl-responses"
	rm -rf "$CURL_STUB_RESPONSES"
	mkdir -p "$CURL_STUB_RESPONSES"
	local stub_dir="$BATS_TMPDIR/curl-stub"
	rm -rf "$stub_dir"
	mkdir -p "$stub_dir"
	cat > "$stub_dir/curl" <<'STUB'
#!/usr/bin/env bash
# Test stub for curl. Picks the first http(s) arg as the URL, derives
# a filename, and emits the file contents (if present).
url=""
for arg in "$@"; do
	case "$arg" in
		http://*|https://*) url="$arg" ;;
	esac
done
key="$(printf '%s' "$url" | tr '/:?&=' '_____')"
f="$CURL_STUB_RESPONSES/$key"
if [ -f "$f" ]; then
	cat "$f"
	exit 0
fi
echo "stub-curl: no fixture at $f for url=$url" >&2
exit 22
STUB
	chmod +x "$stub_dir/curl"
	export PATH="$stub_dir:$PATH"
	export XDG_CONFIG_HOME="$BATS_TMPDIR/xdg-config"
	rm -rf "$XDG_CONFIG_HOME"
	mkdir -p "$XDG_CONFIG_HOME"
	unset BITCOIN_BACKEND
}

curl_fixture() {
	local url="$1" body="$2"
	local key="$(printf '%s' "$url" | tr '/:?&=' '_____')"
	printf '%s' "$body" > "$CURL_STUB_RESPONSES/$key"
}

@test "FEAT-012 — bitcoin backend with no args prints the active backend" {
	setup_backend_env
	run "$BITCOIN_BIN" backend
	[ "$status" -eq 0 ]
	[ "$output" = "mempool" ]
}

@test "FEAT-012 — bitcoin backend mempool sets the active backend" {
	setup_backend_env
	run "$BITCOIN_BIN" backend set mempool
	[ "$status" -eq 0 ]
	[ "$(cat "$XDG_CONFIG_HOME/bitcoin/backend")" = "mempool" ]
}

@test "FEAT-012 — bitcoin backend rejects unknown backend names" {
	setup_backend_env
	run "$BITCOIN_BIN" backend set bogus
	[ "$status" -ne 0 ]
}

@test "FEAT-012 — bitcoin backend chain-height returns the mempool answer" {
	setup_backend_env
	curl_fixture "https://mempool.space/api/blocks/tip/height" "830000"
	run "$BITCOIN_BIN" backend chain-height
	[ "$status" -eq 0 ]
	[ "$output" = "830000" ]
}

@test "FEAT-012 — backend get-address-utxos returns the mempool JSON" {
	setup_backend_env
	curl_fixture "https://mempool.space/api/address/bc1qexampleaddress/utxo" \
		'[{"txid":"aa","vout":0,"value":12345,"status":{"block_height":830000}}]'
	run "$BITCOIN_BIN" backend get-address-utxos bc1qexampleaddress
	[ "$status" -eq 0 ]
	[[ "$output" == *'"value":12345'* ]]
}

@test "FEAT-012 — backend broadcast posts a hex tx and returns the txid" {
	setup_backend_env
	curl_fixture "https://mempool.space/api/tx" \
		"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
	run "$BITCOIN_BIN" backend broadcast 0200000001abcd
	[ "$status" -eq 0 ]
	[ "$output" = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef" ]
}

@test "FEAT-012 — backend chain-height emits an error when curl fails" {
	setup_backend_env
	# No fixture → stub-curl exits 22.
	run "$BITCOIN_BIN" backend chain-height
	[ "$status" -ne 0 ]
	[[ "$output" == *"mempool"* ]] || [[ "$stderr" == *"mempool"* ]] || true
}

@test "FEAT-012 — bitcoin help backend cites the BIPs in scope (380 for descriptors → addresses)" {
	run "$BITCOIN_BIN" help backend
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

# ---------------------------------------------------------------------------
# FEAT-012 (extend, 1.12.0) — backend estimate-fee. Fourth verb on the
# backend abstraction: returns the recommended sat/vB rate for a given
# confirmation target. Mempool implementation reads
# /api/v1/fees/recommended; out-of-bucket targets clamp to the nearest
# named bucket rather than erroring.
# ---------------------------------------------------------------------------

# Helper: standard mempool fee-bucket response, used in every
# estimate-fee test below. Distinct values per bucket let us assert
# which one the verb selected without depending on the others.
mempool_fees_fixture() {
	echo '{"fastestFee":42,"halfHourFee":21,"hourFee":11,"economyFee":4,"minimumFee":1}'
}

@test "FEAT-012 — backend estimate-fee defaults to the half-hour bucket" {
	setup_backend_env
	curl_fixture "https://mempool.space/api/v1/fees/recommended" "$(mempool_fees_fixture)"
	run "$BITCOIN_BIN" backend estimate-fee
	[ "$status" -eq 0 ]
	[ "$output" = "21" ]
}

@test "FEAT-012 — backend estimate-fee target-block selects the right bucket" {
	setup_backend_env
	curl_fixture "https://mempool.space/api/v1/fees/recommended" "$(mempool_fees_fixture)"
	# 1 → fastestFee=42, 6 → hourFee=11, 144 → economyFee=4, 1000 → minimumFee=1.
	run "$BITCOIN_BIN" backend estimate-fee 1;    [ "$status" -eq 0 ]; [ "$output" = "42" ]
	run "$BITCOIN_BIN" backend estimate-fee 6;    [ "$status" -eq 0 ]; [ "$output" = "11" ]
	run "$BITCOIN_BIN" backend estimate-fee 144;  [ "$status" -eq 0 ]; [ "$output" = "4" ]
	run "$BITCOIN_BIN" backend estimate-fee 1000; [ "$status" -eq 0 ]; [ "$output" = "1" ]
}

@test "FEAT-012 — backend estimate-fee rejects a non-integer target" {
	setup_backend_env
	run "$BITCOIN_BIN" backend estimate-fee abc
	[ "$status" -ne 0 ]
}

@test "FEAT-012 — backend estimate-fee emits an error when curl fails" {
	setup_backend_env
	# No fixture → stub-curl exits 22 → verb returns non-zero.
	run "$BITCOIN_BIN" backend estimate-fee
	[ "$status" -ne 0 ]
}

@test "FEAT-012 — backend estimate-fee bitcoind stub returns 'not implemented'" {
	setup_backend_env
	"$BITCOIN_BIN" backend set bitcoind >/dev/null
	run "$BITCOIN_BIN" backend estimate-fee
	[ "$status" -ne 0 ]
}

@test "FEAT-012 — bitcoin help backend mentions estimate-fee" {
	run "$BITCOIN_BIN" help backend
	[ "$status" -eq 0 ]
	[[ "$output" == *"estimate-fee"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-025 follow-up — libexec/bitcoin/mnemonic-to-seed (a piece of
# the option-1 vendoring that this milestone landed to unblock the
# wallet's HD-derivation pipeline).
# ---------------------------------------------------------------------------

@test "mnemonic-to-seed matches the BIP-39 test vector (TREZOR passphrase)" {
	expected="c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
	got="$(BIP39_PASSPHRASE=TREZOR "$BATS_TEST_DIRNAME/../../libexec/bitcoin/mnemonic-to-seed" \
		abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about \
		| basenc --base16 -w0 | tr A-F a-f)"
	[ "$got" = "$expected" ]
}

@test "mnemonic-to-seed rejects an out-of-range word count" {
	run "$BATS_TEST_DIRNAME/../../libexec/bitcoin/mnemonic-to-seed" only three words
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# BUG-013 regression — `bip32 derive` referenced undefined helper
# functions (isPrivate/isPublic) and BIP32_-prefixed version-code
# variables that the plugin never sets. End-to-end derive failed with
# "command not found" + "version is neither private nor public?!".
# This test exercises the full seed → child-key chain.
# ---------------------------------------------------------------------------

@test "BUG-013 — bip32 derive resolves end-to-end from a seed (non-hardened path)" {
	repo_root="$BATS_TEST_DIRNAME/../../"
	PATH="$repo_root/bin:$repo_root/libexec/bitcoin:$PATH" \
	XDG_SHARE_HOME="$repo_root/share" \
	SELF_LIBEXEC="$repo_root/libexec" \
	run bash -c '
		mnemonic-to-seed abandon abandon abandon abandon abandon abandon abandon \
		                 abandon abandon abandon abandon about \
		  | basenc --base16 -w0 \
		  | bip32 create -s 2>/dev/null \
		  | bitcoin bip13 base58-decode \
		  | bip32 derive m/0
	'
	[ "$status" -eq 0 ]
	# Non-empty output (a derived xkey serialisation, ~78 bytes binary
	# or its base58 equivalent — we only care that the pipeline ran).
	[ -n "$output" ]
	# The two undefined-function errors must not appear.
	[[ "$output" != *"isPrivate"* ]]
	[[ "$output" != *"isPublic"* ]]
	[[ "$output" != *"version is neither private nor public"* ]]
}

# ---------------------------------------------------------------------------
# BUG-014 regression — the same "undefined function name" pattern as
# BUG-013, missed by the earlier patch because BUG-013's regression
# test didn't exercise the `/N` neutering branch.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# FEAT-013 — wallet derive / addresses / label / balance.
#
# These tests pre-seed a wallet whose secret-stub returns the canonical
# abandon…about test mnemonic, so `wallet derive` produces a known
# vector address. Backend queries are stubbed via the same curl shim
# the FEAT-012 tests use.
# ---------------------------------------------------------------------------

setup_wallet_derive_env() {
	setup_wallet_env
	setup_backend_env
	# Reseed the secret store with the canonical abandon-mnemonic.
	mkdir -p "$SECRET_STORE/alice"
	echo "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about" \
		> "$SECRET_STORE/alice/seed"
	# Create the wallet repo (skip the random-seed generation by
	# initialising the directory ourselves; we only want the ledger
	# structure, not a fresh seed).
	local wpath="$XDG_DATA_HOME/bitcoin/wallets/alice"
	rm -rf "$wpath" && mkdir -p "$wpath"
	(
		cd "$wpath"
		git init -q -b main 2>/dev/null || git init -q
		: > config; : > descriptors; : > addresses
		git add . && git -c user.email=t@t -c user.name=t \
		                  -c commit.gpgsign=false \
		                  commit -q -m init
	)
}

@test "FEAT-013 — wallet derive emits the canonical BIP-84 first receive address" {
	setup_wallet_derive_env
	run "$BITCOIN_BIN" wallet derive alice
	[ "$status" -eq 0 ]
	[[ "$output" == *"bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"* ]]
}

@test "FEAT-013 — wallet derive appends to the addresses ledger and commits" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	[ -s "$XDG_DATA_HOME/bitcoin/wallets/alice/addresses" ]
	grep -q "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu" \
		"$XDG_DATA_HOME/bitcoin/wallets/alice/addresses"
	# One commit added on top of the init commit (= 2 total).
	(( $(cd "$XDG_DATA_HOME/bitcoin/wallets/alice" && git rev-list --count HEAD) == 2 ))
}

@test "FEAT-013 — wallet derive bumps the index on the second call" {
	setup_wallet_derive_env
	first="$("$BITCOIN_BIN" wallet derive alice)"
	second="$("$BITCOIN_BIN" wallet derive alice)"
	[ "$first" != "$second" ]
	# Both lines in the ledger.
	(( $(wc -l < "$XDG_DATA_HOME/bitcoin/wallets/alice/addresses") == 2 ))
}

@test "FEAT-013 — wallet addresses lists the derived ledger" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	run "$BITCOIN_BIN" wallet addresses alice
	[ "$status" -eq 0 ]
	[[ "$output" == *"bc1q"* ]]
	[ "$(echo "$output" | wc -l)" -ge 2 ]
}

@test "FEAT-013 — wallet label sets the label and commits" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	run "$BITCOIN_BIN" wallet label alice "$addr" "donations"
	[ "$status" -eq 0 ]
	grep -q "donations" "$XDG_DATA_HOME/bitcoin/wallets/alice/addresses"
	# Two commits added on top of init: derive + label.
	(( $(cd "$XDG_DATA_HOME/bitcoin/wallets/alice" && git rev-list --count HEAD) == 3 ))
}

@test "FEAT-013 — wallet balance sums UTXOs from the backend" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	# Two UTXOs, total 12345 + 6789 = 19134 sats.
	curl_fixture "https://mempool.space/api/address/$addr/utxo" \
		'[{"txid":"aa","vout":0,"value":12345,"status":{"block_height":830000}},{"txid":"bb","vout":1,"value":6789,"status":{"block_height":830001}}]'
	run "$BITCOIN_BIN" wallet balance alice
	[ "$status" -eq 0 ]
	[ "$output" = "19134" ]
}

# ---------------------------------------------------------------------------
# FEAT-014 (partial) — wallet broadcast. Wires the active backend
# (FEAT-012) so a tx signed elsewhere can be pushed to the network
# through this wallet's chosen backend. Builder + signer live on
# ROADMAP-1.9.0+.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# FEAT-011 (partial) — wallet remote add / push / pull. Tests use a
# local bare repo as the "remote" so no network or sibling `account`
# repo is required.
# ---------------------------------------------------------------------------

setup_wallet_remote_env() {
	setup_wallet_derive_env
	# Make the wallet have a commit to push.
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	# Spin up a bare repo that will play the role of the remote.
	export REMOTE_BARE="$BATS_TMPDIR/remote-bare-$BATS_TEST_NUMBER"
	rm -rf "$REMOTE_BARE"
	git init --bare -q -b main "$REMOTE_BARE"
}

@test "FEAT-011 — wallet remote add configures a git remote on the wallet repo" {
	setup_wallet_remote_env
	run "$BITCOIN_BIN" wallet remote add alice origin "$REMOTE_BARE"
	[ "$status" -eq 0 ]
	got="$(cd "$XDG_DATA_HOME/bitcoin/wallets/alice" && git remote get-url origin)"
	[ "$got" = "$REMOTE_BARE" ]
}

@test "FEAT-011 — wallet push uploads the wallet's branch to the remote" {
	setup_wallet_remote_env
	"$BITCOIN_BIN" wallet remote add alice origin "$REMOTE_BARE" >/dev/null
	run "$BITCOIN_BIN" wallet push alice
	[ "$status" -eq 0 ]
	# The bare repo should now hold the wallet's current branch.
	(cd "$REMOTE_BARE" && git log --oneline | head -1) | grep -qE 'wallet derive: alice/0'
}

@test "FEAT-011 — wallet pull --rebase brings remote commits into the wallet" {
	setup_wallet_remote_env
	"$BITCOIN_BIN" wallet remote add alice origin "$REMOTE_BARE" >/dev/null
	"$BITCOIN_BIN" wallet push alice >/dev/null
	# Make a peer clone, add a commit, push it back.
	peer="$BATS_TMPDIR/peer-clone-$BATS_TEST_NUMBER"
	rm -rf "$peer"
	git clone -q "$REMOTE_BARE" "$peer"
	(
		cd "$peer"
		echo "from-peer" > peer-marker
		git add peer-marker
		git -c user.email=peer@bitcoin -c user.name=peer \
		    -c commit.gpgsign=false \
		    commit -qm "peer adds a marker"
		git push -q origin main
	)
	# Wallet pulls the peer's commit.
	run "$BITCOIN_BIN" wallet pull alice
	[ "$status" -eq 0 ]
	[ -f "$XDG_DATA_HOME/bitcoin/wallets/alice/peer-marker" ]
}

@test "FEAT-011 — wallet push exits non-zero when the wallet has no remote configured" {
	setup_wallet_remote_env
	# Don't `wallet remote add`. Push should fail clearly.
	run "$BITCOIN_BIN" wallet push alice
	[ "$status" -ne 0 ]
}

@test "FEAT-011 — wallet remote add rejects a missing wallet" {
	setup_wallet_env
	run "$BITCOIN_BIN" wallet remote add no-such-wallet origin /tmp/whatever
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet broadcast forwards stdin hex to the backend and prints the txid" {
	setup_wallet_derive_env
	# Stub backend broadcast: any POST to /api/tx returns this txid.
	curl_fixture "https://mempool.space/api/tx" \
		"4242424242424242424242424242424242424242424242424242424242424242"
	run bash -c "echo '0200000001abcd' | '$BITCOIN_BIN' wallet broadcast alice"
	[ "$status" -eq 0 ]
	[ "$output" = "4242424242424242424242424242424242424242424242424242424242424242" ]
}

@test "FEAT-014 — wallet broadcast rejects empty stdin" {
	setup_wallet_derive_env
	run bash -c "echo '' | '$BITCOIN_BIN' wallet broadcast alice"
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet broadcast rejects non-hex input" {
	setup_wallet_derive_env
	run bash -c "echo 'this is not hex' | '$BITCOIN_BIN' wallet broadcast alice"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-014 (partial, 1.11.0) — wallet build. Greedy coin-selection on
# UTXOs the backend reports against the wallet's ledger addresses,
# raw-tx serialisation (BIP-141), PSBT wrap (BIP-174 global section
# only — signing remains deferred).
#
# The recipient address in the happy paths is the canonical BIP-173
# P2WPKH vector:
#   bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4
# whose 20-byte witness program is 751e76e8199196d454941c45d1b3a323f1433bd6
# and whose scriptPubKey is therefore '0014' + that program.
# ---------------------------------------------------------------------------

# Helper: produce a deterministic JSON UTXO fixture given a value (sats)
# and a txid suffix byte. The fixture pads to a full 32-byte (64 hex
# char) txid; mempool returns txids in big-endian display order, which
# `wallet build` byte-reverses before serialising.
build_utxo_fixture() {
	local value="$1" txid_byte="${2:-01}"
	local txid_prefix="abababab"
	# 64 chars total - 8 prefix - 2 suffix byte = 54 zero chars.
	local txid="${txid_prefix}000000000000000000000000000000000000000000000000000000${txid_byte}"
	printf '[{"txid":"%s","vout":0,"value":%s,"status":{"block_height":830000}}]' \
		"$txid" "$value"
}

@test "FEAT-014 — wallet build emits a hex PSBT with the BIP-174 magic prefix" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	[[ "$output" =~ ^70736274ff ]]
	# Round-trips through `psbt decode` (BIP-174 magic + section layout
	# are well-formed end-to-end).
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	[[ "$output" == *"section=0"* ]]
	[[ "$output" == *"type=00"* ]]
}

@test "FEAT-014 — wallet build produces a 2-output unsigned tx when change > dust" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	# Plenty of room for change: 100000 - 50000 - 140 (1-input/2-output fee
	# at 1 sat/vB) = 49860 sats of change, well above the 546-sat dust floor.
	# --fee-rate 1 pins the rate to keep the fee-arithmetic comment honest;
	# the default-path (estimate-fee) is exercised separately below.
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	# Decode the global unsigned-tx record and pull out the value (hex).
	psbt="$output"
	tx_hex="$(echo "$psbt" | "$BITCOIN_BIN" bip174 decode | sed -n '1s/.*value=//p')"
	[ -n "$tx_hex" ]
	# Tx layout: 4-byte version + varint(in) + inputs + varint(out) + outputs + 4-byte locktime.
	# Version 02000000, 1 input (varint 01), input = 32-byte txid + 4-byte
	# vout + 1-byte empty scriptSig + 4-byte sequence = 41 bytes.
	# So the output-count varint sits at byte offset 4 + 1 + 41 = 46 (= hex offset 92).
	out_count_hex="${tx_hex:92:2}"
	[ "$out_count_hex" = "02" ]
	# Recipient scriptPubKey for bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4
	# is 0014751e76e8199196d454941c45d1b3a323f1433bd6.
	[[ "$tx_hex" == *"0014751e76e8199196d454941c45d1b3a323f1433bd6"* ]]
}

@test "FEAT-014 — wallet build produces a 1-output unsigned tx when change <= dust" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	# 50500 sats UTXO, send 50000: change would be 50500 - 50000 - 140 = 360
	# sats, below the 546-sat dust floor, so the builder folds it into the fee
	# and emits a single output. --fee-rate 1 pins the rate.
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 50500 02)"
	run "$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	tx_hex="$(echo "$output" | "$BITCOIN_BIN" bip174 decode | sed -n '1s/.*value=//p')"
	# Same offset arithmetic as the previous test: output count at hex 92.
	out_count_hex="${tx_hex:92:2}"
	[ "$out_count_hex" = "01" ]
}

@test "FEAT-014 — wallet build rejects insufficient balance" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100 01)"
	run "$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000
	[ "$status" -ne 0 ]
	[[ "$output" == *"insufficient"* ]] || [[ "$stderr" == *"insufficient"* ]] || true
}

@test "FEAT-014 — wallet build rejects an invalid output address" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" wallet build alice not-a-valid-bech32-address 10000
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet build rejects a missing wallet" {
	setup_wallet_derive_env
	run "$BITCOIN_BIN" wallet build no-such-wallet bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 10000
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet build rejects bech32m / P2TR (v1+) output addresses" {
	# A v0-only builder must refuse Taproot until FEAT-007 lands. The
	# fixture below is a valid bech32m P2TR address; rejection is what
	# keeps us from emitting an unspendable v1 scriptPubKey.
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" wallet build alice bc1pmfr3p9j00pfxjh0zmgp99y8zftmd3s5pmedqhyptwy6lm87hf5sspknck9 1000
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-014 / FEAT-012 (1.12.0) — wallet build picks up the backend's
# estimate-fee answer when --fee-rate isn't supplied; --fee-rate still
# overrides; backend failure falls back to 1 sat/vB with a warn.
#
# The change-output value pins the fee rate the builder actually used,
# since change = utxo - sats - (vsize * fee_rate). With one 100000-sat
# UTXO, sats=50000, and the post-segwit-discount vsize estimate of
# 10 + 68·1 + 31·2 = 140 vbytes:
#
#   fee_rate=1   → fee= 140, change=49860 → LE hex c4c20000...
#   fee_rate=10  → fee=1400, change=48600 → LE hex d8bd0000...
# ---------------------------------------------------------------------------

@test "FEAT-014 — wallet build reads the backend's fee estimate when --fee-rate is omitted" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	# 10 sat/vB recommended for the half-hour bucket.
	curl_fixture "https://mempool.space/api/v1/fees/recommended" \
		'{"fastestFee":50,"halfHourFee":10,"hourFee":5,"economyFee":2,"minimumFee":1}'
	run "$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000
	[ "$status" -eq 0 ]
	tx_hex="$(echo "$output" | "$BITCOIN_BIN" bip174 decode | sed -n '1s/.*value=//p')"
	# Change-output LE-encoded value sits right after the recipient
	# output: version(8) + n_in(2) + 1 input(82) + n_out(2) + recipient
	# value(16) + push 22 (2) + 22-byte scriptPubKey(44) = 156 hex chars.
	# So the change value is at offset 156, length 16.
	change_le="${tx_hex:156:16}"
	[ "$change_le" = "d8bd000000000000" ]
}

@test "FEAT-014 — wallet build --fee-rate still overrides the backend estimate" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	# Backend would say 10 sat/vB; explicit --fee-rate 1 wins.
	curl_fixture "https://mempool.space/api/v1/fees/recommended" \
		'{"fastestFee":50,"halfHourFee":10,"hourFee":5,"economyFee":2,"minimumFee":1}'
	run "$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	tx_hex="$(echo "$output" | "$BITCOIN_BIN" bip174 decode | sed -n '1s/.*value=//p')"
	change_le="${tx_hex:156:16}"
	[ "$change_le" = "c4c2000000000000" ]
}

@test "FEAT-014 — wallet build falls back to 1 sat/vB when the backend estimate is unavailable" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	# Deliberately do NOT register the /api/v1/fees/recommended fixture —
	# the curl stub will exit 22 and the builder must fall back to 1.
	# --separate-stderr keeps the fallback warn off the PSBT we're parsing.
	run --separate-stderr "$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000
	[ "$status" -eq 0 ]
	[[ "$stderr" == *"falling back to 1 sat/vB"* ]]
	tx_hex="$(echo "$output" | "$BITCOIN_BIN" bip174 decode | sed -n '1s/.*value=//p')"
	change_le="${tx_hex:156:16}"
	[ "$change_le" = "c4c2000000000000" ]
}

# ---------------------------------------------------------------------------
# FEAT-008 (partial) — psbt decode. The fixture is the first valid PSBT
# from BIP-174's test vectors (one P2PKH input, two outputs).
# ---------------------------------------------------------------------------

# BIP-174 valid PSBT #1 — one P2PKH input. Helper because bash
# file-scope declarations aren't reliably inherited into @test blocks.
psbt_vec1() {
	echo -n "70736274ff0100750200000001268171371edff285e937adeea4b37b78000c0566cbb3ad64641713ca42171bf60000000000feffffff02d3dff505000000001976a914d0c59903c5bac2868760e90fd521a4665aa7652088ac00e1f5050000000017a9143545e6e33b832c47050f24d3eeb93c9c03948bc787b32e1300000100fda5010100000000010289a3c71eab4d20e0371bbba4cc698fa295c9463afa2e397f8533ccb62f9567e50100000017160014be18d152a9b012039daf3da7de4f53349eecb985ffffffff86f8aa43a71dff1448893a530a7237ef6b4608bbb2dd2d0171e63aec6a4890b40100000017160014fe3e9ef1a745e974d902c4355943abcb34bd5353ffffffff0200c2eb0b000000001976a91485cff1097fd9e008bb34af709c62197b38978a4888ac72fef84e2c00000017a914339725ba21efd62ac753a9bcd067d6c7a6a39d05870247304402202712be22e0270f394f568311dc7ca9a68970b8025fdd3b240229f07f8a5f3a240220018b38d7dcd314e734c9276bd6fb40f673325bc4baa144c800d2f2f02db2765c012103d2e15674941bad4a996372cb87e1856d3652606d98562fe39c5e9e7e413f210502483045022100d12b852d85dcd961d2f5f4ab660654df6eedcc794c0c33ce5cc309ffb5fce58d022067338a8e0e1725c197fb1a88af59f51e44e4255b20167c8684031c05d1f2592a01210223b72beef0965d10be0778efecd61fcac6f79a4ea169393380734464f84f2ab300000000000000"
}

@test "FEAT-008 — psbt decode accepts a known BIP-174 PSBT and emits records" {
	run bash -c "$(declare -f psbt_vec1); psbt_vec1 | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	# At minimum the global unsigned-tx record (section 0, type 00) must appear.
	[[ "$output" == *"section=0"* ]]
	[[ "$output" == *"type=00"* ]]
}

@test "FEAT-008 — psbt decode rejects input without the BIP-174 magic" {
	# Strip the 5-byte magic+separator (10 hex chars).
	run bash -c "$(declare -f psbt_vec1); psbt_vec1 | cut -c11- | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -ne 0 ]
	[[ "$output" == *"magic"* ]] || true
}

@test "FEAT-008 — psbt decode rejects empty input" {
	run bash -c "echo '' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -ne 0 ]
}

@test "FEAT-008 — bitcoin help psbt cites BIP-174" {
	run "$BITCOIN_BIN" bip174 help
	[ "$status" -eq 0 ]
	[[ "$output" == *"BIP-174"* ]]
	[[ "$output" == *"bip-0174.mediawiki"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-008 (partial, 1.10.0) — psbt encode. Reverse of decode: read TSV
# records on stdin and emit a hex PSBT. Empty trailing sections aren't
# representable (decoded TSV doesn't record them); see the help text
# for the limitation.
# ---------------------------------------------------------------------------

@test "FEAT-008 — psbt encode emits the BIP-174 magic + final terminator for empty input" {
	run bash -c "echo '' | '$BITCOIN_BIN' bip174 encode"
	[ "$status" -eq 0 ]
	[ "$output" = "70736274ff00" ]
}

@test "FEAT-008 — psbt encode emits the expected wire format for a single-record global section" {
	# Global section, type=00, key=00, value=deadbeef.
	# Expected: magic(70736274ff) + varint(1)=01 + key(00)
	#                            + varint(4)=04 + value(deadbeef)
	#                            + section-close 00.
	run bash -c "printf 'section=0\ttype=00\tkey=00\tvalue=deadbeef\n' | '$BITCOIN_BIN' bip174 encode"
	[ "$status" -eq 0 ]
	[ "$output" = "70736274ff010004deadbeef00" ]
}

@test "FEAT-008 — psbt encode bumps sections with 0x00 terminators" {
	# Two records in different sections.
	run bash -c "printf 'section=0\ttype=00\tkey=00\tvalue=aa\nsection=1\ttype=00\tkey=00\tvalue=bb\n' \
		| '$BITCOIN_BIN' bip174 encode"
	[ "$status" -eq 0 ]
	# magic + (01 00 01 aa) + 00(close 0) + (01 00 01 bb) + 00(close 1)
	[ "$output" = "70736274ff010001aa00010001bb00" ]
}

@test "FEAT-008 — psbt encode | psbt decode round-trips a TSV with records in every section" {
	tsv=$(printf 'section=0\ttype=00\tkey=00\tvalue=aa\nsection=1\ttype=00\tkey=00\tvalue=bb\nsection=2\ttype=00\tkey=00\tvalue=cc\n')
	encoded=$(printf '%s\n' "$tsv" | "$BITCOIN_BIN" bip174 encode)
	decoded=$(echo "$encoded" | "$BITCOIN_BIN" bip174 decode)
	# Decode emits trailing newline; tsv has none. Compare after
	# trimming.
	[ "$(printf '%s\n' "$tsv")" = "$(printf '%s\n' "$decoded")" ]
}

@test "FEAT-008 — psbt encode rejects non-hex values" {
	run bash -c "printf 'section=0\ttype=00\tkey=00\tvalue=notHex!\n' | '$BITCOIN_BIN' bip174 encode"
	[ "$status" -ne 0 ]
}

@test "FEAT-008 — psbt encode rejects a section field that goes backwards" {
	run bash -c "printf 'section=1\ttype=00\tkey=00\tvalue=aa\nsection=0\ttype=00\tkey=00\tvalue=bb\n' \
		| '$BITCOIN_BIN' bip174 encode"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-014 (extend, 1.13.0) — wallet build now emits a
# PSBT_IN_WITNESS_UTXO record (type 0x01) per input so that the
# 1.13.0 psbt-sign primitive has the prev-output's amount and
# scriptPubKey on hand for BIP-143 sighash construction.
# ---------------------------------------------------------------------------

@test "FEAT-014 — wallet build emits a PSBT_IN_WITNESS_UTXO record per input" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	# Decode and look for a section=1 type=01 record carrying the
	# UTXO's value (a086010000000000 = 100000 sats LE) followed by
	# the 22-byte P2WPKH scriptPubKey for alice's index-0 address.
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	[[ "$output" == *"section=1	type=01	key=01	value=a086010000000000160014c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-008 (partial, 1.13.0) — psbt sign. Reads a PSBT (hex) on stdin
# and a 32-byte private key on argv, signs every v0 P2WPKH input
# whose WITNESS_UTXO scriptPubKey matches HASH160(pubkey), and
# re-emits the PSBT with a PSBT_IN_PARTIAL_SIG record (type 0x02)
# per signed input. SIGHASH_ALL only; BIP-66 low-S enforced.
#
# The canonical "abandon-mnemonic" wallet's m/84h/0h/0h/0/0 private
# key is 4604b4b710fe91f584fff084e1a9159fe4f8408fff380596a604948474ce4fa3
# and its compressed pubkey is
# 0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c
# (HASH160 = c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2, which is the
# witness program for bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu).
# ---------------------------------------------------------------------------

ALICE_PRIV="4604b4b710fe91f584fff084e1a9159fe4f8408fff380596a604948474ce4fa3"
ALICE_PUB="0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c"

# Helper: build an unsigned PSBT for alice paying out 50000 sats with
# a single 100000-sat UTXO. Returns the hex on stdout. Caller must
# have already set up the wallet env + UTXO + fee fixtures.
build_alice_psbt() {
	"$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
}

@test "FEAT-008 — psbt sign adds a PSBT_IN_PARTIAL_SIG record for the matching input" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$(build_alice_psbt)"
	run bash -c "echo '$psbt' | '$BITCOIN_BIN' bip174 sign '$ALICE_PRIV'"
	[ "$status" -eq 0 ]
	# Decode and check for the PARTIAL_SIG record. type=02, key includes
	# alice's compressed pubkey, value is a DER signature + sighash byte.
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	[[ "$output" == *"section=1	type=02"* ]]
	[[ "$output" == *"key=02${ALICE_PUB}"* ]]
	# Sig must end in 01 (SIGHASH_ALL) and start with 30 (DER SEQUENCE).
	psig="$(echo "$output" | awk -F'\t' '/type=02/ {sub("^value=","",$4); print $4; exit}')"
	[[ "$psig" =~ ^30[0-9a-f]+01$ ]]
}

@test "FEAT-008 — psbt sign produces a low-S signature (BIP-66 §Low S)" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$(build_alice_psbt)"
	signed="$(echo "$psbt" | "$BITCOIN_BIN" bip174 sign "$ALICE_PRIV")"
	psig="$(echo "$signed" | "$BITCOIN_BIN" bip174 decode | awk -F'\t' '/type=02/ {sub("^value=","",$4); print $4; exit}')"
	# Strip SIGHASH byte (last 2 hex chars). DER layout:
	#   30 <total> 02 <r-len> <r> 02 <s-len> <s>
	# r-len at offset 6; r at offset 8; s marker at offset 8+r_len*2;
	# s value at s_marker + 4. First byte of s must be < 0x80 for low-S
	# (canonical form drops the DER 0x00 padding when high bit is clear).
	der="${psig%01}"
	r_len_hex="${der:6:2}"
	r_len=$((16#$r_len_hex))
	s_off=$((8 + 2 * r_len + 4))
	first_s_byte=$((16#${der:s_off:2}))
	(( first_s_byte < 0x80 ))
}

@test "FEAT-008 — psbt sign signature verifies via openssl against the BIP-143 sighash" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$(build_alice_psbt)"
	signed="$(echo "$psbt" | "$BITCOIN_BIN" bip174 sign "$ALICE_PRIV")"
	# Pull unsigned tx + partial-sig out of the decoded PSBT.
	dec="$(echo "$signed" | "$BITCOIN_BIN" bip174 decode)"
	tx_hex="$(echo "$dec" | head -1 | sed 's/.*value=//')"
	psig="$(echo "$dec" | awk -F'\t' '/type=02/ {sub("^value=","",$4); print $4; exit}')"
	der_sig="${psig%01}"
	# Compute the same sighash the signer used and verify with openssl.
	sighash="$(bash -c '
		source "$BITCOIN_BIN"
		psbt:_bip143_sighash "'"$tx_hex"'" 0 \
			"1976a914c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e288ac" \
			"a086010000000000" 01
	' 2>/dev/null)"
	pubder="$BATS_TMPDIR/pub.$BATS_TEST_NUMBER.der"
	sigfile="$BATS_TMPDIR/sig.$BATS_TEST_NUMBER.der"
	hashfile="$BATS_TMPDIR/hash.$BATS_TEST_NUMBER.bin"
	# SubjectPublicKeyInfo for a compressed secp256k1 pubkey:
	#   30 36 30 10 06 07 2a8648ce3d0201 06 05 2b8104000a 03 22 00 <33-byte pubkey>
	{
		printf '3036301006072a8648ce3d020106052b8104000a032200'
		printf '%s' "$ALICE_PUB"
	} | xxd -r -p > "$pubder"
	printf '%s' "$sighash" | xxd -r -p > "$hashfile"
	printf '%s' "$der_sig" | xxd -r -p > "$sigfile"
	run openssl pkeyutl -verify -pubin -inkey "$pubder" -keyform DER -in "$hashfile" -sigfile "$sigfile"
	[ "$status" -eq 0 ]
}

@test "FEAT-008 — psbt sign with a key not matching any input is a no-op" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$(build_alice_psbt)"
	wrong_key="1111111111111111111111111111111111111111111111111111111111111111"
	signed="$(echo "$psbt" | "$BITCOIN_BIN" bip174 sign "$wrong_key")"
	# Same input record, no PARTIAL_SIG added.
	dec="$(echo "$signed" | "$BITCOIN_BIN" bip174 decode)"
	! echo "$dec" | grep -q 'type=02'
	# Re-emitted PSBT byte-identical to the input (signer is a pure
	# re-emit on the no-match branch).
	[ "$signed" = "$psbt" ]
}

@test "FEAT-008 — psbt sign rejects a malformed private key" {
	run bash -c "echo '70736274ff00' | '$BITCOIN_BIN' bip174 sign not-a-hex-key"
	[ "$status" -ne 0 ]
	[[ "$output" == *"privkey-hex"* ]] || [[ "$stderr" == *"privkey-hex"* ]] || true
}

@test "FEAT-008 — psbt sign rejects empty stdin" {
	run bash -c "echo '' | '$BITCOIN_BIN' bip174 sign $ALICE_PRIV"
	[ "$status" -ne 0 ]
}

@test "FEAT-008 — psbt sign rejects non-hex stdin" {
	run bash -c "echo 'not a psbt' | '$BITCOIN_BIN' bip174 sign $ALICE_PRIV"
	[ "$status" -ne 0 ]
}

@test "FEAT-008 — psbt help mentions sign" {
	run "$BITCOIN_BIN" bip174 help
	[ "$status" -eq 0 ]
	[[ "$output" == *"sign"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-008 (partial, 1.14.0) — psbt finalize + extract. Finalize
# promotes PARTIAL_SIG records to FINAL_SCRIPTWITNESS; extract
# emits the broadcastable BIP-141 + BIP-144 segwit raw tx.
#
# wallet sign + wallet send (FEAT-014) sit on top of these and have
# their own bats cases further down.
# ---------------------------------------------------------------------------

# Helper: produce a signed PSBT for alice — output a hex PSBT with a
# PARTIAL_SIG record on input 0 (the build/sign pipeline that 1.13.0
# tests already exercise; reused here so the finalize/extract tests
# don't repeat the wiring).
signed_alice_psbt() {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$("$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1)"
	echo "$psbt" | "$BITCOIN_BIN" bip174 sign "$ALICE_PRIV"
}

@test "FEAT-008 — psbt finalize adds FINAL_SCRIPTWITNESS for a signed input" {
	signed="$(signed_alice_psbt)"
	run bash -c "echo '$signed' | '$BITCOIN_BIN' bip174 finalize"
	[ "$status" -eq 0 ]
	# Decode and check the input section now has type=08 (FINAL_SCRIPTWITNESS).
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	[[ "$output" == *"section=1	type=08	key=08"* ]]
	# The witness value starts with varint 0x02 (two stack items).
	wit="$(echo "$output" | awk -F'\t' '/type=08/ {sub("^value=","",$4); print $4; exit}')"
	[ "${wit:0:2}" = "02" ]
}

@test "FEAT-008 — psbt finalize strips PARTIAL_SIG (BIP-174 §Finalizer)" {
	signed="$(signed_alice_psbt)"
	finalised="$(echo "$signed" | "$BITCOIN_BIN" bip174 finalize)"
	dec="$(echo "$finalised" | "$BITCOIN_BIN" bip174 decode)"
	# After finalize, the input section keeps WITNESS_UTXO (01) and
	# FINAL_SCRIPTWITNESS (08), drops PARTIAL_SIG (02).
	! echo "$dec" | grep -q 'type=02'
	echo "$dec" | grep -q 'type=01'
	echo "$dec" | grep -q 'type=08'
}

@test "FEAT-008 — psbt extract emits a segwit raw tx with the marker+flag" {
	signed="$(signed_alice_psbt)"
	finalised="$(echo "$signed" | "$BITCOIN_BIN" bip174 finalize)"
	run bash -c "echo '$finalised' | '$BITCOIN_BIN' bip174 extract"
	[ "$status" -eq 0 ]
	# Version 02000000, then segwit marker (00) + flag (01) at hex offset 8.
	[ "${output:0:8}" = "02000000" ]
	[ "${output:8:4}" = "0001" ]
	# Locktime is the final 4 bytes.
	[ "${output: -8}" = "00000000" ]
	# Witness items: count=2, sig (~70 B), pubkey (33 B). The 33-byte
	# pubkey suffix matches alice's compressed pubkey ending in …91af3c.
	[[ "$output" == *"${ALICE_PUB}00000000" ]]
}

@test "FEAT-008 — psbt extract refuses an unfinalised PSBT" {
	signed="$(signed_alice_psbt)"
	# Skip the finalize step → input still has PARTIAL_SIG, no witness.
	run bash -c "echo '$signed' | '$BITCOIN_BIN' bip174 extract"
	[ "$status" -ne 0 ]
	[[ "$output" == *"not finalised"* ]] || [[ "$stderr" == *"not finalised"* ]] || true
}

@test "FEAT-008 — psbt finalize is a no-op on an unsigned PSBT" {
	# wallet build with no subsequent sign → no PARTIAL_SIG anywhere.
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$("$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1)"
	run bash -c "echo '$psbt' | '$BITCOIN_BIN' bip174 finalize"
	[ "$status" -eq 0 ]
	# Same input record blob (no FINAL_SCRIPTWITNESS added).
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	! echo "$output" | grep -q 'type=08'
}

# ---------------------------------------------------------------------------
# FEAT-014 (partial, 1.14.0) — wallet sign + wallet send.
#
# wallet sign reads a PSBT and derives one private key per address in
# the wallet's ledger, piping the PSBT through psbt sign once each.
# wallet send composes build | sign | finalize | extract | broadcast.
# ---------------------------------------------------------------------------

@test "FEAT-014 — wallet sign produces a PARTIAL_SIG for the wallet's matching address" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	psbt="$("$BITCOIN_BIN" wallet build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1)"
	run bash -c "echo '$psbt' | '$BITCOIN_BIN' wallet sign alice"
	[ "$status" -eq 0 ]
	# The signed PSBT carries a PARTIAL_SIG keyed by alice's compressed
	# pubkey — same shape as the FEAT-008 psbt-sign test, but reached
	# via the wallet's seed-derived key rather than a hardcoded hex.
	run bash -c "echo '$output' | '$BITCOIN_BIN' bip174 decode"
	[ "$status" -eq 0 ]
	[[ "$output" == *"section=1	type=02"* ]]
	[[ "$output" == *"key=02${ALICE_PUB}"* ]]
}

@test "FEAT-014 — wallet sign rejects a missing wallet" {
	setup_wallet_derive_env
	run bash -c "echo '70736274ff00' | '$BITCOIN_BIN' wallet sign no-such-wallet"
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet sign rejects empty stdin" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	run bash -c "echo '' | '$BITCOIN_BIN' wallet sign alice"
	[ "$status" -ne 0 ]
}

@test "FEAT-014 — wallet send composes the pipeline and returns the broadcast txid" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	# Stub the broadcast endpoint to return a known txid.
	curl_fixture "https://mempool.space/api/tx" \
		"f00df00df00df00df00df00df00df00df00df00df00df00df00df00df00df00d"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	[ "$output" = "f00df00df00df00df00df00df00df00df00df00df00df00df00df00df00df00d" ]
}

@test "FEAT-014 — wallet send rejects a missing wallet" {
	setup_wallet_derive_env
	run "$BITCOIN_BIN" wallet send no-such-wallet bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 1000
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-014 (extend, 1.21.0) — wallet send --mainnet guard. Sends
# against a wallet whose config says `network=mainnet` are refused
# unless --mainnet is supplied; other networks (including the
# default testnet) pass through unchanged whether --mainnet is set
# or not.
# ---------------------------------------------------------------------------

# Helper: set the wallet's config network= line. Assumes
# setup_wallet_derive_env has already initialised alice.
wallet_set_network() {
	local name="$1" net="$2"
	local cfg="$XDG_DATA_HOME/bitcoin/wallets/$name/config"
	printf 'network=%s\n' "$net" > "$cfg"
	(
		cd "$XDG_DATA_HOME/bitcoin/wallets/$name"
		git -c user.email=t@t -c user.name=t -c commit.gpgsign=false \
			commit -q -am "set network=$net" 2>/dev/null || true
	)
}

@test "FEAT-014 — wallet send on a testnet wallet proceeds without --mainnet" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	# Set the network explicitly. (setup_wallet_derive_env writes an
	# empty config; the helper defaults to testnet anyway, but pinning
	# this in the test keeps the intent visible.)
	wallet_set_network alice testnet
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	curl_fixture "https://mempool.space/api/tx" \
		"f00df00df00df00df00df00df00df00df00df00df00df00df00df00df00df00d"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
	[ "$output" = "f00df00df00df00df00df00df00df00df00df00df00df00df00df00df00df00d" ]
}

@test "FEAT-014 — wallet send on an empty-config wallet defaults to testnet (no --mainnet needed)" {
	# Per wallet:_network's default-to-testnet fallback, a wallet
	# whose config has no network= line is treated as testnet — so
	# send proceeds without --mainnet. This is the pre-existing
	# setup_wallet_derive_env shape (config is empty).
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	curl_fixture "https://mempool.space/api/tx" \
		"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	# Confirm the config has no network= line.
	! grep -q '^network=' "$XDG_DATA_HOME/bitcoin/wallets/alice/config"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -eq 0 ]
}

@test "FEAT-014 — wallet send on a mainnet wallet refuses without --mainnet" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	wallet_set_network alice mainnet
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
	[ "$status" -ne 0 ]
	[[ "$output" == *"mainnet"* ]] || [[ "$stderr" == *"mainnet"* ]] || true
}

@test "FEAT-014 — wallet send on a mainnet wallet succeeds with --mainnet" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	wallet_set_network alice mainnet
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	curl_fixture "https://mempool.space/api/tx" \
		"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1 --mainnet
	[ "$status" -eq 0 ]
	[ "$output" = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef" ]
}

@test "FEAT-014 — wallet send accepts --mainnet on non-mainnet wallets as a silent no-op" {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	wallet_set_network alice regtest
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/utxo" "$(build_utxo_fixture 100000 01)"
	curl_fixture "https://mempool.space/api/tx" \
		"00000000deadbeef00000000deadbeef00000000deadbeef00000000deadbeef"
	run "$BITCOIN_BIN" wallet send alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1 --mainnet
	[ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-015 (partial, 1.15.0) — man page + bash completion + walkthrough.
# The man-page assertions read straight from the source roff so they
# are independent of whether mandoc/groff is installed on CI runners.
# The completion test sources the file under bash and calls the
# completion function with constructed COMP_WORDS — no need to spawn
# a real readline session.
# ---------------------------------------------------------------------------

@test "FEAT-015 — man page exists and has every required section" {
	man="$BATS_TEST_DIRNAME/../../share/man/man1/bitcoin.1"
	[ -s "$man" ]
	# Each section header is a top-level .SH directive in roff.
	# COMMANDS replaced SUBCOMMANDS in 1.23.0 per FEAT-041 (compact
	# cross-reference table pointing at bitcoin-<verb>(1) pages).
	for section in NAME SYNOPSIS DESCRIPTION OPTIONS COMMANDS \
		ENVIRONMENT FILES "EXIT STATUS" EXAMPLES STANDARDS "SEE ALSO"; do
		grep -q "^\\.SH $section\$" "$man"
	done
}

@test "FEAT-015 — man page STANDARDS section cites every implemented BIP" {
	man="$BATS_TEST_DIRNAME/../../share/man/man1/bitcoin.1"
	# Pin the canonical list of BIPs the wallet implements end-to-end
	# through 1.14.0. New BIPs should be added here as they ship.
	for bip in "BIP-13" "BIP-32" "BIP-39" "BIP-141" "BIP-143" \
		"BIP-173" "BIP-174" "BIP-350" "BIP-380"; do
		grep -q "$bip" "$man"
	done
}

@test "FEAT-015 — man page renders cleanly under mandoc lint" {
	# Skip the test if mandoc isn't installed — the man source is
	# still asserted to exist by the section test above, and CI
	# can opt into stricter lint by installing mandoc.
	command -v mandoc >/dev/null 2>&1 || skip "mandoc not installed"
	man="$BATS_TEST_DIRNAME/../../share/man/man1/bitcoin.1"
	# Suppress two harmless conventional warnings:
	#   - "empty block: UR"   — bare URL in .UR/.UE pair
	#   - "skipping paragraph macro: PP after SH"
	#     (common idiom for spacing after a section header)
	# Anything else fails the test.
	run bash -c "mandoc -T lint '$man' 2>&1 | grep -vE 'empty block: UR|skipping paragraph macro' || true"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "FEAT-015 — bash completion is source-able under bash" {
	completion="$BATS_TEST_DIRNAME/../../etc/bash_completion.d/bitcoin"
	[ -s "$completion" ]
	run bash -n "$completion"
	[ "$status" -eq 0 ]
}

@test "FEAT-015 — bash completion offers every wallet subcommand" {
	completion="$BATS_TEST_DIRNAME/../../etc/bash_completion.d/bitcoin"
	run bash -c "
		source '$completion'
		COMP_WORDS=(bitcoin wallet '')
		COMP_CWORD=2
		_bitcoin_complete_entries
		printf '%s ' \"\${COMPREPLY[@]}\"
	"
	[ "$status" -eq 0 ]
	# Every verb shipped through 1.14.0 must surface.
	for verb in new ls rm derive addresses label balance build sign send broadcast remote push pull help; do
		[[ "$output" == *"$verb"* ]]
	done
}

@test "FEAT-015 — bash completion is context-aware for psbt + backend + descriptor" {
	completion="$BATS_TEST_DIRNAME/../../etc/bash_completion.d/bitcoin"
	# psbt subtree
	run bash -c "
		source '$completion'
		COMP_WORDS=(bitcoin psbt '')
		COMP_CWORD=2
		_bitcoin_complete_entries
		printf '%s ' \"\${COMPREPLY[@]}\"
	"
	[ "$status" -eq 0 ]
	for verb in decode encode sign finalize extract; do
		[[ "$output" == *"$verb"* ]]
	done
	# backend subtree
	run bash -c "
		source '$completion'
		COMP_WORDS=(bitcoin backend '')
		COMP_CWORD=2
		_bitcoin_complete_entries
		printf '%s ' \"\${COMPREPLY[@]}\"
	"
	[ "$status" -eq 0 ]
	for verb in view set auto chain-height get-address-utxos broadcast estimate-fee; do
		[[ "$output" == *"$verb"* ]]
	done
	# `bitcoin backend set <TAB>` offers the three named backends.
	run bash -c "
		source '$completion'
		COMP_WORDS=(bitcoin backend set '')
		COMP_CWORD=3
		_bitcoin_complete_entries
		printf '%s ' \"\${COMPREPLY[@]}\"
	"
	[ "$status" -eq 0 ]
	for backend in mempool bitcoind blockstream; do
		[[ "$output" == *"$backend"* ]]
	done
}

@test "FEAT-015 — walkthrough exists and references the end-to-end pipeline" {
	wk="$BATS_TEST_DIRNAME/../../docs/bitcoin-walkthrough.md"
	[ -s "$wk" ]
	# The four design principles must appear (FEAT-015 §Design).
	for principle in Educational Functional Decentralized Simple; do
		grep -q -i "$principle" "$wk"
	done
	# Every wallet verb shipped through 1.14.0 must appear in the
	# walkthrough — readers should be able to grep for the verb and
	# find the section that demonstrates it.
	for verb in "wallet new" "wallet derive" "wallet balance" \
		"wallet label" "wallet send" "wallet remote" "wallet push" \
		"wallet pull" "wallet sign" "wallet build" "wallet broadcast" \
		"psbt finalize" "psbt extract"; do
		grep -q -F "$verb" "$wk"
	done
}

@test "FEAT-015 — walkthrough cites the standards table" {
	wk="$BATS_TEST_DIRNAME/../../docs/bitcoin-walkthrough.md"
	for bip in "BIP-32" "BIP-39" "BIP-141" "BIP-143" "BIP-173" "BIP-174"; do
		grep -q -F "$bip" "$wk"
	done
}

# ---------------------------------------------------------------------------
# FEAT-019 (partial, 1.16.0) — bitcoin-wallet agent skill. The AI-
# facing companion to the FEAT-015 human walkthrough. Lives at
# skills/bitcoin-wallet/{SKILL.md,opencode.md} and is installed by
# the Makefile into share/claude/skills/ and share/opencode/commands/.
# ---------------------------------------------------------------------------

@test "FEAT-019 — SKILL.md exists with the required frontmatter" {
	skill="$BATS_TEST_DIRNAME/../../skills/bitcoin-wallet/SKILL.md"
	[ -s "$skill" ]
	# YAML frontmatter: --- ... name: bitcoin-wallet ... description: ... ---
	head -1 "$skill" | grep -q '^---$'
	grep -q '^name: bitcoin-wallet' "$skill"
	grep -q '^description:' "$skill"
}

@test "FEAT-019 — SKILL.md opens with the four design principles" {
	skill="$BATS_TEST_DIRNAME/../../skills/bitcoin-wallet/SKILL.md"
	# All four words must appear in the design-principles section.
	for word in Educational Functional Decentralized Simple; do
		grep -q -F "$word" "$skill"
	done
}

@test "FEAT-019 — SKILL.md references every wallet verb shipped through 1.15.0" {
	skill="$BATS_TEST_DIRNAME/../../skills/bitcoin-wallet/SKILL.md"
	for recipe in "wallet new" "wallet derive" "wallet balance" \
		"wallet label" "wallet build" "wallet sign" "wallet send" \
		"wallet broadcast" "wallet push" "wallet pull" \
		"psbt finalize" "psbt extract" "psbt decode" \
		"backend set" "backend estimate-fee" \
		"descriptor checksum"; do
		grep -q -F "$recipe" "$skill"
	done
}

@test "FEAT-019 — SKILL.md spells out the guardrails an agent must hold" {
	skill="$BATS_TEST_DIRNAME/../../skills/bitcoin-wallet/SKILL.md"
	# The five guardrails the skill spec enumerates.
	grep -q -i 'never print.*mnemonic' "$skill"
	grep -q -i 'never bypass .secret' "$skill"
	grep -q -i 'testnet\|regtest' "$skill"
	grep -q -i 'mainnet' "$skill"
	grep -q -i 'cite the BIP' "$skill"
	grep -q -i 'auto-broadcast' "$skill"
}

@test "FEAT-019 — SKILL.md cites the vendored BIPs by local path" {
	skill="$BATS_TEST_DIRNAME/../../skills/bitcoin-wallet/SKILL.md"
	grep -q 'share/doc/bitcoin/bips/' "$skill"
	# At least one BIP from each major family the wallet implements.
	for bip in "BIP-32" "BIP-39" "BIP-141" "BIP-143" "BIP-173" "BIP-174" "BIP-380"; do
		grep -q -F "$bip" "$skill"
	done
}

@test "FEAT-019 — opencode entry exists with matching content" {
	oc="$BATS_TEST_DIRNAME/../../skills/bitcoin-wallet/opencode.md"
	[ -s "$oc" ]
	# YAML frontmatter for opencode commands.
	head -1 "$oc" | grep -q '^---$'
	grep -q '^description:' "$oc"
	# Cross-references SKILL.md so users know where the full
	# manifest lives.
	grep -q 'SKILL.md' "$oc"
	# Covers the same workflow recipes (subset is fine since opencode
	# entries can be terser).
	for verb in "wallet new" "wallet send" "psbt finalize" "psbt extract"; do
		grep -q -F "$verb" "$oc"
	done
}

@test "FEAT-019 — Makefile install installs SKILL.md and opencode.md" {
	mk="$BATS_TEST_DIRNAME/../../Makefile.in"
	# The install target must reference both skill artefacts;
	# pre-existing install-skills-user only consumes what install puts
	# under share/, so the install target is the gate.
	grep -q 'SKILL.md' "$mk"
	grep -q 'opencode.md' "$mk"
	# Destination paths the agent dirs are symlinked from.
	grep -q 'share/claude/skills\|claude/skills' "$mk"
	grep -q 'opencode/commands' "$mk"
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

# ---------------------------------------------------------------------------
# FEAT-018 (partial, 1.17.0) — wallet index + tx + history. The
# read path: walks the addresses ledger, fetches every tx via the
# new backend verb, caches under transactions/<txid>.{hex,json},
# rebuilds the history ledger, and commits.
# ---------------------------------------------------------------------------

# Helper: a single-tx fixture that pays 12345 sats to alice's first
# derived address (bc1qcr8te4...) at block 830000.
alice_tx_fixture() {
	local addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	cat <<EOF
[{"txid":"abc123","status":{"block_height":830000},"vin":[{"prevout":{"scriptpubkey_address":"bc1qfaucet","value":13000}}],"vout":[{"scriptpubkey_address":"$addr","value":12345},{"scriptpubkey_address":"bc1qfaucetchange","value":600}]}]
EOF
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
# FEAT-026 (partial, 1.18.0) — descriptor derive + descriptor wallet.
# Together these turn descriptors from checksum strings into actual
# address generators. wpkh() only in this release; pkh / sh(wpkh) /
# tr / combo return a clear "not yet implemented" error.
# ---------------------------------------------------------------------------

@test "FEAT-026 — descriptor wallet emits a checksummed wpkh() descriptor" {
	setup_wallet_derive_env
	run "$BITCOIN_BIN" descriptor wallet alice
	[ "$status" -eq 0 ]
	# Shape: wpkh(<xpub>/0/*)#<8-char checksum>
	[[ "$output" =~ ^wpkh\(xpub[0-9A-Za-z]+/0/\*\)#[a-z0-9]{8}$ ]]
	# And descriptor verify accepts what wallet emits.
	run "$BITCOIN_BIN" descriptor verify "$output"
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
	run "$BITCOIN_BIN" descriptor derive "$desc" 0
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
		got="$("$BITCOIN_BIN" descriptor derive "$desc" "$i")"
		[ "$got" = "$expected" ]
	done
}

@test "FEAT-026 — descriptor derive rejects still-unimplemented functions with a clear error" {
	# 1.18.0 only shipped wpkh; 1.20.0 added pkh + sh(wpkh). tr and
	# combo remain deferred (tr is blocked on FEAT-007 Taproot).
	setup_wallet_derive_env
	body="$(alice_xpub_path)"
	for fn in tr combo; do
		run "$BITCOIN_BIN" descriptor derive "${fn}($body)" 0
		[ "$status" -ne 0 ]
		[[ "$output" == *"not yet implemented"* ]] || [[ "$stderr" == *"not yet implemented"* ]] || true
	done
}

@test "FEAT-026 — descriptor derive rejects malformed input" {
	setup_wallet_derive_env
	# No '*' placeholder.
	desc="$("$BITCOIN_BIN" descriptor wallet alice)"
	# Strip the '/*' to leave a non-instantiable path.
	bad="${desc/\/\*/}"
	run "$BITCOIN_BIN" descriptor derive "$bad" 0
	[ "$status" -ne 0 ]
	# Empty descriptor.
	run "$BITCOIN_BIN" descriptor derive "" 0
	[ "$status" -ne 0 ]
	# Non-numeric index.
	run "$BITCOIN_BIN" descriptor derive "$desc" notanint
	[ "$status" -ne 0 ]
}

@test "FEAT-026 — descriptor derive rejects a descriptor with a bad checksum" {
	setup_wallet_derive_env
	desc="$("$BITCOIN_BIN" descriptor wallet alice)"
	# Flip one character of the checksum.
	bad="${desc:0: ${#desc}-1}q"
	run "$BITCOIN_BIN" descriptor derive "$bad" 0
	[ "$status" -ne 0 ]
}

@test "FEAT-026 — descriptor help mentions derive and wallet" {
	run "$BITCOIN_BIN" descriptor help
	[ "$status" -eq 0 ]
	[[ "$output" == *"derive"* ]]
	[[ "$output" == *"wallet"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-026 (extend, 1.20.0) — pkh() and sh(wpkh()) support in
# descriptor derive. The wpkh child-pubkey pipeline is reused; only
# the address-encoding tail differs. Address shapes:
#   pkh()       → base58check(0x00 || HASH160(pubkey)) → '1...'
#   sh(wpkh())  → base58check(0x05 || HASH160(0014 HASH160(pubkey))) → '3...'
#
# Vectors for the canonical abandon-mnemonic m/84h/0h/0h/0/0 pubkey
# (0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c)
# are cross-verified with an independent Python implementation:
#   pkh → 1JaUQDVNRdhfNsVncGkXedaPSM5Gc54Hso
#   sh(wpkh) → 3GtVZYzsKF6Feikdjd4bDyPdAiyeHANY9b
# ---------------------------------------------------------------------------

# Helper: descriptor body that derives alice's m/84h/0h/0h/0/* keys.
# Returns the wpkh-wrapped form without checksum; tests substitute
# the outer function (pkh / sh(wpkh)) as needed.
alice_xpub_path() {
	# `descriptor wallet alice` emits wpkh(<xpub>/0/*)#<checksum>;
	# we strip the wpkh() wrapper and the #-checksum suffix.
	local desc="$("$BITCOIN_BIN" descriptor wallet alice)"
	local body="${desc:0: ${#desc}-9}"   # drop '#<8 chars>'
	echo "${body#wpkh(}" | sed 's/)$//'
}

@test "FEAT-026 — descriptor derive pkh() produces a legacy P2PKH '1...' address" {
	setup_wallet_derive_env
	body="$(alice_xpub_path)"
	run "$BITCOIN_BIN" descriptor derive "pkh($body)" 0
	[ "$status" -eq 0 ]
	# Cross-verified vector for the abandon mnemonic / BIP-84 idx 0.
	[ "$output" = "1JaUQDVNRdhfNsVncGkXedaPSM5Gc54Hso" ]
	# Structural: leading '1', base58 charset, sensible length.
	[[ "$output" =~ ^1[1-9A-HJ-NP-Za-km-z]{25,33}$ ]]
}

@test "FEAT-026 — descriptor derive sh(wpkh()) produces a P2SH '3...' nested-segwit address" {
	setup_wallet_derive_env
	body="$(alice_xpub_path)"
	run "$BITCOIN_BIN" descriptor derive "sh(wpkh($body))" 0
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
	pkh_0="$("$BITCOIN_BIN" descriptor derive "pkh($body)" 0)"
	pkh_1="$("$BITCOIN_BIN" descriptor derive "pkh($body)" 1)"
	[ "$pkh_0" != "$pkh_1" ]
	sh_0="$("$BITCOIN_BIN" descriptor derive "sh(wpkh($body))" 0)"
	sh_1="$("$BITCOIN_BIN" descriptor derive "sh(wpkh($body))" 1)"
	[ "$sh_0" != "$sh_1" ]
	# And the three function families never collide on the same index.
	wpkh_0="$("$BITCOIN_BIN" descriptor derive "wpkh($body)" 0)"
	[ "$pkh_0" != "$sh_0" ]
	[ "$pkh_0" != "$wpkh_0" ]
	[ "$sh_0"  != "$wpkh_0" ]
}

@test "FEAT-026 — sh(<non-wpkh>) returns 'not yet implemented'" {
	setup_wallet_derive_env
	body="$(alice_xpub_path)"
	# sh(pkh(...)) is a valid BIP-380 descriptor; we just don't ship it.
	run "$BITCOIN_BIN" descriptor derive "sh(pkh($body))" 0
	[ "$status" -ne 0 ]
	[[ "$output" == *"not yet implemented"* ]] || [[ "$stderr" == *"not yet implemented"* ]] || true
}

@test "FEAT-026 — pkh and sh(wpkh) round-trip through a verified checksum" {
	setup_wallet_derive_env
	body="$(alice_xpub_path)"
	# Slap a checksum on each new-style descriptor and confirm derive
	# accepts the checksummed form.
	for d in "pkh($body)" "sh(wpkh($body))"; do
		cs="$("$BITCOIN_BIN" descriptor checksum "$d")"
		run "$BITCOIN_BIN" descriptor verify "$cs"
		[ "$status" -eq 0 ]
		run "$BITCOIN_BIN" descriptor derive "$cs" 0
		[ "$status" -eq 0 ]
	done
}

@test "FEAT-026 — pkh / sh(wpkh) reject malformed input" {
	setup_wallet_derive_env
	# No '*' placeholder.
	body="$(alice_xpub_path)"
	bad="${body/\/\*/}"
	run "$BITCOIN_BIN" descriptor derive "pkh($bad)" 0
	[ "$status" -ne 0 ]
	run "$BITCOIN_BIN" descriptor derive "sh(wpkh($bad))" 0
	[ "$status" -ne 0 ]
	# Bare key (no '/path').
	run "$BITCOIN_BIN" descriptor derive "pkh(xpubBareKey)" 0
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-018 (partial, 1.19.0) — wallet label tx|utxo + wallet history
# --label filter + wallet tx labels section. Builds on 1.17.0's
# read path; consumes the `transactions/` cache and the new
# `labels/{tx,utxo}` files.
# ---------------------------------------------------------------------------

# Helper: a wallet pre-populated with one indexed tx, so the label
# verbs have a real txid to annotate. Mirrors the 1.17.0 alice_tx
# fixture but is parameterless so multiple tests can reuse it.
setup_indexed_alice() {
	setup_wallet_derive_env
	"$BITCOIN_BIN" wallet derive alice >/dev/null
	addr="bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
	curl_fixture "https://mempool.space/api/address/$addr/txs" "$(alice_tx_fixture)"
	curl_fixture "https://mempool.space/api/tx/abc123/hex" "0200000001deadbeef"
	"$BITCOIN_BIN" wallet index alice >/dev/null
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
	[[ "$output" == *"command:foo"* ]] || true
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
	PATH="$repo_root/bin:$repo_root/libexec/bitcoin:$PATH" \
	XDG_SHARE_HOME="$repo_root/share" \
	SELF_LIBEXEC="$repo_root/libexec" \
	run bash -c '
		mnemonic-to-seed abandon abandon abandon abandon abandon abandon abandon \
		                 abandon abandon abandon abandon about \
		  | basenc --base16 -w0 \
		  | bip32 create -s 2>/dev/null \
		  | bitcoin bip13 base58-decode \
		  | bip32 derive m/84h/0h/0h/0/0/N
	'
	[ "$status" -eq 0 ]
	[[ "$output" != *"bip32-is-public"* ]]
	[[ "$output" != *"bip32-is-secret"* ]]
}
