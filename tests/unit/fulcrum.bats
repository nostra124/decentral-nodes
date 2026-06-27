#!/usr/bin/env bats
#
# Unit tests for the `fulcrum` command (2.1.0 milestone):
#   FEAT-055 multi-command packaging + dependency boundary
#   FEAT-056 service lifecycle
#   FEAT-057 config + cert
#   FEAT-058 admin inspection
#   FEAT-060 admin moderation
#
# The init system, sudo, secret store, and the Fulcrum admin socket are
# all mocked: init-system binaries via a PATH shim that logs its args,
# the admin RPC via $FULCRUM_ADMIN_FIXTURE canned JSON, node reachability
# via $FULCRUM_NODE_OK, and paths via $FULCRUM_ROOT/$FULCRUM_CONFIG_DIR/
# $FULCRUM_DATADIR so nothing escapes the per-test tmp dir.

setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	FULCRUM="$REPO/bin/fulcrum-node"
	BITCOIN="$REPO/bin/bitcoin-node"
	export SELF_LIBEXEC="$REPO/libexec"

	FROOT="$BATS_TEST_TMPDIR"
	export HOME="$FROOT/home"; mkdir -p "$HOME"
	export XDG_CONFIG_HOME="$HOME/.config"
	export FULCRUM_CONFIG_DIR="$FROOT/cfg"
	export FULCRUM_DATADIR="$FROOT/db"
	export FULCRUM_ROOT="$FROOT/root"
	# A real stub binary stands in for Fulcrum: enable's preflight
	# (service:_check_runnable) runs `<bin> --version` AS the service
	# account, so the override must point at something executable that
	# exits 0 on --version (BUG-031, mirrors streamline.bats).
	export FULCRUM_FULCRUMD="$FROOT/fulcrumd-stub"
	printf '#!/usr/bin/env bash\n:\n' > "$FULCRUM_FULCRUMD"
	chmod +x "$FULCRUM_FULCRUMD"
	unset FULCRUM_OS FULCRUM_NODE_OK FULCRUM_ADMIN_FIXTURE \
	      FULCRUM_ADMIN_ADDR FULCRUM_PORT_BUSY

	# Mock init-system + privileged tools; each logs its argv to $CALLLOG.
	MOCKBIN="$FROOT/mockbin"; mkdir -p "$MOCKBIN"
	CALLLOG="$FROOT/calls.log"; : > "$CALLLOG"
	local c
	for c in systemctl launchctl journalctl useradd sysadminctl log du \
	         dscl dseditgroup usermod chown tail; do
		printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n' "$c" "$CALLLOG" > "$MOCKBIN/$c"
		chmod +x "$MOCKBIN/$c"
	done
	# du must still print a size for `space`.
	printf '#!/usr/bin/env bash\necho "du $*" >> "%s"\necho "123M\t."\n' "$CALLLOG" > "$MOCKBIN/du"
	chmod +x "$MOCKBIN/du"
	# Hermeticity (BUG-036): a host that already has a real '_fulcrum' account
	# (from a live --system deploy) would short-circuit daemon:_ensure_account's
	# `id "$user"` existence check and skip the dscl account-creation branch the
	# BUG-031 macos test asserts. Stub `id` so any *username* lookup reports
	# "not found", while flag forms (`id -u`, `id -un`) pass through to real id.
	cat > "$MOCKBIN/id" <<-STUB
		#!/usr/bin/env bash
		case "\$1" in
		  -*) exec /usr/bin/id "\$@" ;;
		  "") exec /usr/bin/id ;;
		  *) exit 1 ;;
		esac
	STUB
	chmod +x "$MOCKBIN/id"
	# sudo logs then execs its args (so 'sudo systemctl' still records
	# systemctl). It strips a leading '-u <user>' so the enable preflight's
	# `sudo -u <svc> <bin> --version` execs the binary directly under the
	# single test uid (BUG-031, mirrors streamline.bats).
	cat > "$MOCKBIN/sudo" <<-STUB
		#!/usr/bin/env bash
		echo "sudo \$*" >> "$CALLLOG"
		if [ "\$1" = "-u" ]; then shift 2; fi
		exec "\$@"
	STUB
	chmod +x "$MOCKBIN/sudo"
	export PATH="$MOCKBIN:$PATH"
}

fixdir() {  # create a fixture dir with one <method>.json; echo its path
	local method="$1" json="$2" d="$FROOT/fx.$method"
	mkdir -p "$d"; printf '%s\n' "$json" > "$d/$method.json"; printf '%s\n' "$d"
}

# ===========================================================================
# FEAT-055 — multi-command packaging + dependency boundary
# ===========================================================================

@test "FEAT-055 AC2: fulcrum version equals bitcoin version (one package)" {
	run "$FULCRUM" version
	[ "$status" -eq 0 ]
	[ "$output" = "$(cat "$REPO/VERSION")" ]
	[ "$output" = "$("$BITCOIN" version)" ]
}

@test "FEAT-055 AC3: fulcrum help + modules list the libexec verbs" {
	run "$FULCRUM" help
	[ "$status" -eq 0 ] || [ -n "$output" ]
	run "$FULCRUM" modules
	[ "$status" -eq 0 ]
	[[ "$output" == *daemon* ]]
	[[ "$output" == *config* ]]
	[[ "$output" == *info* ]]
}

