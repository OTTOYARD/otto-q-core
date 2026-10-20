-- tests/fixtures/robotic_wash_stub.sql: what db/migrations/0746's new functions call, as live, for
-- tests/test_robotic_wash_lanes_sql.py. Loaded after tests/fixtures/agent_charge_order_stub.sql, whose vehicles, stalls,
-- runs, visit needs and policy reader it uses. Read from the live catalog on 2026-10-17 between 7:20 and 7:37 PM CT (the
-- test asserts each md5 of prosrc):
--   public.ottoq_crn_draw(bigint,text,text,integer,bigint) f41569b4
--   public.ottoq_sample_calibrated(text,text,bigint,text) 8e9ac086
--   public.ottoq_twin_deal(uuid,text,text,timestamp with time zone,integer,bigint,text) c1ada6ed
--   twin.ottoq_sim_clock_salt(uuid,timestamp with time zone) 0eef7e15
--   twin.ottoq_sim_service_minutes(uuid,text,numeric) 4b50e2f4
--   twin.ottoq_sim_lane_capacity(uuid,text,integer) ef28379b
--   public.ottoq_depot_staffing_count(uuid,text) b8814784
--   public.ottoq_visit_wants_detail(uuid) 9f34be03
--   public.ottoq_flag_needs_service(jsonb) 4a4b34db
--   public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb) 9e6ca1d9
-- The variability tables carry the live columns the deal reads and writes, the live unique key of a card, and the live
-- catalog rows of wash_time and detail_time (lifespan visit, 0.7-1.3, no calibrated distribution: the live
-- ottoq_calibration_distributions has none for either, so the deal draws uniformly, as here).
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS public.ottoq_variability_catalog (var_key text PRIMARY KEY, domain text, label text, definition text,
  unit text, kind text, knob_types text[], neutral_value numeric, min_value numeric, max_value numeric, step numeric,
  select_options text[], is_primary boolean, wired boolean, generator text, display_order integer,
  created_at timestamptz DEFAULT now(), lifespan text, scope text, redraw_event text);
INSERT INTO public.ottoq_variability_catalog (var_key, domain, label, definition, unit, kind, neutral_value, min_value,
                                              max_value, step, lifespan, scope, redraw_event)
VALUES ('wash_time', 'operations', 'Wash duration', 'Exterior-wash duration factor.', '×', 'continuous', 1, 0.7, 1.3, 0.1,
        'visit', 'vehicle', 'service_start'),
       ('detail_time', 'operations', 'Detail duration', 'Interior-detail duration factor.', '×', 'continuous', 1, 0.7, 1.3,
        0.1, 'visit', 'vehicle', 'service_start')
ON CONFLICT (var_key) DO NOTHING;
CREATE TABLE IF NOT EXISTS public.ottoq_variability_cards (id bigserial PRIMARY KEY, sim_run_id uuid, var_key text,
  scope_instance text, lifespan text, bucket_key text, value numeric, meta jsonb, active boolean DEFAULT true,
  drawn_at_clock timestamptz, drawn_at_tick bigint, created_at timestamptz DEFAULT now());
CREATE UNIQUE INDEX IF NOT EXISTS ux_vcards_epoch ON public.ottoq_variability_cards USING btree (sim_run_id, var_key, scope_instance, bucket_key);
CREATE TABLE IF NOT EXISTS public.ottoq_calibration_distributions (distribution_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dataset_code text, variable_name text, segment text, quantile_grid numeric[], sample_count bigint, mean_value numeric,
  stddev_value numeric, min_value numeric, max_value numeric, median_value numeric, best_fit_family text,
  best_fit_parameters jsonb, goodness_of_fit jsonb, units text, hard_min numeric, hard_max numeric, fitted_at timestamptz);
