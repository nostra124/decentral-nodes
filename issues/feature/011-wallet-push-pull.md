---
id: FEAT-011
type: feature
priority: medium
status: open
milestone: 1.27.0
---

## Progress (1.9.0 shipped — push/pull/remote-add only)

Three remote-management verbs landed:

- `bitcoin wallet remote add <wallet> <remote-name> <url>` —
  configures a git remote on the wallet repo (idempotent: replaces
  the URL if `<remote-name>` already exists).
- `bitcoin wallet push <wallet> [<remote>]` — `git push` the
  wallet's current branch to `<remote>` (default `origin`).
- `bitcoin wallet pull <wallet> [<remote>]` — `git pull --rebase`
  from `<remote>`, with the same `commit.gpgsign=false` hygiene
  the rest of the wallet code uses.

5 new bats tests use a local bare git repo as the "remote" — no
network or sibling tooling needed in the test sandbox. Every
failure path emits an `error` line per `skills/logging.md` §4.

### Deferred

- **`account` integration.** Original spec routed remote URLs
  through `bitcoin account get-ssh <name>`. This release takes
  the URL directly so the verbs work without the sibling
  package. A follow-up FEAT can wrap `account` once it's
  installable in the dev sandbox; the existing surface
  (`wallet remote add <wallet> <name> <url>`) is forward-
  compatible with `<url>` becoming an opt-out flag.
- **`wallet sync <wallet>`.** Pull-then-push to every configured
  remote. Trivial wrapper over the verbs that shipped, but
  deferred so this milestone stays focused on the primitives.
- **Custom merge resolvers.** The original spec called for
  `addresses`-union, `psbts/<id>` last-writer-wins, and
  `descriptors` as a hard-error conflict. These are useful
  *policy* layered on top of the *plumbing* this release ships.
  A follow-up FEAT can add a `.gitattributes` + custom merge
  driver.
- **`account` declared in `.rpk/depends/`.** Held until the
  account-resolved-SSH path actually lands.

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
