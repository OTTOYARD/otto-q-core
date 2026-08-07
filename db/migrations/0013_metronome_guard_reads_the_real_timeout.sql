-- migration-version: 20260807002716
-- 0013_metronome_guard_reads_the_real_timeout.sql
-- migration-name:    metronome_guard_reads_the_real_timeout
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- THIS FIXES A DEFECT IN 0012, FOUND BY RUNNING 0012
-- ════════════════════════════════════════════════════════════════════════════════════════
-- 0012 added a ceiling guard to public.ottoq_demo_metronome so the procedure would refuse
-- to BEGIN a tick it could not afford to FINISH before `statement_timeout` cancelled the
-- whole CALL. The guard's logic is right. Its INPUT was wrong, so it never armed:
--
--     v_ceiling_s := NULLIF(current_setting('statement_timeout', true), '')::numeric / 1000.0;
--
-- `current_setting` returns the GUC's DISPLAY form, and Postgres normalises this one to a
-- unit string. Measured on this instance:
--     current_setting('statement_timeout', true)                       => '2min'
--     (select setting from pg_settings where name='statement_timeout') => '120000'
-- `'2min'::numeric` raises 22P02, 0012's own EXCEPTION handler caught it and set
-- v_ceiling_s := 0, and `IF v_guard_on AND v_ceiling_s > 0` is then false forever. The
-- guard was dead code on every call. It never fired, never mis-fired, and never protected
-- anything — 0012's index was doing all the work.
--
-- FIX: read `pg_settings.setting`, which is always the raw value in the GUC's base unit
-- (milliseconds for statement_timeout) and never carries a unit suffix. The EXCEPTION
-- fallback to 0 is KEPT — a guard that cannot read its ceiling must stand down, not guess.
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- ALSO CORRECTED HERE: 0012's SECTION (3) DESCRIBED A CRON COMMAND THAT CANNOT WORK
-- ════════════════════════════════════════════════════════════════════════════════════════
-- 0012 proposed setting cron 12's command to
--     SET statement_timeout = '300s'; CALL public.ottoq_demo_metronome(110);
-- It was applied and it FAILED, three times, within two minutes:
--     ERROR: invalid transaction termination
--     CONTEXT: PL/pgSQL function ottoq_demo_metronome(integer) line 139 at COMMIT
--     (cron 12 runids at 00:19:28 / 00:20:09 / 00:21:32, 22.4 s / 65.5 s / 92.2 s)
-- pg_cron wraps a MULTI-STATEMENT command in one implicit transaction block, so the
-- procedure's own COMMIT becomes illegal. This is exactly why cron 13's
-- `SET statement_timeout = 0; SELECT ottoq_cert_battery_step();` is legal — it calls a
-- FUNCTION, which never commits. A procedure that COMMITs must be the ONLY statement in a
-- pg_cron command. The change was reverted the moment it was observed, and cron 12 is now
--     CALL public.ottoq_demo_metronome(90)
-- — a single statement, so COMMIT is legal again, with the budget raised 50 → 90 s to cut
-- the cold-plan-cache tax 0012 (M4) measured. The 120 s ceiling therefore STAYS, and the
-- guard repaired below — not a cron command — is what keeps the CALL clear of it.
-- Budget 90 s + guard reserve max(1.5 × worst_tick, 15 s) against 0.9 × 120 s = 108 s:
--   * a call whose worst tick so far is 5 s stops at the 90 s budget;
--   * a call that has already paid a 30 s tick stops at 108 − 45 = 63 s;
-- so the CALL returns cleanly and pg_cron starts the next one, instead of being cancelled
-- mid-tick and forfeiting the tick AND the rest of the minute.
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- SAFETY POSTURE
-- ════════════════════════════════════════════════════════════════════════════════════════
--   * Nothing dropped. One procedure CREATE OR REPLACE'd, snapshotted and md5-guarded.
--   * The ONLY behavioural delta vs the 0012 body is the two lines that compute
--     v_ceiling_s. Everything else is byte-for-byte 0012.
--   * The guard can still only make the metronome stop EARLIER. cron 12 stays ACTIVE.
--   * Kill switch unchanged: policy 'metronome_ceiling_guard' = 0 disables it.

BEGIN;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT 'pre-0013', 'procedure', 'public', 'ottoq_demo_metronome',
       pg_get_functiondef('public.ottoq_demo_metronome'::regproc),
       md5(pg_get_functiondef('public.ottoq_demo_metronome'::regproc));

DO $guard$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_demo_metronome'::regproc))
     <> 'da1736f037a2c469f5de7986320ab6ab' THEN
    RAISE EXCEPTION
      'ottoq_demo_metronome is not the 0012 body 0013 was written against (md5 %). Rolling back rather than overwriting.',
      md5(pg_get_functiondef('public.ottoq_demo_metronome'::regproc));
  END IF;
END
$guard$;

CREATE OR REPLACE PROCEDURE public.ottoq_demo_metronome(IN p_budget_s integer DEFAULT 50)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_start timestamptz := clock_timestamp();
  v_run RECORD; v_advanced timestamptz; v_interval numeric; v_base numeric := 6.0;
  v_any boolean; v_window_ms numeric; v_req bigint;
  v_max_ticks int; v_floor numeric; v_max_real_min numeric; v_stop_reason text;
  v_fire_beat_at timestamptz;
  -- 0012 ceiling guard, input repaired by 0013
  v_tick_t0 timestamptz;
  v_worst_tick_s numeric := 0;
  v_ceiling_s numeric;
  v_reserve_s numeric;
  v_guard_on boolean := true;
  v_elapsed_s numeric;
BEGIN
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  -- 0013: pg_settings.setting is the raw value in the GUC's base unit (ms) and never
  -- carries a unit suffix. current_setting() returns the display form ('2min'), which is
  -- not castable to numeric — that is the 0012 defect this migration exists to fix.
  BEGIN
    SELECT s.setting::numeric / 1000.0 INTO v_ceiling_s
      FROM pg_settings s WHERE s.name = 'statement_timeout';
  EXCEPTION WHEN OTHERS THEN
    v_ceiling_s := 0;   -- unreadable ceiling => guard stands down rather than guessing
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

      v_guard_on := ottoq_policy_get(v_run.sim_run_id, 'metronome_ceiling_guard', 1) >= 1;
      IF v_guard_on AND v_ceiling_s > 0 THEN
        v_elapsed_s := EXTRACT(EPOCH FROM (clock_timestamp() - v_start));
        v_reserve_s := GREATEST(v_worst_tick_s * 1.5, 15.0);
        EXIT WHEN v_elapsed_s + v_reserve_s > v_ceiling_s * 0.9;
      END IF;

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

      v_tick_t0 := clock_timestamp();
      v_advanced := NULL;
      BEGIN
        PERFORM set_config('lock_timeout', '8000', true);
        SELECT out_sim_clock_after INTO v_advanced FROM public.ottoq_sim_advance_tick_world(v_run.sim_run_id) LIMIT 1;
      EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome world % failed: %', v_run.sim_run_id, SQLERRM; END;

      IF v_advanced IS NOT NULL THEN
        IF (v_run.ticks % 2) = 1 THEN
          BEGIN
            PERFORM set_config('lock_timeout', '8000', true);
            PERFORM public.ottoq_sim_decide_and_dispatch(v_run.sim_run_id);
          EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome decide % failed: %', v_run.sim_run_id, SQLERRM; END;
        ELSE
          IF v_run.policy = 'otto_q' THEN
            v_window_ms := ottoq_policy_get(v_run.sim_run_id, 'cuopt_solve_window_ms', 4000);
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
