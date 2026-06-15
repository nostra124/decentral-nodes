---
id: FEAT-300
type: feature
priority: high
status: open
---

# `monero install` — verified release-tarball install of the Monero binaries

## Description

**As an** operator bringing up a Monero node
**I want** `monero install` to fetch and verify the official Monero binaries
**So that** `monerod` (and the wallet binaries used by later milestones) are on
disk with their authenticity proven, on a fresh machine, with one command

Monero isn't packaged cleanly in most distros, so — as decided in review and
matching how `bitcoin`/`fulcrum` install — we pull the **official release
tarball** from getmonero.org and verify it (GPG signing key + published SHA256).

## Implementation

`libexec/monero/install`:
- Detect host arch → release asset (`monero-linux-x64`, `monero-linux-armv8`,
  `monero-mac-x64`/`-armv8`); resolve the current version (pinned, overridable
  via `$MONERO_VERSION`).
- Download the tarball + the signed `hashes.txt` (or release SHA256); import the
  Monero maintainer signing key (pinned fingerprint, vendored under
  `share/monero/keys/`), `gpg --verify` the hashes file, then check the tarball
  SHA256 against it. **Fail closed** on any mismatch.
- Extract `monerod`, `monero-wallet-rpc`, `monero-wallet-cli` to the install
  bindir (resolution preferring `/usr/local`,`/opt/local`,`/opt/homebrew` like
  fulcrum, avoiding the dispatcher name collision).
- Idempotent: re-running with the same version is a no-op; `--force`
  re-installs. Test seams (`$MONERO_RELEASE_BASEURL`, `$MONERO_BINDIRS`) for
  hermetic bats.

## Acceptance Criteria

1. `monero install` downloads, GPG-verifies, SHA256-checks, and stages `monerod`
   + the wallet binaries; `monerod --version` runs afterward. Proven (mocked
   download) by `monero.bats`.
2. A tampered tarball (bad SHA256) or a bad signature aborts with a non-zero
   exit and an `error` line naming the failure; nothing is staged. Proven with a
   fixture.
3. Arch detection picks the right asset on x86_64 and aarch64 (seam-overridable
   in the test).
4. Re-running is idempotent; `--force` re-installs. Proven by `monero.bats`.
