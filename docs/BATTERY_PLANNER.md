# The battery planner (B1)

**Written 2026-11-06 for Chase's "Yes, just keep building" (read by 13:20 UTC).** This covers the production battery
planner: what the research lab measured, the chain that brings it to production, what is built and what waits, the order
to switch it on, and what comes next. Times are UTC unless marked CT. Every number has its source beside it.

## 1. What it is, and why

The depot battery is run each tick by the engine's **day plan** (`ottoq_bess_day_plan`, 0435). The day plan picks a
level to hold the grid under, and charges or discharges to defend it.

The research lab tried a different approach on its twin copies. A **planner** budgets the battery over the whole horizon:
a linear program over every 5-minute step, minimising the energy bill, the demand charge on each billing period's highest
half hour, battery wear, and the value of the energy left at the end. It runs on a load forecast **learned from the depot's
own days**, plus that forecast's 80th-percentile out-of-sample miss.

The lab measured it on six 36-hour twin days, billed from 6 PM day 1 so the battery is in steady state
(`lab/research/p2_capacity/planner_36h_lab_2026-11-06.md`):

| plan | mean bill a day | saving on the day plan | seeds better |
|---|---:|---:|---:|
| the day plan as it runs | $1,550.64 | | |
| the planner, learned forecast + its q80 miss | $1,324.62 | **$226.02** | 6 of 6 |
| perfect foresight (the bound) | $1,128.94 | | |

The planner kept every car-facing line of each base day's scorecard. It moves only the battery; the cars charge exactly
as they would without it.

**The gain is the planner's, not the forecast's.** A truer forecast inside the day plan (G524's fix) moved nothing: −$1.23
a day. The learned forecast inside the day plan does worse than the day plan as it is (§5).

The planner cannot run in the database, because there is no LP solver there. ottoq-intelligence is where the depot's
solvers run. So production needs the forecast in the database, the solver in the service, and a seam between them.

## 2. The chain

```
 every tick (energy orchestrator, ottoq_energy_orchestrate)
   ├─ 0803: log the day plan's forecast inputs + the site snapshot ──► ottoq_bess_forecast_log (evidence)
   │                                                     nightly 11:26 UTC ──► ottoq_bess_forecast_refit
   │                                                                              └─► ottoq_bess_forecast_models
   ├─ 0804: ottoq_bess_planner_fire
   │     ├─ ottoq_bess_planner_request: learned forecast (0803 reader), tariff, billing period + peak so far,
   │     │   last half hour's draw, call reserve as a per-step floor, battery, demand rate, wear, end value
   │     ├─ INSERT ottoq_energy_plan (pending, source bess_planner, the request in detail)
   │     └─ net.http_post ──► edge function ottoq-battery-planner {plan_id}   (anon key from the vault)
   │                              ├─ reads the request from the row (never from the caller)
   │                              ├─ POST ottoq-intelligence /optimize/battery-plan  (GLOP, ~20-90 ms)
   │                              └─ rpc ottoq_bess_planner_land  (checks, lands 'ready', ledger row)
   └─ next tick: FR-1 plan-follow (energy_mpc_follow = 1) under 0799:
         only while fresh, never during a demand-response call, inside the battery's own limits;
         otherwise the day plan decides
```

## 3. The pieces

| piece | where | state |
|---|---|---|
| 0799: plan-follow yields to a live grid call; follows a plan only while it is fresh | otto-q-core `db/migrations/0799_…` | **applied** 2026-11-06 17:40:23 UTC (ledger `20261106174023`) |
| 0803: the per-tick forecast log, the nightly refit, the forecast reader | otto-q-core `db/migrations/0803_…` | **applied** 17:47:49 UTC (`20261106174749`); the log **on** at the twin depot since 17:54:09 UTC |
| 0804: the planner's request, fire and landing; the orchestrator's hook | otto-q-core `db/migrations/0804_…` | **applied** 17:50:51 UTC (`20261106175051`); its dials off |
| `ottoq-battery-planner` edge function | otto-q-core `edge-functions/ottoq-battery-planner/` | **deployed** v1, 18:59:37 UTC, verify_jwt on |
| `POST /optimize/battery-plan` | ottoq-intelligence #21 | **merged** 18:55:30 UTC, **deployed** 18:57:55 UTC (`/health` lists `battery_planner`) |
| 0806: a plan starts at the fire's clock; once per step of sim time (G528) | otto-q-core `db/migrations/0806_…` | **applied** 18:39:52 UTC (`20261106183952`) |
| 0807: the daily grade in 5-minute steps whatever the tick (G527) | otto-q-core `db/migrations/0807_…` | **applied** 18:41:39 UTC (`20261106184139`) |

**Lab checks** (each in its migration's header or the PR):

- **0803:** the SQL refit reproduces the lab's Python models to within 4e-11, and the reader gives the lab planner's
  forecast to within 0.05 kW. A 36-hour lab day with the log on wrote 432 rows and left every car and all 864 energy
  commands exactly as the base day.
- **0804:** it applies in order on the lab template (0799, 0803, 0804), and its live check passes on a lab run. On six
  36-hour lab days through the whole chain, 2,554 of 2,556 plans landed and the chain saved $242.18 a day on the day plan
  (§5).
- **The service:** on three lab ticks it returns the lab planner's objective to 1e-9 and its setpoints to 0.1 kW. Its
  suite passes, 61 tests (`step_cap`, and an infeasible plan answering cleanly, included).

## 4. Switching it on (each step a person's)

1. ~~Apply 0799, then 0803, then 0804.~~ **Done** 2026-11-06, 11:40-11:50 AM CT, each on Chase's confirmation at the connector's prompt.
1b. ~~Apply 0806 and 0807~~ **Done** 2026-11-06, 12:39 and 12:41 PM CT. 0806 (G528: a plan starts at the fire's own clock, so a tick shorter than the plan's 5-minute step follows
   it; the planner asked once per step of sim time) and 0807 (G527: the daily grade reads its day in 5-minute steps).
   Production ticks every 2 minutes and 55 of 57 demo runs ticked under 5 sim-minutes, so without 0806 the battery
   never follows a plan there, and without 0807 a grade of a fast-ticking run means nothing. At a 5-minute tick neither
   changes anything.
2. ~~Merge ottoq-intelligence #21 and run its deploy workflow.~~ **Done**: Chase merged it at 12:55 PM CT; the automatic
   deploy (aws-deploy-ssm run 23) finished at 12:57 PM CT, the box's `/health` listing `battery_planner` and its `/assign`
   smoke test answering 200 from CP-SAT.
3. ~~Deploy `ottoq-battery-planner` with verify_jwt on.~~ **Done** at 12:59 PM CT on Chase's "OK, deploy the edge
   function" (v1, the source byte-identical to the repo). Probed as the database fires it: 404 for a plan and a grade that
   do not exist with the vault's key, 401 with none. It reads the service's address from `ottoq_service_endpoints` and the
   token secret `ottoq-cpsat-propose` already uses.
3b. ~~Turn on `bess_hindsight_enabled` at the twin depot.~~ **Done** at 1:02 PM CT under "Chase (delegated to Claude Code:
   0805)"; the first two grades landed at once (§6).
4. ~~Turn on `bess_forecast_learning` = 1 at the twin depot.~~ **Done** at 17:54:09 UTC (11:54 AM CT) under "Chase (delegated
   to Claude Code: 0803)". From then on every demo run logs its ticks. The nightly refit (5:26 AM CT) writes a usable model
   once it has 3 local days with 200 examples at every half hour ahead. The first demo run, 640e4fab (2026-11-06,
   1:14-2:59 PM CT, 5.26 sim-hours), logged 1,249 rows for 1,249 ticks: one fold, reaching every half hour ahead (h = 7:
   478 examples).
