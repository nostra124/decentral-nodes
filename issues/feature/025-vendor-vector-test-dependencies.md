---
id: FEAT-025
type: feature
priority: medium
status: open
---

# Make `tests/vectors/*.t` runnable end-to-end (vendor or document the external dependencies)

## Description

**As a** developer running `make check-vectors`
**I want** the BIP vector tests to either run cleanly or fail with
a clear "missing dependency X" message
**So that** the TAP suite is actionable.

FEAT-006 made `bin/bitcoin` sourceable and wired
`make check-vectors` to assemble a temp PATH with `bitcoin.sh`,
`bitcoin`, and the libexec plugins (`bip13`, `bip32`, `bip39`,
`daemon`, `wif`). That is sufficient for `. bitcoin.sh` to
resolve, but the .t files also invoke external programs the repo
does not ship:

- `base58` — referenced from `tests/vectors/base58.t`,
  `bip-0032.t`, `bip-0039.t`, `bip-0084.t`, `bip-0085.t`,
  `xkey-to-address.t`. Not in `libexec/bitcoin/`. Presumably from
  a sibling repo (likely `crypt`).
- `dc` — referenced from `tests/vectors/basics.t`,
  `secp256k1.t`. Standard Unix tool but not in the minimal CI
  container.
- `wif -u` flag — referenced from `basics.t`. The current
  `libexec/bitcoin/wif` does not implement `-u`.
- Possibly more — the audit (see `skills/audit.md`) should
  enumerate every external invocation in `tests/vectors/`.

The original FEAT-006 acceptance criterion 1 ("prove passes")
referenced a non-existent FEAT-003 as the gating prerequisite for
vendoring those dependencies. FEAT-003 was never filed in this
repo; that is what this feature corrects.

## Implementation

Two acceptable approaches:

1. **Vendor the missing binaries.** Add `libexec/bitcoin/base58`
   (a self-contained bash + openssl implementation) and any other
   bitcoin-specific dependency. Install `dc` as a `Depends`
   declaration in `.rpk/depends`. Implement `wif -u`. This is the
   self-contained path consistent with CLAUDE.md §4 (no shared
   lib).
2. **Document and detect.** Have `make check-vectors` probe each
   dependency up front and `skip` the whole suite with a clear
   message if any are missing. Useful as an intermediate state
   while option 1 is in flight.

Option 2 first, then option 1, is probably the right sequencing.

## Acceptance Criteria

1. `make check-vectors` on a clean cloud sandbox either:
   - Passes all suites (option 1 complete), or
   - Skips with a clear `missing dependency: <name>` message and
     exit 0 (option 2 complete).
2. No silent failures: every `not ok` line names which dependency
   it needed.
3. `.rpk/depends` enumerates every external command the vector
   suite invokes that is NOT vendored.
4. `skills/audit.md`'s reverse-trace (§3.2) does not flag any
   vector-test invocation as an undocumented dependency.

## Notes

This feature is the prerequisite for the "prove tests/vectors/
passes all suites" line that lived in the original FEAT-006 and
in `issues/ROADMAP-1.1.0.md`. With FEAT-025 filed, both of those
references can be relaxed.
