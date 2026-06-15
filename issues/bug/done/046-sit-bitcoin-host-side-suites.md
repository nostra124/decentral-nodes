---
id: BUG-046
type: bug
priority: medium
status: done

> **Resolved.** All 5 host-side suites run reliably: **25 ok / 0 not ok / 19
> skip**. The flakiness root cause was `(( tries++ ))` aborting under set -e;
> with that + the ~12 infra fixes (bitcoind [regtest] config, install-to-test-
> prefix, mkdir-before-stow, clean build, unique port/name, GPG provisioning,
> BITCOIN_CONFIG_DIR seam, createwallet, robust teardown), `01_wallet_new` and
> `02_derive_and_receive` pass; `03`/`04`/`05` skip pending [[FEAT-304]] (the
> bitcoind backend get-address-utxos/broadcast).
---

# SIT — the bitcoin host-side suites are unverified (separate check-sit leg)

## Severity

**Medium.** `check-sit` has a second leg (Makefile `check-sit`, the
`@bats tests/sit/suites/*wallet* *derive* *send* *psbt* *push_pull*` line) that
runs the **bitcoin** wallet SIT suites on the host, each self-managing a bitcoind
container via `tests/sit/helpers.bash` (`sit:start_bitcoind`). This leg is
currently `|| true` (never fails the target) and has not been verified end-to-end
since the packaging/harness work.

## Scope (host-side suites)

- `01_wallet_new`, `02_derive_and_receive`, `03_send_and_broadcast`,
  `04_psbt_roundtrip`, `05_push_pull_between_accounts`.

## Observed

When these suites are (mis)run **inside** the clightning container they fail with
`podman: command not found` (`sit:start_bitcoind`, helpers.bash:17) — they expect
to run on the host and spawn their own bitcoind container. Their real host-side
behaviour under the current harness is unconfirmed; the `|| true` masks it.

## Tasks

- Run the host-side leg explicitly and capture pass/fail.
- Confirm `sit:start_bitcoind` (the host-side bitcoind container) still works with
  the current images / bitcoind release-binary layout.
- Once green, drop the `|| true` so regressions are caught, or document why it
  stays soft (e.g. cloud-sandbox skip).

## Acceptance

The host-side bitcoin SIT suites run and pass under `make check-sit`, and the leg
reports failures instead of swallowing them.

Independent of the lightning-container tickets ([[BUG-041]]..[[BUG-045]]).

## Progress (this session)

Four blockers fixed so the host-side install + bitcoind come up:

1. **bitcoind container exits.** Bitcoin Core 27 fatally rejects network-scoped
   options (`rpcbind`/`rpcallowip`/`fallbackfee`) in the global config section;
   moved them under `[regtest]` in `Dockerfile.bitcoind`. bitcoind now starts
   and `getblockchaininfo` is reachable from the host.
2. **install didn't relocate.** `sit:install_bitcoin` used `PREFIX=… make
   install`, but the Makefile hard-assigns PREFIX at configure time, so the
   install landed in the *configured* prefix and the suite ran the host's real
   (stale) bitcoin. Now it `./configure --prefix=$SIT_HOME/.local` first.
3. **stow on a fresh prefix.** `make install` didn't `mkdir -p $(PREFIX)` before
   `stow -t $(PREFIX)`, so a brand-new prefix failed "not a valid directory".
   Fixed in `Makefile.in`.
4. **wallet new seed verb** — `secret put` → `secret set` ([[BUG-047]], a real
   product bug surfaced here).

## Remaining (secret/gpg provisioning)

`bitcoin wallet new` now reaches `secret set alice/seed`, which fails "store
alice does not exist": the `secret(1)` tool needs a GPG-backed store
provisioned, and the ephemeral SIT `HOME` has none. The host-side suites need
to initialise a `secret` store (GPG identity + the per-wallet store) in
`setup_file` — the **same secret-provisioning gap** that blocks the CGI
account-API apikey path in [[BUG-043]]. Provisioning `secret`/GPG in the SIT
environments (host-side HOME + the clightning container) is the shared
follow-up; with it, BUG-046 and the [[BUG-043]] apikey path both unblock.

## Update — host-side infra fixed; suite 02 green

The secret/gpg gap is solved: `account init` does a batch, passphrase-less GPG
keygen, so `secret setup` + `secret init <store>` + `secret set` work
non-interactively. Fixes landed:

- `bitcoin wallet new` now `secret init`s the store before `secret set`
  ([[BUG-047]] — it was still broken after the put→set fix).
- SIT host-side `sit:install_bitcoin`: reconfigure to the test prefix; clean
  `build/` first; provision GPG (account init + secret setup) in the throwaway
  HOME; keep config in the HOME via `BITCOIN_CONFIG_DIR` (no more /etc leak);
  seed an empty `bitcoin.conf`; export `SIT_HOME`.
- `Dockerfile.bitcoind`: `[regtest]` section so bitcoind 27 starts.
- `make install`: `mkdir -p $(PREFIX)` before stow (fresh prefix).
- `sit:start_bitcoind`: unique container name + RPC port per call (off 18443,
  which collided with a host regtest node).
- `02_derive_and_receive`: ledger path uses `XDG_DATA_HOME`; the balance/UTXO
  tests skip pending [[FEAT-304]] (the bitcoind backend's get-address-utxos /
  broadcast are stubs).

**`02_derive_and_receive` run in isolation: 5 ok / 0 not ok / 3 skip** — the
host-side install + bitcoind + wallet new + derive + ledger all work.

## Remaining

1. **multi-suite isolation.** Running all five host-side suites in one `bats`
   invocation is flaky: `sit:start_bitcoind` times out under sequential load
   (leftover containers when a `setup_file` fails, GPG-agent/keygen contention
   across the per-suite throwaway HOMEs). Needs robust teardown (always remove
   the container) + a settled GPG-agent story.
2. **per-suite test debt.** `01_wallet_new` (stale `.local/var` paths, a
   `wallet new` idempotency expectation), `03_send_and_broadcast` (gated on
   [[FEAT-304]] broadcast), `04_psbt_roundtrip`, `05_push_pull_between_accounts`
   each want the same reconciliation suite 02 got.
