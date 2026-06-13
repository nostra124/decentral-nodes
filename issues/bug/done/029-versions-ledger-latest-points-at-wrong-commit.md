---
id: BUG-029
type: bug
priority: high
status: done
---

# `.rpk/versions` newest entry points at the wrong commit — `rpk update` installs a stale tree

## Severity

**High.** The newest `.rpk/versions` entry (`2.2.0`) recorded the wrong
commit SHA, so `rpk update bitcoin` — which installs
`command:versions | tail -1` — packaged the **2.1.0** tree under the
label 2.2.0. A fresh install of the latest release therefore self-reports
`2.1.0` at runtime and is missing FEAT-059 (the 2.2.0 fulcrum Electrum
backend). No data loss; the workaround (`rpk install bitcoin:HEAD`)
exists but is non-obvious. Affects anyone upgrading to 2.2.0.

## Observed

```
$ rpk update bitcoin        # installs command:versions | tail -1 == 2.2.0
$ rpk version bitcoin
2.2.0                       # install record / bundle dir
$ bitcoin version
2.1.0                       # but the packaged tree is 2.1.0
```

The ledger line vs. the commit it names:

```
$ grep '^2.2.0' .rpk/versions
2.2.0	3baeebcfc0560bb1364c4d1f090fb34a39682eb5
$ git show 3baeebcfc0:VERSION
2.1.0                       # 3baeebc is the 2.1.0 merge (PR #96), not 2.2.0
```

The 2.2.0 bump commit is `f70209c` (`feat: 2.2.0 — fulcrum Electrum
backend (FEAT-059)`), whose `VERSION` is `2.2.0` and which contains
`libexec/fulcrum`.

## Root Cause

`rpk`'s version-bump verbs append `<label>\t$(git rev-parse HEAD)` to
`.rpk/versions` (recording the *parent* HEAD), then `rpk:fix_version_sha`
amends the line so the SHA points at the bump commit itself. For the
`2.2.0` bump (added in `f70209c`) the `fix_version_sha` correction never
took effect, so the line kept the parent SHA `3baeebc` (the 2.1.0 merge).
The earlier 2.x entries (`2.0.0`, `2.1.0`) show the same one-release-behind
drift, but only the newest entry is what `rpk update` installs, so that is
the entry this fix corrects. The recent stable entries (1.27–1.30, 1.34.x)
are consistent, which is why the defect only surfaced at 2.2.0.

This is metadata-only: the 2.2.0 *software* (the `VERSION` file, the code)
was always correct, so no version bump is warranted — the fix makes the
ledger tell the truth about which commit 2.2.0 is.

## Fix Plan

`.rpk/versions`:
- Repoint `2.2.0` from `3baeebcfc0560bb1364c4d1f090fb34a39682eb5`
  (VERSION 2.1.0) to `f70209c880c1b0221baf1702d55b046bc9386ac0`
  (VERSION 2.2.0, contains FEAT-059).

`.github/workflows/test.yml`:
- Add `fetch-depth: 0` to the unit-test job checkout so the regression
  test can resolve a ledger SHA to its `VERSION` file (`git show
  <sha>:VERSION` needs the object, not just shallow HEAD).

## Regression Protection

`tests/unit/bitcoin.bats` gains a test that mirrors rpk's own install
selection — `command:versions | tail -1` for the label, `command:commit`
for the SHA — and asserts the named commit's `VERSION` equals the label:

```bash
@test "BUG-029 — newest .rpk/versions entry maps to a commit whose VERSION matches its label" {
	repo="$BATS_TEST_DIRNAME/../.."
	ledger="$repo/.rpk/versions"
	label="$(grep -v '^#' "$ledger" | cut -f1 | grep -vE '^[[:space:]]*$' \
	         | sort -u -V | tail -1)"
	sha="$(awk -F'\t' -v v="$label" '$1==v{print $2; exit}' "$ledger")"
	run git -C "$repo" show "$sha:VERSION"
	[ "$status" -eq 0 ]
	[ "$(printf '%s' "$output" | tr -d '[:space:]')" = "$label" ]
}
```

Fails against the broken ledger (`3baeebc` → VERSION 2.1.0 ≠ 2.2.0),
passes after the repoint. Guards every future release: the newest ledger
entry must resolve to a commit that self-reports its own label.

## Acceptance Criteria

1. The newest `.rpk/versions` entry resolves to a commit whose `VERSION`
   equals the label. Proven by the BUG-029 test.
2. `rpk install bitcoin:2.2.0` packages a tree that reports `2.2.0` and
   ships `libexec/fulcrum` (FEAT-059). Proven by re-install.
3. The unit-test CI job fetches full history so the ledger test can
   resolve commits. Proven by `fetch-depth: 0` in `test.yml`.
