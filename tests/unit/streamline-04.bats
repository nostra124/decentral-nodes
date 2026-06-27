#!/usr/bin/env bats
#
# streamline unit tests — part 4 of 4 (FEAT-053 split of tests/unit/streamline.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/streamline.bash.

bats_require_minimum_version 1.5.0
load lib/streamline


@test "FEAT-306: share-cookie listed in help; enable's port-busy refusal hints at it" {
	run "$BITCOIN_BIN" daemon help
	[[ "$output" == *"share-cookie"* ]]
	feat034_env linux
	export BITCOIN_PORT_BUSY=8332
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"share-cookie"* ]]
}

@test "FEAT-034 — enable --user (macos) installs a LaunchAgent without UserName" {
	feat034_env macos
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	local unit="$HOME/Library/LaunchAgents/org.bitcoin.bitcoind.plist"
	[ -f "$unit" ]
	! grep -q 'UserName' "$unit"
	grep -q 'launchctl bootstrap gui/' "$FEAT034_CALLS"
}

@test "FEAT-034 — enable --system (linux) creates the bitcoin user and a privileged unit" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	local unit="$BITCOIN_DAEMON_ROOT/etc/systemd/system/bitcoind.service"
	[ -f "$unit" ]
	grep -q '^User=bitcoin' "$unit"
	grep -q "datadir=$BITCOIN_DAEMON_ROOT/var/lib/bitcoin" "$unit"
	grep -q 'useradd .* bitcoin' "$FEAT034_CALLS"
	grep -q 'systemctl enable --now bitcoind' "$FEAT034_CALLS"
	# --system must NOT use the per-user bus.
	! grep -q 'systemctl --user' "$FEAT034_CALLS"
}

@test "FEAT-034 — enable --system (macos) installs a LaunchDaemon running as bitcoin" {
	feat034_env macos
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	local unit="$BITCOIN_DAEMON_ROOT/Library/LaunchDaemons/org.bitcoin.bitcoind.plist"
	[ -f "$unit" ]
	grep -A1 'UserName' "$unit" | grep -q 'bitcoin'
	grep -q 'launchctl bootstrap system' "$FEAT034_CALLS"
}

@test "FEAT-268 — enable --network regtest installs a parallel suffixed unit (linux)" {
	feat034_env linux
	"$BITCOIN_BIN" daemon enable --user --network regtest
	local unit="$XDG_CONFIG_HOME/systemd/user/bitcoind-regtest.service"
	[ -f "$unit" ]
	grep -q -- '-chain=regtest' "$unit"
	grep -q 'bitcoind-regtest.pid' "$unit"
	grep -q 'systemctl --user enable --now bitcoind-regtest' "$FEAT034_CALLS"
}

@test "FEAT-268 — enable --network regtest uses a suffixed label + -chain (macos)" {
	feat034_env macos
	"$BITCOIN_BIN" daemon enable --user --network regtest
	local unit="$HOME/Library/LaunchAgents/org.bitcoin.bitcoind-regtest.plist"
	[ -f "$unit" ]
	grep -q '<string>org.bitcoin.bitcoind-regtest</string>' "$unit"
	grep -q -- '<string>-chain=regtest</string>' "$unit"
	grep -q 'bitcoind-regtest.log' "$unit"
}

@test "FEAT-268 — mainnet unit carries no -chain and the bare label (macos)" {
	feat034_env macos
	"$BITCOIN_BIN" daemon enable --user
	local unit="$HOME/Library/LaunchAgents/org.bitcoin.bitcoind.plist"
	[ -f "$unit" ]
	! grep -q -- '-chain=' "$unit"
	# no empty ProgramArguments string left behind by the stripped @CHAIN@
	! grep -q '<string></string>' "$unit"
	grep -q '<string>org.bitcoin.bitcoind</string>' "$unit"
}

