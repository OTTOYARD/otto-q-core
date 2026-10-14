-- migration-version: PENDING
-- migration-name:    a_car_with_maintenance_or_calibration_due_gets_it_before_it_leaves
--
-- 0715  **A car with preventive maintenance or calibration due gets it before it leaves.** CLAUDE.md rule 9 (Chase,
--        2026-09-27, 8 PM CT) names preventive maintenance and sensor calibration among the services "finished before
--        the car leaves". The visit planner adds those atoms only when the twin's observer happens to draw them, so a car
--        the recall policy called home BECAUSE its interval was due could get a visit with neither, pass the departure
--        test (which reads the visit's atoms), and leave with the interval still due. G218 / G181; the study's VF-1;
--        measured by 0704's scouts on two runs today (db/checks/0440 §13).
--
--        NOT APPLIED. It forces recertification, and on the twin's busy_day scenario, whose intervals are compressed
--        about a hundredfold, it makes the two service bays the depot's wall. Applying it is Chase's decision, beside the
--        scenario's intervals (§4).
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   ottoq_recall_naive_threshold_v1 recalls a deployed car as `service_interval_due` when
--     drive_km_total - km_at_last_pm >= pm_interval_km (the car's config, else the run's dial, else 8000), or
--     drive_hours_total - hours_at_last_calibration >= calib_interval_h (else 250).
--   ottoq.ottoq_derive_visit_needs adds `mechanical_pm` / `sensor_calibration` only when p_obs says so, and the twin
--   observer draws an overdue PM at 0.30 and an overdue calibration at 0.24 (the study, lane on vehicle-first). 0448's
--   block, written to make those atoms required on a recall's visit, keys on the trigger 'service_interval_overdue',
--   which only recall implementation 3 emitted, retired by 0542: it has never fired since. ottoq_departure_clear reads
--   the visit's atoms and the charge; it never reads wear.
--
--   Measured 2026-10-13 by the scout interval_due_departure (a departure after a service_interval_due recall with no PM
--   or calibration done since): run 176b2912, 3 departures (Tesla-AV-070, Waymo-AV-021, Zoox-AV-100); run 57188f55, 5
--   by tick 213. Read by hand for Tesla-AV-070 on 57188f55: recalled for service_interval_due, its visit (arrived
--   13:31:47 sim) carried charge, interior_deep_clean, interior_inspection, readiness_check, sensor_clean, triage_check
--   -- no PM, no calibration -- and it left at 14:40:24 with them still due.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   ottoq.ottoq_derive_visit_needs (md5 cd5c513b), by SUBSTITUTION, two anchors each asserted to occur exactly once:
--     a. two booleans declared;
--     b. 0448's dead block is replaced. The planner asks the recall's own question of the wear it has already read
--        (v_wear.km_since_pm, v_wear.h_since_calib against the car's pm_interval_km / calib_interval_h, else the run's
--        dials, else 8000 / 250), and for each interval due:
--          - adds the atom if the observer did not draw it, in the shape the observer's atom has (service bay,
--            v_pm_min / v_calib_min; calibration after any wash), tagged interval_due;
--          - makes it required on this visit: must_do true, deferrable false, carryover_eligible false.
--   Whatever brought the car in. A car whose interval falls due between recalls is as owed as one recalled for it.
--
--   Not changed, on purpose: ottoq_departure_clear. Once the atom is on the visit, its existing atom test holds the car
--   until the bay work is done, and the bay flow (twin.ottoq_sim_advance_service_flow / ottoq_ingest_service_complete)
--   calls ottoq_wear_mark_serviced, which resets the counter. A wear clause in the departure test would refuse a car
--   whose visit lacks the atom, with nothing scheduled to make it clear: a car stranded forever is not rule 9's
--   re-orchestration either. The scout keeps watching for any departure this misses.
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═════════════════════════════════════════════════════════════════
--
--   Every OTTO-Q run's visits change for every car with an interval due, and its departures with them.
--
-- ══ §4 WHAT APPLYING IT DOES TO THE TWIN, MEASURED, AND THE DECISION BESIDE IT ══════════════════════════════════════
--
--   busy_day sets pm_interval_km per car (ottoq_scenario_apply_fleet_overrides) at a median of 78 km against the need
--   profile's 6,500-9,500 km, and calib_interval_h at a median 4.85 h: compressed about a hundredfold, on purpose, to
--   exercise the service path (G181). On run 57188f55 at 4:54 PM sim, 71 of the twin depot's 116 cars had one due (67
--   PM, 18 calibration). On run 176b2912 the two service bays finished 14 PM and 4 calibrations in 9 sim-hours. With
--   this file, every due car gets the work, and two bays at 40-60 minutes a job cannot clear seventy cars a shift: the
--   twin's busy_day becomes service-bay bound. That is rule 9 reporting a capacity finding, as it should; but the
--   finding is about a compressed scenario, not the depot.
--
--   So the decision is the scenario's, not this file's: apply this with realistic intervals (a research-wing world
--   change, recorded in ottoq_evidence_regimes), or with the compression kept and the bay wall accepted as the stress
--   test it is.
--
-- ══ §5 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the ottoq_derive_visit_needs definition snapshotted under label '0715_pre'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0715 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'::regprocedure))
     IS DISTINCT FROM 'cd5c513bb164a14614003e308009a347' THEN
    RAISE EXCEPTION '0715 P1: ottoq_derive_visit_needs is not the definition this file was written against';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0715_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_derive_visit_needs';

