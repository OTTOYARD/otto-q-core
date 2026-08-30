-- migration-version: 20260830090000
-- migration-name:    the_watermark_does_not_outlive_its_run
-- 0109 -- the last start-state carry the pair-14/15 comparison exposed. run_boot_draw's
-- step 1c anchors vehicle_need_profile.wear_km_applied from the NEW run's wear rows -- and a
-- new run has none, so the UPDATE..FROM matches zero rows and the column silently keeps the
-- PREVIOUS run's mid-run watermark (ottoq_wear_mark_serviced re-anchors it during a run).
-- Behaviorally dead across runs -- mark_serviced's own guard treats a foreign-run watermark
-- as "unknown -> credit 0 and re-anchor" -- but it made two starts after different-seed
-- predecessors fingerprint differently (pair 14: arm A followed a 171717 run, arm B a
-- 424242 run). Pairs 13 and 15 proved equality whenever predecessors matched; this makes
-- the start state seed-only, so the fingerprint stops depending on run HISTORY.
--
-- ONE PATCH: after the 1c anchor, clear the watermark on every profile row the anchor did
-- not reach (wear_km_applied_run <> this run): wear_km_applied/wear_km_applied_run -> NULL.
-- NULL is mark_serviced's documented "unknown" -- first completion credits 0 km and
-- re-anchors, exactly the pre-existing foreign-run behavior, now stated in the row itself.
--
-- Pre-image pin, read live 2026-08-30 (anchor verified at exactly 1 occurrence):
--   public.ottoq_run_boot_draw   ea2cc2924cbf8b5ab4da4f1dcc7b3feb

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_a_old text := 'GET DIAGNOSTICS v_anchored = ROW_COUNT;';
  v_a_new text := E'GET DIAGNOSTICS v_anchored = ROW_COUNT;\n'
               || E'    -- 0109: a watermark the anchor could not reach is the PREVIOUS run''s -- clear it\n'
               || E'    -- so the start state is a function of the seed alone, not of run history.\n'
               || E'    UPDATE public.vehicle_need_profile p\n'
               || E'       SET wear_km_applied = NULL, wear_km_applied_run = NULL\n'
               || E'     WHERE p.wear_km_applied_run IS DISTINCT FROM p_sim_run_id\n'
               || E'       AND (p.wear_km_applied IS NOT NULL OR p.wear_km_applied_run IS NOT NULL);';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_run_boot_draw';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'ea2cc2924cbf8b5ab4da4f1dcc7b3feb' THEN
    RAISE EXCEPTION '0109 abort: run_boot_draw drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_a_old,'')))/length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0109 abort: 1c anchor found % times', v_cnt; END IF;

  EXECUTE replace(v_src, v_a_old, v_a_new);

  IF position('0109: a watermark the anchor could not reach' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0109 abort: patch did not survive';
  END IF;

  RAISE NOTICE '0109 applied: the watermark does not outlive its run.';
END
$do$;
