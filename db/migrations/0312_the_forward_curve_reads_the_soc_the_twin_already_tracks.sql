-- migration-version: 20260914161504
-- migration-name:    0312_the_forward_curve_reads_the_soc_the_twin_already_tracks
--
-- 0312  ottoq_forecast_net_load's FUTURE-ARRIVAL LOOP COMPUTES EACH VEHICLE'S
--       ENERGY NEED FROM THE LITERAL 30, NOT FROM THE VEHICLE
--
-- One expression changes. The join it needs is already in the query.
--
-- ---------------------------------------------------------------------------
-- THE DEFECT (measured in db/checks/0238)
--
-- Loop 2 of public.ottoq_forecast_net_load, the future-arrivals loop:
--
--   v_kwh := GREATEST(0,(COALESCE(r.target_soc, public.ottoq_default_target_soc())
--                        - p_arrival_soc)/100.0 * COALESCE(r.battery_capacity_kwh,75));
--
-- p_arrival_soc is a PARAMETER whose signature default is 30, and the function's
-- only caller, public.ottoq_bess_reserve_target, passes FIVE arguments:
--
--   v_load := ottoq_forecast_net_load(p_sim_run_id, p_depot_id, p_sim_clock,
--                                     p_horizon_ticks, p_tick_min);
--
-- so the sixth is never supplied. EVERY inbound vehicle is assumed to arrive at
-- 30% state of charge.
--
-- Measured against public.ocpp_sessions (71,941 sessions carrying soc_start):
--   actual mean start SoC 75.6%, median 77.0, p05 50.0, p95 88.0
--   sessions at or below the assumed 30%: 331 of 71,941 = 0.46%
--   mean actual energy delivered: 16.81 kWh against ~45 kWh implied by the 30
--
-- The assumption is wrong for 99.54% of sessions and wrong in the direction that
-- inflates forecast demand by roughly 2.7x.
--
-- LOOP 1 OF THE SAME FUNCTION ALREADY DOES THIS CORRECTLY. The active-session
-- loop reads v.current_soc. The two loops of one forecast disagree about whether
-- the vehicle's state of charge is knowable. It is: the twin updates current_soc
-- continuously while a vehicle is deployed (measured 2026-09-14: 81 'active'
-- dispatches carrying 24 distinct SoC values spanning 56-100%, 19 'returning'
-- carrying 11 distinct spanning 64-100%).
--
-- ---------------------------------------------------------------------------
-- WHAT THIS MIGRATION DOES **NOT** DO, deliberately
--
-- It does NOT subtract drive-home drain. Measured drain over 89,307 completed
-- trips is 0.1103 %/min (median 0.1078, p90 0.1760), so across the engine's
-- 30-minute return ETA the correction is ~3.3 SoC points -- against an error of
-- ~45 points, that is noise. Applying it would mean introducing a NEW constant
-- to remove an old one, which is how 0238's defect class reproduces itself.
-- current_soc is a MEASURED value; the drain coefficient would be a fitted one.
-- This migration replaces a guess with a measurement and stops there.
--
-- It does NOT touch return_eta_minutes, which is the literal 30 in all 123,665
-- rows that carry it (0238 section B). That is a second, separate defect: it
-- moves arrival TIMES and therefore the booking calendar, a far wider blast
-- radius than this scalar. It gets its own migration and its own recert.
--
-- It does NOT turn the forward curve ON. See the next section -- that is the
-- larger lever and it must come AFTER this fix, never before.
--
-- ---------------------------------------------------------------------------
-- forces_recert: FALSE -- AND THE REASON IS MEASURED, NOT ARGUED.
--
-- The whole forward-forecast path is gated. public.ottoq_energy_orchestrate
-- line 64:
--
--   IF ottoq_policy_get(p_sim_run_id, 'energy_reserve_shave', 0) >= 0.5 THEN
--     v_demand_target := COALESCE(ottoq_bess_reserve_target(...), v_demand_target);
--
-- The dial defaults to 0, so unless a run sets it, ottoq_bess_reserve_target --
-- and therefore THIS function -- is never called at all.
--
-- Measured on public.ottoq_sim_runs x ottoq_policy_params:
--   run_by='cert_harness': 1,063 runs, shave ON in 6, OFF in 1,057 (99.4%)
--   and ALL SIX of those shave-on cert runs started 2026-08-29, every one of
--   them BELOW the current recert floor -- so not one contributes to a live
--   canon column.
--
-- So this change cannot move any hash in any canon-contributing run, because
-- the function it edits is not reached by any of them. P2 and P3 below ASSERT
-- that rather than trusting this paragraph, and will refuse the migration if a
-- shave-on cert run has appeared above the floor since it was written.
--
-- THE LINEAGE ROW IS WRITTEN IN THIS FILE. 0308 and 0309 each argued
-- forces_recert=false correctly and omitted the row; the floor moved to 0309's
-- apply stamp and ottoq_cert_matrix returned ZERO columns until 0310 repaired
-- it. Not again.
-- ===========================================================================

