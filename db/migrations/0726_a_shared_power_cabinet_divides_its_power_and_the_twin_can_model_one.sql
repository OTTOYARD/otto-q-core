-- migration-version: PENDING
-- migration-name:    a_shared_power_cabinet_divides_its_power_and_the_twin_can_model_one
--
-- 0726  **A shared power cabinet divides its power, and the twin can now model one.** A test day whose build-out puts
--       many robotic fast chargers on a smaller pool of power can turn on `dc_power_sharing`, and the twin then divides
--       the pool between the fast charges under way, as the cabinets such a site is built from do. Off by default: with
--       the dial at 0 every charge draws exactly what it drew before. Research wing, rule 10.
--
-- ══ §1 WHY (db/checks/0451 §2) ═════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-17, 12:49 AM CT, on converting every L2 space to a robotic fast charger: "Only worry would be, with
--   the maximum energy capacity ... with that much DC FC going on at one time, there might be massive megawatt usage."
--   A site of that kind is built from shared cabinets: ABB's Terra HP pair charges "two vehicles simultaneously at up to
--   175kW" (0567's source), and Kempower's power unit, 200-600 kW, "dynamically shares power across every connected
--   Satellite" for up to 12 charging points (https://kempower.com/solution/kempower-power-unit/, read 2026-10-17). The
--   twin cannot express that. twin.ottoq_sim_advance_charge_sessions charges every session at the lowest of the
--   charger's, the car's and the battery's limit, so dcfc_max_concurrent_kw is reported and never enforced; the site's
--   service limit binds only when ottoq_decide_tick (0132) defers a charge at admission, on an estimate a median 1.50x
--   the metered power (0451 §2 (d)) and outside a demand-response call with no credit for the 3,000 kWh battery. So 0724's
--   dcfc40_grid_today measures 40 chargers whose cars wait to start, judged by an over-count, while its cabinets may run
--   past their 1,800 kW. Neither a real shared site nor a bound on one.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The dial `dc_power_sharing`, catalogued 0..1, default 0, not agent-writable, read per run.
--   (b) twin.ottoq_sim_dc_pool_shares(demand jsonb, pool numeric): the pool divided max-min fairly (water-filling). A
--       charge that wants less than an equal share gets all it wants, and what it leaves is divided among the rest.
--       Pure and IMMUTABLE; the order of the keys never matters.
--   (c) twin.ottoq_sim_dc_pool_plan(run, clock, seed): each active charge's demand this tick, computed exactly as the
--       charge step computes its rate (the same vehicle facts, charger, battery temperature draw, rate function, the
--       profile's charge-time multiplier and the car's curve scalar), bounded by the room left in the pack over this
--       tick, which is what the step meters; then the DC pool, the lowest of
--         - dcfc_max_concurrent_kw (the cabinets), and
--         - the grid limit (ottoq_effective_charge_cap_kw: the service, or a demand-response cap on grid import)
--           minus the building's load and plus the sun's output at the run's latest site snapshot, minus the battery's
--           power this tick (positive charging, negative discharging, as the site balance counts it), minus the L2
--           charges' demand (they share the service but not the DC cabinets);
--       floored at 0; and the fast charges' shares of it. When the fast charges want more than the pool it records one
--       `twin.dc_pool_shared` event (info) with the pool, the demand and the count, so an arm shows how often power
--       was the limit.
--   (d) twin.ottoq_sim_advance_charge_sessions, three anchored insertions and nothing else: two variables; before the
--       loop, the plan when the run's dial is 1 (a failure is warned and leaves every charge unshared); and after the
--       car's curve scalar, a fast charge's rate is the lower of its own and its share. The rate is the only thing that
--       changes. The target, the room in the pack, the fault card and every stop are untouched: a shared charge runs
--       slower and still runs to its target (rule 9). Sharing is a property of the hardware a test day builds, never a
--       decision about a car.
--   Not changed: the admission gate. A sharing test day sets `enforce_site_charge_cap` 0 (catalogued since 0286) in its
--   own dials, because a shared cabinet does not refuse a car, it divides its power; the next file's cells do.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the charge step is the body read on 2026-10-17 (prosrc md5 4ca5ac21...); the dial is not
--   catalogued; no scope row sets it. Pre-image to ottoq_schema_snapshots as '0726_pre'. V1: the water-filling on known
--   cases, and on a pool larger than the demand. V2: THE DIAL-OFF PATH IS THE OLD PATH: the stored body with the three
--   0726 insertions removed is byte for byte the pre-image (md5 4ca5ac21...). V3: the dial is catalogued 0..1 default 0,
--   no row sets it, and the helpers carry the charge step's grants (postgres and service_role).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. With the dial at 0 (every canon cell, every run that does not set
--   it) the step reads one dial a tick and computes what it computed before; V2 proves the rest of the body unchanged.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0726_pre' AND object_kind = 'function';
--   DROP FUNCTION twin.ottoq_sim_dc_pool_plan(uuid, timestamptz, bigint), twin.ottoq_sim_dc_pool_shares(jsonb, numeric);
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_sharing';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0726_a_shared_power_cabinet_divides_its_power_and_the_twin_can_model_one'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0726 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the body read, the dial absent ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_sim_advance_charge_sessions(uuid,timestamp with time zone)'))
     IS DISTINCT FROM '4ca5ac211e7fd28a3bba9e6ebefca00e' THEN
    RAISE EXCEPTION '0726 P1: twin.ottoq_sim_advance_charge_sessions is not the body read on 2026-10-17 (md5 4ca5ac21)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_sharing')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'dc_power_sharing') THEN
    RAISE EXCEPTION '0726 P1: dc_power_sharing already exists';
  END IF;
