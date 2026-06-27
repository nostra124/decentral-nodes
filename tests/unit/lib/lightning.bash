#!/usr/bin/env bash
# Shared scaffolding for the tests/unit/lightning-NN.bats suites.
# FEAT-053 split of the monolithic tests/unit/lightning.bats:
# setup()/teardown() + every fixture/helper function live here,
# loaded by each chunk via `load lib/lightning`. Definitions only —
# no top-level statements run at source time.

#
# Unit tests for bin/lightning-node — the educational Lightning Network
# frontend on clightning (FEAT-170..206). Covers the 0.2.0–0.7.0
# surface: dispatcher, source-mode guard, and the
# libexec object dispatchers (wallet / channel / daemon / account /
# ledger / invoice / offer / address / lnurl / liquidity / plugin /
# peer / fee / alert). As of 0.5.x the CLI is purely object-oriented:
# top-level commands are objects, actions live as sub-commands. The
# wallet object is your Lightning identity — it owns both the
# clightning daemon's identity (info/balance/seed/unlock) and the
# git-backed state repo (init/push/pull/backup/restore). The peer
# object handles bare-peering + bootstrap + keepalive (FEAT-199).
# Operational verbs added in 0.7.0: fee (FEAT-200), rebalance
# (FEAT-201), alert (FEAT-204), plus the personal-node + routing-node
# operational guides (FEAT-202/203).


setup() {
	BATS_TMPDIR=${BATS_TMPDIR:-$(mktemp -d)}
	HOME="$(mktemp -d "$BATS_TMPDIR/home.XXXXXX")"
	unset XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_SHARE_HOME
	unset XDG_SOURCE_HOME XDG_BACKUP_HOME XDG_RUNTIME_DIR
	export HOME
	export SELF_QUIET=1
	export LIGHTNING_BIN="$BATS_TEST_DIRNAME/../../bin/lightning-node"

	# Point at a mock lightning-cli so verbs can exercise their
	# parsing logic without a real lightningd.
	FIXTURES="$BATS_TEST_DIRNAME/fixtures"
	export MOCK_STATE="$BATS_TMPDIR/mock-state.$$"
	rm -f "$MOCK_STATE"

	# Tests share these $$-keyed paths across the whole bats run (because
	# $$ stays constant in subshells), and individual @test bodies clean
	# them only via in-line rm -rf at the end — which is SKIPPED when an
	# assertion fails earlier in the body.  Purge here so a flake in test
	# A can't leak state into test B's setup and cascade.  Also reset the
	# mock's newaddr counter so address generation is deterministic per
	# test (otherwise the counter monotonically increases across the run).
	rm -rf "$BATS_TMPDIR/wallets.$$" "$BATS_TMPDIR/lnd.$$"
	rm -f "$MOCK_STATE.newaddr"

	# Shim PATH: put a dir with `lightning-cli -> mock` first.
	BIN_SHIM="$BATS_TMPDIR/bin.$$"
	rm -rf "$BIN_SHIM"
	mkdir -p "$BIN_SHIM"
	ln -sf "$FIXTURES/lightning-cli-mock" "$BIN_SHIM/lightning-cli"
	export PATH="$BIN_SHIM:$PATH"

	# BUG-037 — C locale. The dev box runs a UTF-8 locale (e.g. de_DE.UTF-8)
	# under which `case "$x" in [a-z]…` GLOB RANGES collate uppercase letters
	# into the lowercase range, so input validators that reject capitalised
	# usernames (api-recv/api-verify: `[a-z][a-z0-9_-]*`) wrongly accept them.
	# CI runs in C; pin it here so the range tests are locale-independent.
	export LC_ALL=C
	export LANG=C

	# BUG-037 — hide a host-installed lightningd. On a box that actually runs
	# the stack, `lightningd` is on PATH (e.g. /opt/homebrew/bin/lightningd).
	# That makes `daemon install` hit its idempotency guard ("already on PATH")
	# and short-circuits the auto-unlock probe in `daemon start`. Every test
	# that needs lightningd stubs its OWN copy into $BIN_SHIM (which stays
	# first on PATH), so the real one is never wanted. Drop the directories
	# that carry a real lightningd from PATH, but first preserve any external
	# tool that lives ONLY in such a dir (openssl is the only one on macOS —
	# /opt/homebrew/bin) by symlinking it into $BIN_SHIM.
	local _lnd_dirs="" _d
	local _oldifs="$IFS"; IFS=:
	for _d in $PATH; do
		[ "$_d" = "$BIN_SHIM" ] && continue
		[ -x "$_d/lightningd" ] && _lnd_dirs="$_lnd_dirs $_d"
	done
	IFS="$_oldifs"
	if [ -n "$_lnd_dirs" ]; then
		# Preserve tools that would otherwise vanish with the dropped dirs.
		for _t in openssl; do
			if [ ! -e "$BIN_SHIM/$_t" ]; then
				local _tp; _tp=$(command -v "$_t" 2>/dev/null) || true
				[ -n "$_tp" ] && ln -sf "$_tp" "$BIN_SHIM/$_t"
			fi
		done
		local _newpath=""
		IFS=:
		for _d in $PATH; do
			case " $_lnd_dirs " in *" $_d "*) continue ;; esac
			_newpath="${_newpath:+$_newpath:}$_d"
		done
		IFS="$_oldifs"
		export PATH="$_newpath"
		hash -r 2>/dev/null || true
	fi

	# BUG-037 — launchd plist directories are seams (LIGHTNING_LAUNCHAGENTS_DIR
	# / LIGHTNING_LAUNCHD_DIR). On a host that actually runs the stack (a real
	# /Library/LaunchDaemons/network.lightning.lightningd.plist installed), the
	# daemon's launchd_plist() would otherwise SEE that real system plist and
	# route user-mode installs / operate verbs at it. Pin BOTH dirs under the
	# per-test tmp tree so no test ever reads or writes the real Apple paths.
	# LaunchAgents already defaults to $HOME/Library/LaunchAgents (tmp HOME);
	# pin it explicitly too so the value is independent of HOME games a test
	# might play. Individual system-mode tests (e.g. _bug033_system_setup)
	# re-export LIGHTNING_LAUNCHD_DIR to their own assertable tmp dir.
	export LIGHTNING_LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"
	export LIGHTNING_LAUNCHD_DIR="$BATS_TMPDIR/launchd.$$"
	rm -rf "$LIGHTNING_LAUNCHD_DIR"

	# BUG-052 — pin the backing bitcoind datadir so enable's config-gen is
	# hermetic on a host that is itself running bitcoind (the resolver would
	# otherwise detect the live node's -datadir). The managed default keeps
	# the existing BUG-033 `bitcoin-datadir=/var/lib/bitcoin` assertions true;
	# the BUG-052 test unsets it to exercise auto-detection.
	export LIGHTNING_BITCOIN_DATADIR=/var/lib/bitcoin

	# BUG-037 — `id <username>` stub. The system installers probe whether the
	# service account already exists; on a live host a real _lightning /
	# clightning account makes that probe succeed, so the account-creation
	# branch (and the assertions that depend on it) would be skipped. Stub a
	# username lookup to "not found" so the create path always fires, while
	# the numeric/flag forms (id -u / -g / -G / id with no args) pass through
	# to the real /usr/bin/id so unrelated callers keep working.
	cat > "$BIN_SHIM/id" <<'EOF'
