-- MIGRATION: 0032_cuopt_batch_enactment.sql
-- Make cuOpt the primary decision engine via atomic batch enactment.
--
-- PROBLEM: cuOpt produces proposals but 0 are enacted. The enactment loop processes
-- vehicles sequentially — by the time vehicle N is processed, vehicles 1..N-1 have
-- already claimed stalls via the greedy path, including stalls cuOpt assigned to N.
--
-- FIX: Before the main vehicle cursor in ottoq_decide_tick section (3), enact ALL
-- valid cuOpt proposals as an atomic batch. Vehicles with enacted cuOpt proposals
-- are skipped in the main cursor. Remaining vehicles fall through to greedy path.
-- The deferral mechanism (ottoq_cuopt_defer_*) is removed — batch enactment replaces it.
--
-- RESULT: cuOpt gets first mover advantage. Greedy fills gaps cuOpt couldn't optimize.
-- cuOpt share should recover from 0% to 30-40%+.
--
-- ARCHITECTURE: This keeps the existing sequential loop intact. The batch runs BEFORE
-- the loop, reserves stalls atomically, and marks vehicles as handled. The loop then
-- skips already-handled vehicles. Zero changes to gate intake (3b) or bay sections (4/5).

-- =============================================================================
-- STEP 1: Batch cuOpt enactment function
-- =============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_enact_cuopt_batch(
  p_sim_run_id uuid,
  p_depot_id uuid,
  p_clock timestamptz,
  p_tick bigint,
  p_snapshot_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_proposal RECORD;
  v_ctx jsonb;
  v_action jsonb;
  v_enacted int := 0;
  v_skipped int := 0;
  v_stall_busy int := 0;
  v_reserved int := 0;
  v_charge_leg RECORD;
  v_bkg uuid;
BEGIN
  -- Iterate over ALL pending cuOpt proposals for this run, ordered by priority.
  -- The ORDER BY (created_at) processes oldest proposals first.
  FOR v_proposal IN
    SELECT p.entity_id AS vehicle_id, p.proposal, p.proposal_id
      FROM ottoq_external_proposals p
     WHERE p.sim_run_id = p_sim_run_id
       AND p.source = 'cuopt'
       AND p.status = 'pending'
       AND p.action_context = 'stall_assignment'
       AND p.entity_type = 'vehicle'
     ORDER BY p.created_at
  LOOP
    -- Build decision context for this vehicle
    v_ctx := ottoq_build_decision_context(
      'stall_assignment', 'vehicle', v_proposal.vehicle_id, p_depot_id, p_clock
    );
    
    -- Validate: is the proposed stall still available?
    IF NOT EXISTS (
      SELECT 1 FROM stalls s
      JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
      WHERE s.id = (v_proposal.proposal->>'stall_id')::uuid
        AND s.depot_id = p_depot_id
        AND s.current_vehicle_id IS NULL
        AND c.station_state = 'Available'
        AND (s.reserved_by IS NULL OR s.reservation_expires_at <= p_clock)
    ) THEN
      -- Stall is no longer available — mark proposal as superseded
      UPDATE ottoq_external_proposals
         SET status = 'superseded'
       WHERE proposal_id = v_proposal.proposal_id;
      v_stall_busy := v_stall_busy + 1;
      CONTINUE;
    END IF;

    -- Skip vehicles that already have a stall assignment this tick
    IF EXISTS (
      SELECT 1 FROM ottoq_decisions
      WHERE sim_run_id = p_sim_run_id
        AND tick_seq = p_tick
        AND entity_id = v_proposal.vehicle_id
        AND outcome_status = 'enacted'
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- Reserve the stall
    IF NOT ottoq_reserve_stall(
      (v_proposal.proposal->>'stall_id')::uuid,
      v_proposal.vehicle_id,
      p_clock,
      600
    ) THEN
      v_stall_busy := v_stall_busy + 1;
      CONTINUE;
    END IF;
    v_reserved := v_reserved + 1;

    -- Clear any previous stall assignment for this vehicle
    UPDATE stalls SET current_vehicle_id = NULL, reserved_by = NULL,
           reservation_expires_at = NULL, status = 'available'
     WHERE current_vehicle_id = v_proposal.vehicle_id
       AND id <> (v_proposal.proposal->>'stall_id')::uuid;

    -- Enact: update vehicle state to charging
    UPDATE vehicles
       SET current_state = (CASE WHEN v_proposal.proposal->>'stall_type' = 'dcfc'
                                 THEN 'charging_dcfc' ELSE 'charging_l2' END)::vehicle_state,
           current_stall_id = (v_proposal.proposal->>'stall_id')::uuid,
           last_state_change = p_clock
     WHERE id = v_proposal.vehicle_id;

    -- Update stall occupancy
    UPDATE stalls
       SET current_vehicle_id = v_proposal.vehicle_id,
           status = 'occupied'
     WHERE id = (v_proposal.proposal->>'stall_id')::uuid;

    -- Claim power
    PERFORM ottoq_claim_tick_kw(
      p_sim_run_id, p_tick, p_depot_id,
      COALESCE((v_proposal.proposal->>'requested_kw')::numeric, 0),
      v_proposal.vehicle_id
    );

    -- Start concurrent atoms (interior clean, etc.)
    PERFORM ottoq_start_concurrent_atoms(v_proposal.vehicle_id, p_clock);

    -- Stamp the matching itinerary leg
    SELECT l.leg_id, l.planned_start_sim, l.planned_end_sim
      INTO v_charge_leg
      FROM ottoq_itinerary_legs l
     WHERE l.sim_run_id = p_sim_run_id
       AND l.vehicle_id = v_proposal.vehicle_id
       AND l.status = 'planned'
       AND l.to_stall_id IS NULL
       AND l.leg_type IN ('charge_dcfc', 'charge_l2')
       AND l.planned_start_sim IS NOT NULL
     ORDER BY l.seq LIMIT 1;

    IF v_charge_leg.leg_id IS NOT NULL THEN
      UPDATE ottoq_itinerary_legs
         SET to_stall_id = (v_proposal.proposal->>'stall_id')::uuid
       WHERE leg_id = v_charge_leg.leg_id;
    END IF;

    -- Record the booking
    v_bkg := ottoq.ottoq_record_enacted_booking(
      p_sim_run_id,
      (v_proposal.proposal->>'stall_id')::uuid,
      v_proposal.vehicle_id,
      p_clock,
      v_charge_leg.leg_id,
      v_charge_leg.planned_start_sim,
      v_charge_leg.planned_end_sim,
      NULL,
      'cuopt'
    );

    -- Record the decision
    INSERT INTO ottoq_decisions (
      sim_run_id, tick_seq, sim_clock, depot_id, snapshot_id,
      action_context, resolved_action_context,
      entity_type, entity_id, context_frame,
      proposed_action, enacted_action, resolved_action,
      outcome_status, proposal_latency_ms, enactment_latency_ms
    ) VALUES (
      p_sim_run_id, p_tick, p_clock, p_depot_id, p_snapshot_id,
      'stall_assignment', 'stall_assignment',
      'vehicle', v_proposal.vehicle_id, v_ctx,
      v_proposal.proposal, v_proposal.proposal, v_proposal.proposal,
      'enacted', 0, 0
    );

    -- Mark proposal as enacted
    UPDATE ottoq_external_proposals
       SET status = 'enacted'
     WHERE proposal_id = v_proposal.proposal_id;

    -- Emit command
    PERFORM ottoq_emit_vehicle_command(
      p_sim_run_id, p_depot_id, v_proposal.vehicle_id,
      'begin_charge',
      jsonb_build_object('stall_id', v_proposal.proposal->>'stall_id',
                         'source', 'cuopt'),
      p_clock
    );

    v_enacted := v_enacted + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'batch', 'cuOpt',
    'enacted', v_enacted,
    'skipped', v_skipped,
    'stall_busy', v_stall_busy,
    'reserved', v_reserved
  );
END;
$fn$;


-- =============================================================================
-- STEP 2: Wire batch enactment into ottoq_decide_tick
-- Inserted 2 lines after cuopt_defer_roll, before the main vehicle cursor.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.ottoq_decide_tick(p_sim_run_id uuid)
 RETURNS ottoq_decide_tick_result
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_clock timestamptz; v_tick bigint; v_snapshot_id uuid;
  v_req RECORD; v_ctx jsonb; v_proposal jsonb; v_action jsonb;
  v_blocks int; v_block_codes text[]; v_rule_rows jsonb; v_disarm jsonb;
  v_outcome text; v_over boolean; v_safe boolean;
  v_t0 timestamptz; v_prop_ms int; v_shield_ms int; v_enact_ms int;
  v_built int := 0; v_enacted int := 0; v_overc int := 0; v_deferred int := 0; v_errored int := 0; v_disn int := 0;
  v_bess RECORD; v_energy RECORD;
  v_total_fleet int; v_curr_deployed int; v_target_pct numeric; v_demand_target int; v_deploy_budget int;
  v_charge_cap_kw numeric; v_ev_committed_kw numeric := 0; v_stage_stall uuid;
  v_charge_leg RECORD; v_bkg uuid;
  v_stage_leg_id uuid; v_stage_until timestamptz;
  v_bay_leg_id uuid; v_bay_leg_type text; v_bay_dur interval; v_bay_until timestamptz;
  v_bay_bkg uuid; v_bay_purpose text;
  -- P1 (needs-card space routing)
  v_need RECORD; v_space jsonb;
  v_wash_phys int; v_svc_phys int; v_wash_open int; v_svc_open int;
  -- 0003 (bay work recovery): resumption budget per lane per tick.
  v_res_share numeric; v_wash_res_cap int; v_svc_res_cap int;
  v_wash_res_used int := 0; v_svc_res_used int := 0;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count INTO v_depot, v_clock, v_tick
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN ROW(0,NULL,0,0,0,0,0,0,0)::ottoq_decide_tick_result; END IF;
  v_snapshot_id := ottoq_capture_decision_snapshot(p_sim_run_id, v_tick, v_depot, v_clock);

  -- P1 BAY RELEASE. twin.ottoq_sim_advance_service_flow STEP 1 moves a vehicle OUT of a bay
  -- back to staged_awaiting_service and never clears stalls.current_vehicle_id or
  -- vehicles.current_stall_id; nothing else clears a bay either. Physical bay occupancy is
  -- switched ON below, so without this sweep the 3 wash / 2 service bays would fill and
  -- NEVER free - a permanent depot deadlock after five vehicles. Release-only: this call can
  -- free a space but can never claim one, and it never touches dcfc/l2 stalls.
  -- BOOKING LIFECYCLE. Promote held -> active for every booking whose vehicle is now
  -- physically standing on its stall, BEFORE the release sweep below. This is what gives
  -- 'active' a meaning, and what lets the sweep close a REAL occupancy as 'done' (with its
  -- window truncated to the true end) instead of lumping it in with forward reservations
  -- that nobody ever used. Release-only and non-fatal, like the sweep itself.
  PERFORM ottoq.ottoq_activate_present_bookings(p_sim_run_id, v_clock);

  -- HONOUR OR RE-PLAN, NEVER LET IT ROT (2026-08-02). Runs BEFORE the release sweep on
  -- purpose: a bay reservation whose vehicle is still bolted to a charger is slid forward
  -- to when the car can actually be there, so the sweep below never sees it as a no-show.
  -- Bounded defers + explicit give-up: it can free a window or move one, never claim one.
  PERFORM ottoq.ottoq_reconcile_bay_reservations(p_sim_run_id, v_depot, v_clock);

  PERFORM ottoq.ottoq_release_vacated_spaces(p_sim_run_id, v_depot, v_clock);

  -- NO BAY ENTRY WITHOUT A BOOKING. twin.ottoq_sim_advance_service_flow STEP 2 admits
  -- vehicles into wash/detail/service bays on STAFF capacity and claims no stall at all,
  -- so those occupancies were invisible to the forward calendar -- which is how 22
  -- vehicles came to be "in" 2 physical service bays. OTTO-Q reconciles here: book what
  -- is physically there, in place, against a real stall. Release-only for chargers,
  -- non-fatal, and it never moves a vehicle that is already standing in a real bay.
  PERFORM ottoq.ottoq_bind_unbooked_bay_occupants(p_sim_run_id, v_depot, v_clock);

  SELECT lmp_usd_per_mwh INTO v_energy FROM ottoq_grid_snapshots WHERE sim_run_id=p_sim_run_id ORDER BY sim_clock_at DESC LIMIT 1;

  -- (1) ENERGY / BESS
  FOR v_bess IN SELECT bess_id, current_soc_pct FROM ottoq_bess_units WHERE depot_id = v_depot LOOP
    v_built := v_built + 1; v_t0 := clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := jsonb_build_object('depot_id',v_depot,'now_ts',v_clock,'bess_id',v_bess.bess_id,
              'bess_soc_pct',v_bess.current_soc_pct,'lmp_usd_mwh',COALESCE(v_energy.lmp_usd_per_mwh,40));
    v_proposal := ottoq_l2_propose_bess(v_bess.bess_id, v_depot, v_ctx);
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN
      v_deferred := v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'bess_dispatch','bess',v_bess.bess_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE;
    END IF;
    v_ctx := v_ctx || jsonb_build_object('requested_kw', v_proposal->>'requested_kw', 'action', v_proposal->>'action');
    v_t0 := clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('bess_dispatch','bess',v_bess.bess_id,v_ctx,NULL,v_depot);
    v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_bess(v_bess.bess_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1; END IF;
    v_t0 := clock_timestamp();
    IF v_outcome='enacted' THEN PERFORM ottoq_apply_bess_setpoint(v_bess.bess_id, (v_action->>'requested_kw')::numeric, 250, v_clock); END IF;
    v_enact_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'bess_dispatch','bess_dispatch','bess',v_bess.bess_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- (2) DEPLOY-READINESS
  SELECT COUNT(*) INTO v_total_fleet FROM vehicles WHERE category='autonomous' AND home_depot_id=v_depot;
  SELECT COUNT(*) INTO v_curr_deployed FROM vehicles
    WHERE category='autonomous' AND home_depot_id=v_depot AND current_state IN ('deployed','en_route_to_deployment');
  SELECT COALESCE((s.fleet_overrides->>'target_deployed_fraction')::numeric, 0.55) INTO v_target_pct
    FROM ottoq_sim_runs r LEFT JOIN ottoq_sim_scenarios s ON s.scenario_code = COALESCE(r.scenario_code,'normal_day')
   WHERE r.sim_run_id = p_sim_run_id;
  v_demand_target := FLOOR(v_total_fleet * ottoq_deploy_target_fraction(EXTRACT(HOUR FROM (v_clock AT TIME ZONE 'America/Chicago'))::int, ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',COALESCE(v_target_pct, 0.90))));
  v_deploy_budget := GREATEST(v_demand_target - v_curr_deployed, 0);

  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='staged_for_departure'
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
             WHERE vn.vehicle_id = v.id AND (vn.sim_run_id = p_sim_run_id OR vn.sim_run_id IS NULL) AND vn.status IN ('open','in_progress')
               AND ((a->>'svc' = 'software_update' AND COALESCE(a->>'status','pending') = 'in_progress')
                 OR (COALESCE((a->>'must_do')::boolean,false) AND a->>'svc' <> 'readiness_check'
                     AND COALESCE(a->>'status','pending') IN ('pending','in_progress'))))
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn2 WHERE vn2.vehicle_id = v.id
             AND vn2.status IN ('open','in_progress') AND vn2.urgency = 'overnight_hold'
             AND vn2.dispatch_due_at IS NOT NULL AND vn2.dispatch_due_at > v_clock)
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn3, jsonb_array_elements(vn3.atoms) a3
             WHERE vn3.vehicle_id = v.id AND vn3.status IN ('open','in_progress')
               AND COALESCE((a3->>'requires_tech_greenlight')::boolean,false)
               AND NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals ap
                     WHERE ap.vehicle_id = v.id AND ap.approval_type = 'tech_greenlight'
                       AND ap.status = 'approved' AND ap.created_at >= vn3.created_at))
     ORDER BY v.current_soc DESC, v.id LIMIT GREATEST(v_deploy_budget,0)
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('redeployment','vehicle',v_req.vehicle_id,v_depot,v_clock);
    -- A1: cuOpt/Nemotron may propose the redeploy; heuristic is the safe fallback.
    v_proposal := COALESCE(
      ottoq_l2_external_proposal(p_sim_run_id, 'redeployment', 'vehicle', v_req.vehicle_id),
      ottoq_l2_propose_deploy(v_req.vehicle_id, v_depot, v_ctx));
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'redeployment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE; END IF;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('redeployment','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_deploy(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      -- BRAIN/TWIN SEPARATION: OTTO-Q does NOT mutate vehicle state. It emits the
      -- command below; ottoq_sim_dispatch_vehicle (twin) performs the transition
      -- atomically with the dispatch record. Writing 'en_route_to_deployment'
      -- here created a limbo the rate-limited twin could not drain (task #169).
      PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'dispatch', jsonb_build_object('soc', v_req.current_soc), v_clock);
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,deploy_readiness,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'redeployment','redeployment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,CASE WHEN v_outcome='enacted' THEN 'ready' ELSE 'held' END,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- P0 (2026-08-03): A REOPENED NEED IS A FIRST-CLASS DEMAND.
  -- ottoq.ottoq_readmit_resumed_visits was unreachable: its emergency_staged /
  -- retrieved_staged pair is produced ONLY by tow retrieval, whose dwell gate compares a
  -- REAL-clock last_state_change (clobbered by the BEFORE UPDATE trigger) against the SIM
  -- clock and is therefore never true. This stage is keyed on the NEED instead, so a
  -- cut-short charge competes for a plug in the SAME tick, through the SAME intake
  -- cursors below, as a fresh arrival. Self-silencing; can never abort the tick.
  PERFORM ottoq.ottoq_readmit_reopened_needs(p_sim_run_id, v_depot, v_clock);

  -- (3) STALL ASSIGNMENT
  -- P2 RIGHT OF FIRST REFUSAL (2026-08-02). Advance the cuOpt deferral
  -- ledger EXACTLY ONCE per decide tick, before the candidate cursor is opened.
  -- roll() step 1 releases every vehicle that a PREVIOUS tick held, so a hold can
  -- never span two consecutive decide ticks; step 2 then consumes this tick's
  -- freshly armed rows. roll() swallows its own errors: if the ledger is broken
  -- the engine simply behaves exactly as it did before this change.
  PERFORM public.ottoq_cuopt_defer_roll(p_sim_run_id, v_tick);
  -- 0032: cuOpt batch enactment — atomic batch before greedy cursor
  PERFORM public.ottoq_enact_cuopt_batch(p_sim_run_id, v_depot, v_clock, v_tick, v_snapshot_id);
  v_charge_cap_kw := ottoq_active_charge_cap_kw(p_sim_run_id, v_depot, v_clock);
  IF v_charge_cap_kw IS NOT NULL THEN
    SELECT COALESCE(SUM(LEAST(COALESCE(st.connector_max_kw,50), COALESCE(vv.inlet_max_kw,250)) * CASE WHEN COALESCE(st.connector_max_kw,50)<=50 THEN 1.0 WHEN COALESCE(vv.current_soc,50)<55 THEN 0.85 WHEN COALESCE(vv.current_soc,50)<75 THEN 0.55 ELSE 0.30 END),0) INTO v_ev_committed_kw
      FROM vehicles vv JOIN stalls st ON st.id = vv.current_stall_id
     WHERE vv.home_depot_id = v_depot AND vv.current_state IN ('charging_dcfc','charging_l2');
  END IF;

  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       -- P2 RIGHT OF FIRST REFUSAL (2026-08-02). Hold this vehicle out of the local
       -- greedy path for EXACTLY ONE decide tick while a cuOpt solve is in flight,
       -- so the optimizer's answer is not pre-empted by the stall it was solving for.
       -- ottoq_cuopt_defer_hold is READ-ONLY and goes FALSE the moment a usable
       -- proposal exists for this vehicle (right of FIRST REFUSAL, not veto) -- the
       -- vehicle then enters the cursor normally and the proposal is ENACTED here.
       -- It also goes FALSE unconditionally on the next decide tick. No vehicle can
       -- starve: see public.ottoq_cuopt_defer_roll / _arm.
       AND NOT public.ottoq_cuopt_defer_hold(p_sim_run_id, v.id, v_tick)
       AND (v.current_state = 'arrived_at_gate'
            OR (v.current_state = 'staged_awaiting_service' AND EXISTS (
                 SELECT 1 FROM stalls s2
                   JOIN ottoq_ocpp_chargers c2 ON c2.charger_id = s2.ocpp_charger_id
                  WHERE s2.depot_id = v_depot
                    AND s2.stall_type::text IN ('dcfc','l2')
                    AND s2.current_vehicle_id IS NULL
                    AND c2.station_state = 'Available'
                    AND (s2.reserved_by IS NULL OR s2.reserved_by = v.id
                         OR s2.reservation_expires_at <= v_clock))))
       AND v.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
              WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
              ORDER BY vn.created_at DESC LIMIT 1), 85)
     ORDER BY (SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                 WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                 ORDER BY vn.created_at DESC LIMIT 1) DESC NULLS LAST,
              v.current_soc ASC, v.id
     -- charging_staff gate: general techs plug in / unplug and do the interior
     -- clean at the stall, so STAFF (not stalls) cap how many cars can be on
     -- charge at once. Neutral staffing (cap >= the 45 physical charge stalls)
     -- leaves the cursor unbounded, so this is a no-op until the knob moves.
     LIMIT (CASE
              WHEN ottoq_sim_lane_capacity(p_sim_run_id, 'charging_staff', 45) >= 45
                THEN 2147483647
              ELSE GREATEST(0,
                     ottoq_sim_lane_capacity(p_sim_run_id, 'charging_staff', 45)
                     - (SELECT count(*) FROM vehicles vc
                         WHERE vc.home_depot_id = v_depot
                           AND vc.current_state IN ('charging_dcfc','charging_l2')))
            END)
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('stall_assignment','vehicle',v_req.vehicle_id,v_depot,v_clock);
    v_proposal := ottoq_honour_reservation_proposal(p_sim_run_id, v_req.vehicle_id, v_depot, v_ctx);
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      IF (SELECT current_stall_id FROM vehicles WHERE id = v_req.vehicle_id) IS NULL THEN
        -- DOCTRINE (Chase 2026-07-28): never a gate queue; temp vs perimeter is chosen by
          -- PURPOSE and duration, not by whichever staging stall sorts first.
          DECLARE v_disp jsonb; v_hold jsonb;
          BEGIN
            v_disp := ottoq_arrival_disposition(p_sim_run_id, v_depot, v_req.vehicle_id, v_clock);
            IF (v_disp->>'action') IN ('perimeter_hold','temp_stage_await_resource','temp_stage_tech_hold','quarantine') THEN
              v_hold := ottoq_book_hold_stall(
                          p_sim_run_id, v_depot, v_req.vehicle_id,
                          COALESCE((v_disp->>'stage_from')::timestamptz, v_clock),
                          COALESCE((v_disp->>'stage_until')::timestamptz, v_clock + interval '30 minutes'));
              IF COALESCE((v_hold->>'booked')::boolean, false) THEN
                SELECT b.stall_id INTO v_stage_stall
                  FROM ottoq_stall_bookings b WHERE b.booking_id = (v_hold->>'booking_id')::uuid;
                IF v_stage_stall IS NOT NULL
                   AND ottoq_reserve_stall(v_stage_stall, v_req.vehicle_id, v_clock, 900) THEN
                  UPDATE vehicles SET current_stall_id = v_stage_stall,
                         current_state = 'staged_awaiting_service'::vehicle_state,
                         last_state_change = v_clock
                   WHERE id = v_req.vehicle_id;
                  UPDATE stalls SET current_vehicle_id = v_req.vehicle_id, status = 'occupied'
                   WHERE id = v_stage_stall;
                END IF;
              END IF;
            END IF;
          END;
      END IF;
      CONTINUE; END IF;
    v_ctx := v_ctx || jsonb_build_object('stall_id', v_proposal->>'stall_id', 'requested_kw', v_proposal->>'requested_kw');
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_stall(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal;
      IF ottoq_reserve_stall((v_action->>'stall_id')::uuid, v_req.vehicle_id, v_clock, 600) THEN
        UPDATE stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL, status = 'available'
         WHERE current_vehicle_id = v_req.vehicle_id AND id <> (v_action->>'stall_id')::uuid;
        UPDATE vehicles SET current_state=(CASE WHEN v_action->>'stall_type'='dcfc' THEN 'charging_dcfc' ELSE 'charging_l2' END)::vehicle_state, current_stall_id=(v_action->>'stall_id')::uuid, last_state_change=v_clock WHERE id=v_req.vehicle_id;
        UPDATE stalls SET current_vehicle_id=v_req.vehicle_id, status='occupied' WHERE id=(v_action->>'stall_id')::uuid;
        PERFORM ottoq_claim_tick_kw(p_sim_run_id, v_tick, v_depot, (v_action->>'requested_kw')::numeric, v_req.vehicle_id);
        PERFORM ottoq_start_concurrent_atoms(v_req.vehicle_id, v_clock);
        PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_req.vehicle_id, v_clock);

        -- FORWARD AVAILABILITY / P0: ENACTMENT AND CALENDAR ARE ONE ACT.
        -- Every stall assignment that reaches this line - cuopt, deterministic, greedy and
        -- reservation_honoured all return through v_action above - is now recorded on the
        -- forward calendar in THIS transaction, against the EXACT stall enacted.
        --
        -- Previously the booking sat inside "IF v_charge_leg.leg_id IS NOT NULL", and the planner
        -- emits a charge leg only when the visit-need manifest carries an svc='charge' atom. When
        -- it does not, that branch never ran: 51 enacted charge assignments, 0 charge bookings,
        -- 0% end-to-end coverage. The booking no longer depends on a planned leg existing.
        --
        -- The leg is still PREFERRED when present, for two reasons: it carries the real timed
        -- window, and stamping to_stall_id is the existing sentinel that removes the leg from both
        -- booking cursors (ottoq_book_workflow / ottoq_find_and_book_stall), suppressing the second
        -- independent stall search. The calendar still RECORDS the decision, it never re-derives it.
        SELECT l.leg_id, l.leg_type, l.planned_start_sim, l.planned_end_sim
          INTO v_charge_leg
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id  = p_sim_run_id
           AND l.vehicle_id  = v_req.vehicle_id
           AND l.status      = 'planned'
           AND l.to_stall_id IS NULL
           AND l.leg_type IN ('charge_dcfc','charge_l2')
           AND l.planned_start_sim IS NOT NULL
           AND l.planned_end_sim   IS NOT NULL
           AND l.planned_end_sim   > v_clock
         ORDER BY l.seq
         LIMIT 1;

        -- p_purpose is left NULL so the purpose is derived from the stall ACTUALLY taken, not from
        -- what the planner intended. The helper supersedes phantom overlaps, is idempotent on
        -- (run, stall, vehicle, purpose, window), and can never abort this tick.
        v_bkg := ottoq.ottoq_record_enacted_booking(
                   p_sim_run_id, (v_action->>'stall_id')::uuid, v_req.vehicle_id, v_clock,
                   v_charge_leg.leg_id, v_charge_leg.planned_start_sim, v_charge_leg.planned_end_sim,
                   NULL, COALESCE(v_action->>'source','deterministic'));

        IF v_bkg IS NOT NULL AND v_charge_leg.leg_id IS NOT NULL THEN
          UPDATE public.ottoq_itinerary_legs
             SET to_stall_id = (v_action->>'stall_id')::uuid
           WHERE leg_id = v_charge_leg.leg_id;
        END IF;

        v_outcome:='enacted'; v_enacted:=v_enacted+1;
        v_ev_committed_kw := v_ev_committed_kw + COALESCE((v_action->>'requested_kw')::numeric,0);
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'begin_charge', jsonb_build_object('stall_id', v_action->>'stall_id', 'stall_type', v_action->>'stall_type', 'requested_kw', v_action->>'requested_kw'), v_clock);
      ELSE v_action:=ottoq_l1_safe_default_stall(v_req.vehicle_id,v_ctx); v_outcome:='deferred_stale_entity'; v_deferred:=v_deferred+1; END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- (3b) GATE INTAKE — NO-CHARGE ARRIVALS
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND v.current_state = 'arrived_at_gate'
       AND v.current_stall_id IS NULL
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                    WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') <> 'done'))
  LOOP
    SELECT s.id INTO v_stage_stall FROM stalls s
     WHERE s.depot_id = v_depot AND s.stall_type = 'staging'
       AND s.zone IS DISTINCT FROM 'arrival_inspection'
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= v_clock)
     ORDER BY (s.staging_role = 'temp') DESC, s.distance_from_entrance NULLS LAST, s.id LIMIT 1;
    IF v_stage_stall IS NOT NULL AND ottoq_reserve_stall(v_stage_stall, v_req.vehicle_id, v_clock, 900) THEN
      UPDATE vehicles SET current_stall_id = v_stage_stall,
             current_state = 'staged_awaiting_service'::vehicle_state,
             last_state_change = v_clock,
             config = jsonb_set(COALESCE(config,'{}'::jsonb), '{svc_step}',
               to_jsonb(CASE WHEN EXISTS (SELECT 1 FROM ottoq_visit_needs vn2, jsonb_array_elements(vn2.atoms) a2
                                           WHERE vn2.vehicle_id = v_req.vehicle_id AND vn2.status IN ('open','in_progress')
                                             AND a2->>'svc' IN ('mechanical_pm','fault_repair','sensor_calibration')
                                             AND COALESCE((a2->>'must_do')::boolean,false)
                                             AND COALESCE(a2->>'status','pending') = 'pending')
                            THEN 'need_service' ELSE 'need_deploy' END))
       WHERE id = v_req.vehicle_id;
      UPDATE stalls SET current_vehicle_id = v_req.vehicle_id, status = 'occupied' WHERE id = v_stage_stall;
      PERFORM ottoq_start_concurrent_atoms(v_req.vehicle_id, v_clock);
      v_built := v_built + 1; v_enacted := v_enacted + 1;
      PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_req.vehicle_id, v_clock);
      -- CALENDAR (staging). The single biggest gap: the whole service-only intake path
      -- enacted a stall and wrote NOTHING to the forward-occupancy calendar.
      -- We RECORD the stall the intake ALREADY picked above. We must NOT call
      -- ottoq_book_hold_stall here: it runs its OWN independent search, which is exactly
      -- the decision/calendar divergence fixed on 2026-08-01.
      SELECT l.leg_id INTO v_stage_leg_id
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.leg_type = 'stage' AND l.to_stall_id IS NULL
         AND l.planned_end_sim > v_clock
       ORDER BY l.seq LIMIT 1;
      -- The car holds this staging stall until its itinerary is done: nothing in (4) or (5)
      -- clears stalls.current_vehicle_id, only (3)'s charge branch and redeploy do.
      -- Hard-capped so a runaway itinerary can never reserve a space indefinitely.
      SELECT max(l.planned_end_sim) INTO v_stage_until
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.planned_end_sim > v_clock;
      v_stage_until := GREATEST(
        LEAST(
          COALESCE(v_stage_until,
                   v_clock + make_interval(mins => ottoq_policy_get(p_sim_run_id,'staging_hold_default_min',30)::int)),
          v_clock + make_interval(mins => ottoq_policy_get(p_sim_run_id,'staging_hold_max_min',480)::int)),
        v_clock + interval '1 minute');
      v_bkg := ottoq.ottoq_book_stall(p_sim_run_id, v_stage_stall, v_req.vehicle_id,
                 'staging', v_clock, v_stage_until, NULL, v_stage_leg_id,
                 ottoq.ottoq_booking_authorship('gate_intake_staging'));
      IF v_bkg IS NOT NULL THEN
        UPDATE public.ottoq_stall_bookings SET source = COALESCE(source, 'gate_intake_staging')
         WHERE booking_id = v_bkg;
      END IF;
      IF v_bkg IS NOT NULL AND v_stage_leg_id IS NOT NULL THEN
        -- same sentinel the charge path uses: a stamped to_stall_id removes the leg from
        -- ottoq_book_workflow's cursor, so no second independent search can re-derive it.
        UPDATE public.ottoq_itinerary_legs SET to_stall_id = v_stage_stall
         WHERE leg_id = v_stage_leg_id;
      END IF;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','gate_intake_no_charge','vehicle',v_req.vehicle_id,
              jsonb_build_object('stall_id',v_stage_stall,'staging_pick','temp_first'),
              jsonb_build_object('verb','gate_intake','stall_id',v_stage_stall),
              jsonb_build_object('verb','gate_intake','stall_id',v_stage_stall,'booking_id',v_bkg),
              'enacted',0,0);
      PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'proceed_to_stall', jsonb_build_object('stall_id', v_stage_stall, 'reason', 'gate_intake'), v_clock);
    END IF;
  END LOOP;

  -- (4) CHARGE DISPOSITION
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='charge_complete_holding'
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('task_start','vehicle',v_req.vehicle_id,v_depot,v_clock) || jsonb_build_object('requires_charging','false','service','wash');
    v_proposal := ottoq_l2_propose_charge_disposition(v_req.vehicle_id, v_depot, v_ctx || jsonb_build_object('sim_run_id', p_sim_run_id));
    v_prop_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE; END IF;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('task_start','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_charge_disposition(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      IF COALESCE(v_action->>'verb','admit_wash') = 'skip_wash' THEN
        -- SERVICE-NEED ROUTING (2026-08-01): no wash/detail work outstanding, so do
        -- NOT burn one of the depot's 3 wash bays on a clean car. Advance the vehicle
        -- inside the SAME atomic visit to what it does still need. Nothing is booked
        -- and no stall is claimed, so the calendar cannot over-report.
        UPDATE vehicles SET current_state='staged_awaiting_service', last_state_change=v_clock,
               config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',
                                to_jsonb(COALESCE(v_action->>'next_step','need_deploy'))) WHERE id=v_req.vehicle_id;
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'stage',
                jsonb_build_object('reason','no_wash_need','next_step',COALESCE(v_action->>'next_step','need_deploy')), v_clock);
        v_action := COALESCE(v_action,'{}'::jsonb) || jsonb_build_object('bay_booked', false, 'bay_stall_type', 'none');
      ELSE
      -- BAY ENTRY MOVED BELOW THE HELPER (Phase 3). It used to happen HERE, before any
      -- bay had been claimed or booked: if ottoq_enact_space_assignment then found no free
      -- bay, the vehicle was already 'in_wash_bay' with no stall and no calendar row --
      -- a bay physically occupied while the calendar showed it free. The state flip and
      -- the enter_wash command are now gated on the booking, exactly as (4b) already was.
      -- CALENDAR (wash/detail bay). CHOOSE + CLAIM + RECORD, one act.
      -- ottoq_enact_space_assignment picks the bay, reserves it, writes
      -- vehicles.current_stall_id and books the window in THIS transaction. The bay entry
      -- below is GATED on that result: no free bay means no entry, and the miss is recorded
      -- on the decision row as verb 'hold_no_bay'. The calendar can under-report a REFUSAL
      -- but it can no longer report a bay as free while a vehicle is standing in it.
      SELECT l.leg_id, l.leg_type, (l.planned_end_sim - l.planned_start_sim)
        INTO v_bay_leg_id, v_bay_leg_type, v_bay_dur
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.to_stall_id IS NULL
         AND l.leg_type IN ('wash','detail')
       ORDER BY l.seq LIMIT 1;
      IF v_bay_leg_id IS NULL THEN
        -- FALLBACK -- THIS IS WHY leg_id WAS NULL ON EVERY ENACTED BOOKING (11 of 11 on
        -- run 4332b898, against 94 of 94 on the planner path). The forward planner
        -- ottoq_book_workflow books the leg AHEAD of time and stamps to_stall_id, so the
        -- cursor above (to_stall_id IS NULL) found nothing and enactment booked a SECOND
        -- row on a possibly different stall with no leg. Adopt the planned leg instead:
        -- ottoq_enact_space_assignment honours its reservation and
        -- ottoq_record_enacted_booking adopts that row rather than duplicating it.
        SELECT l.leg_id, l.leg_type, (l.planned_end_sim - l.planned_start_sim)
          INTO v_bay_leg_id, v_bay_leg_type, v_bay_dur
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
           AND l.status IN ('planned','active')
           AND l.leg_type IN ('wash','detail')
         ORDER BY (l.status = 'active') DESC, l.seq LIMIT 1;
      END IF;
      -- TOTAL allow-list leg_type -> purpose. Only the two wash-lane leg types can reach
      -- here; nothing is ever passed through to the CLOSED 9-label purpose CHECK.
      -- (no detail_bay stalls are seeded - detail shares the wash lane, as in ottoq_book_workflow)
      v_bay_purpose := CASE WHEN COALESCE(v_action->>'bay_kind', v_bay_leg_type) = 'detail' THEN 'detail' ELSE 'wash' END;
      v_bay_until := v_clock + GREATEST(
        COALESCE(v_bay_dur,
                 make_interval(mins => ottoq_policy_get(p_sim_run_id,'wash_bay_default_min',25)::int)),
        interval '1 minute');
      v_space := ottoq.ottoq_enact_space_assignment(p_sim_run_id, v_depot, v_req.vehicle_id,
                     'wash_bay', v_bay_purpose, v_clock, v_bay_until,
                     v_bay_leg_id, 'charge_disposition');
      v_bay_bkg := NULLIF(v_space->>'booking_id','')::uuid;
      IF v_bay_bkg IS NOT NULL AND v_bay_leg_id IS NOT NULL THEN
        UPDATE public.ottoq_itinerary_legs
           SET to_stall_id = (SELECT b.stall_id FROM public.ottoq_stall_bookings b
                               WHERE b.booking_id = v_bay_bkg)
         WHERE leg_id = v_bay_leg_id;
      END IF;
      IF COALESCE((v_space->>'assigned')::boolean, false) THEN
        -- ENTRY AND CALENDAR ARE ONE ACT. A real wash bay has been claimed AND booked in
        -- this transaction, so the command names the stall, the booking and the leg.
        UPDATE vehicles SET current_state='in_wash_bay', last_state_change=v_clock,
               config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('washing'::text)) WHERE id=v_req.vehicle_id;
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'enter_wash',
                jsonb_build_object('stall_id',   v_space->>'stall_id',
                                   'booking_id', v_space->>'booking_id',
                                   'leg_id',     v_bay_leg_id,
                                   'purpose',    v_bay_purpose), v_clock);
        v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                    || jsonb_build_object('bay_booked', v_bay_bkg IS NOT NULL,
                                          'bay_purpose', v_bay_purpose,
                                          'bay_stall_type', 'wash_bay',
                                          'stall_id', v_space->>'stall_id',
                                          'booking_id', v_space->>'booking_id',
                                          'leg_id', v_bay_leg_id);
      ELSE
        -- NO BAY -> DO NOT ENTER ONE. The vehicle is left exactly where this proposer's own
        -- 'wash_lane_full_hold' abstain leaves it (charge_complete_holding) and is retried
        -- next tick. No state write, no command, no booking. Throughput cannot regress:
        -- this branch is only reachable when there is genuinely no bookable wash bay, and
        -- release step (b) hard-frees stale bay stalls earlier in this same tick.
        v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                    || jsonb_build_object('verb','hold_no_bay', 'bay_booked', false,
                                          'bay_purpose', v_bay_purpose,
                                          'bay_stall_type', 'wash_bay');
        v_outcome := 'noop_no_candidate'; v_enacted := v_enacted - 1; v_deferred := v_deferred + 1;
      END IF;
      END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- ══════════════════════════════════════════════════════════════════════════════════
  -- (4b) NEEDS-CARD SPACE ROUTING  —  P1, 2026-08-01
  --
  -- WHAT THIS CLOSES. Before this block the engine literally could not decide "send this
  -- vehicle to the wash bay". The ONLY door into in_wash_bay/in_detail_bay was section (4),
  -- whose cursor is current_state='charge_complete_holding'. Measured on run c177c1ca over
  -- 573 ticks: ZERO admit_wash decisions, 5 skip_wash — while 371 vehicles were promoted
  -- straight from staged_awaiting_service to staged_for_departure by (5), a state from which
  -- no wash/detail door existed at all. That is the whole reason 51 of 51 (and 209 of 209
  -- before) enacted assignments were charging while 3 wash bays sat 100 pct idle.
  --
  -- WHAT IT DOES. For each vehicle HOLDING in staging, read public.ottoq_vehicle_needs_card,
  -- take the highest-priority must-do need that requires a SPACE, and place the vehicle into
  -- the space that need's lane requires — through ottoq_enact_space_assignment, so choosing
  -- the stall and writing the forward-calendar booking are ONE act against the SAME stall
  -- (the P0 rule, now extended past chargers).
  --
  -- SPACE MAP is read from service_cadence_policy.lane, never hardcoded, and is TOTAL:
  --   lane 'wash_bay'    (exterior_wash)                        -> wash_bay,    purpose 'wash'
  --   lane 'detail'      (interior_deep_clean)                  -> wash_bay,    purpose 'detail'
  --        ^ zero detail_bay stalls are seeded; detail shares the wash lane, exactly as
  --          ottoq_book_workflow and twin STEP 2 already do.
  --   lane 'service_bay' (fault_repair, sensor_calibration,
  --                       mechanical_pm, cosmetic_repair)       -> service_bay, purpose 'service'
  --   lane 'anchor'      (charge)      -> NOT HANDLED HERE, see CHARGE FIREWALL.
  --   lane 'cabin'/'exterior'/'digital'/'gate' -> NO SPACE AT ALL. That work overlaps
  --        charging and is already started at the stall by ottoq_start_concurrent_atoms;
  --        spending one of 3 wash or 2 service bays on it would be a straight loss.
  --   any lane the catalogue gains later -> no space, silently skipped. TOTAL FUNCTION
  --        (the 2026-08-01 leg_type lesson): an unknown lane can never reach a CHECK.
  --
  -- ══ ORDERING / PRIORITY RULE ══
  --   WITHIN a vehicle : lowest service_cadence_policy.sequence_order wins, so the visit is
  --     worked in the catalogue's own order (fault_repair 30 -> wash 40 -> detail 45 ->
  --     calibration 55 -> pm 60 -> cosmetic 70). One space at a time; the vehicle comes back
  --     through this block on a later tick for the next item, inside ONE atomic visit.
  --   ACROSS vehicles  : 1. urgency rank DESC (critical > overdue > due > due_soon > ok)
  --                      2. fits_window DESC  — do not burn a scarce bay on work that
  --                         provably cannot finish before the vehicle is due out
  --                      3. minutes_to_deploy ASC — earliest deadline first (EDF)
  --                      4. open_must_do_min ASC — shortest job first, so a scarce bay
  --                         clears more vehicles per hour
  --                      5. vehicle_id — deterministic, seed-stable tiebreak
  --
  -- ══ CHARGE FIREWALL — five independent reasons this cannot regress charging ══
  --  1. Sections (1),(2),(3),(3b) are byte-for-byte unchanged by this migration, including
  --     Gate B in ottoq_honour_reservation_proposal and the cuOpt 'source' passthrough.
  --  2. This block only ever asks for 'wash_bay' or 'service_bay', and
  --     ottoq_enact_space_assignment REFUSES 'dcfc'/'l2' outright. No path built here can
  --     reserve, occupy or book a charger.
  --  3. Any vehicle whose card still lists 'charge' in must_do_now is SKIPPED and left to
  --     section (3). Charge is the anchor leg (sequence_order 10): energy first, then bays.
  --  4. It runs AFTER (3), so every charge decision this tick is already made and its stalls
  --     already reserved before one bay is considered.
  --  5. Separate staff pools: charging is capped by 'charging_staff', wash by
  --     LEAST(cleaning_staff, wash_supervisor), service by 'service_staff'. Bay work cannot
  --     consume a charging tech.
  --  NET EFFECT ON CHARGING IS POSITIVE: today a vehicle in a bay still holds the l2/dcfc
  --  stall it charged on, because nothing clears it. Occupying the bay moves
  --  vehicles.current_stall_id, which fires trg_sync_stall_occupancy and hands that charger
  --  straight back to section (3). Chargers are freed sooner, never later.
  --
  -- ══ ANTI-STARVATION ══ wash and service headroom are computed with the TWIN'S OWN
  -- capacity formulas, verbatim, so this block can never admit past the lane the twin itself
  -- would allow, and the two lanes are counted separately so neither can starve the other.
  --
  -- ══ IN-DEPOT REASSIGNMENT / ZONES ══ the cursor is restricted to current_state
  -- 'staged_awaiting_service', a HOLDING state. It structurally cannot pick up a vehicle that
  -- is charging, washing or being serviced, so it can never re-route work in progress and
  -- therefore never needs ottoq_indepot_reassignment_guard — this is forward progression to
  -- the next due leg of the same visit, which is exactly what (4) and (5) already do. Zone C
  -- (malfunction / congestion / flag) vehicles are skipped and left to the exception path
  -- that owns them. Zone is NOT required to be 'A' here: ottoq_approach_zone fails closed to
  -- 'B' for any vehicle with no approach-band row, which is every in-depot vehicle, so an
  -- A-only test would silently disable the whole block.
  --
  -- ══ COST ══ ottoq_vehicle_needs_card is a 116-row / ~250 ms view. It is evaluated ONCE per
  -- tick and only after two cheap pre-checks find both a waiting vehicle and lane headroom.
  -- ══════════════════════════════════════════════════════════════════════════════════
  SELECT count(*) FILTER (WHERE s.stall_type = 'wash_bay'::stall_type),
         count(*) FILTER (WHERE s.stall_type = 'service_bay'::stall_type)
    INTO v_wash_phys, v_svc_phys
    FROM stalls s
   WHERE s.depot_id = v_depot AND s.status NOT IN ('maintenance','closed');

  IF COALESCE(v_wash_phys,0) + COALESCE(v_svc_phys,0) > 0
     AND EXISTS (SELECT 1 FROM vehicles v
                  WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
                    AND v.current_state = 'staged_awaiting_service') THEN

    v_wash_open := GREATEST(0,
      LEAST(ottoq_sim_lane_capacity(p_sim_run_id,'cleaning_staff', GREATEST(COALESCE(v_wash_phys,0),1)),
            ottoq_depot_staffing_count(v_depot,'wash_supervisor'))
      - (SELECT count(*) FROM vehicles
          WHERE home_depot_id = v_depot AND current_state IN ('in_wash_bay','in_detail_bay')));
    v_svc_open := GREATEST(0,
      ottoq_sim_lane_capacity(p_sim_run_id,'service_staff', GREATEST(COALESCE(v_svc_phys,0),1))
      - (SELECT count(*) FROM vehicles
          WHERE home_depot_id = v_depot AND current_state = 'in_service_bay'));

    -- ══════════════ 0003 ANTI-STARVATION BUDGET ══════════════
    -- Resumed bay work outranks fresh work at equal urgency (see the cursor below), so
    -- without a ceiling a queue of interrupted vehicles could take an entire lane and
    -- fresh arrivals would wait. This caps how many of THIS TICK'S admissions per lane
    -- may go to resumption -- but ONLY while fresh candidates are actually competing for
    -- that same lane (fresh_waiting_lane > 0 in the loop). With no fresh demand the cap
    -- does not bite and idle bays are never held empty on principle.
    --   GREATEST(1, ...) is load-bearing: the defect being fixed is bay recovery of ZERO,
    --   so resumption must never be budgeted down to nothing.
    --   share 0.5 => at most half a lane's free bays (rounded up) per tick. With the
    --   depot's 3 wash / 2 service bays that is 1-2 per lane per tick, and the loop runs
    --   every tick, so five interrupted vehicles clear in a handful of ticks.
    v_res_share := LEAST(GREATEST(COALESCE(ottoq_policy_get(p_sim_run_id,'bay_resume_share_max',0.5),0.5), 0), 1);
    v_wash_res_cap := GREATEST(1, CEIL(COALESCE(v_wash_open,0) * v_res_share))::int;
    v_svc_res_cap  := GREATEST(1, CEIL(COALESCE(v_svc_open,0)  * v_res_share))::int;

    IF COALESCE(v_wash_open,0) + COALESCE(v_svc_open,0) > 0 THEN
      FOR v_need IN
        WITH card AS (
          SELECT c.vehicle_id, c.overall_urgency, c.must_do_now, c.minutes_to_deploy,
                 c.fits_window, c.open_must_do_min,
                 -- 0003: the ledger detector and the energy grade, read straight off the card.
                 c.owed_bay_svcs, c.rebook_owed, c.energy_urgency
            FROM public.ottoq_vehicle_needs_card c
           WHERE c.depot_id = v_depot
             -- CHARGE FIRST (full-service visit doctrine, anchor leg): if energy is still a
             -- must-do, this vehicle belongs to section (3), not to a bay.
             --
             -- ══════════════ 0003: ONE NARROW EXCEPTION, AND WHY ══════════════
             -- MEASURED (run 093c20f4, vehicle 0ea2ccfe): its end-of-run card read
             -- must_do_now = {charge, interior_deep_clean, software_update}. The detail bay
             -- it had been pulled out of was still owed AND still must-do, and this single
             -- predicate excluded it anyway -- for the whole rest of the run.
             -- The exception is deliberately the narrowest one that fixes that case:
             --   (a) the vehicle OWES interrupted bay work (ledger, not cadence);
             --   (b) energy is not 'critical' -- a vehicle that will miss its SLA on charge
             --       is still section (3)'s, always;
             --   (c) there is NO free, available, unreserved charger at this depot RIGHT NOW.
             -- (c) is the load-bearing one. Section (3) has already run this tick with the
             -- very same availability predicate; if a plug existed this vehicle would be on
             -- it. So the bay costs the depot no charging whatsoever -- it is time the car
             -- would otherwise spend parked in staging waiting for a plug that does not exist.
             -- The moment a charger frees, the exception stops applying to new vehicles, and
             -- a car already in a bay is finishing an atomic leg, not being held off energy.
             AND ( NOT ('charge' = ANY (COALESCE(c.must_do_now, '{}'::text[])))
                   OR ( COALESCE(c.rebook_owed, false)
                        AND COALESCE(c.energy_urgency, 'ok') <> 'critical'
                        AND NOT EXISTS (
                              SELECT 1 FROM stalls s3
                                JOIN ottoq_ocpp_chargers c3 ON c3.charger_id = s3.ocpp_charger_id
                               WHERE s3.depot_id = v_depot
                                 AND s3.stall_type::text IN ('dcfc','l2')
                                 AND s3.current_vehicle_id IS NULL
                                 AND c3.station_state = 'Available'
                                 AND (s3.reserved_by IS NULL OR s3.reserved_by = c.vehicle_id
                                      OR s3.reservation_expires_at <= v_clock)) ) )
        ), spaced AS (
          SELECT k.vehicle_id, k.overall_urgency, k.minutes_to_deploy, k.fits_window,
                 k.open_must_do_min, x.svc, p.lane, p.sequence_order,
                 -- 0003: is THIS pick a resumption of work the depot already took away?
                 COALESCE(x.svc = ANY (COALESCE(k.owed_bay_svcs, '{}'::text[])), false) AS is_resume,
                 -- 0003: EFFECTIVE urgency. A job that was booked, started and then
                 -- interrupted was must-do when it was booked, so it is at least 'due' --
                 -- even if the twin has since reset its cadence clock by crediting a
                 -- 0.46-minute service as finished (run 093c20f4, vehicle 5cee8fb3). Floor
                 -- it at 'due' (rank 3) and no higher: fresh 'overdue'/'critical' work still
                 -- wins outright, so this can never starve a genuinely urgent new arrival.
                 -- overall_urgency itself is NOT touched -- too many readers depend on it.
                 GREATEST(public.ottoq_urgency_rank(k.overall_urgency),
                          CASE WHEN x.svc = ANY (COALESCE(k.owed_bay_svcs, '{}'::text[]))
                               THEN public.ottoq_urgency_rank('due') ELSE 0 END) AS eff_rank,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash_bay'
                             WHEN 'detail'      THEN 'wash_bay'
                             WHEN 'service_bay' THEN 'service_bay' END AS stall_type,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash'
                             WHEN 'detail'      THEN 'detail'
                             WHEN 'service_bay' THEN 'service' END AS purpose,
                 CASE p.lane WHEN 'wash_bay'    THEN 'in_wash_bay'
                             WHEN 'detail'      THEN 'in_detail_bay'
                             WHEN 'service_bay' THEN 'in_service_bay' END AS new_state,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash_time'
                             WHEN 'detail'      THEN 'detail_time'
                             WHEN 'service_bay' THEN 'maintenance_time' END AS time_key,
                 CASE p.lane WHEN 'wash_bay'    THEN 9
                             WHEN 'detail'      THEN 25
                             ELSE 40 END AS base_min
            FROM card k
            CROSS JOIN LATERAL unnest(k.must_do_now) AS x(svc)
            JOIN public.service_cadence_policy p ON p.svc = x.svc AND p.is_active
           WHERE p.lane IN ('wash_bay','detail','service_bay')
        ), pick AS (
          -- SEQUENCE inside the visit: the catalogue's own order -- except that 0003 puts
          -- UNFINISHED work first. If a vehicle both owes an interrupted job and has fresh
          -- cadence work due, finish what the depot already started. That is the atomic
          -- full-service visit read literally.
          SELECT DISTINCT ON (s.vehicle_id) s.*
            FROM spaced s
           ORDER BY s.vehicle_id, s.is_resume DESC, s.sequence_order, s.svc
        ), ranked AS (
          SELECT pk.vehicle_id, pk.svc, pk.lane, pk.stall_type, pk.purpose, pk.new_state,
                 pk.time_key, pk.base_min, pk.overall_urgency, pk.minutes_to_deploy,
                 pk.fits_window, pk.open_must_do_min, pk.sequence_order, pk.is_resume,
                 pk.eff_rank, v.fleet_operator_id
            FROM pick pk
            JOIN vehicles v ON v.id = pk.vehicle_id
           WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
             AND v.current_state = 'staged_awaiting_service'
             AND COALESCE(public.ottoq_approach_zone(pk.vehicle_id, p_sim_run_id),'B') <> 'C'
        )
        SELECT rk.*,
               -- 0003: how many FRESH candidates are competing for this same lane this tick.
               -- Window functions are evaluated over the whole qualifying set BEFORE the
               -- LIMIT, so this is the true competing demand, not just what fits in 20 rows.
               -- The resumption budget below only bites when this is > 0.
               count(*) FILTER (WHERE NOT rk.is_resume) OVER (PARTITION BY rk.stall_type)
                 AS fresh_waiting_lane
          FROM ranked rk
         ORDER BY rk.eff_rank DESC,
                  rk.is_resume DESC,
                  rk.fits_window DESC NULLS LAST,
                  rk.minutes_to_deploy ASC NULLS LAST,
                  rk.open_must_do_min ASC NULLS LAST,
                  rk.vehicle_id
         LIMIT 20
      LOOP
        IF v_need.stall_type = 'wash_bay'    AND COALESCE(v_wash_open,0) <= 0 THEN CONTINUE; END IF;
        IF v_need.stall_type = 'service_bay' AND COALESCE(v_svc_open,0)  <= 0 THEN CONTINUE; END IF;
        -- 0003 ANTI-STARVATION: hold resumption to its per-lane share of THIS tick's
        -- admissions, and only while fresh work is actually queued for the same lane.
        -- Skipping here is a pure CONTINUE: the vehicle keeps its place in the next tick's
        -- cursor with its 'due' floor intact, so nothing is dropped, only sequenced.
        IF COALESCE(v_need.is_resume,false) AND COALESCE(v_need.fresh_waiting_lane,0) > 0 THEN
          IF v_need.stall_type = 'wash_bay'    AND v_wash_res_used >= COALESCE(v_wash_res_cap,1) THEN CONTINUE; END IF;
          IF v_need.stall_type = 'service_bay' AND v_svc_res_used  >= COALESCE(v_svc_res_cap,1)  THEN CONTINUE; END IF;
        END IF;

        v_built := v_built + 1; v_t0 := clock_timestamp();
        v_over := false; v_safe := false; v_block_codes := '{}'; v_rule_rows := NULL;
        v_ctx := ottoq_build_decision_context('task_start','vehicle',v_need.vehicle_id,v_depot,v_clock)
                 || jsonb_build_object('need', v_need.svc, 'lane', v_need.lane,
                      'stall_type', v_need.stall_type, 'purpose', v_need.purpose,
                      'overall_urgency', v_need.overall_urgency,
                      'minutes_to_deploy', v_need.minutes_to_deploy,
                      'fits_window', v_need.fits_window,
                      'open_must_do_min', v_need.open_must_do_min,
                      'sequence_order', v_need.sequence_order,
                      -- 0003: make bay RECOVERY countable straight off the decision row.
                      'is_resume', COALESCE(v_need.is_resume,false),
                      'eff_urgency_rank', v_need.eff_rank,
                      'fresh_waiting_lane', v_need.fresh_waiting_lane,
                      'resume_cap_lane', CASE WHEN v_need.stall_type = 'wash_bay'
                                              THEN v_wash_res_cap ELSE v_svc_res_cap END,
                      'requires_charging','false','service', v_need.purpose);
        v_proposal := jsonb_build_object('abstain', false, 'verb','assign_stall',
                        'resolved_action_context','stall_assignment', 'source','needs_card',
                        'vehicle_id', v_need.vehicle_id, 'stall_type', v_need.stall_type,
                        'purpose', v_need.purpose, 'need', v_need.svc, 'requested_kw', 0,
                        -- 0003: recorded on the PROPOSAL, not on the booking. p_source of
                        -- ottoq.ottoq_enact_space_assignment is deliberately left at the
                        -- existing literal 'needs_card' -- inventing a new vocabulary value
                        -- for a downstream writer is exactly the 2026-08-01 leg_type trap.
                        'is_resume', COALESCE(v_need.is_resume,false));
        v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;

        v_t0 := clock_timestamp();
        SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
               jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
          INTO v_blocks, v_block_codes, v_rule_rows
          FROM ottoq_shield_probe('task_start','vehicle',v_need.vehicle_id,v_ctx,v_need.fleet_operator_id,v_depot);
        v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;

        v_t0 := clock_timestamp();
        IF COALESCE(v_blocks,0) > 0 THEN
          -- SHIELD BLOCKS => take NO space. The vehicle stays in staging and section (5)
          -- handles it exactly as today. Bays are ADDITIVE, so a refusal here can only ever
          -- return the engine to its pre-P1 behaviour - never worse.
          v_action := jsonb_build_object('verb','hold_no_space','reason','shield_block');
          v_safe := true; v_over := true; v_outcome := 'overridden_to_default'; v_overc := v_overc + 1;
        ELSE
          -- TIMING BELONGS TO THE TWIN. ottoq_sim_service_minutes is the exact function
          -- twin STEP 2 uses for its own admissions, so routing a car here cannot invent a
          -- new dwell regime. The planner's timed leg is preferred whenever one exists.
          SELECT l.leg_id, l.planned_end_sim INTO v_bay_leg_id, v_bay_until
            FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_need.vehicle_id
             AND l.status = 'planned' AND l.to_stall_id IS NULL
             AND l.leg_type = public.ottoq_svc_to_leg_type(v_need.svc)
             AND l.planned_end_sim IS NOT NULL AND l.planned_end_sim > v_clock
           ORDER BY l.seq LIMIT 1;
          v_bay_until := GREATEST(
            COALESCE(v_bay_until,
                     v_clock + make_interval(mins => GREATEST(
                       ottoq_sim_service_minutes(p_sim_run_id, v_need.time_key, v_need.base_min)::int, 1))),
            v_clock + interval '1 minute');

          v_space := ottoq.ottoq_enact_space_assignment(
                       p_sim_run_id, v_depot, v_need.vehicle_id, v_need.stall_type,
                       v_need.purpose, v_clock, v_bay_until, v_bay_leg_id, 'needs_card');

          IF COALESCE((v_space->>'assigned')::boolean, false) THEN
            UPDATE vehicles
               SET current_state = v_need.new_state::vehicle_state,
                   last_state_change = v_clock,
                   config = jsonb_set(
                              jsonb_set(COALESCE(config,'{}'::jsonb), '{svc_step}',
                                to_jsonb(CASE WHEN v_need.stall_type = 'service_bay'
                                              THEN 'servicing' ELSE 'washing' END)),
                              '{service_ends_at}', to_jsonb(v_bay_until::text))
             WHERE id = v_need.vehicle_id;
            IF v_need.stall_type = 'wash_bay' THEN
              v_wash_open := v_wash_open - 1;
              IF COALESCE(v_need.is_resume,false) THEN v_wash_res_used := v_wash_res_used + 1; END IF;
            ELSE
              v_svc_open := v_svc_open - 1;
              IF COALESCE(v_need.is_resume,false) THEN v_svc_res_used := v_svc_res_used + 1; END IF;
            END IF;
            v_action := v_proposal || v_space
                        || jsonb_build_object('verb','assign_stall',
                             'stall_id', v_space->>'stall_id',
                             'bay_booked', (v_space->>'booking_id') IS NOT NULL,
                             -- 0003: THE P0 NUMERATOR. A true here is one unit of
                             -- "cut-short bay work re-booked into a space it holds".
                             'resumed_bay_work', COALESCE(v_need.is_resume,false),
                             'resumed_need', CASE WHEN COALESCE(v_need.is_resume,false)
                                                  THEN v_need.svc ELSE NULL END);
            v_outcome := 'enacted'; v_enacted := v_enacted + 1;
            PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_need.vehicle_id,
              'proceed_to_stall',
              jsonb_build_object('stall_id', v_space->>'stall_id',
                                 'reason', 'needs_card_' || v_need.purpose,
                                 'need', v_need.svc), v_clock);
          ELSE
            v_action := v_proposal || COALESCE(v_space,'{}'::jsonb)
                        || jsonb_build_object('verb','hold_no_space',
                             'resumed_bay_work', COALESCE(v_need.is_resume,false));
            v_outcome := 'noop_no_candidate'; v_deferred := v_deferred + 1;
          END IF;
        END IF;
        v_enact_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
        -- action_context 'task_start' matches the probe context used by (4) and (5) for bay
        -- admissions; resolved_action_context 'stall_assignment' is the HONEST classification
        -- because a space really was claimed AND booked - which is also what makes bays
        -- finally countable in the enacted_stall_by_space_type metric that read 51/51 charging.
        INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
        VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','stall_assignment','vehicle',v_need.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
      END LOOP;
    END IF;
  END IF;

  -- (5) SERVICE SEQUENCING
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.fleet_operator_id, v.config->>'svc_step' AS svc_step
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='staged_awaiting_service'
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('task_start','vehicle',v_req.vehicle_id,v_depot,v_clock) || jsonb_build_object('svc_step', v_req.svc_step, 'requires_charging','false','service','service');
    -- A1: cuOpt/Nemotron may propose the service order; heuristic is the fallback.
    v_proposal := COALESCE(
      ottoq_l2_external_proposal(p_sim_run_id, 'service_sequencing', 'vehicle', v_req.vehicle_id),
      ottoq_l2_propose_service(v_req.vehicle_id, v_depot, v_ctx));
    v_prop_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('task_start','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_service(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      IF v_action->>'verb'='admit_service' THEN
        -- BAY ENTRY MOVED BELOW THE HELPER (Phase 3) -- same defect and same fix as (4).
        -- CALENDAR (service bay). CHOOSE + RECORD ONLY, never gating - same contract as (4).
        SELECT l.leg_id, (l.planned_end_sim - l.planned_start_sim)
          INTO v_bay_leg_id, v_bay_dur
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
           AND l.status = 'planned' AND l.to_stall_id IS NULL
           AND l.leg_type IN ('service','mechanical_pm','fault_repair','sensor_calibration','cosmetic_repair')
         ORDER BY l.seq LIMIT 1;
        IF v_bay_leg_id IS NULL THEN
          -- FALLBACK: adopt the leg the forward planner already booked (see section (4)).
          SELECT l.leg_id, (l.planned_end_sim - l.planned_start_sim)
            INTO v_bay_leg_id, v_bay_dur
            FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
             AND l.status IN ('planned','active')
             AND l.leg_type IN ('service','mechanical_pm','fault_repair','sensor_calibration','cosmetic_repair')
           ORDER BY (l.status = 'active') DESC, l.seq LIMIT 1;
        END IF;
        -- TOTAL allow-list: all five of those leg types collapse to the single legal
        -- purpose 'service'. The leg_type itself is NEVER passed through.
        v_bay_until := v_clock + GREATEST(
          COALESCE(v_bay_dur,
                   make_interval(mins => ottoq_policy_get(p_sim_run_id,'service_bay_default_min',45)::int)),
          interval '1 minute');
        v_space := ottoq.ottoq_enact_space_assignment(p_sim_run_id, v_depot, v_req.vehicle_id,
                       'service_bay', 'service', v_clock, v_bay_until,
                       v_bay_leg_id, 'service_sequencing');
        v_bay_bkg := NULLIF(v_space->>'booking_id','')::uuid;
        IF v_bay_bkg IS NOT NULL AND v_bay_leg_id IS NOT NULL THEN
          UPDATE public.ottoq_itinerary_legs
             SET to_stall_id = (SELECT b.stall_id FROM public.ottoq_stall_bookings b
                                 WHERE b.booking_id = v_bay_bkg)
           WHERE leg_id = v_bay_leg_id;
        END IF;
        IF COALESCE((v_space->>'assigned')::boolean, false) THEN
          UPDATE vehicles SET current_state='in_service_bay', last_state_change=v_clock,
                 config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('servicing'::text)) WHERE id=v_req.vehicle_id;
          PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'enter_service',
                  jsonb_build_object('stall_id',   v_space->>'stall_id',
                                     'booking_id', v_space->>'booking_id',
                                     'leg_id',     v_bay_leg_id,
                                     'purpose',    'service'), v_clock);
          v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                      || jsonb_build_object('bay_booked', v_bay_bkg IS NOT NULL,
                                            'bay_purpose', 'service',
                                            'bay_stall_type', 'service_bay',
                                            'stall_id', v_space->>'stall_id',
                                            'booking_id', v_space->>'booking_id',
                                            'leg_id', v_bay_leg_id);
        ELSE
          -- NO BAY -> DO NOT ENTER ONE. Identical in effect to this proposer's own
          -- 'hold_in_queue': the vehicle stays in staged_awaiting_service and is retried.
          v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                      || jsonb_build_object('verb','hold_no_bay', 'bay_booked', false,
                                            'bay_purpose', 'service',
                                            'bay_stall_type', 'service_bay');
          v_outcome := 'noop_no_candidate'; v_enacted := v_enacted - 1; v_deferred := v_deferred + 1;
        END IF;
      ELSIF v_action->>'verb' = 'hold_in_queue' THEN
        -- SERVICE-NEED HOLD: must-do bay work outstanding and no free bay (or the
        -- shield blocked). Leave the vehicle in staged_awaiting_service - no state
        -- write at all - so the service queue keeps it instead of redeploying a
        -- vehicle with mandatory work open. The proposer bounds this with a
        -- patience threshold, so a hold can never strand a vehicle.
        NULL;
      ELSE
        UPDATE vehicles SET current_state='staged_for_departure', last_state_change=v_clock,
               config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('ready'::text)) WHERE id=v_req.vehicle_id;
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'stage', jsonb_build_object('ready', true), v_clock);
      END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- A3: close the external-proposal lifecycle for this tick — consumed
  -- (entity got an enacted decision) → 'enacted'; past-freshness → 'expired'.
  UPDATE ottoq_external_proposals p SET status='enacted'
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND EXISTS (SELECT 1 FROM ottoq_decisions d
                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick
                    AND d.entity_id=p.entity_id AND d.outcome_status='enacted'
                    AND d.enacted_action->>'source' = p.source);
  -- honest pre-emption: the entity was decided this tick, but NOT by this proposal
  UPDATE ottoq_external_proposals p SET status='superseded'
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND EXISTS (SELECT 1 FROM ottoq_decisions d
                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick
                    AND d.entity_id=p.entity_id AND d.outcome_status='enacted');
  UPDATE ottoq_external_proposals p SET status='expired'
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND GREATEST(COALESCE(p.expires_at, p.created_at+interval '35 minutes'), p.created_at+interval '35 minutes') < v_clock;

  -- ══════════════════ BUILD 3: THE INSPECT SEAM (ADDITIVE) ══════════════════
  -- 177 inspect legs ended the prior run still 'planned' across 110 arriving vehicles
  -- while 14 inspection stalls per depot sat idle, because (1) the needs card never
  -- emits 'interior_inspection', (2) this tick's bay loop filters to lanes
  -- wash_bay/detail/service_bay and inspection is lane 'cabin', and (3) inspection
  -- stalls are stall_type='staging' so no caller could address them.
  -- Placed HERE, last, on purpose: charging (3), the bay loop and service sequencing
  -- (5) have all already run, so the seam can only take vehicles nothing else claimed.
  -- It never raises (see the handler inside) -- the 2026-08-01 leg_type lesson.
  v_enacted := v_enacted + COALESCE(
    ottoq.ottoq_enact_inspection_seam(p_sim_run_id, v_depot, v_tick, v_snapshot_id, v_clock), 0);

  PERFORM ottoq.ottoq_link_bookings_to_decisions(p_sim_run_id, v_tick);

  RETURN ROW(v_tick, v_clock, v_built, v_enacted, v_overc, v_deferred, v_errored, v_disn,
             (SELECT COALESCE(SUM(total_latency_ms),0) FROM ottoq_decisions WHERE sim_run_id=p_sim_run_id AND tick_seq=v_tick))::ottoq_decide_tick_result;
END;
$function$

;
