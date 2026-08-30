-- migration-version: 20260830140000
-- migration-name:    the_soc_state_belongs_to_the_run
-- 0115 -- pair 17 (db/checks/0046, seed 171717/12t, the first pair after production ran on
-- the flagship) FAILED with a signature no previous pair produced: both arms booted with
-- EQUAL world fingerprints (e2902297) and then diverged from tick 1. Root, traced to the
-- row: vehicles.target_soc and vehicles.current_soc_updated_at are written freely during a
-- run (charge targeting, telemetry stamps), survive ottoq_sim_release_depot, and sat
-- outside BOTH ottoq_run_boot_draw AND ottoq.ottoq_world_fingerprint. Arm A charged
-- vehicle 091fa637 to target 90; arm B then booted "fp-identical", read that leftover
-- target in ottoq_l2_optimize_assignments' eligibility (current_soc < COALESCE(target_soc,
-- default) - 0.5), and proposed a stall arm A never proposed. One extra vehicle in one
-- queue; fifty vehicles diverged by the horizon.
--
-- Why pairs 8-16 never caught it: back-to-back identical cert runs leave IDENTICAL
-- leftovers (the 424242 fixpoint lesson, again). Running a production session (e8a0ba01)
-- on the cert depot broke the fixpoint and exposed the gap. The flagship is both the
-- production sandbox and the cert fixture; the cert must therefore boot a world that is a
-- pure function of the seed -- V3's contract, extended to the columns that escaped it.
--
-- THREE PARTS:
--   1. ottoq_run_boot_draw gains step 1e: reset target_soc (NULL -> readers COALESCE the
--      policy default), current_soc_source ('estimated'), current_soc_updated_at
--      (sim_clock_start) for the run's fleet. Production sessions never call the draw
--      (0111), so a real feed's SoC state is never touched.
--   2. ottoq.ottoq_world_fingerprint gains the two columns, per its own rule ("extend the
--      column set only alongside the 0046 probe that justifies it" -- pair 17 is the
--      probe). A future leak of this class fails the fp check loudly instead of forking
--      silently. All prior canonical fp values are re-baselined in db/checks/0046.
--   3. Data repair: 33 live approvals ('approved'/'pending') owned by completed or absent
--      runs -- pre-0097-era residue (old cert runs, the V2 validation run, an operator
--      demo, one orphan; among them the approved-after-expiry indepot_reassign on
--      091fa637). 0097's rule applied retroactively with provenance kept in payload.
--
-- Pre-image pins, read live 2026-08-30 (anchors verified at exactly 1 occurrence each):
--   public.ottoq_run_boot_draw        6a3e358885f61cedb5a909516cd45fad  (post-0109)
--   ottoq.ottoq_world_fingerprint     377606d497e12b69ec45143dac3d8ba1  (post-0107)

-- ---- 1. the boot draw resets the run's SoC state ----
DO $draw$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_anchor text := '  -- ---- 2. WORLD DAY-0 DRAW';
  v_block  text :=
       E'  -- ---- 1e. 0115: THE SOC STATE BELONGS TO THE RUN (pair-17 fork, db/checks/0046).\n'
    || E'  --      target_soc / current_soc_source / current_soc_updated_at are in-run state that\n'
    || E'  --      survived teardown outside both this draw and the world fingerprint. Reset to\n'
    || E'  --      pure functions of the run. Production sessions never call this draw (0111).\n'
    || E'  BEGIN\n'
    || E'    UPDATE vehicles v\n'
    || E'       SET target_soc = NULL,\n'
    || E'           current_soc_source = ''estimated'',\n'
    || E'           current_soc_updated_at = v_run.sim_clock_start\n'
    || E'     WHERE v.home_depot_id = v_run.depot_id AND v.category = ''autonomous'' AND v.is_active\n'
    || E'       AND (v.target_soc IS NOT NULL\n'
    || E'            OR v.current_soc_source IS DISTINCT FROM ''estimated''\n'
    || E'            OR v.current_soc_updated_at IS DISTINCT FROM v_run.sim_clock_start);\n'
    || E'  EXCEPTION WHEN OTHERS THEN\n'
    || E'    RAISE WARNING ''boot_draw: soc-state reset failed SAFELY: % %'', SQLSTATE, SQLERRM;\n'
    || E'  END;\n\n';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_run_boot_draw';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '6a3e358885f61cedb5a909516cd45fad' THEN
    RAISE EXCEPTION '0115 abort: run_boot_draw drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_anchor,'')))/length(v_anchor);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0115 abort: boot-draw anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_anchor, v_block || v_anchor);
  IF position('THE SOC STATE BELONGS TO THE RUN' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0115 abort: boot-draw patch did not survive';
  END IF;
END
$draw$;

-- ---- 2. the fingerprint covers what the draw now owns ----
DO $fp$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := '||COALESCE(v.current_soc_source,''-'')||''|''||COALESCE((v.config - ''condition_drawn_run'')::text,''{}''),';
  v_new text := '||COALESCE(v.current_soc_source,''-'')||''|''||COALESCE(v.target_soc::text,''-'')||''|''' || E'\n'
             || '                     ||COALESCE(v.current_soc_updated_at::text,''-'')||''|''||COALESCE((v.config - ''condition_drawn_run'')::text,''{}''), -- 0115: pair-17 probe';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_world_fingerprint';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '377606d497e12b69ec45143dac3d8ba1' THEN
    RAISE EXCEPTION '0115 abort: world_fingerprint drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_old,'')))/length(v_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0115 abort: fingerprint anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_old, v_new);
  IF position('0115: pair-17 probe' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0115 abort: fingerprint patch did not survive';
  END IF;
END
$fp$;

-- ---- 3. data repair: 0097 applied retroactively to pre-0097 residue ----
DO $repair$
DECLARE v_n int;
BEGIN
  UPDATE ottoq_ops_approvals a
     SET payload = COALESCE(a.payload,'{}'::jsonb)
                   || jsonb_build_object('expired_from', a.status,
                                         'expired_reason', 'stale_cross_run_backfill_0115'),
         status = 'expired',
         decided_at = COALESCE(a.decided_at, now()),
         decided_by = COALESCE(a.decided_by, '0115_backfill')
   WHERE a.status IN ('pending','approved')
     AND NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r
                      WHERE r.sim_run_id = a.sim_run_id
                        AND r.status IN ('running','initializing','paused'));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE '0115 applied: soc state reset at boot, fingerprint extended, % stale live approvals expired.', v_n;
END
$repair$;
