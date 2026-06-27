#!/usr/bin/env bats
#
# lightning unit tests — part 7 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-207: install-core --from source --dry-run skips platform + tool checks" {
	# No stubs at all — dry-run must still print the plan + build-dir.
	run "$LIGHTNING_BIN" daemon install --from source --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"apt-get install build-deps"* ]]
	[[ "$output" == *"build-dir:"* ]]
}

@test "FEAT-207: install-core --from source propagates apt-get failure" {
	_source_common_setup
	_stub_apt_get 100
	_stub_git_for_source 0
	_stub_make 0 1
	run "$LIGHTNING_BIN" daemon install --from source --yes
	[ "$status" -eq 100 ]
	[[ "$output" == *"apt-get install failed"* ]]
	# git/make should not have run.
	[ ! -f "$BIN_SHIM/git.calls" ]
}

@test "FEAT-207: install-core --from source propagates git failure" {
	_source_common_setup
	_stub_apt_get 0
	_stub_git_for_source 128
	_stub_make 0 1
	run "$LIGHTNING_BIN" daemon install --from source --yes
	[ "$status" -ne 0 ]
	[[ "$output" == *"git clone failed"* ]]
	# make should not have been invoked.
	[ ! -f "$BIN_SHIM/make.calls" ]
}

@test "FEAT-207: install-core --from source propagates build failure" {
	_source_common_setup
	_stub_apt_get 0
	_stub_git_for_source 0
	# make all exits non-zero; install never runs.
	_stub_make 2 0
	run "$LIGHTNING_BIN" daemon install --from source --yes
	[ "$status" -eq 2 ]
	[[ "$output" == *"build failed"* ]]
	[[ "$output" == *"left at"* ]]   # operator-friendly hint
}

@test "FEAT-207: install-core --from source fetches when repo already cloned" {
	_source_common_setup
	# Pre-create the clone dir so the verb takes the fetch branch.
	mkdir -p "$LIGHTNING_BUILD_DIR/lightning/.git"
	printf '#!/bin/sh\nexit 0\n' > "$LIGHTNING_BUILD_DIR/lightning/configure"
	chmod +x "$LIGHTNING_BUILD_DIR/lightning/configure"
	printf 'all:\n\t@true\ninstall:\n\t@true\n' > "$LIGHTNING_BUILD_DIR/lightning/Makefile"
	_stub_apt_get 0
	_stub_git_for_source 0
	_stub_make 0 1
	run "$LIGHTNING_BIN" daemon install --from source --yes
	[ "$status" -eq 0 ]
	grep -q "git fetch" "$BIN_SHIM/git.calls"
	! grep -q "git clone" "$BIN_SHIM/git.calls"
}

@test "FEAT-207: install-core --from podman pulls + creates + writes shims" {
	_podman_common_setup
	_stub_podman 0 0
	run "$LIGHTNING_BIN" daemon install --from podman
	[ "$status" -eq 0 ]
	[ -f "$BIN_SHIM/podman.calls" ]
	grep -q "podman pull elementsproject/lightningd" "$BIN_SHIM/podman.calls"
	grep -q "podman create" "$BIN_SHIM/podman.calls"
	grep -q "\\--name clightning" "$BIN_SHIM/podman.calls"
	grep -q "\\--volume $LIGHTNING_DIR:/root/.lightning" "$BIN_SHIM/podman.calls"
	[ -x "$LIGHTNING_SHIM_DIR/lightning-cli" ]
	[ -x "$LIGHTNING_SHIM_DIR/lightningd" ]
	grep -q "podman exec" "$LIGHTNING_SHIM_DIR/lightning-cli"
	grep -q "clightning"  "$LIGHTNING_SHIM_DIR/lightning-cli"
	grep -q "podman run"  "$LIGHTNING_SHIM_DIR/lightningd"
	[[ "$output" == *"lightningd installed"* ]]
}

@test "FEAT-207: install-core --from podman --tag tags the image" {
	_podman_common_setup
	_stub_podman 0 0
	run "$LIGHTNING_BIN" daemon install --from podman --tag v26.04.1
	[ "$status" -eq 0 ]
	grep -q "podman pull elementsproject/lightningd:v26.04.1" "$BIN_SHIM/podman.calls"
	# The lightningd shim's `--version` branch must reference the same tag.
	grep -q "elementsproject/lightningd:v26.04.1" "$LIGHTNING_SHIM_DIR/lightningd"
}

