#!/usr/bin/env bash
# Shared scaffolding for the tests/unit/streamline-NN.bats suites.
# FEAT-053 split of the monolithic tests/unit/streamline.bats:
# setup()/teardown() + every fixture/helper function live here,
# loaded by each chunk via `load lib/streamline`. Definitions only —
# no top-level statements run at source time.

#
# FEAT-035: command-surface streamline.
#
# As verbs migrate from their historical names (mnemonic-to-seed,
# psbt, descriptor, bech32) to the bipXXX canonical names, this
# file asserts the deprecation contract:
#
#   1. The new canonical name works and produces the canonical
#      output.
#   2. The old (deprecated) name continues to work as an alias —
#      same bytes on stdout, identical exit status.
#   3. The alias emits one warn line on stderr naming the
#      canonical replacement and the removal release.
#
# As each extraction lands, add a "Stream A/B/C/D" block here.


setup() {
	export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
	export BITCOIN_BIN="$REPO_ROOT/bin/bitcoin-node"
	export SELF_LIBEXEC="$REPO_ROOT/libexec"
	export SELF_QUIET=1
	export BIP39_PASSPHRASE=TREZOR
	# The BIP-39 §From mnemonic to seed canonical test vector. The
	# abandon-... mnemonic with passphrase TREZOR yields a fixed
	# 64-byte seed; both the canonical and the deprecated paths
	# must produce these exact bytes.
	export ABANDON_MNEMONIC="abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
	export EXPECTED_SEED_HEX="c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
	# Isolated XDG paths so FEAT-037 freeze/unfreeze tests don't
	# clobber a real user's ~/.local/var/bitcoin/wallets.
	BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
	HOME="$(mktemp -d "$BATS_TMPDIR/home.XXXXXX")"
	export HOME
	export XDG_DATA_HOME="$HOME/.local/share"
	mkdir -p "$XDG_DATA_HOME/bitcoin/wallets"
}

# Lightweight wallet fixture for FEAT-037 (frozen.tsv) tests.
# Doesn't need a real seed or backend round-trip: freeze /
# unfreeze just need the wallet dir + an addresses ledger + git.
feat037_setup_wallet() {
	local name="${1:-alice}"
	local path="$XDG_DATA_HOME/bitcoin/wallets/$name"
	mkdir -p "$path"
	printf '0\tbc1qexample\t\n' > "$path/addresses"
	(
		cd "$path"
		git init -q
		git -c user.email=wallet@bitcoin -c user.name=bitcoin \
		    -c commit.gpgsign=false \
			add addresses
		git -c user.email=wallet@bitcoin \
			-c user.name=bitcoin -c commit.gpgsign=false \
			commit -q -m "initial"
	)
}

# ---------------------------------------------------------------------------
# FEAT-043: tx bump (RBF + CPFP).
#
# The parse / validation / cached-tx-inspection paths are tested
# here against a JSON fixture (no seed / no xxd needed). The full
# build|sign|broadcast pipeline is exercised in CI / regtest — the
# same constraint the FEAT-008 sign tests carry.
# ---------------------------------------------------------------------------

# Write a cached transactions/<txid>.json for <wallet>. Args:
#   $1 wallet  $2 txid  $3 sequence (input)  $4 pay_addr  $5 pay_value
# Change always goes to the fixture wallet's address (bc1qexample).
feat043_cache_tx() {
	local wallet="$1" txid="$2" seq="$3" pay_addr="$4" pay_value="$5"
	local path="$XDG_DATA_HOME/bitcoin/wallets/$wallet"
	mkdir -p "$path/transactions"
	cat > "$path/transactions/$txid.json" <<JSON
{"txid":"$txid","status":{"block_height":"mempool"},
 "vin":[{"txid":"aa00bb11cc22dd33ee44ff5500112233445566778899aabbccddeeff00112233","vout":0,"sequence":$seq,"prevout":{"scriptpubkey_address":"bc1qsource","value":100000}}],
 "vout":[{"scriptpubkey_address":"$pay_addr","value":$pay_value},{"scriptpubkey_address":"bc1qexample","value":40000}]}
JSON
}

# ---------------------------------------------------------------------------
# FEAT-040: BTC/EUR price oracle.
#
# csv:// source + cache reads need no network. The coingecko path
# uses a local curl stub (the real API is hit only in the SIT tier).
# ---------------------------------------------------------------------------

# Per-test isolated price environment. HOME is already a temp dir
# (from setup); pin the cache + source config under it.
feat040_env() {
	export XDG_CONFIG_HOME="$HOME/.config"
	export BITCOIN_PRICE_CACHE="$HOME/.bitcoin/cache/price/btc-eur.tsv"
	unset BITCOIN_PRICE_SOURCE
	mkdir -p "$HOME/.config/bitcoin"
}

