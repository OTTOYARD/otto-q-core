-- 0263  TWO ALARMING NUMBERS THAT ARE NOT FINDINGS, AND ONE REPORTED METRIC THAT
--       MISNAMES WHAT IT COUNTS.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), run
-- `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10`. Written while waiting for that run to
-- reach its 540 sim-minute ceiling, and the point of the file is the two
-- refutations: both numbers looked like serious findings, both survived about ten
-- minutes of checking, and recording *why* they are not findings is worth more than
-- the numbers were.
--
-- ══ 1. "ONLY 17% OF BOOKINGS PASS THE L1 SHIELD" — NOT A FINDING ═════════════
--
-- Measured: **644 bookings on this run, 560 `stall_assignment` rule evaluations
-- across 5 rules = 113 shield-gated assignments.** Read naively that is 17.5%
-- coverage of the calendar, and it would extend G44 ("twenty of twenty-nine rules
-- at four decision points") in an alarming direction.
--
-- IT DOES NOT. The five rules at that probe are:
--
--   EN.001.grid_capacity_ceiling        safety_critical   charging
--   EN.005.grid_event_hardstop          safety_critical   charging
--   HW.001.connector_compatibility      safety_critical   charging
--   HW.002.charger_state_precondition   critical          charging
--   HW.004.stall_single_vehicle         critical          ANY booking
--
-- Four of the five are charge-specific and cannot meaningfully evaluate a parking
-- hold: there is no connector to match and no grid load to cap when a vehicle is
-- told to stand somewhere. The bookings that skip the probe are exactly those --
-- `temp_hold` 153, `inspect` 123, `perimeter_hold` 112 -- and the 113 evaluations
-- line up with the run's charge assignments (`charge_l2` 118 + `charge_dcfc` 10 +
-- reroutes). The one rule that applies to any booking, **HW.004, states in its own
-- description that it is enforced by a partial unique index on
-- `stalls.current_vehicle_id`** -- a constraint, not a probe, and therefore in force
-- whether or not the probe runs.
--
-- So the honest sentence is: **the `stall_assignment` probe gates charge
-- assignments, and the one-vehicle-per-stall invariant is enforced by an index for
-- everything else.** Whether a parking hold should face rules of its own is a
-- design question, not a gap in this one.

SELECT e.action_context, e.rule_code, count(*) AS evals,
       (SELECT r.severity FROM public.ottoq_rules r
         WHERE r.rule_code = e.rule_code ORDER BY r.version DESC LIMIT 1) AS severity
  FROM public.ottoq_rule_evaluations e
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
   AND e.action_context = 'stall_assignment'
 GROUP BY 1,2 ORDER BY 3 DESC;

SELECT b.purpose, b.booked_by, count(*) AS bookings
  FROM public.ottoq_stall_bookings b
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = b.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1,2 ORDER BY 3 DESC;

-- ══ 2. "THE REFUSAL RATE TRIPLED" — ALSO NOT A FINDING, AND THE OPPOSITE ════
--
-- **RETRACTED IN PART, 2026-09-20 05:17 — READ `db/checks/0267` INSTEAD.** Everything
-- below was measured at tick 671 of a run that finished at 1,260, and two of its
-- numbers do not survive completion: commands per tick was NOT down 3.3x (it is down
-- 23%, because command volume accelerated sharply in the second half — 1,637 commands
-- at tick 671, 7,885 by 1,260), and dispatches per tick was NOT up 29% (it is up
-- 2.3%). The refusals-per-tick identity to three decimals was a coincidence of the
-- halfway point: finished, it is 0.3494 before against 0.4032 after, i.e. refusals per
-- tick are **up 15%**. The conclusion that survives is the one about the denominator —
-- the refusal PERCENTAGE rose because commands fell — plus the real result, which is
-- +10% tasks completed per tick and -25% commands per dispatch. **The caveat at the
-- end of this section named the confound correctly and the numbers were quotable
-- anyway. A caveat has to be the headline or it is decoration.**
--
-- The CRN pair is `3fb415d8` (pre-fix, whole life, purged but archived) against
-- `5b37ee46` (same seed 777777, same scenario, same depot, same speed 8.0, with
-- 0367–0371 live). From `ottoq_run_archives`, which survives the purge:
--
--   3fb415d8, 1,245 ticks: commands_issued 10,110 · commands_refused 435 (4.30%)
--                          dispatches 168 · tasks_completed 485 · charge_sessions 177
--
--   5b37ee46, at tick 671: commands 1,637 · refused 234 (**14.29%**)
--                          dispatches 117 · SDRs 256
--
-- 4.30% → 14.29% reads like a threefold regression. Per tick it is not a change at
-- all:
--
--   refusals per tick     435/1245 = **0.349**   vs   234/671 = **0.349**
--   commands per tick    10110/1245 = 8.12       vs  1637/671 = **2.44**   (3.3x down)
--   dispatches per tick    168/1245 = 0.135      vs   117/671 = **0.174**   (29% up)
--   commands per dispatch      10110/168 = 60.2  vs    1637/117 = **14.0**  (4.3x down)
--
-- **The engine refuses at exactly the same rate per tick, commands 3.3x less, and
-- dispatches 29% more.** The refusal *percentage* rose because its denominator
-- collapsed -- the churn is gone, not the success. Sixty commands per dispatch was
-- the old cost of placing one vehicle; it is now fourteen.
--
-- HOLD THIS LOOSELY UNTIL THE RUN ENDS. `5b37ee46` was 51% through its 540
-- sim-minute ceiling at that reading, and arrival demand is not uniform across a
-- busy_day -- a partial run's per-tick rate against a full run's is a real
-- confound, not a rounding one. The identity of the refusals-per-tick figure to
-- three decimals is striking enough to be worth stating and weak enough to be worth
-- re-running at completion, which is what Q3 is for.

