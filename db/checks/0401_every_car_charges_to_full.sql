-- 0401  **Every car charges to full: the first operator run under 0539, beside ad106e55.**
--
--       Written on 2026-09-27 around validation run c9d14225, the first operator run after 0539 (every car charges to
--       100%, and the boot reset works again, G266), 0540 (a dial win is recommended, never applied) and 0541 (the
--       challenger's Q1 is retired). Read-only. Started 23:11 UTC (6:11 PM CT) by one-shot cron 770:
--       `ottoq_start_busy_run(8, 1, 9055713631887914180)`, busy_day at 8x on ad106e55's seed.
--
--       **NOT A PAIRED COMPARISON, and the reason is worth keeping.** The seed matches, but the start clock does not:
--       ottoq_demo_start_clock takes the start minute from the seed only when one is passed. ad106e55 was started with
--       no seed (`ottoq_start_busy_run(8)`), so its minute was random (5:03 AM CT sim) and its seed was drawn after.
--       Passing that seed back gives 4:41 AM CT sim. The seed's draws match, but everything read off the clock (the
--       tariff windows, the night boundary, solar, the hour-of-day demand) starts 22 minutes apart, so the two days are
--       close, not identical. A difference that is small against that shift is not evidence of anything. Only a pair
--       started through the pair machinery is CRN.
--
--       **ad106e55's side cannot be re-queried.** Starting this run purged the prior runs' working rows, as designed
--       (`ottoq_purge_prior_runs`; the run-scoped tables are `class='engine'`). Only ad106e55's archive row survives
--       (1,057 ticks, 10:03-19:20 UTC sim). So §0 below is the READ taken at 22:50 UTC, before the purge, and ad106e55's
--       scorecard is 0400 §1's READ. Re-running either query for ad106e55 now returns nothing.

-- ══ §0 BEFORE: WHAT ad106e55's CHARGES WERE TOLD TO STOP AT ═════════════════════════════════════════════════════════
--
--   The StartTransaction target, per plug type. A session stops at the lower of its car's own target and the plug
--   ceiling (before 0539), so this is the target each charge was actually held to.

\echo '=== 0401 §0 — ad106e55, the sessions by the target they were started with ==='
SELECT st.stall_type::text AS plug, (m.payload->>'target_soc_pct')::numeric AS start_target, count(*) AS sessions,
       count(DISTINCT os.vehicle_id) AS cars
  FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
  LEFT JOIN public.ottoq_ocpp_messages m ON m.ocpp_session_id = os.id AND m.message_type = 'StartTransaction'
 WHERE os.sim_run_id = 'ad106e55-e775-4780-b853-418f504d4bcf'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 22:50 UTC, 5:50 PM CT): of 186 sessions, **2 were told 100%** (both fast, both started before 6 AM
--   under the night ceiling), **134 were told 90%** (66 fast: the day ceiling; 69 L2: the car's stamp, which the charge
--   plan had lowered to the fast plug's day ceiling), and **50 were told 85%** (14 fast, 36 L2). 85 was no ceiling in
--   force that afternoon: it is the treatment arm's day ceiling from experiment 08262943, which ran just before, stamped
--   on the cars and never reset because the boot draw's reset failed (G266). Those 50 charges stopped at 85% on a
--   leftover of an abandoned test.

-- ══ §1 THE RUN ═════════════════════════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0401 §1 — the run and its scorecard, beside ad106e55 (0400 §1''s READ) ==='
SELECT r.sim_run_id, r.run_by, r.status, r.random_seed, r.sim_clock_start, r.sim_clock_current, r.tick_count,
       r.started_at, r.ended_at
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = 'c9d14225-a7e6-4cf8-b4b7-7b652db9b283';
SELECT public.ottoq_kpi_five('c9d14225-a7e6-4cf8-b4b7-7b652db9b283');
SELECT public.ottoq_kpi_charge_wait('c9d14225-a7e6-4cf8-b4b7-7b652db9b283');
SELECT public.ottoq_kpi_supply_gap('c9d14225-a7e6-4cf8-b4b7-7b652db9b283') - 'by_hour_ct';
SELECT sim_run_id, metrics FROM public.ottoq_run_archives
 WHERE sim_run_id IN ('c9d14225-a7e6-4cf8-b4b7-7b652db9b283', 'ad106e55-e775-4780-b853-418f504d4bcf');
-- READ (2026-09-28 00:30 UTC, 7:30 PM CT): the governor stopped the run at 00:20:00 UTC (7:20 PM CT), `reached the 540
--   sim-minute ceiling`, at sim 1:53 PM CT: 552 sim-minutes and 1,110 ticks, 4:41 AM to 1:53 PM CT sim.
--   ad106e55 ran 5:03 AM to 2:20 PM CT sim (557 sim-minutes, 1,057 ticks). This run first, then ad106e55 (0400 §1):
--     KPI 1 asset hours 104.22 against 149.72 · KPI 2 turns per point 2.70 against 3.42
--     KPI 3 peak site kW 1,527.4 (demand 1,530.9) against 1,193.7 (demand 1,477.3)
--     KPI 4 touches per turn 1.359 against 0.965 · KPI 5 p95 time to service 287.7 min (p50 20.6) against 240.1 (p50
--       13.6) · returns unserved 16 against 19
--     charge wait: p50 56.8, p95 346.2, max 445.5 min; 128 of 162 visits owing a charge charged, 34 still waiting at the
--       end (p50 347.1 min so far, one for the whole run). ad106e55: p50 27.6, p95 300.2, max 358.4; 171 of 200; 29.
--     supply gap: 256.5 of 360.4 demand car-hours unmet (71.2%), 103.9 deployed, peak shortfall 44. ad106e55: 238.5 of
--       380.6 (62.7%), 142.2 deployed, 44.
--     archive: 94 dispatches against 172, 156 charge sessions against 187, 419 tasks completed against 566.
--   **This run cannot say what charging to 100% did to the day, for two reasons.** It is not paired with ad106e55 (the
--   header: the two days start 22 minutes apart). And **G267 kept 8 to 10 cars out of it (§2(c)), 83.5 car-hours of
--   cars parked, uncharged and unsent.** On ad106e55 the same boot cars owed no charge and went out early. The whole
--   deployed-hours difference (38.3 car-hours) is smaller than what G267 parked, so no part of it can be assigned to
--   charging to 100% from this run. What the run does show is §2: every charge aimed at 100% and reached it unless its
--   charger faulted. The clean read is the rerun after 0542, on the same seed.

-- ══ §2 AFTER: EVERY CHARGE AIMS AT 100%, AND ENDS SHORT ONLY ON A FAULT ═══════════════════════════════════════════════

\echo '=== 0401 §2(a) — the run''s sessions by start target ==='
SELECT st.stall_type::text AS plug, (m.payload->>'target_soc_pct')::numeric AS start_target, count(*) AS sessions,
       count(DISTINCT os.vehicle_id) AS cars
  FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
  LEFT JOIN public.ottoq_ocpp_messages m ON m.ocpp_session_id = os.id AND m.message_type = 'StartTransaction'
 WHERE os.sim_run_id = 'c9d14225-a7e6-4cf8-b4b7-7b652db9b283'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-28 00:28 UTC): **all 156 sessions were started at 100%.** 60 fast (45 cars) and 96 L2 (71 cars). No
