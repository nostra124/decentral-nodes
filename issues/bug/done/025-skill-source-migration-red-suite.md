---
id: BUG-025
type: bug
priority: high
status: done
---

# unit suite red on master — skill-source migration left FEAT-019/048 tests on the old path

audit: 2026-05-30 (testing-surface audit, follow-on)

## Severity

**High.** Master tip `ad723c4` ("register bitcoin-wallet skill under
`.rpk/skills/`") shipped a **red** unit suite: 7 FEAT-019/FEAT-048 tests
(`tests/unit/bitcoin.bats`) failed because the commit moved the skill
source out from under them. This is the third instance of the
red-suite-on-master pattern (cf. BUG-020, BUG-021) and the live
motivation for BUG-023 (the release gate that now blocks tags on red).

## Observed

CI on PR #79 (whose own diff is unrelated — it only de-softens
assertions) failed with:

```
not ok 160 FEAT-019 — SKILL.md exists with the required frontmatter
not ok 161..165 …
#   grep: …/skills/bitcoin-wallet/SKILL.md: No such file or directory
not ok 166 FEAT-019 — opencode entry exists with matching content
```

`ad723c4` did:

```
.../SKILL.md => .rpk/skills/bitcoin-wallet.md   | 30 ++----
skills/bitcoin-wallet/opencode.md               | 104 ---------------------
```

i.e. it consolidated the old split source
`skills/bitcoin-wallet/{SKILL.md,opencode.md}` into a single manifest at
`.rpk/skills/bitcoin-wallet.md` (per the rpk PACKAGING contract,
CLAUDE.md §2) but did **not** update the tests that read the old paths,
and CI offers no pre-merge gate that those tests are green (the unit job
ran red and the tag/merge still went through — BUG-023's gap).

## Root Cause

The migration relocated the skill source and dropped the separate
`opencode.md`, but the FEAT-019/FEAT-048 tests hard-coded
`$BATS_TEST_DIRNAME/../../skills/bitcoin-wallet/SKILL.md` (and
`…/opencode.md`). The content all survived in the new manifest; only the
**path** moved and the **split-file** assumption was removed.

## Fix

Re-point the six SKILL.md assertions at the canonical
`.rpk/skills/bitcoin-wallet.md`. Replace the now-obsolete
"opencode entry exists" test (the file was intentionally folded into the
single manifest) with a guard that asserts the **single canonical
source** exists and the **legacy split files do not** — so a regression
that re-introduces the old layout is caught. The manifest already
contains everything the assertions check (frontmatter, the four design
principles, the 1.33.0 verb set, the `--mainnet` guardrail, the
mnemonic/secret guardrails, and the vendored-BIP paths), so no content
changes were needed.

## Regression Protection

- `bats tests/unit/bitcoin.bats --filter 'FEAT-019|FEAT-048|BUG-025'`:
  all nine content/path tests pass against the new manifest; the new
  BUG-025 guard fails if either legacy split file reappears.
- The one remaining local failure (`make install-skills-user is
  idempotent`) is the pre-existing, **CI-skipped** environmental case
  (no generated Makefile in CI → `skip`), and exposes a *separate*
  Makefile breakage from the same migration — filed as **FEAT-054**, out
  of scope here.

## Acceptance Criteria

- [x] FEAT-019/FEAT-048 SKILL.md tests read `.rpk/skills/bitcoin-wallet.md`.
- [x] A guard asserts the single canonical source and the absence of the
      legacy split files.
- [x] No skill-content change required; suite green (modulo the
      CI-skipped Makefile-idempotency env case → FEAT-054).
