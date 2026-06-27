#!/usr/bin/env bats
#
# lightning unit tests — part 6 of 18 (FEAT-053 split of tests/unit/lightning.bats).
# Shared setup/teardown/fixtures: tests/unit/lib/lightning.bash.

bats_require_minimum_version 1.5.0
load lib/lightning


@test "BUG-032: daemon monitor (system, Linux) tails lightningd.service via journalctl" {
	if [ "$(uname -s)" = "Darwin" ]; then
		skip "Linux-only — exercises journalctl -u"
	fi
	# system-mode journalctl monitor must target the renamed unit
	# lightningd.service (not clightningd.service) and use no sudo.
	cat > "$BIN_SHIM/journalctl" <<EOF
#!/bin/sh
echo "journalctl \$*" >> "$BIN_SHIM/journalctl.calls"
exit 0
EOF
	chmod +x "$BIN_SHIM/journalctl"
	run "$LIGHTNING_BIN" daemon monitor --system
	[ "$status" -eq 0 ]
	grep -q -- "-u lightningd.service" "$BIN_SHIM/journalctl.calls"
	! grep -q "clightningd.service" "$BIN_SHIM/journalctl.calls"
}

@test "BUG-050: macOS operate verbs auto-detect SYSTEM when the LaunchDaemon is installed (no flag)" {
	# Force Darwin so the macOS detection path runs on the Linux CI too.
	cat > "$BIN_SHIM/uname" <<'EOF'
#!/bin/sh
[ "$1" = "-s" ] && { echo Darwin; exit 0; }
exec /usr/bin/uname "$@"
EOF
	chmod +x "$BIN_SHIM/uname"
	# A system LaunchDaemon is installed (the 3.1.0 default); no user agent.
	mkdir -p "$LIGHTNING_LAUNCHD_DIR"
	: > "$LIGHTNING_LAUNCHD_DIR/network.lightning.lightningd.plist"
	rm -rf "$LIGHTNING_LAUNCHAGENTS_DIR"
	# Redirect the system state dir to an empty tmp dir so monitor finds no
	# log and errors with the path it tried (the assertable signal).
	export LIGHTNING_SYSTEM_STATE="$BATS_TMPDIR/sysstate.$$"
	rm -rf "$LIGHTNING_SYSTEM_STATE"
	# No --system/--user flag: this must AUTO-DETECT system, not fall back to
	# user (the BUG-050 regression: system_mode was systemd-only, so macOS
	# always resolved user and monitor tailed ~/.lightning/log).
	run "$LIGHTNING_BIN" daemon monitor
	[ "$status" -eq 2 ]
	[[ "$output" == *"$LIGHTNING_SYSTEM_STATE/log"* ]]
	[[ "$output" != *"/.lightning/log"* ]]
}

@test "BUG-049: peer bootstrap does NOT persist important-peer when lightningd rejects it" {
	# A lightningd whose --help does NOT list --important-peer (the real CLN
	# build that crash-looped on 'unknown option').
	cat > "$BIN_SHIM/lightningd" <<'EOF'
#!/bin/sh
[ "$1" = "--help" ] && { echo "usage: lightningd [options]"; echo "  --alias=<arg>"; exit 0; }
exit 0
EOF
	chmod +x "$BIN_SHIM/lightningd"
	printf '03aaa@1.2.3.4:9735\n03bbb@5.6.7.8:9735\n' > "$BATS_TMPDIR/nodes.$$"
	export LIGHTNING_BOOTSTRAP_NODES="$BATS_TMPDIR/nodes.$$"
	run "$LIGHTNING_BIN" peer bootstrap
	[ "$status" -eq 0 ]
	# The bricking line must NOT be persisted (BUG-049 regression).
	[ ! -f "$HOME/.lightning/config" ] || ! grep -q 'important-peer=' "$HOME/.lightning/config"
}

