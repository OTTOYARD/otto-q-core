-- =====================================================================
-- 0156  A point that fits beats a point that starves
--       ENGINE (OTTO-Q's judgment), not the twin's wiring.
-- =====================================================================
-- This is the second category in Chase's Sep 2 instruction: not "the sim
-- is miswired" but "OTTO-Q is missing something crucial to future
-- functionality." It is a defect in the orchestration itself.
--
-- WHAT THE ENGINE DID
-- public.ottoq_l2_propose_stall_assignment picks the single best point
-- for a vehicle, ordered by (your reserved point, then a point of your
-- wanted type, then nearest, then id) LIMIT 1. It has no notion of how
-- much power the site has left. So on a power-constrained site it would
-- propose the fast point, Layer 1's EN.001.grid_capacity_ceiling would
-- refuse it (enforcement 'block' -> outcome overridden_to_default ->
-- hold_in_queue), and the vehicle was simply held. Next tick, the same
-- proposal, the same refusal. There is no re-proposal path, so a vehicle
-- whose fast-charge draw can NEVER fit under the ceiling never charges,
-- even with a slower point standing empty that would fit easily.
--
-- MEASURED on the grid fixture 'grid-starve' (4 assets, 2 DCFC, 2 L2,
-- seed 424242, 12 ticks, service_max_kw = dcfc_max_concurrent_kw = 150,
-- so EN.001's engineering ceiling is 135 kW). Both arms of a pair, rolled
-- back, 0155 already applied in both:
--
--                        before            after
--   AV-01 end SoC         73%              100%
--   AV-02 end SoC         60%               96%
--   AV-03 end SoC        100%              100%
--   AV-04 end SoC         89%               90%
--   EN.001 blocks          17                 0
--   charge assignments      3                 4  (every asset served)
--   peak site load     51.8 kW           66.2 kW  (ceiling 135 kW)
--   pair verdict       passed            passed
--
-- Two assets sat unchargeable for the whole run while two 19.2 kW points
-- stood free under a 135 kW ceiling with 51.8 kW in use. The site was
-- stranding capacity and the fleet was losing availability - the two
-- things this kernel exists to prevent (CLAUDE.md 2.9: the KPI is
-- asset_hours_available_per_day).
--
-- THE FIX
-- The proposer now knows the site's remaining headroom and prefers a
-- point whose draw FITS it. Headroom is computed by exactly the
-- arithmetic the rule that judges the proposal uses - LEAST(service
-- contract, engineering cap with safety margin) minus current measured
-- demand - so the proposer stops offering what the shield is bound to
-- refuse. The caller may override via p_context->>'headroom_kw' (for
-- mid-tick accumulation; see the open item below).
--
-- This is a STRICT REFINEMENT, deliberately:
--   * headroom NULL (no caps declared) -> every candidate "fits" ->
--     ordering is byte-identical to before.
--   * headroom ample (the flagship: 1620 kW) -> every candidate fits ->
--     ordering is byte-identical to before.
--   * headroom negative (already over) -> nothing fits -> ordering is
--     byte-identical to before, and the gate still refuses.
-- Only when SOME candidate fits and some does not does the order change,
-- which is precisely the starvation case. Verified on the unconstrained
-- fixture: the cap-600 run is unchanged by this migration.
--
-- 'fits' sorts ahead of the reserved-point preference on purpose: a
-- reservation you are physically unable to use is not a reservation, and
-- in every non-scarce case the two orderings coincide, so the
-- reservation contract is preserved wherever it can be honoured.
--
-- WHAT THIS IS NOT. It is not a fallback bolted onto the refusal path,
-- and it does not weaken any rule. The 0132 site-cap gate and every
-- Layer 1 rule still evaluate the proposal and can still refuse it -
-- assignment plus verification, both sides intact. The proposer merely
-- stops proposing what cannot be enacted. Agents propose, the solver
-- disposes; this makes the proposal worth disposing of.
--
-- AUDITABILITY. The rationale now carries headroom_kw, fits_headroom and
-- power_downgrade, so every downgrade is visible in ottoq_decisions
-- rather than inferred. Observed at tick 3 above: AV-04 wanted dcfc,
-- headroom 68.8 kW, dcfc would have drawn 137.5 kW, took L2-01 at
-- 19.2 kW, power_downgrade = true.
--
-- OPEN ITEM (not fixed here, deliberately). Headroom is read from the
-- measured site demand at the sim clock, so within one tick it does not
-- yet see assignments enacted earlier in the SAME tick. The 0132 gate
-- does track that accumulation and still refuses, so this is a missed
-- improvement, never an over-commit. Closing it means passing
-- v_ev_committed_kw into the decision frame as headroom_kw; that touches
-- ottoq_decide_tick and is left to its own migration with its own
-- certification round.
--
-- forces_recert = TRUE.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ottoq_l2_propose_stall_assignment(p_vehicle_id uuid, p_depot_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc   numeric := COALESCE((p_context->>'current_soc')::numeric, 50);
  v_now   timestamptz := COALESCE(NULLIF(p_context->>'now_ts','')::timestamptz, now());
  v_inlet text;
  v_inlet_kw numeric;
  v_want_type text;
  v_urgency text;
  v_stall RECORD;
  v_eff_kw numeric;
  v_headroom_kw numeric;
BEGIN
  SELECT vn.urgency INTO v_urgency FROM ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = 'running' AND r0.depot_id = p_depot_id ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
   ORDER BY vn.created_at DESC LIMIT 1;
  v_want_type := CASE WHEN v_soc < 45 OR v_urgency = 'immediate_dispatch' THEN 'dcfc' ELSE 'l2' END;

  SELECT inlet_type, inlet_max_kw INTO v_inlet, v_inlet_kw FROM vehicles WHERE id = p_vehicle_id;

  /* 0156: HOW MUCH POWER IS LEFT, BY THE JUDGE'S OWN ARITHMETIC.
     EN.001.grid_capacity_ceiling refuses when current demand + this
     request exceeds LEAST(service_max_kw, dcfc_max_concurrent_kw x
     (1 - safety_margin)). Computing headroom the same way is what stops
     this function proposing what that rule is bound to block. NULL (no
     declared cap) means no constraint, and every candidate then fits,
     which is exactly the pre-0156 ordering. */
  SELECT LEAST(d.service_max_kw,
               d.dcfc_max_concurrent_kw * (1 - COALESCE(d.dcfc_safety_margin_pct, 10.0)/100.0))
         - COALESCE(public.ottoq_depot_current_demand_kw(p_depot_id, v_now), 0)
    INTO v_headroom_kw
    FROM depots d WHERE d.id = p_depot_id;
  v_headroom_kw := COALESCE(NULLIF(p_context->>'headroom_kw','')::numeric, v_headroom_kw);

  WITH cand AS (
    SELECT s.id, s.stall_type, s.connector_max_kw, s.relative_y, s.reserved_by,
           (LEAST(COALESCE(s.connector_max_kw,50), COALESCE(v_inlet_kw,250))
            * CASE WHEN COALESCE(s.connector_max_kw,50) <= 50 THEN 1.0
                   WHEN v_soc < 55 THEN 0.85
                   WHEN v_soc < 75 THEN 0.55
                   ELSE 0.30 END) AS eff_kw
      FROM stalls s
      JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id
       AND s.stall_type IN ('dcfc','l2')
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= v_now)
       AND c.station_state = 'Available'
       AND c.last_heartbeat_at >= v_now - INTERVAL '90 seconds'
       AND (
            v_inlet IS NULL
         OR s.connector_type = v_inlet
         OR (s.connector_type = 'Multi' AND v_inlet = ANY(COALESCE(s.supported_inlet_types, ARRAY[]::text[])))
         OR (s.connector_type = 'NACS'  AND v_inlet IN ('NACS','Tesla_Proprietary'))
       )
  )
  SELECT id, stall_type, connector_max_kw, eff_kw,
         (v_headroom_kw IS NULL OR eff_kw <= v_headroom_kw) AS fits
    INTO v_stall
    FROM cand
   ORDER BY (v_headroom_kw IS NULL OR eff_kw <= v_headroom_kw) DESC,   -- 0156: a point you can actually use
            COALESCE(reserved_by = p_vehicle_id, false) DESC,          -- N3: your pre-reserved stall
            (stall_type::text = v_want_type) DESC,
            relative_y ASC NULLS LAST,
            id
   LIMIT 1;

  IF v_stall.id IS NULL THEN
    RETURN jsonb_build_object('abstain', true, 'reason', 'no_compatible_available_stall');
  END IF;

  v_eff_kw := v_stall.eff_kw;   -- 0156: scored once, in the candidate set

  RETURN jsonb_build_object(
    'abstain', false,
    'resolved_action_context', 'stall_assignment',
    'verb', 'assign_stall',
    'vehicle_id', p_vehicle_id,
    'stall_id', v_stall.id,
    'stall_type', v_stall.stall_type,
    'requested_kw', ROUND(v_eff_kw::numeric, 1),
    'rationale', jsonb_build_object('soc', v_soc, 'wanted_type', v_want_type, 'inlet', v_inlet,
      'urgency', v_urgency, 'eff_draw_kw', ROUND(v_eff_kw::numeric, 1),
      'headroom_kw', ROUND(v_headroom_kw::numeric, 1), 'fits_headroom', v_stall.fits,
      'power_downgrade', (v_stall.stall_type::text <> v_want_type AND v_stall.fits)));
END;
$function$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('a_point_that_fits_beats_a_point_that_starves', true,
        'Engine: the stall proposer reads the site''s remaining power headroom by EN.001''s own arithmetic and prefers a point whose draw fits it, so an asset is no longer held indefinitely against a fast point it can never be granted while a slower point stands free. Strict refinement - identical ordering whenever headroom is absent, ample or already exceeded.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