#!/bin/sh
# Flag forms and the no-arg form: delegate to the real id.
case "$1" in
	-*|"") exec /usr/bin/id "$@" ;;
esac
# A bare username argument → report "no such user".
echo "id: $1: no such user" >&2
exit 1
EOF
	chmod +x "$BIN_SHIM/id"
}

teardown() {
	rm -rf "$HOME" "$BIN_SHIM"
	rm -rf "$BATS_TMPDIR/wallets.$$" "$BATS_TMPDIR/lnd.$$"
	rm -f "$MOCK_STATE" "$MOCK_STATE.newaddr"
}

# Stubs curl+tar so `daemon enable --trustedcoin` doesn't hit
# GitHub. curl writes a fake tarball; tar extracts a placeholder
# trustedcoin binary. Tests that want the failure path stub curl
# themselves.
_stub_trustedcoin_curl() {
	cat > "$BIN_SHIM/curl" <<'EOF'
#!/bin/sh
# Pull the -o argument and write a placeholder file there. Real
# tarball isn't needed — our tar stub doesn't read the contents.
while [ $# -gt 0 ]; do
	case "$1" in -o) target=$2; shift 2 ;; *) shift ;; esac
done
[ -n "$target" ] && printf 'STUB TARBALL\n' > "$target"
exit 0
EOF
	chmod +x "$BIN_SHIM/curl"
	# Stub tar to drop a placeholder trustedcoin binary into -C dir.
	cat > "$BIN_SHIM/tar" <<'EOF'
#!/bin/sh
# Find -C <dir> and write trustedcoin there.
while [ $# -gt 0 ]; do
	case "$1" in -C) dest=$2; shift 2 ;; *) shift ;; esac
done
[ -n "$dest" ] && {
	mkdir -p "$dest"
	printf '#!/bin/sh\nexit 0\n' > "$dest/trustedcoin"
	chmod +x "$dest/trustedcoin"
}
exit 0
EOF
	chmod +x "$BIN_SHIM/tar"
}

# ---------------------------------------------------------------------------
# FEAT-198: LSPS1 inbound liquidity via cln-lsps plugin
# ---------------------------------------------------------------------------

# Set up a wallet + an LSP "boltz" config at $wallet/liquidity/lsp/boltz/peer.
# Tests that want the happy path also export MOCK_HELP_INCLUDES so the
# plugin gate passes.
_lsps_setup_wallet() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	mkdir -p "$LIGHTNING_WALLETS_ROOT/alice/liquidity/lsp/boltz"
	# Format: pubkey@host:port — uses a deterministic test pubkey.
	echo "02d96eadea3d780104449aca5c93461ce67c1564e2e1d73225fa67dd3b997a6018@45.86.229.190:9735" \
		> "$LIGHTNING_WALLETS_ROOT/alice/liquidity/lsp/boltz/peer"
}

# Set MOCK_HELP_INCLUDES so `cli help lsps1-get-info` returns a non-empty
# help array; this is how the verb detects the plugin is loaded.
_lsps_plugin_loaded() {
	export MOCK_HELP_INCLUDES='{"command":"lsps1-get-info","verbose":"..."}'
}

# ---------------------------------------------------------------------------
# FEAT-207 stage 1 — real `--from rpk` and `--from brew` invocations
# ---------------------------------------------------------------------------

# Drop a fake rpk on PATH that records its args and (optionally)
# installs a fake lightningd into BIN_SHIM.
_stub_rpk() {
	local exit_code="${1:-0}" install_lightningd="${2:-1}"
	cat > "$BIN_SHIM/rpk" <<EOF
#!/bin/sh
echo "rpk \$*" >> "$BIN_SHIM/rpk.calls"
if [ "$install_lightningd" = "1" ] && [ "$exit_code" = "0" ]; then
	printf '#!/bin/sh\necho "Core Lightning v26.04.1"\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
fi
exit $exit_code
EOF
	chmod +x "$BIN_SHIM/rpk"
}

_stub_brew() {
	local exit_code="${1:-0}" install_lightningd="${2:-1}"
	cat > "$BIN_SHIM/brew" <<EOF
#!/bin/sh
echo "brew \$*" >> "$BIN_SHIM/brew.calls"
if [ "$install_lightningd" = "1" ] && [ "$exit_code" = "0" ]; then
	printf '#!/bin/sh\necho "Core Lightning v26.04.1"\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
fi
exit $exit_code
EOF
	chmod +x "$BIN_SHIM/brew"
}

