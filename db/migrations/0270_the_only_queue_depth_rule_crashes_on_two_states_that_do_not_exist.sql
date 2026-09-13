-- migration-version: PENDING
-- migration-name:    0270_the_only_queue_depth_rule_crashes_on_two_states_that_do_not_exist
--
-- 0270  THE ONLY QUEUE-DEPTH RULE CRASHES ON TWO STATES THAT DO NOT EXIST
--
-- ---------------------------------------------------------------------------
-- THE DEFECT, DEMONSTRATED BEFORE IT WAS FIXED
--
-- SLA.002.max_queue_depth is the engine's only queue-depth rule: active, v2,
-- severity warning, scope fleet_operator, applies_to_actions {arrival,
-- queue_admission}. Its evaluator counts the waiting population like this:
--
--     EXECUTE 'SELECT count(*) FROM vehicles
--               WHERE fleet_operator_id = $1
--                 AND current_state IN (''queued'', ''waiting_assignment'')'
--       INTO v_current USING v_fleet_op_id;
--     EXCEPTION WHEN undefined_column THEN v_current := 0;
--
-- vehicles.current_state is the ENUM vehicle_state. Its seventeen labels are:
--   offline, deployed, en_route_to_depot, arrived_at_gate,
--   staged_awaiting_service, charging_dcfc, charging_l2,
--   charge_complete_holding, in_wash_bay, in_detail_bay, in_service_bay,
--   service_complete_holding, staged_for_departure, en_route_to_deployment,
--   emergency_staged, tow_requested, out_of_service
--
-- Neither 'queued' nor 'waiting_assignment' is among them. Postgres casts the
-- literal to the enum and raises 22P02 -- and the handler catches only
-- undefined_column, so it propagates. Measured, not inferred:
--
--   SELECT ottoq_eval_sla_002_max_queue_depth('vehicle', gen_random_uuid(),
--            jsonb_build_object('fleet_operator_id', <real>, 'depot_id', <real>),
--            '{}'::jsonb);
--   -> RAISED 22P02: invalid input value for enum vehicle_state: "queued"
--
-- WHY NOBODY NOTICED. Nothing calls it. Measured at apply time: 0 functions in
-- public/ottoq/twin reference the evaluator, 0 functions mention the
-- queue_admission probe point, and ottoq_rule_evaluations holds 0 rows for
-- SLA.002.max_queue_depth over its entire life. A rule that has never been
-- invoked cannot fail visibly, so a rule that would ALWAYS fail looks exactly
-- like a rule that works. It read as coverage in every count of the shield.
--
-- ---------------------------------------------------------------------------
-- A SECOND DEFECT IN THE SAME FUNCTION, AND IT WOULD HAVE SURVIVED THE FIRST FIX
--
-- The evaluator takes depot_id from the context, RAISES IF IT IS NULL -- and then
-- never uses it. The count is per fleet operator across every depot. A
-- depot-scoped queue-depth rule that answers with the operator's global backlog
-- is wrong in the direction that matters: it would warn at a quiet depot because
-- a different one is busy. Fixing only the enum labels would have left this in
-- place and looked complete. A4 below exists to catch exactly that.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS FILE DOES AND DELIBERATELY DOES NOT DO
--
-- DOES: make the rule correct and runnable -- real enum labels, depot scoping,
-- static SQL instead of a dynamic string (which is what let a type error hide as
-- a runtime surprise), and NULLIF on the p_parameters cast, which is the same
-- 22P02 class one line up: (p_parameters->>'max_depth')::INTEGER raises on an
-- empty string just as surely as 'queued' does on the enum.
--
-- DOES NOT: make the rule INVOKED. arrival and queue_admission are not among the
-- four probe points the shield actually gates (task_start, stall_assignment,
-- redeployment, bess_dispatch -- CLAUDE.md 2.5's correction, G44). Wiring a probe
-- point is a change to the decide path and forces a recertification round; this
-- does not. After this file the rule is correct and still uncalled, which is an
-- honest improvement over incorrect and uncalled, and it is the precondition for
-- the probe point rather than a substitute for it.
--
-- forces_recert: FALSE, and provable rather than asserted -- 0 callers, 0
-- evaluations ever. Nothing an arm produces can differ, because nothing an arm
-- does reaches this function.
-- ---------------------------------------------------------------------------

DO $p$
DECLARE v_busy int; v_jobs int; v_live int;
BEGIN
  SELECT count(*) INTO v_busy FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_sim_advance_tick%'
          OR query ILIKE '%ottoq_ab_pair%');
  IF v_busy > 0 THEN
    RAISE EXCEPTION '0270 P1: % certification/pair call(s) in flight', v_busy;
  END IF;
  SELECT count(*) INTO v_jobs FROM cron.job
   WHERE (jobname ~ '^r[0-9]+_')
      OR (active AND (command ILIKE '%ottoq_determinism_pair%'
                      OR command ILIKE '%ottoq_cert_battery_step%'));
  IF v_jobs > 0 THEN
    RAISE EXCEPTION '0270 P2: % certification job(s) still scheduled', v_jobs;
  END IF;
  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_live > 0 THEN
    RAISE EXCEPTION '0270 P3: % run(s) running or paused', v_live;
  END IF;
