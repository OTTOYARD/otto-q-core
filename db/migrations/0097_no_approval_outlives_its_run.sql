-- migration-version: 20260829234500
-- migration-name:    no_approval_outlives_its_run
-- 0097 -- the first of check 0046's two in-run nondeterminism mechanisms, fixed at the
-- teardown seam like its siblings (0087 commands, 0089 legs, 0093 plan residue).
--
-- MEASURED (second determinism pair, arms 05553150/e1fe726c): both arms started from
-- byte-identical worlds (same fingerprint) and diverged at tick 2 by five staging decisions.
-- ottoq_ops_approvals is written per run (rows carry sim_run_id) but its THIRTEEN reader
-- functions filter on vehicle/type/status only -- so arm B read arm A's 'approved' rows.
-- The rows on hand are opportunistic_charge / indepot_reassign: an inherited approval
-- suppresses the next run's own request/decide cycle, charging shifts, staging follows
-- (20 vs 32 proposals across the pair is the same drift seen downstream).
--
-- ONE PATCH, one seam, instead of thirteen scoped readers: the finalizer expires the run's
-- still-open approvals ('pending'/'approved' -> 'expired', prior status preserved in the
-- payload). One depot runs one run at a time, so once no approval outlives its run, no run
-- can read another's. Historical stale rows stay as evidence: they are FROZEN (nothing
-- writes them again), hence identical for every future arm -- determinism is unaffected,
-- and the trail keeps its history.
--
-- Pre-image pin, read live 2026-08-29 (anchor verified at exactly 1 occurrence):
--   public.ottoq_sim_release_depot   754e0d1aa21cacd1f9488962ade05d19  (post-0093)

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;

  -- Anchor: the 0087 command-expiry block; approvals expire right after commands do.
  v_a_old text := E'   WHERE sim_run_id = p_sim_run_id AND status IN (''issued'',''confirmed'');';
  v_a_new text := E'   WHERE sim_run_id = p_sim_run_id AND status IN (''issued'',''confirmed'');\n'
               || E'\n'
               || E'  -- 0097: no approval outlives its run. Readers filter on vehicle/type/status only,\n'
               || E'  -- so a surviving ''approved'' row is readable by the NEXT run''s gates -- the tick-2\n'
               || E'  -- divergence channel of the 0046 determinism pair. Prior status kept in payload.\n'
               || E'  BEGIN\n'
               || E'    UPDATE ottoq_ops_approvals\n'
               || E'       SET payload = COALESCE(payload,''{}''::jsonb)\n'
               || E'                     || jsonb_build_object(''expired_from'', status,\n'
               || E'                                           ''expired_reason'', ''run_ended''),\n'
               || E'           status = ''expired'',\n'
               || E'           decided_at = COALESCE(decided_at, now()),\n'
               || E'           decided_by = COALESCE(decided_by, ''run_finalizer'')\n'
               || E'     WHERE sim_run_id = p_sim_run_id AND status IN (''pending'',''approved'');\n'
               || E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''release_depot approval expiry: %'', SQLERRM; END;';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_release_depot';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '754e0d1aa21cacd1f9488962ade05d19' THEN
    RAISE EXCEPTION '0097 abort: release_depot drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a_old, ''))) / length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0097 abort: command-expiry anchor found % times', v_cnt; END IF;

  EXECUTE replace(v_src, v_a_old, v_a_new);

  IF position('no approval outlives its run' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0097 abort: patch did not survive';
  END IF;

  RAISE NOTICE '0097 applied: the finalizer expires the run''s open approvals.';
END
$do$;