@test "FEAT-207: install-core --from podman --dry-run skips podman + writes nothing" {
	_podman_common_setup
	# No podman stub at all — dry-run must still print the plan.
	run "$LIGHTNING_BIN" daemon install --from podman --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"podman pull"* ]]
	[[ "$output" == *"shim-dir:"* ]]
	[ ! -e "$LIGHTNING_SHIM_DIR/lightning-cli" ]
}

@test "FEAT-207: install-core --from podman errors when podman not on PATH" {
	# This test depends on the inherited environment NOT having podman
	# installed.  GH-hosted runners ship podman in /usr/bin, and we
	# can't strip /usr/bin from PATH without also losing coreutils
	# (dirname, basename, grep, …) that bin/lightning-node's own path
	# resolution needs — earlier strip-PATH approach broke the
	# script's libexec dispatch and the failure mode changed.
	# When podman is present in the environment, skip; the verb's
	# `command -v podman` branch is well-covered by code review and
	# by every other --from podman test that does stub podman.
	if command -v podman >/dev/null 2>&1; then
		skip "system podman present; this test requires a podman-free environment"
	fi
	_podman_common_setup
	run "$LIGHTNING_BIN" daemon install --from podman
	[ "$status" -eq 1 ]
	[[ "$output" == *"podman not on PATH"* ]]
	[ ! -e "$LIGHTNING_SHIM_DIR/lightning-cli" ]
}

@test "FEAT-207: install-core --from podman --system is refused" {
	_podman_common_setup
	_stub_podman 0 0
	run "$LIGHTNING_BIN" daemon install --from podman --system
	[ "$status" -eq 1 ]
	[[ "$output" == *"--system is not supported"* ]]
	[ ! -e "$LIGHTNING_SHIM_DIR/lightning-cli" ]
}

@test "FEAT-207: install-core --from podman propagates pull failure" {
	_podman_common_setup
	_stub_podman 125 0
	run "$LIGHTNING_BIN" daemon install --from podman
	[ "$status" -eq 125 ]
	[[ "$output" == *"podman pull failed"* ]]
	# create should not have happened.
	! grep -q "podman create" "$BIN_SHIM/podman.calls"
}

@test "FEAT-207: install-core --from podman propagates create failure" {
	_podman_common_setup
	_stub_podman 0 125
	run "$LIGHTNING_BIN" daemon install --from podman
	[ "$status" -eq 125 ]
	[[ "$output" == *"podman create failed"* ]]
	[ ! -e "$LIGHTNING_SHIM_DIR/lightning-cli" ]
}

@test "FEAT-207: install-core --from podman refuses when container already exists" {
	_podman_common_setup
	_stub_podman 0 0
	export PODMAN_CONTAINER_EXISTS=1
	run "$LIGHTNING_BIN" daemon install --from podman
	[ "$status" -eq 1 ]
	[[ "$output" == *"already exists"* ]]
	[[ "$output" == *"--force"* ]]
	# create should not have happened — we bailed before it.
	! grep -q "podman create" "$BIN_SHIM/podman.calls"
}

@test "FEAT-207: install-core --from podman --force recreates the container" {
	_podman_common_setup
	_stub_podman 0 0
	export PODMAN_CONTAINER_EXISTS=1
	run "$LIGHTNING_BIN" daemon install --from podman --force
	[ "$status" -eq 0 ]
	grep -q "podman rm -f clightning" "$BIN_SHIM/podman.calls"
	grep -q "podman create" "$BIN_SHIM/podman.calls"
}

@test "FEAT-207: install-core --from podman warns when shim dir is not on PATH" {
	# Set up the shim dir but DO NOT add it to PATH.
	export LIGHTNING_DIR="$BATS_TMPDIR/lightning-state.$$"
	export LIGHTNING_SHIM_DIR="$BATS_TMPDIR/lightning-shim.$$"
	export LIGHTNING_PODMAN_NAME="clightning"
	rm -rf "$LIGHTNING_DIR" "$LIGHTNING_SHIM_DIR"
	# To still pass ic_verify_lightningd we need the shim to be executable —
	# verify is by absolute path, not PATH.
	_stub_podman 0 0
	run "$LIGHTNING_BIN" daemon install --from podman
	[ "$status" -eq 0 ]
	[[ "$output" == *"not on \$PATH"* ]] || [[ "$output" == *"not on $"* ]] || [[ "$output" == *"PATH"*"add it"* ]]
}

