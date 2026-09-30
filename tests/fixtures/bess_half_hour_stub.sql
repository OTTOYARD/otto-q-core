-- Stub engine for 0600 and 0601 (tests/test_bess_half_hour_sql.py). The battery's day plan
-- (public.ottoq_bess_day_plan, source md5 8f136624ad07b64a3ef3022b3bab0753), its evaluator (ottoq_bess_plan_eval,
-- 28c8e1aa2e86922861695f95d22a424e), the EV queue forecast (ottoq_forecast_ev_queue_kw, ff2cfc482ce702e664b24ed514435569)
-- and its list scheduler (ottoq_ev_queue_schedule, bb2a1dce2e7d984bb8707dea1873d137) are the live bodies, byte for byte, as
-- measured on 2026-09-30; so is the charge-rate function (20f2d98f41e34238497a5d28304e7004). Everything else is a stub
-- shaped like the columns those functions read: a site whose samples, fleet and chargers a test writes directly.

CREATE SCHEMA IF NOT EXISTS twin;
CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;

-- the site
CREATE TABLE public.depots (id uuid PRIMARY KEY, origin_lat numeric, origin_lng numeric);
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, depot_id uuid NOT NULL);
CREATE TABLE public.ottoq_bess_units (
  bess_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid NOT NULL, capacity_kwh numeric, current_soc_pct numeric,
  soc_min_floor_pct numeric, soc_max_ceiling_pct numeric, max_discharge_kw numeric, max_charge_kw numeric,
  roundtrip_efficiency_pct numeric);
CREATE TABLE public.site_energy_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), depot_id uuid NOT NULL, sim_run_id uuid, "timestamp" timestamptz NOT NULL,
  grid_import_kw numeric, building_load_kw numeric, lighting_load_kw numeric, solar_generation_kw numeric,
  total_ev_charging_kw numeric, billing_period_peak_kw numeric);
CREATE TABLE public.ottoq_canopy_state (depot_id uuid NOT NULL, canopy_code text NOT NULL, nameplate_ac_kw numeric);
CREATE TABLE public.ottoq_weather_snapshots (depot_id uuid NOT NULL, sim_run_id uuid, sim_clock_at timestamptz NOT NULL,
  solar_elevation_deg numeric);
CREATE TABLE public.ottoq_depot_tariffs (
  tariff_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, depot_id uuid NOT NULL, active boolean NOT NULL DEFAULT true,
  season text, season_months int[], demand_first_block_usd_kw numeric, effective_from date NOT NULL DEFAULT '2024-10-01');
CREATE TABLE public.ottoq_tariff_windows (depot_id uuid NOT NULL, active boolean NOT NULL DEFAULT true, season text,
  rate_usd_per_kwh numeric);
CREATE TABLE public.ottoq_policy_param_catalog (param_key text PRIMARY KEY, min_value numeric, max_value numeric,
  default_value numeric, agent_writable boolean NOT NULL DEFAULT false, affects text, description text);
CREATE TABLE public.ottoq_policy_params (scope_type text NOT NULL, scope_id uuid NOT NULL, param_key text NOT NULL,
  param_value numeric NOT NULL, PRIMARY KEY (scope_type, scope_id, param_key));

-- the fleet and the chargers the queue forecast reads
CREATE TABLE public.vehicles (id uuid PRIMARY KEY, home_depot_id uuid NOT NULL, current_state text NOT NULL,
  current_soc numeric, target_soc numeric, battery_capacity_kwh numeric, inlet_max_kw numeric);
CREATE TABLE public.ottoq_ocpp_chargers (charger_id uuid PRIMARY KEY, max_kw numeric, station_state text NOT NULL DEFAULT 'Available',
  decommissioned_at timestamptz);
CREATE TABLE public.stalls (id uuid PRIMARY KEY, depot_id uuid NOT NULL, ocpp_charger_id uuid, connector_max_kw numeric);
CREATE TABLE public.ocpp_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stall_id uuid, vehicle_id uuid, status text,
  sim_run_id uuid, started_at timestamptz, ambient_temp_c numeric);
CREATE TABLE public.ottoq_vehicle_dispatches (sim_run_id uuid, vehicle_id uuid, status text, scheduled_return_at timestamptz);

