---
name: version
description: |
  Bump the `bitcoin` package version. Use when releasing a
  patch / minor / major: edit the source-of-truth file,
  update the bats version assertion, append to the SHA
  ledger, tag the commit. Trigger when the user asks to
  "cut a release", "bump the version", "publish vX.Y.Z",
  or to move a completed roadmap milestone into a release.
---

# `version` skill

## 1. Source of truth

The current version is the single semver string in the file
`VERSION` at the repo root. Every other artefact derives from it:

- `bin/bitcoin` reads `VERSION` at startup. When run from a dev
  tree it resolves to `$repo/VERSION`; when installed it resolves
  to `$PREFIX/share/bitcoin/version` (a copy installed by
  `make install` from `VERSION`).
- `tests/unit/bitcoin-*.bats` asserts `$BITCOIN_BIN version` equals
  the literal expected for the release.
- `.rpk/versions` (note the plural) is the append-only ledger of
  `<version>\t<commit-sha>` pairs.
- `configure` validates that `VERSION` exists and is semver-shaped
  before writing the Makefile.

Never edit `share/bitcoin/version` directly — it is rebuilt from
`VERSION` by `make install`.

## 2. Semver discipline

| Bump | When |
|---|---|
| MAJOR `X.0.0` | Breaking CLI contract change (a subcommand removed or its meaning changed). |
| MINOR `1.Y.0` | New subcommand, new flag, new test contract surface, or a backward-compatible behaviour added. |
| PATCH `1.0.Z` | Bug fix that restores previously documented behaviour. No new contract. |

Each release should correspond to one of the `issues/ROADMAP-X.Y.Z.md`
files. If the ROADMAP file does not exist, draft it first — release
discipline is "ROADMAP first, code second".

## 3. The bump procedure

Run these steps in order. They are intentionally manual — the
`make package` target automates the last three but requires the
rest to be done first.

### Step 1 — confirm the release gate

Open `issues/ROADMAP-<target>.md` and verify every issue listed has
been moved to its `done/` directory and its status flipped to
`done`. If anything is still `open` or unmoved, stop and finish that
work before bumping.

After the bump lands, the roadmap file is removed (`git rm
issues/ROADMAP-<target>.md`) — the milestone is complete and git
history is the permanent record. See `skills/milestones.md` §2.5.

### Step 2 — edit `VERSION`

```sh
echo "1.0.2" > VERSION   # adjust the digits to the target
```

### Step 3 — update the bats version assertion

`tests/unit/bitcoin-*.bats` contains:

```bash
@test "bitcoin version returns <OLD>" {
    run "$BITCOIN_BIN" version
    [ "$status" -eq 0 ]
    [ "$output" = "<OLD>" ]
}
```

Replace both `<OLD>` occurrences with the new version. (FEAT-020
will eventually move this to read `VERSION` directly; until then
the literal is the contract.)

### Step 4 — run the test suite

```sh
make check-unit
```

All bats tests must pass against the new version. If the version
test fails, double-check that `VERSION` and the bats literal match.

### Step 5 — commit, tag, ledger

The `make package` target does steps 5a–5c in one shot:

```sh
make package VERSION=1.0.2
```

which:
- 5a. Appends `1.0.2\t<HEAD-sha>` to `.rpk/versions`.
- 5b. Re-writes `VERSION` to `1.0.2` (idempotent if you did step 2).
- 5c. `git add VERSION .rpk/versions && git commit -m "package 1.0.2" && git tag v1.0.2`.

If you prefer to commit by hand (e.g. you want a different commit
message), do the equivalent manually and skip `make package`.

### Step 6 — push

```sh
git push --follow-tags
```

`--follow-tags` is important — the release tag is what consumers
pin against.

## 4. Hotfix from a non-tip commit

If you need a `1.0.Z+1` from an older tag (security fix):

```sh
git checkout -b hotfix/1.0.Z+1 v1.0.Z
# apply the fix
# run the bump procedure above
git checkout master
git merge hotfix/1.0.Z+1
```

The ledger entry will record both versions in order; the tag
sequence remains monotonic.

## 5. Rollback

A published tag is never deleted. To revert a bad release, cut a
new patch that reverts the offending commits:

```sh
git revert <bad-commit>
make package VERSION=1.0.Z+1
```

Do not retag or rewrite the `.rpk/versions` ledger.

## 6. Checklist (copy this into your PR description)

```
- [ ] All issues in ROADMAP-X.Y.Z are done/ and status=done
- [ ] VERSION contains the new semver
- [ ] bats version assertion updated
- [ ] make check-unit passes
- [ ] .rpk/versions has the new <version>\t<sha> line
- [ ] tag vX.Y.Z exists and points at the package commit
- [ ] git push --follow-tags has been run
```
