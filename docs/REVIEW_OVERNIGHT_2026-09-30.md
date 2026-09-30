# OTTO-Q overnight review: 2026-09-30

Written overnight, 11:45 PM - 6 AM CT, while night 1 of the throughput sweep (`frontier_2026_09_29`) ran on the twin
depot. Nothing here was applied, and nothing wrote to the live database: every figure comes from read-only queries
against committed rows. Every fix is a `PENDING` migration with tests, waiting for Chase's approval.

Chase's three priorities, in his order, are the ranking key:

1. **Energy**: savings from the battery, solar, and forward planning.
2. **Fewer chargers, smaller footprint**: every car fully serviced all day, with no big downtime.
3. **Vehicle revenue and uptime.**

Rules 8, 9 and 10 bind everything below. Only the twin depot was tested. No fix lowers a car's charge target or ends a
charge early. Every lever that changes how the engine behaves is either a repair of something broken, or a research-wing
dial whose default is today's behaviour.

---

## What I found, in plain language

**The battery was working against the bill it exists to lower.** Under Nashville's real prices, the battery earns its
keep almost entirely by cutting the demand charge (NES bills the highest half hour of the month at $21.40/kW in
summer). Three things went wrong on the smoke day:

- The battery misread the peak it had already been billed for. It used the highest five-minute reading (2,415 kW)
  instead of the highest half-hour average that NES actually bills (1,961 kW). It treated the 454 kW gap as free room.
- When it needed to refill its afternoon reserve, it did so at once, at 6 AM, into the busiest half hours of the
  morning.
- Its forecast saw a phantom peak in the next half hour on every tick. It assumed every waiting car would draw
  60% of a fast charger's nameplate power, even cars at 90% that take about 15 kW on the twin's current charge curve.
  Lane A's calibration (0573) raises that figure. 0601 follows whichever curve is live.

**Fixes: 0600 and 0601.**

**One car could never charge on any OTTO-Q test day.** Two maintenance tasks from June were never closed, in a table
nothing has used since. The safety shield counts them, concludes the car is "busy with two tasks", and refuses every
job it is offered. That Zoox sat at 24% for the whole twelve-hour test day on night 1's first OTTO-Q arm. On the
second (20 fast chargers) it waited 8 h 45 min before it first plugged in. Under the FIFO and greedy baselines, which
reach charging another way, the same car plugged in within ten minutes of the start and charged to 100%. So every OTTO-Q arm tonight carries one
stranded car that its baselines don't. That skews night 1's comparison against OTTO-Q, and whoever reads it should
know. **Fix: 0603.**

**The research wing's test days are too slow, and they slow down as they run.** The engine's own decision time per
tick rises about 5.7x from the first hour of a test day to the last, while the amount of work per tick stays flat.
Each test day runs as one 12-hour database transaction. Every update leaves behind an old copy of the row that
nothing can clean up until the day ends, so each lookup gets slower. The real fix belongs to the sweep harness:
commit every so often instead of once. That is a design for Lane A, not a patch I should write tonight.

Separately, the stall calendar carries 641 MB of index for 12,000 rows. One of its three no-double-booking
constraints is fully covered by another and can never refuse anything on its own. **0602** drops that one and
rebuilds the rest. It needs Chase's explicit sign-off, because the rules protect this table by name.

**The fast chargers are spent on nearly-full cars.** On night 1's OTTO-Q arm:

- 63% of fast-charger sessions started at 80% or more.
- Those sessions used half of all fast-charger hours at 15 kW, which is L2 speed.
- Meanwhile, cars arriving at 16–28% sat on L2 for five to eight hours.
- Nothing ever moves a car from L2 to a fast charger that frees up.

On the same seed and the same chargers, OTTO-Q's seat does this more than either baseline: 52% of fast-charger hours
on nearly-full cars, against FIFO's 41% and greedy's 28%. Greedy put **18.5% more energy into cars** (6,683 kWh against
5,639) and served 141 visits against 118. This is the biggest lever on "fewer chargers". The rule that would stop a
car that wanted L2 from grabbing a free fast charger already exists as a dial (0548) and has never been measured. It is
a sweep cell to add, in Lane A's lane. **0604** adds a read-only measure, so any arm (night 1's included) can be
scored on it.

**Two more gaps, both design work:**

- Nothing meters a mass arrival. The engine admits every charge up to the site's electrical limit, and the power cap
  the energy planner publishes is advisory only.
