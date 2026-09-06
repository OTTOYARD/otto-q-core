-- =====================================================================
-- 0206  Every recall decision is a ledger row, and the implementation
--       is a name
-- =====================================================================
-- forces_recert = TRUE. The decide-path function
-- public.ottoq_evaluate_return_need becomes a wrapper: it resolves the
-- implementation by policy, runs it, writes one ledger row, returns the
-- same eight columns. The ladder itself is not retyped: it is copied
-- from the live catalog under the name ottoq_recall_naive_threshold_v1,
-- md5-pinned, and A1 proves the copy equals the original once its name
-- is put back. The prediction for the next round is that no canon moves;
-- the ledger is new content, and h_rcl reports it (measured, not yet
-- enforced -- the 0203/0205 protocol).
-- Requires 0203 (h_rule anchors in the pair and the matrix).
--
-- THE FINDING (pre-Part-B trace, G6)
-- ---------------------------------------------------------------------
-- "When do I stop working" -- the first of the kernel's four questions
-- and the one place intelligence touches revenue (CLAUDE.md 2.7) -- has
-- no ledger. The live Recall Decision is public.ottoq_evaluate_return_need
-- (md5 0c463ada..., 12,063 chars): a rung ladder over reserve, faults,
-- rider flags, comms, timer backstop, service intervals, night waves and
-- wash cadence, called per deployed vehicle per tick by
-- twin.ottoq_sim_advance_deployed_telemetry and on real signals by
-- ottoq.ottoq_decide_return_on_signal. Its output survives only as
-- ottoq_vehicle_dispatches.return_trigger (text) and return_evidence
-- (jsonb), one per dispatch, overwritten in place; the stay-deployed
-- verdicts, which are most of them, survive nowhere. early_recall_log
-- (the concept's older home) has 0 rows and no writer. recall/ (C9) is
-- Python with no database client: it emits recall_issued /
-- recall_refused records offline, and ottoq_events holds zero events of
-- either type. The kernel's implementation has no name: nothing records
-- which decision procedure decided, so nothing can be swapped and
-- compared on the same ledger.
--
-- WHAT CHANGES
-- ---------------------------------------------------------------------
--   1. public.ottoq_recall_decisions: one row per evaluation -- run,
--      vehicle, depot, the sim clock it was decided at, the
--      implementation's name, the eight-column verdict, the caller's
--      horizon and SoC override, the evidence snapshot as inputs, and a
--      content hash over all of it. Append-only (ottoq_block_mutation),
--      FK to the run (NO ACTION), registry class engine, partial index
--      by run. Stay-deployed verdicts are rows too: the decision not to
--      recall is a decision.
--   2. public.ottoq_recall_implementations: the registry of decision
--      procedures. 1 = naive_threshold_v1 (the live ladder, copied from
--      the catalog, byte-identical). 2 = fixed_window_dummy (recalls
--      everything inside a policy window; the swap proof and nothing
--      more, exactly as recall/recall_decision.py ships it).
--   3. Policy parameter recall_implementation_id (default 1) selects the
--      implementation per run, depot or globally through the existing
--      ottoq_policy_get ladder. Swapping is a policy write; no call site
--      changes (A2 proves it by swapping to the dummy in a rolled-back
--      scope and reading the ledger).
--   4. The wrapper writes the ledger row unless ottoq.dryrun is on (the
--      MPC fork convention the rule ledger already follows).
--   5. ottoq_hash_recall_decisions(run) and h_rcl in the pair's arm
--      object; canon_rcl in the matrix. Reported, not judged, until a
--      flagship round shows the arms agree (then a gated promotion, as
--      0205 does for h_rule).
--
-- NOT CHANGED, and why
-- ---------------------------------------------------------------------
--   - The ladder's logic: not one character. Its rung numbers, triggers
--     and evidence keys are what the ledger records.
--   - The two callers: the wrapper keeps the signature, the defaults and
--     the result shape, so twin.ottoq_sim_advance_deployed_telemetry and
--     ottoq.ottoq_decide_return_on_signal are untouched (A0 pins them).
--   - Work-side refusal (G7) is the next migration; this one gives it
--     the row to write.
-- =====================================================================

BEGIN;

CREATE TEMP TABLE pin_0206 ON COMMIT DROP AS
SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
       md5(pg_get_functiondef(p.oid)) AS h, p.prosecdef, p.proacl::text AS acl
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p');

-- ---------------------------------------------------------------------
-- 0. Preconditions.
-- ---------------------------------------------------------------------
DO $pre$
DECLARE v_h text;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job j WHERE j.jobname ~ '^r[0-9]+_')
     OR EXISTS (SELECT 1 FROM pg_stat_activity a
                 WHERE a.query ILIKE '%ottoq_determinism_pair%' AND a.pid <> pg_backend_pid() AND a.state <> 'idle') THEN
    RAISE EXCEPTION '0206 refused: a certification round is scheduled or in flight';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0206 refused: a sim run is running';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name ~ '^0203_') THEN
    RAISE EXCEPTION '0206 refused: 0203 is not applied';
  END IF;
  SELECT h INTO v_h FROM pin_0206
   WHERE sig = 'public.ottoq_evaluate_return_need(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_horizon_min numeric, p_soc_pct numeric)';
  IF v_h IS DISTINCT FROM '0c463ada1588296a31ec1761d16a83d4' THEN
    RAISE EXCEPTION '0206 refused: ottoq_evaluate_return_need is not the body this file was written against (md5 %)', v_h;
  END IF;
  IF to_regclass('public.ottoq_recall_decisions') IS NOT NULL OR to_regclass('public.ottoq_recall_implementations') IS NOT NULL THEN
    RAISE EXCEPTION '0206 refused: a 0206 table already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('ottoq_recall_naive_threshold_v1','ottoq_recall_fixed_window_dummy','ottoq_hash_recall_decisions')) THEN
    RAISE EXCEPTION '0206 refused: a 0206 function already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'recall_implementation_id') THEN
    RAISE EXCEPTION '0206 refused: recall_implementation_id is already in the policy catalog';
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public','ottoq','twin')
         AND p.prosrc ~ 'FROM ottoq_evaluate_return_need\(' AND p.proname <> 'ottoq_evaluate_return_need') <> 2 THEN
    RAISE EXCEPTION '0206 refused: the evaluator no longer has exactly two callers';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.depots WHERE id = 'aacd0bb0-2d02-d101-72cc-33f70e950bc8')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_scenarios s WHERE s.scenario_code = 'grid_smoke' AND s.status = 'active'
                       AND s.depot_id = 'aacd0bb0-2d02-d101-72cc-33f70e950bc8') THEN
    RAISE EXCEPTION '0206 refused: the grid fixture or its scenario is missing; A3 needs a live pair';
  END IF;
  RAISE NOTICE '0206 pre: evaluator pinned at 0c463ada, two callers, nothing in flight';
