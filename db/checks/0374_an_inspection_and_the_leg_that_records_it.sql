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
-- READ (2026-09-27 00:59 UTC): all nine columns passed under 0504, verdicts 439-447, certified 6:57-7:17 PM CT, every
--   one `equal = true`. Moved against 430-438:
--     busy_day/171717/12            endst h_bkg h_cmd h_dec h_evt h_nrg h_rule h_sdr
--     busy_day/171717/24 and /48    all ten (the above plus h_prop h_rcl)
--     busy_day/314159/12            endst h_bkg h_cmd h_dec h_evt h_rule h_sdr
--     busy_day/424242/12            endst h_bkg h_cmd h_dec h_evt h_nrg h_prop h_rule h_sdr
--     busy_day/424242/24            all ten
--     grid_smoke/239001/6 and /424242/6   endst h_evt h_sdr
--     normal_day/171717/12          endst h_bkg h_cmd h_dec h_evt h_prop h_rule h_sdr
--   `fp` moved in none. h_sdr moved in all nine, as it had to: an inspection leg now closes on its atom's times, and a
--   readiness check now closes its own leg and issues its own record. Beyond the records the change reaches the
--   decisions in every busy_day and normal_day column. Why is not traced here; one path is the seam, which sends a car
--   with an open interior leg to the lane, and 0504 closes those legs sooner. 0505, 0506 and 0507 (forces_recert FALSE)
--   started no sweep: no verdict since 447.

-- ══ §5 THE NEXT VALIDATION RUN, PREDICTED BEFORE IT STARTS ══════════════════════════════════════════════════════
--
--   PREDICTED on the next busy_day operator run: (a) no interior inspection leg is closed by a readiness check, and
--   every one an inspection closed starts at its atom's start; (b) done readiness legs roughly equal readiness checks
--   performed (14 of 43 on b0fdc92b), each with a service detail record; (c) no lane visit for a car whose inspection
--   is already done (12 of 66 on b0fdc92b); (d) KPI 5 no longer finds an inspection leg dated by a readiness check,
--   so its bands can move toward earlier first operations.
--
--   READ on validation run 5344fc12 (busy_day, twin depot, started from the twin cockpit at 7:29 PM CT and stopped at
--   7:53; 356 ticks, sim 8:00-11:15 AM; 0502-0505 in force from the start, 0506 and 0507 applied during it):
--   (a) held. 114 interior inspection legs done, 0 closed by a readiness check (26 of 91 on b0fdc92b). The 57 without
--       a lane booking start and end on their atoms' exact times, 57 of 57 (a median 0.0 minutes late, none 30+; on
--       b0fdc92b a median 67.1 late, 20 at 30+). The 57 lane-booked: legs a median 3.0 minutes early, none 30+; 12 of
--       them closed on their atom's times (the inspection finished inside the lane visit and closed the leg first);
--       inspections found for 44, a median 0.8 late, 6 at 30+.
--   (b) held. 42 readiness checks performed, 39 closed their own leg and 3 found none open; 39 readiness legs done,
--       with 39 service detail records (14 of 43 and 29 checks with no record on b0fdc92b). 102 of 141 readiness legs
--       ended `skipped` (128 of 142).
--   (c) held. 59 lane visits, 0 for a car whose inspection was already done (12 of 66). The inspection overlapped the
--       visit in 20 and came after it in 17 (17 and 19): G236's other two classes, which 0504 does not touch.
--   (d) not distinguishable on one run. KPI 5 read p95 26.0 and p50 0.4 minutes (27.6 and 0.4 on b0fdc92b), over 114
--       measured returns (113); this run stopped 29 sim-minutes earlier. Beside it, the charge wait (0501) read p50 14.8,
--       p95 82.7, 48 cars still waiting at the stop, floor 124.3 (8.4, 98.5, 47, 156.2). The KPI 4 audit column
--       `touch_events_override_flag_only` read 67 against 18; not traced here (KPI 4 itself read 0 on both).

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
-- READ on 5344fc12: 42 readiness checks done, 39 readiness legs done, 39 records (§5 above).

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
-- READ (after 0505, applied 20260927002850, 7:28 PM CT, before 5344fc12 started): on 5344fc12, 347 executed commands,
--   167 distinct gaps from 21 to 112 seconds, a median 31 (`stage` 168, a median 28; `begin_charge` 95, 34;
--   `proceed_to_stall` 69, 35; `enter_wash` 11, 37; `enter_service` 4, 34), `confirmed_at = executed_at` on all 347.
--   Every one executed in the tick after the one that issued it: counted against `ottoq_tick_clock_log`, 347 of 347
--   have exactly one tick between issue and execution, and both times sit on a tick's clock. The run's ticks advanced
--   a median 26.7 sim-seconds (mean 33.0, 20.2-335.0), which is the whole spread of the gaps. So G112's mechanism
--   stands, measured this time: the twin's confirm chain costs exactly one tick. The certification arms still read
--   1,800 seconds for their commands (388 arms, 173,064 commands), because none has run since 0505. PREDICTED for the
--   next sweep: one canon tick, which is also 1,800 seconds, so those arms will read the same number for a true
--   reason. No certified digest moved, and none could.

