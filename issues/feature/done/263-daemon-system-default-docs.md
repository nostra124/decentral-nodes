---
id: FEAT-263
type: feature
priority: medium
status: done
---

# Docs & posture: system is the default daemon mode, `--user` the opt-in

## Description

**As a** reader of the man pages and project docs
**I want** the documented default daemon posture to match the code (system)
**So that** I deploy correctly and know `--user` is the rootless escape hatch

FEAT-261/262 flip the runtime default; this aligns the prose so the man
pages and CLAUDE.md don't keep advertising `--user` as the default.

## Implementation

- `share/man/man1/bitcoin-daemon.1` — the `enable`/verb entries describe
  `--system` as default, `--user` as the rootless opt-in.
- `share/man/man1/fulcrum.1` — same for the fulcrum service verbs.
- `CLAUDE.md` §1/§6 — a sentence noting the default deployment posture is
  system; `--user` is the educational/personal/rootless opt-in; lightning's
  flip is phased (3.1.0).

## Acceptance Criteria

1. `bitcoin-daemon.1` and `fulcrum.1` state `--system` as the default for
   `enable`. Proven by `manpages.bats` grep assertions.
2. Neither man page still calls `--user` "the default". Proven by a negative
   grep.
3. CLAUDE.md §1 (or §6) records the system-default posture and the phased
   lightning rollout. (Doc-only; checked by review.)
