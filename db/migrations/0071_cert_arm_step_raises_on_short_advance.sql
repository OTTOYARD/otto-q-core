-- migration-version: 20260824200500
-- migration-name:    cert_arm_step_raises_on_short_advance
-- 0071 -- HARNESS ONLY. public.ottoq_cert_arm_step now RAISES when it advances fewer ticks than
-- it was asked for, instead of returning the smaller number and saying nothing.
--
-- THE DEFECT. The loop exits the moment the run is no longer 'running' and then returns the
-- count it managed. A caller that does not compare the return value to what it requested cannot
-- tell a certification run that happened from one that did not. Observed live on 2026-08-23:
-- run c8a4fbe4 was flipped from 'running' to 'completed' at tick_count 0 by something outside
-- the harness between the arm and the first step; the step was asked for 8 ticks, advanced 0,
-- returned 0, and raised nothing. Every downstream artifact of that run would have been scored
-- and archived as though it were a real 20-tick certification.
--
-- WHY THIS IS THE FIRST FIX IN THE SEQUENCE. It is not the largest problem with the benchmark,
-- but it is the one that makes every other investigation unreliable: a silent short advance
-- corrupts the very experiments used to diagnose the others. It blocked the controlled test of
-- the run-residue hypothesis in docs/RUN_ISOLATION_FINDING.md §3.
--
-- SCOPE. ottoq_cert_arm_step is the determinism harness's stepping entry point and has no
-- caller outside it. The exception carries the run, the requested and actual tick counts, and
-- the status that stopped it, so the failure names its own cause rather than requiring a
-- follow-up query. Production scheduling semantics are untouched.
--
-- Same self-verifying in-place mechanism as 0054-0070. Pre-image pin:
--   public.ottoq_cert_arm_step eabbe6b1b0c2afcb7da382c6f0c14afb
-- Anchor pre-verified read-only: exactly one occurrence.

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := E'  RETURN v_done;\nEND;';
  v_new text := E'  /* ══════════ 0071: A SHORT ADVANCE IS A FAILURE, NOT A RETURN VALUE ══════════\n     The loop above stops as soon as the run stops being ''running''. Returning the count\n     quietly makes a certification that never happened indistinguishable from one that did,\n     for any caller that does not compare this number against what it asked for. Measured on\n     2026-08-23: run c8a4fbe4 was flipped to ''completed'' at tick 0 by something outside this\n     harness between the arm and the first step; 8 ticks were requested, 0 advanced, 0 returned,\n     nothing raised. The exception below names the run, both counts and the status that stopped\n     it, so the failure explains itself without a follow-up query. */\n  IF v_done IS DISTINCT FROM p_ticks THEN\n    RAISE EXCEPTION ''cert_arm_step: advanced % of % requested ticks on run % (status is now %). A certification run that did not happen must not be scored as one that did.'',\n      v_done, p_ticks, p_run,\n      COALESCE((SELECT status FROM ottoq_sim_runs WHERE sim_run_id = p_run), ''<run row missing>'');\n  END IF;\n\n  RETURN v_done;\nEND;';
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'public' AND pr.proname = 'ottoq_cert_arm_step';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'eabbe6b1b0c2afcb7da382c6f0c14afb' THEN
    RAISE EXCEPTION '0071: pre-image md5 % != pinned eabbe6b1b0c2afcb7da382c6f0c14afb', md5(v_src);
  END IF;

  v_cnt := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0071: anchor occurs % times (need 1)', v_cnt; END IF;
  v_src := replace(v_src, v_old, v_new);

  /* Post-conditions, phrased so no comment text in this migration can satisfy them by
     accident -- the trap 0067 and 0068 each fell into once. */
  IF position('IF v_done IS DISTINCT FROM p_ticks THEN' in v_src) = 0 THEN
    RAISE EXCEPTION '0071: the short-advance guard is not present';
  END IF;
  IF position('RAISE EXCEPTION' in v_src) = 0 THEN
    RAISE EXCEPTION '0071: the guard does not raise';
  END IF;
  IF position('IF v_done IS DISTINCT FROM p_ticks THEN' in v_src)
     > position('RETURN v_done;' in v_src) THEN
    RAISE EXCEPTION '0071: the guard must run BEFORE the return';
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, 'ottoq_sim_advance_and_snapshot', '')))
           / length('ottoq_sim_advance_and_snapshot');
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0071: the tick body was disturbed -- advance appears % times (need 1)', v_cnt;
  END IF;

  EXECUTE v_src;
  RAISE NOTICE '0071 patched public.ottoq_cert_arm_step -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'ottoq_cert_arm_step');
END
$do$;
