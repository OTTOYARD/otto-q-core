-- migration-version: PENDING
-- migration-name:    every_charge_and_service_takes_the_time_public_data_says
--
-- 0573  **Every charge and service in the twin takes the time public data says it takes.** Lane A calibration.
--       Chase, 2026-09-29, 8:20 PM CT: "All services take certain amounts of time. You have to calibrate that." The
--       sources, the fits and the confidence of each time are in
--       docs/research/direct/2026-09-30-lane-a-service-time-calibration.md, reproduced by the script beside it.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The charge is the longest step of nearly every visit, and rule 9 charges every car to 100%. So how long a car holds
--   a fast charger, and how many chargers a depot needs, depend on the whole charge curve, the last 20% most of all.
--   `ottoq_sim_compute_charge_rate` gave every car one taper shape, scaled by the car's maximum power: 85-100% of it to
--   20%, a straight line down to 22% at 80%, then to 8% at 100%. Against 99 measured curves (Fastned and InsideEVs,
--   figshare doi:10.6084/m9.figshare.30570653.v1, CC BY 4.0) and EV Database's published times, that shape charges a
--   Tesla Model Y ~15% too fast and a Jaguar I-PACE or a Zoox 22-33% too slowly, counted to 100% (the doc, 2.2 and 2.5).
--   Two vehicle facts were also wrong: the twin's I-PACEs carry a 75 kWh battery (the Benchmark's carry 90, the gross
--   size), where EV Database gives 84.7 kWh usable and 104 kW; and its Zoox carry 135 kWh at 200 kW, where Zoox gives
--   133 kWh and no published charge power (one secondary source gives 100 kW).
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `public.ottoq_sim_compute_charge_rate`, DC branch only, when the caller gives a battery size (every caller does):
--       power = the lowest of the charger's maximum, the car's maximum, and usable kWh x the battery's acceptance at
--       that charge (kW per kWh). The acceptance curve is a table at 0, 5, ..., 100%, interpolated linearly:
--         - Tesla Model Y LR (a car of 250 kW and 75 kWh): its own measured curve to 90%, then the median tail;
--         - Jaguar I-PACE (104 kW and 84.7 kWh): its maximum to 50%, then fitted so 10-80% takes the published 45 min;
--         - every other battery: the median over the 99 measured curves.
--       A battery is recognised by the two numbers every caller already passes (`inlet_max_kw`,
--       `battery_capacity_kwh`); no caller changes. The thermal, state-of-health and noise factors, the L2 branch, the
--       signature and IMMUTABLE are unchanged. A caller with no battery size gets the old shape.
--   (b) Vehicle facts, autonomous cars at the twin depot and at the Benchmark depot (whose cars 0572 lends to the twin
--       for its 150- and 200-car days, so they must be the same models): Waymo I-Pace and Jaguar I-PACE AV to 84.7 kWh
--       and 104 kW (84 cars); Zoox Robotaxi and VH6 to 133 kWh and 100 kW (63 cars). The two classes in
--       `ottoq_vehicle_classes` likewise. Nothing is tested at the Benchmark depot (rule 8). The vehicles trigger
--       records each change as a signed event, 147 of them, filed to no run (measured in the dry run): the audit trail
--       of the calibration itself.
--   (c) Sensor calibration takes 60 minutes, not 30 (floor 30, not 18): `ottoq.ottoq_derive_visit_needs`, one line,
--       and `service_cadence_policy.est_min_default`. Published static calibration takes 30 min to 2 h, 60-90 for a
--       forward camera. It is the one service time besides the charge that sat outside its public range's typical part.
--   Every other service time stays: each sits inside its public range, or no public source exists to move it. The
--   doc labels each with its confidence.
--
-- ══ §3 MEASURED BEFORE APPLYING (the new function in a rolled-back transaction on the live engine, 2026-09-29 8:57 PM
--       CT; 25 C, full health, a 350 kW charger, through ottoq_estimate_charge_minutes itself) ═══════════════════════════
--
--   | battery                         | 10-80% | 80-100% | 20-100% | before, 20-100% |
--   | Model Y LR, 250 kW, 75 kWh      |  29.2  |   27.3  |   54.2  |  46.0           |
--   | I-PACE, 104 kW, 84.7 kWh        |  45.1  |   49.4  |   89.5  | 115.0 (at 75/100)|
--   | Zoox, 100 kW, 133 kWh           |  55.9  |   21.3  |   69.2  | 103.5 (at 135/200)|
--   V1 asserts these exactly.
--
-- ══ §4 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight (0513's probe). P1: no run is live at either depot and no build-out is applied. P2: the rate
--   function is the one measured (md5 20f2d98f41e34238497a5d28304e7004 of its source), the planner's calibration line
--   occurs exactly once, and the two vehicle groups hold 84 and 63 cars. P3: not already applied. Pre-images go to
--   `ottoq_schema_snapshots` as '0573_pre': both functions, and the vehicles' and classes' old facts as table rows.
--   V1: the table in §3. V2: for every L2 input on a grid, and for a DC charge with no battery size, the new function
--   returns exactly what the old one did (the old one is rebuilt from its snapshot under a scratch name, compared and
--   dropped). V3: the vehicles and classes hold the new facts. V4: the planner's new line is present once and the old
--   one is gone; the catalog says 60.
--
-- ══ §5 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE. Every charge in every arm changes length, and the canon day was
--   certified against uncalibrated charges. Night 1's sweep (2026-09-29, 11 PM-6 AM CT) ran before this file and stays in
--   the record as the uncalibrated baseline; the dial restart makes the sweep runner re-run its cells, not mix them.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0573_pre' AND object_kind = 'function';
--   restore the facts from the two 'table_row' snapshots (jsonb arrays of {id, battery_capacity_kwh, inlet_max_kw} and
--   {vehicle_class_code, battery_capacity_kwh, max_charge_rate_kw});
--   UPDATE public.service_cadence_policy SET est_min_default = 30 WHERE svc = 'sensor_calibration';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0573_every_charge_and_service_takes_the_time_public_data_says'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0573 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: no live run where the facts change, and no build-out applied ──
DO $live$
DECLARE t text; v_applied boolean;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE depot_id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
                AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0573 P1: a run is live at the twin or the Benchmark depot';
  END IF;
  -- 0567's charger build-out and 0572's fleet build-out, whichever exist (0572 may land after this file): dynamic, so
  -- an absent table is skipped rather than failing the plan
  FOREACH t IN ARRAY ARRAY['public.ottoq_site_buildout_active', 'public.ottoq_fleet_buildout_active'] LOOP
    IF to_regclass(t) IS NOT NULL THEN
      EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s)', t) INTO v_applied;
      IF v_applied THEN RAISE EXCEPTION '0573 P1: a build-out is applied (%)', t; END IF;
    END IF;
  END LOOP;
