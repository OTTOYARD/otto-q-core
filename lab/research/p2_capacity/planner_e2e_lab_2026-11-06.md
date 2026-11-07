# The battery planner on the forecast production would have, through the chain production would run (research lab, 2026-11-06)

**Question.** The steady-state study (`planner_36h_lab_2026-11-06.md`) found the planner worth $226 a day on the day plan.
That planner read a learned forecast fitted in Python on the lab's after-tick audit, and beyond its four hours the next
seed's whole day copied step by step. Production has neither. Its forecast is learned in the database from the
orchestrator's own mid-tick log (0803). Its hours beyond are its own past days. Its plan comes from a service through an edge
function (0804). Is the planner still worth that on what production would actually have? And is the gain the planner's,
or would the learned forecast inside the day plan do as well?

## Method

- **Days.** As the steady-state study: `normal_day`, 116 cars, 36 hours from 6 AM day 1 (432 ticks of 5 minutes), seeds
  171717, 424242, 616161, 818181, 919191 and 373737. Each is billed over its last 24 hours from 6 PM day 1, against its
  36-hour base day car for car (`planner_table.py --base b36 --window 12 --charge-start`).
- **The forecast production would learn.** Each base day was run again with 0803's log on (`b36log`, template
  `ottoq_lab_0803`: 0801 + 0803). Each kept every car-facing scorecard line and every energy command of its base day, and
  wrote one row a tick from the orchestrator's mid-tick reading. `planner_e2e_template.py` copies the six logs into
  `ottoq_lab_0804m` (0801 + 0799 + 0803 + 0804) and fits one model per seed on the other five days with the database's own
  refit (`ottoq_bess_forecast_refit`, folds by run, 80th percentile, lambda 10).
- **Arms:**
  - `p36prof` / `p36profq`: the lab planner (`battery_lp.py`) on the database's learned forecast and band for four hours,
    and beyond them the depot's learned day by half hour (mean / 80th percentile across days). This uses the after-tick
    models of `ottoq_lab_0803m`, ids 2-7, which equal the Python ones.
  - `p36sqlshape` (two seeds): the same near term with the copied shape beyond. A control: it should be the
    steady-state study's `p36q80` by another road.
  - `dp36learn`: no planner. The day plan reads the learned forecast instead of its rule (`whatif_dayplan_learned.sql`):
    the band for four hours, the learned day's EV mean beyond.
  - `p36e2e`: **production's chain.**
    - Every tick the orchestrator asks for a plan (`bess_planner_enabled`).
    - `ottoq_bess_planner_request` builds the request from the in-tick model held out from the day, the depot's learned
      day beyond (mean), the tariff, the billing period's peak so far with its margin, the call reserve as the depot's
      dials hold it (from 3 hours before the window), the battery and the day plan's money terms.
    - `capacity_day.py --planner-service` plays the edge function: it posts each pending request to a local
      ottoq-intelligence carrying `POST /optimize/battery-plan` (branch `claude/battery-planner`) and lands the answer with
      `ottoq_bess_planner_land`.
    - The next tick follows the plan under 0799 (`energy_mpc_follow`).

## Results

### The forecast production would have, in the lab planner (read 2026-11-06 by 15:14 UTC)

Every day kept every car-facing line of its base day's scorecard (6 of 6 seeds, every arm).

| seed | day plan | no battery | copied day beyond (p36q80) | learned day, mean (p36prof) | learned day, q80 (p36profq) | day plan on the learned forecast (dp36learn) | perfect foresight |
|---|---:|---:|---:|---:|---:|---:|---:|
| 171717 | 1512.83 (1000, 23:35) | 1683.91 | 1348.48 (748) | 1335.81 (729) | 1363.84 (770) | 1546.17 (1043) | 1119.34 |
| 424242 | 1539.61 (1019, 23:00) | 1610.88 | 1343.89 (711) | 1323.15 (678) | 1330.89 (694) | 1496.33 (946) | 1141.76 |
| 616161 | 1696.98 (1160, 22:45) | 1701.86 | 1396.57 (704) | 1397.88 (704) | 1401.55 (708) | 1698.17 (1156) | 1212.05 |
| 818181 | 1576.41 (1066, 22:45) | 1617.14 | 1291.43 (628) | 1298.18 (638) | 1305.83 (655) | 1538.00 (1003) | 1129.14 |
| 919191 | 1486.24 (1018, 22:50) | 1529.85 | 1296.10 (730) | 1290.00 (722) | 1295.30 (723) | 1450.25 (957) | 1051.27 |
| 373737 | 1491.76 (975, 22:15) | 1601.00 | 1271.25 (632) | 1279.40 (646) | 1292.05 (661) | 1456.42 (921) | 1120.10 |

