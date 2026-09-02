-- =====================================================================
-- 0159  Wait, or take what fits, is a policy - not a constant
--       ENGINE. forces_recert = TRUE.
--       WRITTEN AND TESTED; APPLY ONLY AFTER ROUND 8 CLOSES.
-- =====================================================================
-- Chase, 2:3x PM CT Sep 2: "Make the wait-vs-slower-charger choice
-- configurable. Our Agentic or AI layer should optimize for this as
-- well. Knowing when it's better to send a vehicle to wait vs just slow
-- charge. That's a perfect example of orchestration that's needed and
-- should be decided ultimately when a vehicle communicates a depot visit
-- need. OTTO-Q sees all variables and sends queue reservations
-- accordingly."
--
-- 0156 made one choice for everybody: when the fast point will not fit
-- the site's remaining power, take a slower point that does. That beats
-- starving, which is what it replaced, but it is a judgement and it was
-- hard-coded. This migration turns it into a named policy with three
-- modes, resolved through the existing ottoq_policy_get tiering
-- (run -> depot -> global -> literal default), so it is settable per run,
-- per depot, or globally, and so an A/B can pin it per arm exactly the
-- way 0152 pins the proposer keys.
--
--   charge_downgrade_policy
--     0  wait_for_wanted   never downgrade; hold for the wanted type.
--                          This is the pre-0156 behaviour, kept as a
--                          named baseline so the comparison has a
--                          control arm rather than a memory.
--     1  fit_now           always prefer a point that fits the headroom.
--                          The 0156 behaviour. DEFAULT.
--     2  deadline_aware    downgrade only when the slower point can
--                          still make dispatch_due_at; otherwise hold
--                          for the fast one, because holding is the only
--                          way left to hit the deadline.
--
-- Mode 2 is the first decision in this engine that reads the asset's
-- stated deadline. It is deliberately naive and swappable, in the
-- spirit of CLAUDE.md 2.7:
--     hours_needed    = (battery_kwh x (target_soc - soc)/100) / fitting_kw
--     hours_available = dispatch_due_at - now
--     hold  iff  hours_needed > hours_available
--           AND  a point of the wanted type could ever fit the site
--                ceiling at all
-- The second clause is the anti-starvation guard and it is not optional:
-- without it, mode 2 reintroduces exactly the 0156 defect whenever the
-- wanted point's draw exceeds the site ceiling, because it would hold
-- forever for something it can never be granted. With no dispatch_due_at
-- (about half of visits carry none) mode 2 falls back to fit_now, so the
-- absence of a deadline can never cause a stranding.
--
-- WHERE THIS REALLY BELONGS, recorded so the knob is not mistaken for
-- the answer: this is a per-tick, per-vehicle local choice. Chase is
-- right that the decision wants to be made when the asset announces its
-- visit need, with the whole site in view - which is the Recall Decision
-- (CLAUDE.md 2.7, phase C9), whose output already includes
-- target_ready_time and a service bundle. Mode 2 is the deterministic
-- floor that C9 and any later proposer must beat, and the measure they
-- get beaten on is 0158's ottoq_kpi_dispatch_readiness. Flagged, not
-- built: this migration does not attempt the optimiser.
--
-- DEFAULT IS BEHAVIOUR-PRESERVING, PROVEN BY CONTENT HASH. With the
-- catalog default of 1 and no policy rows set, the grid-mtr pair
-- reproduces the post-0156 canon exactly:
--     h_dec  8123dd87f6d0ee4dae9d0a181408a381
--     h_bkg  c229e837eec2bd596563a002100ca7c1
--     h_nrg  86e595ad05bf77b7c008a0f5b7c1ae20
-- and 13 of 13 grid assertions pass. Classified forces_recert = TRUE
-- anyway, because the decide path's proposer changed and the lineage
-- rule errs toward re-certifying. That yields a FALSIFIABLE PREDICTION
-- worth more than the classification: round 9 must reproduce round 8's
-- canons exactly. If it does not, "the default preserves behaviour" is
-- false and this migration is the carrier.
--
-- SEQUENCING: do not apply while a certification round is in flight.
-- Round 8 runs 2:35-4:47 PM CT Sep 2 (plus replacement pair r8_a1b at
-- 4:50 PM CT). Apply after it closes; round 9 certifies.
-- =====================================================================

INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects)
VALUES ('charge_downgrade_policy',
        'What to do when the wanted charge point will not fit the site power headroom. 0 = wait for the wanted type (pre-0156). 1 = take a point that fits (0156, default). 2 = take a point that fits only if it still makes dispatch_due_at, else wait.',
        1, 0, 2, 'ottoq_l2_propose_stall_assignment')
