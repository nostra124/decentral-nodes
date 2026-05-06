---
id: FEAT-011
type: feature
priority: medium
status: open
---

# `bitcoin wallet push` / `pull` between accounts

## Description

**As a** user with a wallet on multiple machines (one hot, one cold;
or laptop + server)
**I want** to push and pull my wallet repo between the SSH remotes
that `account` already manages
**So that** I can sign on one machine and broadcast on another
without copy-pasting PSBTs through other channels.

This builds on FEAT-010 (wallet is a git repo) and depends on
`account` having the target's SSH remote configured. The seed itself
is synced separately via `secret` — pushing the wallet alone is safe
(no key material moves).

## Implementation

Subcommands:

- `bitcoin wallet remote add <wallet> <account>` — resolves the
  account's SSH endpoint via `account`, configures it as a git remote
  named after the account.
- `bitcoin wallet push <wallet> <account>` — `git push` to the resolved
  remote.
- `bitcoin wallet pull <wallet> <account>` — `git pull --rebase` from it.
- `bitcoin wallet sync <wallet>` — pull then push to every configured
  remote.

Conflict policy on merge:

- `addresses`: union; index column resolves to max-of-both. Same-address
  use across accounts is acceptable in this project's model, so no
  gating is added on `derive` to prevent two accounts deriving the same
  index in parallel.
- `history`: union, dedup by txid.
- `psbts/<id>`: last-writer-wins; warn on conflict so the user notices
  a parallel sign attempt.
- `descriptors`: conflict is a hard error — a wallet's policy cannot
  legitimately diverge.

`account` becomes a hard dependency declared in `.rpk/depends/`.

## Acceptance Criteria

1. `bitcoin wallet remote add alice work` configures `work` as a git
   remote whose URL matches the SSH endpoint `account` exposes for the
   `work` account.
2. `bitcoin wallet push alice work` succeeds and the receiving side
   shows the new commits.
3. A simulated conflict on `addresses` between two `derive` operations
   on different accounts resolves to a union with the max index; no
   addresses are dropped, no error is raised.
4. A conflict on `descriptors` aborts the merge with a descriptive
   error.
5. `account` is listed in `.rpk/depends/`.
