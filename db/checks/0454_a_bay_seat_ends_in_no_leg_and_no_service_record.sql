-- 0454  **Most bay work ends in no itinerary leg and no service record, and its planned leg is left behind as a
--        phantom the flow contract keeps re-timing.** -> G464, fixed under a dial by db/migrations/0750.
--        Found while building the service clock (task #30): the clock wanted each bay seat's start and end, and the
--        kernel's record of a completed operation, the SDR, holds them for a small part of the bay work.
--        Read-only, against gxdrcyphqjzjsuhxuqtg, 2026-10-17 between 10:51 and 11:13 PM CT (03:51 and 04:13 UTC Oct 18),
--        bounded by clock reads. The runs are the twin depot's completed runs of 144 ticks or more started from
--        2026-10-16 up to tonight's window (11 runs: 6 normal days, 5 busy days). Every number names its query.
--
-- ══ §1 WHAT IS RECORDED (reproduce: (1), (2)) ═══════════════════════════════════════════════════════════════════════════
--
--   Completed bay atoms against the SDRs issued for their operation, on the 11 runs:
--                                    atoms done    SDRs    share
--     wash (exterior_wash)                  299      32    10.7%
--     detail (interior_deep_clean)          413      73    17.7%
--     service bay (generic_service)         284      90    31.7%
--   The work in place is covered: software_update 94.1%, remote_diagnostics 99.3%, item_retrieval 100%, sensor_clean and
--   interior_tidy above 100% (a leg per pass). Charges are above 100% too (3,307 SDRs for 2,489 charge atoms done: every
--   charge start opens a leg). Read by the bay leg's own end, (2): a planned leg whose work was done ended
--     wash      done 32    skipped 255   (89% of the completed washes)
--     detail    done 71    skipped 298   (81%)
--     service   done 81    skipped 183   (69%)
--
-- ══ §2 WHY (reproduce: (3), (4), (5)) ═══════════════════════════════════════════════════════════════════════════════════
--
--   An SDR is issued when an itinerary leg turns done (trg_0043_leg_done_sdr) or a schedule task completes, and nowhere
--   else. A bay leg turns done at the bay exit: STEP 1 of twin.ottoq_sim_advance_service_flow closes the car's ACTIVE
--   wash, detail and service legs (ottoq_itin_leg_close). A leg becomes active only through ottoq_itin_leg_open, and its
--   two callers are the service flow's own STEP 2 seats and every charge start (twin.ottoq_sim_start_charge_session), (3).
--   The decide seats most bay cars through a command: (4b) books a walk-in and emits enter_wash or enter_service, (5)
--   does the same for service sequencing, and twin.ottoq_sim_confirm_commands carries it out. The confirm walk never
--   names a leg (no reference to ottoq_itinerary_legs, leg_id or the itin_ helpers in its 23,051 characters). So the car
--   is seated, works, and leaves with no active leg; the exit closes nothing, the bay atoms are credited
--   (ottoq_mark_visit_atoms_done), and the planned leg the planner wrote at arrival stays planned until the car deploys,
--   when the flow contract or the visit release marks it skipped. ottoq_close_atom_leg (0504, G232), which closes the
--   work done in place, leaves bay legs out on the premise that "the service flow opens and closes them"; it does so
--   only for its own seats.
--   By the booking that covered the seat, (4): the calendar's activations end their legs done (wash 19 + 14, detail
--   29 + 35, service 10 + 7), and they are where the SDRs come from (32 wash SDRs against 33 activated wash seats). (4b)'s
--   walk-ins bound a planned leg to their booking 114 times in 407 washes, 115 in 414 details and 75 in 143 services, and
--   every one of those legs still ended skipped; service sequencing bound 88 of 112, all skipped.
--   The census that would have shown this, public.ottoq_check_sdr_coverage, starts from done legs and completed schedule
--   tasks, so work that never had a done leg is outside what it can count (5).
--   In production, the reported-completion seam public.ottoq_ingest_service_complete either marks the reported atoms done
--   directly, which issues no SDR, or sets service_done on a car in a bay, which STEP 1 then completes at the same exit.
--
-- ══ §3 WHAT IT COSTS THE PLAN (reproduce: (6)) ═══════════════════════════════════════════════════════════════════════════
--
--   twin.ottoq_sim_advance_flow_contract re-times a car's whole plan (amend_plan) whenever a planned leg's start is more
--   than 20 minutes past and the car is not charging or in a bay. A phantom bay leg is such a leg, so the plan of a car
--   whose wash is done keeps a wash in it, moved later every 20 minutes. On the 11 runs the flow contract made 20,250
--   amend_plan decisions over 1,174 car-runs, and 7,239 of them (35.7%) were made while the car carried a skipped-later
--   bay leg whose work was already done. That is an upper bound on what recording the leg removes: a car can carry
--   another late leg at the same time. The owner app's ready-by is the latest planned end (G454), and reads the same legs.
--   The departure test reads neither legs nor SDRs (public.ottoq_departure_clear), so no car left or stayed because of
--   this (rule 9).
--
-- ══ §4 THE FIX (db/migrations/0750, dial bay_exit_closes_its_leg, default off) ═══════════════════════════════════════════
--
--   At the bay exit, after the credit set is known, a seat that closed no active leg closes the planned bay leg of each
--   service it credited, with the seat's start and the work's end, and binds the booking that covered the seat; a seat
--   with no bay leg at all records one in the car's active itinerary. The existing trigger then issues the SDR. Its arm
--   (bayexit_normal_2026_10_18) pairs with arm 84 (b54f6de5); this file's queries, re-run on the arm, are its readout.

