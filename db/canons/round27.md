# Round 27 — predictions, written 2026-09-08 12:45 UTC / 7:45 AM CT

**Written before round 26 finished and long before round 27 is scheduled**, so
that neither prediction can be tuned to a result. The schedule below is filled
in when the round is laid out; everything above it is fixed as of this commit.

The recertification for two migrations, both drafted and dry-run read-only
against the live catalog while round 26 was still running:

- **0223** — `twin.ottoq_sim_compute_charger_load_kw` hoists
  `ottoq_depot_running_run(p_depot_id)` out of a per-row filter into a
  `MATERIALIZED` CTE. Evidence: `db/checks/0130`.
- **0224** — `ottoq.ottoq_react_to_refusals` stops hardcoding
  `p_data_source:='production'` on rows it hands a sim run id. Evidence:
  `db/checks/0132`.

## Prediction 1 — no verdict atom moves, on any column

For **0224 this is proven, not predicted.** `h_evt` hashes
`event_type | entity | sim_clock_at` over `WHERE e.sim_run_id = v_run`.
`data_source` is in neither the hashed content, nor the ORDER BY, nor the
row-set predicate, and 0224 changes nothing else. Its P1 block asserts that
against the live `ottoq_determinism_pair` at apply time rather than against this
paragraph — so if someone widens `h_evt` before the migration lands, it refuses
rather than lying.

For **0223 it is a prediction**, resting on three things:

1. `ottoq_depot_running_run` is STABLE, which is the declaration that one
   evaluation per statement equals N. P1 asserts the volatility flag.
2. A2a evaluates it per row across all 44,312 flagship `ocpp_sessions` rows —
   passing `cs.depot_id`, a Var, so the planner cannot hoist it — and requires
   every one of those evaluations to equal the single hoisted value. It passed
   on the dry run.
3. A2b compares the CTE form against the flat form on a run key that selects
   real sessions, and refuses to pass if every probe sums to zero.

**If an atom moves, the migration is what gets reverted, not the canon.**

## Prediction 2 — the pair loses about 109 seconds

`db/checks/0130` measured the load meter at **195.4 s per 12-tick pair**, of
which **108.8 s** is 8,966,506 evaluations of a constant. 0223 removes that
108.8 s and leaves the rest.

The baseline is round 26's own numbers, not a remembered range — that mistake
is what made round 26's prediction 2 land 87 s wide:

| column | round 26 | predicted round 27 |
|---|---|---|
| a — `busy_day`/314159/12t | 537 s | ~428 s |
| b — `busy_day`/171717/12t | 533 s | ~424 s |
| c — `normal_day`/171717/12t | 477 s | ~368 s |
| d — `busy_day`/424242/12t | 529 s | ~420 s |
| mean | **519 s** | **~410 s** |

**The stated prediction is the mean: 519 s → about 410 s, ±30.** The ±30 is not
decoration; round 26's four columns spanned 60 s, so a single column landing
outside the band means nothing and the mean landing outside it means the
arithmetic is wrong.

24-tick columns are excluded from the prediction. The meter's cost scales with
ticks and the fingerprint's does not, so the 24-tick saving should be roughly
double — but that is an inference, and round 26's e and f are the first
post-0222 24-tick measurements this project has, so there is no baseline worth
predicting against yet.

## What would falsify each, stated as an action

| result | reading | action |
|---|---|---|
| an atom moves | one of the two arguments is wrong | revert that migration, keep the canon |
| mean lands ~410 | both fixes did what they claimed | sweep FIX 2 (the `ocpp_sessions` Seq Scan) next |
| mean lands ~519 | the hoist bought nothing on a pair | 0223 joins the two earlier fixes that measured beautifully and moved no clock; say so in this file and stop optimising the meter |
| mean lands between | partial | attribute before continuing — do not average it into a win |

## Schedule — laid out 2026-09-08 13:44 UTC, after 0223 and 0224 were applied

| | column | fires (UTC) | fires (CT) | slot |
|---|---|---|---|---|
| a | `busy_day` / 314159 / 12t | 13:55 | 8:55 AM | 17 min |
| b | `busy_day` / 171717 / 12t | 14:12 | 9:12 AM | 17 min |
| c | `normal_day` / 171717 / 12t | 14:29 | 9:29 AM | 17 min |
| d | `busy_day` / 424242 / 12t | 14:46 | 9:46 AM | 17 min |
| e | `busy_day` / 171717 / **24t** | 15:03 | 10:03 AM | 31 min |
| f | `busy_day` / 424242 / **24t** | 15:34 | 10:34 AM | 31 min |
| **g** | `busy_day` / 171717 / **24t**, **instrumented** | 15:52 | 10:52 AM | — |

**The slots are deliberately too generous, and the new lookback is why.** The
last-K-runs window added this morning takes the **max** of the last six runs of
each tick count, and six still reaches back past 0222: 754 s for 12-tick,
1,336 s for 24-tick. So the slots are sized for an engine two fixes ago, giving
17 and 31 minutes against pairs that should run ~7 and ~11.