@test "FEAT-055 AC1: make install stages both bitcoin and fulcrum trees" {
	command -v stow >/dev/null 2>&1 || skip "stow not installed"
	local prefix="$FROOT/prefix"; mkdir -p "$prefix"
	( cd "$REPO" && ./configure --prefix="$prefix" >/dev/null 2>&1 && make install >/dev/null 2>&1 )
	# Staged build tree (stow source) mirrors $PREFIX *relative* —
	# build/decentral-nodes/bin, not build/bitcoin$prefix/bin. The latter was the
	# double-prefix packaging bug (BUG-038): absolute staging + `stow -t
	# $PREFIX` left files at $PREFIX$PREFIX/… and never on PATH.
	[ -f "$REPO/build/decentral-nodes/bin/bitcoin-node" ]
	[ -f "$REPO/build/decentral-nodes/bin/fulcrum-node" ]
	[ -d "$REPO/build/decentral-nodes/libexec/bitcoin-node" ]
	[ -d "$REPO/build/decentral-nodes/libexec/fulcrum-node" ]
	# …and `stow -t $PREFIX` installs directly into $PREFIX.
	[ -x "$prefix/bin/bitcoin-node" ]
	[ -x "$prefix/bin/fulcrum-node" ]
	[ -f "$prefix/share/lightning/apache/lnurlp.conf" ]
	( cd "$REPO" && make uninstall >/dev/null 2>&1; rm -rf build Makefile )
}

@test "FEAT-055 AC6: .rpk/identity is the meta-package (decentral-nodes); no second package" {
	[ "$(cat "$REPO/.rpk/identity")" = decentral-nodes ]
}

@test "FEAT-055 AC4: lint covers fulcrum and shellcheck flags a broken file" {
	grep -qE '^PACKAGES = .*fulcrum' "$REPO/Makefile.in"
	grep -qE 'shellcheck .* bin/\*' "$REPO/Makefile.in"
	command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"
	local broken="$FROOT/broken.sh"
	printf '#!/usr/bin/env bash\nif [ "$x" = ]; then echo bad\n' > "$broken"
	run shellcheck -S warning "$broken"
	[ "$status" -ne 0 ]
}

# Forbidden-sibling scanner mirroring the two FEAT-195 tests.
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

@test "FEAT-055 AC5: bin/fulcrum-node + libexec/fulcrum-node/* call no forbidden siblings" {
	run _scan_forbidden "$REPO/bin/fulcrum-node"
	[ "$status" -eq 1 ]
	local f
	while IFS= read -r f; do
		run _scan_forbidden "$f"
		[ "$status" -eq 1 ] || { echo "forbidden call in $f"; return 1; }
	done < <(find "$REPO/libexec/fulcrum-node" -type f)
}

@test "FEAT-055 AC5: the scanner catches a planted forbidden sibling call" {
	local planted="$FROOT/planted"
	printf '#!/usr/bin/env bash\ncache list\n' > "$planted"
	run _scan_forbidden "$planted"
	[ "$status" -eq 0 ]
}

# ===========================================================================
# FEAT-056 — service lifecycle
# ===========================================================================

@test "FEAT-056 AC1/AC3: enable --user (linux) writes a unit with no User= line" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	run "$FULCRUM" daemon enable --user
	[ "$status" -eq 0 ]
	local unit="$XDG_CONFIG_HOME/systemd/user/fulcrumd.service"
	[ -f "$unit" ]
	grep -q "ExecStart=$FULCRUM_FULCRUMD" "$unit"
	grep -q "$FULCRUM_DATADIR" "$unit"
	! grep -q "^User=" "$unit"
	run "$FULCRUM" daemon disable --user
	[ "$status" -eq 0 ]
	[ ! -f "$unit" ]
}

@test "FEAT-056 AC3: enable --system (linux) renders a User=fulcrum line" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	run "$FULCRUM" daemon enable --system
	[ "$status" -eq 0 ]
	local unit="$FULCRUM_ROOT/etc/systemd/system/fulcrumd.service"
	[ -f "$unit" ]
	grep -q "^User=fulcrum" "$unit"
	# @FULCRUMD@ must have been substituted away.
	! grep -q "@FULCRUMD@" "$unit"
}

@test "FEAT-262: enable defaults to --system when no mode is given (linux)" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	run "$FULCRUM" daemon enable
	[ "$status" -eq 0 ]
	# FEAT-262 flipped the default to --system: a bare enable installs the
	# privileged system unit (dedicated 'fulcrum' account), not the per-user bus.
	local sys="$FULCRUM_ROOT/etc/systemd/system/fulcrumd.service"
	[ -f "$sys" ]
	grep -q "^User=fulcrum" "$sys"
	[ ! -f "$XDG_CONFIG_HOME/systemd/user/fulcrumd.service" ]
	! grep -q "systemctl --user" "$CALLLOG"
}

@test "FEAT-262: disable defaults to --system (linux)" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	"$FULCRUM" daemon enable >/dev/null 2>&1     # default (system) install
	local sys="$FULCRUM_ROOT/etc/systemd/system/fulcrumd.service"
	[ -f "$sys" ]
	run "$FULCRUM" daemon disable
	[ "$status" -eq 0 ]
	[ ! -f "$sys" ]
	! grep -q "systemctl --user disable" "$CALLLOG"
}

@test "FEAT-262: enable help names --system as the default" {
	run "$FULCRUM" daemon enable --help
	[ "$status" -eq 0 ]
	echo "$output" | grep -q -- '--system (default)'
}

@test "FEAT-056 AC1: enable --user (macos) writes a LaunchAgent plist" {
	export FULCRUM_OS=macos FULCRUM_NODE_OK=yes
	run "$FULCRUM" daemon enable --user
	[ "$status" -eq 0 ]
	local unit="$HOME/Library/LaunchAgents/org.fulcrum.fulcrumd.plist"
	[ -f "$unit" ]
	! grep -q "UserName" "$unit"
}

@test "FEAT-056 AC2: enable errors + non-zero when bitcoind RPC unreachable" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=no
	run "$FULCRUM" daemon enable --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"bitcoind RPC unreachable"* ]]
}

@test "FEAT-056 AC4: start/stop dispatch systemctl --user (linux)" {
	export FULCRUM_OS=linux
	run "$FULCRUM" daemon start --user
	[ "$status" -eq 0 ]
	grep -q "systemctl --user start fulcrumd" "$CALLLOG"
	run "$FULCRUM" daemon stop --user
	grep -q "systemctl --user stop fulcrumd" "$CALLLOG"
}

