# Roadmap — 1.3.0 (minor)

The wallet model lands. After 1.0.x–1.2.x established test
infrastructure, 1.3.0 is the first release where `bitcoin` actually
holds a wallet: a git-backed signing context whose seed lives in
`secret`, separated cleanly so the repo can be pushed without
leaking key material.

This release also lays the BIP-citation groundwork that every
subsequent feature ticket promises ("cite the relevant BIP and link
to the vendored copy"). Doing it now means 1.4.0+ inherit a
working citation pipeline instead of bolting one on per feature.

Depends on 1.2.0 (the test infrastructure required to validate the
wallet operations cheaply).

---

## FEAT-010 — Wallet store as a git repository
**File:** `issues/feature/010-wallet-store-as-git-repo.md`
**Effort:** ~1–2 days
The wallet's persistent state — descriptors, address ledger,
history, in-flight PSBTs — lives in a git repo per wallet name.
Seed phrase stays in `secret`, never in the repo. This is the
foundation for FEAT-011 (push/pull), FEAT-013 (balance/scan),
FEAT-014 (tx builder), FEAT-018 (tx index).

## FEAT-017 — Vendor BIP source documents and cite them
**File:** `issues/feature/017-vendor-and-cite-bips.md`
**Effort:** ~half day for vendoring + citation template
Establishes the "vendor a copy under `share/doc/bitcoin/standards/`
and cite by number+title+URL" convention referenced by every
BIP-implementing feature ticket (007–014). Doing it now means
1.4.0+ can use the citation template instead of inventing one.

---

## Recommended order

```
FEAT-017  (BIP vendoring template — foundation cited by everything below)
FEAT-010  (wallet store — the load-bearing change of the release)
```

## Release gate

- `bitcoin wallet new <name>` initialises a git repo at the
  wallet's well-known path (`$XDG_DATA_HOME/bitcoin/wallets/<name>/`
  or per the FEAT-010 spec).
- `bitcoin wallet new <name>` calls `secret put <name>/seed` for
  the BIP-39 mnemonic; the repo never contains the seed.
- `bitcoin wallet ls` lists existing wallets.
- `bitcoin wallet rm <name>` removes the repo and (with `--force`
  or equivalent) the secret.
- Every subcommand exits non-zero with a clear `error` line
  (per `skills/logging.md`) on missing wallet, missing secret, or
  filesystem failure.
- `share/doc/bitcoin/standards/` contains vendored copies of every
  BIP `bitcoin` currently implements (13, 32, 39, 173, 350) plus
  WIF.
- `bitcoin help` / `man bitcoin` cite each implemented BIP with
  number, title, and URL.
- bats coverage: at least 4 new tests for wallet new / ls / rm
  happy paths and the seed-not-in-repo invariant.
- Pre-push hook + CI green on the milestone PR.

## Out of scope (future roadmaps)

- Push/pull between wallets (FEAT-011, planned 1.6.0+)
- Backend abstraction (FEAT-012, planned 1.4.0)
- Balance, derive, scan (FEAT-013, planned 1.4.0)
