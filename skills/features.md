---
name: features
description: |
  File a feature and implement it test-first. The contract
  for this repo is acceptance-criteria-driven development:
  every feature lands with the tests its acceptance criteria
  imply. Trigger when adding a new subcommand, a new flag, a
  new plugin under libexec/bitcoin/, or any change that
  introduces behaviour the user can observe.
---

# `features` skill

## 1. The rule

**No feature lands without acceptance criteria written first.**
Acceptance criteria are the contract — they say what "done"
means before code is written, so reviewers can check the work
against a fixed target instead of a moving one.

Tests are the executable form of those criteria. A feature
without tests is a feature you cannot defend in six months.

## 2. Lifecycle

```
idea  ──►  file FEAT-NNN  ──►  draft tests  ──►  implement
 (1)         (2)                 (3)             (4)
                                                  │
done/  ◄──  CI green  ◄──  push + open PR  ◄─────┘
 (8)         (7)             (5–6)
```

### Step 1 — idea

A feature begins as a *user-facing change*: a new subcommand, a
new flag, a new failure mode that becomes a clean error, a new
backend. If you cannot describe the change in the form "as a
<user>, I want <capability>, so that <outcome>" then it is not
a feature — it might be a refactor (no issue needed) or a bug
(see `skills/bugs.md`).

### Step 2 — file `FEAT-NNN`

Create `issues/feature/NNN-<slug>.md` with this frontmatter
and section structure:

```markdown
---
id: FEAT-NNN
type: feature
priority: high | medium | low
status: open
---

# <one-line summary>

## Description

**As a** <user>
**I want** <capability>
**So that** <outcome>

One or two paragraphs of context. Why this is in scope, what
related work exists, and what is explicitly out of scope.

## Implementation

The technical sketch. File paths, function names, the rough
algorithm. Concise — this is not the PR description; reviewers
will look at the diff for detail.

## Acceptance Criteria

Numbered, machine-checkable list. Each item should be testable
either by a unit test, an integration test, or a documented
manual procedure. If you cannot phrase an item as "we can prove
this by running X and seeing Y", refine it until you can.
```

Numbering: take the next free `NNN` across `issues/feature/` and
`issues/feature/done/`. Bugs and features share no numbering —
`BUG-008` and `FEAT-008` can coexist. Never reuse a retired
number.

Priority: features are always lower than the highest open bug.
The repo policy is **bugs before features at the same priority
level** (CLAUDE.md §3). When in doubt, file medium.

Milestone assignment: every feature is also added to the
appropriate `issues/ROADMAP-X.Y.Z.md` in the same commit as
the feature file. See `skills/milestones.md` for the
versioning rules and the shuffle protocol when an item moves
between roadmaps.

### Step 3 — draft tests

For each acceptance criterion, write the test(s) that will
prove it. Add them in the right tier per `skills/testing.md`
§1:

- New subcommand contract → bats test in `tests/unit/`
- New BIP vector compliance → a `.t` file in `tests/vectors/`
- Container/end-to-end behaviour → bats test in `tests/sit/`

Run the suite. The new tests *must fail* on the unmodified
code path — otherwise they are not testing the new behaviour.
This is the symmetric move to `skills/bugs.md` §3: a feature
test that passes before implementation is testing the wrong
thing.

Commit the failing tests in their own commit:

```sh
git commit -m "tests: acceptance criteria for FEAT-NNN (failing)"
```

This makes the contract visible in git history.

### Step 4 — implement

Make the smallest change that turns the failing tests green and
satisfies the acceptance criteria. Do not bundle unrelated
refactors. If you discover a bug while implementing, stop and
file BUG-NNN per `skills/bugs.md`.

Logging: every new failure branch needs a `warn` / `error` /
`fatal` line. See `skills/logging.md` §4.

### Step 5 — push

```sh
git push   # pre-push hook re-runs unit tests
```

### Step 6 — open PR

PR description must include:

- Link to `issues/feature/NNN-<slug>.md`
- Bullet summary of what's now possible that wasn't before
- Test plan with one checkbox per acceptance criterion
- Note any documentation / man-page changes

### Step 7 — CI green

Same gate as bugs: red CI blocks merge. See
`skills/automerging.md` for the auto-merge contract.

### Step 8 — move to `done/`

After merge:

```sh
git mv issues/feature/NNN-<slug>.md issues/feature/done/NNN-<slug>.md
# edit the file: status: open → status: done
```

Add an entry to `issues/ROADMAP-X.Y.Z.md` mapping the feature
to the release it shipped in. If the feature is closing a
roadmap milestone, double-check every other item on that
roadmap file is also done before declaring the milestone
complete.

## 3. Feature vs. bug — the boundary

| Symptom | File |
|---|---|
| Documented behaviour does something different from the docs | bug |
| Documented behaviour does the right thing but in a way that confuses users | feature ("clarify docs" or "rename flag") |
| Undocumented behaviour exists by accident and someone relied on it | feature ("specify X explicitly") |
| Undocumented behaviour is missing | feature |
| Test or vector that was supposed to run is failing | bug |
| Test or vector that was never written for a known gap | feature |

Edge cases: if a change crosses both, file the bug (TDD) and
let the feature be a follow-up. Never bundle bug + feature in
one issue.

## 4. Priority rules

| Priority | Definition |
|---|---|
| high | Required for the next milestone in `issues/ROADMAP-*.md`. |
| medium | Useful, no fixed deadline, no dependent work blocked. |
| low | Polish / convenience. |

Anything in `ROADMAP-X.Y.Z.md` is at least medium by definition.

## 5. Reading the existing feature log

`issues/feature/` holds open features; `issues/feature/done/`
holds shipped features. The frontmatter `status: done` is the
authoritative flag.

Examples worth reading before filing a new one:
- `issues/feature/006-bitcoin-sourceable-as-library.md` —
  small, well-scoped feature with one-line implementation
  guidance
- `issues/feature/021-bats-coverage-expansion.md` — feature
  that introduces multiple tests with concrete code
- `issues/feature/195-bitcoin-foundation-prep.md` — umbrella
  feature that lists sub-features (use sparingly)

## 6. Checklist (copy into PR description for any feature)

```
- [ ] FEAT-NNN file exists with Description / Implementation /
      Acceptance Criteria
- [ ] Acceptance-criteria tests committed BEFORE implementation
- [ ] Confirmed tests fail on unmodified code (output quoted)
- [ ] Implementation is minimum-viable; no unrelated refactor
- [ ] Every new failure branch logs (skills/logging.md)
- [ ] make check-unit green after implementation
- [ ] CI green on PR head commit
- [ ] Feature file moved to issues/feature/done/ with status: done
      after merge
- [ ] Roadmap file updated if this closes a milestone item
```
