---
id: FEAT-013
type: feature
priority: high
status: open
---

# Balance, address derivation, and gap-limit scanner

## Description

**As a** wallet user
**I want** to see my balance, list my addresses, and derive the next
unused receive address
**So that** I can actually receive bitcoin into the wallet.

Depends on FEAT-010 (wallet store), FEAT-012 (backend), and benefits
from FEAT-009 (descriptors) for address-policy expression.

## Implementation

Subcommands:

- `bitcoin wallet balance [<wallet>]` — sum of confirmed and
  unconfirmed values across the wallet's UTXOs as reported by the
  backend.
- `bitcoin wallet addresses [<wallet>]` — print every derived address
  with its index, descriptor, and label.
- `bitcoin wallet derive <wallet>` — derive the next address per the
  active descriptor; append to `addresses` and commit. Same-address
  reuse across accounts is acceptable (see FEAT-011), so the index
  is simply incremented locally; no remote-coordination check.
- `bitcoin wallet scan <wallet>` — apply the gap-limit rule
  (default 20): derive forward until N consecutive addresses have no
  on-chain history per the backend; commit any newly-discovered uses.
- `bitcoin wallet label addr <wallet> <address> <label>` — set or
  update the human-readable label on a derived address. Updates the
  `addresses` ledger and commits. `<label>` of empty string clears.

`scan` is the recovery primitive: importing a fresh wallet from seed
+ descriptor and running `scan` recovers all on-chain activity
without needing the wallet's prior `addresses` file.

Gap limit configurable via the descriptor metadata or `--gap N`.

UTXO data lives in `~/.cache/bitcoin/<wallet>/utxos.tsv`, refreshed
by any of the above commands. Cache TTL configurable; `--refresh`
forces.

Help and man page cite BIP-32 (HD derivation), BIP-44/49/84/86
(account-level paths), and link to the vendored copies per FEAT-017.

## Acceptance Criteria

1. `bitcoin wallet derive alice` returns a fresh address each call,
   monotonically incrementing the index, and the wallet repo gains
   one commit per call.
2. `bitcoin wallet balance alice` matches `bitcoin-cli
   getreceivedbyaddress` for the same descriptors on regtest.
3. `bitcoin wallet scan alice` against a freshly imported wallet
   (with only `seed-ref` + `descriptors`, seed reachable via
   `secret`) recovers all addresses that have on-chain history,
   stopping after `gap` consecutive empty addresses.
4. Cache invalidation: a `derive` after a `scan` reuses cached UTXO
   data unless `--refresh` is passed.
5. `bitcoin wallet label addr alice <addr> "donations"` updates the
   ledger; `bitcoin wallet addresses alice` shows the new label;
   the wallet repo gains one commit.
