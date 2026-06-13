---
id: FEAT-265
type: feature
priority: medium
status: done
---

# Docs: lightning daemon system-default; close out the phased rollout

## Description

**As a** reader of the lightning man page and project docs
**I want** the documented default to match the code (system) post-3.1.0
**So that** the whole stack reads as "system by default, --user to opt out"

FEAT-264 flips the runtime default; this aligns the prose and removes the
"lightning is phased / 3.1.0 pending" note added to CLAUDE.md in 3.0.0.

## Implementation

- `share/man/man1/lightning-daemon.1` — the `enable` entry (and the
  sub-command mode note) describe `--system` as default, `--user` as the
  rootless opt-in.
- `CLAUDE.md` §1 — update the 3.0.0 daemon-posture paragraph: lightning now
  also defaults system (3.1.0); drop the "deferred to 3.1.0" wording.

## Acceptance Criteria

1. `lightning-daemon.1` states `--system` as the `enable` default and no
   longer calls `--user` the default. Proven by `manpages.bats` grep
   assertions (if the page exists) or by review.
2. CLAUDE.md §1 records that all three surfaces (bitcoin, fulcrum, lightning)
   default to system as of 3.1.0. (Doc-only; checked by review.)