END $p$;

-- ---------------------------------------------------------------------------
-- G. THE PRE-IMAGE, PINNED. Absence check first, so re-running this file after
--    it is applied gets the message written for that case (the 0269 lesson).
-- ---------------------------------------------------------------------------
DO $g$
DECLARE v_src text; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_eval_sla_002_max_queue_depth';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0270 G1: expected exactly 1 evaluator, found %', v_n;
  END IF;

  SELECT p.prosrc INTO STRICT v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_eval_sla_002_max_queue_depth';

  IF position('current_depot_id' in v_src) > 0 THEN
    RAISE EXCEPTION '0270 G2: the evaluator is already depot-scoped; this file installs that';
  END IF;

  IF md5(v_src) <> 'c17ac1c04db6cb23b1f686754b175b5d' THEN
    RAISE EXCEPTION '0270 G3: prosrc md5 is %, expected c17ac1c04db6cb23b1f686754b175b5d -- the body moved', md5(v_src);
  END IF;

  -- The defect must actually be present, or there is nothing here to fix.
  IF position('''queued''' in v_src) = 0 THEN
    RAISE EXCEPTION '0270 G4: the dead literal is not in the body; re-derive this file';
  END IF;
END $g$;

-- ---------------------------------------------------------------------------
-- S. PRE-IMAGE SNAPSHOT.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0270-pre', 'function', 'public',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_eval_sla_002_max_queue_depth';

