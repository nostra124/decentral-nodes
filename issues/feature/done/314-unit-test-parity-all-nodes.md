---
id: FEAT-314
type: feature
priority: medium
status: done
milestone: 3.4.0
---

# Unit-test parity: a bats suite for every node dispatcher

## Summary

Seven shipping dispatchers have **no unit tests at all** — `tor-node`,
`ipfs-node`, `storj-node`, `joinmarket-node`, `liquid-node`,
`stacks-node`, `i2pd-node`. (bitcoin/lightning/fulcrum/monero are covered
under their base-name suites; forgejo/webmin/usermin got suites this
cycle.) Every dispatcher should have at least the shared contract suite.

## Acceptance criteria

1. A `tests/unit/<node>.bats` for each of the seven untested dispatchers,
   asserting the shared dispatcher contract:
   - `<node> version` equals `$(cat VERSION)`;
   - `<node> help` exits 0 and lists its verbs;
   - unknown verb exits non-zero naming the verb;
   - FEAT-195 forbidden-sibling scan over `bin/<node>` +
     `libexec/<node>/*`;
   - `PACKAGES`/`.rpk` registration + `make install` staging.
2. A meta-guard (extending `tests/unit/dispatcher-paths.bats`) that fails
   if any `bin/*-node` lacks a corresponding unit suite — so future nodes
   can't ship untested.

## Notes

Mirror the `forgejo-node.bats` / `webmin-node.bats` structure. Depends on
BUG-058 (the packaging fix) so the `make install` assertions are
meaningful for these nodes.
