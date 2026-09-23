-- 0327  **The 08:00 UTC check-in asked whether the realised fault rate matches λ = 0.00088. It does not
--       yet have an answer, and the reason changed while I was measuring: the run is 10.8% complete, not
--       complete, AND the hazard it has been running has been 3.80x too high for a unit reason in
--       `0413` — my own fix. `db/migrations/0420` corrects that.**
--
--       Answering the check-in step by step, including the two steps whose premises turned out wrong.
--       Measured 2026-09-22 08:00–08:10 UTC (03:00–03:10 CT) on run
--       `61cedc05-fa8a-44f0-8a31-5cd6404404ff` (busy_day, seed 700001, twin depot).
--
-- ══ §1 STEP 1 — THE RUN IS NOT COMPLETE, AND THE ETA IN THE CHECK-IN WAS WRONG ══
--
-- The check-in expected *"~1,104 ticks"* to be a full run. Measured:
--
--     status                                   running
--     tick_count                               1,179
--     sim_clock_start / _current / _end         09:37:00 / 12:11:01 / 2026-09-23 09:37:00
--     sim hours elapsed / target                2.60 of 24.0   -> **10.8% complete**
--     real minutes elapsed                      152.7
--
-- **The run is bounded by `sim_clock_end`, not by a tick count** — 24 sim-hours — and in `live` playback
-- at `speed_x` 1.0 the sim clock advances one second per real second. Tick count was the wrong unit to
-- predict completion in: at 7.9 sim-seconds per tick it takes ~10,900 ticks to cover a sim-day, not 1,104.
--
-- **CORRECTION, ten minutes after writing the paragraph above: it will NOT reach 24 sim-hours, because
-- the run governor stops it at nine.** `ottoq_run_governor_auto_stop` (cron 17, every 2 minutes) stops any
-- `running` run whose sim clock has travelled `run_governor_max_sim_minutes`, and this run is
-- `run_by='operator_demo'` — not one of the two exempt values (`production_live`, `cert_harness`). The
-- dial resolves to **540** sim-minutes from the **global** row (`00000000-…`, set 2026-08-13); the catalog
-- default is 139 and the only depot override, 1,440, belongs to the benchmark depot `22222222-…`, not the
-- twin. So `sim_clock_end` is not the binding limit — **the governor is, at 9 sim-hours.** At 168.7
-- sim-minutes when measured, the run has ~371 sim-minutes left, which in live 1× is ~6.2 real hours, so
-- it self-terminates around **14:25 UTC (09:25 CT)** rather than tomorrow morning. §7 is the consequence,
-- and it is the one that changes what to do next.
--
-- ══ §2 STEP 2 — THE CENSORING `0324` HIT IS GONE. THIS IS THE GOOD NEWS ════════
--
-- `0324` §1 could not check λ's value partly because the exposure denominator was censored: at tick 157
-- the state-timeline reconstruction saw **38%** of the true vehicle-hours, because a vehicle that has not
-- yet changed state contributes no segment. Measured now, over the whole run with `sim_clock_at`:
--
--     total vehicle-hours reconstructed        301.2
--     116 vehicles x 2.597 sim-hours           301.2
--     => share of the truth seen             **100.0%**
--     eligible vehicle-hours                   229.1   (76% of total)
--     vehicles with at least one state change  116 of 116
--
-- **The reconstruction is now exact.** Every vehicle has moved at least once, so the segment method has
-- no blind vehicles left, and the sanity check the check-in asked for passes with nothing to spare. The
-- denominator is trustworthy at this run length; it was not at tick 157.
--
-- ══ §3 STEP 3 — AND THE VALUE CHECK IS STILL UNAVAILABLE, FOR THE ORIGINAL REASON ═
--
--     observed vehicles condemned (`tow_requested`)          0
--     eligible vehicle-hours                             229.1
--     expected at the INTENDED λ 0.00088                 0.202
--     expected at the EFFECTIVE λ (0.00088 x 3.80)       0.766
--     95% upper bound on the rate from 0 events          3 / 229.1 = 0.0131 / eligible vehicle-hour
--
-- **Zero faults excludes neither hypothesis.** P(0 | 0.202) = 82%, P(0 | 0.766) = 46%, and the
-- rule-of-three upper bound sits 15x above the intended λ and 4x above the effective one. `0324` §1 said
-- this needs roughly **1,700 eligible vehicle-hours**; we have **229**, or 13% of the way. **The fix is
-- still validated as a correction and the calibration is still not validated as a value** — exactly the
-- distinction `0324` drew, unchanged, on a denominator that is now sound rather than censored.
--
-- ══ §4 STEP 4 — DO NOT RE-TUNE, AND THE REASON IS STRONGER THAN THE CHECK-IN KNEW ═
--
-- The check-in anticipated that a materially-off realised rate should be fixed by re-deriving the
-- denominator from a clean run rather than tuning λ. **There is now a prior reason: the hazard the engine
-- has actually been applying is not the one `0413` intended.**
--
-- `0413` re-denominated the hazard per eligible vehicle-hour and then converted it with
-- `ottoq_sim_runs.tick_interval_seconds`. That column is the **real-time metronome cadence.** Measured
-- from `ottoq_tick_clock_log.sim_advance_s`, which records the sim-time advance per tick:
--
--     ticks logged                     1,179
--     mean sim_advance_s                7.90    (min 6.2, max 99.6)
--     what 0413 assumed                30.00
--     => overstated in `live` mode      **3.80x**
--     a `fixed`-mode tick advances      tick_interval_seconds x time_scale = **1,800 s (30 min)**
--     => understated in `fixed` mode    **60x**
--
-- So every fault number this branch has produced was generated under a hazard 3.80x too high, and every
-- **certification** run — `fixed` mode, which `0258` mandates for `run_by IN ('cert_harness',
-- 'benchmark')` — ran one 60x too low. **Calibrating λ against observed faults now would fit λ to
-- compensate for a unit bug.** Fixed in `db/migrations/0420` (applied `20260922080856`), which reads
-- `payload->>'tick_minutes_actual'` — a value the world advancer already publishes every tick under a
-- comment saying it exists *"so every per-tick RATE cap downstream scales with the real tick size."*
--
-- **AND IT COSTS THIS RUN AS A λ MEASUREMENT, which is worth stating plainly.** `0420` landed at tick
-- ~1,180 of a run that will reach ~10,900. Its first 1,180 ticks ran at the overstated hazard and the
-- rest will run at the corrected one, so `61cedc05` is now **hazard-mixed and cannot serve the value
-- check at all** — not merely "not yet". A fresh run is required. That is not a loss: at 229 of 1,700
-- eligible vehicle-hours it could not have answered today regardless, and it has already paid for
-- itself by exposing the defect.
--
-- ══ §5 STEP 5 — THE CENSUS FOUND A TRANSITION `0412` MISSED, AND SM.001 CAUGHT IT
--       INDEPENDENTLY ═════════════════════════════════════════════════════════
--
-- The check-in expected the end-of-run reset group to have occurred. It has not — the run has not ended —
-- so `0412` group (b) is still absent for good reasons rather than fixed ones. What did appear is new:
--
--     from_state        to_state              occurrences   bucket
--     ---------------   -------------------   -----------   ----------------------------------------
--     offline           charge_complete_holding        15   0412 group (c): boot-state, deliberately left
--     arrived_at_gate   in_service_bay                  1   **OPERATIONAL GAP**
--
-- **`0412`'s V3 asserted the operational bucket was EMPTY, and `0324` §2 confirmed it empty at tick 125.
-- At tick ~1,179 it holds one row.** That is `0412`'s own recorded lesson — *"a one-run census is a lower
-- bound"* — demonstrated a second time, now against horizon rather than against run count: the same
-- census on the same runs finds more as the world runs longer. `0412` declared `arrived_at_gate ->
-- in_wash_bay` on exactly this reasoning (the table admitted the *exit* from a bay and not the *entry*)
-- and stopped one bay type short.
--
-- **AND SM.001 FOUND IT WITHOUT BEING TOLD, WHICH IS THE RESULT THAT MATTERS.** Measured on this run:
--
--     SM.001 evaluations   949
--     passed               948
--     failed                 1  <- `invalid transition for vehicle: arrived_at_gate → in_service_bay`,
--                                  severity `critical`, `enforcement_taken='shadow_fail'`, 06:41:43 UTC
--     from_state='offline'   0
--
-- **The events census and the shadow rule agree on exactly one transition, derived independently.** This
-- is the complement of `0324` §3: there, SM.001 read green over fifteen undeclared transitions because
-- the seeding path never reaches its probe, and the lesson was that a passing rule is evidence only over
-- the population its probe sees. Here the transition IS inside that population, and the rule caught it on
-- the first occurrence. **Same rule, same run: blind to the seeder, exact on the engine.** Coverage and
-- cleanliness are different properties and this run demonstrates both halves at once.
--
-- (`from_state='offline'` is still 0 against 15 such events, so `0324` §3's finding holds unchanged at
-- ten times the horizon, and `0412` §4's promotion order still must be rewritten against the events
-- census rather than against SM.001's log.)
--
-- ══ §6 WHAT I AM DELIBERATELY NOT DECLARING ═══════════════════════════════════
--
-- **I am not adding `arrived_at_gate -> in_service_bay` to `ottoq_state_transitions`, on one occurrence.**
-- `0412` declined to widen the gate for `emergency_staged -> staged_awaiting_service` precisely because an
-- engine doing what the table forbids can be an **engine** defect rather than a declaration gap, and
-- widening it would erase the finding instead of fixing it. The same question applies here and I cannot
-- answer it from the data: whether a vehicle may go from the gate **straight into a service bay**, skipping
-- staging, is the fixture's intent. The wash analogue was declared on a census of many occurrences; this
-- is one. **It is in `shadow`, so nothing is blocked either way, and the evidence is durable in
-- `ottoq_rule_evaluations` and above.** It needs Chase's intent, not my inference.
--
-- ══ §7 NO DEMO RUN CAN EVER ANSWER THE λ QUESTION, AND THE RECERT SWEEP CAN ════
--
-- Putting §1's correction together with §3's requirement settles the plan, and the answer is structural
-- rather than a matter of waiting longer:
--
--     the governor caps a demo run at                     540 sim-minutes = 9.0 sim-hours
--     twin depot vehicles                                 116
--     eligible share measured on this run                  76%
--     => eligible vehicle-hours a FULL demo run yields   ~793
--     eligible vehicle-hours the value check needs      ~1,700   (0324 §1)
--
-- **A governor-capped demo run tops out at less than half of what the measurement needs. Waiting for this
-- run to finish, or starting another one, cannot answer the question — not slowly, but never.**
--
-- **What can: a certification pair.** `run_by='cert_harness'` is one of the two values the governor
-- exempts, and a cert pair runs `fixed` playback where a tick advances `tick_interval_seconds *
-- time_scale` = **30 sim-minutes**. So a 48-tick canon covers **24 sim-hours** — about **2,100 eligible
-- vehicle-hours in one arm**, above the requirement, in roughly 24 real minutes rather than 24 real
-- hours. `ottoq_determinism_canon` holds 48-tick columns.
--
-- **And it is already scheduled.** Cron job 746 runs every minute, takes an advisory lock, **returns
-- immediately if any run is `running` or `paused`**, and otherwise picks the first canon where
-- `enabled AND NOT satisfies_floor`. Measured now: **9 of 9 canons are enabled and failing their floor**,
-- which is what `0420`'s `forces_recert=TRUE` is for. So the recert sweep `0420` owes (G131) and the λ
-- value measurement are **the same runs**, and the only thing standing between them and starting is the
-- demo run holding the engine until ~14:25 UTC.
--
-- **So the correct action is to do nothing to the live run and let the governor have it.** Not stopping it
-- by hand is deliberate: it is `run_by='operator_demo'`, its remaining 6 hours cost nothing that the
-- recert sweep needs, and stopping a run a person may be watching is not a call to make unattended when
-- the governor will make it anyway within the hour.
--
-- The honest status, in one line: *the denominator is finally sound, no demo run can ever reach the
-- ~1,700 eligible vehicle-hours the value check needs, the governor-exempt 48-tick cert pairs can and are
-- already queued behind the live run, and the shadow shield caught an undeclared transition on its first
-- occurrence.*

\echo '=== 0327 §1 correction + §7 — the governor caps this run at 9 sim-hours, not 24 ==='
SELECT r.run_by,
       (COALESCE(r.run_by,'') IN ('production_live','cert_harness')) AS governor_exempt,
       round(EXTRACT(epoch FROM (r.sim_clock_current - r.sim_clock_start))/60.0, 1) AS sim_minutes_done,
       public.ottoq_policy_get(r.sim_run_id,'run_governor_max_sim_minutes',139) AS governor_ceiling_min,
       round(EXTRACT(epoch FROM (r.sim_clock_end - r.sim_clock_start))/60.0, 0) AS sim_clock_end_min,
       round((116 * public.ottoq_policy_get(r.sim_run_id,'run_governor_max_sim_minutes',139)/60.0
              * 0.76)::numeric, 0) AS eligible_vh_a_full_demo_run_yields,
       1700 AS eligible_vh_needed
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id='61cedc05-fa8a-44f0-8a31-5cd6404404ff';
-- 540 from the GLOBAL row; the catalog default is 139 and the only depot override (1,440) belongs to the
-- benchmark depot, not the twin. ~793 eligible vehicle-hours against ~1,700 needed: a demo run cannot
-- answer the lambda question at all, however long it runs.

\echo '=== 0327 §7 — the recert sweep IS the measurement vehicle, and it is already queued ==='
SELECT count(*) AS canons_enabled,
       count(*) FILTER (WHERE NOT satisfies_floor) AS awaiting_recert,
       count(*) FILTER (WHERE NOT satisfies_floor AND ticks >= 48) AS awaiting_at_48_ticks,
       48 * 30 AS a_48_tick_fixed_run_covers_sim_minutes,
       round((116 * (48*30)/60.0 * 0.76)::numeric, 0) AS eligible_vh_one_48_tick_arm_yields
  FROM public.ottoq_determinism_canon WHERE enabled;
-- Cert pairs are governor-EXEMPT and run fixed playback (30 sim-minutes per tick), so 48 ticks is a full
-- sim-day: ~2,100 eligible vehicle-hours per arm, above the requirement. Cron 746 starts them the moment
-- no run is 'running' -- which is why the right action is to leave the live run alone.

\echo '=== 0327 §1 — step 1: the run is 10.8% complete, and tick count was the wrong unit ==='
SELECT status, tick_count,
       sim_clock_start, sim_clock_current, sim_clock_end,
       round(EXTRACT(epoch FROM (sim_clock_current - sim_clock_start))/3600.0, 3) AS sim_hours_done,
       round(EXTRACT(epoch FROM (sim_clock_end   - sim_clock_start))/3600.0, 1)   AS sim_hours_target,
       round(100.0 * EXTRACT(epoch FROM (sim_clock_current - sim_clock_start))
                   / NULLIF(EXTRACT(epoch FROM (sim_clock_end - sim_clock_start)),0), 1) AS pct_complete,
       payload->>'playback_mode' AS playback_mode, payload->>'speed_x' AS speed_x
  FROM public.ottoq_sim_runs WHERE sim_run_id='61cedc05-fa8a-44f0-8a31-5cd6404404ff';
-- Bounded by sim_clock_end (24 sim-hours), not by ticks. In live mode at 1x that is ~24 REAL hours.

\echo '=== 0327 §2+§3 — the denominator is uncensored now, and still 13% of what a value check needs ==='
WITH r AS (
  SELECT sim_run_id, sim_clock_start AS t0, sim_clock_current AS t1,
         EXTRACT(epoch FROM (sim_clock_current - sim_clock_start))/3600.0 AS sim_hours
    FROM public.ottoq_sim_runs WHERE sim_run_id='61cedc05-fa8a-44f0-8a31-5cd6404404ff'
), ev AS (
  SELECT e.entity_id AS vid, e.sim_clock_at AS t,
         e.payload->'diff'->'current_state'->>'from' AS sf,
         e.payload->'diff'->'current_state'->>'to'   AS st
    FROM public.ottoq_events e, r
   WHERE e.sim_run_id=r.sim_run_id AND e.event_type='vehicle.state_changed'
     AND e.payload->'diff' ? 'current_state'
), seg AS (
  SELECT vid, sf AS st, (SELECT t0 FROM r) AS a, t AS b
    FROM (SELECT vid,t,sf,row_number() OVER (PARTITION BY vid ORDER BY t) rn FROM ev) q WHERE rn=1
  UNION ALL
  SELECT vid, st, t, COALESCE(lead(t) OVER (PARTITION BY vid ORDER BY t), (SELECT t1 FROM r)) FROM ev
), expo AS (
  SELECT sum(EXTRACT(epoch FROM (b-a)))/3600.0 AS total_vh,
         sum(EXTRACT(epoch FROM (b-a))) FILTER (WHERE st IN
           ('charging_dcfc','charging_l2','in_wash_bay','in_detail_bay','in_service_bay',
            'charge_complete_holding','staged_awaiting_service'))/3600.0 AS eligible_vh
    FROM seg WHERE b>a
)
SELECT round((SELECT total_vh FROM expo)::numeric,1)                              AS total_vh_measured,
       round((116*(SELECT sim_hours FROM r))::numeric,1)                          AS total_vh_if_uncensored,
       round((100.0*(SELECT total_vh FROM expo)/(116*(SELECT sim_hours FROM r)))::numeric,1) AS pct_of_truth,
       round((SELECT eligible_vh FROM expo)::numeric,1)                           AS eligible_vh,
       round((0.00088*(SELECT eligible_vh FROM expo))::numeric,3)                 AS expected_at_intended_lambda,
       round((0.00088*3.80*(SELECT eligible_vh FROM expo))::numeric,3)            AS expected_at_effective_lambda,
       (SELECT count(DISTINCT vid) FROM ev WHERE st='tow_requested')              AS observed_condemned,
       round((3.0/NULLIF((SELECT eligible_vh FROM expo),0))::numeric,5)           AS rule_of_three_upper_bound,
       1700                                                                       AS eligible_vh_needed;
-- 100.0% of the truth (0324 saw 38%), 229 of ~1,700 needed, 0 observed. Neither lambda excluded.

\echo '=== 0327 §4 — the tick-size defect that 0420 fixes, from the log that records it per tick ==='
SELECT playback_mode, speed_x, count(*) AS ticks,
       round(avg(sim_advance_s)::numeric,2) AS mean_sim_advance_s,
       min(sim_advance_s) AS min_s, max(sim_advance_s) AS max_s,
       30 AS what_0413_assumed_s,
       round((30.0/NULLIF(avg(sim_advance_s),0))::numeric,2) AS live_overstatement,
       (SELECT round((r.tick_interval_seconds::numeric * r.time_scale)::numeric,0)
          FROM public.ottoq_sim_runs r
         WHERE r.sim_run_id='61cedc05-fa8a-44f0-8a31-5cd6404404ff')  AS fixed_mode_advance_s,
       (SELECT round(((r.tick_interval_seconds::numeric * r.time_scale)/30.0)::numeric,0)
          FROM public.ottoq_sim_runs r
         WHERE r.sim_run_id='61cedc05-fa8a-44f0-8a31-5cd6404404ff')  AS fixed_mode_understatement
  FROM public.ottoq_tick_clock_log
 WHERE sim_run_id='61cedc05-fa8a-44f0-8a31-5cd6404404ff'
 GROUP BY 1,2;
-- 7.90 actual vs 30 assumed = 3.80x too high in live; 1,800 vs 30 = 60x too low in fixed, which is the
-- mode every certification uses. Wrong in both directions, so no single run's outcomes could reveal it.

\echo '=== 0327 §5 — the transition 0412 missed, in the bucket its V3 asserted empty ==='
WITH observed AS (
  SELECT payload->'diff'->'current_state'->>'from' AS f,
         payload->'diff'->'current_state'->>'to'   AS t, count(*) AS n
    FROM public.ottoq_events
   WHERE sim_run_id='61cedc05-fa8a-44f0-8a31-5cd6404404ff'
     AND event_type='vehicle.state_changed' AND payload->'diff' ? 'current_state'
     AND payload->'diff'->'current_state'->>'from' IS DISTINCT FROM payload->'diff'->'current_state'->>'to'
   GROUP BY 1,2
)
SELECT o.f AS from_state, o.t AS to_state, o.n AS occurrences,
       CASE WHEN o.f='offline' THEN '0412 group (c): boot-state, deliberately left'
            WHEN o.t='offline' THEN '0412 group (b): end-of-run reset'
            WHEN o.f IN ('tow_requested','emergency_staged') THEN '0412 group (a): return-to-service'
            ELSE 'OPERATIONAL GAP -- 0412 should have closed this' END AS bucket
  FROM observed o
  LEFT JOIN public.ottoq_state_transitions s
    ON s.entity_kind='vehicle' AND s.from_state=o.f AND s.to_state=o.t AND s.status='active'
 WHERE s.transition_id IS NULL
 ORDER BY o.n DESC;

\echo '=== 0327 §5 — and SM.001 caught it on its first occurrence, independently of the census ==='
SELECT count(*) AS evaluations,
       count(*) FILTER (WHERE passed) AS passed,
       count(*) FILTER (WHERE NOT passed) AS failed,
       count(*) FILTER (WHERE context->>'from_state'='offline') AS from_offline,
       max(CASE WHEN NOT passed THEN left(reason,80) END) AS the_failure,
       max(CASE WHEN NOT passed THEN enforcement_taken END) AS enforcement_taken
  FROM public.ottoq_rule_evaluations
 WHERE rule_code='SM.001.vehicle_transition_validity'
   AND evaluated_at > (SELECT started_at FROM public.ottoq_sim_runs
                        WHERE sim_run_id='61cedc05-fa8a-44f0-8a31-5cd6404404ff');
-- 949 / 948 / 1, and from_offline still 0 against 15 such events. The rule is exact on the engine and
-- blind to the seeder, in the same run -- 0324 §3's lesson and its complement together.