- The recall decision is still the placeholder threshold. It calls cars back into a depot that is already leaving 93%
  of demand unmet.

**What checked out:**

- Rule 9 held on all five night-1 arms completed by 1 AM CT: 668 departures, none below target, none with needed work
  open, and no charge unknown at departure.
- The fast-charger pointer leak (G121) is not present in the committed world tonight.
- CP-SAT's high "zero proposals" rate is mostly the depot having nothing free to assign, not a solver fault.

---

## Ranked weaknesses and what was done

| Rank | Finding | Priority hit | What changed tonight | Needs |
|---|---|---|---|---|
| 1 | **G310**: the battery billed itself on samples, refilled its reserve at once, and never looked at the half hour | 1 (energy) | **0600**: the billed peak is the completed half hour; the refill fills the valleys before the DR window; no grid charge lifts its half hour over the cap; a dial so a test day can plan the way it is billed | Approval; apply with 0573/0574, before night 2 |
| 2 | **G311**: the forecast charged near-full cars at 60% of nameplate, a phantom peak every tick | 1 (energy) | **0601**: each waiting car at the rate its battery accepts, never above the old rate | Approval; apply with 0600 |
| 3 | **G315**: OTTO-Q's seat spends 52% of fast-charger hours on nearly full cars (fifo 41%, greedy 28%); greedy delivers 18.5% more energy; no L2-to-fast upgrade | 2 (chargers), 3 (uptime) | **0604**: a read-only charger-fit measure for every arm; 0548's dial proposed as a sweep cell | Lane A: a sweep cell; approval for 0604 |
| 4 | **G313**: two June tasks strand one car on every OTTO-Q test day | 3 (uptime), and the fairness of every OTTO-Q vs baseline comparison | **0603**: the four orphaned rows cancelled | Approval; Lane A should read night 1's OTTO-Q arms with this car named |
| 5 | **G314**: test days slow down as they run (one transaction per arm) | research-wing throughput | Measured; design recommended to Lane A | Lane A |
| 6 | **G312**: a dominated EXCLUDE constraint and 641 MB of calendar index | research-wing throughput | **0602**: drop v2, REINDEX | **Chase's explicit sign-off** (rule 6) |
| 7 | **G316**: nothing meters a mass arrival; the published cap is advisory | 1 and 2 | Measured; design only | Research wing |
| 8 | **G317**: recall is the naive placeholder and site-blind | 3 (revenue) | Measured; design only | Research wing |

Also fixed: `tests/test_throughput_sweep_sql.py::test_the_smoke_arm_runs_first_and_night_one_waits_for_its_window`
went red on `main` at 04:00 UTC tonight, the minute night 1's window opened, because it read the sweeps' calendar
dates literally against `now()`. Night 2's and night 3's tests would have gone the same way on 10-01 and 10-02. The
tests now re-anchor the dated sweeps to `now()` and still assert the authored dates.

### How the fixes interact with Lane A's pending 0570-0577

- **0600 and 0601** touch the battery plan and its queue forecast, which 0573-0577 do not (P1 pins the live md5s, and
  those are the ones 0573-0577 leave in place). Both are forces_recert TRUE. The twin depot has `energy_reserve_shave`
  = 1 at depot scope (set by the promoter on 2026-09-26), so certification runs there reach the plan. Applied in the
  same window as 0573/0574, which already recertify, they cost no extra recert. Applied **before night 2** (0575),
  night 2 measures the repaired planner instead of the one described above.
- **0600's dial `bess_plan_bill_from_min`** exists because 0576/0577 bill a value day from an hour in. Left at 0, the
  plan treats the test's artificial opening surge as a real billed peak and charges freely under it. Set to 60
  run-scoped on value arms, the plan and the bill agree. That is Lane A's call. The default is the true NES bill.
- **0603** changes OTTO-Q's seat on every test day (the car charges). It is TRUE/TRUE for that reason.
- **0602** is FALSE/FALSE (no function changes, and no accepted or refused row changes, which V2 executes). Applying
  it in the same window keeps things simple.
- **0604** is FALSE/FALSE: a new read-only function with no caller.

---

## Component by component

### Energy: battery day plan, forecast, orchestrator (priority 1)

