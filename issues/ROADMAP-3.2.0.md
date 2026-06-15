# Roadmap — 3.2.0 (minor)

First milestone of the **`monero`** command: a Monero node + installer, slotting
into the combined stack exactly like `lightning`/`fulcrum` (CLAUDE.md §0). This
release ships only the **node/daemon/install/config** surface — the wallet
(3.3.0) and decentralized mining via P2Pool + xmrig (3.4.0) are separate
milestones that build on it.

Design decisions locked in review: install from **official release tarballs**
(GPG signing key + SHA256), **`--system` default** with `--user` opt-in, and a
phased node → wallet → mining rollout. The new command keeps the package
identity `bitcoin` (one rpk package, many dispatchers), the no-shared-lib policy
(§4: only `account`/`config`/`secret`/`crypt`), `/etc/monero` config, and its own
man pages + `tests/unit/monero.bats` contract joined into the combined suite.

---

## FEAT-299 — `monero` command dispatcher + package wiring
**File:** `issues/feature/299-monero-command-dispatcher.md`
**Effort:** ~120 lines (bin/monero + Makefile/.rpk wiring + skeleton tests)
The `bin/monero` dispatcher with libexec lookup by binary name, `help`/`version`
reading the shared `VERSION`, lint + a `tests/unit/monero.bats` contract, and the
no-forbidden-sibling guard. Identity stays `bitcoin`; `PACKAGES` gains `monero`.

## FEAT-300 — `monero install` (verified release-tarball install)
**File:** `issues/feature/300-monero-install.md`
**Effort:** ~200 lines
Download `monerod` + `monero-wallet-rpc`/`-cli` from getmonero.org for the host
arch (x86_64/aarch64), verify the GPG signing key + SHA256, stage the binaries.
Idempotent; fails closed on a bad signature/checksum.

## FEAT-301 — `monero daemon {enable,start,stop,status,monitor}`
**File:** `issues/feature/301-monero-daemon.md`
**Effort:** ~400 lines
The daemon abstraction mirroring `bitcoin daemon`: `--system` default service
(`_monero` account, `/var/lib/monero`, systemd/launchd units) with `--user`
opt-in, monerod with restricted RPC on localhost, optional `--prune`,
multi-network (`--mainnet`/`--stagenet`/`--testnet`), group-read `monitor` (no
sudo fallback).

## FEAT-302 — `monero config {list,get,set}`
**File:** `issues/feature/302-monero-config.md`
**Effort:** ~250 lines
Effective-config frontend over monerod options under `/etc/monero`: TSV
`NAME⇥VALUE⇥DESCRIPTION` with compiled-in defaults parsed from `monerod
--help`. Mirrors `bitcoin config` (FEAT-298).

## FEAT-303 — man pages + node walkthrough
**File:** `issues/feature/303-monero-node-docs.md`
**Effort:** ~150 lines
`monero(1)` + per-verb `monero-*.1` man pages and a `docs/monero-walkthrough.md`
covering install → daemon enable → status, mirroring the bitcoin/lightning docs
contract.

---

## Recommended order

```
FEAT-299   skeleton first — nothing dispatches without it
FEAT-300   install — the daemon needs monerod on disk
FEAT-301   daemon — the core deliverable, depends on 299+300
FEAT-302   config — reads the installed monerod's --help; depends on 300
FEAT-303   docs — describe the shipped surface last
```

## Release gate

- `tests/unit/monero.bats` is green and joined into the combined unit suite;
  `make check-unit` stays green across bitcoin + lightning + fulcrum + monero.
- `monero` calls no forbidden siblings (the §4 boundary test extended to monero).
- `monero daemon enable` (no flag) installs a **system** service under `_monero`;
  `--user` installs the rootless unit; both proven by `monero.bats`.
- `monero install` verifies GPG + SHA256 and fails closed on tampering (proven
  with a fixture).
- `.rpk/identity` is still `bitcoin`; `make install` stages the `monero` tree.
- Man pages render (`man <file>` portably, per BUG-039) for every `monero` verb.