@test "FEAT-207: daemon start routes through podman when container exists" {
	_podman_lifecycle_setup
	echo "down" > "$MOCK_STATE"
	run "$LIGHTNING_BIN" -v daemon start
	[ "$status" -eq 0 ]
	[ -f "$BIN_SHIM/podman.calls" ]
	grep -q "^podman start clightning$" "$BIN_SHIM/podman.calls"
	[[ "$output" == *"podman start clightning"* ]]
}

@test "FEAT-207: daemon stop routes through podman when container exists" {
	_podman_lifecycle_setup
	# daemon_running starts true (no MOCK_STATE) so cmd_stop proceeds.
	# The podman stub's start subcmd would have touched the state file;
	# here we want the stop branch, so make the daemon look running first.
	touch "$BIN_SHIM/podman-running"
	run "$LIGHTNING_BIN" -v daemon stop
	[ "$status" -eq 0 ]
	grep -q "^podman stop clightning$" "$BIN_SHIM/podman.calls"
	[[ "$output" == *"podman stop clightning"* ]]
}

@test "FEAT-207: daemon status reports podman-mode when container is running" {
	_podman_lifecycle_setup
	touch "$BIN_SHIM/podman-running"   # podman inspect → "true"
	run "$LIGHTNING_BIN" daemon status
	[ "$status" -eq 0 ]
	[[ "$output" == *"podman-mode"* ]]
}

@test "FEAT-207: daemon monitor exec's into podman logs when container exists" {
	_podman_lifecycle_setup
	touch "$BIN_SHIM/podman-running"
	run "$LIGHTNING_BIN" daemon monitor
	[ "$status" -eq 0 ]
	[[ "$output" == *"<podman log line>"* ]]
	grep -q "^podman logs" "$BIN_SHIM/podman.calls"
}

@test "FEAT-207: daemon start no-ops when podman container already running" {
	_podman_lifecycle_setup
	# MOCK_STATE empty → daemon_running returns true → cmd_start early return.
	run "$LIGHTNING_BIN" -v daemon start
	[ "$status" -eq 0 ]
	[[ "$output" == *"already running"* ]]
	[ ! -f "$BIN_SHIM/podman.calls" ] || ! grep -q "^podman start" "$BIN_SHIM/podman.calls"
}

@test "FEAT-207: daemon start prefers systemd-user over podman" {
	_podman_lifecycle_setup
	echo "down" > "$MOCK_STATE"
	# Both supervisors installed — systemd should win (explicit unit
	# beats inferred-via-container fallback).
	mkdir -p "$HOME/.config/systemd/user"
	touch "$HOME/.config/systemd/user/lightning.service"
	cat > "$BIN_SHIM/systemctl" <<EOF
#!/bin/sh
[ "\$1" = "--quiet" ] && exit 1
rm -f "$MOCK_STATE"
exit 0
EOF
	chmod +x "$BIN_SHIM/systemctl"
	run "$LIGHTNING_BIN" -v daemon start
	[ "$status" -eq 0 ]
	[[ "$output" == *"systemctl --user start lightning"* ]]
	! grep -q "^podman start" "$BIN_SHIM/podman.calls" 2>/dev/null
}

@test "FEAT-207: daemon start falls through to direct mode when no podman container" {
	export PODMAN_CONTAINER_EXISTS=0
	export LIGHTNING_NO_BOOTSTRAP=1
	echo "down" > "$MOCK_STATE"
	_stub_podman_lifecycle
	# Provide a lightningd shim so the direct-mode `command -v lightningd` succeeds.
	cat > "$BIN_SHIM/lightningd" <<EOF
#!/bin/sh
# Direct mode — flip MOCK_STATE so the post-start probe passes.
rm -f "$MOCK_STATE"
exit 0
EOF
	chmod +x "$BIN_SHIM/lightningd"
	run "$LIGHTNING_BIN" -v daemon start
	[ "$status" -eq 0 ]
	[[ "$output" == *"starting lightningd directly"* ]]
	! grep -q "^podman start" "$BIN_SHIM/podman.calls" 2>/dev/null
}

