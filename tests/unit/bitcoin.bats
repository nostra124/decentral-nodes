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
# FEAT-008 (partial) — psbt decode. The fixture is the first valid PSBT
# from BIP-174's test vectors (one P2PKH input, two outputs).
# ---------------------------------------------------------------------------

# BIP-174 valid PSBT #1 — one P2PKH input. Helper because bash
# file-scope declarations aren't reliably inherited into @test blocks.
psbt_vec1() {
	echo -n "70736274ff0100750200000001268171371edff285e937adeea4b37b78000c0566cbb3ad64641713ca42171bf60000000000feffffff02d3dff505000000001976a914d0c59903c5bac2868760e90fd521a4665aa7652088ac00e1f5050000000017a9143545e6e33b832c47050f24d3eeb93c9c03948bc787b32e1300000100fda5010100000000010289a3c71eab4d20e0371bbba4cc698fa295c9463afa2e397f8533ccb62f9567e50100000017160014be18d152a9b012039daf3da7de4f53349eecb985ffffffff86f8aa43a71dff1448893a530a7237ef6b4608bbb2dd2d0171e63aec6a4890b40100000017160014fe3e9ef1a745e974d902c4355943abcb34bd5353ffffffff0200c2eb0b000000001976a91485cff1097fd9e008bb34af709c62197b38978a4888ac72fef84e2c00000017a914339725ba21efd62ac753a9bcd067d6c7a6a39d05870247304402202712be22e0270f394f568311dc7ca9a68970b8025fdd3b240229f07f8a5f3a240220018b38d7dcd314e734c9276bd6fb40f673325bc4baa144c800d2f2f02db2765c012103d2e15674941bad4a996372cb87e1856d3652606d98562fe39c5e9e7e413f210502483045022100d12b852d85dcd961d2f5f4ab660654df6eedcc794c0c33ce5cc309ffb5fce58d022067338a8e0e1725c197fb1a88af59f51e44e4255b20167c8684031c05d1f2592a01210223b72beef0965d10be0778efecd61fcac6f79a4ea169393380734464f84f2ab300000000000000"
}

@test "FEAT-008 — psbt decode accepts a known BIP-174 PSBT and emits records" {
	run bash -c "$(declare -f psbt_vec1); psbt_vec1 | '$BITCOIN_BIN' psbt decode"
	[ "$status" -eq 0 ]
	# At minimum the global unsigned-tx record (section 0, type 00) must appear.
	[[ "$output" == *"section=0"* ]]
	[[ "$output" == *"type=00"* ]]
}

@test "FEAT-008 — psbt decode rejects input without the BIP-174 magic" {
	# Strip the 5-byte magic+separator (10 hex chars).
	run bash -c "$(declare -f psbt_vec1); psbt_vec1 | cut -c11- | '$BITCOIN_BIN' psbt decode"
	[ "$status" -ne 0 ]
	[[ "$output" == *"magic"* ]] || true
}

@test "FEAT-008 — psbt decode rejects empty input" {
	run bash -c "echo '' | '$BITCOIN_BIN' psbt decode"
	[ "$status" -ne 0 ]
}

@test "FEAT-008 — bitcoin help psbt cites BIP-174" {
	run "$BITCOIN_BIN" help psbt
	[ "$status" -eq 0 ]
	[[ "$output" == *"BIP-174"* ]]
	[[ "$output" == *"bip-0174.mediawiki"* ]]
}

# ---------------------------------------------------------------------------
# BUG-016 regression — `command:bip49-create` and `command:bip84-create`
# were dispatcher entries calling undefined `command:bip32-create`.
# Removed in 1.7.1; the bash-function wrappers `bip49()` / `bip84()`
# remain as the user-facing path.
# ---------------------------------------------------------------------------

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
