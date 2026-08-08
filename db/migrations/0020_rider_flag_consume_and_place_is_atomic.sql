-- migration-version: PENDING
-- migration-name:    rider_flag_consume_and_place_is_atomic
--
-- 0020_rider_flag_consume_and_place_is_atomic.sql
-- ============================================================================
-- A FLAG CANNOT BE MARKED HANDLED UNLESS THE WORK IS ON A VISIT THAT EXISTS
-- ============================================================================
--
-- ══ THE REPORTED DEFECT ══
--
-- After 0019, 2 of 16 rider flags (`f0077a3a`, `99ddf4ff`, both exterior) were
-- advanced to status='recalled' while every run-scoped query said the cleaning
-- had vanished: `recalled_visit_key` appeared to match no row, and neither
-- vehicle appeared to carry a rider-flagged atom on any visit in its run.  Both
-- cars ended `staged_for_departure`.  The brief called this "worse than the bug
-- it replaced", because 0018's failure (2 of 18 stuck visibly `pending`) was at
-- least legible, and this one reported success it had not earned.
--
-- ══ THE LEAD I WAS GIVEN, AND WHAT HAPPENED TO IT ══
--
-- THE LEAD: `twin.ottoq_sim_generate_service_manifest` builds `visit_key` from
-- `vehicles.last_state_change`, which the BEFORE UPDATE trigger
-- `public.log_vehicle_state_change` clobbers to `NOW()` (real wall clock), so a
-- sim-domain key and a real-domain key share one key space and the flag ends up
-- pointing at nothing.
--
-- HALF CONFIRMED, AND **REFUTED AS THE CAUSE OF THIS DEFECT**.
--
--   CONFIRMED, as a phenomenon.  `log_vehicle_state_change` really does execute
--   `NEW.last_state_change = NOW()` on every state change, and it really does
--   overwrite an explicit sim-clock assignment made in the same UPDATE (both
--   `twin.ottoq_sim_wash_triage` and `ottoq.ottoq_rider_flag_indepot_sweep`
--   assign `last_state_change = p_sim_clock` and are silently overridden).  The
--   contamination is visible in the data: 5 of 21 surviving flags carry a
--   `recalled_visit_key` whose timestamp decodes to a REAL wall-clock instant
--   (`20260808154131` x3, `20260808160932` x2) that equals a run's `started_at`,
--   not any sim time.  Two clock domains really are sharing one key space.
--
--   REFUTED, as the cause of THESE TWO.  Both failing keys decode to clean SIM
--   times that match their own recall exactly:
--     f0077a3a ... :20260808200000   flag raised 19:56 sim, recalled 20:00 sim
--     99ddf4ff ... :20260809010000   flag raised 01:00 sim, recalled 01:00 sim
--   Neither is a real-clock value.  The lead cannot explain them.
--
--   AND THE PREMISE UNDER THE LEAD IS FALSE.  `recalled_visit_key` does NOT
--   "match no row in ottoq_visit_needs".  Both keys match a row, on the right
--   vehicle, and BOTH ROWS CARRY THE RIDER-FLAGGED ATOM -- correctly shaped,
--   `must_do:true`, `deferrable:false`, `requires_bay:'wash_bay'`,
--   `rider_flagged:true`, with the recall `why` string.  f0077a3a's wash even
--   reached `status:'done'` at sim 2026-08-09T04:08:49.  **The work did not
--   vanish.  One of the two was actually washed; the other was correctly placed
--   and had not reached a bay when the run ended.**  That is the honest reading,
--   and it is a materially different (and smaller) failure than the one reported.
--
-- ══ WHAT ACTUALLY HAPPENED -- READ FROM THE SCHEMA, NOT INFERRED ══
--
--   `visit_key` = `vehicle_id || ':' || to_char(clock,'YYYYMMDDHH24MISS')`.
--   IT CARRIES NO RUN IDENTIFIER.  And the table's uniqueness was
--
--       UNIQUE (vehicle_id, visit_key)          -- run-blind
--
--   with the generator writing
--
--       ON CONFLICT (vehicle_id, visit_key) DO UPDATE
--         SET atoms=..., urgency=..., archetype=..., meta=..., status='open'
--                                                 -- and NOT sim_run_id
--
--   Runs `a30661fd` and `b857fd29` both had `sim_clock_start = 2026-08-08
--   13:00:00` and both walked the same 30-sim-min tick grid.  So when a vehicle
--   arrived at the same sim minute in both runs, the two runs produced a
--   BYTE-IDENTICAL `visit_key`.  The later run's INSERT therefore fell through to
--   DO UPDATE and OVERWROTE the earlier run's visit row -- replacing its atoms
--   and meta with the new run's manifest, while leaving `sim_run_id` and
--   `created_at` pointing at the EARLIER run.
--
--   Proof, from the surviving rows.  4 visit rows are stamped `sim_run_id =
--   a30661fd` and carry `meta->>'rider_flagged' = 'true'`.  Run a30661fd drew
--   only TWO flags (`aff36072`, `5fe5fe42`).  The other two are `f0077a3a` and
--   `99ddf4ff` -- whose flags belong to run `b857fd29`.  `meta.rider_flagged`
--   can only be written true when a flag exists for that vehicle IN v_run, and
--   run a30661fd had no flag for either car, so run b857fd29 wrote that meta,
--   through DO UPDATE, onto run a30661fd's row.  Those are exactly the two
--   "vanished" flags.
--
--   So the failure is symmetric and worse than it looked in one direction and
--   better in the other:
--     (i)  the CURRENT run's rider work becomes invisible to every run-scoped
--          query, which is what was reported as "the cleaning vanished"; and
--     (ii) an ALREADY-COMPLETED run's ledger is silently rewritten after the
--          fact by a later run.  That is a black-box integrity problem well
--          beyond rider flags, and nobody was looking for it.
--
--   `recalled_visit_key` being a reconstructed STRING with no referential
--   integrity is what let this stay invisible: there was no way for the database
--   to notice the flag and the visit had drifted apart.
--
--   EXTERIOR-ONLY WAS A COINCIDENCE.  The mechanism is kind-agnostic -- it needs
--   only a vehicle arriving at the same sim minute in two runs sharing a
--   `sim_clock_start`.  Nothing in it reads `flag_kind`.  At n=2 the exterior
--   clustering carries no signal.
--
-- ══ WHAT THIS FILE CHANGES ══
--
--  (1) RUN-SCOPED UNIQUENESS.  `UNIQUE (vehicle_id, visit_key)` is replaced by a
--      unique index on (vehicle_id, visit_key, COALESCE(sim_run_id, nil-uuid)),
--      and both upserts are re-inferred onto it.  Two runs are now two visits.
--      Deliberately done at the INDEX, not by changing the key STRING: `visit_key`
--      is also the salt for every `ottoq_sim_seeded_random(v_seed, v_visit||...)`
--      draw in the manifest, so putting a run tag in the string would change
--      every manifest draw and unpin seed 424242.  This route changes no draw.
--
--  (2) CONSUME-AND-PLACE IS ONE ATOMIC STEP, KEYED ON `visit_id`.  The flag is no
--      longer written in the middle of manifest assembly, before any visit row
--      exists.  The manifest block now only READS the flag and shapes the atom;
--      the upsert gains `RETURNING visit_id`; and the flag transition happens
--      AFTER that, stamping the new `recalled_visit_id` uuid.  Same for the
--      in-depot sweep.  Nothing resolves a visit by rebuilding a string any more.
--
--  (3) THE ASSERTION 0019 SHOULD HAVE HAD, AS A RUNTIME GUARD.  A BEFORE trigger
--      on `ottoq_rider_cleaning_flags` refuses any transition to a non-`pending`
--      status unless `recalled_visit_id` resolves to a visit that EXISTS, is the
--      SAME vehicle, is the SAME run, and CARRIES a `rider_flagged` atom.  It
--      raises SQLSTATE 'OQ020'.  This bug class is silent, so the guard is loud:
--      it aborts the statement at the moment of the lie rather than leaving a
--      ledger to be audited later.  See the RISK note at section 5.
--
--  (4) `served_at_sim_clock` IS ACTUALLY STAMPED.  Neither the in-depot sweep nor
--      the arrival path ever stamped it on completion -- only the retire branch
--      did, and that requires the vehicle to ARRIVE AGAIN.  That is the 6-of-16
--      "served" against 11-of-16 done-by-atom undercount.  Fixed with ONE trigger
--      on `ottoq_visit_needs` that fires when a rider-flagged atom reaches
--      `status='done'`, rather than by patching each of the two writers
--      (`twin.ottoq_sim_advance_visit_atoms`, `public.ottoq_mark_visit_atoms_done`)
--      and missing the third one somebody adds later.
--
--  (5) THE MIS-ANCHORING IS FIXED -- SEE THE DECISION BELOW.
--
-- ══ THE ANCHORING DECISION (asked for explicitly) ══
--
--  CONFIRMED FIRST.  `public.ottoq_start_demo_run` calls
--  `ottoq_sim_run_scenario(...)` -- which runs `ottoq_run_boot_draw`, and the
--  draw anchors every flag at `v_run.sim_clock_start + seeded offset` -- and only
--  THEN rebases `sim_clock_start` to a random minute-of-day.  So a run started
--  from the normal start button anchors its flags against a clock that no longer
--  exists, off by up to a full day.
--
--  DECIDED: FIX IT, and fix it where it cannot be routed around.  0019 avoided it
--  by calling `ottoq_sim_run_scenario(...,'operator_demo')` directly, which is not
--  what the founder presses.  A feature that only works when you bypass the start
--  button is not a working feature.
--
--  HOW: not by rewriting `ottoq_start_demo_run` (a 3rd function replaced for one
--  clause), but with a trigger on `ottoq_sim_runs` that shifts every still-pending
--  flag by exactly the delta whenever `sim_clock_start` moves.  That is strictly
--  more total: it holds for `ottoq_start_demo_run`, for any future rebaser, and
--  for a hand-run UPDATE.  The seeded offset inside the window is preserved
--  exactly -- only the base moves -- so the draw stays deterministic.
--
--  NOT FIXED HERE, AND NAMED: the same start path also forces live playback
--  clamped to 3x, which is the other half of why a normally-started run cannot
--  reach night.  That is a playback-rate concern with no bearing on flag
--  correctness, it is not what this file is about, and changing tick pacing
--  underneath a metronome that has its own timeout ceiling (0012/0013) is not a
--  change to make as a rider on a data-integrity migration.  Deferred on purpose.
--
-- ══ WHAT IS DELIBERATELY NOT CHANGED ══
--
--  The `log_vehicle_state_change` clock clobber is REAL and is left alone.  Once
--  uniqueness is run-scoped it can no longer cause a cross-run collision, which
--  was its only path to losing work; what remains is that some `visit_key`s are
--  ugly (real-clock) rather than wrong.  Fixing it means either changing a
--  BEFORE UPDATE trigger that fires on every vehicle write in the system, or
--  re-sourcing `v_clock` in the manifest -- and `v_clock` seeds every
--  `ottoq_sim_seeded_random` salt, so re-sourcing it changes every draw in every
--  run.  Neither is worth it to fix cosmetics.  Logged as a residual.
--
-- ══ md5 GUARDS ══
--  Pre-images this file was written against, captured from the live instance:
--    twin.ottoq_sim_generate_service_manifest  dd6ac3a84afd12aa94cf8d09e74ffeda
--    ottoq.ottoq_rider_flag_indepot_sweep      79353bd68e81b5180565161a6af59847
--  Section 0 refuses to proceed if either has moved.  Nothing is DROPped: the two
--  functions are CREATE OR REPLACEd, and the one constraint that is dropped has
--  its exact definition captured to `public.mig0020_prestate` first.
-- ============================================================================

