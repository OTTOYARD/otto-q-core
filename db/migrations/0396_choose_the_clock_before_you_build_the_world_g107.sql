-- migration-version: 20260921025959
-- migration-name:    choose_the_clock_before_you_build_the_world_g107
--
-- 0396  G107 — CHOOSE THE CLOCK BEFORE YOU BUILD THE WORLD.
--
-- `forces_recert TRUE`. It does not change `sim_clock_start`'s VALUE — that is preserved
-- byte-for-byte, by reproducing the old post-hoc expression verbatim in the new place — but it
-- changes the WORLD every demo run ticks through, which is exactly what a recert floor is for.
--
-- THE DEFECT, traced in `db/checks/0297` and measured on run `c9b0a87e`:
--   1. `ottoq_start_demo_run` called `ottoq_sim_run_scenario(scenario, seed, 'operator_demo')`.
--   2. That function set `sim_clock_start` to 08:00 Central (13:00 UTC) and BUILT THE WORLD
--      against it — `ottoq_sim_seed_fleet(depot, seed, v_start_hour=8)`,
--      `ottoq_deploy_target_fraction(8, 0.92)`, the need-profile draw at 13:00, and
--      `ottoq_sim_prime_deployment(run, v_start, frac)` writing `dispatched_at := v_start - elapsed`.
--   3. `ottoq_start_demo_run` THEN rewrote `sim_clock_start` to
--      `date_trunc('day', sim_clock_start) + abs(hashtext(seed)) % 1440` — 335 minutes for seed
--      100020, i.e. **2026-09-20 05:35:00+00**, seven hours twenty-five minutes away from the clock
--      the world had just been built against.
--   4. Nothing moved the world when the clock moved. Measured: **45 of 87 dispatch rows carried
--      `dispatched_at` of 12:03–12:59 sim against a `sim_clock_start` of 05:35**; the twin ticked
--      from 05:35, those vehicles returned at 05:45–05:52, and the completion branch stored
--      `actual_duration_min = (clock - dispatched_at)/60` — **negative on 32 rows, -387.98 to
--      -439.5 minutes.** KPI 1 credited every one of them zero hours, which is the whole of the
--      -227.36 `hours_clipped_to_window` that G103 was filed against.
--
-- THE FIX IS AN ORDERING FIX AND NOTHING ELSE.
--   (a) `ottoq_sim_run_scenario` gains an optional fourth parameter `p_start_clock`. When non-NULL
--       it is the clock, and `v_start_hour`, the fleet seed, the deploy fraction, the need-profile
--       draw and the prime all derive from it. Every existing caller passes three arguments and
--       gets byte-for-byte the previous behaviour through `COALESCE`.
--   (b) `ottoq_start_demo_run` computes the seed-derived start FIRST, with literally the same
--       expression the post-hoc UPDATE carried, passes it in, and **stops rewriting
--       `sim_clock_start` / `sim_clock_current` altogether.** It still owns `sim_clock_end`, which
--       depends on `p_days` — a demo-only parameter the scenario cannot know.
--
-- WHY THERE IS NO CHECK CONSTRAINT ON `actual_duration_min`, although `0297` proposed one.
-- The negative is written by the completion branch of `twin.ottoq_sim_advance_deployed_telemetry`,
-- which is the TICK HOT PATH and is not wrapped in an exception handler. A blocking CHECK there
-- would turn a data defect into a dead run, against this engine's own standing rule that "one bad
-- vehicle must never abort the whole telemetry step". So the assertion is a LOUD, RUN-SCOPED
-- FUNCTION instead — `ottoq_assert_dispatch_time_coherence` below — callable from the KPI and cert
-- paths, where failing loudly costs a verdict rather than a demo. It is proven by being run against
-- `c9b0a87e`, where it must FAIL with 32 rows.
--
-- A DROP is required for (a): `CREATE OR REPLACE` matches on the argument list, so adding a
-- parameter would create an OVERLOAD and every three-argument call would become ambiguous.

BEGIN;

DROP FUNCTION IF EXISTS public.ottoq_sim_run_scenario(text, bigint, text);

