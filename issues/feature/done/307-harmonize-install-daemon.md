---
id: FEAT-307
type: feature
status: shipped
---

# Harmonize install + daemon management across the four commands

## Description

**As an** operator of the combined stack
**I want** the same install + daemon-management surface on bitcoin, lightning,
fulcrum, and monero
**So that** muscle memory transfers and there are no per-command surprises

The four commands had diverged: install lived top-level for monero/fulcrum but
under `daemon` for bitcoin/lightning; only fulcrum exposed top-level daemon
verbs (`fulcrum enable`, …); `restart`/`space` weren't universal.

## Harmonized contract

- **install** is a **top-level** verb on every command: `bitcoin install`,
  `lightning install`, `fulcrum install`, `monero install`. The old
  `<cmd> daemon install` keeps working as an alias (bitcoin/lightning/fulcrum).
- **daemon lifecycle** is `<cmd> daemon <verb>` everywhere, core set
  `enable / disable / start / stop / status / monitor` (already consistent
  after FEAT-305). Command-specific extras stay (bitcoin share-cookie/password,
  lightning restart/run, fulcrum admin verbs, monero --prune).
- Fulcrum's **top-level daemon shims removed** (`fulcrum enable/disable/start/
  stop/status/monitor/space`) — `fulcrum daemon <verb>` is canonical. `fulcrum
  install` + the admin verbs (info/stats/ban/…) stay top-level.

(Path-layout harmonization — common user paths across platforms — is a
separate follow-up.)

## Implementation

- `libexec/bitcoin/install`, `libexec/lightning/install`: thin top-level
  wrappers delegating to the daemon plugin's install verb.
- Removed `libexec/fulcrum/{enable,disable,start,stop,status,monitor,space}`
  symlinks.
- BUG-053 folded in: `bitcoin daemon status` detects the **running** node's
  datadir (covers an external node) and reports `up but unauthorized` (with a
  share-cookie hint) when a node listens but its cookie isn't readable.
- Man pages: `fulcrum(1)` lifecycle documented as `fulcrum daemon <verb>`.

## Acceptance Criteria

1. `<cmd> install` works top-level on all four; `<cmd> daemon install` still
   works on bitcoin/lightning/fulcrum. Proven by streamline/lightning/fulcrum/
   monero bats.
2. `fulcrum <verb>` (top-level lifecycle) is gone; `fulcrum daemon <verb>`
   works. Proven by fulcrum.bats.
3. `bitcoin daemon status` reflects the running node, not the empty managed
   datadir. Proven by streamline.bats (BUG-053).
