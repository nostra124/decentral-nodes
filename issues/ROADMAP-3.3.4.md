# Roadmap — 3.3.4 (patch)

Bug-fix-only release: make installs actually work for every node. No new
behaviour (semver patch).

---

## BUG-058 — `make install` ships no verbs for the `-node` commands
**File:** `issues/bug/058-install-node-rename-incomplete.md`
**Effort:** medium (packaging rename completion + `share/` dir moves +
an installed-tree regression test)
The `-node` rename never reached `PACKAGES`/`.rpk` `COMMANDS`/`share/`, so
`make install` stages empty `libexec/<cmd>` dirs and seven nodes aren't
registered at all — every installed node except forgejo/webmin/usermin
has zero verbs. Complete the rename so the installed tree resolves verbs
and prints the right VERSION, with an installed-tree regression test.

---

## Recommended order

```
BUG-058   the only item; lands with its installed-tree regression test
```

## Release gate

- `./configure && make install` to a temp prefix, then every `bin/<cmd>`
  resolves a real verb and `<cmd> version` prints `$(cat VERSION)`.
- `bats tests/unit/*.bats` green (incl. the new installed-tree check).
- `VERSION` bumped to `3.3.4`.