DO $derive$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'::regprocedure);
  v_old_decl constant text := E'  v_rf_place boolean := false; v_rf_retire boolean := false;\n';
  v_new_decl constant text := E'  v_rf_place boolean := false; v_rf_retire boolean := false;\n'
                           || E'  v_pm_due boolean := false; v_calib_due boolean := false;   --: 0715\n';
  v_old_block constant text :=
       E'  /* 0448 (G181): a vehicle recalled because its interval maintenance was hard-overdue gets that maintenance on\n'
    || E'     this visit -- the recall''s service bundle (CLAUDE.md 2.7), exactly as 0018/0019 made a rider-flag\n'
    || E'     recall''s cleaning must_do. Only interval_scheduled_v1 emits this trigger; naive_threshold_v1 never does. */\n'
    || E'  IF (SELECT d.return_trigger FROM public.ottoq_vehicle_dispatches d\n'
    || E'       WHERE d.vehicle_id = p_vehicle_id AND d.sim_run_id = v_run\n'
    || E'       ORDER BY d.dispatched_at DESC, d.dispatch_id LIMIT 1) = ''service_interval_overdue''\n'
    || E'     AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>''svc'' IN (''mechanical_pm'',''sensor_calibration'')) THEN\n'
    || E'    SELECT jsonb_agg(CASE WHEN a->>''svc'' IN (''mechanical_pm'',''sensor_calibration'')\n'
    || E'                          THEN a || jsonb_build_object(''must_do'', true, ''deferrable'', false,\n'
    || E'                                 ''carryover_eligible'', false, ''return_trigger'', ''service_interval_overdue'')\n'
    || E'                          ELSE a END ORDER BY o)\n'
    || E'      INTO v_m FROM jsonb_array_elements(v_m) WITH ORDINALITY AS t(a, o);\n'
    || E'  END IF;\n';
  v_new_block constant text :=
       E'  /* 0715 (G218, CLAUDE.md rule 9): preventive maintenance and calibration are finished before a car leaves. An\n'
    || E'     interval that is due puts its work on this visit, required, whatever the observer drew and whatever brought\n'
    || E'     the car in. The due test is the recall''s own (ottoq_recall_naive_threshold_v1) on the wear read above. It\n'
    || E'     replaces 0448''s block, which keyed on a trigger (service_interval_overdue) no live recall emits since 0542. */\n'
    || E'  v_pm_due    := COALESCE(v_wear.km_since_pm, 0)\n'
    || E'                 >= COALESCE(v_pm_int, public.ottoq_policy_get(COALESCE(p_sim_run_id, v_run), ''pm_interval_km'', 8000));\n'
    || E'  v_calib_due := COALESCE(v_wear.h_since_calib, 0)\n'
    || E'                 >= COALESCE(v_calib_int, public.ottoq_policy_get(COALESCE(p_sim_run_id, v_run), ''calib_interval_h'', 250));\n'
    || E'  IF v_calib_due AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>''svc'' = ''sensor_calibration'') THEN\n'
    || E'    v_m := v_m || jsonb_build_object(''svc'',''sensor_calibration'',''must_do'',true,''deferrable'',false,\n'
    || E'      ''est_min'',v_calib_min,''slot'',''dedicated_service'',''concurrency'',''bay'',''requires_bay'',''service_bay'',\n'
    || E'      ''predecessors'',jsonb_build_array(''exterior_wash''),''carryover_eligible'',false);\n'
    || E'  END IF;\n'
    || E'  IF v_pm_due AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>''svc'' = ''mechanical_pm'') THEN\n'
    || E'    v_m := v_m || jsonb_build_object(''svc'',''mechanical_pm'',''must_do'',true,''deferrable'',false,\n'
    || E'      ''est_min'',v_pm_min,''concurrency'',''bay'',''requires_bay'',''service_bay'',''carryover_eligible'',false);\n'
    || E'  END IF;\n'
    || E'  IF v_pm_due OR v_calib_due THEN\n'
    || E'    SELECT jsonb_agg(CASE WHEN (a->>''svc'' = ''mechanical_pm'' AND v_pm_due)\n'
    || E'                            OR (a->>''svc'' = ''sensor_calibration'' AND v_calib_due)\n'
    || E'                          THEN a || jsonb_build_object(''must_do'', true, ''deferrable'', false,\n'
    || E'                                 ''carryover_eligible'', false, ''interval_due'', true)\n'
    || E'                          ELSE a END ORDER BY o)\n'
    || E'      INTO v_m FROM jsonb_array_elements(v_m) WITH ORDINALITY AS t(a, o);\n'
    || E'  END IF;\n';
  v_n int; v_m int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, v_old_decl, ''))) / length(v_old_decl);
  v_m := (length(v_def) - length(replace(v_def, v_old_block, ''))) / length(v_old_block);
  IF v_n <> 1 OR v_m <> 1 THEN
    RAISE EXCEPTION '0715: anchors found % and % times in ottoq_derive_visit_needs, expected exactly 1 each', v_n, v_m;
  END IF;
  EXECUTE replace(replace(v_def, v_old_decl, v_new_decl), v_old_block, v_new_block);
END $derive$;

DO $v$
DECLARE v_def text := pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'::regprocedure);
BEGIN
  IF strpos(v_def, 'v_pm_due    := COALESCE(v_wear.km_since_pm, 0)') = 0
     OR strpos(v_def, '''service_interval_overdue''') > 0 THEN
    RAISE EXCEPTION '0715 V1 FAILED: the planner does not ask the interval question, or 0448''s dead block remains';
  END IF;
  RAISE NOTICE '0715 V1 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0715_a_car_with_maintenance_or_calibration_due_gets_it_before_it_leaves', true, true,
  'G218 / G181, rule 9: a due PM or calibration interval puts its work on the visit, required, whatever the observer '
  'drew (0448''s block keyed on a trigger no live recall emits). Every OTTO-Q run''s visits and departures change for '
  'cars with an interval due: TRUE/TRUE. On busy_day''s compressed intervals the two service bays become the wall '
  '(db/checks/0440 §13).',
  now());

COMMIT;