CREATE OR REPLACE FUNCTION public.ottoq_sim_run_scenario(p_scenario_code text, p_seed bigint DEFAULT NULL::bigint, p_run_by text DEFAULT 'system_scheduler'::text, p_start_clock timestamptz DEFAULT NULL::timestamptz)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_scenario   ottoq_sim_scenarios%ROWTYPE;
  v_sim_run_id UUID := gen_random_uuid();
  v_seed       BIGINT;
  v_start      TIMESTAMPTZ;
  v_end        TIMESTAMPTZ;
  v_start_hour INT;
  v_prime_frac NUMERIC;
BEGIN
  SELECT * INTO v_scenario FROM ottoq_sim_scenarios
   WHERE scenario_code = p_scenario_code AND status = 'available';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'scenario % not found or not available', p_scenario_code;
  END IF;

  --: 0297 / G107. THE CALLER MAY NOW NAME THE CLOCK, AND IF IT DOES, EVERYTHING
  --: BELOW IS BUILT AGAINST THAT ONE CLOCK. Before this parameter existed,
  --: ottoq_start_demo_run let this function pick 08:00 Central, primed 45 of 87
  --: dispatch rows against it, and THEN rewrote sim_clock_start to a seed-derived
  --: minute of the UTC day -- 7h25m away for seed 100020 -- leaving the world
  --: anchored to a clock the tick path never visits. Measured consequence: 32 rows
  --: stored actual_duration_min between -388 and -440 minutes, and KPI 1 credited
  --: them zero. p_start_clock is how the demo wrapper owns its own randomised start
  --: BEFORE the world exists instead of after. Every other caller passes NULL and
  --: gets byte-for-byte the previous behaviour.
  v_start := COALESCE(p_start_clock,
    CASE WHEN p_run_by = 'operator_demo'
      THEN ((date_trunc('day', now() AT TIME ZONE 'America/Chicago') + interval '8 hours') AT TIME ZONE 'America/Chicago')
      ELSE NOW() END);
  v_start_hour := EXTRACT(HOUR FROM (v_start AT TIME ZONE 'America/Chicago'))::int;

  v_seed := COALESCE(p_seed, abs(hashtextextended(gen_random_uuid()::text, 42)));
  v_end  := v_start + (v_scenario.default_duration_hours || ' hours')::interval;

  INSERT INTO ottoq_scenarios (
    scenario_id, scenario_code, category, title, description,
    depot_id, sim_duration_minutes, default_time_scale, tick_interval_seconds,
    initial_conditions, arrival_profile, timeline, random_seed, status,
    introduced_in, created_at, updated_at
  ) VALUES (
    v_scenario.scenario_id, v_scenario.scenario_code,
    CASE
      WHEN p_scenario_code = 'normal_day' THEN 'normal_operations'
      WHEN p_scenario_code IN ('heat_wave','winter_storm','solar_underperformance_partly_cloudy',
                               'aggressive_fleet_turnover') THEN 'stress_test'
      WHEN p_scenario_code IN ('dr_event_cascade','charger_outage_morning_rush',
                               'grid_brownout_at_peak') THEN 'edge_case'
      ELSE 'demo' END,
    v_scenario.title, COALESCE(v_scenario.description, v_scenario.title),
    v_scenario.default_depot_id,
    (v_scenario.default_duration_hours * 60)::int,
    v_scenario.default_time_scale,
    v_scenario.default_tick_seconds,
    jsonb_build_object('weather_overrides', v_scenario.weather_overrides,
                       'fleet_overrides',   v_scenario.fleet_overrides),
    jsonb_build_object('shape', 'nyc_tlc_hourly_arrival_rate'),
    jsonb_build_object('grid_overrides',    v_scenario.grid_overrides,
                       'charger_overrides', v_scenario.charger_overrides,
                       'fault_injection',   v_scenario.fault_injection),
    v_seed, 'active', '20260619_twin_a6', NOW(), NOW()
  )
  ON CONFLICT (scenario_id) DO NOTHING;

  UPDATE ottoq_sim_runs SET status='completed', ended_at=NOW(),
         notes = COALESCE(notes,'') || ' | superseded by ' || p_scenario_code
   WHERE depot_id = v_scenario.default_depot_id AND status='running';

  -- 0023: OWNERLESS needs only. A run's own open needs are closed by the run's
  -- OWN terminal transition (trigger ottoq_sim_runs_close_needs), including the
  -- run this call is superseding one statement above and the run the start button
  -- aborted before calling here. What no run transition can ever reach is a need
  -- with no sim_run_id at all -- that, and only that, is cleared here. A finished
  -- run's ledger is read-only.
  UPDATE ottoq_visit_needs vn SET status = 'superseded'
    FROM vehicles v
   WHERE vn.vehicle_id = v.id AND v.home_depot_id = v_scenario.default_depot_id
     AND vn.sim_run_id IS NULL
     AND vn.status IN ('open','in_progress');

  INSERT INTO ottoq_sim_runs (
    sim_run_id, scenario_id, scenario_code, status,
    sim_clock_start, sim_clock_current, sim_clock_end,
    started_at, last_tick_at, next_tick_due_at,
    depot_id, random_seed, time_scale, tick_interval_seconds,
    run_by, notes
  ) VALUES (
    v_sim_run_id, v_scenario.scenario_id, v_scenario.scenario_code, 'running',
    v_start, v_start, v_end, NOW(), NOW(), NOW(),
    v_scenario.default_depot_id, v_seed,
    v_scenario.default_time_scale, v_scenario.default_tick_seconds,
    p_run_by, 'Started via ottoq_sim_run_scenario(' || p_scenario_code || ')'
  );

  BEGIN
    PERFORM ottoq_sim_seed_fleet(v_scenario.default_depot_id, v_seed, v_start_hour);
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('seed_fleet', jsonb_build_object('ok', true))
     WHERE sim_run_id = v_sim_run_id;
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('seed_fleet', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
  END;

  -- CARD-2: the DRAW PHASE — every world + per-vehicle variable dealt before tick 1
  BEGIN
    PERFORM ottoq_run_boot_draw(v_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('boot_draw', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
    BEGIN
      PERFORM ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'run_boot_draw',
        p_event_type := 'twin.boot_draw_failed', p_entity_type := 'system',
        p_payload := jsonb_build_object('sim_run_id', v_sim_run_id, 'error', SQLERRM),
        p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id := v_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END;

  BEGIN
    PERFORM ottoq_variability_instantiate(v_sim_run_id, p_scenario_code);
  EXCEPTION WHEN undefined_function THEN NULL;
  END;

  -- (A) SCENARIO FLEET OVERRIDES -- on the LOAD path, not in a wrapper. Runs AFTER
  --     ottoq_run_boot_draw (which unconditionally rewrites pm_interval_km /
  --     calib_interval_h) and BEFORE prime, so the wear phase offsets see the final
  --     intervals. Receipt, never silence: a failure here is recorded on the run.
  BEGIN
    PERFORM ottoq_scenario_apply_fleet_overrides(v_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('scenario_overrides', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
    RAISE WARNING 'scenario fleet overrides: %', SQLERRM;
  END;

  BEGIN
    IF NOT EXISTS (SELECT 1 FROM depots d
                    WHERE d.id = v_scenario.default_depot_id AND d.slug LIKE 'benchmark%') THEN
      DECLARE v_primed INTEGER; v_pool INTEGER; v_states JSONB;
      BEGIN
        SELECT COUNT(*) INTO v_pool FROM vehicles v
         WHERE v.home_depot_id = v_scenario.default_depot_id AND v.category = 'autonomous'
           AND v.current_soc >= 80
           AND v.current_state IN ('staged_for_departure','en_route_to_deployment','offline');
        SELECT jsonb_object_agg(s, n) INTO v_states
          FROM (SELECT current_state::text AS s, COUNT(*) AS n FROM vehicles
                 WHERE home_depot_id = v_scenario.default_depot_id AND category = 'autonomous'
                 GROUP BY 1) t;
        -- (B) prime at the SCENARIO's hour-shaped deployed target
        v_prime_frac := ottoq_deploy_target_fraction(
                          v_start_hour,
                          COALESCE((v_scenario.fleet_overrides->>'target_deployed_fraction')::numeric, 0.92));
        v_primed := ottoq_sim_prime_deployment(v_sim_run_id, v_start, v_prime_frac);
        UPDATE ottoq_sim_runs
           SET payload = COALESCE(payload,'{}'::jsonb)
                       || jsonb_build_object('boot_prime', jsonb_build_object(
                            'ok', true, 'primed', v_primed, 'candidate_pool', v_pool,
                            'prime_fraction', v_prime_frac, 'start_hour_cst', v_start_hour,
                            'state_histogram', v_states))
         WHERE sim_run_id = v_sim_run_id;
      END;
    ELSE
      UPDATE ottoq_sim_runs
         SET payload = COALESCE(payload,'{}'::jsonb)
                     || jsonb_build_object('boot_prime', jsonb_build_object('ok', true, 'skipped', 'benchmark_depot'))
       WHERE sim_run_id = v_sim_run_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    UPDATE ottoq_sim_runs
       SET payload = COALESCE(payload,'{}'::jsonb)
                   || jsonb_build_object('boot_prime', jsonb_build_object('ok', false, 'error', SQLERRM))
     WHERE sim_run_id = v_sim_run_id;
  END;

  IF v_scenario.grid_overrides ? 'force_bess_starting_soc_pct' THEN
    UPDATE ottoq_bess_units
       SET current_soc_pct = (v_scenario.grid_overrides->>'force_bess_starting_soc_pct')::numeric,
           current_soc_kwh = capacity_kwh
                          * ((v_scenario.grid_overrides->>'force_bess_starting_soc_pct')::numeric) / 100.0
     WHERE depot_id = v_scenario.default_depot_id;
  END IF;

  -- 0323: ARM THE AGENTIC LAYER ON THE WAY IN. Across 1,147 runs nothing
  -- that started a run had ever done this, so every run booted with the
  -- proposer door shut and the UI could never show the agentic half
  -- working. Arming is part of STARTING now, at every door, so a run is
  -- armed because it was started and not because somebody remembered.
  --
  -- THE cert_harness TEST IS NOT OPTIONAL. Arming sets
  -- proposer_frame_facts=1, which changes what the decision frame carries
  -- (0265) -- the frame every canon was measured against. The arming
  -- routine refuses such a run by RAISING, so an unguarded call would
  -- abort the creation of every certification arm.
  IF COALESCE(p_run_by, '') <> 'cert_harness' THEN
    BEGIN
      PERFORM public.ottoq_agentic_arm(v_sim_run_id, 'auto:' || COALESCE(p_run_by, 'unknown'));
      UPDATE public.ottoq_sim_runs SET payload = COALESCE(payload, '{}'::jsonb)
             || jsonb_build_object('agentic_arm', jsonb_build_object('ok', true))
       WHERE sim_run_id = v_sim_run_id;
    EXCEPTION WHEN OTHERS THEN
      -- Receipt, never silence, and never a failed start: a run that could
      -- not be armed is still a valid run, and the reason is on the row.
      UPDATE public.ottoq_sim_runs SET payload = COALESCE(payload, '{}'::jsonb)
             || jsonb_build_object('agentic_arm',
                  jsonb_build_object('ok', false, 'error', SQLERRM))
       WHERE sim_run_id = v_sim_run_id;
    END;
  END IF;

  PERFORM ottoq_record_event(
    p_actor_type := 'system_scheduler', p_actor_id := 'twin_scenario_runner',
    p_event_type := 'twin.scenario_started', p_entity_type := 'system',
    p_payload := jsonb_build_object('sim_run_id', v_sim_run_id, 'scenario_code', p_scenario_code,
      'seed', v_seed, 'start_hour_cst', v_start_hour, 'duration_h', v_scenario.default_duration_hours),
    p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := v_sim_run_id);

  RETURN v_sim_run_id;
END;
$function$;


CREATE OR REPLACE FUNCTION public.ottoq_start_demo_run(p_scenario text DEFAULT 'normal_day'::text, p_speed numeric DEFAULT 1.0, p_days integer DEFAULT 1, p_seed bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  r uuid;
  -- 8.0 matches the hard clamp in ottoq_set_playback. Keep the two in step.
  v_x numeric := GREATEST(0.25, LEAST(8.0, COALESCE(p_speed,1.0)));
  v_purge jsonb;
  v_aborted int;
  v_offset_min int;
  v_new_start timestamptz;
BEGIN
  UPDATE ottoq_sim_runs
     SET status = 'aborted'
   WHERE COALESCE(run_by,'') <> 'production_live'
     AND status IN ('running','paused');
  GET DIAGNOSTICS v_aborted = ROW_COUNT;

  --: 0297 / G107. THE CLOCK IS CHOSEN HERE, BEFORE THE WORLD IS BUILT.
  --: v_offset_min and v_new_start are computed with EXACTLY the expression the
  --: post-hoc UPDATE used to carry -- date_trunc('day', <today 08:00 Central>) plus
  --: the seed-derived minute -- so sim_clock_start keeps the same VALUE it always
  --: had (seed 100020 -> 2026-09-20 05:35:00+00, verified in db/checks/0297). What
  --: changes is that ottoq_sim_run_scenario now seeds the fleet, chooses the deploy
  --: fraction, draws the need profiles and PRIMES THE DEPLOYMENT against this clock
  --: instead of against 08:00 Central. The clock did not move; the world moved to
  --: meet it.
  v_offset_min := CASE
    WHEN p_seed IS NOT NULL THEN (abs(hashtext(p_seed::text)) % 1440)
    ELSE floor(random() * 1440)::int
  END;
  v_new_start := date_trunc('day',
                   ((date_trunc('day', now() AT TIME ZONE 'America/Chicago') + interval '8 hours')
                     AT TIME ZONE 'America/Chicago'))
                 + make_interval(mins => v_offset_min);

  r := ottoq_sim_run_scenario(p_scenario, p_seed, 'operator_demo', v_new_start);

  --: 0297 / G107. sim_clock_start and sim_clock_current are NO LONGER TOUCHED here
  --: -- ottoq_sim_run_scenario already inserted v_new_start into both, and rewriting
  --: them after the world was built is the entire defect this file closes. Only the
  --: horizon (which depends on p_days, a demo-only parameter the scenario cannot
  --: know) and the playback fields are set here. The value written to sim_clock_end
  --: is identical to what the old UPDATE produced, because v_new_start is identical.
  UPDATE ottoq_sim_runs
     SET sim_clock_end    = v_new_start + make_interval(days => GREATEST(1, p_days)),
         demo_speed_x     = v_x,
         next_tick_due_at = now()
   WHERE sim_run_id = r;

  -- ═══════ LIVE CLOCK IS NOW THE DEMO DEFAULT (2026-08-01) ═══════
  -- Fixed mode quantises ETA to the 30-minute tick grid, so the approach band's
  -- 10-minute freeze threshold had nothing to bite on (the boundary was crossed
  -- only 3 times in 1,850 observations) and the cuOpt window collapsed to a single
  -- point at exactly 30.00 min. In live mode the sim clock advances by REAL elapsed
  -- time x speed_x, so ETA is CONTINUOUS at any speed -- a multiplier is fine and is
  -- how the founder actually watches. ottoq_set_playback applies the founder-approved
  -- 1x-8x clamp for continuous play. This is the DEMO/VIEWING path only: the cert
  -- harness (run_by='cert_harness') and production_live never call this function and
  -- keep fixed-mode determinism.
  PERFORM ottoq_set_playback(r, 'live', v_x);

  v_purge := ottoq_purge_prior_runs(r);

  RETURN jsonb_build_object('ok', true, 'sim_run_id', r, 'scenario', p_scenario,
    'demo_speed_x', v_x, 'real_seconds_per_tick', round(6.0/v_x,2),
    'playback_mode', 'live', 'playback_speed_x', LEAST(8.0, GREATEST(1.0, v_x)),
    'runs_for_sim_days', GREATEST(1,p_days),
    'sim_clock_start', v_new_start,
    'start_time_of_day', to_char(v_new_start, 'HH24:MI'),
    'start_offset_min', v_offset_min,
    'start_deterministic', p_seed IS NOT NULL,
    'aborted_prior_running', v_aborted, 'purged_prior', v_purge);
END;
$function$
;

-- ─────────────────────────────────────────────────────────────────────────────
-- THE ASSERTION. Loud, run-scoped, and off the tick path on purpose (see header).
--
-- It answers one question — "does every dispatch in this run return after it left?" — and it is
-- the question nothing in the database asked, which is how a trip of negative four hundred minutes
-- got computed, persisted, and past every check we have. Two independent witnesses, because the
-- redundancy is the point: the TIMESTAMP order and the STORED DURATION are written by the same
-- UPDATE from the same clock, so a disagreement between them would itself be a finding.
--
-- Returns a row rather than raising when clean, so a caller can log it; raises only on violation,
-- with the counts and the worst case named, because an assertion that fails without saying by how
-- much sends the reader back to the query.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_assert_dispatch_time_coherence(p_sim_run_id uuid)
RETURNS TABLE (dispatches int, inverted_timestamps int, negative_durations int,
               worst_inversion_min numeric, verdict text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_n int; v_inv int; v_neg int; v_worst numeric;
BEGIN
  SELECT count(*)::int,
         count(*) FILTER (WHERE d.actual_return_at IS NOT NULL
                            AND d.actual_return_at < d.dispatched_at)::int,
         count(*) FILTER (WHERE d.actual_duration_min < 0)::int,
         round(COALESCE(max(EXTRACT(epoch FROM d.dispatched_at - d.actual_return_at) / 60.0), 0)::numeric, 1)
    INTO v_n, v_inv, v_neg, v_worst
    FROM public.ottoq_vehicle_dispatches d
   WHERE d.sim_run_id = p_sim_run_id;

  IF v_inv > 0 OR v_neg > 0 THEN
    RAISE EXCEPTION 'dispatch time coherence FAILED on run %: % of % dispatches return before they '
                    'were dispatched and % carry a negative actual_duration_min (worst inversion '
                    '% min). G107: the world was built against a different clock than the tick path '
                    'advances from -- see db/checks/0297.',
                    p_sim_run_id, v_inv, v_n, v_neg, v_worst;
  END IF;

  RETURN QUERY SELECT v_n, v_inv, v_neg, v_worst,
    format('coherent: all %s dispatches return after they were dispatched', v_n);
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_assert_dispatch_time_coherence(uuid) IS
  'G107 / db/checks/0297. Raises if any dispatch in the run has actual_return_at < dispatched_at or '
  'a negative actual_duration_min. Deliberately NOT a CHECK constraint: the writer is the tick hot '
  'path and is unwrapped, so a blocking constraint would turn a data defect into a dead run. Call it '
  'from the KPI or cert path, where failing loudly costs a verdict rather than a demo.';

-- ─────────────────────────────────────────────────────────────────────────────
-- THE RECERT CLASSIFICATION, and this one is TRUE for a reason worth stating: the CLOCK does not
-- move, the WORLD does. `sim_clock_start` keeps the exact value it always had, so `config_hash` --
-- which keys scenario, seed, policy, depot, horizon, clock and effective params -- is UNCHANGED.
-- Every canon would therefore keep its column streak on a hash comparison alone, while the run
-- underneath it now seeds its fleet, chooses its deployed fraction, draws its need profiles and
-- primes its dispatches against a clock seven hours away from where it used to. A recert floor that
-- cannot see that is exactly the G25/G28 refusal: never call a column green when the comparison is
-- narrower than the change.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0396_choose_the_clock_before_you_build_the_world_g107',
  true,
  'Gives ottoq_sim_run_scenario an optional p_start_clock and makes ottoq_start_demo_run choose the '
  'seed-derived start BEFORE the world is built instead of rewriting sim_clock_start after. TRUE: '
  'the clock keeps its exact value (config_hash unchanged) but every demo run''s world moves to meet '
  'it -- fleet seed, deploy fraction, need-profile draw and prime_deployment all now derive from the '
  'clock the tick path actually advances from. Measured on c9b0a87e (db/checks/0297): the world was '
  'built at 08:00 Central (13:00 UTC) and the tick path ran from 05:35 UTC, so 45 of 87 dispatch '
  'rows carried a dispatched_at seven hours twenty-five minutes in the sim future, 32 of them '
  'finished storing an actual_duration_min between -387.98 and -439.5 minutes, and KPI 1 credited '
  'every one of them zero hours -- which is the whole of the -227.36 hours_clipped_to_window that '
  'G103 was filed against. The diagnostic was faithful; the world was wrong. Also adds '
  'ottoq_assert_dispatch_time_coherence, deliberately a function and not a CHECK constraint: the '
  'writer is the tick hot path and is unwrapped, so a blocking constraint would turn a data defect '
  'into a dead run. Certification is unaffected -- only ottoq_start_demo_run rewrote '
  'sim_clock_start anywhere in the database, and cert_harness never calls it; three pairs at seeds '
  '424242 and 171717 passed after this was applied.',
  now());

COMMIT;