@test "FEAT-056 AC4: start --system drives the system systemctl (linux)" {
	export FULCRUM_OS=linux
	run "$FULCRUM" daemon start --system
	[ "$status" -eq 0 ]
	grep -q "systemctl start fulcrumd" "$CALLLOG"
}

@test "FEAT-056 AC4: start (macos) drives launchctl kickstart" {
	export FULCRUM_OS=macos
	run "$FULCRUM" daemon start --user
	grep -q "launchctl kickstart gui/.*/org.fulcrum.fulcrumd" "$CALLLOG"
}

@test "FEAT-056 AC5: space reports index usage, errors when dir absent" {
	export FULCRUM_OS=linux
	rm -rf "$FULCRUM_DATADIR"
	run "$FULCRUM" daemon space --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"does not exist"* ]]
	mkdir -p "$FULCRUM_DATADIR"
	run "$FULCRUM" daemon space --user
	[ "$status" -eq 0 ]
}

@test "FEAT-056 AC6: install --from <bad> is rejected with error + non-zero" {
	run "$FULCRUM" install --from nonsense
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown source"* ]]
}

# --- uniform `daemon status` (parity with bitcoin/lightning/monero) --------

@test "daemon status: healthy reports the synced height from the admin RPC" {
	export FULCRUM_OS=linux
	export FULCRUM_ADMIN_FIXTURE="$(fixdir getinfo '{"version":"Fulcrum 1.9.1","height":799123,"clients":3}')"
	run "$FULCRUM" daemon status --user
	[ "$status" -eq 0 ]
	[[ "$output" == *"healthy"* ]]
	[[ "$output" == *"799123"* ]]
}

@test "daemon status: down errors non-zero with a hint when the admin RPC is unreachable" {
	export FULCRUM_OS=linux
	export FULCRUM_ADMIN_FIXTURE="$BATS_TEST_TMPDIR/empty-fx"   # no getinfo.json -> unreachable
	mkdir -p "$FULCRUM_ADMIN_FIXTURE"
	run "$FULCRUM" daemon status --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"down"* ]]
	[[ "$output" == *"unreachable"* ]]
}

@test "FEAT-307: fulcrum's top-level daemon verbs are removed (canonical: fulcrum daemon <verb>)" {
	# Harmonized: daemon lifecycle is `fulcrum daemon <verb>` only — the old
	# top-level shims (fulcrum enable/start/status/…) are gone. install +
	# admin verbs stay top-level.
	for v in enable disable start stop status monitor space; do
		[ ! -e "$REPO/libexec/fulcrum-node/$v" ] || { echo "lingering top-level shim: $v"; return 1; }
		run "$FULCRUM" "$v" --help
		[ "$status" -ne 0 ]
		[[ "$output" == *"not a fulcrum-node command"* ]]
	done
	# install stays top-level.
	[ -e "$REPO/libexec/fulcrum-node/install" ]
}

@test "daemon status: help + listing mention status" {
	run "$FULCRUM" daemon help
	[[ "$output" == *"status"* ]]
	run "$FULCRUM" daemon status --help
	[[ "$output" == *"reachable"* ]]
}

@test "FEAT-270: install --from release downloads, SHA256-verifies, and installs the prebuilt binary" {
	local td="$BATS_TEST_TMPDIR/rel"; mkdir -p "$td/stub" "$td/pfx/bin" "$td/pkg/Fulcrum-9.9.9-x86_64-linux"
	printf '#!/bin/sh\necho fake-fulcrum\n' > "$td/pkg/Fulcrum-9.9.9-x86_64-linux/Fulcrum"
	chmod +x "$td/pkg/Fulcrum-9.9.9-x86_64-linux/Fulcrum"
	( cd "$td/pkg" && tar -czf "$td/asset.tar.gz" Fulcrum-9.9.9-x86_64-linux )
	local sum; sum="$(sha256sum "$td/asset.tar.gz" | awk '{print $1}')"
	printf '%s  Fulcrum-9.9.9-x86_64-linux.tar.gz\n' "$sum" > "$td/sums.txt"
	cat > "$td/latest.json" <<-JSON
		{"tag_name":"v9.9.9","assets":[
		 {"name":"Fulcrum-9.9.9-x86_64-linux.tar.gz","browser_download_url":"http://stub/tarball"},
		 {"name":"Fulcrum-9.9.9-shasums.txt","browser_download_url":"http://stub/sums"}]}
	JSON
	cat > "$td/stub/uname" <<-STUB
		#!/usr/bin/env bash
		case "\$1" in -s) echo Linux ;; -m) echo x86_64 ;; *) echo Linux ;; esac
	STUB
	cat > "$td/stub/curl" <<-STUB
		#!/usr/bin/env bash
		out=""; url=""
		while [ \$# -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2 ;; -*) shift ;; *) url="\$1"; shift ;; esac; done
		case "\$url" in
		  */latest)  cat "$td/latest.json" ;;
		  */tarball) cp "$td/asset.tar.gz" "\$out" ;;
		  */sums)    cp "$td/sums.txt" "\$out" ;;
		  *) exit 22 ;;
		esac
	STUB
	printf '#!/usr/bin/env bash\nexec "$@"\n' > "$td/stub/sudo"
	chmod +x "$td/stub/"*
	PATH="$td/stub:$PATH" FULCRUM_RELEASE_API="http://stub" run "$FULCRUM" install --from release --prefix "$td/pfx"
	[ "$status" -eq 0 ]
	[ -x "$td/pfx/bin/Fulcrum" ]
	echo "$output" | grep -q "sha256 verified"
	echo "$output" | grep -q "installed Fulcrum v9.9.9"
}

