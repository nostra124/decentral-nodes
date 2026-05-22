#!/usr/bin/env bats
#
# FEAT-041: per-subcommand man pages.
#
# Every verb in `bitcoin modules` plus every command: function in
# bin/bitcoin must have a corresponding share/man/man1/bitcoin-<verb>.1
# source file conforming to the 10-section structure (NAME, SYNOPSIS,
# DESCRIPTION, OPTIONS, EXIT STATUS, FILES, ENVIRONMENT, SEE ALSO,
# HISTORY; STANDARDS for BIP plugins only).
#
# The Makefile globs share/man/man1/* into $MANDIR/man1/ at install
# time, so the source-tree presence check is enough — install is a
# separate concern covered by the install target.

bats_require_minimum_version 1.5.0

setup() {
	export REPO_ROOT="$BATS_TEST_DIRNAME/../.."
	export MAN_DIR="$REPO_ROOT/share/man/man1"
}

# ---------------------------------------------------------------------------
# Coverage: every shipping verb has a man-page source file.
# ---------------------------------------------------------------------------

# Verbs implemented inside bin/bitcoin as command:<name> functions.
# Help / version / modules are documented in the parent bitcoin(1)
# and intentionally do not get their own page.
# psbt dropped to DEPRECATED_ALIASES in 1.23.0 (FEAT-035 Stream D).
# bech32 dropped to DEPRECATED_ALIASES in 1.23.0 (FEAT-035 Stream C2)
# — canonical homes are bip173 (bech32) and bip350 (bech32m).
# descriptor partially deprecated in 1.23.0 (FEAT-035 Stream B):
# checksum/verify/derive are aliases to bip380; descriptor wallet
# stays in bin/bitcoin. The page is a .so include to bip380.
# tax verb added in 1.23.0 (FEAT-038); label subcommand today,
# report-de + price land in 1.25.0.
# tx verb added in 1.23.0 (FEAT-036); additive surface delegating
# to wallet:* in this release.
# utxo verb added in 1.23.0 (FEAT-037); ships ls / freeze / unfreeze
# in this release.
COMMAND_VERBS="wallet tx utxo tax backend"

# Verbs implemented as standalone libexec/bitcoin/<name> executables.
# mnemonic-to-seed dropped to DEPRECATED_ALIASES in 1.23.0
# (FEAT-035): the standalone shim still exists but the canonical
# subcommand is now `bitcoin bip39 mnemonic-to-seed`.
# bip173 / bip350 added in 1.23.0 (FEAT-035 Stream C).
# bip174 added in 1.23.0 (FEAT-035 Stream D).
LIBEXEC_VERBS="bip13 bip32 bip39 bip173 bip174 bip350 bip380 daemon wif"

# Deprecated aliases that ship a `.so`-include man page pointing
# at their canonical replacement (FEAT-041 alias convention).
# Each entry is "<alias>=<canonical>".
DEPRECATED_ALIASES="mnemonic-to-seed=bip39 psbt=bip174 bech32=bip173 descriptor=bip380"

@test "every command: verb has a bitcoin-<verb>.1 source file" {
	for v in $COMMAND_VERBS; do
		[ -f "$MAN_DIR/bitcoin-$v.1" ] \
			|| { echo "missing: $MAN_DIR/bitcoin-$v.1"; return 1; }
	done
}

@test "every libexec verb has a bitcoin-<verb>.1 source file" {
	for v in $LIBEXEC_VERBS; do
		[ -f "$MAN_DIR/bitcoin-$v.1" ] \
			|| { echo "missing: $MAN_DIR/bitcoin-$v.1"; return 1; }
	done
}

@test "parent bitcoin(1) source file exists" {
	[ -f "$MAN_DIR/bitcoin.1" ]
}

# ---------------------------------------------------------------------------
# Structure: each per-verb page contains every required section.
# Per FEAT-041: NAME, SYNOPSIS, DESCRIPTION, OPTIONS, EXIT STATUS,
# FILES, ENVIRONMENT, SEE ALSO, HISTORY.
# (STANDARDS is required only for BIP plugins and verified separately.)
# ---------------------------------------------------------------------------

