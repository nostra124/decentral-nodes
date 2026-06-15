#!/usr/bin/env bats
#
# Unit tests for the `monero` command (3.2.0 milestone):
#   FEAT-299 multi-command packaging + dependency boundary (this file's
#            skeleton contract; FEAT-300/301/302 extend it with the
#            install / daemon / config verbs).
#
# monero is the fourth top-level command shipped by the one `bitcoin` rpk
# package (after bitcoin / lightning / fulcrum). The contract mirrors the
# fulcrum FEAT-055 acceptance tests one-for-one.

setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	MONERO="$REPO/bin/monero"
	BITCOIN="$REPO/bin/bitcoin"
	export SELF_LIBEXEC="$REPO/libexec"
	MROOT="$BATS_TEST_TMPDIR"
	export HOME="$MROOT/home"; mkdir -p "$HOME"
}

# ===========================================================================
# FEAT-299 — multi-command packaging + dependency boundary
# ===========================================================================

@test "FEAT-299 AC1: monero version equals bitcoin version (one package)" {
	run "$MONERO" version
	[ "$status" -eq 0 ]
	[ "$output" = "$(cat "$REPO/VERSION")" ]
	[ "$output" = "$("$BITCOIN" version)" ]
}

@test "FEAT-299 AC1: monero help lists the generic + node verbs" {
	run "$MONERO" help
	[ "$status" -eq 0 ] || [ -n "$output" ]
	[[ "$output" == *version* ]]
	[[ "$output" == *modules* ]]
	[[ "$output" == *install* ]]
	[[ "$output" == *daemon* ]]
	[[ "$output" == *config* ]]
}

@test "FEAT-299 AC1: monero modules exits 0 (lists libexec verbs, empty ok)" {
	run "$MONERO" modules
	[ "$status" -eq 0 ]
}

@test "FEAT-299 AC2: monero <unknown> exits non-zero naming the verb" {
	run "$MONERO" frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *frobnicate* ]]
	[[ "$output" == *"not a monero command"* ]]
}

@test "FEAT-299 AC3: .rpk/identity is unchanged (bitcoin); no second package" {
	[ "$(cat "$REPO/.rpk/identity")" = bitcoin ]
	grep -qE '^COMMANDS=.*monero' "$REPO/.rpk/package"
}

@test "FEAT-299 AC4: make install stages the monero tree alongside the others" {
	command -v stow >/dev/null 2>&1 || skip "stow not installed"
	local prefix="$MROOT/prefix"; mkdir -p "$prefix"
	( cd "$REPO" && ./configure --prefix="$prefix" >/dev/null 2>&1 && make install >/dev/null 2>&1 )
	# Staged build tree (stow source) mirrors $PREFIX *relative* (BUG-038).
	[ -f "$REPO/build/bitcoin/bin/monero" ]
	[ -d "$REPO/build/bitcoin/libexec/monero" ]
	# …and stow installs the dispatcher directly onto PATH under $PREFIX.
	[ -x "$prefix/bin/monero" ]
	[ -f "$prefix/share/monero/version" ]
	( cd "$REPO" && make uninstall >/dev/null 2>&1; rm -rf build Makefile )
}

@test "FEAT-299 AC4: lint covers monero (PACKAGES + bin/* shellcheck)" {
	grep -qE '^PACKAGES = .*monero' "$REPO/Makefile.in"
	grep -qE 'shellcheck .* bin/\*' "$REPO/Makefile.in"
}

# Forbidden-sibling scanner mirroring the two FEAT-195 / fulcrum FEAT-055 tests.
_scan_forbidden() {  # returns 0 if a violation is found, 1 if clean
	local f="$1" word
	for word in cache data hosts scripts task; do
		grep -qE "^[[:space:]]*${word}[[:space:]]" "$f" && return 0
		grep -qE "\\\$\\([[:space:]]*${word}[[:space:]]" "$f" && return 0
	done
	# bare `bitcoin` command (not bitcoin-cli / bitcoind, which have a
	# non-space char after 'bitcoin')
	grep -qE "^[[:space:]]*bitcoin[[:space:]]" "$f" && return 0
	return 1
}

@test "FEAT-299 AC5: bin/monero + libexec/monero/* call no forbidden siblings" {
	run _scan_forbidden "$REPO/bin/monero"
	[ "$status" -eq 1 ]
	local f
	# libexec/monero/ may be empty in the skeleton; find handles that.
	while IFS= read -r f; do
		run _scan_forbidden "$f"
		[ "$status" -eq 1 ] || { echo "forbidden call in $f"; return 1; }
	done < <(find "$REPO/libexec/monero" -type f 2>/dev/null)
}

