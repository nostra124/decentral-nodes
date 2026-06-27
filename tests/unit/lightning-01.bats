#!/usr/bin/env bats
#
# lightning unit tests — part 1 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


# ---------------------------------------------------------------------------
# Smoke + semver contract (FEAT-005)
# ---------------------------------------------------------------------------

@test "lightning binary exists and is executable" {
	[ -x "$LIGHTNING_BIN" ]
}

@test "lightning version matches the root VERSION file" {
	# Read VERSION at test time (mirrors bitcoin.bats / FEAT-020) so a
	# release bump doesn't require editing this literal.
	run "$LIGHTNING_BIN" version
	[ "$status" -eq 0 ]
	[ "$output" = "$(cat "$BATS_TEST_DIRNAME/../../VERSION")" ]
}

@test "FEAT-307: top-level 'lightning install' routes to the daemon installer (canonical)" {
	# Harmonized: install is a top-level verb on every command; the old
	# 'lightning daemon install' keeps working as an alias.
	run "$LIGHTNING_BIN" install --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"install"* ]]
	run "$LIGHTNING_BIN" daemon install --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"install"* ]]
}

@test "lightning version comes from the root VERSION file" {
	local vf="$BATS_TEST_DIRNAME/../../VERSION"
	[ -f "$vf" ]
	run "$LIGHTNING_BIN" version
	[ "$output" = "$(tr -d '[:space:]' < "$vf")" ]
}

@test "lightning help prints usage" {
	run "$LIGHTNING_BIN" help
	[ -n "$output" ]
}

@test "lightning with no args prints help" {
	run "$LIGHTNING_BIN"
	[ -n "$output" ]
}

