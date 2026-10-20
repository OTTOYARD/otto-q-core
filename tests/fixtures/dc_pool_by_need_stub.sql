-- tests/fixtures/dc_pool_by_need_stub.sql -- what db/migrations/0737 reads, for tests/test_dc_pool_by_need_sql.py.
-- GENERATED from the live catalog on 2026-10-17. twin.ottoq_sim_dc_pool_shares (0726, prosrc md5 864684e0) and
-- public.ottoq_policy_get (prosrc md5 72b658f3) are the live bodies; twin.ottoq_sim_dc_pool_plan is the ottoq_schema_snapshots
-- row labelled 0737_pre (0729's body, prosrc md5 6afd8ee2, the body 0737's P1 requires), with the live grants. The plan is
-- only patched and read here, never called: the sessions, stalls, cars and energy it reads are not in the stub. The two
-- sweep tables are the live column lists, holding the three sweeps 0737's (d) and V3 read. Two charge sessions of two cars
-- on arm 83's run are there for V2. ottoq_certification_in_flight is a stand-in, as in the other stubs.
SET client_min_messages = warning;
CREATE SCHEMA IF NOT EXISTS twin; CREATE SCHEMA IF NOT EXISTS ottoq; CREATE SCHEMA IF NOT EXISTS extensions;
DO $roles$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;

CREATE TABLE public.ottoq_policy_param_catalog (param_key text PRIMARY KEY, description text, default_value numeric, min_value numeric, max_value numeric, affects text, min_exclusive numeric, max_exclusive numeric, agent_writable boolean, agent_min_value numeric, agent_max_value numeric, agent_max_drift_pct numeric);
CREATE TABLE public.ottoq_policy_params (scope_type text, scope_id uuid, param_key text, param_value numeric, updated_by text, updated_at timestamp with time zone, PRIMARY KEY (scope_type, scope_id, param_key));
CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, depot_id uuid);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial PRIMARY KEY, taken_at timestamp with time zone DEFAULT now(), label text, object_kind text, schema_name text, object_name text, definition text, def_md5 text);
CREATE TABLE public.ottoq_cert_lineage (name text UNIQUE, forces_recert boolean, note text, classified_at timestamp with time zone, forces_dial_restart boolean);
CREATE TABLE public.ottoq_throughput_sweeps (sweep_id uuid DEFAULT gen_random_uuid(), sweep_code text, title text, depot_id uuid, scenario text, sim_start timestamp with time zone, ticks integer, sim_min_per_tick numeric, seeds bigint[], replicates integer DEFAULT 1, priority integer DEFAULT 100, arm_budget_s integer, status text DEFAULT 'active'::text, run_after timestamp with time zone, notes text, created_by text DEFAULT 'research_wing'::text, created_at timestamp with time zone DEFAULT now(), concluded_at timestamp with time zone, fleet_code text);
CREATE TABLE public.ottoq_throughput_sweep_cells (cell_id uuid DEFAULT gen_random_uuid(), sweep_id uuid, cell_code text, ord integer, seat text, buildout_code text, fixed_params jsonb DEFAULT '{}'::jsonb, control_cell_code text);
CREATE TABLE public.ocpp_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid, sim_run_id uuid, status text DEFAULT 'active');
CREATE TABLE public.ottoq_visit_needs (visit_id uuid DEFAULT gen_random_uuid(), vehicle_id uuid, sim_run_id uuid, depot_id uuid, arrived_at timestamp with time zone, visit_key text, archetype text, urgency text, dispatch_due_at timestamp with time zone, target_soc numeric, atoms jsonb, status text, source text, meta jsonb, created_at timestamp with time zone DEFAULT now());

-- STAND-IN: the live probe reads pg_stat_activity for pairs, the recert runner, dial pairs and sweeps.
CREATE OR REPLACE FUNCTION public.ottoq_certification_in_flight(p_with_dial boolean DEFAULT true)
 RETURNS integer LANGUAGE sql STABLE
AS $function$
  SELECT CASE WHEN current_setting('ottoq.simulate_certification_in_flight', true) = 'on' THEN 1 ELSE 0 END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v numeric; v_depot uuid; v_seen text;
