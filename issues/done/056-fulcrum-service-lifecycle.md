---
id: FEAT-056
type: feature
priority: high
status: done
---

# `fulcrum` service lifecycle (install / enable / start / stop / …)

## Description

**As a** node operator who has bitcoind running
**I want** `fulcrum install`, `enable`, `disable`, `start`, `stop`,
`monitor`, and `space`
**So that** I can stand up and supervise a Fulcrum Electrum server
the same way `bitcoin daemon` supervises bitcoind.

This is the service-management half of the Fulcrum integration and is
modelled directly on `libexec/bitcoin/daemon` (FEAT-034): a
template-rendered systemd `.service` on Linux or launchd `.plist` on
macOS, in `--user` (no root) or `--system` (dedicated `fulcrum`
account) mode, with every privileged step routed through `$SUDO` and
every absolute system path through a `$FULCRUM_ROOT` DESTDIR prefix so
the bats matrix can mock the init system. Depends on FEAT-055 for the
`bin/fulcrum` dispatcher and `libexec/fulcrum/` install path.
Out of scope: writing `fulcrum.conf` (FEAT-057) and the admin-RPC
inspection verbs (FEAT-058).

## Implementation

`libexec/fulcrum/service` — one plugin holding all lifecycle verbs as
`service:` functions, mirroring the `daemon:` helper layout:

- `service:_os` / `service:_root` / `service:_unit_path` /
  `service:_render` — copied-and-adapted from `daemon`, keyed to
  `$FULCRUM_OS` / `$FULCRUM_ROOT` / `$FULCRUM_FULCRUMD` overrides for
  the test matrix. No shared helper (CLAUDE.md §5).
- `install [--from brew|apt|source|docker]` — fetch/build Fulcrum.
  Source/docker are the realistic paths (Fulcrum is a C++/Qt build);
  each branch emits a clear `error` on failure.
- `enable [--user|--system]` — render the unit from
  `share/bitcoin/units/fulcrum.{service,plist}`, install it, start it.
  Fails loudly (`error`) if bitcoind RPC is not reachable, since
  Fulcrum cannot index without it.
- `disable [--user|--system]` — stop and remove the unit; data dir
  preserved.
- `start` / `stop` / `monitor [--user|--system]` — init-system
  wrappers, same shape as `daemon`.
- `space` — show the Fulcrum **index** disk usage (its `datadir`),
  which is the operationally interesting number during initial sync.

New unit templates under `share/bitcoin/units/` substitute
`@FULCRUMD@` / `@DATADIR@` / `@CONFIG@` / `@USER@`; `--user` mode
strips the privilege-drop directive exactly as `daemon:_render` does.

## Acceptance Criteria

1. `fulcrum enable --user` with a mocked init system writes a unit to
   the per-user path and activates it; `fulcrum disable --user`
   removes it. Proven by bats with `$FULCRUM_ROOT` redirecting writes
   to a tmp dir, asserting on both linux and macos via `$FULCRUM_OS`.
2. `fulcrum enable` emits an `error` and exits non-zero when bitcoind
   RPC is unreachable (mocked). Proven by a bats test asserting the
   log line names the condition.
3. The rendered systemd unit contains `@FULCRUMD@`/`@DATADIR@`
   substituted and, in `--system` mode, a `User=fulcrum` line; in
   `--user` mode that line is absent. Proven by bats on the rendered
   output for both modes.
4. `fulcrum start` / `stop` / `monitor` dispatch the correct
   `systemctl` / `launchctl` invocation per os×mode. Proven by bats
   capturing the mocked init-system command line.
5. `fulcrum space` reports the configured `datadir` usage and errors
   cleanly when the dir is absent. Proven by bats.
6. `install --from <bad>` rejects an unknown source with an `error`
   line and non-zero exit. Proven by bats.
7. Every new failure branch emits a `warn`/`error`/`fatal` line per
   skills/logging.md. Proven by the per-branch bats assertions above.