| plan | mean bill | saving on the day plan | seeds better | share of the gap to perfect foresight |
|---|---:|---:|---:|---:|
| the day plan as it runs | $1,550.64 | | | 0% |
| the planner, a copied day beyond (the steady-state study) | $1,324.62 | $226.02 | 6 of 6 | 54% |
| **the planner, the depot's learned day beyond (mean)** | **$1,320.74** | **$229.90** | **6 of 6** | **55%** |
| the planner, the learned day's 80th percentile beyond | $1,331.58 | $219.06 | 6 of 6 | 52% |
| no planner: the day plan on the learned forecast | $1,530.89 | $19.75 | 4 of 6 | 5% |

Bills in USD over the window from 6 PM day 1 at the base day's battery states (half-hour peak kW, and the half hour's end
CT for the day plan). The control `p36sqlshape` (the database's forecast with the copied day) is `p36q80` by another
road, within the rounding of the forecast's inputs: $1,343.88 against $1,343.89 on 424242 (711 kW both), $1,297.22 against
$1,296.10 on 919191 (732 against 730 kW).

- **What production would have is as good as the copied day.** Beyond the forecast's four hours, the depot's own learned
  day (the mean of its past days by half hour) does as well as another seed's whole day copied step by step: $229.90 a day
  against $226.02, better on 3 seeds of 6. The cautious version (the 80th percentile across days) does a little worse,
  $219.06: holding energy for a worse evening than comes costs more than it saves. `bess_planner_beyond` stays 0 (the
  mean).
- **The gain is the planner's.** The same learned forecast inside the day plan saves $19.75 a day, better on 4 seeds of 6,
  5% of the gap. The day plan holds a level and charges into the evening's wave; it does not budget the battery for the
  evening it can now see.

### Production's chain, end to end

The chain was run five times. Each run found something the lab planner never had to face, because it plans *before* a
tick from the state *after* the last one. Production asks for its plan *inside* a tick, from the orchestrator. Each defect
was fixed in 0804 (or the service) before the next run. The bills are over the window from 6 PM day 1, as above.

| run | what 0804 sent | seeds | saving on the day plan | what it showed |
|---|---|---:|---:|---|
| `p36e2e` | the first request | 2 | $5.02 | **the tick under way was missing from the plan's windows.** Only step 0 of a plan ever runs. A plan blind to the half hour forming put its discharge in later steps, and every tick's new plan did the same. Through day 1's 10 PM wave (EV 1,086-1,204 kW) the battery sat at 65% doing nothing. The billed peak ratcheted to 958 kW overnight and 1,109 kW at midday (seed 424242: $1,622.79, worse than no battery). |
| `p36e2ef` | + the tick's own load and grid draw | 2 | $216.60 | the windows were right. But the peak already billed came from the day plan's ratchet, which counts the snapshot at the billing period's first instant: it belongs to the interval before, the last unbilled one, where the plan charged freely. That counted an 815 kW half hour as paid at 6 PM (seed 171717). The past was also counted in snapshots, which is half an hour only at a 5-minute tick (production ticks every 2). |
| `p36e2eflag2` | the same, every answer landing two ticks late | 2 | -$135.32 | **late plans stack charging bursts.** The demand charge bills 30-minute averages, so a plan may charge at full power inside a half hour. Followed from their third step, four stale plans each charged at 1,500 kW in the steps before 1 PM. Seed 424242 billed 1,171 kW at 12:55 PM: $1,684.69, worse than no battery. |
| `p36e2ec` | + the billed peak from the period's start, minutes not snapshots, `step_cap` (no step above its period's peak) | 6 | **$232.36** | 6 of 6 seeds, 55% of the gap to perfect foresight, level with the lab planner ($229.90). Three plans of 1,704 on one seed were infeasible: the battery sat at 15.5% and the planner deferred charging, the off-peak price being flat, until the 11 AM call-reserve floor was out of reach. The service then failed them as HTTP 500 on a NaN objective; it now answers `infeasible`. |
| `p36e2eclag2` | the capped request, two ticks late | 2 | $113.01 | the cap holds: seeds 171717 and 424242 beat the day plan by $60.77 and $165.26 (uncapped, they lost $125.56 and $145.08). |
| `p36prod` | + the battery's charge carried past the tick's own dispatch (read mid-tick, before it): **0804 as filed** | 6 | **$242.18** | 6 of 6, 57% of the gap; see below |
| `p36prodlag2` | 0804 as filed, every answer landing two ticks late | 6 | $123.93 | 6 of 6, 29% of the gap |

