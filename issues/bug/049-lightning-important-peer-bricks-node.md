---
id: BUG-049
type: bug
priority: high
status: open
---

# lightning peer bootstrap persists `important-peer=`, which some lightningd builds reject — bricking the node

## Severity

**High.** `lightning peer bootstrap` (FEAT-199 Layer 1) writes an
`important-peer=<uri>` block into `$LIGHTNING_DIR/config`. Core Lightning
builds that do not recognise the `important-peer` option **refuse to start**
when it is present ("unknown option"), so after a bootstrap the node enters
a crash-loop and never comes up. The operator's own node is taken down by a
routine bootstrap. Workaround: hand-edit the config to delete the block.

## Observed

Live host, `lightningd v26.04.1`, after `lightning peer bootstrap`:

```
$ lightning daemon monitor
2026-06-13T19:09:26.018Z INFO lightningd: v26.04.1
lightningd: Config file /Users/rene/.lightning/config line 5:
    important-peer=03cb79...@194.62.84.31:9735: unknown option
```

`~/.lightning/config`:

```
# >>> lightning peers — managed by 'peer bootstrap'
important-peer=03cb79...@194.62.84.31:9735
important-peer=035e4f...@170.75.163.209:9735
...
# <<< lightning peers
```

`important_peer_write` (libexec/lightning/peer) emits the block
unconditionally, with no check that the installed lightningd accepts the
option.

## Root Cause

FEAT-199 Layer 1 assumed every lightningd accepts `important-peer`. The
installed build does not, and lightningd treats an unknown config option as
fatal at startup. Persisting an option the local daemon rejects therefore
prevents the node from starting. The bootstrap never probed for support.

## Fix Plan

- `libexec/lightning/peer`: add `important_peer_supported()` — probe
  `lightningd --help` for `--important-peer` (test seam
  `$LIGHTNING_IMPORTANT_PEER_SUPPORTED=1|0`).
- In `important_peer_write`, always `important_peer_clear` first (idempotent,
  removes any prior bricking block), then **skip** persisting and `warn`
  when the option is unsupported — the FEAT-199 Layer 2 keepalive sidecar
  still reconnects the peers without the config line.

## Regression Protection

`tests/unit/lightning.bats`:

```bats
@test "BUG-049: peer bootstrap does NOT persist important-peer when lightningd rejects it" {
	cat > "$BIN_SHIM/lightningd" <<'EOF'
#!/bin/sh
[ "$1" = "--help" ] && { echo "usage: lightningd [options]"; echo "  --alias=<arg>"; exit 0; }
exit 0
EOF
	chmod +x "$BIN_SHIM/lightningd"
	printf '03aaa@1.2.3.4:9735\n03bbb@5.6.7.8:9735\n' > "$BATS_TMPDIR/nodes.$$"
	export LIGHTNING_BOOTSTRAP_NODES="$BATS_TMPDIR/nodes.$$"
	run "$LIGHTNING_BIN" peer bootstrap
	[ "$status" -eq 0 ]
	[ ! -f "$HOME/.lightning/config" ] || ! grep -q 'important-peer=' "$HOME/.lightning/config"
}

@test "BUG-049: peer bootstrap persists important-peer when lightningd accepts it" {
	export LIGHTNING_IMPORTANT_PEER_SUPPORTED=1
	printf '03aaa@1.2.3.4:9735\n' > "$BATS_TMPDIR/nodes.$$"
	export LIGHTNING_BOOTSTRAP_NODES="$BATS_TMPDIR/nodes.$$"
	run "$LIGHTNING_BIN" peer bootstrap
	[ "$status" -eq 0 ]
	grep -q 'important-peer=03aaa@1.2.3.4:9735' "$HOME/.lightning/config"
}
```

The first test fails on the broken code (the block is written regardless),
passes after the fix.

## Acceptance Criteria

1. `peer bootstrap` against a lightningd that does not accept
   `important-peer` writes **no** `important-peer=` line and exits 0.
2. A re-run clears any previously written (bricking) block.
3. When lightningd accepts the option, the block is still persisted.