# ---------------------------------------------------------------------------
# FEAT-207 stage 2 — real `--from apk` invocation
# ---------------------------------------------------------------------------

# Records its args and (when exit 0) drops a fake lightningd onto PATH.
_stub_apk() {
	local exit_code="${1:-0}" install_lightningd="${2:-1}"
	cat > "$BIN_SHIM/apk" <<EOF
#!/bin/sh
echo "apk \$*" >> "$BIN_SHIM/apk.calls"
if [ "$install_lightningd" = "1" ] && [ "$exit_code" = "0" ]; then
	printf '#!/bin/sh\necho "Core Lightning v26.04.1"\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
fi
exit $exit_code
EOF
	chmod +x "$BIN_SHIM/apk"
}

# Privilege-escalation prefix stubs.  Each just exec's the rest of the
# argv — that lets the apk stub still record what was requested.
_stub_doas() {
	cat > "$BIN_SHIM/doas" <<'EOF'
#!/bin/sh
echo "doas $*" >> "${BIN_SHIM_CALLS_DIR:-$(dirname "$0")}/doas.calls"
exec "$@"
EOF
	chmod +x "$BIN_SHIM/doas"
}
_stub_sudo() {
	cat > "$BIN_SHIM/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >> "${BIN_SHIM_CALLS_DIR:-$(dirname "$0")}/sudo.calls"
exec "$@"
EOF
	chmod +x "$BIN_SHIM/sudo"
}

# CI containers often run as root, which makes `ic_root_prefix` return
# empty (correctly — no escalation needed).  This stub fakes a non-root
# UID so we can exercise the doas/sudo branches.
_stub_id_nonroot() {
	cat > "$BIN_SHIM/id" <<'EOF'
#!/bin/sh
case "$1" in
	-u) echo 1000 ;;
	*)  exec /usr/bin/id "$@" ;;
esac
EOF
	chmod +x "$BIN_SHIM/id"
}

# Mirror image: GH-hosted runners run as a non-root user, which makes
# `ic_root_prefix` pick sudo.  This stub fakes `id -u` returning 0 so
# we can exercise the no-prefix branch under any test runner.
_stub_id_root() {
	cat > "$BIN_SHIM/id" <<'EOF'
#!/bin/sh
case "$1" in
	-u) echo 0 ;;
	*)  exec /usr/bin/id "$@" ;;
esac
EOF
	chmod +x "$BIN_SHIM/id"
}

# BUG-037 — pretend `uname -s` reports Linux. On a real macOS host the
# daemon's is_macos()/platform_id() short-circuit to darwin/launchd BEFORE
# they ever read LIGHTNING_OS_RELEASE, so the faked /etc/os-release was
# ignored and the apk/source install paths were unreachable. Stubbing uname
# lets those Linux package-manager paths actually run (every external tool
# they touch — apk/apt-get/git/make/doas/sudo — is already stubbed in
# $BIN_SHIM), so the tests exercise real logic instead of erroring out.
_stub_uname_linux() {
	cat > "$BIN_SHIM/uname" <<'EOF'
#!/bin/sh
[ "$1" = "-s" ] && { echo Linux; exit 0; }
exec /usr/bin/uname "$@"
EOF
	chmod +x "$BIN_SHIM/uname"
}

# Fake /etc/os-release pointing platform_id() at Alpine.
_fake_alpine_os_release() {
	local f="$BATS_TMPDIR/os-release.$$"
	cat > "$f" <<'EOF'
ID=alpine
VERSION_ID=3.20.0
PRETTY_NAME="Alpine Linux v3.20"
EOF
	export LIGHTNING_OS_RELEASE="$f"
	# So platform_id() doesn't short-circuit to darwin on a macOS host.
	_stub_uname_linux
}

# ---------------------------------------------------------------------------
# FEAT-207 stage 3 — real `--from source` invocation (Ubuntu apt + git + make)
# ---------------------------------------------------------------------------

_stub_apt_get() {
	local exit_code="${1:-0}"
	cat > "$BIN_SHIM/apt-get" <<EOF
#!/bin/sh
echo "apt-get \$*" >> "$BIN_SHIM/apt-get.calls"
exit $exit_code
EOF
	chmod +x "$BIN_SHIM/apt-get"
}

