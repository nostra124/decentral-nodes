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
