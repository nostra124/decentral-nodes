---
id: BUG-023
type: bug
priority: high
status: done
---

# release-tag cuts the version tag on a red test suite

audit: 2026-05-30 (testing-surface audit)

## Severity

**High.** `.github/workflows/release-tag.yml` triggered on *every* push
to `master` and created the `vX.Y.Z` tag + GitHub Release purely from
`VERSION`, with **no dependency on `tests.yml`**. A red suite therefore
still shipped a tag — exactly the §11 bypass BUG-020 flagged, and how
**v1.34.0 was tagged while `bip174-p2pkh` was red** (BUG-021). The gate
the project documents (CLAUDE.md §9/§11) was not enforced for releases.

## Observed

`release-tag.yml` (before):

```yaml
on:
  push:
    branches: [master, main]
```

No `needs:` / `workflow_run` link to the `tests` workflow; the tag job
ran in parallel with (and independent of) the suite.

## Root Cause

The tag job keyed off the push event, not the test outcome. Two
workflows triggered by the same push raced; the tag was cut regardless
of whether `tests` passed, failed, or was still running.

## Fix

Re-trigger `release-tag` on the **`tests` workflow completing**, and gate
the job on success + push + release branch:

```yaml
on:
  workflow_run:
    workflows: ["tests"]
    types: [completed]
jobs:
  tag:
    if: >-
      github.event.workflow_run.conclusion == 'success' &&
      github.event.workflow_run.event == 'push' &&
      (github.event.workflow_run.head_branch == 'master' ||
       github.event.workflow_run.head_branch == 'main')
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.workflow_run.head_sha }}
      # … tag at head_sha …
```

`workflow_run` defaults to the default-branch tip, so the checkout and
`gh release create --target` are pinned to `head_sha` (the exact commit
the green suite ran against). Idempotency (skip if the tag/release
already exists) is unchanged.

## Regression Protection

- The tag job's `if:` cannot be satisfied unless `tests` concluded
  `success`, so a red suite can no longer produce a tag. The gating is
  the standard `workflow_run` pattern and the workflow YAML validates;
  the live proof is the next release cutting only after green.
- Follow-on: now that `tests` also has a `lint` job (FEAT-049), the
  release waits on lint too.

## Acceptance Criteria

- [x] `release-tag` triggers on `workflow_run` / `tests` completion.
- [x] The tag job runs only on `success` + `push` + master/main.
- [x] The tag/release targets `workflow_run.head_sha`.
- [x] Idempotent re-run behaviour preserved.
