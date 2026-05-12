---
name: milestones
description: |
  Plan and execute releases via version-numbered backlog
  files at `issues/ROADMAP-X.Y.Z.md`. Each file is the
  canonical list of features and bugs going into one
  release; we develop one milestone per session run.
  Trigger when planning a new release, moving an item
  between releases, declaring a milestone complete, or
  deciding where to file a newly-discovered feature.
---

# `milestones` skill

## 1. The model

The repo plans by **version**, not by date or by board. Every
planned feature or bug fix is assigned to a target version, and
that assignment lives in a single text file:

```
issues/ROADMAP-<MAJOR>.<MINOR>.<PATCH>.md
```

The ROADMAP file is the **canonical backlog** for that release.
Three properties of the model that matter:

1. **Versioned, not dated.** A roadmap file commits to "what is in
   this release", not "when this release ships". The version is
   stable; the calendar is not.
2. **Per-file = per-release.** One file lists exactly one release's
   contents. There is no master backlog spanning multiple releases —
   each future release is its own file.
3. **Mirrors `done/` for traceability.** Every shipped feature lives
   in `issues/feature/done/` forever; every fixed bug lives in
   `issues/bug/done/` forever. The ROADMAP file is consumed at
   release time and removed, but the per-item files persist as
   the institutional record.

## 2. Lifecycle

```
PLAN                EXECUTE              CLOSE
                                          
file ROADMAP-X.Y.Z  ──►  implement  ──►  remove ROADMAP-X.Y.Z.md
   │  (per-session)        │   (one         (git history keeps it)
   ▼                       ▼    milestone        │
assign items                move features/        ▼
   │                       bugs to done/      done/ stays forever
   ▼                          │
shuffle if needed             │
   │                          │
   └──► update BOTH roadmaps  │
        when moving an item   │
```

### 2.1 Plan: create the roadmap file

When a future release is conceived (e.g. a set of related features
emerge from a review):

```sh
$EDITOR issues/ROADMAP-X.Y.Z.md
```

Required structure:

```markdown
# Roadmap — X.Y.Z (<patch|minor|major>)

Short paragraph: what this release is about. Mention any
prerequisite release.

---

## FEAT-NNN — <title>
**File:** `issues/feature/NNN-<slug>.md`
**Effort:** <line-count or "Xh">
<one-paragraph summary>

## BUG-NNN — <title>
**File:** `issues/bug/NNN-<slug>.md`
**Effort:** <line-count or "Xh">
<one-paragraph summary>

(repeat for each item)

---

## Recommended order

```
ITEM-A   (one-line why first)
ITEM-B   (one-line why second)
...
```

## Release gate

Hard requirements for marking the release complete:
- specific test invariants
- specific tools / commands that must exit 0
```

The semver bump implied by the version is the contract:

| Suffix | Meaning |
|---|---|
| .Z (patch) | Bug fixes only. No new behavior, no new flags, no new commands. |
| .Y.0 (minor) | New behavior added in a backward-compatible way. |
| X.0.0 (major) | Backward-incompatible change. Always discuss before filing. |

If you find yourself mixing a bug fix and a new feature in the
same roadmap file, you have the wrong version number. Split the
roadmap.

### 2.2 Assign: edit the FEAT/BUG file frontmatter

Each item in the roadmap exists as a standalone file at
`issues/feature/NNN-…md` or `issues/bug/NNN-…md`. The roadmap
links to that file. There is no other "assignment" mechanism —
the link from the roadmap to the item is the assignment.

When you create a new feature or bug that targets a known future
release, write the file and add it to the roadmap in the same
commit so the link is never dangling.

### 2.3 Shuffle: when an item moves

Reality intrudes. A feature planned for 1.1.0 turns out to be
larger than expected and slips to 1.2.0. A bug planned for 1.0.2
turns out to be a hot fix and is pulled forward into 1.0.1.

When moving an item between roadmaps:

1. **Remove** the item's section from the source roadmap.
2. **Add** it to the destination roadmap in the appropriate spot
   (note the new dependency order if any).
3. **Audit** all other files that reference this item — typically
   another roadmap's "depends on" prose, or another feature/bug
   file's narrative. Update those references in the same commit.
4. **Commit message** must name both files and the item id:
   `roadmap: move FEAT-021 from 1.1.0 to 1.2.0`.

