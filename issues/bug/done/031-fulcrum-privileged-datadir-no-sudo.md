---
id: BUG-031
type: bug
priority: high
status: done
---

# fulcrum enable/config: privileged datadir/config ops bypass sudo (EACCES, false success)

## Severity

**High.** In the default `--system` mode `fulcrum enable` (and
`fulcrum config init --system`) provision a datadir/config dir owned by
the dedicated `fulcrum` account, then write `fulcrum.conf` with a bare
shell redirect that runs as the *invoking* user — so the write fails
with EACCES yet `config init` still prints `wrote …` as if it
succeeded. The operator is also left unable to read the config/log
without sudo. The same flawed account-provisioning pattern that BUG-030
fixed for `bitcoin` is still present here: macOS uses a visible,
dynamically-numbered `sysadminctl -addUser -roleAccount`, and Linux uses
`useradd --system --no-create-home` *without* `--user-group`, so no
dedicated group exists for the operator to join.

## Observed

On macOS, system mode (the 3.0.0/FEAT-262 default), the same failure
mode as BUG-030 on `bitcoin`:

```
$ fulcrum config init --system
config: error - init: cannot write '/etc/fulcrum/fulcrum.conf'   # or a
                                                                  # false "wrote" if perms slip
$ fulcrum monitor      # macos: tail of a fulcrum-owned log → Permission denied
```

## Root Cause

`command:enable` (`libexec/fulcrum/service`) provisions the service
account and chowns the datadir to it, but:

1. **macOS account** is created with `sysadminctl -addUser
   -roleAccount` — a visible, dynamically-numbered account, not a
   hidden UID-pinned one. **Linux account** is created with
   `useradd --system --no-create-home` (no `--user-group`), so there is
   no dedicated `fulcrum` group, and the operator is never added to one.
2. The datadir is chowned `$SUDO chown "$user"` (user only, no group),
   default mode (not `0750`), so the operator cannot reach it.
3. `command:init` in `libexec/fulcrum/config` writes `fulcrum.conf`
   with a **bare redirect** (`{ … } > "$file"`) that runs as the
   invoking user; in a `fulcrum`-owned `/etc/fulcrum` this fails with
   EACCES, and even the explicit-failure check can be skipped if the
   dir is group-writable. The config never reaches the service.
4. `command:monitor` (macOS) tails the service-owned log, and Linux
   `monitor`/`logs` wrap `journalctl` — these are fine without group
   access only because the operator is in the group after the fix.

## Fix Plan

