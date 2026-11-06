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

PENDING.
