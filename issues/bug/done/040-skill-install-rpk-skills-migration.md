---
id: BUG-040
type: bug
priority: medium
status: done
---

# Skill install plumbing still reads the dead `skills/<name>/SKILL.md` layout; nothing installs and FEAT-019 fails

## Severity

**Medium.** `make install` / `make install-skills-user` (and the `.rpk/package`
install) silently install **zero** agent skills, and
`tests/unit/bitcoin.bats` "FEAT-019 AC#3 / FEAT-048 — make install-skills-user
is idempotent across all three agents" fails on every configured tree. The
bitcoin/lightning agent skills (`bitcoin-wallet`, `bitcoin-operator`,
`lightning-*`) ship in the repo but never reach `~/.claude/skills`,
`~/.raven/workspace/skills`, or `~/.config/opencode/commands`.

## Observed

`bats tests/unit/bitcoin.bats` →
`not ok … make install-skills-user is idempotent across all three agents`
(`count1` is 0, the test wants 3). `make install-skills-user` creates no
symlinks; `make install` stages no `share/{claude,raven,opencode}` skills.

## Root cause

Commit `ad723c4` ("register bitcoin-wallet skill under .rpk/skills/") migrated
the skill **source** from `skills/<name>/SKILL.md` + `opencode.md` to the
rpk-native flat `.rpk/skills/<name>.md` ("so `rpk skills` discovers it") and
removed the old `skills/<name>/` directories. But the **install plumbing** was
left iterating the old layout:

- `Makefile.in` `install` (skill staging), `install-skills-user`,
  `uninstall-skills-user` — all loop `skills/*-*` and test `SKILL.md` /
  `opencode.md`.
- `.rpk/package` — same loop.
- `tests/unit/bitcoin.bats` FEAT-019 — asserts `skills/bitcoin-wallet/` and an
  exact count of 3 links.

So `ls -d skills/*-*` matches nothing (the repo's `skills/` now holds only flat
developer-doc `.md` files), the loops are no-ops, and the test fails. The
lightning side was already migrated — `tests/unit/lightning.bats` FEAT-180
reads `.rpk/skills/lightning-wallet.md` — which is why only the bitcoin
plumbing was stranded.

## Fix

Point every install path at `.rpk/skills/*.md` and install each single file to
all three agent destinations (Claude + Raven share it as `SKILL.md`; opencode
gets `<name>.md`):

- `Makefile.in`: `install` staging, `install-skills-user`,
  `uninstall-skills-user`.
- `.rpk/package`: the same loop.
- `tests/unit/bitcoin.bats` FEAT-019: source the skill list from
  `.rpk/skills/*.md`, expect `3 * nskills` links (the combined stack ships
  several), keep the `bitcoin-wallet`-in-each-agent + idempotency assertions.

## Regression test

`tests/unit/bitcoin.bats` "FEAT-019 …" now passes; `make install` stages
`share/claude/skills/{bitcoin-wallet,bitcoin-operator,lightning-*}` and
`share/opencode/commands/*.md`. Verified: 5 skills × 3 agents install, the
loop is idempotent, and `bitcoin-wallet` lands in each agent dir.
