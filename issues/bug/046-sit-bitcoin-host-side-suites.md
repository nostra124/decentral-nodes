---
id: BUG-046
type: bug
priority: medium
status: open
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
