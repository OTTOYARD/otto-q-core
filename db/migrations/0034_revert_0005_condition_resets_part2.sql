-- migration-version: 20260810171310
-- migration-name:    revert_0005_condition_resets_part2
--
-- P1-15: Narrowly revert §2's unconditional `exterior_soil_level := round(soil_index, 3)`
-- from migration 0005, which copies a sensor-soil counter (capped ~0.30) into a body-soil
-- field banded at 0.45/0.65/0.85, causing ratcheting towards `ok`. Also gate the
-- `open_fault_codes := '{}'` / `worst_fault_severity := 99` writes that ride the same array.
--
-- KEEP §3 (inspection wiring) — it is proven correct.
--
-- This file REVERTS a REVERT. The original 0005 was correct; the fix for P1-15 must be
-- even narrower than the narrow fix was. It only removes the soil projection and fault
-- reset; the odometer watermark anchoring at boot (§4) and other parts remain.
--
-- BLAST RADIUS
--   One function replaced (public.ottoq_wear_mark_serviced), none created or dropped.
--   No table changes. No index, no constraint, no policy. The phase-11/14 baseline is
--   untouched: nothing here books, releases, picks, prices, or moves an urgency.
--
-- VERIFY
--   V1-V4: Run the static checks from 0005 §6 in a transaction and ROLLBACK.
--   V5: Re-measure the headline for P1-15's defect: 8 of 17 vehicles were laundered out of wash
--       bands by the soil reset with no wash bay. Capture after the next run is stopped.
--   V6: Re-check §4's odometer watermark: it must still anchor at boot. Query the boot
--       manifest payload for `odometer_watermarks_anchored` and confirm it is 116 on boot.
--   V7: Re-run the verification from the original 0005, but EXPECT the soil divergence to
--       stay high and the fault resets to be conditional.
--

-- Snapshot pre-state
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0034_revert_0005_part2_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_wear_mark_serviced';

-- Guard: expect the md5 of the function as modified by 0005
DO $guard$
DECLARE
  v_expect CONSTANT text := 'a44cdd6c31df748b63986881a9f697a2'; -- md5 of 0005's ottoq_wear_mark_serviced
  v_actual text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_actual
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_wear_mark_serviced';

  IF v_actual IS NULL THEN
    RAISE EXCEPTION 'GUARD: public.ottoq_wear_mark_serviced does not exist.';
  ELSIF v_actual <> v_expect THEN
    RAISE EXCEPTION
      'GUARD: public.ottoq_wear_mark_serviced live md5 % does not match expected %. Aborting.',
      v_actual, v_expect;
  END IF;
  RAISE NOTICE 'GUARD: public.ottoq_wear_mark_serviced matches expected definition.';
END
$guard$;