# Install a curl stub that maps the coingecko history URL for a
# given date to a canned market_data.current_price.eur body.
feat040_coingecko_stub() {
	local stub_dir="$BATS_TMPDIR/cg-stub.$BATS_TEST_NUMBER"
	rm -rf "$stub_dir"; mkdir -p "$stub_dir"
	cat > "$stub_dir/curl" <<'STUB'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in http*://*) url="$a";; esac; done
# Any coingecko history URL → a fixed EUR price keyed by the date arg.
case "$url" in
	*simple/price*)
		# FEAT-266 spot endpoint → fixed current price.
		echo '{"bitcoin":{"eur":43210.0}}'
		exit 0 ;;
	*coins/bitcoin/history*)
		d="$(printf '%s' "$url" | sed -n 's/.*date=\([0-9-]*\).*/\1/p')"
		# DD-MM-YYYY → deterministic price (just echo a fixed value).
		echo '{"market_data":{"current_price":{"eur":42000.5}}}'
		exit 0 ;;
esac
echo "cg-stub: no fixture for $url" >&2
exit 22
STUB
	chmod +x "$stub_dir/curl"
	export PATH="$stub_dir:$PATH"
}

# ---------------------------------------------------------------------------
# FEAT-271: bitcoin config (list/get/set/unset/path). A temp datadir holds
# bitcoin.conf; a stub bitcoind serves -help so 'get' can resolve defaults.
# ---------------------------------------------------------------------------
feat271_env() {
	export BITCOIN_CONFIG_DATADIR="$HOME/cfgdir"
	# Config lives under a dir now (FHS /etc on a real host); point the
	# frontend at the tmp dir so the suite stays hermetic even when a real
	# /etc/bitcoin/bitcoin.conf exists on the dev box.
	export BITCOIN_CONFIG_DIR="$HOME/cfgdir"
	mkdir -p "$BITCOIN_CONFIG_DATADIR"
	printf '# bitcoin.conf\nserver=1\ndbcache=600\n' > "$BITCOIN_CONFIG_DATADIR/bitcoin.conf"
	export BITCOIN_BITCOIND="$HOME/bitcoind-help-stub"
	# Covers: a comma-form default "(4 to 16384, default: 450)", a multi-line
	# wrapped description, and an option with NO default (alertnotify).
	cat > "$BITCOIN_BITCOIND" <<-'STUB'
		#!/usr/bin/env bash
		[ "$1" = -help ] && printf '%s\n' \
		  '  -maxconnections=<n>' \
		  '       Maintain at most <n> connections (default: 125).' \
		  '  -dbcache=<n>' \
		  '       Maximum database cache size <n> MiB (4 to 16384, default:' \
		  '       450). In addition, unused mempool memory is shared.' \
		  '  -alertnotify=<cmd>' \
		  '       Execute command when an alert is raised.'
		exit 0
	STUB
	chmod +x "$BITCOIN_BITCOIND"
}

# ---------------------------------------------------------------------------
# FEAT-034: service-managed bitcoind (daemon enable / disable).
#
# The init system is mocked so the suite runs in CI without loading
# real services: stub systemctl / launchctl / useradd / sysadminctl /
# chown record their invocations, a stub sudo transparently execs its
# args, and a stub bitcoind is resolved via $BITCOIN_BITCOIND. All
# --system absolute paths are redirected under $BITCOIN_DAEMON_ROOT,
# and $BITCOIN_DAEMON_OS forces the systemd-vs-launchd branch so both
# OS families are exercised on one runner.
# ---------------------------------------------------------------------------

