-- 0435  **A rider's reported cleaning, raised while the car is parked, is dropped when the twin derives a new visit
--        over it, and 15 departures since 0543 left with it owed.** (G413, CLAUDE.md rule 9; fixed by 0698.)
--        Found reading G399's labels (0431 §5 (c)). Measured 2026-10-10 between 08:22:45 and 08:42:29 UTC
--        (3:22-3:42 AM CT), §4b between 08:54:39 and 08:56:35 UTC (3:54-3:56 AM CT), all read from the clock;
--        read-only, twin depot 11111111-…, during the nightly sweep window (reads only).
--
-- ══ §1 HOW A VISIT ENDS ON THE TWIN DEPOT (reproduce (1)) ═══════════════════════════════════════════════════════
--
--   Of the twin depot's visits, 9 are labelled 'complete' (all nine are G399's: a visit the twin generated for an
--   arrival that never came, every atom untouched) and 35,415 'superseded'. A visit normally ends superseded: the
--   dispatcher's release (ottoq.ottoq_release_visit_artifacts) supersedes the car's open visit as it leaves, and the run
--   finalizer (ottoq_close_run_needs) supersedes what is open when a run ends, stamping closed_by.
--
-- ══ §2 SINCE 0543 (184 RUNS, 171 OF THEM busy_day; reproduce (2)) ═══════════════════════════════════════════════
--
--   Superseded visits with no closed_by (so not closed by a run's end): 18,006 with every required atom done or
--   cancelled, and 44 with required work owed (5 untouched, 39 with some work done). All 44 came from
--   ottoq.ottoq_rider_flag_indepot_sweep: a rider's cleaning report that comes due while the car is parked, put on a
--   visit of its own (archetype R_rider_flag_cleaning) when the car has no open visit. Closed at a run's end with
--   required work owed: 2,885 untouched and 13,503 with some work done (cars still at the depot when the run stopped).
--
-- ══ §3 WHAT HAPPENED TO THOSE CARS (reproduce (3), (4)) ═════════════════════════════════════════════════════════
--
--   39 of the 44 cars left after the report. Every one of the 39 had a new visit derived over the report's visit first
--   (source twin_generator, between the report and the departure). In 24 the cleaning was performed anyway before the
--   car left (a twin.service_completed crediting it between the report and the departure); how the service flow knew
--   is not traced here. **15 left with no record of it: 13 interior deep cleans and 2 exterior washes, all on busy_day,
--   in 15 runs, 7 distinct cars.** Pair arms replay one world (G153), so the 15 are not 15 independent observations.
--
-- ══ §4 THE MECHANISM (reproduce (5), (6)) ═══════════════════════════════════════════════════════════════════════
--
--   - ottoq.ottoq_rider_flag_indepot_sweep puts the cleaning on its own visit and consumes the flag, so the deriver's
--     rider branch (which reads flags 'pending' or 'recalled') never raises it again.
--   - ottoq.ottoq_derive_visit_needs builds the new visit from the observation, takes work only from a 'carried_over'
--     visit, and supersedes every 'open' or 'in_progress' visit of the car ("unscoped supersede", RECORDED in its
--     header). The cleaning goes with the supersede.
--   - ottoq_departure_clear reads only 'open' and 'in_progress' visits, so it no longer sees the cleaning.
--   The car traced end to end (5): run 0bbdcc07, car 5604331f (Zoox), on the run's sim clock: the sweep opened the
--   cleaning's visit at 14:09:31 UTC (9:09 AM CT); the twin derived visit M_pass_through_or_P_triage at 14:51:32 UTC
--   (9:51 AM CT), whose own meta reads rider_flag_kind 'interior' with rider_flagged false; its four atoms (readiness,
--   interior inspection, interior tidy, triage) closed; the car left at 14:59:30 UTC (9:59 AM CT) without visiting a
--   detail bay.
--
-- ══ §4b THE CHARGE AT DEPARTURE HOLDS (reproduce (7)) ═════════════════════════════════════════════════════════
--
--   The same audit for the other half of rule 9: since 0543, 21,438 twin-depot departures from the depot (6,068 first
--   departures after a run's start, 15,370 after a return) all left at 99% or more. The 12,669 dispatch rows whose
--   soc_at_dispatch_pct is below 99 (as low as 85) are every one a run-start deployment: a car the run begins with on
--   the road, at its seeded charge, that never left the depot. Read soc_at_dispatch_pct as a departure's charge only
--   after dropping the rows dispatched at the run's sim_clock_start.
--
-- ══ §5 WHAT FOLLOWS ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) 0698: the deriver carries every required atom an open or in-progress visit of the car on the same run still
--       owes onto the new visit (not the charge or the readiness check, which it sets afresh; not a guard-demoted atom).
--       It changes the twin's world with every flag off, so it forces a recertification, and is written to ride the
--       one 0657 and 0696 force the same morning.
--   (b) Production would not have the twin's own cleaning to fall back on: there, only the visit's atoms say a car owes
--       a cleaning. So the 24 the twin cleaned anyway are not evidence the defect is harmless.
--   (c) G399 (a visit labelled 'complete' with its work untouched) stays open: 9 visits, all for arrivals that never
--       came, none with a departure owing work.
--
-- ══ REPRODUCE (read-only) ══

-- (1) how the twin depot's visits are labelled
WITH v AS (
  SELECT vn.status,
         (SELECT count(*) FROM jsonb_array_elements(vn.atoms) a
           WHERE COALESCE((a->>'must_do')::boolean, false) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')) AS must_open,
         (SELECT count(*) FROM jsonb_array_elements(vn.atoms) a WHERE COALESCE(a->>'status','pending') IN ('in_progress','done')) AS touched
    FROM public.ottoq_visit_needs vn WHERE vn.depot_id = '11111111-1111-1111-1111-111111111111')
SELECT status, count(*) AS visits, count(*) FILTER (WHERE must_open > 0) AS required_open,
       count(*) FILTER (WHERE must_open > 0 AND touched = 0) AS required_open_untouched
  FROM v GROUP BY status ORDER BY status;

-- (2) since 0543 (applied 2026-09-28 01:38:04 UTC): superseded visits by closing path
WITH runs AS (SELECT sim_run_id FROM public.ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-09-28 01:38:04+00'),
v AS (
  SELECT vn.source, vn.meta->>'closed_by' AS closed_by,
         EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                  WHERE COALESCE((a->>'must_do')::boolean, false) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')) AS required_open,
         EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE COALESCE(a->>'status','pending') IN ('in_progress','done')) AS some_work
    FROM public.ottoq_visit_needs vn JOIN runs USING (sim_run_id)
   WHERE vn.depot_id = '11111111-1111-1111-1111-111111111111' AND vn.status = 'superseded')
SELECT closed_by IS NOT NULL AS closed_at_run_end, required_open, some_work,
       CASE WHEN required_open AND closed_by IS NULL THEN source END AS source, count(*) AS visits
  FROM v GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;

-- (3) the report's visits superseded owing work: did the car leave, and was the work done before it did
WITH runs AS (SELECT sim_run_id, scenario_code FROM public.ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-09-28 01:38:04+00'),
v AS (
  SELECT vn.visit_id, vn.sim_run_id, r.scenario_code, vn.vehicle_id, vn.arrived_at AS opened_sim,
         (SELECT array_agg(DISTINCT a->>'svc') FROM jsonb_array_elements(vn.atoms) a
           WHERE COALESCE((a->>'must_do')::boolean, false) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled')
             AND a->>'svc' <> 'charge') AS open_svcs
    FROM public.ottoq_visit_needs vn JOIN runs r USING (sim_run_id)
   WHERE vn.depot_id = '11111111-1111-1111-1111-111111111111' AND vn.status = 'superseded'
     AND vn.meta->>'closed_by' IS NULL AND vn.source = 'rider_flag_indepot_sweep'),
w AS (
  SELECT v.*, (SELECT min(d.dispatched_at) FROM public.ottoq_vehicle_dispatches d
                WHERE d.sim_run_id = v.sim_run_id AND d.vehicle_id = v.vehicle_id AND d.dispatched_at >= v.opened_sim) AS left_sim
    FROM v WHERE open_svcs IS NOT NULL),
x AS (
  SELECT w.*, EXISTS (SELECT 1 FROM public.ottoq_events e
                       WHERE e.sim_run_id = w.sim_run_id AND e.entity_id = w.vehicle_id AND e.event_type = 'twin.service_completed'
                         AND e.sim_clock_at BETWEEN w.opened_sim AND w.left_sim
                         AND (SELECT bool_and(e.payload->'credited' ? s) FROM unnest(w.open_svcs) s)) AS performed
    FROM w)
SELECT count(*) AS visits, count(*) FILTER (WHERE left_sim IS NOT NULL) AS car_left,
       count(*) FILTER (WHERE left_sim IS NOT NULL AND performed) AS performed_before_leaving,
       count(*) FILTER (WHERE left_sim IS NOT NULL AND NOT performed) AS left_owing,
       count(*) FILTER (WHERE left_sim IS NOT NULL AND NOT performed AND 'interior_deep_clean' = ANY(open_svcs)) AS owing_deep_clean,
       count(*) FILTER (WHERE left_sim IS NOT NULL AND NOT performed AND 'exterior_wash' = ANY(open_svcs)) AS owing_wash,
       count(DISTINCT vehicle_id) FILTER (WHERE left_sim IS NOT NULL AND NOT performed) AS distinct_cars,
       count(DISTINCT sim_run_id) FILTER (WHERE left_sim IS NOT NULL AND NOT performed) AS runs,
       count(*) FILTER (WHERE left_sim IS NOT NULL AND NOT performed AND scenario_code = 'busy_day') AS on_busy_day
  FROM x;

-- (4) the mechanism, per car that left: the first visit derived after the report and before the departure
WITH runs AS (SELECT sim_run_id FROM public.ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-09-28 01:38:04+00'),
v AS (
  SELECT vn.sim_run_id, vn.vehicle_id, vn.arrived_at AS opened_sim
    FROM public.ottoq_visit_needs vn JOIN runs USING (sim_run_id)
   WHERE vn.depot_id = '11111111-1111-1111-1111-111111111111' AND vn.status = 'superseded'
     AND vn.meta->>'closed_by' IS NULL AND vn.source = 'rider_flag_indepot_sweep'
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                  WHERE COALESCE((a->>'must_do')::boolean, false) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))),
w AS (
  SELECT v.*, (SELECT min(d.dispatched_at) FROM public.ottoq_vehicle_dispatches d
                WHERE d.sim_run_id = v.sim_run_id AND d.vehicle_id = v.vehicle_id AND d.dispatched_at >= v.opened_sim) AS left_sim
    FROM v)
SELECT (SELECT n2.source FROM public.ottoq_visit_needs n2
         WHERE n2.sim_run_id = w.sim_run_id AND n2.vehicle_id = w.vehicle_id
           AND n2.arrived_at > w.opened_sim AND n2.arrived_at <= w.left_sim
         ORDER BY n2.arrived_at LIMIT 1) AS superseded_by, count(*) AS cars
  FROM w WHERE left_sim IS NOT NULL GROUP BY 1;

-- (5) the car traced end to end: its visits on run 0bbdcc07
SELECT vn.source, vn.status, vn.arrived_at AS sim_at, vn.archetype,
       (SELECT jsonb_agg(jsonb_build_object('svc', a->>'svc', 'status', COALESCE(a->>'status','pending'))) FROM jsonb_array_elements(vn.atoms) a) AS atoms,
       vn.meta->>'rider_flag_kind' AS rider_flag_kind, vn.meta->>'rider_flagged' AS rider_flagged
  FROM public.ottoq_visit_needs vn
 WHERE vn.sim_run_id = '0bbdcc07-6b45-4b55-a929-77ed4c76ab35' AND vn.vehicle_id = '5604331f-284d-4768-a521-b60693aebe25'
 ORDER BY vn.arrived_at;

-- (6) the code, as it stood: the deriver's carry reads only 'carried_over', its supersede takes 'open' and
--     'in_progress'; the departure test reads only 'open' and 'in_progress'
SELECT p.oid::regprocedure AS fn,
       position('status = ''carried_over''' in p.prosrc) > 0 AS reads_carried_over,
       position('SET status = ''superseded''' in p.prosrc) > 0 AS supersedes,
       position('vn.status IN (''open'', ''in_progress'')' in p.prosrc) > 0 AS reads_open_visits
  FROM pg_proc p
 WHERE p.oid IN ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamptz,uuid,jsonb)'::regprocedure,
                 'public.ottoq_departure_clear(uuid,uuid,timestamptz,boolean)'::regprocedure);

-- (7) the charge at departure: run-start deployments apart from departures from the depot
WITH runs AS (SELECT sim_run_id, sim_clock_start FROM public.ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND started_at >= '2026-09-28 01:38:04+00'),
d AS (
  SELECT d.*, r.sim_clock_start,
         EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches p
                  WHERE p.sim_run_id = d.sim_run_id AND p.vehicle_id = d.vehicle_id
                    AND p.actual_return_at IS NOT NULL AND p.actual_return_at <= d.dispatched_at
                    AND p.dispatch_id <> d.dispatch_id) AS came_back_before
    FROM public.ottoq_vehicle_dispatches d JOIN runs r USING (sim_run_id))
SELECT CASE WHEN dispatched_at <= sim_clock_start + interval '1 minute' THEN 'at run start'
            WHEN came_back_before THEN 'left after a return'
            ELSE 'first departure of the run, after the start' END AS kind,
       count(*) AS dispatches, count(*) FILTER (WHERE soc_at_dispatch_pct < 99) AS below_99,
       min(soc_at_dispatch_pct) AS min_soc
  FROM d GROUP BY 1 ORDER BY 1;
