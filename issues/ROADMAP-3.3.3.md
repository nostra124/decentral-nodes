# Roadmap — 3.3.3 (patch)

Bug-fix-only release that gets CI back to green and verifies the
container integration suites. No new behaviour, no new flags, no new
commands (semver patch contract, skills/milestones.md §2.1).

The headline is **BUG-044**: the mandatory unit-test gate has been red
since the `-node` rename (`e732c2b`) because the tests still invoke the
old `bin/bitcoin` / `bin/lightning` names. Nothing else can merge green
until this lands, so it ships first as a patch.

---

## BUG-044 — unit tests still invoke the pre-`-node` binary names
**File:** `issues/bug/044-test-suite-node-rename.md`
**Effort:** ~moderate (mechanical path updates across tests/unit/*.bats,
plus a handful of `$SELF`-dependent assertion fixes)
The `bats + pytest unit tests` workflow is red on `master` and every PR:
the dispatchers were renamed to the `-node` suffix but the unit tests
still reference the removed `bin/<cmd>` paths (exit 127). Add a guard
that every `bin/<cmd>` path a test references resolves to an executable,
then update the suites to the `-node` names and the
`libexec/<cmd>-node/` layout.

## BUG-043 — SIT apache CGI account-API / LNURL / walkthrough suites
**File:** `issues/bug/043-sit-cgi-account-api-suites.md`
**Effort:** container/SIT harness work (`secret` in the image, apache
`.well-known/lightning/` routing, client LNURL verb stubs)
The `10_wellknown_api`, `05_lnurl_flow`, and `11_walkthrough` SIT suites
are still `skip`-ped against the live stack. Now unblockable in cloud
sessions thanks to the podman SessionStart hook (the container tiers can
actually run). Bring the three suites green end-to-end.

---

## Recommended order

```
BUG-044   first — restores the merge gate; everything else needs green CI
BUG-043   second — depends on a runnable container tier (podman hook)
```

## Release gate

- `bats tests/unit/*.bats` passes locally and the `bats + pytest unit
  tests` workflow is green on the release commit.
- `make check-sit` brings the three named SIT suites green (no residual
  `skip "… BUG-043"` markers).
- `VERSION` bumped to `3.3.3` per skills/version.md.