CREATE TEMP TABLE IF NOT EXISTS ottoq_0312_witness (
  label text PRIMARY KEY, arr numeric[], peak numeric, total numeric
);

DO $pre$
DECLARE
  v_md5 text; v_readers int; v_shave_above_floor int; v_default text; v_arr numeric[];
  c_run   CONSTANT uuid := '834b3a59-f582-4aec-9317-a30a4989bf4b';
  c_depot CONSTANT uuid := '22222222-2222-2222-2222-222222222222';
  c_clock CONSTANT timestamptz := '2026-09-02 02:00:00+00';
BEGIN
  -- P1. THE FUNCTION IS THE ONE THIS MIGRATION READ. If it has changed since,
  --     the replacement text below may silently drop someone else's edit.
  SELECT md5(p.prosrc) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_forecast_net_load';
  IF v_md5 IS DISTINCT FROM 'eb4da52c6ca633ac4bf0d707756b6f0a' THEN
    RAISE EXCEPTION '0312 P1: ottoq_forecast_net_load prosrc md5 is %, expected eb4da52c6ca633ac4bf0d707756b6f0a; '
                    'the function changed after this migration was written', COALESCE(v_md5,'ABSENT');
  END IF;

  -- P2. THE DEFECT IS STILL PRESENT: the default is still 30 and the only
  --     caller still declines to pass it.
  SELECT pg_get_function_arguments(p.oid) INTO v_default
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_forecast_net_load';
  IF position('p_arrival_soc numeric DEFAULT 30' in v_default) = 0 THEN
    RAISE EXCEPTION '0312 P2: p_arrival_soc no longer defaults to 30 (args: %); re-measure before applying', v_default;
  END IF;
  SELECT count(*) INTO v_readers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc LIKE '%ottoq_forecast_net_load(%'
     AND p.proname <> 'ottoq_forecast_net_load';
  IF v_readers <> 1 THEN
    RAISE EXCEPTION '0312 P2: expected exactly 1 caller of ottoq_forecast_net_load, found %; '
                    'the forces_recert=false argument rests on the caller census', v_readers;
  END IF;

  -- P3. THE INERTNESS CLAIM, ASSERTED. No cert run above the recert floor may
  --     have the forward curve switched on. If one has appeared, this migration
  --     is NOT free and must be reclassified forces_recert=true before applying.
  SELECT count(*) INTO v_shave_above_floor
    FROM public.ottoq_sim_runs r
    JOIN public.ottoq_policy_params pp
      ON pp.scope_type='run' AND pp.scope_id=r.sim_run_id
     AND pp.param_key='energy_reserve_shave' AND pp.param_value >= 0.5
   WHERE r.run_by='cert_harness'
     AND r.started_at > public.ottoq_cert_recert_floor();
  IF v_shave_above_floor <> 0 THEN
    RAISE EXCEPTION '0312 P3: % cert_harness run(s) above the recert floor have energy_reserve_shave >= 0.5; '
                    'this change is no longer inert and must be reclassified forces_recert=true', v_shave_above_floor;
  END IF;

  -- P4. CAPTURE THE BEFORE-STATE on a witness with real inbound vehicles, so
  --     the post-block can assert the change actually took effect rather than
  --     merely that the source text moved.
  v_arr := public.ottoq_forecast_net_load(c_run, c_depot, c_clock, 16, 30);
  IF v_arr IS NULL OR array_length(v_arr,1) IS DISTINCT FROM 16 THEN
    RAISE EXCEPTION '0312 P4: witness forecast is not a 16-element array (got %); pick a new witness',
                    COALESCE(array_length(v_arr,1)::text,'NULL');
  END IF;
  INSERT INTO ottoq_0312_witness(label, arr, peak, total)
  SELECT 'before', v_arr, (SELECT max(u) FROM unnest(v_arr) u), (SELECT sum(u) FROM unnest(v_arr) u)
  ON CONFLICT (label) DO UPDATE SET arr=EXCLUDED.arr, peak=EXCLUDED.peak, total=EXCLUDED.total;
