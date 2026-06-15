---
id: BUG-033
type: bug
priority: high
---

# lightning daemon enable --system does not produce a working node on a
fresh machine: brew-symlink lightningd path, unwired bitcoind backend,
and missing bitcoin-group membership each need manual fixing by hand

## Severity

**High.** `--system` is the 3.1.0 lightning enable default
(FEAT-264/265) — the "reliable substrate other software builds on."
On a fresh host, `lightning daemon enable --system` currently installs a
service unit that crash-loops with an empty-looking log: lightningd
cannot find its subdaemons, its bcli plugin cannot reach bitcoind, and
(separately) the cln-grpc plugin aborts startup. Every one of these had
to be fixed by hand during a real live deployment before the node would
stay up. A boot-persistent default that does not boot is a defect.

## Observed (live deployment, macOS Apple Silicon, system mode)

Three independent failures, each fatal, surfaced in sequence:

1. **"I cannot find myself at /opt/homebrew/bin/lightningd".** The unit's
   ExecStart was `$(command -v lightningd)`, i.e. the Homebrew *symlink*
   `/opt/homebrew/bin/lightningd`. Core Lightning locates its subdaemons
   (`lightning_channeld`, `lightning_gossipd`, …) at `../libexec/
   c-lightning/` *relative to the resolved binary*, so from the symlink
   it cannot find them and refuses to start. Pointing the plist at the
   readlink-resolved Cellar path fixed it.

2. **"bitcoin-cli exec failed" → "Bitcoin backend died".** launchd (and
   systemd) run with a minimal PATH, so the bcli plugin could not exec
   `bitcoin-cli`, and could not find bitcoind's datadir/cookie. The
   generated `config` wrote only `network=`, `log-file=`,
   `rpc-file-mode=` — nothing pinning the backend.

3. **cln-grpc crash.** cln-grpc is a built-in "important" plugin; when it
   cannot bind its gRPC port lightningd treats the failure as fatal and
   exits. The combined educational stack does not use cln-grpc.

## Root cause

`libexec/lightning/daemon`, in the system installers
(`install_macos_system`, `install_system`, `install_openrc_system`):

1. ExecStart used the unresolved `command -v lightningd` (a brew symlink).
2. The generated system `config` never wired bitcoind into bcli.
3. cln-grpc was left enabled.
4. The service account was never added to bitcoind's service group, so
   even with the datadir pinned it could not read the now-group-readable
   cookie (FEAT-274 sets `rpccookieperms=group`).

## Fix

All three (four) fixes land in the system installers only; `--user` mode
is unchanged.

1. **Resolve lightningd.** New helper `daemon:_resolve_bin` does
   `readlink -f "$(command -v lightningd)"` (falling back to the bare
   path). The macOS plist and Linux systemd ExecStart use the resolved
   path.

2. **Wire the bitcoind backend into the generated system `config`:**
   - `bitcoin-cli=<resolved>` — `daemon:_resolve_bitcoin_cli` prefers
     `/opt/local/bin` (MacPorts) then `/opt/homebrew/bin` then PATH, and
     `readlink -f`s the result (launchd/systemd can't find it on PATH).
   - `bitcoin-datadir=/var/lib/bitcoin` — the system bitcoind datadir, so
     bcli reads its `.cookie`.
   - `disable-plugin=cln-grpc`.
   No bind-addr is hardcoded (the live port-9735 clash was a dev-machine
   artifact; a fresh host has none).

3. **Join the bitcoind service group (best-effort).** New helper
   `daemon:_join_bitcoin_group` adds the service account to `_bitcoin`
   (macOS, `dseditgroup`) / `bitcoin` (Linux, `usermod -aG`). If the
   group does not exist (bitcoin not enabled yet) it `info`s a hint and
   continues — it never fails enable. This is a soft system-group op, not
   a call to the `bitcoin` command (allowed under §4 for the combined
   stack).

## Regression protection

`tests/unit/lightning.bats`, eight BUG-033 tests (Linux + macOS pairs),
exercising the real system installers with the privileged tooling stubbed
and the state/unit/plist dirs redirected under `$BATS_TMPDIR` via new
test seams (`LIGHTNING_SYSTEM_STATE`, `LIGHTNING_SYSTEMD_DIR`,
`LIGHTNING_LAUNCHD_DIR`, mirroring the existing `LIGHTNING_OPENRC_STATE`):

- the generated ExecStart references the readlink-resolved lightningd
  target, never the stubbed brew-style symlink;
- the generated system `config` contains `bitcoin-cli=`,
  `bitcoin-datadir=/var/lib/bitcoin`, and `disable-plugin=cln-grpc`;
- enable adds the service user to the bitcoin group when it exists
  (asserted on the mocked `usermod` / `dseditgroup` call) and does NOT
  fail when it is absent.

## Acceptance criteria

1. `lightning daemon enable --system` writes a unit whose ExecStart is
   the readlink-resolved lightningd, not a symlink.
2. The generated system config wires `bitcoin-cli=<abs>`,
   `bitcoin-datadir=/var/lib/bitcoin`, and `disable-plugin=cln-grpc`.
3. The service account is best-effort-added to the bitcoind group
   (`_bitcoin`/`bitcoin`); a missing group hints and continues, never
   fails enable.
4. `--user` mode is unchanged.
5. `bats tests/unit/lightning.bats` is green including the BUG-033 tests.
