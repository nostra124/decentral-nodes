---
id: FEAT-315
type: feature
priority: medium
status: open
milestone: 3.4.0
---

# SIT smoke suites for the service nodes (forgejo / webmin / usermin)

## Summary

`forgejo-node`, `webmin-node`, and `usermin-node` have unit tests for
arg-parsing and packaging, but nothing exercises an actual install +
service bring-up. Now that podman is permanent in cloud sessions
(FEAT-309), add container SIT suites that prove the real flow end-to-end.

## Acceptance criteria

1. `tests/sit/suites/` (or per-node podman Dockerfiles) that, in a
   container:
   - run `<node> daemon install` (or install the package),
   - `<node> daemon enable && start`,
   - poll the service endpoint until healthy:
     - forgejo: `GET http://127.0.0.1:3000` returns the setup page;
     - webmin: `https://127.0.0.1:10000` (TLS, self-signed) responds;
     - usermin: `https://127.0.0.1:20000` responds;
   - `<node> daemon status` reports running, `stop` tears it down.
2. Soft-skip when podman is absent (mirrors `make check-sit`).
3. Wired into `make check-sit`; documented in `tests/sit/README.md`.

## Notes

These are the first SIT suites for the self-hosting nodes; keep them fast
(single-container, no external network beyond the package repo) and
deterministic. Builds on FEAT-309 (podman) and complements the
unit-level coverage.

## Environment prerequisites (measured 2026-06-27)

Authoring + running this needs a host the Claude Code cloud sandbox does
**not** provide, even with FEAT-309's podman in place — confirmed by
direct probing:

1. **Outbound network from run-time containers.** `podman run`
   containers in the cloud sandbox have no external egress (the agent
   proxy is host-loopback-only; `codeberg.org` / `dl.forgejo.org` /
   `download.webmin.com` are unreachable at both build and run time).
   Each node's `daemon install` downloads from exactly those hosts, so
   the install step can't complete there. Develop/run on a desktop or a
   CI runner with unrestricted egress.
2. **systemd in the container.** `forgejo`/`webmin`/`usermin` install as
   systemd units; the existing SIT harness (clightning) uses a custom
   entrypoint, not systemd. The smoke container must either run systemd
   (`podman run --systemd=true` on a cgroups-v2 host) or the suites must
   drive the daemons' non-systemd/`--user` run path. Decide this when
   authoring.
3. **Health-check seams.** forgejo `:3000` (HTTP setup page), webmin
   `:10000` / usermin `:20000` (HTTPS self-signed — poll with
   `curl -k`).

Because the suites cannot be executed in the cloud sandbox, they were
**not** authored blind here (unrun container/systemd test code would fake
coverage). This issue is ready to implement on a podman host with egress;
the patterns to mirror are `tests/sit/podman/Dockerfile.bitcoind` and
`tests/sit/helpers.bash`, and the soft-skip + `make check-sit` wiring is
already in place.
