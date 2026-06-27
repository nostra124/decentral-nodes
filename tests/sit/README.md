# SIT — system integration tests for `lightning`

> Per FEAT-182. End-to-end coverage against a real clightning
> + bitcoind + Apache stack running in a podman container.
> The unit suite at `tests/unit/lightning-*.bats` covers the
> shell verbs in isolation; SIT covers the seams between
> them.

## Layout

    tests/sit/
    ├── podman/
    │   ├── Dockerfile.regtest        # bitcoind regtest base
    │   └── Dockerfile.clightning     # adds lightningd + apache + python3
    │                                  # + the lightning package itself
    ├── helpers.bash                  # shared spin-up: bring up two
    │                                  # lightningd instances, fund them,
    │                                  # connect them, mine some blocks.
    └── suites/
        ├── 01_daemon_lifecycle.bats
        ├── 02_channel_open_close.bats
        ├── 03_invoice_pay_bolt11.bats
        ├── 04_offer_pay_bolt12.bats
        ├── 05_lnurl_flow.bats
        ├── 06_address_create_pay.bats
        ├── 07_wallet_account_ledger.bats
        ├── 08_wallet_push_pull.bats
        ├── 09_inbound_liquidity_lsps1.bats
        ├── 10_wellknown_api.bats
        ├── 11_walkthrough.bats           # locked to FEAT-181
        └── 12_softdep_probe.bats         # missing lightning-cli /
                                           # python3 / apache2 fail clearly

## Running

    # From the repo root:
    make check-sit

The make target soft-skips when `podman` isn't installed,
so CI without container support reports a clean
"skipping" rather than a failure.

> **Podman present ≠ SIT runnable (cloud-sandbox limits, measured
> 2026-06-27).** The Claude Code on the web SessionStart hook
> (FEAT-309) installs `podman`, but two further constraints mean the
> SIT tiers still cannot complete in that sandbox — they need a
> desktop / CI host with real egress:
> - **Run-time containers have no outbound network.** `podman run`
>   containers can't reach external hosts (the agent proxy listens on
>   the host loopback, outside the container netns). Direct fetches to
>   `codeberg.org` / `dl.forgejo.org` / `download.webmin.com` fail at
>   both build *and* run time, so any suite whose flow downloads a
>   service (the FEAT-315 `*-node daemon install` step) can't proceed.
>   `apt` works at build time only because the Debian mirror is
>   proxied. Run `make check-sit` where containers have unrestricted
>   egress.
> - **The bitcoin host-side suites need the rpk sibling stack.**
>   `02_derive_and_receive.bats` (the FEAT-304 proof) calls
>   `sit:install_bitcoin`, which needs `bitcoin-cli` on the host plus
>   the `account` / `secret` sibling commands (`bitcoin wallet new`
>   stores the seed via `secret`). Those are separate `nostra124/rpk`
>   packages, absent from a bare cloud sandbox. Install the rpk
>   siblings + Bitcoin Core first.

Internally it does:

    podman build -t lightning-regtest    -f tests/sit/podman/Dockerfile.regtest    tests/sit
    podman build -t lightning-clightning -f tests/sit/podman/Dockerfile.clightning .
    podman run --rm \
        -v $PWD/tests/sit/suites:/suites:ro \
        lightning-clightning \
        /bin/bash -c "bats /suites/*.bats"

The clightning Dockerfile copies the whole repo into the
image, so `lightning` inside the container is whatever
your working tree is — no need to install before running.

> **Status of the legacy `make check-sit` images (rebuilt 2026-06-08):**
> - `Dockerfile.regtest` — **fixed + builds**: Debian dropped
>   the `bitcoind` apt package, so it installs the official
>   multi-arch Bitcoin Core release binaries.
> - `Dockerfile.clightning` — **builds, installs, and the
>   stack comes up**: `lightningd` (also absent from apt) is
>   copied from the upstream `polarlightning/clightning`
>   image; the bogus `libapache2-mod-cgi` package was dropped
>   (mod_cgi ships in `apache2` on bookworm) and `sudo` added.
>   The Makefile `stow`/double-prefix packaging bug it used to
>   hit is fixed (`make install` installs directly into
>   `$PREFIX`), so the `lightning` CLI installs world-executably.
>   A `clightning-entrypoint.sh` now brings the whole regtest
>   stack up under one user — **bitcoind + lightningd (regtest,
>   synced) + apache** — verified live (`getinfo` returns a
>   regtest node). Run it: `podman run --rm lightning-clightning`.
> - **CGI account API — mostly wired, one residual:** the
>   container threads `LIGHTNING_NETWORK=regtest` to the
>   sudo-bridged verbs (apache `SetEnv` + sudoers `env_keep`),
>   and two **real apache-conf bugs were fixed in the source
>   `lnurlp.conf`**: `CGIPassAuth On` (Apache 2.4.13+ strips
>   `Authorization`, so every bearer endpoint 401'd) and
>   `AcceptPathInfo On`. Verified working: `GET /v1/health`
>   returns `{"ok":true,"daemon":true,…}` (full chain
>   apache→CGI→sudo→verb→lightningd), and bare `/v1/accounts`
>   now returns a proper `401` instead of an empty body.
>   **Residual:** sub-path routes (`/v1/accounts/<id>/balance`)
>   still 404 — a further Apache PATH_INFO nuance, undiagnosed.
> - **Remaining:** finish the sub-path routing, then validate
>   the 12 SIT suites (their `helpers.bash` needs
>   `LIGHTNING_NETWORK=regtest`). These are prerequisites for
>   the `2.0.0` shadow-run parity diff (FEAT-326).
>
> The bash-verb **unit** suite is the primary gate today.

> **thunderd moved out (2.0.0).** The Rust `thunderd` daemon
> and its live-node integration harness now live in the
> sister repo `nostra124/thunder`. As of 2.0.0 the account
> API is served by thunderd; this package reverse-proxies
> `/.well-known/lightning/v1/accounts` to it (see
> `share/lightning/apache/lnurlp.conf`).

## What's NOT covered here

- Real LSP / Loop / Boltz endpoints. The
  `09_inbound_liquidity_lsps1.bats` suite uses a stub
  LSPS1 server inside the container; it proves the wire
  shape, not the third-party behaviour.
- Real DNS publishing for BIP-353. The suite uses
  `/etc/hosts` to point `example.com` at `127.0.0.1`.
- TLS. The Apache vhost in the container serves over
  plaintext HTTP because `127.0.0.1` doesn't need it; do
  not deploy this way in production.

## Determinism

Each suite uses fresh state: a clean wallet repo, fresh
bitcoind blocks mined into a known address, fresh
clightning data dirs. Helpers tear down between tests so
runs are independent.

## When a suite fails

The container logs are written to
`tests/sit/out/<suite>.log`. Reproduce locally:

    podman run -it --rm \
        -v $PWD/tests/sit/suites:/suites:ro \
        lightning-clightning \
        bats /suites/<suite>.bats
