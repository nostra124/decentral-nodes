# `bitcoin` — the combined Bitcoin stack

> Educational Bitcoin + Lightning toolkit: sourceable BIP primitives,
> multi-backend wallet, and a Core-Lightning frontend — shipped from one
> rpk package with multiple command dispatchers.

This repository merges the former `nostra124/lightning` repo into
`nostra124/bitcoin` so the full stack lives in one tree. Today it ships
two dispatchers; a third (`bin/fulcrum`, the Electrum/Fulcrum server
frontend, FEAT-055..060) slots into the same layout when it lands.

| Command | Purpose |
|---|---|
| `bin/bitcoin` | BIP plugins (BIP 13/32/39/173/174/340/341/350/380, WIF), wallet surface, daemon abstraction |
| `bin/lightning` | Core-Lightning (clightning) frontend: channels, invoices, payments, LNURL, the `.well-known/lightning/` HTTP API |
| `bin/fulcrum` | *(planned)* Electrum/Fulcrum index server frontend |

## Install

    git clone https://github.com/nostra124/bitcoin
    cd bitcoin
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
| `bin/bitcoin`, `bin/lightning` | entry points (one dispatcher per command) |
| `libexec/bitcoin/`, `libexec/lightning/` | per-command sub-commands / plugins |
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

- `man bitcoin`, `man lightning`
- `docs/bitcoin-walkthrough.md`, `docs/lightning.md` — CLI references
- `share/doc/lightning/walkthrough/README.md` — Lightning walkthrough
- `share/doc/bitcoin/bips/` — vendored BIPs
- `share/doc/lightning/standards/` — vendored BOLTs + LNURL specs
- `CLAUDE.md` — agent guide
- `.rpk/skills/*.md` — agent skills (bitcoin + lightning)

## Conventions

This package follows the rpk per-package convention, generalised to ship
multiple commands from one identity:

- One rpk package (`bitcoin`), multiple dispatchers. Each command keeps
  its own namespaced `libexec/<cmd>/`, `share/<cmd>/`, `share/doc/<cmd>/`.
- No shared library: helper boilerplate is duplicated per command, not
  factored out (see `CLAUDE.md` §4–5). `bitcoin` and `lightning` do not
  shell out to each other.
- Stow-based install via `make install`.
- Versioning: semver, with `VERSION` (project root) as the source of
  truth and `.rpk/versions` as the per-release SHA ledger. See
  `skills/version.md` for the bump procedure.

## License

GPL-3 (per the cross-cutting policy in the parent `scripts` collection).