@test "BUG-049: peer bootstrap persists important-peer when lightningd accepts it" {
	export LIGHTNING_IMPORTANT_PEER_SUPPORTED=1
	printf '03aaa@1.2.3.4:9735\n' > "$BATS_TMPDIR/nodes.$$"
	export LIGHTNING_BOOTSTRAP_NODES="$BATS_TMPDIR/nodes.$$"
	run "$LIGHTNING_BIN" peer bootstrap
	[ "$status" -eq 0 ]
	grep -q 'important-peer=03aaa@1.2.3.4:9735' "$HOME/.lightning/config"
}

@test "1.2.0 ext: daemon with unknown subcommand prints usage" {
	run "$LIGHTNING_BIN" daemon takeover
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown"* ]]
}

# --- tor -------------------------------------------------------------------

@test "1.2.0 ext: tor status with no lightning-cli returns non-zero" {
	export PATH="/usr/bin:/bin"
	hash -r
	run "$LIGHTNING_BIN" node tor status
	# Reports tor not running and no lightning-cli, exits non-zero.
	[ "$status" -ne 0 ]
}

@test "1.2.0 ext: tor with unknown subcommand prints usage" {
	run "$LIGHTNING_BIN" node tor sideways
	[ "$status" -ne 0 ]
	[[ "$output" == *"usage"* ]]
}

# --- qr ----------------------------------------------------------------------

@test "1.2.0 ext: qr with unknown flag fails" {
	run "$LIGHTNING_BIN" qr "lnbcrt10n1ptest" --webp out.webp
	[ "$status" -ne 0 ]
}

@test "1.2.0 ext: qr - reads text from stdin" {
	# Just verify exit 0 + non-empty output. The actual rendered
	# content differs: with qrencode it's UTF-8 half-blocks; without
	# it's the fallback echo of the text.
	run bash -c "echo lnbcrt10n1pstdintest | '$LIGHTNING_BIN' qr -"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

# --- bin/lightning-node dispatcher edge cases -----------------------------------

@test "1.2.0 ext: sourced dispatcher doesn't run getopts on host's argv" {
	# Regression: getopts in a sourced script can chew host's argv.
	# After sourcing, $1 should still be whatever the host had.
	local sh="$LIGHTNING_BIN"
	run bash -c "set -- foo bar; . '$sh'; echo \"\$1\""
	[ "$status" -eq 0 ]
	[ "$output" = "foo" ]
}

# ---------------------------------------------------------------------------
# 1.3.0 — kcov coverage measurement
# ---------------------------------------------------------------------------

@test "1.3.0: Makefile.in has a `coverage` target that wraps bats in kcov" {
	f="$BATS_TEST_DIRNAME/../../Makefile.in"
	[ -f "$f" ]
	grep -q "^coverage:" "$f"
	grep -q "kcov" "$f"
	grep -q "COVERAGE_DIR" "$f"
}

@test "1.3.0: CI workflow has a separate coverage job that uploads HTML" {
	f="$BATS_TEST_DIRNAME/../../.github/workflows/test.yml"
	[ -f "$f" ]
	grep -q "^  coverage:" "$f"
	grep -q "kcov" "$f"
	grep -q "upload-artifact" "$f"
	grep -q "coverage-html" "$f"
}

@test "1.3.0: coverage job depends on the test job (sequenced)" {
	f="$BATS_TEST_DIRNAME/../../.github/workflows/test.yml"
	# `needs: test` ensures the gate-job runs first.
	grep -qE "^[[:space:]]*needs:[[:space:]]*test" "$f"
}

# ---------------------------------------------------------------------------
# FEAT-207 — `lightning daemon install` scaffold
# (issues/feature/207-clightning-install.md)
# ---------------------------------------------------------------------------

@test "FEAT-207: daemon install --help mentions the sources" {
	run "$LIGHTNING_BIN" daemon install --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"rpk"*    ]]
	[[ "$output" == *"brew"*   ]]
	[[ "$output" == *"apk"*    ]]
	[[ "$output" == *"source"* ]]
	[[ "$output" == *"podman"* ]]
}

