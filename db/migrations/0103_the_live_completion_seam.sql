-- migration-version: 20260830030000
-- migration-name:    the_live_completion_seam
-- 0103 -- third and final round of the natural-completion teardown (0101 -> 0102 -> here),
-- each round caught by the same forced-completion smoke before anything real depended on it.
--
-- WHAT THE SMOKES ESTABLISHED:
--   0101 put the finalize inside twin.ottoq_sim_advance_clock -- but the LIVE tick path never
--   calls that function. public.ottoq_sim_advance_tick_world computes the clock ITSELF, writes
--   status='completed' mid-function (its clock UPDATE: status=CASE WHEN v_completed ...), keeps
--   running its remaining phases, and returns out_completed=TRUE with out_sim_clock_after SET.
--   0102 moved the finalize to the driver's early branch -- which requires
--   out_sim_clock_after IS NULL and therefore NEVER fires on this path. Worse, the driver then
--   runs ottoq_sim_decide_and_dispatch even on the completed tick (pre-existing behavior:
--   17-19 commands issued post-completion in every smoke).
--
-- THE FIX: finalize at the driver's TAIL -- after the world function AND the decide/dispatch
-- pass have both fully returned -- whenever the world reported completion. That expires the
-- post-completion commands (0087), closes the legs (0089), strips residue (0093), expires
-- approvals (0097), and writes the archive, exactly as a governor stop would. The 0102 early
-- branch stays: it is unreachable on this world impl but correct if an alternate world
-- function ever does return a NULL clock.
--
-- Pre-image pin, read live 2026-08-29 (anchor verified at exactly 1 occurrence):
--   public.ottoq_sim_advance_tick   816ec155726fa6fb04e24dd308a24048  (post-0102)

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_a_old text := E'  out_completed:=w.out_completed;\n  RETURN NEXT;';
  v_a_new text := E'  out_completed:=w.out_completed;\n'
               || E'  -- 0103: the LIVE completion seam. advance_tick_world writes status=''completed''\n'
               || E'  -- mid-function and still returns a non-NULL clock, so the early branch above\n'
               || E'  -- never fires; decide_and_dispatch has also already run (and may have issued\n'
               || E'  -- commands post-completion -- the finalizer expires them). Finalize HERE, after\n'
               || E'  -- the full tick. GUC pinned per 0092 so teardown events carry this run.\n'
               || E'  IF w.out_completed THEN\n'
               || E'    BEGIN\n'
               || E'      PERFORM set_config(''ottoq.sim_run_id'', p_sim_run_id::text, true);\n'
               || E'      PERFORM ottoq_sim_release_depot(p_sim_run_id, ''sim_clock_end_reached'');\n'
               || E'    EXCEPTION WHEN OTHERS THEN\n'
               || E'      RAISE WARNING ''advance_tick completion teardown FAILED: % %'', SQLSTATE, SQLERRM;\n'
               || E'    END;\n'
               || E'  END IF;\n'
               || E'  RETURN NEXT;';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_advance_tick';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '816ec155726fa6fb04e24dd308a24048' THEN
    RAISE EXCEPTION '0103 abort: advance_tick drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a_old, ''))) / length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0103 abort: tail anchor found % times', v_cnt; END IF;

  EXECUTE replace(v_src, v_a_old, v_a_new);

  IF position('the LIVE completion seam' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0103 abort: patch did not survive';
  END IF;

  RAISE NOTICE '0103 applied: natural completion finalizes at the live seam.';
END
$do$;