**Mapped.** The call chain is `ottoq_energy_orchestrate` → `ottoq_bess_day_plan` (0435, 0444, 0477, 0479) →
`ottoq_bess_plan_eval`, with the forecast from `ottoq_forecast_ev_known_kw` and `ottoq_forecast_ev_queue_kw` →
`ottoq_ev_queue_schedule`. The site-energy step writes `billing_period_peak_kw`. The orchestrator defends the plan's
level against the actual net load and publishes the plan as the site's forward schedule (0442).

**Tested.** `tests/test_bess_half_hour_sql.py` has 14 tests. They run against the live plan, evaluator, forecast,
scheduler and rate function, each carried byte for byte (md5-asserted), on the smoke arm's own samples. Before 0600,
the stub reproduces the live 118.1 kW refill at 11:25 UTC exactly.

**Validated.** Smoke arm `88e46ad3`:

- The opening half hour averaged 1,635 kW of EV charging plus 214 kW of battery charging. The four half hours after it
  carried 506, 697, 764 and 755 kW of battery charging.
- The billed half hour (11:10–11:40) averaged 1,960.8 kW while the plan's "ratchet" read 2,415.1 kW.
- The forecast's next half hour sat between 1,752 and 2,222 kW on every tick from 11:25 to 13:00 UTC, while actual net
  load fell from 1,937 to 610 kW.

**Counterfactual on the smoke opening.**

- With 0600, the refill at 11:25–11:35 goes to zero: the valley is later, and the half-hour guard binds.
- The billed half hour falls from 1,960.8 to about 1,834 kW. At NES's first-block rate that is about $2,700 a month on
  that day's opening alone.
- This is arithmetic on the recorded samples, not a re-run. The real figure comes from night 2 once 0600 is applied.

**0601 and 0573 together.** 0573 (Lane A) recalibrates the charge curves that 0601 reads. On tonight's uncalibrated
taper, a car at 90% averages 8–15% of its maximum to 100%, and that is what arm 3 measured. On 0573's measured tails,
a calibrated I-PACE at 90% takes about 16 kW (0444 forecast it at 62.4), and a median-curve Zoox takes about 60 kW
(0444: 120). So the phantom shrinks once 0573 lands, and 0601 keeps the forecast on whichever curve the twin charges
by. Its V-block asserts that invariant rather than tonight's numbers. It was first written with a "quarter of the old
rate" threshold that 0573's curves would have failed at apply time. That was caught by applying it on top of 0573's
actual rate function in a test, which now stays in the suite.

**One downstream reader to watch after applying 0601.** The plan's level becomes the published `charge_cap_kw`.
`ottoq_build_site_descriptor` hands that to CP-SAT as a hard cumulative power bound. A phantom-free level is lower, so
CP-SAT may propose fewer charges. No car is held back: the decide gate never reads that cap (0136), and the local path
assigns whatever CP-SAT declines.

**Also noted.** Solar uses clear-sky-index persistence with a nameplate prior. It is sound for a forecast of this
horizon and unchanged.

### Charging: charger choice, charge order, fast vs L2 (priority 2)

**Mapped.** Charger choice runs through three proposers:

- the per-car assigner `ottoq_l2_propose_stall_assignment` (`deterministic_v1`);
- the batch optimizer `ottoq_l2_optimize_assignments` (`greedy_constrained`, SoC-first);
- reservations (`reservation_honoured` / `reservation_reassigned`).

`ottoq_decide_tick`'s charge cursor enacts them. 0570 (Lane A) adds the cursor's order to the batch, and 0548's
`charge_kind_match` dial exists at default 0.

**Validated on night 1 arm 3 (`85a5d396`).**

- 117 fast-charger sessions averaged 24.5 kW. Those starting at 80% or more took 43.5 of 84 fast-charger hours at
  14.8–16.3 kW.
- 51 enacted fast-charger picks went to cars at 80% or more whose own proposal said `wanted_type='l2'`.
- At 11:10 UTC, 14 cars at 16–47% went to L2 for 130–515 minutes, while three sessions at 80% or more started on fast
  chargers within ±15 minutes.

**The three seats on the same seed** (night 1, `frontier_2026_09_29`, seed 686364201590009433, 10 fast chargers, 12
hours), read with 0604's body run read-only:

| seat (run) | fast-charger hours on cars that started at ≥80% | fast-charger kWh | all charging kWh | visits served |
|---|---|---|---|---|
| otto_q (`85a5d396`) | 43.5 of 84.0 h (52%) | 2,038 | 5,639 | 118 |
| fifo (`d038fb17`) | 34.4 of 84.9 h (41%) | 2,131 | 5,905 | 102 |
| greedy (`1edc847e`) | 27.0 of 97.2 h (28%) | 2,722 | 6,683 | 141 |

