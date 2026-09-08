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

## Schedule

*(filled in when the round is laid out, from `scripts/schedule-round.sql` with
the last-K-runs window added 2026-09-08)*

## Results

*(filled in as the columns land)*
