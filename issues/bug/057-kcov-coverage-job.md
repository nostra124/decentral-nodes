---
id: BUG-057
type: bug
priority: low
status: open
---

# `kcov coverage` CI job fails (exit 2 under kcov; stale build dir)

## Severity

**Low.** `kcov coverage` is a reporting job, not the merge gate (the gate
is `bats + pytest unit tests`). It does not block correctness — but it is
red and should be green.

## Why it surfaced now

The job declares `needs: test`, so it was **skipped in every prior run**
while the unit gate was red (BUG-056). Once BUG-056 landed and the gate
went green, `kcov coverage` ran for the first time and exposed its own
pre-existing breakage.

## Symptoms (run 28200454714, job 83540799237)

1. The `run coverage` step (`make coverage`) exits 2 with a wall of
   `bats-exec-test: line 185: printf: write error: Broken pipe` — bats's
   output pipe breaking under kcov instrumentation. `make coverage` runs:

   ```
   kcov --include-path=…bitcoin-node,…lightning-node --exclude-path=…/tests \
        $(BUILD_DIR)/coverage bats tests/unit/*.bats >/dev/null
   ```

2. The `summarize coverage` step and the HTML upload look at the stale
   path `build/bitcoin/coverage/…`, but the build dir is now
   `build/decentral-nodes/` (the rpk identity is `decentral-nodes`, not
   `bitcoin`). So even on success no artifact would be found
   (`No files were found with the provided path: build/bitcoin/coverage/`).

## Fix (sketch)

- Point the workflow's `summarize` + `upload-artifact` paths at
  `build/decentral-nodes/coverage/` (or derive from `rpk identity` /
  `$(BUILD_DIR)`), not the hard-coded `build/bitcoin/`.
- Diagnose the kcov+bats broken-pipe / exit-2. Candidates: a bats test
  that pipes into a short reader (`… | head`) raising SIGPIPE under
  kcov's instrumented bash; running bats without `--jobs`; or pinning a
  formatter. Reproduce locally with `make coverage` + kcov v43.
- Consider making the job `continue-on-error: true` in the interim so the
  coverage report is advisory (it is not the merge gate), mirroring the
  advisory shellcheck job.

## Notes

Filed after #126 (BUG-056) turned the gate green and the maintainer
opted to merge and track kcov separately rather than block on it.
