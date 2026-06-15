---
id: BUG-042
type: bug
priority: medium
status: open
---

# SIT — the LN channel/payment live suites need a pass against the working stack

## Severity

**Medium.** With the harness now bringing up a real two-node regtest stack and
the channel-OPEN flow green end-to-end (BUG-038), the remaining Lightning
channel/payment suites still fail — they were written but never run green, so
they carry stale verbs and timing assumptions. These are the suites that prove
the core `lightning` verb surface against a live node.

## Scope (container suites)

- `02_channel_open_close` — open passes; **close** still needs a pass (the
  `lightning channels` → `lightning channel list` typo is fixed; verify the
  close → `channel pending` → CLOSINGD/ONCHAIN transition end-to-end).
- `03_invoice_pay_bolt11` — alice pays a BOLT-11 minted by bob; recv mints a
  BOLT-11 with a description.
- `04_offer_pay_bolt12` — alice pays a BOLT-12 offer from bob.
- `14_fee_forward` — `fee get`/`fee set` round-trip; `forward stats`/`forward
  list` headers (the `channels` typo is fixed here too).
- the `balance returns the current SQLite-computed value` test.

## Observed (last full run)

```
not ok 4  channel close + pending shows it closing
not ok 5  alice pays a BOLT-11 invoice minted by bob
not ok 6  alice pays a BOLT-12 offer from bob
not ok 8  recv mints a BOLT-11 with the message in the description
not ok 9  balance returns the current SQLite-computed value
not ok 23 fee get …   not ok 24 fee set …
not ok 25 forward stats …   not ok 26 forward list …
```

Most cascade from setup needing a synced node + a funded channel — so they
should largely clear once [[BUG-041]] (fast polling) lands. Triage each for
genuine stale-verb / assertion bugs vs. timing.

## Acceptance

Each listed suite passes against the live stack under `make check-sit`. File any
genuine `lightning`-verb bug separately (with a unit regression per
`skills/bugs.md`).

Depends on [[BUG-041]] for practical iteration.
