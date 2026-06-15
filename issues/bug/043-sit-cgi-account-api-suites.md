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

## Findings (this session)

`11_walkthrough` and `06_address_create_pay` are **green** now (the verb +
PATH fixes from [[BUG-042]]). Two clusters remain, both deeper FEAT-196 / LNURL
integration, not stale verbs:

1. **`10_wellknown_api` (recv/balance/401/402) — two blockers:**
   - **`secret` not in the SIT container.** `lightning account apikey create`
     fails with "the `secret` package is required", so `API_KEY` is empty and
     the auth tests can't run. The image needs the rpk `secret` tool installed
     (the account API stores keys in `secret`).
   - **apache 404.** `curl http://example.com/.well-known/lightning/alice/recv`
     returns **404** even though the CGI scripts are present + executable at
     `/usr/local/share/lightning/wellknown/lightning/{recv,send,balance}.py` and
     `lightning.conf` has the RewriteRule + ScriptAlias. The
     RewriteRule→ScriptAlias routing (or `AllowOverride`/`Options +ExecCGI` on
     that path, or the `example.com` vhost) needs debugging.
2. **`05_lnurl_flow` — client LNURL verb.** `node lnurl-info <raw-url>` doesn't
   return the stub's `callback` JSON; the client-side LNURL-pay path may expect
   a `user@domain` / bech32 `lnurl1…` rather than a raw URL, or needs a
   different verb. Low value (the server LNURL is covered by 06/10).

## Acceptance

`10_wellknown_api`, `05_lnurl_flow`, and `11_walkthrough` (done) pass under
`make check-sit`. The wellknown cluster needs the `secret` package in the image
+ the apache route fixed; any genuine CGI/auth bug gets its own ticket +
regression (`tests/python/` covers the CGI layer).

Depends on [[BUG-041]]/[[BUG-042]] for the channel/pay steps.