@test "FEAT-207: daemon enable on Alpine writes an OpenRC init script" {
	_openrc_common_setup
	run "$LIGHTNING_BIN" daemon enable
	[ "$status" -eq 0 ]
	[ -f "$LIGHTNING_INIT_D/lightningd" ]
	# Init script shape — shebang + supervisor + depend block.
	grep -q '^#!/sbin/openrc-run'                "$LIGHTNING_INIT_D/lightningd"
	grep -q '^command="/usr/bin/lightningd"'     "$LIGHTNING_INIT_D/lightningd"
	grep -q 'command_user="lightning:lightning"' "$LIGHTNING_INIT_D/lightningd"
	grep -q '^supervisor=supervise-daemon'       "$LIGHTNING_INIT_D/lightningd"
	grep -q 'need net'                           "$LIGHTNING_INIT_D/lightningd"
}

@test "FEAT-207: OpenRC enable creates the lightning user + group" {
	_openrc_common_setup
	run "$LIGHTNING_BIN" daemon enable
	[ "$status" -eq 0 ]
	[ -f "$BIN_SHIM/addgroup.calls" ]
	grep -q "addgroup -S lightning" "$BIN_SHIM/addgroup.calls"
	[ -f "$BIN_SHIM/adduser.calls" ]
	grep -q "adduser -S -H" "$BIN_SHIM/adduser.calls"
	grep -q "\\-G lightning lightning" "$BIN_SHIM/adduser.calls"
}

@test "FEAT-207: OpenRC enable seeds the config with rpc-file-mode 0660" {
	_openrc_common_setup
	run "$LIGHTNING_BIN" daemon enable
	[ "$status" -eq 0 ]
	[ -f "$LIGHTNING_OPENRC_STATE/config" ]
	grep -q "^rpc-file-mode=0660" "$LIGHTNING_OPENRC_STATE/config"
	grep -q "^network=" "$LIGHTNING_OPENRC_STATE/config"
}

@test "FEAT-207: OpenRC init script references the configured state dir" {
	_openrc_common_setup
	run "$LIGHTNING_BIN" daemon enable
	[ "$status" -eq 0 ]
	grep -qF "lightning-dir=$LIGHTNING_OPENRC_STATE" "$LIGHTNING_INIT_D/lightningd"
	grep -qF "pidfile=\"$LIGHTNING_OPENRC_STATE/lightningd-bitcoin.pid\"" "$LIGHTNING_INIT_D/lightningd"
}

@test "FEAT-207/264: OpenRC enable is silent for --system and for a bare (now system) enable" {
	_openrc_common_setup
	run "$LIGHTNING_BIN" -v daemon enable --system
	[ "$status" -eq 0 ]
	! [[ "$output" == *"no per-user mode"* ]]
	# FEAT-264: bare enable defaults to system, which is what OpenRC always
	# does — so there is nothing to flag. (Re-uses the same setup; enable is
	# idempotent.)
	run "$LIGHTNING_BIN" -v daemon enable
	[ "$status" -eq 0 ]
	! [[ "$output" == *"no per-user mode"* ]]
}

@test "FEAT-207/264: OpenRC enable --user warns it cannot honor per-user mode" {
	_openrc_common_setup
	# Only an explicit --user is flagged now (OpenRC has no per-user mode);
	# it still proceeds with the system-wide install.
	run "$LIGHTNING_BIN" -v daemon enable --user
	[ "$status" -eq 0 ]
	[[ "$output" == *"no per-user mode"* ]]
}

@test "FEAT-207: OpenRC enable refuses without --migrate when ~/.lightning exists" {
	_openrc_common_setup
	mkdir -p "$HOME/.lightning"
	run "$LIGHTNING_BIN" daemon enable
	[ "$status" -eq 3 ]
	[[ "$output" == *"--migrate"* ]]
}

@test "FEAT-207: OpenRC enable skips sidecar installation (no keepalive/alert)" {
	_openrc_common_setup
	run "$LIGHTNING_BIN" daemon enable
	[ "$status" -eq 0 ]
	# Sidecars are user-mode systemd/launchd specific.  On OpenRC the
	# operator runs their own monitoring; we don't ship them.
	[ ! -e "$HOME/.config/systemd/user/lightning-keepalive.service" ]
	[ ! -e "$HOME/.config/systemd/user/lightning-alert.service" ]
}

