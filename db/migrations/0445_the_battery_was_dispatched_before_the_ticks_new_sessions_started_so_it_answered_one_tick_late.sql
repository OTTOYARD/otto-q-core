-- migration-version: 20260923042310
-- migration-name:    the_battery_was_dispatched_before_the_ticks_new_sessions_started_so_it_answered_one_tick_late
--
-- 0445  **The battery was dispatched before the tick's new charging sessions started, so it always answered one tick
--       late.** Both world orchestrators, `public.ottoq_sim_advance_tick_world` (demo runs, every pair) and
--       `twin.ottoq_world_advance` (production-live runs), call `ottoq_energy_orchestrate` and
--       `ottoq_sim_energy_controller` BEFORE `ottoq_sim_reconcile_charge_sessions`. The sessions that reconciliation
--       starts then draw power in the same tick's `ottoq_sim_advance_charge_sessions` / `ottoq_sim_advance_all_energy`,
--       against a battery setpoint computed before they existed. FINDINGS G178.
--
-- ══ §1 MEASURED 2026-09-23, RUN 324eb0f1 ═══════════════════════════════════════════════════════════════════════
--
--   - Tick 3, sim 04:23:19 CT: the orchestrator's `desired_ev_kw` was 0 and its net load 48 kW, while 26 sessions
--     started in that tick and the snapshot at the same instant shows 345 kW of EV.
--   - Tick 5, sim 04:24:18 CT: the orchestrator saw a net load of 377 kW; the snapshot at the same instant shows
--     1,523 kW of EV and 1,574 kW of grid draw. The battery's answer came at tick 6.
--   - Statement order, from source: in `ottoq_sim_advance_tick_world` orchestrate < controller < reconcile at
--     characters 4319 < 4457 < 5593; in `twin.ottoq_world_advance` 1874 < 2108 < 2594.
--   - At the demo cadence (~0.5 sim-min per tick) the lag is 30 seconds of a 30-minute billing interval. At the
--     certification cadence, which the dial-experiment pairs of 0439 also use, it is the whole interval: no
--     strategy could shave the first half hour of any surge, and every energy verdict measured there understated
--     any strategy whose value is at a surge's leading edge.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   In both orchestrators the orchestration block (the policy-gated `ottoq_energy_orchestrate` and the
--   feed-gated `ottoq_sim_energy_controller`) moves from before the charge block to between
--   `ottoq_sim_reconcile_charge_sessions` and `ottoq_sim_advance_charge_sessions`. The feed-gated block is split at
--   that point so the orchestration keeps its own gates exactly (it ran on a non-sim feed before and still does).
--   Everything else keeps its order: prearrival and command confirmation, then the arm walk (tick_world only),
--   the early heartbeat (0424) and reconciliation, then the battery, then energy delivery and the site snapshot.
--
--   Why this order and not "the plant follows a grid target within the tick": that model is the physically
--   faithful one and remains the direction for real hardware, but it rewrites the plant. This is the smallest
--   change that removes the lag: the orchestrator's `desired_ev_kw` already sums the ACTIVE sessions' rates, and
--   after this move the sessions reconciliation just started are active when it looks.
--
-- ══ §3 WHAT WAS CHECKED BEFORE MOVING IT ════════════════════════════════════════════════════════════════════
--
--   - Nothing on the charge side reads the battery or the orchestrator's output: `ottoq_sim_reconcile_charge_sessions`,
--     `twin.ottoq_sim_start_charge_session`, `twin.ottoq_sim_advance_charge_sessions`, `twin.ottoq_sim_advance_all_energy`
--     and `twin.ottoq_sim_auto_charge_assign_tick` contain no `charge_cap`, `energy_commands`, `bess_setpoint` or
--     `charge_allowance`; the one match, in advance_charge_sessions, is the comment "peak shaving is the BESS's job".
--   - The rules probed at `charge_session_start` (enforced since 0428) do not read the battery: EN.001, EN.002,
--     EN.004 and EN.005's evaluators touch no BESS row, snapshot or energy command. EN.003 reads the battery's SoC,
--     which only `ottoq_sim_advance_all_energy` moves, and that still runs after both positions.
--   - The heartbeat stays before reconciliation (0424's reason for existing), and the arm walk stays before the
--     charge block (tick_world's own comment on why the arm moves first).
--
-- ══ §4 forces_recert TRUE ════════════════════════════════════════════════════════════════════════════════════
--
--   Every certification run orchestrates energy (heuristic mode), so the battery's setpoint at every tick where a
--   session starts changes, and with it the energy and events atoms. The canon is re-earned by the recert runner.
--   The behavioural proof is the first certified pair and the first dial pair after this: at a tick where sessions
--   start, the battery command's `desired_ev_kw` now includes them.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0445 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%' OR query ILIKE '%ottoq_dial_experiment_runner%'
          OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0445 P0: a pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0445 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: both orchestrators as read on 2026-09-23, every anchor unique ──
DO $$
DECLARE v_src text; v_n int; v_a text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'public.ottoq_sim_advance_tick_world'::regproc;
  IF md5(v_src) <> 'be38b51c780490c9a983e84aae3c6cc0' THEN
    RAISE EXCEPTION '0445 P1: ottoq_sim_advance_tick_world md5 is %', md5(v_src);
  END IF;
  FOREACH v_a IN ARRAY ARRAY[
      E'  IF (v_run.policy IS NULL OR v_run.policy = ''otto_q'') AND ottoq_policy_get(p_sim_run_id,''energy_orchestration_enabled'',1) > 0 THEN\n'
      || E'    PERFORM ottoq_energy_orchestrate(p_sim_run_id, v_run.depot_id, v_new_sim_clock, v_run.tick_count + 1);\n'
      || E'  END IF;\n  IF v_feed_sim THEN\n'
      || E'    PERFORM ottoq_sim_energy_controller(p_sim_run_id, v_run.depot_id, v_new_sim_clock);\n  END IF;\n',
      E'    PERFORM ottoq_sim_reconcile_charge_sessions(p_sim_run_id, v_new_sim_clock);\n'
      || E'    SELECT COUNT(*) INTO v_charge_adv FROM ottoq_sim_advance_charge_sessions(p_sim_run_id, v_new_sim_clock);\n']
  LOOP
    v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
    IF v_n <> 1 THEN RAISE EXCEPTION '0445 P1: tick_world anchor matched % times: %', v_n, left(v_a, 70); END IF;
  END LOOP;

  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'twin.ottoq_world_advance'::regproc;
  IF md5(v_src) <> '2c37ad199f942326437483b8ee952bd8' THEN
    RAISE EXCEPTION '0445 P1: twin.ottoq_world_advance md5 is %', md5(v_src);
  END IF;
  FOREACH v_a IN ARRAY ARRAY[
      E'  -- OTTO-Q ENERGY ORCHESTRATION (the #1 demand-shave edge) — gated + defensive\n'
      || E'  IF (v_run.policy IS NULL OR v_run.policy = ''otto_q'')\n'
      || E'     AND ottoq_policy_get(v_run.sim_run_id,''energy_orchestration_enabled'',1) > 0 THEN\n'
      || E'    BEGIN PERFORM ottoq_energy_orchestrate(v_run.sim_run_id, v_run.depot_id, v_now, v_run.tick_count + 1);\n'
      || E'    EXCEPTION WHEN OTHERS THEN RAISE WARNING ''world_advance energy_orchestrate: %'', SQLERRM; END;\n'
      || E'  END IF;\n  IF v_feed_sim THEN\n'
      || E'  BEGIN PERFORM ottoq_sim_energy_controller(v_run.sim_run_id, v_run.depot_id, v_now);\n'
      || E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''world_advance energy_controller: %'', SQLERRM; END;\n  END IF;\n',
      E'  BEGIN PERFORM ottoq_sim_reconcile_charge_sessions(v_run.sim_run_id, v_now);\n'
      || E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''world_advance reconcile_charge: %'', SQLERRM; END;\n']
  LOOP
    v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
    IF v_n <> 1 THEN RAISE EXCEPTION '0445 P1: world_advance anchor matched % times: %', v_n, left(v_a, 70); END IF;
  END LOOP;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0445_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_sim_advance_tick_world'::regproc, 'twin.ottoq_world_advance'::regproc);

-- ── THE MOVE, public.ottoq_sim_advance_tick_world ──
DO $splice$
DECLARE v_def text; v_new text;
  c_block CONSTANT text :=
         E'  IF (v_run.policy IS NULL OR v_run.policy = ''otto_q'') AND ottoq_policy_get(p_sim_run_id,''energy_orchestration_enabled'',1) > 0 THEN\n'
      || E'    PERFORM ottoq_energy_orchestrate(p_sim_run_id, v_run.depot_id, v_new_sim_clock, v_run.tick_count + 1);\n'
      || E'  END IF;\n  IF v_feed_sim THEN\n'
      || E'    PERFORM ottoq_sim_energy_controller(p_sim_run_id, v_run.depot_id, v_new_sim_clock);\n  END IF;\n';
  c_split CONSTANT text :=
         E'    PERFORM ottoq_sim_reconcile_charge_sessions(p_sim_run_id, v_new_sim_clock);\n'
      || E'    SELECT COUNT(*) INTO v_charge_adv FROM ottoq_sim_advance_charge_sessions(p_sim_run_id, v_new_sim_clock);\n';
BEGIN
  v_def := pg_get_functiondef('public.ottoq_sim_advance_tick_world'::regproc);
  v_new := replace(v_def, c_block,
         E'  -- 0445 (G178): the battery is dispatched below, after reconciliation starts this tick''s sessions\n');
  v_new := replace(v_new, c_split,
         E'    PERFORM ottoq_sim_reconcile_charge_sessions(p_sim_run_id, v_new_sim_clock);\n'
      || E'  END IF;\n'
      || E'  /* 0445 (G178): THE BATTERY ANSWERS THE LOAD IT WILL SEE. The orchestrator sums the ACTIVE sessions'' rates,\n'
      || E'     so it must run after reconciliation has started this tick''s sessions and before energy is delivered;\n'
      || E'     above the charge block it answered one tick late (a whole billing interval at 30 sim-min per tick). */\n'
      || c_block
      || E'  IF v_feed_sim THEN\n'
      || E'    SELECT COUNT(*) INTO v_charge_adv FROM ottoq_sim_advance_charge_sessions(p_sim_run_id, v_new_sim_clock);\n');
  IF v_new = v_def
     OR (length(v_new) - length(replace(v_new, 'PERFORM ottoq_energy_orchestrate(', ''))) / length('PERFORM ottoq_energy_orchestrate(') <> 1
     OR (length(v_new) - length(replace(v_new, 'PERFORM ottoq_sim_energy_controller(', ''))) / length('PERFORM ottoq_sim_energy_controller(') <> 1 THEN
    RAISE EXCEPTION '0445: the tick_world move did not apply cleanly';
  END IF;
  EXECUTE v_new;
END $splice$;

-- ── THE MOVE, twin.ottoq_world_advance ──
DO $splice$
DECLARE v_def text; v_new text;
  c_block CONSTANT text :=
         E'  -- OTTO-Q ENERGY ORCHESTRATION (the #1 demand-shave edge) — gated + defensive\n'
      || E'  IF (v_run.policy IS NULL OR v_run.policy = ''otto_q'')\n'
      || E'     AND ottoq_policy_get(v_run.sim_run_id,''energy_orchestration_enabled'',1) > 0 THEN\n'
      || E'    BEGIN PERFORM ottoq_energy_orchestrate(v_run.sim_run_id, v_run.depot_id, v_now, v_run.tick_count + 1);\n'
      || E'    EXCEPTION WHEN OTHERS THEN RAISE WARNING ''world_advance energy_orchestrate: %'', SQLERRM; END;\n'
      || E'  END IF;\n  IF v_feed_sim THEN\n'
      || E'  BEGIN PERFORM ottoq_sim_energy_controller(v_run.sim_run_id, v_run.depot_id, v_now);\n'
      || E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''world_advance energy_controller: %'', SQLERRM; END;\n  END IF;\n';
  c_split CONSTANT text :=
         E'  BEGIN PERFORM ottoq_sim_reconcile_charge_sessions(v_run.sim_run_id, v_now);\n'
      || E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''world_advance reconcile_charge: %'', SQLERRM; END;\n';
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_world_advance'::regproc);
  v_new := replace(v_def, c_block,
         E'  -- 0445 (G178): the battery is dispatched below, after reconciliation starts this tick''s sessions\n');
  v_new := replace(v_new, c_split,
         c_split
      || E'  END IF;\n'
      || E'  /* 0445 (G178): the battery answers the load it will see -- after reconciliation, before delivery. */\n'
      || c_block
      || E'  IF v_feed_sim THEN\n');
  IF v_new = v_def
     OR (length(v_new) - length(replace(v_new, 'PERFORM ottoq_energy_orchestrate(', ''))) / length('PERFORM ottoq_energy_orchestrate(') <> 1
     OR (length(v_new) - length(replace(v_new, 'PERFORM ottoq_sim_energy_controller(', ''))) / length('PERFORM ottoq_sim_energy_controller(') <> 1 THEN
    RAISE EXCEPTION '0445: the world_advance move did not apply cleanly';
  END IF;
  EXECUTE v_new;
END $splice$;

-- ── V1: in comment-stripped source, both orchestrators run reconcile < orchestrate < controller < charge advance
--       < energy advance, with the heartbeat still before reconcile and (tick_world) the arm before the charge block ──
DO $$
DECLARE v_fn regproc; v_src text; p_hb int; p_rec int; p_orch int; p_ctl int; p_chg int; p_nrg int; p_arm int;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.ottoq_sim_advance_tick_world'::regproc, 'twin.ottoq_world_advance'::regproc] LOOP
    SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
      FROM pg_proc WHERE oid = v_fn;
    p_hb   := position('SET last_heartbeat_at' IN v_src);
    p_rec  := position('ottoq_sim_reconcile_charge_sessions(' IN v_src);
    p_orch := position('ottoq_energy_orchestrate(' IN v_src);
    p_ctl  := position('ottoq_sim_energy_controller(' IN v_src);
    p_chg  := position('ottoq_sim_advance_charge_sessions(' IN v_src);
    p_nrg  := position('ottoq_sim_advance_all_energy(' IN v_src);
    IF NOT (p_hb > 0 AND p_hb < p_rec AND p_rec < p_orch AND p_orch < p_ctl AND p_ctl < p_chg AND p_chg < p_nrg) THEN
      RAISE EXCEPTION '0445 V1: % order is heartbeat % reconcile % orchestrate % controller % charge % energy %',
        v_fn, p_hb, p_rec, p_orch, p_ctl, p_chg, p_nrg;
    END IF;
    IF v_fn = 'public.ottoq_sim_advance_tick_world'::regproc THEN
      p_arm := position('ottoq_arm_advance_cycles(' IN v_src);
      IF NOT (p_arm > 0 AND p_arm < p_rec) THEN RAISE EXCEPTION '0445 V1: the arm no longer walks before the charge block'; END IF;
    END IF;
    -- the orchestration is gated on policy, never on the feed, exactly as before
    IF position('energy_orchestration_enabled' IN v_src) = 0 OR position('energy_orchestration_enabled' IN v_src) > p_orch THEN
      RAISE EXCEPTION '0445 V1: % lost the orchestration''s policy gate', v_fn;
    END IF;
  END LOOP;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0445_the_battery_was_dispatched_before_the_ticks_new_sessions_started_so_it_answered_one_tick_late',
   true,
   'G178: in ottoq_sim_advance_tick_world and twin.ottoq_world_advance the energy orchestration and the energy '
   'controller move from before the charge block to between ottoq_sim_reconcile_charge_sessions and '
   'ottoq_sim_advance_charge_sessions, so the battery is dispatched against the sessions that start this tick. '
   'TRUE: every certification run orchestrates energy, and the setpoint at every tick where a session starts changes.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert TRUE. After applying: the recert runner (cron 746) re-earns the canon; then, on the first certified
-- pair and the first dial pair, the battery command at a tick where sessions start carries their rate in
-- `desired_ev_kw`. Rollback: restore both functions from ottoq_schema_snapshots label '0445_pre'.