@test "FEAT-268 — enable rejects an unknown network" {
	feat034_env linux
	run --separate-stderr "$BITCOIN_BIN" daemon enable --user --network frobnet
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "unknown network 'frobnet'"
}

@test "FEAT-268 — regtest and mainnet user units coexist" {
	feat034_env linux
	"$BITCOIN_BIN" daemon enable --user
	"$BITCOIN_BIN" daemon enable --user --network regtest
	[ -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
	[ -f "$XDG_CONFIG_HOME/systemd/user/bitcoind-regtest.service" ]
}

@test "BUG-030 — enable (system) installs bitcoin.conf via sudo, not a bare redirect" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	# The datadir is owned by the dedicated 'bitcoin' account, so a bare
	# `cat > "$conf"` would run as the invoking user and fail with EACCES
	# while still printing "created". The write must route through sudo,
	# at 0640 owned by the service group.
	local conf="$BITCOIN_DAEMON_ROOT/etc/bitcoin/bitcoin.conf"
	grep -Eq 'sudo install -m 0640 .*bitcoin\.conf' "$FEAT034_CALLS"
	grep -q 'chown bitcoin:bitcoin .*bitcoin\.conf' "$FEAT034_CALLS"
	[ -f "$conf" ]
	grep -q '^server=1' "$conf"
}

@test "FEAT-274 — enable (system) sets rpccookieperms=group when bitcoind supports it" {
	feat034_env linux
	# bitcoind stub that advertises -rpccookieperms in -help (Core 28+).
	printf '#!/usr/bin/env bash\n[ "$1" = -help ] && echo "  -rpccookieperms=<readable-by>"\nexit 0\n' > "$BITCOIN_BITCOIND"
	chmod +x "$BITCOIN_BITCOIND"
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	# Makes the .cookie group-readable so sibling daemons authenticate.
	grep -q '^rpccookieperms=group' "$BITCOIN_DAEMON_ROOT/etc/bitcoin/bitcoin.conf"
}

@test "FEAT-274 — enable omits rpccookieperms on a node that predates it" {
	feat034_env linux
	# default stub emits no -help output → option unsupported → not written.
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	! grep -q 'rpccookieperms' "$BITCOIN_DAEMON_ROOT/etc/bitcoin/bitcoin.conf"
}

@test "BUG-030 — enable (system) provisions a dedicated group and joins the operator" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	# Three-user model: a same-named group is created (--user-group), the
	# datadir is group-owned and 0750, and the operator joins the group so
	# they reach config/cookie/log without sudo.
	grep -q 'useradd .*--user-group .*bitcoin' "$FEAT034_CALLS"
	grep -q 'usermod -a -G bitcoin' "$FEAT034_CALLS"
	grep -q 'chown bitcoin:bitcoin .*var/lib/bitcoin' "$FEAT034_CALLS"
}

@test "BUG-030 — enable (system) refuses to install a unit the service account can't run" {
	feat034_env linux
	# Simulate the Homebrew-keg/dyld crash-loop: a binary that execs but
	# fails (here, fails its --version preflight).
	printf '#!/usr/bin/env bash\nexit 1\n' > "$BITCOIN_BITCOIND"
	chmod +x "$BITCOIN_BITCOIND"
	run --separate-stderr "$BITCOIN_BIN" daemon enable --system
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "cannot run"
	# Must bail BEFORE installing the unit (no silent crash-loop left behind).
	[ ! -f "$BITCOIN_DAEMON_ROOT/etc/systemd/system/bitcoind.service" ]
}

@test "FEAT-261 — enable defaults to --system when no mode is given" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable
	[ "$status" -eq 0 ]
	# FEAT-261 flipped the default from --user to --system: a bare enable
	# now installs the privileged system unit under a dedicated account
	# and must NOT touch the per-user bus.
	[ -f "$BITCOIN_DAEMON_ROOT/etc/systemd/system/bitcoind.service" ]
	[ ! -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
	grep -q '^User=bitcoin' "$BITCOIN_DAEMON_ROOT/etc/systemd/system/bitcoind.service"
	grep -q 'useradd .* bitcoin' "$FEAT034_CALLS"
	grep -q 'systemctl enable --now bitcoind' "$FEAT034_CALLS"
	! grep -q 'systemctl --user' "$FEAT034_CALLS"
}

