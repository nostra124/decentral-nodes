---
id: BUG-047
type: bug
priority: high
status: done
---

# `bitcoin wallet new` uses `secret put`, but the verb is `secret set` — seed never stored

## Severity

**High.** `bin/bitcoin`'s `wallet new` stored the generated seed with
`secret put <name>/seed`, but the `secret(1)` tool's write verb is `set`
(reads use `get`). So `secret put` fails with "unknown command put", `wallet
new` exits 9 ("'secret put …/seed' failed"), and no wallet can be created.
Every read path already used the correct `secret get`. Surfaced by the SIT
host-side derive suite ([[BUG-046]]).

## Fix

`bin/bitcoin`: `secret put "$name/seed"` → `secret set "$name/seed"` (and the
two doc comments). The unit `secret` stub modelled the wrong verb (`put`), which
is why the existing FEAT-010 tests passed against the bug; the stub now models
the real `set`/`get`, turning "wallet new stores the seed via secret" into the
regression — it fails against `put`, passes against `set`.

## Regression

`tests/unit/bitcoin.bats` "FEAT-010 — wallet new stores the seed via secret".