@test "lightning unknown subcommand exits non-zero (BUG-005 regression)" {
	run "$LIGHTNING_BIN" definitely-not-a-real-subcommand
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Help surface — every spec hook documented today should be discoverable
# ---------------------------------------------------------------------------

@test "help mentions BOLT specs" {
	run "$LIGHTNING_BIN" help
	[[ "$output" == *"BOLT"* ]]
}

@test "help mentions clightning (Core Lightning)" {
	run "$LIGHTNING_BIN" help
	[[ "$output" == *"clightning"* || "$output" == *"Core Lightning"* ]]
}

@test "help mentions LNURL / Lightning Address vendored standards" {
	run "$LIGHTNING_BIN" help
	[[ "$output" == *"LNURL"* || "$output" == *"Lightning Address"* ]]
}

@test "help lists the 1.0.0 verb surface" {
	run "$LIGHTNING_BIN" help
	[[ "$output" == *"wallet"* ]]
	[[ "$output" == *"account"* ]]
	[[ "$output" == *"channel"* ]]
	[[ "$output" == *"daemon"* ]]
	[[ "$output" == *"node"* ]]
	[[ "$output" == *"pay"* ]]
	[[ "$output" == *"req"* ]]
	[[ "$output" == *"address"* ]]
}

@test "help lists the one-shot verbs" {
	run "$LIGHTNING_BIN" help
	[[ "$output" == *"wallet"* ]]
	[[ "$output" == *"account"* ]]
	[[ "$output" == *"address"* ]]
	[[ "$output" == *"node"* ]]
	[[ "$output" == *"channel"* ]]
	[[ "$output" == *"peer"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-170: source-mode guard
# ---------------------------------------------------------------------------

@test "FEAT-170: sourcing the dispatcher defines functions without dispatch" {
	local sh="$LIGHTNING_BIN"
	# Source in a subshell; should NOT print help (the dispatcher must
	# return early) but should define `command:version`.
	run bash -c ". '$sh'; type -t command:version"
	[ "$status" -eq 0 ]
	[ "$output" = "function" ]
}

@test "FEAT-170: no script-invocation matches for sister packages in bin/lightning-node" {
	# Acceptance criterion 4: bin/lightning-node must not shell out to
	# other packages (cache / check / data / hosts / repo / scripts /
	# task / user). Allow the word as part of help text / comments
	# only; reject as the first token after whitespace or as `$(`.
	run grep -wEn '^[[:space:]]*(cache|check|data|hosts|repo|scripts|task|user)[[:space:]]|\$\((cache|check|data|hosts|repo|scripts|task|user)[[:space:]]' "$LIGHTNING_BIN"
	[ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# FEAT-171: clightning backend wiring
# ---------------------------------------------------------------------------

@test "FEAT-171: lightning wallet info renders getinfo summary" {
	run "$LIGHTNING_BIN" wallet info
	[ "$status" -eq 0 ]
	[[ "$output" == *"TESTNODE"* ]]
	[[ "$output" == *"regtest"* ]]
}

@test "FEAT-171: lightning wallet id returns the pubkey" {
	run "$LIGHTNING_BIN" wallet id
	[ "$status" -eq 0 ]
	[ "$output" = "020000000000000000000000000000000000000000000000000000000000000001" ]
}

@test "FEAT-171: wallet peers is deprecated -> hints at 'peer list'" {
	run "$LIGHTNING_BIN" wallet peers
	[ "$status" -ne 0 ]
	[[ "$output" == *"peer list"* ]]
}

@test "FEAT-171: lightning peer list returns the TSV header" {
	run "$LIGHTNING_BIN" peer list
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "pubkey	connected	features	addr" ]]
}

@test "FEAT-171: lightning channel list returns the TSV header" {
	run "$LIGHTNING_BIN" channel list
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "id	peer	capacity	local	remote	state" ]]
}

@test "FEAT-171: lightning wallet balance is a recfile (single record)" {
	run "$LIGHTNING_BIN" wallet balance
	[ "$status" -eq 0 ]
	# Three key: value lines, no TSV header.
	[ "${#lines[@]}" -eq 3 ]
	[[ "${lines[0]}" == "onchain_confirmed_sat:"* ]]
	[[ "${lines[1]}" == "onchain_unconfirmed_sat:"* ]]
	[[ "${lines[2]}" == "channels_sat:"* ]]
	# Each line ends in the expected zero value (mocked listfunds).
	[[ "${lines[0]}" == *"0" ]]
	[[ "${lines[1]}" == *"0" ]]
	[[ "${lines[2]}" == *"0" ]]
}

@test "FEAT-171: lightning wallet balance --on-chain prints an address" {
	run "$LIGHTNING_BIN" wallet balance --on-chain
	[ "$status" -eq 0 ]
	[[ "$output" == bcrt1q* ]]
}

@test "FEAT-171: verbs exit 127 when lightning-cli is absent" {
	# Hide lightning-cli from PATH.
	export PATH="/usr/bin:/bin"
	run -127 "$LIGHTNING_BIN" wallet info
	[[ "$output" == *"install Core Lightning"* ]]
}

@test "lightning wallet (no args) prints usage" {
	run "$LIGHTNING_BIN" wallet
	[ "$status" -ne 0 ]
	[[ "$output" == *"subcommands"* || "$output" == *"node"* ]]
}

# ---------------------------------------------------------------------------
# FEAT-183: daemon lifecycle
# ---------------------------------------------------------------------------

@test "FEAT-183: lightning daemon (no args) prints usage" {
	run "$LIGHTNING_BIN" daemon
	[ "$status" -ne 0 ]
	[[ "$output" == *"usage"* ]]
}

@test "FEAT-183: lightning daemon status reports 'healthy' when RPC is up" {
	run "$LIGHTNING_BIN" daemon status
	[ "$status" -eq 0 ]
	[[ "$output" == *"healthy"* ]]
}

@test "FEAT-183: lightning daemon status reports 'down' when RPC is down" {
	echo "down" > "$MOCK_STATE"
	run "$LIGHTNING_BIN" daemon status
	[ "$status" -eq 2 ]
	[[ "$output" == *"down"* ]]
}

@test "FEAT-183: lightning daemon enable writes a user-mode systemd unit (Linux)" {
	if [ "$(uname -s)" = "Darwin" ]; then
		skip "Linux-only — macOS uses launchd"
	fi
	# Stub lightningd so enable's ExecStart resolves.
	ln -sf /bin/true "$BIN_SHIM/lightningd"
	# FEAT-264: --user is now explicit (bare enable defaults to --system).
	run "$LIGHTNING_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	[ -f "$HOME/.config/systemd/user/lightning.service" ]
	grep -q "Description=Lightning Network daemon" "$HOME/.config/systemd/user/lightning.service"
}

@test "FEAT-264: lightning daemon enable defaults to --system" {
	# Bare enable now resolves to system mode. Prove it without root via the
	# system-only migrate guard: with a user-mode ~/.lightning present the
	# system installer refuses (exit 3). install_user has no such guard, so
	# this would have written a user unit and exited 0 under the old default.
	# Cross-platform: install_system (Linux) and install_macos_system share
	# the guard, and it fires before any sudo/privileged step.
	ln -sf /bin/true "$BIN_SHIM/lightningd"
	mkdir -p "$HOME/.lightning"
	run "$LIGHTNING_BIN" daemon enable
	[ "$status" -eq 3 ]
	# The refusal is error-level (both lines — the detection and the
	# "pass --migrate" hint — so they survive the fixture's SELF_QUIET=1;
	# FEAT-207 asserts the --migrate hint stays visible). "user-mode
	# install detected" is printed only by the system installers, never
	# install_user.
	[[ "$output" == *"user-mode install detected"* ]]
	[[ "$output" == *"refusing"* ]]
}

# FEAT-269 — the main lightningd service is network-aware: regtest /
# testnet / signet run as PARALLEL units alongside mainnet. mainnet
# (CLN calls it 'bitcoin') keeps the BARE unit names for backward
# compatibility; other networks get a -<net> suffix. The naming logic
# lives in lightning:_apply_network, exercised here through the macOS
# user-mode LaunchAgent (no root needed) plus the reject path.

@test "FEAT-269: enable --network regtest installs a suffixed LaunchAgent (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then
		skip "macOS-only — exercises the per-network launchd label"
	fi
	ln -sf /bin/true "$BIN_SHIM/lightningd"
	run "$LIGHTNING_BIN" daemon enable --user --network regtest
	[ "$status" -eq 0 ]
	local plist="$HOME/Library/LaunchAgents/network.lightning.lightningd-regtest.plist"
	[ -f "$plist" ]
	grep -q "<string>network.lightning.lightningd-regtest</string>" "$plist"
	# The ExecStart env carries the resolved network so lightningd runs
	# on the right chain (its own data subdir + ports).
	grep -A1 "<key>LIGHTNING_NETWORK</key>" "$plist" | grep -q "<string>regtest</string>"
}

@test "FEAT-269: mainnet enable keeps the bare LaunchAgent label (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then
		skip "macOS-only — exercises the bare-name backward-compat path"
	fi
	ln -sf /bin/true "$BIN_SHIM/lightningd"
	run "$LIGHTNING_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	# Bare plist, no -<net> suffix anywhere.
	local plist="$HOME/Library/LaunchAgents/network.lightning.lightningd.plist"
	[ -f "$plist" ]
	[ ! -f "$HOME/Library/LaunchAgents/network.lightning.lightningd-bitcoin.plist" ]
	grep -q "<string>network.lightning.lightningd</string>" "$plist"
	! grep -q "lightningd-" "$plist"
}

