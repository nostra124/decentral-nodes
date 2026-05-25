---
id: BUG-017
type: bug
priority: high
status: done
---

# rpk packaging scaffolding missing — depends empty, no type/package

audit: 2026-05-25

## Severity

**High.** `rpk install bitcoin` failed entirely:

- All 10 `.rpk/depends/*` files were empty (0 bytes) and
  non-executable, causing `Permission denied` on every dependency.
- `.rpk/type` and `.rpk/package` were missing, so the install
  was a no-op even after the depends error was bypassed.

## Observed

```
$ rpk install bitcoin
/Users/rene/.local/src/bitcoin/.rpk/depends/account: Permission denied
rpk - warn:  bitcoin - dependency 'account' failed (exit 126)
... (same for all 10 depends)
rpk - warn:  bitcoin - install was a no-op: no .rpk/package and
             no .rpk/install script.
```

## Root Cause

The `.rpk/` directory was partially scaffolded: the `depends/`
directory existed with stub files but none had executable
permissions or actual content. The required `.rpk/type` and
`.rpk/package` files had never been created.

## Fix Plan

1. Made all `.rpk/depends/*` executable.
2. Wrote proper dependency-check scripts using the platform-
   dispatcher pattern for OS binaries (`command -v` + `rpk
   platform` case) and the `rpk status` pattern for rpk
   package dependencies.
3. Created `.rpk/type` with `user`.
4. Created `.rpk/package` following the standard skeleton,
   using `./configure --prefix="$TARGET"` plus direct file
   copies (bypassing the Makefile's internal stow, since rpk
   handles stow).

## Regression Protection

`rpk depends bitcoin` runs all 10 scripts and exits 0.
`rpk install bitcoin` completes depends + package + stow.

## Acceptance Criteria

- [x] `rpk depends bitcoin` shows all 10 deps passing.
- [x] `rpk install bitcoin` succeeds and installs the bundle.
- [x] `bitcoin version` returns the installed version.