REQUIRED_SECTIONS="NAME SYNOPSIS DESCRIPTION OPTIONS \"EXIT STATUS\" FILES ENVIRONMENT \"SEE ALSO\" HISTORY"

assert_sections() {
	local page="$1"
	for section in NAME SYNOPSIS DESCRIPTION OPTIONS "EXIT STATUS" FILES ENVIRONMENT "SEE ALSO" HISTORY; do
		grep -qE "^\.SH \"?${section}\"?$" "$page" \
			|| { echo "$page: missing .SH $section"; return 1; }
	done
}

@test "bitcoin-bip13.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-bip13.1"
}

@test "bitcoin-bip32.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-bip32.1"
}

@test "bitcoin-bip39.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-bip39.1"
}

@test "bitcoin-bip173.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-bip173.1"
}

@test "bitcoin-bip350.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-bip350.1"
}

@test "bitcoin-bip174.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-bip174.1"
}

@test "bitcoin-bip380.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-bip380.1"
}

@test "bitcoin-wif.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-wif.1"
}

@test "bitcoin-daemon.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-daemon.1"
}

@test "bitcoin-mnemonic-to-seed.1 is a .so-include alias to bitcoin-bip39.1" {
	# FEAT-041 alias convention: a deprecated-alias page is a tiny
	# file that resolves to its canonical via groff's .so directive.
	grep -qE '^\.so man1/bitcoin-bip39\.1$' "$MAN_DIR/bitcoin-mnemonic-to-seed.1"
}

@test "bitcoin-wallet.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-wallet.1"
}

@test "bitcoin-backend.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-backend.1"
}

@test "bitcoin-tax.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-tax.1"
}

@test "bitcoin-tx.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-tx.1"
}

@test "bitcoin-utxo.1 has all required sections" {
	assert_sections "$MAN_DIR/bitcoin-utxo.1"
}

@test "bitcoin-descriptor.1 is a .so-include alias to bitcoin-bip380.1" {
	# FEAT-041 alias convention (Stream B made descriptor partially
	# deprecated — checksum/verify/derive forward to bip380).
	grep -qE '^\.so man1/bitcoin-bip380\.1$' "$MAN_DIR/bitcoin-descriptor.1"
}

@test "bitcoin-psbt.1 is a .so-include alias to bitcoin-bip174.1" {
	# FEAT-041 alias convention (Stream D made psbt a deprecated alias).
	grep -qE '^\.so man1/bitcoin-bip174\.1$' "$MAN_DIR/bitcoin-psbt.1"
}

@test "bitcoin-bech32.1 is a .so-include alias to bitcoin-bip173.1" {
	# FEAT-041 alias convention (Stream C2 made bech32 a deprecated alias).
	grep -qE '^\.so man1/bitcoin-bip173\.1$' "$MAN_DIR/bitcoin-bech32.1"
}

# ---------------------------------------------------------------------------
# BIP-plugin pages additionally carry a STANDARDS section that cites
# the BIP. (Object verbs don't — they compose primitives, not specs.)
# ---------------------------------------------------------------------------

@test "BIP-plugin pages carry .SH STANDARDS" {
	# Deprecated-alias pages (.so includes) inherit STANDARDS from
	# their canonical, so we skip them here.
	for v in bip13 bip32 bip39 bip173 bip174 bip350 bip380 wif; do
		grep -qE "^\.SH STANDARDS$" "$MAN_DIR/bitcoin-$v.1" \
			|| { echo "$MAN_DIR/bitcoin-$v.1: missing .SH STANDARDS"; return 1; }
	done
}

# ---------------------------------------------------------------------------
# NAME line shape: `bitcoin-<verb> \- one-line summary`.
# ---------------------------------------------------------------------------

