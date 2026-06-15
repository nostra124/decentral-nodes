---
id: BUG-045
type: bug
priority: low
status: open
---

# SIT — bob's bundled clnrest/wss-proxy plugins abort (missing python gevent/websockets)

## Severity

**Low (noise / robustness).** bob's second lightningd logs two plugin aborts on
every start:

```
plugin-clnrest:   Killing plugin: disabled itself: No module named 'gevent'
plugin-wss-proxy: Killing plugin: disabled itself: No module named 'websockets'
```

These are **self-disables** (the plugins are not "important"), so they no longer
crash the node — `cln-grpc` was the fatal one and is now disabled (BUG-038). But
the noise hides real issues in the bob log and is a latent trap if a future CLN
marks them important.

## Fix (pick one)

- Install the python deps in `Dockerfile.clightning`:
  `pip install --break-system-packages gevent websockets` (or via apt), **or**
- Disable them explicitly for bob in `sit_setup_alice_bob`:
  `--disable-plugin=clnrest --disable-plugin=wss-proxy` (mirrors the cln-grpc
  disable), and do the same for alice's bring-up if the logs warrant it.

Prefer the explicit `--disable-plugin` route unless a suite actually exercises
the REST/wss API.

## Acceptance

bob's log is clean of plugin aborts; the node still comes up. No behaviour
change to the tests.
