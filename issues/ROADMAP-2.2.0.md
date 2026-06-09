# Roadmap — 2.2.0 (minor)

Fulcrum as a wallet backend. Wires the `bitcoin` side to the Fulcrum
server stood up in 2.1.0: a `fulcrum` Electrum-protocol backend so
`wallet balance` / `wallet index` / `broadcast` query the operator's
own node instead of the public mempool.space API.

**Prerequisite:** 2.1.0 (a runnable Fulcrum server). This release is
deliberately split from 2.1.0 because it touches a different surface
(the `backend` abstraction, FEAT-012) and is independently testable
against a stubbed Electrum responder.

New, backward-compatible behaviour (a new backend option; existing
backends and the default are unchanged) — hence the minor bump.

---

## FEAT-059 — `bitcoin backend set fulcrum`
**File:** `issues/feature/059-fulcrum-electrum-backend.md`
**Effort:** ~220 lines (Electrum client + 5 backend verbs + wiring tests)
Fills in the `fulcrum` backend in the existing abstraction: an
Electrum-protocol client (scripthash mapping + `listunspent` /
`get_history` / `headers.subscribe` / `transaction.broadcast` /
`estimatefee`) speaking to the server's tcp/ssl port. Lives entirely
inside the bitcoin backend per the no-shared-lib boundary (CLAUDE.md
§4) — it never shells out to the `fulcrum` command. Output shapes
match the mempool backend so the wallet code path is unchanged.

---

## Recommended order

```
FEAT-059   single item
```

## Release gate

- `make check-unit` green, including new backend bats cases against a
  stubbed Electrum responder (FEAT-059 AC-2..6).
- The FEAT-195 dependency-boundary tests remain green (the backend
  adds no forbidden sibling call — FEAT-059 AC-7).
- `wallet balance` wiring test passes with `fulcrum` as the active
  backend (FEAT-059 AC-6).
- VERSION bumped to 2.2.0 per skills/version.md.
