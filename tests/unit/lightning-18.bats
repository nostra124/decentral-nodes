#!/usr/bin/env bats
#
# lightning unit tests — part 18 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "FEAT-411: invoice-decode man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-invoice-decode.1" ]
}

# FEAT-412 — node-watchtower-status verb

@test "FEAT-471: peer-disconnect verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/peer-disconnect" ]
}

@test "FEAT-471: peer-disconnect man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-peer-disconnect.1" ]
}

# FEAT-472 — node-keysend-status verb

@test "FEAT-478: wallet-export-csv verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-export-csv" ]
}

@test "FEAT-478: wallet-export-csv man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-wallet-export-csv.1" ]
}

# FEAT-479 — peer-connect verb

@test "FEAT-479: peer-connect verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/peer-connect" ]
}

@test "FEAT-479: peer-connect man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-peer-connect.1" ]
}

# FEAT-480 — node-version verb

@test "FEAT-480: node-version verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/node-version" ]
}

@test "FEAT-480: node-version man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-node-version.1" ]
}

# FEAT-481 — channel-capacity-check verb

@test "FEAT-487: wallet-stats verb exists and is executable" {
	[ -x "$BATS_TEST_DIRNAME/../../libexec/lightning-node/wallet-stats" ]
}

@test "FEAT-487: wallet-stats man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-wallet-stats.1" ]
}

# FEAT-488 — node-max-payment verb

@test "FEAT-651: node-version man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-node-version.1" ]
}

@test "FEAT-676: wallet-prune man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-wallet-prune.1" ]
}

@test "FEAT-679: peer-disconnect man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-peer-disconnect.1" ]
}

@test "FEAT-688: wallet-user man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-wallet-user.1" ]
}

@test "FEAT-728: wallet-stats man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-wallet-stats.1" ]
}

@test "FEAT-773: wallet-export-csv man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-wallet-export-csv.1" ]
}

@test "FEAT-1057: peer-disconnect man page exists" {
	[ -f "$BATS_TEST_DIRNAME/../../share/man/man1/lightning-peer-disconnect.1" ]
}

@test "FEAT-272 — config list shows the conf-set keys" {
	feat272_env
	run "$LIGHTNING_BIN" config list
	[ "$status" -eq 0 ]
	echo "$output" | grep -q 'network'
	echo "$output" | grep -q 'log-level'
}

@test "FEAT-272 — config get returns the conf value (source: conf)" {
	feat272_env
	run "$LIGHTNING_BIN" config get log-level
	[ "$status" -eq 0 ]
	echo "$output" | grep -q 'debug'
}

@test "FEAT-272 — config get falls back to the lightningd default" {
	feat272_env
	run "$LIGHTNING_BIN" config get alias
	[ "$status" -eq 0 ]
	echo "$output" | grep -q 'SILLY-NAME'
}

@test "FEAT-272 — config set replaces/adds a key and warns to restart" {
	feat272_env
	run "$LIGHTNING_BIN" config set fee-base 1000
	[ "$status" -eq 0 ]
	echo "$output" | grep -qi 'restart'
	grep -q '^fee-base=1000' "$LIGHTNING_CONFIG_DIR/config"
}

@test "FEAT-272 — config unset removes a key" {
	feat272_env
	"$LIGHTNING_BIN" config set foo bar
	"$LIGHTNING_BIN" config unset foo
	! grep -q '^foo=' "$LIGHTNING_CONFIG_DIR/config"
}

@test "FEAT-272 — config get errors for an unknown key with no default" {
	feat272_env
	run "$LIGHTNING_BIN" config get totallyboguskey
	[ "$status" -ne 0 ]
}

@test "FEAT-272 — config path prints the conf file" {
	feat272_env
	run "$LIGHTNING_BIN" config path
	[ "$status" -eq 0 ]
	[ "$output" = "$LIGHTNING_CONFIG_DIR/config" ]
}

# ---------------------------------------------------------------------------
# FEAT-298: lightning config list = TSV (NAME<TAB>VALUE<TAB>DESCRIPTION)
# with compiled-in defaults from `lightningd --help`, mirroring bitcoin's
# FEAT-271. Reuses feat272_env's stubbed lightningd + temp config dir, so
# it's hermetic (LIGHTNING_CONFIG_DIR override) and never touches /etc.
# ---------------------------------------------------------------------------
@test "FEAT-298 — config list is TSV (name/value/description) with effective values + defaults" {
	feat272_env
	run "$LIGHTNING_BIN" config list
	[ "$status" -eq 0 ]
	echo "$output" | head -1 | grep -q 'NAME'
	# conf value overrides the default (log-level set to debug in conf):
	echo "$output" | awk -F'\t' '$1=="log-level"&&$2=="debug"{f=1} END{exit !f}'
	# an unset option shows its compiled-in default + description:
	echo "$output" | awk -F'\t' '$1=="alias"&&$2=="SILLY-NAME"&&$3~/alias for node/{f=1} END{exit !f}'
	# a conf-only key (not in --help) still appears:
	echo "$output" | awk -F'\t' '$1=="network"&&$2=="bitcoin"{f=1} END{exit !f}'
}

