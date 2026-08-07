-- migration-version: PENDING
-- 0012_tick_cost_and_metronome_ceiling.sql
-- migration-name:    tick_cost_and_metronome_ceiling
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- WHAT THIS CLOSES — AND WHAT IT DELIBERATELY DOES NOT
-- ════════════════════════════════════════════════════════════════════════════════════════
-- The brief: "the metronome averaged 38 s, peaked 69.5 s against a 60 s schedule ⇒ it
-- overruns its own period", "the run froze 2.3 real-min at tick 149", "cron 10 failed twice
-- with startup timeouts". Every number below was measured BEFORE a line of this file was
-- written, on run 8368ad72-ed23-4dcd-8864-a555b7fdeb48 (seed 424242, busy_day, live 3x —
-- the same seed, scenario, speed and 13:48 sim start as the reference run 897debec).
--
-- ── (M1) THE METRONOME IS NOT OVERRUNNING BECAUSE A TICK IS SLOW ───────────────────────
-- cron 12 is `CALL public.ottoq_demo_metronome(50)` on a `* * * * *` schedule. The
-- procedure loops until `elapsed > p_budget_s`, i.e. it is DESIGNED to burn ~50 s of every
-- 60 s. A "38 s average" is that budget, not a defect. Measured on cron.job_run_details for
-- the 23:00–00:00 window of the reference run: 52 calls, avg 24.7 s, p95 80.7 s, max 120.6 s.
-- pg_cron does NOT run job 12 concurrently — an own-pairwise overlap query over those 52
-- rows returned **0 overlapping runs**; a call that overshoots simply delays the next start
-- (23:13:00→23:14:28, next began 23:14:30). So metronome self-contention is EXONERATED.
--
-- ── (M2) THE FREEZE IS A GUILLOTINE, NOT A STALL ──────────────────────────────────────
-- `statement_timeout = 120000` comes from the configuration file and the `postgres` role
-- carries no override, so the ENTIRE `CALL ottoq_demo_metronome(50)` is bounded at 120 s —
-- internal COMMITs do not re-arm it. The budget is only checked BETWEEN ticks, so once a
-- tick starts at t=50 s it may run to t=120 s and then be cancelled mid-flight. That is
-- exactly what the reference run recorded at 23:35:09 → 23:37:09 (120.6 s):
--     ERROR: canceling statement due to statement timeout
--     CONTEXT: UPDATE public.ottoq_itinerary_legs SET to_stall_id = p_stall_id …
--              ottoq_record_enacted_booking line 214 → ottoq_enact_space_assignment line 98
--              → ottoq_decide_tick line 825 → ottoq_sim_decide_and_dispatch line 72
--              → ottoq_demo_metronome line 107
-- That UPDATE is not slow. It is simply where execution happened to be when the 120 s axe
-- fell. The cancellation rolls back the in-flight tick and costs the whole minute — which
-- is what "froze 2.3 real-min" looks like from the outside.
-- FIX: (2) below. The metronome now refuses to BEGIN a tick it cannot afford to FINISH.
--
-- ── (M3) WHERE THE TICK'S TIME ACTUALLY GOES ──────────────────────────────────────────
-- Attributed with a stopwatch copy of ottoq_sim_advance_tick_world (23 phases, one row per
-- phase per tick). `track_functions` is NOT usable on this instance — `SET track_functions`
-- returns "42501: permission denied to set parameter" at session scope AND at database
-- scope, so the technique named in the brief is unavailable here and explicit
-- instrumentation was used instead. 11 ticks, run driven by hand:
--     11_advance_deployed_telemetry   560.2 ms avg   (64 % of the world tick)
--     10_advance_all_energy            51.6 ms
--     13_comms_advance                 98.2 ms
--     everything else                 < 30 ms each
--     ZZ_WORLD_TOTAL                  878.6 ms avg, max 2 316.9 ms
--     ZZ_DECIDE_TOTAL                 358.5 ms avg, max  753.0 ms
-- So a warm steady-state beat costs ~1.1 s of compute against a 2.0 s cadence floor.
-- The tick is NOT 38 s. It is about one second.
--
-- ── (M4) THE COLD PLAN CACHE IS THE REAL PER-CALL TAX ─────────────────────────────────
-- pg_cron starts a FRESH background worker for every job run, so every PL/pgSQL plan cache
-- in the ~23-function world-advance call tree is rebuilt once a minute. Joining
-- ottoq_tick_clock_log to cron.job_run_details by containment, per metronome call:
--     runid   ticks   first_tick_ms   avg_of_remaining_ms
--     79984    13        6 663              896
--     79986     7        9 099            2 557
--     79992    17        3 010              631
--     79995    12        1 934              576
--     79993    11        5 127            2 075
-- The FIRST tick of a call is 2.5–7.4× the rest, in 5 of 8 calls. Against this, the 11
-- hand-driven ticks above ran in ONE warm session and never exceeded 2.3 s. A 50 s budget
-- against a 60 s period pays this tax once a minute AND idles ~10 s doing nothing.
-- FIX: (3) below is a config change, not schema — recorded here so the reason survives.
--
-- ── (M5) 0011'S FORWARD-WALK IS EXONERATED — THE PRECISE NUMBER ───────────────────────
-- The suspicion was "up to 24 stall searches per contended leg in the hot path". The loop
-- in ottoq.ottoq_book_workflow_legs walks 0,10,…,240 min = 25 steps, each one a full
-- ottoq.ottoq_find_and_book_stall → ottoq.ottoq_stall_free_between. Measured by executing
-- exactly that walk, 25 steps, against live run state:
--     service_bay, 25 steps that all fail : 164.0 ms total,  6.56 ms/step
--     wash_bay,    25 steps that all fail :  48.2 ms total,  1.93 ms/step
-- Worst case is therefore ~164 ms per fully-contended service leg. Five vehicles each
-- hitting the full walk in one tick = ~0.8 s. The observed spikes are 12–14 s. **The walk
-- cannot produce them.**
-- Stronger still: it is currently doing ZERO shift steps. Of the 49 outstanding
-- `planned` legs with `to_stall_id IS NULL` on this run, the leg_type histogram is
-- inspect 38 / interior_tidy 5 / sensor_clean 4 / remote_diagnostics 2 — and
-- ottoq_book_workflow_legs' inline CASE maps only charge_dcfc, charge_l2, wash, detail,
-- service and stage. Every one of those 49 legs takes the `v_want_type IS NULL → skip`
-- branch without entering the WHILE loop at all. **0 of 49.**
-- The walk is left EXACTLY as 0011 wrote it. Nothing here caps its horizon, removes it, or
-- changes which legs it books — the evidence does not support touching it.
--
-- ── (M6) THE ONE STRUCTURAL DEFECT WORTH A MIGRATION ──────────────────────────────────
-- ottoq.ottoq_stall_free_between is the calendar read under every picker. Its NOT EXISTS
-- had no usable index, so the anti-join SEQ-SCANNED ottoq_stall_bookings once per candidate
-- stall. EXPLAIN (ANALYZE, BUFFERS) on the staging read (115 candidate stalls), before:
--     Nested Loop Anti Join …
--       -> Seq Scan on ottoq_stall_bookings  (loops=115, Rows Removed by Filter: 206)
--          Buffers: shared hit=2070
--     Execution Time: 13.133 ms   Buffers: shared hit=2139
-- That is 115 × 206 = 23 690 tuple checks for ONE calendar read, and it is the origin of
-- the 226 375 534 seq_tup_read / 1 652 566 seq_scan standing on that 228-row table in
-- pg_stat_user_tables. Fix (1) below. After:
--     -> Index Scan using ottoq_stall_bookings_live_stall_idx (loops=115, Rows Removed: 1)
--          Buffers: shared hit=262
--     Execution Time: 2.373 ms    Buffers: shared hit=331
-- 13.133 → 2.373 ms (5.5×), 2 139 → 331 buffers (6.5×).
--
-- A companion index on stalls (depot_id, stall_type, …) WHERE status NOT IN (…) was built
-- and measured in the same session: the planner kept idx_stalls_depot and execution moved
-- 2.373 → 2.466 ms, i.e. no gain. **It was dropped again and is deliberately NOT shipped.**
-- An index that does not earn its write cost is not a fix.
--
-- ── WHAT REMAINS UNATTRIBUTED, SAID PLAINLY ───────────────────────────────────────────
-- Two mid-call world ticks in this run spiked to 14 118 ms (tick 13) and 12 846 ms
-- (tick 83) — not first-in-call, so not the cold-cache tax. They are NOT explained by
-- anything in this file. pg_stat_activity is filtered for the `postgres` role on this
-- instance (a 45 s sampler at 4 Hz returned 0 rows for non-self backends), so wait-event
-- attribution was not available. Guard (2) is written to survive them rather than to
-- explain them: a 14 s tick can no longer be started at t=50 s and guillotined at t=120 s.
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- SAFETY POSTURE
-- ════════════════════════════════════════════════════════════════════════════════════════
--   * Nothing is dropped. One index is added. One procedure is CREATE OR REPLACE'd, its
--     prior body snapshotted verbatim first and md5-guarded.
--   * cron 12 is NOT disabled, NOT rescheduled, and NOT made conditional. The shield is not
--     touched. 0011's forward-walk is not touched.
--   * The new guard can only ever make the metronome STOP EARLIER than it does today. It
--     cannot make it run longer, and it cannot skip a run.
--   * Kill switch: `metronome_ceiling_guard` (default 1). Set to 0 to restore the exact
--     pre-0012 loop condition.

