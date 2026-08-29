-- migration-version: 20260830023000
-- migration-name:    finalize_at_the_driver_not_mid_world
-- 0102 -- corrects 0101, caught by its own smoke test BEFORE any real run depended on it.
--
-- 0101 called the finalizer from inside twin.ottoq_sim_advance_clock's completion branch.
-- The smoke (natural completion forced one tick out, rolled back) showed status='completed'
-- with 19 commands and 127 legs still open and zero archive: the teardown ran MID-WORLD --
-- advance_clock sits inside the tick's phase sequence, where in-flight state (arm cycles
-- mid-mate, vehicles mid-move) can legitimately make teardown statements raise, and 0101's
-- failure isolation then rolled the WHOLE teardown back to its savepoint and only warned.
-- Proof of the correct seam: the identical release_depot call made AFTER
-- ottoq_sim_advance_tick returned succeeded cleanly ({ok:true, archived:true} on the same
-- forced-completion state).
--
-- TWO PATCHES:
--   A. twin.ottoq_sim_advance_clock: revert the 0101 block verbatim -- the completion branch
--      goes back to event + RETURN.
--   B. public.ottoq_sim_advance_tick (the tick DRIVER): its existing completion branch
--      ("world reported completed") gains the finalize -- after the world function has fully
--      returned, every phase loop closed, same transaction. GUC pinned per 0092;
--      failure-isolated so a teardown error cannot mask completion.
--
-- Pre-image pins, read live 2026-08-29 (each anchor verified at exactly 1 occurrence):
--   twin.ottoq_sim_advance_clock    68ff861092ea4361cffe4167e5ad20cb  (post-0101)
--   public.ottoq_sim_advance_tick   434c324f23c60db79ee5a80f1e0d7a18

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;

  -- A: the exact 0101 insertion, reverted to the original completion tail.
  v_a_old text := E'    -- 0101: a run that completes naturally gets the SAME teardown as a stopped one.\n'
               || E'    -- Without this, natural completion left every ledger open (commands, legs,\n'
               || E'    -- approvals, plan residue) and wrote no archive -- checks R4/R11 red with no\n'
               || E'    -- visible cause. GUC pinned per 0092 so teardown events carry this run.\n'
               || E'    BEGIN\n'
               || E'      PERFORM set_config(''ottoq.sim_run_id'', p_sim_run_id::text, true);\n'
               || E'      PERFORM public.ottoq_sim_release_depot(p_sim_run_id, ''sim_clock_end_reached'');\n'
               || E'    EXCEPTION WHEN OTHERS THEN\n'
               || E'      RAISE WARNING ''advance_clock completion teardown FAILED: % %'', SQLSTATE, SQLERRM;\n'
               || E'    END;\n'
               || E'    RETURN NULL;';
  v_a_new text := E'    RETURN NULL;';

  -- B: the driver's completion branch.
  v_b_old text := E'  IF w.out_completed AND w.out_sim_clock_after IS NULL THEN\n'
               || E'    out_completed:=TRUE; RETURN NEXT; RETURN;\n'
               || E'  END IF;';
  v_b_new text := E'  IF w.out_completed AND w.out_sim_clock_after IS NULL THEN\n'
               || E'    -- 0102: a run that completes naturally gets the SAME teardown as a stopped one.\n'
               || E'    -- Finalized HERE -- after the world function has returned and every phase loop\n'
               || E'    -- closed -- because mid-world teardown (0101''s seam) trips on in-flight state.\n'
               || E'    -- GUC pinned per 0092 so teardown events carry this run.\n'
               || E'    BEGIN\n'
               || E'      PERFORM set_config(''ottoq.sim_run_id'', p_sim_run_id::text, true);\n'
               || E'      PERFORM ottoq_sim_release_depot(p_sim_run_id, ''sim_clock_end_reached'');\n'
               || E'    EXCEPTION WHEN OTHERS THEN\n'
               || E'      RAISE WARNING ''advance_tick completion teardown FAILED: % %'', SQLSTATE, SQLERRM;\n'
               || E'    END;\n'
               || E'    out_completed:=TRUE; RETURN NEXT; RETURN;\n'
               || E'  END IF;';
BEGIN
  -- ---------- A: revert 0101 ----------
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_clock';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '68ff861092ea4361cffe4167e5ad20cb' THEN
    RAISE EXCEPTION '0102 abort: advance_clock drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a_old, ''))) / length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0102 abort: 0101 block found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_a_old, v_a_new);
  IF position('sim_clock_end_reached' in pg_get_functiondef(v_oid)) > 0 THEN
    RAISE EXCEPTION '0102 abort: 0101 block did not revert';
  END IF;

  -- ---------- B: finalize at the driver ----------
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_advance_tick';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '434c324f23c60db79ee5a80f1e0d7a18' THEN
    RAISE EXCEPTION '0102 abort: advance_tick drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_b_old, ''))) / length(v_b_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0102 abort: driver branch anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_b_old, v_b_new);
  IF position('sim_clock_end_reached' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0102 abort: driver patch did not survive';
  END IF;

  RAISE NOTICE '0102 applied: natural completion finalizes at the driver seam.';
END
$do$;
