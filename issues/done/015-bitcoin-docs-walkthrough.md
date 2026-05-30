---
id: FEAT-015
type: feature
priority: medium
status: done
milestone: 1.29.0
closed: 1.29.0
---

## Progress (1.15.0 shipped — man page + bash completion + walkthrough)

Three of the six acceptance criteria are closed; the remaining
three (SIT validation, default-network configuration, agent
skill) are explicit follow-ups.

- **`share/man/man1/bitcoin.1`** rewritten against the 1.14.0
  verb set. All conventional sections present (NAME, SYNOPSIS,
  DESCRIPTION, OPTIONS, SUBCOMMANDS, ENVIRONMENT, FILES,
  EXIT STATUS, EXAMPLES, STANDARDS, SEE ALSO). DESCRIPTION
  opens with the four design principles (educational,
  functional, decentralized, simple). STANDARDS enumerates
  BIP-13/32/39/141/143/173/174/350/380/381/386 with upstream
  URL and the vendored path under
  `share/doc/bitcoin/bips/`. EXAMPLES walks the cold-signing
  flow in five lines.
- **`etc/bash_completion.d/bitcoin`** rewritten to be
  context-aware. Top-level completion merges the dispatcher's
  built-ins with whatever `bitcoin modules` reports
  (libexec/bitcoin plugins). The wallet, psbt, descriptor, and
  backend subtrees each have their own verb list; `wallet
  remote` and `backend set` go one level deeper.
- **`docs/bitcoin-walkthrough.md`** is the new human-facing
  walkthrough. Opens with the design principles, walks a
  reader from `wallet new` through `wallet derive`, balance
  query, label, the end-to-end `wallet send` pipeline, and the
  cold-signing flow over `wallet push/pull`. Every section
  cites the relevant BIP(s) with both upstream URL and local
  vendored path.

8 new bats tests cover: man page sections present; STANDARDS
section enumerates every implemented BIP; mandoc lint
(skipped where mandoc isn't installed); completion is
source-able; completion offers every wallet subcommand;
completion is context-aware for psbt / backend / descriptor;
walkthrough references every wallet verb; walkthrough cites
the standards table. Total bats now 129.

### Deferred to ROADMAP-1.22.0+

- **AC5** — every walkthrough command exercised by
  `tests/sit/`. Tracked under FEAT-016; needs the podman /
  regtest harness which the cloud sandbox can't run.
- **AI-agent walkthrough** — same content, agent-facing form.
  Tracked under FEAT-019.
- ~~AC6~~ — default network = testnet on a fresh install.
  Closed in 1.21.0: `wallet new` has written
  `network=testnet` to `<wallet>/config` since 1.3.0
  (FEAT-010), and 1.21.0's `wallet send --mainnet` guard
  reads that line and refuses to broadcast against a
  mainnet-configured wallet without explicit opt-in. The
  per-wallet network field is the source of truth; a
  top-level `bitcoin config set network` is not needed for
  the educational walkthrough's threat model.

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
