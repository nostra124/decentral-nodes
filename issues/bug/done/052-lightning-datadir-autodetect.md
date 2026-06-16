---
id: BUG-052
type: bug
status: closed
---

# lightning daemon enable hardcodes bitcoin-datadir=/var/lib/bitcoin

## Severity

**Medium.** `lightning daemon enable` always wrote
`bitcoin-datadir=/var/lib/bitcoin` into the generated config — the managed
`bitcoin daemon` path. A node backed by an **external** bitcoind (e.g. a
MacPorts node at `/opt/local/var/lib/bitcoind`) was therefore pointed at the
wrong datadir, so bcli could not find the cookie and the backend died until
the operator hand-edited `bitcoin-datadir`. Together with BUG-051 (group
membership) this was the last manual step in wiring an external node.

## Observed

`libexec/lightning/daemon` (three install paths) emitted a literal:

```sh
bitcoin-datadir=/var/lib/bitcoin
```

regardless of where bitcoind actually keeps its data/cookie.

## Root Cause

The datadir was a hardcoded constant, not resolved from the running /
installed bitcoind.

## Fix Plan

- Add `daemon:_resolve_bitcoin_datadir`: `$LIGHTNING_BITCOIN_DATADIR`
  authoritative when set (also the hermeticity seam — the suite pins it to
  `/var/lib/bitcoin`); else a running bitcoind's `-datadir`; else the first
  known datadir holding a `.cookie` (`/var/lib/bitcoin`,
  `/opt/local/var/lib/bitcoind`, `/opt/homebrew/var/lib/bitcoind`,
  `~/.bitcoin`, `~/Library/Application Support/Bitcoin`); else
  `/var/lib/bitcoin`.
- Use it at all three config-gen sites.

## Regression Protection

`tests/unit/lightning.bats`: unset the seam, stub `ps` to report a bitcoind
with `-datadir=/opt/local/var/lib/bitcoind`, assert the generated config
carries that datadir (not `/var/lib/bitcoin`). setup() pins
`LIGHTNING_BITCOIN_DATADIR=/var/lib/bitcoin` so the existing BUG-033
assertions stay hermetic on a host running bitcoind.

## Acceptance Criteria

1. enable auto-detects a running external bitcoind's datadir into the config.
2. Falls back to a `.cookie`-bearing known dir, else `/var/lib/bitcoin`.
3. Existing BUG-033 config tests stay green.