@test "FEAT-207: daemon install --from docker is refused" {
	run "$LIGHTNING_BIN" daemon install --from docker
	[ "$status" -ne 0 ]
	[[ "$output" == *"docker is not supported"* ]] || \
	[[ "$output" == *"docker"* && "$output" == *"podman"* ]]
}

@test "FEAT-207: install-core --dry-run --from rpk prints the rpk plan" {
	run "$LIGHTNING_BIN" daemon install --from rpk --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"source:"*"rpk"* ]]
	[[ "$output" == *"rpk install lightningd"* ]]
}

@test "FEAT-207: install-core --dry-run --from brew prints the brew plan" {
	run "$LIGHTNING_BIN" daemon install --from brew --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"brew install core-lightning"* ]]
}

@test "FEAT-207: install-core --dry-run --from apk prints the apk plan" {
	run "$LIGHTNING_BIN" daemon install --from apk --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"apk add lightningd"* ]]
}

@test "FEAT-207: install-core --dry-run --from source prints the source plan" {
	run "$LIGHTNING_BIN" daemon install --from source --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"git clone"* ]]
	[[ "$output" == *"configure"* ]]
}

@test "FEAT-207: install-core --dry-run --from podman prints the podman plan" {
	run "$LIGHTNING_BIN" daemon install --from podman --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"podman pull"* ]]
	[[ "$output" == *"elementsproject/lightningd"* ]]
}

@test "FEAT-207: install-core --from invalid_source --dry-run is refused" {
	run "$LIGHTNING_BIN" daemon install --from invalid_source --dry-run
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown source"* || "$output" == *"invalid"* ]]
}

@test "FEAT-207: install-core --tag pin shows up in the plan" {
	run "$LIGHTNING_BIN" daemon install --from brew --tag v26.04.1 --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"tag:"*"v26.04.1"* ]]
}

@test "FEAT-207: install-core unknown flag fails" {
	run "$LIGHTNING_BIN" daemon install --not-a-real-flag
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown flag"* ]]
}

@test "FEAT-207: install-core --from rpk runs rpk install lightningd" {
	_stub_rpk 0 1
	run "$LIGHTNING_BIN" daemon install --from rpk --yes
	[ "$status" -eq 0 ]
	[ -f "$BIN_SHIM/rpk.calls" ]
	grep -q "rpk install lightningd" "$BIN_SHIM/rpk.calls"
	grep -q "\\--yes" "$BIN_SHIM/rpk.calls"
	[[ "$output" == *"lightningd installed"* ]]
}

@test "FEAT-207: install-core --from rpk --tag pins the version" {
	_stub_rpk 0 1
	run "$LIGHTNING_BIN" daemon install --from rpk --tag v26.04.1
	[ "$status" -eq 0 ]
	# rpk's own flag is --version (the user-facing --tag maps onto it).
	grep -q "\\--version v26.04.1" "$BIN_SHIM/rpk.calls"
}

@test "FEAT-207: install-core --from rpk propagates rpk failure" {
	_stub_rpk 17 0
	run "$LIGHTNING_BIN" daemon install --from rpk
	[ "$status" -eq 17 ]
	[[ "$output" == *"rpk install failed"* ]]
	[[ "$output" == *"rpk package isn't published"* ]]
}

@test "FEAT-207: install-core --from rpk errors when rpk not on PATH" {
	# No rpk shim — the BIN_SHIM is clean by default.
	# BUG-037 — scrub PATH so a real `rpk` on the host (this IS an rpk box:
	# ~/.local/bin/rpk) can't satisfy the on-PATH check we're asserting is
	# absent. On CI rpk isn't installed, so this matches that condition.
	export PATH="$BIN_SHIM:/usr/bin:/bin"
	run "$LIGHTNING_BIN" daemon install --from rpk
	[ "$status" -eq 1 ]
	[[ "$output" == *"rpk not on PATH"* ]]
}