This is one seed. Per CLAUDE.md (G153), one seed is one independent observation, so this points at a cause rather than
proving a ranking. Night 1's remaining seeds will say whether it holds.

**Recommendation (G315).** Measure `charge_kind_match` = 1 as a sweep cell next to 0570's `charge_batch_order`, then
design an L2-to-fast upgrade. Rule 9 is untouched by both: faster charging to the same 100%.

### The L1 shield (probe points, posture, enforcement)

**Validated.** On night 1 arm 3, the only rule that refused anything was `HW.005` (143 refusals), and every one was
the stranded Zoox (G313). The SLA rules at `redeployment` (SLA.001, 004, 007) evaluated 166–462 times with zero
failures. `safety_critical_unprevented` = 0 on arms 3, 4 and 5 (the seed's three dcfc10 seats).

**New finding (G313).** A critical, enforced rule was reading a table the engine stopped writing in June, with no run
scope. This is the "a wiring count is not a protection count" lesson from CLAUDE.md 2.5 in a new form: the rule was
wired and enforced, and its input was dead.

### Visits, needs, atoms, and the rule-9 departure test

**Validated.** `scorecard.rule9` on all five night-1 arms completed by 1 AM CT shows `left_below_target` 0,
`left_with_needed_work_open` 0 and `charge_unknown_at_departure` 0. That covers 118, 102, 141, 159 and 148 departures
(dcfc10 otto_q, fifo, greedy; dcfc20 otto_q, fifo).
The stranded Zoox was held, not released (its deploy gate escalated at 240 minutes). Rule 9 did its job even when the
shield misfired.

### Proposers and propose/dispose

Partitioned by day, per CLAUDE.md's standing test (`ottoq_model_call_ledger`, twin depot, 09-26 to 09-30):

- **CP-SAT:** 4,480 calls, 22 enacted, and 4,202 (94%) `solved_but_zero_proposals`. The intelligence ledger's own
  `no_candidate_calls` (6,385 lifetime) nearly equals its zero-proposal count (6,650), so most zero answers are a frame
  with nothing free to assign. It reads as capacity-bound, not broken.
- **Nemotron:** enacted 4,370 of 4,483 calls, fell back 113 times. Mean decision latency is 13–26 s by day.
- **cuOpt:** last call 2026-09-27 12:03 UTC.
- The sweep's arms use none of these. Their proposals are `greedy_constrained`, `ottoq_service_priority` and `fifo`.

### Recall (C9)

**Validated.** Night 1 arm 3 made 1,406 decisions, all `naive_threshold_v1`, and 182 of them returned a car. That is a
placeholder recalling into a depot with 93% of demand unmet. See G317.

**Rule 9 bounds the fix, and it was checked before writing it.** 0542 retired `interval_scheduled_v1` because it kept
cars working past their maintenance interval. So the site-aware recall G317 recommends may only *time* a return inside
the slack the car's own need allows, and reserve its slot. It must never recall later than the need requires. Low-SoC,
fault and safety triggers are never timed. It is not built tonight.

### Twin core: tick pipeline, determinism, canon, research throughput

**Validated.**

- Night 1 arms: 1,309.8 s (otto_q), 1,022.7 s (fifo) and 932.5 s (greedy) for 144 five-minute ticks.
- Decision latency per tick rose from 416 to 2,376 ms across arm 3 while decisions per tick stayed flat.
- `vehicles` held 226 rows in 6,422 pages at 05:09 UTC, 6,938 at 05:24, and 8,074 at 05:59 with arm 7 nineteen
  minutes in. That is about 5,700 more versions of 226 rows inside one open transaction. See G314 for the mechanism
  and the structural fix.
- The same cell, early and late, on two seeds: the smoke arm (dcfc20.otto_q, `88e46ad3`, seed 481151490073635577)
  averaged 2.9 s a tick over its 24 ticks, and night 1's arm 6 (dcfc20.otto_q, `9cbe9eae`, seed 686364201590009433)
  averaged 9.3 s a tick over 144 (1,339.4 s).

**The structural fix for G314, as a design for Lane A** (0568's arm is one plpgsql function: the world lock is an
advisory *transaction* lock, each tick is a subtransaction, and 0567's build-out guard is a deferred constraint trigger
that refuses COMMIT while a build-out is applied):

1. Run the arm as a procedure that `CALL`s from pg_cron and COMMITs every N ticks. N = 12 is one sim-hour. The
   retention purge already runs as a committing procedure (0294).
2. Hold the world lock as a *session* advisory lock across those commits, released in a final block and on error.
3. Rebuild 0567's guarantee as a lease instead of a commit-time refusal. The applied build-out records its holder
   (pid and run); the arm restores it at teardown; a janitor restores any build-out whose holder is gone.
4. Accept that a failed arm leaves committed run-scoped rows. They are purged like any run's, and the arm row still
   records the failure.

**What the growing versions are.** I differenced the table statistics across arm 7's commit (`55f57dfe`,
dcfc20.fifo, 06:01 UTC):