@test "FEAT-270: install --from release refuses on a non-Linux host (no prebuilt mac binary)" {
	local stub="$BATS_TEST_TMPDIR/macuname"; mkdir -p "$stub"
	printf '#!/usr/bin/env bash\ncase "$1" in -s) echo Darwin ;; -m) echo arm64 ;; *) echo Darwin ;; esac\n' > "$stub/uname"
	chmod +x "$stub/uname"
	PATH="$stub:$PATH" run "$FULCRUM" install --from release
	[ "$status" -ne 0 ]
	echo "$output" | grep -q "only for Linux"
}

@test "FEAT-270: install help lists release, source, and docker" {
	run "$FULCRUM" install --help
	[ "$status" -eq 0 ]
	for s in release source docker; do echo "$output" | grep -q "$s" || { echo "missing: $s"; return 1; }; done
}

# ===========================================================================
# BUG-031 — fulcrum enable/config: privileged datadir/config ops via sudo
#
# Mirrors BUG-030 (bitcoin). The setup() sudo stub already logs its argv
# to $CALLLOG and execs, and dscl/dseditgroup/usermod/chown are stubbed
# (logging only), so these tests assert the *privileged call shape* of
# the three-user service-account model rather than the EACCES literally.
#
# A system enable must route the system datadir at $FULCRUM_ROOT/var/lib/
# fulcrum (not the test-only $FULCRUM_DATADIR override), so unset the
# override for the system-mode enable tests.
# ===========================================================================

@test "BUG-031: enable (system, linux) provisions a dedicated group and joins the operator" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	unset FULCRUM_DATADIR
	run "$FULCRUM" daemon enable --system
	[ "$status" -eq 0 ]
	# A --user-group account so the dedicated 'fulcrum' group exists, and
	# the invoking operator is added to it (group access, no sudo).
	grep -q 'useradd .*--user-group .*fulcrum' "$CALLLOG"
	grep -q 'usermod -a -G fulcrum' "$CALLLOG"
}

@test "BUG-031: enable (system, linux) owns the datadir <svc>:<svc> at 0750" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	unset FULCRUM_DATADIR
	run "$FULCRUM" daemon enable --system
	[ "$status" -eq 0 ]
	grep -q 'chown fulcrum:fulcrum .*var/lib/fulcrum' "$CALLLOG"
	grep -Eq 'chmod 0750 .*var/lib/fulcrum' "$CALLLOG"
}

@test "BUG-031: enable (system) refuses to install a unit the service account can't run" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	unset FULCRUM_DATADIR
	# Simulate the Homebrew-keg/dyld crash-loop: a binary that execs but
	# fails its --version preflight (a non-traversable parent dir or an
	# unreadable linked dylib has the same observable shape).
	printf '#!/usr/bin/env bash\nexit 1\n' > "$FULCRUM_FULCRUMD"
	chmod +x "$FULCRUM_FULCRUMD"
	run --separate-stderr "$FULCRUM" daemon enable --system
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "cannot run"
	# Must bail BEFORE installing the unit (no silent crash-loop left behind).
	[ ! -f "$FULCRUM_ROOT/etc/systemd/system/fulcrumd.service" ]
}

@test "BUG-031: config init (system) installs fulcrum.conf via sudo install -m 0640, not a bare redirect" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	export FULCRUM_CONFIG_DIR="$FULCRUM_ROOT/etc/fulcrum"
	run "$FULCRUM" config init --system
	[ "$status" -eq 0 ]
	local conf="$FULCRUM_CONFIG_DIR/fulcrum.conf"
	grep -Eq 'sudo install -m 0640 .*fulcrum\.conf' "$CALLLOG"
	grep -q 'chown fulcrum:fulcrum .*fulcrum\.conf' "$CALLLOG"
	[ -f "$conf" ]
	grep -q '^bitcoind = ' "$conf"
}

@test "BUG-031: config init (system) fails loudly when the privileged write fails" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	export FULCRUM_CONFIG_DIR="$FULCRUM_ROOT/etc/fulcrum"
	# Make 'sudo install …' fail so we prove the failure is detected and
	# never reported as success.
	cat > "$MOCKBIN/sudo" <<-STUB
		#!/usr/bin/env bash
		echo "sudo \$*" >> "$CALLLOG"
		if [ "\$1" = install ]; then exit 1; fi
		exec "\$@"
	STUB
	chmod +x "$MOCKBIN/sudo"
	run "$FULCRUM" config init --system
	[ "$status" -ne 0 ]
	[[ "$output" != *"wrote "* ]]
	[[ "$output" == *error* ]]
}

@test "BUG-031: enable (system, macos) creates a hidden UID-296 _fulcrum dscl account" {
	export FULCRUM_OS=macos FULCRUM_NODE_OK=yes
	unset FULCRUM_DATADIR
	run "$FULCRUM" daemon enable --system
	[ "$status" -eq 0 ]
	grep -q 'dscl . -create /Users/_fulcrum UniqueID 296' "$CALLLOG"
	grep -q 'dscl . -create /Users/_fulcrum IsHidden 1' "$CALLLOG"
	grep -q 'dscl . -create /Users/_fulcrum UserShell /usr/bin/false' "$CALLLOG"
	grep -q 'dseditgroup -o edit -a .* -t user _fulcrum' "$CALLLOG"
}

@test "BUG-031: monitor (system, macos) reads the log directly via group access (no sudo)" {
	export FULCRUM_OS=macos
	# monitor fails fast with a hint when there's no log yet (BUG-034), so
	# seed one (the system datadir is $FULCRUM_DATADIR via the harness).
	mkdir -p "$FULCRUM_DATADIR"; : > "$FULCRUM_DATADIR/fulcrum.log"
	run "$FULCRUM" daemon monitor --system
	[ "$status" -eq 0 ]
	! grep -q 'sudo' "$CALLLOG"
}

@test "BUG-034: monitor errors with a hint when no log exists yet" {
	export FULCRUM_OS=macos
	mkdir -p "$FULCRUM_DATADIR"; rm -f "$FULCRUM_DATADIR/fulcrum.log"
	run "$FULCRUM" daemon monitor --system
	[ "$status" -ne 0 ]
	echo "$output" | grep -q 'no log yet'
}