# git stub: records args; for `clone <repo> <dest>` it creates <dest>
# with a stub configure script and Makefile so the subsequent build
# step doesn't have to find them on PATH.
_stub_git_for_source() {
	local exit_code="${1:-0}"
	cat > "$BIN_SHIM/git" <<EOF
#!/bin/sh
echo "git \$*" >> "$BIN_SHIM/git.calls"
if [ "\$1" = "clone" ]; then
	# Destination is the last arg (\$# is the count).
	eval dest=\\\${\$#}
	mkdir -p "\$dest/.git" "\$dest"
	printf '#!/bin/sh\nexit 0\n' > "\$dest/configure"
	chmod +x "\$dest/configure"
	# A no-op Makefile — \`make\` itself is a separate shim that fakes
	# install by dropping a lightningd binary onto PATH.
	printf 'all:\n\t@true\ninstall:\n\t@true\n' > "\$dest/Makefile"
fi
exit $exit_code
EOF
	chmod +x "$BIN_SHIM/git"
}

# make stub: records args; on `make install` drops a fake lightningd
# into BIN_SHIM so ic_verify_lightningd passes.  Mirrors the apk-stub
# pattern.
_stub_make() {
	local exit_code="${1:-0}" install_lightningd="${2:-1}"
	cat > "$BIN_SHIM/make" <<EOF
#!/bin/sh
echo "make \$*" >> "$BIN_SHIM/make.calls"
if [ "\$1" = "install" ] && [ "$install_lightningd" = "1" ] && [ "$exit_code" = "0" ]; then
	printf '#!/bin/sh\necho "Core Lightning v26.04.1"\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
fi
exit $exit_code
EOF
	chmod +x "$BIN_SHIM/make"
}

# Drop a fake /etc/os-release identifying as Ubuntu (the CI container
# IS Ubuntu — this is belt-and-braces in case the test order changes).
_fake_ubuntu_os_release() {
	local f="$BATS_TMPDIR/os-release.$$.ubuntu"
	cat > "$f" <<'EOF'
ID=ubuntu
VERSION_ID=24.04
PRETTY_NAME="Ubuntu 24.04"
EOF
	export LIGHTNING_OS_RELEASE="$f"
	# BUG-037 — so platform_id() reads the override instead of short-circuiting
	# to darwin on a macOS host (the source/apt path is otherwise unreachable).
	_stub_uname_linux
}

# Common setup for source-backend tests.
_source_common_setup() {
	_fake_ubuntu_os_release
	export LIGHTNING_BUILD_DIR="$BATS_TMPDIR/lightning-build.$$"
	rm -rf "$LIGHTNING_BUILD_DIR"
	export BIN_SHIM_CALLS_DIR="$BIN_SHIM"
	# GH-hosted runners are non-root → ic_root_prefix returns sudo and
	# the verb runs `sudo apt-get install` + `sudo make install`.  Stub
	# sudo so those calls route through our apt-get / make shims rather
	# than asking real sudo for a password (which fails on no-TTY).
	_stub_sudo
}

# ---------------------------------------------------------------------------
# FEAT-207 stage 4 — real `--from podman` invocation
# ---------------------------------------------------------------------------

# Records every podman invocation; handles the few sub-commands the
# verb cares about.  `container exists` returns 1 by default (no
# container); set PODMAN_CONTAINER_EXISTS=1 in the test env to flip it.
_stub_podman() {
	local pull_exit="${1:-0}" create_exit="${2:-0}"
	cat > "$BIN_SHIM/podman" <<EOF
#!/bin/sh
echo "podman \$*" >> "$BIN_SHIM/podman.calls"
case "\$1" in
	pull)
		exit $pull_exit ;;
	container)
		if [ "\$2" = "exists" ]; then
			[ "\${PODMAN_CONTAINER_EXISTS:-0}" = "1" ] && exit 0 || exit 1
		fi
		exit 0 ;;
	create)
		exit $create_exit ;;
	rm)
		exit 0 ;;
	run)
		# Used by the lightningd shim for --version checks.
		echo "Core Lightning v26.04.1"
		exit 0 ;;
	exec)
		# Used by the lightning-cli shim at runtime.  Not exercised here.
		exit 0 ;;
esac
exit 0
EOF
	chmod +x "$BIN_SHIM/podman"
}

_podman_common_setup() {
	# Isolate state and shim dirs into BATS_TMPDIR so tests don't litter $HOME.
	export LIGHTNING_DIR="$BATS_TMPDIR/lightning-state.$$"
	export LIGHTNING_SHIM_DIR="$BATS_TMPDIR/lightning-shim.$$"
	export LIGHTNING_PODMAN_NAME="clightning"
	rm -rf "$LIGHTNING_DIR" "$LIGHTNING_SHIM_DIR"
	# Make the shim dir part of PATH so the post-install warning doesn't fire.
	export PATH="$LIGHTNING_SHIM_DIR:$PATH"
}

# ---------------------------------------------------------------------------
# FEAT-207 — daemon lifecycle commands wired through podman
# ---------------------------------------------------------------------------

# Lifecycle variant of _stub_podman.  Defaults to "container exists,
# not running"; the start/stop verbs flip a state file the inspect
# branch reads.  daemon_running's `cli getinfo` (against the mocked
# lightning-cli) keys off MOCK_STATE, which podman start/stop also
# flip so the post-start probe + cli-tied checks see consistent state.
_stub_podman_lifecycle() {
	cat > "$BIN_SHIM/podman" <<EOF
#!/bin/sh
echo "podman \$*" >> "$BIN_SHIM/podman.calls"
state="$BIN_SHIM/podman-running"
case "\$1" in
	container)
		if [ "\$2" = "exists" ]; then
			[ "\${PODMAN_CONTAINER_EXISTS:-1}" = "1" ] && exit 0 || exit 1
		fi
		exit 0 ;;
	start)
		touch "\$state"
		rm -f "$MOCK_STATE"
		exit 0 ;;
	stop)
		rm -f "\$state"
		echo "down" > "$MOCK_STATE"
		exit 0 ;;
	inspect)
		if [ -f "\$state" ]; then echo "true"; else echo "false"; fi
		exit 0 ;;
	logs)
		echo "<podman log line>"
		exit 0 ;;
	exec)
		# CLI shim runtime path — not exercised here.
		exit 0 ;;
esac
exit 0
EOF
	chmod +x "$BIN_SHIM/podman"
}

_podman_lifecycle_setup() {
	export LIGHTNING_PODMAN_NAME="clightning"
	# Bootstrap is a separate code path that calls cli listpeers + jq.
	# Skip it for the lifecycle tests — peer-graph wiring isn't part of
	# what we're testing here.
	export LIGHTNING_NO_BOOTSTRAP=1
	# BUG-037 — on a macOS host that runs the live stack, launchctl has the
	# REAL network.lightning.lightningd job loaded, so cmd_stop/cmd_status see
	# launchd_loaded=true and pick the launchd branch BEFORE podman. Stub
	# launchctl so `launchctl list <label>` reports no loaded job (exit 1),
	# matching the no-launchd CI baseline; the podman branch then wins.
	cat > "$BIN_SHIM/launchctl" <<'EOF'
#!/bin/sh
# `launchctl list <label>` -> not loaded; everything else is a no-op.
exit 1
EOF
	chmod +x "$BIN_SHIM/launchctl"
	_stub_podman_lifecycle
}

