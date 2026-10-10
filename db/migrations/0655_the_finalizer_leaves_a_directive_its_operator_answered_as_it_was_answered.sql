-- migration-version: PENDING
-- migration-name:    the_finalizer_leaves_a_directive_its_operator_answered_as_it_was_answered
--
-- 0655  **The run finalizer no longer expires a directive its operator accepted through the v2 door.** Found while
--        preparing 0654's paired measurement (db/checks/0431), before any run had the flag on.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0087 made public.ottoq_sim_release_depot leave no command dangling when a run ends: every command still 'issued'
--   or 'confirmed' becomes 'expired' with reason_code 'run_ended', confirmed_by 'run_finalizer' and confirmed_at now()
--   (wall time). In the old dock 'confirmed' is a state between: an OEM acknowledged the command through
--   ottoq_ack_vehicle_command and 'executed' was still to come, so at the end of a run it was dangling.
--
--   Through the v2 door it is the answer. ottoq.ottoq_v2_apply (0650) turns an accepted ack into status 'confirmed',
--   confirmed_by 'operator:<name>', confirmed_at the ack's clock, and the contract has no later "executed" ack: what
--   the operator then does is observed (telemetry, arrival, the charger), not acknowledged again. With
--   twin_operator_door on, the twin's operators accept every directive the world carried out, so at the end of every
--   run the finalizer would rewrite all of them as directives nobody answered:
--     - who answered (operator:sim-a, operator:sim-b) and when, replaced by run_finalizer and a wall-clock time;
--     - public.ottoq_assert_operator_isolation, run after the run, would read each of those rows as a directive its
--       operator answered and the engine recorded under another name;
--     - the command atom re-derived from the archive would no longer match the one a pair computed before its stop
--       (h_cmd digests status and reason_code), the class db/checks/0329 named: a verdict its own evidence cannot
--       recompute.
--   ottoq_production_stop calls the same finalizer, so a real operator's accepted directives would go the same way.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_sim_release_depot, patched at one anchor between md5s of the live definition
--   (f49f39094967b722093046f048c3934f before, dd32bb96cb341205a783f246ae6189d1 after): its command expiry skips a
--   command whose status is 'confirmed' and whose confirmed_by begins 'operator:'. ottoq.ottoq_v2_apply is the only
--   function that writes that name onto a command. Everything else the finalizer does is unchanged, and an 'issued'
--   command, or one the old dock confirmed, expires as before.
--
-- ══ §3 WHAT IT DOES NOT CHANGE; forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════
--
--   No command has ever been confirmed by an 'operator:' name outside a rolled-back probe (P1 asserts 0 rows), and
--   twin_operator_door is set nowhere, so every release so far, and every release until the flag is set, expires
--   exactly the rows it expired before.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0655_pre'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0655 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0654_the_walk_reports_to_the_twin_and_the_ticks_let_its_operators_answer_first') THEN
    RAISE EXCEPTION '0655 P1: 0654 is not classified; apply in order';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands WHERE confirmed_by LIKE 'operator:%') THEN
    RAISE EXCEPTION '0655 P1: a command is already confirmed by an operator: name; this file assumes none is';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_operator_door') THEN
    RAISE EXCEPTION '0655 P1: twin_operator_door is set somewhere; this file assumes it is 0 everywhere';
  END IF;
END $premises$;

-- ── snapshot: the definition as it stood ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0655_pre', 'function', 'public', 'ottoq_sim_release_depot(uuid,text)', d.def, md5(d.def)
  FROM (SELECT pg_get_functiondef('public.ottoq_sim_release_depot(uuid,text)'::regprocedure) AS def) d;