@test "BUG-031: monitor (system, linux) uses journalctl with no sudo" {
	export FULCRUM_OS=linux
	run "$FULCRUM" daemon monitor --system
	[ "$status" -eq 0 ]
	grep -q 'journalctl -u fulcrumd' "$CALLLOG"
	! grep -q 'sudo journalctl' "$CALLLOG"
}

@test "BUG-031: enable usage hint shows [--user] only, prose keeps --system default" {
	run "$FULCRUM" daemon enable --help
	[ "$status" -eq 0 ]
	echo "$output" | grep -q 'usage:.*\[--user\]'
	! echo "$output" | grep -Eq 'usage:.*--system \| --user'
	! echo "$output" | grep -Eq 'usage:.*--user \| --system'
	echo "$output" | grep -q -- '--system (default)'
}

# ===========================================================================
# BUG-034 — fulcrum enable/config deployment wiring
#
# Five fixes from a live --system deployment that needed manual steps:
#   1. config init --system scaffolds SYSTEM paths (datadir/cookie), not user
#   2. the scaffold drops the removed 'fast-sync' option (fulcrumd 2.x refuses
#      to start if present)
#   3. enable makes the system config dir traversable by the service account
#   4. binary resolution prefers the real Fulcrum in known system dirs over a
#      PATH name-collision with this package's own dispatcher
#   5. enable best-effort-joins the bitcoin service group so the svc reads the
#      node's group-readable cookie
# ===========================================================================

@test "BUG-034: config init --system scaffolds SYSTEM datadir + system cookie, not user paths" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	export FULCRUM_CONFIG_DIR="$FULCRUM_ROOT/etc/fulcrum"
	# The system datadir/cookie are derived from $FULCRUM_ROOT; unset the
	# test datadir override so the mode branch is exercised.
	unset FULCRUM_DATADIR FULCRUM_NODE_DATADIR
	run "$FULCRUM" config init --system
	[ "$status" -eq 0 ]
	local conf="$FULCRUM_CONFIG_DIR/fulcrum.conf"
	grep -q "^datadir = $FULCRUM_ROOT/var/lib/fulcrum\$" "$conf"
	grep -q "^rpccookie = $FULCRUM_ROOT/var/lib/bitcoin/.cookie\$" "$conf"
	# Must NOT scaffold the operator's user paths in system mode.
	! grep -q "^datadir = $HOME/.fulcrum\$" "$conf"
	! grep -q "$HOME/.bitcoin/.cookie" "$conf"
}

@test "BUG-034: config init (user) still scaffolds the per-user datadir + cookie" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	unset FULCRUM_DATADIR FULCRUM_NODE_DATADIR
	run "$FULCRUM" config init --user
	[ "$status" -eq 0 ]
	local conf="$FULCRUM_CONFIG_DIR/fulcrum.conf"
	grep -q "^datadir = $HOME/.fulcrum\$" "$conf"
	grep -q "^rpccookie = $HOME/.bitcoin/.cookie\$" "$conf"
}

@test "BUG-034: the scaffold contains NO removed 'fast-sync' option (keeps db_mem)" {
	export FULCRUM_NODE_OK=yes
	run "$FULCRUM" config init
	[ "$status" -eq 0 ]
	local conf="$FULCRUM_CONFIG_DIR/fulcrum.conf"
	! grep -q "fast-sync" "$conf"
	grep -q "^db_mem = " "$conf"
}

@test "BUG-034: 'fast-sync' is no longer in the editable allow-list" {
	"$FULCRUM" config init >/dev/null 2>&1
	run "$FULCRUM" config set fast-sync 1024
	[ "$status" -ne 0 ]
	[[ "$output" == *"allow-list"* ]]
}

@test "BUG-034: enable (system, linux) makes the config dir traversable by the svc account" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	unset FULCRUM_DATADIR FULCRUM_CONFIG_DIR
	run "$FULCRUM" daemon enable --system
	[ "$status" -eq 0 ]
	# Config dir owned by the service account and chmod'd traversable (0755),
	# so the daemon can open fulcrum.conf (was 0750 root:wheel → EACCES).
	grep -Eq 'chown fulcrum:fulcrum .*etc/fulcrum' "$CALLLOG"
	grep -Eq 'chmod 0755 .*etc/fulcrum' "$CALLLOG"
}

@test "BUG-034: binary resolution prefers a real system Fulcrum over a PATH dispatcher shim" {
	# Fake the package's own dispatcher leaking onto PATH as 'Fulcrum'.
	local pathdir="$FROOT/pathbin"; mkdir -p "$pathdir"
	printf '#!/usr/bin/env bash\necho dispatcher-shim\n' > "$pathdir/Fulcrum"
	chmod +x "$pathdir/Fulcrum"
	# A real Electrum server in a fake system bin dir.
	local sysdir="$FROOT/usr-local-bin"; mkdir -p "$sysdir"
	printf '#!/usr/bin/env bash\n:\n' > "$sysdir/Fulcrum"
	chmod +x "$sysdir/Fulcrum"
	# Source the daemon and resolve with the override unset; the system dir
	# (via the test-only $FULCRUM_SYSTEM_BINDIRS knob) must win over PATH.
	run env -u FULCRUM_FULCRUMD FULCRUM_SYSTEM_BINDIRS="$sysdir" \
		PATH="$pathdir:$PATH" bash -c \
		'source "$1"; daemon:_fulcrumd' _ "$REPO/libexec/fulcrum-node/daemon"
	[ "$status" -eq 0 ]
	[ "$output" = "$sysdir/Fulcrum" ]
}

