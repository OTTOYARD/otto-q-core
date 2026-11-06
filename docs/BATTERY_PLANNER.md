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
| 0799: plan-follow yields to a live grid call; follows a plan only while it is fresh | otto-q-core `db/migrations/0799_…` | **pending** (lab-tested) |
| 0803: the per-tick forecast log, the nightly refit, the forecast reader | otto-q-core `db/migrations/0803_…` | **pending** (lab-tested) |
| 0804: the planner's request, fire and landing; the orchestrator's hook | otto-q-core `db/migrations/0804_…` | **pending** (lab-tested) |
| `ottoq-battery-planner` edge function | otto-q-core `edge-functions/ottoq-battery-planner/` | **not deployed** |
| `POST /optimize/battery-plan` | ottoq-intelligence PR #21 (`claude/battery-planner`) | **draft PR** |

**Lab checks** (each in its migration's header or the PR):

- **0803:** the SQL refit reproduces the lab's Python models to within 4e-11, and the reader gives the lab planner's
  forecast to within 0.05 kW. A 36-hour lab day with the log on wrote 432 rows and left every car and all 864 energy
  commands exactly as the base day.
- **0804:** it applies in order on the lab template (0799, 0803, 0804). Its live check passes on a lab run. A 3-hour lab
  day through the whole chain landed 35 of 35 plans; the battery followed the plan on every tick after the first.
- **The service:** on three lab ticks it returns the lab planner's objective to 1e-9 and its setpoints to 0.1 kW. Its
  suite passes, 58 tests.

## 4. Switching it on (each step a person's)

1. Apply 0799, then 0803, then 0804. Each checks for the one before it.
2. Merge ottoq-intelligence #21 and run its deploy workflow. `/health` lists `battery_planner`.
3. Deploy `ottoq-battery-planner` with verify_jwt on. It reads the service's address from `ottoq_service_endpoints` and the
   token secret `ottoq-cpsat-propose` already uses.
4. Turn on `bess_forecast_learning` = 1 at the twin depot. From then on every demo run logs its ticks. The nightly refit
   writes a usable model once it has 3 local days with 200 examples at every half hour ahead.
5. Once a usable model exists (`SELECT public.ottoq_bess_forecast_model('11111111-…')` is not null), turn on
   `bess_planner_enabled` = 1 and `energy_mpc_follow` = 1 at the twin depot.
6. Check one demo run:
   - energy commands with mode `mpc_follow`;
   - `ottoq_energy_plan` rows from `bess_planner` landing `ready`;
   - ledger rows under `intelligence_battery_planner`.

Until a model is usable, the request is empty and the day plan decides. That is also true whenever the planner is late or
fails, and whenever a demand-response call is live.

## 5. The lab on production's own forecast (2026-11-06)

PENDING: the six seeds through the production chain (`p36e2e`), and the comparison of what the planner reads beyond the
forecast's four hours.

## 6. B2: the battery grades itself in hindsight (0805, pending)

Each local day a run's battery ran is graded once the day is over. 0805 does this hourly, behind
`bess_hindsight_enabled`. The planner run on the day's realized load is perfect foresight. Set beside the realized bill and
the no-battery bill, every one priced at the realized end charge, it gives:

- **capture share** = (no battery − realized) / (no battery − perfect foresight): how much of what could have been saved
  was saved;
- **left on the table** = realized − perfect foresight;
- the half hours that set each peak.

Each row is kept whole in `ottoq_bess_hindsight` (evidence), so it outlives the demo-run purge of the snapshots it was built
from. `ottoq_bess_hindsight_board` is the one line a day a person or an agent reads.

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