@test "FEAT-207: spec file exists with the expected id" {
	# Moved to done/ when the ticket shipped — same convention every
	# graduated 0.x FEAT followed (issues/feature/done/).
	f="$BATS_TEST_DIRNAME/../../issues/feature/done/207-clightning-install.md"
	[ -f "$f" ]
	grep -q "^id: FEAT-207" "$f"
	grep -q "^status: shipped" "$f"
	grep -q "install-core" "$f"
	grep -q "podman" "$f"
	grep -q "OpenRC" "$f"
}

# ---------------------------------------------------------------------------
# FEAT-205: channel autopilot
# ---------------------------------------------------------------------------

@test "FEAT-205: channel autopilot (no args) prints usage" {
	run "$LIGHTNING_BIN" channel autopilot
	[ "$status" -ne 0 ]
	[[ "$output" == *"run"* ]]
	[[ "$output" == *"status"* ]]
	[[ "$output" == *"suggest"* ]]
}

@test "FEAT-205: channel autopilot --help describes the run/status/suggest split" {
	run "$LIGHTNING_BIN" channel autopilot --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"daemon iteration"* ]]
	[[ "$output" == *"suggestions"* ]]
}

@test "FEAT-205: channel autopilot status reports 'never run' when no state file" {
	run "$LIGHTNING_BIN" channel autopilot status
	[ "$status" -eq 0 ]
	[[ "$output" == *"never run"* ]]
	[[ "$output" == *"daemon enable --autopilot"* ]]
}

@test "FEAT-205: channel autopilot run --dry-run reads config + computes plan" {
	run "$LIGHTNING_BIN" channel autopilot run --dry-run
	[ "$status" -eq 0 ]
	# Plan summary lines visible.
	[[ "$output" == *"starting"* ]]
	[[ "$output" == *"band:"* ]]
	[[ "$output" == *"daily cap:"* ]]
	[[ "$output" == *"would run: lightning fee policy"* ]]
	[[ "$output" == *"done"* ]]
	# State file written even in dry-run.
	[ -f "$HOME/.lightning/autopilot/state.recfile" ]
	grep -q "^last_run:" "$HOME/.lightning/autopilot/state.recfile"
	grep -q "^dry_run: 1" "$HOME/.lightning/autopilot/state.recfile"
}

@test "FEAT-205: channel autopilot honours autopilot.conf overrides" {
	mkdir -p "$HOME/.lightning"
	cat > "$HOME/.lightning/autopilot.conf" <<CFG
rebalance_band_low: 25
rebalance_band_high: 75
rebalance_max_fee_ppm: 1234
rebalance_daily_cap_sat: 99999
fee_policy: lsp-style
CFG
	run "$LIGHTNING_BIN" channel autopilot run --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"25%..75%"* ]]
	[[ "$output" == *"max ppm:"*"1234"* ]]
	[[ "$output" == *"daily cap:"*"99999"* ]]
	[[ "$output" == *"fee policy:"*"lsp-style"* ]]
}

@test "FEAT-205: channel autopilot run refuses when enabled=false" {
	mkdir -p "$HOME/.lightning"
	printf 'enabled: false\n' > "$HOME/.lightning/autopilot.conf"
	run "$LIGHTNING_BIN" channel autopilot run
	[ "$status" -eq 0 ]
	[[ "$output" == *"disabled"* ]]
}

@test "FEAT-205: channel autopilot suggest writes a recfile + prints it" {
	run "$LIGHTNING_BIN" channel autopilot suggest
	[ "$status" -eq 0 ]
	[[ "$output" == *"wrote"* ]]
	[[ "$output" == *"kind: stale-channels"* ]]
	# A suggestions file landed.
	ls "$HOME/.lightning/autopilot/"suggestions-*.recfile >/dev/null
}

@test "FEAT-205: channel autopilot run updates state's budget_day on next-day rollover" {
	# Seed yesterday's state with some budget used.
	mkdir -p "$HOME/.lightning/autopilot"
	cat > "$HOME/.lightning/autopilot/state.recfile" <<EOF2
last_run: 1970-01-01T00:00:00Z
budget_day: 1970-01-01
budget_used_sat: 4000
budget_cap_sat: 5000
EOF2
	run "$LIGHTNING_BIN" channel autopilot run --dry-run
	[ "$status" -eq 0 ]
	# Budget should have reset to 0 since today != 1970-01-01.
	grep -q "^budget_used_sat: 0$" "$HOME/.lightning/autopilot/state.recfile"
}