@test "BUG-034: binary resolution falls back to PATH when no system Fulcrum exists" {
	local pathdir="$FROOT/pathbin2"; mkdir -p "$pathdir"
	printf '#!/usr/bin/env bash\n:\n' > "$pathdir/Fulcrum"
	chmod +x "$pathdir/Fulcrum"
	local emptydir="$FROOT/empty-sys"; mkdir -p "$emptydir"
	run env -u FULCRUM_FULCRUMD FULCRUM_SYSTEM_BINDIRS="$emptydir" \
		PATH="$pathdir:$PATH" bash -c \
		'source "$1"; daemon:_fulcrumd' _ "$REPO/libexec/fulcrum-node/daemon"
	[ "$status" -eq 0 ]
	[ "$output" = "$pathdir/Fulcrum" ]
}

@test "BUG-034: \$FULCRUM_FULCRUMD override beats the system-dir list" {
	local sysdir="$FROOT/usr-local-bin3"; mkdir -p "$sysdir"
	printf '#!/usr/bin/env bash\n:\n' > "$sysdir/Fulcrum"
	chmod +x "$sysdir/Fulcrum"
	run env FULCRUM_FULCRUMD=/my/override/Fulcrum FULCRUM_SYSTEM_BINDIRS="$sysdir" \
		bash -c 'source "$1"; daemon:_fulcrumd' _ "$REPO/libexec/fulcrum-node/daemon"
	[ "$status" -eq 0 ]
	[ "$output" = "/my/override/Fulcrum" ]
}

@test "BUG-034: enable (system, linux) best-effort-adds the svc to the bitcoin group when present" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	unset FULCRUM_DATADIR
	# The default usermod stub succeeds → the join is recorded.
	run "$FULCRUM" daemon enable --system
	[ "$status" -eq 0 ]
	grep -q 'usermod -aG bitcoin fulcrum' "$CALLLOG"
}

@test "BUG-034: enable (system, macos) best-effort-adds the svc to the _bitcoin group" {
	export FULCRUM_OS=macos FULCRUM_NODE_OK=yes
	unset FULCRUM_DATADIR
	run "$FULCRUM" daemon enable --system
	[ "$status" -eq 0 ]
	grep -q 'dseditgroup -o edit -a _fulcrum -t user _bitcoin' "$CALLLOG"
}

@test "BUG-034: enable does NOT fail when the bitcoin group is absent" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	unset FULCRUM_DATADIR
	# Make usermod fail (group absent) — enable must still succeed.
	printf '#!/usr/bin/env bash\necho "usermod $*" >> "%s"\nexit 1\n' "$CALLLOG" > "$MOCKBIN/usermod"
	chmod +x "$MOCKBIN/usermod"
	run "$FULCRUM" daemon enable --system
	[ "$status" -eq 0 ]
	# A hint is emitted, but enable does not abort.
	[[ "$output" == *"could not add"* ]]
	[ -f "$FULCRUM_ROOT/etc/systemd/system/fulcrumd.service" ]
}

# ===========================================================================
# FEAT-057 — config + cert
# ===========================================================================

@test "FEAT-057 AC1: config init writes bitcoind/auth/tcp/ssl/admin" {
	run "$FULCRUM" config init
	[ "$status" -eq 0 ]
	local f="$FULCRUM_CONFIG_DIR/fulcrum.conf"
	grep -q "^bitcoind = 127.0.0.1:8332" "$f"
	grep -q "^rpccookie = " "$f"
	grep -q "^tcp = " "$f"
	grep -q "^ssl = " "$f"
	grep -q "^admin = 127.0.0.1:" "$f"
}

@test "FEAT-057 AC2: with rpcauth in secret, config init emits rpcuser/rpcpassword" {
	printf '#!/usr/bin/env bash\n[ "$1" = get ] && [ "$2" = "bitcoin/rpc/bitcoin" ] && { echo "s3cr3t"; exit 0; }\nexit 1\n' > "$MOCKBIN/secret"
	chmod +x "$MOCKBIN/secret"
	run "$FULCRUM" config init
	[ "$status" -eq 0 ]
	local f="$FULCRUM_CONFIG_DIR/fulcrum.conf"
	grep -q "^rpcuser = bitcoin" "$f"
	grep -q "^rpcpassword = s3cr3t" "$f"
	! grep -q "^rpccookie" "$f"
	rm -f "$MOCKBIN/secret"
}

@test "FEAT-057 AC3: config set db_mem round-trips via config get" {
	"$FULCRUM" config init >/dev/null 2>&1
	run "$FULCRUM" config set db_mem 4096
	[ "$status" -eq 0 ]
	run "$FULCRUM" config get db_mem
	[ "$status" -eq 0 ]
	[ "$output" = "4096" ]
}

@test "FEAT-057 AC4: config set of a non-allow-listed key is rejected" {
	"$FULCRUM" config init >/dev/null 2>&1
	run "$FULCRUM" config set rpcpassword pwned
	[ "$status" -ne 0 ]
	[[ "$output" == *"rpcpassword"* ]]
	[[ "$output" == *"allow-list"* ]]
}

@test "FEAT-057 AC5: validate fails when bitcoind is unreachable" {
	"$FULCRUM" config init --no-ssl >/dev/null 2>&1
	export FULCRUM_NODE_OK=no
	run "$FULCRUM" config validate
	[ "$status" -ne 0 ]
	[[ "$output" == *"bitcoind RPC unreachable"* ]]
}

@test "FEAT-057 AC5: validate fails when ssl is set but the cert is missing" {
	"$FULCRUM" config init >/dev/null 2>&1   # ssl on, no cert generated
	export FULCRUM_NODE_OK=yes
	run "$FULCRUM" config validate
	[ "$status" -ne 0 ]
	[[ "$output" == *"cert"* ]]
}

@test "FEAT-057 AC5: validate fails when a configured port is in use" {
	"$FULCRUM" config init --no-ssl >/dev/null 2>&1
	export FULCRUM_NODE_OK=yes FULCRUM_PORT_BUSY=50001
	run "$FULCRUM" config validate
	[ "$status" -ne 0 ]
	[[ "$output" == *"50001"* ]]
	[[ "$output" == *"in use"* ]]
}

