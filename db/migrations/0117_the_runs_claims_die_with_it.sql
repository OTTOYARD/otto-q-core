-- migration-version: 20260830160000
-- migration-name:    the_runs_claims_die_with_it
-- 0117 -- first fix out of the V7 residue sweep. vehicles.owning_sim_run_id is
-- ottoq.ottoq_admit_stranded_vehicles' claim column: set to the claiming run
-- (COALESCE-kept), used to filter candidates (owning IS NULL OR owning = this run) --
-- and RELEASED BY NOTHING. Catalog sweep confirms admit_stranded is the only writer;
-- blackbox / purge-check / comms-escalate / log-deploy only read it. Measured live:
-- 21 vehicles still claimed by the COMPLETED production session -- every run since has
-- silently skipped them at stranded-admit. A session's claims die with it, exactly like
-- its approvals (0097), its calendar claims (0114), and its reservation timestamps (0116).
--
-- FIX: ottoq_sim_release_depot releases the stopping run's claims in the run-scoped
-- ledger section (BOTH feed modes -- the claim is orchestration state, not physical
-- state). One-time repair releases claims held by any non-running run.
--
-- Fingerprint note, on purpose: owning_sim_run_id is NOT added to the world fingerprint
-- in this migration. It carries a per-run uuid (0054: never a determinism key), and with
-- this release in place it is NULL at every clean boot; the V7 sweep's final fingerprint
-- revision will add it (as a presence marker, not the uuid) together with the other
-- sweep findings, so the canon re-mints once, not once per column.
--
-- Pre-image pin, read live 2026-08-30 (anchor verified at exactly 1 occurrence):
--   public.ottoq_sim_release_depot   9b11b35aebe8ac78ae1deb0c760ed3f6  (post-0116)

DO $patch$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_anchor text := E'   WHERE sim_run_id = p_sim_run_id AND status IN (''active'',''returning'');';
  v_block  text := E'\n\n'
    || E'  -- 0117: the run''s vehicle claims die with it. owning_sim_run_id is admit_stranded''s\n'
    || E'  -- cross-run claim; left in place it starves every later run''s stranded-admit\n'
    || E'  -- (21 vehicles measured claimed by a completed production session). Both modes:\n'
    || E'  -- the claim is orchestration state, never physical state.\n'
    || E'  UPDATE vehicles SET owning_sim_run_id = NULL\n'
    || E'   WHERE owning_sim_run_id = p_sim_run_id;';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_release_depot';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '9b11b35aebe8ac78ae1deb0c760ed3f6' THEN
    RAISE EXCEPTION '0117 abort: release_depot drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_anchor,'')))/length(v_anchor);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0117 abort: anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_anchor, v_anchor || v_block);
  IF position('the run''s vehicle claims die with it' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0117 abort: patch did not survive';
  END IF;
END
$patch$;

-- one-time repair: claims held by runs that are no longer running
DO $repair$
DECLARE v_n int;
BEGIN
  UPDATE vehicles v SET owning_sim_run_id = NULL
   WHERE v.owning_sim_run_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r
                      WHERE r.sim_run_id = v.owning_sim_run_id
                        AND r.status IN ('running','initializing','paused'));
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE '0117 applied: claims release at teardown; % stale claims repaired.', v_n;
END
$repair$;