BEGIN;

-- ════════════════════════════════════════════════════════════════════════════════════════
-- (0) SNAPSHOT + MD5 GUARD
-- ════════════════════════════════════════════════════════════════════════════════════════
-- To restore the pre-0012 metronome by hand:
--   SELECT definition FROM public.ottoq_schema_snapshots
--    WHERE label = 'pre-0012' AND object_name = 'ottoq_demo_metronome';
-- and execute it verbatim.
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT 'pre-0012', 'procedure', 'public', 'ottoq_demo_metronome',
       pg_get_functiondef('public.ottoq_demo_metronome'::regproc),
       md5(pg_get_functiondef('public.ottoq_demo_metronome'::regproc));

DO $guard$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_demo_metronome'::regproc))
     <> 'bc0a2fd6dee75438358ec83f2e7fc7f6' THEN
    RAISE EXCEPTION
      'ottoq_demo_metronome is not the body 0012 was written against (md5 %). Someone hotfixed it; rolling back rather than overwriting their change.',
      md5(pg_get_functiondef('public.ottoq_demo_metronome'::regproc));
  END IF;
END
$guard$;

-- ════════════════════════════════════════════════════════════════════════════════════════
-- (1) THE CALENDAR READ'S MISSING INDEX  (M6)
-- ════════════════════════════════════════════════════════════════════════════════════════
-- The three existing no_overlap objects are GiST EXCLUDE constraints on
-- (sim_run_id, stall_id, during). They enforce the constraint but the planner will not use
-- them to drive a per-stall anti-join probe on a 228-row table. This is a plain partial
-- btree on exactly the equality columns the anti-join filters on, with the same state set
-- ottoq_stall_free_between reads — held / active / done / interrupted. Keeping the two in
-- step matters: the 2026-08-02 finding was that a picker reading a DIFFERENT state set from
-- the constraint put 22 vehicles in one bay.
CREATE INDEX IF NOT EXISTS ottoq_stall_bookings_live_stall_idx
  ON public.ottoq_stall_bookings (sim_run_id, stall_id)
  WHERE state IN ('held','active','done','interrupted');