@test "FEAT-299 AC5: the scanner catches a planted forbidden sibling call" {
	local planted="$MROOT/planted"
	printf '#!/usr/bin/env bash\ncache list\n' > "$planted"
	run _scan_forbidden "$planted"
	[ "$status" -eq 0 ]
}

# ===========================================================================
# FEAT-300 — verified release-tarball install
#
# Build a real .tar.bz2 (real SHA256) and serve it + a clearsigned hashes
# file + the signing key through PATH-stubbed curl; uname forces the arch;
# gpg is stubbed (import show-only emits the pinned fingerprint, --verify
# honours $MONERO_TEST_GPG_BAD). The SHA256 leg is genuinely exercised.
# ===========================================================================

PINNED_FPR=81AC591FE9C4B65C5806AFC3F0AF4D462A0BDF92

# _mk_release_fixture <arch-machine> — set up stubs + seams for one install.
# Echoes nothing; exports MONERO_* seams and prepends the stub dir to PATH.
_mk_release_fixture() {
	local machine="${1:-x86_64}"
	local td="$MROOT/rel"; mkdir -p "$td/stub" "$td/pfx/bin" "$td/pkg"
	export MONERO_VERSION=v0.18.3.4
	local asset="monero-linux-x64-$MONERO_VERSION"
	[ "$machine" = aarch64 ] && asset="monero-linux-armv8-$MONERO_VERSION"
	# A real release tree -> real tarball -> real sha256.
	mkdir -p "$td/pkg/$asset"
	printf '#!/bin/sh\necho "Monero '\''Fluorine Fermi'\'' (%s-release)"\n' "$MONERO_VERSION" \
		> "$td/pkg/$asset/monerod"
	printf '#!/bin/sh\n:\n' > "$td/pkg/$asset/monero-wallet-rpc"
	printf '#!/bin/sh\n:\n' > "$td/pkg/$asset/monero-wallet-cli"
	chmod +x "$td/pkg/$asset/"*
	( cd "$td/pkg" && tar -cjf "$td/$asset.tar.bz2" "$asset" )
	local sum
	if command -v sha256sum >/dev/null 2>&1; then
		sum="$(sha256sum "$td/$asset.tar.bz2" | awk '{print $1}')"
	else
		sum="$(shasum -a 256 "$td/$asset.tar.bz2" | awk '{print $1}')"
	fi
	cat > "$td/hashes.txt" <<-EOF
		-----BEGIN PGP SIGNED MESSAGE-----
		Hash: SHA256

		$sum  $asset.tar.bz2
		-----BEGIN PGP SIGNATURE-----
		(stub signature)
		-----END PGP SIGNATURE-----
	EOF
	printf 'STUB KEY\n' > "$td/key.asc"
	# Stubs.
	cat > "$td/stub/uname" <<-STUB
		#!/usr/bin/env bash
		case "\$1" in -s) echo Linux ;; -m) echo $machine ;; *) echo Linux ;; esac
	STUB
	cat > "$td/stub/curl" <<-STUB
		#!/usr/bin/env bash
		out=""; url=""
		while [ \$# -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2 ;; -*) shift ;; *) url="\$1"; shift ;; esac; done
		case "\$url" in
		  *binaryfate.asc|*key*) cp "$td/key.asc" "\$out" ;;
		  *hashes.txt)           cp "$td/hashes.txt" "\$out" ;;
		  *.tar.bz2)             cp "$td/\$(basename "\$url")" "\$out" 2>/dev/null || exit 22 ;;
		  *) exit 22 ;;
		esac
	STUB
	cat > "$td/stub/gpg" <<-STUB
		#!/usr/bin/env bash
		args="\$*"
		case "\$args" in
		  *show-only*)
		    if [ -n "\$MONERO_TEST_KEY_BAD" ]; then
		      echo "fpr:::::::::DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF:"
		    else
		      echo "fpr:::::::::$PINNED_FPR:"
		    fi ;;
		  *--verify*) [ -n "\$MONERO_TEST_GPG_BAD" ] && exit 1; exit 0 ;;
		  *) exit 0 ;;
		esac
	STUB
	chmod +x "$td/stub/"*
	export PATH="$td/stub:$PATH"
	export MONERO_KEYCACHE="$td/keycache.asc"
	export MONERO_KEY_URL="http://stub/binaryfate.asc"
	export MONERO_HASHES_URL="http://stub/hashes.txt"
	export MONERO_RELEASE_BASEURL="http://stub"
	REL_PREFIX="$td/pfx/bin"
	REL_ASSET="$asset"
}

