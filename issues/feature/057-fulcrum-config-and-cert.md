---
id: FEAT-057
type: feature
priority: high
status: open
---

# `fulcrum config` and `fulcrum cert` — render fulcrum.conf and TLS cert

## Description

**As a** node operator standing up Fulcrum
**I want** `fulcrum config init/show/get/set/validate` and a `fulcrum
cert` verb
**So that** I get a working `fulcrum.conf` wired to my local bitcoind
with sane educational defaults, can inspect and tweak the handful of
knobs that matter, and can generate the self-signed certificate the
SSL/WSS port requires.

Fulcrum exposes ~70 config options; surfacing all of them is the wrong
move for an educational tool. `config init` writes a curated default
file (cookie auth to the local node, `tcp` 50001, `ssl` 50002, `admin`
bound to localhost, a reasonable `db_mem`/`fast-sync`), and `config
set` edits only a curated subset. The SSL port needs a PEM cert+key;
`openssl` is already a package dependency (`.rpk/depends/openssl`), so
`fulcrum cert` generates a self-signed pair. Depends on FEAT-055/056.
Out of scope: the admin-RPC verbs (FEAT-058) and the bitcoin backend
(FEAT-059).

## Implementation

`libexec/fulcrum/config`:
- `config init [--ssl|--no-ssl]` — render `fulcrum.conf` into the
  config dir. `bitcoind = 127.0.0.1:8332`; auth defaults to
  `rpccookie = <node datadir>/.cookie`, switching to
  `rpcuser`/`rpcpassword` read from `secret` when the node was brought
  up with `bitcoin daemon enable --public` (rpcauth). `admin` bound to
  `127.0.0.1` only.
- `config show` — print the effective file.
- `config get <key>` / `config set <key> <val>` — operate on a curated
  allow-list (`db_mem`, `fast-sync`, `max_history`, `peering`,
  `announce`, `hostname`, `banner`, `tcp`, `ssl`). Any other key is
  rejected with an `error` naming the key.
- `config validate` — bitcoind RPC reachable? `cert`/`key` present if
  `ssl` is set? configured ports free? Each failed check emits a
  distinct `error` line; exit non-zero if any fail.

`libexec/fulcrum/cert`:
- `cert [--force]` — generate a self-signed `cert.pem`/`key.pem` via
  `openssl req -x509 -newkey ...` into the config dir; refuse to
  overwrite an existing pair without `--force` (warn + non-zero).

## Acceptance Criteria

1. `fulcrum config init` writes a `fulcrum.conf` containing
   `bitcoind`, an auth line (`rpccookie` by default), `tcp`, `ssl`,
   and a localhost `admin` line. Proven by bats asserting on the
   rendered file.
2. With rpcauth configured in `secret`, `config init` emits
   `rpcuser`/`rpcpassword` (read from the secret store, mocked) instead
   of `rpccookie`. Proven by bats with a stubbed `secret`.
3. `config set db_mem 4096` updates only that key and round-trips via
   `config get db_mem`. Proven by bats.
4. `config set <not-in-allowlist> x` is rejected with an `error`
   naming the key and exits non-zero. Proven by bats.
5. `config validate` returns non-zero and emits a per-failure `error`
   when bitcoind is unreachable, when `ssl` is set but the cert is
   missing, and when a configured port is in use — each mocked
   independently. Proven by three bats cases.
6. `fulcrum cert` produces a parseable self-signed `cert.pem`/`key.pem`
   pair (verified with `openssl x509 -noout -in cert.pem`); a second
   run without `--force` refuses and warns. Proven by bats.
