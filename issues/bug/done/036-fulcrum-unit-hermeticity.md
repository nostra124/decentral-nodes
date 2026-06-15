---
id: BUG-036
type: bug
priority: high
status: done
---

# fulcrum unit test is non-hermetic: BUG-031 macos account test fails on a host with a real `_fulcrum` account

## Severity

**High.** `tests/unit/fulcrum.bats` is the unit contract for the
`fulcrum` command and runs on every push. On a host that has already
run a live `fulcrum enable --system` deploy — which creates a real
`_fulcrum` service account — one test fails deterministically even
though the code under test is correct. A unit test must not depend on
the ambient state of the host it runs on.

## Observed

On a developer box where `_fulcrum` exists (`id _fulcrum` →
`uid=309(_fulcrum) …`):

```
$ bats tests/unit/fulcrum.bats
…
not ok 28 BUG-031: enable (system, macos) creates a hidden UID-296 _fulcrum dscl account
```

The test asserts the `dscl . -create /Users/_fulcrum …` calls were
logged. They never run, so the assertions fail.

## Root Cause

`daemon:_ensure_account` (`libexec/fulcrum/daemon`) gates account
creation on an existence check:

```sh
id "$user" >/dev/null 2>&1 && return 0
```

The test's `setup()` mocks `systemctl`, `launchctl`, `dscl`,
`dseditgroup`, `usermod`, `chown`, etc. into a PATH shim, but it does
**not** mock `id`. So `id _fulcrum` resolves against the real host. On
a box with a live deploy the account already exists, `_ensure_account`
short-circuits, the dscl-create branch is skipped, and the BUG-031
macos test's account-creation assertions fail.

This is a test-hermeticity defect, not a defect in the daemon: the
short-circuit is correct production behavior (don't re-create an
existing account). The test environment simply leaked host state.

## Fix

Add an `id` stub to the `setup()` MOCKBIN shims in
`tests/unit/fulcrum.bats` so any **username** lookup reports
"not found", while **flag** forms pass through to the real `id`:

```sh
case "$1" in
  -*) exec /usr/bin/id "$@" ;;   # id -u / id -un (operator/launchctl domain)
  "") exec /usr/bin/id ;;
  *)  exit 1 ;;                  # id <username> → "not found"
esac
```

With this, `id _fulcrum` reports not-found regardless of host state, so
the dscl-create branch always runs and the BUG-031 assertions hold. The
`-*` / `""` passthrough preserves the operator lookups the other tests
rely on (`op="${USER:-$(id -un)}"` and the `id -u` launchctl domain
target), so no other test changes behavior.

## Acceptance criteria

1. `bats tests/unit/fulcrum.bats` is fully green (0 failures) on a host
   that already has a real `_fulcrum` account from a live deploy.
2. No production code changes — the fix is test-only; the
   `daemon:_ensure_account` short-circuit is unchanged.
3. The `id` stub passes flag forms (`id -u`, `id -un`) through to the
   real `id` so the operator/group tests still pass.

## Regression test

The existing test
`BUG-031: enable (system, macos) creates a hidden UID-296 _fulcrum dscl account`
is the regression: it failed against the un-stubbed setup on a host with
a real `_fulcrum` account and passes once the `id` stub is in place.