@test "FEAT-057 AC6: cert generates a parseable pair; second run refuses" {
	command -v openssl >/dev/null 2>&1 || skip "openssl not installed"
	run "$FULCRUM" cert
	[ "$status" -eq 0 ]
	run openssl x509 -noout -subject -in "$FULCRUM_CONFIG_DIR/cert.pem"
	[ "$status" -eq 0 ]
	run "$FULCRUM" cert
	[ "$status" -ne 0 ]
	[[ "$output" == *"--force"* ]]
	run "$FULCRUM" cert --force
	[ "$status" -eq 0 ]
}

# ===========================================================================
# FEAT-273 — config list/get/set/unset/path (modeled on bitcoin's FEAT-271,
# minus the default fallback: Fulcrum has no -help default dump, so a key
# not in the conf is an error). A temp config dir holds fulcrum.conf with
# both spaced ('key = value') and unspaced ('key=value') lines.
# ===========================================================================

feat273_env() {
	mkdir -p "$FULCRUM_CONFIG_DIR"
	printf '# fulcrum.conf\ndb_mem = 2048\ntcp=0.0.0.0:50001\n' \
		> "$FULCRUM_CONFIG_DIR/fulcrum.conf"
}

@test "FEAT-273 — config list shows the conf-set keys" {
	feat273_env
	run "$FULCRUM" config list
	[ "$status" -eq 0 ]
	echo "$output" | grep -q 'db_mem'
	echo "$output" | grep -q 'tcp'
}

@test "FEAT-273 — config get returns the conf value (spaced and unspaced)" {
	feat273_env
	run "$FULCRUM" config get db_mem
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '2048'
	run "$FULCRUM" config get tcp
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '0.0.0.0:50001'
}

@test "FEAT-273 — config get errors for an unknown key (no Fulcrum default)" {
	feat273_env
	run "$FULCRUM" config get totallyboguskey
	[ "$status" -ne 0 ]
	[[ "$output" == *"no default source for Fulcrum"* ]]
}

@test "FEAT-273 — config set replaces/adds a key and warns to restart" {
	feat273_env
	run "$FULCRUM" config set db_mem 4096
	[ "$status" -eq 0 ]
	echo "$output" | grep -qi 'restart'
	grep -qE '^db_mem = 4096' "$FULCRUM_CONFIG_DIR/fulcrum.conf"
}

@test "FEAT-273 — config unset removes a key" {
	feat273_env
	"$FULCRUM" config set banner hi >/dev/null 2>&1
	"$FULCRUM" config unset banner
	! grep -qE '^[[:space:]]*banner[[:space:]]*=' "$FULCRUM_CONFIG_DIR/fulcrum.conf"
}

@test "FEAT-273 — config path prints the conf file" {
	feat273_env
	run "$FULCRUM" config path
	[ "$status" -eq 0 ]
	[ "$output" = "$FULCRUM_CONFIG_DIR/fulcrum.conf" ]
}

# ---------------------------------------------------------------------------
# FEAT-298: fulcrum config list = TSV (NAME<TAB>VALUE<TAB>DESCRIPTION),
# mirroring bitcoin's FEAT-271. Fulcrum has no --help default dump, so
# VALUE is always the conf value and DESCRIPTION comes from a built-in
# map (empty for keys not in it). Hermetic via FULCRUM_CONFIG_DIR.
# ---------------------------------------------------------------------------
feat298_env() {
	mkdir -p "$FULCRUM_CONFIG_DIR"
	printf '# fulcrum.conf\ndb_mem = 2048\ntcp=0.0.0.0:50001\nsome_custom_key = 7\n' \
		> "$FULCRUM_CONFIG_DIR/fulcrum.conf"
}

@test "FEAT-298 — config list is TSV (name/value/description) from the conf + desc map" {
	feat298_env
	# fulcrum's setup() doesn't export SELF_QUIET, so a stderr info line may
	# merge into $output; the awk field tests skip it (it has no tabs).
	run "$FULCRUM" config list
	[ "$status" -eq 0 ]
	# Header row is present, tab-separated:
	echo "$output" | awk -F'\t' '$1=="NAME"&&$2=="VALUE"&&$3=="DESCRIPTION"{f=1} END{exit !f}'
	# conf value + a description from the built-in map:
	echo "$output" | awk -F'\t' '$1=="db_mem"&&$2=="2048"&&$3~/memory cache/{f=1} END{exit !f}'
	# unspaced 'key=value' line is parsed the same way:
	echo "$output" | awk -F'\t' '$1=="tcp"&&$2=="0.0.0.0:50001"{f=1} END{exit !f}'
	# a key not in the map gets an empty description (3 fields, blank 3rd):
	echo "$output" | awk -F'\t' '$1=="some_custom_key"&&$2=="7"&&$3==""{f=1} END{exit !f}'
}

@test "FEAT-298 — config list --set is accepted and lists the conf-set keys" {
	feat298_env
	run "$FULCRUM" config list --set
	[ "$status" -eq 0 ]
	echo "$output" | awk -F'\t' '$1=="NAME"{f=1} END{exit !f}'
	echo "$output" | awk -F'\t' '$1=="db_mem"&&$2=="2048"{f=1} END{exit !f}'
}

# ===========================================================================
# FEAT-058 — admin inspection
# ===========================================================================

@test "FEAT-058 AC1: info prints version, synced height, client count" {
	export FULCRUM_ADMIN_FIXTURE
	FULCRUM_ADMIN_FIXTURE="$(fixdir getinfo '{"version":"Fulcrum 1.9.1","height":799000,"daemon_height":800000,"clients":3,"db_size":"45 GiB"}')"
	run "$FULCRUM" info
	[ "$status" -eq 0 ]
	[[ "$output" == *"Fulcrum 1.9.1"* ]]
	[[ "$output" == *"799000"* ]]
	[[ "$output" == *"clients: 3"* ]]
}

