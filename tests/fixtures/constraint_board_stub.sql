-- tests/fixtures/constraint_board_stub.sql — what the live public.ottoq_agent_board reads and the miniature depot of
-- tests/test_agent_charge_order_sql.py does not hold, for tests/test_depot_constraint_sql.py.
--
-- Empty tables with the columns the board reads, and stand-ins for the five functions its gated sections call: each
-- returns a fixed, recognisable value, so a test can see which sections a board carries without running them. Nothing
-- here is created when the world already holds it.

CREATE TABLE IF NOT EXISTS public.ottoq_itinerary_legs (
  leg_id uuid DEFAULT gen_random_uuid(), sim_run_id uuid, vehicle_id uuid, status text, deviation_s numeric);
CREATE TABLE IF NOT EXISTS public.site_energy_snapshots (
  depot_id uuid, sim_run_id uuid, "timestamp" timestamptz, building_load_kw numeric, total_ev_charging_kw numeric,
  solar_generation_kw numeric);
CREATE TABLE IF NOT EXISTS public.ottoq_bess_units (depot_id uuid, current_soc_pct numeric, current_power_kw numeric);
CREATE TABLE IF NOT EXISTS public.ottoq_energy_commands (
  command_id bigserial, sim_run_id uuid, depot_id uuid, command_type text, reason text, issued_at timestamptz,
  tick_seq bigint);
CREATE TABLE IF NOT EXISTS public.ottoq_ops_approvals (depot_id uuid, approval_type text, status text);
CREATE TABLE IF NOT EXISTS public.ottoq_sim_scenarios (scenario_code text, fleet_overrides jsonb);

DO $stand_ins$
BEGIN
  IF to_regprocedure('public.ottoq_arrival_forecast(uuid,timestamptz,uuid,integer)') IS NULL THEN
    EXECUTE $f$CREATE FUNCTION public.ottoq_arrival_forecast(p_depot uuid, p_clock timestamptz, p_run uuid, p_min integer)
      RETURNS TABLE(predicted_charge_kw numeric) LANGUAGE sql STABLE AS 'SELECT 0::numeric'$f$;
  END IF;
  IF to_regprocedure('public.ottoq_agent_board_grounding(uuid,uuid,timestamptz)') IS NULL THEN
    EXECUTE $f$CREATE FUNCTION public.ottoq_agent_board_grounding(p_run uuid, p_depot uuid, p_clock timestamptz)
      RETURNS jsonb LANGUAGE sql STABLE AS $b$SELECT '{"stand_in": "grounding"}'::jsonb$b$$f$;
  END IF;
  IF to_regprocedure('public.ottoq_agent_review(uuid,integer)') IS NULL THEN
    EXECUTE $f$CREATE FUNCTION public.ottoq_agent_review(p_run uuid, p_n integer)
      RETURNS jsonb LANGUAGE sql STABLE AS $b$SELECT '{"stand_in": "review"}'::jsonb$b$$f$;
  END IF;
  IF to_regprocedure('public.ottoq_agent_asset_depth(uuid,uuid,timestamptz,integer,integer)') IS NULL THEN
    EXECUTE $f$CREATE FUNCTION public.ottoq_agent_asset_depth(p_run uuid, p_depot uuid, p_clock timestamptz, a integer, b integer)
      RETURNS jsonb LANGUAGE sql STABLE AS $b$SELECT '{"assets": {"stand_in": "asset_depth"}}'::jsonb$b$$f$;
  END IF;
  IF to_regprocedure('public.ottoq_vehicle_scouts_digest(uuid,integer)') IS NULL THEN
    EXECUTE $f$CREATE FUNCTION public.ottoq_vehicle_scouts_digest(p_run uuid, p_n integer)
      RETURNS jsonb LANGUAGE sql STABLE AS $b$SELECT '{"stand_in": "scouts"}'::jsonb$b$$f$;
  END IF;
END $stand_ins$;
