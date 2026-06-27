---
name: audit
description: |
  Walk the shipping code's behavior and verify that every
  observable capability traces back to a feature or bug
  file. Run this periodically (at minimum every release, or
  every 30 days, whichever is sooner) and after any large
  refactor. Trigger when the user asks for an audit, a
  traceability check, a "are we still on contract" review,
  or when filing a new feature reveals adjacent
  undocumented behavior.
---

# `audit` skill

## 1. The invariant

> Every observable behavior of the shipping software is documented
> by a closed feature (`issues/feature/done/`) or a closed bug
> (`issues/bug/done/`).

The roadmap-and-done discipline (`skills/milestones.md`) only pays
off if this invariant actually holds. If `done/` files describe
behavior that doesn't exist, or if shipping behavior has no `done/`
file, the trail breaks and the institutional memory is fiction.

Audits are how we re-anchor the trail to reality.

## 2. When to audit

| Trigger | Why |
|---|---|
| Every release | The release is the natural checkpoint. Audit before tagging — easier to fix while context is fresh. |
| Every 30 days | If releases are sparse, time-bounded audits prevent drift. |
| After a large refactor | Refactors tend to delete or merge behavior without a paper trail. |
| When filing a feature reveals adjacent surface | "I'm filing FEAT-X for behavior Y; while I'm here, is Z also documented?" |
| When a user reports "X is undocumented" | Reactive, but still a valid trigger. |

If none of these have happened in 30 days and an audit has not run,
file FEAT-NNN for "audit overdue" and run one.

## 3. The four checks

An audit walks the surface area and asks four questions. Each one
has a different remediation if it fails.

### 3.1 Forward trace: surface → done/

For every public surface (CLI command, flag, plugin under
`libexec/bitcoin/`, configuration variable, exit code documented in
the man page), find at least one file in `issues/feature/done/` or
`issues/bug/done/` that introduced or modified it.

Sources of truth for the surface area:
- `bin/bitcoin` `command:*` functions and their `help:*` siblings
- `libexec/bitcoin/*` entry-point scripts
- `share/man/man1/bitcoin.1` (if present)
- `docs/bitcoin-walkthrough.md` (if present)
- `tests/unit/bitcoin-*.bats` assertions (these define the contract)

**Failure mode:** "behavior exists, no `done/` file."
**Remediation:** File a backfill feature documenting what the
behavior is and that it pre-existed. Tag it
`priority: low, status: open` and assign it to the next roadmap.
Don't try to retro-fit a "shipped" status — the audit itself is
the artefact that proves the behavior exists.

### 3.2 Reverse trace: done/ → surface

For every file in `issues/feature/done/` and `issues/bug/done/`,
verify the behavior it describes still exists in the shipping code.

**Failure mode:** "`done/` file describes behavior that no longer
exists."
**Remediation:** Either:
- Behavior was *intentionally* removed: file BUG-NNN documenting
  the regression. The fix is either to restore the behavior
  (regression bug) or to file a follow-up feature documenting the
  deliberate removal and pointing at the original done/ file. Add
  a one-line note to the original done/ file pointing at the new
  file. Never delete the done/ file.
- Behavior was *accidentally* removed: regular bug, follow
  `skills/bugs.md`. Restore the behavior; the test added in §3 of
  that skill prevents future drift.

### 3.3 Test trace: tests → done/

For every assertion in `tests/unit/*.bats` and
`tests/vectors/*.t`, find a `done/` file that justifies it.

**Failure mode:** "test asserts a contract with no `done/` file."
**Remediation:** Either the test is the contract (rare — the
contract should normally be the feature file) and we backfill the
feature, OR the test is over-specifying and should be loosened.
The audit is the right time to make that call.

### 3.4 Roadmap trace: open ROADMAP-*.md → reality

For every `issues/ROADMAP-X.Y.Z.md` that exists, verify:
- Every item it lists has a corresponding open file in
  `issues/feature/` or `issues/bug/`.
