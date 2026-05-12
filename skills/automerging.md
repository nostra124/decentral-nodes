---
name: automerging
description: |
  Land a PR the moment CI is green — either via GitHub
  auto-merge (preferred when the repo allows it) or by an
  agent watching CI activity and merging manually. The
  author keeps the loop closed on red CI by filing bugs and
  fixing them test-first. Trigger when a PR is review-ready
  and the only thing left is CI; when arming auto-merge or
  the manual-merge watcher; or when diagnosing why a PR did
  not land despite green CI.
---

# `automerging` skill

## 0. Repository policy: which mode is active

This repository uses **manual merge by an agent watching the PR**,
because repository-level auto-merge (Settings → General → Pull
Requests → *Allow auto-merge*) is currently **off**. The agent is
subscribed to the PR via `mcp__github__subscribe_pr_activity` and
merges on the first green CI run.

If the policy changes to *Allow auto-merge*, §3 (Enabling
auto-merge via the GitHub MCP tool) becomes the preferred path and
§3b (Manual merge by an agent) becomes the fallback. Either way,
the CI-fail loop in §4 is unchanged — that is the contract this
skill exists to defend.

## 1. Why "merge the moment CI is green"

After a PR is review-ready, the only remaining gate is CI. Without
automation, a human has to come back, watch the run finish, and
click Merge. That delay buys nothing — CI is the same regardless
of who is watching. The two modes below collapse the wait to zero
while preserving the gate: nothing merges until CI is green.

The contract this skill encodes:

1. **Arm the merge once the PR is review-ready** (not earlier),
   whichever mode is active.
2. **If CI fails: file a BUG, write the failing test, fix, push.**
   Do not retry, do not bypass, do not merge around it.
3. **Loop until green.** Auto-merge stays armed across pushes; the
   manual-merge watcher receives webhook events for each new run
   and reacts on the eventual green one.

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

## 3. Mode A — GitHub auto-merge (when the repo setting is on)

Currently **inactive** for this repo. To switch to this mode, an
admin must enable *Settings → General → Pull Requests → Allow
auto-merge*, then update §0 above.

When active, arm via the GitHub MCP tool:

```
mcp__github__enable_pr_auto_merge
  owner: nostra124
  repo: bitcoin
  pullRequestNumber: <N>
  mergeMethod: SQUASH | MERGE | REBASE
```

For this repo the default merge method is `SQUASH` (keeps the
mainline linear; the PR body becomes the squashed commit message).
Use `MERGE` when the PR's commit history is itself meaningful
(e.g., the bugs TDD workflow's "failing test, then fix" two-commit
pair you want preserved). Use `REBASE` only when explicitly asked.

Once armed, GitHub will:

1. Wait for all checks to complete.
2. If all required checks are green, merge using the configured
   method.
3. If any required check is red, leave the PR unmerged and the
   auto-merge armed (a new push will re-trigger the wait).
4. If the PR goes back to draft, disarm auto-merge.

## 3b. Mode B — manual merge by an agent watching CI (active here)

This is the path this repo uses today, because `Allow auto-merge`
is off at the repo level. The contract is the same — wait for
green, then merge — but the wait is held by an agent receiving PR
webhook events instead of by GitHub's auto-merge daemon.

Setup, in order:

1. PR author confirms the PR is non-draft and the local pre-push
   hook passed (same §2 prerequisites as Mode A).
2. Author (or agent) calls
   `mcp__github__subscribe_pr_activity` with the PR number. This
   wires `<github-webhook-activity>` events into the conversation.
3. Agent waits passively. **Do not poll**: webhook events arrive
   when CI completes, and polling wastes context.
4. On the green CI event, agent calls `mcp__github__merge_pull_request`
   with `mergeMethod: SQUASH` (or `MERGE` if TDD commit history must
   be preserved, per §3).
5. On a red CI event, agent goes to §4 (the CI-fail loop). The
   subscription stays live across re-pushes; do not re-subscribe.

If the agent's session ends before CI completes, re-subscribing on
resume picks the stream back up — the contract is the same.

Why this mode is acceptable: the merge action still gates on
"green CI on the PR head commit" and still emits a normal merge
commit / squash commit. The only thing that changes versus Mode A
is *who* presses the button.

Why this mode is **not** as good: it depends on the agent's
session being live (or re-subscribed) when CI finishes. The
preferred long-term state is Mode A; flip the repo setting when
convenient.

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
6. **Wait.** Mode A: auto-merge stays armed across pushes; no
   re-arming needed. Mode B: the PR-activity subscription stays
   live; the agent receives the next CI event automatically.

## 5. Disarming

Mode A: disarm via the GitHub MCP tool:

```
mcp__github__disable_pr_auto_merge
  owner: nostra124
  repo: bitcoin
  pullRequestNumber: <N>
```

Marking the PR back to draft also disarms it. After more changes,
mark ready-for-review and re-enable auto-merge.

Mode B: unsubscribe via `mcp__github__unsubscribe_pr_activity`.
Marking the PR back to draft does *not* automatically unsubscribe
the watcher, but the watcher will not merge a draft — the merge
call would fail. Still, prefer to unsubscribe explicitly when the
PR is no longer ready, to keep the event stream clean.

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

## 8. Checklist (use when arming the merge, either mode)

```
Common:
- [ ] PR is not draft
- [ ] PR body links the FEAT-NNN or BUG-NNN being resolved
- [ ] Local pre-push hook passed
- [ ] No merge conflicts with master
- [ ] mergeMethod chosen (SQUASH unless TDD commit history matters)

Mode A (if `Allow auto-merge` is on for the repo):
- [ ] enable_pr_auto_merge called

Mode B (current default for this repo):
- [ ] subscribe_pr_activity called for this PR
- [ ] Agent session will remain live (or will be re-subscribed)
      long enough to receive the CI completion event
```

After CI runs:

```
- [ ] CI green: PR merged (Mode A: by GitHub; Mode B: by agent
      via merge_pull_request); PR closed
- [ ] CI red:   BUG-NNN filed, failing test committed, fix pushed,
                loop until green
```