@test "FEAT-300 AC1: install downloads, GPG-verifies, SHA256-checks, and stages monerod" {
	_mk_release_fixture x86_64
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -eq 0 ]
	[ -x "$REL_PREFIX/monerod" ]
	[ -x "$REL_PREFIX/monero-wallet-rpc" ]
	[ -x "$REL_PREFIX/monero-wallet-cli" ]
	[[ "$output" == *"sha256 verified"* ]]
	[[ "$output" == *"signature verified"* ]]
	"$REL_PREFIX/monerod" --version | grep -q "$MONERO_VERSION"
}

@test "FEAT-300 AC2: a tampered tarball (bad SHA256) aborts and stages nothing" {
	_mk_release_fixture x86_64
	# Corrupt the served tarball AFTER the hashes were computed.
	printf 'tampered' >> "$MROOT/rel/$REL_ASSET.tar.bz2"
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -ne 0 ]
	[[ "$output" == *"SHA256 mismatch"* ]]
	[ ! -e "$REL_PREFIX/monerod" ]
}

@test "FEAT-300 AC2: a bad GPG signature aborts and stages nothing" {
	_mk_release_fixture x86_64
	export MONERO_TEST_GPG_BAD=1
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -ne 0 ]
	[[ "$output" == *"did NOT verify"* ]]
	[ ! -e "$REL_PREFIX/monerod" ]
}

@test "FEAT-300 AC2: a key whose fingerprint != the pinned one is refused" {
	_mk_release_fixture x86_64
	export MONERO_TEST_KEY_BAD=1
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -ne 0 ]
	[[ "$output" == *"fingerprint mismatch"* ]]
	[ ! -e "$REL_PREFIX/monerod" ]
}

@test "FEAT-300 AC3: arch detection picks the armv8 asset on aarch64" {
	_mk_release_fixture aarch64
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -eq 0 ]
	[[ "$output" == *"monero-linux-armv8"* ]]
	[ -x "$REL_PREFIX/monerod" ]
}

@test "FEAT-300 AC4: re-running is idempotent; --force re-installs" {
	_mk_release_fixture x86_64
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -eq 0 ]
	run "$MONERO" install --prefix "$REL_PREFIX"
	[ "$status" -eq 0 ]
	[[ "$output" == *"already installed"* ]]
	run "$MONERO" install --prefix "$REL_PREFIX" --force
	[ "$status" -eq 0 ]
	[[ "$output" == *"sha256 verified"* ]]
}

@test "FEAT-300 AC: install help lists release, version, prefix, force" {
	run "$MONERO" install --help
	[ "$status" -eq 0 ]
	for s in release version prefix force; do
		[[ "$output" == *"$s"* ]] || { echo "missing: $s"; return 1; }
	done
}

# ===========================================================================
# FEAT-301 — system-default monerod service (mirrors streamline.bats
# feat034_env). Init-system binaries are stubbed (logging their argv to
# $MCALLS); sudo execs transparently; MONERO_DAEMON_OS forces the os branch;
# MONERO_DAEMON_ROOT redirects every --system absolute path into a tmp tree.
# ===========================================================================