SELECT a.sim_run_id, a.tick_count, a.random_seed, a.scenario, a.speed_x,
       a.metrics->>'commands_issued'    AS commands_issued,
       a.metrics->>'commands_refused'   AS commands_refused,
       a.metrics->>'dispatches'         AS dispatches,
       a.metrics->>'tasks_completed'    AS tasks_completed,
       a.metrics->>'charge_sessions'    AS charge_sessions,
       round((a.metrics->>'commands_issued')::numeric  / NULLIF(a.tick_count,0), 3) AS cmds_per_tick,
       round((a.metrics->>'commands_refused')::numeric / NULLIF(a.tick_count,0), 3) AS refusals_per_tick,
       round((a.metrics->>'dispatches')::numeric       / NULLIF(a.tick_count,0), 3) AS dispatches_per_tick,
       round((a.metrics->>'commands_issued')::numeric
             / NULLIF((a.metrics->>'dispatches')::numeric,0), 1)                     AS cmds_per_dispatch,
       a.engine_hash, a.config_hash
  FROM public.ottoq_run_archives a
 WHERE a.depot_id = '11111111-1111-1111-1111-111111111111'
   AND a.random_seed = 777777
   AND a.scenario = 'busy_day'
 ORDER BY a.archived_at DESC LIMIT 6;

-- `engine_hash` will differ between the two rows, and that is correct rather than a
-- problem: all five of 0367–0371 are `forces_recert TRUE`, so the canon matrix is
-- supposed to notice. The pair is still CRN-valid — same seed, scenario, depot and
-- speed — because what changed is the decide path, which is the thing under test.
--
-- ══ 3. `stranded_recharges` COUNTS NEITHER RECHARGES NOR VEHICLES ════════════
--
-- This one IS a defect, small and in a reported number, which is the worst place
-- for a small one. `twin.ottoq_sim_advance_service_flow` emits
-- `twin.recharge_stranded` with payload `{"recharged": N, "floor": 80}` -- **239
-- events on this run, carrying 1,333 vehicle-requeues between them, up to 16 in a
-- single tick** -- and `public.ottoq_twin_events_window` surfaces it to any
-- reader as `reliability.stranded_recharges`, computed as
-- `count(*) WHERE event_type='twin.recharge_stranded'`.
--
-- WHAT THE CODE ACTUALLY DOES, read at the writer: **nothing is recharged.** The
-- loop sets `current_state = 'staged_awaiting_service'` and `svc_step =
-- 'need_charge'`, then places the vehicle in a temp stall chosen by
-- `ottoq_replan_stranded_undercharge`. No SoC is written. Its own comment says why:
-- *"DOCTRINE (Chase 2026-07-28): never bounce a vehicle to the gate"*, and the
-- split is correct -- OTTO-Q chooses, the twin executes the returned plan. **It is
-- a re-queue, not a rescue.**
--
-- So the reported field is wrong twice over:
--   (a) it says "recharges" for an action that grants no charge, and a reader would
--       take 239 as 239 vehicles topped up by the simulator -- which would make the
--       twin look like it was covering for the orchestrator. It is not.
--   (b) it counts EVENTS, not vehicles. Each event carries `recharged: N` for the N
--       vehicles that tick, so the true count is `sum(payload->>'recharged')`:
--       **1,333 against the 239 it reports, an under-count of 5.6x.** Two errors
--       compounding in opposite directions in one published field -- it names an
--       action that did not happen and then under-counts the action that did.
--
-- Not fixed here: renaming a field in a live report is a compatibility question for
-- whatever reads `ottoq_twin_events_window`, and `sum()` versus `count()` changes a
-- published number. The honest interim: **do not quote `stranded_recharges`.** Q4
-- gives both figures under names that say what they are.

SELECT count(*)                                            AS requeue_events,
       sum((e.payload->>'recharged')::numeric)             AS vehicles_requeued,
       min((e.payload->>'floor')::numeric)                 AS soc_floor,
       max((e.payload->>'recharged')::numeric)             AS max_in_one_tick
  FROM public.ottoq_events e
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
   AND e.event_type = 'twin.recharge_stranded';