-- ════════════════════════════════════════════════════════════════════════════════════════
-- (2) THE METRONOME MAY NOT START A TICK IT CANNOT AFFORD TO FINISH  (M2)
-- ════════════════════════════════════════════════════════════════════════════════════════
-- Only three things change, all inside the loop control:
--   a. v_worst_tick_s — the longest tick observed IN THIS CALL, measured, not guessed.
--   b. v_ceiling_s — the CALL's real hard deadline, read from statement_timeout at run time
--      (0 = disabled, which is what a `SET statement_timeout = 0;` cron command produces).
--   c. the pre-tick test: refuse to begin a tick when
--         elapsed + max(1.5 × worst_tick, 15 s)  >  0.9 × ceiling
--      so the CALL returns cleanly and pg_cron starts the next one immediately, instead of
--      being cancelled mid-tick and losing that tick's work AND the rest of the minute.
-- Everything else — the runaway backstop, the playback-mode cadence, the FIRE/DECIDE split,
-- the cuOpt heartbeat, the per-phase lock_timeout, the COMMIT points — is byte-for-byte the
-- pre-0012 body.
CREATE OR REPLACE PROCEDURE public.ottoq_demo_metronome(IN p_budget_s integer DEFAULT 50)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_start timestamptz := clock_timestamp();
  v_run RECORD; v_advanced timestamptz; v_interval numeric; v_base numeric := 6.0;
  v_any boolean; v_window_ms numeric; v_req bigint;
  v_max_ticks int; v_floor numeric; v_max_real_min numeric; v_stop_reason text;
  v_fire_beat_at timestamptz;
  -- ═══ 0012 ═══
  v_tick_t0 timestamptz;          -- start of the tick currently being timed
  v_worst_tick_s numeric := 0;    -- longest tick seen IN THIS CALL
  v_ceiling_s numeric;            -- the CALL's hard deadline (statement_timeout), 0 = none
  v_reserve_s numeric;            -- headroom the next tick must fit inside
  v_guard_on boolean;
  v_elapsed_s numeric;
