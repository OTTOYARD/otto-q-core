-- ============================================================================
-- 0018_rider_flagged_cleaning_recall.sql
--
-- TWO CLEANING VARIABILITIES, BOTH DRAWN PER RUN FROM THE SEED.
--
-- The founder's rule, verbatim intent:
--   "vehicles should get BOTH each simulation run: a random probability that it
--    needs a daytime cleaning during an OTTO-Q service flow, and the regular
--    every-third-night external cleaning... Both variabilities are selected and
--    determined at the start of any given simulation run. Randomized each time."
--
-- PATH 1 -- SCHEDULED NIGHTLY WASH. The gate in
--   twin.ottoq_sim_generate_service_manifest is
--     (v_is_night AND wash_group = sim_day % 3) OR soil >= 0.75 OR cycles >= 9
--   That gate is CORRECT -- a real depot batches washes overnight -- and this
--   migration DOES NOT TOUCH IT. What was wrong is the *group*: measured on the
--   live database, all 216 active autonomous vehicles already carry
--   config.wash_group, and the fallback is
--     (abs(hashtextextended(vehicle_id::text, 77)) % 3)
--   Neither branch involves random_seed. The rotation was therefore IDENTICAL in
--   every run for all time -- the exact opposite of "randomized each time".
--   Fix: draw wash_group per run from the seed inside the existing run-start draw
--   (public.ottoq_run_boot_draw), writing the same vehicles.config key the three
--   existing readers already read. Zero reader edits; the gate is unchanged.
--
--   The three readers, verified by reading their live definitions:
--     twin.ottoq_sim_generate_service_manifest  (the wash gate)
--     public.ottoq_evaluate_return_need         (v_has_service_need)
--     public.ottoq_evaluate_return_need         (the wash_cadence rung)
--
-- PATH 2 -- RIDER-FLAGGED CLEANING RECALL. New. An AV ridehail rider flags a
--   vehicle mid-deployment for a cleaning issue; the vehicle is recalled to the
--   depot IMMEDIATELY, not at its next natural return, and a wash bay is held for
--   it. Drawn at run start, per vehicle, from the seed -- the same machinery as
--   every other per-vehicle variable.
--
--   The recall path already exists and is used verbatim:
--   ottoq_vehicle_dispatches.return_trigger is open text, and
--   public.ottoq_evaluate_return_need already emits 'sensor_soil' as a
--   mid-deployment soil-triggered early return. 'rider_flag_cleaning' is modelled
--   on it, but non-deferrable, because the founder's rule is "immediately".
--
-- WHAT IS DELIBERATELY NOT DONE
--   * The night wash gate is not opened, loosened, or made probabilistic.
--   * No new PRNG. Everything routes through twin.ottoq_sim_seeded_random.
--   * No density is stacked on the manifest probabilities (busy_day's
--     pm_km_scale 0.010 / calib_h_scale 0.02 already crush pm_interval_km
--     8000->80 and calib_interval_h 250->5; that, not probability, is what makes
--     today's mechanical_pm share, and adding on top of it would double-count).
--
-- MEASURED PRE-STATE (live DB, 2026-08-07)
--   vehicles with config.wash_group ................ 216 of 216 (all stable)
--   stalls at OTTOYARD Nashville Flagship .......... wash_bay 3, service_bay 2,
--                                                    dcfc 10, l2 30, staging 115
--   detail_bay stalls .............................. 0  (in EITHER depot)
--   return_trigger CHECK constraints ............... none (only
--                                                    chk_completed_has_return_trigger,
--                                                    a NOT NULL-when-completed rule)
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. POLICY VALUES -- tunable without a migration, via ottoq_policy_get.
--    param_value is numeric, scope 'global' (run/depot scopes override).
-- ---------------------------------------------------------------------------

INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, notes)
VALUES
  ('global', NULL, 'rider_flag_daily_pct', 3.0,
   'Percent of the fleet a ridehail rider flags for a cleaning issue per SIM-DAY. '
   || '3.0 on a 116-vehicle depot is ~3.5 recalls/day: enough to see one in a short '
   || 'demo, far too few to swamp 3 wash bays. Tune here, not in code.'),
  ('global', NULL, 'rider_flag_interior_share', 0.70,
   'Share of rider cleaning flags that are INTERIOR (spills, trash, odour) rather '
   || 'than exterior. Rideshare complaints skew heavily interior, hence 0.70. The '
   || 'remainder are exterior.'),
  ('global', NULL, 'rider_flag_window_h', 14,
   'Hours from run start over which flag times are spread. 14 h from the demo start '
   || 'of 08:00 local = 08:00-22:00, i.e. the daytime deployment window the founder '
   || 'described ("a random daytime cleaning during an OTTO-Q service flow").')
ON CONFLICT (scope_type, scope_id, param_key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. WHERE THE DRAW IS STORED
--
--    Per-vehicle drawn variables live on public.vehicle_need_profile (PK per
--    vehicle, stamped drawn_for_run / drawn_seed / drawn_at_sim_clock). The
--    rider flag is one more drawn variable, so it goes there -- NOT in a
--    parallel structure.
-- ---------------------------------------------------------------------------

ALTER TABLE public.vehicle_need_profile
  ADD COLUMN IF NOT EXISTS rider_flag_pending  boolean     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS rider_flag_kind     text,
  ADD COLUMN IF NOT EXISTS rider_flag_due_at   timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.vehicle_need_profile'::regclass
                    AND conname  = 'chk_vnp_rider_flag_kind') THEN
    ALTER TABLE public.vehicle_need_profile
      ADD CONSTRAINT chk_vnp_rider_flag_kind
      CHECK (rider_flag_kind IS NULL OR rider_flag_kind IN ('interior','exterior'));
  END IF;
END $$;

COMMENT ON COLUMN public.vehicle_need_profile.rider_flag_pending IS
  '0018: this vehicle was drawn, at run start from the run seed, to be flagged by a '
  'ridehail rider for a cleaning issue during this run. Seed-deterministic, '
  'order-independent, redrawn every run.';
COMMENT ON COLUMN public.vehicle_need_profile.rider_flag_kind IS
  '0018: interior | exterior. Drawn from salt rflagkind:<vehicle_id>.';
COMMENT ON COLUMN public.vehicle_need_profile.rider_flag_due_at IS
  '0018: SIM clock at which the rider raises the flag. Before this moment the vehicle '
  'deploys normally; from it, ottoq_evaluate_return_need recalls it immediately.';

-- ---------------------------------------------------------------------------
-- 3. THE VISIBLE LEDGER
--
--    The founder's demo is: a rider flags a car -> Orchestra pops a notification
--    -> OTTO-Q queues it -> it routes to a specific bay -> you watch it arrive in
--    the 3D twin. Every one of those steps has to be a first-class ROW another
--    surface can read: the trigger, the flagged kind, a truthful `why`, and the
--    bay. That is this table. It is 'ottoq_'-prefixed so a run start purges it
--    with the rest of the run.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.ottoq_rider_cleaning_flags (
  flag_id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sim_run_id            uuid        NOT NULL,
  vehicle_id            uuid        NOT NULL,
  depot_id              uuid,
  flag_kind             text        NOT NULL,
  status                text        NOT NULL DEFAULT 'pending',
  why                   text        NOT NULL,
  return_trigger        text        NOT NULL DEFAULT 'rider_flag_cleaning',
  service_atom          text        NOT NULL,
  stall_type_required   text,
  raised_at_sim_clock   timestamptz NOT NULL,
  recalled_at_sim_clock timestamptz,
  recalled_visit_key    text,
  served_at_sim_clock   timestamptz,
  reserved_stall_id     uuid,
  drawn_seed            bigint,
  created_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_rcf_kind   CHECK (flag_kind IN ('interior','exterior')),
  CONSTRAINT chk_rcf_status CHECK (status IN ('pending','recalled','served')),
  CONSTRAINT uq_rcf_run_vehicle UNIQUE (sim_run_id, vehicle_id)
);

CREATE INDEX IF NOT EXISTS idx_rcf_run_status
  ON public.ottoq_rider_cleaning_flags (sim_run_id, status);
CREATE INDEX IF NOT EXISTS idx_rcf_vehicle
  ON public.ottoq_rider_cleaning_flags (vehicle_id, sim_run_id);

COMMENT ON TABLE public.ottoq_rider_cleaning_flags IS
  '0018: one row per rider-flagged cleaning recall, drawn at run start from the run '
  'seed. Lifecycle pending -> recalled (the manifest has put the cleaning atom on the '
  'visit) -> served (a later visit proves the flagged visit closed). Written so an '
  'operator surface can display the flag, the reason, the trigger and the bay without '
  'joining anything.';
COMMENT ON COLUMN public.ottoq_rider_cleaning_flags.why IS
  'Human-readable, truthful reason. Never a template that outruns the evidence.';
COMMENT ON COLUMN public.ottoq_rider_cleaning_flags.stall_type_required IS
  'Resolved through ottoq.ottoq_svc_to_stall_type at draw time, so an unbookable '
  'requirement is impossible by construction rather than discovered at booking.';

-- 4. seed_phase_max is DECLARATIVE ONLY -- say so in the schema rather than let it lie.
COMMENT ON COLUMN public.service_cadence_policy.seed_phase_max IS
  'DECLARATIVE ONLY as of 0018. These four values (exterior_wash 1.45, '
  'interior_deep_clean 1.18, mechanical_pm 1.45, sensor_calibration 1.50) are the exact '
  'constants hardcoded inside public.ottoq_seed_vehicle_need_profiles, but that function '
  'NEVER READS THIS COLUMN. Editing it changes nothing. Verified 2026-08-07. Left in '
  'place because it documents the constants correctly; wiring the seeder to read it '
  'means rewriting a 12 kB hot-path function and was judged not worth the blast radius '
  'in this migration.';

COMMIT;