BEGIN;

SET LOCAL statement_timeout = '120s';
SET LOCAL lock_timeout      = '15s';

-- ============================================================================
-- 0. md5 GUARD + PRE-STATE CAPTURE.  Refuse to run against a surprise.
-- ============================================================================
DO $guard$
DECLARE
  v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_generate_service_manifest';
  IF v_md5 IS DISTINCT FROM 'dd6ac3a84afd12aa94cf8d09e74ffeda' THEN
    RAISE EXCEPTION '0020 ABORT: twin.ottoq_sim_generate_service_manifest pre-image is %, expected dd6ac3a84afd12aa94cf8d09e74ffeda', COALESCE(v_md5,'<missing>');
  END IF;

  SELECT md5(pg_get_functiondef(p.oid)) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_rider_flag_indepot_sweep';
  IF v_md5 IS DISTINCT FROM '79353bd68e81b5180565161a6af59847' THEN
    RAISE EXCEPTION '0020 ABORT: ottoq.ottoq_rider_flag_indepot_sweep pre-image is %, expected 79353bd68e81b5180565161a6af59847', COALESCE(v_md5,'<missing>');
  END IF;
END
$guard$;

-- The only thing this file drops is one constraint.  Capture it verbatim first,
-- in a table that is NOT ottoq-prefixed so a run start cannot purge it.
CREATE TABLE IF NOT EXISTS public.mig0020_prestate (
  captured_at timestamptz NOT NULL DEFAULT now(),
  object      text        NOT NULL,
  definition  text        NOT NULL
);

