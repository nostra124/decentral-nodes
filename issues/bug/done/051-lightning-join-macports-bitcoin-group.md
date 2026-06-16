---
id: BUG-051
type: bug
priority: medium
status: closed
---

# lightning daemon enable can't auto-join an external bitcoind's cookie group on macOS

## Severity

**Medium.** `lightning daemon enable --system` adds the `_lightning` service
account to the bitcoind cookie group so it can read the group-readable
`.cookie` (FEAT-274 / BUG-033). On macOS it only ever tried the **managed**
`_bitcoin` group. A lightning node backed by an **external** bitcoind — e.g.
a MacPorts/upstream `bitcoind`, whose service account + cookie group is
`bitcoin` (not `_bitcoin`) — therefore never gets cookie access, and the
operator has to run `dseditgroup` by hand. The bcli backend then fails to
authenticate.

## Observed

Live macOS host, MacPorts `bitcoind` (group `bitcoin`, gid 508), bringing up
lightning against it. `daemon:_join_bitcoin_group` (libexec/lightning/daemon):

```sh
if is_macos; then
	if dscl . -read /Groups/_bitcoin >/dev/null 2>&1; then    # only _bitcoin
		sudo dseditgroup -o edit -a "$svc_user" -t user _bitcoin ...
	else
		info "_bitcoin group not found — enable 'bitcoin daemon' ..."
	fi
fi
```

The `bitcoin` group (the MacPorts cookie group) is never considered, so
`_lightning` is not added to it and can't read
`/opt/local/var/lib/bitcoind/.cookie`.

## Root Cause

`daemon:_join_bitcoin_group` hard-codes the single managed group per OS
(`_bitcoin` on macOS, `bitcoin` on Linux). It does not account for an
external bitcoind whose cookie group differs from the managed daemon's.

## Fix Plan

- `libexec/lightning/daemon`: add `daemon:_bitcoin_group_exists` (dscl /
  getent) and have `daemon:_join_bitcoin_group` iterate **both** candidate
  groups (`_bitcoin`, `bitcoin`), adding the service account to every one
  that exists (harmless to be in an extra group; covers whichever bitcoind
  backs the node). Still a soft op that never fails enable.

Note: making the cookie itself group-readable (`rpccookieperms=group`) is the
**bitcoind** side — `bitcoin daemon enable` does it for the managed node
(FEAT-274); for an external node the operator sets it on that node. This bug
covers only the lightning-side group membership.

## Regression Protection

`tests/unit/lightning.bats` — macOS, `_bitcoin` absent but `bitcoin` present;
assert enable adds `_lightning` to `bitcoin`:

```bats
@test "BUG-051: enable joins the 'bitcoin' cookie group when _bitcoin is absent (macOS)" {
	if [ "$(uname -s)" != "Darwin" ]; then skip "macOS-only"; fi
	_bug033_system_setup
	cat > "$BIN_SHIM/dscl" <<EOF
#!/bin/sh
echo "dscl \$*" >> "$BIN_SHIM/dscl.calls"
case "\$*" in
	*"-read /Groups/bitcoin"*) exit 0 ;;
	*-create*) exit 0 ;;
	*-read*|*-list*) exit 1 ;;
	*) exit 1 ;;
esac
EOF
	chmod +x "$BIN_SHIM/dscl"
	run "$LIGHTNING_BIN" daemon enable --system
	[ "$status" -eq 0 ]
	grep -q "dseditgroup -o edit -a _lightning -t user bitcoin" "$BIN_SHIM/dseditgroup.calls"
	! grep -q "user _bitcoin" "$BIN_SHIM/dseditgroup.calls"
}
```

Fails on the broken code (only `_bitcoin` is tried), passes after the fix.

## Acceptance Criteria

1. On macOS, enable adds `_lightning` to `bitcoin` when that group exists and
   `_bitcoin` does not.
2. When both exist, it joins both; when neither does, it emits a hint and
   does not fail enable.
3. The existing BUG-033 group tests stay green.
