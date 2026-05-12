# `bitcoin`

> Educational Bitcoin wallet + library: sourceable BIP primitives, multi-backend, account-scoped wallet repo

## Install

    git clone https://github.com/nostra124/bitcoin
    cd bitcoin
    ./install --prefix=$HOME/.local

Or in two steps:

    ./configure --prefix=$HOME/.local
    make install

## Quick start

    bitcoin help
    bitcoin version

## Layout

| Path | Purpose |
|---|---|
| `bin/bitcoin` | the entry point |
| `libexec/bitcoin/` | sub-commands (where applicable) |
| `docs/bitcoin.md` | CLI contract reference |
| `share/man/man1/bitcoin.1` | man page |
| `share/doc/bitcoin/standards/` | vendored references (educational) |
| `skills/bitcoin-wallet/` | agent skill |
| `tests/unit/bitcoin.bats` | unit tests |
| `tests/sit/` | system integration (when present) |
| `.cpk/` | container packaging overlay |
| `.rpk/` | rpk metadata (version, versions ledger, depends/) |

## Documentation

- `man bitcoin`
- `docs/bitcoin.md` — CLI contract reference
- `share/doc/bitcoin/standards/README.md` — vendored standards
- `CLAUDE.md` — agent guide
- `skills/bitcoin-wallet/SKILL.md` — agent skill

## Conventions

This package follows the rpk per-script repo convention:

- Per-script repo: this repo contains only `bitcoin`'s artefacts.
- No shared library: helper boilerplate is duplicated, not factored out (see `CLAUDE.md` §4–5).
- Stow-based install via `make install`.
- Versioning: semver, with `VERSION` (project root) as the source of truth and `.rpk/versions` as the per-release SHA ledger. See `skills/version.md` for the bump procedure.

## License

GPL-3 (per the cross-cutting policy in the parent `scripts` collection).