-- Revert §2: Remove the unconditional soil copy and fault reset
-- Keep: odometer advance, wash date, deep clean date, calibration date, PM date, cabin cleanup on tidy, software update, item retrieval
-- Remove: exterior_soil_level := COALESCE(round(v_soil, 3), p.exterior_soil_level)
--         open_fault_codes := '{}'
--         worst_fault_severity := 99
-- Add: condition the fault resets on the service that actually fixes faults
--
CREATE OR REPLACE FUNCTION public.ottoq_wear_mark_serviced(p_vehicle_id uuid, p_sim_run_id uuid, p_service text, p_clock timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_wear_found boolean;
  v_drive_km   numeric;
  v_soil       numeric;
BEGIN
  -- ══════════════ PART 1 — THE WEAR LEDGER (UNCHANGED, BYTE-FOR-BYTE) ══════════════
  UPDATE ottoq_vehicle_wear w SET
    soil_index = CASE WHEN p_service IN ('exterior_wash','sensor_clean','interior_deep_clean')
                      THEN 0 ELSE w.soil_index END,
    cabin_litter_events = CASE WHEN p_service IN ('interior_tidy','interior_deep_clean')
                      THEN 0 ELSE w.cabin_litter_events END,
    km_at_last_pm = CASE WHEN p_service = 'mechanical_pm'
                      THEN w.drive_km_total ELSE w.km_at_last_pm END,
    hours_at_last_calibration = CASE WHEN p_service = 'sensor_calibration'
                      THEN w.drive_hours_total ELSE w.hours_at_last_calibration END,
    calibrated_at = CASE WHEN p_service = 'sensor_calibration'
                      THEN p_clock ELSE w.calibrated_at END,
    open_dtc_count = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
                      THEN 0 ELSE w.open_dtc_count END,
    worst_open_dtc_rank = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
                      THEN 99 ELSE w.worst_open_dtc_rank END,
    updated_at = now()
  WHERE w.vehicle_id = p_vehicle_id AND w.sim_run_id = p_sim_run_id;

  v_wear_found := FOUND;

  -- ══════════════ PART 2 — DATES AND CONDITIONAL RESETS, NO SOIL OR FAULT RATCHETS ══════════════
  BEGIN
    SELECT w.drive_km_total, w.soil_index
      INTO v_drive_km, v_soil
      FROM ottoq_vehicle_wear w
     WHERE w.vehicle_id = p_vehicle_id
       AND w.sim_run_id = p_sim_run_id
     LIMIT 1;

    UPDATE public.vehicle_need_profile p SET
      odometer_km = COALESCE(p.odometer_km, 0) + GREATEST(0,
                      COALESCE(v_drive_km, 0)
                      - CASE WHEN p.wear_km_applied_run IS NOT DISTINCT FROM p_sim_run_id
                             THEN COALESCE(p.wear_km_applied, COALESCE(v_drive_km, 0))
                             ELSE COALESCE(v_drive_km, 0) END),

      last_wash_at = CASE WHEN p_service = 'exterior_wash'
                          THEN p_clock ELSE p.last_wash_at END,
      last_deep_clean_at = CASE WHEN p_service = 'interior_deep_clean'
                          THEN p_clock ELSE p.last_deep_clean_at END,
      last_calibration_at = CASE WHEN p_service = 'sensor_calibration'
                          THEN p_clock ELSE p.last_calibration_at END,
      last_pm_at = CASE WHEN p_service = 'mechanical_pm'
                          THEN p_clock ELSE p.last_pm_at END,

      km_at_last_pm = CASE WHEN p_service = 'mechanical_pm'
                          THEN COALESCE(p.odometer_km, 0) + GREATEST(0,
                                 COALESCE(v_drive_km, 0)
                                 - CASE WHEN p.wear_km_applied_run IS NOT DISTINCT FROM p_sim_run_id
                                        THEN COALESCE(p.wear_km_applied, COALESCE(v_drive_km, 0))
                                        ELSE COALESCE(v_drive_km, 0) END)
                          ELSE p.km_at_last_pm END,

      -- Remove the unconditional soil copy
      -- Remove the unconditional fault array/severity reset

      cabin_condition = CASE
                          WHEN p_service = 'interior_deep_clean' THEN 'clean'
                          WHEN p_service = 'interior_tidy'
                               AND p.cabin_condition = 'light_litter' THEN 'clean'
                          ELSE p.cabin_condition END,

      -- Condition fault resets on actual fault-fixing services
      open_fault_codes = CASE WHEN p_service = 'fault_repair'
                          THEN '{}'::text[] ELSE p.open_fault_codes END,
      worst_fault_severity = CASE WHEN p_service = 'fault_repair'
                          THEN 99 ELSE p.worst_fault_severity END,

      software_version = CASE WHEN p_service = 'software_update'
                          THEN COALESCE(p.sw_target_version, p.software_version)
                          ELSE p.software_version END,

      item_retrieval_pending = CASE WHEN p_service = 'item_retrieval'
                          THEN false ELSE p.item_retrieval_pending END,

      wear_km_applied = CASE WHEN p.wear_km_applied_run IS NOT DISTINCT FROM p_sim_run_id
                             THEN GREATEST(COALESCE(p.wear_km_applied, 0), COALESCE(v_drive_km, 0))
                             ELSE COALESCE(v_drive_km, 0) END,
      wear_km_applied_run = p_sim_run_id,

      updated_at = now()
    WHERE p.vehicle_id = p_vehicle_id;

  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'ottoq_wear_mark_serviced: vehicle_need_profile reset FAILED SAFELY for vehicle % service %: % %',
                  p_vehicle_id, p_service, SQLSTATE, SQLERRM;
  END;

  RETURN v_wear_found;
END;
$function$;

-- Post-snapshot
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0034_revert_0005_part2_post', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_wear_mark_serviced';
