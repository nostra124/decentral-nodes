---
id: FEAT-017
type: feature
priority: medium
status: done
---

# Vendor BIP source documents and cite them in help and man pages

## Description

**As a** user reading `bitcoin help` or `man bitcoin`
**I want** every implemented BIP cited by number and title, linked to
the upstream URL, and available as a locally installed reference
**So that** the wallet doubles as a learning tool: I can follow any
operation back to the spec text without leaving the machine, and the
spec I'm reading matches the version the wallet was built against.

This ticket is referenced by every bitcoin feature ticket (FEAT-007
through FEAT-015) — they all promise "cite the relevant BIP and
link to the vendored copy". This ticket establishes the vendoring
convention and the citation template they all use.

## Implementation

1. **Vendor BIP source documents** under
   `share/doc/bitcoin/bips/bip-NNNN.mediawiki`, in their original
   upstream format. Source from `github.com/bitcoin/bips` at a
   pinned commit recorded in `share/doc/bitcoin/bips/UPSTREAM.txt`
   (commit SHA + date).

   Initial set, matching what the wallet implements or plans to
   implement:

       bip-0013   P2SH addresses
       bip-0032   HD wallets
       bip-0039   mnemonic seed phrases
       bip-0044   multi-account hierarchy
       bip-0049   derivation for P2WPKH-nested-in-P2SH
       bip-0084   derivation for native P2WPKH
       bip-0086   derivation for single-key P2TR
       bip-0085   deterministic entropy from BIP-32 keys
       bip-0141   segregated witness consensus layer
       bip-0143   transaction signature verification for v0 witness
       bip-0173   bech32 segwit address format
       bip-0174   PSBT
       bip-0340   Schnorr signatures for secp256k1
       bip-0341   Taproot SegWit version 1 spending rules
       bip-0342   Tapscript validation
       bip-0350   bech32m
       bip-0371   Taproot fields for PSBT
       bip-0380   Output script descriptors (general)
       bip-0381   non-segwit descriptors
       bip-0386   tr() output script descriptor

2. **Citation template** for `bitcoin help <subcommand>`:

       Implements:
         BIP-NNN  <title>
         <upstream-url>
         local:   /usr/local/share/doc/bitcoin/bips/bip-NNNN.mediawiki

   Help functions read the install prefix from the same source the
   rest of the script uses, so the local path is correct whether
   installed under `~/.local` or `/usr/local`.

3. **Man page STANDARDS section** lists every implemented BIP with
   upstream URL and local path (per FEAT-015 §1).

4. **Refresh script** at `share/doc/bitcoin/bips/refresh` that
   re-fetches the vendored set from a configurable upstream commit,
   updates `UPSTREAM.txt`, and commits. Run manually; not part of
   `make` targets.

5. **`.rpk/package`** installs `share/doc/bitcoin/bips/*` to
   `$PREFIX/share/doc/bitcoin/bips/`.

## Acceptance Criteria

1. `share/doc/bitcoin/bips/` contains every BIP listed above as a
   `.mediawiki` file, plus `UPSTREAM.txt` recording the source commit.
2. `bitcoin help <subcommand>` for any subcommand that implements a
   BIP prints the citation template above with the correct local path
   for the active install prefix.
3. `man bitcoin` STANDARDS section enumerates every vendored BIP with
   both upstream URL and local path.
4. After `make install`, every cited local path resolves to a readable
   file.
5. `share/doc/bitcoin/bips/refresh` re-fetches the set from a given
   upstream commit and updates `UPSTREAM.txt`; the diff is reviewable.
