# FEAT-054 — point Makefile skill install at the consolidated `.rpk/skills/` source

**Status:** open
**Milestone:** unscheduled

## Summary

Master `ad723c4` consolidated the skill source from
`skills/bitcoin-wallet/{SKILL.md,opencode.md}` into the single manifest
`.rpk/skills/bitcoin-wallet.md` (see BUG-025), but the **Makefile install
plumbing still globs the old split paths**:

- `package` / install (around lines 84–94) copies `$$skill/SKILL.md` and
  `$$skill/opencode.md` from `skills/<name>/` — neither exists now.
- `install-skills-user` (around lines 195–203) symlinks based on those
  same vanished files.

Net effect: `make install-skills-user` installs **nothing** for the
wallet skill. This surfaces as the `FEAT-019 AC#3 / FEAT-048 — make
install-skills-user is idempotent across all three agents` test failing
(it expects 3 installed links, gets 0). The test only runs where a
generated `Makefile` is present; CI **skips** it, so the breakage is
invisible to CI today.

## Proposal

Rework the Makefile (and mirror in `.rpk/package`) to install from the
single `.rpk/skills/<name>.md` manifest to all three agent destinations
(Claude dir, Raven dir, opencode `.md` command), matching the rpk
PACKAGING contract. Then the idempotency test passes wherever a Makefile
exists, and it should be promoted out of the `skip` path (or FEAT-051's
preflight made to assert the manifest source).

## Acceptance Criteria

- [ ] Makefile `package` + `install-skills-user` read `.rpk/skills/<name>.md`.
- [ ] `.rpk/package` mirrors the same source.
- [ ] `make install-skills-user` installs to all three agent dirs and is
      idempotent (the FEAT-019 AC#3 test passes with a configured build).
- [ ] No reference to the removed `skills/<name>/{SKILL.md,opencode.md}`.
