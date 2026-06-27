---
id: FEAT-316
type: feature
priority: medium
status: open
milestone: 3.7.0
---

# `config` verb for forgejo / webmin / usermin

## Summary

The chain nodes expose a `config` frontend (FEAT-271/272/273/298:
`bitcoin/lightning/fulcrum config list|get|set|unset|path`). The service
nodes have none — operators hand-edit `app.ini` / `miniserv.conf`. Add a
matching `config` verb so the common knobs are first-class.

## Acceptance criteria

1. `forgejo-node config {list,get,set,unset,path}` over
   `/etc/forgejo/app.ini`.
2. `webmin-node config` and `usermin-node config` over
   `/etc/webmin/miniserv.conf` and `/etc/usermin/miniserv.conf`.
3. Common keys surfaced with descriptions: listen port, SSL on/off, and
   the `allow=` host restriction (the main security lever).
4. TSV `NAME<TAB>VALUE<TAB>DESCRIPTION` output, mirroring FEAT-298;
   `set`/`unset` preserve ownership/perms via sudo and warn to restart.
5. man-page coverage + bats tests (incl. the dependency-boundary scan).

## Notes

Reuse the existing config-frontend shape from `libexec/bitcoin-node/
config`. Pairs naturally with FEAT-317 (security defaults), which sets
sane `allow=`/bind values this verb can then inspect.