END $live$;

-- ── P2: the rate function measured, the planner's line, the vehicle groups ──
DO $premises$
DECLARE v_src text; n int;
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_sim_compute_charge_rate(numeric,numeric,numeric,numeric,numeric,numeric,numeric,bigint,text)'::regprocedure)
     IS DISTINCT FROM '20f2d98f41e34238497a5d28304e7004' THEN
    RAISE EXCEPTION '0573 P2: ottoq_sim_compute_charge_rate is not the function measured on 2026-09-29';
  END IF;
  v_src := pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'::regprocedure);
  n := (length(v_src) - length(replace(v_src, 'v_calib_min := GREATEST(18, round(30 * COALESCE(v_svcspd,1)))::int;', '')))
       / length('v_calib_min := GREATEST(18, round(30 * COALESCE(v_svcspd,1)))::int;');
  IF n <> 1 THEN
    RAISE EXCEPTION '0573 P2: the planner''s sensor-calibration line occurs % times, not 1', n;
  END IF;
  n := (SELECT count(*) FROM public.vehicles
         WHERE category = 'autonomous'
           AND home_depot_id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
           AND ((make = 'Waymo' AND model = 'I-Pace') OR (make = 'Jaguar' AND model = 'I-PACE AV')));
  IF n <> 84 THEN RAISE EXCEPTION '0573 P2: % I-PACE cars at the two depots, not 84', n; END IF;
  n := (SELECT count(*) FROM public.vehicles
         WHERE category = 'autonomous'
           AND home_depot_id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
           AND make = 'Zoox' AND model IN ('Robotaxi', 'VH6'));
  IF n <> 63 THEN RAISE EXCEPTION '0573 P2: % Zoox cars at the two depots, not 63', n; END IF;
  IF (SELECT count(*) FROM public.ottoq_vehicle_classes
       WHERE vehicle_class_code IN ('waymo_jaguar_ipace_2024', 'zoox_robotaxi_2024')) <> 2 THEN
    RAISE EXCEPTION '0573 P2: the two vehicle classes are not both present';
  END IF;
  IF (SELECT est_min_default FROM public.service_cadence_policy WHERE svc = 'sensor_calibration') IS DISTINCT FROM 30 THEN
    RAISE EXCEPTION '0573 P2: the catalog''s sensor calibration is not 30 minutes';
  END IF;