@test "every per-verb page has a well-formed NAME line" {
	# Deprecated-alias pages (.so includes) inherit NAME from their
	# canonical, so we skip them here.
	for v in $COMMAND_VERBS $LIBEXEC_VERBS; do
		page="$MAN_DIR/bitcoin-$v.1"
		# The line after .SH NAME should match `bitcoin\-<verb> \- summary`.
		# Allow escaped hyphens within the verb name.
		name_line=$(awk '/^\.SH NAME$/{getline; print; exit}' "$page")
		echo "$name_line" | grep -qE "^bitcoin\\\\-[a-z0-9\\\\-]+ \\\\- " \
			|| { echo "$page: NAME line malformed: $name_line"; return 1; }
	done
}

# ---------------------------------------------------------------------------
# Deprecated-alias man pages resolve to their canonical via `.so`.
# `man -l <alias.1>` should render the canonical page's content
# (proves the include path is correct and resolvable).
# ---------------------------------------------------------------------------

@test "deprecated-alias pages resolve to their canonical via .so" {
	for entry in $DEPRECATED_ALIASES; do
		alias="${entry%%=*}"
		canonical="${entry##*=}"
		alias_page="$MAN_DIR/bitcoin-$alias.1"
		canonical_page="$MAN_DIR/bitcoin-$canonical.1"
		[ -f "$alias_page" ] || { echo "missing $alias_page"; return 1; }
		[ -f "$canonical_page" ] || { echo "missing $canonical_page"; return 1; }
		grep -qE "^\.so man1/bitcoin-$canonical\.1$" "$alias_page" \
			|| { echo "$alias_page: missing .so include for bitcoin-$canonical.1"; return 1; }
	done
}

# ---------------------------------------------------------------------------
# Parent bitcoin(1) `.SH COMMANDS` cross-references every per-verb page.
# Catches drift if a verb is added without its `.BR bitcoin-<verb> (1)`
# entry in the parent.
# ---------------------------------------------------------------------------

@test "bitcoin(1) .SH COMMANDS references every per-verb page" {
	# Pull the COMMANDS section out, fail if any verb is missing a
	# .BR bitcoin-<verb> (1) entry.
	section=$(awk '/^\.SH COMMANDS$/{f=1; next} /^\.SH [A-Z]/{f=0} f' "$MAN_DIR/bitcoin.1")
	[ -n "$section" ] || { echo "bitcoin(1) missing .SH COMMANDS"; return 1; }
	for v in $COMMAND_VERBS $LIBEXEC_VERBS; do
		echo "$section" | grep -qE "^\.BR bitcoin-$v \(1\)$" \
			|| { echo "bitcoin(1) .SH COMMANDS missing entry for $v"; return 1; }
	done
}

# ---------------------------------------------------------------------------
# `man` resolves each page from the source tree (no install needed).
# This proves the file is well-formed enough that mandoc / man-db
# will accept it.
# ---------------------------------------------------------------------------

@test "man -l renders every per-verb page without error" {
	# `man -l` (BSD-style "local file" mode, supported by both
	# man-db and mandoc) parses the file as a manpage. If the macro
	# usage is malformed, man exits non-zero.
	#
	# Alias pages (`.so` includes) are NOT covered here: `man -l`
	# resolves `.so man1/<file>` relative to MANDIR, which isn't
	# set when invoking on an explicit source path. The earlier
	# "resolve to canonical via .so" assertion already proves the
	# include path is well-formed; the canonical's own `man -l`
	# pass below proves the included file renders.
	command -v man >/dev/null || skip "man not installed"
	for v in $COMMAND_VERBS $LIBEXEC_VERBS; do
		run man -l "$MAN_DIR/bitcoin-$v.1"
		[ "$status" -eq 0 ] \
			|| { echo "man -l failed for bitcoin-$v.1: $output"; return 1; }
		[ -n "$output" ]
	done
}

@test "man -l renders parent bitcoin(1) without error" {
	command -v man >/dev/null || skip "man not installed"
	run man -l "$MAN_DIR/bitcoin.1"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}