@test "FEAT-261 — daemon enable help names --system as the default" {
	run "$BITCOIN_BIN" daemon enable --help
	[ "$status" -eq 0 ]
	# help:enable writes to stderr; bats `run` folds it into $output.
	echo "$output" | grep -q -- '--system (default)'
}

@test "FEAT-034 — enable is idempotent (second call succeeds, unit refreshed)" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	[ -f "$XDG_CONFIG_HOME/systemd/user/bitcoind.service" ]
}

@test "FEAT-034 — enable errors clearly when bitcoind is absent" {
	feat034_env linux
	unset BITCOIN_BITCOIND
	# BUG-035: daemon:_bitcoind_candidates also probes the absolute
	# MacPorts / Homebrew dirs, which exist on a host running the live
	# stack. Empty the $BITCOIN_SYSTEM_BINDIRS seam (and keep
	# BITCOIN_BITCOIND unset) so the absolute-dir probe finds nothing,
	# and pin PATH to the stub dir + the system bindirs (no bitcoind on
	# any of them) so the PATH probe finds nothing either → the
	# absent-error path runs.
	export BITCOIN_SYSTEM_BINDIRS=""
	export PATH="$HOME/daemon-stub:/usr/bin:/bin:/usr/sbin:/sbin"
	run --separate-stderr "$BITCOIN_BIN" daemon enable --user
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "no 'bitcoind' found"
	echo "$stderr" | grep -q 'bitcoin daemon install'
}

@test "BUG-035 — daemon honors the \$BITCOIN_SYSTEM_BINDIRS override" {
	feat034_env linux
	unset BITCOIN_BITCOIND
	# Point the seam at a temp dir holding our own runnable bitcoind, and
	# scrub PATH so the host's real binaries can't leak in. enable must
	# discover the seam binary and wire it into the rendered unit.
	local bindir="$HOME/seam-bin"
	mkdir -p "$bindir"
	printf '#!/usr/bin/env bash\n:\n' > "$bindir/bitcoind"
	chmod +x "$bindir/bitcoind"
	export BITCOIN_SYSTEM_BINDIRS="$bindir"
	export PATH="$HOME/daemon-stub:/usr/bin:/bin:/usr/sbin:/sbin"
	run "$BITCOIN_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	grep -q "ExecStart=$bindir/bitcoind " \
		"$XDG_CONFIG_HOME/systemd/user/bitcoind.service"
}

@test "FEAT-034 — disable --user removes the unit and tears the service down" {
	feat034_env linux
	"$BITCOIN_BIN" daemon enable --user
	local unit="$XDG_CONFIG_HOME/systemd/user/bitcoind.service"
	[ -f "$unit" ]
	run "$BITCOIN_BIN" daemon disable --user
	[ "$status" -eq 0 ]
	[ ! -e "$unit" ]
	grep -q 'systemctl --user disable --now bitcoind' "$FEAT034_CALLS"
}

@test "FEAT-034 — disable preserves the data directory" {
	feat034_env linux
	"$BITCOIN_BIN" daemon enable --user
	# BUG-027: assert on the datadir `enable` actually creates
	# (daemon:_datadir → $HOME/.bitcoin since 0d2d7d1), not the XDG
	# wallet store setup() pre-creates — otherwise the test is vacuous.
	local datadir="$HOME/.bitcoin"
	[ -d "$datadir" ]
	"$BITCOIN_BIN" daemon disable --user
	[ -d "$datadir" ]
}