END $premises$;

-- ── P3: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0573_every_charge_and_service_takes_the_time_public_data_says') THEN
    RAISE EXCEPTION '0573 P3: already applied';
  END IF;
END $once$;

-- ── pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0573_pre', 'function', p.pronamespace::regnamespace::text, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p
 WHERE p.oid IN ('public.ottoq_sim_compute_charge_rate(numeric,numeric,numeric,numeric,numeric,numeric,numeric,bigint,text)'::regprocedure,
                 'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'::regprocedure);

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0573_pre', 'table_row', 'public', 'vehicles', d::text, md5(d::text)
  FROM (SELECT jsonb_agg(jsonb_build_object('id', v.id, 'battery_capacity_kwh', v.battery_capacity_kwh,
                                            'inlet_max_kw', v.inlet_max_kw) ORDER BY v.id) AS d
          FROM public.vehicles v
         WHERE v.category = 'autonomous'
           AND v.home_depot_id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
           AND ((v.make = 'Waymo' AND v.model = 'I-Pace') OR (v.make = 'Jaguar' AND v.model = 'I-PACE AV')
                OR (v.make = 'Zoox' AND v.model IN ('Robotaxi', 'VH6')))) x;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0573_pre', 'table_row', 'public', 'ottoq_vehicle_classes', d::text, md5(d::text)
  FROM (SELECT jsonb_agg(jsonb_build_object('vehicle_class_code', c.vehicle_class_code,
                                            'battery_capacity_kwh', c.battery_capacity_kwh,
                                            'max_charge_rate_kw', c.max_charge_rate_kw) ORDER BY c.vehicle_class_code) AS d
          FROM public.ottoq_vehicle_classes c
         WHERE c.vehicle_class_code IN ('waymo_jaguar_ipace_2024', 'zoox_robotaxi_2024')) x;

-- ── (a) the charge rate: a battery's acceptance per kWh, capped by the car and the charger ──
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
  v_accept         NUMERIC[];
  v_soc            NUMERIC;
  v_i              INT;
BEGIN
  v_base_rate := LEAST(p_charger_max_kw, p_vehicle_max_kw);
  IF v_base_rate <= 0 THEN RETURN 0; END IF;
  v_is_dcfc := p_charger_max_kw > 22;

  IF v_is_dcfc AND p_battery_capacity_kwh > 0 THEN
    -- 0573: what the battery accepts, in kW per usable kWh, at 0, 5, ..., 100% charge, capped by the car's and the
    -- charger's maxima. Sources and fits: docs/research/direct/2026-09-30-lane-a-service-time-calibration.md.
    v_accept := CASE
      -- Tesla Model Y Long Range (250 kW, 75 kWh usable): its own measured curve (Fastned, figshare
      -- doi:10.6084/m9.figshare.30570653.v1) to 90%, then the median tail of the 20 curves measured to 98%+
      WHEN p_vehicle_max_kw = 250 AND p_battery_capacity_kwh = 75 THEN
        ARRAY[3.062, 3.062, 2.934, 2.607, 2.428, 2.315, 2.191, 1.953, 1.758, 1.570, 1.404,
              1.244, 1.112, 1.042, 0.971, 0.878, 0.647, 0.593, 0.461, 0.375, 0.219]::numeric[]
      -- Jaguar I-PACE (104 kW, 84.7 kWh usable): its maximum to 50%, then fitted so 10-80% takes EV Database's
      -- published 45 minutes, then the median tail
      WHEN p_vehicle_max_kw = 104 AND p_battery_capacity_kwh = 84.7 THEN
        ARRAY[3.000, 3.000, 3.000, 3.000, 3.000, 3.000, 3.000, 3.000, 3.000, 3.000, 3.000,
              1.079, 0.929, 0.780, 0.631, 0.481, 0.332, 0.309, 0.278, 0.219, 0.103]::numeric[]
      -- every other battery: the median over the dataset's 99 measured curves
      ELSE
        ARRAY[1.906, 1.949, 1.992, 1.991, 1.945, 1.948, 1.855, 1.679, 1.653, 1.581, 1.543,
              1.367, 1.229, 1.121, 1.013, 0.950, 0.790, 0.702, 0.608, 0.484, 0.312]::numeric[]
    END;
    v_soc := LEAST(100, GREATEST(0, COALESCE(p_soc_pct, 100)));
    v_i := LEAST(19, floor(v_soc / 5)::int);
    v_curve_factor := LEAST(1.0, p_battery_capacity_kwh
                                 * (v_accept[v_i + 1] + (v_accept[v_i + 2] - v_accept[v_i + 1]) * (v_soc - 5 * v_i) / 5)
                                 / v_base_rate);
  ELSIF v_is_dcfc THEN
    -- no battery size given: the shape used before 0573
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