-- (1) Completed bay atoms against SDRs, by operation, on the 11 runs.
WITH runs AS (SELECT sim_run_id FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND tick_count >= 144
                 AND started_at >= '2026-10-16 00:00+00' AND started_at < '2026-10-18 03:50+00'),
atoms AS (
  SELECT vn.sim_run_id, a->>'svc' AS svc, a->>'status' AS st
    FROM ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
   WHERE vn.sim_run_id IN (SELECT sim_run_id FROM runs)),
done AS (
  SELECT CASE svc WHEN 'exterior_wash' THEN 'wash' WHEN 'interior_deep_clean' THEN 'detail' WHEN 'charge' THEN 'charge'
                  WHEN 'fault_repair' THEN 'generic_service' WHEN 'mechanical_pm' THEN 'generic_service'
                  WHEN 'sensor_calibration' THEN 'generic_service' WHEN 'cosmetic_repair' THEN 'generic_service'
                  ELSE svc END AS op, count(*) FILTER (WHERE st = 'done') AS atoms_done, count(*) AS atoms
    FROM atoms GROUP BY 1),
sdr AS (
  SELECT CASE WHEN operation_code IN ('charge_dcfc','charge_l2') THEN 'charge' ELSE operation_code END AS op, count(*) AS sdrs
    FROM ottoq_service_detail_records WHERE sim_run_id IN (SELECT sim_run_id FROM runs) GROUP BY 1)
SELECT COALESCE(d.op, s.op) AS op, d.atoms, d.atoms_done, s.sdrs, round(100.0 * s.sdrs / NULLIF(d.atoms_done, 0), 1) AS sdr_pct
  FROM done d FULL JOIN sdr s ON s.op = d.op ORDER BY d.atoms_done DESC NULLS LAST;

-- (2) Bay legs by their own end, against the status of the atom the planner tagged them with.
WITH runs AS (SELECT sim_run_id FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND tick_count >= 144
                 AND started_at >= '2026-10-16 00:00+00' AND started_at < '2026-10-18 03:50+00')