@test "FEAT-269: regtest and mainnet user units coexist (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then
		skip "macOS-only — exercises parallel LaunchAgents"
	fi
	ln -sf /bin/true "$BIN_SHIM/lightningd"
	"$LIGHTNING_BIN" daemon enable --user >/dev/null 2>&1
	"$LIGHTNING_BIN" daemon enable --user --network regtest >/dev/null 2>&1
	[ -f "$HOME/Library/LaunchAgents/network.lightning.lightningd.plist" ]
	[ -f "$HOME/Library/LaunchAgents/network.lightning.lightningd-regtest.plist" ]
}

@test "FEAT-269: enable rejects an unknown network before any write" {
	ln -sf /bin/true "$BIN_SHIM/lightningd"
	run --separate-stderr "$LIGHTNING_BIN" daemon enable --user --network frobnet
	[ "$status" -ne 0 ]
	echo "$stderr$output" | grep -q "unknown network 'frobnet'"
	# Aborted before touching the init system — no plist written.
	[ ! -f "$HOME/Library/LaunchAgents/network.lightning.lightningd-frobnet.plist" ]
}

@test "FEAT-269: start rejects an unknown network" {
	echo "down" > "$MOCK_STATE"
	run --separate-stderr "$LIGHTNING_BIN" daemon start --network frobnet
	[ "$status" -ne 0 ]
	echo "$stderr$output" | grep -q "unknown network 'frobnet'"
}