@test "FEAT-207: install-core --from rpk --dry-run skips the rpk-on-PATH check" {
	# Operators may be planning on a different machine — dry-run shouldn't
	# require the package manager to be installed locally.
	run "$LIGHTNING_BIN" daemon install --from rpk --dry-run
	[ "$status" -eq 0 ]
	[ ! -f "$BIN_SHIM/rpk.calls" ]
	[[ "$output" == *"rpk install lightningd"* ]]
}

@test "FEAT-207: install-core --from rpk fails if lightningd missing post-install" {
	# rpk reports success but doesn't actually install the binary.
	_stub_rpk 0 0
	run "$LIGHTNING_BIN" daemon install --from rpk
	[ "$status" -eq 1 ]
	[[ "$output" == *"reported success"* ]]
	[[ "$output" == *"not on PATH"* ]]
}

@test "FEAT-207: install-core --from brew off-macOS exits with a clear hint" {
	# bats CI runs Linux — is_macos returns false there, so --from brew errors.
	# BUG-037 — on a macOS host is_macos() is true and brew would be ACCEPTED,
	# so stub `uname -s` -> Linux to exercise the off-macOS rejection path the
	# same way CI does.
	_stub_uname_linux
	_stub_brew 0 1
	run "$LIGHTNING_BIN" daemon install --from brew
	[ "$status" -eq 1 ]
	[[ "$output" == *"macOS-only"* ]] || [[ "$output" == *"macOS"* ]]
}

@test "FEAT-207: install-core --from brew --dry-run prints the brew install plan" {
	# Dry-run skips the macOS gate and the brew-on-PATH check, so the
	# Linux CI can still validate the plan text.
	run "$LIGHTNING_BIN" daemon install --from brew --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"brew install core-lightning"* ]]
}

@test "FEAT-207: install-core --from brew --tag uses the @version formula" {
	run "$LIGHTNING_BIN" daemon install --from brew --tag v26.04.1 --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"core-lightning@v26.04.1"* ]]
}

@test "FEAT-207: install-core --from brew --force uses brew reinstall" {
	run "$LIGHTNING_BIN" daemon install --from brew --force --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"brew reinstall"* ]]
}

@test "FEAT-207: install-core refuses when lightningd is already on PATH" {
	# Drop a fake lightningd ahead of the call.
	printf '#!/bin/sh\necho "Core Lightning v25.05.0"\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	_stub_rpk 0 1
	run "$LIGHTNING_BIN" daemon install --from rpk
	[ "$status" -eq 1 ]
	[[ "$output" == *"already on PATH"* ]]
	[[ "$output" == *"--force"* ]]
	[ ! -f "$BIN_SHIM/rpk.calls" ]
}

@test "FEAT-207: install-core --force overrides the idempotency check" {
	printf '#!/bin/sh\necho "Core Lightning v25.05.0"\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	_stub_rpk 0 1
	run "$LIGHTNING_BIN" daemon install --from rpk --force
	[ "$status" -eq 0 ]
	[ -f "$BIN_SHIM/rpk.calls" ]
	grep -q "\\--force" "$BIN_SHIM/rpk.calls"
}

@test "FEAT-207: install-core --dry-run skips the idempotency check" {
	# Dry-run is "what would you do" — it shouldn't refuse on existing installs.
	printf '#!/bin/sh\necho "Core Lightning v25.05.0"\n' > "$BIN_SHIM/lightningd"
	chmod +x "$BIN_SHIM/lightningd"
	run "$LIGHTNING_BIN" daemon install --from rpk --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"plan:"* ]]
}

@test "FEAT-207: install-core --from apk runs apk add lightningd via doas" {
	_fake_alpine_os_release
	_stub_id_nonroot
	_stub_apk 0 1
	_stub_doas
	export BIN_SHIM_CALLS_DIR="$BIN_SHIM"
	run "$LIGHTNING_BIN" daemon install --from apk
	[ "$status" -eq 0 ]
	[ -f "$BIN_SHIM/apk.calls" ]
	grep -q "apk add lightningd" "$BIN_SHIM/apk.calls"
	[ -f "$BIN_SHIM/doas.calls" ]
	grep -q "doas apk add" "$BIN_SHIM/doas.calls"
	[[ "$output" == *"lightningd installed"* ]]
}

