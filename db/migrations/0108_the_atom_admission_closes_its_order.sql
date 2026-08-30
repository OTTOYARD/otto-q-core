-- migration-version: 20260830080000
-- migration-name:    the_atom_admission_closes_its_order
-- 0108 -- closes what pair 12 (seed 171717, post-0107) left open. That pair was equal on
-- commands, events and bookings; the residue was (a) one task_start/triage_confirm decision
-- for vehicle 9be45c35 recorded at tick 11 in one arm and tick 12 in the other, and (b) a
-- world-fingerprint mismatch between two provably equal starts.
--
-- THREE PATCHES:
--   1. twin.ottoq_sim_advance_visit_atoms, the concurrent-atoms admission cursor:
--        ORDER BY (urgency) DESC, (charging) DESC, v.last_state_change ASC LIMIT 30
--      -- the 0054/0098 disease, one more site: last_state_change TIES for same-tick
--      transitions, so who makes the LIMIT-30 cut (and therefore which tick a vehicle's
--      atoms START, and with them the triage verdict) fell to heap order. It moves atoms
--      inside ottoq_visit_needs only, which is why the fork showed no command, booking or
--      event difference. Run-stable vn.vehicle_id tail appended.
--      (A double-boot-draw probe first proved the 0107 profile redraw perfectly idempotent
--      -- differing_columns=[NONE] -- eliminating the start state before blaming the tick.)
--   2. Same function, the tech_greenlight raise guard: its NOT EXISTS deduplication read
--      ottoq_ops_approvals with NO sim_run_id filter -- and every determinism arm replays
--      the same sim day, so a PREVIOUS run's approval (decided_at inside the same sim
--      window) can suppress THIS run's raise. Not the pair-12 witness's path (that vehicle
--      had no greenlight rows) but a live cross-run leak of exactly the class 0107 closed
--      for profiles. The guard gains ap.sim_run_id = p_sim_run_id.
--   3. ottoq.ottoq_world_fingerprint: the vehicle section hashed v.config verbatim, and
--      since 0107 the boot draw stamps config.condition_drawn_run = the run's own uuid --
--      so two identical worlds now fingerprint differently by construction. Nothing reads
--      the key for logic (verified: only diagnostics and the reset strip/keep lists name
--      it). The config hash now excludes it.
--
-- Pre-image pins, read live 2026-08-30 (each anchor verified at exactly 1 occurrence):
--   twin.ottoq_sim_advance_visit_atoms   893c4de4fff7c6e5ee162c36d5678414
--   ottoq.ottoq_world_fingerprint        3bb23c941eaa392bf3f6bd1cf605452c  (post-0107)

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;

  v_a_old text := E'v.last_state_change ASC\n     LIMIT 30';
  v_a_new text := E'v.last_state_change ASC,\n              vn.vehicle_id   /* 0108: run-stable tail; same-tick transitions tie */\n     LIMIT 30';

  v_g_old text := 'AND (ap.status = ''pending'' OR ap.decided_at > p_clock - interval ''60 minutes'')';
  v_g_new text := 'AND ap.sim_run_id = p_sim_run_id  /* 0108: a prior run''s approval must not suppress this run''s raise */
                               AND (ap.status = ''pending'' OR ap.decided_at > p_clock - interval ''60 minutes'')';

  v_c_old text := 'COALESCE(v.config::text,''{}'')';
  v_c_new text := 'COALESCE((v.config - ''condition_drawn_run'')::text,''{}'')';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_visit_atoms';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '893c4de4fff7c6e5ee162c36d5678414' THEN
    RAISE EXCEPTION '0108 abort: advance_visit_atoms drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_a_old,'')))/length(v_a_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0108 abort: cursor anchor found % times', v_cnt; END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_g_old,'')))/length(v_g_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0108 abort: guard anchor found % times', v_cnt; END IF;
  v_src := replace(v_src, v_a_old, v_a_new);
  v_src := replace(v_src, v_g_old, v_g_new);
  EXECUTE v_src;
  v_src := pg_get_functiondef(v_oid);
  IF position('0108: run-stable tail' in v_src) = 0
     OR position('ap.sim_run_id = p_sim_run_id' in v_src) = 0 THEN
    RAISE EXCEPTION '0108 abort: advance_visit_atoms patch did not survive';
  END IF;

  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_world_fingerprint';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '3bb23c941eaa392bf3f6bd1cf605452c' THEN
    RAISE EXCEPTION '0108 abort: world_fingerprint drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_c_old,'')))/length(v_c_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0108 abort: config anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_c_old, v_c_new);
  IF position('- ''condition_drawn_run''' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0108 abort: fingerprint patch did not survive';
  END IF;

  RAISE NOTICE '0108 applied: atom admission ordered, greenlight guard run-scoped, fingerprint de-noised.';
END
$do$;
