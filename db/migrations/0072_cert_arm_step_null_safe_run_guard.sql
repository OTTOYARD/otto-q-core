-- migration-version: 20260824201500
-- migration-name:    cert_arm_step_null_safe_run_guard
-- 0072 -- HARNESS ONLY. public.ottoq_cert_arm_step's loop guard becomes NULL-safe, so a run
-- that does not exist stops the loop instead of being advanced.
--
-- FOUND BY 0071'S OWN VERIFICATION TEST, which is the reason that test existed. Immediately
-- after applying 0071 the guard was exercised against a deliberately absent run:
--
--     SELECT public.ottoq_cert_arm_step('00000000-...-000000000000'::uuid, 3);   -- returned 3
--
-- It returned 3. It reported advancing three ticks on a run with no row. The loop guard reads
--
--     EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id = p_run) <> 'running';
--
-- and for a missing run that subquery is NULL, so the comparison is NULL, which is not TRUE,
-- so EXIT never fires. The loop then ran to completion, v_done equalled p_ticks, and 0071's new
-- short-advance guard was satisfied -- a full, clean, entirely fictitious success.
--
-- This is strictly worse than the defect 0071 fixed. 0071 stopped a run that half-happened from
-- being reported as whole; this stops a run that never existed from being reported as perfect.
-- Verified harmless in the instance that exposed it: ottoq_sim_advance_and_snapshot no-ops on a
-- missing run, so zero snapshots, decisions, sessions and bookings were written under the null
-- UUID. The damage was to the REPORT, not to the data -- which is precisely the failure mode
-- the certification exists to prevent.
--
-- IS DISTINCT FROM is the fix rather than COALESCE to a sentinel, because the sentinel would be
-- a string that could in principle collide with a real status value; IS DISTINCT FROM has no
-- such value to choose.
--
-- Same self-verifying in-place mechanism as 0054-0071. Pre-image pin:
--   public.ottoq_cert_arm_step ac9f944d31ea38a7d7dd22fefdebca39   (the 0071 post-image)
-- Anchor pre-verified read-only: exactly one occurrence.

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := E'    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=p_run) <> ''running'';';
  v_new text := E'    /* 0072: NULL-safe. A missing run row makes the subquery NULL, and a NULL comparison\n       is not TRUE, so the old form never exited and reported a fictitious full advance. */\n    EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=p_run) IS DISTINCT FROM ''running'';';
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'public' AND pr.proname = 'ottoq_cert_arm_step';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'ac9f944d31ea38a7d7dd22fefdebca39' THEN
    RAISE EXCEPTION '0072: pre-image md5 % != pinned ac9f944d31ea38a7d7dd22fefdebca39', md5(v_src);
  END IF;

  v_cnt := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0072: anchor occurs % times (need 1)', v_cnt; END IF;
  v_src := replace(v_src, v_old, v_new);

  /* Post-conditions. Deliberately assert on the EXIT statement itself, not on the bare phrase,
     so this migration's own comment cannot satisfy them -- the trap 0067 and 0068 each hit. */
  IF position(E'EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=p_run) IS DISTINCT FROM ''running'';' in v_src) = 0 THEN
    RAISE EXCEPTION '0072: the NULL-safe exit guard is not present';
  END IF;
  IF position(E'EXIT WHEN (SELECT status FROM ottoq_sim_runs WHERE sim_run_id=p_run) <> ''running'';' in v_src) <> 0 THEN
    RAISE EXCEPTION '0072: the NULL-blind exit guard survived';
  END IF;
  IF position('IF v_done IS DISTINCT FROM p_ticks THEN' in v_src) = 0 THEN
    RAISE EXCEPTION '0072: 0071 short-advance guard was lost';
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, 'ottoq_sim_advance_and_snapshot', '')))
           / length('ottoq_sim_advance_and_snapshot');
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0072: the tick body was disturbed -- advance appears % times (need 1)', v_cnt;
  END IF;

  EXECUTE v_src;
  RAISE NOTICE '0072 patched public.ottoq_cert_arm_step -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'ottoq_cert_arm_step');
END
$do$;
