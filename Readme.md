# `decentral-nodes` — decentralized infrastructure toolkit

> Educational toolkit for decentralized infrastructure: Bitcoin, Lightning,
> privacy tools (Tor/I2P/JoinMarket), storage (IPFS/Storj), and naming (Handshake)
> — shipped from one rpk package with multiple command dispatchers.

This repository provides a unified toolkit for decentralized infrastructure.
It includes Bitcoin/Lightning tools, privacy tools (Tor, I2P, JoinMarket),
storage (IPFS, Storj), and naming services (Handshake). Each tool has its
own dispatcher and libexec tree.

| Command | Purpose |
|---|---|
| `bin/bitcoin-node` | BIP plugins (BIP 13/32/39/173/174/340/341/350/380, WIF), wallet surface, daemon abstraction |
| `bin/lightning-node` | Core-Lightning (clightning) frontend: channels, invoices, payments, LNURL, the `.well-known/lightning/` HTTP API |
| `bin/fulcrum-node` | Electrum/Fulcrum index server frontend |
| `bin/liquid-node` | Liquid Network (Elements) frontend: peg-ins, peg-outs, assets |
| `bin/monero-node` | Monero node frontend: wallet, daemon, transactions |
| `bin/stacks-node` | Stacks node frontend: Bitcoin-aware smart contracts |

**Tier 2** (Network Privacy): `tor-node`, `ipfs-node` — implemented; `m2pd-node` (external: github.com/nostra124/m2pd)

**Tier 3** (Advanced): `joinmarket-node`, `storj-node`, `forgejo-node` (self-hosted Git forge + CI runners), `webmin-node` (web system administration) — implemented; `hns-node` (Handshake), `yggdrasil-node` — planned

## Install

    git clone https://github.com/nostra124/decentral-nodes
    cd decentral-nodes
    ./install --prefix=$HOME/.local

Or in two steps:

    ./configure --prefix=$HOME/.local
    make install

`make install` stages every command in one stow tree and symlinks it into
`$PREFIX`.

## Quick start

    bitcoin help
    bitcoin version
    lightning help
    lightning version

## Layout

| Path | Purpose |
|---|---|
| `bin/bitcoin-node`, `bin/lightning-node` | entry points (one dispatcher per command) |
| `libexec/bitcoin-node/`, `libexec/lightning-node/` | per-command sub-commands / plugins |
| `share/<cmd>/` | per-command runtime assets (wordlists, schema.sql, hooks, CGI) |
| `share/doc/<cmd>/` | per-command docs + vendored standards (BIPs, BOLTs, LNURL) |
| `share/man/man1/<cmd>-*.1` | man pages |
| `docs/bitcoin-walkthrough.md`, `docs/lightning.md` | CLI references / walkthroughs |
| `share/doc/lightning/walkthrough/README.md` | Lightning hands-on walkthrough |
| `tests/unit/*.bats` | unit tests (bitcoin + lightning) |
| `tests/python/` | pytest for the lightning CGI / HTTP API |
| `tests/sit/` | system integration (podman; bitcoind + clightning regtest) |
| `.rpk/` | rpk metadata (identity, version, versions ledger, depends/) |

## Documentation

- `man bitcoin-node`, `man lightning-node`
- `docs/bitcoin-walkthrough.md`, `docs/lightning.md` — CLI references
- `share/doc/lightning/walkthrough/README.md` — Lightning walkthrough
- `share/doc/bitcoin/bips/` — vendored BIPs
- `share/doc/lightning/standards/` — vendored BOLTs + LNURL specs
- `CLAUDE.md` — agent guide
- `.rpk/skills/*.md` — agent skills (bitcoin + lightning)

## Conventions

This package follows the rpk per-package convention, generalised to ship
multiple commands from one identity:

- One rpk package (`decentral-nodes`), multiple dispatchers. Each command keeps
  its own namespaced `libexec/<cmd>/`, `share/<cmd>/`, `share/doc/<cmd>/`.
- No shared library: helper boilerplate is duplicated per command, not
  factored out (see `CLAUDE.md` §4–5). Commands do not shell out to each other.
- Stow-based install via `make install`.
- Versioning: semver, with `VERSION` (project root) as the source of
  truth and `.rpk/versions` as the per-release SHA ledger. See
  `skills/version.md` for the bump procedure.

## License

GPL-3 (per the cross-cutting policy in the parent `scripts` collection).