@test "FEAT-269: --network=regtest equals-form parses (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then
		skip "macOS-only — exercises the per-network launchd label"
	fi
	ln -sf /bin/true "$BIN_SHIM/lightningd"
	run "$LIGHTNING_BIN" daemon enable --user --network=regtest
	[ "$status" -eq 0 ]
	[ -f "$HOME/Library/LaunchAgents/network.lightning.lightningd-regtest.plist" ]
}

@test "FEAT-269: main/mainnet aliases normalize to the bare CLN 'bitcoin' label (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then
		skip "macOS-only — exercises mainnet alias normalization"
	fi
	ln -sf /bin/true "$BIN_SHIM/lightningd"
	run "$LIGHTNING_BIN" daemon enable --user --network mainnet
	[ "$status" -eq 0 ]
	[ -f "$HOME/Library/LaunchAgents/network.lightning.lightningd.plist" ]
	[ ! -f "$HOME/Library/LaunchAgents/network.lightning.lightningd-mainnet.plist" ]
}

@test "FEAT-183: lightning daemon enable writes a LaunchAgent plist (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then
		skip "macOS-only — Linux uses systemd"
	fi
	ln -sf /bin/true "$BIN_SHIM/lightningd"
	run "$LIGHTNING_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	local plist="$HOME/Library/LaunchAgents/network.lightning.lightningd.plist"
	[ -f "$plist" ]
	grep -q "<string>network.lightning.lightningd</string>" "$plist"
	grep -q "<string>daemon</string>" "$plist"
	grep -q "<string>run</string>" "$plist"
	grep -q "<key>RunAtLoad</key>" "$plist"
	grep -q "<key>KeepAlive</key>" "$plist"
}

@test "FEAT-183: lightning daemon run requires lightningd binary" {
	# Daemon NOT running, lightningd binary NOT present → exit 127.
	echo "down" > "$MOCK_STATE"
	export PATH="$BIN_SHIM:/usr/bin:/bin"
	run "$LIGHTNING_BIN" daemon run
	[ "$status" -eq 127 ]
	[[ "$output" == *"lightningd not found"* ]]
}

@test "FEAT-183: lightning daemon run refuses when daemon is already running" {
	# Mock lightning-cli getinfo returns success (state = up) by default.
	run "$LIGHTNING_BIN" daemon run
	[ "$status" -eq 1 ]
	[[ "$output" == *"already running"* ]]
}

@test "FEAT-183: lightning daemon help lists run alongside start" {
	run "$LIGHTNING_BIN" daemon
	[[ "$output" == *"run"* ]]
	[[ "$output" == *"start"* ]]
	[[ "$output" == *"foreground"* ]]
}

@test "FEAT-183: daemon start routes through installed LaunchAgent (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then
		skip "macOS-only — exercises launchctl detection"
	fi
	# Daemon must be down so start doesn't short-circuit.
	echo "down" > "$MOCK_STATE"
	# Pretend the plist is installed (file presence is what detection checks).
	mkdir -p "$HOME/Library/LaunchAgents"
	touch "$HOME/Library/LaunchAgents/network.lightning.lightningd.plist"
	# Stub launchctl so we can prove start invoked it (not lightningd directly).
	cat > "$BIN_SHIM/launchctl" <<EOF