That is the rule working, not failing. `scripts/schedule-round.sql` argues
max-of-K rather than mean-of-K precisely because a slot too SHORT puts two pairs
on one depot and contaminates both — which had to be fixed by hand mid-round 25
— while a slot too LONG costs only wall clock. I had four post-0222 12-tick
measurements in hand and the temptation to tighten by hand was real. Following
the committed rule instead is the point of having written it down.

After this round the window will hold six post-0222 runs and tighten on its own.

## g — the seventh column, and why it is not one of the six

`r27_g` repeats column e's world **instrumented**, and sits after f so it cannot
perturb the six that judge prediction 2. `r25_g` is the precedent.

It carries `track_functions='all'` — **not** `'pl'`, which is the setting `r25_g`
used and the reason `db/checks/0129` could not see what `0130` later found. `'pl'`
counts only procedural-language functions, and every hop of the load-meter chain
is a SQL function. The baseline snapshot of `pg_stat_user_functions` was taken at
**13:45:25 UTC**; no other session sets `track_functions`, so the delta across
`r27_g` is exactly that pair.

It answers G27 directly: **is `ottoq_determinism_pair`'s self time on a 24-tick
pair ~255 s, the same as the 12-tick pair `r25_g` measured, or ~500 s?** "Four
fixed calls" predicts the former. If it holds, the fingerprint is not where
round 26's extra 24-tick saving came from, and the buffer-cache hypothesis gets
its first real test in `ottoq_sim_advance_tick`'s per-tick time — 18.3 s per tick
pre-0222, per `0129`.

## What to record, per column

`db/checks/0134` (found while round 26 was running): the matrix compares nine
atoms and the pair enforces fourteen. So the round file is the only place four
of them are diffed across rounds. Record **all** of these per column, not the
eleven that were habit:

    fp  h_cmd  h_dec  h_evt  h_bkg  h_nrg  h_prop  h_defr  h_cal
    h_rule  h_rcl  h_sdr          <- carried/printed or absent in the matrix
    endst  (as md5(endst::text), arm A; assert arm B equal)

Round 26's `endst` table is the model: four columns, both rounds, identical —
which is what proved 0222 agreed with the function it replaced rather than
merely with itself.

## Results

### a — `busy_day` / 314159 / 12 ticks — **PASS**, 358 s

Fired 13:55:00 UTC (8:55 AM CT), ended 14:00:58, **358 s**.

**Prediction 1 holds on this column: nothing moved.** All fourteen atoms equal
between the arms, and every one of them equal to round 26's value — including
the four the matrix cannot see, which is the reason round 26's endst table
existed and why 0134 says to keep diffing them by hand.

| atom | arm A | arm B | vs round 26 |
|---|---|---|---|
| `fp` | `803698f3` | `803698f3` | = |
| `h_cmd` | `109e340b` | `109e340b` | = |
| `h_dec` | `9abdb4af` | `9abdb4af` | = |
| `h_evt` | `9c631343` | `9c631343` | = |
| `h_bkg` | `174b8835` | `174b8835` | = |
| `h_nrg` | `a9c6b693` | `a9c6b693` | = |
| `h_prop` | `a79c1095` | `a79c1095` | = |
| `h_defr` | `d41d8cd9` | `d41d8cd9` | = (empty-string md5 — no deferrals) |
| `h_cal` | `11a24626` | `11a24626` | = |
| `h_rule` | `fc69953b` | `fc69953b` | = |
| `h_rcl` | `0e67b89a` | `0e67b89a` | = |
| `h_sdr` | `a1f79c20` | `a1f79c20` | = |
| `endst` (md5) | `7b63e109` | `7b63e109` | = |
| `ticks` | 12 | 12 | = |

`h_evt` deserves a sentence of its own, because 0224 changed what goes into
`ottoq_events.data_source` and this atom hashes that table. It did not move, and
that is not luck: 0224's P1 block asserted against the live
`ottoq_determinism_pair` that `h_evt` hashes event_type, entity and sim_clock
over one run scope and never reads `data_source`. The prediction was made from
the verdict function's own body and the round agrees with it.

### Prediction 2 on column a: right about the direction, still wrong about the size

| | round 26 | predicted | round 27 | |
|---|---|---|---|---|
| a — `busy_day`/314159/12t | 537 s | ~428 s | **358 s** | **70 s faster than predicted** |

The per-column prediction was 537 − 109 = 428 s. It came in at 358 s, a saving of
**179 s** where 109 s was claimed — 1.64x the prediction, in the direction that
flatters the fix.

**One column is not a verdict on prediction 2** — the committed rule is that the
mean judges it, and a single column outside the band means nothing. But it is
worth naming now which way this is likely to go, before the other five land and
the temptation to explain them appears: the same shape as G27. Round 26's
24-tick columns also saved about 2.2x what the fingerprint arithmetic predicted,
and that anomaly is what `r27_g` was scheduled to measure. If b, c and d also
overshoot, then 0223 and 0222 are both cheaper than their own arithmetic says,
and the arithmetic — not the fixes — is what needs explaining. `r27_g`'s
`pg_stat_user_functions` diff is the instrument for that, and it is already
scheduled with `track_functions='all'` precisely so it can see SQL functions,
which is what blinded `0129`.