SELECT l.leg_type, l.status,
       COALESCE((SELECT x->>'status' FROM ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) x
                  WHERE vn.visit_id = i.visit_id AND x->>'svc' = l.duration_basis->>'atom' LIMIT 1), '(no atom)') AS atom_status,
       count(*) AS legs
  FROM ottoq_itinerary_legs l JOIN ottoq_vehicle_itineraries i USING (itinerary_id)
 WHERE l.sim_run_id IN (SELECT sim_run_id FROM runs) AND l.leg_type IN ('wash','detail','service')
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 4 DESC;

-- (3) Who opens a leg, who issues an SDR, and the confirm walk's references to legs (none).
SELECT 'opens a leg' AS what, string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY 1) AS which
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc ~ 'ottoq_itin_leg_open\s*\(' AND p.proname <> 'ottoq_itin_leg_open'
UNION ALL
SELECT 'issues an SDR', string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY 1)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc ~ 'ottoq_emit_sdr\s*\(' AND p.proname <> 'ottoq_emit_sdr'
UNION ALL
SELECT 'the confirm walk names a leg', (p.prosrc ~ '(itinerary_legs|leg_id|itin_)')::text || ' (' || length(p.prosrc) || ' characters)'
  FROM pg_proc p WHERE p.oid = 'twin.ottoq_sim_confirm_commands(uuid,timestamp with time zone)'::regprocedure;

-- (4) The bookings that covered bay seats, by door: how many carried a leg, and how those legs ended.
WITH runs AS (SELECT sim_run_id FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND tick_count >= 144
                 AND started_at >= '2026-10-16 00:00+00' AND started_at < '2026-10-18 03:50+00')
SELECT b.purpose, b.source, count(*) AS bookings, count(b.leg_id) AS with_leg,
       string_agg(DISTINCT l.status, ',') AS leg_statuses
  FROM ottoq_stall_bookings b LEFT JOIN ottoq_itinerary_legs l ON l.leg_id = b.leg_id
 WHERE b.sim_run_id IN (SELECT sim_run_id FROM runs) AND b.purpose IN ('wash','detail','service')
 GROUP BY 1, 2 ORDER BY 1, 3 DESC;

-- (5) The coverage census's two starting points.
SELECT pg_get_functiondef('public.ottoq_check_sdr_coverage(uuid)'::regprocedure) ~ 'l\.status = ''done''' AS starts_from_done_legs;

-- (6) amend_plan decisions, and those made while the car carried a bay leg skipped later whose work was already done.
WITH runs AS (SELECT sim_run_id FROM ottoq_sim_runs
               WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND tick_count >= 144
                 AND started_at >= '2026-10-16 00:00+00' AND started_at < '2026-10-18 03:50+00'),
phantom AS (
  SELECT l.sim_run_id, l.vehicle_id, (x->>'done_at')::timestamptz AS done_at
    FROM ottoq_itinerary_legs l JOIN ottoq_vehicle_itineraries i USING (itinerary_id)
    JOIN ottoq_visit_needs vn ON vn.visit_id = i.visit_id
    CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) x
   WHERE l.sim_run_id IN (SELECT sim_run_id FROM runs) AND l.leg_type IN ('wash','detail','service')
     AND l.status = 'skipped' AND x->>'svc' = l.duration_basis->>'atom' AND x->>'status' = 'done'),
am AS (
  SELECT d.sim_run_id, d.entity_id AS vehicle_id, d.sim_clock
    FROM ottoq_decisions d
   WHERE d.sim_run_id IN (SELECT sim_run_id FROM runs) AND d.resolved_action_context = 'itinerary_amended')
SELECT count(*) AS amend_plan_decisions,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM phantom p WHERE p.sim_run_id = am.sim_run_id
                                         AND p.vehicle_id = am.vehicle_id AND p.done_at <= am.sim_clock)) AS with_a_phantom_bay_leg,
       count(DISTINCT am.vehicle_id::text || am.sim_run_id::text) AS car_runs
  FROM am;
