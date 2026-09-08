# Round 26 — 2026-09-08 (scheduled 11:35–13:22 UTC / 6:35–8:22 AM CT)

The recertification for five migrations applied 11:15–11:20 UTC: **0219** (h_sdr
enforced), **0213** (KPI-4 vocabulary), **0220** (schedule_task SDR emitter),
**0221** (the run-scope predicate), **0222** (the boot fingerprint).

Flagship depot `11111111-…`, pinned sim start `2026-09-01 02:00:00+00`, proposer
quiesced, arm budget 900 s.

## Slots, derived rather than chosen

First round scheduled by `scripts/schedule-round.sql`, which reads the slowest
completed run of each tick count from the last five days and multiplies by 1.35.
That gave **19-minute slots for 12-tick and 31 for 24-tick**, against the 16 and
26 hand-picked for round 25 — which collided mid-round and had to be moved by
hand.

| | column | fires (UTC) | fires (CT) |
|---|---|---|---|
| a | `busy_day` / 314159 / 12t | 11:35 | 6:35 AM |
| b | `busy_day` / 171717 / 12t | 11:54 | 6:54 AM |
| c | `normal_day` / 171717 / 12t | 12:13 | 7:13 AM |
| d | `busy_day` / 424242 / 12t | 12:32 | 7:32 AM |
| e | `busy_day` / 171717 / **24t** | 12:51 | 7:51 AM |
| f | `busy_day` / 424242 / **24t** | 13:22 | 8:22 AM |

The spacing is derived from **pre-0222** durations, so it is deliberately
generous: if 0222 does what it should, every pair finishes well inside its slot.
Erring that way costs wall clock and cannot corrupt a round.

## The two predictions, stated before the round runs

**1. No verdict atom moves, on any column.** Four of the five migrations touch
paths the certification exercises, and every one of them argues it is
output-identical rather than merely harmless:

- **0222** rewrites `ottoq_boot_state_fingerprint`, which computes the
  **enforced** `endst` atom. Its A2 recomputed the fingerprint on two real
  `(depot, run)` pairs — including one where *every* row is foreign, so the
  `fgn` branch ran at its widest — and got byte-identical answers.
- **0221** rewrites `ottoq_validate_assignment`, a decide-path function. The row
  set differs only on a booking carrying the all-zero sentinel uuid, and P1
  asserted there are none.
- **0219** enforces an atom that already agrees on all six columns.
- **0213** and **0220** touch a KPI view and a dormant trigger the pair cannot
  reach (0220's P2 asserted the twin's schedule materializer still has no
  callers).

If an atom moves, the argument is wrong somewhere and **the migration is what
gets reverted, not the canon.**

**2. The pair gets materially faster.** `ottoq_boot_state_fingerprint` measured
warm on flagship after 0222: **260.6 ms and 218.2 ms**, against ~64,000 ms
before — 250–290×. It is called four times a pair, so 255.3 s of a 700.7 s pair
should become about one second. The 12-tick columns should land near **450 s**
rather than 700–830.

That is a prediction, not a claim. Two earlier performance fixes on this task
measured beautifully in isolation and bought zero seconds on the pair; this one
is written down in advance so it can be wrong in public.

## Results

### a — `busy_day` / 314159 / 12 ticks — **PASS**

Fired 11:35:00 UTC, ended 11:43:57, **537 s**, `equal true`. Every atom
byte-identical to the same column in round 25:

| atom | round 25 | round 26 a | |
|---|---|---|---|
| `fp` | `803698f3` | `803698f3` | = |
| `h_cmd` | `109e340b` | `109e340b` | = |
| `h_dec` | `9abdb4af` | `9abdb4af` | = |
| `h_evt` | `9c631343` | `9c631343` | = |
| `h_bkg` | `174b8835` | `174b8835` | = |
| `h_nrg` | `a9c6b693` | `a9c6b693` | = |
| `h_prop` | `a79c1095` | `a79c1095` | = |
| `h_cal` | `11a24626` | `11a24626` | = |
| `h_rule` | `fc69953b` | `fc69953b` | = |
| `h_rcl` | `0e67b89a` | `0e67b89a` | = |
| `h_sdr` | `a1f79c20` | `a1f79c20` | = |

The `round 25` column is round 25's **g** re-run (10:52 UTC), not its 08:25
pair-1: pair 1 predates 0218 and its `h_sdr` was the contaminated kind
(`0df9a909` vs `65ec044e`). Every other atom is identical in both.

**Prediction 1 holds on this column.** Five migrations — including 0222's
rewrite of the function that computes the *enforced* `endst` atom, and 0221's
rewrite of a decide-path function — moved nothing. This is also the first round
in which `h_sdr` could have failed the pair rather than merely been recorded
(0219 enforced it), and it did not.

**Prediction 2 — the mechanism is right to within 14%, the number I published
was wrong.** I wrote "near 450 s"; it landed at **537 s**. Both halves of that
deserve saying, because they call for opposite next actions.

The baseline, measured rather than remembered — every 12-tick flagship pair in
`cron.job_run_details` over the 30 hours before 0222, all uninstrumented:

```
822  832  720  731  643  819  777  749  758  649        (09-07 evening, rounds 22–24)
797  801  812  686  735  754                            (09-08 morning, round 25 a–d)
```

n = 16 · min **643** · max **832** · mean **755** · spread ±95 s round to round

Plus `r25_g` at **701 s**, the same column as `r26_a`, carrying
`track_functions='pl'` and `pg_stat_statements.track='all'`. That it beat the
same column's uninstrumented 812 s is the first thing to notice: **the noise on
this measurement is around ±90 s**, so no single-pair comparison settles
anything. The robust statement is the order statistic:

| | |
|---|---|
| pre-0222 12-tick, n=16, min | 643 s |
| pre-0222 12-tick, mean | 755 s |
| **r26_a** | **537 s** |
| vs. the mean | −218 s (−29%) |
| vs. the *fastest pair ever recorded* on this workload | −106 s |
| what the fingerprint arithmetic predicted | −255 s |
| what my published landing point said | ~450 s |

So the fix delivered **218 of the 255 seconds** it argued for — 86% of its own
prediction, and 537 s is below all sixteen pre-0222 measurements, which no
amount of ±90 s noise explains away. The 450 s figure was wrong because I
subtracted 255 from ~700 when the measured mean was 755. The mechanism held;
the arithmetic was done against a baseline I had not looked up.

That is worth separating out, because "the fix underdelivered" would mean going
back into `ottoq_boot_state_fingerprint`, and "I subtracted from the wrong
number" means the fingerprint is done and the next 439 s —
`ottoq_sim_decide_and_dispatch` at 388.7 s, per `db/checks/0129` — is where the
remaining time lives.
