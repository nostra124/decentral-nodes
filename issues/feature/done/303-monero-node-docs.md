---
id: FEAT-303
type: feature
priority: medium
status: shipped
---

# `monero` man pages + node walkthrough

## Description

**As a** user learning the Monero node surface
**I want** man pages for every `monero` node verb and a walkthrough doc
**So that** the install → daemon → config flow is documented to the same
standard as `bitcoin`/`lightning`

## Implementation

- `share/man/man1/monero.1` — parent page: synopsis, the node verbs, SEE ALSO
  (`bitcoin(1)`, `lightning(1)`), pointer to the walkthrough.
- `share/man/man1/monero-<verb>.1` — per-verb pages for `install`, `daemon`,
  `config` (and the `daemon` subverbs as the others do it). Alias `.so` includes
  where a verb shares a page.
- `docs/monero-walkthrough.md` — install (verified tarball) → `daemon enable`
  (system) → `status`/`monitor` → `config list/set`, including the `--user`,
  `--stagenet`, and `--prune` paths and the secret/account model.
- Wire the pages into `make install` (the `share/man/man1/monero-*.1` glob is
  already covered once FEAT-299 adds `monero` to `PACKAGES`).

## Acceptance Criteria

1. Every shipped `monero` node verb has a man page; `man <file>` renders each
   without error (portable invocation per BUG-039). Proven by a `monero.bats`
   (or `manpages.bats`) test that walks the verbs.
2. The parent `monero(1)` lists the verbs and renders.
3. `docs/monero-walkthrough.md` exists and covers install → daemon → config,
   including `--user`/`--stagenet`/`--prune`. Proven by a doc-presence/grep test.
