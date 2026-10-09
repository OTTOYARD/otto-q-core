-- migration-version: PENDING
-- migration-name:    the_futures_read_the_latest_return_model_that_was_usable
--
-- 0637  **The futures read the latest return model that was usable, and say when a newer one was not.**
--       The kernel's check on an agent's charge order forecasts every car at work home with the depot's return model
--       (return_v1), refitted every night. Every reader took the newest fit whatever it said about itself
--       (ottoq_learned_estimate orders by id), so a night whose refit found too few returns to be usable would leave the
--       futures forecasting no car at work at all until the evidence grew back, and nothing would say so (G377). The
--       charge clock has read its latest usable fit since 0622 (ottoq_charge_clock_model); the return model now does too.
--
-- ══ §1 WHY (measured 2026-10-09 08:25-08:35 UTC, 3:25-3:35 AM CT, on live, read-only) ═════════════════════════════════════
--
--   (a) The return model learns from run-scoped engine data (ottoq_vehicle_dispatches, ottoq_recall_decisions,
--       ocpp_sessions; class 'engine', which a demo run's purge deletes), and from 30 reserve returns it is usable. Its
--       readers are four: the check's state (ottoq_charge_line_state), the inbound forecast when called without a model
--       (ottoq_charge_line_inbound), the agent's board (ottoq_agent_charge_queue_board) and the self-review (three
--       reads in ottoq_arbiter_self_assessment_v3). Each reads ottoq_learned_estimate(depot, 'return_v1'): the newest
--       fit by id, usable or not.
--   (b) It has not bitten: the twin depot's five return fits (2, 4, 6, 8, 10; 1,376-1,615 returns over 18-20 runs) are
--       all usable. It is the first production night that would find it: a depot whose evidence is still thin, or a
--       night after an outage, writes an unusable fit, and the state then carries no inbound forecast (0619's state
--       forecasts a car at work only from a usable model).
--   (c) Rule 10 holds as it was: the fit is still written every night and stays as evidence; only the reader changes, to
--       the latest fit that said it was usable, and the self-review names a newer fit it passed over.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_return_model(depot): the depot's latest usable return_v1 fit, else its latest, as
--       ottoq_learned_estimate returns it; when a newer fit was not usable, `passed_over` names it (its id, when, its
--       evidence). With the latest fit usable, ottoq_learned_estimate's answer exactly; with none, NULL.
--   (b) The four readers read it in place of ottoq_learned_estimate(depot, 'return_v1'), every call (1, 1, 1 and 3).
--   (c) The self-review: when the return model passed over a newer fit, an open area says which and from what.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running. P1 the four bodies are the ones 0636 left, each with the call the measured
--   number of times; the objects are new. V1 the reader by meaning on the twin depot's fits; every call replaced. V2 with
--   the latest fit usable (the twin depot today), the state, the inbound forecast, the board and the self-review read
--   exactly as before, on the latest stored order's run and clock. V3 the self-review. Executed by
--   tests/test_agent_return_usable_sql.py on the miniature depot.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0619-0636: the return model is read by the check on an agent's
--   charge order, its futures, the agent's board and the self-review; no kernel decision, dial or seat reads it, and no
--   certification arm runs the agent or the charge order. No dial: with every fit usable it changes nothing.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0637_pre' AND object_kind = 'function'; then
--   DROP FUNCTION public.ottoq_return_model(uuid); DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0637_the_futures_read_the_latest_return_model_that_was_usable'.

BEGIN;

-- ── P0: nothing in flight, no run running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0637 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0637 P0: a run is running; its check reads the return model this changes. Apply between runs';
  END IF;
END $inflight$;

-- ── P1: the bodies are the ones 0636 left, each with the call the measured number of times; the objects are new ──
CREATE TEMP TABLE _0637_fn (sig text, src_md5 text, calls int) ON COMMIT DROP;
INSERT INTO _0637_fn VALUES
  ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)',                    'a3fa936f617f2fd5aa9b6ee1d286a5c1', 1),
  ('public.ottoq_charge_line_inbound(uuid,uuid,timestamp with time zone,numeric,jsonb)',    '1f494446970a6003752d1cc6b88231a1', 1),
  ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)',             'd926a4802a8a1bfe3d51900e23896ca2', 1),
  ('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)',        '5699e59030d46f9154cc6ef41c3ffab2', 3);