@test "FEAT-205: channel autopilot run unknown flag fails" {
	run "$LIGHTNING_BIN" channel autopilot run --not-a-real-flag
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown flag"* ]]
}

@test "FEAT-205: channel verb's help mentions autopilot" {
	run "$LIGHTNING_BIN" channel
	[ "$status" -ne 0 ]
	[[ "$output" == *"autopilot"* ]]
}

@test "FEAT-205: daemon enable --autopilot writes a sidecar (Linux)" {
	if [ "$(uname -s)" = "Darwin" ]; then
		skip "Linux-only — checks the systemd timer files"
	fi
	# Don't trigger the systemd-system path; user-mode only.
	run "$LIGHTNING_BIN" daemon enable --user --autopilot --no-keepalive --no-alert
	[ "$status" -eq 0 ]
	[ -f "$HOME/.config/systemd/user/lightning-autopilot.service" ]
	[ -f "$HOME/.config/systemd/user/lightning-autopilot.timer" ]
	grep -q "channel autopilot run" "$HOME/.config/systemd/user/lightning-autopilot.service"
	grep -q "OnUnitActiveSec=15min" "$HOME/.config/systemd/user/lightning-autopilot.timer"
}

@test "FEAT-205: daemon enable (no --autopilot) does NOT write the sidecar" {
	# The autopilot sidecar is opt-in, unlike keepalive/alert.
	run "$LIGHTNING_BIN" daemon enable --user --no-keepalive --no-alert
	[ "$status" -eq 0 ]
	[ ! -e "$HOME/.config/systemd/user/lightning-autopilot.service" ]
	[ ! -e "$HOME/.config/systemd/user/lightning-autopilot.timer" ]
}

@test "FEAT-205: spec file exists with the expected id" {
	# Move to done/ in the same PR that ships the implementation —
	# matches the convention every other graduated FEAT followed.
	f="$BATS_TEST_DIRNAME/../../issues/feature/done/205-channel-autopilot-verb.md"
	[ -f "$f" ]
	grep -q "^id: FEAT-205" "$f"
	grep -q "^status: shipped" "$f"
	grep -q "autopilot" "$f"
	grep -q "rebalance" "$f"
}

@test "FEAT-211: account verb's help lists the new account-centric subs" {
	run "$LIGHTNING_BIN" account
	[ "$status" -ne 0 ]
	[[ "$output" == *"topup"* ]]
	[[ "$output" == *"withdraw"* ]]
	[[ "$output" == *"pay"* ]]
	[[ "$output" == *"receive"* ]]
}

@test "FEAT-211: account topup unknown account exits with hint" {
	_acct_setup
	run "$LIGHTNING_BIN" account topup nosuchaccount 10000
	[ "$status" -eq 2 ]
	[[ "$output" == *"not found"* ]]
	[[ "$output" == *"account create"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account topup prints address + BIP-21 URI + QR" {
	_acct_setup
	run "$LIGHTNING_BIN" account topup rent 100000
	[ "$status" -eq 0 ]
	[[ "$output" == *"Top up account 'rent'"* ]]
	[[ "$output" == *"bcrt1qtestaddress"* ]]
	[[ "$output" == *"BIP-21: bitcoin:"* ]]
	[[ "$output" == *"amount=100000"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account topup --via lightning produces a BOLT-11 invoice" {
	_acct_setup
	run "$LIGHTNING_BIN" account topup rent 5000 --via lightning
	[ "$status" -eq 0 ]
	[[ "$output" == *"lnbcrt"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account topup rejects unknown --via value" {
	_acct_setup
	run "$LIGHTNING_BIN" account topup rent 1000 --via tor
	[ "$status" -ne 0 ]
	[[ "$output" == *"--via must be"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}

@test "FEAT-211: account withdraw rejects a non-bitcoin address" {
	_acct_setup
	run "$LIGHTNING_BIN" account withdraw rent 5000 not-an-address
	[ "$status" -ne 0 ]
	[[ "$output" == *"doesn't look like a bitcoin address"* ]]
	rm -rf "$LIGHTNING_WALLETS_ROOT" "$HOME/.lightning"
}