@test "FEAT-298 — config list --set shows only the conf-set keys" {
	feat272_env
	run "$LIGHTNING_BIN" config list --set
	[ "$status" -eq 0 ]
	echo "$output" | awk -F'\t' '$1=="network"&&$2=="bitcoin"{f=1} END{exit !f}'
	echo "$output" | awk -F'\t' '$1=="log-level"&&$2=="debug"{f=1} END{exit !f}'
	# alias is a default-only key → excluded by --set
	! echo "$output" | awk -F'\t' '$1=="alias"{f=1} END{exit !f}'
}

# ---- fix #1: resolved lightningd path in the ExecStart ----

@test "BUG-033: system unit ExecStart uses the resolved lightningd, not the symlink (Linux)" {
	if [ "$(uname -s)" = "Darwin" ]; then skip "Linux-only — systemd unit"; fi
	_bug033_system_setup
	run "$LIGHTNING_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	local unit="$LIGHTNING_SYSTEMD_DIR/lightningd.service"
	[ -f "$unit" ]
	# References the resolved real target, never the brew-style symlink.
	grep -qF "ExecStart=$(readlink -f "$BIN_SHIM/lightningd") " "$unit"
	grep -q "ExecStart=.*lightningd-real.$$ " "$unit"
	! grep -qF "ExecStart=$BIN_SHIM/lightningd " "$unit"
}

@test "BUG-033: system plist ExecStart uses the resolved lightningd, not the symlink (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then skip "macOS-only — LaunchDaemon"; fi
	_bug033_system_setup
	_bug033_stub_dscl
	run "$LIGHTNING_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	local plist="$LIGHTNING_LAUNCHD_DIR/network.lightning.lightningd.plist"
	[ -f "$plist" ]
	# readlink -f resolves the symlink to the real target (macOS may
	# canonicalize /tmp -> /private/tmp, so match the resolved path and
	# the real basename, not the raw $BATS_TMPDIR prefix). The brew-style
	# symlink path must NOT appear.
	grep -qF "<string>$(readlink -f "$BIN_SHIM/lightningd")</string>" "$plist"
	grep -q "lightningd-real.$$</string>" "$plist"
	! grep -qF "<string>$BIN_SHIM/lightningd</string>" "$plist"
}

# ---- fix #2: bitcoind backend wired into the generated config ----

@test "BUG-033: system config wires bitcoin-cli, bitcoin-datadir, and disables cln-grpc (Linux)" {
	if [ "$(uname -s)" = "Darwin" ]; then skip "Linux-only — install_system"; fi
	_bug033_system_setup
	run "$LIGHTNING_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	# FEAT-298: config under /etc (here redirected via LIGHTNING_CONFIG_DIR).
	local cfg="$LIGHTNING_CONFIG_DIR/config"
	[ -f "$cfg" ]
	grep -q "^bitcoin-cli=" "$cfg"
	grep -q "^bitcoin-datadir=/var/lib/bitcoin$" "$cfg"
	grep -q "^disable-plugin=cln-grpc$" "$cfg"
}

@test "BUG-033: system config wires bitcoin-cli, bitcoin-datadir, and disables cln-grpc (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then skip "macOS-only — install_macos_system"; fi
	_bug033_system_setup
	_bug033_stub_dscl
	run "$LIGHTNING_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	# FEAT-298: config under /etc (here redirected via LIGHTNING_CONFIG_DIR).
	local cfg="$LIGHTNING_CONFIG_DIR/config"
	[ -f "$cfg" ]
	grep -q "^bitcoin-cli=" "$cfg"
	grep -q "^bitcoin-datadir=/var/lib/bitcoin$" "$cfg"
	grep -q "^disable-plugin=cln-grpc$" "$cfg"
}

# ---- fix #3: best-effort join of the bitcoind service group ----

@test "BUG-033: enable adds the service user to the bitcoin group when it exists (Linux)" {
	if [ "$(uname -s)" = "Darwin" ]; then skip "Linux-only — usermod -aG bitcoin"; fi
	_bug033_system_setup
	# Re-stub getent so the 'bitcoin' group lookup succeeds (group exists),
	# while passwd lightning still returns not-found (user create fires).
	cat > "$BIN_SHIM/getent" <<EOF
#!/bin/sh
echo "getent \$*" >> "$BIN_SHIM/getent.calls"
case "\$*" in
	"group bitcoin") exit 0 ;;
	*) exit 2 ;;