--   other target appears. ad106e55's 186 were 2 at 100, 134 at 90 and 50 at 85 (§0).

\echo '=== 0401 §2(b) — every ended session that stopped below its start target, by stop reason ==='
SELECT st.stall_type::text AS plug, os.stopped_reason, count(*) AS sessions,
       round(avg((m.payload->>'target_soc_pct')::numeric - COALESCE(os.soc_end, 0)), 1) AS mean_short_by
  FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
  LEFT JOIN public.ottoq_ocpp_messages m ON m.ocpp_session_id = os.id AND m.message_type = 'StartTransaction'
 WHERE os.sim_run_id = 'c9d14225-a7e6-4cf8-b4b7-7b652db9b283' AND os.status <> 'active'
   AND os.soc_end < (m.payload->>'target_soc_pct')::numeric - 0.5
 GROUP BY 1, 2 ORDER BY 1, 3 DESC;
\echo '=== 0401 §2(b2) — the completed sessions: how far and how long ==='
SELECT st.stall_type::text AS plug, count(*) AS completed, round(avg(os.soc_start), 1) AS mean_soc_start,
       round(avg(os.soc_end), 1) AS mean_soc_end,
       round(avg(EXTRACT(EPOCH FROM (os.ended_at - os.started_at)) / 60.0), 1) AS mean_min
  FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
 WHERE os.sim_run_id = 'c9d14225-a7e6-4cf8-b4b7-7b652db9b283' AND os.status = 'completed'
 GROUP BY 1 ORDER BY 1;
-- READ (2026-09-28 00:28 UTC): **the only charges that ended short ended on a charger fault: 6 sessions.** Four were
--   fast (communication dropout 1, connector cable 1, station hardware 2; 20 to 32 points short) and two L2 (connector
--   cable; 26 points short). **All 112 completed sessions ended at 100.0%.** 46 fast charges ran from a mean 37.8% in
--   92.6 minutes (p50 95.6), and 66 L2 charges from 58.3% in 173.9 minutes (p50 175.6). 38 more (10 fast, 28 L2)
--   were still charging at 1:53 PM CT sim, when the run's teardown closed them as `sim_reset`. That is the run
--   ending, not a charge stopped short. Rule 9 held on every charge.