@test "FEAT-034 — daemon help lists enable and disable" {
	run bash -c "'$BITCOIN_BIN' daemon help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE "(^|[[:space:]])enable([[:space:]]|$)"
	echo "$output" | grep -qE "(^|[[:space:]])disable([[:space:]]|$)"
}

@test "FEAT-033 — install --from brew runs 'brew install bitcoin'" {
	feat033_env
	run "$BITCOIN_BIN" daemon install --from brew
	[ "$status" -eq 0 ]
	grep -q 'brew install bitcoin' "$FEAT033_CALLS"
}

@test "FEAT-033 — install --from apt installs bitcoind via apt-get" {
	feat033_env
	run "$BITCOIN_BIN" daemon install --from apt
	[ "$status" -eq 0 ]
	grep -q 'apt-get install -y bitcoind' "$FEAT033_CALLS"
}

@test "FEAT-033 — install --from apk adds the bitcoin package" {
	feat033_env
	run "$BITCOIN_BIN" daemon install --from apk
	[ "$status" -eq 0 ]
	grep -q 'apk add bitcoin' "$FEAT033_CALLS"
}

@test "FEAT-033 — install auto-detects apt on ubuntu" {
	feat033_env
	ACCT_PLATFORM=ubuntu run "$BITCOIN_BIN" daemon install
	[ "$status" -eq 0 ]
	grep -q 'apt-get install -y bitcoind' "$FEAT033_CALLS"
}

@test "FEAT-033 — install auto-detects apk on alpine" {
	feat033_env
	ACCT_PLATFORM=alpine run "$BITCOIN_BIN" daemon install
	[ "$status" -eq 0 ]
	grep -q 'apk add bitcoin' "$FEAT033_CALLS"
}

@test "FEAT-033 — install auto-detects macports on macos (macports-first)" {
	feat033_env
	ACCT_PLATFORM=macos run "$BITCOIN_BIN" daemon install
	[ "$status" -eq 0 ]
	# macports-first: /opt/local is world-readable, so a dedicated
	# service account can run the binary (brew is the fallback).
	grep -q 'port install bitcoin' "$FEAT033_CALLS"
}

@test "FEAT-033 — install errors when the package manager is absent" {
	feat033_env
	rm -f "$HOME/install-stub/brew"
	run --separate-stderr "$BITCOIN_BIN" daemon install --from brew
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "required tool 'brew' not found"
}

@test "FEAT-033 — install --from rpk errors with a pointer to the rpk doc" {
	feat033_env
	run --separate-stderr "$BITCOIN_BIN" daemon install --from rpk
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q 'not yet available'
	echo "$stderr" | grep -q 'docs/rpk-bitcoind.md'
}

@test "FEAT-033 — install rejects an unknown source" {
	feat033_env
	run --separate-stderr "$BITCOIN_BIN" daemon install --from frobnicate
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "unknown source 'frobnicate'"
	echo "$stderr" | grep -q 'brew, macports, apt, apk, source, rpk'
}

@test "FEAT-033 — install prints the installed bitcoind --version" {
	feat033_env
	run "$BITCOIN_BIN" daemon install --from apt
	[ "$status" -eq 0 ]
	echo "$output" | grep -q 'Bitcoin Core version v27.0.0'
}

@test "FEAT-033 — daemon help lists install" {
	run bash -c "'$BITCOIN_BIN' daemon help 2>&1"
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE "(^|[[:space:]])install([[:space:]]|$)"
}

@test "BUG-015 — start --user drives systemctl --user (linux)" {
	bug015_env
	# FEAT-261: --user is now explicit (the bare default is --system).
	BITCOIN_DAEMON_OS=linux run "$BITCOIN_BIN" daemon start --user
	[ "$status" -eq 0 ]
	grep -q 'systemctl --user start bitcoind' "$BUG015_CALLS"
}

