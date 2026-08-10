-- MIGRATION: 0041_fix_metronome_ceiling.sql
-- Fix the metronome ceiling guard: read statement_timeout from pg_settings
-- instead of current_setting(). current_setting returns '2min' which fails
-- ::numeric, setting ceiling to 0 and disabling the guard.
-- Without the guard, the metronome runs until statement_timeout kills it,
-- rolling back all tick advancement changes.
-- 
-- This migration applies the fix from 0013 without the md5 guard.

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