- No item is already de-facto shipped (i.e. the behavior is in
  master but the issue file hasn't moved to `done/`).
- The release-gate criteria are still meaningful (no stale
  references to defunct tooling).

**Failure mode:** "ROADMAP lists an item that's already shipped."
**Remediation:** Move the issue file to `done/`, flip status,
remove the item from the ROADMAP. This is the cleanup §3 of
`skills/milestones.md` should have caught.

## 4. How to run the audit

A complete audit produces a single document at
`issues/audit/YYYY-MM-DD.md` with the findings. The document is
itself a kind of feature file — it has a frontmatter, a body, and
acceptance criteria for the backfill work.

### 4.1 Setup

```sh
mkdir -p issues/audit
$EDITOR issues/audit/YYYY-MM-DD.md   # use today's date
```

Frontmatter:

```markdown
---
type: audit
date: YYYY-MM-DD
auditor: <name or agent id>
status: open
---

# Audit YYYY-MM-DD

## Surface walked

- bin/bitcoin commands: <list>
- libexec/bitcoin/*: <list>
- man page sections: <list>
- test files: <list>

## Findings

(per check)

## Backfill work

(linked FEAT-NNN / BUG-NNN files for each remediation)
```

### 4.2 Walk

For each item under "Surface walked", record the matching
`done/` file or mark it `MISSING` with a one-line note. The output
is a flat list — readability beats cleverness here.

Use grep aggressively:

```sh
grep -l '<feature-keyword>' issues/feature/done/ issues/bug/done/
```

### 4.3 Findings

For every `MISSING`, file the backfill issue per `skills/features.md`
or `skills/bugs.md`. Tag each one with `audit: YYYY-MM-DD` in its
body so a reverse search ("what came out of the last audit?") is
one grep away.

Assign each backfill issue to a roadmap per `skills/milestones.md`.
Low-priority backfills typically go to the next minor; high-
priority ones (regressions, removed behavior, security gaps) get
pulled into the next patch.

### 4.4 Close

When all backfill issues are filed:

```markdown
status: open → status: closed
```

The audit file moves nowhere — it stays at
`issues/audit/YYYY-MM-DD.md` permanently. Old audits are the
project's history of what was looked at and when. **Never delete an
audit file**, even one with no findings ("audit ran clean" is a
finding worth recording).

## 5. Reading prior audits

`issues/audit/` is sorted by date. A new audit starts by reading
the previous one to see whether its backfill items have all been
addressed. If any are still open, they migrate forward — either
re-listed in the new audit or simply re-prioritised in the
roadmaps.

## 6. Audit vs. review

| Tool | Scope | Cadence | Output |
|---|---|---|---|
| audit (this skill) | Whole repo. Are done/ files real? | Periodic | `issues/audit/YYYY-MM-DD.md` |
| `/review` (a slash-command in some sessions) | One PR | Per-PR | Inline comments on the PR |

Audits run *across* PRs; reviews run *within* a PR. They overlap
in spirit (both check that the change is honest) but they answer
different questions. Don't substitute one for the other.

## 7. Checklist (copy when running an audit)

```
Setup:
- [ ] issues/audit/YYYY-MM-DD.md created with frontmatter

Surface walked:
- [ ] bin/bitcoin command:* — every command mapped to a done/ file
- [ ] libexec/bitcoin/* — every plugin mapped to a done/ file
- [ ] tests/unit/*.bats — every assertion mapped to a done/ file
- [ ] tests/vectors/*.t — every assertion mapped to a done/ file
- [ ] share/man/man1/*.1 — every section mapped to a done/ file
  (if man page exists)

Findings:
- [ ] Forward gaps (§3.1) recorded
- [ ] Reverse gaps (§3.2) recorded
- [ ] Test gaps (§3.3) recorded
- [ ] Roadmap gaps (§3.4) recorded

Backfill:
- [ ] FEAT-NNN / BUG-NNN filed for each gap
- [ ] Each backfill assigned to a roadmap
- [ ] Each backfill body tagged "audit: YYYY-MM-DD"

Close:
- [ ] Audit file frontmatter status: closed
- [ ] Audit file stays in issues/audit/ (not moved, not deleted)
- [ ] Audit summary in the next standup / PR / release notes
```