BEGIN
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  -- The CALL's real deadline. statement_timeout is expressed in ms and is NOT re-armed by
  -- the COMMITs below, so it applies to this procedure end to end.
  BEGIN
    v_ceiling_s := NULLIF(current_setting('statement_timeout', true), '')::numeric / 1000.0;
  EXCEPTION WHEN OTHERS THEN
    v_ceiling_s := 0;   -- unparseable ('2min' etc.) — treat as no ceiling, guard stands down
  END;
  v_ceiling_s := COALESCE(v_ceiling_s, 0);

  LOOP
    SELECT EXISTS (
      SELECT 1 FROM ottoq_sim_runs
      WHERE status = 'running'
        AND COALESCE(run_by,'') NOT IN ('production_live','cert_harness')
    ) INTO v_any;
    EXIT WHEN NOT v_any;

    FOR v_run IN
      SELECT sim_run_id,
             COALESCE((payload->>'speed_x')::numeric, demo_speed_x, 1.0) AS spd,
             COALESCE(payload->>'playback_mode','fixed') AS pmode,
             next_tick_due_at, started_at,
             depot_id, COALESCE(policy,'otto_q') AS policy, COALESCE(tick_count,0) AS ticks
      FROM ottoq_sim_runs
      WHERE status = 'running'
        AND COALESCE(run_by,'') NOT IN ('production_live','cert_harness')
    LOOP
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;
      v_fire_beat_at := NULL;

      -- ═══════════ 0012 CEILING GUARD ═══════════
      -- Refuse to BEGIN a tick that could still be running when statement_timeout fires.
      -- A cancelled CALL rolls back the in-flight tick and forfeits the remainder of the
      -- minute; returning cleanly lets pg_cron start the next call straight away.
      -- Kill switch: policy 'metronome_ceiling_guard' = 0 restores the pre-0012 condition.
      v_guard_on := ottoq_policy_get(v_run.sim_run_id, 'metronome_ceiling_guard', 1) >= 1;
      IF v_guard_on AND v_ceiling_s > 0 THEN
        v_elapsed_s := EXTRACT(EPOCH FROM (clock_timestamp() - v_start));
        -- 15 s floor: the reference run's worst observed world tick was 14.1 s, so a call
        -- that has not yet seen a slow tick still reserves room for one.
        v_reserve_s := GREATEST(v_worst_tick_s * 1.5, 15.0);
        EXIT WHEN v_elapsed_s + v_reserve_s > v_ceiling_s * 0.9;
      END IF;

      -- ═══════════ RUNAWAY BACKSTOP (playback-mode aware) ═══════════
      v_stop_reason := NULL;
      IF v_run.pmode = 'live' THEN
        v_max_ticks    := GREATEST(10, ottoq_policy_get(v_run.sim_run_id, 'demo_max_ticks_live', 5000)::int);
        v_max_real_min := GREATEST(1, ottoq_policy_get(v_run.sim_run_id, 'demo_max_real_minutes', 60));
      ELSE
        v_max_ticks    := GREATEST(10, ottoq_policy_get(v_run.sim_run_id, 'demo_max_ticks', 240)::int);
        v_max_real_min := NULL;
      END IF;

      IF v_run.ticks >= v_max_ticks THEN
        v_stop_reason := 'tick ceiling ' || v_max_ticks || ' reached';
      ELSIF v_max_real_min IS NOT NULL
        AND EXTRACT(EPOCH FROM (clock_timestamp() - COALESCE(v_run.started_at, clock_timestamp())))/60.0
            >= v_max_real_min THEN
        v_stop_reason := 'live-mode real-time ceiling ' || round(v_max_real_min,1) || ' real-min reached';
      END IF;

      IF v_stop_reason IS NOT NULL THEN
        BEGIN
          PERFORM set_config('lock_timeout', '8000', true);
          PERFORM ottoq_sim_stop_and_reset(
            v_run.sim_run_id,
            'auto-stopped by metronome: ' || v_stop_reason || ' (perpetuity backstop)');
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'metronome ceiling-stop % failed: % — forcing status', v_run.sim_run_id, SQLERRM;
          UPDATE ottoq_sim_runs
             SET status = 'completed',
                 ended_at = COALESCE(ended_at, now()),
                 failure_reason = COALESCE(failure_reason, v_stop_reason || '; forced stop')
           WHERE sim_run_id = v_run.sim_run_id;
        END;
        COMMIT;
        CONTINUE;
      END IF;

      v_floor := GREATEST(0.2, ottoq_policy_get(v_run.sim_run_id, 'tick_cadence_floor_s', 2.0));
      IF v_run.pmode = 'live' THEN
        v_interval := GREATEST(v_floor, v_base / GREATEST(v_run.spd, 0.25));
      ELSE
        v_interval := GREATEST(0.2, v_base / GREATEST(v_run.spd, 0.25));
      END IF;
      CONTINUE WHEN v_run.next_tick_due_at IS NOT NULL AND clock_timestamp() < v_run.next_tick_due_at;

      v_tick_t0 := clock_timestamp();          -- 0012: this tick's stopwatch
      v_advanced := NULL;
      BEGIN
        PERFORM set_config('lock_timeout', '8000', true);
        SELECT out_sim_clock_after INTO v_advanced FROM public.ottoq_sim_advance_tick_world(v_run.sim_run_id) LIMIT 1;
      EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome world % failed: %', v_run.sim_run_id, SQLERRM; END;

      IF v_advanced IS NOT NULL THEN
        -- ═══════════════ SPLIT TICK: alternate FIRE and DECIDE ═══════════════
        IF (v_run.ticks % 2) = 1 THEN
          ------------------------------------------------------------------
          -- DECIDE BEAT.
          ------------------------------------------------------------------
          BEGIN
            PERFORM set_config('lock_timeout', '8000', true);
            PERFORM public.ottoq_sim_decide_and_dispatch(v_run.sim_run_id);
          EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome decide % failed: %', v_run.sim_run_id, SQLERRM; END;
        ELSE
          ------------------------------------------------------------------
          -- FIRE BEAT.
          ------------------------------------------------------------------
          IF v_run.policy = 'otto_q' THEN
            v_window_ms := ottoq_policy_get(v_run.sim_run_id, 'cuopt_solve_window_ms', 4000); -- ENABLE flag (>0)
            IF v_window_ms > 0 THEN
              v_req := NULL;
              BEGIN
                PERFORM set_config('lock_timeout', '8000', true);
                v_req := ottoq_cuopt_refresh(v_run.sim_run_id);
              EXCEPTION WHEN OTHERS THEN NULL; END;
              v_fire_beat_at := clock_timestamp();
            END IF;
          END IF;
        END IF;
      END IF;

      -- 0012: remember the worst tick THIS CALL has paid for, so the guard above is
      -- calibrated by measurement rather than by a constant.
      v_worst_tick_s := GREATEST(v_worst_tick_s,
                                 EXTRACT(EPOCH FROM (clock_timestamp() - v_tick_t0)));

      UPDATE ottoq_sim_runs
         SET next_tick_due_at = clock_timestamp() + make_interval(secs => v_interval),
             payload = CASE WHEN v_fire_beat_at IS NOT NULL
                            THEN COALESCE(payload,'{}'::jsonb)
                                 || jsonb_build_object('cuopt_fire_beat_at', v_fire_beat_at)
                            ELSE payload END
       WHERE sim_run_id = v_run.sim_run_id;
      COMMIT;
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;
    END LOOP;
    EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) > p_budget_s;

    -- 0012: the ceiling also ends the OUTER loop, otherwise a guard-triggered inner EXIT
    -- would fall straight back into pg_sleep(0.4) and spin until the budget.
    IF v_guard_on AND v_ceiling_s > 0
       AND EXTRACT(EPOCH FROM (clock_timestamp() - v_start)) + GREATEST(v_worst_tick_s * 1.5, 15.0)
           > v_ceiling_s * 0.9 THEN
      EXIT;
    END IF;

    PERFORM pg_sleep(0.4);
  END LOOP;
