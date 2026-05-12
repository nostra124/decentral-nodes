---
name: bugs
description: |
  File a bug and fix it test-first. The contract for this
  repo is TDD on bugs — every bug fix lands with a
  regression test that *demonstrably failed* against the
  broken code. Trigger when a defect is reported, when CI
  reports a regression, when triaging a user issue, or when
  you discover a latent bug while reading code.
---

# `bugs` skill

## 1. The rule

**No bug fix lands without a regression test that fails on the
broken code first.** This is test-driven development applied to
bugs: the test is the evidence the bug exists; the fix is the
evidence the bug is gone; the green test forever after is the
evidence it stays gone.

Skipping the failing-test step is forbidden, even for "obvious"
fixes. The "obvious fix" that has no regression test is the
fix that regresses six months later.

## 2. Lifecycle

```
identified  ──►  file BUG-NNN  ──►  write failing test  ──►  fix
   (1)              (2)                 (3)                  (4)
                                                              │
done/  ◄──  CI green  ◄──  push + open PR  ◄──  test passes  ◄┘
 (8)         (7)             (6)               (5)
```

### Step 1 — identified

A defect is either reported, surfaced by CI, or noticed during
review. The first action is to confirm it reproduces. If you
cannot reproduce, do not file a bug — file a feature for
"investigate X" instead and gather evidence.

If the defect surfaced via CI, the failure log is already in the
PR comment thread (see `skills/testing.md` §2.3). Quote the
relevant lines in the bug body.

### Step 2 — file `BUG-NNN` (and assign it to a milestone)

Bugs, like features, are assigned to a target release via
`issues/ROADMAP-X.Y.Z.md`. Critical bugs typically pull into the
next patch release; lower-priority bugs go to the next minor or
later. See `skills/milestones.md` for the assignment protocol.


Create `issues/bug/NNN-<slug>.md` with this frontmatter and
section structure:

```markdown
---
id: BUG-NNN
type: bug
priority: critical | high | medium | low
status: open
---

# <one-line summary>

## Severity

One sentence: who is affected, how badly, whether a workaround
exists.

## Observed

The smallest reproduction. File paths with line numbers, a
command that demonstrates the failure, or the failing test
output. Quote — do not paraphrase.

## Root Cause

Why the broken code is broken. If unknown, write "unknown — see
investigation in <link>" and stop here; do not guess.

## Fix Plan

The change set. List the files and what each change is.

## Regression Protection

The test(s) that will be added to catch this if it returns.
Include the actual test code.

## Acceptance Criteria

Numbered, machine-checkable list of conditions for closing the
bug.
```

Numbering: take the next free `NNN` across `issues/bug/` and
`issues/bug/done/`. Never reuse a retired number.

### Step 3 — write the failing test

Add the regression test to `tests/unit/bitcoin.bats` (or the
matching tier, see `skills/testing.md` §1). The test must
exercise the broken path *as a user would* — not the patched
internals.

Run the suite to confirm the test **fails on the broken code**:

```sh
make check-unit   # must show: not ok, with the new test failing
```

If the new test passes against unpatched code, it is not a
regression test for this bug. Tighten the assertion until it
fails for the right reason, then proceed.

Commit the failing test in its own commit *before* the fix:

```sh
git commit -m "tests: failing regression for BUG-NNN"
```

This is what makes the TDD provenance auditable. Reviewers can
check out the test commit and confirm the test fails.

### Step 4 — fix

Make the minimum change that turns the failing test green. Do
not refactor surrounding code, do not improve unrelated
behaviour, do not change unrelated tests. One bug, one fix.

If the fix is non-obvious, leave a single-line comment in the
code referencing the bug id (e.g. `# BUG-011: see issues/bug/done/`).

### Step 5 — test passes

```sh
make check-unit   # must show all green including the new test
```

If the test still fails, the fix is wrong. If unrelated tests
fail, you broke something else — revert and split the change.

### Step 6 — push + open PR

```sh
git push           # pre-push hook re-runs unit tests
```

PR description must include:

- Link to `issues/bug/NNN-<slug>.md`
- "Fixes BUG-NNN" in the body (helps cross-reference)
- The two-commit history (failing test, then fix) is acceptable;
  squashing is acceptable too if the failing-test commit's
  message is preserved in the merge commit body.

### Step 7 — CI green

CI must pass on the PR head commit. If CI fails, *do not* file
a new bug for the CI failure — diagnose whether it is:

- a flake (rerun once; if reflakes, file a separate bug for the
  flake)
- the same bug not actually fixed (back to Step 4)
- an unrelated regression you introduced (back to Step 4, fix
  both)

### Step 8 — move to `done/`

Once the PR is merged:

```sh
git mv issues/bug/NNN-<slug>.md issues/bug/done/NNN-<slug>.md
# edit the file: status: open → status: done
```

Land this in a separate commit so the file move is reviewable.
**Never delete a bug file** — even from `done/`. They are the
project's institutional memory.

## 3. When NOT to file a bug

| Situation | What to file instead |
|---|---|
| "X should do Y but doesn't" with no prior contract that it should | feature (see `skills/features.md`) |
| "X is slow" with no SLO | feature ("measure X latency") |
| "I don't understand the code" | nothing; ask in chat |
| "X failed once and I can't reproduce" | nothing; keep the log, watch for repeat |
| CI flake (one-off transient) | nothing on first occurrence; bug if it recurs |

## 4. Bug priority

| Priority | Definition |
|---|---|
| critical | Data loss, security exposure, or "all users blocked." |
| high | A documented path is broken for most users; no workaround. |
| medium | Edge case is broken; workaround exists. |
| low | Cosmetic or documentation-only. |

When in doubt, file higher and let the reviewer down-grade.

## 5. Reading the existing bug log

`issues/bug/` holds open bugs; `issues/bug/done/` holds resolved
bugs. The frontmatter `status: done` is the authoritative flag —
the directory is convenience. Tools that scan the tree should
key on the frontmatter.

Examples worth reading before filing:
- `issues/bug/done/008-bitcoin-bech32-broken.md` — long-form
  multi-issue bug with section structure
- `issues/bug/done/010-bech32-verify-checksum-undefined-functions.md`
  — short-form fix-with-regression-test bug
- `issues/bug/done/011-command-bech32-rejects-uppercase.md` —
  spec-divergence bug

## 6. Checklist (copy into PR description for any bug fix)

```
- [ ] BUG-NNN file exists with all required sections
- [ ] Failing regression test committed BEFORE the fix
- [ ] Confirmed test fails on broken code (artifact attached or
      output quoted)
- [ ] Fix is minimum-change; no unrelated edits
- [ ] make check-unit green after the fix
- [ ] CI green on the PR head commit
- [ ] Bug file moved to issues/bug/done/ with status: done after merge
```