4b. ~~Apply 0808 (G529) before the next demo runs.~~ **Done** 2026-11-07 at 05:45:53 UTC (11:45 PM CT on 11-06). Without it, a half hour ahead that only one fold reached gets a band of
   0 kW, and the model is still called usable. Two runs of an hour each would have produced exactly that model, and the
   models are append-only. With 0808, usable needs every half hour's band read from 3 folds' out-of-sample misses, so
   **each of the next two demo runs must run 4 sim-hours or more** (about 80 real minutes at the app's 3x; 640e4fab ran
   5.26).
4c. ~~Run the forecast-training demo runs.~~ **Done** 2026-11-07, on Chase's go-ahead to run the twin on his behalf: three
   runs after 0808, 3091816d (busy_day, 5.2 sim-hours), 5c19fd60 (normal_day, stopped by its own 60-minute backstop at
   3 sim-hours) and 73d71553 (busy_day, 5.45). The nightly refit wrote model 7 at 11:26:00 UTC and a refit by hand after the
   last run wrote model 8 at 11:42:44 UTC, both usable (5 folds; model 8 23,881 examples, every half hour graded by 3 to 5
   folds).
5. ~~Turn on `bess_planner_enabled` = 1 and `energy_mpc_follow` = 1 at the twin depot.~~ **Done** at 11:43:39 UTC (5:43 AM CT)
   under "Chase (delegated to Claude Code: 0804)", receipts ok, with model 8 in use.
