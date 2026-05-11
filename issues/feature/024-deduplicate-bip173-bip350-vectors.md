---
id: FEAT-024
type: feature
priority: low
status: open
---

# Deduplicate shared bech32 vectors between `bip-0173.t` and `bip-0350.t`

## Description

`tests/vectors/bip-0173.t` and `tests/vectors/bip-0350.t` both carry the
same set of seven correct-bech32 and eight incorrect-bech32 strings in
their respective `correct_bech32` / `incorrect_bech32` arrays. The only
difference is that BIP-350 also adds the bech32m sets.

Keeping two copies means:
- A corrected vector must be updated in both files.
- A new BIP-173 edge case must be remembered across both files.
- A reviewer can't tell whether the divergence is intentional.

### Preferred approach — `bip-0173.t` delegates to `bip-0350.t`

BIP-350 supersedes BIP-173 for the original bech32 algorithm while adding
bech32m. `bip-0173.t` can source the shared vector arrays from
`bip-0350.t` (or from a shared fixture file) and run only the BIP-173-
specific assertions (those that don't involve bech32m or segwit v1+).

Alternatively, if the two specs need to be exercised independently (e.g.,
for spec-compliance audit purposes), extract the shared vectors to a
`tests/vectors/fixtures/bech32-common.sh` file and source it from both.

### Minimum viable fix

At minimum, add a comment to each file pointing to the other as the
canonical source, so a maintainer knows to keep them in sync.

## Acceptance Criteria

1. The seven correct-bech32 and eight incorrect-bech32 vectors appear in
   exactly one location (or are clearly sourced from one location).
2. Both `bip-0173.t` and `bip-0350.t` continue to pass `prove`.
3. Adding a new bech32 (non-bech32m) test vector requires editing only
   one file.
