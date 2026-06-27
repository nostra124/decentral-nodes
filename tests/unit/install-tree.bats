#!/usr/bin/env bats
#
# FEAT-313 / BUG-058 regression: the dev-tree unit suites never exercise
# what `make install` actually produces, which let BUG-058 ship (installed
# nodes with zero verbs). This tier installs into a temp prefix and asserts
# every dispatcher's verbs are staged — the thing dev-tree tests can't see.

setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "BUG-058: make install stages verbs for every -node command + version resolves" {
	command -v stow >/dev/null 2>&1 || skip "stow not installed"
	local prefix="$BATS_TEST_TMPDIR/pfx"; mkdir -p "$prefix"
	( cd "$REPO" && ./configure --prefix="$prefix" >/dev/null 2>&1 \
		&& make install >/dev/null 2>&1 ) || { echo "configure/install failed"; return 1; }

	local path cmd fail=0
	# Universal invariant: every dispatcher installs AND its verbs are
	# staged (not an empty mkdir'd dir) — the BUG-058 core.
	for path in "$REPO"/bin/*-node; do
		cmd="$(basename "$path")"
		[ -x "$prefix/bin/$cmd" ] || { echo "FAIL $cmd: not on PATH"; fail=1; continue; }
		if [ -z "$(ls -A "$prefix/libexec/$cmd" 2>/dev/null)" ]; then
			echo "FAIL $cmd: no verbs under libexec/$cmd (BUG-058)"; fail=1
		fi
	done

	# Version-file install + resolution, one per dispatcher style:
	# bitcoin-node (rich command:version) and forgejo-node (inline shim).
	local v; v="$(cat "$REPO/VERSION")"
	for cmd in bitcoin-node forgejo-node; do
		run env -u SELF_LIBEXEC -u SELF_VERSION "$prefix/bin/$cmd" version
		if [ "$status" -ne 0 ] || [ "$output" != "$v" ]; then
			echo "FAIL $cmd: version status=$status out='$output' want='$v'"; fail=1
		fi
	done

	# Data namespace staged (hardcoded share/bitcoin, not the -node name).
	[ -d "$prefix/share/bitcoin/bip39" ] || { echo "FAIL: share/bitcoin data not installed"; fail=1; }

	( cd "$REPO" && make uninstall >/dev/null 2>&1; rm -rf build Makefile )
	[ "$fail" -eq 0 ]
}

@test "BUG-058: every bin/*-node is registered in PACKAGES and .rpk COMMANDS" {
	local pkgs cmds path cmd fail=0
	pkgs=" $(grep -m1 '^PACKAGES = ' "$REPO/Makefile.in" | sed 's/^PACKAGES = //') "
	cmds=" $(grep -m1 '^COMMANDS=' "$REPO/.rpk/package" | sed 's/^COMMANDS=//; s/\"//g') "
	for path in "$REPO"/bin/*-node; do
		cmd="$(basename "$path")"
		[[ "$pkgs" == *" $cmd "* ]] || { echo "FAIL: $cmd missing from Makefile.in PACKAGES"; fail=1; }
		[[ "$cmds" == *" $cmd "* ]] || { echo "FAIL: $cmd missing from .rpk COMMANDS"; fail=1; }
	done
	[ "$fail" -eq 0 ]
}