CREATE TABLE IF NOT EXISTS public.ottoq_variability_profiles (profile_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sim_run_id uuid UNIQUE, name text UNIQUE, knobs jsonb, notes text, created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS public.ottoq_depot_staffing (depot_id uuid, role text, headcount integer, notes text,
  updated_at timestamptz DEFAULT now(), PRIMARY KEY (depot_id, role));

-- live: public.ottoq_crn_draw(bigint,text,text,integer,bigint) (prosrc md5 f41569b4516d943dcaced5745e62c57b)
CREATE OR REPLACE FUNCTION public.ottoq_crn_draw(p_run_seed bigint, p_stream text, p_slot_key text, p_sim_day integer DEFAULT 0, p_tick bigint DEFAULT 0)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- hashtextextended gives a stable 64-bit hash; map to [0,1). The seed is the salt
  -- so different A/B seeds → different worlds, same seed → identical exogenous draws.
  SELECT (abs(hashtextextended(
            p_stream || '|' || p_slot_key || '|' || p_sim_day::text || '|' || p_tick::text,
            p_run_seed)) % 1000000000)::double precision / 1000000000.0;
$function$;

-- live: public.ottoq_sample_calibrated(text,text,bigint,text) (prosrc md5 8e9ac0861143cb73a78e8290f2ed4480)
CREATE OR REPLACE FUNCTION public.ottoq_sample_calibrated(p_variable_name text, p_segment text DEFAULT 'global'::text, p_seed bigint DEFAULT 42, p_salt text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_dist        ottoq_calibration_distributions%ROWTYPE;
  v_u           NUMERIC;
  v_pos         NUMERIC;
  v_idx_low     INTEGER;
  v_idx_high    INTEGER;
  v_frac        NUMERIC;
  v_val_low     NUMERIC;
  v_val_high    NUMERIC;
  v_result      NUMERIC;
  v_salt        TEXT;
BEGIN
  v_salt := COALESCE(p_salt, p_variable_name || ':' || p_segment);

  -- 1. Resolve distribution (exact segment, then 'global' fallback)
  SELECT * INTO v_dist
    FROM ottoq_calibration_distributions
   WHERE variable_name = p_variable_name
     AND segment = p_segment
   LIMIT 1;

  IF NOT FOUND THEN
    SELECT * INTO v_dist
      FROM ottoq_calibration_distributions
     WHERE variable_name = p_variable_name
       AND segment = 'global'
     LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    -- No calibration data for this variable — return NULL so the caller
    -- knows to fall back (and ideally logs a calibration gap).
    RETURN NULL;
  END IF;

  -- 2. Deterministic uniform draw
  v_u := ottoq_sim_seeded_random(p_seed, v_salt);

  -- 3. Map onto the 101-point quantile grid (indices 1..101 in PG arrays)
  v_pos      := v_u * 100.0;            -- 0..100
  v_idx_low  := floor(v_pos)::INTEGER;  -- 0..100
  v_idx_high := LEAST(v_idx_low + 1, 100);
  v_frac     := v_pos - v_idx_low;

  v_val_low  := v_dist.quantile_grid[v_idx_low + 1];   -- PG arrays 1-indexed
  v_val_high := v_dist.quantile_grid[v_idx_high + 1];
  v_result   := v_val_low + (v_val_high - v_val_low) * v_frac;

  -- 4. Clamp to physical bounds
  IF v_dist.hard_min IS NOT NULL THEN v_result := GREATEST(v_result, v_dist.hard_min); END IF;
  IF v_dist.hard_max IS NOT NULL THEN v_result := LEAST(v_result, v_dist.hard_max); END IF;

  RETURN v_result;
END;
$function$;

-- live: public.ottoq_twin_deal(uuid,text,text,timestamp with time zone,integer,bigint,text) (prosrc md5 c1ada6eddbb0474e0c1325862fab8d04)
CREATE OR REPLACE FUNCTION public.ottoq_twin_deal(p_run_id uuid, p_var_key text, p_scope_instance text, p_sim_clock timestamp with time zone, p_sim_day integer DEFAULT 0, p_tick bigint DEFAULT 0, p_segment text DEFAULT 'global'::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_lifespan text; v_min numeric; v_max numeric;
  v_seed bigint; v_bucket text; v_val numeric; v_salt text;
  v_block_hrs constant int := 4;
BEGIN
  SELECT lifespan, min_value, max_value INTO v_lifespan, v_min, v_max
    FROM ottoq_variability_catalog WHERE var_key = p_var_key;
  IF v_lifespan IS NULL THEN RETURN NULL; END IF;           -- unknown variable

  SELECT COALESCE(random_seed, 42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = p_run_id;
  v_seed := COALESCE(v_seed, 42);

  -- the lifespan epoch (when a fresh card is dealt)
  v_bucket := CASE v_lifespan
    WHEN 'run'   THEN 'run'
    WHEN 'day'   THEN 'day:' || p_sim_day
    WHEN 'block' THEN 'block:' || p_sim_day || ':' || (EXTRACT(HOUR FROM p_sim_clock)::int / v_block_hrs)
    ELSE v_lifespan || ':' || p_scope_instance              -- session/arrival/visit/trip/event: instance = epoch
  END;

  SELECT value INTO v_val FROM ottoq_variability_cards
   WHERE sim_run_id = p_run_id AND var_key = p_var_key
     AND scope_instance = p_scope_instance AND bucket_key = v_bucket;
  IF FOUND THEN RETURN v_val; END IF;                       -- card still valid → hold it

  -- deal a fresh card: calibrated draw where a fitted distribution exists, else uniform over bounds
  v_salt := p_var_key || '|' || p_scope_instance || '|' || v_bucket;
  v_val := ottoq_sample_calibrated(p_var_key, p_segment, v_seed, v_salt);
  IF v_val IS NULL THEN
    v_val := COALESCE(v_min,0)
           + ottoq_crn_draw(v_seed, p_var_key, v_bucket, p_sim_day, 0)
             * (COALESCE(v_max,1) - COALESCE(v_min,0));
  END IF;

  UPDATE ottoq_variability_cards SET active = false
    WHERE sim_run_id = p_run_id AND var_key = p_var_key AND scope_instance = p_scope_instance AND active;
  INSERT INTO ottoq_variability_cards(sim_run_id, var_key, scope_instance, lifespan, bucket_key, value, drawn_at_clock, drawn_at_tick)
    VALUES (p_run_id, p_var_key, p_scope_instance, v_lifespan, v_bucket, v_val, p_sim_clock, p_tick)
    ON CONFLICT (sim_run_id, var_key, scope_instance, bucket_key) DO UPDATE SET active = true
    RETURNING value INTO v_val;
  RETURN v_val;
END $function$;

-- live: twin.ottoq_sim_clock_salt(uuid,timestamp with time zone) (prosrc md5 0eef7e15309ba4c7546201e82d36e452)
CREATE OR REPLACE FUNCTION twin.ottoq_sim_clock_salt(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- Whole seconds since the run''s own sim_clock_start: pure function of
  -- (run, sim clock), identical across same-seed runs regardless of the wall
  -- clock at start. Falls back to the absolute text (the old behavior) only
  -- when the run row is unknown, so nothing regresses on edge paths.
  SELECT COALESCE(
    (SELECT floor(EXTRACT(EPOCH FROM (p_clock - r.sim_clock_start)))::text
       FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id),
    p_clock::text);
$function$;

-- live: twin.ottoq_sim_service_minutes(uuid,text,numeric) (prosrc md5 4b50e2f4d1dc4c7bfcd54dd92b65b99c)
CREATE OR REPLACE FUNCTION twin.ottoq_sim_service_minutes(p_sim_run_id uuid, p_time_key text, p_base_min numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_knobs JSONB; v_m NUMERIC;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN p_base_min; END IF;
  SELECT knobs INTO v_knobs FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id;
  v_m := COALESCE((v_knobs #>> ARRAY['_rates', p_time_key])::numeric, 1);
  RETURN GREATEST(1, p_base_min * v_m);
END;
$function$;

-- live: twin.ottoq_sim_lane_capacity(uuid,text,integer) (prosrc md5 ef28379b407a30e118837a3b6cb618e4)
CREATE OR REPLACE FUNCTION twin.ottoq_sim_lane_capacity(p_sim_run_id uuid, p_lane_staff_key text, p_physical integer)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_knobs   JSONB;
  v_master  NUMERIC;
  v_lane    NUMERIC;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN p_physical; END IF;
  SELECT knobs INTO v_knobs FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id;
  IF v_knobs IS NULL THEN RETURN p_physical; END IF;
  v_master := COALESCE((v_knobs #>> ARRAY['_rates','staffing_level'])::numeric, 1);
  v_lane   := COALESCE((v_knobs #>> ARRAY['_rates', p_lane_staff_key])::numeric, 1);
  -- Any positive staffing keeps at least ONE lane open (understaffing slows the
  -- flow + grows staging; it never fully gridlocks). Zero staffing = closed.
  IF v_master * v_lane <= 0 THEN RETURN 0; END IF;
  RETURN GREATEST(1, FLOOR(p_physical * v_master * v_lane))::int;
END;
$function$;

-- live: public.ottoq_depot_staffing_count(uuid,text) (prosrc md5 b8814784deaea5ef2121f7bb6632dcc9)
CREATE OR REPLACE FUNCTION public.ottoq_depot_staffing_count(p_depot_id uuid, p_role text)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE((SELECT headcount FROM ottoq_depot_staffing
                    WHERE depot_id = p_depot_id AND role = p_role),
                  CASE p_role WHEN 'general_tech' THEN 10
                              WHEN 'wash_supervisor' THEN 2
                              WHEN 'service_tech' THEN 3 ELSE 1 END);
$function$;

-- live: public.ottoq_visit_wants_detail(uuid) (prosrc md5 9f34be03a1e76e53a2a4be2ad03da1a5)
CREATE OR REPLACE FUNCTION public.ottoq_visit_wants_detail(p_vehicle uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
    WHERE vn.vehicle_id = p_vehicle AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = 'running' AND r0.depot_id = vn.depot_id ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
      AND a->>'svc' = 'interior_deep_clean' AND COALESCE(a->>'status','pending') <> 'done');
$function$;

-- live: public.ottoq_flag_needs_service(jsonb) (prosrc md5 4a4b34dbc25397403462a492c1827546)
CREATE OR REPLACE FUNCTION public.ottoq_flag_needs_service(p_config jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
  -- 0556 (G289): a technician flag (config.flagged_issue) is service-bay work, unless the readiness gate raised it for a
  -- car that waited too long (deploy_gate_stuck, deploy_gate_hard_cap). That flag is a note for a person, not work.
  SELECT COALESCE((p_config->>'flagged_issue')::boolean, false)
     AND COALESCE(p_config->>'flagged_issue_type', '') NOT IN ('deploy_gate_stuck', 'deploy_gate_hard_cap')
$function$;

-- live: public.ottoq_l2_propose_charge_disposition(uuid,uuid,jsonb) (prosrc md5 9e6ca1d95a3053ce4f50901cb723c0d5)
CREATE OR REPLACE FUNCTION public.ottoq_l2_propose_charge_disposition(p_vehicle_id uuid, p_depot_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_in_wash int; v_wash_cap int; v_phys int; v_run uuid;
  v_needs_wash boolean; v_wants_detail boolean; v_flagged boolean; v_needs_service boolean;
BEGIN
  -- SERVICE-NEED GATE (2026-08-01). This proposer used to be NEED-BLIND: it admitted
  -- ANY vehicle leaving charge into the wash lane whenever the lane was not full.
  -- Measured on run 274389e1-0b5e-4c14-936e-12b1e6000c60: 18 of 18 engine wash
  -- admissions had NO exterior_wash and NO interior_deep_clean atom anywhere in their
  -- visit. The twin's own admitter (twin.ottoq_sim_advance_service_flow STEP 2, tag
  -- M1_need_gated_wash) IS need-gated, so two writers disagreed and OTTO-Q was the
  -- dumber one. The predicate and the capacity rule below are the twin's, verbatim.

  -- Resolve the run so the staffing knobs actually apply. The old code passed NULL and
  -- ottoq_sim_lane_capacity returns p_physical unchanged on NULL => the staffing slider
  -- was silently dead on this lane.
  v_run := NULLIF(p_context->>'sim_run_id','')::uuid;
  IF v_run IS NULL THEN
    SELECT r.sim_run_id INTO v_run FROM ottoq_sim_runs r
     WHERE r.depot_id = p_depot_id AND r.ended_at IS NULL
     ORDER BY r.started_at DESC LIMIT 1;
  END IF;

  -- physical wash bays are REAL here (3 seeded); the old comment claiming none was wrong.
  SELECT count(*) INTO v_phys FROM stalls s
   WHERE s.depot_id = p_depot_id AND s.stall_type = 'wash_bay'::stall_type;
  v_phys := COALESCE(NULLIF(v_phys,0), 3);
  -- wash_supervisor_pool: same LEAST(lane, supervisors) rule the twin's STEP 2 uses.
  v_wash_cap := LEAST(ottoq_sim_lane_capacity(v_run, 'cleaning_staff', v_phys),
                      ottoq_depot_staffing_count(p_depot_id, 'wash_supervisor'));

  SELECT COALESCE(v.config->>'flagged_issue_type','') IN ('minor_cosmetic','wash_due')
    INTO v_flagged FROM vehicles v WHERE v.id = p_vehicle_id;
  v_flagged := COALESCE(v_flagged, false);

  v_needs_wash := v_flagged OR EXISTS (
      SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
       WHERE n.vehicle_id = p_vehicle_id AND n.status IN ('open','in_progress') AND COALESCE(n.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = 'running' AND r0.depot_id = p_depot_id ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
         AND a->>'svc' IN ('exterior_wash','interior_deep_clean')
         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'));

  SELECT count(*) INTO v_in_wash FROM vehicles
   WHERE home_depot_id = p_depot_id AND current_state IN ('in_wash_bay','in_detail_bay');

  IF v_needs_wash THEN
    IF v_in_wash < v_wash_cap THEN
      v_wants_detail := v_flagged OR ottoq_visit_wants_detail(p_vehicle_id);
      RETURN jsonb_build_object('abstain', false, 'resolved_action_context','task_start',
        'verb','admit_wash', 'vehicle_id', p_vehicle_id, 'requested_kw', 0,
        'bay_kind', CASE WHEN v_wants_detail THEN 'detail' ELSE 'wash' END,
        'rationale', jsonb_build_object('in_wash', v_in_wash, 'wash_cap', v_wash_cap,
                                        'need', 'wash_atom_outstanding', 'flagged', v_flagged));
    END IF;
    -- unchanged from today: genuine need + full lane => hold in charge_complete_holding
    RETURN jsonb_build_object('abstain', true, 'reason', 'wash_lane_full_hold',
      'rationale', jsonb_build_object('in_wash', v_in_wash, 'wash_cap', v_wash_cap));
  END IF;

  -- NO wash/detail work outstanding. Do NOT spend one of 3 scarce bays on a clean car.
  -- Advance it inside the SAME atomic visit to whatever it does still need.
  v_needs_service := EXISTS (
      SELECT 1 FROM ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
       WHERE n.vehicle_id = p_vehicle_id AND n.status IN ('open','in_progress') AND COALESCE(n.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = 'running' AND r0.depot_id = p_depot_id ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
         AND a->>'svc' IN ('mechanical_pm','sensor_calibration','cosmetic_repair','fault_repair')
         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
    -- 0556 (G289): a technician flag routes to the service bay, but not the readiness gate's own
    OR COALESCE((SELECT public.ottoq_flag_needs_service(v.config) FROM vehicles v WHERE v.id = p_vehicle_id), false);

  RETURN jsonb_build_object('abstain', false, 'resolved_action_context','task_start',
    'verb','skip_wash', 'vehicle_id', p_vehicle_id, 'requested_kw', 0,
    'next_step', CASE WHEN v_needs_service THEN 'need_service' ELSE 'need_deploy' END,
    'rationale', jsonb_build_object('need','no_wash_outstanding', 'wash_cap', v_wash_cap,
                                    'routes_to_service', v_needs_service));
END;
$function$;