-- ══ §7 WHAT THE CARDS SAID (G232, THE DISPLAY HALF: 0506, 0507) ═════════════════════════════════════════════════
--
--   0504 fixed the record. The vehicle cards read the plan: `public.ottoq_depot_cards` builds each car's steps from its
--   itinerary legs, and PULSE and OrchestrAV print the first upcoming step as "Next: <leg type> at <planned start>" and
--   the current one as "Now: <leg type> until <planned end>". Read live on 5344fc12 before either migration: at sim
--   9:23 AM PULSE showed 37 "Next" lines, 11 of them already past (9 read "Inspect", the oldest 8:20 AM); at 9:32, 5
--   charging cars had a readiness check next that was up to 67 minutes past; at 10:35, 10 of 25 active L2 charges had
--   started 30+ minutes before their planned start, and their "until" was off by up to 242 minutes (Tesla-AV-049: "Now:
--   Level 2 charge until 4:51 PM" beside "Next: Readiness check at 1:01 PM", for a charge that started at 9:51 AM).
--   The card's progress bar already measured from the actual start, so the bar and the time disagreed.
--
--   0506 (applied 20260927004648, 7:46 PM CT, during the run): every step carries `atom`, and an upcoming step whose
--   planned start is behind the run's clock carries `overdue_min`; contract 1.1 -> 1.2. 0507 (20260927005114, 7:51 PM
--   CT): the current step carries `expected_end`, its actual start plus its planned duration. Both forces_recert
--   FALSE (a cockpit read function), both dry-run and applied with V3 passing on the live cards (0507's: all 31
--   current steps carried `expected_end`). The cockpits print "Readiness check" or "Interior inspection" for an
--   inspect step, "planned <time>, <n> min ago" in amber for an overdue next step, and the current step "until" its
--   expected end (OTTOYARD/ottoyard-field-ops#16, OTTOYARD/ottoyard-OTTO-Q#22).

\echo '=== 0374 §7 — on a live run: steps behind the clock, overdue marks, and current steps whose end moved ==='
WITH c AS (SELECT public.ottoq_depot_cards('11111111-1111-1111-1111-111111111111', NULL) AS j),
st AS (SELECT (c.j->>'sim_clock')::timestamptz AS clk, s
         FROM c, jsonb_array_elements(c.j->'vehicles') v, jsonb_array_elements(COALESCE(v->'card'->'steps', '[]'::jsonb)) s)
SELECT count(*) FILTER (WHERE s->>'status' = 'upcoming' AND (s->>'planned_start')::timestamptz < clk) AS upcoming_behind_clock,
       count(*) FILTER (WHERE s->>'status' = 'upcoming' AND s->>'overdue_min' IS NOT NULL) AS marked_overdue,
       count(*) FILTER (WHERE s->>'leg_type' = 'inspect' AND s->>'atom' IS NULL) AS inspect_without_atom,
       count(*) FILTER (WHERE s->>'status' = 'current') AS current_steps,
       count(*) FILTER (WHERE s->>'status' = 'current'
                          AND abs(EXTRACT(epoch FROM (s->>'expected_end')::timestamptz
                                                   - (s->>'planned_end')::timestamptz)) >= 1800) AS current_end_moved_30_plus
  FROM st;
-- READ on 5344fc12, in the cockpits after both applies: PULSE at sim 11:07 AM and OrchestrAV at 11:05 read the same
--   cars the same way. Tesla-AV-049 "Now: Level 2 charge until 12:57 PM" (was 4:51 PM) and "Next: Readiness check at
--   1:01 PM"; Tesla-AV-048 "Next: Readiness check planned 10:58 AM, 9 min ago" (7 in OrchestrAV two minutes earlier);
--   Tesla-AV-043 "Now: DC fast charge until 11:17 AM" and "Next: Level 2 charge planned 10:49 AM, 18 min ago".
--   The query above needs a live run; with none live it returns zeros.
--
--   What the last card shows is the plan side of G232, still open. The planner gave Tesla-AV-043 an L2 charge; the
--   charge step put it on a DC fast charger, and the itinerary gained a `taxi` and a `charge_dcfc` leg while the
--   planned `charge_l2` leg stayed upcoming, then ended `skipped`. On 5344fc12, 24 itineraries (18 with the DC charge
--   done, 6 still charging at the stop) kept a planned L2 leg beside the DC charge that served it, so the card said
--   "Next: Level 2 charge" for a charge that was already happening. 0506 made that line say how late it is; it cannot
--   say the step is moot, because the plan does not.

\echo '=== 0374 §7(b) — itineraries whose planned charge leg stayed beside a charge of the other type ==='
WITH it AS (
  SELECT l.itinerary_id,
         string_agg(l.leg_type || ':' || l.status, ',' ORDER BY l.seq) FILTER (WHERE l.leg_type LIKE 'charge%') AS charge_legs
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = :'run'
   GROUP BY 1)
SELECT charge_legs, count(*) AS itineraries FROM it WHERE charge_legs IS NOT NULL GROUP BY 1 ORDER BY 2 DESC;
-- READ on 5344fc12: charge_l2:skipped 45 (no charge ran), charge_l2:done 39, charge_l2:amended 23 (charging at the
--   stop), charge_l2:skipped,charge_dcfc:done 18, charge_dcfc:done 8, charge_l2:skipped,charge_dcfc:amended 6,
--   charge_dcfc:done,charge_l2:done 1.
