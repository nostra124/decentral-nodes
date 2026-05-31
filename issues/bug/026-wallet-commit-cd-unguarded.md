---
id: BUG-026
type: bug
priority: high
status: open
---

# wallet git-commit subshells `cd "$path"` without a guard — can commit into the wrong repo

audit: 2026-05-30 (testing-surface audit, follow-on)

## Severity

**High.** Every wallet verb that records state does so in a subshell of
the shape:

```sh
(
	cd "$path"
	git add <files>
	git -c user.email=wallet@bitcoin -c user.name=bitcoin \
		commit -q -m "wallet <verb>: …"
)
```

In `bin/bitcoin`, **8** of these `cd "$path"` statements have **no
`|| exit`/`|| return` guard** (lines 1496, 1535, 2500, 2547, 2783, 2821,
3643, 3826/3850 — `utxo freeze/unfreeze`, `wallet derive`,
`derive --walk`, `wallet label`, `label <kind>`, `wallet index`, and the
`remote`/`push` paths). If `cd "$path"` fails (the wallet dir is missing,
was removed mid-run, or is unwritable), the subshell **keeps going** and
`git add`/`git commit` execute in the **inherited working directory** —
which, for anyone running `bitcoin` from inside a git checkout, is that
checkout. The wallet's state is then committed into the wrong repository
under the `wallet@bitcoin` / `bitcoin` identity.

## Observed

During the 2026-05-30 session, concurrent `wallet derive` / `wallet
index` test runs (whose `XDG_DATA_HOME` wallet dir was being torn
down/recreated by an overlapping run) committed **into the live
`bitcoin` checkout**, producing rogue commits authored
`bitcoin <wallet@bitcoin>` with messages like:

```
04d83d6 wallet derive: alice/1 -> bc1qnjg0jd8228aq7egyzacy8cys3knf9xvrerkf9g
08df1db wallet index: alice
```

one of which became the parent of a pushed commit and had to be
rewritten out of history. The same failure mode is reachable in
production: run `bitcoin wallet derive <name>` from inside any git repo
at the moment the wallet dir is unavailable, and the derive commit lands
in *your* repo.

`watch` (line 3965) and the verb at 4038 already use
`cd "$path" || exit 1`, which is the correct pattern; the other eight do
not.

## Root Cause

`cd "$path"` is unchecked inside the commit subshell. A failed `cd` does
not abort the subshell (no `set -e` in that scope, and the `cd` exit
status is discarded), so subsequent `git` commands run against `$PWD`.

## Fix (proposed)

Guard every wallet commit subshell's `cd`:

```sh
( cd "$path" || { error "wallet <verb>: cannot enter $path"; exit 6; }
  … )
```

(or factor a single `_wallet_git "$path" <args>` helper that does the
guarded `cd` + fixed identity once, removing the repeated
`-c user.email=… -c user.name=…` boilerplate and the per-call risk).
Belt-and-braces: pass `git -C "$path"` instead of `cd`, so the working
tree is named explicitly and a bad path fails the `git` call rather than
silently retargeting `$PWD`.

## Regression Protection (test-driven, per skills/bugs.md)

A red-first test: invoke a wallet commit verb with `$path` pointing at a
**non-existent** dir while CWD is a throwaway git repo, and assert (a)
the verb exits non-zero with a clear error and (b) **no new commit
appears in the CWD repo**. This fails against the current unguarded code
(the commit lands in CWD) and passes once the `cd` is guarded.

## Acceptance Criteria

- [ ] All wallet commit subshells guard `cd "$path"` (or use `git -C`).
- [ ] A failed `cd`/missing wallet dir aborts the verb non-zero with a
      named error; no commit is made anywhere.
- [ ] Regression test: a commit verb run with a bad `$path` from inside
      an unrelated git repo makes **no** commit in that repo (red before
      the fix).
- [ ] No behaviour change on the happy path (wallet dir present).
