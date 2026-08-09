-- MIGRATION 0026: Fix staging allocation to prefer perimeter stalls before temp stalls.
-- 
-- P1-3: The ORDER BY clause that picks staging stalls was sorting with DESC, which prioritized 'temp'
-- stalls first. The doctrine states that perimeter stalls should be used first, with temp stalls as
-- overflow. This change flips 'DESC' to 'ASC' in two ORDER BY clauses to match doctrine.
-- 
-- Locations:
-- 1. ottoq_book_appointment: around line 645 in functions_ottoq.sql
-- 2. ottoq_sim_prearrival_contracts: around line 3957 in functions_ottoq.sql
-- 
-- The fix changes '(s.staging_role = ''temp'') DESC' to '(s.staging_role = ''temp'') ASC' in both,
-- so that true (for 'temp') sorts higher than false -> meaning perimeter (non-temp) stalls are
-- selected first.

-- This is a CREATE OR REPLACE migration, not a DROP + CREATE. That pattern avoids downtime.
-- The migration does NOT change any existing database state, only the function definitions.
--
-- See also: MIGRATION_LOG.md

-- Create replacement version of ottoq_book_appointment
CREATE OR REPLACE FUNCTION ottoq.ottoq_book_appointment(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamp with time zone, p_trigger text, p_urgency text, p_is_deferrable boolean, p_eta_minutes numeric, p_soc numeric, p_depot_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_had_need boolean; v_atoms jsonb; v_has_charge boolean;
  v_want_class text; v_stall uuid; v_stall_type text; v_ttl int;
  v_corr jsonb; v_eta_at timestamptz; v_cmd_type text; v_inlet text; v_plan jsonb; v_chg_kw numeric; v_new_est int; v_vv record; v_cplan jsonb;
BEGIN
  v_depot := COALESCE(p_depot_id,
                      (SELECT depot_id FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id),
                      (SELECT home_depot_id FROM vehicles WHERE id = p_vehicle_id));
  IF v_depot IS NULL THEN RETURN jsonb_build_object('secured', false, 'reason', 'no_depot'); END IF;

  SELECT inlet_type INTO v_inlet FROM vehicles WHERE id = p_vehicle_id;
  v_eta_at := p_clock + (GREATEST(COALESCE(p_eta_minutes, 30), 5)::text || ' minutes')::interval;

  SELECT EXISTS(SELECT 1 FROM ottoq_visit_needs vn
                 WHERE vn.vehicle_id = p_vehicle_id AND vn.sim_run_id IS NOT DISTINCT FROM p_sim_run_id AND vn.status IN ('open','in_progress'))
    INTO v_had_need;
  IF NOT v_had_need THEN
    BEGIN
      PERFORM ottoq_sim_generate_service_manifest(p_vehicle_id, p_sim_run_id, NULL);
    EXCEPTION WHEN OTHERS THEN NULL; -- booking survives a manifest hiccup (tick hot path)
    END;
  END IF;

  BEGIN PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, p_vehicle_id, v_eta_at);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  SELECT vn.atoms INTO v_atoms FROM ottoq_visit_needs vn
    WHERE vn.vehicle_id = p_vehicle_id AND vn.sim_run_id IS NOT DISTINCT FROM p_sim_run_id AND vn.status IN ('open','in_progress')
    ORDER BY vn.created_at DESC NULLS LAST LIMIT 1;

  v_has_charge := COALESCE((SELECT EXISTS(
      SELECT 1 FROM jsonb_array_elements(COALESCE(v_atoms, '[]'::jsonb)) a
       WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))), false);

  -- CHARGE DOCTRINE: the per-visit charge plan decides class + target.
  -- Chemistry-aware (LFP 100 / NMC 90 + periodic balance), slack-aware (L2 all night
  -- when there is time, DCFC when there is not). Persisted so the SESSION runs to it,
  -- and so no mid-session class switch is ever needed to hit the target.
  v_want_class := NULL; v_cplan := NULL;
  IF v_has_charge THEN
    BEGIN
      v_cplan := ottoq_charge_plan_for_visit(p_vehicle_id, p_clock, NULL);
      IF COALESCE((v_cplan->>'ok')::boolean, false) THEN
        v_want_class := v_cplan->>'charger_class';
        -- SAFETY OVERRIDE: a critically-drained vehicle never waits on a slow charger.
        IF COALESCE(p_soc, 100) < 25 OR p_urgency IN ('critical','urgent') THEN
          v_want_class := 'dcfc';
          v_cplan := v_cplan || jsonb_build_object('class_override','urgency_dcfc');
        END IF;
        UPDATE vehicles
           SET target_soc = GREATEST(COALESCE((v_cplan->>'target_soc')::numeric, 90), COALESCE(p_soc,0)),
               config = COALESCE(config,'{}'::jsonb) || jsonb_build_object(
                 'charge_plan', jsonb_build_object(
                   'class', v_want_class, 'target_soc', (v_cplan->>'target_soc')::numeric,
                   'reason', CASE WHEN v_cplan ? 'class_override'
                      THEN 'urgency_dcfc_override(planned:' || COALESCE(v_cplan->>'reason','?') || ')'
                      ELSE v_cplan->>'reason' END,
                   'no_mid_session_switch', true,
                   'planned_at', p_clock))
         WHERE id = p_vehicle_id;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_cplan := NULL;  -- booking survives a policy hiccup (tick hot path)
    END;
    -- charge_atom_target_stamped: push the planned target onto the manifest atom
    IF v_cplan IS NOT NULL AND COALESCE((v_cplan->>'ok')::boolean,false)
       AND v_atoms IS NOT NULL AND jsonb_typeof(v_atoms)='array' THEN
      SELECT jsonb_agg(CASE WHEN a->>'svc' = 'charge'
                            THEN a || jsonb_build_object(
                                   'target_soc', (v_cplan->>'target_soc')::numeric,
                                   'charger_class', v_want_class)
                            ELSE a END)
        INTO v_atoms FROM jsonb_array_elements(v_atoms) a;
    END IF;

    IF v_want_class IS NULL THEN   -- fallback: prior heuristic
      v_want_class := CASE
        WHEN p_trigger IN ('overnight_prestage','wash_cadence') THEN 'l2'
        WHEN COALESCE(p_soc, 100) < 45 OR p_urgency IN ('critical','urgent') THEN 'dcfc'
        ELSE 'l2' END;
    END IF;
  END IF;

  v_ttl := (GREATEST(COALESCE(p_eta_minutes, 30), 10) + 40)::int * 60;

  IF v_has_charge THEN
    -- reserve only an INLET-COMPATIBLE charge stall so the booking is honourable on arrival
    SELECT s.id, s.stall_type INTO v_stall, v_stall_type
      FROM stalls s
      JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = v_depot AND s.stall_type IN ('dcfc','l2')
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= p_clock)
       AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '35 minutes'
       AND (v_inlet IS NULL
            OR s.connector_type = v_inlet
            OR (s.connector_type = 'Multi' AND v_inlet = ANY(COALESCE(s.supported_inlet_types, ARRAY[]::text[])))
            OR (s.connector_type = 'NACS'  AND v_inlet IN ('NACS','Tesla_Proprietary')))
     ORDER BY (s.stall_type::text = v_want_class) DESC, s.relative_y ASC NULLS LAST, s.id
     LIMIT 1;
    IF v_stall IS NOT NULL AND NOT ottoq_reserve_stall(v_stall, p_vehicle_id, p_clock, v_ttl) THEN
      v_stall := NULL;
    END IF;
  END IF;

  IF v_stall IS NULL THEN
    SELECT s.id, s.stall_type INTO v_stall, v_stall_type FROM stalls s
     WHERE s.depot_id = v_depot AND s.stall_type = 'staging'
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= p_clock)
     ORDER BY (s.staging_role = 'temp') ASC, s.distance_from_entrance NULLS LAST, s.id
     LIMIT 1;
    IF v_stall IS NOT NULL AND NOT ottoq_reserve_stall(v_stall, p_vehicle_id, p_clock, v_ttl) THEN
      v_stall := NULL;
    END IF;
  END IF;

  IF v_stall IS NULL THEN
    RETURN jsonb_build_object('secured', false, 'reason', 'no_free_stall',
                              'has_charge', v_has_charge, 'want_class', v_want_class);
  END IF;

  -- ORCH-1: the full TIMED workflow plan, decided while the vehicle is en route.
  -- booked-charger recompute: the manifest priced the charge atom at a nominal
  -- DCFC; re-estimate against the RESERVED stall's real charger power (an L2
  -- overnight top-up is hours, not minutes) before building the timeline.
  BEGIN
    IF v_has_charge AND v_stall_type IN ('dcfc','l2') THEN
      SELECT c.max_kw INTO v_chg_kw
        FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
       WHERE s.id = v_stall;
      SELECT v.battery_capacity_kwh, v.inlet_max_kw,
             (v.config->>'battery_soh_pct')::numeric AS soh,
             (v.config->>'charge_curve_scalar')::numeric AS curve,
             COALESCE(v.target_soc,85) AS tsoc
        INTO v_vv FROM vehicles v WHERE v.id = p_vehicle_id;
      IF v_chg_kw IS NOT NULL THEN
        v_new_est := GREATEST(5, round(COALESCE(ottoq_estimate_charge_minutes(
            COALESCE(p_soc, 50), v_vv.tsoc, v_chg_kw, COALESCE(v_vv.inlet_max_kw, v_chg_kw),
            COALESCE(v_vv.battery_capacity_kwh, 75), 25, COALESCE(v_vv.soh, 95),
            GREATEST(0.2, ottoq_profile_rate_mult(p_sim_run_id,'charge_time')
                          / GREATEST(0.2, COALESCE(v_vv.curve, 1.0)))), 25)))::int;
        SELECT jsonb_agg(CASE WHEN a->>'svc' = 'charge'
                              THEN a || jsonb_build_object('est_min', v_new_est, 'charger_kw', v_chg_kw)
                              ELSE a END)
          INTO v_atoms FROM jsonb_array_elements(COALESCE(v_atoms,'[]'::jsonb)) a;
      END IF;
    END IF;
    v_plan := ottoq_build_workflow_plan(p_vehicle_id, p_sim_run_id, v_eta_at, v_atoms);
    UPDATE ottoq_visit_needs vn
       SET atoms = COALESCE(v_atoms, vn.atoms),
           meta = COALESCE(vn.meta,'{}'::jsonb)
              || jsonb_build_object('workflow_plan', v_plan, 'planned_at', p_clock,
                                    'booked_stall_id', v_stall, 'booked_stall_type', v_stall_type)
     WHERE vn.vehicle_id = p_vehicle_id AND vn.sim_run_id IS NOT DISTINCT FROM p_sim_run_id
       AND vn.status IN ('open','in_progress');
  EXCEPTION WHEN OTHERS THEN v_plan := NULL; -- plan is additive; booking never fails on it
  END;

  v_cmd_type := CASE WHEN v_stall_type = 'staging' THEN 'stage' ELSE 'proceed_to_stall' END;
  BEGIN
    v_corr := ottoq_comms_send_command(p_sim_run_id, p_vehicle_id, v_cmd_type,
      jsonb_build_object('stall_id', v_stall, 'stall_type', v_stall_type, 'eta_at', v_eta_at,
                         'workflow', COALESCE(v_atoms, '[]'::jsonb), 'plan', v_plan, 'trigger', p_trigger, 'urgency', p_urgency),
      p_clock, false);
  EXCEPTION WHEN OTHERS THEN v_corr := NULL; END;
  BEGIN
    PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, p_vehicle_id, v_cmd_type,
      jsonb_build_object('stall_id', v_stall, 'stall_type', v_stall_type, 'ttl_s', v_ttl,
                         'eta_at', v_eta_at, 'plan', v_plan, 'trigger', p_trigger, 'urgency', p_urgency, 'appointment', true,
                         'correlation_id', v_corr->>'correlation_id'), p_clock);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('secured', true, 'stall_id', v_stall, 'stall_type', v_stall_type,
                            'charger_class', v_want_class, 'ttl_s', v_ttl, 'command_type', v_cmd_type,
                            'correlation_id', v_corr->>'correlation_id', 'has_charge', v_has_charge,
                            'projected_ready_at', v_plan->>'projected_ready_at',
                            'plan_total_min', v_plan->>'total_min');
