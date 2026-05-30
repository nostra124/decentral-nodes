---
id: BUG-021
type: bug
priority: high
status: done
---

# unit suite red — bip174-p2pkh.bats fixture + openssl verify bugs

audit: 2026-05-30

## Severity

**High.** The bats unit suite (the CI gate, CLAUDE.md §9 / §11) is red
on `master`: six tests in `tests/unit/bip174-p2pkh.bats` fail. As BUG-020
documented, `release-tag.yml` cuts the tag on any push to `master` and
does **not** gate on `tests.yml`, so v1.34.0 (and the 1.33.x line before
it) was tagged on a red suite — the bypass §11 forbids. These six are
the entire remaining red surface (the other 436 tests pass).

## Observed

`bats tests/unit/bip174-p2pkh.bats` on `master` (runner with `xxd` +
`dc` + `openssl`):

```
not ok 1 FEAT-014 — psbt sign emits PARTIAL_SIG for P2PKH input
#   [[ "$output" == *"type=02"* ]]' failed
not ok 2 FEAT-014 — P2PKH PARTIAL_SIG is low-S (BIP-66)
#   /…/bip174-p2pkh.bats: line 71: 16#: invalid integer constant (error token is "16#")
not ok 3 FEAT-014 — P2PKH signature verifies against legacy double-SHA256 sighash
#   Signature Verification Failure
not ok 4 FEAT-014 — psbt finalize produces FINAL_SCRIPTSIG (no witness) for P2PKH
not ok 5 FEAT-014 — psbt extract produces broadcastable legacy tx for P2PKH
#   bip174: error - psbt extract: input 0 has neither FINAL_SCRIPTSIG nor FINAL_SCRIPTWITNESS
not ok 8 FEAT-014 — P2SH-P2WPKH signature verifies against BIP-143 sighash
#   Signature Verification Failure
```

(Tests 6, 7, 9 pass — the P2SH path that uses a *different*, correctly
sized inline tx literal.)

## Root Cause

Two independent **test-only** defects. The shipped `bip174` plugin is
correct — proven by the FEAT-008 test `psbt sign signature verifies via
openssl against the BIP-143 sighash` (bitcoin.bats), which signs with
the same plugin and verifies green.

1. **Malformed `UNSIGNED_TX` fixture (tests 1, 2, 4, 5).** The shared
   `UNSIGNED_TX` literal is **83 bytes**, but the PSBT wrappers declare
   its `PSBT_GLOBAL_UNSIGNED_TX` length as `010052` = **82 bytes** (the
   correct size of a 1-in/1-out/22-byte-output tx — it carried a
   spurious trailing `00`). `psbt:_parse_structured` honours the length
   prefix, reads 82 bytes, and the leftover byte becomes a phantom
   `keylen=00` that desyncs the per-section walk: the input's
   WITNESS_UTXO is mis-filed into the *output* section, `INPUT[0]` is
   empty, and `command:sign` skips the input ("no WITNESS_UTXO →
   continue") — emitting **no** PARTIAL_SIG and exiting 0. Tests 2/5
   then cascade off the empty signature (the `16#` arithmetic error is
   bash choking on an empty DER string). The P2SH tests escaped because
   their literal (line 43) embeds a correctly sized 82-byte tx.

2. **Wrong `openssl pkeyutl -verify` invocation (tests 3, 8).** Both
   verify steps pass `-rawin`, which tells OpenSSL the `-in` file is an
   *unhashed message*; OpenSSL then hashes the already-final 32-byte
   sighash again, so the signature never matches → "Signature
   Verification Failure". The proven FEAT-008 verify path omits
   `-rawin` and treats the sighash as the pre-computed digest.

## Fix Plan

1. Correct `UNSIGNED_TX` to exactly 82 bytes (drop the stray trailing
   `00`) so it matches the `010052` length the wrappers declare.
2. Drop `-rawin` from both `openssl pkeyutl -verify` calls; verify the
   sighash as the pre-hashed digest, matching the FEAT-008 path.

No production code changes — the `bip174` signing/sighash logic is
correct and independently covered; only the stale test fixture and the
verify invocation move.

## Regression Protection

- `bats tests/unit/bip174-p2pkh.bats` is green (9/9).
- Tests 3 and 8 now perform a *real* ECDSA verification of the plugin's
  P2PKH (legacy double-SHA256) and P2SH-P2WPKH (BIP-143) signatures, so
  a genuine regression in either sighash path would now fail the suite
  (previously it could not, since the sig was empty / the verify was
  mis-invoked).

## Follow-up (not in this fix)

`command:sign` skips an input that lacks WITNESS_UTXO **silently**
(`continue` with only a code comment). Per CLAUDE.md §10 every failure
branch should emit a `warn`. A separate change could add
`warn "psbt sign: input N has no WITNESS_UTXO; not signing"` so a
malformed PSBT surfaces instead of producing an unsigned result with
exit 0. Tracked for a future logging-hardening pass, not this bug.

## Acceptance Criteria

- [x] `UNSIGNED_TX` is exactly 82 bytes, matching the `010052` prefix.
- [x] Neither `openssl pkeyutl -verify` call uses `-rawin`.
- [x] `bats tests/unit/bip174-p2pkh.bats` passes 9/9.
- [x] No change to `libexec/bitcoin/bip174` (shipped behaviour correct).