INSERT INTO public.mig0020_prestate (object, definition)
SELECT 'constraint ' || conrelid::regclass || '.' || conname, pg_get_constraintdef(oid)
  FROM pg_constraint
 WHERE conrelid = 'public.ottoq_visit_needs'::regclass
   AND conname  = 'ottoq_visit_needs_vehicle_id_visit_key_key'
   AND NOT EXISTS (SELECT 1 FROM public.mig0020_prestate
                    WHERE object = 'constraint public.ottoq_visit_needs.ottoq_visit_needs_vehicle_id_visit_key_key');

INSERT INTO public.mig0020_prestate (object, definition)
SELECT n.nspname || '.' || p.proname, pg_get_functiondef(p.oid)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname, p.proname) IN (('twin','ottoq_sim_generate_service_manifest'),
                                  ('ottoq','ottoq_rider_flag_indepot_sweep'))
   AND NOT EXISTS (SELECT 1 FROM public.mig0020_prestate m
                    WHERE m.object = n.nspname || '.' || p.proname);

-- ============================================================================
-- 1. RUN-SCOPED UNIQUENESS ON ottoq_visit_needs
-- ============================================================================
-- Nothing references the old constraint (checked: the only FK pointing at this
-- table is ottoq_ops_approvals.visit_id -> visit_id, the PRIMARY KEY), and the
-- only two ON CONFLICT sites naming it are the two functions replaced below.

CREATE UNIQUE INDEX IF NOT EXISTS ottoq_visit_needs_vehicle_visit_run_uk
  ON public.ottoq_visit_needs
     (vehicle_id, visit_key, (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)));

ALTER TABLE public.ottoq_visit_needs
  DROP CONSTRAINT IF EXISTS ottoq_visit_needs_vehicle_id_visit_key_key;

-- ============================================================================
-- 2. THE FLAG POINTS AT A VISIT BY ID, NOT BY A REBUILT STRING
-- ============================================================================
-- `recalled_visit_key` is KEPT (never drop) and keeps being written, because it
-- is human-readable in the ledger and evidence queries already read it.  It is
-- no longer LOAD-BEARING: nothing resolves a visit through it after this file.
ALTER TABLE public.ottoq_rider_cleaning_flags
  ADD COLUMN IF NOT EXISTS recalled_visit_id uuid;

DO $fk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conrelid = 'public.ottoq_rider_cleaning_flags'::regclass
                    AND conname  = 'ottoq_rider_cleaning_flags_recalled_visit_id_fkey') THEN
    -- ON DELETE CASCADE on purpose.  Flags and visits are both run-scoped and are
    -- purged together at run start.  SET NULL would instead fire an UPDATE on the
    -- flag row during a purge, which the section-5 guard would then refuse --
    -- turning a routine teardown into a hard failure.  CASCADE deletes the row,
    -- fires no UPDATE, and reaches the same end state.
    ALTER TABLE public.ottoq_rider_cleaning_flags
      ADD CONSTRAINT ottoq_rider_cleaning_flags_recalled_visit_id_fkey
      FOREIGN KEY (recalled_visit_id) REFERENCES public.ottoq_visit_needs(visit_id)
      ON DELETE CASCADE;
  END IF;
END
$fk$;

CREATE INDEX IF NOT EXISTS ottoq_rider_cleaning_flags_recalled_visit_id_idx
  ON public.ottoq_rider_cleaning_flags (recalled_visit_id);

-- Backfill what can be resolved honestly, so the surviving evidence rows are not
-- left in a shape the guard would consider a lie.  Resolved by (vehicle_id,
-- visit_key) AND requiring the visit to actually carry a rider-flagged atom --
-- an unresolvable legacy row is LEFT NULL rather than guessed at.
UPDATE public.ottoq_rider_cleaning_flags f
   SET recalled_visit_id = v.visit_id
  FROM public.ottoq_visit_needs v
 WHERE f.recalled_visit_id IS NULL
   AND f.status <> 'pending'
   AND v.vehicle_id = f.vehicle_id
   AND v.visit_key  = f.recalled_visit_key
   AND v.sim_run_id IS NOT DISTINCT FROM f.sim_run_id
   AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v.atoms,'[]'::jsonb)) e
                WHERE COALESCE((e->>'rider_flagged')::boolean, false));
-- The same-run clause is what makes this backfill honest rather than tidy. The
-- two flags this migration exists for (f0077a3a, 99ddf4ff) DO have a key match
-- carrying the atom -- on a row belonging to the PREVIOUS run. Binding them would
-- launder the defect into a clean-looking ledger. They are left NULL, which is
-- the truthful state, and the next visit re-places their work.