# ---------------------------------------------------------------------------
# FEAT-207 — Alpine / OpenRC daemon enable
# ---------------------------------------------------------------------------

# Stubs for the system-account tools the OpenRC install path shells
# out to.  Each records its args; a few also produce side effects so
# the next step of the install pipeline finds what it expects (the
# state dir from `install -d`, in particular).
_stub_busybox_user_tools() {
	# addgroup / adduser / chown — record + exit 0.
	for cmd in addgroup adduser chown; do
		cat > "$BIN_SHIM/$cmd" <<EOF
#!/bin/sh
echo "$cmd \$*" >> "$BIN_SHIM/$cmd.calls"
exit 0
EOF
		chmod +x "$BIN_SHIM/$cmd"
	done
	# getent — always "not found" so the create-user / create-group
	# paths fire (without it the verb assumes the accounts already exist
	# and skips the addgroup / adduser calls we want to assert).
	cat > "$BIN_SHIM/getent" <<EOF
#!/bin/sh
echo "getent \$*" >> "$BIN_SHIM/getent.calls"
exit 2
EOF
	chmod +x "$BIN_SHIM/getent"
	# install -d <dir> needs to create the dir so the following
	# tee / chown calls have a parent to write into.  Ownership flags
	# (-o/-g) are dropped — we don't have the system users on the test
	# host anyway.
	cat > "$BIN_SHIM/install" <<EOF
#!/bin/sh
echo "install \$*" >> "$BIN_SHIM/install.calls"
for last in "\$@"; do :; done
case "\$*" in *-d*) mkdir -p "\$last" ;; esac
exit 0
EOF
	chmod +x "$BIN_SHIM/install"
}

_openrc_common_setup() {
	_fake_alpine_os_release   # also stubs uname -s -> Linux (BUG-037)
	# BUG-037 — init_system() picks OpenRC when `openrc` is on PATH (or
	# /etc/init.d exists) AND platform_id is alpine. On a macOS host neither
	# /etc/init.d nor a real openrc exists, so without this stub `daemon
	# enable` would route to the macOS launchd installer and the OpenRC
	# assertions could never run. Stub openrc so the Alpine/OpenRC code path
	# is reachable; everything it shells out to is stubbed below or seam-routed
	# (LIGHTNING_INIT_D / LIGHTNING_OPENRC_STATE).
	cat > "$BIN_SHIM/openrc" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$BIN_SHIM/openrc"
	export LIGHTNING_INIT_D="$BATS_TMPDIR/init.d.$$"
	export LIGHTNING_OPENRC_STATE="$BATS_TMPDIR/lightning-state.$$"
	rm -rf "$LIGHTNING_INIT_D" "$LIGHTNING_OPENRC_STATE"
	# CI runs as non-root → ic_root_prefix returns sudo.  Stub it so
	# the privileged calls (addgroup, install, tee, …) route through
	# our shims rather than asking real sudo for a password.
	_stub_sudo
	_stub_busybox_user_tools
	export BIN_SHIM_CALLS_DIR="$BIN_SHIM"
}

# ---------------------------------------------------------------------------
# FEAT-211: account-centric user-facing verb facade
# ---------------------------------------------------------------------------

# Common: create a wallet + an account.  Returns once both exist.
_acct_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent "monthly rent" --limit 100000 --overdraft warn >/dev/null
}

# ---------------------------------------------------------------------------
# FEAT-212 PR-1: account create mints bitcoin-address ID + API key,
# plus `account close`, `account nickname`, schema migration.
# ---------------------------------------------------------------------------

_acct212_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
}

# ---------------------------------------------------------------------------
# FEAT-212 PR-2: HTTP-API shell verbs (api-account-*).
# These exercise the verbs directly; the Python CGI dispatcher is
# covered separately under tests/python/test_api_accounts.py.
# ---------------------------------------------------------------------------

_acct212pr2_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	BATS_ADDR=$(sqlite3 "$LIGHTNING_WALLETS_ROOT/alice/state.db" "SELECT address FROM accounts WHERE name='rent';")
}

_acct212pr2_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-212 PR-4: deposit watcher.
# ---------------------------------------------------------------------------

_acct212pr4_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	BATS_ADDR_RENT=$(sqlite3 "$LIGHTNING_WALLETS_ROOT/alice/state.db" "SELECT address FROM accounts WHERE name='rent';")
}

_acct212pr4_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-212 PR-5: account garbage collector.
# ---------------------------------------------------------------------------

_acct212pr5_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create fresh >/dev/null
	"$LIGHTNING_BIN" account create stale >/dev/null
	"$LIGHTNING_BIN" account create closer >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	# Backdate 'stale' to 95 days ago.
	sqlite3 "$BATS_DB" "UPDATE accounts SET last_api_call_at = strftime('%s','now')-95*86400, created_at = strftime('%s','now')-95*86400 WHERE name='stale';"
	# Mark 'closer' as long-closed (14 days ago).
	sqlite3 "$BATS_DB" "UPDATE accounts SET closed_at = strftime('%s','now')-14*86400 WHERE name='closer';"
}

_acct212pr5_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-213: operator fee skim primitives.
# ---------------------------------------------------------------------------

_acct213_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='rent';")
	BATS_FEES="$LIGHTNING_WALLETS_ROOT/alice/fees.recfile"
}

_acct213_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# The FEAT-213 spec assertion lives in its own batch spec PR
# (FEAT-213..220); this implementation PR doesn't carry it directly.
# A spec-existence test would fail in CI until the spec PR merges.

# ---------------------------------------------------------------------------
# FEAT-214: fee revenue dashboard verb.
# ---------------------------------------------------------------------------

_acct214_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='rent';")
}

_acct214_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-215: fee-policy autotune cron.
# ---------------------------------------------------------------------------

_acct215_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create rent >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='rent';")
	BATS_FEES="$LIGHTNING_WALLETS_ROOT/alice/fees.recfile"
}

