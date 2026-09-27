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
-- READ: pending

-- ══ §2 AFTER: EVERY CHARGE AIMS AT 100%, AND ENDS SHORT ONLY ON A FAULT ═══════════════════════════════════════════════

\echo '=== 0401 §2(a) — the run''s sessions by start target ==='
SELECT st.stall_type::text AS plug, (m.payload->>'target_soc_pct')::numeric AS start_target, count(*) AS sessions,
       count(DISTINCT os.vehicle_id) AS cars
  FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
  LEFT JOIN public.ottoq_ocpp_messages m ON m.ocpp_session_id = os.id AND m.message_type = 'StartTransaction'
 WHERE os.sim_run_id = 'c9d14225-a7e6-4cf8-b4b7-7b652db9b283'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ: pending

\echo '=== 0401 §2(b) — every ended session that stopped below its start target, by stop reason ==='
SELECT st.stall_type::text AS plug, os.stopped_reason, count(*) AS sessions,
       round(avg((m.payload->>'target_soc_pct')::numeric - COALESCE(os.soc_end, 0)), 1) AS mean_short_by
  FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
  LEFT JOIN public.ottoq_ocpp_messages m ON m.ocpp_session_id = os.id AND m.message_type = 'StartTransaction'
 WHERE os.sim_run_id = 'c9d14225-a7e6-4cf8-b4b7-7b652db9b283' AND os.status <> 'active'
   AND os.soc_end < (m.payload->>'target_soc_pct')::numeric - 0.5
 GROUP BY 1, 2 ORDER BY 1, 3 DESC;
-- READ: pending

\echo '=== 0401 §2(c) — cars parked ready while they still owe a must-do charge (G267) ==='
--   A car in staged_for_departure is past every charging path, and neither dispatcher takes a car with open must-do
--   work. So a car that arrives there still owing its charge waits, uncharged and unsent, until the run ends.
SELECT COALESCE(v.display_name, v.id::text) AS car, v.current_soc, v.last_state_change, vn.urgency,
       (SELECT a->>'target_soc' FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge') AS charge_target,
       round(EXTRACT(EPOCH FROM (r.sim_clock_current - v.last_state_change)) / 60.0) AS parked_min
  FROM public.ottoq_visit_needs vn
  JOIN public.vehicles v ON v.id = vn.vehicle_id
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = vn.sim_run_id
 WHERE vn.sim_run_id = 'c9d14225-a7e6-4cf8-b4b7-7b652db9b283' AND vn.status IN ('open', 'in_progress')
   AND v.current_state = 'staged_for_departure'
   AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                WHERE a->>'svc' = 'charge' AND COALESCE((a->>'must_do')::boolean, false)
                  AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled'))
 ORDER BY v.last_state_change;
-- READ (2026-09-27 23:23 UTC, mid-run at 6:22 AM CT sim): 10 cars at 88-97%, each with a charge to 100 pending, 9 of
--   them parked since 09:49-09:52 UTC sim (the run's first ten minutes) and one since 10:40. All 10 were boot-placed
--   `charge_complete_holding` and released by the wash triage (Waymo-AV-032: offline to charge_complete_holding at
--   09:41:00, then staged_for_departure/ready at 09:49:00). End-of-run READ: pending.

-- ══ §3 G266: THE BOOT RESET WORKED ═══════════════════════════════════════════════════════════════════════════════════
-- READ: pending

-- ══ §4 THE CHALLENGER AND THE LEARNER ═════════════════════════════════════════════════════════════════════════════════
-- READ: pending
