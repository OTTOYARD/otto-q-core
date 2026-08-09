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