- The 226-row `vehicles` table took 33,541 updates in one test day. Only 9% were HOT, so 91% wrote a new entry into
  each of its 9 indexes.
- Only 14,049 of those updates produced a `vehicle.state_changed` event. So 58% changed nothing but clock columns.
  That is the trigger's own test (0015): only `updated_at`, `current_soc_updated_at` or `last_state_change` moved, or
  nothing did.
- **Most of them come from one statement.** `twin.ottoq_sim_emit_depot_heartbeats` rewrites every in-depot car's
  whole 1.5 KB row on every tick, only to bump `current_soc_updated_at`, the liveness timestamp HW.003 reads. With
  roughly 90–100 cars in its ten states over 144 ticks, that is about 13,000–15,000 of arm 7's 33,541 updates. That
  figure is an estimate from the arms' state counts, not a measurement. A narrow per-vehicle liveness table would take
  that churn off the vehicle row, and it is what a production telemetry stream would write anyway, so it adds no
  simulation-only path.
- Two cuts follow, neither built tonight. First, stop the writers that re-stamp a car's sim-clock columns when nothing
  else moved. Then drop the byte-identical rest with PostgreSQL's `suppress_redundant_updates_trigger()`. The
  suppressor alone catches only that subset, because the two sim-clock columns change on every re-stamp. And a
  suppressed UPDATE reports zero rows, which flips `FOUND` and `ROW_COUNT` for any caller that branches on them.
- I ran that census tonight, comment-stripped, over `public`, `twin` and `ottoq`. 59 functions hold 113
  `UPDATE vehicles` sites, and 27 of those functions branch on `FOUND` or `ROW_COUNT`. The suppressor is therefore not
  a safe blanket fix: each of the 27 would need reading first. The heartbeat statement is the one to move first. It
  reads `ROW_COUNT` only to return it.

**Expected effect, an estimate and not a measurement.** If a committed hour costs what the first two hours cost
today, a 144-tick arm drops from about 22 minutes to about 7, and a 24-hour test day from 45–80 minutes to about 15.
That is enough to fit night 2's 24 value arms in the window. The first run after the change says whether it holds.
0602 is a separate, static saving on the calendar's path.

- `pg_stat_user_functions` still carries counters from an earlier profiling session: `ottoq_policy_get` has 21.2M
  calls and 924 s of self time, and `ottoq_approach_zone` averages 78.5 ms per call including children. They date from
  an unknown window, so they are named, not ranked.

**Mass arrival (G316).**

- The decide path admits charges up to `ottoq_ev_charge_allowance_kw` (the service or DR ceiling). The plan's
  `charge_cap_kw` is advisory.
- A shift change would plug everyone in at full power, as the smoke arm's 2,369 kW at 11:10 UTC shows.
- 0577 separates the artificial test opening from a real one for scoring; nothing yet manages a real one.
- **Rule 9 bounds any fix.** Metered charging may share site power by due time, but every car still reaches 100%,
  none is made ready later than its owner's due time, and a car with no due time charges at full rate. Slowing a car
  to trim the site's bill beyond that is a lever on the vehicle.

### Overnight learning loop

- `challenger_scan` runs every minute (cron 765).
- Automatic dial promotion is off per rule 10 (0540).
- Nothing in tonight's evidence contradicts either. Not further reviewed tonight.

---

## Evidence: the queries behind each number

All read-only, run 2026-09-30 between 04:56 and 06:25 UTC (11:56 PM–1:25 AM CT), filtered by run or by the twin depot
(`11111111-1111-1111-1111-111111111111`).