ON CONFLICT (param_key) DO UPDATE
  SET description=EXCLUDED.description, default_value=EXCLUDED.default_value,
      min_value=EXCLUDED.min_value, max_value=EXCLUDED.max_value, affects=EXCLUDED.affects;

CREATE OR REPLACE FUNCTION public.ottoq_l2_propose_stall_assignment(p_vehicle_id uuid, p_depot_id uuid, p_context jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_soc   numeric := COALESCE((p_context->>'current_soc')::numeric, 50);
  v_now   timestamptz := COALESCE(NULLIF(p_context->>'now_ts','')::timestamptz, now());
  v_inlet text; v_inlet_kw numeric; v_want_type text; v_urgency text;
  v_stall RECORD; v_eff_kw numeric; v_headroom_kw numeric;
  v_run uuid; v_mode int; v_prefer_fit boolean;
  v_due timestamptz; v_target_soc numeric; v_batt_kwh numeric;
  v_fit_kw numeric; v_hours_needed numeric; v_hours_available numeric;
  v_want_kw numeric; v_ceiling numeric; v_wait_reason text := NULL;
BEGIN
  SELECT r0.sim_run_id INTO v_run FROM public.ottoq_sim_runs r0
   WHERE r0.status='running' AND r0.depot_id=p_depot_id ORDER BY r0.started_at DESC LIMIT 1;

  /* 0159: the visit need is where the asset states its deadline and its
     target, so read all three here rather than only urgency. */
  SELECT vn.urgency, vn.dispatch_due_at, vn.target_soc INTO v_urgency, v_due, v_target_soc
    FROM ottoq_visit_needs vn
   WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress')
     AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
       = COALESCE(v_run,'00000000-0000-0000-0000-000000000000'::uuid)   /* 0124 */
   ORDER BY vn.created_at DESC LIMIT 1;
  v_want_type := CASE WHEN v_soc < 45 OR v_urgency = 'immediate_dispatch' THEN 'dcfc' ELSE 'l2' END;

  SELECT inlet_type, inlet_max_kw, battery_capacity_kwh INTO v_inlet, v_inlet_kw, v_batt_kwh
    FROM vehicles WHERE id = p_vehicle_id;

  /* 0156: headroom by EN.001's own arithmetic. v_ceiling is the absolute
     cap, used by mode 2's anti-starvation guard. */
  SELECT LEAST(d.service_max_kw, d.dcfc_max_concurrent_kw * (1 - COALESCE(d.dcfc_safety_margin_pct,10.0)/100.0)),
         LEAST(d.service_max_kw, d.dcfc_max_concurrent_kw * (1 - COALESCE(d.dcfc_safety_margin_pct,10.0)/100.0))
         - COALESCE(public.ottoq_depot_current_demand_kw(p_depot_id, v_now), 0)
    INTO v_ceiling, v_headroom_kw
    FROM depots d WHERE d.id = p_depot_id;
  v_headroom_kw := COALESCE(NULLIF(p_context->>'headroom_kw','')::numeric, v_headroom_kw);

  v_mode := public.ottoq_policy_get(v_run, 'charge_downgrade_policy', 1)::int;
  IF v_mode = 0 THEN
    v_prefer_fit := false; v_wait_reason := 'policy_wait_for_wanted';
  ELSIF v_mode = 2 THEN
    v_prefer_fit := true;
    -- best draw among points that FIT right now
    SELECT max(LEAST(COALESCE(s.connector_max_kw,50), COALESCE(v_inlet_kw,250))
               * CASE WHEN COALESCE(s.connector_max_kw,50) <= 50 THEN 1.0
                      WHEN v_soc < 55 THEN 0.85 WHEN v_soc < 75 THEN 0.55 ELSE 0.30 END)
      INTO v_fit_kw FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id=s.ocpp_charger_id
     WHERE s.depot_id=p_depot_id AND s.stall_type IN ('dcfc','l2') AND s.current_vehicle_id IS NULL
       AND c.station_state='Available'
       AND (v_headroom_kw IS NULL OR (LEAST(COALESCE(s.connector_max_kw,50), COALESCE(v_inlet_kw,250))
               * CASE WHEN COALESCE(s.connector_max_kw,50) <= 50 THEN 1.0
                      WHEN v_soc < 55 THEN 0.85 WHEN v_soc < 75 THEN 0.55 ELSE 0.30 END) <= v_headroom_kw);
    -- best draw the WANTED type could ever offer, for the guard
    SELECT max(LEAST(COALESCE(s.connector_max_kw,50), COALESCE(v_inlet_kw,250))
               * CASE WHEN COALESCE(s.connector_max_kw,50) <= 50 THEN 1.0
                      WHEN v_soc < 55 THEN 0.85 WHEN v_soc < 75 THEN 0.55 ELSE 0.30 END)
      INTO v_want_kw FROM stalls s WHERE s.depot_id=p_depot_id AND s.stall_type::text = v_want_type;
    IF v_due IS NOT NULL AND v_fit_kw IS NOT NULL AND v_fit_kw > 0 AND v_batt_kwh IS NOT NULL THEN
      v_hours_needed := (v_batt_kwh * GREATEST(COALESCE(v_target_soc, public.ottoq_default_target_soc()) - v_soc, 0) / 100.0) / v_fit_kw;
      v_hours_available := EXTRACT(epoch FROM (v_due - v_now)) / 3600.0;
      /* Hold ONLY if the slow point misses the deadline AND the fast point
         is physically grantable on this site. Without the second clause
         mode 2 would hold forever for a point it can never be given -
         precisely the 0156 starvation defect. */
      IF v_hours_needed > v_hours_available
         AND v_want_kw IS NOT NULL AND (v_ceiling IS NULL OR v_want_kw <= v_ceiling) THEN
        v_prefer_fit := false; v_wait_reason := 'slow_point_misses_due_at';
      END IF;
    END IF;
  ELSE
    v_prefer_fit := true;
  END IF;

  WITH cand AS (
    SELECT s.id, s.stall_type, s.connector_max_kw, s.relative_y, s.reserved_by,
           (LEAST(COALESCE(s.connector_max_kw,50), COALESCE(v_inlet_kw,250))
            * CASE WHEN COALESCE(s.connector_max_kw,50) <= 50 THEN 1.0
                   WHEN v_soc < 55 THEN 0.85 WHEN v_soc < 75 THEN 0.55 ELSE 0.30 END) AS eff_kw
      FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type IN ('dcfc','l2') AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = p_vehicle_id OR s.reservation_expires_at <= v_now)
       AND c.station_state = 'Available' AND c.last_heartbeat_at >= v_now - INTERVAL '90 seconds'
       AND (v_inlet IS NULL OR s.connector_type = v_inlet
         OR (s.connector_type = 'Multi' AND v_inlet = ANY(COALESCE(s.supported_inlet_types, ARRAY[]::text[])))
         OR (s.connector_type = 'NACS'  AND v_inlet IN ('NACS','Tesla_Proprietary'))))
  SELECT id, stall_type, connector_max_kw, eff_kw,
         (v_headroom_kw IS NULL OR eff_kw <= v_headroom_kw) AS fits
    INTO v_stall FROM cand
   /* When v_prefer_fit is false the first key is constant false and the
      ordering collapses to the pre-0156 one, exactly. */
   ORDER BY (v_prefer_fit AND (v_headroom_kw IS NULL OR eff_kw <= v_headroom_kw)) DESC,
            COALESCE(reserved_by = p_vehicle_id, false) DESC,
            (stall_type::text = v_want_type) DESC, relative_y ASC NULLS LAST, id
   LIMIT 1;

  IF v_stall.id IS NULL THEN RETURN jsonb_build_object('abstain', true, 'reason', 'no_compatible_available_stall'); END IF;
  v_eff_kw := v_stall.eff_kw;
  RETURN jsonb_build_object('abstain', false, 'resolved_action_context', 'stall_assignment', 'verb', 'assign_stall',
    'vehicle_id', p_vehicle_id, 'stall_id', v_stall.id, 'stall_type', v_stall.stall_type,
    'requested_kw', ROUND(v_eff_kw::numeric, 1),
    'rationale', jsonb_build_object('soc', v_soc, 'wanted_type', v_want_type, 'inlet', v_inlet,
      'urgency', v_urgency, 'eff_draw_kw', ROUND(v_eff_kw::numeric, 1),
      'headroom_kw', ROUND(v_headroom_kw::numeric, 1), 'fits_headroom', v_stall.fits,
      'downgrade_policy', v_mode, 'held_for_wanted', COALESCE(v_wait_reason,'-'),
      'power_downgrade', (v_stall.stall_type::text <> v_want_type AND v_stall.fits AND v_prefer_fit)));
END;
$function$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('wait_or_take_what_fits_is_a_policy_not_a_constant', true,
        'Engine: charge_downgrade_policy (0 wait_for_wanted / 1 fit_now, default / 2 deadline_aware) replaces 0156''s hard-coded choice. Mode 2 is the first decision reading ottoq_visit_needs.dispatch_due_at, with an anti-starvation guard so it never holds for a point the site can never grant. Default 1 reproduces the post-0156 canon byte-for-byte on grid-mtr; classified forcing anyway, which makes round 9 reproducing round 8 a falsifiable prediction.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