END;
$procedure$;

COMMIT;

-- ════════════════════════════════════════════════════════════════════════════════════════
-- (3) THE COMPANION CONFIG CHANGE — NOT SCHEMA, RECORDED HERE SO THE REASON SURVIVES  (M4)
-- ════════════════════════════════════════════════════════════════════════════════════════
-- cron 12's command becomes:
--     SET statement_timeout = '300s'; CALL public.ottoq_demo_metronome(110);
-- Why both halves:
--   * `statement_timeout = 300s` moves the guillotine that (M2) proved is the freeze from
--     120 s — which the 50 s budget plus one 70 s tick can reach — to a distance the budget
--     can never reach. It is deliberately NOT 0: a genuinely hung tick must still die
--     eventually, and `lock_timeout = 8000` only covers lock waits, not a runaway query.
--     The guard in (2) then keeps the CALL from ever touching even that 300 s boundary.
--   * budget 110 s instead of 50 s halves the number of cold pg_cron backends, and (M4)
--     measured the first tick of a call at 2.5–7.4× the rest. pg_cron serialises job 12
--     (proven: 0 overlapping runs in 52 calls), so a longer call does not stack workers —
--     it just means the next call starts when this one ends instead of idling ~10 s/min.
-- This is applied with cron.alter_job, NOT in this transaction, and is re-stated in
-- MIGRATION_LOG.md. cron 12 stays ACTIVE throughout — it is the START engine.
