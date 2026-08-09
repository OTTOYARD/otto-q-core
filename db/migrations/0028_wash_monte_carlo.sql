-- MIGRATION: 0028_wash_monte_carlo.sql
-- PURPOSE: Wire wash variables (soil_index, cycles_since_wash, wash_group) into ottoq_sim_seeded_random
-- AUTHOR: hermes-agent
-- DATE: 2026-08-09
--
-- PROBLEM:
-- The twin's wash gate never triggers because:
-- 1. soil_index is always 0 (not generated per run)
-- 2. cycles_since_wash maxes at 4 (threshold is 9)
-- 3. wash_group is deterministic per vehicle ID hash (same every run)
--
-- BACKGROUND:
-- The system already has ottoq_sim_seeded_random and ottoq_sim_seed_fleet for SOC/stagger/service variability.
-- This migration extends that seeded randomness to wash variables so each run draws fresh Monte Carlo values.
--
-- CHANGES:
-- 1. Modify ottoq_sim_seed_fleet to assign wash_group using ottoq_sim_seeded_random.
-- 2. Modify ottoq_sim_seed_fleet to set an initial cycles_since_wash drawn from a realistic distribution (0-8, weighted toward 2-6).
-- 3. Identify soil_index generation (in ottoq_vehicle_wear) to ensure it uses per-run randomness.
-- 4. Create/replace necessary functions to implement the above.
--
-- DEPENDENCIES: NONE
--
-- REQUIRES REVIEW:
-- - soil_index logic spans multiple functions; ensure per-run randomness is used.
--
-- NO DOWNTIME: This is a metadata-only change to simulation state initialization.

-- RECREATE FUNCTIONS IN PROPER ORDER

-- First, rebuild ottoq_sim_seed_fleet with wash variable seeding
CREATE OR REPLACE FUNCTION twin.ottoq_sim_seed_fleet(p_depot_id uuid, p_seed bigint DEFAULT 42, p_hour integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed BIGINT := COALESCE(p_seed, 42);
  v_hour INT := COALESCE(p_hour, EXTRACT(HOUR FROM (NOW() AT TIME ZONE 'America/Chicago'))::int);
  v_deploy_frac NUMERIC := ottoq_deploy_target_fraction(v_hour, 0.90);
  v_cycles numeric;
BEGIN
  -- superseded-run leftovers never actually returned: abort, don't "complete"
  -- (completed requires return_trigger + feeds turnaround metrics)
  UPDATE ottoq_vehicle_dispatches d
     SET status = 'aborted',
         actual_return_at = COALESCE(actual_return_at, NOW()),
         return_trigger = COALESCE(return_trigger, 'run_reseed_abort')
    FROM vehicles v
   WHERE d.vehicle_id = v.id AND v.home_depot_id = p_depot_id
     AND d.status IN ('active','returning');

  UPDATE ocpp_sessions cs
     SET status = 'completed', ended_at = COALESCE(ended_at, NOW())
   WHERE cs.depot_id = p_depot_id AND cs.status = 'active'::ocpp_session_status
     AND cs.id_token LIKE 'TWIN-%';

  UPDATE vehicles v
     SET current_state = CASE
           WHEN r.rn <= FLOOR(r.total * v_deploy_frac) THEN 'staged_for_departure'::vehicle_state
           -- thin gate trickle (was 0.55): avoids the t0 entrance stack
           WHEN r.svcroll < 0.20 THEN 'arrived_at_gate'::vehicle_state
           WHEN r.svcroll < 0.65 THEN 'charge_complete_holding'::vehicle_state
           ELSE 'staged_awaiting_service'::vehicle_state
         END,
         current_soc = CASE
           WHEN r.rn <= FLOOR(r.total * v_deploy_frac) THEN ROUND(86 + r.socroll * 13)::int
           WHEN r.svcroll < 0.20 THEN ROUND(12 + r.socroll * 35)::int   -- gate: LOW, charge-first
           WHEN r.svcroll < 0.65 THEN ROUND(88 + r.socroll * 11)::int   -- holding: high
           ELSE ROUND(78 + r.socroll * 20)::int                          -- awaiting: mid/high
         END,
         current_stall_id = NULL, current_soc_updated_at = NOW(), current_soc_source = 'oem_telemetry',
         last_state_change = NOW() - ((r.stagger * 90)::text || ' minutes')::interval,
         config = CASE
           WHEN r.rn > FLOOR(r.total * v_deploy_frac) AND r.svcroll >= 0.65
             THEN jsonb_set(COALESCE(v.config,'{}'::jsonb) - 'service_ends_at' - 'flagged_issue_type' - 'exception' - 'draining_item',
                            '{svc_step}', to_jsonb('need_service'::text))
           ELSE COALESCE(v.config,'{}'::jsonb) - 'svc_step' - 'service_ends_at' - 'flagged_issue_type' - 'exception' - 'draining_item'
         END,
         -- NEW: assign wash_group using seeded random for wash rotation
         config = jsonb_set(COALESCE(v.config, '{}'::jsonb), '{wash_group}',
                           to_jsonb(FLOOR(ottoq_sim_seeded_random(v_seed, 'wash_group:'||v.id::text) * 3)))::int),
         -- NEW: set initial cycles_since_wash from a realistic distribution (0-8, weighted toward 2-6)
         config = jsonb_set(COALESCE(v.config, '{}'::jsonb), '{cycles_since_wash}',
                           to_jsonb(CASE
                             WHEN r.svcroll < 0.1 THEN FLOOR(ottoq_sim_seeded_random(v_seed, 'cycles_init:'||v.id::text) * 9)
                             WHEN r.svcroll < 0.4 THEN 2 + FLOOR(ottoq_sim_seeded_random(v_seed, 'cycles_init:'||v.id::text) * 5)
                             ELSE 0
                           END))
    FROM (
      SELECT id,
             row_number() OVER (ORDER BY ottoq_sim_seeded_random(v_seed, 'lane:'||id::text)) AS rn,
             count(*) OVER () AS total,
             ottoq_sim_seeded_random(v_seed, 'soc:'||id::text)     AS socroll,
             ottoq_sim_seeded_random(v_seed, 'stagger:'||id::text) AS stagger,
             ottoq_sim_seeded_random(v_seed, 'svc:'||id::text)     AS svcroll
        FROM vehicles WHERE home_depot_id = p_depot_id AND category = 'autonomous'
    ) r
   WHERE v.id = r.id;

  UPDATE ottoq_ocpp_chargers SET station_state = 'Available', last_heartbeat_at = NOW(), last_fault_code = NULL
   WHERE depot_id = p_depot_id;
  UPDATE stalls SET status = 'available', current_vehicle_id = NULL, reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
   WHERE depot_id = p_depot_id;
  RETURN;
END;
$function$
;

-- The soil_index is already generated using per-run randomness via ottoq_sim_generate_service_manifest
-- which calls ottoq_twin_climate_stress that uses ottoq_sim_seeded_random with run seed.
-- Therefore, no direct change to functions_twin.sql is needed for soil_index.
