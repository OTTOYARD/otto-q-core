-- migration-version: 20260830060000
-- migration-name:    the_production_brain_stands_off_a_cert_run
-- 0106 -- the last contamination path pair 9 exposed. With 0104+0105 applied, two same-seed
-- 12-tick arms (466a8404 / 2b970077) produced byte-identical COMMAND (671/671), DECISION
-- (1856/1856) and BOOKING streams -- and the event multiset differed by exactly SIX
-- vehicle.state_changed rows, all stamped 23:08:00.602, on the minute boundary, only in the
-- arm that happened to be alive when the ottoq-depot-tick cron fired.
--
-- ROOT: public.ottoq_cron_tick's idle gate is
--     IF NOT EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status='running') THEN RETURN;
-- ANY running run satisfies it -- a cert_harness determinism arm included. The cron then
-- runs the whole production brain against the flagship depot: ottoq_world_advance(), the
-- ottoq-orchestrate-tick edge function (submit=true), the orchestrator agent, and
-- ottoq-wave-admit (commit=true) -- which is precisely the observed intrusion: six
-- arrived_at_gate vehicles flipped to staged_awaiting_service with last_state_change set to
-- the run's own sim clock, correctly tagged to the cert run by 0092's event tagging.
-- Every earlier pair simply never happened to overlap a */2-minute boundary; a slower or
-- longer arm WOULD have had the production brain mutate its world mid-run.
--
-- The metronome already refuses to drive cert_harness runs; the depot-tick cron predates
-- that discipline. Same rule now: a depot whose only running runs are cert arms is IDLE to
-- the production brain.
--
-- ONE PATCH: the gate counts only runs the production brain may drive
-- (run_by <> 'cert_harness'). A real production/demo run still wakes everything exactly as
-- before. (Known caveat, unchanged by this patch: a cert arm sharing the depot with a
-- SIMULTANEOUS production run is still contaminated -- cert arms own the depot by
-- convention; the instrument's reset would destroy a live run's world anyway.)
--
-- Pre-image pin, read live 2026-08-29 (anchor verified at exactly 1 occurrence):
--   public.ottoq_cron_tick   0000aacc9027798730952daa214d5ece

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_a_old text := 'IF NOT EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = ''running'') THEN';
  v_a_new text := 'IF NOT EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = ''running'''
               || ' AND COALESCE(run_by,'''') <> ''cert_harness'') THEN  -- 0106: cert arms do not wake the production brain';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cron_tick';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '0000aacc9027798730952daa214d5ece' THEN
    RAISE EXCEPTION '0106 abort: cron_tick drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_a_old,'')))/length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0106 abort: gate anchor found % times', v_cnt; END IF;

  EXECUTE replace(v_src, v_a_old, v_a_new);

  IF position('cert arms do not wake the production brain' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0106 abort: patch did not survive';
  END IF;

  RAISE NOTICE '0106 applied: the production brain stands off a cert run.';
END
$do$;
