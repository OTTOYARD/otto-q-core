-- migration-version: 20260830235000
-- migration-name:    the_teardown_retires_the_interrupted
-- 0127 -- the 171717/24t carrier, NAMED BY THE INSTRUMENT on its first outing (0125;
-- db/checks/0046 pair 54). The pair's boot-state fingerprint showed exactly ONE
-- difference between the arms' starting worlds: bookings.fgn -- foreign live-state
-- stall bookings, 203 in arm A vs 206 in arm B. Arm A's teardown had leaked three.
-- The world census found the class: 209 leftover bookings across the campaign lineage,
-- essentially all state='interrupted' -- written by the vehicle exception-handler path
-- (the same path 0119 gave a total order; the same perimeter_hold vehicle appears), and
-- retired by NOTHING: release_depot's booking release reads
--     WHERE sim_run_id = p_sim_run_id AND state IN ('held','active');
-- so 'interrupted' rows survive every teardown and accumulate, one to three per run.
-- The EXCLUDE constraints are run-scoped (sim_run_id WITH =), so the leftovers never
-- block physically -- but every "live booking" read filters state IN
-- ('held','active','interrupted', ...), and any such read not ALSO run-scoped sees a set
-- that differs between a pair's arms. Whether a leaked row intersects a probe window is
-- lineage luck -- exactly the observed intermittency (P43 pass, P44 fail, P53 fail,
-- P54 pass).
--
-- FIX at the source: teardown retires 'interrupted' with the same stroke that retires
-- 'held' and 'active' -- one word in the state list, both feed modes (the clause is
-- ledger-side, before the feed-mode split). Once no live-state row survives a teardown,
-- the foreign-live hazard set is empty for EVERY reader, known and unknown.
-- Plus the one-time repair: the 209 accumulated leaks are retired with an audit-visible
-- release_reason. Production rows (sim_run_id NULL) untouched; historical released/
-- superseded/done rows untouched (evidence stays).
--
-- Prediction (falsifiable): with the hazard set empty, 171717/24t transition+confirm
-- passes, and the boot fingerprints of every future healthy pair show bookings.fgn n=0.
--
-- Pre-image pin, read live 2026-08-30 (anchor verified at exactly 1 occurrence):
--   public.ottoq_sim_release_depot   e4e918d80f522ed2a7d8b26eae6b4578

DO $patch$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := 'WHERE sim_run_id = p_sim_run_id AND state IN (''held'',''active'');';
  v_new text := 'WHERE sim_run_id = p_sim_run_id AND state IN (''held'',''active'',''interrupted'');  -- 0127: interrupted rows are live state too; leaking them across runs was the 171717/24t carrier';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_release_depot';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'e4e918d80f522ed2a7d8b26eae6b4578' THEN
    RAISE EXCEPTION '0127 abort: release_depot drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0127 abort: anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_old, v_new);
  IF position('leaking them across runs' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0127 abort: patch did not survive';
  END IF;
  RAISE NOTICE '0127 applied: the teardown retires the interrupted.';
END
$patch$;

-- One-time repair: retire every live-state booking whose run is over. Audit-visible
-- reason; counts reported. Production (NULL-run) rows are not touched.
DO $repair$
DECLARE v_n int;
BEGIN
  UPDATE public.ottoq_stall_bookings b
     SET state = 'released', released_at = now(),
         release_reason = '0127_interrupted_leak_repair'
   WHERE b.sim_run_id IS NOT NULL
     AND b.state IN ('held','active','interrupted')
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                      WHERE r.sim_run_id = b.sim_run_id AND r.status = 'running');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE '0127 repair: % leaked live-state bookings of dead runs retired.', v_n;
END
$repair$;
