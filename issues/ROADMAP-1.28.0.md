# Roadmap — 1.28.0 (minor)

**Docs, testing & agents.** The wallet is functionally broad after
1.26.0–1.27.0; 1.28.0 makes it *learnable* and *verifiable*. A real
regtest harness proves the spend pipeline end to end (and retires the
stubbed acceptance criteria carried by earlier features), the docs
surface gets completed, and an agent skill teaches AI assistants to
drive the wallet safely.

## Status

| Feature | Status | Notes |
|---------|--------|-------|
| FEAT-016 SIT: end-to-end receive→spend on regtest | planned | unblocks regtest ACs parked in FEAT-008 / FEAT-014 |
| FEAT-015 `bitcoin(1)` man page, bash completion, README walkthrough | planned | per-subcommand man pages (FEAT-041) already shipped |
| FEAT-019 `bitcoin-wallet` agent skill | planned | |

## What lands

1. **FEAT-016 — SIT regtest harness.** A podman/regtest `bitcoind`
   harness that funds an address, builds → signs → broadcasts a spend,
   and asserts the backend sees the txid within a block. This is the
   keystone: it closes FEAT-008 AC #2 and FEAT-014 AC #1 / #3
   (`testmempoolaccept` on regtest), which have been structurally
   tested at the unit tier but never end-to-end.

2. **FEAT-015 — docs surface.** The `bitcoin(1)` overview man page
   (cross-referencing the per-command pages FEAT-041 shipped), bash
   completion for the command tree, and a README walkthrough of the
   cold-storage story. Largely a completion pass over groundwork
   already laid.

3. **FEAT-019 — `bitcoin-wallet` agent skill.** A skill that educates
   AI agents on the wallet's verbs, the secret/seed boundary, and the
   testnet-by-default / `--mainnet`-guard safety model — so an agent
   can operate the wallet without footguns.

## Depends on

- FEAT-014 send pipeline (shipped) — the thing the SIT exercises.
- A container runtime (podman) on the SIT tier per `skills/testing.md`.

## Notes

FEAT-016 is sequenced first within the milestone: once the regtest
harness exists, the trailing acceptance criteria on FEAT-008 and
FEAT-014 can finally be checked off rather than carried as "needs the
SIT harness".
