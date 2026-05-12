---
id: FEAT-020
type: feature
priority: high
status: done
---

# Fix bats test environment isolation: pin `SELF_LIBEXEC` and read version from source

## Description

`tests/unit/bitcoin.bats` has two latent pollution risks that can cause
false passes or false failures depending on what is installed on the host.

### Problem A — `SELF_LIBEXEC` not pinned

`bin/bitcoin` resolves `SELF_LIBEXEC` by probing four directories in
order: env override → in-checkout sibling → `$HOME/.local/libexec` →
`/usr/local/libexec` → `/usr/libexec`. The test's `setup()` overwrites
`HOME` with a temp dir, which rules out `$HOME/.local/libexec`, but it
leaves `/usr/local/libexec` and `/usr/libexec` live. A globally-installed
`bitcoin` at a different version will be found and used instead of the
in-tree one. The tests then exercise the wrong binary's libexec.

Fix: export `SELF_LIBEXEC` explicitly in `setup()`:

```bash
export SELF_LIBEXEC="$BATS_TEST_DIRNAME/../../libexec"
```

### Problem B — version test hard-codes `1.0.0`

```bash
@test "bitcoin version returns 1.0.0" {
    run "$BITCOIN_BIN" version
    [ "$output" = "1.0.0" ]
}
```

`bin/bitcoin` reads the version at runtime from `.rpk/version`. When the
package is bumped to 1.1.0 the test will fail for the wrong reason. The
test should read the expected value from the same source the binary does:

```bash
@test "bitcoin version matches .rpk/version" {
    expected="$(cat "$BATS_TEST_DIRNAME/../../.rpk/version")"
    run "$BITCOIN_BIN" version
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}
```

## Acceptance Criteria

1. Running `make check-unit` from a machine with a system-installed
   `bitcoin` in `/usr/local/libexec` exercises only the in-tree
   `libexec/bitcoin/` plugins.
2. The version test passes after `make package VERSION=1.1.0` without
   editing the test file.
3. `setup()` exports `SELF_LIBEXEC`.
