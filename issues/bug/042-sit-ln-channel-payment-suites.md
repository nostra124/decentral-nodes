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

## Progress

- [[BUG-041]] (fast polling) is **done** — iteration is now ~1–2s per
  confirmation instead of ~30s.
- **`channel close` verb fixed.** It exited non-zero on a jq "Invalid numeric
  literal": `lightning-cli close` streams `# …` fee-negotiation notices to
  stdout before the JSON, and `cmd_close` fed them to jq. It now strips `^#`
  (and accepts the newer `txs[0]` reply shape). Regression added — the
  `lightning-cli-mock` now emits the notices, so the close test fails on the old
  verb and passes on the fix. The close verb returns ok + reaches ONCHAIN
  end-to-end in isolation.

## Remaining

1. **Test isolation / channel-state accumulation.** Each test's `setup` opens a
   fresh channel but nothing closes/forgets alice's prior channels, so they pile
   up and each `sit_open_channel` CHANNELD_NORMAL wait slows across a suite (the
   `02` *close* test stalls behind it). Make each test start from a clean channel
   set (teardown closes / dev-forgets alice's channels, or each suite resets).
2. Then triage `03_invoice_pay_bolt11`, `04_offer_pay_bolt12`, `14_fee_forward`,
   and the balance test for genuine stale-verb / assertion bugs.

## Acceptance

Each listed suite passes against the live stack under `make check-sit`. File any
genuine `lightning`-verb bug separately (with a unit regression per
`skills/bugs.md`).

Depends on [[BUG-041]] (done) for practical iteration.
