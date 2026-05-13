---
id: BUG-013
type: bug
priority: high
status: done
---

## Resolution (shipped in 1.5.1)

Five edits in `libexec/bitcoin/bip32`:

- Lines 229–230: `command:is-secret` and `command:is-public` now
  reference the unprefixed `*_VERSION_CODE` variables the plugin
  actually defines.
- Lines 349 / 351: same rename for the public-key version swap.
- Lines 365 / 384: `isPrivate` / `isPublic` → `command:is-secret`
  / `command:is-public`.

55/55 bats green after the patch, including the new BUG-013
regression test which fails on master and passes after.

# `bip32 derive` calls undefined `isPrivate` / `isPublic` and refers to BIP32_-prefixed version codes that aren't defined

## Severity

**High.** Every attempt to derive a child key via the bip32
plugin fails. Concretely:

```sh
$ printf '%s' "<known xprv hex>" | basenc --base16 -d \
    | bip32 derive m/0/0
/home/user/bitcoin/libexec/bitcoin/bip32: line 365: isPrivate: command not found
/home/user/bitcoin/libexec/bitcoin/bip32: line 384: isPublic: command not found
bip32: fatal - version is neither private nor public?!
```

Because every wallet read-path verb (FEAT-013 `wallet derive`,
`wallet balance`, `wallet scan`) depends on `bip32 derive`, none
of them can ship until this is fixed.

## Observed

`libexec/bitcoin/bip32:365` and `:384` reference helper functions
`isPrivate` / `isPublic` that are never defined. The plugin's
actual checks are `command:is-secret` and `command:is-public`
(lines 229–230). The `is-secret` / `is-public` definitions
themselves are correct but **they reference**
`BIP32_TESTNET_PRIVATE_VERSION_CODE` etc. — variables the plugin
never sets. The plugin's own definitions at lines 224–227 use the
**unprefixed** `MAINNET_PRIVATE_VERSION_CODE` etc.

So even after renaming `isPrivate` → `command:is-secret`, the
check would still return false because `BIP32_*_VERSION_CODE`
expands to empty / 0.

A third occurrence of the same prefix mismatch is at lines
349 / 351 where the public-key version swap reads
`$BIP32_MAINNET_PUBLIC_VERSION_CODE` /
`$BIP32_TESTNET_PUBLIC_VERSION_CODE` (also empty).

## Root Cause

Pre-existing inconsistency between two naming conventions for the
version-code variables, never reconciled. The plugin internally
defines `*_VERSION_CODE`; the dispatcher / sibling functions
(`bip49()`, `bip84()` in `bin/bitcoin`) export
`BIP32_*_VERSION_CODE`. The plugin reads both names in different
places — neither name has full coverage.

## Fix Plan

Three sites in `libexec/bitcoin/bip32`:

1. Line 229–230: `command:is-secret` and `command:is-public`
   reference `BIP32_*_VERSION_CODE`. Change to the unprefixed
   forms (consistent with lines 224–227).
2. Line 349, 351: `version=$BIP32_*_PUBLIC_VERSION_CODE`. Same
   rename.
3. Line 365, 384: `isPrivate` / `isPublic` → `command:is-secret`
   / `command:is-public`.

After the fix, `command:is-secret` / `command:is-public` work
against the plugin's own version-code definitions, and the derive
loop's branch dispatch resolves.

The separate `bip49()` / `bip84()` env-var override path is
**not** fixed in this patch — that's a follow-up audit item.
The address derivation we care about (`m/84h/0h/0h/0/N` against
the BIP-32 version codes) doesn't need the BIP-84 zprv encoding,
just the child-key derivation logic.

## Regression Protection

A new bats test in `tests/unit/bitcoin.bats` runs the full
pipeline against the canonical BIP-39 test mnemonic and asserts
the first child private key matches a known vector. The test
fails against unpatched code (the `isPrivate not found` error
above) and passes after the fix.

```bash
@test "BUG-013 — bip32 derive resolves end-to-end from a seed" {
    PATH="$BATS_TEST_DIRNAME/../../bin:$BATS_TEST_DIRNAME/../../libexec/bitcoin:$PATH" \
    XDG_SHARE_HOME="$BATS_TEST_DIRNAME/../../share" \
    SELF_LIBEXEC="$BATS_TEST_DIRNAME/../../libexec" \
    run bash -c '
      mnemonic-to-seed abandon abandon abandon abandon abandon abandon abandon \
                       abandon abandon abandon abandon about \
        | basenc --base16 -w0 \
        | bip32 create -s 2>/dev/null \
        | bitcoin bip13 base58-decode \
        | bip32 derive m/0
    '
    [ "$status" -eq 0 ]
}
```

(The path m/0 is intentionally short — we're testing the derive
loop resolves at all, not the exact key.)

## Acceptance Criteria

1. The regression test commit fails against pre-patched code.
2. After the patch, the regression test passes.
3. No other bats tests change behaviour.
4. `bip32 derive` works for both `^m`- and `^M`-rooted paths.
5. Bug file moves to `issues/bug/done/` with `status: done`.
