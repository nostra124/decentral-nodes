---
id: FEAT-195
type: feature
priority: high
status: open
---

# Bitcoin foundation prep — call only `account` + `config` + `secret` + `crypt` at runtime

## Description

**As a** maintainer preparing to extract `bitcoin` as its
own educational rpk package
**I want** `bin/bitcoin`'s call set cleaned up to the
established foundation contract
**So that** the extraction (FEAT-196) is mechanical and
the dependency declaration in `nostra124/bitcoin/.rpk/depends/`
is correct.

The educational completion of bitcoin (FEAT-006..019) plus
the cross-cutting pieces (FEAT-040 crypt openssl, FEAT-127
dht stamping references) define the feature surface. This
ticket is the standalone audit of `bin/bitcoin`'s sibling-
script calls and the cleanup before extraction.

## Implementation

### Today's deps

Per the original dep map: `bitcoin` calls `cache config
data scripts`. After all the cross-cutting work:

- `cache` — deleted entirely (FEAT-045). Verify-grep
  guards against re-introduction.
- `scripts` — deleted (FEAT-001 libexec migration). Verify
  no `scripts has` / `scripts list` calls.
- `data` — review every call site. Bitcoin's data usage is
  minimal (likely small key/identity TSVs); inline as direct
  file ops under `$XDG_DATA_HOME/bitcoin/`.
- `config` — kept (`bitcoin → config`).

### New deps after FEAT-006..019

The educational + feature work introduces:

- `account` — for wallet remotes (FEAT-011 push/pull).
- `secret` — for the seed (FEAT-010).
- `crypt` — for the BIP signing primitives once FEAT-040
  (`crypt openssl`) is the place primitives live; until
  then bitcoin's inlined `dc`/`openssl` math stays.

After cleanup: bitcoin calls **`account`, `config`,
`secret`, `crypt`** at runtime. `rpk` is deployment-only.

### Audit

    grep -wEn '(cache|check|data|hosts|repo|scripts|task|user)' bin/bitcoin

Should return no script-invocation matches after cleanup.
Calls to `account` / `config` / `secret` / `crypt` are
expected and kept.

### Cycle check

`account` / `config` / `secret` / `crypt` don't call
bitcoin → no cycle. (Verified by inspecting their dep
maps.)

### Soft system deps

System-level requirements probed at runtime per FEAT-039:

- `bitcoin-cli` (when local-bitcoind backend selected per
  FEAT-012) — soft, falls back to mempool / blockstream
  REST.
- `gpg` — only via `crypt`; not direct.
- `openssl` — for the `dc`-based math fallback if not
  routing through `crypt openssl`.
- `git` — for wallet repo (FEAT-010).
- `recsel`/`recfix` — for the rec-format sidecar queries
  if any (matches archive's pattern).

### CLAUDE.md template

`docs/templates/CLAUDE.md.bitcoin` follows the eight-section
structure from FEAT-193. The agent-skill pointer is
`bitcoin-wallet` (FEAT-019, already filed).

## Acceptance Criteria

1. `grep -wEn '(cache|check|data|hosts|repo|scripts|task|user)' bin/bitcoin`
   returns no script-invocation matches.
2. `bin/bitcoin help` lists the same surface as before
   (verbs introduced by FEAT-006..019 may have landed by
   the time this ticket runs; surface should be a superset
   of today's).
3. `account` / `config` / `secret` / `crypt` are the only
   sibling-script deps at runtime.
4. `docs/templates/CLAUDE.md.bitcoin` exists and follows
   the FEAT-193 eight-section structure.
5. Existing bitcoin smoke tests + `t/*.t` BIP vector
   tests pass after the refactor.
