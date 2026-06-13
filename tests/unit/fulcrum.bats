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
	FULCRUM="$REPO/bin/fulcrum"
	BITCOIN="$REPO/bin/bitcoin"
	export SELF_LIBEXEC="$REPO/libexec"

	FROOT="$BATS_TEST_TMPDIR"
	export HOME="$FROOT/home"; mkdir -p "$HOME"
	export XDG_CONFIG_HOME="$HOME/.config"
	export FULCRUM_CONFIG_DIR="$FROOT/cfg"
	export FULCRUM_DATADIR="$FROOT/db"
	export FULCRUM_ROOT="$FROOT/root"
	export FULCRUM_FULCRUMD="/opt/fulcrum/Fulcrum"
	unset FULCRUM_OS FULCRUM_NODE_OK FULCRUM_ADMIN_FIXTURE \
	      FULCRUM_ADMIN_ADDR FULCRUM_PORT_BUSY

	# Mock init-system + privileged tools; each logs its argv to $CALLLOG.
	MOCKBIN="$FROOT/mockbin"; mkdir -p "$MOCKBIN"
	CALLLOG="$FROOT/calls.log"; : > "$CALLLOG"
	local c
	for c in systemctl launchctl journalctl useradd sysadminctl log du; do
		printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\n' "$c" "$CALLLOG" > "$MOCKBIN/$c"
		chmod +x "$MOCKBIN/$c"
	done
	# du must still print a size for `space`.
	printf '#!/usr/bin/env bash\necho "du $*" >> "%s"\necho "123M\t."\n' "$CALLLOG" > "$MOCKBIN/du"
	chmod +x "$MOCKBIN/du"
	# sudo logs then execs its args (so 'sudo systemctl' still records systemctl).
	printf '#!/usr/bin/env bash\necho "sudo $*" >> "%s"\nexec "$@"\n' "$CALLLOG" > "$MOCKBIN/sudo"
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
	[[ "$output" == *service* ]]
	[[ "$output" == *config* ]]
	[[ "$output" == *info* ]]
}

@test "FEAT-055 AC1: make install stages both bitcoin and fulcrum trees" {
	command -v stow >/dev/null 2>&1 || skip "stow not installed"
	local prefix="$FROOT/prefix"; mkdir -p "$prefix"
	( cd "$REPO" && ./configure --prefix="$prefix" >/dev/null 2>&1 && make install >/dev/null 2>&1 )
	# Staged build tree (stow source) carries every command.
	[ -f "$REPO/build/bitcoin$prefix/bin/bitcoin" ]
	[ -f "$REPO/build/bitcoin$prefix/bin/fulcrum" ]
	[ -d "$REPO/build/bitcoin$prefix/libexec/bitcoin" ]
	[ -d "$REPO/build/bitcoin$prefix/libexec/fulcrum" ]
	( cd "$REPO" && make uninstall >/dev/null 2>&1; rm -rf build Makefile )
}

@test "FEAT-055 AC6: .rpk/identity is unchanged (bitcoin); no second package" {
	[ "$(cat "$REPO/.rpk/identity")" = bitcoin ]
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

@test "FEAT-055 AC5: bin/fulcrum + libexec/fulcrum/* call no forbidden siblings" {
	run _scan_forbidden "$REPO/bin/fulcrum"
	[ "$status" -eq 1 ]
	local f
	while IFS= read -r f; do
		run _scan_forbidden "$f"
		[ "$status" -eq 1 ] || { echo "forbidden call in $f"; return 1; }
	done < <(find "$REPO/libexec/fulcrum" -type f)
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
	run "$FULCRUM" enable --user
	[ "$status" -eq 0 ]
	local unit="$XDG_CONFIG_HOME/systemd/user/fulcrumd.service"
	[ -f "$unit" ]
	grep -q "ExecStart=/opt/fulcrum/Fulcrum" "$unit"
	grep -q "$FULCRUM_DATADIR" "$unit"
	! grep -q "^User=" "$unit"
	run "$FULCRUM" disable --user
	[ "$status" -eq 0 ]
	[ ! -f "$unit" ]
}

@test "FEAT-056 AC3: enable --system (linux) renders a User=fulcrum line" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	run "$FULCRUM" enable --system
	[ "$status" -eq 0 ]
	local unit="$FULCRUM_ROOT/etc/systemd/system/fulcrumd.service"
	[ -f "$unit" ]
	grep -q "^User=fulcrum" "$unit"
	# @FULCRUMD@ must have been substituted away.
	! grep -q "@FULCRUMD@" "$unit"
}

@test "FEAT-262: enable defaults to --system when no mode is given (linux)" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=yes
	run "$FULCRUM" enable
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
	"$FULCRUM" enable >/dev/null 2>&1     # default (system) install
	local sys="$FULCRUM_ROOT/etc/systemd/system/fulcrumd.service"
	[ -f "$sys" ]
	run "$FULCRUM" disable
	[ "$status" -eq 0 ]
	[ ! -f "$sys" ]
	! grep -q "systemctl --user disable" "$CALLLOG"
}

@test "FEAT-262: enable help names --system as the default" {
	run "$FULCRUM" enable --help
	[ "$status" -eq 0 ]
	echo "$output" | grep -q -- '--system (default)'
}

@test "FEAT-056 AC1: enable --user (macos) writes a LaunchAgent plist" {
	export FULCRUM_OS=macos FULCRUM_NODE_OK=yes
	run "$FULCRUM" enable --user
	[ "$status" -eq 0 ]
	local unit="$HOME/Library/LaunchAgents/org.fulcrum.fulcrumd.plist"
	[ -f "$unit" ]
	! grep -q "UserName" "$unit"
}

@test "FEAT-056 AC2: enable errors + non-zero when bitcoind RPC unreachable" {
	export FULCRUM_OS=linux FULCRUM_NODE_OK=no
	run "$FULCRUM" enable --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"bitcoind RPC unreachable"* ]]
}

@test "FEAT-056 AC4: start/stop dispatch systemctl --user (linux)" {
	export FULCRUM_OS=linux
	run "$FULCRUM" start --user
	[ "$status" -eq 0 ]
	grep -q "systemctl --user start fulcrumd" "$CALLLOG"
	run "$FULCRUM" stop --user
	grep -q "systemctl --user stop fulcrumd" "$CALLLOG"
}

@test "FEAT-056 AC4: start --system drives the system systemctl (linux)" {
	export FULCRUM_OS=linux
	run "$FULCRUM" start --system
	[ "$status" -eq 0 ]
	grep -q "systemctl start fulcrumd" "$CALLLOG"
}

@test "FEAT-056 AC4: start (macos) drives launchctl kickstart" {
	export FULCRUM_OS=macos
	run "$FULCRUM" start --user
	grep -q "launchctl kickstart gui/.*/org.fulcrum.fulcrumd" "$CALLLOG"
}

@test "FEAT-056 AC5: space reports index usage, errors when dir absent" {
	export FULCRUM_OS=linux
	rm -rf "$FULCRUM_DATADIR"
	run "$FULCRUM" space --user
	[ "$status" -ne 0 ]
	[[ "$output" == *"does not exist"* ]]
	mkdir -p "$FULCRUM_DATADIR"
	run "$FULCRUM" space --user
	[ "$status" -eq 0 ]
}

@test "FEAT-056 AC6: install --from <bad> is rejected with error + non-zero" {
	run "$FULCRUM" install --from nonsense
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown source"* ]]
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
	[[ "$output" == *"not a fulcrum command"* ]]
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
