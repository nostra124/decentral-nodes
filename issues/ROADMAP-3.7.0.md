# Roadmap — 3.7.0 (minor)

Service-node enhancements: bring the self-hosting nodes (forgejo / webmin
/ usermin) up to the same operability + safety bar as the chain nodes.
Backward-compatible additions only (semver minor). Sequenced after the
atomic-swap work (3.6.0); depends on the self-hosting nodes shipped in
3.5.0.

---

## FEAT-316 — `config` verb for forgejo / webmin / usermin
**File:** `issues/feature/316-config-verb-service-nodes.md`
**Effort:** medium
A `config list|get|set|unset|path` frontend over `app.ini` /
`miniserv.conf`, mirroring `bitcoin/lightning/fulcrum config`
(FEAT-271/272/273/298). Surfaces port, SSL, and the `allow=` host
restriction.

## FEAT-317 — access-control defaults for webmin / usermin
**File:** `issues/feature/317-webmin-usermin-security-defaults.md`
**Effort:** small–medium
`daemon enable [--allow <cidr>...]` writes `allow=` rules; with no flag,
default to a safe, loudly-logged posture rather than listening to the
world silently. Pairs with FEAT-316 (which can read the result).

---

## Recommended order

```
FEAT-316   config frontend — the inspection/edit substrate
FEAT-317   security defaults — builds on the config plumbing
```

## Release gate

- Both verbs covered by man pages + bats (incl. the FEAT-195 boundary
  scan), and the conf mutations are idempotent.
- `VERSION` bumped to `3.7.0`.