END $pre$;

-- ---------------------------------------------------------------------------
-- THE CHANGE. Loop 2 gains r.current_soc in its cursor and uses it; everything
-- else in this function is byte-identical to what P1 pinned. p_arrival_soc is
-- KEPT as the fallback for a vehicle whose SoC is genuinely unknown, so the
-- signature is unchanged and the existing 5-argument call still binds.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_forecast_net_load(
  p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamp with time zone,
  p_horizon_ticks integer DEFAULT 16, p_tick_min numeric DEFAULT 30,
  p_arrival_soc numeric DEFAULT 30)
 RETURNS numeric[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_base numeric; v_solar numeric; v_load numeric[]; h int; r RECORD;
  v_rate numeric; v_kwh numeric; v_dur_min numeric; v_step_min numeric;
BEGIN
  SELECT COALESCE(building_load_kw,0)+COALESCE(lighting_load_kw,0), COALESCE(solar_generation_kw,0)
    INTO v_base, v_solar FROM site_energy_snapshots
   WHERE depot_id=p_depot_id AND sim_run_id=p_sim_run_id ORDER BY timestamp DESC LIMIT 1;
  v_base := COALESCE(v_base, 50); v_solar := COALESCE(v_solar, 0);
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

  -- net load = base + concurrent charging - solar (floored at base)
  FOR h IN 1..p_horizon_ticks LOOP
    v_load[h] := GREATEST(v_base, v_base + v_load[h] - v_solar);
  END LOOP;
  RETURN v_load;
END;
$function$;

COMMENT ON FUNCTION public.ottoq_forecast_net_load(uuid,uuid,timestamptz,integer,numeric,numeric) IS
'Forward net-load curve over p_horizon_ticks x p_tick_min (default 16 x 30 min = an 8-hour horizon). '
'Loop 1 sums currently-active charging sessions; loop 2 adds scheduled future arrivals. BOTH loops read '
'the vehicle''s own measured current_soc -- loop 2 did not before 0312, it used p_arrival_soc (default 30) '
'for every vehicle, which measured wrong for 99.54% of real arrivals (db/checks/0238). p_arrival_soc is now '
'ONLY the fallback for a vehicle whose current_soc IS NULL. NOTE the arrival TIME axis is still the policy '
'constant 30 minutes (ottoq_vehicle_dispatches.return_eta_minutes is 30 in all rows) -- that is a separate, '
'unfixed defect. This function is reached only when the energy_reserve_shave dial is >= 0.5, via '
'ottoq_bess_reserve_target from ottoq_energy_orchestrate line 64; the dial defaults to 0.';

DO $post$
DECLARE
  v_before numeric[]; v_after numeric[]; v_pk_b numeric; v_pk_a numeric; v_tt_b numeric; v_tt_a numeric;
  v_md5 text; v_args text;
  c_run   CONSTANT uuid := '834b3a59-f582-4aec-9317-a30a4989bf4b';
  c_depot CONSTANT uuid := '22222222-2222-2222-2222-222222222222';
  c_clock CONSTANT timestamptz := '2026-09-02 02:00:00+00';
BEGIN
  -- A1. THE SIGNATURE IS UNCHANGED, so ottoq_bess_reserve_target's 5-argument
  --     call still binds to this function and not to some new overload.
  SELECT pg_get_function_arguments(p.oid), md5(p.prosrc) INTO v_args, v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_forecast_net_load';
  IF position('p_arrival_soc numeric DEFAULT 30' in v_args) = 0 THEN
    RAISE EXCEPTION '0312 A1: signature changed (%); the existing caller would no longer bind', v_args;
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_forecast_net_load') <> 1 THEN
    RAISE EXCEPTION '0312 A1: more than one ottoq_forecast_net_load now exists; an overload was created';
  END IF;

  -- A2. THE SOURCE ACTUALLY CHANGED, in the direction intended.
  IF v_md5 = 'eb4da52c6ca633ac4bf0d707756b6f0a' THEN
    RAISE EXCEPTION '0312 A2: prosrc md5 is unchanged; the replacement did not take';
  END IF;

  -- A3. THE POINT-A-TO-POINT-B ASSERTION. The witness carries 23 inbound
  --     vehicles whose measured SoC averages 84.4% -- every one of them above
  --     the 30 the function used to assume -- so the forecast MUST come down.
  --     A source-text check alone would not prove the value moved.
  SELECT arr, peak, total INTO v_before, v_pk_b, v_tt_b FROM ottoq_0312_witness WHERE label='before';
  IF v_before IS NULL THEN
    RAISE EXCEPTION '0312 A3: the before-state was not captured; the pre-block did not run';
  END IF;
  v_after := public.ottoq_forecast_net_load(c_run, c_depot, c_clock, 16, 30);
  SELECT max(u), sum(u) INTO v_pk_a, v_tt_a FROM unnest(v_after) u;

  IF v_after = v_before THEN
    RAISE EXCEPTION '0312 A3: the witness forecast is byte-identical before and after (peak % kW, total %); '
                    'the change had no effect on a case built to exercise it', v_pk_b, v_tt_b;
  END IF;
  IF v_tt_a > v_tt_b THEN
    RAISE EXCEPTION '0312 A3: forecast total ROSE from % to % on a witness whose vehicles all sit above 30%% SoC; '
                    'reading the real SoC must lower the predicted need, so this is backwards', v_tt_b, v_tt_a;
  END IF;

  RAISE NOTICE '0312 A3 OK -- witness forecast peak % -> % kW, total % -> % kWh-equivalent over 16 ticks',
               v_pk_b, v_pk_a, v_tt_b, v_tt_a;
END $post$;

-- The lineage row, IN THIS FILE, because 0308/0309 omitted theirs and the
-- recert floor swallowed every certification column until 0310 repaired it.
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0312_the_forward_curve_reads_the_soc_the_twin_already_tracks', false,
   'ottoq_forecast_net_load loop 2 now reads each inbound vehicle''s measured current_soc instead of the '
   'p_arrival_soc parameter, whose default 30 was used for every vehicle and measured wrong for 99.54% of '
   'real arrivals (db/checks/0238). Signature, cursor order and every other line are unchanged; '
   'p_arrival_soc is kept as the NULL fallback. forces_recert=false is MEASURED, not argued: the function is '
   'reached only when the energy_reserve_shave dial is >= 0.5, and of 1,063 cert_harness runs only 6 ever had '
   'it on -- all six started 2026-08-29, all below the recert floor, so none contributes to a live canon. '
   'P3 asserts that condition at apply time and refuses if a shave-on cert run has appeared above the floor.',
   now())
ON CONFLICT (name) DO NOTHING;
