---
id: BUG-044
type: bug
priority: low
status: done
---

# SIT — softdep-probe suite assertions fail (graceful-degradation behaviour)

## Severity

**Low.** `12_softdep_probe` verifies the `lightning` verbs degrade gracefully
when an optional dependency is hidden from `PATH`. It does **not** need the live
two-node stack, so it's independent of [[BUG-041]]/[[BUG-042]] — but two of its
assertions fail, which is either a real graceful-degradation bug in the verbs or
a stale test expectation.

## Observed

```
not ok 18 lightning info exits 127 with install hint when lightning-cli is hidden
   # [[ "$output" == *"install Core Lightning"* ]] failed   (12_softdep_probe.bats:11)
not ok 20 lightning address create exits 3 when apache2 is absent
   # [ "$status" -eq 3 ] failed                              (12_softdep_probe.bats:38)
ok 19 … sqlite3 hidden  # skipped (sqlite3 reachable)
```

## Triage

For each: run the verb with the dependency hidden and check the real exit code +
message against the assertion. Decide whether the **verb** should emit the
install hint / exit code (fix `libexec/lightning/*`, with a unit regression per
`skills/bugs.md`) or the **test** expectation drifted (fix the suite). The
install-hint wording and the apache-absent exit code (3) are the contract to
confirm.

## Acceptance

`12_softdep_probe` passes (or its tests skip cleanly when the probe is N/A, like
the sqlite3 one). Independent of the live-stack tickets.