END $pre$;

-- ---------------------------------------------------------------------
-- 1. The ledger and the registry of implementations.
-- ---------------------------------------------------------------------
CREATE TABLE public.ottoq_recall_decisions (
  recall_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sim_run_id         uuid NOT NULL REFERENCES public.ottoq_sim_runs(sim_run_id),
  vehicle_id         uuid NOT NULL,
  depot_id           uuid,
  decided_at_sim     timestamp with time zone NOT NULL,
  decided_at         timestamp with time zone NOT NULL DEFAULT now(),
  implementation     text NOT NULL,
  should_return      boolean NOT NULL,
  return_trigger     text,
  urgency            text,
  rung               smallint,
  is_deferrable      boolean,
  lead_ticks         smallint,
  projected_eta_min  numeric,
  horizon_min        numeric,
  soc_override       numeric,
  inputs             jsonb NOT NULL DEFAULT '{}'::jsonb,
  content_hash       text NOT NULL,
  data_source        text NOT NULL DEFAULT 'twin'
);
COMMENT ON TABLE public.ottoq_recall_decisions IS
  '0206: the Recall Decision ledger (CLAUDE.md 2.7 / C9). One row per evaluation of "when do I stop working", including the decision to stay deployed. implementation names the procedure that decided; inputs is its evidence snapshot; content_hash covers vehicle, sim clock, implementation, verdict and inputs. Append-only. Twin rows die with their run (registry class engine); production rows persist.';
CREATE INDEX idx_ottoq_recall_decisions_run ON public.ottoq_recall_decisions (sim_run_id, decided_at_sim, vehicle_id);
CREATE TRIGGER trg_ottoq_recall_decisions_append_only
  BEFORE UPDATE OR DELETE ON public.ottoq_recall_decisions
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_block_mutation();

CREATE TABLE public.ottoq_recall_implementations (
  impl_id            smallint PRIMARY KEY,
  implementation     text NOT NULL UNIQUE,
  evaluator_function text NOT NULL,
  status             text NOT NULL CHECK (status IN ('active','parked')),
  note               text
);
COMMENT ON TABLE public.ottoq_recall_implementations IS
  '0206: the registry of Recall Decision procedures. ottoq_evaluate_return_need dispatches to evaluator_function for the impl_id selected by policy parameter recall_implementation_id. Same signature, same result shape, no call-site change.';
INSERT INTO public.ottoq_recall_implementations (impl_id, implementation, evaluator_function, status, note) VALUES
  (1, 'naive_threshold_v1', 'ottoq_recall_naive_threshold_v1', 'active',
   'The live rung ladder, copied from the catalog byte-for-byte under this name (0206 A1). Deliberately naive: fixed thresholds, top-down, first hit wins; no forecasting, no cost model, no learning. Every smarter successor has this baseline to beat on the same ledger.'),
  (2, 'fixed_window_dummy', 'ottoq_recall_fixed_window_dummy', 'parked',
   'The swap proof and nothing more: recalls every deployed asset inside a policy window (recall_fixed_window_from_hour .. to_hour, depot-local). Not a policy anyone should run. Selecting it is a policy write; no call site changes.');

INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects) VALUES
  ('recall_implementation_id', 'Which registered Recall Decision procedure decides (ottoq_recall_implementations.impl_id): 1 = naive_threshold_v1, the live ladder; 2 = fixed_window_dummy, the swap proof.', 1, 1, 2,
   'ottoq_evaluate_return_need -> ottoq_recall_decisions.implementation; every return-to-depot decision'),
  ('recall_fixed_window_from_hour', 'fixed_window_dummy only: depot-local hour the recall window opens.', 16, 0, 23, 'ottoq_recall_fixed_window_dummy'),
  ('recall_fixed_window_to_hour',   'fixed_window_dummy only: depot-local hour the recall window closes (exclusive).', 24, 1, 24, 'ottoq_recall_fixed_window_dummy')
ON CONFLICT (param_key) DO NOTHING;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public','ottoq_recall_decisions','sim_run_id','engine',
        '0206: a twin run''s recall decisions die with the run; production decisions persist.')
ON CONFLICT (table_schema, table_name, column_name) DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. The ladder, from the catalog, under its name. One fragment: the
--    function name in the header. Nothing in the body is touched.
-- ---------------------------------------------------------------------
DO $copy$
DECLARE v_def text; v_n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_evaluate_return_need(uuid,uuid,timestamptz,numeric,numeric)'::regprocedure);
  IF md5(v_def) <> '0c463ada1588296a31ec1761d16a83d4' THEN
    RAISE EXCEPTION '0206 step 2: the evaluator moved between the pin and the copy';
  END IF;
  v_n := (length(v_def) - length(replace(v_def, 'FUNCTION public.ottoq_evaluate_return_need(', ''))) / length('FUNCTION public.ottoq_evaluate_return_need(');
  IF v_n <> 1 THEN RAISE EXCEPTION '0206 step 2: header fragment occurs % times', v_n; END IF;
  v_def := replace(v_def, 'FUNCTION public.ottoq_evaluate_return_need(', 'FUNCTION public.ottoq_recall_naive_threshold_v1(');
  EXECUTE v_def;
  RAISE NOTICE '0206 step 2: ottoq_recall_naive_threshold_v1 created from the catalog copy of the evaluator';
END $copy$;
COMMENT ON FUNCTION public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamptz,numeric,numeric) IS
  '0206: implementation 1, naive_threshold_v1. The rung ladder that was public.ottoq_evaluate_return_need until 0206, copied from the catalog with only its name changed (md5 of the original: 0c463ada1588296a31ec1761d16a83d4). Deliberately naive. Do not call directly; the wrapper records the decision.';

-- ---------------------------------------------------------------------
-- 3. The swap proof.
-- ---------------------------------------------------------------------
CREATE FUNCTION public.ottoq_recall_fixed_window_dummy(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_horizon_min numeric DEFAULT 30, p_soc_pct numeric DEFAULT NULL::numeric)
 RETURNS TABLE(should_return boolean, return_trigger text, urgency text, rung smallint, is_deferrable boolean, lead_ticks smallint, projected_eta_min numeric, evidence jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_hour int; v_from int; v_to int; v_eta numeric; v_depot uuid;
BEGIN
  -- 0206. Implementation 2. Recalls everything inside a fixed depot-local
  -- window and nothing outside it. Exists to prove the swap; not a policy.
  IF p_sim_run_id IS NULL THEN
    RAISE EXCEPTION 'ottoq_recall_fixed_window_dummy requires a run scope';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM ottoq_vehicle_dispatches d
                  WHERE d.vehicle_id = p_vehicle_id AND d.sim_run_id = p_sim_run_id AND d.status = 'active') THEN
    RETURN QUERY SELECT false, NULL::text, 'none', 10::smallint, NULL::boolean, NULL::smallint, NULL::numeric,
                        jsonb_build_object('reason','no active dispatch in run','implementation','fixed_window_dummy');
    RETURN;
  END IF;
  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;
  v_from := ottoq_policy_get(p_sim_run_id, 'recall_fixed_window_from_hour', 16)::int;
  v_to   := ottoq_policy_get(p_sim_run_id, 'recall_fixed_window_to_hour',   24)::int;
  IF v_hour >= v_from AND v_hour < v_to THEN
    SELECT v.home_depot_id INTO v_depot FROM vehicles v WHERE v.id = p_vehicle_id;
    v_eta := ottoq_return_eta_minutes(p_vehicle_id, v_depot, p_sim_run_id);
    RETURN QUERY SELECT true, 'fixed_window', 'scheduled', 11::smallint, true, 1::smallint, v_eta,
                        jsonb_build_object('hour_local', v_hour, 'window', jsonb_build_array(v_from, v_to),
                                           'implementation', 'fixed_window_dummy',
                                           'why', 'the swap proof: recalls everything inside a fixed window');
    RETURN;
  END IF;
  RETURN QUERY SELECT false, NULL::text, 'none', 10::smallint, NULL::boolean, NULL::smallint, NULL::numeric,
                      jsonb_build_object('hour_local', v_hour, 'window', jsonb_build_array(v_from, v_to),
                                         'implementation', 'fixed_window_dummy', 'decision', 'outside window; stay deployed');