-- ── the finalizer leaves an answered directive answered ──
DO $p_release$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_sim_release_depot(uuid,text)'::regprocedure);
  a text[] := ARRAY[$a01$         payload = COALESCE(payload,'{}'::jsonb) || jsonb_build_object('expired_reason','run_ended_before_reaction')
   WHERE sim_run_id = p_sim_run_id AND status IN ('issued','confirmed');
$a01$];
  b text[] := ARRAY[$b01$         payload = COALESCE(payload,'{}'::jsonb) || jsonb_build_object('expired_reason','run_ended_before_reaction')
   WHERE sim_run_id = p_sim_run_id AND status IN ('issued','confirmed')
     -- 0655: a directive its operator accepted through the v2 door (0650: 'confirmed', confirmed_by 'operator:<name>')
     -- was answered, not left dangling, and keeps the answer, the operator's name and the time it was given.
     AND NOT (status = 'confirmed' AND COALESCE(confirmed_by, '') LIKE 'operator:%');
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'f49f39094967b722093046f048c3934f' THEN
    RAISE EXCEPTION '0655: the finalizer is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0655: anchor % of the finalizer occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'dd32bb96cb341205a783f246ae6189d1' THEN
    RAISE EXCEPTION '0655: the finalizer, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('public.ottoq_sim_release_depot(uuid,text)'::regprocedure)) <> 'dd32bb96cb341205a783f246ae6189d1' THEN
    RAISE EXCEPTION '0655: the finalizer did not read back as written';
  END IF;
END $p_release$;

-- ── V1: on the live finalizer, the twin depot's newest run, in a sub-block that rolls back ──
DO $v1$
DECLARE
  v_msg text; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_veh uuid[]; v_stall uuid; v_rel jsonb;
  c_issued uuid; c_dock uuid; c_door uuid; r_issued text; r_dock text; r_door text;
BEGIN
  SELECT sim_run_id, COALESCE(sim_clock_current, started_at) INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = v_twin AND COALESCE(run_by, '') <> 'production_live' AND status <> 'running'
   ORDER BY started_at DESC LIMIT 1;
  SELECT array_agg(id ORDER BY display_name) INTO v_veh
    FROM (SELECT id, display_name FROM public.vehicles
           WHERE home_depot_id = v_twin AND fleet_operator_id IS NOT NULL ORDER BY display_name LIMIT 3) s;
  SELECT id INTO v_stall FROM public.stalls WHERE depot_id = v_twin AND stall_type = 'staging' ORDER BY stall_code LIMIT 1;
  IF v_run IS NULL OR COALESCE(cardinality(v_veh), 0) < 3 OR v_stall IS NULL THEN
    RAISE EXCEPTION '0655 V1: no stopped twin run, three fleet cars or a staging stall to probe with';
  END IF;

  BEGIN
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_veh[1], 'hold', jsonb_build_object('stall_id', v_stall), v_clock, '0655_v1_probe') RETURNING command_id INTO c_issued;
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_veh[2], 'hold', jsonb_build_object('stall_id', v_stall), v_clock, '0655_v1_probe') RETURNING command_id INTO c_dock;
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_veh[3], 'hold', jsonb_build_object('stall_id', v_stall), v_clock, '0655_v1_probe') RETURNING command_id INTO c_door;
    -- the old dock's in-between state, and the v2 door's answer
    UPDATE public.ottoq_vehicle_commands SET status = 'confirmed', confirmed_at = v_clock, confirmed_by = 'oem_fleet'
     WHERE command_id = c_dock;
    UPDATE public.ottoq_vehicle_commands SET status = 'confirmed', confirmed_at = v_clock, confirmed_by = 'operator:sim-a'
     WHERE command_id = c_door;
    v_rel := public.ottoq_sim_release_depot(v_run, '0655_v1_probe');
    SELECT status || '|' || COALESCE(reason_code, '-') || '|' || COALESCE(confirmed_by, '-') || '|' || (confirmed_at = v_clock)
      INTO r_issued FROM public.ottoq_vehicle_commands WHERE command_id = c_issued;
    SELECT status || '|' || COALESCE(reason_code, '-') || '|' || COALESCE(confirmed_by, '-') || '|' || (confirmed_at = v_clock)
      INTO r_dock FROM public.ottoq_vehicle_commands WHERE command_id = c_dock;
    SELECT status || '|' || COALESCE(reason_code, '-') || '|' || COALESCE(confirmed_by, '-') || '|' || (confirmed_at = v_clock)
      INTO r_door FROM public.ottoq_vehicle_commands WHERE command_id = c_door;
    RAISE EXCEPTION '0655 V1 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0655 V1 PROBED' THEN RAISE EXCEPTION '0655 V1: the probe itself failed: %', v_msg; END IF;

  IF NOT COALESCE((v_rel ->> 'ok')::boolean, false) THEN RAISE EXCEPTION '0655 V1 FAILED: the finalizer: %', v_rel; END IF;
  IF r_issued IS DISTINCT FROM 'expired|run_ended|run_finalizer|false' THEN
    RAISE EXCEPTION '0655 V1 FAILED: an unanswered command did not expire as before: %', r_issued;
  END IF;
  IF r_dock IS DISTINCT FROM 'expired|run_ended|run_finalizer|false' THEN
    RAISE EXCEPTION '0655 V1 FAILED: the old dock''s confirmed command did not expire as before: %', r_dock;
  END IF;
  IF r_door IS DISTINCT FROM 'confirmed|-|operator:sim-a|true' THEN
    RAISE EXCEPTION '0655 V1 FAILED: the operator''s answer did not survive the finalizer: %', r_door;
  END IF;
  RAISE NOTICE '0655 V1 PASSED on run %: unanswered %, old dock %, operator %; all rolled back', v_run, r_issued, r_dock, r_door;
END $v1$;

-- ── V2: the definition as written, and nothing left behind ──
DO $v2$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_sim_release_depot(uuid,text)'::regprocedure)) <> 'dd32bb96cb341205a783f246ae6189d1' THEN
    RAISE EXCEPTION '0655 V2 FAILED: the finalizer is not as written';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_vehicle_commands WHERE issued_by = '0655_v1_probe' OR confirmed_by LIKE 'operator:%') THEN
    RAISE EXCEPTION '0655 V2 FAILED: a probe command outlived its rollback';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0655_the_finalizer_leaves_a_directive_its_operator_answered_as_it_was_answered', false, false,
  'ottoq_sim_release_depot no longer expires a command confirmed by an operator: name (an accepted ack through the v2 '
  'door, 0650); unanswered commands and the old dock''s confirmed ones expire as before. No command has ever been '
  'confirmed by an operator: name and twin_operator_door is set nowhere, so every release is as before. FALSE/FALSE.',
  now());

COMMIT;