_acct215_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-218: referral schema + invite codes.
# ---------------------------------------------------------------------------

_acct218_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create alice-acct >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='alice-acct';")
}

_acct218_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-219: referral fee distribution.
# ---------------------------------------------------------------------------

_acct219_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create inv-acct >/dev/null
	"$LIGHTNING_BIN" account invite-code create inv-acct --code refcode >/dev/null
	REMOTE_ADDR=10.0.0.1 "$LIGHTNING_BIN" api-accounts-create --invite-code refcode >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_INV_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='inv-acct';")
	BATS_REF_NAME=$(sqlite3 "$BATS_DB" "SELECT name FROM accounts WHERE name LIKE 'anon-%' LIMIT 1;")
	BATS_REF_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='$BATS_REF_NAME';")
}

_acct219_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-223: inter-account transfer.
# ---------------------------------------------------------------------------

_acct223_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create alpha >/dev/null
	"$LIGHTNING_BIN" account create beta >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_A_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='alpha';")
	BATS_B_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='beta';")
	# Fund alpha.
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts,account,direction,amount_msat,message) VALUES(datetime('now'),'alpha','in',100000000,'seed');"
}

_acct223_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# The FEAT-223 spec assertion lives in its own batch spec PR
# (FEAT-223..227); this implementation PR doesn't carry it directly.

# ---------------------------------------------------------------------------
# FEAT-225: commercial invoice with structured reference + payment terms.
# ---------------------------------------------------------------------------

_acct225_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create shop >/dev/null
	"$LIGHTNING_BIN" account create other >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_SHOP_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='shop';")
	BATS_OTHER_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='other';")
}

_acct225_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning" "$MOCK_STATE.lastdesc"
}

# ---------------------------------------------------------------------------
# FEAT-222 PR-2: wallet-user layer (schema + CLI bootstrap).
# ---------------------------------------------------------------------------

_user222_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
}

_user222_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-222 PR-3: passkey crypto foundation (schema + helpers).
# ---------------------------------------------------------------------------

_acct222pr3_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	# Trigger migrate_accounts_schema so the FEAT-222 PR-3 tables
	# (user_passkeys + auth_challenges_user) materialise on this DB.
	"$LIGHTNING_BIN" account list >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
}

# Stub the rpk `secret` tool with a $BATS_TMPDIR-backed key-value store so
# _session-token's mint/verify roundtrip is reproducible without a real
# keyring.  The store path must be stable across invocations within the
# test (each invocation forks a fresh shell -> its own $$), so the dir
# uses BIN_SHIM (which is already test-unique) rather than $$.
_stub_secret() {
	cat > "$BIN_SHIM/secret" <<EOF
#!/bin/bash
store="$BIN_SHIM/secret-store"
mkdir -p "\$store"
case "\$1" in
	get) f="\$store/\${2//\//_}"; [ -f "\$f" ] && cat "\$f" || exit 1 ;;
	set) f="\$store/\${2//\//_}"; cat > "\$f" ;;
	*) exit 1 ;;
esac
EOF
	chmod +x "$BIN_SHIM/secret"
}

# ---------------------------------------------------------------------------
# FEAT-229: sat/fiat price oracle.
# ---------------------------------------------------------------------------

_price229_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
}

_price229_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-226: standing orders (Dauerauftrag) — scheduled recurring payment.
# ---------------------------------------------------------------------------

_acct226_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create payer >/dev/null
	"$LIGHTNING_BIN" account create landlord >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_PAYER_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='payer';")
	# Fund payer.
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts,account,direction,amount_msat,message) VALUES(datetime('now'),'payer','in',100000000,'seed');"
}

_acct226_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-227: direct debit (Lastschrift) + mandates.
# ---------------------------------------------------------------------------

_acct227_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create cust >/dev/null
	"$LIGHTNING_BIN" account create shop >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_CUST_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='cust';")
	BATS_SHOP_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='shop';")
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts,account,direction,amount_msat,message) VALUES(datetime('now'),'cust','in',100000000,'seed');"
}

_acct227_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

_mk_mandate() {
	# $1 mode (auto|approval); echoes "<mid> <secret>"
	local out
	out=$("$LIGHTNING_BIN" api-account-mandate "$BATS_CUST_ADDR" create shop 50000 monthly --mode "${1:-auto}")
	echo "$(echo "$out" | jq -r '.id') $(echo "$out" | jq -r '.secret')"
}

# ---------------------------------------------------------------------------
# FEAT-228: commerce charge lifecycle (escrow / auth-capture / refund /
# installments / dunning).
# ---------------------------------------------------------------------------

_acct228_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create shop >/dev/null
	"$LIGHTNING_BIN" account create buyer >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_SHOP_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='shop';")
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts,account,direction,amount_msat,message) VALUES(datetime('now'),'buyer','in',100000000,'seed');"
}

_acct228_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

_chg() {
	# echoes a new charge id for buyer of $1 sat (extra args passed through)
	"$LIGHTNING_BIN" api-account-charge "$BATS_SHOP_ADDR" create buyer "$@" | jq -r '.id'
}

_sat() { sqlite3 "$BATS_DB" "SELECT COALESCE(SUM(amount_msat),0)/1000 FROM ledger WHERE account='$1';"; }

# ---------------------------------------------------------------------------
# FEAT-230: tax-relevant transaction DATA export (FIFO, fiat-valued).
# ---------------------------------------------------------------------------

_acct230_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create trader >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	# Acquisitions: 2023-05-01 (500k sat @25000), 2024-01-10 (1M sat @40000).
	# Disposal:    2024-06-10 (400k sat @50000) -> FIFO matches the 2023 lot.
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts,account,direction,amount_msat,message) VALUES
		('2023-05-01 12:00:00','trader','in', 500000000,'acq1'),
		('2024-01-10 12:00:00','trader','in',1000000000,'acq2'),
		('2024-06-10 12:00:00','trader','out',-400000000,'spend1');"
	sqlite3 "$BATS_DB" "INSERT INTO prices(ts,base,btc_fiat,source) VALUES
		(1682942400,'EUR',25000,'test'),
		(1704888000,'EUR',40000,'test'),
		(1718020800,'EUR',50000,'test');"
}

