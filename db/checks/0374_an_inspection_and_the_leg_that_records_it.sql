-- 0374  **G232: the interior inspection ran on time, and its itinerary leg was closed by another task (0504).**
--
--       0372 §5 read the late inspections on validation run `b0fdc92b` as a plan that dates them inside a charge that
--       starts late. Matched to the atoms that performed them, the inspections were on plan; what was late was the leg
--       that records them, because `public.ottoq_close_atom_leg` never found an inspection's leg and the car's readiness
--       check closed it instead. Read on `b0fdc92b` after its stop (sim clock 16:44:49 UTC) and before the next run
--       purges it, 2026-09-26 23:45-00:00 UTC. Takes the run as a psql variable:
--
--           \set run '<sim_run_id>'

-- ══ §1 WHAT CLOSED EACH INTERIOR INSPECTION LEG ═════════════════════════════════════════════════════════════════
--
--   Three writers can close an `inspect` leg: `ottoq_close_atom_leg` when an atom finishes, the inspection lane
--   (`ottoq.ottoq_release_expired_bookings` when the lane's booking ends, and the seam's own sweep), and nothing else.
--   A leg closed by the readiness check carries that check's `done_at` as its `actual_end_sim`.

\echo '=== 0374 §1 — done interior inspection legs, by what closed them ==='
WITH r AS (
  SELECT vn.vehicle_id, (a->>'done_at')::timestamptz AS r_done
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
   WHERE vn.sim_run_id = :'run' AND a->>'svc' = 'readiness_check' AND a->>'status' = 'done'),
legs AS (
  SELECT l.leg_id,
         EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b WHERE b.leg_id = l.leg_id AND b.purpose = 'inspect') AS lane_booked,
         EXISTS (SELECT 1 FROM r WHERE r.vehicle_id = l.vehicle_id AND r.r_done = l.actual_end_sim) AS by_readiness
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = :'run' AND l.leg_type = 'inspect'
     AND l.duration_basis->>'atom' = 'interior_inspection' AND l.status = 'done')
SELECT lane_booked, by_readiness, count(*) AS legs FROM legs GROUP BY 1, 2 ORDER BY 1, 2;
-- READ on b0fdc92b: 91 done. No lane booking, closed by the readiness check: 25. Lane booking, closed by the lane: 65.
--   Lane booking, closed by the readiness check first: 1. Closed by the inspection itself: 0.

\echo '=== 0374 §1(b) — the same legs against the atom that performed the inspection ==='
--   Atoms are matched to legs by car and time, not by visit id: continuous re-derivation supersedes a visit and
--   writes a new one, while the itinerary keeps the first visit's id (every lane-booked leg's visit is `superseded`).
WITH legs AS (
  SELECT l.leg_id, l.vehicle_id, l.planned_start_sim, l.actual_start_sim, l.actual_end_sim,
         EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b WHERE b.leg_id = l.leg_id AND b.purpose = 'inspect') AS lane_booked
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = :'run' AND l.leg_type = 'inspect'
     AND l.duration_basis->>'atom' = 'interior_inspection' AND l.status = 'done'),
atoms AS (
  SELECT vn.vehicle_id, (a->>'started_at')::timestamptz AS a_start, (a->>'ends_at')::timestamptz AS a_end
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
   WHERE vn.sim_run_id = :'run' AND a->>'svc' = 'interior_inspection' AND a ? 'started_at'),
j AS (
  SELECT l.*, x.a_start
    FROM legs l
    LEFT JOIN LATERAL (SELECT a.a_start FROM atoms a WHERE a.vehicle_id = l.vehicle_id
                        ORDER BY abs(EXTRACT(epoch FROM a.a_start - COALESCE(l.actual_start_sim, l.planned_start_sim)))
                        LIMIT 1) x ON true)
SELECT lane_booked, count(*) AS legs, count(a_start) AS atom_found,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM actual_start_sim - planned_start_sim) / 60))::numeric, 1)
         AS p50_leg_late_min,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM a_start - planned_start_sim) / 60))::numeric, 1)
         AS p50_atom_late_min,
       count(*) FILTER (WHERE actual_start_sim - planned_start_sim >= interval '30 minutes') AS leg_30_plus,
       count(*) FILTER (WHERE a_start - planned_start_sim >= interval '30 minutes') AS atom_30_plus
  FROM j GROUP BY 1 ORDER BY 1;