END;
$function$;

-- Create replacement version of ottoq_sim_prearrival_contracts
CREATE OR REPLACE FUNCTION ottoq.ottoq_sim_prearrival_contracts(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_rec RECORD; v_eta timestamptz; v_stall uuid; v_n int := 0;
  v_has_charge boolean; v_ttl int; v_eta_min numeric;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;

  -- BACKSTOP 1: en_route car with no workflow (AP-4 books at need-fire; this catches cars that
  -- reached en_route by another path). Provenance stays 'twin_generator' (honest derivation).
  FOR v_rec IN
    SELECT v.id AS vehicle_id
      FROM vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND v.current_state = 'en_route_to_depot'
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                        WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress'))
     LIMIT 40
  LOOP
    PERFORM ottoq_sim_generate_service_manifest(v_rec.vehicle_id, p_sim_run_id, NULL);
    SELECT COALESCE(MAX(d.scheduled_return_at), p_clock) INTO v_eta
      FROM ottoq_vehicle_dispatches d
     WHERE d.vehicle_id = v_rec.vehicle_id AND d.actual_return_at IS NULL;
    PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.vehicle_id, GREATEST(p_clock, v_eta));
    v_n := v_n + 1;
  END LOOP;

  -- BACKSTOP 2: en_route car with no live reservation gets one (widened to the whole approach,
  -- ETA-derived TTL so the hold survives transit + gate queue).
  FOR v_rec IN
    SELECT v.id AS vehicle_id, vn.atoms, vn.urgency, v.current_soc,
           (SELECT MIN(d.scheduled_return_at) FROM ottoq_vehicle_dispatches d
             WHERE d.vehicle_id = v.id AND d.actual_return_at IS NULL) AS eta_at
      FROM vehicles v
      JOIN ottoq_visit_needs vn ON vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND v.current_state = 'en_route_to_depot'
       AND NOT EXISTS (SELECT 1 FROM stalls s WHERE s.reserved_by = v.id
                         AND s.reservation_expires_at > p_clock)
     LIMIT 40
  LOOP
    v_eta_min := GREATEST(EXTRACT(EPOCH FROM (COALESCE(v_rec.eta_at, p_clock + interval '15 min') - p_clock))/60.0, 10);
    v_ttl := (v_eta_min + 40)::int * 60;
    SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(v_rec.atoms) a
                    WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))
      INTO v_has_charge;
    v_stall := NULL;
    IF v_has_charge THEN
      SELECT s.id INTO v_stall FROM stalls s
        JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
       WHERE s.depot_id = v_depot AND s.stall_type IN ('dcfc','l2')
         AND s.current_vehicle_id IS NULL
         AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_clock)
         AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '35 minutes'
       ORDER BY (s.stall_type::text = (CASE WHEN v_rec.urgency = 'immediate_dispatch' OR v_rec.current_soc < 45
                                      THEN 'dcfc' ELSE 'l2' END)) DESC,
                s.relative_y ASC NULLS LAST, s.id
       LIMIT 1;
    END IF;
    IF v_stall IS NULL THEN
      SELECT s.id INTO v_stall FROM stalls s
       WHERE s.depot_id = v_depot AND s.stall_type = 'staging'
         AND s.current_vehicle_id IS NULL
         AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_clock)
       ORDER BY (s.staging_role = 'temp') ASC, s.distance_from_entrance NULLS LAST, s.id
       LIMIT 1;
    END IF;
    IF v_stall IS NOT NULL THEN
      PERFORM ottoq_reserve_stall(v_stall, v_rec.vehicle_id, p_clock, v_ttl);
      v_n := v_n + 1;
    END IF;
  END LOOP;

  -- M1 REFRESH: keep a booked car's own reservation alive while it approaches / queues at the
  -- gate, so an ETA slip cannot drop the hold before the arrival assignment claims it.
  UPDATE stalls s
     SET reservation_expires_at = p_clock + interval '40 minutes'
    FROM vehicles v
   WHERE s.reserved_by = v.id
     AND v.home_depot_id = v_depot AND v.category = 'autonomous'
     AND v.current_state IN ('arrived_at_gate','en_route_to_depot')
     AND s.reservation_expires_at > p_clock
     AND s.reservation_expires_at <= p_clock + interval '20 minutes'
     AND s.current_vehicle_id IS NULL;

  RETURN v_n;
END;
$function$;
-- End of migration 0026