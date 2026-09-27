-- migration-version: 20260923012530
-- migration-name:    the_readiness_check_had_a_second_door_out_of_the_depot_and_0431_only_guarded_one
--
-- 0437  **A vehicle could still leave without its readiness check through a second door: 0431 held vehicles
--       staged for departure until the check was done, and the dispatcher also releases vehicles parked in
--       staging with their services marked ready, where the check is never performed.** FINDINGS G170 (0431's
--       predicted residual).
--
-- ══ §1 WHAT IS WRONG ═════════════════════════════════════════════════════════
--
--   `ottoq.ottoq_plan_dispatch_tick('deploy_plan')` admits four states as departure candidates:
--   `en_route_to_deployment`, `staged_for_departure`, `offline`, and
--   `staged_awaiting_service` with `config->>'svc_step' = 'ready'`. Its "no open must-do" clause exempts
--   `readiness_check`, because the check is performed IN `staged_for_departure`. `0431` then holds
--   `staged_for_departure` vehicles one tick until `twin.ottoq_sim_advance_visit_atoms` has done it.
--   But that step completes the check only for `current_state = 'staged_for_departure'`, so a vehicle leaving
--   through `staged_awaiting_service` passes the dispatcher with the check still pending.
--   Measured on run `7a42982a`: both of its readiness violations (2 of 124 dispatches, 1.6%, against 24.5–25.8%
--   before 0431) took that path: `charging_l2 → staged_awaiting_service → deployed`, the second hop 0–22
--   sim-seconds after the first (vehicles `7ec698b8…` at 07:56:04 CT and `72ccc3d4…` at 10:54:25 CT).
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════
--
--   The check is performed at the second door, and the hold guards it. Both sides use the dispatcher's own
--   predicate for that door, `staged_awaiting_service AND COALESCE(config->>'svc_step','ready') IN ('ready')`,
--   so the hold can never strand a vehicle: every vehicle it holds is one the check step will complete at the
--   start of the next tick.
--   1. `twin.ottoq_sim_advance_visit_atoms`: the cursor that finds a pending check selects either state, and
--      carries `svc_step` so the branch that performs it can test the same predicate.
--   2. `ottoq.ottoq_plan_dispatch_tick`: 0431's hold covers either state. The dial
--      `dispatch_holds_for_readiness_check` still switches it off.
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════
--
--   Dispatch timing and atom completion both move.
--
-- ══ §4 WHAT THIS DOES NOT DO ═══════════════════════════════════════════════════
--
--   `en_route_to_deployment` and `offline` are also candidates, and neither performs the check. No violation
--   on `7a42982a` used them; `ottoq_assert_departure_readiness(run)` will say whether one ever does.
--
-- ══ §5 PRE-FLIGHT, CHANGE, VERIFICATION ══════════════════════════════════════

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0437 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0437 P0: a determinism pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0437 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: md5 guards and unique anchors ──
DO $$
DECLARE v_src text; v_n int; v_a text; v_i int;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_dispatch_tick';
  IF md5(v_src) <> '2a6768994db3493020525b284a075e06' THEN
    RAISE EXCEPTION '0437 P1: ottoq.ottoq_plan_dispatch_tick md5 is % -- it changed since this file read it', md5(v_src);
  END IF;
  v_a := E'AND NOT (v.current_state = ''staged_for_departure''\n                AND (SELECT public.ottoq_policy_get(p_sim_run_id, ''dispatch_holds_for_readiness_check'', 1)) >= 1\n';
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0437 P1: dispatcher hold anchor matched % times', v_n; END IF;
  v_a := E'OR (v.current_state = ''staged_awaiting_service'' AND COALESCE(v.config->>''svc_step'',''ready'') IN (''ready''))';
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0437 P1: the dispatcher''s second-door predicate matched % times -- the mirror would be wrong', v_n; END IF;

  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_visit_atoms';
  IF md5(v_src) <> 'd253536760e56e6b37f1149ec1ac052d' THEN
    RAISE EXCEPTION '0437 P1: twin.ottoq_sim_advance_visit_atoms md5 is % -- it changed since this file read it', md5(v_src);
  END IF;
  v_i := 0;
  FOREACH v_a IN ARRAY ARRAY[
    E'    SELECT vn.visit_id, vn.vehicle_id, vn.atoms, v.current_state\n      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id\n',
    E'         OR (v.current_state = ''staged_for_departure''\n             AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a\n                          WHERE a->>''svc'' = ''readiness_check'' AND COALESCE(a->>''status'',''pending'') = ''pending'')))\n',
    E'         AND v_rec.current_state = ''staged_for_departure'' THEN\n'
  ] LOOP
    v_i := v_i + 1;
    v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
    IF v_n <> 1 THEN RAISE EXCEPTION '0437 P1: visit-atoms anchor % matched % times', v_i, v_n; END IF;
  END LOOP;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0437_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname, p.proname) IN (('ottoq','ottoq_plan_dispatch_tick'), ('twin','ottoq_sim_advance_visit_atoms'));

