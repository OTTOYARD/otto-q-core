-- migration-version: 20260926062937
-- migration-name:    the_run_list_showed_certification_arms_and_pushed_the_operators_own_runs_off_it
--
-- 0470  **The run list showed the certification harness's arms and pushed the operator's own runs off it.**
--       FINDINGS G202.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   2026-09-26 06:10 UTC, mid-sweep: `ottoq_sim_runs` held 130 runs, 120 of them arms of a harness pair (determinism
--   recert, dial experiment or A/B) and 10 the operator's. `public.ottoq_twin_run_list` returns the newest 50 by
--   start time, so the twin cockpit's Runs tab listed 30 arms of the recert sweep then running and none of the
--   operator's runs: validation run 317d4331, stopped 80 minutes earlier, was already off the list. Every forcing
--   migration triggers a sweep of 18 arms, so this recurs after every engine change.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The list leaves out harness arms. All three harnesses (`ottoq_determinism_pair`, `ottoq_dial_pair`,
--   `ottoq_ab_pair`) stamp `validation_status` on both arm runs, and an operator's run never has one, so the filter is
--   `validation_status IS NULL`. The arms' verdicts keep their own ledgers (`ottoq_determinism_verdict_ledger`,
--   `ottoq_dial_pair_ledger`) and matrix; nothing there reads this list. Counters, fields and shape are unchanged.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   Reporting only: the edge function `otto-twin-control` (GET /sim_runs) is the one caller, and no tick path reads it.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0470 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured (after 0466) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_twin_run_list(integer)'::regprocedure)) <> '2118c0cdc40c1bac8c3b2b297b29c7b2' THEN
    RAISE EXCEPTION '0470 P2: public.ottoq_twin_run_list is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0470_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_twin_run_list(integer)'::regprocedure;

DO $patch_list$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_twin_run_list(integer)'::regprocedure);
  v_pat text := $p$FROM ottoq_sim_runs sr0\s+ORDER BY sr0\.started_at DESC NULLS LAST, sr0\.sim_run_id$p$;
  v_new text := $r$FROM ottoq_sim_runs sr0
      -- 0470 (G202): the operator's runs only. Every harness (determinism, dial, A/B pair) stamps validation_status
      -- on its arms and an operator's run never has one; a recert sweep's 18 arms had pushed every run off the list.
      WHERE sr0.validation_status IS NULL
      ORDER BY sr0.started_at DESC NULLS LAST, sr0.sim_run_id$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0470: the run cursor matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_list$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_list jsonb := public.ottoq_twin_run_list(50);
        v_newest uuid;
BEGIN
  -- V1: no harness arm is listed.
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_list) e
               JOIN public.ottoq_sim_runs r ON r.sim_run_id = (e->>'sim_run_id')::uuid
              WHERE r.validation_status IS NOT NULL) THEN
    RAISE EXCEPTION '0470 V1: a harness arm is still listed';
  END IF;
  -- V2: the newest operator run is the first row.
  SELECT sim_run_id INTO v_newest FROM public.ottoq_sim_runs WHERE validation_status IS NULL
   ORDER BY started_at DESC NULLS LAST, sim_run_id LIMIT 1;
  IF v_newest IS NOT NULL AND (v_list->0->>'sim_run_id')::uuid IS DISTINCT FROM v_newest THEN
    RAISE EXCEPTION '0470 V2: the newest operator run % is not first', v_newest;
  END IF;
  -- V3: same grants as before (the browser key never had it; the edge function calls it).
  IF has_function_privilege('anon', 'public.ottoq_twin_run_list(integer)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_twin_run_list(integer)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_twin_run_list(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '0470 V3: the grants moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0470_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0470_the_run_list_showed_certification_arms_and_pushed_the_operators_own_runs_off_it', false,
  'Reporting: public.ottoq_twin_run_list leaves out harness arms (validation_status set). No tick path calls it.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