-- ============================================================================
-- 5. THE RUN-START DRAW  (public.ottoq_run_boot_draw)
--
--    EXTENDED, not duplicated. Two additions, both inside the existing draw:
--      (a) wash_group -- PATH 1. Per run, from the seed. New salt 'washgrp:'.
--      (b) the rider cleaning flag -- PATH 2. New salts 'rflag:', 'rflagkind:',
--          'rflagwhen:'.
--
--    SALT DISCIPLINE. Every salt below is a namespace that did not previously
--    exist (checked against vnp:, veh_, pmphase:, calphase:, soilphase:, inv:,
--    arr:, soc:, ext:, svc:, pick:, ota_wave:). A reused salt would silently
--    correlate two supposedly independent variables. No timestamp or tick appears
--    in any salt -- the salt is '<namespace>:' || vehicle_id and nothing else, so
--    the draw is a property of the RUN, not of the second a vehicle happened to
--    arrive.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ottoq_run_boot_draw(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run   ottoq_sim_runs%ROWTYPE;
  v_seed  bigint;
  v_n     int := 0;
  v_world jsonb := '{}'::jsonb;
  v_key   text;
  v_manifest jsonb;
  v_t0    timestamptz := clock_timestamp();
  v_profiles jsonb := jsonb_build_object('ok', false, 'skipped', true);
  v_anchored int := 0;   -- 0005: how many odometer watermarks were anchored at boot
  -- 0018
  v_rf_rate      numeric;
  v_rf_int_share numeric;
  v_rf_window_h  numeric;
  v_rf_days      numeric;
  v_rf_p         numeric;
  v_rf_n         int := 0;
  v_rf_int       int := 0;
  v_rf_ext       int := 0;
  v_rf jsonb := jsonb_build_object('ok', false, 'skipped', true);
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
  v_seed := COALESCE(v_run.random_seed, 42);

  -- ---- 1. PER-VEHICLE CONDITION DRAW (config = hot-loop truth; cards = provenance)
  WITH fleet AS (
    SELECT v.id
      FROM vehicles v
     WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous' AND v.is_active
  ), draws AS (
    SELECT id,
      round((88 + 12 * (1 - power(ottoq_sim_seeded_random(v_seed, 'veh_soh:'    || id::text), 2)))::numeric, 1) AS soh,
      round((0.88 + 0.30 * ottoq_sim_seeded_random(v_seed, 'veh_cons:'          || id::text))::numeric, 3)      AS cons,
      round((0.85 + 0.25 * ottoq_sim_seeded_random(v_seed, 'veh_curve:'         || id::text))::numeric, 3)      AS curve,
      round((0.5 + 1.5 * power(ottoq_sim_seeded_random(v_seed, 'veh_soil:'      || id::text), 2))::numeric, 3)  AS soil,
      round((6500 + 3000 * ottoq_sim_seeded_random(v_seed, 'veh_pm:'            || id::text))::numeric, 0)      AS pm_km,
      round((180 + 140 * ottoq_sim_seeded_random(v_seed, 'veh_calib:'           || id::text))::numeric, 0)      AS calib_h,
      round((0.80 + 0.45 * ottoq_sim_seeded_random(v_seed, 'veh_svcspd:'        || id::text))::numeric, 3)      AS svcspd,
      (2 + floor(3 * ottoq_sim_seeded_random(v_seed, 'veh_washcad:'             || id::text)))::int             AS washcad,
      ottoq_sim_seeded_random(v_seed, 'veh_washphase:' || id::text)                                             AS washphase,
      -- 0018 PATH 1: the every-third-night wash GROUP, drawn per run from the run
      -- seed. Previously config.wash_group was written once and never redrawn, and
      -- the fallback was a pure hash of vehicle_id -- so the "randomised each run"
      -- rotation was in fact frozen for all time. floor(3*r) is a clean uniform
      -- third; the gate that consumes it is untouched.
      floor(3 * ottoq_sim_seeded_random(v_seed, 'washgrp:' || id::text))::int         AS washgrp
    FROM fleet
  ), cfg AS (
    UPDATE vehicles v SET config = COALESCE(v.config, '{}'::jsonb) || jsonb_build_object(
        'battery_soh_pct',      d.soh,
        'consumption_scalar',   d.cons,
        'charge_curve_scalar',  d.curve,
        'soil_rate',            d.soil,
        'pm_interval_km',       d.pm_km,
        'calib_interval_h',     d.calib_h,
        'service_speed_scalar', d.svcspd,
        'wash_cadence_cycles',  d.washcad,
        'cycles_since_wash',    floor(d.washcad * d.washphase)::int,
        'wash_group',           d.washgrp,
        'condition_drawn_run',  p_sim_run_id::text)
      FROM draws d WHERE v.id = d.id
      RETURNING v.id, d.soh, d.cons, d.curve, d.soil, d.pm_km, d.calib_h, d.svcspd,
                d.washcad, d.washgrp
  ), cards AS (
    INSERT INTO ottoq_variability_cards
      (sim_run_id, var_key, scope_instance, lifespan, bucket_key, value, drawn_at_clock, drawn_at_tick)
    SELECT p_sim_run_id, x.k, c.id::text, 'run', 'run', x.val, v_run.sim_clock_start, 0
      FROM cfg c CROSS JOIN LATERAL (VALUES
        ('veh_battery_soh_pct',      c.soh),
        ('veh_consumption_scalar',   c.cons),
        ('veh_charge_curve_scalar',  c.curve),
        ('veh_soil_rate',            c.soil),
        ('veh_pm_interval_km',       c.pm_km),
        ('veh_calib_interval_h',     c.calib_h),
        ('veh_service_speed_scalar', c.svcspd),
        ('veh_wash_cadence_cycles',  c.washcad::numeric),
        ('veh_wash_group',           c.washgrp::numeric)) AS x(k, val)
    ON CONFLICT (sim_run_id, var_key, scope_instance, bucket_key) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM cfg;

  -- ---- 1b. RICH PER-VEHICLE NEED PROFILE (energy / cleanliness / sensor+software /
  --          mechanical / operational commitment / items). Runs AFTER the condition draw
  --          so it inherits soh / soil_rate / pm_interval_km / calib_interval_h.
  --          Wrapped: a profile failure must NEVER abort a run boot.
  BEGIN
    v_profiles := ottoq_seed_vehicle_need_profiles(p_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    v_profiles := jsonb_build_object('ok', false, 'error', SQLERRM);
    RAISE WARNING 'boot_draw: need-profile seeding failed: %', SQLERRM;
  END;

  -- ---- 1c. 0005: ANCHOR THE ODOMETER WATERMARK AT BOOT.
  BEGIN
    UPDATE public.vehicle_need_profile p
       SET wear_km_applied     = COALESCE(w.drive_km_total, 0),
           wear_km_applied_run = p_sim_run_id
      FROM public.ottoq_vehicle_wear w
     WHERE w.vehicle_id = p.vehicle_id
       AND w.sim_run_id = p_sim_run_id;
    GET DIAGNOSTICS v_anchored = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    v_anchored := -1;
    RAISE WARNING 'boot_draw: odometer watermark anchoring failed SAFELY: % %', SQLSTATE, SQLERRM;
  END;

  -- ---- 1d. 0018 PATH 2: RIDER-FLAGGED CLEANING RECALL.
  --      Runs AFTER the profile seeder so it writes onto rows that exist. Own
  --      handler: a flag failure must never abort a run boot, exactly like 1b/1c.
  --
  --      RATE. rider_flag_daily_pct is a percentage of the fleet PER SIM-DAY, so a
  --      2-day run must flag roughly twice as many vehicles as a 1-day run. The
  --      per-vehicle probability is therefore rate/100 * run_days, clamped to 1.
  --
  --      TIME. The flag is raised at a seeded moment inside the first
  --      rider_flag_window_h hours of the run -- the daytime deployment window.
  --      The salt carries no clock, so the moment is a property of (seed, vehicle),
  --      not of when the vehicle happened to be looked at.
  BEGIN
    v_rf_rate      := ottoq_policy_get(p_sim_run_id, 'rider_flag_daily_pct',      3.0);
    v_rf_int_share := ottoq_policy_get(p_sim_run_id, 'rider_flag_interior_share', 0.70);
    v_rf_window_h  := ottoq_policy_get(p_sim_run_id, 'rider_flag_window_h',       14);
    v_rf_days := GREATEST(0.25, LEAST(7.0,
      EXTRACT(epoch FROM (COALESCE(v_run.sim_clock_end, v_run.sim_clock_start + interval '1 day')
                          - v_run.sim_clock_start)) / 86400.0));
    v_rf_p := LEAST(1.0, GREATEST(0.0, (v_rf_rate / 100.0) * v_rf_days));

    WITH fleet AS (
      SELECT v.id, v.home_depot_id
        FROM vehicles v
       WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous' AND v.is_active
    ), drawn AS (
      SELECT f.id, f.home_depot_id,
             (ottoq_sim_seeded_random(v_seed, 'rflag:' || f.id::text) < v_rf_p) AS flagged,
             CASE WHEN ottoq_sim_seeded_random(v_seed, 'rflagkind:' || f.id::text) < v_rf_int_share
                  THEN 'interior' ELSE 'exterior' END AS kind,
             v_run.sim_clock_start
               + make_interval(mins => floor(v_rf_window_h * 60
                   * ottoq_sim_seeded_random(v_seed, 'rflagwhen:' || f.id::text))::int) AS due_at
        FROM fleet f
    ), upd AS (
      UPDATE public.vehicle_need_profile p
         SET rider_flag_pending = d.flagged,
             rider_flag_kind    = CASE WHEN d.flagged THEN d.kind END,
             rider_flag_due_at  = CASE WHEN d.flagged THEN d.due_at END
        FROM drawn d
       WHERE p.vehicle_id = d.id
      RETURNING p.vehicle_id
    ), ins AS (
      INSERT INTO public.ottoq_rider_cleaning_flags
        (sim_run_id, vehicle_id, depot_id, flag_kind, status, why, return_trigger,
         service_atom, stall_type_required, raised_at_sim_clock, drawn_seed)
      SELECT p_sim_run_id, d.id, d.home_depot_id, d.kind, 'pending',
             CASE WHEN d.kind = 'interior'
                  THEN 'Ridehail rider reported an interior cleanliness issue mid-trip '
                       || '(spill / trash / odour). Vehicle recalled to depot for an '
                       || 'interior detail before it carries another passenger.'
                  ELSE 'Ridehail rider reported an exterior cleanliness issue mid-trip. '
                       || 'Vehicle recalled to depot for a wash before it carries '
                       || 'another passenger.' END,
             'rider_flag_cleaning',
             CASE WHEN d.kind = 'interior' THEN 'interior_deep_clean' ELSE 'exterior_wash' END,
             -- Resolved NOW, through the same total mapping the booker uses, so a
             -- draw that demands an unbookable stall type is impossible rather than
             -- discovered at booking time. Both atoms resolve to 'wash_bay':
             -- interior_deep_clean's lane is 'detail', and there are ZERO detail_bay
             -- stalls in this depot, so ottoq_svc_to_stall_type folds detail onto the
             -- wash lane. An interior flag and an exterior flag compete for the SAME
             -- three bays. That is a real constraint, not an accident.
             ottoq.ottoq_svc_to_stall_type(
               CASE WHEN d.kind = 'interior' THEN 'interior_deep_clean' ELSE 'exterior_wash' END,
               d.home_depot_id),
             d.due_at, v_seed
        FROM drawn d
       WHERE d.flagged
      ON CONFLICT (sim_run_id, vehicle_id) DO NOTHING
      RETURNING flag_kind
    )
    SELECT count(*)::int,
           count(*) FILTER (WHERE flag_kind = 'interior')::int,
           count(*) FILTER (WHERE flag_kind = 'exterior')::int
      INTO v_rf_n, v_rf_int, v_rf_ext
      FROM ins;

    v_rf := jsonb_build_object(
      'ok', true, 'flagged', v_rf_n, 'interior', v_rf_int, 'exterior', v_rf_ext,
      'daily_pct', v_rf_rate, 'interior_share', v_rf_int_share,
      'run_days', round(v_rf_days, 3), 'per_vehicle_p', round(v_rf_p, 5),
      'window_h', v_rf_window_h);
  EXCEPTION WHEN OTHERS THEN
    v_rf := jsonb_build_object('ok', false, 'error', SQLERRM);
    RAISE WARNING 'boot_draw: rider cleaning flag draw failed SAFELY: % %', SQLSTATE, SQLERRM;
  END;

  -- ---- 2. WORLD DAY-0 DRAW (every run/day/block world card dealt before tick 1)
  FOR v_key IN
    SELECT var_key FROM ottoq_variability_catalog
     WHERE lifespan IN ('run','day','block') AND COALESCE(scope,'') <> 'vehicle'
  LOOP
    BEGIN
      v_world := v_world || jsonb_build_object(v_key,
        ottoq_twin_deal(p_sim_run_id, v_key, 'global', v_run.sim_clock_start,
                        (v_run.sim_clock_start::date - DATE '2020-01-01'), 0, 'global'));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- ---- 3. THE BOOT MANIFEST (loading-screen + Black Box content)
  SELECT jsonb_build_object(
    'ok', true, 'drawn_at', now(), 'seed', v_seed, 'vehicles_drawn', v_n,
    'draw_ms', round(EXTRACT(epoch FROM (clock_timestamp() - v_t0)) * 1000),
    'need_profiles', v_profiles,
    'odometer_watermarks_anchored', v_anchored,
    'rider_cleaning_flags', v_rf,
    -- 0018: was the seed CHOSEN by the caller or drawn fresh? The founder's rule is
    -- "randomized each time", and the only thing that can break it is a caller that
    -- pins p_seed. Recording it here makes the pin visible instead of invisible.
    'seed_was_explicit', (v_run.notes IS NOT NULL AND v_seed IS NOT NULL
                          AND v_seed < 100000000),
    'wash_rotation', jsonb_build_object(
      'source', 'per-run seeded draw (salt washgrp:) -- 0018',
      'groups', (SELECT jsonb_object_agg(g::text, n) FROM (
                   SELECT (v.config->>'wash_group')::int AS g, count(*) AS n
                     FROM vehicles v
                    WHERE v.home_depot_id = v_run.depot_id
                      AND v.category = 'autonomous' AND v.is_active
                      AND v.config ? 'wash_group'
                    GROUP BY 1) s)),
    'world_day0', v_world,
    'fleet_condition', (
      SELECT jsonb_object_agg(k, jsonb_build_object('min', mn, 'avg', av, 'max', mx))
      FROM (
        SELECT var_key AS k, round(min(value),2) AS mn, round(avg(value),2) AS av, round(max(value),2) AS mx
          FROM ottoq_variability_cards
         WHERE sim_run_id = p_sim_run_id AND var_key LIKE 'veh\_%' ESCAPE '\'
         GROUP BY var_key) s))
  INTO v_manifest;

  UPDATE ottoq_sim_runs
     SET payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object('boot_draw', v_manifest)
   WHERE sim_run_id = p_sim_run_id;

  RETURN v_manifest;
END;
$function$;

-- ============================================================================
-- 6. THE RECALL  (public.ottoq_evaluate_return_need)
--
--    One new rung. Everything else is byte-identical to the live definition.
--
--    PLACEMENT. Rung 3.5, expressed as rung 4 -- immediately AFTER the safety and
--    energy rungs (critical_reserve 0, fault_safety_critical 1, fault_major 2,
--    low_soc_reserve 3) and BEFORE comms_stale / timer_backstop / everything
--    routine. A dirty cabin never outranks a safety fault or a reserve breach.
--
--    DEFERRABLE = FALSE, and deliberately placed ABOVE the contention gate
--    (the `LEAST(v_wait_ticks*30, v_wait_cap) <= v_max_wait_min` test that guards
--    the routine rungs). The founder's rule is "routed back to the depot
--    IMMEDIATELY". In twin.ottoq_sim_advance_deployed_telemetry a non-deferrable
--    need departs whether or not a stall was secured, so this recall cannot be
--    starved by a busy depot.
--
--    VEHICLE-FIRST is not violated: this is not a prediction holding a ready
--    vehicle back, it is a customer-visible defect pulling a vehicle out of
--    service. It cannot fire before rider_flag_due_at, so a vehicle with a flag
--    later in the run deploys and earns normally until the rider raises it.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ottoq_evaluate_return_need(p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_horizon_min numeric DEFAULT 30, p_soc_pct numeric DEFAULT NULL::numeric)
 RETURNS TABLE(should_return boolean, return_trigger text, urgency text, rung smallint, is_deferrable boolean, lead_ticks smallint, projected_eta_min numeric, evidence jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_v RECORD; v_pkt RECORD; v_w RECORD;
  v_soc numeric; v_reserve numeric; v_floor numeric; v_eta_min numeric;
  v_hour int; v_depot uuid;
  v_burn_per_min numeric; v_burn_guard numeric; v_reserve_margin numeric;
  v_dtc_debt int; v_comms_stale int; v_wait_cap int; v_backstop_ticks int;
  v_wash_soil numeric; v_sensor_soil numeric; v_pm_km numeric; v_calib_h numeric;
  v_free_chargers int; v_inbound int; v_wait_ticks int; v_max_wait_min numeric;
  v_in_window boolean; v_slot int; v_slot_open boolean; v_holdout boolean;
  v_pkt_age_min numeric; v_has_service_need boolean; v_overnight_need boolean;
  v_ev jsonb;
  v_rf RECORD;   -- 0018
BEGIN
  IF p_sim_run_id IS NULL THEN
    RAISE EXCEPTION 'ottoq_evaluate_return_need requires a run scope';
  END IF;

  SELECT d.dispatch_id, d.scheduled_return_at, d.dispatched_at, v.home_depot_id, v.config,
         v.current_soc, v.min_soc_threshold
    INTO v_v
    FROM ottoq_vehicle_dispatches d JOIN vehicles v ON v.id = d.vehicle_id
   WHERE d.vehicle_id = p_vehicle_id AND d.sim_run_id = p_sim_run_id AND d.status = 'active'
   ORDER BY d.dispatched_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::text, 'none', 10::smallint, NULL::boolean,
                        NULL::smallint, NULL::numeric,
                        jsonb_build_object('reason','no active dispatch in run');
    RETURN;
  END IF;
  v_depot := v_v.home_depot_id;

  SELECT tp.soc_pct, tp.sim_clock_at
    INTO v_pkt
    FROM ottoq_telemetry_packets tp
   WHERE tp.vehicle_id = p_vehicle_id AND tp.sim_run_id = p_sim_run_id
     AND tp.sim_clock_at <= p_sim_clock_now AND tp.soc_pct IS NOT NULL
   ORDER BY tp.sim_clock_at DESC, tp.packet_seq DESC LIMIT 1;

  SELECT w.worst_open_dtc_rank, w.open_dtc_count, w.soil_index,
         w.drive_km_total, w.km_at_last_pm, w.drive_hours_total,
         w.hours_at_last_calibration, w.calibrated_at
    INTO v_w
    FROM ottoq_vehicle_wear w
   WHERE w.vehicle_id = p_vehicle_id AND w.sim_run_id = p_sim_run_id;

  v_soc     := COALESCE(p_soc_pct, v_pkt.soc_pct, v_v.current_soc);
  v_reserve := ottoq_effective_reserve_soc(p_vehicle_id, p_sim_clock_now);
  v_floor   := ottoq_effective_deploy_floor_at(p_vehicle_id, p_sim_clock_now);
  v_eta_min := ottoq_return_eta_minutes(p_vehicle_id, v_depot, p_sim_run_id);
  v_hour    := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  v_burn_per_min   := ottoq_policy_get(p_sim_run_id,'p99_burn_pct_per_min',0.25);
  v_reserve_margin := ottoq_policy_get(p_sim_run_id,'reserve_margin_pct',15);
  v_dtc_debt       := ottoq_policy_get(p_sim_run_id,'dtc_debt_threshold',3)::int;
  v_comms_stale    := ottoq_policy_get(p_sim_run_id,'comms_stale_ticks',3)::int;
  v_wait_cap       := ottoq_policy_get(p_sim_run_id,'contention_wait_cap_min',
                        ottoq_policy_get(p_sim_run_id,'contention_wait_cap_ticks',4) * 30)::int;
  v_backstop_ticks := ottoq_policy_get(p_sim_run_id,'timer_backstop_min',
                        ottoq_policy_get(p_sim_run_id,'timer_backstop_ticks',48) * 30)::int;
  v_wash_soil      := ottoq_policy_get(p_sim_run_id,'wash_soil_threshold',0.50);
  v_sensor_soil    := ottoq_policy_get(p_sim_run_id,'sensor_soil_threshold',0.35);
  v_pm_km          := COALESCE((v_v.config->>'pm_interval_km')::numeric, ottoq_policy_get(p_sim_run_id,'pm_interval_km',8000));
  v_calib_h        := COALESCE((v_v.config->>'calib_interval_h')::numeric, ottoq_policy_get(p_sim_run_id,'calib_interval_h',250));

  v_burn_guard := v_burn_per_min * (v_eta_min + p_horizon_min);

  SELECT count(*) INTO v_free_chargers FROM stalls s
   WHERE s.depot_id = v_depot AND s.stall_kind = 'charging'
     AND s.status = 'available' AND s.current_vehicle_id IS NULL;
  SELECT count(*) INTO v_inbound FROM vehicles vv
   WHERE vv.home_depot_id = v_depot AND vv.category='autonomous'
     AND vv.current_state IN ('en_route_to_depot','arrived_at_gate');

  v_wait_ticks := CASE WHEN v_free_chargers >= v_inbound + 1 THEN 0
         ELSE CEIL((v_inbound + 1 - v_free_chargers)/GREATEST(v_free_chargers,1)::numeric) END;
  v_max_wait_min := COALESCE((SELECT s.max_queue_wait_minutes FROM ottoq_fleet_operator_slas s
     JOIN vehicles vv ON vv.id=p_vehicle_id AND vv.fleet_operator_id=s.fleet_operator_id
     WHERE s.status='active' ORDER BY s.version DESC LIMIT 1), 30);

  v_pkt_age_min := CASE WHEN v_pkt.sim_clock_at IS NULL THEN NULL
                        ELSE EXTRACT(EPOCH FROM (p_sim_clock_now - v_pkt.sim_clock_at))/60.0 END;

  v_has_service_need := COALESCE(v_w.soil_index,0) >= v_sensor_soil
     OR COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0) >= v_pm_km
     OR (COALESCE((v_v.config->>'wash_group')::int,
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3))
                = ((p_sim_clock_now::date - DATE '2020-01-01') % 3));
  v_overnight_need := v_has_service_need OR v_soc < v_floor;

  -- 0018: the rider flag, read (never drawn) from the run-start draw. Read-only on
  -- the hot path. NULL-safe: a vehicle with no profile row simply has no flag.
  SELECT p.rider_flag_pending, p.rider_flag_kind, p.rider_flag_due_at
    INTO v_rf
    FROM public.vehicle_need_profile p
   WHERE p.vehicle_id = p_vehicle_id
     AND p.drawn_for_run = p_sim_run_id;

  v_ev := jsonb_build_object(
    'soc', v_soc, 'reserve', v_reserve, 'deploy_floor', v_floor, 'target_absent_from_loop', true,
    'burn_guard', round(v_burn_guard,2), 'reserve_margin', v_reserve_margin,
    'eta_min', v_eta_min, 'free_chargers', v_free_chargers, 'inbound', v_inbound,
    'wait_ticks', v_wait_ticks, 'reserved_by_bias', 'supply overcounted (reserved_by not consulted)',
    'worst_dtc_rank', v_w.worst_open_dtc_rank, 'soil', v_w.soil_index, 'hour_local', v_hour);

  IF v_soc <= v_reserve + v_burn_guard THEN
    RETURN QUERY SELECT true,'critical_reserve','critical',0::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF COALESCE(v_w.worst_open_dtc_rank,99) = 0 THEN
    RETURN QUERY SELECT true,'fault_safety_critical','critical',1::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF COALESCE(v_w.worst_open_dtc_rank,99) = 1 OR COALESCE(v_w.open_dtc_count,0) >= v_dtc_debt THEN
    RETURN QUERY SELECT true,'fault_major','urgent',2::smallint,false,1::smallint,v_eta_min,v_ev; RETURN;
  END IF;
  IF v_soc <= v_reserve + v_reserve_margin THEN
    RETURN QUERY SELECT true,'low_soc_reserve','urgent',3::smallint,false,1::smallint,v_eta_min,v_ev; RETURN;
  END IF;

  -- ===== 0018: RIDER-FLAGGED CLEANING RECALL =====
  -- Below safety and reserve, above everything routine, and NOT behind the
  -- contention gate. is_deferrable = false, lead_ticks = 0: the vehicle turns for
  -- the depot on this tick.
  IF COALESCE(v_rf.rider_flag_pending, false)
     AND v_rf.rider_flag_due_at IS NOT NULL
     AND p_sim_clock_now >= v_rf.rider_flag_due_at THEN
    RETURN QUERY SELECT true,'rider_flag_cleaning','urgent',4::smallint,false,0::smallint,v_eta_min,
                        v_ev || jsonb_build_object(
                          'rider_flag_kind', COALESCE(v_rf.rider_flag_kind,'interior'),
                          'rider_flag_raised_at', v_rf.rider_flag_due_at,
                          'why', 'A ridehail rider reported a '
                                 || COALESCE(v_rf.rider_flag_kind,'interior')
                                 || ' cleanliness issue. Recalled to depot now rather '
                                 || 'than at its next natural return.'); RETURN;
  END IF;

  IF (v_pkt_age_min IS NULL
        AND EXTRACT(EPOCH FROM (p_sim_clock_now - v_v.dispatched_at))/60.0 >= v_comms_stale * p_horizon_min)
     OR (v_pkt_age_min IS NOT NULL AND v_pkt_age_min >= v_comms_stale * p_horizon_min) THEN
    RETURN QUERY SELECT true,'comms_stale','urgent',8::smallint,false,0::smallint,v_eta_min,
                        v_ev || jsonb_build_object('pkt_age_min', v_pkt_age_min); RETURN;
  END IF;
  IF v_v.scheduled_return_at IS NOT NULL
     AND p_sim_clock_now >= v_v.scheduled_return_at + (v_backstop_ticks || ' minutes')::interval THEN
    RETURN QUERY SELECT true,'timer_backstop','anomaly',9::smallint,false,0::smallint,v_eta_min,v_ev; RETURN;
  END IF;

  IF LEAST(v_wait_ticks * 30.0, v_wait_cap) <= v_max_wait_min THEN
    IF COALESCE(v_w.drive_km_total,0) - COALESCE(v_w.km_at_last_pm,0) >= v_pm_km
       OR COALESCE(v_w.drive_hours_total,0) - COALESCE(v_w.hours_at_last_calibration,0) >= v_calib_h THEN
      RETURN QUERY SELECT true,'service_interval_due','routine',4::smallint,true,2::smallint,v_eta_min,v_ev; RETURN;
    END IF;
    IF COALESCE(v_w.soil_index,0) >= v_sensor_soil THEN
      RETURN QUERY SELECT true,'sensor_soil','routine',5::smallint,true,1::smallint,v_eta_min,v_ev; RETURN;
    END IF;
    v_in_window := (v_hour >= 22 OR v_hour < 4);
    v_slot      := LEAST(3, width_bucket(v_soc, 0, 100, 3));
    v_slot_open := (v_hour >= 22 AND v_hour - 22 >= v_slot - 1) OR v_hour < 4;
    v_holdout := ottoq_is_overnight_holdout(p_vehicle_id, p_sim_run_id, p_sim_clock_now, ottoq_policy_get(p_sim_run_id, 'overnight_holdout_pct', 1)::int);
    IF v_in_window AND v_slot_open AND v_overnight_need AND (NOT v_holdout OR (v_hour >= 3 AND v_hour < 22)) THEN
      RETURN QUERY SELECT true,'overnight_prestage','scheduled',6::smallint,true,1::smallint,v_eta_min,
                          v_ev || jsonb_build_object('slot', v_slot); RETURN;
    END IF;
    IF (COALESCE(v_w.soil_index,0) >= v_wash_soil
        OR COALESCE((v_v.config->>'wash_group')::int,
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3))
                = ((p_sim_clock_now::date - DATE '2020-01-01') % 3))
       AND (v_hour < 7 OR v_hour >= 21) THEN
      RETURN QUERY SELECT true,'wash_cadence','routine',7::smallint,true,2::smallint,v_eta_min,v_ev; RETURN;
    END IF;
  END IF;

  RETURN QUERY SELECT false, NULL::text, 'none', 10::smallint, NULL::boolean, NULL::smallint, NULL::numeric,
                      v_ev || jsonb_build_object('decision','no need; stay deployed');
END;
$function$;

-- ============================================================================
-- 7. THE ATOM  (twin.ottoq_sim_generate_service_manifest)
--
--    One new block, inserted after the exterior_wash gate. THE NIGHT WASH GATE
--    ITSELF IS UNCHANGED, character for character.
--
--    IDEMPOTENCE. The manifest generator is called from four places
--    (ottoq_book_appointment, ottoq_sim_prearrival_contracts,
--    twin.ottoq_sim_generate_arrival_manifests, twin.ottoq_sim_wash_triage), and
--    ottoq_book_appointment calls it at the RETURN SIGNAL -- which is what puts
--    the bay reservation ~30 sim-min ahead of arrival (0011). So the flag must
--    survive repeated generation within one visit and must NOT survive into the
--    next one. The flag row therefore carries the visit key it was consumed by:
--      pending                          -> emit the atom, stamp recalled + visit key
--      recalled, same visit key         -> emit the atom again (regeneration)
--      recalled, different visit key    -> that visit closed: mark served, stop emitting
--    No completion hook in a fifth function, and no double-washing.
--
--    TOTAL FUNCTION. flag_kind is constrained to interior|exterior, but the branch
--    still has an ELSE that treats anything unrecognised as interior rather than
--    dropping the work. This codebase has already had one unmapped word abort
--    every decision every tick while cron reported success.
-- ============================================================================

CREATE OR REPLACE FUNCTION twin.ottoq_sim_generate_service_manifest(p_vehicle_id uuid, p_sim_run_id uuid DEFAULT NULL::uuid, p_seed bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc numeric; v_target numeric; v_cycles int; v_seed bigint; v_m jsonb := '[]'::jsonb;
  v_depot uuid; v_clock timestamptz; v_run uuid; v_plan jsonb; v_visit text;
  v_precip_stress numeric := 0; v_boost numeric := 0;
  v_probs jsonb; v_clamp_lo numeric := 0.005; v_clamp_hi numeric := 0.90;
  v_p numeric; v_conf numeric;
  v_hour int; v_urgency text; v_due timestamptz; v_visit_target numeric;
  v_is_night boolean; v_tail_scale numeric; v_insp_p numeric; v_night_start int; v_night_end int;
  v_fault boolean := false; v_ota boolean := false;
  v_band_lo numeric; v_band_hi numeric;
  v_sla_floor numeric; v_sim_day int;
  v_carry jsonb; v_carry_visit uuid; v_atom jsonb;
  v_archetype text;
  v_wear RECORD; v_soil numeric := 0; v_cap numeric; v_inlet_kw numeric; v_soh numeric;
  v_curve numeric; v_svcspd numeric; v_pm_int numeric; v_calib_int numeric; v_washcad int;
  v_pm_prog numeric := 0; v_calib_prog numeric := 0;
  v_wash_min int; v_deep_min int; v_pm_min int; v_calib_min int; v_charge_min int := 0;
  v_rf RECORD; v_rf_svc text; v_rf_min int;   -- 0018
BEGIN
  SELECT current_soc, COALESCE(target_soc,85), COALESCE((config->>'cycles_since_wash')::int,0),
         home_depot_id, COALESCE(last_state_change, now()),
         battery_capacity_kwh, inlet_max_kw,
         (config->>'battery_soh_pct')::numeric, (config->>'charge_curve_scalar')::numeric,
         (config->>'service_speed_scalar')::numeric, (config->>'pm_interval_km')::numeric,
         (config->>'calib_interval_h')::numeric, (config->>'wash_cadence_cycles')::int
    INTO v_soc, v_target, v_cycles, v_depot, v_clock,
         v_cap, v_inlet_kw, v_soh, v_curve, v_svcspd, v_pm_int, v_calib_int, v_washcad
    FROM vehicles WHERE id = p_vehicle_id;
  IF v_soc IS NULL THEN RETURN NULL; END IF;
  SELECT w.soil_index,
         w.drive_km_total    - COALESCE(w.km_at_last_pm,0)             AS km_since_pm,
         w.drive_hours_total - COALESCE(w.hours_at_last_calibration,0) AS h_since_calib
    INTO v_wear FROM ottoq_vehicle_wear w
   WHERE w.vehicle_id = p_vehicle_id AND (p_sim_run_id IS NULL OR w.sim_run_id = p_sim_run_id)
   ORDER BY w.updated_at DESC LIMIT 1;
  v_soil := COALESCE(v_wear.soil_index, 0);

  v_run := COALESCE(p_sim_run_id,
    (SELECT sim_run_id FROM ottoq_sim_runs r
      WHERE r.status = 'running' AND r.depot_id = v_depot
      ORDER BY started_at DESC LIMIT 1));

  v_plan := ottoq_feed_plan('service_manifest');

  IF p_seed IS NOT NULL THEN
    v_seed := p_seed;
  ELSIF v_run IS NOT NULL THEN
    SELECT COALESCE(random_seed, 42) INTO v_seed FROM ottoq_sim_runs WHERE sim_run_id = v_run;
  ELSE
    v_seed := abs(hashtextextended(p_vehicle_id::text || 'manifest', 13));
  END IF;
  v_visit := p_vehicle_id::text || ':' || to_char(v_clock, 'YYYYMMDDHH24MISS');
  v_sim_day := (v_clock::date - DATE '2020-01-01');

  IF v_run IS NOT NULL AND v_plan IS NOT NULL THEN
    v_precip_stress := COALESCE((ottoq_twin_climate_stress(v_run, v_sim_day)->>'precip_stress')::numeric, 0);
    v_boost := v_precip_stress * COALESCE((v_plan->>'precip_soil_coupling')::numeric, 0.6);
  END IF;

  v_probs := COALESCE(v_plan->'probabilities', jsonb_build_object(
    'interior_tidy',0.35,'sensor_clean',0.20,'interior_deep_clean',0.10,
    'exterior_wash',0.20,'sensor_calibration',0.04,'mechanical_pm',0.05,'cosmetic_repair',0.02));
  v_tail_scale := GREATEST(0, COALESCE((v_plan->>'long_tail_scale')::numeric, 0.5));
  v_probs := v_probs || jsonb_build_object(
    'sensor_clean',        COALESCE((v_probs->>'sensor_clean')::numeric,0.20)        * v_tail_scale,
    'interior_deep_clean', COALESCE((v_probs->>'interior_deep_clean')::numeric,0.10) * v_tail_scale,
    'sensor_calibration',  COALESCE((v_probs->>'sensor_calibration')::numeric,0.04)  * v_tail_scale,
    'mechanical_pm',       COALESCE((v_probs->>'mechanical_pm')::numeric,0.05)       * v_tail_scale,
    'cosmetic_repair',     COALESCE((v_probs->>'cosmetic_repair')::numeric,0.02)     * v_tail_scale);
  IF v_plan IS NOT NULL THEN
    v_clamp_lo := COALESCE((v_plan->'probability_clamp'->>0)::numeric, 0.005);
    v_clamp_hi := COALESCE((v_plan->'probability_clamp'->>1)::numeric, 0.90);
  END IF;
  v_band_lo := COALESCE((v_plan->>'confirm_band_lo')::numeric, 0.40);
  v_band_hi := COALESCE((v_plan->>'confirm_band_hi')::numeric, 0.75);

  -- ===== URGENCY (time-of-day shaped; fault overrides to tech_hold) =====
  v_fault := ottoq_sim_seeded_random(v_seed, v_visit || ':fault') < COALESCE((v_plan->>'fault_repair_p')::numeric, 0.02);
  v_hour := EXTRACT(HOUR FROM (v_clock AT TIME ZONE 'America/Chicago'))::int;
  IF v_fault THEN
    v_urgency := 'tech_hold';
  ELSIF v_hour >= 22 OR v_hour < 4 THEN
    v_urgency := CASE WHEN ottoq_sim_seeded_random(v_seed, v_visit || ':urg')
                        < COALESCE((v_plan->>'overnight_hold_p_night')::numeric, 0.75)
                 THEN 'overnight_hold' ELSE 'standard' END;
  ELSE
    v_urgency := CASE WHEN ottoq_sim_seeded_random(v_seed, v_visit || ':urg')
                        < COALESCE((v_plan->>'immediate_dispatch_p_day')::numeric, 0.30)
                 THEN 'immediate_dispatch' ELSE 'standard' END;
  END IF;
  v_due := CASE v_urgency
    WHEN 'immediate_dispatch' THEN v_clock + interval '45 minutes'
    WHEN 'overnight_hold' THEN
      (((v_clock AT TIME ZONE 'America/Chicago')::date
        + CASE WHEN v_hour >= 4 THEN 1 ELSE 0 END) + time '07:00') AT TIME ZONE 'America/Chicago'
    ELSE NULL END;
  BEGIN
    SELECT min_soc_at_deployment_pct INTO v_sla_floor
      FROM ottoq_get_active_sla((SELECT fleet_operator_id FROM vehicles WHERE id = p_vehicle_id));
  EXCEPTION WHEN OTHERS THEN v_sla_floor := NULL; END;
  v_sla_floor := COALESCE(v_sla_floor, 80);
  v_visit_target := CASE WHEN v_urgency = 'immediate_dispatch'
                         THEN GREATEST(v_sla_floor + 5, 70) ELSE v_target END;

  v_pm_prog    := CASE WHEN COALESCE(v_pm_int,0)    > 0 THEN COALESCE(v_wear.km_since_pm,0)   / v_pm_int    ELSE 0 END;
  v_calib_prog := CASE WHEN COALESCE(v_calib_int,0) > 0 THEN COALESCE(v_wear.h_since_calib,0) / v_calib_int ELSE 0 END;
  v_wash_min  := GREATEST(8, LEAST(10, round(9 * COALESCE(CASE WHEN v_run IS NOT NULL THEN ottoq_twin_deal(v_run,'wash_time',        v_visit, v_clock, v_sim_day, 0, 'global') END, 1.0) * COALESCE(v_svcspd,1))))::int;
  v_deep_min  := GREATEST(12, round(20 * COALESCE(CASE WHEN v_run IS NOT NULL THEN ottoq_twin_deal(v_run,'detail_time',      v_visit, v_clock, v_sim_day, 0, 'global') END, 1.0) * COALESCE(v_svcspd,1)))::int;
  v_pm_min    := GREATEST(20, round(40 * COALESCE(CASE WHEN v_run IS NOT NULL THEN ottoq_twin_deal(v_run,'maintenance_time', v_visit, v_clock, v_sim_day, 0, 'global') END, 1.0) * COALESCE(v_svcspd,1)))::int;
  v_calib_min := GREATEST(18, round(30 * COALESCE(v_svcspd,1)))::int;
  IF v_soc < v_visit_target - 1 THEN
    v_charge_min := GREATEST(8, round(COALESCE(
      ottoq_estimate_charge_minutes(v_soc, v_visit_target, 150, COALESCE(v_inlet_kw,150),
                                    COALESCE(v_cap,75), 25, COALESCE(v_soh,95),
                                    GREATEST(0.2, (CASE WHEN v_run IS NULL THEN 1.0 ELSE ottoq_profile_rate_mult(v_run,'charge_time') END)
                                                  / GREATEST(0.2, COALESCE(v_curve,1.0)))), 25)))::int;
  END IF;

  -- ===== ATOMS =====
  IF v_soc < v_visit_target - 1 THEN
    v_m := v_m || jsonb_build_object('svc','charge','must_do',true,'deferrable',false,
      'target_soc',v_visit_target,'est_min',v_charge_min,'concurrency','anchor');
  END IF;
  v_m := v_m || jsonb_build_object('svc','readiness_check','must_do',true,'deferrable',false,
      'est_min',3,'concurrency','gate','predecessors',jsonb_build_array('*'));
  v_night_start := COALESCE((v_plan->>'night_start_hour')::int, 20);
  v_night_end   := COALESCE((v_plan->>'night_end_hour')::int, 6);
  v_is_night    := (v_hour >= v_night_start OR v_hour < v_night_end);

  v_insp_p := CASE WHEN v_is_night
                   THEN COALESCE((v_plan->>'night_interior_inspection_p')::numeric, 0.95)
                   ELSE COALESCE((v_plan->>'day_interior_inspection_p')::numeric, 0.93) END;
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':insp') < v_insp_p THEN
    v_m := v_m || jsonb_build_object('svc','interior_inspection','must_do',true,'deferrable',false,
      'est_min', (3 + round(2 * ottoq_sim_seeded_random(v_seed, v_visit || ':inspmin')))::int,
      'concurrency','cabin','at_charge_stall',true);
  END IF;

  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'interior_tidy')::numeric * (1 + v_boost) * (0.6 + 1.6 * v_soil)));
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':tidy') < v_p THEN
    v_conf := round((0.30 + 0.70 * ottoq_sim_seeded_random(v_seed, v_visit || ':tidyconf'))::numeric, 2);
    v_m := v_m || jsonb_build_object('svc','interior_tidy','must_do',true,'deferrable',false,
      'est_min', (3 + round(2 * ottoq_sim_seeded_random(v_seed, v_visit || ':tidymin')))::int,
      'concurrency','cabin','confidence',v_conf,
      'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi);
  END IF;
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':item') < COALESCE((v_plan->>'item_retrieval_p')::numeric, 0.06) THEN
    v_m := v_m || jsonb_build_object('svc','item_retrieval','must_do',true,'deferrable',false,
      'est_min',4,'concurrency','cabin','confidence',1.0,'confirm_required',false);
  END IF;
  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'sensor_clean')::numeric * (1 + v_boost) * (0.6 + 1.6 * v_soil)));
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':sclean') < v_p THEN
    v_conf := round((0.30 + 0.70 * ottoq_sim_seeded_random(v_seed, v_visit || ':scleanconf'))::numeric, 2);
    v_m := v_m || jsonb_build_object('svc','sensor_clean','must_do',true,'deferrable',false,
      'est_min',5,'concurrency','exterior','confidence',v_conf,
      'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi);
  END IF;
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':diag') < COALESCE((v_plan->>'remote_diagnostics_p')::numeric, 0.05) THEN
    v_m := v_m || jsonb_build_object('svc','remote_diagnostics','must_do',false,'deferrable',true,
      'est_min',5,'concurrency','digital');
  END IF;
  v_ota := ottoq_sim_seeded_random(v_seed, 'ota_wave:' || v_sim_day::text) < COALESCE((v_plan->>'ota_wave_daily_p')::numeric, 0.08);
  IF v_ota THEN
    v_m := v_m || jsonb_build_object('svc','software_update','must_do',false,'deferrable',true,
      'est_min', 15 + floor(ottoq_sim_seeded_random(v_seed, v_visit || ':otamin') * 30)::int,
      'concurrency','digital','blocks_dispatch_while_running',true);
  END IF;
  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'interior_deep_clean')::numeric * (1 + v_boost * 0.5)));
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':deep') < v_p THEN
    v_m := v_m || jsonb_build_object('svc','interior_deep_clean','must_do',false,'deferrable',true,
      'est_min',v_deep_min,'concurrency','bay','requires_bay','detail','carryover_eligible',true);
  END IF;

  -- exterior wash (rain OR cadence, deferrable, precedes calibration)
  -- ==========================================================================
  -- PATH 1 GATE -- UNCHANGED BY 0018. Wash is EVERY 3rd NIGHT and only at night.
  -- The rotation is a calendar third of the fleet per night, so each vehicle
  -- washes every 3rd day. 0018 changed only WHERE wash_group comes from (it is
  -- now redrawn per run from the run seed in ottoq_run_boot_draw), not this gate.
  -- Exceptions preserved verbatim: a visibly dirty vehicle is washed off-rotation,
  -- and a long backstop catches anything the rotation missed.
  -- ==========================================================================
  v_p := LEAST(v_clamp_hi, GREATEST(v_clamp_lo, (v_probs->>'exterior_wash')::numeric * (1 + v_boost) * (0.6 + 1.6 * v_soil)));
  IF (v_is_night
       AND COALESCE((SELECT (config->>'wash_group')::int FROM vehicles WHERE id = p_vehicle_id),
                    (abs(hashtextextended(p_vehicle_id::text, 77)) % 3)) = (v_sim_day % 3))
     OR v_soil >= COALESCE((v_plan->>'wash_soil_override')::numeric, 0.75)
     OR v_cycles >= COALESCE((v_plan->>'wash_backstop_cycles')::int, 9) THEN
    v_m := v_m || jsonb_build_object('svc','exterior_wash','must_do',false,'deferrable',true,
      'est_min',v_wash_min,'concurrency','bay','requires_bay','wash_bay','carryover_eligible',true);
  END IF;

  -- ==========================================================================
  -- 0018 PATH 2 -- RIDER-FLAGGED CLEANING. The vehicle was recalled mid-deployment
  -- because a rider reported a cleanliness issue, so the cleaning is must_do and
  -- NOT deferrable: this visit is what the recall was for. Everything else about
  -- the visit (charge, inspection, night wash if due) still applies -- the visit
  -- stays ATOMIC.
  -- ==========================================================================
  IF v_run IS NOT NULL THEN
    SELECT f.flag_id, f.flag_kind, f.status, f.recalled_visit_key
      INTO v_rf
      FROM public.ottoq_rider_cleaning_flags f
     WHERE f.sim_run_id = v_run AND f.vehicle_id = p_vehicle_id
       AND f.status IN ('pending','recalled')
       AND f.raised_at_sim_clock <= v_clock;

    IF v_rf.flag_id IS NOT NULL THEN
      IF v_rf.status = 'recalled' AND v_rf.recalled_visit_key IS DISTINCT FROM v_visit THEN
        -- The visit this flag was consumed by has closed. Retire it; do not re-emit.
        UPDATE public.ottoq_rider_cleaning_flags
           SET status = 'served', served_at_sim_clock = v_clock
         WHERE flag_id = v_rf.flag_id;
      ELSE
        -- TOTAL: 'exterior' takes the wash lane; interior AND anything unrecognised
        -- takes the detail lane. An unknown word must never silently drop the work.
        IF v_rf.flag_kind = 'exterior' THEN
          v_rf_svc := 'exterior_wash'; v_rf_min := v_wash_min;
        ELSE
          v_rf_svc := 'interior_deep_clean'; v_rf_min := v_deep_min;
        END IF;

        -- If the routine draw already put this atom on the visit, PROMOTE it to
        -- must_do rather than adding a duplicate; otherwise append it.
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = v_rf_svc) THEN
          SELECT jsonb_agg(CASE WHEN a->>'svc' = v_rf_svc
                                THEN a || jsonb_build_object('must_do', true, 'deferrable', false,
                                       'carryover_eligible', false,
                                       'rider_flagged', true,
                                       'rider_flag_kind', COALESCE(v_rf.flag_kind,'interior'),
                                       'return_trigger', 'rider_flag_cleaning')
                                ELSE a END)
            INTO v_m FROM jsonb_array_elements(v_m) a;
        ELSE
          v_m := v_m || jsonb_build_object(
            'svc', v_rf_svc, 'must_do', true, 'deferrable', false,
            'est_min', v_rf_min, 'concurrency', 'bay',
            'requires_bay', CASE WHEN v_rf_svc = 'exterior_wash' THEN 'wash_bay' ELSE 'detail' END,
            'carryover_eligible', false,
            'rider_flagged', true,
            'rider_flag_kind', COALESCE(v_rf.flag_kind,'interior'),
            'return_trigger', 'rider_flag_cleaning',
            'why', 'Rider-reported ' || COALESCE(v_rf.flag_kind,'interior')
                   || ' cleanliness issue; vehicle was recalled for this.');
        END IF;

        UPDATE public.ottoq_rider_cleaning_flags
           SET status = 'recalled',
               recalled_at_sim_clock = COALESCE(recalled_at_sim_clock, v_clock),
               recalled_visit_key    = v_visit
         WHERE flag_id = v_rf.flag_id;
      END IF;
    END IF;
  END IF;

  IF v_is_night
     AND ottoq_sim_seeded_random(v_seed, v_visit || ':walkaround')
         < COALESCE((v_plan->>'night_walkaround_p')::numeric, 0.90) THEN
    v_m := v_m || jsonb_build_object('svc','perimeter_walkaround','must_do',true,'deferrable',false,
      'est_min', (10 + round(5 * ottoq_sim_seeded_random(v_seed, v_visit || ':walkmin')))::int,
      'concurrency','hold','at_perimeter',true);
  END IF;
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':calib') < LEAST(0.95, (v_probs->>'sensor_calibration')::numeric
        * CASE WHEN v_calib_prog >= 1.0 THEN 12 WHEN v_calib_prog >= 0.8 THEN 4 ELSE 0.5 END) THEN
    v_m := v_m || jsonb_build_object('svc','sensor_calibration','must_do',false,'deferrable',true,
      'est_min',v_calib_min,'slot','dedicated_service','concurrency','bay','requires_bay','service_bay',
      'predecessors',jsonb_build_array('exterior_wash'),'carryover_eligible',true);
  END IF;
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':pm') < LEAST(0.95, (v_probs->>'mechanical_pm')::numeric
        * CASE WHEN v_pm_prog >= 1.0 THEN 12 WHEN v_pm_prog >= 0.8 THEN 4 ELSE 0.5 END) THEN
    v_m := v_m || jsonb_build_object('svc','mechanical_pm','must_do',false,'deferrable',true,
      'est_min',v_pm_min,'concurrency','bay','requires_bay','service_bay','carryover_eligible',true);
  END IF;
  IF ottoq_sim_seeded_random(v_seed, v_visit || ':cosmetic') < (v_probs->>'cosmetic_repair')::numeric THEN
    v_conf := round((0.30 + 0.70 * ottoq_sim_seeded_random(v_seed, v_visit || ':cosconf'))::numeric, 2);
    v_m := v_m || jsonb_build_object('svc','cosmetic_repair','must_do',false,'deferrable',true,
      'est_min',60,'disposition','offline_candidate','concurrency','bay','requires_bay','service_bay',
      'confidence',v_conf,'confirm_required', v_conf BETWEEN v_band_lo AND v_band_hi,
      'carryover_eligible',true);
  END IF;
  IF v_fault THEN
    v_m := v_m || jsonb_build_object('svc','fault_repair','must_do',true,'deferrable',false,
      'est_min', 30 + floor(ottoq_sim_seeded_random(v_seed, v_visit || ':faultmin') * 90)::int,
      'concurrency','bay','requires_bay','service_bay','requires_tech_greenlight',true);
  END IF;

  -- ===== CARRYOVER =====
  SELECT visit_id, atoms INTO v_carry_visit, v_carry
    FROM ottoq_visit_needs
   WHERE vehicle_id = p_vehicle_id AND status = 'carried_over'
   ORDER BY created_at DESC LIMIT 1;
  IF v_carry IS NOT NULL THEN
    FOR v_atom IN SELECT * FROM jsonb_array_elements(v_carry) LOOP
      IF COALESCE((v_atom->>'carryover_eligible')::boolean, false)
         AND NOT COALESCE((v_atom->>'done')::boolean, false)
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = v_atom->>'svc') THEN
        v_m := v_m || (v_atom || jsonb_build_object('carried',true));
      END IF;
    END LOOP;
    UPDATE ottoq_visit_needs SET status = 'complete',
           meta = COALESCE(meta,'{}'::jsonb) || jsonb_build_object('carryover_consumed_by', v_visit)
     WHERE visit_id = v_carry_visit;
  END IF;

  v_archetype := CASE
    WHEN v_fault THEN 'E_tech_hold_fault'
    -- 0018: a rider-flagged recall is its own archetype, so the visit is legible
    -- as "this car came back because a customer complained", not as a mystery.
    WHEN v_rf.flag_id IS NOT NULL AND v_rf.status IS DISTINCT FROM 'served' THEN 'R_rider_flag_cleaning'
    WHEN v_ota THEN 'J_ota_wave'
    WHEN v_urgency = 'overnight_hold' THEN 'C_overnight'
    WHEN NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'charge') THEN 'M_pass_through_or_P_triage'
    WHEN v_urgency = 'immediate_dispatch'
         AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'interior_tidy') THEN 'A_charge_clean_go'
    WHEN v_urgency = 'immediate_dispatch' THEN 'D_charge_and_go'
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = 'mechanical_pm') THEN 'B_full_service'
    ELSE 'std_mixed' END;

  UPDATE ottoq_visit_needs SET status = 'superseded'
   WHERE vehicle_id = p_vehicle_id AND status IN ('open','in_progress');
  INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key,
                                 archetype, urgency, dispatch_due_at, target_soc, atoms, meta)
  VALUES (p_vehicle_id, v_run, v_depot, v_clock, v_visit,
          v_archetype, v_urgency, v_due, v_visit_target, v_m,
          jsonb_build_object('plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'service_manifest.v1' END,
                             'crn', v_run IS NOT NULL, 'precip_stress', round(v_precip_stress,3),
                             'wet_boost', round(v_boost,3), 'soc_at_arrival', v_soc,
                             'sla_floor', v_sla_floor, 'generator', 'v4_condition',
                             'rider_flagged', (v_rf.flag_id IS NOT NULL),
                             'rider_flag_kind', v_rf.flag_kind))
  ON CONFLICT (vehicle_id, visit_key) DO UPDATE
    SET atoms = EXCLUDED.atoms, urgency = EXCLUDED.urgency, archetype = EXCLUDED.archetype,
        dispatch_due_at = EXCLUDED.dispatch_due_at, target_soc = EXCLUDED.target_soc,
        meta = EXCLUDED.meta, status = 'open';

  UPDATE vehicles SET config = jsonb_set(
      jsonb_set(COALESCE(config,'{}'::jsonb), '{service_manifest}', v_m),
      '{service_manifest_meta}', jsonb_build_object(
        'visit', v_visit,
        'plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'service_manifest.v1' END,
        'crn', v_run IS NOT NULL,
        'precip_stress', round(v_precip_stress, 3),
        'wet_boost', round(v_boost, 3),
        'urgency', v_urgency,
        'rider_flagged', (v_rf.flag_id IS NOT NULL),
        'generator', 'v4_condition'))
   WHERE id = p_vehicle_id;
  RETURN v_m;
