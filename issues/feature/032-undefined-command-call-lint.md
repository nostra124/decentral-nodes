---
id: FEAT-032
type: feature
priority: medium
status: open
---

# Lint: detect `command:<name>` invocations where `<name>` isn't defined in the same file

audit: 2026-05-13

## Description

**As a** maintainer reviewing a bitcoin PR
**I want** a static check that catches "undefined function name"
defects (the BUG-013 / BUG-014 / BUG-016 family) at lint time
**So that** the next instance of this defect class is found
before CI rather than during the next milestone.

The audit's "Hardening proposal" — three closed bugs (BUG-013,
BUG-014, BUG-016) all share the shape "code calls
`command:<name>` where `<name>` doesn't exist as a defined
function". Bash doesn't catch this; the failure surfaces only
when the broken branch is reached.

A simple grep-and-set-difference check at lint time would catch
the entire defect class:

```sh
# Pseudocode
for f in bin/bitcoin libexec/bitcoin/*; do
    defined=$(grep -oE '^(command:|[a-z][a-z0-9_:-]*\(\))' "$f" \
              | sed 's/().*//; s/^command://')
    invoked=$(grep -oE 'command:[a-z0-9_-]+' "$f" \
              | sed 's/^command://')
    for name in $invoked; do
        if ! grep -qxF "$name" <<< "$defined" \
           && ! grep -qxF "command:$name" <<< "$defined"; then
            echo "$f: command:$name invoked but not defined"
        fi
    done
done
```

Wire this into `make lint` (or a new `make lint-cmd-names`
target). CI runs `make lint` already (via shellcheck).

## Acceptance Criteria

1. `make lint` (or equivalent) catches the BUG-016 defect on
   master (assuming BUG-016 isn't fixed yet) — i.e. the lint
   step exits non-zero with `bin/bitcoin: command:bip32-create
   invoked but not defined`.
2. After BUG-016 is fixed, the lint step exits 0.
3. A regression test asserts the lint script reports a known-bad
   fixture (a tiny script with an undefined `command:foo` call).
