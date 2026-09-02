-- =====================================================================
-- 0154  The assertion matched a key only one verb carries
-- =====================================================================
-- twin.ottoq_grid_assert (0153) check 2 required every enacted stall
-- assignment's enacted_action to carry a booking_id that resolves to a
-- booking for that vehicle on that point. Measured on the first 12-tick
-- grid trial: 0 of 6. Measured on the latest flagship arm (round 7,
-- 7:49 AM CT Sep 2): 191 enacted stall assignments, 12 carry a
-- booking_id key (all verb gate_intake, all 12 resolve correctly), 179
-- do not (verb assign_stall) - and ALL 191 have a booking for that
-- vehicle on that point in that run. The engine's rule ("enactment and
-- calendar are one act") holds; the instrument read a key only one verb
-- writes. Same class as 0148: the check must be stated in terms the
-- data actually carries.
--
-- Fix: match on (run, vehicle, point); when a booking_id key IS present
-- it must also be that booking. Harness only; forces_recert = false.
-- =====================================================================

CREATE OR REPLACE FUNCTION twin.ottoq_grid_assert(p_run uuid)
RETURNS TABLE(check_code text, passed boolean, detail text)
LANGUAGE plpgsql STABLE
AS $fn$
DECLARE
  v_depot uuid; v_status text; v_ticks int; v_cap numeric; v_max numeric;
  n bigint; n2 bigint; n3 bigint; v_out text; v_eq text;