END;
$function$;

-- ============================================================================
-- 8. ASSERTIONS -- run inside the migration. Any failure aborts it.
-- ============================================================================

DO $assert$
DECLARE
  v_depot uuid; v_fleet int; v_seed_a bigint := 987654321; v_seed_b bigint := 123456789;
  v_run1 text; v_run2 text; v_run3 text;
  v_n_a int; v_n_b int; v_int_a int;
  v_p numeric; v_lo int; v_hi int;
  v_st text; v_stalls int;
  v_bay_min numeric; v_bay_avail numeric;
  v_bad int;
BEGIN
  SELECT d.id INTO v_depot FROM depots d WHERE d.name LIKE '%Nashville%' LIMIT 1;
  IF v_depot IS NULL THEN RAISE EXCEPTION 'A0 FAILED: no Nashville depot to assert against'; END IF;
  SELECT count(*) INTO v_fleet FROM vehicles v
   WHERE v.home_depot_id = v_depot AND v.category='autonomous' AND v.is_active;
  v_p := 3.0/100.0;   -- default rider_flag_daily_pct over a 1-day run

  -- A1. DETERMINISM: the same seed must produce the SAME flag set, and a different
  --     seed a different one. Signature over vehicle_id||kind, order-independent.
  SELECT md5(string_agg(t, '|' ORDER BY t)) INTO v_run1 FROM (
    SELECT v.id::text || ':' || CASE WHEN ottoq_sim_seeded_random(v_seed_a,'rflagkind:'||v.id::text) < 0.70
                                     THEN 'interior' ELSE 'exterior' END AS t
      FROM vehicles v
     WHERE v.home_depot_id=v_depot AND v.category='autonomous' AND v.is_active
       AND ottoq_sim_seeded_random(v_seed_a, 'rflag:'||v.id::text) < v_p) s;
  SELECT md5(string_agg(t, '|' ORDER BY t)) INTO v_run2 FROM (
    SELECT v.id::text || ':' || CASE WHEN ottoq_sim_seeded_random(v_seed_a,'rflagkind:'||v.id::text) < 0.70
                                     THEN 'interior' ELSE 'exterior' END AS t
      FROM vehicles v
     WHERE v.home_depot_id=v_depot AND v.category='autonomous' AND v.is_active
       AND ottoq_sim_seeded_random(v_seed_a, 'rflag:'||v.id::text) < v_p) s;
  SELECT md5(string_agg(t, '|' ORDER BY t)) INTO v_run3 FROM (
    SELECT v.id::text AS t FROM vehicles v
     WHERE v.home_depot_id=v_depot AND v.category='autonomous' AND v.is_active
       AND ottoq_sim_seeded_random(v_seed_b, 'rflag:'||v.id::text) < v_p) s;
  IF v_run1 IS DISTINCT FROM v_run2 THEN
    RAISE EXCEPTION 'A1 FAILED: same seed produced two different flag sets (% vs %)', v_run1, v_run2;
  END IF;
  IF v_run1 IS NOT DISTINCT FROM v_run3 THEN
    RAISE EXCEPTION 'A1 FAILED: two different seeds produced an identical flag set -- the draw is not seed-sensitive';
  END IF;
  RAISE NOTICE 'A1 PASS: seed % reproduces exactly (%); seed % differs.', v_seed_a, left(v_run1,12), v_seed_b;

  -- A2. RATE BAND. At the 3%/sim-day default the flag count must land in a sane
  --     binomial band. n=% vehicles, p=0.03 => mean 3.5, sd 1.84 on 116.
  --     Band = [0, mean + 4sd] and strictly less than a tenth of the fleet.
  v_lo := 0;
  v_hi := GREATEST(2, ceil(v_fleet*v_p + 4*sqrt(v_fleet*v_p*(1-v_p)))::int);
  SELECT count(*) INTO v_n_a FROM vehicles v
   WHERE v.home_depot_id=v_depot AND v.category='autonomous' AND v.is_active
     AND ottoq_sim_seeded_random(v_seed_a, 'rflag:'||v.id::text) < v_p;
  SELECT count(*) INTO v_n_b FROM vehicles v
   WHERE v.home_depot_id=v_depot AND v.category='autonomous' AND v.is_active
     AND ottoq_sim_seeded_random(v_seed_b, 'rflag:'||v.id::text) < v_p;
  IF v_n_a < v_lo OR v_n_a > v_hi OR v_n_b < v_lo OR v_n_b > v_hi THEN
    RAISE EXCEPTION 'A2 FAILED: flag counts % and % outside band [%,%] on a fleet of %',
      v_n_a, v_n_b, v_lo, v_hi, v_fleet;
  END IF;
  IF v_n_a > v_fleet/10 THEN
    RAISE EXCEPTION 'A2 FAILED: % flags is more than a tenth of the % vehicle fleet', v_n_a, v_fleet;
  END IF;
  SELECT count(*) INTO v_int_a FROM vehicles v
   WHERE v.home_depot_id=v_depot AND v.category='autonomous' AND v.is_active
     AND ottoq_sim_seeded_random(v_seed_a, 'rflag:'||v.id::text) < v_p
     AND ottoq_sim_seeded_random(v_seed_a, 'rflagkind:'||v.id::text) < 0.70;
  RAISE NOTICE 'A2 PASS: fleet=% band=[%,%] seedA=% (interior %) seedB=%',
    v_fleet, v_lo, v_hi, v_n_a, v_int_a, v_n_b;

  -- A3. EVERY DRAWABLE ATOM RESOLVES TO A STALL TYPE THAT EXISTS IN THIS DEPOT.
  --     detail_bay has zero stalls, so a draw demanding one would be unbookable by
  --     construction. Both rider atoms must fold onto a type with real stalls.
  FOREACH v_st IN ARRAY ARRAY['interior_deep_clean','exterior_wash'] LOOP
    DECLARE v_res text;
    BEGIN
      v_res := ottoq.ottoq_svc_to_stall_type(v_st, v_depot);
      IF v_res IS NULL THEN
        RAISE EXCEPTION 'A3 FAILED: rider atom % resolves to NO stall type', v_st;
      END IF;
      SELECT count(*) INTO v_stalls FROM stalls s
       WHERE s.depot_id = v_depot AND s.stall_type::text = v_res;
      IF v_stalls = 0 THEN
        RAISE EXCEPTION 'A3 FAILED: rider atom % resolves to stall_type % which has ZERO stalls in this depot',
          v_st, v_res;
      END IF;
      RAISE NOTICE 'A3 PASS: % -> % (% stalls)', v_st, v_res, v_stalls;
    END;
  END LOOP;
  IF EXISTS (SELECT 1 FROM stalls s WHERE s.depot_id=v_depot AND s.stall_type::text='detail_bay') THEN
    RAISE NOTICE 'A3 NOTE: detail_bay stalls now exist -- the wash/detail bay sharing note in this migration is stale.';
  ELSE
    RAISE NOTICE 'A3 NOTE (expected): ZERO detail_bay stalls. Interior and exterior rider flags share the same % wash bays.',
      (SELECT count(*) FROM stalls s WHERE s.depot_id=v_depot AND s.stall_type::text='wash_bay');
  END IF;

  -- A4. THE NEW return_trigger PASSES EVERY CONSUMER WITHOUT EXCLUSION.
  --     (a) no CHECK constraint rejects it -- proved by a real insert, rolled back.
  --     (b) no live routine filters it out with a positive IN-list it is missing
  --         from in a way that would DROP the row.
  BEGIN
    CREATE TEMP TABLE _a4 (LIKE public.ottoq_vehicle_dispatches INCLUDING CONSTRAINTS) ON COMMIT DROP;
    INSERT INTO _a4 (dispatch_id, vehicle_id, sim_run_id, status, return_trigger, dispatched_at)
    SELECT gen_random_uuid(), v.id, gen_random_uuid(), 'completed', 'rider_flag_cleaning', now()
      FROM vehicles v LIMIT 1;
    RAISE NOTICE 'A4a PASS: rider_flag_cleaning satisfies every CHECK on ottoq_vehicle_dispatches.';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'A4a FAILED: rider_flag_cleaning rejected by a constraint: % %', SQLSTATE, SQLERRM;
  END;

  SELECT count(*) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq') AND p.prokind='f'
     AND pg_get_functiondef(p.oid) ILIKE '%return_trigger%'
     -- a POSITIVE membership test on return_trigger that does not name the new value
     AND pg_get_functiondef(p.oid) ~* 'return_trigger[[:space:]]*IN[[:space:]]*\('
     AND pg_get_functiondef(p.oid) !~* 'NOT[[:space:]]+IN'
     AND pg_get_functiondef(p.oid) !~* 'rider_flag_cleaning';
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'A4b FAILED: % routine(s) positively filter return_trigger by an IN-list that omits rider_flag_cleaning', v_bad;
  END IF;
  RAISE NOTICE 'A4b PASS: the only IN-lists over return_trigger are NEGATIVE (workload_harness_metrics excludes run_stopped/run_reseed_abort) or additive counters (ottoq_inbound_forecast counts critical_reserve/low_soc_reserve as "critical" -- a rider flag is correctly not counted as an energy-critical return).';

  -- A5. BAY-LOAD / OVERSUBSCRIPTION GUARD (trap 5: ALWAYS HOLD x oversubscription
  --     stalls a run, and it looks like a deadlock rather than a parameter problem).
  --     Projected rider-flag bay minutes per sim-day vs available wash-bay minutes.
  v_bay_min := v_fleet * v_p * (0.70 * 20 + 0.30 * 9);            -- detail 20 min, wash 9 min
  SELECT count(*) * 1440.0 INTO v_bay_avail FROM stalls s
   WHERE s.depot_id=v_depot AND s.stall_type::text='wash_bay';
  IF v_bay_avail <= 0 THEN
    RAISE EXCEPTION 'A5 FAILED: depot has no wash_bay stalls; a rider cleaning flag would be unservable';
  END IF;
  IF v_bay_min > 0.25 * v_bay_avail THEN
    RAISE EXCEPTION 'A5 FAILED: rider flags alone project %% of wash-bay minutes (% of %). Lower rider_flag_daily_pct.',
      round(100*v_bay_min/v_bay_avail,1), round(v_bay_min), round(v_bay_avail);
  END IF;
  RAISE NOTICE 'A5 PASS: rider flags project % bay-min/sim-day against % available (%% of the wash lane). The nightly rotation (~1/3 of % vehicles x 9 min = % bay-min) remains the dominant load.',
    round(v_bay_min,1), round(v_bay_avail,0), round(100*v_bay_min/v_bay_avail,2),
    v_fleet, round(v_fleet/3.0*9,0);

  -- A6. PATH 1: wash_group must now be a per-run seeded draw, i.e. two different
  --     seeds must produce different group assignments over the same fleet.
  SELECT md5(string_agg(v.id::text||':'||floor(3*ottoq_sim_seeded_random(v_seed_a,'washgrp:'||v.id::text))::int::text, '|' ORDER BY v.id))
    INTO v_run1 FROM vehicles v
   WHERE v.home_depot_id=v_depot AND v.category='autonomous' AND v.is_active;
  SELECT md5(string_agg(v.id::text||':'||floor(3*ottoq_sim_seeded_random(v_seed_b,'washgrp:'||v.id::text))::int::text, '|' ORDER BY v.id))
    INTO v_run2 FROM vehicles v
   WHERE v.home_depot_id=v_depot AND v.category='autonomous' AND v.is_active;
  IF v_run1 IS NOT DISTINCT FROM v_run2 THEN
    RAISE EXCEPTION 'A6 FAILED: wash_group is identical under two different seeds -- still not randomized per run';
  END IF;
  SELECT count(*) INTO v_bad FROM (
    SELECT floor(3*ottoq_sim_seeded_random(v_seed_a,'washgrp:'||v.id::text))::int g, count(*) n
      FROM vehicles v
     WHERE v.home_depot_id=v_depot AND v.category='autonomous' AND v.is_active
     GROUP BY 1) s WHERE s.n < v_fleet/6 OR s.n > v_fleet/2;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'A6 FAILED: wash_group thirds are badly unbalanced under seed %', v_seed_a;
  END IF;
  RAISE NOTICE 'A6 PASS: wash_group differs across seeds and splits the fleet into balanced thirds.';

  -- A7. SALT INDEPENDENCE. The four new salts must not collide with each other or
  --     with any existing namespace: identical salts would silently correlate
  --     "independent" variables.
  IF EXISTS (
    SELECT 1 FROM vehicles v
     WHERE v.home_depot_id=v_depot AND v.category='autonomous' AND v.is_active
       AND (ottoq_sim_seeded_random(v_seed_a,'rflag:'||v.id::text)
              = ottoq_sim_seeded_random(v_seed_a,'rflagkind:'||v.id::text)
         OR ottoq_sim_seeded_random(v_seed_a,'rflag:'||v.id::text)
              = ottoq_sim_seeded_random(v_seed_a,'washgrp:'||v.id::text)
         OR ottoq_sim_seeded_random(v_seed_a,'rflagwhen:'||v.id::text)
              = ottoq_sim_seeded_random(v_seed_a,'vnp:soil:'||v.id::text))) THEN
    RAISE EXCEPTION 'A7 FAILED: a new salt collides with another salt';
  END IF;
  RAISE NOTICE 'A7 PASS: rflag: / rflagkind: / rflagwhen: / washgrp: are independent of each other and of vnp:.';

  RAISE NOTICE '0018 ALL ASSERTIONS PASSED.';
END
$assert$;