BEGIN
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='run' AND scope_id=p_sim_run_id AND param_key=p_param_key;
  IF v IS NOT NULL THEN
    -- 0533 (G258): the read witness. A dial pair asks, after each arm, whether the arm read its own run-scoped value of
    -- the dial at all: a dial nothing reads at run scope cannot make two arms differ. One entry per run and key, in a
    -- transaction-local setting, so it costs nothing outside the run tier and leaves with the transaction.
    v_seen := COALESCE(current_setting('ottoq.run_scope_reads', true), '');
    IF strpos(v_seen, ',' || p_sim_run_id::text || ':' || p_param_key || ',') = 0 THEN
      PERFORM set_config('ottoq.run_scope_reads',
                         CASE WHEN v_seen = '' THEN ',' ELSE v_seen END || p_sim_run_id::text || ':' || p_param_key || ',', true);
    END IF;
    RETURN v;
  END IF;
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF v_depot IS NOT NULL THEN
    SELECT param_value INTO v FROM ottoq_policy_params
     WHERE scope_type='depot' AND scope_id=v_depot AND param_key=p_param_key;
    IF v IS NOT NULL THEN RETURN v; END IF;
  END IF;
  -- global tier: sentinel, not NULL (scope_id is in the primary key)
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='global' AND scope_id='00000000-0000-0000-0000-000000000000'::uuid
     AND param_key=p_param_key;
  RETURN COALESCE(v, p_default);
END;
$function$;