monero_daemon_env() {
	local os="${1:-linux}"
	export MONERO_DAEMON_OS="$os"
	export XDG_CONFIG_HOME="$HOME/.config"
	export MONERO_DAEMON_ROOT="$HOME/root"
	export SELF_UNITS="$REPO/share/monero/units"
	export MCALLS="$HOME/monero-daemon-calls.log"; : > "$MCALLS"
	local stub="$HOME/mdstub" c; mkdir -p "$stub"
	for c in systemctl launchctl useradd dscl dseditgroup usermod chown du; do
		printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "%s"\nexit 0\n' "$c" "$MCALLS" > "$stub/$c"
		chmod +x "$stub/$c"
	done
	# du must still print a size for `space`.
	printf '#!/usr/bin/env bash\nprintf "du %%s\\n" "$*" >> "%s"\necho "42G\t."\n' "$MCALLS" > "$stub/du"
	chmod +x "$stub/du"
	# Username lookups report not-found so the account-creation branch fires;
	# flag forms pass through to the real id.
	cat > "$stub/id" <<-'STUB'
		#!/usr/bin/env bash
		case "$1" in -*) exec /usr/bin/id "$@" ;; "") exec /usr/bin/id ;; *) exit 1 ;; esac
	STUB
	chmod +x "$stub/id"
	cat > "$stub/sudo" <<-STUB
		#!/usr/bin/env bash
		printf 'sudo %s\n' "\$*" >> "$MCALLS"
		[ "\$1" = "-u" ] && shift 2
		exec "\$@"
	STUB
	chmod +x "$stub/sudo"
	# curl backs `status`: empty (down) unless MONERO_TEST_RPC_JSON is set.
	cat > "$stub/curl" <<-STUB
		#!/usr/bin/env bash
		[ -n "\$MONERO_TEST_RPC_JSON" ] && printf '%s' "\$MONERO_TEST_RPC_JSON"
		exit 0
	STUB
	chmod +x "$stub/curl"
	export PATH="$stub:$PATH"
	export MONERO_MONEROD="$HOME/monerod-stub"
	printf '#!/usr/bin/env bash\n:\n' > "$MONERO_MONEROD"; chmod +x "$MONERO_MONEROD"
	# Hermetic on a host running monerod: sentinel matches no real port.
	export MONERO_PORT_BUSY=none
}

@test "FEAT-301 AC1: daemon enable (system, linux) creates the account, unit (User=monero), and starts it" {
	monero_daemon_env linux
	run "$MONERO" daemon enable
	[ "$status" -eq 0 ]
	local unit="$MONERO_DAEMON_ROOT/etc/systemd/system/monerod.service"
	[ -f "$unit" ]
	grep -q '^User=monero' "$unit"
	grep -q "ExecStart=$MONERO_MONEROD --non-interactive --config-file=" "$unit"
	# account provisioned + service enabled
	grep -q 'useradd .* monero' "$MCALLS"
	grep -q 'systemctl .*enable --now monerod' "$MCALLS"
	# datadir under the redirected root
	[ -d "$MONERO_DAEMON_ROOT/var/lib/monero" ]
}

@test "FEAT-301 AC1: daemon enable (system, macos) installs a LaunchDaemon running as _monero" {
	monero_daemon_env macos
	run "$MONERO" daemon enable
	[ "$status" -eq 0 ]
	local unit="$MONERO_DAEMON_ROOT/Library/LaunchDaemons/net.monero.monerod.plist"
	[ -f "$unit" ]
	grep -q '<string>_monero</string>' "$unit"
	grep -q 'dscl .* /Users/_monero' "$MCALLS"
}

@test "FEAT-301 AC2: daemon enable --user (linux) installs a rootless unit with no User=" {
	monero_daemon_env linux
	run "$MONERO" daemon enable --user
	[ "$status" -eq 0 ]
	local unit="$XDG_CONFIG_HOME/systemd/user/monerod.service"
	[ -f "$unit" ]
	! grep -q '^User=' "$unit"
	grep -q 'systemctl --user enable --now monerod' "$MCALLS"
}

@test "FEAT-301 AC3: --stagenet installs a distinctly-labelled unit alongside mainnet" {
	monero_daemon_env linux
	"$MONERO" daemon enable --user >/dev/null 2>&1
	"$MONERO" daemon enable --user --stagenet >/dev/null 2>&1
	[ -f "$XDG_CONFIG_HOME/systemd/user/monerod.service" ]
	[ -f "$XDG_CONFIG_HOME/systemd/user/monerod-stagenet.service" ]
	# stagenet unit carries the --stagenet chain flag
	grep -q -- '--stagenet' "$XDG_CONFIG_HOME/systemd/user/monerod-stagenet.service"
	! grep -q -- '--stagenet' "$XDG_CONFIG_HOME/systemd/user/monerod.service"
}

@test "FEAT-301 AC5: monerod config binds restricted RPC to localhost; --prune adds prune-blockchain" {
	monero_daemon_env linux
	run "$MONERO" daemon enable --user --prune
	[ "$status" -eq 0 ]
	local conf="$HOME/.bitmonero/monerod.conf"
	[ -f "$conf" ]
	grep -q '^rpc-bind-ip=127.0.0.1' "$conf"
	grep -q '^rpc-bind-port=18081' "$conf"
	grep -q '^restricted-rpc=1' "$conf"
	grep -q '^prune-blockchain=1' "$conf"
}

