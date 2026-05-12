---
name: logging
description: |
  Emit logs at the right level — debug, info, warn, error —
  using the per-script helpers already defined in
  `bin/bitcoin` and each `libexec/bitcoin/<plugin>`.
  Trigger when adding a new code path that might fail,
  diagnosing a silent failure, or reviewing PRs for log
  coverage. Use this skill to decide which level applies
  and to standardise the message shape.
---

# `logging` skill

## 1. Why we log

Logs are the contract between the running program and the human (or
agent) trying to understand it. Every code path that can fail
silently is a debugging tax paid every time it does. **A bug that
can't be reproduced from logs alone usually points at missing logs
upstream of the failure point.**

For this repo, "enough logs to identify the issue" means:

- Every error path emits at least one `error` or `fatal` line.
- Every `warn` line names the condition and its consequence.
- Every `info` line is something a user wants to see during a
  normal run.
- Every `debug` line is something a developer wants to see while
  diagnosing.

## 2. The four levels

| Level | Helper | Suppressed by | Colour | Use for |
|---|---|---|---|---|
| debug | `debug "msg"` | default off; on via `-d` / `SELF_DEBUG=1` | none (stderr only) | Loop iteration values, function entry/exit, intermediate hashes — anything that helps a maintainer reconstruct the run. |
| info | `info "msg"` | `-q` / `SELF_QUIET=1` | yellow | Normal progress milestones in a long operation. Not every line — only ones a human wants to see during a normal run. |
| warn | `warn "msg"` | nothing | red | Recoverable problem. The program continued, but the caller should know. Example: cache miss, retry, soft-skip. |
| error | `error "msg"` | nothing | red bold | Unrecoverable problem the caller chose not to exit on. If the function is exiting too, use `fatal` / `die` (both wrap an error message with `exit`). |

`fatal "msg" [exitcode]` and `die "msg" [exitcode]` exit after
logging. Use them only when continuing would be wrong.

All helpers write to `stderr` so stdout stays usable as pipeable
output (which is the contract for most subcommands).

## 3. Message shape

Each helper prefixes the line with `<SELF>: <level> - ` where
`$SELF` is the script's basename. Do not duplicate the prefix.

Good:
```bash
warn "bech32 charset mismatch at position $p"
```

Bad (duplicate prefix, wrong tense):
```bash
echo "bitcoin: warn - bech32 charset mismatch" >&2     # bypass helper
warn "we found a problem here"                          # too vague
```

Rules:
- Name the *condition*, not the *outcome*. "bech32 charset mismatch"
  is better than "could not decode".
- Include the value that triggered it. `at position $p`, `got
  $checksum`, `expected $version`. The reader should not have to
  re-run the script to understand the log.
- Use lowercase. No trailing punctuation.

## 4. The "enough logs" gate

Before a change leaves the checkout, walk every new branch and ask:

1. Can this branch fail?
2. If yes, does it emit at least one `warn` / `error` / `fatal` line
   that says *what* failed and *why* the program is taking this
   branch?

If either answer is no, add the log before pushing. This is
non-negotiable in the same way that `tests/unit/bitcoin.bats` is the
contract: silent failures undermine the whole testing pyramid
because the test never even tells you what to assert against.

## 5. Where the helpers live

Every entry-point script defines its own copy of these helpers — per
the no-shared-lib policy (CLAUDE.md §4). When adding a new
`libexec/bitcoin/<plugin>`, copy the canonical block from
`bin/bitcoin` lines 35–60 verbatim. Do not factor them out.

If you add a new level (do not without discussing first), update
every script in lockstep — and update this file.

## 6. Logging vs. user-facing output

`stderr` carries logs; `stdout` carries the program's output (e.g.
the bech32 string, the derived address). Never log to `stdout` — it
breaks the contract `cmd | next-thing`.

## 7. Checklist (copy into PR description if logging changed)

```
- [ ] Every new failure branch emits a warn/error/fatal line
- [ ] Every log line names the condition + offending value
- [ ] No log writes to stdout
- [ ] No duplicate `$SELF: level - ` prefix inside helper args
- [ ] If a new level was added, all libexec/* mirror it
```
