---
id: BUG-041
type: bug
priority: high
status: done
---

> **Resolved.** Both nodes now poll bitcoind every 1s via `--developer
> --dev-bitcoind-poll=1` — bob in `sit_setup_alice_bob`, alice via
> `developer`/`dev-bitcoind-poll=1` written to its config in the entrypoint.
> Validated: channel **setup ~1s, open ~2s** (was ~35s each); mined blocks are
> seen within ~2s. The `02_channel_open_close` *open* test passes. (The *close*
> test's remaining slowness is channel-state accumulation across tests, tracked
> under [[BUG-042]], not polling.)

# SIT — lightningd has no fast bitcoind polling, so confirmation-heavy live tests time out

## Severity

**High (keystone).** This blocks every confirmation-heavy SIT test and makes the
others slow to iterate on. Core Lightning's `bcli` backend polls bitcoind for new
blocks only ~every 30 s, so after `sit_mine` the nodes don't see the new tip for
up to 30 s. `sit_mine` now waits for that (BUG-038), which is *correct* but means
each confirmation costs ~30 s; the channel-close and multi-hop-pay suites then
exceed the `check-sit` `timeout` guard. Until lightningd polls fast, the full
two-node suite can't run green in a reasonable wall-clock.

## Observed

```
mined to 107 (alice was 101)
t=5s alice=101 … t=35s alice=107  → CAUGHT_UP at ~35s
```

`02_channel_open_close` test 1 (open) passes in ~1–2 min; test 2 (close) exceeds
the 300 s probe budget. `--dev-bitcoind-poll=1` (with and without `--developer`)
is rejected by this image's lightningd (`polarlightning/clightning:24.11.1`).

## Hypothesis / options

1. The Polar image's lightningd may not be a developer build — confirm with
   `lightningd --help | grep -i developer` / check `--version` for `DEVELOPER=1`.
2. If dev-enabled: pass `--dev-bitcoind-poll=1` to **both** nodes — alice via the
   entrypoint (write it to `~/.lightning/<net>/config` before `lightning daemon
   start`, SIT-only) and bob via `sit_setup_alice_bob`. Then drop / shorten the
   `sit_mine` wait.
3. If not dev-enabled: either build a developer lightningd into the image, or
   accept the 30 s waits and raise the `check-sit` timeout (slow but green).

## Acceptance

- After mining in regtest, both nodes reflect the new blockheight within ~2 s.
- `02_channel_open_close` (open **and** close) passes well within the timeout.
- The `sit_mine` wait is removed or reduced to a short bound.

Depends on nothing; unblocks [[BUG-042]] (LN flows) iteration.
