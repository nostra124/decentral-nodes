---
id: BUG-016
type: bug
priority: medium
status: open
---

# `command:bip49-create` / `command:bip84-create` call undefined `command:bip32-create`

audit: 2026-05-13

## Severity

**Medium.** Same defect class as BUG-013 / BUG-014 (calls
referencing a function name that doesn't exist). Surfaced by the
audit's mechanical surface walk, not by a user — `bitcoin
bip49-create` and `bitcoin bip84-create` are rarely invoked
because the wallet flow uses the bash-function wrappers
`bip49()` / `bip84()` instead.

## Observed

`bin/bitcoin` defines two `command:` dispatcher entries:

```bash
command:bip49-create() {
  BIP32_MAINNET_PUBLIC_VERSION_CODE=0x049d7cb2 \
  …
  command:bip32-create "$@"
}

command:bip84-create() {
  BIP32_MAINNET_PUBLIC_VERSION_CODE=0x04b24746 \
  …
  command:bip32-create "$@"
}
```

`command:bip32-create` is not defined anywhere in this repo:

```sh
$ grep -n "command:bip32-create" bin/bitcoin libexec/bitcoin/*
bin/bitcoin: …  # only the two call sites
$ grep -n "^command:bip32-create" bin/bitcoin libexec/bitcoin/*
$ # empty
```

`bitcoin bip49-create` therefore fails with `command:bip32-create:
command not found`.

## Root Cause

Same pattern as BUG-013/014 — function names that diverged from
their definitions and bash doesn't catch it. Probably refers to
an old name for `libexec/bitcoin/bip32 create` (which is
`command:create` *inside* the bip32 plugin, not at the
dispatcher level).

## Fix Plan

Two options:

1. **Rewire the wrappers** to invoke the libexec plugin
   directly:

   ```bash
   command:bip49-create() {
       BIP32_MAINNET_PUBLIC_VERSION_CODE=0x049d7cb2 \
       BIP32_MAINNET_PRIVATE_VERSION_CODE=0x049d7878 \
       BIP32_TESTNET_PUBLIC_VERSION_CODE=0x044a5262 \
       BIP32_TESTNET_PRIVATE_VERSION_CODE=0x044a4e28 \
       "$SELF_LIBEXEC/$SELF/bip32" create "$@"
   }
   ```

   This also has to confront the latent bug where the
   `BIP32_*_VERSION_CODE` env vars *aren't read* by the bip32
   plugin (it reads the un-prefixed forms). Filed as the audit's
   "audit follow-up" note.

2. **Remove the wrappers** if the bash-function `bip49()` /
   `bip84()` (defined later in `bin/bitcoin`) are the canonical
   user surface. Update `bitcoin help` accordingly.

## Regression Protection

A new bats test:

```bash
@test "BUG-016 — bitcoin bip49-create resolves to a working dispatcher path" {
    run "$BITCOIN_BIN" bip49-create
    # Whatever the implementation does (success or a clean error),
    # it must NOT emit "command:bip32-create: command not found".
    [[ "$output" != *"command:bip32-create"* ]]
}
```

(Fails on master, passes after the fix.)

## Acceptance Criteria

1. `bitcoin bip49-create` and `bitcoin bip84-create` do not emit
   "command not found" for `command:bip32-create`.
2. New regression test in `tests/unit/bitcoin.bats`.
3. Bug file moves to `issues/bug/done/`.
4. If the wrappers are removed (option 2), the `bitcoin help`
   text in the dispatcher is updated to match.