_acct230_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-216: interest mode — negative fees pay users a yield (opt-in).
# ---------------------------------------------------------------------------

_acct216_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create saver >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='saver';")
	BATS_FEES="$LIGHTNING_WALLETS_ROOT/alice/fees.recfile"
}

_acct216_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

_deposit_100k() {
	local outs
	outs=$(jq -nc --arg a "$BATS_ADDR" \
		'[{"txid":"feed","output":0,"status":"confirmed","address":$a,"amount_msat":"100000000msat"}]')
	MOCK_LISTFUNDS_OUTPUTS="$outs" "$LIGHTNING_BIN" account topup-watcher run >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# FEAT-217: autopilot pay-target intelligence.
# ---------------------------------------------------------------------------

_paytarget_history() {
	# Build a MOCK_LISTPAYS JSON: $1=node, recent completed pays.
	local now; now=$(date -u +%s)
	export PT_A=02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
	export PT_B=03bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
	export PT_C=02cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
	MOCK_LISTPAYS=$(jq -nc --arg a "$PT_A" --arg b "$PT_B" --arg c "$PT_C" --argjson now "$now" '[
		{status:"complete",destination:$a,amount_msat:"10000000msat",created_at:($now-100)},
		{status:"complete",destination:$a,amount_msat:10000000,created_at:($now-200)},
		{status:"complete",destination:$a,amount_msat:10000000,created_at:($now-300)},
		{status:"complete",destination:$b,amount_msat:5000000,created_at:($now-400)},
		{status:"complete",destination:$c,amount_msat:50000000,created_at:($now-500)},
		{status:"failed",  destination:$b,amount_msat:99000000,created_at:($now-50)},
		{status:"complete",destination:$a,amount_msat:9999000000,created_at:($now-99999999)}
	]')
	export MOCK_LISTPAYS
}

# ---------------------------------------------------------------------------
# FEAT-233: compliance module framework (hooks + config + audit log).
# ---------------------------------------------------------------------------

_cc_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create alpha >/dev/null
	"$LIGHTNING_BIN" account create beta >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_CF="$LIGHTNING_WALLETS_ROOT/alice/compliance.recfile"
	BATS_A_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='alpha';")
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts,account,direction,amount_msat,message) VALUES(datetime('now'),'alpha','in',100000000,'seed');"
}

_cc_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

_cc_test_module() {
	# $1 = deny|allow ; append a self-test module record.
	printf '\nmodule: test\nenabled: on\ndecision: %s\n' "$1" >> "$BATS_CF"
}

# ---------------------------------------------------------------------------
# FEAT-209: wallet PWA + `lightning ui` installer.
# ---------------------------------------------------------------------------







# ---------------------------------------------------------------------------
# FEAT-346/347: "Real PWA" — service worker (offline app shell) + web push.
# ---------------------------------------------------------------------------








# ---------------------------------------------------------------------------
# FEAT-220: referral UX in the PWA (invite-codes endpoint + PWA wiring).
# ---------------------------------------------------------------------------

_acct220_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create bob >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_ADDR=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='bob';")
}

_acct220_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}


# ---------------------------------------------------------------------------
# FEAT-231: PWA commerce + POS (mandate pulls listing + PWA wiring).
# ---------------------------------------------------------------------------

_acct231_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create cust >/dev/null
	"$LIGHTNING_BIN" account create shop >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_CUST=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='cust';")
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts,account,direction,amount_msat,message) VALUES(datetime('now'),'cust','in',100000000,'seed');"
}

_acct231_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}



# ---------------------------------------------------------------------------
# FEAT-222 PR-5: user invite-codes + hierarchical governance.
# ---------------------------------------------------------------------------

_pr5_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.pr5.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.pr5.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	# Create two users: root + child.
	ROOT_UID=$("$LIGHTNING_BIN" wallet user create --label root 2>/dev/null | awk '/created/{print $NF}')
	CHILD_UID=$("$LIGHTNING_BIN" wallet user create --label child --referrer "$ROOT_UID" 2>/dev/null | awk '/created/{print $NF}')
}

_pr5_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-222 PR-7: PWA user registration / login flow + Show API key.
# ---------------------------------------------------------------------------










# ---------------------------------------------------------------------------
# FEAT-222 PR-6: access control — require_referral + invite whitelist.
# ---------------------------------------------------------------------------

_acct222pr6_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create sponsor >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_ACCESS="$LIGHTNING_WALLETS_ROOT/alice/access.recfile"
}

_acct222pr6_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-243: capability profiles + fund classification.
# ---------------------------------------------------------------------------

_acct243_setup() {
	export LIGHTNING_WALLETS_ROOT="$BATS_TMPDIR/wallets.$$"
	export LIGHTNING_DIR="$BATS_TMPDIR/lnd.$$"
	mkdir -p "$LIGHTNING_DIR"
	"$LIGHTNING_BIN" wallet new alice >/dev/null
	"$LIGHTNING_BIN" account create cust >/dev/null
	"$LIGHTNING_BIN" account create shop >/dev/null
	BATS_DB="$LIGHTNING_WALLETS_ROOT/alice/state.db"
	BATS_CUST=$(sqlite3 "$BATS_DB" "SELECT address FROM accounts WHERE name='cust';")
	sqlite3 "$BATS_DB" "INSERT INTO ledger(ts,account,direction,amount_msat,message) VALUES(datetime('now'),'cust','in',100000000,'seed');"
}

_acct243_teardown() {
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$LIGHTNING_DIR" "$HOME/.lightning"
}