- **G310.** Energy commands for the smoke arm:
  ```sql
  SELECT tick_seq, setpoint_kw, reason->'day_plan'->>'charge_reason', reason->'day_plan'->>'ratchet_kw',
         reason->'day_plan'->>'level_kw'
    FROM ottoq_energy_commands
   WHERE sim_run_id = '88e46ad3-8ed5-4609-892a-38298e19dfca' AND command_type = 'bess_setpoint_kw';
  ```
  Half-hour energy:
  ```sql
  SELECT date_trunc('hour', timestamp) + floor(extract(minute FROM timestamp)/30)*interval '30 min',
         avg(total_ev_charging_kw), avg(grid_import_kw), avg(-bess_output_kw)
    FROM site_energy_snapshots
   WHERE sim_run_id = '88e46ad3-…'
   GROUP BY 1;
  ```
  The writer of `billing_period_peak_kw` is `twin.ottoq_sim_advance_site_energy`.
- **G311.** The logged forecasts:
  ```sql
  SELECT plan_start_clock, forecast_load_kw[1:3] FROM ottoq_energy_plan WHERE sim_run_id = '88e46ad3-…';
  ```
  Session power by SoC decile:
  ```sql
  SELECT st.stall_type, width_bucket(o.soc_start, 0, 100, 10),
         sum(o.energy_delivered_kwh) / (sum(<duration>)/60)
    FROM ocpp_sessions o JOIN stalls st ON st.id = o.stall_id
   WHERE o.sim_run_id = '85a5d396-09b3-4626-9904-29b23234d46c'
   GROUP BY 1, 2;
  ```
- **G313.**
  ```sql
  SELECT entity_id, count(*), min(tick_seq), max(tick_seq)
    FROM ottoq_decisions
   WHERE sim_run_id = '85a5d396-…' AND outcome_status = 'overridden_to_default'
   GROUP BY 1;

  SELECT count(DISTINCT sim_run_id), count(*), count(DISTINCT entity_id)
    FROM ottoq_rule_evaluations
   WHERE rule_code = 'HW.005.vehicle_one_active_task' AND NOT passed AND depot_id = '1111…';

  SELECT status, count(*), max(updated_at) FROM schedule_tasks GROUP BY 1;
  ```
  Then `ocpp_sessions` for vehicle `229f655b-803c-47c0-95fd-ca8adb9d8ef0` on runs `85a5d396`, `d038fb17`, `1edc847e`
  and `88e46ad3`.
- **G312.** `pg_constraint` (contype `x`), `pg_index` with `pg_relation_size`, and `pg_stat_user_indexes`, all for
  `ottoq_stall_bookings`.
- **G314.** Decision latency per sim-hour:
  ```sql
  SELECT (tick_seq-1)/12, count(*), sum(total_latency_ms)/12
    FROM ottoq_decisions
   WHERE sim_run_id = '85a5d396-…'
   GROUP BY 1;
  ```
  Plus `pg_relation_size('public.vehicles')`, sampled at 05:09, 05:24 and 05:59 UTC with an arm active.
  `pg_stat_user_tables.n_tup_upd` / `n_tup_hot_upd` for `vehicles` sampled at 05:47 and 06:07 UTC, differenced across
  arm 7's commit, against `count(*)` of its `vehicle.state_changed` events. The census counted
  `update\s+(public\.)?vehicles\s` matches in comment-stripped `prosrc` over `public`, `twin` and `ottoq`, with
  `IF (NOT) FOUND` / `GET DIAGNOSTICS … = ROW_COUNT` per function.
- **G315.** 0604's function body, run read-only with the parameters inlined, on `85a5d396`, `d038fb17` and
  `1edc847e`. Enacted `stall_assignment` decisions of `85a5d396` grouped by
  `proposed_action->>'stall_type'`, `(rationale->>'soc') >= 80`, `l2_engine` and `rationale->>'wanted_type'`. The
  overlap check compares each L2 start below 50% against fast-charger sessions at 80% or more that were running or
  started within ±15 minutes.
- **G316.** Every reader of `charge_cap_kw` and `ottoq_active_charge_cap_kw` in `pg_proc`.
- **G317.**
  ```sql
  SELECT implementation, should_return, return_trigger, count(*)
    FROM ottoq_recall_decisions
   WHERE sim_run_id = '85a5d396-…'
   GROUP BY 1, 2, 3;
  ```