@test "FEAT-058 AC2: sync shows blocks-behind and <100% when behind the tip" {
	FULCRUM_ADMIN_FIXTURE="$(fixdir getinfo '{"version":"x","height":799000,"daemon_height":800000}')" \
		run "$FULCRUM" sync
	[ "$status" -eq 0 ]
	[[ "$output" == *"1000 blocks behind"* ]]
	[[ "$output" == *"99%"* ]]
}

@test "FEAT-058 AC2: sync reports fully synced (100%) at the tip" {
	FULCRUM_ADMIN_FIXTURE="$(fixdir getinfo '{"version":"x","height":800000,"daemon_height":800000}')" \
		run "$FULCRUM" sync
	[ "$status" -eq 0 ]
	[[ "$output" == *"100%"* ]]
}

@test "FEAT-058 AC3: admin verbs exit non-zero + warn when port unreachable" {
	export FULCRUM_ADMIN_ADDR=127.0.0.1:65533   # closed, no fixture
	local v
	for v in info sync stats clients; do
		run "$FULCRUM" "$v"
		[ "$status" -ne 0 ] || { echo "$v did not fail"; return 1; }
		[[ "$output" == *"65533"* ]] || { echo "$v did not name the addr"; return 1; }
	done
}

@test "FEAT-058 AC4: clients lists entries from a multi-client fixture" {
	command -v jq >/dev/null 2>&1 || skip "jq not installed"
	FULCRUM_ADMIN_FIXTURE="$(fixdir clients '[{"id":1,"addr":"1.2.3.4"},{"id":2,"addr":"5.6.7.8"}]')" \
		run "$FULCRUM" clients
	[ "$status" -eq 0 ]
	[[ "$output" == *"1.2.3.4"* ]]
	[[ "$output" == *"5.6.7.8"* ]]
}

@test "FEAT-058 AC5: stats prints the stats JSON from a fixture" {
	FULCRUM_ADMIN_FIXTURE="$(fixdir stats '{"txs":42,"peers":7}')" \
		run "$FULCRUM" stats
	[ "$status" -eq 0 ]
	[[ "$output" == *"42"* ]]
}

@test "FEAT-058 AC6: logs invokes journalctl --user for the fulcrum unit (linux)" {
	export FULCRUM_OS=linux
	run "$FULCRUM" logs
	grep -q "journalctl --user -u fulcrumd" "$CALLLOG"
}

@test "FEAT-058 AC7: 'admin version' prints server and command versions" {
	FULCRUM_ADMIN_FIXTURE="$(fixdir getinfo '{"version":"Fulcrum 1.9.1"}')" \
		run "$FULCRUM" admin version
	[ "$status" -eq 0 ]
	[[ "$output" == *"Fulcrum 1.9.1"* ]]
	[[ "$output" == *"$(cat "$REPO/VERSION")"* ]]
}

@test "FEAT-058 AC8: 'fulcrum query' is not a known verb" {
	run "$FULCRUM" query
	[ "$status" -ne 0 ]
	[[ "$output" == *"not a fulcrum-node command"* ]]
}

# ===========================================================================
# FEAT-060 — admin moderation
# ===========================================================================

@test "FEAT-060 AC1: peers lists entries from a fixture" {
	command -v jq >/dev/null 2>&1 || skip "jq not installed"
	FULCRUM_ADMIN_FIXTURE="$(fixdir peers '[{"host":"node1.example"},{"host":"node2.example"}]')" \
		run "$FULCRUM" peers
	[ "$status" -eq 0 ]
	[[ "$output" == *"node1.example"* ]]
}

@test "FEAT-060 AC1: ban / kick report the server reply from a fixture" {
	FULCRUM_ADMIN_FIXTURE="$(fixdir ban '{"banned":"1.2.3.4"}')" \
		run "$FULCRUM" ban 1.2.3.4
	[ "$status" -eq 0 ]
	[[ "$output" == *"1.2.3.4"* ]]
	FULCRUM_ADMIN_FIXTURE="$(fixdir kick '{"kicked":7}')" \
		run "$FULCRUM" kick 7
	[ "$status" -eq 0 ]
	[[ "$output" == *"7"* ]]
}

@test "FEAT-060 AC1: banlist lists banned entries from a fixture" {
	FULCRUM_ADMIN_FIXTURE="$(fixdir listbanned '{"banned":["1.2.3.4"]}')" \
		run "$FULCRUM" banlist
	[ "$status" -eq 0 ]
	[[ "$output" == *"1.2.3.4"* ]]
}

@test "FEAT-060 AC1: loglevel accepts a valid level and reports the reply" {
	FULCRUM_ADMIN_FIXTURE="$(fixdir loglevel '{"loglevel":"debug"}')" \
		run "$FULCRUM" loglevel debug
	[ "$status" -eq 0 ]
	[[ "$output" == *"debug"* ]]
}

@test "FEAT-060 AC2: loglevel rejects a bad value before any call" {
	# No fixture / no server: a pre-call rejection must still exit non-zero
	# with an error naming the bad value (proves it never reached the RPC).
	export FULCRUM_ADMIN_ADDR=127.0.0.1:65533
	run "$FULCRUM" loglevel screaming
	[ "$status" -ne 0 ]
	[[ "$output" == *"screaming"* ]]
	[[ "$output" == *"normal|debug|trace"* ]]
}

@test "FEAT-060 AC3: moderation verbs warn + non-zero when unreachable" {
	export FULCRUM_ADMIN_ADDR=127.0.0.1:65533
	run "$FULCRUM" ban 1.2.3.4
	[ "$status" -ne 0 ]
	[[ "$output" == *"65533"* ]]
	run "$FULCRUM" peers
	[ "$status" -ne 0 ]
	[[ "$output" == *"65533"* ]]
}
