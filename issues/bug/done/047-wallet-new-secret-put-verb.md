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

## Follow-up caveat

The verb fix (`put`→`set`) is correct and unit-verified, but on a real system
`wallet new` then reaches `secret: store <name> does not exist` — `secret set
<store>/<param>` needs the store provisioned. The unit `secret` stub auto-creates
the path, so it doesn't exercise this. Whether `wallet new` should create the
secret store itself (vs. requiring `secret` to be pre-initialised) is an open
question tracked with the secret/gpg provisioning work in [[BUG-046]]/[[BUG-043]].