-- ── (1) THE CHECK IS PERFORMED AT THE SECOND DOOR ──
DO $splice$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_visit_atoms';
  v_new := v_def;
  v_new := replace(v_new,
    E'    SELECT vn.visit_id, vn.vehicle_id, vn.atoms, v.current_state\n      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id\n',
    E'    SELECT vn.visit_id, vn.vehicle_id, vn.atoms, v.current_state,\n'
    || E'           COALESCE(v.config->>''svc_step'',''ready'') AS svc_step   /* 0437 */\n'
    || E'      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id\n');
  v_new := replace(v_new,
    E'         OR (v.current_state = ''staged_for_departure''\n             AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a\n                          WHERE a->>''svc'' = ''readiness_check'' AND COALESCE(a->>''status'',''pending'') = ''pending'')))\n',
    E'         OR ((v.current_state = ''staged_for_departure''\n'
    || E'              /* 0437: the dispatcher''s second door, by its own predicate */\n'
    || E'              OR (v.current_state = ''staged_awaiting_service'' AND COALESCE(v.config->>''svc_step'',''ready'') IN (''ready'')))\n'
    || E'             AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a\n'
    || E'                          WHERE a->>''svc'' = ''readiness_check'' AND COALESCE(a->>''status'',''pending'') = ''pending'')))\n');
  v_new := replace(v_new,
    E'         AND v_rec.current_state = ''staged_for_departure'' THEN\n',
    E'         AND (v_rec.current_state = ''staged_for_departure''\n'
    || E'              OR (v_rec.current_state = ''staged_awaiting_service'' AND v_rec.svc_step IN (''ready''))) THEN   /* 0437 */\n');
  IF v_new = v_def THEN RAISE EXCEPTION '0437 (1): no splice applied'; END IF;
  EXECUTE v_new;
END $splice$;

-- ── (2) THE HOLD GUARDS IT ──
DO $splice$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_dispatch_tick';
  v_new := replace(v_def,
    E'AND NOT (v.current_state = ''staged_for_departure''\n                AND (SELECT public.ottoq_policy_get(p_sim_run_id, ''dispatch_holds_for_readiness_check'', 1)) >= 1\n',
    E'AND NOT ((v.current_state = ''staged_for_departure''\n'
    || E'                 -- 0437: the second door, by the candidate clause''s own predicate (G170)\n'
    || E'                 OR (v.current_state = ''staged_awaiting_service'' AND COALESCE(v.config->>''svc_step'',''ready'') IN (''ready'')))\n'
    || E'                AND (SELECT public.ottoq_policy_get(p_sim_run_id, ''dispatch_holds_for_readiness_check'', 1)) >= 1\n');
  IF v_new = v_def THEN RAISE EXCEPTION '0437 (2): no splice applied'; END IF;
  EXECUTE v_new;
END $splice$;

-- ── V1: the hold and the check step name the same two states with the same predicate ──
DO $$
DECLARE v_disp text; v_atoms text; v_pred text := 'OR (v.current_state = ''staged_awaiting_service'' AND COALESCE(v.config->>''svc_step'',''ready'') IN (''ready''))';
BEGIN
  SELECT p.prosrc INTO v_disp FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_plan_dispatch_tick';
  SELECT p.prosrc INTO v_atoms FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_visit_atoms';
  -- the candidate clause and the hold, both in the dispatcher: the predicate now appears twice there
  IF (length(v_disp) - length(replace(v_disp, v_pred, ''))) / length(v_pred) <> 2 THEN
    RAISE EXCEPTION '0437 V1: the dispatcher does not carry the second-door predicate in both its candidate clause and its hold';
  END IF;
  -- the check step's cursor carries it once, and its branch tests the carried svc_step
  IF (length(v_atoms) - length(replace(v_atoms, v_pred, ''))) / length(v_pred) <> 1
  OR position('OR (v_rec.current_state = ''staged_awaiting_service'' AND v_rec.svc_step IN (''ready''))) THEN' IN v_atoms) = 0
  OR position('COALESCE(v.config->>''svc_step'',''ready'') AS svc_step' IN v_atoms) = 0 THEN
    RAISE EXCEPTION '0437 V1: the check step does not perform the check at the second door';
  END IF;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0437_the_readiness_check_had_a_second_door_out_of_the_depot_and_0431_only_guarded_one',
   true,
   'The readiness check is performed, and 0431''s hold applies, at the staged_awaiting_service/svc_step=ready '
   'departure door too (G170). Dispatch timing and atom completion move: recert.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert TRUE. After a fresh run: SELECT * FROM public.ottoq_assert_departure_readiness(run) should be empty.
-- Rollback: dispatch_holds_for_readiness_check = 0 lifts the hold (the check still runs at both doors), or restore
-- from ottoq_schema_snapshots label '0437_pre'.