END;
$function$;
COMMENT ON FUNCTION public.ottoq_recall_fixed_window_dummy(uuid,uuid,timestamptz,numeric,numeric) IS
  '0206: implementation 2, fixed_window_dummy. The swap proof. Do not run in anger.';

-- ---------------------------------------------------------------------
-- 4. The wrapper: the same name, signature, defaults and result shape.
--    CREATE OR REPLACE keeps the function's ACL.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_evaluate_return_need(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_horizon_min numeric DEFAULT 30, p_soc_pct numeric DEFAULT NULL::numeric)
 RETURNS TABLE(should_return boolean, return_trigger text, urgency text, rung smallint, is_deferrable boolean, lead_ticks smallint, projected_eta_min numeric, evidence jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_impl_id int; v_impl record; v_row record; v_depot uuid; v_src text; v_hash text;
BEGIN
  -- 0206. THE RECALL DECISION (CLAUDE.md 2.7). Resolve the implementation by
  -- policy, run it, write the ledger row, return its verdict unchanged. The
  -- two call sites (twin deployed-telemetry, real-signal path) are exactly
  -- as they were.
  IF p_sim_run_id IS NULL THEN
    RAISE EXCEPTION 'ottoq_evaluate_return_need requires a run scope';
  END IF;
  v_impl_id := ottoq_policy_get(p_sim_run_id, 'recall_implementation_id', 1)::int;
  SELECT i.* INTO v_impl FROM public.ottoq_recall_implementations i WHERE i.impl_id = v_impl_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ottoq_evaluate_return_need: no recall implementation with impl_id % (policy recall_implementation_id)', v_impl_id;
  END IF;

  EXECUTE format('SELECT * FROM public.%I($1, $2, $3, $4, $5)', v_impl.evaluator_function)
     INTO v_row USING p_vehicle_id, p_sim_run_id, p_sim_clock_now, p_horizon_min, p_soc_pct;

  IF current_setting('ottoq.dryrun', true) IS DISTINCT FROM 'on' THEN   -- MPC fork: evaluate, do not persist
    SELECT v.home_depot_id INTO v_depot FROM public.vehicles v WHERE v.id = p_vehicle_id;
    SELECT CASE WHEN r.run_by = 'production_live' THEN 'production' ELSE 'twin' END INTO v_src
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
    v_hash := md5(p_vehicle_id::text
              || '|' || to_char(p_sim_clock_now AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US')
              || '|' || v_impl.implementation
              || '|' || COALESCE(v_row.should_return::text, '-')
              || '|' || COALESCE(v_row.return_trigger, '-')
              || '|' || COALESCE(v_row.urgency, '-')
              || '|' || COALESCE(v_row.rung::text, '-')
              || '|' || COALESCE(v_row.is_deferrable::text, '-')
              || '|' || COALESCE(v_row.lead_ticks::text, '-')
              || '|' || COALESCE(v_row.projected_eta_min::text, '-')
              || '|' || COALESCE(p_horizon_min::text, '-')
              || '|' || COALESCE(p_soc_pct::text, '-')
              || '|' || COALESCE(v_row.evidence::text, '-'));
    INSERT INTO public.ottoq_recall_decisions
      (sim_run_id, vehicle_id, depot_id, decided_at_sim, implementation, should_return, return_trigger, urgency, rung,
       is_deferrable, lead_ticks, projected_eta_min, horizon_min, soc_override, inputs, content_hash, data_source)
    VALUES
      (p_sim_run_id, p_vehicle_id, v_depot, p_sim_clock_now, v_impl.implementation, COALESCE(v_row.should_return, false),
       v_row.return_trigger, v_row.urgency, v_row.rung, v_row.is_deferrable, v_row.lead_ticks, v_row.projected_eta_min,
       p_horizon_min, p_soc_pct, COALESCE(v_row.evidence, '{}'::jsonb), v_hash, COALESCE(v_src, 'twin'));
  END IF;

  RETURN QUERY SELECT v_row.should_return, v_row.return_trigger, v_row.urgency, v_row.rung,
                      v_row.is_deferrable, v_row.lead_ticks, v_row.projected_eta_min, v_row.evidence;
END;
$function$;
COMMENT ON FUNCTION public.ottoq_evaluate_return_need(uuid,uuid,timestamptz,numeric,numeric) IS
  '0206: the Recall Decision entry point. Dispatches to the implementation selected by policy recall_implementation_id (ottoq_recall_implementations), writes one ottoq_recall_decisions row per evaluation, returns the verdict. The ladder that lived here until 0206 is ottoq_recall_naive_threshold_v1, unchanged.';

-- ---------------------------------------------------------------------
-- 5. Privileges: the two implementations carry the wrapper's ACL; the
--    ledger is readable by the app roles, written only through the wrapper.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamptz,numeric,numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ottoq_recall_fixed_window_dummy(uuid,uuid,timestamptz,numeric,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamptz,numeric,numeric) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_recall_fixed_window_dummy(uuid,uuid,timestamptz,numeric,numeric) TO authenticated, service_role;
REVOKE ALL ON TABLE public.ottoq_recall_decisions FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.ottoq_recall_implementations FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.ottoq_recall_decisions TO authenticated, service_role;
GRANT SELECT ON TABLE public.ottoq_recall_implementations TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- 6. h_rcl: the hash, the arm object, the matrix column.
-- ---------------------------------------------------------------------
CREATE FUNCTION public.ottoq_hash_recall_decisions(p_run uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
  -- 0206. The run's recall decisions as a content multiset. content_hash
  -- already covers vehicle, sim clock, implementation, verdict and inputs;
  -- ordering by (sim clock, vehicle, hash) is content order, not arrival.
  SELECT md5(COALESCE(string_agg(d.content_hash, E'\n' ORDER BY d.decided_at_sim, d.vehicle_id, d.content_hash), ''))
    FROM public.ottoq_recall_decisions d
   WHERE d.sim_run_id = p_run;
$function$;
COMMENT ON FUNCTION public.ottoq_hash_recall_decisions(uuid) IS
  '0206: md5 over the run''s ottoq_recall_decisions content hashes, in content order. This is h_rcl in the pair verdict: measured from 0206, enforced after a flagship round shows the arms agree.';

DO $pair$
DECLARE
  v_def text; v_n int; v_h0 text;
  v_old text := $f$'h_rule', public.ottoq_hash_rule_evaluations(v_run))$f$;
  v_new text := $f$'h_rule', public.ottoq_hash_rule_evaluations(v_run), 'h_rcl', public.ottoq_hash_recall_decisions(v_run))$f$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)'::regprocedure);
  v_h0 := md5(v_def);
  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF v_n <> 1 THEN RAISE EXCEPTION '0206 step 6: the pair''s h_rule fragment occurs % times, expected exactly once', v_n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
  IF md5(replace(pg_get_functiondef('public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)'::regprocedure), v_new, v_old)) <> v_h0 THEN
    RAISE EXCEPTION '0206 A1 FAILED: the pair differs from its pin outside the one fragment';
  END IF;
  RAISE NOTICE '0206 step 6: the pair carries h_rcl; reverse replacement restores the pin';
