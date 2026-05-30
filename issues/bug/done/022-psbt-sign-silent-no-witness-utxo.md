---
id: BUG-022
type: bug
priority: low
status: done
---

# psbt sign silently skips an input that has no WITNESS_UTXO

audit: 2026-05-30

## Severity

**Low.** `bitcoin bip174 sign` (and `tx sign` / `wallet sign`, which
delegate to it) silently skipped any input lacking a WITNESS_UTXO
record — `continue` with only a code comment, no diagnostic — and still
exited 0. The caller got an unsigned (or partially-signed) PSBT back
with no indication an input was passed over. This violates CLAUDE.md
§10 ("every failure branch must emit at least one warn/error/fatal line
that names the condition and the offending value"). It also masked
BUG-021: a malformed PSBT whose section walk desynced presented as an
input with no WITNESS_UTXO, so signing produced an unsigned result and
exit 0 with no signal.

## Observed

```
$ printf '70736274ff010052<82B unsigned tx>000000' | bitcoin bip174 sign <priv>
70736274ff010052…000000          # echoed back, no PARTIAL_SIG, exit 0
$                                # no warn, no error — looks like success
```

## Root Cause

In `command:sign` (`libexec/bitcoin/bip174`) the per-input loop opened
with:

```sh
if [ -z "$wu" ]; then
    # No WITNESS_UTXO record — can't sign without it.
    continue
fi
```

The branch is a genuine "cannot sign" failure (incomplete/malformed
PSBT) but emitted nothing. It must stay distinct from the *legitimate*
no-op later in the loop, where an input simply isn't owned by this key
(multi-party / multi-sig flows) — that case is quiet by design.

## Fix

Add a `warn` to the no-WITNESS_UTXO branch only:

```sh
warn "psbt sign: input $i has no WITNESS_UTXO record; not signing it"
```

`warn()` is unconditional on stderr; `info()` is the one gated by
`SELF_QUIET`. The key-mismatch no-op is left silent (normal, not a
failure). No change to any signature/sighash logic.

## Regression Protection

Two tests in `tests/unit/bip174-p2pkh.bats`:

- `BUG-022 — psbt sign warns when an input has no WITNESS_UTXO`: a
  well-formed 1-in/1-out PSBT with an empty input map; asserts the warn
  names `WITNESS_UTXO` and `input 0`. Failed against the silent code
  first (stderr empty), passes after the fix.
- `BUG-022 — psbt sign with a non-matching key stays a quiet no-op`:
  guards that the fix does NOT over-warn — signing a valid-WITNESS_UTXO
  input with a foreign key leaves the PSBT byte-identical, stderr empty.

The existing FEAT-008 key-mismatch no-op tests (bitcoin.bats,
bip174-taproot.bats) — which run `bip174 sign` without `SELF_QUIET` and
assert byte-identical output — remain green.

## Acceptance Criteria

- [x] The no-WITNESS_UTXO skip in `command:sign` emits a `warn` naming
      the input index.
- [x] Key-mismatch signing stays a silent, byte-identical no-op.
- [x] New regression tests cover both, red-then-green.
- [x] No change to signing/sighash behaviour; `shellcheck` clean.
