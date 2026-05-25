# AGENTS.md

This repository is an rpk package. The `.rpk/` directory contains the build
scripts and metadata rpk uses to version, package, and install it.

## Key files

- `.rpk/type` — `user` or `system`
- `.rpk/versions` — version ledger; each line: `<semver><TAB><commit-sha>`
- `.rpk/package` — builds a bundle for a given version
- `.rpk/install` (optional) — runs after stow links the bundle
- `.rpk/depends/*` — prerequisite scripts, one per dependency

## Reference

Full packaging guide (the `.rpk/` contract, build-system cookbook, and an
agent playbook for creating packages from upstream repos):

    ~/.local/share/doc/rpk/PACKAGING.md       (user install)
    /usr/local/share/doc/rpk/PACKAGING.md     (system install)
    docs/PACKAGING.md                         (in the rpk source tree)

CLI reference: `man rpk`.

## Common operations

    rpk patch <pkg>            # record a new patch version (current HEAD)
    rpk package <pkg>          # build a bundle for the latest version
    rpk install <pkg>          # package (if needed) and stow into target
    rpk update <pkg>           # pull latest, reinstall if already installed
    rpk show <pkg>             # inspect package state
