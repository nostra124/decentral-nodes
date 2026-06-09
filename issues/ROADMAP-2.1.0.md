# Roadmap — 2.1.0 (minor)

Fulcrum server management. Ships a third top-level command,
`fulcrum`, from the bitcoin package: standing up, configuring,
inspecting, and moderating a Fulcrum Electrum server that indexes the
local bitcoind. This release is the *server-management* half only — the
wallet-side Electrum backend that queries Fulcrum is FEAT-059,
scheduled for 2.2.0 (which depends on this release).

All five items are new, backward-compatible behaviour (new command,
new plugins) — hence the minor bump. No existing `bitcoin` or
`lightning` contract changes.

> **Note (post-merge baseline):** the multi-command packaging
> groundwork is **already done**. The `nostra124/lightning` merge
> (2.0.0) generalised `Makefile.in`, `.rpk/package`, and the
> `lint`/`install` targets to loop over `PACKAGES` (currently
> `bitcoin lightning`) and per-command `libexec/<cmd>` /
> `share/<cmd>` / `share/doc/<cmd>` trees. So FEAT-055 is now mostly
> "add `fulcrum` to that list + drop in the dispatcher", not a build
> rewrite — its scope and estimate below are reduced accordingly.

---

## FEAT-055 — Ship a third command (`bin/fulcrum`) from the bitcoin package
**File:** `issues/feature/055-fulcrum-multi-command-packaging.md`
**Effort:** ~60 lines (dispatcher + add to `PACKAGES` + boundary tests)
The packaging path is already multi-command after the lightning merge,
so this shrinks to:
- Add `fulcrum` to `PACKAGES` in `Makefile.in` (and `COMMANDS` in
  `.rpk/package`) so install/lint pick up `bin/fulcrum`,
  `libexec/fulcrum/`, `share/fulcrum/`, `share/doc/fulcrum/`.
- Land a skeleton `bin/fulcrum` dispatcher reusing the SELF-keyed
  FEAT-001 header (same shape as `bin/bitcoin` / `bin/lightning`).
- Add the fulcrum dependency-boundary tests mirroring FEAT-195
  (`tests/unit/fulcrum.bats`), rejecting forbidden sibling calls.
The enabler every other item depends on.

## FEAT-056 — `fulcrum` service lifecycle
**File:** `issues/feature/056-fulcrum-service-lifecycle.md`
**Effort:** ~300 lines (plugin + unit templates, modelled on daemon/FEAT-034)
`install / enable / disable / start / stop / monitor / space` as
`libexec/fulcrum/service`, with systemd/launchd unit templates and the
`$FULCRUM_ROOT`/`$FULCRUM_OS` mockable matrix. `enable` fails loudly if
bitcoind RPC is unreachable.

## FEAT-057 — `fulcrum config` and `fulcrum cert`
**File:** `issues/feature/057-fulcrum-config-and-cert.md`
**Effort:** ~200 lines (two plugins)
`config init/show/get/set/validate` renders a curated `fulcrum.conf`
wired to the local node (cookie auth by default, rpcauth from `secret`
when present); `cert` generates the self-signed PEM pair the SSL port
needs via the already-vendored `openssl`.

## FEAT-058 — `fulcrum` admin inspection
**File:** `issues/feature/058-fulcrum-admin-inspection.md`
**Effort:** ~180 lines (admin-RPC client + verbs)
`info / sync / stats / clients / logs / version` over the localhost
admin port. `sync` (progress vs node tip) is the headline educational
verb. Lands the `admin:_call` client that FEAT-060 builds on. Excludes
the admin `query` command (belongs to the bitcoin backend); the
moderation tier is FEAT-060, below.

## FEAT-060 — `fulcrum` advanced admin tier (peers / ban / unban / kick / loglevel)
**File:** `issues/feature/060-fulcrum-admin-moderation.md`
**Effort:** ~120 lines (thin admin-RPC wrappers + per-verb bats)
The operational/moderation half of the admin surface, built on the
`admin:_call` client from FEAT-058:
- `peers` / `addpeer <host>` / `rmpeer <host>` — peer-list management.
- `ban <id|ip>` / `unban <ip>` / `banlist` — client/IP bans.
- `kick <id|ip>` — disconnect a client.
- `loglevel <normal|debug|trace>` — runtime verbosity (rejects bad
  values before any call).
Each wraps the matching `FulcrumAdmin` method and reports the server's
reply; an unreachable admin port → `warn`/`error` naming the address
and non-zero exit (same contract as FEAT-058). Pulled into this release
so the `fulcrum` admin surface ships complete in one go.

---

## Recommended order

```
FEAT-055   packaging + dispatcher — nothing installs without it
FEAT-056   lifecycle — needs the command + libexec install path
FEAT-057   config + cert — enable/start are only useful once a conf exists
FEAT-058   admin inspection — needs the admin port that config init sets up;
                              lands the admin:_call client
FEAT-060   admin moderation — thin wrappers on FEAT-058's admin:_call
```

## Release gate

- `make check-unit` green, including the new `tests/unit/fulcrum.bats`.
- `make lint` (shellcheck) green over `bin/fulcrum` and every
  `libexec/fulcrum/*` (the `lint` target already loops `PACKAGES`).
- `make install` into a staging prefix produces all three — `bitcoin`,
  `lightning`, and `fulcrum` — binaries and every `libexec/<cmd>` tree,
  with `fulcrum` added to `PACKAGES` (FEAT-055 AC-1).
- The fulcrum dependency-boundary tests pass and reject a planted
  forbidden-sibling call (FEAT-055 AC-5).
- Every `fulcrum` admin verb (FEAT-058 + FEAT-060) is asserted against
  a fixture admin responder, and `loglevel <bad-value>` is rejected
  before any call (FEAT-060 AC-1/AC-2).
- VERSION bumped to 2.1.0 per skills/version.md.
