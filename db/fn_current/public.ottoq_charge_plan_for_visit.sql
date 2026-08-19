-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: 51d7c228da928cde0f000b5dbe2eaba6
CREATE OR REPLACE FUNCTION public.ottoq_charge_plan_for_visit(p_vehicle_id uuid, p_clock timestamp with time zone DEFAULT now(), p_hours_until_deploy numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v vehicles%ROWTYPE; v_hour int; v_overnight boolean; v_chem text;
  v_target numeric; v_class text; v_slack numeric; v_l2_min numeric; v_reason text;
  v_days_since numeric; v_bal int; v_baseline timestamptz;
  v_night_start int; v_dc_cap numeric;
BEGIN
  SELECT * INTO v FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason','vehicle_not_found'); END IF;
  v_chem := COALESCE(v.config->>'battery_chemistry', 'lfp');
  v_bal  := COALESCE((v.config->>'balance_interval_days')::int, 0);
  v_hour := EXTRACT(HOUR FROM (p_clock AT TIME ZONE 'America/Chicago'))::int;

  -- ONE NIGHT for the whole system. This used to be a local (v_hour >= 21 OR v_hour < 5),
  -- which disagreed with the depot night window every SoC ceiling is resolved against.
  v_overnight  := public.ottoq_is_depot_night(p_clock);
  v_night_start := public.ottoq_policy_get(NULL, 'depot_night_start_hour', 20)::int;

  v_slack := COALESCE(p_hours_until_deploy,
               CASE WHEN v_overnight
                    THEN GREATEST(0.5, 5.0 + CASE WHEN v_hour >= v_night_start
                                                  THEN (24 - v_hour) ELSE -v_hour END)
                    ELSE 1.0 END);

  -- What the CAR wants: chemistry default, or an explicit per-vehicle nightly target.
  v_target := COALESCE((v.config->>'nightly_soc_target')::numeric,
                       CASE WHEN v_chem='lfp' THEN 100 ELSE 90 END);

  IF v_chem <> 'lfp' AND v_bal > 0 THEN
    -- baseline = last recorded balance charge, else the onboarding date (NOT "due now")
    v_baseline := COALESCE((v.config->>'last_balance_charge_at')::timestamptz,
                           (v.config->>'battery_onboarded_at')::timestamptz, p_clock);
    v_days_since := EXTRACT(EPOCH FROM (p_clock - v_baseline))/86400.0;
    IF v_days_since >= v_bal THEN v_target := 100; v_reason := 'nmc_periodic_balance_charge'; END IF;
  END IF;

  -- What the DEPOT allows on a fast plug at this hour. A ceiling, never a floor.
  v_dc_cap := public.ottoq_target_soc_cap('dcfc', p_clock);

  v_l2_min := ottoq_charge_minutes_between(COALESCE(v.current_soc,20), v_target, 19.2, 150,
                COALESCE(v.battery_capacity_kwh,75), COALESCE((v.config->>'battery_soh_pct')::numeric,95));

  -- DCFC FIRST, ALWAYS. This branch used to prefer L2 overnight whenever L2 could
  -- finish inside the slack window. Leaving it would have had the planner asking
  -- for 'l2' while ottoq_l2_optimize_assignments handed out fast plugs -- the two
  -- halves of the same decision disagreeing. L2 is reached only as overflow, in the
  -- picker, when no fast plug is free.
  IF v_overnight THEN
    v_class := 'dcfc'; v_target := LEAST(v_target, v_dc_cap);
    v_reason := COALESCE(v_reason, 'overnight_dcfc_to_' || v_dc_cap::text);
  ELSE
    v_class := 'dcfc'; v_target := LEAST(v_target, v_dc_cap);
    v_reason := COALESCE(v_reason, 'daytime_fast_turnaround_' || v_dc_cap::text);
  END IF;

  RETURN jsonb_build_object('ok', true, 'vehicle_id', p_vehicle_id,
    'charger_class', v_class, 'target_soc', v_target, 'chemistry', v_chem,
    'overnight', v_overnight, 'hours_until_deploy', ROUND(v_slack,2),
    'dcfc_cap_at_plan_time', v_dc_cap,
    'est_l2_minutes_to_target', v_l2_min, 'reason', v_reason, 'no_mid_session_switch', true);
END; $function$