\echo '=== 0401 §2(c) — cars parked ready while they still owe a must-do charge (G267) ==='
--   A car in staged_for_departure is past every charging path, and neither dispatcher takes a car with open must-do
--   work. So a car that arrives there still owing its charge waits, uncharged and unsent. Read from the signed state
--   stream, because the run's teardown resets every car's state (a query on vehicles after the run finds nothing).
WITH st AS (
  SELECT e.entity_id AS vehicle_id, e.sim_clock_at AS entered,
         e.payload->'diff'->'current_state'->>'to' AS st_to,
         lead(e.sim_clock_at) OVER (PARTITION BY e.entity_id ORDER BY e.sim_clock_at) AS left_at,
         lead(e.payload->'diff'->'current_state'->>'to') OVER (PARTITION BY e.entity_id ORDER BY e.sim_clock_at) AS next_state
    FROM public.ottoq_events e
   WHERE e.sim_run_id = 'c9d14225-a7e6-4cf8-b4b7-7b652db9b283' AND e.event_type = 'vehicle.state_changed'
     AND e.payload->'diff' ? 'current_state'
)
SELECT COALESCE(v.display_name, v.id::text) AS car,
       to_char(s.entered AT TIME ZONE 'America/Chicago', 'HH24:MI') AS parked_ct,
       to_char(s.left_at AT TIME ZONE 'America/Chicago', 'HH24:MI') AS left_ct, s.next_state,
       round(EXTRACT(EPOCH FROM (COALESCE(s.left_at, r.sim_clock_current) - s.entered)) / 60.0) AS parked_min
  FROM st s
  JOIN public.vehicles v ON v.id = s.vehicle_id
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = 'c9d14225-a7e6-4cf8-b4b7-7b652db9b283'
 WHERE s.st_to = 'staged_for_departure' AND COALESCE(s.left_at, r.sim_clock_current) > s.entered
   AND EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
                WHERE vn.vehicle_id = s.vehicle_id AND vn.sim_run_id = r.sim_run_id AND a->>'svc' = 'charge'
                  AND COALESCE((a->>'must_do')::boolean, false) AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled'))
   AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions os
                    WHERE os.vehicle_id = s.vehicle_id AND os.sim_run_id = r.sim_run_id
                      AND os.started_at BETWEEN s.entered AND COALESCE(s.left_at, 'infinity'))
 ORDER BY s.entered, 1;
-- READ (2026-09-27 23:23 UTC, mid-run at 6:22 AM CT sim, from vehicles): 10 cars at 88-97%, each with a charge to 100
--   pending. All 10 were boot-placed `charge_complete_holding` and released by the wash triage (Waymo-AV-032:
--   offline to charge_complete_holding at 4:41 AM CT sim, then staged_for_departure/ready at 4:49).
-- READ (2026-09-28 00:31 UTC, end of run, from the state stream): **8 cars sat parked from 4:49 AM to the teardown at
--   1:53 PM CT sim, 544 minutes each** (Tesla-AV-046, -055, -057; Waymo-AV-012, -028, -032, -033; Zoox-AV-096).
--   Waymo-AV-004 sat 492 minutes, from 5:40 AM. Waymo-AV-018 sat 164 minutes, until 7:32 AM, when a newly required
--   deep clean sent it back to the service queue and the readiness gate then routed its charge. It did not leave the
--   depot either. **83.5 car-hours in all, none charged and none sent out.** Three of the ten were immediate-dispatch
--   visits. No charging session touched any of them while they were parked.

-- ══ §3 G266: THE BOOT RESET WORKED ═══════════════════════════════════════════════════════════════════════════════════

\echo '=== 0401 §3 — every twin car carries its own target ==='
SELECT count(*) AS twin_cars, count(*) FILTER (WHERE v.target_soc = 100) AS target_100
  FROM public.vehicles v
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous';
-- READ (2026-09-28 00:29 UTC): 116 of 116 twin cars carry 100. With §2(a) (every StartTransaction at 100, where
--   ad106e55 had 50 sessions at a leftover 85), this shows the boot reset now succeeds (G266).

-- ══ §4 THE CHALLENGER AND THE LEARNER ═════════════════════════════════════════════════════════════════════════════════

\echo '=== 0401 §4 — the challenger''s board for the run, and the promotion switch ==='
SELECT q->>'tag' AS tag, q->'run' AS this_run
  FROM jsonb_array_elements(public.ottoq_challenger_board('c9d14225-a7e6-4cf8-b4b7-7b652db9b283')->'questions') q;
SELECT public.ottoq_policy_get(NULL, 'dial_promotion_enabled', -1) AS dial_promotion_enabled;
-- READ (2026-09-28 00:30 UTC): **Q1 opened no episode** (0541: retired; its lifetime record, 42 graded on ad106e55,
--   stays readable). Q2 opened none (2 transient sightings). Q3 opened 6, 3 confirmed and 3 inconclusive: a fault
--   while cars waited on NASH-DCFC-STALL-03 for at least 256 minutes, on NASH-L2-STALL-20 for at least 136, and on
--   NASH-DCFC-STALL-04 for at least 64. That is charger capacity lost to faults, which rule 9 names as a capacity
--   answer. `dial_promotion_enabled` reads 0 (0540).