@test "FEAT-301 AC5: testnet uses its own restricted-RPC port (28081)" {
	monero_daemon_env linux
	run "$MONERO" daemon enable --user --testnet
	[ "$status" -eq 0 ]
	grep -q '^rpc-bind-port=28081' "$HOME/.bitmonero/monerod-testnet.conf"
}

@test "FEAT-301 AC4: status (down) errors with a hint and uses no sudo" {
	monero_daemon_env linux
	run "$MONERO" daemon status --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"down"* ]]
	[[ "$output" == *"not reachable"* ]]
	! grep -q '^sudo ' "$MCALLS"
}

@test "FEAT-301 AC4: status (up) reports the height from get_info, no sudo" {
	monero_daemon_env linux
	export MONERO_TEST_RPC_JSON='{"height": 3201234, "status": "OK"}'
	run "$MONERO" daemon status --user
	[ "$status" -eq 0 ]
	[[ "$output" == *"healthy"* ]]
	[[ "$output" == *"3201234"* ]]
	! grep -q '^sudo ' "$MCALLS"
}

@test "FEAT-301 AC4: monitor with no log errors naming the path, no sudo" {
	monero_daemon_env linux
	run "$MONERO" daemon monitor --user
	[ "$status" -eq 2 ]
	[[ "$output" == *"no log"* ]]
	[[ "$output" == *".bitmonero"* ]]
	! grep -q '^sudo ' "$MCALLS"
}

@test "FEAT-301: BUG-048 lesson — enable refuses when the restricted-RPC port is busy" {
	monero_daemon_env linux
	export MONERO_PORT_BUSY=18081
	run "$MONERO" daemon enable --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"18081"* ]]
	[[ "$output" == *"in use"* ]]
	[ ! -f "$XDG_CONFIG_HOME/systemd/user/monerod.service" ]
}

@test "FEAT-301 AC6: help enable names --system as the default and --user as the opt-in" {
	run "$MONERO" daemon enable --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"--system"* ]]
	[[ "$output" == *"default"* ]]
	[[ "$output" == *"--user"* ]]
}

@test "FEAT-301: daemon with no subcommand prints usage (exit 0)" {
	run "$MONERO" daemon
	[ "$status" -eq 0 ]
	[[ "$output" == *"enable"* ]]
	[[ "$output" == *"monitor"* ]]
}

@test "FEAT-301: daemon unknown subcommand errors non-zero" {
	run "$MONERO" daemon frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a 'monero daemon' command"* ]]
}

# ===========================================================================
# FEAT-302 — effective-config frontend over monerod. A stub `monerod --help`
# supplies the boost program_options defaults; the config dir is a tmp dir
# (no sudo needed for writes there).
# ===========================================================================

monero_config_env() {
	export MONERO_CONFIG_DIR="$HOME/etc-monero"; mkdir -p "$MONERO_CONFIG_DIR"
	export MONERO_MONEROD="$HOME/monerod-help"
	cat > "$MONERO_MONEROD" <<-'STUB'
		#!/bin/sh
		cat <<'HELP'
		Monero 'Fluorine Fermi' (v0.18.3.4-release)

		Options:
		  --data-dir arg                        Specify data directory
		  --rpc-bind-port arg (=18081)          Port for RPC server
		  --log-level arg (=0)                  Set default log level
		  --prune-blockchain                    Prune blockchain
		HELP
	STUB
	chmod +x "$MONERO_MONEROD"
}

@test "FEAT-302 AC1: config list emits TSV NAME/VALUE/DESCRIPTION incl. compiled-in defaults" {
	monero_config_env
	run "$MONERO" config list
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -q "^NAME	VALUE	DESCRIPTION$"
	# A defaulted option carries a non-empty VALUE column (literal tabs).
	printf '%s\n' "$output" | grep -q "rpc-bind-port	18081	"
	# A flag (no default) still appears in the listing.
	printf '%s\n' "$output" | grep -q '^prune-blockchain'
}

@test "FEAT-302 AC2: config get returns the default when unset, the conf value when set" {
	monero_config_env
	run "$MONERO" config get rpc-bind-port
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = 18081 ]
	# Now set it and read back.
	printf 'rpc-bind-port=29999\n' > "$MONERO_CONFIG_DIR/monerod.conf"
	run "$MONERO" config get rpc-bind-port
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = 29999 ]
}

