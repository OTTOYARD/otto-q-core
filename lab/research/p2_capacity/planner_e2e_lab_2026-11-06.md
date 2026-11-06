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

PENDING.