-- ============================================================================
-- 3. THE MANIFEST GENERATOR -- CONSUME AFTER PLACE, KEYED ON visit_id
-- ============================================================================
-- Only three regions differ from the 0019 pre-image:
--   (a) the rider-flag block no longer WRITES the flag; it only reads it and
--       shapes the atom, and remembers the previously-consumed visit_id;
--   (b) the upsert is re-inferred onto the run-scoped index and gains RETURNING;
--   (c) a new block after the upsert performs the flag transition against the
--       visit_id that was actually written.
-- Everything else -- every probability, every seeded salt, every atom shape --
-- is byte-identical to the pre-image on purpose.
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
  -- 0018. SCALARS, not a RECORD: the flag lookup is skipped entirely when v_run is
  -- NULL (benchmark / no active run), and reading a field of a never-assigned
  -- plpgsql RECORD raises "record is not assigned yet". Scalars are NULL-safe.
  v_rf_id uuid; v_rf_kind text; v_rf_status text; v_rf_visit text;
  v_rf_svc text; v_rf_min int;
  -- 0020. The visit row this call actually wrote, and the visit the flag was
  -- previously consumed by. Both uuids. Nothing is resolved by string any more.
  v_visit_id uuid; v_rf_prev_visit_id uuid; v_this_visit_id uuid;
  v_rf_place boolean := false; v_rf_retire boolean := false;
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
  -- 0020 NOTE. v_visit is UNCHANGED on purpose. It is not only the visit_key, it
  -- is the salt for every ottoq_sim_seeded_random draw below. Run scoping is done
  -- at the unique INDEX instead, so no draw moves and seed pinning survives.
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
  -- 0018 PATH 2 -- RIDER-FLAGGED CLEANING, RESHAPED BY 0020.
  --
  -- 0019 wrote the flag to 'recalled' RIGHT HERE, in the middle of assembling a
  -- manifest, ~120 lines before any visit row existed to carry it. That ordering
  -- is what made the failure silent: the ledger recorded "handled" against a
  -- visit_key that was still only a string in a variable, and nothing downstream
  -- could tell whether the row that key named was this run's or a previous run's.
  --
  -- 0020 SPLITS THE STEP: this block only READS the flag and shapes the atom.
  -- The flag transition happens after the upsert, against the visit_id the
  -- database actually returned. See section (0020 CONSUME) below.
  -- ==========================================================================
  IF v_run IS NOT NULL THEN
    SELECT f.flag_id, f.flag_kind, f.status, f.recalled_visit_key, f.recalled_visit_id
      INTO v_rf_id, v_rf_kind, v_rf_status, v_rf_visit, v_rf_prev_visit_id
      FROM public.ottoq_rider_cleaning_flags f
     WHERE f.sim_run_id = v_run AND f.vehicle_id = p_vehicle_id
       AND f.status IN ('pending','recalled')
       AND f.raised_at_sim_clock <= v_clock;

    IF v_rf_id IS NOT NULL THEN
      -- TOTAL: 'exterior' takes the wash lane; interior AND anything unrecognised
      -- takes the detail lane. An unknown word must never silently drop the work.
      IF v_rf_kind = 'exterior' THEN
        v_rf_svc := 'exterior_wash'; v_rf_min := v_wash_min;
      ELSE
        v_rf_svc := 'interior_deep_clean'; v_rf_min := v_deep_min;
      END IF;

      -- RETIRE-OR-PLACE, decided by uuid instead of by string comparison.
      -- 0019 asked "is the key I just rebuilt different from the key stored on the
      -- flag?" -- two strings from two clock domains and two runs, compared as if
      -- they named the same thing. The question it MEANT to ask is "is the visit
      -- row this call is about to write the same ROW that already consumed this
      -- flag?", so ask that: look up the row this upsert will land on, on the same
      -- run-scoped unique index the upsert infers.
      --
      -- Decided HERE, before the atom is shaped, and not after the upsert. Placing
      -- first and retiring afterwards would leave a must_do, non-deferrable
      -- cleaning stranded on the new visit that nothing will ever clear -- and
      -- ALWAYS HOLD would then keep a clean car in the depot indefinitely.
      SELECT n.visit_id INTO v_this_visit_id
        FROM ottoq_visit_needs n
       WHERE n.vehicle_id = p_vehicle_id
         AND n.visit_key  = v_visit
         AND COALESCE(n.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
           = COALESCE(v_run,        '00000000-0000-0000-0000-000000000000'::uuid);

      IF v_rf_status = 'recalled'
         AND v_rf_prev_visit_id IS NOT NULL
         AND v_rf_prev_visit_id IS DISTINCT FROM v_this_visit_id THEN
        -- A different visit already took this cleaning. Retire the flag; do not
        -- re-emit the atom, or the car gets washed twice and held for the second.
        v_rf_retire := true;
        v_rf_status := 'served';
      ELSE
        v_rf_place  := true;
        v_rf_status := 'recalled';
      END IF;
    END IF;

    IF v_rf_place THEN
      -- If the routine draw already put this atom on the visit, PROMOTE it to
      -- must_do rather than adding a duplicate; otherwise append it.
      IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_m) e WHERE e->>'svc' = v_rf_svc) THEN
        SELECT jsonb_agg(CASE WHEN a->>'svc' = v_rf_svc
                              THEN a || jsonb_build_object('must_do', true, 'deferrable', false,
                                     'carryover_eligible', false,
                                     'rider_flagged', true,
                                     'rider_flag_kind', COALESCE(v_rf_kind,'interior'),
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
          'rider_flag_kind', COALESCE(v_rf_kind,'interior'),
          'return_trigger', 'rider_flag_cleaning',
          'why', 'Rider-reported ' || COALESCE(v_rf_kind,'interior')
                 || ' cleanliness issue; vehicle was recalled for this.');
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
    WHEN v_rf_id IS NOT NULL AND v_rf_status = 'recalled' THEN 'R_rider_flag_cleaning'
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
  -- 0020: the conflict target is now the RUN-SCOPED index. Two runs walking the
  -- same sim clock produce two visits, not one row overwritten by the other.
  -- RETURNING gives the atomic step below a real uuid to bind the flag to.
  INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key,
                                 archetype, urgency, dispatch_due_at, target_soc, atoms, meta)
  VALUES (p_vehicle_id, v_run, v_depot, v_clock, v_visit,
          v_archetype, v_urgency, v_due, v_visit_target, v_m,
          jsonb_build_object('plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'service_manifest.v1' END,
                             'crn', v_run IS NOT NULL, 'precip_stress', round(v_precip_stress,3),
                             'wet_boost', round(v_boost,3), 'soc_at_arrival', v_soc,
                             'sla_floor', v_sla_floor, 'generator', 'v4_condition',
                             'rider_flagged', (v_rf_id IS NOT NULL AND v_rf_status = 'recalled'),
                             'rider_flag_kind', v_rf_kind))
  ON CONFLICT (vehicle_id, visit_key, (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)))
  DO UPDATE
    SET atoms = EXCLUDED.atoms, urgency = EXCLUDED.urgency, archetype = EXCLUDED.archetype,
        dispatch_due_at = EXCLUDED.dispatch_due_at, target_soc = EXCLUDED.target_soc,
        meta = EXCLUDED.meta, status = 'open'
  RETURNING visit_id INTO v_visit_id;

  -- ══════════════════ 0020 CONSUME -- ONE ATOMIC STEP ══════════════════
  -- The visit row now EXISTS and carries the atom. Only now may the flag say it
  -- has been handled, and it says so by pointing at that row's visit_id.
  --
  -- The place-or-retire decision was already taken, by uuid, above. All that is
  -- left is to record it against the row the database just handed back. If the
  -- upsert somehow returned nothing, the flag is NOT touched: it stays 'pending'
  -- and is re-offered next tick. Failing to consume is recoverable; consuming
  -- without placing is the defect.
  IF v_rf_id IS NOT NULL AND v_visit_id IS NOT NULL THEN
    IF v_rf_retire THEN
      UPDATE public.ottoq_rider_cleaning_flags
         SET status = 'served', served_at_sim_clock = COALESCE(served_at_sim_clock, v_clock)
       WHERE flag_id = v_rf_id;
    ELSIF v_rf_place THEN
      UPDATE public.ottoq_rider_cleaning_flags
         SET status                = 'recalled',
             recalled_at_sim_clock = COALESCE(recalled_at_sim_clock, v_clock),
             recalled_visit_key    = v_visit,
             recalled_visit_id     = v_visit_id
       WHERE flag_id = v_rf_id;
    END IF;
  END IF;

  UPDATE vehicles SET config = jsonb_set(
      jsonb_set(COALESCE(config,'{}'::jsonb), '{service_manifest}', v_m),
      '{service_manifest_meta}', jsonb_build_object(
        'visit', v_visit,
        'visit_id', v_visit_id,
        'plan', CASE WHEN v_plan IS NULL THEN 'legacy' ELSE 'service_manifest.v1' END,
        'crn', v_run IS NOT NULL,
        'precip_stress', round(v_precip_stress, 3),
        'wet_boost', round(v_boost, 3),
        'urgency', v_urgency,
        'rider_flagged', (v_rf_id IS NOT NULL AND v_rf_status = 'recalled'),
        'generator', 'v4_condition'))
   WHERE id = p_vehicle_id;
  RETURN v_m;
