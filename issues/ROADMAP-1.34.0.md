# ROADMAP 1.34.0

Maintenance milestone: realign the agent-skill surface with the
shipping CLI and the upstream rpk skill convention.

## Features

- [x] **FEAT-048** — refresh the `bitcoin-wallet` agent skill to the
  1.33.0 verb set and add the Raven install target (Claude + Raven
  share `SKILL.md`; opencode uses `opencode.md`). Fixes the dangling
  opencode `install-skills-user` symlink and corrects the `--mainnet`
  guardrail. See `issues/feature/done/048-*.md`.

## Bugs

- none

## Release gate

- [x] All issues above are in `done/` with status `done`.
- [x] `tests/unit/bitcoin.bats` FEAT-048 regression tests pass.
- [x] No new forward gaps (see `issues/audit/2026-05-30.md`).

Bump type: **MINOR** (new test-contract surface + new install target,
backward compatible). 1.33.0 → 1.34.0.
