---
id: BUG-028
type: bug
priority: high
status: done
---

# tests workflow has no timeout/concurrency guards — hung jobs burn the Actions budget

## Severity

**High.** `.github/workflows/test.yml` sets no `timeout-minutes` and no
`concurrency` group. When the `bats unit tests` job slows or a test
blocks, the job sits `in_progress` for GitHub's default **360-minute**
ceiling instead of failing fast, and every new push to a PR starts an
additional full run without cancelling the superseded one. The result
is multiple multi-hour "zombie" runs consuming the repository's Actions
minutes — observed live as PRs #89/#90/#91 wedging on `bats` and
draining the budget — which in turn blocks merges and releases
(`release-tag` only fires on a `success` conclusion that never comes).

## Observed

`.github/workflows/test.yml` — neither job declares a runtime cap and
there is no concurrency control:

```
$ grep -nE 'timeout-minutes|concurrency' .github/workflows/test.yml
(no output)
```

PRs #89, #90, #91 each showed `bats unit tests` stuck at
`status: in_progress` for >10 minutes with `get_status` reporting
`state: pending` (no failure) — i.e. the job was not failing, it was
running unbounded. The shared `concurrency`-less config meant the
repeated pushes left several such runs alive at once.

## Root Cause

GitHub Actions defaults a job with no `timeout-minutes` to a 6-hour
limit, and with no `concurrency` group every event triggers an
independent run. `test.yml` relies on those defaults, so a single slow
or hanging unit test escalates into hours of billed runner time, and
rapid pushes multiply it.

## Fix Plan

`.github/workflows/test.yml`:
- Add a top-level `concurrency` block keyed on the ref with
  `cancel-in-progress: true`, so a new push cancels the previous run on
  the same PR/branch.
- Add `timeout-minutes` to both jobs (`unit`: 30, `lint`: 10) so a
  hang is bounded instead of running for 6 hours. The unit suite runs
  ~9 min (measured; slower under runner throttling), so 30 is headroom,
  not a tight SLA.
- Set `BATS_TEST_TIMEOUT: 120` for the bats step so an individual
  hanging test is killed and named, rather than wedging the whole job.

No change to what the suite tests; this is purely CI-execution hygiene.

## Regression Protection

A new `tests/unit/ci-workflow.bats` asserts the guards are present, so
they cannot silently regress:

```bash
setup() { export REPO_ROOT="$BATS_TEST_DIRNAME/../.."; }

@test "BUG-028 — tests workflow caps job runtime (timeout-minutes)" {
	# Both jobs (unit + lint) must declare a timeout.
	local n
	n=$(grep -cE '^[[:space:]]+timeout-minutes:' \
	        "$REPO_ROOT/.github/workflows/test.yml")
	[ "$n" -ge 2 ]
}

@test "BUG-028 — tests workflow cancels superseded runs (concurrency)" {
	grep -qE '^concurrency:' "$REPO_ROOT/.github/workflows/test.yml"
	grep -qE 'cancel-in-progress:[[:space:]]*true' \
	    "$REPO_ROOT/.github/workflows/test.yml"
}
```

Both assertions fail against the current (guard-less) workflow and pass
after the fix.

## Acceptance Criteria

1. `.github/workflows/test.yml` declares a top-level `concurrency`
   group with `cancel-in-progress: true`. Proven by
   `tests/unit/ci-workflow.bats`.
2. Both the `unit` and `lint` jobs declare `timeout-minutes`. Proven by
   the same test (count >= 2).
3. The bats step sets `BATS_TEST_TIMEOUT`. Proven by inspection / grep.
4. The workflow remains valid YAML and the suite is green. Proven by
   the `tests` run on the PR concluding (not hanging).