-- ── (b) the vehicle facts ──
DO $facts$
DECLARE n int;
BEGIN
  UPDATE public.vehicles
     SET battery_capacity_kwh = 84.7, inlet_max_kw = 104
   WHERE category = 'autonomous'
     AND home_depot_id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
     AND ((make = 'Waymo' AND model = 'I-Pace') OR (make = 'Jaguar' AND model = 'I-PACE AV'));
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 84 THEN RAISE EXCEPTION '0573 (b): % I-PACE cars updated, not 84', n; END IF;

  UPDATE public.vehicles
     SET battery_capacity_kwh = 133, inlet_max_kw = 100
   WHERE category = 'autonomous'
     AND home_depot_id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
     AND make = 'Zoox' AND model IN ('Robotaxi', 'VH6');
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 63 THEN RAISE EXCEPTION '0573 (b): % Zoox cars updated, not 63', n; END IF;

  UPDATE public.ottoq_vehicle_classes
     SET battery_capacity_kwh = CASE vehicle_class_code WHEN 'waymo_jaguar_ipace_2024' THEN 84.7 ELSE 133 END,
         max_charge_rate_kw   = CASE vehicle_class_code WHEN 'waymo_jaguar_ipace_2024' THEN 104 ELSE 100 END
   WHERE vehicle_class_code IN ('waymo_jaguar_ipace_2024', 'zoox_robotaxi_2024');
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 2 THEN RAISE EXCEPTION '0573 (b): % classes updated, not 2', n; END IF;
END $facts$;

-- ── (c) sensor calibration takes 60 minutes ──
DO $calib$
DECLARE v_def text; n int;
  c_old CONSTANT text := 'v_calib_min := GREATEST(18, round(30 * COALESCE(v_svcspd,1)))::int;';
  c_new CONSTANT text := 'v_calib_min := GREATEST(30, round(60 * COALESCE(v_svcspd,1)))::int;  -- 0573: 60 min typical (30-120), public static calibration times';
BEGIN
  v_def := pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0573 (c): the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);

  UPDATE public.service_cadence_policy
     SET est_min_default = 60,
         notes = notes || ' 0573: 60 min typical (30-120), public static calibration times.'
   WHERE svc = 'sensor_calibration' AND est_min_default = 30;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION '0573 (c): % catalog rows updated, not 1', n; END IF;
END $calib$;

-- ── V1: the charge times measured before applying (§3), exactly ──
DO $v1$
DECLARE r record; got numeric;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('Model Y 10-80',  10::numeric,  80::numeric, 250::numeric, 75::numeric,   29.2::numeric),
      ('Model Y 80-100', 80,          100,          250,          75,            27.3),
      ('I-PACE 10-80',   10,           80,          104,          84.7,          45.1),
      ('I-PACE 80-100',  80,          100,          104,          84.7,          49.4),
      ('Zoox 10-80',     10,           80,          100,          133,           55.9),
      ('Zoox 80-100',    80,          100,          100,          133,           21.3)) x(label, s0, s1, vmax, kwh, want)
  LOOP
    got := public.ottoq_estimate_charge_minutes(r.s0, r.s1, 350, r.vmax, r.kwh, 25, 100, 1);
    IF got IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION '0573 V1: % is % minutes, not %', r.label, got, r.want;
    END IF;
  END LOOP;
END $v1$;