Forgetting step 3 is the silent failure mode of this workflow.
A grep through all roadmaps for the item id before committing is
the cheap insurance.

### 2.4 Execute: one milestone per session run

The rule: **one session run lands one complete milestone.** Do not
half-land a roadmap and pick it up next session — the cost of
swapping the milestone context back in is high, and partial
milestones are a leading indicator of mis-scoped roadmaps.

Concretely, in a milestone session you:

1. Re-read the roadmap top to bottom.
2. Implement items in the recommended order per `skills/features.md`
   (tests before code) and `skills/bugs.md` (regression test before
   fix).
3. Run the release gate locally; everything must pass.
4. Bump the version per `skills/version.md`.
5. Move every per-item file to `done/` and flip its frontmatter
   `status: done`.
6. **Remove the roadmap file** (see §2.5).
7. Open the PR; let the auto-merge / watcher take it from there
   (`skills/automerging.md`).

If a session genuinely cannot complete a milestone — e.g. an
unforeseen bug requires its own multi-session investigation — the
right move is to *re-scope the roadmap* before ending the session.
Move the blocking item out (§2.3), update the version number if
the remaining scope no longer warrants the bump, and ship the
smaller milestone. Never leave a "half-done" roadmap in `issues/`.

### 2.5 Close: remove the roadmap file

When the release ships (i.e. the version bump commit lands on
`master` and the tag exists), delete the roadmap file:

```sh
git rm issues/ROADMAP-X.Y.Z.md
```

The git history is the permanent record of what the milestone
contained. The per-item files in `done/` are the per-feature
record. The roadmap file itself has done its job and adds noise
when left behind.

Do **not** add a `done/` directory for roadmaps. The two records
(git history + `done/` for items) are sufficient.

### 2.6 Items: feature and bug files persist in `done/`

`issues/feature/done/NNN-*.md` and `issues/bug/done/NNN-*.md` are
the project's institutional memory. **Never delete them.**

Their purpose is traceability: years later, when someone asks "why
does `bitcoin bech32` reject mixed case?", a grep through
`issues/bug/done/` lands on BUG-011 and the answer is one read
away.

The `status` frontmatter changes from `open` to `done` when the
file moves, but the file itself stays forever. Re-using a retired
number is forbidden (see `skills/features.md` §2 and
`skills/bugs.md` §2).

## 3. Where milestones plug into the other skills

| Skill | Connection |
|---|---|
| `skills/features.md` | Every feature is assigned to a milestone before implementation. Step 8 (move to done/) is also a milestone closure step. |
| `skills/bugs.md` | Same. Bug priority + milestone assignment together determine "what we work next". |
| `skills/version.md` | The version bump is the technical act of closing a milestone. Read both skills together when releasing. |
| `skills/automerging.md` | The merge of the milestone PR is when the release is "done". A green CI on the release PR triggers the merge. |
| `skills/audit.md` | Regular audits verify that the items in `done/` actually trace to behavior in shipping code. The roadmap-and-done discipline only pays off if `done/` is real. |

## 4. Reading the existing roadmaps

`issues/ROADMAP-*.md` lists every currently-planned future release.
The naming sorts naturally: `ROADMAP-1.0.1.md` precedes
`ROADMAP-1.1.0.md` precedes `ROADMAP-1.2.0.md`.

Examples worth reading before filing a new one:
- The pattern for a patch roadmap (bug fixes only)
- The pattern for a minor roadmap (features that respect existing
  contracts)
- How the "Recommended order" section captures dependencies between
  items in the same release

## 5. Checklist (copy into PR description for any milestone)

```
Plan (already done by the time the PR opens):
- [ ] issues/ROADMAP-X.Y.Z.md exists with every planned item listed
- [ ] Each item links to a real FEAT-NNN / BUG-NNN file
- [ ] Release gate is concrete (specific commands, exit codes)

Execute (this PR):
- [ ] Every item implemented per skills/features.md or skills/bugs.md
- [ ] Release gate passes locally
- [ ] VERSION bumped per skills/version.md
- [ ] Every per-item file moved to done/ with status: done
- [ ] issues/ROADMAP-X.Y.Z.md removed (git rm)

Merge (after green CI):
- [ ] Tag vX.Y.Z exists (created by make package or by hand)
- [ ] PR squashed/merged via skills/automerging.md
- [ ] Next roadmap file (if any) updated for items that slipped
```
