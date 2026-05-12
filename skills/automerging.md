---
name: automerging
description: |
  Arm GitHub auto-merge on a PR so it merges itself the
  moment CI goes green. The author keeps the loop closed on
  red CI by filing bugs and fixing them test-first. Trigger
  when a PR is review-ready and the only thing left is CI;
  when you want a hands-off merge once green; or when
  diagnosing why a PR did not auto-merge despite green CI.
---

# `automerging` skill

## 1. Why auto-merge

After a PR is review-ready, the only remaining gate is CI. Without
auto-merge, a human has to come back, watch the run finish, and
click Merge. That delay buys nothing — CI is the same regardless
of who is watching. Auto-merge collapses the wait to zero while
preserving the gate: GitHub still refuses to merge until CI is
green.

The contract this skill encodes:

1. **Enable auto-merge once the PR is review-ready** (not earlier).
2. **If CI fails: file a BUG, write the failing test, fix, push.**
   Do not retry, do not bypass, do not merge around it.
3. **Loop until green.** Auto-merge stays armed across pushes — a
   new commit re-arms the merge condition.

## 2. Prerequisites

Before enabling auto-merge:

| Prerequisite | How to check |
|---|---|
| PR is not a draft | The "Ready for review" button has been clicked |
| Acceptance criteria are met (per `skills/features.md` or `skills/bugs.md`) | Self-review the PR checklist |
| Local pre-push hook has passed | `git push` succeeded without `--no-verify` |
| No merge conflicts with the base branch | GitHub shows "This branch has no conflicts" |

Auto-merge will sit and wait if any of these are missing, so
strictly speaking they are not blockers for *arming* the merge —
but if you arm it and then find one of these unmet, you waste a
loop on yourself. Check first.

## 3. Enabling auto-merge

Via the GitHub MCP tool:

```
mcp__github__enable_pr_auto_merge
  owner: nostra124
  repo: bitcoin
  pullRequestNumber: <N>
  mergeMethod: squash | merge | rebase
```

For this repo the default merge method is `squash` (keeps the
mainline linear; the PR body becomes the squashed commit message).
Use `merge` when the PR's commit history is itself meaningful
(e.g., the bugs TDD workflow's "failing test, then fix" two-commit
pair you want preserved). Use `rebase` only when explicitly asked.

Once armed, GitHub will:

1. Wait for all checks to complete.
2. If all required checks are green, merge using the configured
   method.
3. If any required check is red, leave the PR unmerged and the
   auto-merge armed (a new push will re-trigger the wait).
4. If the PR goes back to draft, disarm auto-merge.

## 4. When CI fails

This is the loop that keeps the contract honest. **No bypass.**

```
CI red  ──►  read the PR-comment failure log  ──►  file BUG-NNN
                                                        │
                                                        ▼
   push  ◄──  test green locally  ◄──  fix  ◄──  failing regression test
    │
    ▼
   CI re-runs automatically  ──►  green?  ──► auto-merge fires
                                    │
                                    └──► red → back to top of loop
```

Detail per step:

1. **Read the PR comment.** The workflow posts the last ~60 KB of
   `bats.log` as a PR comment on failure (see `skills/testing.md`
   §2.3). That comment is the diagnostic surface — read it first.
2. **File BUG-NNN.** Follow `skills/bugs.md`. Even if the fix is
   one line, the bug must exist so the regression is traceable.
   Acceptable shortcut: if the CI failure is *only* due to an
   unrelated flake that has happened before and you have already
   filed it, link the existing bug instead of filing a duplicate.
3. **Write the failing regression test.** Per `skills/bugs.md` §3,
   commit the test *before* the fix.
4. **Fix.** Minimum change. No drive-by refactors.
5. **Push.** The pre-push hook re-runs unit tests locally. CI
   re-runs automatically.
6. **Wait.** Auto-merge stays armed; you do not need to re-arm.
   If CI is now green, the merge fires.

## 5. Disarming

To disarm auto-merge (e.g. you want to add another change):

```
mcp__github__disable_pr_auto_merge
  owner: nostra124
  repo: bitcoin
  pullRequestNumber: <N>
```

Marking the PR back to draft also disarms it. After more changes,
mark ready-for-review and re-enable auto-merge.

## 6. What auto-merge does NOT do

- It does **not** approve the PR. If the repo has required
  approvals, those still need a human reviewer. This repo
  currently does not require approvals; if that changes, update
  this section.
- It does **not** bypass branch protection. Required checks are
  still required.
- It does **not** retry flaky CI. A red check leaves the PR
  unmerged until a new push triggers a re-run.
- It does **not** rebase against `master`. If a conflict appears
  while waiting, you must rebase / merge manually, push, and the
  wait resumes.

## 7. The forbidden bypasses

If CI is failing and you find yourself thinking any of the
following — stop and read this section.

| Temptation | Why it's wrong | Do this instead |
|---|---|---|
| Merge without CI green (admin force-merge) | Breaks the merge gate. Whatever you ship is unrunnable for someone. | Fix CI per §4. |
| Use `--no-verify` to bypass the pre-push hook | Local catches what CI catches; bypassing locally means you push known-broken code. | Run the suite. If it's broken, fix it. |
| Re-run the same red CI and hope it flips green | Hides intermittent failures that bite later. | File a flake bug. Don't merge until you understand it. |
| Disable the failing test | The test is the contract. Disabling it changes the contract silently. | Either the code is wrong or the test is wrong — fix one, justify which. |
| Merge a "trivial fix" without a regression test | This is exactly the path that causes the bug to come back. | Write the test first (`skills/bugs.md`). |

## 8. Checklist (use when arming auto-merge)

```
- [ ] PR is not draft
- [ ] PR body links the FEAT-NNN or BUG-NNN being resolved
- [ ] Local pre-push hook passed
- [ ] No merge conflicts with master
- [ ] mergeMethod chosen (squash unless TDD commit history matters)
- [ ] enable_pr_auto_merge called
```

After CI runs:

```
- [ ] CI green: auto-merge fired, PR closed
- [ ] CI red:   BUG-NNN filed, failing test committed, fix pushed,
                loop until green
```