-- READ on b0fdc92b: the 25 without a lane booking (all closed by the readiness check): legs a median 67.1 minutes
--   late, 20 at 30+; their inspections a median 0.0 minutes late, 4 at 30+. The 66 lane-booked: legs a median 3.0
--   minutes early, none at 30+; inspections found for 51, a median 2.2 early, 7 at 30+.
--   So the late inspections of 0372 §5 (24 planned inside a charge, a median 37.8 late) are this: legs dated by the
--   readiness check, not inspections done late.

\echo '=== 0374 §1(c) — how long before the readiness check closed it had the inspection finished ==='
WITH r AS (
  SELECT vn.vehicle_id, (a->>'done_at')::timestamptz AS r_done
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
   WHERE vn.sim_run_id = :'run' AND a->>'svc' = 'readiness_check' AND a->>'status' = 'done'),
atoms AS (
  SELECT vn.vehicle_id, a->>'status' AS st, (a->>'ends_at')::timestamptz AS a_end
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
   WHERE vn.sim_run_id = :'run' AND a->>'svc' = 'interior_inspection' AND a ? 'started_at'),
legs AS (
  SELECT l.vehicle_id, l.actual_end_sim
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = :'run' AND l.leg_type = 'inspect'
     AND l.duration_basis->>'atom' = 'interior_inspection' AND l.status = 'done'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b WHERE b.leg_id = l.leg_id AND b.purpose = 'inspect')
     AND EXISTS (SELECT 1 FROM r WHERE r.vehicle_id = l.vehicle_id AND r.r_done = l.actual_end_sim))
SELECT count(*) AS legs, count(*) FILTER (WHERE x.a_end < l.actual_end_sim) AS inspection_done_before,
       round((percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(epoch FROM l.actual_end_sim - x.a_end) / 60))::numeric, 1) AS p50_min,
       round(max(EXTRACT(epoch FROM l.actual_end_sim - x.a_end) / 60)::numeric, 1) AS max_min
  FROM legs l
  LEFT JOIN LATERAL (SELECT a.a_end FROM atoms a WHERE a.vehicle_id = l.vehicle_id AND a.a_end <= l.actual_end_sim
                      ORDER BY a.a_end DESC LIMIT 1) x ON true;
-- READ on b0fdc92b: 25 legs; in 24 the inspection had finished first, a median 84.8 minutes before (max 188.9).

-- ══ §2 WHAT EACH READINESS CHECK CLOSED ═════════════════════════════════════════════════════════════════════════

\echo '=== 0374 §2 — readiness checks performed, by the leg each one closed ==='
WITH r AS (
  SELECT vn.vehicle_id, (a->>'done_at')::timestamptz AS r_done
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
   WHERE vn.sim_run_id = :'run' AND a->>'svc' = 'readiness_check' AND a->>'status' = 'done')
SELECT COALESCE(l.duration_basis->>'atom', '(no leg closed)') AS leg_closed, count(*) AS readiness_checks
  FROM r
  LEFT JOIN public.ottoq_itinerary_legs l
    ON l.sim_run_id = :'run' AND l.vehicle_id = r.vehicle_id
   AND l.leg_type = 'inspect' AND l.status = 'done' AND l.actual_end_sim = r.r_done
 GROUP BY 1 ORDER BY 2 DESC;
-- READ on b0fdc92b: 43 readiness checks. 26 closed an interior inspection's leg, 14 their own, 3 no open inspect
--   leg. 128 of the run's 142 readiness legs ended `skipped`. Each leg that reaches `done` issues a service detail
--   record (`trg_0043_leg_done_sdr`), so 29 readiness checks issued none, and 26 inspections were settled at the
--   readiness check's time.
--   The cause is one function and one argument. `ottoq_close_atom_leg(run, car, svc, ...)` matched
--   `leg_type = svc`. An inspection passed `interior_inspection`, and no leg has that type (the planner writes
--   `inspect` and tags the atom in `duration_basis`), so it closed nothing. The readiness check passed `inspect` and
--   got the car's first open inspect leg by `seq`, which is the inspection's whenever that one was still open.

-- ══ §3 THE INSPECTION LANE AND THE INSPECTION (G236, NOT CHANGED BY 0504) ═══════════════════════════════════════
--
--   The inspection seam sends a car with a planned interior-inspection leg to the `arrival_inspection` lane and books
--   it there, and the lane's booking closes the leg when it ends. The inspection itself is a cabin atom, started by
--   `public.ottoq_start_concurrent_atoms` wherever the car is when a general technician is free: in the lane, in a
--   staging zone while it waits, or at a charger. Nothing ties the two.

