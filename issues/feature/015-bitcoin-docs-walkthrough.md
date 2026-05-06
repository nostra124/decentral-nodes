---
id: FEAT-015
type: feature
priority: medium
status: open
---

# `bitcoin(1)` man page, bash completion, and README walkthrough

## Description

**As a** new user of the educational bitcoin wallet
**I want** a man page, shell completion, and a README that walks me
from a fresh `bitcoin wallet new` to receiving and spending on
regtest
**So that** the wallet is actually approachable as a learning tool.

This is the educational deliverable; without it the wallet is just
features.

## Design principles

The wallet — and everything we write about it — is anchored on four
words: **educational, functional, decentralized, simple.** The man
page DESCRIPTION, the README walkthrough opening, and the agent skill
(FEAT-019) all state these explicitly so that contributors and
agents have a shared yardstick when scoping new features or trimming
old ones.

## Implementation

1. **`bitcoin(1)` man page** under `share/man/man1/bitcoin.1`, seeded
   from the existing `bitcoin help` output and `docs/bitcoin.md`
   (FEAT-004). Sections: NAME, SYNOPSIS, DESCRIPTION, SUBCOMMANDS,
   ENVIRONMENT, FILES, EXIT STATUS, EXAMPLES, **STANDARDS**, SEE ALSO.

   The DESCRIPTION opens by stating the four design principles so a
   reader knows the wallet's intent before reading any flag.

   The STANDARDS section enumerates every BIP the wallet implements,
   citing each with title, status (Final/Active/Draft), upstream URL,
   and the local installed path under
   `share/doc/bitcoin/bips/bip-NNNN.mediawiki` per FEAT-017.

2. **`etc/bash_completion.d/bitcoin`** — completes top-level
   subcommands plus context-aware completion for `wallet`, `psbt`,
   `descriptor`, `backend` subtrees.

3. **README walkthrough** at `docs/bitcoin-walkthrough.md`:
   - Setting up regtest (with optional `bitcoind` or with public
     mempool/blockstream backend pointing at signet as a substitute).
   - `bitcoin wallet new alice` — passphrase, seed phrase displayed
     once with a "write this down" warning, seed stored via `secret`.
   - `bitcoin wallet derive alice` to get an address, fund it.
   - `bitcoin wallet balance alice`.
   - `bitcoin wallet send alice <addr> 0.0001`.
   - The git push/pull flow: setting up a second account `bob`,
     pushing the wallet, signing on `bob`, broadcasting from `alice`.
   - Each section cites the relevant BIP(s) and links to both the
     upstream URL and the locally vendored copy.

4. **Default network is testnet/regtest.** Mainnet requires either
   the `--mainnet` flag per command or
   `bitcoin config set network mainnet`.

## Acceptance Criteria

1. `man bitcoin` renders with all sections populated, including a
   STANDARDS section enumerating every implemented BIP with upstream
   URL and local path.
2. `bitcoin help <subcommand>` for any subcommand that implements a
   BIP cites the BIP number, title, and local installed path.
3. Tab completion works for `bitcoin <TAB>`, `bitcoin wallet <TAB>`,
   `bitcoin psbt <TAB>`, `bitcoin descriptor <TAB>`,
   `bitcoin backend <TAB>`.
4. A new user following `docs/bitcoin-walkthrough.md` step by step
   on regtest reaches a successful spend without consulting any
   other documentation.
5. Every command in the walkthrough is exercised by `tests/sit/`
   (FEAT-016).
6. Default network on a fresh install is testnet/regtest.
