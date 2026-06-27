#!/usr/bin/env bash
# Shared scaffolding for the tests/unit/bitcoin-NN.bats suites.
# FEAT-053 split of the monolithic tests/unit/bitcoin.bats:
# setup()/teardown() + every fixture/helper function live here,
# loaded by each chunk via `load lib/bitcoin`. Definitions only —
# no top-level statements run at source time.

#
# Unit tests for bin/bitcoin-node — the BIP-173/350 + bip32/39/49/84
# wallet frontend (FEAT-006..019). Pinned to semver per FEAT-005.
#
# Coverage scope: the dispatcher surface (version / help / modules)
# plus a bug-replicating test for BUG-008. The cryptographic
# primitives have separate test-vector coverage in
# tests/vectors/bip-*.t (gated on FEAT-006's bitcoin.sh module
# being sourceable).

# 1.5.0 introduced `run --separate-stderr`, which the 1.12.0 fee-
# fallback test relies on to assert the warn line lands on stderr.

setup() {
	BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
	HOME="$(mktemp -d "$BATS_TMPDIR/home.XXXXXX")"
	unset XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_SHARE_HOME
	unset XDG_SOURCE_HOME XDG_BACKUP_HOME XDG_RUNTIME_DIR
	export HOME
	export SELF_QUIET=1
	export BITCOIN_BIN="$BATS_TEST_DIRNAME/../../bin/bitcoin-node"
	# FEAT-020: pin SELF_LIBEXEC so a system-installed bitcoin
	# at /usr/local/libexec cannot pollute the in-tree test run.
	export SELF_LIBEXEC="$BATS_TEST_DIRNAME/../../libexec"
}

teardown() {
	rm -rf "$HOME"
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
	init) : ;;
	set) mkdir -p "$store/$(dirname "$key")"; cat > "$store/$key" ;;
	get) cat "$store/$key" ;;
	rm)  rm -f "$store/$key" ;;
	ls)  ls "$store/$(dirname "$key")" 2>/dev/null ;;
	*)   echo "stub-secret: unknown verb '$verb'" >&2; exit 1 ;;
esac
STUB
	chmod +x "$stub_dir/secret"
	# bin/ on PATH because libexec plugins shell out to the parent
	# `bitcoin` dispatcher (e.g. `bip32 create` does
	# `... | bitcoin-node bip13 base58-encode`).
	PATH="$BATS_TEST_DIRNAME/../../bin:$stub_dir:$PATH"
	export PATH
	export XDG_DATA_HOME="$BATS_TMPDIR/xdg-data"
	rm -rf "$XDG_DATA_HOME"
	mkdir -p "$XDG_DATA_HOME"
	# bip39 reads its wordlist from $XDG_SHARE_HOME/bitcoin/bip39/<lang>.txt.
	# Point it at the vendored copy in the dev tree.
	export XDG_SHARE_HOME="$BATS_TEST_DIRNAME/../../share"
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

# FEAT-304 — bitcoind backend. The backend talks JSON-RPC over HTTP to the
# configured rpc.url; for tests we use its fixture seam
# ($BITCOIN_BITCOIND_RPC_FIXTURE, a dir of <method>.json) so no node, curl,
# or config read is exercised — the same pattern the fulcrum backend uses.
# `bitcoind_rpc_fixture <method> <envelope>` sets a canned JSON-RPC reply
# (pass the full envelope, e.g. '{"result":…,"error":null}'). A method with
# no fixture makes the RPC call fail, modelling an unreachable node.
setup_bitcoind_backend_env() {
	export BITCOIN_BITCOIND_RPC_FIXTURE="$BATS_TMPDIR/bitcoind-rpc"
	rm -rf "$BITCOIN_BITCOIND_RPC_FIXTURE"
	mkdir -p "$BITCOIN_BITCOIND_RPC_FIXTURE"
	export XDG_CONFIG_HOME="$BATS_TMPDIR/xdg-config-bitcoind"
	rm -rf "$XDG_CONFIG_HOME"
	mkdir -p "$XDG_CONFIG_HOME"
	export BITCOIN_BACKEND=bitcoind
}

bitcoind_rpc_fixture() {
	local method="$1" body="$2"
	printf '%s' "$body" > "$BITCOIN_BITCOIND_RPC_FIXTURE/$method.json"
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

# ---------------------------------------------------------------------------
# FEAT-008 (partial) — psbt decode. The fixture is the first valid PSBT
# from BIP-174's test vectors (one P2PKH input, two outputs).
# ---------------------------------------------------------------------------

# BIP-174 valid PSBT #1 — one P2PKH input. Helper because bash
# file-scope declarations aren't reliably inherited into @test blocks.
psbt_vec1() {
	echo -n "70736274ff0100750200000001268171371edff285e937adeea4b37b78000c0566cbb3ad64641713ca42171bf60000000000feffffff02d3dff505000000001976a914d0c59903c5bac2868760e90fd521a4665aa7652088ac00e1f5050000000017a9143545e6e33b832c47050f24d3eeb93c9c03948bc787b32e1300000100fda5010100000000010289a3c71eab4d20e0371bbba4cc698fa295c9463afa2e397f8533ccb62f9567e50100000017160014be18d152a9b012039daf3da7de4f53349eecb985ffffffff86f8aa43a71dff1448893a530a7237ef6b4608bbb2dd2d0171e63aec6a4890b40100000017160014fe3e9ef1a745e974d902c4355943abcb34bd5353ffffffff0200c2eb0b000000001976a91485cff1097fd9e008bb34af709c62197b38978a4888ac72fef84e2c00000017a914339725ba21efd62ac753a9bcd067d6c7a6a39d05870247304402202712be22e0270f394f568311dc7ca9a68970b8025fdd3b240229f07f8a5f3a240220018b38d7dcd314e734c9276bd6fb40f673325bc4baa144c800d2f2f02db2765c012103d2e15674941bad4a996372cb87e1856d3652606d98562fe39c5e9e7e413f210502483045022100d12b852d85dcd961d2f5f4ab660654df6eedcc794c0c33ce5cc309ffb5fce58d022067338a8e0e1725c197fb1a88af59f51e44e4255b20167c8684031c05d1f2592a01210223b72beef0965d10be0778efecd61fcac6f79a4ea169393380734464f84f2ab300000000000000"
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
	"$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1
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
	psbt="$("$BITCOIN_BIN" tx build alice bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4 50000 --fee-rate 1)"
	echo "$psbt" | "$BITCOIN_BIN" bip174 sign "$ALICE_PRIV"
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

# ---------------------------------------------------------------------------
# FEAT-059 — fulcrum (Electrum protocol) backend. The Electrum client
# lives inside bin/bitcoin-node (no shelling out to the `fulcrum` command,
# CLAUDE.md §4). The socket is stubbed with canned JSON via
# $BITCOIN_FULCRUM_FIXTURE (a dir of <electrum.method>.json files).
# ---------------------------------------------------------------------------

# Accumulate a canned reply for one Electrum method into the fixture dir.
fulcrum_fixture() {
	: "${FULCRUM_FX:=$BATS_TMPDIR/ffx-$BATS_TEST_NUMBER}"
	mkdir -p "$FULCRUM_FX"
	printf '%s' "$2" > "$FULCRUM_FX/$1.json"
	export BITCOIN_FULCRUM_FIXTURE="$FULCRUM_FX"
}
