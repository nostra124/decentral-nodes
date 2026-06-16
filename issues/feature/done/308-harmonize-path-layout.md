---
id: FEAT-308
type: feature
status: shipped
---

# Common path layout across platforms and scripts

## Description

**As an** operator of the combined stack
**I want** the same data/config paths on Linux and macOS, and a consistent
scheme across bitcoin/lightning/fulcrum/monero
**So that** I don't have to remember per-OS / per-command path quirks

System paths were already harmonized; the divergence was in **user mode**:
bitcoin & fulcrum special-cased macOS to `~/Library/Application Support/X`,
fulcrum used XDG `~/.config/fulcrum`, and monero used monerod's native
`~/.bitmonero` — while lightning used `~/.lightning` on both.

## Harmonized contract

| | system | user (Linux **and** macOS) |
|---|---|---|
| datadir | `/var/lib/<cmd>` | `~/.<cmd>` |
| config  | `/etc/<cmd>`     | `~/.<cmd>` (in the datadir) |
| units   | systemd `/etc/systemd/system` · launchd `/Library/LaunchDaemons` (system); `~/.config/systemd/user` · `~/Library/LaunchAgents` (user) — platform-native, unchanged |

So: `~/.bitcoin`, `~/.lightning`, `~/.fulcrum`, `~/.monero` — identical on
Linux and macOS.

## Implementation

- bitcoin `daemon:_datadir`: dropped the macOS `~/Library/Application
  Support/Bitcoin` branch → `~/.bitcoin` everywhere.
- fulcrum `daemon:_datadir` / `_config_dir` / `config:_dir` / `cert:_dir`:
  dropped the macOS Library + Linux XDG branches → `~/.fulcrum` everywhere.
- monero `daemon:_datadir` / `config:_confdir`: `~/.bitmonero` → `~/.monero`
  (monerod is launched with `--data-dir`, so the native default is moot).
- The lightning BUG-052 resolver still searches bitcoind's *native* macOS
  path (`~/Library/Application Support/Bitcoin`) when DETECTING an external
  bitcoind — that's about finding the node, not our layout, so it's kept.
- Man pages + monero walkthrough updated.

## Acceptance Criteria

1. User-mode datadir/config is `~/.<cmd>` on both Linux and macOS for all four
   commands (no `~/Library`, no XDG, no `~/.bitmonero`). Proven by the
   per-command bats.
2. System paths unchanged (`/var/lib/<cmd>`, `/etc/<cmd>`).
3. All unit suites stay green.