-- the migration ledger and the in-flight probe (0513), driven by a table so a test can make a pair be running
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL,
  forces_dial_restart boolean NOT NULL DEFAULT false, note text, classified_at timestamptz);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigint GENERATED ALWAYS AS IDENTITY, label text, object_kind text,
  schema_name text, object_name text, definition text, def_md5 text);
CREATE TABLE public.stub_in_flight (n int NOT NULL);
INSERT INTO public.stub_in_flight VALUES (0);
CREATE FUNCTION public.ottoq_certification_in_flight(p_include_dial boolean DEFAULT false) RETURNS integer
  LANGUAGE sql STABLE AS $$ SELECT n FROM public.stub_in_flight $$;

-- the reads the plan makes that are not the subject here: no forecast uncertainty, clean panels, a flat 8 c tariff,
-- the sun below the horizon unless a test puts it up, and whatever known EV load a test writes
CREATE FUNCTION public.ottoq_forecast_uncertainty(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz) RETURNS numeric
  LANGUAGE sql STABLE AS $$ SELECT 0::numeric $$;
CREATE FUNCTION twin.ottoq_sim_canopy_soiling(p_run uuid, p_depot uuid, p_canopy text, p_clock timestamptz, p_ro boolean)
  RETURNS numeric LANGUAGE sql STABLE AS $$ SELECT 1::numeric $$;
CREATE FUNCTION twin.ottoq_sim_current_tariff(p_depot_id uuid, p_t timestamptz, OUT out_label text, OUT out_rate_usd_kwh numeric)
  LANGUAGE sql STABLE AS $$ SELECT 'off_peak'::text, 0.08::numeric $$;
CREATE FUNCTION twin.ottoq_sim_solar_elevation_deg(p_t timestamptz, p_lat numeric, p_lng numeric) RETURNS numeric
  LANGUAGE sql STABLE AS $$ SELECT -10::numeric $$;
CREATE TABLE public.stub_known_kw (k int PRIMARY KEY, kw numeric NOT NULL);
CREATE FUNCTION public.ottoq_forecast_ev_known_kw(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamptz,
  p_horizon_ticks int, p_tick_min numeric, p_arrival_soc numeric) RETURNS numeric[]
  LANGUAGE sql STABLE AS $$
  SELECT array_agg(COALESCE(s.kw, 0) ORDER BY g.k) FROM generate_series(1, p_horizon_ticks) g(k) LEFT JOIN public.stub_known_kw s USING (k) $$;
CREATE FUNCTION public.ottoq_default_target_soc() RETURNS numeric LANGUAGE sql IMMUTABLE AS $$ SELECT 100::numeric $$;

-- the dial reader, the live source's tiers (run, then depot, then global), without 0533's read witness
CREATE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric) RETURNS numeric
  LANGUAGE plpgsql STABLE AS $$
DECLARE v numeric; v_depot uuid;
BEGIN
  SELECT param_value INTO v FROM ottoq_policy_params WHERE scope_type='run' AND scope_id=p_sim_run_id AND param_key=p_param_key;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF v_depot IS NOT NULL THEN
    SELECT param_value INTO v FROM ottoq_policy_params WHERE scope_type='depot' AND scope_id=v_depot AND param_key=p_param_key;
    IF v IS NOT NULL THEN RETURN v; END IF;
  END IF;
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='global' AND scope_id='00000000-0000-0000-0000-000000000000'::uuid AND param_key=p_param_key;
  RETURN COALESCE(v, p_default);
END $$;

