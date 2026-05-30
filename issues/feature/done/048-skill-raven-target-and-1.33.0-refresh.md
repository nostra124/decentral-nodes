# FEAT-048 — refresh the `bitcoin-wallet` agent skill + add the Raven install target

**Status:** closed (1.34.0)
**Milestone:** 1.34.0

## Summary

The `bitcoin-wallet` agent skill (FEAT-019) was last written against
the 1.15.0 verb set. Two things drifted:

1. **Content went stale.** The command surface was streamlined
   (FEAT-035) and grew new top-level nouns (FEAT-036 `tx`, FEAT-037
   `utxo`, FEAT-038/039 `tax`, FEAT-040 `price`, FEAT-046/047
   `address`), and the `--mainnet` broadcast guard shipped (FEAT-014).
   The skill still taught the deprecated `psbt`/`wallet build` verbs
   and claimed `--mainnet` "isn't shipped".

2. **The rpk skill convention changed.** Upstream
   (<https://github.com/nostra124/rpk>, `docs/PACKAGING.md`) now
   installs every skill to **three** agent destinations — Claude,
   Raven, and opencode — with Claude and Raven sharing the same
   `SKILL.md` (no Raven-specific file). FEAT-019 explicitly deferred
   Raven; this closes that gap.

## Changes

### Skill content (`skills/bitcoin-wallet/`)

- `SKILL.md` refreshed to the 1.33.0 canonical surface and
  restructured to the rpk skill conventions (When to use → Design
  principles → wallet model → Workflow recipes → Guardrails →
  Common failure modes → Related skills → Where to read more).
  - Canonical verbs: PSBT ops are `tx {decode,finalize,extract}`
    (pass-through to `bip174`); descriptor checksum/verify moved to
    `bip380`. New recipes: coin control (`utxo`), fee-bumping
    (`tx bump --rbf|--cpfp`), watch-only (`wallet watch`), address
    tools (`address validate|type|decode|generate`), price + German
    tax (`price`, `tax report-de`).
  - Guardrail 3 corrected: `--mainnet` **is** shipped (FEAT-014); the
    guard now documents the live flag and warns the agent not to add
    it on the user's behalf.
- `opencode.md` refreshed to match (table-form recipes, same verbs).

### Install plumbing (Raven target + opencode fix)

- `Makefile.in install`: also copy `SKILL.md` to
  `share/raven/skills/<name>/` (Claude + Raven share the file).
- `.rpk/package`: same Raven destination, mirroring the Makefile.
- `Makefile.in install-skills-user`: rewritten with correct
  per-agent layout —
  - Claude   → `~/.claude/skills/<name>` (dir)
  - Raven    → `~/.raven/workspace/skills/<name>` (dir)
  - opencode → `~/.config/opencode/commands/<name>.md` (file)
  - **Bug fixed:** the previous loop symlinked opencode to a
    non-existent `share/opencode/skills/<name>` (wrong subdir, and
    missing the `.md`). The symlink was dangling. Now it points at
    the installed `share/opencode/commands/<name>.md`.
- `Makefile.in uninstall-skills-user`: removes the correctly-named
  symlinks across all three agent dirs.

### Docs

- `CLAUDE.md` §2: reference the upstream rpk repo + `docs/PACKAGING.md`
  as the authority for the `.rpk/` and skill-install conventions; fix
  the stale BIP-vendoring path (`share/doc/bitcoin/standards/` →
  `share/doc/bitcoin/bips/`, the path `cite()` and the skill actually
  use).

## Tests (`tests/unit/bitcoin.bats`)

- `FEAT-048 — SKILL.md references the canonical 1.33.0 verb set`:
  asserts the current verbs and that the deprecated standalone
  `bitcoin psbt {decode,finalize,extract}` is not taught as a live
  recipe. (Failed against the pre-refresh SKILL.md, which lacked the
  `tx`/`utxo`/`address`/`price`/`tax` verbs.)
- `FEAT-048 — SKILL.md corrects the --mainnet guardrail`: asserts the
  flag is documented and the "isn't shipped" phrasing is gone.
  (Failed against the old guardrail text.)
- `FEAT-048 — Makefile + .rpk/package install the Raven SKILL.md too`:
  asserts `raven/skills` in both build paths, the Raven user dir, and
  the corrected opencode `.md` symlink. (Failed before the Raven
  target existed.)
- `FEAT-019 AC#3 / FEAT-048 — install-skills-user is idempotent across
  all three agents`: extended to seed a `~/.raven/workspace/skills`
  dir and assert exactly three correctly-named symlinks, stable across
  two runs.
- Updated the existing opencode verb test to the canonical `tx` verbs.

## Acceptance criteria

1. ✅ `SKILL.md`/`opencode.md` describe only verbs that exist at 1.33.0;
   no deprecated `psbt`/`descriptor checksum` taught as live recipes.
2. ✅ The `--mainnet` guardrail reflects the shipped flag.
3. ✅ `make install` and `.rpk/package` install `SKILL.md` to both
   `claude/skills/` and `raven/skills/`, and `opencode.md` to
   `opencode/commands/`.
4. ✅ `make install-skills-user` symlinks correctly into all three
   user agent dirs (iff they exist) and is idempotent;
   `uninstall-skills-user` removes exactly those symlinks.
5. ✅ Every BIP-implementing recipe cites the BIP and the vendored
   `share/doc/bitcoin/bips/` path.

## Release note

The VERSION bump to 1.34.0 and the `.rpk/versions` ledger entry are
handled by the rpk release tooling (`rpk minor`) at merge — not edited
by hand (per the rpk-author guardrail on `VERSION`/`.rpk/versions`).