feat034_env() {
	local os="${1:-linux}"
	export BITCOIN_DAEMON_OS="$os"
	export XDG_CONFIG_HOME="$HOME/.config"
	export BITCOIN_DAEMON_ROOT="$HOME/root"
	export SELF_UNITS="$REPO_ROOT/share/bitcoin/units"
	export FEAT034_CALLS="$HOME/daemon-calls.log"
	: > "$FEAT034_CALLS"

	local stub="$HOME/daemon-stub" c
	mkdir -p "$stub"
	for c in systemctl launchctl useradd sysadminctl chown dscl dseditgroup usermod; do
		cat > "$stub/$c" <<-STUB
			#!/usr/bin/env bash
			printf '%s %s\n' "$c" "\$*" >> "$FEAT034_CALLS"
			exit 0
		STUB
		chmod +x "$stub/$c"
	done
	# BUG-035: on a host that already runs the live stack a real
	# 'bitcoin'/'_bitcoin' account exists, so daemon:_ensure_account's
	# `id "$user"` short-circuits and the account-creation branch never
	# runs. This stub makes any *username* lookup report not-found (so the
	# creation path is always exercised) while passing the option forms
	# (-u / -un / -g …) through to the real id (daemon:_domain needs them).
	cat > "$stub/id" <<-'STUB'
		#!/usr/bin/env bash
		case "$1" in
			-*) exec /usr/bin/id "$@" ;;
			"") exec /usr/bin/id ;;
			*)  exit 1 ;;
		esac
	STUB
	chmod +x "$stub/id"
	# Transparent sudo, but it records its invocation so tests can assert
	# that privileged steps (e.g. installing bitcoin.conf into the root-
	# owned datadir, BUG-030) actually route through sudo.
	cat > "$stub/sudo" <<-STUB
		#!/usr/bin/env bash
		printf 'sudo %s\n' "\$*" >> "$FEAT034_CALLS"
		# Emulate sudo's '-u <user>' (tests run under a single uid).
		if [ "\$1" = "-u" ]; then shift 2; fi
		exec "\$@"
	STUB
	chmod +x "$stub/sudo"
	export PATH="$stub:$PATH"

	# enable() resolves bitcoind through this override. Honors --version
	# so the enable preflight (daemon:_check_runnable) passes.
	export BITCOIN_BITCOIND="$HOME/bitcoind-stub"
	printf '#!/usr/bin/env bash\n:\n' > "$BITCOIN_BITCOIND"
	chmod +x "$BITCOIN_BITCOIND"
	# BUG-048 — neutralise the RPC-port preflight by default so these tests
	# are hermetic on a host that is itself running a bitcoind (the dev box's
	# real node binds 8332). The sentinel matches no real port → "all free".
	# The BUG-048 cases below override it with the specific busy port.
	export BITCOIN_PORT_BUSY=none
	# BUG-053 / FEAT-306 — pin the process source so status' running-node
	# detection + share-cookie are hermetic (the real `ps` would otherwise
	# find the host's live bitcoind). "" = nothing running; cases override it.
	export BITCOIN_PS=""
}

# ---------------------------------------------------------------------------
# FEAT-033: install Bitcoin Core itself (daemon install).
#
# Each package manager and `account` are stubbed on PATH; sudo execs
# its args transparently; a stub bitcoind reports a version so the
# confirmation message can be asserted. $ACCT_PLATFORM drives the
# auto-detect default.
# ---------------------------------------------------------------------------

feat033_env() {
	export FEAT033_CALLS="$HOME/install-calls.log"
	: > "$FEAT033_CALLS"
	local stub="$HOME/install-stub" c
	mkdir -p "$stub"
	for c in brew port apt-get apk add-apt-repository; do
		cat > "$stub/$c" <<-STUB
			#!/usr/bin/env bash
			printf '%s %s\n' "$c" "\$*" >> "$FEAT033_CALLS"
			exit 0
		STUB
		chmod +x "$stub/$c"
	done
	cat > "$stub/sudo" <<-'STUB'
		#!/usr/bin/env bash
		exec "$@"
	STUB
	chmod +x "$stub/sudo"
	cat > "$stub/account" <<-'STUB'
		#!/usr/bin/env bash
		[ "$1" = platform ] && printf '%s\n' "${ACCT_PLATFORM:-}"
		exit 0
	STUB
	chmod +x "$stub/account"
	cat > "$stub/bitcoind" <<-'STUB'
		#!/usr/bin/env bash
		[ "$1" = --version ] && echo "Bitcoin Core version v27.0.0"
		exit 0
	STUB
	chmod +x "$stub/bitcoind"
	# BUG-035: pin PATH to the stub dir + the system bindirs only — NOT the
	# inherited PATH — so a real brew / port / bitcoind on the host (the live
	# stack) can't leak in. The package-manager-absent test removes the stub
	# 'brew' and must then see it as genuinely not-found.
	export PATH="$stub:/usr/bin:/bin:/usr/sbin:/sbin"
}

# ---------------------------------------------------------------------------
# BUG-015: legacy daemon verbs folded onto the new abstraction.
#
# start / stop / monitor / space now drive the same systemd / launchd
# service `enable` installs, with --user (default) / --system modes.
# systemctl / launchctl / journalctl are stubbed; space runs real
# `du` against the data dir.
# ---------------------------------------------------------------------------

bug015_env() {
	export BUG015_CALLS="$HOME/lifecycle-calls.log"
	: > "$BUG015_CALLS"
	local stub="$HOME/lifecycle-stub" c
	mkdir -p "$stub"
	# `tail` is stubbed so monitor's macOS `tail -f` records instead of
	# blocking; it also lets BUG-030 assert the sudo-wrapped log read.
	for c in systemctl launchctl journalctl tail; do
		cat > "$stub/$c" <<-STUB
			#!/usr/bin/env bash
			printf '%s %s\n' "$c" "\$*" >> "$BUG015_CALLS"
			exit 0
		STUB
		chmod +x "$stub/$c"
	done
	# Transparent sudo that records its invocation (see BUG-030).
	cat > "$stub/sudo" <<-STUB
		#!/usr/bin/env bash
		printf 'sudo %s\n' "\$*" >> "$BUG015_CALLS"
		exec "\$@"
	STUB
	chmod +x "$stub/sudo"
	export PATH="$stub:$PATH"
}
