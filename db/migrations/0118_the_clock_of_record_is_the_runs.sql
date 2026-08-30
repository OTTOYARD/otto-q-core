-- migration-version: 20260830170000
-- migration-name:    the_clock_of_record_is_the_runs
-- 0118 -- pair 23 (db/checks/0046) isolated the last known stream discriminator: with fps
-- EQUAL and decisions EQUAL, arm A reproduced the exact Y-stream (pairs 17B/18B) and arm B
-- the exact Z-stream (pairs 18A/19/22) -- two attractors, selected by state invisible to
-- both the fingerprint and the decision ledger. The 0049 watch item fits it precisely:
-- vehicles.last_state_change. Teardown stamps only the vehicles it stands down, with the
-- transaction's wall now(); vehicles already offline keep their mid-run SIM-domain values.
-- A FIRST arm therefore boots with multiple wall tiers (one per prior teardown) among its
-- offline fleet, while a SECOND arm boots with exactly one (its sibling's) -- a different
-- RELATIVE ORDER for every fairness cursor that sorts by last_state_change, and an
-- ordering the fingerprint never sees.
--
-- FIX, on the V3 principle (the run draws its own world): ottoq_run_boot_draw step 1f
-- stamps last_state_change := sim_clock_start for the run's whole autonomous fleet. Every
-- boot then has ONE tier -- ties broken by v.id in every 0054-disciplined cursor -- and
-- watchdogs measure staleness from the run's own start, a run-pure value. Production
-- sessions never call the draw (0111), so a real feed's state clocks are untouched.
-- Behavior-touching by design (the canon re-mints); pair-verified on both seeds.
--
-- Fingerprint note: with this stamp, last_state_change is constant at boot; the sweep-final
-- fp revision (db/checks/0049) adds it together with the other batch so the canon re-mints
-- once more, not once per column.
--
-- Pre-image pin, read live 2026-08-30 (anchor verified at exactly 1 occurrence):
--   public.ottoq_run_boot_draw   dfabc9a8dca7ba5f78404402f7061470  (post-0115)

DO $patch$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_anchor text := '  -- ---- 2. WORLD DAY-0 DRAW';
  v_block  text :=
       E'  -- ---- 1f. 0118: THE CLOCK OF RECORD IS THE RUN''S (pair-23 fork, db/checks/0046).\n'
    || E'  --      Teardown wall-stamps only stood-down vehicles; mid-run offline vehicles keep\n'
    || E'  --      sim-domain values -- so the OFFLINE fleet''s relative order under\n'
    || E'  --      ORDER BY last_state_change is a function of HOW MANY teardowns shaped the\n'
    || E'  --      lineage. One uniform run-pure stamp gives every boot one tier (v.id breaks\n'
    || E'  --      ties) and watchdogs a run-anchored staleness origin.\n'
    || E'  BEGIN\n'
    || E'    UPDATE vehicles v\n'
    || E'       SET last_state_change = v_run.sim_clock_start\n'
    || E'     WHERE v.home_depot_id = v_run.depot_id AND v.category = ''autonomous'' AND v.is_active\n'
    || E'       AND v.last_state_change IS DISTINCT FROM v_run.sim_clock_start;\n'
    || E'  EXCEPTION WHEN OTHERS THEN\n'
    || E'    RAISE WARNING ''boot_draw: state-clock stamp failed SAFELY: % %'', SQLSTATE, SQLERRM;\n'
    || E'  END;\n\n';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_run_boot_draw';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'dfabc9a8dca7ba5f78404402f7061470' THEN
    RAISE EXCEPTION '0118 abort: run_boot_draw drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_anchor,'')))/length(v_anchor);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0118 abort: anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_anchor, v_block || v_anchor);
  IF position('THE CLOCK OF RECORD IS THE RUN''S' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0118 abort: patch did not survive';
  END IF;
  RAISE NOTICE '0118 applied: every boot starts the state clocks at the run''s own start.';
END
$patch$;