@test "FEAT-207: install-core --from apk falls back to sudo when doas is absent" {
	_fake_alpine_os_release
	_stub_id_nonroot
	_stub_apk 0 1
	_stub_sudo
	export BIN_SHIM_CALLS_DIR="$BIN_SHIM"
	run "$LIGHTNING_BIN" daemon install --from apk
	[ "$status" -eq 0 ]
	[ -f "$BIN_SHIM/sudo.calls" ]
	grep -q "sudo apk add" "$BIN_SHIM/sudo.calls"
	[ ! -f "$BIN_SHIM/doas.calls" ]
}

@test "FEAT-207: install-core --from apk skips prefix when already root" {
	# When ic_root_prefix returns empty (id -u == 0), the apk call is bare.
	# Force id -u to 0 — GH-hosted runners are non-root, locally we may
	# already be root, so either way we get a deterministic answer.
	_fake_alpine_os_release
	_stub_id_root
	_stub_apk 0 1
	export BIN_SHIM_CALLS_DIR="$BIN_SHIM"
	run "$LIGHTNING_BIN" daemon install --from apk
	[ "$status" -eq 0 ]
	[ -f "$BIN_SHIM/apk.calls" ]
	# Bare `apk add` — no doas / sudo prefix on the line.
	[ ! -f "$BIN_SHIM/doas.calls" ]
	[ ! -f "$BIN_SHIM/sudo.calls" ]
}

@test "FEAT-207: install-core --from apk --tag pins via apk's = syntax" {
	_fake_alpine_os_release
	_stub_apk 0 1
	_stub_doas
	export BIN_SHIM_CALLS_DIR="$BIN_SHIM"
	run "$LIGHTNING_BIN" daemon install --from apk --tag 26.04.1-r0
	[ "$status" -eq 0 ]
	grep -q "lightningd=26.04.1-r0" "$BIN_SHIM/apk.calls"
}

@test "FEAT-207: install-core --from apk --force uses --force-overwrite" {
	_fake_alpine_os_release
	_stub_apk 0 1
	_stub_doas
	export BIN_SHIM_CALLS_DIR="$BIN_SHIM"
	run "$LIGHTNING_BIN" daemon install --from apk --force
	[ "$status" -eq 0 ]
	grep -q "\\--force-overwrite" "$BIN_SHIM/apk.calls"
}

@test "FEAT-207: install-core --from apk off-Alpine exits with a clear hint" {
	# No fake os-release — platform_id() returns the real platform
	# (ubuntu in CI).
	_stub_apk 0 1
	_stub_doas
	export BIN_SHIM_CALLS_DIR="$BIN_SHIM"
	run "$LIGHTNING_BIN" daemon install --from apk
	[ "$status" -eq 1 ]
	[[ "$output" == *"not an Alpine system"* ]]
	[ ! -f "$BIN_SHIM/apk.calls" ]
}

@test "FEAT-207: install-core --from apk --dry-run skips platform + apk checks" {
	# No fake os-release, no apk shim — dry-run should still print the plan.
	run "$LIGHTNING_BIN" daemon install --from apk --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"apk add lightningd"* ]]
}

@test "FEAT-207: install-core --from apk propagates apk failure" {
	_fake_alpine_os_release
	_stub_apk 42 0
	_stub_doas
	export BIN_SHIM_CALLS_DIR="$BIN_SHIM"
	run "$LIGHTNING_BIN" daemon install --from apk
	[ "$status" -eq 42 ]
	[[ "$output" == *"apk add failed"* ]]
}

@test "FEAT-207: install-core --from apk fails if lightningd missing post-install" {
	_fake_alpine_os_release
	_stub_apk 0 0
	_stub_doas
	export BIN_SHIM_CALLS_DIR="$BIN_SHIM"
	run "$LIGHTNING_BIN" daemon install --from apk
	[ "$status" -eq 1 ]
	[[ "$output" == *"reported success"* ]]
}