DO $premises$
DECLARE r record; n int;
BEGIN
  FOR r IN SELECT * FROM _0637_fn LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS DISTINCT FROM r.src_md5 THEN
      RAISE EXCEPTION '0637 P1: % is not the body measured (md5 %); read it again', r.sig, left(r.src_md5, 8);
    END IF;
    n := (SELECT (length(prosrc) - length(replace(prosrc, 'public.ottoq_learned_estimate(p_depot_id, ''return_v1'')', '')))
                 / length('public.ottoq_learned_estimate(p_depot_id, ''return_v1'')')
            FROM pg_proc WHERE oid = to_regprocedure(r.sig));
    IF n IS DISTINCT FROM r.calls THEN
      RAISE EXCEPTION '0637 P1: % reads the return model % times, not %', r.sig, n, r.calls;
    END IF;
  END LOOP;
  -- no other reader in the engine's schemas
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
              WHERE s.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ 'ottoq_learned_estimate\([^)]*return_v1'
                AND p.oid::regprocedure::text NOT IN (SELECT replace(f.sig, 'public.', '') FROM _0637_fn f)) THEN
    RAISE EXCEPTION '0637 P1: a reader of the return model this does not know: %',
      (SELECT string_agg(p.oid::regprocedure::text, ', ') FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
        WHERE s.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ 'ottoq_learned_estimate\([^)]*return_v1'
          AND p.oid::regprocedure::text NOT IN (SELECT replace(f.sig, 'public.', '') FROM _0637_fn f));
  END IF;
  IF to_regprocedure('public.ottoq_return_model(uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0637_the_futures_read_the_latest_return_model_that_was_usable') THEN
    RAISE EXCEPTION '0637 P1: already applied';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0637_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN (SELECT to_regprocedure(f.sig) FROM _0637_fn f);

-- what V2 compares against: the four readers as they stood, on the latest stored order's run and clock at the twin depot
CREATE TEMP TABLE _0637_pre ON COMMIT DROP AS
SELECT s.sim_run_id, s.sim_clock,
       public.ottoq_charge_line_state(s.sim_run_id, s.depot_id, s.sim_clock) AS st,
       (SELECT jsonb_agg(to_jsonb(i) ORDER BY i.vehicle_id, i.eta_min)
          FROM public.ottoq_charge_line_inbound(s.sim_run_id, s.depot_id, s.sim_clock, NULL, NULL) i) AS inb,
       public.ottoq_agent_charge_queue_board(s.sim_run_id, s.depot_id, s.sim_clock) AS board,
       public.ottoq_arbiter_self_assessment_v3(s.depot_id, now() - interval '7 days', false) - 'generated_at' AS review
  FROM (SELECT sn.sim_run_id, sn.depot_id, sn.sim_clock FROM public.ottoq_charge_order_snapshots sn
         WHERE sn.depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY sn.order_id DESC LIMIT 1) s;