6. Check one demo run. **Under way**: a0001fd6 (busy_day at 3x) started 11:43:54 UTC. Read 11:47-12:11 UTC:
   - energy commands with mode `mpc_follow`: yes, the battery's setpoint equal to the ready plan's step 0 (101.5 kW at
     8:11 AM CT sim, where the day plan would have discharged 383);
   - `ottoq_energy_plan` rows from `bess_planner` landing `ready`: yes, solver glop, about 70 ms each, 16 by 12:11 UTC;
   - ledger rows under `intelligence_battery_planner`: 16, all HTTP 200, answered.
   Its stop is set for 13:30 UTC (about 5.2 sim-hours) and its grade for the 14:17 UTC sweep.
6b. **G530: model 8 plans on a worse forecast than the day plan's beyond the next half hour.** Its own record: out of sample
   it misses more than the day plan's own EV forecast at 6 of 8 half hours. The ridge is fitted at lam = 10 and overfits
   demo runs of a few hours; on the band the battery reads (0.8 pinball loss, summed over the half hours) it scores 858.6 kW
   against the day plan's 825.1, where the regularization chosen out of sample scores 497.1 (551.2 nested). 0809 chooses
   it per half hour and defers to the day plan where that missed less; on the six 36-hour lab days it changes nothing
   ([g530_lab](../lab/research/p2_capacity/g530_lab_2026-11-07.md)). **Pending Chase's approval**; once applied, a refit by
   hand after the planner run writes the first model under it, and the next demo run reads it.

Until a model is usable, the request is empty and the day plan decides. That is also true whenever the planner is late or
fails, and whenever a demand-response call is live.

**Run length matters.** The twin's operator demo runs have averaged 3.5 sim-hours (57 runs; the longest 9.4). Production
sessions have averaged 20.9. The forecast needs runs longer than 4 hours to learn its last half hour ahead, and the planner
earns its keep over a whole evening, so the value above is a steady-state value. Short demo runs will mostly show the day
plan.

## 5. The lab, on production's forecast and through production's chain (2026-11-06)

Full record: `lab/research/p2_capacity/planner_e2e_lab_2026-11-06.md`. Six 36-hour twin days billed from 6 PM, every car
the same as on its base day:

| plan | mean bill a day | saving on the day plan | seeds better | share of the gap to perfect foresight |
|---|---:|---:|---:|---:|
| the day plan as it runs | $1,550.64 | | | 0% |
| the day plan reading the learned forecast | $1,530.89 | $19.75 | 4 of 6 | 5% |
| the lab planner, the depot's learned day beyond 4 hours | $1,320.74 | $229.90 | 6 of 6 | 55% |
| **production's chain end to end (0804 as filed, #21)** | **$1,308.46** | **$242.18** | **6 of 6** | **57%** |
| the same, every answer landing two ticks late | $1,426.71 | $123.93 | 6 of 6 | 29% |
| perfect foresight (the bound) | $1,128.94 | | | |

**Production's chain.** Every tick the orchestrator asked for a plan. The lab's stand-in for the edge function posted it to
a local copy of the service and landed the answer. The battery followed it on 99.1% of ticks. The billed half hour held at
559–765 kW, against the day plan's 975–1,160 kW.

**Running the real chain found four defects, each fixed before filing:**

1. **The tick under way was missing from the plan's windows.** The battery sat at 65% through a 1,200 kW wave.
2. **The billed peak counted the billing period's boundary snapshot,** and the past was counted in snapshots rather than
   minutes, which breaks at production's 2-minute tick.
3. **Plans followed late stacked charging bursts.** The fix is the service's `step_cap`.
4. **An unreachable reserve floor crashed the answer** (NaN) instead of failing it cleanly.

Two of the four could cost more than no battery.

## 6. B2: the battery grades itself in hindsight (0805, applied 2026-11-06 17:53:21 UTC; its dial off)

Each local day a run's battery ran is graded once the day is over. 0805 does this hourly, behind
`bess_hindsight_enabled`. The planner run on the day's realized load is perfect foresight. Set beside the realized bill and
the no-battery bill, every one priced at the realized end charge, it gives:

- **capture share** = (no battery − realized) / (no battery − perfect foresight): how much of what could have been saved
  was saved;
- **left on the table** = realized − perfect foresight;
- the half hours that set each peak.

Each row is kept whole in `ottoq_bess_hindsight` (evidence), so it outlives the demo-run purge of the snapshots it was built
from. `ottoq_bess_hindsight_board` is the one line a day a person or an agent reads.