-- ---------------------------------------------------------------------------
-- 1. THE REPLACEMENT.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_eval_sla_002_max_queue_depth(
  p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_fleet_op_id  UUID;
  v_depot_id     UUID;
  v_sla          ottoq_fleet_operator_slas;
  v_max_depth    INTEGER;
  v_current      INTEGER;
BEGIN
  v_fleet_op_id := NULLIF(p_context ->> 'fleet_operator_id','')::UUID;
  v_depot_id    := NULLIF(p_context ->> 'depot_id','')::UUID;

  IF v_fleet_op_id IS NULL OR v_depot_id IS NULL THEN
    RETURN ROW(TRUE, 'missing fleet_operator/depot context', NULL, '{}'::jsonb, NULL)::ottoq_rule_result;
  END IF;

  v_sla := ottoq_get_active_sla(v_fleet_op_id);

  -- 0270: NULLIF before the cast. ''::INTEGER raises 22P02 exactly the way the
  -- enum literal did; the catalog ships this rule with default_parameters '{}',
  -- so this path is the common one, not the exotic one.
  v_max_depth := COALESCE(
    NULLIF(p_parameters ->> 'max_depth','')::INTEGER,
    v_sla.max_queue_depth,
    50
  );

  -- 0270: static SQL over the REAL vehicle_state labels, scoped to the depot the
  -- context names. Was: dynamic SQL over 'queued'/'waiting_assignment', which are
  -- not labels of this enum, with depot_id validated and then ignored.
  -- "Waiting" here means present at the depot and not yet in a service point:
  -- arrived_at_gate (through the gate, unassigned) and staged_awaiting_service
  -- (holding a staging stall, waiting for a bay or charger).
  SELECT count(*) INTO v_current
    FROM public.vehicles v
   WHERE v.fleet_operator_id = v_fleet_op_id
     AND v.current_depot_id  = v_depot_id
     AND v.current_state IN ('arrived_at_gate', 'staged_awaiting_service');

  IF v_current >= v_max_depth THEN
    RETURN ROW(FALSE,
      format('queue depth %s >= SLA max %s', v_current, v_max_depth),
      'warning',
      jsonb_build_object('current', v_current, 'max', v_max_depth,
                         'fleet_operator_id', v_fleet_op_id,
                         'depot_id', v_depot_id),
      'defer_new_arrivals_or_scale_capacity'
    )::ottoq_rule_result;
  END IF;

  RETURN ROW(TRUE,
    format('queue depth %s of %s allowed', v_current, v_max_depth),
    NULL,
    jsonb_build_object('current', v_current, 'max', v_max_depth,
                       'depot_id', v_depot_id),
    NULL
  )::ottoq_rule_result;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 2. CLASSIFICATION, before the assertions (0267's lesson: an assertion that
--    calls live code can fail for unrelated reasons, and a non-atomic apply that
--    dies there must not leave the change unclassified).
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0270_the_only_queue_depth_rule_crashes_on_two_states_that_do_not_exist', false,
        'SLA.002.max_queue_depth, the engine''s only queue-depth rule, raised 22P02 on every call: its evaluator compared the vehicle_state ENUM to ''queued'' and ''waiting_assignment'', neither of which is a label of that enum, and its only exception handler caught undefined_column. Proven live before the fix. Second defect fixed in the same pass: depot_id was validated non-null and then never used, so a depot-scoped rule counted the operator''s global backlog. Also NULLIF before the max_depth cast, same 22P02 class. Non-forcing, and provable rather than asserted: at apply time 0 functions referenced the evaluator, 0 functions mentioned the queue_admission probe point, and ottoq_rule_evaluations held 0 rows for this rule over its entire life -- nothing an arm does reaches this function. This makes the rule CORRECT; it does not make it INVOKED, because arrival/queue_admission are not among the four probe points the shield gates (G44). Wiring one is a decide-path change and forces recert; this is its precondition.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ---------------------------------------------------------------------------
-- 3. ASSERTIONS. A2 is the discriminating one: it RAISES before this file and
--    passes after. A4 is the one that would have caught a half-fix.
-- ---------------------------------------------------------------------------
DO $a$
DECLARE
  v_src text; v_fo uuid; v_busy_dep uuid; v_quiet_dep uuid;
  v_res public.ottoq_rule_result; v_expect int; v_busy_n int; v_quiet_n int;
BEGIN
  SELECT p.prosrc INTO STRICT v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_eval_sla_002_max_queue_depth';

  --: A1. THE DEAD LITERALS ARE GONE and the real ones are present.
  IF position('''queued''' in v_src) > 0 OR position('waiting_assignment' in v_src) > 0 THEN
    RAISE EXCEPTION '0270 A1: a non-existent vehicle_state label is still in the body';
  END IF;
  IF position('arrived_at_gate' in v_src) = 0
     OR position('staged_awaiting_service' in v_src) = 0 THEN
    RAISE EXCEPTION '0270 A1: the real waiting-state labels are not in the body';
  END IF;

  -- Pick a fleet operator and the depot that actually has a queue right now.
  SELECT v.fleet_operator_id, v.current_depot_id
    INTO v_fo, v_busy_dep
    FROM public.vehicles v
   WHERE v.current_state IN ('arrived_at_gate','staged_awaiting_service')
     AND v.fleet_operator_id IS NOT NULL AND v.current_depot_id IS NOT NULL
   ORDER BY v.id
   LIMIT 1;
  IF v_fo IS NULL THEN
    RAISE EXCEPTION '0270 A2: no waiting vehicle exists to test against; re-derive this file';
  END IF;

  --: A2. THE DISCRIMINATOR -- it RETURNS instead of raising 22P02.
  --:     This is the whole point of the file and it fails before it.
  v_res := public.ottoq_eval_sla_002_max_queue_depth(
             'vehicle', gen_random_uuid(),
             jsonb_build_object('fleet_operator_id', v_fo, 'depot_id', v_busy_dep),
             '{}'::jsonb);

  --: A3. AND IT COUNTS THE RIGHT THING. The number it reports must equal the
  --:     count computed independently here -- not merely be a number.
  SELECT count(*) INTO v_expect
    FROM public.vehicles v
   WHERE v.fleet_operator_id = v_fo
     AND v.current_depot_id  = v_busy_dep
     AND v.current_state IN ('arrived_at_gate','staged_awaiting_service');
  v_busy_n := (v_res.payload ->> 'current')::int;
  IF v_busy_n IS DISTINCT FROM v_expect THEN
    RAISE EXCEPTION '0270 A3: evaluator reported % waiting, independent count says %',
                    v_busy_n, v_expect;
  END IF;

  --: A4. AND THE DEPOT SCOPING ACTUALLY BITES. Ask the SAME operator about a
  --:     depot where it has nobody waiting; the answer must differ. Without this,
  --:     a fix that corrected the enum labels and still ignored depot_id would
  --:     pass A1, A2 and A3 -- which is exactly the half-fix worth catching.
  SELECT d.id INTO v_quiet_dep
    FROM public.depots d
   WHERE d.id <> v_busy_dep
     AND NOT EXISTS (SELECT 1 FROM public.vehicles v
                      WHERE v.current_depot_id = d.id
                        AND v.fleet_operator_id = v_fo
                        AND v.current_state IN ('arrived_at_gate','staged_awaiting_service'))
   ORDER BY d.id
   LIMIT 1;

  IF v_quiet_dep IS NULL THEN
    RAISE WARNING '0270 A4: no quiet depot available for this operator; scoping not exercised';
  ELSE
    v_res := public.ottoq_eval_sla_002_max_queue_depth(
               'vehicle', gen_random_uuid(),
               jsonb_build_object('fleet_operator_id', v_fo, 'depot_id', v_quiet_dep),
               '{}'::jsonb);
    v_quiet_n := (v_res.payload ->> 'current')::int;
    IF v_quiet_n <> 0 THEN
      RAISE EXCEPTION '0270 A4: quiet depot reports % waiting, expected 0 -- depot scoping is not applied', v_quiet_n;
    END IF;
    IF v_busy_n = 0 THEN
      RAISE EXCEPTION '0270 A4: busy depot also reported 0; the two cases are indistinguishable and prove nothing';
    END IF;
  END IF;

  RAISE NOTICE '0270: A1-A4 passed; the rule runs (busy depot % waiting, quiet depot %), counts correctly, and is depot-scoped',
               v_busy_n, coalesce(v_quiet_n, -1);
END $a$;

-- ---------------------------------------------------------------------------
-- APPLY LOG
-- (not yet applied)
-- ---------------------------------------------------------------------------
