---
id: FEAT-317
type: feature
priority: medium
status: open
milestone: 3.7.0
---

# Access-control defaults for webmin / usermin

## Summary

Webmin (root admin, :10000) and Usermin (per-user, :20000) expose
powerful surfaces over HTTPS. The current `daemon enable` accepts the
package defaults, which may listen on all interfaces with no host
restriction. Give operators an easy, safe-by-default lever.

## Acceptance criteria

1. `webmin-node daemon enable [--allow <cidr>...]` and the same for
   `usermin-node`: write the corresponding `allow=` lines into
   `miniserv.conf` (restart to apply).
2. With no `--allow`, default to a clearly-logged safe posture — e.g.
   restrict to `127.0.0.1`/private ranges, or at minimum emit a `warn`
   that the service is reachable from all interfaces with a one-line
   remediation.
3. Idempotent; never broadens access silently.
4. Documented in the man-page SECURITY sections; bats coverage for the
   conf mutation.

## Notes

Complements FEAT-316 (the `config` verb can read/show the resulting
`allow=`). Keep it advisory-but-loud rather than surprising operators by
locking them out of a remote box.
