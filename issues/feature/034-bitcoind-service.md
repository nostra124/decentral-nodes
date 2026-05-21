---
id: FEAT-034
type: feature
priority: medium
status: open
---

# `bitcoin daemon enable` / `disable` — service-managed bitcoind

## Description

**As a** user who has just installed `bitcoind` (FEAT-033 or by
hand)
**I want** one command that drops a service unit into the right
place and brings the daemon up so it survives reboots
**So that** I get a real always-on Bitcoin node without learning
each platform's init system.

Two modes:

- `--user`: per-user service (no root). `systemctl --user` on
  Linux, `launchctl bootstrap gui/$UID` on macOS. Lives in the
  invoking user's home; data dir under `$XDG_DATA_HOME/bitcoin`.
- `--system`: system-wide service. `systemctl` on Linux,
  `launchctl bootstrap system` on macOS. Runs as a dedicated
  `bitcoin` system user (created on first enable if missing);
  data dir under `/var/lib/bitcoin`.

## Implementation

New verbs on the `daemon` plugin (folded with the existing
`start`/`stop`/`monitor`/`space` per BUG-015's branch (c)):

    bitcoin daemon enable  [--user | --system]   # default: --user
    bitcoin daemon disable [--user | --system]

Unit-file templates ship at:

    share/bitcoin/units/bitcoind.service           (systemd, user + system both)
    share/bitcoin/units/bitcoind.plist             (launchd, user + system both)

The templates have `@DATADIR@`, `@USER@`, `@BITCOIND@` markers
that the verb substitutes at enable time. `@USER@` is the
invoking user for `--user` and the `bitcoin` system user for
`--system`. `@BITCOIND@` is `command -v bitcoind` at enable time
(no PATH lookup at service start — surfaces the missing-bitcoind
error during `enable`, not in journalctl after the fact).

Per-mode placement:

| Mode + OS         | Unit file path                                  | Activation |
|--------------------|---------------------------------------------------|-----------|
| `--user` + Linux   | `~/.config/systemd/user/bitcoind.service`         | `systemctl --user daemon-reload && systemctl --user enable --now bitcoind` |
| `--system` + Linux | `/etc/systemd/system/bitcoind.service`            | `sudo systemctl daemon-reload && sudo systemctl enable --now bitcoind` |
| `--user` + macOS   | `~/Library/LaunchAgents/org.bitcoin.bitcoind.plist` | `launchctl bootstrap gui/$UID …` |
| `--system` + macOS | `/Library/LaunchDaemons/org.bitcoin.bitcoind.plist` | `sudo launchctl bootstrap system …` |

`--system` mode on first call:

- Creates a system user `bitcoin` (no login, no home) via
  `useradd --system --no-create-home --shell /usr/sbin/nologin
  bitcoin` (Linux) or `sysadminctl -addUser bitcoin -roleAccount`
  (macOS), iff missing.
- Creates `/var/lib/bitcoin` owned by that user.
- Drops privilege via `User=bitcoin` in the systemd unit, or
  `UserName` in the launchd plist.

`disable` is symmetric: tear down the service and remove the unit
file. Does NOT delete the data dir (`/var/lib/bitcoin` or
`$XDG_DATA_HOME/bitcoin`) — that's destructive, kept for an
explicit `daemon purge` verb in a future roadmap.

The existing `start`/`stop` verbs (per BUG-015) continue to work
against whichever service `enable` created — they're a thin shim
over `systemctl start`/`stop` and `launchctl kickstart`/`bootout`.

## Acceptance Criteria

1. `bitcoin daemon enable --user` on Linux creates the unit at
   `~/.config/systemd/user/bitcoind.service`, runs `systemctl
   --user daemon-reload`, and the service is `active (running)`
   within 30s.
2. `bitcoin daemon enable --user` on macOS creates the plist at
   `~/Library/LaunchAgents/org.bitcoin.bitcoind.plist` and the
   service is `Running` per `launchctl print gui/$UID/org.bitcoin.bitcoind`.
3. `bitcoin daemon enable --system` (as root or via sudo) creates
   the system user `bitcoin` if missing, places the unit in
   `/etc/systemd/system/`, and the service runs as user `bitcoin`.
4. `bitcoin daemon disable --user|--system` brings the service
   down and removes the unit file. Data dir is preserved.
5. `bitcoin daemon enable` called twice is idempotent (no error
   on re-enable; refreshes the substituted templates).
6. `bitcoin daemon enable` with no `bitcoind` on PATH errors with
   a clear message pointing at `bitcoin daemon install` (FEAT-033).
7. bats coverage: at least 8 new tests covering each mode × OS
   matrix happy path, the idempotency case, the missing-bitcoind
   error, and the disable-preserves-data assertion (mocked
   `systemctl` / `launchctl` so the suite runs in CI without
   actually loading services).
8. Pre-push hook + CI green on the milestone PR.
9. Cited from `bitcoin help daemon` and from the man page.