@test "FEAT-302 AC3: config set persists to the conf and is read back by get/list" {
	monero_config_env
	: > "$MONERO_CONFIG_DIR/monerod.conf"   # an existing conf to write into
	run "$MONERO" config set log-level 2
	[ "$status" -eq 0 ]
	grep -q '^log-level=2' "$MONERO_CONFIG_DIR/monerod.conf"
	run "$MONERO" config get log-level
	[ "${lines[0]}" = 2 ]
	# list shows the set value (not the default 0).
	run "$MONERO" config list
	printf '%s\n' "$output" | grep -q "log-level	2	"
}

@test "FEAT-302 AC3: set replaces an existing key rather than duplicating it" {
	monero_config_env
	printf 'log-level=0\n' > "$MONERO_CONFIG_DIR/monerod.conf"
	"$MONERO" config set log-level 4 >/dev/null 2>&1
	[ "$(grep -c '^log-level=' "$MONERO_CONFIG_DIR/monerod.conf")" -eq 1 ]
	grep -q '^log-level=4' "$MONERO_CONFIG_DIR/monerod.conf"
}

@test "FEAT-302: config path prints the monerod.conf path; unset reverts to default" {
	monero_config_env
	run "$MONERO" config path
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == *"/monerod.conf" ]]
	printf 'log-level=7\n' > "$MONERO_CONFIG_DIR/monerod.conf"
	"$MONERO" config unset log-level >/dev/null 2>&1
	! grep -q '^log-level=' "$MONERO_CONFIG_DIR/monerod.conf"
	run "$MONERO" config get log-level
	[ "${lines[0]}" = 0 ]   # back to the compiled-in default
}

@test "FEAT-302 AC4: list/default parsing is awk-portable (BSD awk + gawk)" {
	monero_config_env
	# Force BSD awk if present (macOS /usr/bin/awk); else the system awk.
	# The parse must still yield the defaulted value.
	run "$MONERO" config list
	[ "$status" -eq 0 ]
	printf '%s\n' "$output" | grep -q "rpc-bind-port	18081	"
}

# ===========================================================================
# FEAT-303 — man pages + walkthrough
# ===========================================================================

MAN_DIR_M="$BATS_TEST_DIRNAME/../../share/man/man1"

# Render a manpage file portably (BUG-039): GNU man-db takes `-l`, BSD/macOS
# man renders a path argument directly; prefer -l where supported.
render_manfile_m() {
	if man -l "$1" >/dev/null 2>&1; then man -l "$1"; else man "$1"; fi
}

@test "FEAT-303 AC1/AC2: every monero node verb (+ parent) has a man page that renders" {
	command -v man >/dev/null || skip "man not installed"
	local f
	for f in monero monero-install monero-daemon monero-config; do
		[ -f "$MAN_DIR_M/$f.1" ] || { echo "missing: $f.1"; return 1; }
		run render_manfile_m "$MAN_DIR_M/$f.1"
		[ "$status" -eq 0 ] || { echo "render failed for $f.1: $output"; return 1; }
		[ -n "$output" ]
	done
}

@test "FEAT-303 AC2: parent monero(1) lists the node verbs" {
	for v in install daemon config version modules; do
		grep -q "$v" "$MAN_DIR_M/monero.1" || { echo "monero.1 missing $v"; return 1; }
	done
	# SEE ALSO cross-references the sibling commands.
	grep -q 'bitcoin (1)' "$MAN_DIR_M/monero.1"
	grep -q 'lightning (1)' "$MAN_DIR_M/monero.1"
}

@test "FEAT-303 AC3: walkthrough covers install -> daemon -> config, incl. --user/--stagenet/--prune" {
	local doc="$BATS_TEST_DIRNAME/../../docs/monero-walkthrough.md"
	[ -f "$doc" ]
	grep -q 'monero install' "$doc"
	grep -q 'monero daemon enable' "$doc"
	grep -q 'monero config' "$doc"
	grep -q -- '--user' "$doc"
	grep -q -- '--stagenet' "$doc"
	grep -q -- '--prune' "$doc"
}

@test "FEAT-303: daemon man page keeps system as the documented default (not user)" {
	# The (default) marker belongs to system, never to the rootless user mode
	# (the 3.x daemon posture). Source escapes dashes as \-\-, so match prose.
	grep -q 'system service (default)' "$MAN_DIR_M/monero-daemon.1"
	! grep -qi 'per-user service (default)' "$MAN_DIR_M/monero-daemon.1"
}
