-- migration-version: 20260923012432
-- migration-name:    the_battery_planned_eight_hours_ahead_on_a_forecast_where_charging_stops_and_was_empty_before_the_expensive_afternoon
--
-- 0435  **The battery's planner looked eight hours ahead, on a forecast in which EV charging stops as soon as
--       today's sessions finish. So it spent the battery flattening cheap morning load, after the month's peak
--       was already billed, and met the expensive afternoon near its floor.** Evidence: run `7a42982a` (busy_day,
--       twin depot), `db/checks/0353` §4, FINDINGS G169, docs/REVIEW_RANKED_FINDINGS_2026-09-22.md rank 1b.
--
-- ══ §1 WHAT IS WRONG, FROM SOURCE AND FROM THE RUN ═══════════════════════════
--
--   (a) THE HORIZON. With `energy_reserve_shave` on — the agent's switch; `ottoq_prime` wrote all 273 run-scope
--       rows of it, every one 1 — `ottoq_energy_orchestrate`'s FR-1b branch takes its grid target from
--       `ottoq_bess_reserve_target(run, depot, clock, 16, 30)`: sixteen 30-minute steps. From 04:00 CT it cannot
--       see 13:00, where NES GSA-3's on-peak energy starts: $0.158/kWh, $0.235 at 17–19, against $0.052
--       off-peak (0–6) and $0.092 mid-peak (6–13) (`ottoq_tariff_windows`, twin depot).
--   (b) THE FORECAST. `ottoq_forecast_net_load` holds building load and solar at their last snapshot and counts
--       EV load only from sessions already running and dispatches already scheduled to return. On this depot a
--       dispatch lasts 0.3–0.6 sim-hours (96 on `7a42982a` by 09:50 CT, 4 active at a time), so within about an
--       hour the forecast is base load alone, and the water-fill shaves a load it believes is about to vanish.
--       Measured on `7a42982a` (`ottoq_energy_commands`, mode `discharge_reserve_shave`): grid target 125 kW at
--       05:00, 192 at 06:00, 262 at 07:00, 521 at 08:00; discharge 627/507/585/269 kW; EV load meanwhile
--       697/633/755/742 kW. SoC 94.7% at 04:12 → 25.2% at 10:23, still discharging.
--   (c) THE PRICE. Shaving pays only above the peak already billed this month. `7a42982a`'s billing-period peak
--       was 1,657 kW, set in the 04:00 boot burst, so every kWh the battery spent between 05:00 and 11:00 bought
--       NO demand charge. That energy displaced grid energy at $0.052–$0.092 that the afternoon would have
--       displaced at $0.158–$0.235.
--   (d) THE UNITS (found here, NOT fixed here: G172). `ottoq_bess_units.roundtrip_efficiency_pct` holds a
--       FRACTION — 0.96 on the twin depot — and the plant reads it as one (`twin.ottoq_sim_bess_step`:
--       `SQRT(COALESCE(v.roundtrip_efficiency_pct, 0.96))`). Three planners read it as a PERCENT —
--       `ottoq_bess_reserve_target`, `ottoq_energy_mpc_replan` and `ottoq_fr1_reactive_min_peak` all compute
--       `sqrt(GREATEST(0.5, COALESCE(…,90)/100.0))`. That gives 0.0096, which clamps to 0.5, so a 96% battery is
--       planned as a 50% one: 0.707 per direction instead of 0.980. The water-fill is kept below as the as-was
--       policy, so its reading is left as it ran; the day plan reads the column either way (fraction ≤ 1, else
--       percent).
--   (e) THE SOLVER'S POWER CAP (G173, and very likely most of G167). `ottoq_build_site_descriptor` gives CP-SAT
--       `power_cap_kw_hard = floor(LEAST(service_max_kw, ottoq_active_charge_cap_kw(...)))`, and
--       `solvers/cpsat/model.py` spends that in `AddCumulative`. The live cap is this orchestrator's advisory
--       `charge_cap_kw` = target − building + solar + battery dispatch. While the battery shaves toward a target,
--       dispatch = net − target, so the cap equals the EV load already running.
--       Measured on `7a42982a`: over its 811 `discharge_reserve_shave` ticks the solver's headroom (cap − EV)
--       averaged 16 kW (median 24 kW), and 808 of the 811 were under 100 kW — less than one DCFC. The 112 idle
--       ticks averaged 920 kW. A cumulative constraint with no headroom can start a charge only after another
--       ends, and G167's abstentions read exactly that way from the inside: "planned to start at +N min, beyond
--       this tick's 30-min window".
--       The cap's arithmetic is right: at the defended level there IS no headroom. What was wrong is the level,
--       125–521 kW (b). In plan mode the level is the billed peak unless shaving pays, and battery charging no
--       longer consumes the fleet's share (§2.6).
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════
--
--   A day-length plan replaces the water-fill as the implementation of `energy_reserve_shave`. The water-fill
--   stays reachable as a named policy: `bess_day_plan_enabled = 0`, globally or per run.
--
--   1. HORIZON. 30-minute steps (the tariff's own demand interval, `demand_basis = NCP_30min`) from now to
--      local midnight, at least 8 h and at most 24 h, re-solved every tick.
--   2. FORECAST. Every term comes from this run's own rows or static site data, so both arms of a pair see the
--      same plan:
--      - EV: the known sessions and returns, lifted VERBATIM out of `ottoq_forecast_net_load` into
--        `ottoq_forecast_ev_known_kw` (the parent now calls it; V1 proves its output unchanged), floored at the
--        mean EV load of the last 60 sim-minutes (persistence).
--      - building: the depot's hourly median outside any run (`sim_run_id IS NULL`; 2,455 rows, 24 of 24 hours
--        populated at writing), plus the current anomaly decaying with a 4-hour time constant.
--      - solar: clear-sky-index persistence (observed kW over sin(solar elevation) across the last hour of
--        daylight, carried along the sun's path). `twin.ottoq_sim_solar_elevation_deg` is IMMUTABLE astronomy
--        and reads no simulated state, so a production site computes the same number. Before first light the
--        estimate is nameplate × soiling × 0.75 (ASSUMPTION, §4.5).
--   3. OBJECTIVE (`ottoq_bess_plan_eval`, pure arithmetic).
--      - For a candidate grid level m, the battery must hold net load at or under m, on both power and
--        cumulative energy, net of a per-step reserve.
--      - Energy left over goes to the steps where a kWh is worth most, and never so much that the site exports.
--      - value = demand value of the peak removed above the billed peak (the ratchet)
--                + Σ (TOU price − replacement cost − wear) × kWh.
--      - replacement cost = the cheapest TOU rate ÷ round-trip; demand value per day = $21.40 ÷ 30 (dial).
--      - The value is concave in m (it is an LP's value in its right-hand side). So the plan bisects for the
--        lowest feasible m, then ternary-searches above it; ties go to the higher level, which spends less.
--      - A level under the billed peak buys nothing, so the plan defends the ratchet instead whenever that
--        scores no worse.
--   4. DR RESERVE. On summer-tariff days, 600 kWh (dial) is held until 14:00 and released linearly to 20:00,
--      the DR program window. A live call overrides the plan: the orchestrator's DR branch discharges to the
--      call's cap, reserve included. `0433` §4.2 deferred this reserve until SoC at ignition was measured;
--      `db/checks/0353` §3 is that measurement.
--   5. RECHARGE. Only when the plan discharges nothing now, and only under the defended level minus
--      max(100 kW, 10% of the level). It takes at most half the remaining headroom, so the fleet keeps the other
--      half while the battery ramps down at 250 kW per tick (`ottoq_apply_bess_setpoint`). It charges when:
--      - now is the cheapest window;
--      - a kWh bought now (price ÷ round-trip + wear) is worth more at a later step the plan could not fill;
--      - the peak level itself is energy-bound;
--      - the DR reserve is short;
--      - or there is solar surplus.
--   6. THE FLEET FIRST. In plan mode the advisory charge cap (`ottoq_active_charge_cap_kw`, which
--      `ottoq_build_site_descriptor` gives the solvers) no longer counts battery charging against EV headroom:
--      the headroom up to the level belongs to the fleet, and the battery yields.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════
--
--   - Every changed control line sits behind `energy_reserve_shave >= 0.5`, and no certification run reaches
--     it. P3 asserts that no depot- or global-scope row turns it on and that no `cert_harness` run has a
--     run-scope row. The agent never fires on cert runs, and `ottoq_agentic_arm` refuses them (42501).
--   - The one key added to the logged command reason (`day_plan`) is appended only in plan mode (`|| '{}'`
--     otherwise), so `h_nrg`, which digests `reason::text`, sees identical text. V4(i) proves it on a probe.
--   - `ottoq_forecast_net_load` is rewritten to call the lifted loops, and V1 proves its output identical.
--
-- ══ §4 WHAT THIS DOES NOT DO, AND THE ASSUMPTIONS ═══════════════════════════════
--
--   1. The EV forecast is a floor, not a model of work-side demand. Persistence cannot see an evening return
--      wave or a lull. A deploy-curve EV model is the next step, and it needs G163 (run-scoped need profiles)
--      first.
--   2. The DR reserve is season-gated, not temperature-gated, because the twin's temperature curve is wrong:
--      it peaks at 20:00 CT (G171). The code is `SIN(RADIANS(15 × (hour − 14)))` next to the comment "peak ~2
--      PM", and a temperature gate would inherit that defect. The 600 kWh default is the twin's own expected
--      DR event: E[reduction] = 50 + 350/2 = 225 kW times E[duration] = 90 + 150 × E[U^0.75] = 175.7 min gives
--      ≈ 660 kWh, rounded down. A production site sizes it from its enrolled commitment.
--   3. Demand is amortised over a 30-day month (dial). The tariff bills a 30-minute average, but the twin's
--      `billing_period_peak_kw` is the maximum instantaneous sample. The plan defends the instantaneous level,
--      which is the conservative reading.
--   4. Wear is $0.02/kWh — ASSUMPTION, a dial. No degradation cost exists anywhere in the schema.
--   5. The solar prior of 0.75 is an ASSUMPTION, replaced by the measured clear-sky index once the sun passes
--      8.63° (sin = 0.15).
--   6. G172 (the planners' efficiency units) is not fixed; see §1(d).
--   7. The AWS MPC bridge (G168) is untouched. This is an in-database, LP-shaped heuristic re-solved every tick,
--      not an optimiser.
--   8. The agent's board does not show the plan yet. The plan logs a scalar summary on every BESS command
--      (`reason->'day_plan'`) and can be read in full with `SELECT public.ottoq_bess_day_plan(run, depot,
--      clock)`.
--
-- ══ §5 PRE-FLIGHT, CHANGE, VERIFICATION ══════════════════════════════════════

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0435 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0435 P0: a determinism pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0435 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: md5 guards (the two changed functions, and the three the plan leans on for meaning) ──
DO $$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN SELECT n.nspname, p.proname, md5(p.prosrc) AS m FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE (n.nspname, p.proname) IN (('public','ottoq_energy_orchestrate'), ('public','ottoq_forecast_net_load'),
                                             ('twin','ottoq_sim_current_tariff'), ('twin','ottoq_sim_solar_elevation_deg'),
                                             ('public','ottoq_policy_get'))
  LOOP
    v_n := v_n + 1;
    IF (r.proname = 'ottoq_energy_orchestrate'      AND r.m <> '3d41b1f1c5662f6839978c1c53e50cef')
    OR (r.proname = 'ottoq_forecast_net_load'       AND r.m <> '10d0740ba9dd2ca048207e62fad78d81')
    OR (r.proname = 'ottoq_sim_current_tariff'      AND r.m <> '8f93e635552b6be131f7e54e8eb1f54b')
    OR (r.proname = 'ottoq_sim_solar_elevation_deg' AND r.m <> '407b7efa5dda3970bda5805456198cc6')
    OR (r.proname = 'ottoq_policy_get'              AND r.m <> '5129f0fa4c090298616b32a952abf12d') THEN
      RAISE EXCEPTION '0435 P1: %.% prosrc md5 is % -- it changed since this file read it', r.nspname, r.proname, r.m;
    END IF;
  END LOOP;
  IF v_n <> 5 THEN RAISE EXCEPTION '0435 P1: expected 5 functions (one overload each), found %', v_n; END IF;
  IF to_regprocedure('public.ottoq_bess_day_plan(uuid,uuid,timestamptz,numeric)') IS NOT NULL
  OR to_regprocedure('public.ottoq_forecast_ev_known_kw(uuid,uuid,timestamptz,integer,numeric,numeric)') IS NOT NULL THEN
    RAISE EXCEPTION '0435 P1: a 0435 function already exists -- this file has been applied, or half-applied';
  END IF;
END $$;

-- ── P2: every orchestrator anchor occurs exactly once ──
DO $$
DECLARE v_src text; v_n int; v_a text; v_i int := 0;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_energy_orchestrate';
  FOREACH v_a IN ARRAY ARRAY[
    E'  v_reserve_shave boolean := false;\n',
    E'  IF ottoq_policy_get(p_sim_run_id, ''energy_reserve_shave'', 0) >= 0.5 THEN\n    v_demand_target := COALESCE(ottoq_bess_reserve_target(p_sim_run_id, p_depot_id, p_sim_clock, 16, 30), v_demand_target);\n    v_reserve_shave := true;\n  END IF;\n',
    E'    v_mode := ''mpc_follow'';\n  ELSIF v_net_load > v_demand_target AND v_soc > v_reserve_floor + 3 THEN\n',
    E'  v_charge_cap := GREATEST(50, v_demand_target - v_base_load + v_solar + v_bess_dispatch);\n',
    E'''mpc_setpoint_kw'', CASE WHEN v_mpc_follow THEN round(v_mpc_setpoint,1) END, ''mpc_step'', v_step));\n'
  ] LOOP
    v_i := v_i + 1;
    v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
    IF v_n <> 1 THEN RAISE EXCEPTION '0435 P2: orchestrator anchor % matched % times', v_i, v_n; END IF;
  END LOOP;
  -- the DR clamp runs AFTER the FR-1b block, so the plan's level is DR-clamped on the same line as before
  IF position('IF v_dr_active THEN v_demand_target := LEAST(v_demand_target, v_dr_cap); END IF;' IN v_src)
     < position('-- FR-1b: causal reserve-aware water-fill target' IN v_src) THEN
    RAISE EXCEPTION '0435 P2: the DR clamp no longer follows the FR-1b block';
  END IF;
END $$;

-- ── P3: premises ──
DO $$
DECLARE v_n int; v_src text; v_rt numeric;
BEGIN
  -- (a) no certification run can reach plan mode
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key = 'energy_reserve_shave' AND scope_type IN ('depot','global') AND param_value >= 0.5;
  IF v_n <> 0 THEN RAISE EXCEPTION '0435 P3: % depot/global row(s) turn energy_reserve_shave on -- cert runs would enter plan mode', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params pp JOIN public.ottoq_sim_runs r ON r.sim_run_id = pp.scope_id
   WHERE pp.scope_type = 'run' AND pp.param_key = 'energy_reserve_shave' AND pp.param_value >= 0.5 AND r.run_by = 'cert_harness';
  IF v_n <> 0 THEN RAISE EXCEPTION '0435 P3: % cert_harness run(s) carry energy_reserve_shave on', v_n; END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agentic_arm';
  IF v_src IS NULL OR position('cert_harness' IN v_src) = 0 OR position('42501' IN v_src) = 0 THEN
    RAISE EXCEPTION '0435 P3: ottoq_agentic_arm no longer refuses cert_harness runs';
  END IF;
  -- (b) the twin depot's battery stores round-trip as a FRACTION (§1(d)); the plan reads either form
  SELECT roundtrip_efficiency_pct INTO v_rt FROM public.ottoq_bess_units
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' ORDER BY bess_id LIMIT 1;
  IF v_rt IS NULL OR v_rt > 1 THEN
    RAISE NOTICE '0435 P3: twin depot round-trip reads % -- §1(d) described a fraction; the plan handles both', v_rt;
  END IF;
  -- (c) the demand rate the plan prices is where the header says it is
  SELECT count(*) INTO v_n FROM public.ottoq_depot_tariffs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND active AND season = 'summer' AND demand_first_block_usd_kw = 21.40;
  IF v_n <> 1 THEN RAISE EXCEPTION '0435 P3: expected one active summer NES GSA-3 row at $21.40/kW, found %', v_n; END IF;
END $$;

-- ── P4: what ottoq_forecast_net_load returns BEFORE the rewrite, for V1 ──
CREATE TEMP TABLE _0435_fnl ON COMMIT DROP AS
WITH r AS (
  SELECT sim_run_id, depot_id, sim_clock_current FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND sim_clock_current IS NOT NULL
   ORDER BY started_at DESC LIMIT 1)
SELECT r.sim_run_id, r.depot_id, c.clk, c.h,
       public.ottoq_forecast_net_load(r.sim_run_id, r.depot_id, c.clk, c.h, 30, 30) AS out
  FROM r CROSS JOIN LATERAL (VALUES (r.sim_clock_current, 16), (r.sim_clock_current - interval '3 hours', 16),
                                    (r.sim_clock_current - interval '6 hours', 48)) AS c(clk, h);

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0435_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname, p.proname) IN (('public','ottoq_energy_orchestrate'), ('public','ottoq_forecast_net_load'));

-- ── DIALS ──
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('bess_day_plan_enabled',
        '0435: when >= 1 (and energy_reserve_shave is on) the battery follows public.ottoq_bess_day_plan -- a '
        'day-length, price- and demand-aware plan re-solved every tick; 0 restores the 8-hour water-fill '
        '(ottoq_bess_reserve_target), kept as a named policy.',
        1, 0, 1, 'public.ottoq_energy_orchestrate (FR-1b)', false),
       ('bess_plan_dr_reserve_kwh',
        '0435: AC kWh the day plan holds for a demand-response call on summer-tariff days, in full until the DR '
        'window opens and released linearly to its close. Default = the twin DR program''s expected event '
        '(225 kW x 2.9 h), rounded down. 0 disables.',
        600, 0, 3000, 'public.ottoq_bess_day_plan', false),
       ('bess_plan_dr_window_start_hour', '0435: local hour the DR reserve starts releasing.', 14, 0, 23, 'public.ottoq_bess_day_plan', false),
       ('bess_plan_dr_window_end_hour',   '0435: local hour the DR reserve is fully released.', 20, 1, 24, 'public.ottoq_bess_day_plan', false),
       ('bess_plan_demand_amortization_days',
        '0435: days the monthly demand charge ($/kW, NCP_30min) is spread over when the plan values a kW of peak '
        'removed today. 30 = a steady-state month.', 30, 1, 31, 'public.ottoq_bess_day_plan', false),
       ('bess_plan_degradation_usd_kwh',
        '0435: wear cost charged against every kWh the plan discharges. ASSUMPTION: no degradation cost exists '
        'in the schema.', 0.02, 0, 0.2, 'public.ottoq_bess_day_plan', false)
ON CONFLICT (param_key) DO NOTHING;

-- ── (A) THE KNOWN-EV FORECAST, lifted verbatim, and its parent rewritten to call it ──
CREATE OR REPLACE FUNCTION public.ottoq_forecast_ev_known_kw(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone, p_horizon_ticks integer DEFAULT 16, p_tick_min numeric DEFAULT 30, p_arrival_soc numeric DEFAULT 30)
 RETURNS numeric[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0435: the two charging loops of ottoq_forecast_net_load, lifted out VERBATIM so the day plan can read the
   known EV load on its own (the parent folds it into a net load floored at base, which hides EV under solar).
   The parent now calls this; 0435 V1 proves the parent's output unchanged. p_depot_id is unused, exactly as it
   was in the parent: both loops are run-scoped. */
DECLARE
  v_load numeric[]; h int; r RECORD;
  v_rate numeric; v_kwh numeric; v_dur_min numeric; v_step_min numeric;
BEGIN
  v_load := array_fill(0::numeric, ARRAY[p_horizon_ticks]);

  -- (1) currently-active charging sessions: hold their rate until they finish
  FOR r IN
    SELECT ottoq_sim_compute_charge_rate(
             p_soc_pct := v.current_soc, p_battery_temp_c := COALESCE(s.ambient_temp_c,22)+5,
             p_ambient_temp_c := COALESCE(s.ambient_temp_c,22), p_charger_max_kw := ch.max_kw,
             p_vehicle_max_kw := v.inlet_max_kw, p_battery_capacity_kwh := v.battery_capacity_kwh,
             p_battery_soh_pct := 95, p_noise_seed := 1, p_noise_salt := s.vehicle_id::text) AS rate,
           GREATEST(0,(COALESCE(v.target_soc, public.ottoq_default_target_soc())-v.current_soc)/100.0*COALESCE(v.battery_capacity_kwh,75)) AS kwh
    FROM ocpp_sessions s JOIN stalls st ON st.id=s.stall_id
    JOIN ottoq_ocpp_chargers ch ON ch.charger_id=st.ocpp_charger_id
    JOIN vehicles v ON v.id=s.vehicle_id
    WHERE s.status='active' AND s.sim_run_id=p_sim_run_id
    ORDER BY st.id   /* 0054: stall identity, never per-run session UUIDs */
  LOOP
    v_rate := GREATEST(r.rate, 1); v_dur_min := r.kwh / v_rate * 60.0;
    FOR h IN 1..p_horizon_ticks LOOP
      IF (h-1)*p_tick_min < v_dur_min THEN v_load[h] := v_load[h] + v_rate; END IF;
    END LOOP;
  END LOOP;

  -- (2) scheduled future arrivals: charge from their ETA through their charge window
  --     0312: the arrival SoC is the vehicle's OWN measured SoC, which the twin
  --     updates continuously while deployed. p_arrival_soc survives only as the
  --     fallback for a vehicle whose SoC is genuinely unknown. Before 0312 this
  --     loop used p_arrival_soc unconditionally, i.e. the literal 30 for every
  --     vehicle, which was wrong for 99.54% of measured arrivals (db/checks/0238).
  FOR r IN
    SELECT d.scheduled_return_at AS eta, v.target_soc, v.battery_capacity_kwh, v.inlet_max_kw,
           v.current_soc
    FROM ottoq_vehicle_dispatches d JOIN vehicles v ON v.id=d.vehicle_id
    WHERE d.sim_run_id=p_sim_run_id AND d.status IN ('active','returning')
      AND d.scheduled_return_at IS NOT NULL
      AND d.scheduled_return_at <= p_sim_clock + (p_horizon_ticks*p_tick_min)*interval '1 min'
      AND d.scheduled_return_at >  p_sim_clock - interval '30 min'
      ORDER BY v.id   /* 0054: run-stable cursor order */
  LOOP
    v_rate := LEAST(COALESCE(r.inlet_max_kw,150), 250) * 0.60;  -- avg DCFC session power
    v_kwh  := GREATEST(0,(COALESCE(r.target_soc, public.ottoq_default_target_soc())
                          - COALESCE(r.current_soc, p_arrival_soc))/100.0*COALESCE(r.battery_capacity_kwh,75));
    v_dur_min := v_kwh / GREATEST(v_rate,1) * 60.0;
    FOR h IN 1..p_horizon_ticks LOOP
      v_step_min := EXTRACT(EPOCH FROM (p_sim_clock + ((h-1)*p_tick_min)*interval '1 min' - r.eta))/60.0;
      IF v_step_min >= -p_tick_min AND v_step_min < v_dur_min THEN v_load[h] := v_load[h] + v_rate; END IF;
    END LOOP;
  END LOOP;

  RETURN v_load;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_forecast_net_load(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone, p_horizon_ticks integer DEFAULT 16, p_tick_min numeric DEFAULT 30, p_arrival_soc numeric DEFAULT 30)
 RETURNS numeric[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_base numeric; v_solar numeric; v_load numeric[]; h int;
BEGIN
  SELECT COALESCE(building_load_kw,0)+COALESCE(lighting_load_kw,0), COALESCE(solar_generation_kw,0)
    INTO v_base, v_solar FROM site_energy_snapshots
   WHERE depot_id=p_depot_id AND sim_run_id=p_sim_run_id ORDER BY timestamp DESC LIMIT 1;
  v_base := COALESCE(v_base, 50); v_solar := COALESCE(v_solar, 0);

  -- (1) + (2): the known charging load; 0435 lifted both loops verbatim into ottoq_forecast_ev_known_kw
  v_load := public.ottoq_forecast_ev_known_kw(p_sim_run_id, p_depot_id, p_sim_clock, p_horizon_ticks, p_tick_min, p_arrival_soc);

  -- net load = base + concurrent charging - solar (floored at base)
  FOR h IN 1..p_horizon_ticks LOOP
    v_load[h] := GREATEST(v_base, v_base + v_load[h] - v_solar);
  END LOOP;
  RETURN v_load;
END;
$function$;

-- ── (B) ONE CANDIDATE LEVEL, EVALUATED ──
CREATE OR REPLACE FUNCTION public.ottoq_bess_plan_eval(
    p_level numeric, p_net numeric[], p_price numeric[], p_reserve numeric[],
    p_e_avail numeric, p_pd numeric, p_dt numeric, p_d_day numeric, p_ratchet numeric,
    p_c_rep numeric, p_c_deg numeric,
    OUT feasible boolean, OUT value_usd numeric, OUT used_kwh numeric,
    OUT shave_now_kw numeric, OUT arb_now_kw numeric, OUT spare_price numeric, OUT discharge_kw numeric[])
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
/* 0435: pure arithmetic, no table reads. Given a grid level to defend and a forecast (kW per step, p_dt hours
   each), returns whether the battery can hold it -- power, and cumulative energy net of a per-step reserve --
   then spends what is left on the steps where a kWh is worth most, and scores the whole thing:
     value = p_d_day x (peak removed above the already-billed peak p_ratchet)
           + sum over steps of (price - p_c_rep - p_c_deg) x kWh discharged.
   Discharge never exceeds the step's net load, so the plan never exports. Price ties go to the LATER step,
   which keeps energy in the battery longer. spare_price is the highest price at which one more kWh would
   have been used (a step with power headroom that ran out of energy): what the recharge decision prices
   against. 0435 V2 pins this function to three hand-solved cases. */
DECLARE
  n int := COALESCE(array_length(p_net, 1), 0);
  k int; j int;
  v_shave numeric[]; v_arb numeric[]; v_slack numeric[]; v_order int[];
  v_cum numeric := 0; v_lmax numeric := 0; v_hr numeric; v_lim numeric; v_x numeric; v_val numeric := 0;
BEGIN
  feasible := false; used_kwh := 0; shave_now_kw := 0; arb_now_kw := 0;
  IF n = 0 THEN RETURN; END IF;
  v_shave := array_fill(0::numeric, ARRAY[n]); v_arb := array_fill(0::numeric, ARRAY[n]);
  v_slack := array_fill(0::numeric, ARRAY[n]);

  FOR k IN 1..n LOOP
    v_lmax := GREATEST(v_lmax, p_net[k]);
    IF p_net[k] - p_level > p_pd + 1e-6 THEN RETURN; END IF;      -- the battery's power cannot hold this level
    v_shave[k] := GREATEST(0, p_net[k] - p_level);
    v_cum := v_cum + v_shave[k] * p_dt;
    v_slack[k] := p_e_avail - p_reserve[k] - v_cum;
    IF v_slack[k] < -1e-6 THEN RETURN; END IF;                    -- ...or its energy, net of the reserve
  END LOOP;

  SELECT array_agg(i ORDER BY p_price[i] DESC, i DESC) INTO v_order FROM generate_subscripts(p_net, 1) AS i;
  FOREACH j IN ARRAY v_order LOOP
    EXIT WHEN p_price[j] - p_c_rep - p_c_deg <= 0;                -- sorted: nothing further is worth a cycle
    v_hr := LEAST(p_pd - v_shave[j], p_net[j] - v_shave[j]);
    CONTINUE WHEN v_hr <= 1e-6;
    v_lim := v_slack[j];
    FOR k IN j..n LOOP v_lim := LEAST(v_lim, v_slack[k]); END LOOP;
    IF v_lim <= 1e-6 THEN
      spare_price := GREATEST(COALESCE(spare_price, 0), p_price[j]);
      CONTINUE;
    END IF;
    v_x := LEAST(v_hr * p_dt, v_lim);
    v_arb[j] := v_x / p_dt;
    FOR k IN j..n LOOP v_slack[k] := v_slack[k] - v_x; END LOOP;
    IF v_x < v_hr * p_dt - 1e-6 THEN spare_price := GREATEST(COALESCE(spare_price, 0), p_price[j]); END IF;
  END LOOP;

  FOR k IN 1..n LOOP
    v_val := v_val + (p_price[k] - p_c_rep - p_c_deg) * (v_shave[k] + v_arb[k]) * p_dt;
    used_kwh := used_kwh + (v_shave[k] + v_arb[k]) * p_dt;
  END LOOP;
  value_usd := v_val + p_d_day * (GREATEST(p_ratchet, v_lmax) - GREATEST(p_ratchet, LEAST(p_level, v_lmax)));
  feasible := true; shave_now_kw := v_shave[1]; arb_now_kw := v_arb[1];
  SELECT array_agg(v_shave[i] + v_arb[i] ORDER BY i) INTO discharge_kw FROM generate_subscripts(v_shave, 1) AS i;
END;
$function$;

-- ── (C) THE DAY PLAN ──
CREATE OR REPLACE FUNCTION public.ottoq_bess_day_plan(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone, p_net_load_now_kw numeric DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0435: the battery's plan for the rest of the local day, re-solved every tick (a rolling horizon). Steps are
   30 minutes because NES GSA-3 bills demand on the highest 30-consecutive-minute kW of the month
   (ottoq_depot_tariffs.demand_basis = NCP_30min). Every input is this run's own rows or static site data, so
   two arms of a pair see the same plan. Design, assumptions and limits: db/migrations/0435 header. */
DECLARE
  c_tz CONSTANT text := 'America/Chicago';
  c_dt CONSTANT numeric := 0.5;
  v_cap numeric; v_soc numeric; v_floor numeric; v_ceil numeric; v_pd numeric; v_pc numeric; v_rt numeric; v_eta numeric;
  v_rt_raw numeric; v_res_floor numeric; v_e_avail numeric; v_e_room numeric;
  v_local timestamp; v_day_end timestamptz; v_n int; k int; i int;
  v_t timestamptz; v_hf numeric; v_hr int; v_tmp numeric;
  v_price numeric[]; v_base numeric[]; v_solar numeric[]; v_ev numeric[]; v_net numeric[]; v_res numeric[]; v_known numeric[];
  v_base_now numeric; v_solar_now numeric; v_ev_now numeric; v_ev_persist numeric; v_ratchet numeric;
  v_prof numeric[]; v_prof_now numeric; v_anom numeric;
  v_lat numeric; v_lng numeric; v_ac numeric; v_soil numeric; v_kcs numeric; v_k_src text;
  v_last_day timestamptz; v_sum_solar numeric; v_sum_cs numeric;
  v_month int; v_tou_season text; v_dmd_season text; v_d_rate numeric; v_amort numeric; v_d_day numeric;
  v_min_rate numeric; v_c_rep numeric; v_c_deg numeric;
  v_dr_kwh numeric; v_dr_s numeric; v_dr_e numeric; v_summer boolean;
  v_lmax numeric; v_floor_m numeric; v_lo numeric; v_hi numeric; v_mid numeric; v_a numeric; v_b numeric;
  v_m1 numeric; v_m2 numeric; v_m_min numeric; v_level numeric; v_level_bound boolean := false;
  v_e record; v_e2 record; v_best record; v_mode text;
  v_charge numeric := 0; v_head numeric; v_surplus numeric; v_why_charge text := NULL;
  v_t0 timestamptz := clock_timestamp();
BEGIN
  -- the battery
  SELECT capacity_kwh, current_soc_pct, COALESCE(soc_min_floor_pct,10), COALESCE(soc_max_ceiling_pct,90),
         COALESCE(max_discharge_kw,500), COALESCE(max_charge_kw,500), roundtrip_efficiency_pct
    INTO v_cap, v_soc, v_floor, v_ceil, v_pd, v_pc, v_rt_raw
    FROM ottoq_bess_units WHERE depot_id = p_depot_id ORDER BY bess_id LIMIT 1;
  IF v_cap IS NULL OR v_soc IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_bess'); END IF;
  -- the column holds a FRACTION on the twin (0.96; the plant reads it so) and is named as a percent (G172)
  v_rt := LEAST(1.0, GREATEST(0.5, CASE WHEN v_rt_raw IS NULL THEN 0.96 WHEN v_rt_raw <= 1 THEN v_rt_raw ELSE v_rt_raw / 100.0 END));
  v_eta := sqrt(v_rt);
  -- the orchestrator's own discharge gate: floor + 20 x forecast uncertainty + 3 points
  v_res_floor := v_floor + COALESCE(ottoq_forecast_uncertainty(p_sim_run_id, p_depot_id, p_sim_clock), 0) * 20 + 3;
  v_e_avail := GREATEST(0, (v_soc - v_res_floor) / 100.0 * v_cap) * v_eta;          -- deliverable AC kWh
  v_e_room  := GREATEST(0, (v_ceil - 3 - v_soc) / 100.0 * v_cap) / v_eta;           -- AC kWh it can still take

  -- the horizon: to local midnight, never under 8 h, never over 24 h
  v_local := p_sim_clock AT TIME ZONE c_tz;
  v_day_end := (date_trunc('day', v_local) + interval '1 day') AT TIME ZONE c_tz;
  v_n := LEAST(48, GREATEST(16, ceil(EXTRACT(EPOCH FROM (v_day_end - p_sim_clock)) / 1800.0)::int));

  -- what the site is doing now (this run's rows only)
  SELECT COALESCE(e.building_load_kw,0) + COALESCE(e.lighting_load_kw,0), COALESCE(e.solar_generation_kw,0),
         COALESCE(e.total_ev_charging_kw,0), COALESCE(e.billing_period_peak_kw,0)
    INTO v_base_now, v_solar_now, v_ev_now, v_ratchet
    FROM site_energy_snapshots e
   WHERE e.depot_id = p_depot_id AND e.sim_run_id = p_sim_run_id AND e.timestamp <= p_sim_clock
   ORDER BY e.timestamp DESC LIMIT 1;
  IF NOT FOUND THEN v_base_now := 50; v_solar_now := 0; v_ev_now := 0; v_ratchet := 0; END IF;
  SELECT avg(e.total_ev_charging_kw) INTO v_ev_persist FROM site_energy_snapshots e
   WHERE e.depot_id = p_depot_id AND e.sim_run_id = p_sim_run_id
     AND e.timestamp > p_sim_clock - interval '60 minutes' AND e.timestamp <= p_sim_clock;
  v_ev_persist := COALESCE(v_ev_persist, v_ev_now);

  -- building load: the depot's own hourly median outside any run, the current anomaly decaying over 4 h
  SELECT array_agg(x.p50 ORDER BY g.h) INTO v_prof
    FROM generate_series(0, 23) AS g(h)
    LEFT JOIN (SELECT EXTRACT(HOUR FROM e.timestamp AT TIME ZONE c_tz)::int AS h,
                      percentile_cont(0.5) WITHIN GROUP (ORDER BY COALESCE(e.building_load_kw,0) + COALESCE(e.lighting_load_kw,0))::numeric AS p50
                 FROM site_energy_snapshots e WHERE e.depot_id = p_depot_id AND e.sim_run_id IS NULL GROUP BY 1) x ON x.h = g.h;
  v_prof_now := COALESCE(v_prof[EXTRACT(HOUR FROM v_local)::int + 1], v_base_now);
  v_anom := v_base_now - v_prof_now;

  -- solar: clear-sky index persistence (observed kW over sin(elevation)); a nameplate prior before first light
  SELECT d.origin_lat, d.origin_lng INTO v_lat, v_lng FROM depots d WHERE d.id = p_depot_id;
  v_lat := COALESCE(v_lat, 36.1397); v_lng := COALESCE(v_lng, -86.7728);
  SELECT COALESCE(sum(c.nameplate_ac_kw), 0), COALESCE(avg(c.current_soiling), 1) INTO v_ac, v_soil
    FROM ottoq_canopy_state c WHERE c.depot_id = p_depot_id;
  SELECT max(w.sim_clock_at) INTO v_last_day FROM ottoq_weather_snapshots w
   WHERE w.depot_id = p_depot_id AND w.sim_run_id = p_sim_run_id AND w.sim_clock_at <= p_sim_clock
     AND w.solar_elevation_deg >= 8.63;                                                -- sin(8.63 deg) = 0.15
  IF v_last_day IS NOT NULL AND v_last_day > p_sim_clock - interval '3 hours' THEN
    SELECT sum(e.solar_generation_kw), sum(sin(radians(w.solar_elevation_deg))) INTO v_sum_solar, v_sum_cs
      FROM ottoq_weather_snapshots w
      JOIN site_energy_snapshots e ON e.sim_run_id = w.sim_run_id AND e.depot_id = w.depot_id AND e.timestamp = w.sim_clock_at
     WHERE w.depot_id = p_depot_id AND w.sim_run_id = p_sim_run_id AND w.solar_elevation_deg >= 8.63
       AND w.sim_clock_at > v_last_day - interval '60 minutes' AND w.sim_clock_at <= v_last_day;
  END IF;
  IF COALESCE(v_sum_cs, 0) > 0 THEN
    v_kcs := v_sum_solar / v_sum_cs; v_k_src := 'clear_sky_index_last_hour_of_daylight';
  ELSE
    v_kcs := v_ac * v_soil * 0.75; v_k_src := 'prior_nameplate_x_soiling_x_0.75';    -- ASSUMPTION (0435 §4.5)
  END IF;

  -- EV: what is known (sessions, returns) floored at what the depot drew over the last hour
  v_known := public.ottoq_forecast_ev_known_kw(p_sim_run_id, p_depot_id, p_sim_clock, v_n, 30, 30);

  -- money: TOU rate per step (the twin's own lookup, so plan and bill agree), demand rate, replacement, wear
  v_month := EXTRACT(MONTH FROM v_local)::int;
  v_tou_season := CASE WHEN v_month BETWEEN 6 AND 9 THEN 'summer' WHEN v_month IN (12,1,2) THEN 'winter' ELSE 'shoulder' END;
  SELECT t.season, t.demand_first_block_usd_kw INTO v_dmd_season, v_d_rate
    FROM ottoq_depot_tariffs t WHERE t.depot_id = p_depot_id AND t.active AND v_month = ANY(t.season_months)
   ORDER BY t.effective_from DESC, t.tariff_row_id LIMIT 1;
  v_summer := COALESCE(v_dmd_season = 'summer', false);
  v_amort := GREATEST(1, ottoq_policy_get(p_sim_run_id, 'bess_plan_demand_amortization_days', 30));
  v_d_day := COALESCE(v_d_rate, 0) / v_amort;
  SELECT min(w.rate_usd_per_kwh) INTO v_min_rate FROM ottoq_tariff_windows w
   WHERE w.depot_id = p_depot_id AND w.active AND (w.season = 'all' OR w.season = v_tou_season);
  v_c_rep := COALESCE(v_min_rate, 0.05) / v_rt;
  v_c_deg := GREATEST(0, ottoq_policy_get(p_sim_run_id, 'bess_plan_degradation_usd_kwh', 0.02));
  v_dr_kwh := GREATEST(0, ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_reserve_kwh', 600));
  v_dr_s := ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_window_start_hour', 14);
  v_dr_e := ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_window_end_hour', 20);

  v_price := array_fill(0::numeric, ARRAY[v_n]); v_base := v_price; v_solar := v_price; v_ev := v_price;
  v_net := v_price; v_res := v_price;
  FOR k IN 1..v_n LOOP
    v_t := p_sim_clock + ((k - 1) * 30) * interval '1 minute';
    v_hf := EXTRACT(HOUR FROM v_t AT TIME ZONE c_tz) + EXTRACT(MINUTE FROM v_t AT TIME ZONE c_tz) / 60.0;
    v_hr := floor(v_hf)::int;
    SELECT t.out_rate_usd_kwh INTO v_tmp FROM twin.ottoq_sim_current_tariff(p_depot_id, v_t) t;
    v_price[k] := COALESCE(v_tmp, 0.10);
    v_base[k] := GREATEST(0, COALESCE(v_prof[v_hr + 1], v_prof_now) + v_anom * exp(-((k - 1) * c_dt) / 4.0));
    v_solar[k] := LEAST(v_ac, GREATEST(0, v_kcs * GREATEST(0, sin(radians(twin.ottoq_sim_solar_elevation_deg(v_t, v_lat, v_lng))))));
    v_ev[k] := GREATEST(COALESCE(v_known[k], 0), v_ev_persist);
    v_net[k] := GREATEST(0, v_base[k] + v_ev[k] - v_solar[k]);
    v_res[k] := CASE WHEN NOT v_summer OR v_dr_kwh <= 0 OR v_dr_e <= v_dr_s THEN 0
                     WHEN v_hf < v_dr_s THEN v_dr_kwh
                     WHEN v_hf < v_dr_e THEN v_dr_kwh * (v_dr_e - v_hf) / (v_dr_e - v_dr_s)
                     ELSE 0 END;
  END LOOP;
  IF p_net_load_now_kw IS NOT NULL THEN v_net[1] := GREATEST(0, p_net_load_now_kw); END IF;

  -- solve: the lowest level the battery can hold, then the value-maximising level above it
  SELECT max(x) INTO v_lmax FROM unnest(v_net) AS x;
  v_floor_m := GREATEST(0, v_lmax - v_pd);
  SELECT * INTO v_best FROM public.ottoq_bess_plan_eval(v_lmax, v_net, v_price, v_res, v_e_avail, v_pd, c_dt, v_d_day, v_ratchet, v_c_rep, v_c_deg);
  IF NOT v_best.feasible THEN
    -- the battery already sits under the DR reserve: hold everything for the call, and refill
    v_level := GREATEST(v_lmax, v_ratchet); v_mode := 'reserve_protected';
    SELECT * INTO v_best FROM public.ottoq_bess_plan_eval(v_lmax, v_net, v_price, array_fill(0::numeric, ARRAY[v_n]), 0, v_pd, c_dt, v_d_day, v_ratchet, v_c_rep, v_c_deg);
  ELSE
    SELECT * INTO v_e FROM public.ottoq_bess_plan_eval(v_floor_m, v_net, v_price, v_res, v_e_avail, v_pd, c_dt, v_d_day, v_ratchet, v_c_rep, v_c_deg);
    IF v_e.feasible THEN
      v_m_min := v_floor_m;
    ELSE
      v_lo := v_floor_m; v_hi := v_lmax;
      FOR i IN 1..18 LOOP                                     -- feasibility is monotone in the level
        v_mid := (v_lo + v_hi) / 2.0;
        SELECT * INTO v_e FROM public.ottoq_bess_plan_eval(v_mid, v_net, v_price, v_res, v_e_avail, v_pd, c_dt, v_d_day, v_ratchet, v_c_rep, v_c_deg);
        IF v_e.feasible THEN v_hi := v_mid; ELSE v_lo := v_mid; END IF;
      END LOOP;
      v_m_min := v_hi;
    END IF;
    v_a := v_m_min; v_b := v_lmax;
    FOR i IN 1..18 LOOP                                       -- an LP's value is concave in its right-hand side
      v_m1 := v_a + (v_b - v_a) / 3.0; v_m2 := v_b - (v_b - v_a) / 3.0;
      SELECT * INTO v_e  FROM public.ottoq_bess_plan_eval(v_m1, v_net, v_price, v_res, v_e_avail, v_pd, c_dt, v_d_day, v_ratchet, v_c_rep, v_c_deg);
      SELECT * INTO v_e2 FROM public.ottoq_bess_plan_eval(v_m2, v_net, v_price, v_res, v_e_avail, v_pd, c_dt, v_d_day, v_ratchet, v_c_rep, v_c_deg);
      IF COALESCE(v_e.value_usd, -1e12) <= COALESCE(v_e2.value_usd, -1e12) THEN v_a := v_m1; ELSE v_b := v_m2; END IF;
    END LOOP;
    v_level := v_b;
    SELECT * INTO v_best FROM public.ottoq_bess_plan_eval(v_level, v_net, v_price, v_res, v_e_avail, v_pd, c_dt, v_d_day, v_ratchet, v_c_rep, v_c_deg);
    v_level_bound := (v_level - v_m_min) < 1 AND v_m_min > v_floor_m + 1;
    -- a level under the already-billed peak buys no demand charge: defend the ratchet when that is no worse
    IF v_ratchet > v_level THEN
      SELECT * INTO v_e FROM public.ottoq_bess_plan_eval(LEAST(v_ratchet, v_lmax), v_net, v_price, v_res, v_e_avail, v_pd, c_dt, v_d_day, v_ratchet, v_c_rep, v_c_deg);
      IF v_e.feasible AND v_e.value_usd >= v_best.value_usd - 0.01 THEN
        v_best := v_e; v_level := v_ratchet; v_level_bound := false;
      END IF;
    END IF;
    v_mode := CASE WHEN v_best.shave_now_kw > 0 THEN 'shave' WHEN v_best.arb_now_kw > 0 THEN 'arbitrage' ELSE 'hold' END;
  END IF;

  -- recharge: only when nothing is discharged now, under the level less a margin, and with half the headroom
  IF v_best.shave_now_kw + v_best.arb_now_kw <= 0 AND v_e_room > 1 THEN
    v_head := GREATEST(0, v_level - v_net[1] - GREATEST(100, 0.10 * v_level));
    IF v_mode = 'reserve_protected' THEN
      v_why_charge := 'restore_dr_reserve';
    ELSIF v_price[1] <= COALESCE(v_min_rate, 0) + 1e-9 THEN
      v_why_charge := 'cheapest_window';
    ELSIF v_best.spare_price IS NOT NULL AND v_price[1] / v_rt + v_c_deg < v_best.spare_price THEN
      v_why_charge := 'worth_more_later';
    ELSIF v_level_bound THEN
      v_why_charge := 'peak_is_energy_bound';
    END IF;
    IF v_why_charge IS NOT NULL THEN v_charge := LEAST(v_pc, 0.5 * v_head, v_e_room / c_dt); END IF;
    v_surplus := GREATEST(0, v_solar_now - v_base_now - v_ev_now);
    IF v_surplus > 5 AND v_surplus > v_charge THEN
      v_charge := LEAST(v_pc, v_surplus, v_e_room / c_dt); v_why_charge := 'solar_surplus';
    END IF;
    IF v_charge > 0 THEN v_mode := 'charge'; ELSE v_why_charge := NULL; END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'plan', '0435', 'mode', v_mode,
    'level_kw', round(v_level, 1), 'shave_now_kw', round(v_best.shave_now_kw, 1), 'arb_now_kw', round(v_best.arb_now_kw, 1),
    'charge_now_kw', round(v_charge, 1), 'charge_reason', v_why_charge,
    'e_avail_kwh', round(v_e_avail, 1), 'e_room_kwh', round(v_e_room, 1), 'reserve_now_kwh', round(v_res[1], 1),
    'ratchet_kw', round(v_ratchet, 1), 'forecast_peak_kw', round(v_lmax, 1), 'level_energy_bound', v_level_bound,
    'plan_value_usd', round(v_best.value_usd, 2), 'plan_discharge_kwh', round(v_best.used_kwh, 1),
    'spare_price', v_best.spare_price, 'price_now', v_price[1], 'roundtrip', v_rt,
    'horizon_steps', v_n, 'step_min', 30,
    'demand_usd_per_kw_day', round(v_d_day, 4), 'replacement_usd_kwh', round(v_c_rep, 4), 'degradation_usd_kwh', v_c_deg,
    'solar_k_kw', round(v_kcs, 1), 'solar_k_source', v_k_src, 'ev_persist_kw', round(v_ev_persist, 1),
    'solve_ms', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) * 1000),
    'forecast', jsonb_build_object(
       'net_kw',   (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_net)   WITH ORDINALITY AS u(x, o)),
       'ev_kw',    (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_ev)    WITH ORDINALITY AS u(x, o)),
       'solar_kw', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_solar) WITH ORDINALITY AS u(x, o)),
       'base_kw',  (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_base)  WITH ORDINALITY AS u(x, o)),
       'price',    to_jsonb(v_price),
       'reserve_kwh', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_res) WITH ORDINALITY AS u(x, o))),
    'discharge_plan_kw', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_best.discharge_kw) WITH ORDINALITY AS u(x, o)));
END;
$function$;

REVOKE ALL ON FUNCTION public.ottoq_forecast_ev_known_kw(uuid, uuid, timestamptz, integer, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_forecast_ev_known_kw(uuid, uuid, timestamptz, integer, numeric, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_bess_plan_eval(numeric, numeric[], numeric[], numeric[], numeric, numeric, numeric, numeric, numeric, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_bess_plan_eval(numeric, numeric[], numeric[], numeric[], numeric, numeric, numeric, numeric, numeric, numeric, numeric) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_bess_day_plan(uuid, uuid, timestamptz, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_bess_day_plan(uuid, uuid, timestamptz, numeric) TO authenticated, service_role;

-- ── (D) THE ORCHESTRATOR FOLLOWS THE PLAN (five splices, each anchor asserted unique in P2) ──
DO $splice$
DECLARE v_def text; v_new text; v_a text; v_b text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_energy_orchestrate';
  v_new := v_def;

  -- 1. declare the plan
  v_a := E'  v_reserve_shave boolean := false;\n';
  v_b := E'  v_reserve_shave boolean := false;\n  v_day_plan jsonb := NULL;   /* 0435 */\n';
  v_new := replace(v_new, v_a, v_b);

  -- 2. the plan is the reserve-shave switch's implementation; the water-fill remains the named fallback
  v_a := E'  IF ottoq_policy_get(p_sim_run_id, ''energy_reserve_shave'', 0) >= 0.5 THEN\n    v_demand_target := COALESCE(ottoq_bess_reserve_target(p_sim_run_id, p_depot_id, p_sim_clock, 16, 30), v_demand_target);\n    v_reserve_shave := true;\n  END IF;\n';
  v_b := E'  IF ottoq_policy_get(p_sim_run_id, ''energy_reserve_shave'', 0) >= 0.5 THEN\n'
      || E'    /* 0435: the day plan replaces the 8-hour water-fill as this switch''s implementation; a failed plan is\n'
      || E'       logged and falls back to the water-fill, which bess_day_plan_enabled = 0 selects outright. */\n'
      || E'    IF ottoq_policy_get(p_sim_run_id, ''bess_day_plan_enabled'', 1) >= 0.5 THEN\n'
      || E'      BEGIN\n'
      || E'        v_day_plan := public.ottoq_bess_day_plan(p_sim_run_id, p_depot_id, p_sim_clock, v_net_load);\n'
      || E'      EXCEPTION WHEN OTHERS THEN\n'
      || E'        v_day_plan := jsonb_build_object(''ok'', false, ''error'', SQLERRM);\n'
      || E'      END;\n'
      || E'    END IF;\n'
      || E'    IF COALESCE((v_day_plan->>''ok'')::boolean, false) THEN\n'
      || E'      v_demand_target := (v_day_plan->>''level_kw'')::numeric;\n'
      || E'    ELSE\n'
      || E'      v_demand_target := COALESCE(ottoq_bess_reserve_target(p_sim_run_id, p_depot_id, p_sim_clock, 16, 30), v_demand_target);\n'
      || E'    END IF;\n'
      || E'    v_reserve_shave := true;\n'
      || E'  END IF;\n';
  v_new := replace(v_new, v_a, v_b);

  -- 3. the plan's branch: defend the (DR-clamped) level in real time; arbitrage and recharge per the plan
  v_a := E'    v_mode := ''mpc_follow'';\n  ELSIF v_net_load > v_demand_target AND v_soc > v_reserve_floor + 3 THEN\n';
  v_b := E'    v_mode := ''mpc_follow'';\n'
      || E'  ELSIF COALESCE((v_day_plan->>''ok'')::boolean, false) THEN\n'
      || E'    /* 0435: the level (DR-clamped above) is defended against the ACTUAL net load; arbitrage and recharge\n'
      || E'       are the plan''s, and a live DR call overrides both, reserve included. */\n'
      || E'    IF v_net_load > v_demand_target AND v_soc > v_reserve_floor + 3 THEN\n'
      || E'      v_bess_dispatch := LEAST(v_maxdis, v_net_load - v_demand_target\n'
      || E'                         + CASE WHEN v_dr_active THEN 0 ELSE COALESCE((v_day_plan->>''arb_now_kw'')::numeric, 0) END);\n'
      || E'      v_mode := CASE WHEN v_dr_active THEN ''discharge_dr'' ELSE ''plan_defend_level'' END;\n'
      || E'    ELSIF NOT v_dr_active AND COALESCE((v_day_plan->>''arb_now_kw'')::numeric, 0) > 0 AND v_soc > v_reserve_floor + 3 THEN\n'
      || E'      v_bess_dispatch := LEAST(v_maxdis, (v_day_plan->>''arb_now_kw'')::numeric, GREATEST(0, v_net_load));\n'
      || E'      v_mode := ''plan_arbitrage'';\n'
      || E'    ELSIF NOT v_dr_active AND COALESCE((v_day_plan->>''charge_now_kw'')::numeric, 0) > 0 AND v_soc < v_ceil - 3 THEN\n'
      || E'      v_bess_dispatch := -LEAST(v_maxchg, (v_day_plan->>''charge_now_kw'')::numeric, GREATEST(0, v_demand_target - v_net_load));\n'
      || E'      v_mode := ''plan_charge'';\n'
      || E'    ELSE\n'
      || E'      v_bess_dispatch := 0; v_mode := CASE WHEN v_dr_active THEN ''plan_hold_dr'' ELSE ''plan_hold'' END;\n'
      || E'    END IF;\n'
      || E'  ELSIF v_net_load > v_demand_target AND v_soc > v_reserve_floor + 3 THEN\n';
  v_new := replace(v_new, v_a, v_b);

  -- 4. in plan mode the fleet's headroom does not pay for the battery's charging
  v_a := E'  v_charge_cap := GREATEST(50, v_demand_target - v_base_load + v_solar + v_bess_dispatch);\n';
  v_b := E'  v_charge_cap := GREATEST(50, v_demand_target - v_base_load + v_solar + v_bess_dispatch);\n'
      || E'  /* 0435: in plan mode EV headroom up to the level is the fleet''s; battery charging yields, not the fleet */\n'
      || E'  IF COALESCE((v_day_plan->>''ok'')::boolean, false) THEN\n'
      || E'    v_charge_cap := GREATEST(50, v_demand_target - v_base_load + v_solar + GREATEST(v_bess_dispatch, 0));\n'
      || E'  END IF;\n';
  v_new := replace(v_new, v_a, v_b);

  -- 5. the plan's scalars ride on the BESS command -- appended only when a plan ran, so h_nrg is unchanged otherwise
  v_a := E'''mpc_setpoint_kw'', CASE WHEN v_mpc_follow THEN round(v_mpc_setpoint,1) END, ''mpc_step'', v_step));\n';
  v_b := E'''mpc_setpoint_kw'', CASE WHEN v_mpc_follow THEN round(v_mpc_setpoint,1) END, ''mpc_step'', v_step)\n'
      || E'     || CASE WHEN v_day_plan IS NOT NULL THEN jsonb_build_object(''day_plan'', v_day_plan - ''forecast'' - ''discharge_plan_kw'')\n'
      || E'             ELSE ''{}''::jsonb END);   /* 0435 */\n';
  v_new := replace(v_new, v_a, v_b);

  IF v_new = v_def THEN RAISE EXCEPTION '0435 (D): no splice applied'; END IF;
  EXECUTE v_new;
END $splice$;

-- ── V1: ottoq_forecast_net_load returns exactly what it returned before the rewrite ──
DO $$
DECLARE v_bad int; v_n int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE f.out IS DISTINCT FROM public.ottoq_forecast_net_load(f.sim_run_id, f.depot_id, f.clk, f.h, 30, 30))
    INTO v_n, v_bad FROM _0435_fnl f;
  IF v_n = 0 THEN RAISE EXCEPTION '0435 V1: no twin run to compare against'; END IF;
  IF v_bad <> 0 THEN RAISE EXCEPTION '0435 V1: ottoq_forecast_net_load changed output on % of % probes', v_bad, v_n; END IF;
END $$;

-- ── V2: the evaluator on three hand-solved cases ──
DO $$
DECLARE r record;
BEGIN
  -- (a) arbitrage ordering: 300 kWh over prices 0.05/0.10/0.20/0.30 at 500 kW, value/kWh = price - 0.08
  --     step 4 takes 250 kWh (0.22), step 3 the last 50 (0.12): 55 + 6 = 61; step 3 ran out of energy -> spare 0.20
  SELECT * INTO r FROM public.ottoq_bess_plan_eval(500, ARRAY[500,500,500,500]::numeric[], ARRAY[0.05,0.10,0.20,0.30]::numeric[],
                        ARRAY[0,0,0,0]::numeric[], 300, 1000, 0.5, 0, 0, 0.06, 0.02);
  IF NOT r.feasible OR r.value_usd <> 61 OR r.used_kwh <> 300 OR r.discharge_kw <> ARRAY[0,0,100,500]::numeric[] OR r.spare_price <> 0.20 THEN
    RAISE EXCEPTION '0435 V2(a): got feasible=% value=% used=% discharge=% spare=%', r.feasible, r.value_usd, r.used_kwh, r.discharge_kw, r.spare_price;
  END IF;
  -- (b) demand: a 1,500 kW spike over 800 kW; 400 kWh holds 775 exactly (362.5 + 3 x 12.5), not 774
  SELECT * INTO r FROM public.ottoq_bess_plan_eval(775, ARRAY[1500,800,800,800]::numeric[], ARRAY[0.10,0.10,0.10,0.10]::numeric[],
                        ARRAY[0,0,0,0]::numeric[], 400, 1000, 0.5, 0.7, 0, 0.06, 0.02);
  IF NOT r.feasible OR r.value_usd <> 515.5 OR r.shave_now_kw <> 725 THEN
    RAISE EXCEPTION '0435 V2(b): at 775 got feasible=% value=% shave_now=%', r.feasible, r.value_usd, r.shave_now_kw;
  END IF;
  SELECT * INTO r FROM public.ottoq_bess_plan_eval(774, ARRAY[1500,800,800,800]::numeric[], ARRAY[0.10,0.10,0.10,0.10]::numeric[],
                        ARRAY[0,0,0,0]::numeric[], 400, 1000, 0.5, 0.7, 0, 0.06, 0.02);
  IF r.feasible THEN RAISE EXCEPTION '0435 V2(b): 774 kW should not be holdable on 400 kWh'; END IF;
  -- (c) the reserve binds cumulatively: 400 kWh, reserve 300/200/100/0 -> step 4 takes 300, step 3 the 100 left
  SELECT * INTO r FROM public.ottoq_bess_plan_eval(600, ARRAY[600,600,600,600]::numeric[], ARRAY[0.30,0.30,0.30,0.30]::numeric[],
                        ARRAY[300,200,100,0]::numeric[], 400, 1000, 0.5, 0, 0, 0.06, 0.02);
  IF NOT r.feasible OR r.discharge_kw <> ARRAY[0,0,200,600]::numeric[] OR r.used_kwh <> 400 OR r.value_usd <> 88 THEN
    RAISE EXCEPTION '0435 V2(c): got feasible=% discharge=% used=% value=%', r.feasible, r.discharge_kw, r.used_kwh, r.value_usd;
  END IF;
END $$;

-- ── V3: the plan on the newest twin run: well-formed, deterministic, bounded in time ──
DO $$
DECLARE v_run uuid; v_depot uuid; v_clock timestamptz; v_p1 jsonb; v_p2 jsonb; v_n int;
BEGIN
  SELECT sim_run_id, depot_id, sim_clock_current INTO v_run, v_depot, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND sim_clock_current IS NOT NULL ORDER BY started_at DESC LIMIT 1;
  v_p1 := public.ottoq_bess_day_plan(v_run, v_depot, v_clock);
  v_p2 := public.ottoq_bess_day_plan(v_run, v_depot, v_clock);
  IF NOT COALESCE((v_p1->>'ok')::boolean, false) THEN RAISE EXCEPTION '0435 V3: plan not ok: %', v_p1; END IF;
  v_n := (v_p1->>'horizon_steps')::int;
  IF v_n NOT BETWEEN 16 AND 48 OR jsonb_array_length(v_p1->'forecast'->'net_kw') <> v_n
     OR jsonb_array_length(v_p1->'discharge_plan_kw') <> v_n THEN
    RAISE EXCEPTION '0435 V3: horizon % does not match its arrays', v_n;
  END IF;
  IF (v_p1->>'arb_now_kw')::numeric > 0 AND (v_p1->>'charge_now_kw')::numeric > 0 THEN
    RAISE EXCEPTION '0435 V3: the plan charges and discharges in the same step';
  END IF;
  IF (v_p1 - 'solve_ms') IS DISTINCT FROM (v_p2 - 'solve_ms') THEN RAISE EXCEPTION '0435 V3: two calls disagree'; END IF;
  IF (v_p1->>'solve_ms')::numeric > 500 THEN RAISE EXCEPTION '0435 V3: solve took % ms', v_p1->>'solve_ms'; END IF;
  RAISE NOTICE '0435 V3: run % at % -> mode % level % kW, % steps, % ms', v_run, v_clock, v_p1->>'mode', v_p1->>'level_kw', v_n, v_p1->>'solve_ms';
END $$;

-- ── V4: the orchestrator, on a rolled-back probe over the newest twin run ──
--   (i) switch off -> no 'day_plan' key and no plan mode (the cert path's text is unchanged)
--  (ii) switch on  -> the plan runs and says so
-- (iii) switch on, bess_day_plan_enabled = 0 -> the water-fill, no plan
DO $$
DECLARE v_run uuid; v_depot uuid; v_clock timestamptz; v_reason jsonb; v_ok boolean := false; v_msg text := '';
BEGIN
  SELECT sim_run_id, depot_id, sim_clock_current INTO v_run, v_depot, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND sim_clock_current IS NOT NULL ORDER BY started_at DESC LIMIT 1;
  BEGIN
    DELETE FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = v_run
       AND param_key IN ('energy_reserve_shave', 'bess_day_plan_enabled', 'energy_mpc_follow');
    PERFORM public.ottoq_energy_orchestrate(v_run, v_depot, v_clock, 9000001);
    SELECT reason INTO v_reason FROM public.ottoq_energy_commands WHERE sim_run_id = v_run AND tick_seq = 9000001 AND command_type = 'bess_setpoint_kw';
    IF v_reason ? 'day_plan' OR v_reason->>'mode' LIKE 'plan_%' THEN v_msg := v_msg || ' (i) plan ran with the switch off;'; END IF;

    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('run', v_run, 'energy_reserve_shave', 1, '0435_probe');
    PERFORM public.ottoq_energy_orchestrate(v_run, v_depot, v_clock, 9000002);
    SELECT reason INTO v_reason FROM public.ottoq_energy_commands WHERE sim_run_id = v_run AND tick_seq = 9000002 AND command_type = 'bess_setpoint_kw';
    IF NOT (v_reason ? 'day_plan') OR NOT COALESCE((v_reason->'day_plan'->>'ok')::boolean, false)
       OR NOT (v_reason->>'mode' LIKE 'plan_%' OR v_reason->>'mode' IN ('discharge_dr', 'thermal_hold')) THEN
      v_msg := v_msg || format(' (ii) mode %s day_plan %s;', v_reason->>'mode', v_reason->'day_plan');
    END IF;

    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('run', v_run, 'bess_day_plan_enabled', 0, '0435_probe');
    PERFORM public.ottoq_energy_orchestrate(v_run, v_depot, v_clock, 9000003);
    SELECT reason INTO v_reason FROM public.ottoq_energy_commands WHERE sim_run_id = v_run AND tick_seq = 9000003 AND command_type = 'bess_setpoint_kw';
    IF v_reason ? 'day_plan' OR v_reason->>'mode' LIKE 'plan_%' OR NOT COALESCE((v_reason->>'reserve_shave')::boolean, false) THEN
      v_msg := v_msg || format(' (iii) mode %s reserve_shave %s;', v_reason->>'mode', v_reason->>'reserve_shave');
    END IF;
    v_ok := (v_msg = '');
    RAISE EXCEPTION USING MESSAGE = '0435_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0435_probe_rollback' THEN RAISE; END IF;
  END;
  IF NOT v_ok THEN RAISE EXCEPTION '0435 V4:%', v_msg; END IF;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0435_the_battery_planned_eight_hours_ahead_on_a_forecast_where_charging_stops_and_was_empty_before_the_expensive_afternoon',
   false,
   'Day-length battery plan (public.ottoq_bess_day_plan) behind energy_reserve_shave, which no cert run turns on '
   '(P3); the command-reason key it adds is appended only in plan mode (V4(i)); ottoq_forecast_net_load refactored '
   'with output proven identical (V1).')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert FALSE. After applying: start an armed demo run (the agent turns energy_reserve_shave on) and read
-- reason->'day_plan' on the BESS commands -- mode, level_kw, charge_reason -- against site_energy_snapshots by hour.
-- The claim to test: SoC is at or above the reserve at 14:00 CT, and the on-peak hours carry the discharge.
-- Rollback: set bess_day_plan_enabled = 0 (global or per run), or restore from ottoq_schema_snapshots label '0435_pre'.