END;
$function$;

-- ============================================================================
-- 4. THE IN-DEPOT SWEEP -- SAME TWO CORRECTIONS
-- ============================================================================
-- Differs from the 0019 pre-image in three places:
--   (a) the open/in_progress lookup is scoped STRICTLY to this run. 0019 allowed
--       `OR n.sim_run_id IS NULL`, which is the same cross-run leak in another
--       costume, and it would now be refused by the section-5 guard anyway;
--   (b) the flag transition stamps `recalled_visit_id`;
--   (c) the catch-all handler no longer swallows the guard. A handler that turns
--       "this placement is a lie" into RAISE WARNING + RETURN 0 would restore
--       exactly the silence this file exists to remove, so SQLSTATE 'OQ020' is
--       re-raised.
CREATE OR REPLACE FUNCTION ottoq.ottoq_rider_flag_indepot_sweep(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec RECORD;
  v_n int := 0; v_opened int := 0; v_appended int := 0;
  v_svc text; v_min int; v_bay text; v_stall_type text;
  v_visit_id uuid; v_visit_key text; v_atoms jsonb; v_has boolean;
  v_atom jsonb; v_holding boolean;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  FOR v_rec IN
    SELECT f.flag_id, f.vehicle_id, f.flag_kind, f.raised_at_sim_clock,
           v.current_state::text AS vstate
      FROM public.ottoq_rider_cleaning_flags f
      JOIN public.vehicles v ON v.id = f.vehicle_id
     WHERE f.sim_run_id = p_sim_run_id
       AND f.status     = 'pending'
       AND f.raised_at_sim_clock <= p_clock
       AND v.home_depot_id = p_depot_id
       -- NOT ON THE ROAD. This is the exact complement of the condition
       -- public.ottoq_evaluate_return_need requires, so between the two of them
       -- every flagged vehicle is owned by exactly one path and never by both.
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches d
                        WHERE d.vehicle_id = f.vehicle_id
                          AND d.sim_run_id = p_sim_run_id
                          AND d.status IN ('active','returning'))
       AND v.current_state NOT IN ('deployed','en_route_to_deployment','en_route_to_depot')
     ORDER BY f.raised_at_sim_clock, f.vehicle_id
     LIMIT 40
  LOOP
    -- TOTAL MAPPING. Identical to the one 0018 uses in the arrival manifest.
    IF v_rec.flag_kind = 'exterior' THEN
      v_svc := 'exterior_wash';        v_min := 25; v_bay := 'wash_bay';
    ELSE
      v_svc := 'interior_deep_clean';  v_min := 35; v_bay := 'detail';
    END IF;

    -- Resolve through the same total resolver the booker uses, so an atom that
    -- names a stall type this depot does not have is impossible rather than
    -- discovered at booking time. NULL here would mean "no bay", which for a
    -- cleaning atom is wrong, so fall back to the wash lane explicitly.
    v_stall_type := COALESCE(ottoq.ottoq_svc_to_stall_type(v_svc, p_depot_id), 'wash_bay');

    v_atom := jsonb_build_object(
      'svc', v_svc, 'must_do', true, 'deferrable', false,
      'est_min', v_min, 'concurrency', 'bay',
      'requires_bay', v_bay,
      'stall_type_required', v_stall_type,
      'carryover_eligible', false,
      'rider_flagged', true,
      'rider_flag_kind', COALESCE(v_rec.flag_kind, 'interior'),
      'return_trigger', 'rider_flag_cleaning',
      'raised_in_depot', true,
      'why', 'Rider-reported ' || COALESCE(v_rec.flag_kind,'interior')
             || ' cleanliness issue. The vehicle was already in the depot when the '
             || 'report matured, so the cleaning was added to this visit rather than '
             || 'triggering a recall.');

    -- The newest OPEN / IN_PROGRESS visit for this vehicle IN THIS RUN.
    -- 0020: `OR n.sim_run_id IS NULL` removed. Attaching this run's rider work to
    -- a run-less or foreign visit row is the same cross-run defect this file
    -- exists to close; if no in-run visit is open, one is opened below.
    v_visit_id := NULL; v_visit_key := NULL; v_atoms := NULL;
    SELECT n.visit_id, n.visit_key, n.atoms
      INTO v_visit_id, v_visit_key, v_atoms
      FROM public.ottoq_visit_needs n
     WHERE n.vehicle_id = v_rec.vehicle_id
       AND n.status IN ('open','in_progress')
       AND n.sim_run_id = p_sim_run_id
     ORDER BY n.created_at DESC
     LIMIT 1;

    IF v_visit_id IS NOT NULL THEN
      -- PROMOTE-OR-APPEND, exactly as 0018 does on arrival: if the routine draw
      -- already put this atom on the visit, make it must_do rather than adding a
      -- duplicate the sequencer would try to work twice.
      SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_atoms,'[]'::jsonb)) e
                      WHERE e->>'svc' = v_svc) INTO v_has;
      IF v_has THEN
        UPDATE public.ottoq_visit_needs n
           SET atoms = (SELECT jsonb_agg(CASE WHEN a->>'svc' = v_svc
                                 THEN a || jsonb_build_object(
                                        'must_do', true, 'deferrable', false,
                                        'carryover_eligible', false,
                                        'rider_flagged', true,
                                        'rider_flag_kind', COALESCE(v_rec.flag_kind,'interior'),
                                        'return_trigger', 'rider_flag_cleaning',
                                        'raised_in_depot', true)
                                 ELSE a END)
                          FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) a),
               meta  = COALESCE(n.meta,'{}'::jsonb)
                       || jsonb_build_object('rider_flagged', true,
                                             'rider_flag_kind', v_rec.flag_kind,
                                             'rider_flag_path', 'indepot_sweep')
         WHERE n.visit_id = v_visit_id;
      ELSE
        UPDATE public.ottoq_visit_needs n
           SET atoms = COALESCE(n.atoms,'[]'::jsonb) || v_atom,
               meta  = COALESCE(n.meta,'{}'::jsonb)
                       || jsonb_build_object('rider_flagged', true,
                                             'rider_flag_kind', v_rec.flag_kind,
                                             'rider_flag_path', 'indepot_sweep')
         WHERE n.visit_id = v_visit_id;
      END IF;
      v_appended := v_appended + 1;
    ELSE
      -- NO OPEN VISIT. This is the 15-sim-hour case: the car finished its visit,
      -- the flag matured afterwards, and there was nothing left to attach work
      -- to. Open a visit whose whole content is the cleaning. urgency
      -- 'standard' on purpose -- 'overnight_hold' carries a dispatch_due_at gate
      -- in ottoq_decide_tick (2) that would hold the car past the work.
      v_visit_key := v_rec.vehicle_id::text || ':rf:' || to_char(p_clock, 'YYYYMMDDHH24MISS');
      INSERT INTO public.ottoq_visit_needs
        (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, archetype,
         urgency, atoms, status, source, meta)
      VALUES
        (v_rec.vehicle_id, p_sim_run_id, p_depot_id, p_clock, v_visit_key,
         'R_rider_flag_cleaning', 'standard', jsonb_build_array(v_atom), 'open',
         'rider_flag_indepot_sweep',
         jsonb_build_object('rider_flagged', true,
                            'rider_flag_kind', v_rec.flag_kind,
                            'rider_flag_path', 'indepot_sweep',
                            'generator', 'ottoq_rider_flag_indepot_sweep'))
      ON CONFLICT (vehicle_id, visit_key, (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)))
      DO UPDATE
        SET atoms = EXCLUDED.atoms, status = 'open', meta = EXCLUDED.meta
      RETURNING visit_id INTO v_visit_id;
      v_opened := v_opened + 1;
    END IF;

    -- THE FLAG IS NOW CONSUMED, AND ONLY NOW. Ownership has moved to the must_do
    -- atom on the visit named by v_visit_id -- a row that provably exists,
    -- because the database just handed back its primary key. 0019 stamped a
    -- reconstructed string here instead; that is the defect this closes.
    UPDATE public.ottoq_rider_cleaning_flags
       SET status                = 'recalled',
           recalled_at_sim_clock = COALESCE(recalled_at_sim_clock, p_clock),
           recalled_visit_key    = v_visit_key,
           recalled_visit_id     = v_visit_id,
           stall_type_required   = COALESCE(stall_type_required, v_stall_type)
     WHERE flag_id = v_rec.flag_id;

    -- Put the car where the bay router can see it, but ONLY if it is holding.
    v_holding := v_rec.vstate IN ('staged_for_departure','charge_complete_holding',
                                  'service_complete_holding','staged_awaiting_service','offline');
    IF v_holding AND v_rec.vstate <> 'staged_awaiting_service' THEN
      UPDATE public.vehicles
         SET current_state     = 'staged_awaiting_service'::vehicle_state,
             last_state_change = p_clock,
             config            = jsonb_set(COALESCE(config,'{}'::jsonb),
                                           '{svc_step}', to_jsonb('need_service'::text))
       WHERE id = v_rec.vehicle_id;
    END IF;

    -- Give the visit an itinerary so the bay leg exists. Never fatal: section
    -- 4b of ottoq_decide_tick can place the vehicle from the needs card alone.
    IF v_holding THEN
      BEGIN
        PERFORM public.ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.vehicle_id, p_clock);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'rider flag in-depot replan failed for %: % %', v_rec.vehicle_id, SQLSTATE, SQLERRM;
      END;
    END IF;

    v_n := v_n + 1;
  END LOOP;

  -- ONE summary event per tick. Event-write amplification is the known tick-cost
  -- driver on this instance (0012), so this stage never writes per vehicle.
  IF v_n > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'rider_flag_indepot_sweep',
        p_event_type := 'ottoq.rider_flag_serviced_in_depot',
        p_entity_type := 'depot', p_entity_id := p_depot_id, p_depot_id := p_depot_id,
        p_payload := jsonb_build_object(
          'flags_actioned', v_n, 'visits_opened', v_opened, 'visits_appended', v_appended,
          'sim_clock', p_clock,
          'doctrine', 'a parked car needs no recall, it needs the atom on its visit'),
        p_severity := 'info', p_ingest_source := 'ottoq', p_data_source := 'twin',
        p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'rider flag sweep summary event dropped: % %', SQLSTATE, SQLERRM;
    END;
  END IF;

  RETURN v_n;