CREATE OR REPLACE FUNCTION twin.ottoq_sim_dc_pool_shares(p_demand jsonb, p_pool_kw numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
-- 0726: water-filling. Charges are visited from the smallest demand up; each gets the lesser of its demand and an equal
-- share of what is left, so a charge that wants less than its share leaves the rest to the others. Ties in demand are
-- visited in key order, which cannot change any share (equal demands get equal shares). Total, never above the pool.
DECLARE
  r record; v_left numeric; v_n int; v_i int := 0; v_fair numeric; v_out jsonb := '{}'::jsonb;
BEGIN
  IF p_demand IS NULL OR p_demand = '{}'::jsonb THEN
    RETURN '{}'::jsonb;
  END IF;
  v_left := GREATEST(0, COALESCE(p_pool_kw, 0));
  SELECT count(*) INTO v_n FROM jsonb_each_text(p_demand);
  FOR r IN SELECT e.key AS k, GREATEST(0, COALESCE(e.value::numeric, 0)) AS d
             FROM jsonb_each_text(p_demand) e ORDER BY GREATEST(0, COALESCE(e.value::numeric, 0)), e.key LOOP
    v_fair := v_left / (v_n - v_i);
    IF r.d <= v_fair THEN
      v_out := v_out || jsonb_build_object(r.k, r.d);
      v_left := v_left - r.d;
    ELSE
      v_out := v_out || jsonb_build_object(r.k, v_fair);
      v_left := v_left - v_fair;
    END IF;
    v_i := v_i + 1;
  END LOOP;
  RETURN v_out;
END
$function$;
REVOKE ALL ON FUNCTION twin.ottoq_sim_dc_pool_shares(jsonb, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_dc_pool_shares(jsonb, numeric) TO service_role;

CREATE OR REPLACE FUNCTION twin.ottoq_sim_dc_pool_plan(p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_seed bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
-- 0726: each active charge's demand computed exactly as twin.ottoq_sim_advance_charge_sessions computes its rate, then
-- bounded by the room left in the pack over this tick (what the step meters), split into fast (shared) and L2 (on the
-- service, not on the DC cabinets); the DC pool; and the fast charges' shares of it. Reads only. Sessions are this run's
-- own active twin sessions, as the step's loop selects them.
DECLARE
  s record; v_depot uuid; v_rate numeric; v_bt numeric; v_amb numeric; v_last timestamptz; v_el numeric;
  v_target numeric; v_room numeric; v_dem numeric;
  v_dc jsonb := '{}'::jsonb; v_dc_sum numeric := 0; v_l2_sum numeric := 0; v_n_dc int := 0;
  v_dc_cap numeric; v_grid_cap numeric; v_bld numeric; v_sol numeric; v_bess numeric; v_room_grid numeric; v_pool numeric;
BEGIN
  SELECT r.depot_id INTO v_depot FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN
    RETURN jsonb_build_object('shares', '{}'::jsonb, 'why', 'no run');
  END IF;

  FOR s IN
    SELECT cs.id, cs.vehicle_id, cs.started_at, cs.ambient_temp_c, cs.soc_start, cs.energy_delivered_kwh,
           cs.last_meter_value, st.stall_type::text AS stall_type, st.ocpp_charger_id,
           v.current_soc, v.battery_capacity_kwh, v.inlet_max_kw, v.target_soc,
           (v.config->>'battery_soh_pct')::numeric AS soh, (v.config->>'charge_curve_scalar')::numeric AS curve_scalar,
           c.max_kw AS charger_kw
      FROM public.ocpp_sessions cs
      JOIN public.stalls st ON st.id = cs.stall_id
      JOIN public.vehicles v ON v.id = cs.vehicle_id
      LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = st.ocpp_charger_id
     WHERE cs.status = 'active' AND cs.id_token LIKE 'TWIN-%'
       AND cs.sim_run_id IS NOT DISTINCT FROM p_sim_run_id
     ORDER BY cs.vehicle_id
  LOOP
    v_last := COALESCE((s.last_meter_value->>'at')::timestamptz, s.started_at);
    v_el := LEAST(EXTRACT(EPOCH FROM (p_sim_clock_now - v_last)) / 60.0, 90);
    IF v_el <= 0 THEN
      CONTINUE;                                   -- the step skips it this tick, so it draws nothing
    END IF;
    v_amb := COALESCE(s.ambient_temp_c, 22);
    v_bt := v_amb + 5
      + twin.ottoq_sim_seeded_random(p_seed, 'btemp:' || s.vehicle_id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, s.started_at)) * 8
      + LEAST(15, EXTRACT(EPOCH FROM (p_sim_clock_now - s.started_at)) / 600.0 * 5);
    v_rate := public.ottoq_sim_compute_charge_rate(
      p_soc_pct := s.current_soc, p_battery_temp_c := v_bt,
      p_ambient_temp_c := v_amb, p_charger_max_kw := s.charger_kw,
      p_vehicle_max_kw := s.inlet_max_kw, p_battery_capacity_kwh := s.battery_capacity_kwh,
      p_battery_soh_pct := COALESCE(s.soh, 95), p_noise_seed := p_seed,
      p_noise_salt := s.vehicle_id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, s.started_at) || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now));
    v_rate := v_rate / GREATEST(0.2, public.ottoq_profile_rate_mult(p_sim_run_id, 'charge_time'));
    v_rate := v_rate * COALESCE(s.curve_scalar, 1.0);
    v_dem := GREATEST(0, COALESCE(v_rate, 0));
    IF COALESCE(s.battery_capacity_kwh, 0) > 0 THEN
      v_target := LEAST(COALESCE(s.target_soc, public.ottoq_default_target_soc()),
                        public.ottoq_target_soc_cap(s.stall_type, s.started_at, p_sim_run_id));
      v_room := GREATEST(0, ((v_target - COALESCE(s.soc_start, s.current_soc, 0)) / 100.0) * s.battery_capacity_kwh
                            - COALESCE(s.energy_delivered_kwh, 0));
      v_dem := LEAST(v_dem, v_room / (v_el / 60.0));
    END IF;
    IF s.stall_type = 'dcfc' THEN
      v_dc := v_dc || jsonb_build_object(s.id::text, round(v_dem, 4));
      v_dc_sum := v_dc_sum + v_dem;
      v_n_dc := v_n_dc + 1;
    ELSE
      v_l2_sum := v_l2_sum + v_dem;
    END IF;
  END LOOP;

  SELECT d.dcfc_max_concurrent_kw INTO v_dc_cap FROM public.depots d WHERE d.id = v_depot;
  -- 0729: under dc_power_managed a site controller holds every charge at the engineering cap EN.001 judges against
  -- (the cabinets' rating less the depot's safety margin), so the fast chargers' share of it is that cap less this
  -- tick's L2, which the rule counts against the same cap
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'dc_power_managed', 0), 0) >= 1 AND v_dc_cap IS NOT NULL THEN
    SELECT GREATEST(0, v_dc_cap * (1 - COALESCE(d.dcfc_safety_margin_pct, 10.0) / 100.0) - v_l2_sum) INTO v_dc_cap
      FROM public.depots d WHERE d.id = v_depot;
  END IF;
  v_grid_cap := public.ottoq_effective_charge_cap_kw(p_sim_run_id, v_depot, p_sim_clock_now);
  SELECT e.building_load_kw, e.solar_generation_kw INTO v_bld, v_sol
    FROM public.site_energy_snapshots e
   WHERE e.depot_id = v_depot AND e.timestamp <= p_sim_clock_now AND e.sim_run_id = p_sim_run_id
   ORDER BY e.timestamp DESC, e.id LIMIT 1;
  SELECT COALESCE(sum(b.current_power_kw), 0) INTO v_bess FROM public.ottoq_bess_units b WHERE b.depot_id = v_depot;
  v_room_grid := CASE WHEN v_grid_cap IS NULL THEN NULL
                      ELSE v_grid_cap - COALESCE(v_bld, 0) + COALESCE(v_sol, 0) - v_bess - v_l2_sum END;
  v_pool := GREATEST(0, LEAST(COALESCE(v_dc_cap, v_room_grid), COALESCE(v_room_grid, v_dc_cap)));

  RETURN jsonb_build_object(
    'pool_kw', round(COALESCE(v_pool, v_dc_sum), 1), 'dc_demand_kw', round(v_dc_sum, 1), 'l2_demand_kw', round(v_l2_sum, 1),
    'dc_cap_kw', v_dc_cap, 'grid_room_kw', round(v_room_grid, 1), 'dc_charges', v_n_dc,
    'binds', v_pool IS NOT NULL AND v_dc_sum > v_pool,
    'shares', CASE WHEN v_pool IS NULL OR v_dc_sum <= v_pool THEN '{}'::jsonb
                   ELSE twin.ottoq_sim_dc_pool_shares(v_dc, v_pool) END);