END $pair$;

DO $mx$
DECLARE
  v_def text; v_n int; i int; v_h0 text; v_back text;
  v_old text[] := ARRAY[
    $f$canon_cal text, canon_rule text)$f$,
    $f$p.j->'arm_a'->>'h_cal'$f$,
    $f$rk.c_cal, rk.c_rule$f$,
    $f$l.c_cal, l.c_rule$f$];
  v_new text[] := ARRAY[
    $f$canon_cal text, canon_rule text, canon_rcl text)$f$,
    $f$p.j->'arm_a'->>'h_rcl'                    AS c_rcl,    -- 0206; NULL before 0206; reported, not judged
         p.j->'arm_a'->>'h_cal'$f$,
    $f$rk.c_cal, rk.c_rule, rk.c_rcl$f$,
    $f$l.c_cal, l.c_rule, l.c_rcl$f$];
BEGIN
  v_def := pg_get_functiondef('public.ottoq_cert_matrix(timestamptz)'::regprocedure);
  v_h0 := md5(v_def);
  FOR i IN 1..4 LOOP
    v_n := (length(v_def) - length(replace(v_def, v_old[i], ''))) / length(v_old[i]);
    IF v_n <> 1 THEN RAISE EXCEPTION '0206 step 6: matrix fragment % occurs % times, expected exactly once', i, v_n; END IF;
    v_def := replace(v_def, v_old[i], v_new[i]);
  END LOOP;
  DROP FUNCTION public.ottoq_cert_matrix(timestamp with time zone);
  EXECUTE v_def;
  v_back := pg_get_functiondef('public.ottoq_cert_matrix(timestamptz)'::regprocedure);
  FOR i IN 1..4 LOOP v_back := replace(v_back, v_new[i], v_old[i]); END LOOP;
  IF md5(v_back) <> v_h0 THEN RAISE EXCEPTION '0206 A1 FAILED: the matrix differs from its pin outside the four fragments'; END IF;
  RAISE NOTICE '0206 step 6: the matrix reports canon_rcl; reverse replacement restores the pin';
END $mx$;