\echo '=== 0374 §3 — each lane visit against the car''s inspection, matched by car and time ==='
WITH bk AS (
  SELECT b.vehicle_id, lower(b.during) AS b_start, upper(b.during) AS b_end,
         (SELECT min(l0.planned_start_sim) FROM public.ottoq_itinerary_legs l0 WHERE l0.itinerary_id = l.itinerary_id) AS itin_start
    FROM public.ottoq_stall_bookings b
    JOIN public.ottoq_itinerary_legs l ON l.leg_id = b.leg_id
   WHERE b.sim_run_id = :'run' AND b.purpose = 'inspect'),
atoms AS (
  SELECT vn.vehicle_id, (a->>'started_at')::timestamptz AS a_start, (a->>'ends_at')::timestamptz AS a_end
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
   WHERE vn.sim_run_id = :'run' AND a->>'svc' = 'interior_inspection' AND a ? 'started_at')
SELECT count(*) AS lane_visits,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM atoms a WHERE a.vehicle_id = bk.vehicle_id
                                         AND a.a_end <= bk.b_start AND a.a_start >= bk.itin_start - interval '30 minutes'))
         AS inspection_done_before_the_lane,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM atoms a WHERE a.vehicle_id = bk.vehicle_id
                                         AND a.a_start < bk.b_end AND a.a_end > bk.b_start)) AS inspection_during_the_lane,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM atoms a WHERE a.vehicle_id = bk.vehicle_id
                                         AND a.a_start >= bk.b_end AND a.a_start < bk.b_end + interval '4 hours'))
         AS inspection_after_the_lane
  FROM bk;
-- READ on b0fdc92b: 66 lane visits. The inspection had already been done in 12, overlapped the visit in 17, and came
--   after it in 19; the rest matched no inspection nearby (the classes can overlap for a car with two atoms, so they
--   are bounds, not a partition). So the lane's booking closes the interior-inspection leg, and issues its service
--   record, at the lane visit's end in cases where the inspection happened elsewhere, earlier or later.
--   0504 removes the first class going forward: a finished inspection closes its own leg, and the seam sends only a
--   car with a planned one. The other two remain (G236). `twin.ottoq_sim_advance_visit_atoms` picks a car still
--   `arrived_at_gate` for the atom starter only when it has a pending exterior or digital atom (its
--   M3_cabin_at_charger rule holds cabin work for the charger and the holding states), and the starter then starts
--   every pending cabin, exterior and digital atom the technician pool allows. So a car that is still
--   `arrived_at_gate` in the lane with only cabin work pending is not inspected there. Whether the interior inspection belongs in the lane (the seam) or at the charger
--   (the catalog: `at_charge_stall`, "Cheap tech-pool lane at the charge stall") is a product question, not a
--   bookkeeping one.

-- ══ §4 THE APPLY, AND THE CANON UNDER IT ════════════════════════════════════════════════════════════════════════

\echo '=== 0374 §4 — 0504 as applied ==='
SELECT m.version, m.name, md5(m.statements[1]) AS stored_md5
  FROM supabase_migrations.schema_migrations m
 WHERE m.name = 'an_inspection_closes_its_own_leg_not_the_readiness_check';
-- READ: 20260926235621 (6:56 PM CT), md5 3aec4c9130c48e248a82beb1bbc94b9a, equal to the file's body; forces_recert
--   TRUE. Dry-run first, V3 passing (a planted interior tidy, inspection, wash and readiness leg on b0fdc92b: the
--   inspection closed its own leg with its own times and nothing else, the tidy closed as before, the wash stayed
--   open, the readiness check closed its own, and each closed leg issued one service detail record). Applied after
--   the 0502/0503 sweep passed all nine columns (verdicts 430-438, the last at 6:45 PM CT).

\echo '=== 0374 §4(b) — the canon since 0504, and what moved against its verdict under 0503 ==='
WITH now_v AS (
  SELECT DISTINCT ON (scenario, seed, ticks) verdict_id, scenario, seed, ticks, equal, verdict->'arm_a' AS a
    FROM public.ottoq_determinism_verdict_ledger
   WHERE certified_at > '2026-09-26 23:56:21+00'
   ORDER BY scenario, seed, ticks, verdict_id DESC),
before_v AS (
  SELECT DISTINCT ON (scenario, seed, ticks) verdict_id, scenario, seed, ticks, verdict->'arm_a' AS a
    FROM public.ottoq_determinism_verdict_ledger
   WHERE verdict_id BETWEEN 430 AND 438
   ORDER BY scenario, seed, ticks, verdict_id DESC)
