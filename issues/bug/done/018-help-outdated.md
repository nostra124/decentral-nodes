---
id: BUG-018
type: bug
priority: medium
status: done
---

# Help text outdated — missing commands, libexec plugins not findable

audit: 2026-05-25

## Severity

**Medium.** `bitcoin help` still showed the 1.22-era command surface:

- Listed deprecated `bech32*` commands as current (they were
  removed in 1.24.0).
- Had an empty `bip350` section with only "TODO: register in
  bitcoind wallet".
- Missing all 1.23-1.24 commands: `backend`, `descriptor`,
  `wallet`, `tx`, `utxo`, `tax`, `price`, `daemon`.
- `bitcoin help daemon` failed with "'daemon' is not an bitcoin
  command" because `command:help` only checked builtin functions,
  not libexec plugins.
- Typo: "frontent" instead of "frontend".

## Observed

```
$ bitcoin help
…
  bip173 commands: bech32 [-m], bech32-verify …
  bip350 commands:
  TODO: register in bitcoind wallet

$ bitcoin help daemon
'daemon' is not an bitcoin command
```

## Root Cause

The `command:help` function's main-usage text had not been updated
since the 1.22 era. The `$1` dispatching branch used `has command
$1` which only finds builtin `command:*` functions, not libexec
plugins. No `help:daemon` function existed.

## Fix Plan

1. Replaced the main help text with a concise grouped listing
   organised by workflow (setup → wallet/tx → primitives →
   advanced). Each group lists only the command name and a
   one-line summary.
2. Added `help:daemon()`, `help:bip173()`, `help:bip350()`,
   `help:bip174()` functions.
3. Added `_is_libexec()` helper and updated `command:help`'s
   $1 branch to accept libexec plugins, falling back to
   `exec "$SELF_LIBEXEC/$SELF/$1" help`.

## Regression Protection

- `bitcoin help` shows the full command surface.
- `bitcoin help daemon` shows daemon subcommands.
- `bitcoin daemon` dispatches to the libexec plugin and shows
  its own help.

## Acceptance Criteria

- [x] `bitcoin help` lists all current commands, no deprecated
      entries.
- [x] `bitcoin help daemon` shows daemon subcommands.
- [x] `bitcoin help bip173` shows bip173 help (from libexec).
- [x] No "frontent" typo.