EXCEPTION
  -- 0020. The placement guard is NOT swallowed. Everything else still fails safe.
  WHEN SQLSTATE 'OQ020' THEN
    RAISE;
  WHEN OTHERS THEN
    RAISE WARNING 'ottoq_rider_flag_indepot_sweep FAILED SAFELY: % %', SQLSTATE, SQLERRM;
    RETURN 0;
END
$function$;

-- ============================================================================
-- 5. THE RUNTIME GUARD -- A FLAG MAY NOT CLAIM WORK THAT IS NOT ON A VISIT
-- ============================================================================
-- This is the assertion 0019 should have carried, and it is a TRIGGER rather
-- than a migration-time check on purpose: the failure class is silent, so it has
-- to fail at the instant it happens, not at the next audit.
--
-- RISK, STATED PLAINLY. This raises, and callers of the manifest generator (e.g.
-- twin.ottoq_sim_generate_arrival_manifests) have no handler, so a violation
-- aborts the tick. That is deliberate and it is the point: a stopped run that
-- says why beats a finished run that quietly lost a customer complaint. The
-- guard only fires on an actual TRANSITION (INSERT, or a change of status /
-- recalled_visit_id), so routine UPDATEs and teardown do not touch it.
CREATE OR REPLACE FUNCTION public.ottoq_rider_flag_placement_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_veh uuid; v_run uuid; v_has_atom boolean;
BEGIN
  -- Only a transition is interesting.
  IF TG_OP = 'UPDATE'
     AND NEW.status            IS NOT DISTINCT FROM OLD.status
     AND NEW.recalled_visit_id IS NOT DISTINCT FROM OLD.recalled_visit_id THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'pending' THEN
    RETURN NEW;
  END IF;

  IF NEW.recalled_visit_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = 'OQ020',
      MESSAGE = format('rider flag %s (vehicle %s) moved to status ''%s'' with no visit bound to it',
                       NEW.flag_id, NEW.vehicle_id, NEW.status),
      HINT    = 'consume-and-place must be one step: write the visit, then bind the flag to the returned visit_id';
  END IF;

  SELECT n.vehicle_id, n.sim_run_id,
         EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) e
                  WHERE COALESCE((e->>'rider_flagged')::boolean, false))
    INTO v_veh, v_run, v_has_atom
    FROM public.ottoq_visit_needs n
   WHERE n.visit_id = NEW.recalled_visit_id;

  IF v_veh IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'OQ020',
      MESSAGE = format('rider flag %s points at visit %s, which does not exist',
                       NEW.flag_id, NEW.recalled_visit_id);
  END IF;
  IF v_veh IS DISTINCT FROM NEW.vehicle_id THEN
    RAISE EXCEPTION USING ERRCODE = 'OQ020',
      MESSAGE = format('rider flag %s (vehicle %s) points at visit %s, which belongs to vehicle %s',
                       NEW.flag_id, NEW.vehicle_id, NEW.recalled_visit_id, v_veh);
  END IF;
  IF v_run IS DISTINCT FROM NEW.sim_run_id THEN
    RAISE EXCEPTION USING ERRCODE = 'OQ020',
      MESSAGE = format('rider flag %s (run %s) points at visit %s, which belongs to run %s',
                       NEW.flag_id, NEW.sim_run_id, NEW.recalled_visit_id, COALESCE(v_run::text,'<null>')),
      HINT    = 'this is the exact 0019 failure: a visit_key rebuilt as a string matched a previous run''s row';
  END IF;
  IF NOT v_has_atom THEN
    RAISE EXCEPTION USING ERRCODE = 'OQ020',
      MESSAGE = format('rider flag %s claims visit %s handled it, but that visit carries no rider-flagged atom',
                       NEW.flag_id, NEW.recalled_visit_id);
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ottoq_rider_flag_placement_guard ON public.ottoq_rider_cleaning_flags;
CREATE TRIGGER trg_ottoq_rider_flag_placement_guard
  BEFORE INSERT OR UPDATE ON public.ottoq_rider_cleaning_flags
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_rider_flag_placement_guard();

