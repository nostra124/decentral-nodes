---
id: FEAT-035
type: feature
priority: high
status: done
---

# Command-surface streamline — `bipXXX` plugins + object verbs

## Description

**As a** learner reading the BIP specs alongside the wallet
**I want** every BIP the wallet implements to live under
`bitcoin bipXXX <verb>` so the CLI mirrors the standard
**So that** I can map `bitcoin bip174 decode` directly back to
BIP-174's spec text without translating "psbt" → "BIP-174" in
my head.

**As a** wallet operator
**I want** object verbs (`tx`, `utxo`, `wallet`) that compose
those BIP primitives
**So that** I work in nouns I care about and never have to know
which BIP backs which step.

See `docs/command-surface.md` for the architecture.

## Implementation

### Renames (canonical = new; old = deprecated alias)

| Old (deprecated)            | New (canonical)                         |
|-----------------------------|------------------------------------------|
| `bitcoin psbt <verb>`       | `bitcoin bip174 <verb>`                  |
| `bitcoin descriptor <verb>` | `bitcoin bip380 <verb>` (note: `descriptor wallet` → `bip380 emit`) |
| `bitcoin mnemonic-to-seed`  | `bitcoin bip39 mnemonic-to-seed`         |

### New plugins extracted from the dispatcher

| New plugin     | Source                                        |
|----------------|------------------------------------------------|
| `bip173`       | bech32 encode/decode helpers currently in `bin/bitcoin` (segwit v0). |
| `bip350`       | bech32m encode/decode helpers currently in `bin/bitcoin` (segwit v1+). |

Each new plugin gets:
- A standalone executable at `libexec/bitcoin/bipXXX` with a
  BIP citation at the top of the file (per repo convention).
- Its own `tests/vectors/bipXXX.bats` driven from the BIP's
  appendix vectors.
- Its own `share/man/man1/bitcoin-bipXXX.1` per the FEAT-041
  convention (10-section structure, BIP cite in STANDARDS).
- Logging helpers defined inline per `skills/logging.md` §4 (no
  shared library — per CLAUDE.md §4 no-shared-lib policy).

### Deprecation aliases

Old verb names continue to dispatch. Each emits one `warn`
line on stderr naming the canonical form:

    bitcoin psbt decode
    # → warn: 'psbt' is deprecated since 1.23.0; use 'bip174'.
    # … then runs bip174 decode unchanged.

Each alias also ships a one-line `share/man/man1/bitcoin-<alias>.1`
that `.so`-includes the canonical man page (per FEAT-041
convention) so `man bitcoin-psbt` keeps working.

Aliases are removed in 1.24.0. The `warn` line cites the
removal release so users have one release-cycle of notice.

### Object-verb facades

`wallet new` continues to do the same thing — but now calls
`bip39 mnemonic` → `bip39 mnemonic-to-seed` → `bip32
master-from-seed` → `bip380 emit` rather than reaching into
helpers. No user-visible change. Internal call paths in
`bin/bitcoin` lose their `descriptor:` / `psbt:` private
namespaces; those move to the new plugins.

`tx` (FEAT-036) and `utxo` (FEAT-037) extractions land in
follow-up PRs in this milestone — but FEAT-035 leaves the
dispatcher in a shape where extracting them is a routing
change, not a code move.

## Regression protection

The vector tests under `tests/vectors/` are the contract.
After the streamline, **every existing vector test must pass
unchanged** — both invoked under the old name and under the
new name.

New bats cases for each rename:
- Old name still works on a valid input → produces same bytes
  as the new name.
- Old name emits exactly one `warn` line naming the canonical
  form.
- New name does NOT emit a `warn` line.
- `bitcoin modules` lists both the new `bipXXX` plugins and
  the deprecated aliases, with the alias rows marked.

## Acceptance criteria

1. `libexec/bitcoin/bip173`, `bip174`, `bip350`, `bip380` exist
   as standalone executables with BIP citations and their own
   bats vector files.
2. `libexec/bitcoin/mnemonic-to-seed` is removed; `bitcoin
   mnemonic-to-seed` continues to work as a deprecated alias
   that dispatches to `bip39 mnemonic-to-seed`.
3. `command:descriptor` and `command:psbt` in `bin/bitcoin`
   become thin alias-dispatchers that emit a `warn` line and
   forward to `bip380` / `bip174`. The implementation code
   moves into the plugins.
4. All pre-1.23.0 vector tests pass byte-for-byte under both
   the old and new verb names.
5. `bitcoin modules` output documents the new layout (one
   section for `bipXXX` plugins, one for object verbs, one for
   deprecated aliases).
6. The dispatcher contract test (FEAT-027) is updated to
   assert: object verbs never reach past `bipXXX` plugins to
   reimplement crypto; `bipXXX` plugins never call each other
   or read wallet state.
7. Every new `bipXXX` plugin and every deprecated alias ships
   with `share/man/man1/bitcoin-<verb>.1` per FEAT-041; the
   top-level `bitcoin(1)` `.SH COMMANDS` section is updated to
   list them.