END $premises$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0726_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_advance_charge_sessions(uuid,timestamp with time zone)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('dc_power_sharing',
        '0726: the test day''s fast chargers share one DC power pool, as a shared-cabinet site''s do. 1 = the twin '
        'divides the lowest of dcfc_max_concurrent_kw and the grid''s room (the service or a demand-response cap, less '
        'the building and the battery''s charging, plus the sun and the battery''s discharge, less the L2 charges) between '
        'the fast charges under way, max-min fairly; a charge runs slower and still runs to its target. 0 = every charge '
        'at its own physical rate (the twin before 0726). A property of the hardware a build-out models, never a decision '
        'about a car: research days only.',
        0, 0, 1, 'twin.ottoq_sim_advance_charge_sessions', false);

-- ── (b) the pool, divided max-min fairly ──
CREATE OR REPLACE FUNCTION twin.ottoq_sim_dc_pool_shares(p_demand jsonb, p_pool_kw numeric)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
SET search_path = twin, ottoq, public, extensions
AS $fn$
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
$fn$;

-- ── (c) this tick's demand, the pool, and the shares ──
CREATE OR REPLACE FUNCTION twin.ottoq_sim_dc_pool_plan(p_sim_run_id uuid, p_sim_clock_now timestamptz, p_seed bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path = twin, ottoq, public, extensions
AS $fn$
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
$fn$;

REVOKE ALL ON FUNCTION twin.ottoq_sim_dc_pool_shares(jsonb, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION twin.ottoq_sim_dc_pool_plan(uuid, timestamptz, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_dc_pool_shares(jsonb, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_dc_pool_plan(uuid, timestamptz, bigint) TO service_role;

-- ══ (d) the charge step: three anchored insertions, each anchor once ════════════════════════════════════════════════════
CREATE TEMP TABLE _0726_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0726_patch VALUES
(1,
$old$  v_seed          BIGINT;
BEGIN
$old$,
$new$  v_seed          BIGINT;
  v_share_on      BOOLEAN := false;            -- 0726
  v_share         JSONB := '{}'::jsonb;        -- 0726
BEGIN
$new$),
(2,
$old$  FOR v_session IN
    SELECT s.*, st.ocpp_charger_id, st.stall_type
$old$,
$new$  -- 0726: A SHARED DC POWER POOL, WHEN THE TEST DAY BUILDS ONE (dial dc_power_sharing, default 0). The cabinets of a
  -- shared-cabinet site divide their power between the cars on them; the doctrine above is unchanged by it, because a
  -- share is the hardware's limit, never a decision about a car, and a shared charge still runs to its target. Off, this
  -- reads one dial and nothing else changes.
  v_share_on := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'dc_power_sharing', 0), 0) >= 1;
  IF v_share_on THEN
    BEGIN
      v_share := twin.ottoq_sim_dc_pool_plan(p_sim_run_id, p_sim_clock_now, v_seed);
      IF COALESCE((v_share->>'binds')::boolean, false) THEN
        PERFORM ottoq_record_event(
          p_actor_type:='ottoq_engine', p_actor_id:='twin_dc_pool',
          p_event_type:='twin.dc_pool_shared', p_entity_type:='depot',
          p_entity_id:=(SELECT r.depot_id FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id),
          p_payload:=v_share - 'shares',
          p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
      END IF;
      v_share := COALESCE(v_share->'shares', '{}'::jsonb);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0726 dc pool plan: % %', SQLSTATE, SQLERRM;
      v_share := '{}'::jsonb;
    END;
  END IF;

  FOR v_session IN
    SELECT s.*, st.ocpp_charger_id, st.stall_type
$new$),
(3,
$old$    v_rate_kw := v_rate_kw * COALESCE(v_vehicle.curve_scalar, 1.0);
$old$,
$new$    v_rate_kw := v_rate_kw * COALESCE(v_vehicle.curve_scalar, 1.0);
    -- 0726: under a shared DC pool a fast charge draws no more than its share this tick; its target is unchanged
    IF v_share_on AND v_session.stall_type::text = 'dcfc' AND v_share ? v_session.id::text THEN
      v_rate_kw := LEAST(v_rate_kw, (v_share->>v_session.id::text)::numeric);
    END IF;
$new$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_charge_sessions(uuid,timestamp with time zone)'::regprocedure);
  FOR p IN SELECT * FROM _0726_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0726 (d): anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('twin.ottoq_sim_advance_charge_sessions(uuid,timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0726 (d): the charge step is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the water-filling ──
DO $v1$
DECLARE v jsonb;
BEGIN
  v := twin.ottoq_sim_dc_pool_shares('{"a": 100, "b": 100, "c": 250}'::jsonb, 300);
  IF (v->>'a')::numeric <> 100 OR (v->>'b')::numeric <> 100 OR (v->>'c')::numeric <> 100 THEN
    RAISE EXCEPTION '0726 V1: {100,100,250} into 300 gave %', v;
  END IF;
  v := twin.ottoq_sim_dc_pool_shares('{"a": 50, "b": 200, "c": 200}'::jsonb, 300);
  IF (v->>'a')::numeric <> 50 OR (v->>'b')::numeric <> 125 OR (v->>'c')::numeric <> 125 THEN
    RAISE EXCEPTION '0726 V1: {50,200,200} into 300 gave %', v;
  END IF;
  v := twin.ottoq_sim_dc_pool_shares('{"z": 200, "y": 50, "x": 200}'::jsonb, 300);   -- key order cannot matter
  IF (v->>'y')::numeric <> 50 OR (v->>'x')::numeric <> 125 OR (v->>'z')::numeric <> 125 THEN
    RAISE EXCEPTION '0726 V1: key order changed a share: %', v;
  END IF;
  v := twin.ottoq_sim_dc_pool_shares('{"a": 40, "b": 60}'::jsonb, 1000);             -- room for everyone
  IF (v->>'a')::numeric <> 40 OR (v->>'b')::numeric <> 60 THEN
    RAISE EXCEPTION '0726 V1: a pool larger than the demand cut a charge: %', v;
  END IF;
  v := twin.ottoq_sim_dc_pool_shares('{"a": 40, "b": 60}'::jsonb, 0);
  IF (v->>'a')::numeric <> 0 OR (v->>'b')::numeric <> 0 THEN
    RAISE EXCEPTION '0726 V1: an empty pool gave power: %', v;
  END IF;
  IF twin.ottoq_sim_dc_pool_shares('{}'::jsonb, 100) <> '{}'::jsonb THEN
    RAISE EXCEPTION '0726 V1: no charges should give no shares';
  END IF;
END $v1$;

-- ── V2: the dial-off path is the old path: the stored body less the three insertions is the pre-image ──
DO $v2$
DECLARE p record; v_body text;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'twin.ottoq_sim_advance_charge_sessions(uuid,timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0726_patch ORDER BY seq LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '4ca5ac211e7fd28a3bba9e6ebefca00e' THEN
    RAISE EXCEPTION '0726 V2: the charge step less the 0726 insertions is not the pre-image (md5 %)', md5(v_body);
  END IF;
END $v2$;

-- ── V3: the dial and the grants ──
DO $v3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_sharing'
                  AND default_value = 0 AND min_value = 0 AND max_value = 1 AND NOT agent_writable) THEN
    RAISE EXCEPTION '0726 V3: dc_power_sharing is not catalogued 0..1 default 0, not agent-writable';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'dc_power_sharing') THEN
    RAISE EXCEPTION '0726 V3: a scope row sets dc_power_sharing; only a test day''s own dials may';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_dc_pool_plan(uuid,timestamp with time zone,bigint)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'twin.ottoq_sim_dc_pool_shares(jsonb,numeric)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'twin.ottoq_sim_dc_pool_plan(uuid,timestamp with time zone,bigint)', 'EXECUTE') THEN
    RAISE EXCEPTION '0726 V3: the helpers'' grants are not postgres and service_role only';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0726_a_shared_power_cabinet_divides_its_power_and_the_twin_can_model_one', false, false,
  'Dial dc_power_sharing (default 0) and two twin helpers; the charge step gains three insertions that act only when a '
  'run sets the dial: a fast charge then draws no more than its max-min fair share of the DC pool. V2 proves the body '
  'less the insertions is the pre-image, so every run at 0 computes what it computed before.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