-- ============================================================================
-- 6. served_at_sim_clock IS STAMPED WHEN THE WORK IS ACTUALLY DONE
-- ============================================================================
-- The undercount (6 of 16 "served" against 11 of 16 done-by-atom) was not a
-- counting error, it was a missing write: only the arrival RETIRE branch ever
-- stamped served_at_sim_clock, and reaching that branch requires the vehicle to
-- come back and generate ANOTHER visit. A car cleaned on its last visit of the
-- run therefore never got stamped.
--
-- Placed on ottoq_visit_needs rather than in the two functions that mark atoms
-- done (twin.ottoq_sim_advance_visit_atoms, public.ottoq_mark_visit_atoms_done)
-- so a third writer added later is covered for free. The WHEN clause keeps it
-- off the hot path: two cheap text comparisons, false for every visit that is
-- not rider-flagged.
CREATE OR REPLACE FUNCTION public.ottoq_rider_flag_mark_served()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_done_at timestamptz;
BEGIN
  SELECT COALESCE((e->>'done_at')::timestamptz, (e->>'ends_at')::timestamptz)
    INTO v_done_at
    FROM jsonb_array_elements(COALESCE(NEW.atoms,'[]'::jsonb)) e
   WHERE COALESCE((e->>'rider_flagged')::boolean, false)
     AND e->>'status' = 'done'
   ORDER BY 1 DESC NULLS LAST
   LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE public.ottoq_rider_cleaning_flags f
     SET status              = 'served',
         served_at_sim_clock = COALESCE(f.served_at_sim_clock, v_done_at, NEW.arrived_at)
   WHERE f.recalled_visit_id = NEW.visit_id
     AND f.status <> 'served';

  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ottoq_rider_flag_mark_served ON public.ottoq_visit_needs;
CREATE TRIGGER trg_ottoq_rider_flag_mark_served
  AFTER UPDATE ON public.ottoq_visit_needs
  FOR EACH ROW
  WHEN (NEW.meta->>'rider_flagged' = 'true' AND OLD.atoms IS DISTINCT FROM NEW.atoms)
  EXECUTE FUNCTION public.ottoq_rider_flag_mark_served();

-- ============================================================================
-- 7. THE ANCHORING FIX -- FLAGS FOLLOW THE CLOCK THEY ARE ANCHORED TO
-- ============================================================================
-- ottoq_run_boot_draw anchors every flag at sim_clock_start + a seeded offset,
-- and ottoq_start_demo_run then rebases sim_clock_start to a random minute of
-- day. Flags were left anchored to a clock that no longer existed.
--
-- Fixed at the clock rather than in ottoq_start_demo_run, so it holds for ANY
-- rebaser. Only the base moves; the seeded offset inside the window is carried
-- forward exactly, so the draw stays deterministic.
CREATE OR REPLACE FUNCTION public.ottoq_reanchor_rider_flags_on_clock_rebase()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_delta interval := NEW.sim_clock_start - OLD.sim_clock_start;
BEGIN
  IF v_delta IS NULL OR v_delta = interval '0' THEN
    RETURN NULL;
  END IF;

  UPDATE public.ottoq_rider_cleaning_flags
     SET raised_at_sim_clock = raised_at_sim_clock + v_delta
   WHERE sim_run_id = NEW.sim_run_id
     AND status = 'pending';

  BEGIN
    UPDATE public.vehicle_need_profile
       SET rider_flag_due_at = rider_flag_due_at + v_delta
     WHERE rider_flag_due_at IS NOT NULL
       AND COALESCE(rider_flag_pending, false);
  EXCEPTION WHEN OTHERS THEN
    -- The profile mirror is advisory; ottoq_evaluate_return_need reads the flags
    -- table. Never let it break a run start.
    RAISE WARNING 'rider flag profile re-anchor skipped: % %', SQLSTATE, SQLERRM;
  END;

  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ottoq_reanchor_rider_flags ON public.ottoq_sim_runs;
