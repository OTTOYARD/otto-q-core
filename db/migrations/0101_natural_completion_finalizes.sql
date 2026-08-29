-- migration-version: 20260830020000
-- migration-name:    natural_completion_finalizes
-- 0101 -- closes the latent teardown gap found during V2: twin.ottoq_sim_advance_clock's
-- natural-completion branch (sim clock reaches sim_clock_end) sets status='completed', emits
-- twin.sim_run_completed, and RETURNs -- without ever calling the finalizer. A run that ends
-- this way would skip everything the finalizer guarantees: bookings released, commands expired
-- (0087), legs closed (0089), plan residue stripped (0093), approvals expired (0097),
-- tasks_completed tallied, the archive written.
--
-- LATENT, not yet acute: zero twin.sim_run_completed events exist -- every historical run ended
-- via an explicit stop (governor ceiling, stall watchdog, or operator). But the branch is live
-- code one long-enough run away from firing, and a completed run with open ledgers would fail
-- checks R4/R11 for a reason nobody could see in the stop path.
--
-- ONE PATCH: after the completion event, pin the event-tagging GUC (0092 discipline -- explicit
-- beats relying on the transaction cache) and run public.ottoq_sim_release_depot with reason
-- 'sim_clock_end_reached', failure-isolated so a teardown error can never mask the completion
-- itself. mark_stopped is NOT needed: this branch already wrote status/ended_at itself.
--
-- Pre-image pin, read live 2026-08-29 (anchor verified at exactly 1 occurrence):
--   twin.ottoq_sim_advance_clock   ea85be3780d62e4ed30a5f22afa11939

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_a_old text := E'      p_data_source := ''twin'', p_sim_run_id := p_sim_run_id\n'
               || E'    );\n'
               || E'    RETURN NULL;\n'
               || E'  END IF;';
  v_a_new text := E'      p_data_source := ''twin'', p_sim_run_id := p_sim_run_id\n'
               || E'    );\n'
               || E'    -- 0101: a run that completes naturally gets the SAME teardown as a stopped one.\n'
               || E'    -- Without this, natural completion left every ledger open (commands, legs,\n'
               || E'    -- approvals, plan residue) and wrote no archive -- checks R4/R11 red with no\n'
               || E'    -- visible cause. GUC pinned per 0092 so teardown events carry this run.\n'
               || E'    BEGIN\n'
               || E'      PERFORM set_config(''ottoq.sim_run_id'', p_sim_run_id::text, true);\n'
               || E'      PERFORM public.ottoq_sim_release_depot(p_sim_run_id, ''sim_clock_end_reached'');\n'
               || E'    EXCEPTION WHEN OTHERS THEN\n'
               || E'      RAISE WARNING ''advance_clock completion teardown FAILED: % %'', SQLSTATE, SQLERRM;\n'
               || E'    END;\n'
               || E'    RETURN NULL;\n'
               || E'  END IF;';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_clock';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'ea85be3780d62e4ed30a5f22afa11939' THEN
    RAISE EXCEPTION '0101 abort: advance_clock drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a_old, ''))) / length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0101 abort: completion-branch anchor found % times', v_cnt; END IF;

  EXECUTE replace(v_src, v_a_old, v_a_new);

  IF position('sim_clock_end_reached' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0101 abort: patch did not survive';
  END IF;

  RAISE NOTICE '0101 applied: natural completion finalizes.';
END
$do$;
