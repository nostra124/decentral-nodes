---
id: BUG-030
type: bug
priority: high
status: open
---

# daemon enable/monitor: privileged datadir ops bypass sudo (EACCES, false success)

## Severity

**High.** In the default `--system` mode `bitcoin daemon enable`
fails to write `bitcoin.conf` (so the node may start with no
`server=1`/cookie auth) yet prints `created … (cookie auth)` as if it
succeeded, and `bitcoin daemon monitor` cannot read the log at all.
The user is left with a daemon that looks enabled but has no usable
config and no observability.

## Observed

On macOS, system mode (the 3.0.0 default), reproduced verbatim:

```
$ bitcoin daemon enable
/Users/rene/.local/libexec/bitcoin/daemon: Zeile 477: /var/lib/bitcoin/bitcoin.conf: Permission denied
daemon: info - created /var/lib/bitcoin/bitcoin.conf (cookie auth)
daemon: info - installed /Library/LaunchDaemons/org.bitcoin.bitcoind.plist
daemon: info - bitcoind service enabled (system/macos)

$ bitcoin daemon monitor
tail: '/var/lib/bitcoin/bitcoind.log' kann nicht zum Lesen geöffnet werden: Permission denied
```

The redirect on line 477 hit `Permission denied`, but the very next
line still claimed the file was `created`. The config was never
written.

## Root Cause

`command:enable` creates the datadir and chowns it to the dedicated
`bitcoin` service account (`libexec/bitcoin/daemon:450-452`):

```sh
$SUDO mkdir -p "$datadir"
[ "$mode" = system ] && $SUDO chown "$user" "$datadir" 2>/dev/null
```

It then writes the config with a **bare shell redirect** that runs as
the *invoking* user, not under `$SUDO` (lines 464 and 477):

```sh
cat > "$conf" <<-CONF
server=1
CONF
```

The datadir is now owned by `bitcoin`, so the redirect fails with
EACCES. Two compounding defects:

1. The write is not routed through `$SUDO` (unlike the unit file,
   which correctly uses `$SUDO install` at line 493).
2. The redirect failure is not checked, so the following
   `info "created $conf …"` prints unconditionally — a false success.

`command:monitor` has the same class of bug for reading: on macOS it
tails the datadir log **without** `$SUDO` (line 207), even though it
already computed `SUDO=sudo` for system mode:

```sh
[ "$mode" = system ] && SUDO=sudo
...
tail -f "$(daemon:_datadir "$mode")/bitcoind.log" ;;   # no $SUDO
```

The log is created by launchd/bitcoind owned by the `bitcoin` account,
so a non-root `tail` gets EACCES.

## Fix Plan

The clean fix is the **three-user model the lightning daemon already
uses**: root installs, the daemon runs as a dedicated service account,
and the operator joins that account's group to read config/cookie/log
*without sudo*. `libexec/bitcoin/daemon` (and the installed mirror at
`~/.local/libexec/bitcoin/daemon`):

1. **Service account + group** — replace the macOS
   `sysadminctl -addUser -roleAccount` (which produced a visible,
   dynamically-numbered account, e.g. UID 510) with a hidden,
   UID-pinned `dscl` account `_bitcoin` (UID 295, `IsHidden=1`,
   `/usr/bin/false`); on Linux use `useradd --system --user-group` so
   the dedicated `bitcoin` group exists. Add the invoking operator to
   the group (`dseditgroup` / `usermod -aG`).
2. **State dir** — `0750`, owned `<svc>:<svc>`, so the group (and only
   the group) can reach it.
3. **enable config write** — write each generated `bitcoin.conf` to a
   `mktemp` file, then `$SUDO install -m 0640 "$tmp" "$conf"` +
   `$SUDO chown <svc>:<svc>` (group-readable). On failure, `error` and
   `return 1` instead of falsely reporting success. Both `--public`
   and the default (cookie-auth) branches.
4. **monitor** — read the log **directly** (no sudo): the operator is
   in the service group and the datadir is group-readable. (Group
   membership applies on next login.)
5. **disable** — default to `--system` like `enable` (it previously
   defaulted to `--user`, so a bare `disable` silently missed the
   system unit).
6. **Consistency / UX** — the default mode is already `--system`
   (FEAT-261), so drop the redundant `--system` token from every
   `usage:` / command-list hint, leaving `[--user]` as the explicit
   opt-in. Keep the prose that names `--system` as the default.

No behavior change in `--user` mode (where `$SUDO` is empty and no
service account is provisioned), so the existing rootless tests are
unaffected. The same model is applied to the `fulcrum` and `lightning`
daemons for a consistent, production-ready posture.

## Regression Protection

`tests/unit/streamline.bats`. The mock harness uses a transparent
`sudo` stub, so the EACCES cannot be reproduced literally; instead the
tests assert the **privileged call shape** by making the `sudo` stub
log its invocations:

```bash
@test "BUG-030 — enable (system) installs bitcoin.conf via sudo, not a bare redirect" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	local conf="$BITCOIN_DAEMON_ROOT/var/lib/bitcoin/bitcoin.conf"
	grep -Eq 'sudo install -m 0640 .*bitcoin\.conf' "$FEAT034_CALLS"
	grep -q 'chown bitcoin:bitcoin .*bitcoin\.conf' "$FEAT034_CALLS"
	[ -f "$conf" ]
	grep -q '^server=1' "$conf"
}

@test "BUG-030 — enable (system) provisions a dedicated group and joins the operator" {
	feat034_env linux
	run "$BITCOIN_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	grep -q 'useradd .*--user-group .*bitcoin' "$FEAT034_CALLS"
	grep -q 'usermod -a -G bitcoin' "$FEAT034_CALLS"
	grep -q 'chown bitcoin:bitcoin .*var/lib/bitcoin' "$FEAT034_CALLS"
}

@test "BUG-030 — monitor (system, macos) reads the log directly via group access (no sudo)" {
	bug015_env
	BITCOIN_DAEMON_OS=macos run "$BITCOIN_BIN" daemon monitor --system
	[ "$status" -eq 0 ]
	grep -Eq 'tail -f .*bitcoind\.log' "$BUG015_CALLS"
	! grep -q 'sudo' "$BUG015_CALLS"
}
```

The enable tests assert the privileged call shape (sudo install at
0640, group ownership, `--user-group`, operator join); the monitor
test asserts the log is read with no sudo. All fail against the broken
code and pass after the fix.

## Acceptance Criteria

1. `daemon enable --system` provisions a dedicated service account
   (`_bitcoin` hidden on macOS, `bitcoin:bitcoin` on Linux) and adds
   the operator to the group.
2. `bitcoin.conf` is written through `$SUDO install -m 0640`, owned
   `<svc>:<svc>`; the file exists with `server=1` after the call.
3. A failed config write makes `enable` exit non-zero and emit an
   `error`, never an `info … created` line.
4. `daemon monitor --system` reads the log **without** sudo (group
   access).
5. `daemon disable` defaults to `--system`.
6. Every `usage:`/command-list hint shows `[--user]` only; no
   `[--system|--user]` or `[--user|--system]` tokens remain. The
   "default: system" / "--system (default)" prose stays.
7. `make check-unit` is green, including the BUG-030 tests.