SELECT n.scenario || '/' || n.seed || '/' || n.ticks AS col, b.verdict_id AS was, n.verdict_id AS now, n.equal,
       (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(n.a) k
         WHERE (k LIKE 'h\_%' OR k IN ('fp','endst'))
           AND n.a->>k IS DISTINCT FROM b.a->>k) AS moved
  FROM now_v n LEFT JOIN before_v b USING (scenario, seed, ticks)
 ORDER BY 1;
-- READ: pending.

-- ══ §5 THE NEXT VALIDATION RUN, PREDICTED BEFORE IT STARTS ══════════════════════════════════════════════════════
--
--   PREDICTED on the next busy_day operator run: (a) no interior inspection leg is closed by a readiness check, and
--   every one an inspection closed starts at its atom's start; (b) done readiness legs roughly equal readiness checks
--   performed (14 of 43 on b0fdc92b), each with a service detail record; (c) no lane visit for a car whose inspection
--   is already done (12 of 66 on b0fdc92b); (d) KPI 5 no longer finds an inspection leg dated by a readiness check,
--   so its bands can move toward earlier first operations.

\echo '=== 0374 §5(a) — done interior inspection legs by what closed them (the §1 query), and against their atom ==='
--   Run §1 and §1(b) on the new run: `by_readiness` should read 0 rows true, and the legs without a lane booking
--   should start a median 0.0 minutes from their atoms.

\echo '=== 0374 §5(b) — readiness checks performed against readiness legs done, and their service records ==='
SELECT (SELECT count(*) FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
         WHERE vn.sim_run_id = :'run' AND a->>'svc' = 'readiness_check' AND a->>'status' = 'done') AS readiness_checks_done,
       (SELECT count(*) FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id = :'run' AND l.leg_type = 'inspect' AND l.duration_basis->>'atom' = 'readiness_check'
           AND l.status = 'done') AS readiness_legs_done,
       (SELECT count(*) FROM public.ottoq_service_detail_records s
          JOIN public.ottoq_itinerary_legs l ON l.leg_id = s.leg_id
         WHERE s.sim_run_id = :'run' AND l.duration_basis->>'atom' = 'readiness_check') AS readiness_sdrs;
-- READ: pending.

\echo '=== 0374 §5(c) — lane visits for a car whose inspection was already done (the §3 query) ==='
--   Run §3 on the new run: `inspection_done_before_the_lane` should read 0.

-- ══ §6 THE COMMAND'S EXECUTION TIME (G237, 0505) ════════════════════════════════════════════════════════════════
--
--   Found while reading §3's appointments: measured from `executed_at`, 1 of 77 recall appointments reached its lane
--   stall; measured from `issued_at`, 28 of 77. The column was the difference. `twin.ottoq_sim_confirm_commands`
--   executes a command in the tick it runs and stamped `confirmed_at` and `executed_at` with issue + 30 minutes.

\echo '=== 0374 §6 — executed commands at the twin depot, by the gap between issue and recorded execution ==='
SELECT CASE WHEN r.validation_status IS NULL THEN 'operator' ELSE 'certification arm' END AS run_class,
       count(DISTINCT r.sim_run_id) AS runs, count(*) AS executed_commands,
       count(DISTINCT EXTRACT(epoch FROM c.executed_at - c.issued_at)) AS distinct_gaps,
       min(EXTRACT(epoch FROM c.executed_at - c.issued_at)) AS min_s, max(EXTRACT(epoch FROM c.executed_at - c.issued_at)) AS max_s
  FROM public.ottoq_vehicle_commands c
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = c.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND c.status = 'executed'
 GROUP BY 1 ORDER BY 1;
-- READ (2026-09-27 00:20 UTC, before 0505): certification arms 386 runs, 171,470 executed commands, ONE distinct gap,
--   1,800 seconds. Operator runs 9, 19,763 commands, 31 distinct gaps: every command of the eight runs since
--   2026-08-30 at exactly 1,800 seconds (b0fdc92b: 281 of 281), and the 30 commands of one run from 2026-07-21
--   (b54929ce) at 61-100 seconds, the only rows that record a real gap. An operator run ticks about every 33
--   sim-seconds and a canon arm every 30 sim-minutes, so on the canon the constant equals one tick, which is how 0308
--   §8 could read it as a measured one-tick lag (G112). Whether the confirm step really runs one tick after the
--   command is issued is not shown by this column, before or after 0505 on the canon; it is shown on an operator run.
--   PREDICTED after 0505: executed_at = the confirm step's clock, so on an operator run the gap is one or a few ticks
--   (tens of seconds to a few minutes) and varies; certified digests do not move (neither column is in one).