Apply the **three-user model** BUG-030 landed for `bitcoin` (root
installs, daemon runs as a dedicated service account, operator joins the
account's group to read config/log without sudo). `libexec/fulcrum/*`
(and the installed mirrors at `~/.local/libexec/fulcrum/*`):

1. **Service account + group** — replace macOS
   `sysadminctl -addUser -roleAccount` with a hidden, UID-pinned `dscl`
   account `_fulcrum` (UID/GID 296, `IsHidden=1`, `/usr/bin/false`,
   collision-increment fallback); on Linux use
   `useradd --system --user-group` so the dedicated `fulcrum` group
   exists. Add the invoking operator to the group
   (`dseditgroup -o edit -a $USER -t user _fulcrum` /
   `usermod -a -G fulcrum $USER`) and print a "log out and back in for
   group membership" hint.
2. **State dir** — `/var/lib/fulcrum`, `0750`, owned `<svc>:<svc>`, so
   only the group can reach it.
3. **enable + config init writes** — write each generated config to a
   `mktemp` file, then `$SUDO install -m 0640 "$tmp" "$conf"` +
   `$SUDO chown <svc>:<svc>` (group-readable). On failure, `error` and
   `return 1` instead of falsely reporting success.
4. **monitor** — read the log **directly** (no sudo): the operator is in
   the service group and the datadir is group-readable. On Linux the
   system unit uses `journalctl -u fulcrumd` (no sudo, like lightning).
5. **disable** — already defaults to `--system`; keep it.
6. **Consistency / UX** — drop the redundant `--system` token from every
   `usage:`/command-list hint, leaving `[--user]` as the explicit
   opt-in. Keep the prose that names `--system` as the default.

No behavior change in `--user` mode (`$SUDO` empty, no service account
provisioned), so the existing rootless tests are unaffected.

## Regression Protection

`tests/unit/fulcrum.bats`. The mock harness uses a transparent `sudo`
stub that logs its invocations, plus stubs for `dscl dseditgroup
usermod chown`, so tests assert the **privileged call shape**:

```bash
@test "BUG-031 — enable (system) provisions a dedicated group and joins the operator (linux)" {
	fulcrum_sys_env linux
	run "$FULCRUM" enable --system
	[ "$status" -eq 0 ]
	grep -q 'useradd .*--user-group .*fulcrum' "$CALLLOG"
	grep -q 'usermod -a -G fulcrum' "$CALLLOG"
	grep -q 'chown fulcrum:fulcrum .*var/lib/fulcrum' "$CALLLOG"
}
```

The enable tests assert the privileged call shape (sudo install at
0640, group ownership, `--user-group`, operator join); a macOS test
asserts the hidden UID-296 `dscl` account; the monitor test asserts the
log is read with no sudo. All fail against the broken code and pass
after the fix.

## Acceptance Criteria

1. `fulcrum enable --system` provisions a dedicated service account
   (`_fulcrum` hidden, UID 296 on macOS; `fulcrum:fulcrum` on Linux)
   and adds the operator to the group.
2. The datadir (`/var/lib/fulcrum`) is `0750`, owned `<svc>:<svc>`.
3. `fulcrum.conf` is written through `$SUDO install -m 0640`, owned
   `<svc>:<svc>`; a failed write makes the command exit non-zero with an
   `error`, never a false `wrote`/`created` line.
4. `fulcrum monitor --system` reads the log **without** sudo (group
   access on macOS; `journalctl -u fulcrumd` with no sudo on Linux).
5. Every `usage:`/command-list hint shows `[--user]` only; no
   `[--system|--user]`/`[--user|--system]` tokens remain. The
   "--system (default)" prose stays.
6. `make check-unit` is green, including the BUG-031 tests.

## Follow-up: runnable-binary preflight (mirrors BUG-030/bitcoin)

The `--system` daemon runs `Fulcrum` as the dedicated service account
(`_fulcrum` on macOS, `fulcrum` on Linux). If that account cannot
*execute* the binary — a cleared exec bit, a non-traversable parent
directory, or an unreadable linked dylib (a restrictive umask on a
Homebrew keg under `/opt/homebrew` is the usual cause) — launchd/systemd
crash-loops silently with `EX_CONFIG` / a dyld `errno=13` and an empty
log. A bare `test -x` cannot catch this; only running the binary as the
service account does.

`command:enable` (libexec/fulcrum/service) now runs a preflight in system
mode — `service:_check_runnable`, which executes `$SUDO -u <svc> <bin>
--version` (Fulcrum's `--version`/`-v` prints its version banner and
exits 0 without starting the server) — *after* the service account is
provisioned and the operator joins the group, and *before* the unit is
installed. On failure it emits a clear multi-line `error` naming the
account + binary and the fix
(`sudo chmod -R o+rX "$(brew --prefix)"/{Cellar,opt,lib}`), then returns
non-zero without installing the unit. Wording is copied verbatim from
bitcoin's `daemon:_check_runnable`.

Regression test (tests/unit/fulcrum.bats): "BUG-031: enable (system)
refuses to install a unit the service account can't run" points the
fulcrumd override at a stub that `exit 1`s, runs `enable --system`, and
asserts non-zero status, stderr containing "cannot run", and that the
unit file was **not** created. The shared `sudo` stub now strips a
leading `-u <user>` (so `sudo -u <svc> <bin> --version` execs the binary
under the single test uid) and the fulcrumd stub honors `--version` by
exiting 0 — mirroring the streamline.bats harness for BUG-030.