**Not yet safe on a fast-ticking demo run (G527, read on production's data 2026-11-06 17:58 UTC).** The latest twin run,
edf611ad, ticked about every 12 sim-seconds: its 74 snapshots span 14.6 sim-minutes, the segment rounds its step to 0
minutes and its demand window to one snapshot, and the slice is billed at a full day's demand rate. The lab's days tick
every 5 minutes and never showed it. Fixed by 0807 (applied 18:41:39 UTC).

**The first grades, in production (2026-11-06 19:02 UTC).** `bess_hindsight_enabled` went on at the twin depot at 19:02:02 UTC
and the sweep, run once by hand, graded the two past demo days still in the database long enough to grade (9 sim-hours each;
four shorter runs were passed over, as 0807 intends). Both through the deployed chain, HTTP 200 in 53 and 36 ms:

| day | run | realized | no battery | perfect foresight | captured | left on the table | billed half hour |
|---|---|---:|---:|---:|---:|---:|---:|
| 2026-10-23, 8 AM-5 PM | 78c0624c | $1,376.77 | $1,544.05 | $1,216.31 | 51.0% | $160.46 | 1,086 kW (no battery 1,371; perfect 806) |
| 2026-10-25, 8 AM-5 PM | 763734d4 | $1,378.26 | $1,479.42 | $1,120.02 | 28.2% | $258.24 | 1,222 kW (no battery 1,384; perfect 806) |
| 2026-11-06, 8:02 AM-1:15 PM | 640e4fab | $1,166.64 | $1,338.43 | $892.89 | 38.6% | $273.75 | 1,137 kW at 10:55 AM (no battery 1,418; perfect 662) |
| 2026-11-07, 8:00 AM-1:14 PM | 3091816d | $1,425.72 | $1,590.49 | $1,149.75 | 37.4% | $275.97 | 1,414 kW at 10:10 AM (no battery 1,683; perfect 967) |
| 2026-11-07, 8:01-11:00 AM (normal_day) | 5c19fd60 | $1,171.94 | $1,241.40 | $286.96 | 7.3% | $884.98 | 1,490 kW at 8:25 AM (no battery 1,569; perfect 146) |
| 2026-11-07, 8:01 AM-1:28 PM | 73d71553 | $1,257.13 | $1,361.93 | $932.48 | 24.4% | $324.65 | 1,221 kW at 10:35 AM (no battery 1,396; perfect 674) |

The first two days ran on the day plan before today's battery changes. The third is the first demo run after them
(busy_day, 1,249 ticks, about 15 sim-seconds each), graded by the hourly sweep at 21:17:01 UTC (3:17 PM CT) through the
deployed chain: HTTP 200 in 70 ms, the LP solved in 52 ms. All three ran without the planner (`followed_a_plan` 0). On the
third, the battery spent 675 of 1,249 ticks defending its level, 388 charging and 186 holding, and it discharged 546 kWh.
Over the same run the day plan's own EV forecast for the next half hour averaged 2.21 times the draw that came (2,797 kW
against 1,268), so it kept guarding against a peak that never came. Replacing that forecast is the learned forecast's
job. Each part-day pays a whole day's demand rate for its own peak, as the research lab bills a day.

The three runs of 2026-11-07 are the forecast-training runs (4c), all on the day plan (`followed_a_plan` 0), each graded by
the next :17 sweep (08:17, 09:17 and 12:17 UTC). On 73d71553 the battery discharged only 358 kWh and ended at 2,479 kWh of
its 2,672. On the normal day the billed half hour was the first (8:25 AM), the depot's EV draw then fell to almost nothing while the
day plan kept forecasting 1,200 to 1,700 kW (g530_lab), and the battery discharged 38 kWh all morning: 7.3% captured, where
perfect foresight would have held that half hour to 146 kW. A grade lands at the first :17 after a run stops; a read before
then shows no grade, not a lost one.

Lab check: on the same window the grade bills exactly as the research lab's `bound_energy.py` ($1,539.61 realized,
$1,497.50 no battery). Two lab days were graded end to end: 52.8% captured with $211.74 left on the first; −1.6% with
$473.70 left on the second.

## 7. Next

- **The agent's part.** Production's agent wakes for exceptions (0795). A battery exception is the realized EV draw
  running above the learned forecast's upper band for an hour, a planner failing or late, or a day graded below its usual
  capture share. On such an exception, the agent would read the hindsight board and the forecast's grades, explain to a
  person what happened, and propose (never apply, rule 10) a change for a person to approve. One example is the planner
  reading the learned day's 80th percentile on a day the depot runs hot.
- **OTTO-Command.** A read-only battery tool ("how did the battery do yesterday?") answering from the board.
- **Publish the followed plan.** When the battery follows the planner, the site's forward schedule (`ottoq_publish_day_plan`,
  0442) should carry the planner's plan rather than none.
- **Monthly billing.** The lab bills a day for its own peak. The tariff bills the month's highest half hour, and the request
  already carries the month's peak so far as the billed peak. What that changes over a month is unmeasured.