-- ── V2: every L2 charge, and a DC charge with no battery size, is exactly what it was ──
DO $v2$
DECLARE v_old text; n bigint;
BEGIN
  SELECT definition INTO v_old FROM public.ottoq_schema_snapshots
   WHERE label = '0573_pre' AND object_kind = 'function' AND object_name = 'ottoq_sim_compute_charge_rate'
   ORDER BY snapshot_id DESC LIMIT 1;
  EXECUTE replace(v_old, 'FUNCTION public.ottoq_sim_compute_charge_rate(', 'FUNCTION public.zz_0573_pre_charge_rate(');
  SELECT count(*) INTO n
    FROM generate_series(0, 100, 5) s(soc)
    CROSS JOIN (VALUES (-5::numeric), (5), (12), (25), (40)) t(temp)
    CROSS JOIN (VALUES (7.2::numeric, 7.4::numeric, 84.7::numeric), (11, 11, 75), (19.2, 11, 133), (22, NULL, 75),
                       (350, 104, NULL), (350, 250, 0), (150, NULL, NULL)) c(charger, vmax, kwh)
   WHERE public.ottoq_sim_compute_charge_rate(s.soc, t.temp, t.temp, c.charger, c.vmax, c.kwh, 95, 7, 'v2')
         IS DISTINCT FROM public.zz_0573_pre_charge_rate(s.soc, t.temp, t.temp, c.charger, c.vmax, c.kwh, 95, 7, 'v2');
  DROP FUNCTION public.zz_0573_pre_charge_rate(numeric, numeric, numeric, numeric, numeric, numeric, numeric, bigint, text);
  IF n <> 0 THEN RAISE EXCEPTION '0573 V2: % L2 or sizeless DC inputs changed', n; END IF;
END $v2$;

-- ── V3: the facts ──
DO $v3$
BEGIN
  IF (SELECT count(*) FROM public.vehicles
       WHERE category = 'autonomous'
         AND home_depot_id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
         AND battery_capacity_kwh = 84.7 AND inlet_max_kw = 104) <> 84
  OR (SELECT count(*) FROM public.vehicles
       WHERE category = 'autonomous'
         AND home_depot_id IN ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222')
         AND battery_capacity_kwh = 133 AND inlet_max_kw = 100) <> 63
  OR (SELECT count(*) FROM public.ottoq_vehicle_classes
       WHERE (vehicle_class_code = 'waymo_jaguar_ipace_2024' AND battery_capacity_kwh = 84.7 AND max_charge_rate_kw = 104)
          OR (vehicle_class_code = 'zoox_robotaxi_2024' AND battery_capacity_kwh = 133 AND max_charge_rate_kw = 100)) <> 2 THEN
    RAISE EXCEPTION '0573 V3: the vehicle or class facts are not the calibrated ones';
  END IF;
END $v3$;

-- ── V4: the planner and the catalog ──
DO $v4$
DECLARE v_src text;
BEGIN
  v_src := (SELECT prosrc FROM pg_proc
             WHERE oid = 'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'::regprocedure);
  IF position('v_calib_min := GREATEST(18, round(30 * COALESCE(v_svcspd,1)))::int;' IN v_src) > 0
     OR (length(v_src) - length(replace(v_src, 'v_calib_min := GREATEST(30, round(60 * COALESCE(v_svcspd,1)))::int;', '')))
        / length('v_calib_min := GREATEST(30, round(60 * COALESCE(v_svcspd,1)))::int;') <> 1 THEN
    RAISE EXCEPTION '0573 V4: the planner''s sensor-calibration line is not the new one, exactly once';
  END IF;
  IF (SELECT est_min_default FROM public.service_cadence_policy WHERE svc = 'sensor_calibration') IS DISTINCT FROM 60 THEN
    RAISE EXCEPTION '0573 V4: the catalog''s sensor calibration is not 60 minutes';
  END IF;
END $v4$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0573_every_charge_and_service_takes_the_time_public_data_says', true, true,
  'Lane A calibration (docs/research/direct/2026-09-30-lane-a-service-time-calibration.md). The DC charge rate is a '
  'battery''s acceptance per usable kWh, capped by the car and the charger: Model Y LR from its measured curve, I-PACE '
  'fitted to EV Database''s 45 min 10-80%, every other battery the median of 99 measured curves. I-PACE cars at the twin '
  'and Benchmark depots to 84.7 kWh / 104 kW, Zoox to 133 kWh / 100 kW, and their classes. Sensor calibration 60 min, '
  'not 30. Every charge in every arm changes length.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
