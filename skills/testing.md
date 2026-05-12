---
name: testing
description: |
  Run the right test suite at the right point in the change
  lifecycle (local edit → pre-push → CI). Three test tiers
  (unit / sit / pit) and three execution surfaces (manual,
  pre-push hook, GitHub Actions). Local tests are the
  priority; CI is the mandatory merge gate. Trigger when
  the user wants to "run the tests", "set up CI", "add a
  pre-push hook", diagnose a failed run, or understand which
  suite covers which contract.
---

# `testing` skill

## 0. Two non-negotiables

1. **Local-first.** Every change must be validated by running tests
   *on the developer's machine* before it leaves the checkout. The
   pre-push hook enforces this — never bypass it (`--no-verify` is
   forbidden on this repo). If you need to push WIP, use a draft PR
   so CI carries the load instead.
2. **CI is mandatory for merge.** No PR may be merged with a red or
   missing CI run. The `tests / bats unit tests` workflow is the
   merge gate; failing or skipped runs block merge regardless of how
   green the local run was. If CI is broken, the fix is to repair
   CI — not to merge around it.

These two work together: local runs catch issues fast and cheap; CI
is the team-wide invariant that the change is reproducible outside
the author's machine. Skipping either erodes the contract.

Related skills:
- `skills/bugs.md` — when CI fails, file a BUG and write the
  failing regression test before fixing.
- `skills/features.md` — when adding behaviour, write the
  acceptance tests before implementation.
- `skills/logging.md` — every new failure branch must log enough
  to diagnose the failure from the log alone.
- `skills/automerging.md` — arm auto-merge once the PR is
  review-ready; the loop on red CI lives here.

## 1. Test tiers

| Tier | Location | Tooling | Scope |
|---|---|---|---|
| unit | `tests/unit/*.bats` | `bats` | CLI dispatcher + per-subcommand contracts (`bitcoin version`, `bech32`, etc.). Fast, no network, no containers. |
| vectors | `tests/vectors/*.t` | `prove` (TAP) | BIP test vectors. Gated on FEAT-006 (sourceable `bitcoin.sh`); currently dormant. |
| sit | `tests/sit/` | `podman` | System Integration Tests. Container-based, exercise full install + wallet flow against a regtest backend. |
| pit | `tests/pit/` | `podman` | Production Integration Tests. Container-based; broader scenario coverage (multi-wallet, key migrations). Optional — directory may not exist. |

## 2. Execution surfaces

There are three places tests run, with **different selection rules**
at each:

### 2.1 Manual (local development)

Run any tier directly via `make`:

```sh
make check-unit       # bats tests/unit/*.bats
make check-vectors    # prove tests/vectors/*.t  (after FEAT-006)
make check-sit        # SIT against the regtest container
make check-pit        # PIT (if tests/pit/ exists)
make check            # unit + vectors
make check-all        # unit + vectors + sit + pit
```

Use this surface for tight TDD loops. Each target soft-skips when
its tooling is missing (e.g. `bats not installed; skipping`).

### 2.2 Pre-push hook (`.githooks/pre-push`)

Runs automatically on `git push` once wired up:

```sh
git config core.hooksPath .githooks   # one-time, per checkout
```

The hook detects the environment by tool availability and runs the
matching subset:

| Environment | Detection signal | Suites run |
|---|---|---|
| cloud sandbox (Claude.ai code, Codespaces, CI runner) | `command -v podman` fails | unit |
| desktop / dev VM with podman | `command -v podman` succeeds | unit + sit + pit (if dirs exist) |

The rule is "fail closed": a non-zero exit aborts the push so a
broken test cannot reach the remote. The pre-push hook is wired in
`.githooks/pre-push`; `make check-pre-push` invokes it directly for
debugging.

`configure` prints the one-time `git config core.hooksPath` hint
when it detects an unwired checkout.

### 2.3 GitHub Actions (`.github/workflows/test.yml`) — mandatory merge gate

Runs on every `pull_request` and on `push` to `master` / `main`.
**A green run of `tests / bats unit tests` is mandatory for merge.**
Treat a red or missing CI run as a hard merge blocker — no
exceptions, no "but it works on my machine".

Note that CI is the *second* safety net, not the first. Local tests
(§2.1 / §2.2) catch ~all preventable failures before they reach
the remote. CI exists to prove the change is reproducible *off* the
author's machine — same dependencies, clean checkout, deterministic
environment. If CI fails on a change that passed locally, something
about the change depends on the local environment; fix that, don't
retry the run.