-- the live charge-rate function and the stateless RNG it reads, byte for byte (as tests/fixtures/charge_calibration_stub.sql)
CREATE OR REPLACE FUNCTION twin.ottoq_sim_seeded_random(p_seed bigint, p_salt text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hash BIGINT;
BEGIN
  -- Combine seed + salt into a deterministic hash, normalize to [0,1)
  v_hash := abs(hashtextextended(p_seed::text || ':' || p_salt, p_seed));
  RETURN (v_hash % 1000000)::NUMERIC / 1000000.0;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_sim_compute_charge_rate(p_soc_pct numeric, p_battery_temp_c numeric, p_ambient_temp_c numeric, p_charger_max_kw numeric, p_vehicle_max_kw numeric, p_battery_capacity_kwh numeric, p_battery_soh_pct numeric DEFAULT 100, p_noise_seed bigint DEFAULT 0, p_noise_salt text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_base_rate      NUMERIC;
  v_is_dcfc        BOOLEAN;
  v_curve_factor   NUMERIC := 1.0;
  v_thermal_factor NUMERIC := 1.0;
  v_soh_factor     NUMERIC;
  v_noise_factor   NUMERIC;
BEGIN
  v_base_rate := LEAST(p_charger_max_kw, p_vehicle_max_kw);
  IF v_base_rate <= 0 THEN RETURN 0; END IF;
  v_is_dcfc := p_charger_max_kw > 22;

  IF v_is_dcfc THEN
    -- DCFC: ramp to peak by 20%, NEAR-LINEAR decline 20->80% (1.0 -> 0.22),
    -- steeper CV tail 80->100% (0.22 -> 0.08). 20->80 on a 75kWh pack lands
    -- ~25-30 min at typical effective power — the measured reality.
    IF p_soc_pct < 20 THEN
      v_curve_factor := 0.85 + (p_soc_pct / 20.0) * 0.15;
    ELSIF p_soc_pct <= 80 THEN
      v_curve_factor := 1.0 - ((p_soc_pct - 20.0) / 60.0) * 0.78;
    ELSE
      v_curve_factor := GREATEST(0.08, 0.22 - ((p_soc_pct - 80.0) / 20.0) * 0.14);
    END IF;
  ELSE
    -- L2/AC: onboard-charger limited, flat with ~88% AC->DC efficiency;
    -- taper only near full.
    v_curve_factor := CASE WHEN p_soc_pct > 95 THEN 0.88 * 0.5 ELSE 0.88 END;
  END IF;

  -- thermal derate: INL-calibrated cold behavior; heat derate unchanged
  IF p_battery_temp_c > 35 THEN
    v_thermal_factor := GREATEST(0.30, 1.0 - (p_battery_temp_c - 35) * 0.020);
  ELSIF p_battery_temp_c < 0 THEN
    v_thermal_factor := GREATEST(0.20, 0.35 + p_battery_temp_c * 0.010);  -- <=0C: 0.35 and falling
  ELSIF p_battery_temp_c < 10 THEN
    v_thermal_factor := 0.65;                                             -- 0-10C: x0.65 (INL)
  ELSIF p_battery_temp_c < 15 THEN
    v_thermal_factor := 0.65 + (p_battery_temp_c - 10) * 0.07;            -- blend 10->15C
  END IF;

  v_soh_factor := 0.70 + (p_battery_soh_pct / 100.0) * 0.30;
  v_noise_factor := 0.97 + ottoq_sim_seeded_random(
    p_noise_seed, COALESCE(p_noise_salt, '') || ':' || p_soc_pct::text) * 0.06;

  RETURN ROUND((v_base_rate * v_curve_factor * v_thermal_factor * v_soh_factor * v_noise_factor)::NUMERIC, 3);
END;
$function$;

-- the live queue forecast and its list scheduler, byte for byte (created by 0444 and unchanged since)
CREATE FUNCTION public.ottoq_ev_queue_schedule(
  p_charger_kw numeric[], p_charger_free_min numeric[],
  p_job_kwh numeric[], p_job_release_min numeric[], p_job_inlet_kw numeric[],
  p_step_min numeric, p_steps integer,
  OUT load_kw numeric[], OUT placed integer, OUT unplaced integer, OUT placed_kwh numeric)
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0444: list scheduling of charge jobs onto chargers, for a load FORECAST. Jobs arrive in queue order; each takes
   the charger that can start it earliest (ties: more kW, then lower index). Load is each step's AVERAGE kW, so
   sum(load) x step/60 is the energy delivered inside the horizon. Pure: no table is read. */
DECLARE
  v_free numeric[]; v_nc int; v_nj int; j int; c int; h int;
  v_best int; v_bt numeric; v_t numeric; v_ac numeric; v_rate numeric;
  v_s numeric; v_e numeric; v_end numeric; v_lo numeric; v_hi numeric;
BEGIN
  IF p_step_min IS NULL OR p_step_min <= 0 OR p_steps IS NULL OR p_steps < 1 THEN
    RAISE EXCEPTION 'ottoq_ev_queue_schedule: step_min % and steps % must be positive', p_step_min, p_steps;
  END IF;
  load_kw := array_fill(0::numeric, ARRAY[p_steps]);
  placed := 0; unplaced := 0; placed_kwh := 0;
  v_nc := COALESCE(array_length(p_charger_kw, 1), 0);
  v_nj := COALESCE(array_length(p_job_kwh, 1), 0);
  IF COALESCE(array_length(p_charger_free_min, 1), 0) <> v_nc
     OR COALESCE(array_length(p_job_release_min, 1), 0) <> v_nj
     OR COALESCE(array_length(p_job_inlet_kw, 1), 0) <> v_nj THEN
    RAISE EXCEPTION 'ottoq_ev_queue_schedule: charger or job arrays disagree in length';
  END IF;
  IF v_nj = 0 THEN RETURN; END IF;
  v_free := COALESCE(p_charger_free_min, '{}'::numeric[]);
  v_end := p_step_min * p_steps;

  FOR j IN 1 .. v_nj LOOP
    IF COALESCE(p_job_kwh[j], 0) <= 0 THEN CONTINUE; END IF;
    v_best := NULL; v_bt := NULL;
    FOR c IN 1 .. v_nc LOOP
      IF COALESCE(p_charger_kw[c], 0) <= 0 THEN CONTINUE; END IF;
      v_t := GREATEST(COALESCE(v_free[c], 0), COALESCE(p_job_release_min[j], 0));
      IF v_best IS NULL OR v_t < v_bt OR (v_t = v_bt AND p_charger_kw[c] > p_charger_kw[v_best]) THEN
        v_best := c; v_bt := v_t;
      END IF;
    END LOOP;
    IF v_best IS NULL OR v_bt >= v_end THEN unplaced := unplaced + 1; CONTINUE; END IF;

    v_ac   := LEAST(p_charger_kw[v_best], COALESCE(NULLIF(p_job_inlet_kw[j], 0), p_charger_kw[v_best]));
    v_rate := GREATEST(1, LEAST(v_ac, 250) * CASE WHEN v_ac <= 50 THEN 1.0 ELSE 0.60 END);
    v_s := v_bt;
    v_e := v_s + p_job_kwh[j] / v_rate * 60.0;
    v_free[v_best] := v_e;
    placed := placed + 1; placed_kwh := placed_kwh + p_job_kwh[j];
    FOR h IN (floor(v_s / p_step_min)::int + 1) .. LEAST(p_steps, ceil(v_e / p_step_min)::int) LOOP
      v_lo := GREATEST(v_s, (h - 1) * p_step_min);
      v_hi := LEAST(v_e, h * p_step_min);
      IF v_hi > v_lo THEN load_kw[h] := load_kw[h] + v_rate * (v_hi - v_lo) / p_step_min; END IF;
    END LOOP;
  END LOOP;
END $fn$;

CREATE FUNCTION public.ottoq_forecast_ev_queue_kw(
  p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamptz, p_horizon_steps integer, p_step_min numeric,
  OUT load_kw numeric[], OUT pending_n integer, OUT pending_kwh numeric, OUT returning_n integer,
  OUT chargers_n integer, OUT unplaced_n integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0444 (G177): the EV load the depot will draw, as a queue. Running sessions hold their charger until their
   forecast end (ottoq_forecast_ev_known_kw loop (1)'s arithmetic, verbatim); vehicles waiting on site and returning
   dispatches (loop (2)'s predicate) are scheduled onto the chargers as they free, by ottoq_ev_queue_schedule.
   Every input is this run's rows or the depot's static data, so the two arms of a pair see the same forecast. */
DECLARE
  r record; v_q record; h int;
  v_ckw numeric[] := '{}'; v_cfree numeric[] := '{}'; v_active numeric[];
  v_jkwh numeric[] := '{}'; v_jrel numeric[] := '{}'; v_jin numeric[] := '{}'; v_ql numeric[];
  v_rate numeric; v_dur numeric; v_hi numeric;
BEGIN
  v_active := array_fill(0::numeric, ARRAY[p_horizon_steps]);
  pending_n := 0; pending_kwh := 0; returning_n := 0;

  -- the chargers, and the running session on each (a faulted charger counts only while a session still runs on it)
  FOR r IN
    SELECT COALESCE(ch.max_kw, st.connector_max_kw, 0)::numeric AS kw, a.rate, a.kwh
      FROM stalls st
      JOIN ottoq_ocpp_chargers ch ON ch.charger_id = st.ocpp_charger_id
      LEFT JOIN LATERAL (
        SELECT ottoq_sim_compute_charge_rate(
                 p_soc_pct := v.current_soc, p_battery_temp_c := COALESCE(s.ambient_temp_c,22)+5,
                 p_ambient_temp_c := COALESCE(s.ambient_temp_c,22), p_charger_max_kw := ch.max_kw,
                 p_vehicle_max_kw := v.inlet_max_kw, p_battery_capacity_kwh := v.battery_capacity_kwh,
                 p_battery_soh_pct := 95, p_noise_seed := 1, p_noise_salt := s.vehicle_id::text) AS rate,
               GREATEST(0,(COALESCE(v.target_soc, public.ottoq_default_target_soc())-v.current_soc)/100.0
                          *COALESCE(v.battery_capacity_kwh,75)) AS kwh
          FROM ocpp_sessions s JOIN vehicles v ON v.id = s.vehicle_id
         WHERE s.stall_id = st.id AND s.status = 'active' AND s.sim_run_id = p_sim_run_id
         ORDER BY s.started_at DESC, s.vehicle_id
         LIMIT 1) a ON true
     WHERE st.depot_id = p_depot_id AND ch.decommissioned_at IS NULL
       AND (a.rate IS NOT NULL OR ch.station_state IS DISTINCT FROM 'Faulted')
     ORDER BY st.id
  LOOP
    v_ckw := v_ckw || r.kw;
    IF r.rate IS NULL THEN
      v_cfree := v_cfree || 0::numeric;
    ELSE
      v_rate := GREATEST(r.rate, 1);
      v_dur  := r.kwh / v_rate * 60.0;
      v_cfree := v_cfree || v_dur;
      FOR h IN 1 .. LEAST(p_horizon_steps, ceil(v_dur / p_step_min)::int) LOOP
        v_hi := LEAST(v_dur, h * p_step_min);
        IF v_hi > (h - 1) * p_step_min THEN
          v_active[h] := v_active[h] + v_rate * (v_hi - (h - 1) * p_step_min) / p_step_min;
        END IF;
      END LOOP;
    END IF;
  END LOOP;

  -- the queue: the fleet waiting on site now, then the returns at their ETAs
  FOR r IN
    SELECT q.kwh, q.rel, q.inlet, q.kind FROM (
      SELECT GREATEST(0,(COALESCE(v.target_soc, public.ottoq_default_target_soc())-v.current_soc)/100.0
                        *COALESCE(v.battery_capacity_kwh,75)) AS kwh,
             0::numeric AS rel, COALESCE(v.inlet_max_kw,150)::numeric AS inlet, 'on_site'::text AS kind,
             v.current_soc AS soc, v.id AS vid
        FROM vehicles v
       WHERE v.home_depot_id = p_depot_id
         AND v.current_state IN ('arrived_at_gate','staged_awaiting_service')
         AND v.current_soc IS NOT NULL
         AND v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc())
         AND NOT EXISTS (SELECT 1 FROM ocpp_sessions s
                          WHERE s.vehicle_id = v.id AND s.status = 'active' AND s.sim_run_id = p_sim_run_id)
      UNION ALL
      SELECT GREATEST(0,(COALESCE(v.target_soc, public.ottoq_default_target_soc())-COALESCE(v.current_soc, 30))/100.0
                        *COALESCE(v.battery_capacity_kwh,75)),
             GREATEST(0, EXTRACT(EPOCH FROM (d.scheduled_return_at - p_sim_clock)) / 60.0),
             COALESCE(v.inlet_max_kw,150)::numeric, 'returning', COALESCE(v.current_soc, 30), v.id
        FROM ottoq_vehicle_dispatches d JOIN vehicles v ON v.id = d.vehicle_id
       WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning')
         AND d.scheduled_return_at IS NOT NULL
         AND d.scheduled_return_at <= p_sim_clock + (p_horizon_steps * p_step_min) * interval '1 min'
         AND d.scheduled_return_at >  p_sim_clock - interval '30 min'
         AND v.current_state NOT IN ('arrived_at_gate','staged_awaiting_service','charging_dcfc','charging_l2')
    ) q
    WHERE q.kwh > 0
    ORDER BY q.rel, q.soc, q.vid
  LOOP
    v_jkwh := v_jkwh || r.kwh; v_jrel := v_jrel || r.rel; v_jin := v_jin || r.inlet;
    IF r.kind = 'on_site' THEN
      pending_n := pending_n + 1; pending_kwh := pending_kwh + r.kwh;
    ELSE
      returning_n := returning_n + 1;
    END IF;
  END LOOP;

  SELECT * INTO v_q FROM public.ottoq_ev_queue_schedule(v_ckw, v_cfree, v_jkwh, v_jrel, v_jin, p_step_min, p_horizon_steps);
  v_ql := v_q.load_kw;
  load_kw := v_active;
  FOR h IN 1 .. p_horizon_steps LOOP
    load_kw[h] := load_kw[h] + COALESCE(v_ql[h], 0);
  END LOOP;
  chargers_n := COALESCE(array_length(v_ckw, 1), 0);
  unplaced_n := v_q.unplaced;
END $fn$;

-- the live evaluator and day plan, byte for byte
CREATE FUNCTION public.ottoq_bess_plan_eval(p_level numeric, p_net numeric[], p_price numeric[], p_reserve numeric[], p_e_avail numeric, p_pd numeric, p_dt numeric, p_d_day numeric, p_ratchet numeric, p_c_rep numeric, p_c_deg numeric, OUT feasible boolean, OUT value_usd numeric, OUT used_kwh numeric, OUT shave_now_kw numeric, OUT arb_now_kw numeric, OUT spare_price numeric, OUT discharge_kw numeric[])
 RETURNS record
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
$function$
;

CREATE FUNCTION public.ottoq_bess_day_plan(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone, p_net_load_now_kw numeric DEFAULT NULL::numeric)
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
  v_q record; v_queue numeric[];   /* 0444 */
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
  SELECT COALESCE(sum(c.nameplate_ac_kw), 0),
         -- 0479 (G214): the run's own soiling, as the solar step reads it
         COALESCE(avg(twin.ottoq_sim_canopy_soiling(p_sim_run_id, p_depot_id, c.canopy_code, p_sim_clock, true)), 1) INTO v_ac, v_soil
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
  -- 0444 (G177): and the fleet already on site waiting for a charger, queued onto the chargers as they free
  SELECT * INTO v_q FROM public.ottoq_forecast_ev_queue_kw(p_sim_run_id, p_depot_id, p_sim_clock, v_n, 30);
  v_queue := v_q.load_kw;

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
    v_ev[k] := GREATEST(COALESCE(v_known[k], 0), COALESCE(v_queue[k], 0), v_ev_persist);   /* 0444 */
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
    'ev_queue', jsonb_build_object('pending_n', v_q.pending_n, 'pending_kwh', round(v_q.pending_kwh, 1),
                 'returning_n', v_q.returning_n, 'chargers', v_q.chargers_n, 'unplaced_n', v_q.unplaced_n,
                 'peak_kw', round((SELECT max(x) FROM unnest(v_queue) AS x), 1)),   /* 0444 */
    'solve_ms', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) * 1000),
    'forecast', jsonb_build_object(
       'net_kw',   (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_net)   WITH ORDINALITY AS u(x, o)),
       'ev_kw',    (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_ev)    WITH ORDINALITY AS u(x, o)),
       'ev_queue_kw', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_queue) WITH ORDINALITY AS u(x, o)),   /* 0444 */
       'ev_known_kw', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_known) WITH ORDINALITY AS u(x, o)),
       'solar_kw', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_solar) WITH ORDINALITY AS u(x, o)),
       'base_kw',  (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_base)  WITH ORDINALITY AS u(x, o)),
       'price',    to_jsonb(v_price),
       'reserve_kwh', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_res) WITH ORDINALITY AS u(x, o))),
    'discharge_plan_kw', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_best.discharge_kw) WITH ORDINALITY AS u(x, o)));
END;
$function$
;

-- the plan's one caller, as 0444 P2 finds it: the orchestrator (a stub that only asks)
CREATE FUNCTION public.ottoq_energy_orchestrate(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamptz, p_tick_seq bigint)
  RETURNS numeric LANGUAGE plpgsql AS $$
BEGIN
  RETURN (public.ottoq_bess_day_plan(p_sim_run_id, p_depot_id, p_sim_clock, NULL)->>'charge_now_kw')::numeric;
END $$;