### 0804 as filed (read 2026-11-06 by 16:24 UTC; the days ran 15:52-16:23 UTC)

| seed | day plan | no battery | the lab planner, learned day beyond (p36prof) | **production's chain (p36prod)** | the same, two ticks late (p36prodlag2) | perfect foresight |
|---|---:|---:|---:|---:|---:|---:|
| 171717 | 1512.83 (1000, 23:35) | 1683.91 | 1335.81 (729) | 1314.44 (693, 23:35) | 1443.78 (880, 23:30) | 1119.34 |
| 424242 | 1539.61 (1019, 23:00) | 1610.88 | 1323.15 (678) | 1299.42 (633, 23:40) | 1374.20 (745, 22:45) | 1141.76 |
| 616161 | 1696.98 (1160, 22:45) | 1701.86 | 1397.88 (704) | 1412.71 (718, 23:40) | 1559.17 (930, 13:00) | 1212.05 |
| 818181 | 1576.41 (1066, 22:45) | 1617.14 | 1298.18 (638) | 1261.13 (571, 18:45) | 1470.88 (895, 22:20) | 1129.14 |
| 919191 | 1486.24 (1018, 22:50) | 1529.85 | 1290.00 (722) | 1190.27 (559, 22:35) | 1306.16 (732, 22:40) | 1051.27 |
| 373737 | 1491.76 (975, 22:15) | 1601.00 | 1279.40 (646) | 1372.80 (765, 23:25) | 1406.06 (807, 23:35) | 1120.10 |
| **mean** | **$1,550.64** | **$1,624.11** | **$1,320.74** | **$1,308.46** | **$1,426.71** | **$1,128.94** |

- **Production's chain saves $242.18 a day on the day plan, on all six seeds** ($118.96-315.28). That is 57% of the gap to
  perfect foresight, against $229.90 and 55% for the lab planner on the same forecast. Against no battery it saves $315.64
  a day. The billed half hour stood at 559-765 kW, against the day plan's 975-1,160 kW. Every car-facing line of every
  scorecard was its base day's.
- **The chain worked.** The engine asked for 2,556 plans and 2,554 landed. The other two failed with no answer: the lab's
  local service was restarted at 15:53 UTC during the runs, and the day plan took those ticks. The battery followed a plan
  on 99.1% of ticks; the rest were each day's first tick and its last minutes, when the run ends too soon for a half hour
  to plan. Round trip about 40 ms against the local service, solve about 35 ms.
- **Late answers cost half, and still pay.** With every answer two ticks late, followed from its third step, the chain
  saves $123.93 a day, still better than the day plan on all six seeds (29% of the gap). Two plans on 424242 were
  infeasible, the 11 AM reserve floor out of reach. They failed with that reason, and the day plan took those ticks.
  Production's round trip (seconds, against a 2-minute tick) should land most plans before the next tick. The freshness
  limit (`energy_mpc_max_plan_age_steps`, 0799) bounds how late a plan may be followed, and the ledger's latency column
  says when it matters.

## What it says

1. **The planner production would run is worth what the lab measured: $242 a day on the day plan at the twin's demand
   model, on all six seeds.** That is about $7,300 a month with each day billed for its own peak. The tariff bills the
   month's highest half hour, and the chain carries the month's billed peak as the period's. It needs no data production
   will not have: its forecast learns from the depot's own days, and its hours beyond four are the depot's own learned day.
2. **Running the real chain end to end was the test that mattered.** Four defects that every unit check passed, two of
   them able to cost more than no battery, showed up only when the plan went through production's own timing: asked
   inside a tick, answered by a service, followed at the step the clock is in. Each is fixed in 0804 or the service (#21).
3. **The gain is the planner's, not the forecast's.** The learned forecast inside the day plan is worth $19.75 a day.

Lab days, 116 cars, one scenario, six seeds, 36-hour runs billed from 6 PM (`bess_plan_bill_from_min` = 720 is a lab
value), the local service standing in for the edge function and the AWS service: a reading of the method on the twin, not
a forecast of production's bill.
