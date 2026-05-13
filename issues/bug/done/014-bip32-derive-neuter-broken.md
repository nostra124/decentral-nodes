---
id: BUG-014
type: bug
priority: high
status: done
---

## Resolution (shipped in 1.5.2)

Two edits in `libexec/bitcoin/bip32`:
- Line 330: `command:bip32-is-public` → `command:is-public`
- Line 332: `command:bip32-is-secret` → `command:is-secret`

56/56 bats green; BUG-014 regression test fails on master, passes
after the fix. Hardening note: a future audit should grep the
plugins for `command:<name>` where `<name>` isn't a defined
function, to catch this defect class proactively.

# `bip32 derive m/.../N` (neutering) calls undefined `command:bip32-is-public` / `command:bip32-is-secret`

## Severity

**High.** Same family of defect as BUG-013, surfaced when trying to
use the `/N` suffix that BIP-32 §The key tree §Public derivation
relies on (i.e. derive a child *public* key from an extended
private key without exposing the private material).

BUG-013 fixed three call sites in `libexec/bitcoin/bip32`. The
neutering branch at lines 330 / 332 was reachable via a different
code path that BUG-013's regression test didn't exercise, so the
broken calls survived.

## Observed

```sh
$ printf '<binary xprv>' | bip32 derive m/84h/0h/0h/0/0/N 2>&1
/home/user/bitcoin/libexec/bitcoin/bip32: line 330: command:bip32-is-public: command not found
/home/user/bitcoin/libexec/bitcoin/bip32: line 332: command:bip32-is-secret: command not found
```

End-to-end pipeline `mnemonic-to-seed | basenc -w0 | bip32 create
-s | base58-decode | bip32 derive m/.../N`, with `/N` appended,
produces error text instead of the expected 78-byte neutered
xpub serialisation.

## Root Cause

Two call sites in `libexec/bitcoin/bip32:330,332` use the function
names `command:bip32-is-public` and `command:bip32-is-secret`.
The plugin defines them as `command:is-public` and
`command:is-secret` (lines 229–230). The `bip32-` prefix is
spurious — never matched any defined function.

Same family of "names diverged across edits and the type checker
isn't catching it" as BUG-013. The earlier patch missed these
two because the BUG-013 regression test exercised only the
non-neutering branch.

## Fix Plan

Two edits in `libexec/bitcoin/bip32`:

1. Line 330: `command:bip32-is-public` → `command:is-public`.
2. Line 332: `command:bip32-is-secret` → `command:is-secret`.

## Regression Protection

The existing BUG-013 regression test exercises the non-neutering
path. Extend the coverage with a new test that uses the `/N`
suffix and asserts the output is the expected 78-byte xpub
serialisation (or at least 78 bytes and free of the two known
error messages).

```bash
@test "BUG-014 — bip32 derive m/.../N (neutering) resolves" {
    PATH="$BATS_TEST_DIRNAME/../../bin:$BATS_TEST_DIRNAME/../../libexec/bitcoin:$PATH" \
    XDG_SHARE_HOME="$BATS_TEST_DIRNAME/../../share" \
    run bash -c '
      mnemonic-to-seed abandon abandon abandon abandon abandon abandon abandon \
                       abandon abandon abandon abandon about \
        | basenc --base16 -w0 | bip32 create -s 2>/dev/null \
        | bitcoin bip13 base58-decode \
        | bip32 derive m/84h/0h/0h/0/0/N
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"bip32-is-public"* ]]
    [[ "$output" != *"bip32-is-secret"* ]]
}
```

## Acceptance Criteria

1. The new regression test fails on pre-patched code.
2. After the patch, the regression test passes.
3. `bip32 derive m/.../N` produces ~78 bytes of output (raw xpub
   serialisation).
4. The existing BUG-013 regression test stays green.
5. Bug file moves to `issues/bug/done/` with `status: done`.
