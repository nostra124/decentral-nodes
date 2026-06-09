---
id: BUG-027
type: bug
priority: high
status: done
---

# daemon datadir tests stale after the ~/.bitcoin refactor

## Severity

CI-blocking for every PR while it lasted: the unit suite went red
because a `daemon space` test asserted the pre-refactor datadir path.
A second test silently degraded to a vacuous assertion, so it stopped
guarding `daemon enable`'s datadir behaviour entirely. No end-user
data loss; the defect is in the test suite's fidelity, but it gated
all merges and let `1.34.2` tag on a red suite.

## Observed

`tests/unit/streamline.bats`, `bats unit tests` job on PR #89's base
(commit `e9b4f64`, run 27200055071):

```
not ok 423 BUG-015 — space reports the data dir's disk usage
# (in test file tests/unit/streamline.bats, line 1452)
#   `[ "$status" -eq 0 ]' failed
```

The test created `$XDG_DATA_HOME/bitcoin` and expected `daemon space`
to report its size, but `daemon space` reads `daemon:_datadir`, which
returns `$HOME/.bitcoin` (user mode) — an absent path — so it errored
and exited non-zero.

A second, latent instance in the same file
(`tests/unit/streamline.bats:1228`, `FEAT-034 — disable preserves the
data directory`):

```bash
"$BITCOIN_BIN" daemon enable --user
local datadir="$XDG_DATA_HOME/bitcoin"
[ -d "$datadir" ]            # passes only because setup() pre-creates
                             # $XDG_DATA_HOME/bitcoin/wallets
```

`command:enable` actually does `mkdir -p "$(daemon:_datadir)"` =
`$HOME/.bitcoin` (`libexec/bitcoin/daemon:55`), so the assertion no
longer observes what `enable` created — it observes the wallet store
`setup()` made. The test passes vacuously and would keep passing even
if `enable` stopped creating a datadir.

## Root Cause

Commit `0d2d7d1` ("fix: use ~/.bitcoin as default user datadir instead
of XDG path") moved the user-mode datadir from `$XDG_DATA_HOME/bitcoin`
to `$HOME/.bitcoin` in `daemon:_datadir`, but two assertions in
`tests/unit/streamline.bats` still referenced the old XDG path. One
broke loudly (`space`), the other degraded quietly (`disable`
preserves), because `setup()` independently creates
`$XDG_DATA_HOME/bitcoin/wallets`.

## Fix Plan

- `tests/unit/streamline.bats` — BUG-015 `space` tests point at
  `$HOME/.bitcoin`. **Already shipped in `0d4a36f` (PR #89)** as an
  inline CI unblock; recorded here for traceability.
- `tests/unit/streamline.bats:1228` — `FEAT-034 disable preserves the
  data directory` asserts on `$HOME/.bitcoin` (the path `enable`
  creates) instead of `$XDG_DATA_HOME/bitcoin`. This change (this PR).

No production code change: `daemon:_datadir` and `command:enable` are
correct; only the tests were stale.

## Regression Protection

The corrected `disable`-preserves test no longer creates the datadir
itself — it relies on `daemon enable --user` to create `$HOME/.bitcoin`
and on `disable` to leave it intact:

```bash
@test "FEAT-034 — disable preserves the data directory" {
	feat034_env linux
	"$BITCOIN_BIN" daemon enable --user
	local datadir="$HOME/.bitcoin"
	[ -d "$datadir" ]
	"$BITCOIN_BIN" daemon disable --user
	[ -d "$datadir" ]
}
```

Because `setup()` never creates `$HOME/.bitcoin`, this assertion now
fails if `enable` ever stops provisioning the datadir — i.e. it
guards the behaviour the old version only pretended to.

## Acceptance Criteria

1. No daemon-datadir test in `tests/unit/streamline.bats` asserts the
   pre-refactor `$XDG_DATA_HOME/bitcoin` path. Proven by
   `grep -n 'XDG_DATA_HOME/bitcoin' tests/unit/streamline.bats`
   returning nothing in a daemon-datadir context.
2. `FEAT-034 — disable preserves the data directory` asserts that
   `daemon enable --user` created `$HOME/.bitcoin` and `disable`
   preserved it. Proven by reading the test.
3. `make check-unit` (CI `bats unit tests`) is green, including
   tests 423 and the FEAT-034 disable-preserves test.
