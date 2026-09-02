-- =====================================================================
-- 0157  The assertions state the rule the engine actually has
--       INSTRUMENT. Harness only; forces_recert = false.
-- =====================================================================
-- Two of the eleven grid assertions (0153/0154) encoded a policy OTTO-Q
-- does not implement and should not: "the fast point goes to the most
-- depleted, L2 only as overflow." The engine's real rule is need-matched
-- routing - ottoq_l2_propose_stall_assignment sets wanted_type to 'dcfc'
-- only below 45% SoC or on immediate_dispatch, otherwise 'l2' - because
-- fast charging above ~70% SoC is slower per kWh and harder on the cells
-- (CLAUDE.md 2.5, the piecewise curve). An asset at 85% on an L2 point
-- with a DCFC point free is the engine being right, and the old check
-- called it a violation: it failed with "1 of 1 local-path L2
-- assignments made while a DCFC point was unbooked" against an
-- assignment whose own rationale read wanted_type = l2, soc 85.
--
-- most_depleted_gets_the_fast_point had the same flaw: it flagged a
-- lower-SoC asset on L2 beside a higher-SoC asset on DCFC, when the
-- lower one had ASKED for L2 and the higher one's L2 point was reserved
-- for a third vehicle.
--
-- site_power_cap_held read only site_energy_snapshots.total_ev_charging
-- _kw. That is charger-reported power (see 0155) and it lags the
-- commitment, so the check could not fail: it passed both tight-cap
-- trials at "max 16.9 kW vs cap" while the plan held 75-157 kW, and
-- would pass a run committing twice the cap. The number that must not
-- exceed the cap is what the scheduler COMMITS.
--
-- Adds no_asset_starves_while_a_capable_point_is_free (the check that
-- would have caught the 0156 defect) and the_power_cap_was_exercised
-- (so a green cap row on a slack run cannot read as evidence).
--
-- FALSIFIED BEFORE TRUSTED. With the pre-0156 proposer restored inside a
-- rolled-back transaction: no_asset_starves... = FALSE ("2 of 4 assets
-- ended under 90% having never been assigned a charge point while one
-- stood free") and charge_point_matches_the_asset_need = FALSE ("0 of
-- 3"). On the live engine, same fixture: 13 of 13 pass. Record in
-- db/checks/0075.
-- =====================================================================

CREATE OR REPLACE FUNCTION twin.ottoq_grid_assert(p_run uuid)
RETURNS TABLE(check_code text, passed boolean, detail text)
LANGUAGE plpgsql STABLE
AS $fn$
DECLARE
  v_depot uuid; v_status text; v_ticks int; v_cap numeric; v_max numeric;
  n bigint; n2 bigint; n3 bigint; v_out text; v_eq text;
  v_plan numeric; v_bound boolean; v_refusals bigint;
BEGIN
  SELECT r.depot_id, r.status, r.tick_count INTO v_depot, v_status, v_ticks
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run;
  IF v_depot IS NULL THEN RAISE EXCEPTION 'grid_assert: run % not found', p_run; END IF;
  SELECT d.service_max_kw INTO v_cap FROM public.depots d WHERE d.id = v_depot;

  -- 1. the run finished
  check_code := 'run_completed'; passed := (v_status = 'completed');
  detail := 'status='||COALESCE(v_status,'-')||', ticks='||COALESCE(v_ticks::text,'-'); RETURN NEXT;

  -- 2. enactment and calendar are one act (0154)
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

  -- 5. 0157: THE POINT MATCHES THE ASSET'S NEED, or the record says why not.
  --    Replaces dcfc_first_l2_only_as_overflow, which asserted a policy the
  --    engine does not have. wanted_type comes from the proposer's own
  --    rationale; a mismatch is justified by an explicit power downgrade (0156)
  --    or by no point of the wanted type being free at that moment.
  SELECT count(*),
         count(*) FILTER (WHERE
              d.enacted_action->'rationale'->>'wanted_type' IS NULL
           OR s.stall_type::text = d.enacted_action->'rationale'->>'wanted_type'
           OR COALESCE(d.enacted_action->'rationale'->>'power_downgrade','false') = 'true'
           OR NOT EXISTS (SELECT 1 FROM public.stalls s2
                           WHERE s2.depot_id = v_depot
                             AND s2.stall_type::text = d.enacted_action->'rationale'->>'wanted_type'
                             AND s2.ocpp_charger_id IS NOT NULL
                             AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings o
                                              WHERE o.sim_run_id = p_run AND o.stall_id = s2.id
                                                AND o.state IN ('held','active','done','interrupted')
                                                AND o.during @> d.sim_clock)))
    INTO n, n2
    FROM public.ottoq_decisions d JOIN public.stalls s ON s.id = (d.enacted_action->>'stall_id')::uuid
   WHERE d.sim_run_id = p_run AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
     AND s.stall_type::text IN ('dcfc','l2');
  check_code := 'charge_point_matches_the_asset_need'; passed := (n > 0 AND n = n2);
  detail := n2||' of '||n||' charge assignments matched wanted_type, were a declared power downgrade, or had no point of the wanted type free'
            ||CASE WHEN n = 0 THEN ' (vacuous: no charge assignments)' ELSE '' END; RETURN NEXT;

  -- 6. 0157: the fast point goes to whoever needs it. An inversion is a
  --    same-tick pair where the L2-assigned asset WANTED dcfc and the
  --    DCFC-assigned asset wanted l2 - a real misallocation. Ranking by raw SoC
  --    was wrong: a higher-SoC asset can correctly hold the fast point when the
  --    lower-SoC one asked for a slow one.
  SELECT count(*) INTO n
    FROM public.ottoq_decisions a JOIN public.stalls sa ON sa.id = (a.enacted_action->>'stall_id')::uuid
    JOIN public.ottoq_decisions b ON b.sim_run_id = a.sim_run_id AND b.tick_seq = a.tick_seq
                                 AND b.action_context = 'stall_assignment' AND b.outcome_status = 'enacted'
    JOIN public.stalls sb ON sb.id = (b.enacted_action->>'stall_id')::uuid
   WHERE a.sim_run_id = p_run AND a.action_context = 'stall_assignment' AND a.outcome_status = 'enacted'
     AND sa.stall_type::text = 'l2'  AND a.enacted_action->'rationale'->>'wanted_type' = 'dcfc'
     AND sb.stall_type::text = 'dcfc' AND b.enacted_action->'rationale'->>'wanted_type' = 'l2'
     AND COALESCE(a.enacted_action->'rationale'->>'power_downgrade','false') <> 'true';
  SELECT count(*) INTO n2
    FROM public.ottoq_decisions d JOIN public.stalls s ON s.id = (d.enacted_action->>'stall_id')::uuid
   WHERE d.sim_run_id = p_run AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
     AND s.stall_type::text IN ('dcfc','l2');
  check_code := 'the_fast_point_goes_to_whoever_needs_it'; passed := (n = 0 AND n2 > 0);
  detail := n||' need-inversions among '||n2||' charge assignments'||CASE WHEN n2 = 0 THEN ' (vacuous)' ELSE '' END; RETURN NEXT;

  -- 7. 0157: THE CAP HOLDS IN THE PLAN, NOT ONLY ON THE METER. The meter is
  --    charger-reported and lags the commitment; a check that reads it alone
  --    passes a run in which the scheduler committed twice the cap. The plan is
  --    replayed from the booking calendar: at every decision clock, the sum of
  --    requested_kw over the charge bookings live at that instant.
  SELECT max(e.total_ev_charging_kw) INTO v_max FROM public.site_energy_snapshots e WHERE e.sim_run_id = p_run;
  SELECT COALESCE(max(t.plan_kw), 0) INTO v_plan FROM (
     SELECT c.sim_clock,
            SUM((a.enacted_action->>'requested_kw')::numeric) AS plan_kw
       FROM (SELECT DISTINCT sim_clock FROM public.ottoq_decisions WHERE sim_run_id = p_run) c
       JOIN public.ottoq_stall_bookings b ON b.sim_run_id = p_run
                                         AND b.purpose IN ('charge_dcfc','charge_l2')
                                         AND b.state IN ('held','active','done','interrupted')
                                         AND b.during @> c.sim_clock
       JOIN public.ottoq_decisions a ON a.sim_run_id = p_run AND a.entity_id = b.vehicle_id
                                    AND a.action_context = 'stall_assignment' AND a.outcome_status = 'enacted'
                                    AND (a.enacted_action->>'stall_id')::uuid = b.stall_id
                                    AND a.sim_clock = lower(b.during)
      GROUP BY c.sim_clock) t;
  check_code := 'site_power_cap_held_in_plan_and_meter';
  passed := (v_cap IS NOT NULL AND v_plan <= v_cap AND COALESCE(v_max, -1) <= v_cap AND v_max IS NOT NULL);
  detail := 'peak planned commitment '||v_plan||' kW, peak metered '||COALESCE(v_max::text,'(no snapshots)')
            ||' kW, service_max_kw '||COALESCE(v_cap::text,'(none declared)'); RETURN NEXT;

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

  -- 11. the same seed produced the same run
  SELECT r.validation_notes::jsonb->>'outcome', r.validation_notes::jsonb->>'equal' INTO v_out, v_eq
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_run;
  check_code := 'pair_verdict_passed'; passed := (v_out = 'passed');
  detail := COALESCE('outcome='||v_out||', equal='||v_eq, 'no verdict on this run (not a certification arm)'); RETURN NEXT;

  -- 12. 0157: NO ASSET STARVES WHILE A CAPABLE POINT IS FREE. The 0156 check.
  --     An asset starved if it ended below 90% SoC, never received a single
  --     charge assignment all run, and at some decision clock a charging point
  --     with a charger stood unbooked. That is the exact signature of the
  --     defect 0156 closed: two assets at 73% and 60% held for a whole run
  --     beside two idle 19.2 kW points.
  SELECT count(*), count(*) FILTER (WHERE starved) INTO n, n2 FROM (
    SELECT v.id,
           (v.current_soc < 90
            AND NOT EXISTS (SELECT 1 FROM public.ottoq_decisions d
                             JOIN public.stalls s ON s.id = (d.enacted_action->>'stall_id')::uuid
                            WHERE d.sim_run_id = p_run AND d.entity_id = v.id
                              AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
                              AND s.stall_type::text IN ('dcfc','l2'))
            AND EXISTS (SELECT 1 FROM (SELECT DISTINCT sim_clock FROM public.ottoq_decisions WHERE sim_run_id = p_run) c
                         JOIN public.stalls s2 ON s2.depot_id = v_depot
                                              AND s2.stall_type::text IN ('dcfc','l2')
                                              AND s2.ocpp_charger_id IS NOT NULL
                        WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings o
                                           WHERE o.sim_run_id = p_run AND o.stall_id = s2.id
                                             AND o.state IN ('held','active','done','interrupted')
                                             AND o.during @> c.sim_clock))
           ) AS starved
      FROM public.vehicles v WHERE v.home_depot_id = v_depot AND v.category = 'autonomous') x;
  check_code := 'no_asset_starves_while_a_capable_point_is_free'; passed := (n > 0 AND n2 = 0);
  detail := n2||' of '||n||' assets ended under 90% having never been assigned a charge point while one stood free'
            ||CASE WHEN n = 0 THEN ' (vacuous: no assets)' ELSE '' END; RETURN NEXT;

  -- 13. 0157: was the cap ever actually tested? A green cap check on a run
  --     where the cap never bound is not evidence, and must not read as if it
  --     were. When it did bind, a refusal must exist to show for it.
  SELECT count(*) INTO v_refusals
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = p_run
     AND (d.outcome_status = 'deferred_site_power_cap'
          OR (d.outcome_status = 'overridden_to_default'
              AND d.override_rule_codes @> ARRAY['EN.001.grid_capacity_ceiling']));
  v_bound := (v_cap IS NOT NULL AND v_plan > v_cap * 0.80);
  check_code := 'the_power_cap_was_exercised';
  passed := (NOT v_bound) OR (v_refusals > 0);
  detail := CASE WHEN v_bound THEN 'cap bound (peak plan '||v_plan||' kW vs '||v_cap||' kW); '||v_refusals||' power refusals recorded'
                 ELSE 'CAP NEVER BOUND on this run (peak plan '||v_plan||' kW vs cap '||COALESCE(v_cap::text,'none')
                      ||') - this run is not evidence about the cap; '||v_refusals||' power refusals' END; RETURN NEXT;
  RETURN;
END;
$fn$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_assertions_state_the_rule_the_engine_actually_has', false,
        'Harness: grid assertions 5 and 6 restated against the engine''s real need-matched routing rule instead of a naive dcfc-first policy it does not implement; the cap check now replays the plan from the booking calendar as well as reading the meter; adds no_asset_starves_while_a_capable_point_is_free (the 0156 check) and the_power_cap_was_exercised so a green row on a slack run cannot pass as evidence.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