@test "FEAT-261 — start defaults to --system (linux)" {
	bug015_env
	BITCOIN_DAEMON_OS=linux run "$BITCOIN_BIN" daemon start
	[ "$status" -eq 0 ]
	grep -q 'systemctl start bitcoind' "$BUG015_CALLS"
	! grep -q 'systemctl --user' "$BUG015_CALLS"
}

@test "BUG-015 — start --system drives system systemctl (linux)" {
	bug015_env
	BITCOIN_DAEMON_OS=linux run "$BITCOIN_BIN" daemon start --system
	[ "$status" -eq 0 ]
	grep -q 'systemctl start bitcoind' "$BUG015_CALLS"
	! grep -q 'systemctl --user' "$BUG015_CALLS"
}

@test "BUG-015 — stop --user drives systemctl --user (linux)" {
	bug015_env
	BITCOIN_DAEMON_OS=linux run "$BITCOIN_BIN" daemon stop --user
	[ "$status" -eq 0 ]
	grep -q 'systemctl --user stop bitcoind' "$BUG015_CALLS"
}

@test "BUG-015 — start --user kickstarts the LaunchAgent (macos)" {
	bug015_env
	BITCOIN_DAEMON_OS=macos run "$BITCOIN_BIN" daemon start --user
	[ "$status" -eq 0 ]
	# BUG-019 fix #4: plain `launchctl kickstart` (the -k force-kill
	# raced with KeepAlive and caused the crash loop).
	grep -q 'launchctl kickstart gui/.*/org.bitcoin.bitcoind' "$BUG015_CALLS"
}

@test "BUG-015 — stop --user signals the LaunchAgent (macos)" {
	bug015_env
	BITCOIN_DAEMON_OS=macos run "$BITCOIN_BIN" daemon stop --user
	[ "$status" -eq 0 ]
	grep -q 'launchctl kill SIGTERM gui/.*/org.bitcoin.bitcoind' "$BUG015_CALLS"
}

@test "BUG-015 — monitor follows the journal (linux)" {
	bug015_env
	BITCOIN_DAEMON_OS=linux run "$BITCOIN_BIN" daemon monitor --user
	[ "$status" -eq 0 ]
	grep -q 'journalctl --user -u bitcoind -f' "$BUG015_CALLS"
}

@test "BUG-030 — monitor (system, macos) reads the log directly via group access (no sudo)" {
	bug015_env
	BITCOIN_DAEMON_OS=macos run "$BITCOIN_BIN" daemon monitor --system
	[ "$status" -eq 0 ]
	# Three-user model: the operator is in the service group and the datadir
	# is group-readable, so the log is tailed directly — no sudo.
	grep -Eq 'tail -f .*bitcoind\.log' "$BUG015_CALLS"
	! grep -q 'sudo' "$BUG015_CALLS"
}

@test "BUG-015 — space errors when the data dir is absent" {
	bug015_env
	# setup() gives a fresh $HOME with no ~/.bitcoin, so the user-mode
	# datadir (daemon:_datadir → $HOME/.bitcoin since 0d2d7d1) is absent
	# and the error path is hit.
	run --separate-stderr "$BITCOIN_BIN" daemon space --user
	[ "$status" -ne 0 ]
	echo "$stderr" | grep -q "data dir '.*' does not exist"
}

@test "BUG-015 — space reports the data dir's disk usage" {
	bug015_env
	# BUG-035: pin the OS to linux so daemon:_datadir resolves to the
	# $HOME/.bitcoin path this test populates (on a macOS host the user-mode
	# datadir would otherwise be "$HOME/Library/Application Support/Bitcoin",
	# leaving the created dir unseen and `space` hitting the absent-error).
	export BITCOIN_DAEMON_OS=linux
	mkdir -p "$HOME/.bitcoin"
	head -c 4096 /dev/zero > "$HOME/.bitcoin/blk"
	run "$BITCOIN_BIN" daemon space --user
	[ "$status" -eq 0 ]
	echo "$output" | grep -qE '^[0-9.]+[KMG]?'
}