CREATE TRIGGER trg_ottoq_reanchor_rider_flags
  AFTER UPDATE OF sim_clock_start ON public.ottoq_sim_runs
  FOR EACH ROW
  WHEN (NEW.sim_clock_start IS DISTINCT FROM OLD.sim_clock_start)
  EXECUTE FUNCTION public.ottoq_reanchor_rider_flags_on_clock_rebase();

-- ============================================================================
-- 8. ASSERTIONS. If any of these fail the whole file rolls back.
-- ============================================================================
DO $assert$
DECLARE
  n int; v_ok boolean;
BEGIN
  -- A1. The run-blind uniqueness is gone and the run-scoped one is in place.
  SELECT count(*) INTO n FROM pg_constraint
   WHERE conrelid = 'public.ottoq_visit_needs'::regclass
     AND conname  = 'ottoq_visit_needs_vehicle_id_visit_key_key';
  IF n <> 0 THEN RAISE EXCEPTION 'A1 FAILED: run-blind unique constraint still present'; END IF;

  SELECT count(*) INTO n FROM pg_indexes
   WHERE tablename = 'ottoq_visit_needs' AND indexname = 'ottoq_visit_needs_vehicle_visit_run_uk';
  IF n <> 1 THEN RAISE EXCEPTION 'A1 FAILED: run-scoped unique index missing'; END IF;

  -- A2. The flag can point at a visit by id, with real referential integrity.
  SELECT count(*) INTO n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_rider_cleaning_flags'
     AND column_name='recalled_visit_id';
  IF n <> 1 THEN RAISE EXCEPTION 'A2 FAILED: recalled_visit_id column missing'; END IF;

  SELECT count(*) INTO n FROM pg_constraint
   WHERE conrelid = 'public.ottoq_rider_cleaning_flags'::regclass
     AND conname  = 'ottoq_rider_cleaning_flags_recalled_visit_id_fkey';
  IF n <> 1 THEN RAISE EXCEPTION 'A2 FAILED: recalled_visit_id FK missing'; END IF;

  -- A3. All three triggers exist and are enabled.
  SELECT count(*) INTO n FROM pg_trigger
   WHERE NOT tgisinternal AND tgname IN ('trg_ottoq_rider_flag_placement_guard',
                                         'trg_ottoq_rider_flag_mark_served',
                                         'trg_ottoq_reanchor_rider_flags')
     AND tgenabled <> 'D';
  IF n <> 3 THEN RAISE EXCEPTION 'A3 FAILED: expected 3 enabled 0020 triggers, found %', n; END IF;

  -- A4. Neither replaced function still resolves a visit by rebuilding a string,
  --     and neither still writes the flag before the visit exists.
  SELECT pg_get_functiondef(p.oid) !~ 'recalled_visit_key\s+IS DISTINCT FROM'
    INTO v_ok FROM pg_proc p JOIN pg_namespace n2 ON n2.oid=p.pronamespace
   WHERE n2.nspname='twin' AND p.proname='ottoq_sim_generate_service_manifest';
  IF NOT COALESCE(v_ok,false) THEN RAISE EXCEPTION 'A4 FAILED: manifest generator still compares visit keys as strings'; END IF;

  SELECT pg_get_functiondef(p.oid) ~ 'RETURNING visit_id INTO v_visit_id'
    INTO v_ok FROM pg_proc p JOIN pg_namespace n2 ON n2.oid=p.pronamespace
   WHERE n2.nspname='twin' AND p.proname='ottoq_sim_generate_service_manifest';
  IF NOT COALESCE(v_ok,false) THEN RAISE EXCEPTION 'A4 FAILED: manifest generator does not capture the written visit_id'; END IF;

  SELECT pg_get_functiondef(p.oid) ~ 'WHEN SQLSTATE ''OQ020'''
    INTO v_ok FROM pg_proc p JOIN pg_namespace n2 ON n2.oid=p.pronamespace
   WHERE n2.nspname='ottoq' AND p.proname='ottoq_rider_flag_indepot_sweep';
  IF NOT COALESCE(v_ok,false) THEN RAISE EXCEPTION 'A4 FAILED: in-depot sweep still swallows the placement guard'; END IF;

  -- A5. TOTALITY. Every flag_kind maps to a bookable stall type. There are ZERO
  --     detail_bay stalls; the detail lane must fold onto wash_bay. An
  --     unrecognised kind must land somewhere real, never nowhere.
  SELECT count(*) INTO n FROM public.depots d
   WHERE d.id IN (SELECT DISTINCT home_depot_id FROM public.vehicles WHERE category='autonomous' AND home_depot_id IS NOT NULL)
     AND (COALESCE(ottoq.ottoq_svc_to_stall_type('exterior_wash', d.id),'') = ''
       OR COALESCE(ottoq.ottoq_svc_to_stall_type('interior_deep_clean', d.id),'') = '');
  IF n <> 0 THEN RAISE EXCEPTION 'A5 FAILED: % depot(s) cannot resolve a cleaning atom to a stall type', n; END IF;

  -- A6. The guard is not vacuous: no surviving flag is left in a state it would
  --     have refused, EXCEPT rows it can no longer speak for (legacy, unbindable).
  SELECT count(*) INTO n
    FROM public.ottoq_rider_cleaning_flags f
   WHERE f.status <> 'pending' AND f.recalled_visit_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.ottoq_visit_needs v
        WHERE v.visit_id = f.recalled_visit_id
          AND v.vehicle_id = f.vehicle_id
          AND v.sim_run_id IS NOT DISTINCT FROM f.sim_run_id
          AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v.atoms,'[]'::jsonb)) e
                       WHERE COALESCE((e->>'rider_flagged')::boolean,false)));
  IF n <> 0 THEN RAISE EXCEPTION 'A6 FAILED: % bound flag(s) violate the guard invariant', n; END IF;

  RAISE NOTICE '0020 assertions A1-A6 PASSED';
END
$assert$;

COMMIT;