#!/bin/sh
[ "\$1" = "list" ] && exit 1   # report "not loaded"
# load/kickstart succeeds — flip MOCK_STATE so the post-start
# probe sees a healthy daemon.
rm -f "$MOCK_STATE"
exit 0
EOF
	chmod +x "$BIN_SHIM/launchctl"
	# Stub lightningd as a real script (ln -sf /bin/true would be a
	# dangling symlink on macOS where /bin/true doesn't exist).
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	run "$LIGHTNING_BIN" -v daemon start
	[ "$status" -eq 0 ]
	[[ "$output" == *"launchctl load -w"* ]]
	# Must NOT have fallen through to the direct path.
	[[ "$output" != *"no service unit installed"* ]]
}

@test "FEAT-183: daemon start routes through systemd --user when unit installed (Linux)" {
	if [ "$(uname -s)" = "Darwin" ]; then
		skip "Linux-only — exercises systemctl --user detection"
	fi
	echo "down" > "$MOCK_STATE"
	mkdir -p "$HOME/.config/systemd/user"
	touch "$HOME/.config/systemd/user/lightning.service"
	# Stub systemctl so the routing is observable without a real systemd.
	cat > "$BIN_SHIM/systemctl" <<EOF
#!/bin/sh
[ "\$1" = "--quiet" ] && exit 1   # report system-mode NOT enabled
# start command succeeds — flip MOCK_STATE so post-start probe passes.
rm -f "$MOCK_STATE"
exit 0
EOF
	chmod +x "$BIN_SHIM/systemctl"
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	run "$LIGHTNING_BIN" -v daemon start
	[ "$status" -eq 0 ]
	[[ "$output" == *"systemctl --user start lightning"* ]]
}

@test "FEAT-183: daemon status down surfaces last BROKEN line from log" {
	echo "down" > "$MOCK_STATE"
	mkdir -p "$HOME/.lightning"
	cat > "$HOME/.lightning/log" <<'EOF'
2026-05-18T21:00:00.000Z INFO lightningd: v26.04.1
2026-05-18T21:00:01.000Z **BROKEN** plugin-bcli: The Bitcoin backend died.
2026-05-18T21:00:01.500Z INFO lightningd: shutting down
EOF
	run "$LIGHTNING_BIN" daemon status
	[ "$status" -eq 2 ]
	[[ "$output" == *"down"* ]]
	[[ "$output" == *"BROKEN"* ]]
	[[ "$output" == *"Bitcoin backend died"* ]]
	[[ "$output" == *"daemon monitor"* ]]
}

@test "FEAT-183: daemon start warns when bitcoin-cli is missing" {
	echo "down" > "$MOCK_STATE"
	# bitcoin-cli absent (the BIN_SHIM doesn't define it).
	# Stub lightningd so the lightningd-not-found branch doesn't fire first.
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	export PATH="$BIN_SHIM:/usr/bin:/bin"
	# Daemon stays "down" after start → expect non-zero, but the
	# warning should appear in output regardless.
	run "$LIGHTNING_BIN" -v daemon start
	[[ "$output" == *"bitcoin-cli not found"* ]]
}

@test "FEAT-183: daemon start surfaces the error when daemon dies during startup" {
	echo "down" > "$MOCK_STATE"
	mkdir -p "$HOME/.lightning"
	# Pre-seed a log with a fatal line — simulates the daemon
	# crashing during startup.
	cat > "$HOME/.lightning/log" <<'EOF'
2026-05-18T22:00:00.000Z **BROKEN** plugin-bcli: The Bitcoin backend died.
EOF
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	# BUG-037 — scrub PATH (as the sibling bitcoin-cli test does) so a real
	# `secret` on the host's PATH can't trigger cmd_start's auto-unlock hook,
	# which would `wallet unlock --stored` (a no-op success) and return 0
	# BEFORE the post-start probe runs. On CI `secret` is absent, so the hook
	# is skipped and the probe fires; pin the same condition here.
	export PATH="$BIN_SHIM:/usr/bin:/bin"
	run "$LIGHTNING_BIN" -v daemon start
	# Exit 2 = post-start probe found the daemon down.
	[ "$status" -eq 2 ]
	[[ "$output" == *"did not come up"* ]]
	[[ "$output" == *"BROKEN"* ]]
}