BEGIN
  SELECT r.depot_id, r.status, r.tick_count INTO v_depot, v_status, v_ticks
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run;
  IF v_depot IS NULL THEN RAISE EXCEPTION 'grid_assert: run % not found', p_run; END IF;
  SELECT d.service_max_kw INTO v_cap FROM public.depots d WHERE d.id = v_depot;

  -- 1. the run finished
  check_code := 'run_completed'; passed := (v_status = 'completed');
  detail := 'status='||COALESCE(v_status,'-')||', ticks='||COALESCE(v_ticks::text,'-'); RETURN NEXT;

  -- 2. enactment and calendar are one act (decide_tick's own rule): every
  --    enacted stall assignment has a booking for that vehicle on that point in
  --    this run; where the action names a booking_id, it is that booking.
  --    (0154: only gate_intake writes booking_id; assign_stall does not.)
  SELECT count(*),
         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                                         WHERE b.sim_run_id = p_run AND b.vehicle_id = d.entity_id
                                           AND b.stall_id = (d.enacted_action->>'stall_id')::uuid
                                           AND (NOT (d.enacted_action ? 'booking_id')
                                                OR b.booking_id = (d.enacted_action->>'booking_id')::uuid))),
         count(*) FILTER (WHERE d.enacted_action ? 'booking_id')
    INTO n, n2, n3
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = p_run AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted';
  check_code := 'every_enacted_assignment_is_booked'; passed := (n > 0 AND n = n2);
  detail := n2||' of '||n||' enacted assignments have a booking for that vehicle on that point ('||n3||' name their booking_id)'
            ||CASE WHEN n = 0 THEN ' (vacuous: none enacted)' ELSE '' END; RETURN NEXT;

  -- 3. no point double-booked, checked independently of the EXCLUDE constraint
  SELECT count(*) INTO n
    FROM public.ottoq_stall_bookings a
    JOIN public.ottoq_stall_bookings b ON b.sim_run_id = a.sim_run_id AND b.stall_id = a.stall_id
                                       AND b.booking_id > a.booking_id AND a.during && b.during
   WHERE a.sim_run_id = p_run
     AND a.state IN ('held','active','done','interrupted') AND b.state IN ('held','active','done','interrupted');
  SELECT count(*) INTO n2 FROM public.ottoq_stall_bookings WHERE sim_run_id = p_run;
  check_code := 'no_point_double_booked'; passed := (n = 0 AND n2 > 0);
  detail := n||' overlapping live bookings among '||n2||CASE WHEN n2 = 0 THEN ' (vacuous: no bookings)' ELSE '' END; RETURN NEXT;

  -- 4. every operation lands on a point capable of it
  SELECT count(*),
         count(*) FILTER (WHERE NOT (
              (b.purpose = 'charge_dcfc' AND s.stall_type::text = 'dcfc' AND s.ocpp_charger_id IS NOT NULL)
           OR (b.purpose = 'charge_l2'   AND s.stall_type::text = 'l2'   AND s.ocpp_charger_id IS NOT NULL)
           OR (b.purpose IN ('wash','detail') AND s.stall_type::text = 'wash_bay')
           OR (b.purpose = 'service' AND s.stall_type::text = 'service_bay')
           OR (b.purpose IN ('inspect','temp_hold','perimeter_hold','staging') AND s.stall_type::text = 'staging')))
    INTO n, n2
    FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
   WHERE b.sim_run_id = p_run;
  check_code := 'every_booking_on_a_capable_point'; passed := (n > 0 AND n2 = 0);
  detail := n2||' of '||n||' bookings on an incapable point'||CASE WHEN n = 0 THEN ' (vacuous)' ELSE '' END; RETURN NEXT;

  -- 5. DCFC first, L2 only as overflow (ottoq_l2_optimize_assignments' scoring rule),
  --    read off the calendar. Legitimate exceptions to investigate before blaming
  --    the engine: a faulted charger, a live reservation.
  SELECT count(*) INTO n3 FROM public.ottoq_stall_bookings b WHERE b.sim_run_id = p_run AND b.purpose IN ('charge_dcfc','charge_l2');
  SELECT count(*),
         count(*) FILTER (WHERE EXISTS (
            SELECT 1 FROM public.stalls s
             WHERE s.depot_id = v_depot AND s.stall_type::text = 'dcfc' AND s.ocpp_charger_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings o
                                WHERE o.sim_run_id = p_run AND o.stall_id = s.id AND o.booking_id <> b.booking_id
                                  AND o.state IN ('held','active','done','interrupted')
                                  AND o.during @> lower(b.during))))
    INTO n, n2
    FROM public.ottoq_stall_bookings b
   WHERE b.sim_run_id = p_run AND b.purpose = 'charge_l2' AND b.source IN ('greedy_constrained','deterministic');
  check_code := 'dcfc_first_l2_only_as_overflow'; passed := (n3 > 0 AND n2 = 0);
  detail := n2||' of '||n||' local-path L2 assignments made while a DCFC point was unbooked ('||n3||' charge bookings in all)'
            ||CASE WHEN n3 = 0 THEN ' (vacuous: no charging)' ELSE '' END; RETURN NEXT;

  -- 6. most depleted first (the cursor's ORDER BY current_soc ASC)
  SELECT count(*) INTO n
    FROM (SELECT d.tick_seq, (d.context_frame->>'current_soc')::numeric AS soc, s.stall_type::text AS st
            FROM public.ottoq_decisions d JOIN public.stalls s ON s.id = (d.enacted_action->>'stall_id')::uuid
           WHERE d.sim_run_id = p_run AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
             AND s.stall_type::text IN ('dcfc','l2')) x
   WHERE x.st = 'l2'
     AND EXISTS (SELECT 1 FROM public.ottoq_decisions d2 JOIN public.stalls s2 ON s2.id = (d2.enacted_action->>'stall_id')::uuid
                  WHERE d2.sim_run_id = p_run AND d2.tick_seq = x.tick_seq
                    AND d2.action_context = 'stall_assignment' AND d2.outcome_status = 'enacted'
                    AND s2.stall_type::text = 'dcfc' AND (d2.context_frame->>'current_soc')::numeric > x.soc);
  SELECT count(*) INTO n2
    FROM public.ottoq_decisions d JOIN public.stalls s ON s.id = (d.enacted_action->>'stall_id')::uuid
   WHERE d.sim_run_id = p_run AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
     AND s.stall_type::text IN ('dcfc','l2');
  check_code := 'most_depleted_gets_the_fast_point'; passed := (n = 0 AND n2 > 0);
  detail := n||' same-tick inversions among '||n2||' charging assignments'||CASE WHEN n2 = 0 THEN ' (vacuous)' ELSE '' END; RETURN NEXT;

  -- 7. the declared site power cap held (the 0132 gate), measured on the energy snapshots
  SELECT max(e.total_ev_charging_kw) INTO v_max FROM public.site_energy_snapshots e WHERE e.sim_run_id = p_run;
  check_code := 'site_power_cap_held'; passed := (v_cap IS NOT NULL AND v_max IS NOT NULL AND v_max <= v_cap);
  detail := 'max ev charging '||COALESCE(v_max::text,'(no snapshots)')||' kW vs service_max_kw '||COALESCE(v_cap::text,'(none declared)'); RETURN NEXT;

  -- 8. every completed service operation terminates in an SDR (the C3 rule)
  SELECT count(*),
         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_service_detail_records r
                                         WHERE r.leg_id = l.leg_id AND r.sim_run_id = p_run))
    INTO n, n2
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = p_run AND l.status = 'done' AND l.leg_type NOT IN ('taxi','stage','depart');
  check_code := 'every_completed_operation_has_an_sdr'; passed := (n > 0 AND n = n2);
  detail := n2||' of '||n||' completed service legs have an SDR'||CASE WHEN n = 0 THEN ' (vacuous: none completed)' ELSE '' END; RETURN NEXT;

  -- 9. every refusal carries a reason code
  SELECT count(*), count(*) FILTER (WHERE reason_code IS NULL) INTO n, n2
    FROM public.ottoq_vehicle_commands WHERE sim_run_id = p_run AND status = 'refused';
  check_code := 'every_refusal_carries_a_reason'; passed := (n2 = 0);
  detail := n2||' of '||n||' refusals without a reason code'||CASE WHEN n = 0 THEN ' (no refusals)' ELSE '' END; RETURN NEXT;

  -- 10. the proposer stayed out (0152)
  SELECT count(*), count(*) FILTER (WHERE abstained_reason IS DISTINCT FROM 'policy_disabled') INTO n, n2
    FROM public.cuopt_invocation_log WHERE sim_run_id = p_run;
  check_code := 'proposer_quiesced'; passed := (n > 0 AND n2 = 0);
  detail := n||' proposer invocations, '||n2||' other than policy_disabled'; RETURN NEXT;

  -- 11. the same seed produced the same run (the pair verdict on this arm)
  SELECT r.validation_notes::jsonb->>'outcome', r.validation_notes::jsonb->>'equal' INTO v_out, v_eq
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run;
  check_code := 'pair_verdict_passed'; passed := (v_out = 'passed');
  detail := COALESCE('outcome='||v_out||', equal='||v_eq, 'no verdict on this run (not a certification arm)'); RETURN NEXT;
  RETURN;
END;
$fn$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_assertion_matched_a_key_only_one_verb_carries', false,
        'twin.ottoq_grid_assert check 2 matches a booking on (run, vehicle, point) and only requires the booking_id where the action names one. Harness only.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