esac
EOF
	chmod +x "$BIN_SHIM/getent"
	run "$LIGHTNING_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	[ -f "$BIN_SHIM/usermod.calls" ]
	grep -q "usermod -aG bitcoin lightning" "$BIN_SHIM/usermod.calls"
}

@test "BUG-033: enable does NOT fail when the bitcoin group is absent (Linux)" {
	if [ "$(uname -s)" = "Darwin" ]; then skip "Linux-only"; fi
	_bug033_system_setup
	# Default getent stub returns not-found for everything, including the
	# bitcoin group → the join is a hint, not a failure.
	run "$LIGHTNING_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	# No `usermod -aG bitcoin` happened (group missing).
	if [ -f "$BIN_SHIM/usermod.calls" ]; then
		! grep -q "usermod -aG bitcoin" "$BIN_SHIM/usermod.calls"
	fi
}

@test "BUG-033: enable adds the service user to the _bitcoin group when it exists (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then skip "macOS-only — dseditgroup _bitcoin"; fi
	_bug033_system_setup
	# dscl: -read /Groups/_bitcoin succeeds (group exists), other reads fail.
	cat > "$BIN_SHIM/dscl" <<EOF
#!/bin/sh
echo "dscl \$*" >> "$BIN_SHIM/dscl.calls"
case "\$*" in
	*"-read /Groups/_bitcoin"*) exit 0 ;;
	*-create*) exit 0 ;;
	*-read*|*-list*) exit 1 ;;
	*) exit 1 ;;
esac
EOF
	chmod +x "$BIN_SHIM/dscl"
	run "$LIGHTNING_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	[ -f "$BIN_SHIM/dseditgroup.calls" ]
	grep -q "dseditgroup -o edit -a _lightning -t user _bitcoin" "$BIN_SHIM/dseditgroup.calls"
}

@test "BUG-033: enable does NOT fail when the _bitcoin group is absent (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then skip "macOS-only"; fi
	_bug033_system_setup
	_bug033_stub_dscl   # every -read fails → _bitcoin group "absent"
	run "$LIGHTNING_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	# No dseditgroup add to _bitcoin (only the operator-group add to _lightning).
	if [ -f "$BIN_SHIM/dseditgroup.calls" ]; then
		! grep -q "_bitcoin" "$BIN_SHIM/dseditgroup.calls"
	fi
}

@test "BUG-051: enable joins the 'bitcoin' cookie group when _bitcoin is absent (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then skip "macOS-only — external MacPorts bitcoind group"; fi
	_bug033_system_setup
	# _bitcoin (managed) absent; 'bitcoin' (MacPorts/upstream) present.
	cat > "$BIN_SHIM/dscl" <<EOF
#!/bin/sh
echo "dscl \$*" >> "$BIN_SHIM/dscl.calls"
case "\$*" in
	*"-read /Groups/bitcoin"*) exit 0 ;;
	*-create*) exit 0 ;;
	*-read*|*-list*) exit 1 ;;
	*) exit 1 ;;
esac
EOF
	chmod +x "$BIN_SHIM/dscl"
	run "$LIGHTNING_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	[ -f "$BIN_SHIM/dseditgroup.calls" ]
	grep -q "dseditgroup -o edit -a _lightning -t user bitcoin" "$BIN_SHIM/dseditgroup.calls"
	! grep -q "user _bitcoin" "$BIN_SHIM/dseditgroup.calls"
}

@test "BUG-052: enable auto-detects the backing bitcoind datadir (external node, zero manual edits)" {
	_bug033_system_setup
	[ "$(uname -s)" = "Darwin" ] && _bug033_stub_dscl
	unset LIGHTNING_BITCOIN_DATADIR          # exercise auto-detection
	# A running bitcoind whose -datadir is an external (MacPorts) path.
	cat > "$BIN_SHIM/ps" <<'EOF'
#!/bin/sh
echo "bitcoin 821 /opt/local/bin/bitcoind -datadir=/opt/local/var/lib/bitcoind -conf=/opt/local/etc/bitcoin/bitcoin.conf"
EOF
	chmod +x "$BIN_SHIM/ps"
	run "$LIGHTNING_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	local cfg="$LIGHTNING_CONFIG_DIR/config"
	[ -f "$cfg" ]
	grep -q "^bitcoin-datadir=/opt/local/var/lib/bitcoind$" "$cfg"
	! grep -q "^bitcoin-datadir=/var/lib/bitcoin$" "$cfg"
}