END
$function$;
REVOKE ALL ON FUNCTION twin.ottoq_sim_dc_pool_plan(uuid, timestamp with time zone, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_dc_pool_plan(uuid, timestamp with time zone, bigint) TO service_role;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0736_a_realistic_promise_at_arrival_and_its_grade', false, false, 'stub: 0736 applied', now());

INSERT INTO public.ottoq_throughput_sweeps (sweep_id, sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, created_at)
VALUES ('607a5b07-252f-45bd-978b-49f2f956a61c', 'value_2026_09_30', 'value night 2', '11111111-1111-1111-1111-111111111111',
        'busy_day', '2026-09-01 11:00:00+00', 288, 5, ARRAY[686364201590009433, 305838298283560562, 1071807412374370855]::bigint[],
        0, 50, NULL, 'active', '2026-09-30 11:54:52.208019+00'),
       ('49a12dfa-d924-4bbe-99bc-ab3d923d4c02', 'dcfc40_managed_normal_2026_10_17', 'arm 85''s sweep',
        '11111111-1111-1111-1111-111111111111', 'normal_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[686364201590009433]::bigint[], 0, 15, 5400, 'active', '2026-10-17 08:15:53.47018+00'),
       ('44543372-a4d5-4e3c-a999-2f5055b7c1ac', 'seeds23_normal_2026_10_17', '0732''s seeds',
        '11111111-1111-1111-1111-111111111111', 'normal_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[305838298283560562, 1071807412374370855]::bigint[], 0, 16, 5400, 'active', '2026-10-17 10:52:50.512279+00');
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
VALUES ('49a12dfa-d924-4bbe-99bc-ab3d923d4c02', 'dcfc40_cab2400.managed', 1, 'otto_q', 'dcfc40_cab2400',
        '{"dc_power_managed": 1, "dc_power_sharing": 1, "deploy_peak_fraction": 0.9, "enforce_site_charge_cap": 0}');

-- two of arm 83's charge sessions, of two cars, for 0737's V2
INSERT INTO public.ocpp_sessions (id, vehicle_id, sim_run_id, status)
VALUES ('5e000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001', 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd', 'completed'),
       ('5e000000-0000-0000-0000-000000000002', 'ca000000-0000-0000-0000-000000000002', 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd', 'completed');