Currently the workflow runs **unit tests only** — SIT and PIT need
podman-in-podman which the default runner doesn't ship. When that
changes, extend the matrix; do not silently regress to "unit only on
CI but full suite locally," that asymmetry hides bugs.

**On failure, the workflow posts the bats log as a PR comment.** This
is the contract that lets an assistant agent (the Claude Code agent
watching the PR) read failures via `mcp__github__pull_request_read
get_comments` without needing log-download permissions. The relevant
step is `Comment failure log on PR` in the workflow file — keep its
`tail -c 60000` cap intact (GitHub rejects comments larger than
65 535 bytes).

If you add new test tiers to CI, mirror the comment-on-failure step
for each one so failure surfaces stay machine-readable.

### 2.3.1 CI completion is always a reaction event

An agent watching the PR (per `skills/automerging.md` Mode B) **must
react to every CI completion webhook — green and red.** Treat the
arrival of a `<github-webhook-activity>` event with a terminal
conclusion (`success`, `failure`, `cancelled`, `timed_out`,
`action_required`) as a turn that requires output. Silently waiting
on a red event is a session hang; the user has no way to tell
whether the watcher is alive.

The full both-completions contract — including the one-line
acknowledgement requirement and the per-conclusion reaction matrix —
lives in `skills/automerging.md` §3b.1.

## 3. Triage workflow when CI fails

1. Acknowledge the failure webhook in the conversation (run id,
   conclusion, commit SHA). See `skills/automerging.md` §3b.2.
2. Open the PR; the most recent failure comment is at the bottom.
3. The comment includes: workflow-run URL, commit SHA, last ~60 KB
   of `bats.log`.
4. If the log is truncated, click the workflow-run URL or
   `gh run view --log-failed <run-id>` for the full output. The
   workflow also uploads `bats.log` as an artifact.
5. Reproduce locally with the same command the workflow ran:
   `bats tests/unit/*.bats`.
6. File `BUG-NNN` per `skills/bugs.md`, write the failing
   regression test *before* the fix, then fix, commit, push. The
   pre-push hook re-runs unit tests before the push; CI re-runs
   and the next webhook event arrives (back to §2.3.1).

## 4. Adding a new test

| You wrote a … | Put it in | Then |
|---|---|---|
| Regression for a fixed bug (CLI contract) | `tests/unit/bitcoin.bats` | Reference the BUG-NNN id in a comment above the test |
| BIP-vector translation | `tests/vectors/<bip>.t` | Add to plan count (FEAT-022 makes this automatic) |
| Container scenario | `tests/sit/<scenario>.bats` | Document the regtest invariants it relies on |
| Long-running / multi-wallet scenario | `tests/pit/<scenario>.bats` | Add a `README.md` if it's the first PIT file |

After adding tests, run the suite that owns the new file *and* the
ones it depends on (e.g. a new PIT test should pass on a clean
desktop with `make check-all`, not just `make check-pit`).

## 5. Common failures and remedies

| Symptom | Cause | Fix |
|---|---|---|
| `bitcoin version returns X.Y.Z` fails | `VERSION` not in sync with bats literal | Follow `skills/version.md` step 3 |
| `bats: command not found` in CI | runner image missing bats | `sudo apt-get install -y bats` step (already in workflow) |
| `podman: command not found` on local push | hook detected cloud sandbox correctly; SIT/PIT skipped | No action — that's the cloud-sandbox path |
| PR comment never posted on failure | workflow lacks `pull-requests: write` permission | Check `permissions:` block at workflow top |
| Comment truncated | log >60 KB | Click the workflow-run URL for the full log |

## 6. Checklist (copy into PR description for any test-touching change)

In order. Each row is a prerequisite for the next — do not skip
ahead. The local-first rows are non-negotiable; the CI row is the
mandatory merge gate.

```
Local (do these first, in order):
- [ ] Pre-push hook wired: git config core.hooksPath .githooks
- [ ] make check-unit passes on the dev machine
- [ ] If podman is available: make check-all passes (adds sit + pit)
- [ ] git push succeeds (the pre-push hook re-runs unit tests)

CI (mandatory merge gate, must be green):
- [ ] Workflow tests / bats unit tests is green on the PR head commit
- [ ] No outstanding failure comment from a prior red run (if there
      was one, the fix landed — comment is historical context, not
      a deferred TODO)
```

**Do not merge** with any local item unchecked or with CI red /
missing / pending.