-- ══ (a) the reader ════════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_return_model(p_depot uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0637: the return model the futures read: the depot's latest usable return_v1 fit, else its latest, in the shape
  -- ottoq_learned_estimate gives, with `passed_over` naming a newer fit that was not usable. With the latest fit usable,
  -- what ottoq_learned_estimate gives for return_v1, exactly; with none, NULL.
  WITH l AS (
    SELECT e.estimate_id, e.fitted_at, e.n_evidence, e.n_runs FROM public.ottoq_learned_estimates e
     WHERE e.depot_id = p_depot AND e.model = 'return_v1' ORDER BY e.estimate_id DESC LIMIT 1
  ), u AS (
    SELECT e.estimate_id FROM public.ottoq_learned_estimates e
     WHERE e.depot_id = p_depot AND e.model = 'return_v1' AND e.usable ORDER BY e.estimate_id DESC LIMIT 1
  )
  SELECT jsonb_build_object('estimate_id', x.estimate_id, 'model', x.model, 'fitted_at', x.fitted_at, 'usable', x.usable,
                            'n_evidence', x.n_evidence, 'n_runs', x.n_runs, 'params', x.params)
         || CASE WHEN x.estimate_id <> l.estimate_id
                 THEN jsonb_build_object('passed_over', jsonb_build_object('estimate_id', l.estimate_id,
                        'fitted_at', l.fitted_at, 'n_evidence', l.n_evidence, 'n_runs', l.n_runs))
                 ELSE '{}'::jsonb END
    FROM l
    LEFT JOIN u ON true
    JOIN public.ottoq_learned_estimates x ON x.estimate_id = COALESCE(u.estimate_id, l.estimate_id)
$fn$;

COMMENT ON FUNCTION public.ottoq_return_model(uuid) IS
'0637. The return model the check''s futures, the agent''s board and the self-review read: the depot''s latest usable return_v1 fit, else its latest, with `passed_over` naming a newer fit that was not usable (G377). The fit is still written every night and kept as evidence; only the reader skips one that said it was not usable.';

GRANT EXECUTE ON FUNCTION public.ottoq_return_model(uuid) TO anon, authenticated, service_role;

-- ══ (b) (c) the readers: every call; the review's area ════════════════════════════════════════════════════════════════════
DO $patch$
DECLARE
  f record; v_def text; n int;
  c_old constant text := 'public.ottoq_learned_estimate(p_depot_id, ''return_v1'')';
  c_new constant text := 'public.ottoq_return_model(p_depot_id)';
  c_area_old constant text := '  -- (9) the win probability, and the bar';
  c_area_new constant text :=
'  -- 0637: the return model passed over a newer fit that was not usable (G377)
  IF public.ottoq_return_model(p_depot_id) ? ''passed_over'' THEN
    v_areas := v_areas || jsonb_build_object(
      ''area'', ''return_model_passed_over'', ''kind'', ''capability_gap'', ''part'', NULL, ''status'', ''open'',
      ''thin'', false, ''tier'', 3, ''weight'', v_n,
      ''title'', ''The return model''''s latest fit was not usable'',
      ''finding'', ''The fit of '' || to_char((public.ottoq_return_model(p_depot_id) #>> ''{passed_over,fitted_at}'')::timestamptz, ''YYYY-MM-DD HH24:MI'')
                 || '' UTC found '' || (public.ottoq_return_model(p_depot_id) #>> ''{passed_over,n_evidence}'')
                 || '' returns, too few to be usable, so the futures forecast cars at work by the fit of ''
                 || to_char((public.ottoq_return_model(p_depot_id) ->> ''fitted_at'')::timestamptz, ''YYYY-MM-DD HH24:MI'')
                 || '' UTC, the latest that was. Its evidence is the engine''''s run-scoped data, which a demo run''''s purge deletes.'',
      ''action'', ''Keep the returns as evidence, as the charge clock keeps its charges, so the model''''s evidence cannot thin.'',
      ''evidence'', public.ottoq_return_model(p_depot_id) -> ''passed_over'');
  END IF;

  -- (9) the win probability, and the bar';
BEGIN
  FOR f IN SELECT * FROM _0637_fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.sig));
    n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
    IF n <> f.calls THEN
      RAISE EXCEPTION '0637 %: the call appears % times, not %', f.sig, n, f.calls;
    END IF;
    v_def := replace(v_def, c_old, c_new);
    IF f.sig LIKE 'public.ottoq_arbiter_self_assessment_v3(%' THEN
      n := (length(v_def) - length(replace(v_def, c_area_old, ''))) / length(c_area_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0637 %: the review''s anchor appears % times, not 1', f.sig, n;
      END IF;
      v_def := replace(v_def, c_area_old, c_area_new);
    END IF;
    EXECUTE v_def;
    -- V1: the stored definition is the pre-image with exactly these replacements
    IF pg_get_functiondef(to_regprocedure(f.sig)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0637 V1: % is not stored as patched', f.sig;
    END IF;
  END LOOP;
END $patch$;

-- ══ V1: the reader by meaning; every call replaced ════════════════════════════════════════════════════════════════════════
DO $v1$
DECLARE c_twin constant uuid := '11111111-1111-1111-1111-111111111111'; v_a jsonb; v_b jsonb;
BEGIN
  v_a := public.ottoq_learned_estimate(c_twin, 'return_v1');
  v_b := public.ottoq_return_model(c_twin);
  IF COALESCE((v_a ->> 'usable')::boolean, false) AND v_b IS DISTINCT FROM v_a THEN
    RAISE EXCEPTION '0637 V1: with the latest fit usable the reader is not ottoq_learned_estimate''s answer';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
              WHERE s.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ 'ottoq_learned_estimate\([^)]*return_v1') THEN
    RAISE EXCEPTION '0637 V1: a reader still reads the newest return fit whatever it says';
  END IF;
  IF (SELECT count(*) FROM pg_proc p WHERE p.prosrc LIKE '%public.ottoq_return_model(p_depot_id)%') <> 4 THEN
    RAISE EXCEPTION '0637 V1: the four readers do not read the usable model';
  END IF;
  RAISE NOTICE '0637 V1: the twin depot''s return model is fit % (latest fit %, usable %); every reader reads it',
    v_b ->> 'estimate_id', v_a ->> 'estimate_id', v_a ->> 'usable';
END $v1$;

-- ══ V2: with the latest fit usable, the four readers read exactly as before ═══════════════════════════════════════════════
DO $v2$
DECLARE p record; v_same text := '';
BEGIN
  SELECT * INTO p FROM _0637_pre;
  IF p.sim_run_id IS NULL THEN
    RAISE NOTICE '0637 V2: no stored order to read; executed by the tests';
    RETURN;
  END IF;
  IF NOT COALESCE((public.ottoq_learned_estimate('11111111-1111-1111-1111-111111111111', 'return_v1') ->> 'usable')::boolean, false) THEN
    RAISE NOTICE '0637 V2: the twin depot''s latest return fit is not usable; the readers changed on purpose';
    RETURN;
  END IF;
  IF public.ottoq_charge_line_state(p.sim_run_id, '11111111-1111-1111-1111-111111111111', p.sim_clock) IS DISTINCT FROM p.st
     OR (SELECT jsonb_agg(to_jsonb(i) ORDER BY i.vehicle_id, i.eta_min)
           FROM public.ottoq_charge_line_inbound(p.sim_run_id, '11111111-1111-1111-1111-111111111111', p.sim_clock, NULL, NULL) i)
          IS DISTINCT FROM p.inb
     OR public.ottoq_agent_charge_queue_board(p.sim_run_id, '11111111-1111-1111-1111-111111111111', p.sim_clock)
          IS DISTINCT FROM p.board
     OR public.ottoq_arbiter_self_assessment_v3('11111111-1111-1111-1111-111111111111', now() - interval '7 days', false)
          - 'generated_at' IS DISTINCT FROM p.review THEN
    RAISE EXCEPTION '0637 V2: a reader changed while the latest return fit is usable';
  END IF;
  RAISE NOTICE '0637 V2: with the latest return fit usable, the state, the inbound forecast, the board and the self-review read exactly as before (run %, sim %)',
    left(p.sim_run_id::text, 8), p.sim_clock;
END $v2$;

-- ══ V3: the self-review ═══════════════════════════════════════════════════════════════════════════════════════════════════
DO $v3$
DECLARE v jsonb; v_t timestamptz := clock_timestamp();
BEGIN
  v := public.ottoq_arbiter_self_assessment_v3('11111111-1111-1111-1111-111111111111', now() - interval '7 days', false);
  RAISE NOTICE '0637 V3: the self-review in % ms; its return model area: %', round(extract(epoch FROM clock_timestamp() - v_t) * 1000),
    COALESCE((SELECT x.value ->> 'finding' FROM jsonb_array_elements(v -> 'improvement_areas') x
               WHERE x.value ->> 'area' = 'return_model_passed_over'), 'none (no newer fit was passed over)');
END $v3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0637_the_futures_read_the_latest_return_model_that_was_usable', false, false,
  'the check''s state, the inbound forecast, the agent''s board and the self-review read the depot''s latest usable return '
  'model (ottoq_return_model) in place of the newest fit whatever it said, and the review names a newer fit it passed '
  'over (G377). FALSE/FALSE as 0619-0636: the return model is read by the check on an agent''s charge order, its futures, '
  'the agent''s board and the self-review; no kernel decision, dial or seat reads it, and no certification arm runs the '
  'agent or the charge order.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