# ---------------------------------------------------------------------------
# FEAT-272: lightning config (list/get/set/unset/path). A temp config dir
# holds the CLN 'config' file; a stub lightningd serves --help so 'get' can
# resolve compiled-in defaults.
# ---------------------------------------------------------------------------
feat272_env() {
	export LIGHTNING_CONFIG_DIR="$HOME/cfgdir"
	mkdir -p "$LIGHTNING_CONFIG_DIR"
	printf '# cln config\nnetwork=bitcoin\nlog-level=debug\n' > "$LIGHTNING_CONFIG_DIR/config"
	export LIGHTNING_LIGHTNINGD="$HOME/lightningd-help-stub"
	cat > "$LIGHTNING_LIGHTNINGD" <<-'STUB'
		#!/usr/bin/env bash
		[ "$1" = --help ] && printf '%s\n' \
		  '  --alias=<arg>' \
		  '       Up to 32-byte alias for node (default: SILLY-NAME).' \
		  '  --log-level=<arg>' \
		  '       Log level (default: info).'
		exit 0
	STUB
	chmod +x "$LIGHTNING_LIGHTNINGD"
}

# ---------------------------------------------------------------------------
# BUG-033 — `daemon enable --system` must produce a WORKING node on a
# fresh machine with no manual steps. Three fixes, all in the system
# installers (install_system / install_macos_system / install_openrc_system):
#   1. ExecStart points at the readlink-resolved lightningd, not the brew
#      symlink (CLN: "I cannot find myself at ..." otherwise).
#   2. The generated system config wires the bitcoind backend in:
#      bitcoin-cli=<abs>, bitcoin-datadir=/var/lib/bitcoin, and
#      disable-plugin=cln-grpc (cln-grpc crashes lightningd if it can't
#      bind its port).
#   3. The service user is best-effort-added to the bitcoind service
#      group so it can read bitcoind's group-readable cookie (FEAT-274);
#      a missing group hints + continues, never fails enable.
# ---------------------------------------------------------------------------

# Stub the privileged + user-creation tooling for an in-place system
# enable, redirecting every filesystem write under $BATS_TMPDIR. Stubs:
#   sudo            -> exec passthrough (records nothing extra needed)
#   useradd/usermod -> record, exit 0
#   getent          -> "not found" so the create paths fire
#   dscl/dseditgroup-> record (macOS); reads return nonzero
#   install         -> mkdir -p the -d target
#   chown           -> no-op
#   systemctl       -> no-op (daemon-reload)
# Sets LIGHTNING_SYSTEM_STATE / LIGHTNING_SYSTEMD_DIR / LIGHTNING_LAUNCHD_DIR
# so the generated config + unit land somewhere assertable.
_bug033_system_setup() {
	export LIGHTNING_SYSTEM_STATE="$BATS_TMPDIR/lnsys-state.$$"
	export LIGHTNING_SYSTEMD_DIR="$BATS_TMPDIR/lnsys-systemd.$$"
	export LIGHTNING_LAUNCHD_DIR="$BATS_TMPDIR/lnsys-launchd.$$"
	# FEAT-298: the system config now lives under /etc (FHS). Redirect it to
	# a temp dir so the installer's writes stay hermetic (no real /etc leak).
	export LIGHTNING_CONFIG_DIR="$BATS_TMPDIR/lnsys-etc.$$"
	rm -rf "$LIGHTNING_SYSTEM_STATE" "$LIGHTNING_SYSTEMD_DIR" "$LIGHTNING_LAUNCHD_DIR" "$LIGHTNING_CONFIG_DIR"
	export BIN_SHIM_CALLS_DIR="$BIN_SHIM"

	_stub_sudo

	# A REAL lightningd target + a symlink to it, so we can assert the
	# unit references the resolved target and not the symlink (fix #1).
	cat > "$BATS_TMPDIR/lightningd-real.$$" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$BATS_TMPDIR/lightningd-real.$$"
	ln -sf "$BATS_TMPDIR/lightningd-real.$$" "$BIN_SHIM/lightningd"

	# bitcoin-cli on PATH so fix #2 has an absolute path to pin.
	cat > "$BIN_SHIM/bitcoin-cli" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$BIN_SHIM/bitcoin-cli"

	# User-creation + privileged no-ops, recording their calls.
	for cmd in useradd usermod chown dseditgroup; do
		cat > "$BIN_SHIM/$cmd" <<EOF
#!/bin/sh
echo "$cmd \$*" >> "$BIN_SHIM/$cmd.calls"
exit 0
EOF
		chmod +x "$BIN_SHIM/$cmd"
	done
	# getent — not found, so create paths fire and group lookups can be
	# toggled per-test by re-stubbing.
	cat > "$BIN_SHIM/getent" <<EOF
#!/bin/sh
echo "getent \$*" >> "$BIN_SHIM/getent.calls"
exit 2
EOF
	chmod +x "$BIN_SHIM/getent"
	# install -d <dir> creates the dir; ownership flags ignored.
	cat > "$BIN_SHIM/install" <<EOF
#!/bin/sh
echo "install \$*" >> "$BIN_SHIM/install.calls"
for last in "\$@"; do :; done
case "\$*" in *-d*) mkdir -p "\$last" ;; esac
exit 0
EOF
	chmod +x "$BIN_SHIM/install"
	# systemctl — no-op (daemon-reload).
	cat > "$BIN_SHIM/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$BIN_SHIM/systemctl"
}

# macOS extra: stub dscl. Reads (-read/-list) return nonzero so the
# create path runs; -create records + succeeds.
_bug033_stub_dscl() {
	cat > "$BIN_SHIM/dscl" <<EOF
#!/bin/sh
echo "dscl \$*" >> "$BIN_SHIM/dscl.calls"
case "\$*" in
	*-create*) exit 0 ;;
	*-read*|*-list*) exit 1 ;;
	*) exit 1 ;;
esac
EOF
	chmod +x "$BIN_SHIM/dscl"
}
