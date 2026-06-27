---
id: FEAT-313
type: feature
priority: high
status: done
milestone: 3.4.0
---

# Installed-tree (post-`make install`) test tier

## Summary

The unit suites run dispatchers straight from the dev tree
(`bin/<cmd>-node` + `SELF_LIBEXEC=…/libexec`), so they never exercise
what `make install` actually produces. That blind spot let BUG-058 ship
(installed nodes with zero verbs). Add a test tier that validates the
**staged/installed** tree.

## Acceptance criteria

1. A test (bats) that runs `./configure --prefix=<tmp> && make install`
   once, then for **every** dispatcher in `bin/`:
   - the installed `libexec/<cmd>/` contains ≥1 verb;
   - `<cmd> version` (run from the prefix, resolving its own
     `SELF_LIBEXEC`) prints `$(cat VERSION)`;
   - at least one real verb resolves (e.g. `help`/a known subcommand)
     rather than falling through to usage.
2. Runs in CI where `stow` is available; soft-skips when `stow` is
   absent.
3. Drives off the `PACKAGES`/`bin/` list so new nodes are covered
   automatically (no per-node hand-maintenance).

## Notes

Supersedes the minimal regression in BUG-058. This is the structural fix
for the "tests only cover dev-tree" gap; pair it with FEAT-314 (per-node
unit parity) so both the dev and installed surfaces are covered.
