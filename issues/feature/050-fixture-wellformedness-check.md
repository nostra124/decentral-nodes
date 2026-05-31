# FEAT-050 — fixture well-formedness check for PSBT/tx test vectors

**Status:** open
**Milestone:** unscheduled

## Summary

Hand-crafted hex fixtures in the bats suite (45+ long-hex literals) have
no internal-consistency check. BUG-021 shipped a `UNSIGNED_TX` literal
that was 83 bytes while its PSBT length prefix declared 82; the parser
honoured the prefix and the stray byte desynced section parsing, so
`sign` silently produced no signature. Nothing caught the mismatch at
authoring time.

## Proposal

Add a small test helper (in a shared `tests/unit/helpers.bash`) that
either:

1. validates a PSBT/tx fixture's declared lengths against its actual
   byte count (e.g. `assert_psbt_wellformed "$hex"`, `tx_byte_len`), or
2. *generates* the fixtures from the shipped tools / a tiny builder
   rather than pasting hex, so length fields are correct by construction.

A `@test` should assert every checked-in PSBT fixture is well-formed, so
a future off-by-one fails immediately and locally (red on a deliberately
corrupted fixture).

## Acceptance Criteria

- [ ] A helper validates PSBT/tx fixture length fields vs. byte length.
- [ ] The bip174 / tx fixtures are validated by a test.
- [ ] Documented in `skills/testing.md`.
