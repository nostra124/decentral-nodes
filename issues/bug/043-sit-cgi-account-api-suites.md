---
id: BUG-043
type: bug
priority: medium
status: open
---

# SIT — the apache CGI account-API / LNURL / walkthrough suites are unverified against the live stack

## Severity

**Medium.** These suites exercise the apache sudo-bridge account API (FEAT-196)
and the Lightning Address / LNURL path (FEAT-176/210) — a different subsystem
from the raw `lightning` verbs. The container already brings apache up and
threads `LIGHTNING_NETWORK=regtest` through the CGI (BUG-038), but the API flows
have never run green.

## Scope (container suites)

- `10_wellknown_api` — `wrong API key returns 401 with no body`, `overdraft=deny
  + insufficient balance returns 402`.
- `05_lnurl_flow` — alice pays a LUD-06 endpoint and the response BOLT-11
  settles (spans apache CGI → BOLT-11 pay).
- `11_walkthrough` — the end-to-end §1–§7 narrative (node reachable → wallet new
  → channel open → BOLT-11 pay → BOLT-12 offer-pay → address create).

## Observed (last full run)

```
not ok 10 wrong API key returns 401 with no body
not ok 11 overdraft=deny + insufficient balance returns 402
not ok 7  alice pays a LUD-06 endpoint and the response BOLT-11 settles
not ok 12..17 §1 reachable / §2 wallet new / §3 channel open / §4 BOLT-11 /
              §5 BOLT-12 / §7 address create
```

The walkthrough §steps reuse the channel/pay machinery, so they overlap
[[BUG-042]] and [[BUG-041]]; the API-specific assertions (401/402, CGI auth,
PathInfo) are the genuinely separate part. Triage the apache/CGI layer (sudoers
`env_keep`, `CGIPassAuth`, `AcceptPathInfo`, the SQLite balance the 402 path
reads) independently.

## Acceptance

`10_wellknown_api`, `05_lnurl_flow`, and `11_walkthrough` pass under
`make check-sit`. Any genuine CGI/auth bug gets its own ticket + regression
(`tests/python/` covers the CGI layer).

Depends on [[BUG-041]]/[[BUG-042]] for the channel/pay steps.