@test "FEAT-183: daemon enable plist sets ThrottleInterval (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then
		skip "macOS-only — checks the launchd plist"
	fi
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	run "$LIGHTNING_BIN" daemon enable --user
	[ "$status" -eq 0 ]
	local plist="$HOME/Library/LaunchAgents/network.lightning.lightningd.plist"
	grep -q "<key>ThrottleInterval</key>" "$plist"
	grep -q "<integer>30</integer>" "$plist"
}

@test "FEAT-183: daemon enable --trustedcoin writes managed block + auto-installs plugin" {
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	_stub_trustedcoin_curl
	run "$LIGHTNING_BIN" daemon enable --user --trustedcoin
	[ "$status" -eq 0 ]
	[ -f "$HOME/.lightning/config" ]
	grep -q "disable-plugin=bcli" "$HOME/.lightning/config"
	grep -q "lightning backend" "$HOME/.lightning/config"
	grep -q "trustedcoin" "$HOME/.lightning/config"
	# The plugin binary should have landed in plugins/ and be executable.
	[ -x "$HOME/.lightning/plugins/trustedcoin" ]
}

@test "FEAT-183: daemon enable --trustedcoin skips fetch if binary already present" {
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	mkdir -p "$HOME/.lightning/plugins"
	printf '#!/bin/sh\nexit 0\n' > "$HOME/.lightning/plugins/trustedcoin"
	chmod +x "$HOME/.lightning/plugins/trustedcoin"
	# Fail loudly if curl gets called.
	printf '#!/bin/sh\necho "curl should not be called" >&2; exit 99\n' > "$BIN_SHIM/curl"
	chmod +x "$BIN_SHIM/curl"
	run "$LIGHTNING_BIN" -v daemon enable --user --trustedcoin
	[ "$status" -eq 0 ]
	[[ "$output" == *"already present"* ]]
	[[ "$output" != *"fetching trustedcoin"* ]]
}

@test "FEAT-183: daemon enable --trustedcoin reports failure when curl fails (Linux)" {
	if [ "$(uname -s)" = "Darwin" ]; then
		skip "macOS uses go install, not curl"
	fi
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	printf '#!/bin/sh\nexit 22\n' > "$BIN_SHIM/curl"
	chmod +x "$BIN_SHIM/curl"
	run "$LIGHTNING_BIN" daemon enable --user --trustedcoin
	# Config is still written; download failure is surfaced.
	grep -q "disable-plugin=bcli" "$HOME/.lightning/config"
	[[ "$output" == *"failed to download"* ]]
	[[ "$output" == *"manual install"* ]]
}

@test "FEAT-183: daemon enable --trustedcoin needs go on macOS without one" {
	if [ "$(uname -s)" != "Darwin" ]; then
		skip "macOS-only — prebuilt binaries cover Linux/BSD"
	fi
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	# Hide go from PATH.
	export PATH="$BIN_SHIM:/usr/bin:/bin"
	run "$LIGHTNING_BIN" daemon enable --user --trustedcoin
	grep -q "disable-plugin=bcli" "$HOME/.lightning/config"
	[[ "$output" == *"doesn't ship a prebuilt macOS binary"* ]]
	[[ "$output" == *"go install"* ]]
}

@test "FEAT-183: daemon enable --bitcoind strips the managed block" {
	printf '#!/bin/sh\nexit 0\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	_stub_trustedcoin_curl
	# First enable trustedcoin.
	"$LIGHTNING_BIN" daemon enable --user --trustedcoin >/dev/null 2>&1
	grep -q "disable-plugin=bcli" "$HOME/.lightning/config"
	# Then disable.
	run "$LIGHTNING_BIN" daemon enable --user --bitcoind
	[ "$status" -eq 0 ]
	! grep -q "disable-plugin=bcli" "$HOME/.lightning/config"
	! grep -q "lightning backend" "$HOME/.lightning/config"
}
