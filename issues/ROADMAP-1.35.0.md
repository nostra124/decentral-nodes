# Roadmap — 1.35.0 (minor)

Fulcrum server management. Ships a second top-level command,
`fulcrum`, from the bitcoin package: standing up, configuring, and
inspecting a Fulcrum Electrum server that indexes the local bitcoind.
This release is the *server-management* half only — the wallet-side
Electrum backend that queries Fulcrum is FEAT-059, scheduled for
1.36.0 (which depends on this release).

All four items are new, backward-compatible behaviour (new command,
new plugins) — hence the minor bump. No existing `bitcoin` contract
changes.

---

## FEAT-055 — Ship a second command (`bin/fulcrum`) from the bitcoin package
**File:** `issues/feature/055-fulcrum-multi-command-packaging.md`
**Effort:** ~120 lines (Makefile/install generalisation + skeleton dispatcher + boundary tests)
Generalise the install path (Makefile, `install` script, shellcheck
lint) from a single `libexec/$(PACKAGE)` tree to every `libexec/*`
tree, and land a skeleton `bin/fulcrum` dispatcher reusing the
SELF-keyed FEAT-001 header. Adds the fulcrum dependency-boundary tests
mirroring FEAT-195. The enabler every other item depends on.

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
verb. Excludes the admin `query` command (belongs to the bitcoin
backend) and the moderation tier (FEAT-060, unscheduled).

---

## Recommended order

```
FEAT-055   packaging + dispatcher — nothing installs without it
FEAT-056   lifecycle — needs the command + libexec install path
FEAT-057   config + cert — enable/start are only useful once a conf exists
FEAT-058   admin inspection — needs the admin port that config init sets up
```

## Release gate

- `make check-unit` green, including the new `tests/unit/fulcrum.bats`.
- `make lint` (shellcheck) green over `bin/fulcrum` and every
  `libexec/fulcrum/*`.
- `make install` into a staging prefix produces both `bitcoin` and
  `fulcrum` binaries and both libexec trees (FEAT-055 AC-1).
- The fulcrum dependency-boundary tests pass and reject a planted
  forbidden-sibling call (FEAT-055 AC-5).
- VERSION bumped to 1.35.0 per skills/version.md.
