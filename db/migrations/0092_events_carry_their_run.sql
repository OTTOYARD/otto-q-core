-- migration-version: 20260829213000
-- migration-name:    events_carry_their_run
-- 0092 -- the "emission suppression" of check 0046's arm C was neither suppression nor a flood
-- guard. It was MIS-TAGGING, and it has been polluting the production/twin separation at every
-- run teardown since the tagging cache existed.
--
-- MECHANISM. ottoq.ottoq_active_sim_run_id() -- the function every state-change trigger asks
-- "which run does this event belong to" -- caches its answer in a TRANSACTION-scoped GUC
-- (ottoq.sim_run_id), including the answer 'none'. Two ways that lies:
--
--   1. A transaction that touches vehicles/stalls BEFORE a run exists (the determinism arm did:
--      fleet reset -> start_run -> 12 ticks, one transaction) caches 'none' at the reset and
--      stays blind for the entire transaction: every trigger event of all 12 ticks was written
--      sim_run_id NULL, data_source 'production'. Measured: arm C recorded 30 vehicle.state_changed
--      against the run while arms A/B (ticked in separate transactions) recorded 1566/1422.
--
--   2. THE TEARDOWN. ottoq_sim_stop_and_reset marks the run stopped FIRST, then release_depot
--      resets stalls and vehicles -- and by then no run is 'running', so every teardown
--      state-change event has ALWAYS been tagged production/NULL. Measured: 4,074 orphaned
--      vehicle/stall.state_changed rows in one 16-minute window (2026-08-29 16:50-17:06), the
--      first at 16:50:00.127502 -- the exact ended_at of run d5a8b7e8's governor stop.
--
-- Sim rows masquerading as production rows corrupt the one filter (data_source) that makes sim
-- and real telemetry share tables safely (CLAUDE.md 2.8). Historical orphans stay as evidence.
--
-- THREE PATCHES:
--   A. ottoq.ottoq_active_sim_run_id: never cache a miss. A found run id is still cached for
--      the transaction; 'none' is re-checked on the next call, so a run created later in the
--      same transaction becomes visible.
--   B. twin.ottoq_sim_start_run: pin the GUC to the new run id immediately after creating the
--      row -- the same transaction's remaining work (cold-start prime, callers' first ticks)
--      tags correctly even though the row is not yet visible to other transactions.
--   C. public.ottoq_sim_stop_and_reset: pin the GUC to the run being torn down before marking
--      it stopped -- the teardown's own trigger events carry the run they tear down.
--
-- Check 0045 R12 (added with this migration) watches the teardown case permanently: a completed
-- run must leave zero untagged witness events inside its own wall-clock window.
--
-- Pre-image pins, read live 2026-08-29 (each anchor verified at exactly 1 occurrence):
--   ottoq.ottoq_active_sim_run_id     55699e72c19cd4677f29e10de39391f0
--   twin.ottoq_sim_start_run          a8454174d97ad2466320c22ed341f8ae
--   public.ottoq_sim_stop_and_reset   5993b258bcc64a4f4aa35081a5d1f309

DO $do$
DECLARE
  v_oid oid; v_src text; v_new text; v_cnt int;

  -- ---- A: the cache write in active_sim_run_id ----
  v_a_old text := E'  PERFORM set_config(''ottoq.sim_run_id'', COALESCE(v_id::text, ''none''), true);\n'
               || E'  RETURN v_id;';
  v_a_new text := E'  -- 0092: NEVER cache a miss. A ''none'' cached before a run exists blinds the whole\n'
               || E'  -- transaction (measured: 12 ticks of trigger events written as production/NULL).\n'
               || E'  IF v_id IS NOT NULL THEN\n'
               || E'    PERFORM set_config(''ottoq.sim_run_id'', v_id::text, true);\n'
               || E'  END IF;\n'
               || E'  RETURN v_id;';

  -- ---- B: start_run pins the GUC right after creating the run row ----
  v_b_old text := E'  );\n\n  -- COLD START.';
  v_b_new text := E'  );\n\n'
               || E'  -- 0092: pin this transaction''s event tagging to the run just created; the row is\n'
               || E'  -- not yet visible to the lookup path a trigger would use mid-transaction.\n'
               || E'  PERFORM set_config(''ottoq.sim_run_id'', v_run_id::text, true);\n\n'
               || E'  -- COLD START.';

  -- ---- C: teardown pins the GUC before the run stops being ''running'' ----
  v_c_old text := E'BEGIN\n  v_marked := ottoq_sim_mark_stopped(p_sim_run_id, p_reason);';
  v_c_new text := E'BEGIN\n'
               || E'  -- 0092: the teardown''s own trigger events must carry the run they tear down;\n'
               || E'  -- once mark_stopped flips the status, the lookup path can no longer find it.\n'
               || E'  PERFORM set_config(''ottoq.sim_run_id'', p_sim_run_id::text, true);\n'
               || E'  v_marked := ottoq_sim_mark_stopped(p_sim_run_id, p_reason);';
BEGIN
  -- ---------- A ----------
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_active_sim_run_id';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '55699e72c19cd4677f29e10de39391f0' THEN
    RAISE EXCEPTION '0092 abort: active_sim_run_id drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a_old, ''))) / length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0092 abort: cache anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_a_old, v_a_new);
  IF position('NEVER cache a miss' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0092 abort: patch A did not survive';
  END IF;

  -- ---------- B ----------
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_run';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'a8454174d97ad2466320c22ed341f8ae' THEN
    RAISE EXCEPTION '0092 abort: sim_start_run drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_b_old, ''))) / length(v_b_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0092 abort: start-run anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_b_old, v_b_new);
  IF position('pin this transaction' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0092 abort: patch B did not survive';
  END IF;

  -- ---------- C ----------
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_stop_and_reset';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '5993b258bcc64a4f4aa35081a5d1f309' THEN
    RAISE EXCEPTION '0092 abort: stop_and_reset drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_c_old, ''))) / length(v_c_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0092 abort: teardown anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_c_old, v_c_new);
  IF position('carry the run they tear down' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0092 abort: patch C did not survive';
  END IF;

  RAISE NOTICE '0092 applied: events carry their run — no cached misses, tagged starts, tagged teardowns.';
END
$do$;