-- ---------------------------------------------------------------------
-- ASSERTIONS
-- ---------------------------------------------------------------------
DO $assert$
DECLARE
  v_changed text[]; v_new text[]; v_def text; v_run uuid; v_clock timestamptz; v_veh uuid; v_n bigint; v_m bigint;
  v_a record; v_b record; v_impl text; v_pair jsonb; v_ra uuid; v_rb uuid; v_bad bigint; v_hash_re bigint; v_acl_w text;
BEGIN
  -- ── A0. THE PIN. The evaluator, the pair and the matrix changed; three new; callers untouched.
  SELECT array_agg(a.sig ORDER BY a.sig) INTO v_changed
    FROM pin_0206 a
    JOIN (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
                 md5(pg_get_functiondef(p.oid)) AS h, p.prosecdef
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b USING (sig)
   WHERE a.h <> b.h OR a.prosecdef <> b.prosecdef;
  IF v_changed IS DISTINCT FROM ARRAY[
       'public.ottoq_cert_matrix(p_since timestamp with time zone)',
       'public.ottoq_determinism_pair(p_seed bigint, p_ticks integer, p_scenario text, p_depot uuid, p_sim_start timestamp with time zone, p_arm_budget_s integer)',
       'public.ottoq_evaluate_return_need(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_horizon_min numeric, p_soc_pct numeric)'] THEN
    RAISE EXCEPTION '0206 A0 FAILED: function bodies changed = %', v_changed;
  END IF;
  SELECT array_agg(b.sig ORDER BY b.sig) INTO v_new
    FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b
    LEFT JOIN pin_0206 a USING (sig) WHERE a.sig IS NULL;
  IF v_new IS DISTINCT FROM ARRAY[
       'public.ottoq_hash_recall_decisions(p_run uuid)',
       'public.ottoq_recall_fixed_window_dummy(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_horizon_min numeric, p_soc_pct numeric)',
       'public.ottoq_recall_naive_threshold_v1(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_horizon_min numeric, p_soc_pct numeric)'] THEN
    RAISE EXCEPTION '0206 A0 FAILED: new functions = %', v_new;
  END IF;
  RAISE NOTICE '0206 A0: pin holds; evaluator, pair, matrix changed; ladder copy, dummy, hash new';

  -- ── A1. The ladder copy IS the pinned evaluator once its name is put back.
  v_def := pg_get_functiondef('public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamptz,numeric,numeric)'::regprocedure);
  v_def := replace(v_def, 'FUNCTION public.ottoq_recall_naive_threshold_v1(', 'FUNCTION public.ottoq_evaluate_return_need(');
  IF md5(v_def) <> '0c463ada1588296a31ec1761d16a83d4' THEN
    RAISE EXCEPTION '0206 A1 FAILED: the ladder copy differs from the pinned evaluator';
  END IF;
  RAISE NOTICE '0206 A1: naive_threshold_v1 is the pinned ladder, byte for byte';

  -- ── A2. The wrapper, in a rolled-back scope: same verdict as the ladder for
  --        three vehicles of the newest completed flagship run; one ledger row
  --        per call naming naive_threshold_v1 with a hash that recomputes; then
  --        the swap -- one policy write selects the dummy, the ledger says so,
  --        no call site changed.
  SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed'
   ORDER BY r.started_at DESC, r.sim_run_id DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE EXCEPTION '0206 A2 FAILED: no completed flagship run'; END IF;
  BEGIN
    v_n := 0;
    FOR v_veh IN SELECT d.vehicle_id FROM public.ottoq_vehicle_dispatches d WHERE d.sim_run_id = v_run ORDER BY d.dispatched_at, d.vehicle_id LIMIT 3 LOOP
      SELECT * INTO v_a FROM public.ottoq_evaluate_return_need(v_veh, v_run, v_clock, 30, NULL);
      SELECT * INTO v_b FROM public.ottoq_recall_naive_threshold_v1(v_veh, v_run, v_clock, 30, NULL);
      IF row_to_json(v_a)::text <> row_to_json(v_b)::text THEN
        RAISE EXCEPTION '0206 A2 FAILED: wrapper and ladder disagree for vehicle %: % vs %', v_veh, row_to_json(v_a), row_to_json(v_b);
      END IF;
      v_n := v_n + 1;
    END LOOP;
    IF v_n = 0 THEN RAISE EXCEPTION '0206 A2 FAILED: the run % has no dispatches to probe', v_run; END IF;
    SELECT count(*), count(*) FILTER (WHERE implementation <> 'naive_threshold_v1'),
           count(*) FILTER (WHERE content_hash <> md5(vehicle_id::text
              || '|' || to_char(decided_at_sim AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS.US')
              || '|' || implementation || '|' || COALESCE(should_return::text,'-') || '|' || COALESCE(return_trigger,'-')
              || '|' || COALESCE(urgency,'-') || '|' || COALESCE(rung::text,'-') || '|' || COALESCE(is_deferrable::text,'-')
              || '|' || COALESCE(lead_ticks::text,'-') || '|' || COALESCE(projected_eta_min::text,'-')
              || '|' || COALESCE(horizon_min::text,'-') || '|' || COALESCE(soc_override::text,'-') || '|' || COALESCE(inputs::text,'-')))
      INTO v_m, v_bad, v_hash_re
      FROM public.ottoq_recall_decisions WHERE sim_run_id = v_run;
    IF v_m <> v_n THEN RAISE EXCEPTION '0206 A2 FAILED: % calls wrote % ledger rows', v_n, v_m; END IF;
    IF v_bad > 0 THEN RAISE EXCEPTION '0206 A2 FAILED: % rows name an implementation other than naive_threshold_v1', v_bad; END IF;
    IF v_hash_re > 0 THEN RAISE EXCEPTION '0206 A2 FAILED: % rows carry a content_hash that does not recompute', v_hash_re; END IF;
    -- the swap
    IF NOT COALESCE((public.ottoq_policy_set('run', v_run, 'recall_implementation_id', 2, '0206-probe')->>'ok')::boolean, false) THEN
      RAISE EXCEPTION '0206 A2 FAILED: ottoq_policy_set refused recall_implementation_id';
    END IF;
    SELECT * INTO v_a FROM public.ottoq_evaluate_return_need(v_veh, v_run, v_clock, 30, NULL);
    IF v_a.evidence->>'implementation' IS DISTINCT FROM 'fixed_window_dummy' THEN
      RAISE EXCEPTION '0206 A2 FAILED: after the policy write the wrapper still ran %', COALESCE(v_a.evidence->>'implementation','naive_threshold_v1');
    END IF;
    SELECT implementation INTO v_impl FROM public.ottoq_recall_decisions WHERE sim_run_id = v_run ORDER BY decided_at DESC, recall_id DESC LIMIT 1;
    IF v_impl IS DISTINCT FROM 'fixed_window_dummy' THEN
      RAISE EXCEPTION '0206 A2 FAILED: the ledger names % after the swap', v_impl;
    END IF;
    -- dryrun: evaluate, do not persist
    PERFORM set_config('ottoq.dryrun', 'on', true);
    SELECT count(*) INTO v_m FROM public.ottoq_recall_decisions WHERE sim_run_id = v_run;
    SELECT * INTO v_a FROM public.ottoq_evaluate_return_need(v_veh, v_run, v_clock, 30, NULL);
    IF (SELECT count(*) FROM public.ottoq_recall_decisions WHERE sim_run_id = v_run) <> v_m THEN
      RAISE EXCEPTION '0206 A2 FAILED: a dry run wrote a ledger row';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0206', MESSAGE = 'scope rollback';
  EXCEPTION WHEN SQLSTATE 'P0206' THEN NULL;
  END;
  PERFORM set_config('ottoq.dryrun', '', true);
  IF EXISTS (SELECT 1 FROM public.ottoq_recall_decisions WHERE sim_run_id = v_run)
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'recall_implementation_id') THEN
    RAISE EXCEPTION '0206 A2 FAILED: the probe scope did not roll back';
  END IF;
  RAISE NOTICE '0206 A2: wrapper = ladder on % vehicles; one row per call; hashes recompute; the swap is a policy write; dryrun writes nothing; all rolled back', v_n;

  -- ── A3. LIVE. A six-tick grid pair: both arms carry h_rcl, agree, non-empty,
  --        every row names naive_threshold_v1, the hash recomputes from the ledger,
  --        and the pair still passes on everything it already judged.
  v_pair := public.ottoq_determinism_pair(424242, 6, 'grid_smoke', 'aacd0bb0-2d02-d101-72cc-33f70e950bc8'::uuid,
                                          '2026-09-01 02:00:00+00'::timestamptz, 120);
  IF NOT COALESCE((v_pair->>'equal')::boolean, false) THEN
    RAISE EXCEPTION '0206 A3 FAILED: the grid pair did not pass (outcome %)', v_pair->>'outcome';
  END IF;
  v_ra := (v_pair->'arm_a'->>'run')::uuid;  v_rb := (v_pair->'arm_b'->>'run')::uuid;
  IF v_pair->'arm_a'->>'h_rcl' IS NULL OR v_pair->'arm_b'->>'h_rcl' IS NULL THEN
    RAISE EXCEPTION '0206 A3 FAILED: an arm carries no h_rcl';
  END IF;
  IF (v_pair->'arm_a'->>'h_rcl') <> (v_pair->'arm_b'->>'h_rcl') THEN
    RAISE EXCEPTION '0206 A3 FAILED: the arms disagree on h_rcl: % vs %', left(v_pair->'arm_a'->>'h_rcl',8), left(v_pair->'arm_b'->>'h_rcl',8);
  END IF;
  IF (v_pair->'arm_a'->>'h_rcl') = md5('') THEN
    RAISE EXCEPTION '0206 A3 FAILED: the grid arms made no recall decisions; the ledger has nothing to show';
  END IF;
  SELECT count(*), count(*) FILTER (WHERE implementation <> 'naive_threshold_v1'), count(*) FILTER (WHERE should_return)
    INTO v_n, v_bad, v_m FROM public.ottoq_recall_decisions WHERE sim_run_id = v_ra;
  IF v_n = 0 OR v_bad > 0 THEN RAISE EXCEPTION '0206 A3 FAILED: arm % has % rows, % not naive', v_ra, v_n, v_bad; END IF;
  IF public.ottoq_hash_recall_decisions(v_ra) <> (v_pair->'arm_a'->>'h_rcl') THEN
    RAISE EXCEPTION '0206 A3 FAILED: h_rcl does not recompute from the ledger for arm %', v_ra;
  END IF;
  RAISE NOTICE '0206 A3: grid pair % / %: h_rcl % on both arms over % decisions (% recalls)', v_ra, v_rb, left(v_pair->'arm_a'->>'h_rcl',8), v_n, v_m;

  -- ── A4. The matrix reports canon_rcl on the grid column and NULL on flagship.
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_matrix(now() - interval '1 hour') m
                  WHERE m.depot = 'aacd0bb0-2d02-d101-72cc-33f70e950bc8' AND m.canon_rcl = (v_pair->'arm_a'->>'h_rcl')) THEN
    RAISE EXCEPTION '0206 A4 FAILED: the grid column does not report the pair''s h_rcl';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_matrix(now() - interval '30 days') m
              WHERE m.depot = '11111111-1111-1111-1111-111111111111' AND m.canon_rcl IS NOT NULL) THEN
    RAISE EXCEPTION '0206 A4 FAILED: a flagship column reports canon_rcl before any flagship pair carried h_rcl';
  END IF;

  -- ── A5. Shape and privileges: registry clean, FK NO ACTION, append-only,
  --        the implementations carry the wrapper's ACL, the ledger is SELECT-only for the app roles.
  IF EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block' OR table_name = 'ottoq_recall_decisions') THEN
    RAISE EXCEPTION '0206 A5 FAILED: run-scope registry check is not clean';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = 'public.ottoq_recall_decisions'::regclass AND k.contype = 'f'
                    AND k.confrelid = 'public.ottoq_sim_runs'::regclass AND k.confdeltype = 'a') THEN
    RAISE EXCEPTION '0206 A5 FAILED: FK to the run table missing or not NO ACTION';
  END IF;
  BEGIN
    DELETE FROM public.ottoq_recall_decisions WHERE sim_run_id = v_ra;
    RAISE EXCEPTION '0206 A5 FAILED: the ledger accepted a DELETE';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM NOT LIKE 'OTTOQ_APPEND_ONLY%' THEN RAISE; END IF;
  END;
  SELECT acl INTO v_acl_w FROM pin_0206 WHERE sig LIKE 'public.ottoq_evaluate_return_need(%';
  IF (SELECT proacl::text FROM pg_proc WHERE oid = 'public.ottoq_evaluate_return_need(uuid,uuid,timestamptz,numeric,numeric)'::regprocedure) IS DISTINCT FROM v_acl_w THEN
    RAISE EXCEPTION '0206 A5 FAILED: the wrapper''s ACL moved';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamptz,numeric,numeric)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_recall_fixed_window_dummy(uuid,uuid,timestamptz,numeric,numeric)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamptz,numeric,numeric)', 'EXECUTE')
     OR has_table_privilege('anon', 'public.ottoq_recall_decisions', 'SELECT')
     OR has_table_privilege('authenticated', 'public.ottoq_recall_decisions', 'INSERT')
     OR NOT has_table_privilege('authenticated', 'public.ottoq_recall_decisions', 'SELECT') THEN
    RAISE EXCEPTION '0206 A5 FAILED: privileges on the implementations or the ledger are not as stated';
  END IF;
  RAISE NOTICE '0206 A5: registry clean, FK NO ACTION, append-only, privileges as stated';
  RAISE NOTICE '0206: all assertions passed';
END $assert$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0206_every_recall_decision_is_a_ledger_row_and_the_implementation_is_a_name', TRUE,
  'G6. public.ottoq_evaluate_return_need is now a wrapper: policy recall_implementation_id selects a row of '
  'ottoq_recall_implementations (1 = naive_threshold_v1, the live ladder copied from the catalog byte-for-byte; 2 = '
  'fixed_window_dummy, the swap proof), runs it, writes one ottoq_recall_decisions row per evaluation (run, vehicle, sim clock, '
  'implementation, verdict, inputs, content hash; append-only, registry class engine), returns the verdict unchanged. Both call '
  'sites untouched. h_rcl in the arm object and canon_rcl in the matrix, measured not judged. A3 ran a live grid pair and the '
  'arms agreed. forces_recert TRUE because the decide-path body changed; the prediction for the next round is that no canon '
  'moves (A1 proves the ladder is byte-identical).',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;