@test "FEAT-207: platform_id reads LIGHTNING_OS_RELEASE override" {
	# Sanity check for the test hook itself — used by stage-2 onwards.
	_fake_alpine_os_release
	# Reach into the daemon verb's helper via subshell.
	run env LIGHTNING_OS_RELEASE="$LIGHTNING_OS_RELEASE" sh -c '
		. "'"$BATS_TEST_DIRNAME"'/../../libexec/lightning-node/daemon" >/dev/null 2>&1
		platform_id
	' 2>/dev/null || true
	# The daemon script invokes case logic when sourced; we can't rely on
	# fully sourcing it.  Instead exercise the override through the verb:
	run "$LIGHTNING_BIN" daemon install --from apk --dry-run
	[ "$status" -eq 0 ]
	# Output line is "platform:   alpine"
	[[ "$output" == *"platform:"*"alpine"* ]]
}

@test "FEAT-207: install-core --from source --yes runs the full sequence" {
	_source_common_setup
	_stub_apt_get 0
	_stub_git_for_source 0
	_stub_make 0 1
	run "$LIGHTNING_BIN" daemon install --from source --yes
	[ "$status" -eq 0 ]
	# apt-get install was called with the build deps.
	[ -f "$BIN_SHIM/apt-get.calls" ]
	grep -q "apt-get install" "$BIN_SHIM/apt-get.calls"
	grep -q "build-essential"  "$BIN_SHIM/apt-get.calls"
	grep -q "libsqlite3-dev"   "$BIN_SHIM/apt-get.calls"
	grep -q "libsodium-dev"    "$BIN_SHIM/apt-get.calls"
	# git clone went to the configured build dir.
	[ -f "$BIN_SHIM/git.calls" ]
	grep -q "git clone .*ElementsProject/lightning" "$BIN_SHIM/git.calls"
	grep -q "$LIGHTNING_BUILD_DIR/lightning" "$BIN_SHIM/git.calls"
	# make + make install ran.
	[ -f "$BIN_SHIM/make.calls" ]
	grep -q "^make" "$BIN_SHIM/make.calls"
	grep -q "make install" "$BIN_SHIM/make.calls"
	# Post-install verification fired.
	[[ "$output" == *"lightningd installed"* ]]
}

@test "FEAT-207: install-core --from source --yes --tag checks out the tag" {
	_source_common_setup
	_stub_apt_get 0
	_stub_git_for_source 0
	_stub_make 0 1
	run "$LIGHTNING_BIN" daemon install --from source --yes --tag v26.04.1
	[ "$status" -eq 0 ]
	grep -q "git checkout v26.04.1" "$BIN_SHIM/git.calls"
}

@test "FEAT-207: install-core --from source refuses without --yes when stdin isn't a TTY" {
	_source_common_setup
	_stub_apt_get 0
	_stub_git_for_source 0
	_stub_make 0 1
	# bats `run` doesn't allocate a TTY, so this is the path under test.
	run "$LIGHTNING_BIN" daemon install --from source
	[ "$status" -eq 1 ]
	[[ "$output" == *"not a TTY"* ]]
	[[ "$output" == *"--yes"* ]]
	[ ! -f "$BIN_SHIM/apt-get.calls" ]
}

@test "FEAT-207: install-core --from source off-Ubuntu exits with a clear hint" {
	# Fake Alpine — same os-release machinery the apk tests use.
	_fake_alpine_os_release
	export LIGHTNING_BUILD_DIR="$BATS_TMPDIR/lightning-build.$$"
	_stub_apt_get 0
	_stub_git_for_source 0
	_stub_make 0 1
	run "$LIGHTNING_BIN" daemon install --from source --yes
	[ "$status" -eq 1 ]
	[[ "$output" == *"Ubuntu"* ]] || [[ "$output" == *"ubuntu"* ]]
	[[ "$output" == *"apk"* ]]
	[ ! -f "$BIN_SHIM/apt-get.calls" ]
}
