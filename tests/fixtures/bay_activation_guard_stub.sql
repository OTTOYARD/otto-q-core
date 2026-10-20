-- tests/fixtures/bay_activation_guard_stub.sql: the stall triggers a car's move between stalls fires, as live, for
-- tests/test_bay_activation_frees_parking_sql.py (db/migrations/0755). Loaded after tests/fixtures/agent_charge_order_stub.sql
-- and tests/fixtures/bay_activation_stub.sql, whose stalls, vehicles, runs and policy reader it uses. The 0743 fixture leaves
-- these three triggers out, and with them out a car parked in staging is seated by the bay calendar; on live it is not.
-- Read from the live catalog on 2026-10-18 between 2:57 and 3:09 AM CT (the tests assert each md5 of prosrc):
--   public.ottoq_stall_seat_is_exclusive 7ce8d314 (trg_ottoq_stall_seat_is_exclusive: before a stall names a car, every other
--   stall that names it lets it go), public.ottoq_trg_reassignment_guard b45ed802 (trg_reassignment_guard: a stall letting
--   go of a car mid-work asks the in-depot gate, and keeps the car if the gate says no), public.update_timestamp da5ac28a
--   (trg_stalls_updated), the gate itself, public.ottoq_indepot_reassignment_guard 3a4e4a7a, with the grant it writes,
--   public.ottoq_mark_reassign_granted aca59505, and the table it records its decisions in, public.ottoq_ops_approvals.
SET client_min_messages = warning;

-- live: the gate's decision table (columns as live)
CREATE TABLE IF NOT EXISTS public.ottoq_ops_approvals (
  approval_id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY, approval_type text NOT NULL, vehicle_id uuid NOT NULL,
  visit_id uuid, sim_run_id uuid, depot_id uuid, status text NOT NULL DEFAULT 'pending'::text,
  priority text NOT NULL DEFAULT 'normal'::text, payload jsonb, requested_at timestamp with time zone NOT NULL,
  decide_after timestamp with time zone, expires_at timestamp with time zone, decided_at timestamp with time zone,
  decided_by text, created_at timestamp with time zone NOT NULL DEFAULT now());

-- live: the five functions, byte for byte
CREATE OR REPLACE FUNCTION public.ottoq_mark_reassign_granted(p_vehicle_id uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF p_vehicle_id IS NULL THEN RETURN; END IF;
  -- set_config(..., is_local => true) is TRANSACTION-scoped: the grant dies with the
  -- transaction, so it can never authorise a release in some later, unrelated one.
  PERFORM set_config('ottoq.reassign_ok',
                     COALESCE(current_setting('ottoq.reassign_ok', true), '')
                       || p_vehicle_id::text || ',',
                     true);
EXCEPTION WHEN OTHERS THEN
  -- Never let bookkeeping break a decision that has already been made.
  RETURN;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_indepot_reassignment_guard(p_vehicle_id uuid, p_sim_run_id uuid, p_reason text DEFAULT 'optimization'::text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_veh vehicles%ROWTYPE;
  v_approval uuid;
  -- 0002: the SIM clock this depot is actually living in, and the two latencies
  -- that govern how long a gated decision may sit unanswered.
  v_clock_sim timestamptz;
  v_auto_min  numeric;
  v_maxp_min  numeric;
  v_sev text;
  v_mid boolean;
  v_enforce numeric;
  v_pay jsonb;
  v_immob boolean;
  v_req numeric;
  v_defer_class text;
  v_bay boolean;
  v_si boolean;          -- service-incompatible: the SERVICE cannot safely continue in place
  v_si_basis text;
  v_fault_class text;
  -- 0003 (P1a/P1b): the audit object and the sim-domain decision stamp that the three
  -- born-approved fast paths were missing.
  v_dec jsonb;
  v_dec_at timestamptz;
BEGIN
  SELECT * INTO v_veh FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('allowed', false, 'reason', 'vehicle_not_found'); END IF;

  IF v_veh.current_state IN ('deployed','en_route_to_depot','en_route_to_deployment','offline') THEN
    -- 0012: the gate has just SAID YES. Stamp a transaction-local grant so
    -- trg_reassignment_guard cannot re-ask with its own generic reason and
    -- reverse this very decision.
    PERFORM public.ottoq_mark_reassign_granted(p_vehicle_id);
    RETURN jsonb_build_object('allowed', true, 'mode', 'outside_walls');
  END IF;

  v_sev     := lower(COALESCE(p_payload->>'severity',''));
  v_mid     := v_veh.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay','charging_dcfc','charging_l2');
  v_bay     := v_veh.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay');
  v_enforce := COALESCE(ottoq_policy_get(p_sim_run_id, 'indepot_guard_enforce', 1), 1);
  v_pay     := COALESCE(p_payload, '{}'::jsonb)
               || jsonb_build_object('reason', p_reason, 'state', v_veh.current_state::text, 'mid_service', v_mid);

  -- ══════════════ 0002: STAMP THE CLOCK DOMAIN ONTO THE ROW ══════════════
  -- This function stamps requested_at / decide_after / expires_at with now() -- the REAL
  -- wall clock. The other writer of this table (ottoq.ottoq_plan_opportunistic_charges)
  -- stamps the same three columns with the SIM clock. Two writers, two domains, same
  -- columns: any reader that compares them to a sim clock is silently wrong for half the
  -- rows, and that is exactly how 55 approvals became undecidable AND unexpirable.
  --
  -- The real columns are DELIBERATELY LEFT ALONE. Re-interpreting them would rewrite the
  -- meaning of every historical row and of every dashboard that reads them. Instead the
  -- sim-domain triple is added ALONGSIDE, inside the payload, and the row now says which
  -- domain it belongs to. A reader picks the matching domain; nothing has to guess.
  -- (The cleaner long-term shape is real *_sim columns, as ottoq_stall_bookings already
  -- has with booked_at_sim. That is a schema change and belongs in its own migration.)
  SELECT r.sim_clock_current INTO v_clock_sim FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  v_auto_min := GREATEST(COALESCE(ottoq_policy_get(p_sim_run_id,'indepot_reassign_auto_decide_min',8),8), 0);
  v_maxp_min := GREATEST(COALESCE(ottoq_policy_get(p_sim_run_id,'indepot_reassign_max_pending_min',30),30), v_auto_min);
  v_pay := v_pay || CASE
             WHEN v_clock_sim IS NULL
               -- No sim run: production. The real clock IS the domain, so nothing to add.
               THEN jsonb_build_object('clock_domain','real')
             ELSE jsonb_build_object('clock_domain','sim',
                    'requested_at_sim', v_clock_sim,
                    'decide_after_sim', v_clock_sim + (v_auto_min || ' minutes')::interval,
                    'expires_at_sim',   v_clock_sim + (v_maxp_min || ' minutes')::interval)
           END;

  -- ══════════ 0003 (P1a + P1b): THE FAST PATH IS STILL A DECISION ══════════
  -- THE DEFECT. Three branches below insert their approval ALREADY 'approved'. All three
  -- stamped decided_at with now() -- the REAL wall clock -- on rows whose requested_at_sim
  -- is a SIM timestamp, and none of them wrote a payload.decision audit object. Two
  -- consequences, both measured on run 093c20f4:
  --   (a) 2 of 48 gate rows had no audit trail at all, so "who decided this, on what
  --       basis" was answerable for 46 rows and unanswerable for 2.
  --   (b) latency computed as (decided_at - payload.requested_at_sim) subtracted a SIM
  --       timestamp from a REAL one on exactly those 2 rows. That is what produced the
  --       nonsense range "min 0.01 / max 22.18 sim-min"; only the median 8.27 survived.
  --       This is the 8th instance of the sim-vs-real clock-domain bug class here, and
  --       the second one to occur INSIDE a measurement rather than inside a decision.
  --
  -- THE FIX, AND WHAT IT DELIBERATELY DOES NOT DO. These paths stay FAST. A vehicle that
  -- genuinely cannot continue safely does NOT wait 8 sim-minutes for a gate to answer a
  -- question whose answer is already known. Nothing about WHEN they act changes -- only
  -- that they now say, in the sim domain and in the same shape the auto-gate uses, what
  -- was decided and why. latency_min is stamped 0 because it IS 0, honestly.
  --
  -- The real requested_at / decide_after / expires_at columns are still left alone, for
  -- the reason given above: rewriting them would rewrite every historical row.
  v_dec_at := COALESCE(v_clock_sim, now());

  -- ESCAPE HATCH A: policy kill-switch restores the pre-fix auto-allow for all fault traffic.
  IF v_enforce < 1 AND p_reason IN ('resource_fault','vehicle_fault') THEN
    -- 0012: the gate has just SAID YES. Stamp a transaction-local grant so
    -- trg_reassignment_guard cannot re-ask with its own generic reason and
    -- reverse this very decision.
    PERFORM public.ottoq_mark_reassign_granted(p_vehicle_id);
    RETURN jsonb_build_object('allowed', true, 'mode', 'legacy_auto_allow', 'recorded', false);
  END IF;

  -- RESOURCE FAULT: the SPACE broke. The vehicle physically cannot stay, so it still moves --
  -- but it is now RECORDED as a gated decision instead of being silently waved through.
  IF p_reason = 'resource_fault' THEN
    v_dec := jsonb_build_object('decision', jsonb_build_object(
               'verdict',                'approved',
               'reason',                 'zone_c_reopener_resource_fault_space_unusable',
               'decided_at_sim',         v_clock_sim,
               'decided_at_domain',      CASE WHEN v_clock_sim IS NULL THEN 'real' ELSE 'sim' END,
               'latency_min',            0,
               'fast_path',              true,
               'fast_path_basis',        'space_unusable_vehicle_cannot_remain',
               'decider',                'ottoq_indepot_safety_carveout_v1',
               'copilot_seen',           false,
               'copilot_recommendation', 'not_consulted_safety_fast_path',
               'copilot_binding',        false,
               'doctrine',               'nemotron_reviews_ottoq_decides'));
    INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
           requested_at, decide_after, expires_at, priority, status, decided_at, decided_by)
    VALUES ('indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
            v_pay || jsonb_build_object('gate_mode','resource_fault_auto_reroute',
                                        'auto_reason','space_unusable_vehicle_must_move')
                  || v_dec,
            now(), now(), now() + interval '30 minutes', 'high', 'approved', v_dec_at,
            'auto_gate:resource_fault')
    RETURNING approval_id INTO v_approval;
    -- 0012: the gate has just SAID YES. Stamp a transaction-local grant so
    -- trg_reassignment_guard cannot re-ask with its own generic reason and
    -- reverse this very decision.
    PERFORM public.ottoq_mark_reassign_granted(p_vehicle_id);
    RETURN jsonb_build_object('allowed', true, 'mode', 'resource_fault_auto_reroute',
                              'recorded', true, 'approval_id', v_approval, 'preserve_work', true,
                              'rebook_required', true);
  END IF;

  -- VEHICLE FAULT: the vehicle broke; the bay itself is fine.
  IF p_reason = 'vehicle_fault' THEN

    -- No atomic work to protect. Allow, audited. (Unchanged.)
    IF NOT v_mid THEN
      v_dec := jsonb_build_object('decision', jsonb_build_object(
                 'verdict',                'approved',
                 'reason',                 'zone_c_reopener_vehicle_fault_no_atomic_work_to_protect',
                 'decided_at_sim',         v_clock_sim,
                 'decided_at_domain',      CASE WHEN v_clock_sim IS NULL THEN 'real' ELSE 'sim' END,
                 'latency_min',            0,
                 'fast_path',              true,
                 'fast_path_basis',        'not_mid_service_nothing_to_cut_short',
                 'decider',                'ottoq_indepot_safety_carveout_v1',
                 'copilot_seen',           false,
                 'copilot_recommendation', 'not_consulted_safety_fast_path',
                 'copilot_binding',        false,
                 'doctrine',               'nemotron_reviews_ottoq_decides'));
      INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
             requested_at, decide_after, expires_at, priority, status, decided_at, decided_by)
      VALUES ('indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
              v_pay || jsonb_build_object('gate_mode','vehicle_fault_not_in_service')
                    || v_dec,
              now(), now(), now() + interval '30 minutes', 'normal', 'approved', v_dec_at,
              'auto_gate:vehicle_fault_not_in_service')
      RETURNING approval_id INTO v_approval;
      -- 0012: the gate has just SAID YES. Stamp a transaction-local grant so
      -- trg_reassignment_guard cannot re-ask with its own generic reason and
      -- reverse this very decision.
      PERFORM public.ottoq_mark_reassign_granted(p_vehicle_id);
      RETURN jsonb_build_object('allowed', true, 'mode', 'vehicle_fault_not_in_service',
                                'recorded', true, 'approval_id', v_approval);
    END IF;

    -- ══════════════ PHASE 10 FIX A (kept) ══════════════
    -- SEVERITY IS A CONSEQUENCE RATING, NOT A DISPOSITION.
    v_immob      := COALESCE((p_payload->>'immobilizing')::boolean, false);
    v_fault_class:= NULLIF(p_payload->>'fault_class','');
    v_req        := COALESCE(ottoq_policy_get(p_sim_run_id,'indepot_critical_requires_immobilizing',1),1);

    -- ══════════════ PHASE 12 FIX (P2) — IMMOBILIZING IS NOT A LICENCE TO CUT THE WORK ══════════════
    -- MEASURED (phase 11, seed 424242): all 12 work-cutting evictions came through this branch,
    -- 10 of them off charging_l2, destroying 595.56 of the 641.30 minutes -- avg 66.17 min each,
    -- max 139.96. The predicate that let them through was `immobilizing`, and immobilizing is
    -- the WRONG question for a vehicle sitting on a plug.
    --   "Immobilizing" answers: can the vehicle LEAVE UNDER ITS OWN POWER?  -> tow vs drive-away.
    --   It does NOT answer: can the SERVICE SAFELY CONTINUE WHERE IT IS?
    -- A charger does not care that the drive system, steering or brakes are broken. A vehicle
    -- that cannot move cannot be "evicted" at all -- it must be TOWED, and it keeps occupying
    -- that stall until the tow arrives, so terminating the charge buys the depot nothing and
    -- throws away the energy work. The faults that genuinely forbid continuing in place are the
    -- ENERGY/THERMAL ones (HV isolation, battery thermal, charge-system) plus anything in a BAY,
    -- where the cycle physically requires the vehicle to move.
    -- `service_incompatible` is the new explicit signal (production: the OEM fault code's
    -- class). TOTAL FUNCTION: a caller that does not send it falls back to the old
    -- `immobilizing` behaviour, so no other caller changes.
    v_si := COALESCE((p_payload->>'service_incompatible')::boolean, v_immob);
    v_si_basis := CASE WHEN p_payload ? 'service_incompatible' THEN 'fault_class' ELSE 'legacy_immobilizing_fallback' END;
    IF v_immob AND v_bay THEN
      -- A vehicle that cannot move cannot complete a wash/detail/service cycle.
      v_si := true; v_si_basis := 'immobilizing_in_bay';
    END IF;

    IF v_sev = 'critical' AND (v_si OR v_req < 1) THEN
      -- ZONE C, genuine: the service cannot continue in place. Evict -- safety first, and the
      -- tow/tech path must never deadlock -- but it is a GATED, AUDITED decision and the caller
      -- is told it MUST preserve the outstanding work and RE-BOOK it.
      -- gate_mode string is deliberately UNCHANGED so phase-10/11/12 harness sections stay
      -- like-for-like; the narrowed basis is stamped alongside it.
      -- 0003 (P1a): THIS is the carve-out the adversarial pass flagged. It stays a fast
      -- path -- an immobilised vehicle must never queue behind paperwork -- but it now
      -- stamps the SIM clock and carries the same payload.decision object the auto-gate
      -- writes, so it is auditable and its latency is measurable in one domain.
      v_dec := jsonb_build_object('decision', jsonb_build_object(
                 'verdict',                'approved',
                 'reason',                 'zone_c_reopener_vehicle_fault_service_cannot_continue_in_place',
                 'decided_at_sim',         v_clock_sim,
                 'decided_at_domain',      CASE WHEN v_clock_sim IS NULL THEN 'real' ELSE 'sim' END,
                 'latency_min',            0,
                 'fast_path',              true,
                 'fast_path_basis',        COALESCE(v_si_basis,'unknown'),
                 'decider',                'ottoq_indepot_safety_carveout_v1',
                 'copilot_seen',           false,
                 'copilot_recommendation', 'not_consulted_safety_fast_path',
                 'copilot_binding',        false,
                 'doctrine',               'nemotron_reviews_ottoq_decides'));
      INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
             requested_at, decide_after, expires_at, priority, status, decided_at, decided_by)
      VALUES ('indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
              v_pay || jsonb_build_object('gate_mode','vehicle_fault_critical_immobilizing',
                        'immobilizing', v_immob,
                        'service_incompatible', v_si,
                        'evict_basis', v_si_basis,
                        'fault_class', v_fault_class,
                        'auto_reason', CASE WHEN v_req < 1 THEN 'policy_immobilizing_check_disabled'
                                            ELSE 'service_cannot_continue_in_place' END,
                        'work_disposition','outstanding_work_must_survive_as_due_and_be_rebooked')
                    || v_dec,
              now(), now(), now() + interval '30 minutes', 'high', 'approved', v_dec_at,
              'auto_gate:vehicle_fault_critical_immobilizing')
      RETURNING approval_id INTO v_approval;
      -- 0012: the gate has just SAID YES. Stamp a transaction-local grant so
      -- trg_reassignment_guard cannot re-ask with its own generic reason and
      -- reverse this very decision.
      PERFORM public.ottoq_mark_reassign_granted(p_vehicle_id);
      RETURN jsonb_build_object('allowed', true, 'mode', 'vehicle_fault_critical_immobilizing',
                                'recorded', true, 'approval_id', v_approval, 'preserve_work', true,
                                'rebook_required', true,
                                'service_incompatible', v_si, 'evict_basis', v_si_basis,
                                'immobilizing', v_immob, 'fault_class', v_fault_class);
    END IF;

    -- MID-SERVICE, SERVICE CAN CONTINUE: DEFER. The atomic visit finishes first; the exception
    -- handler resumes the eviction afterwards. THREE defer classes, three budgets:
    --   immobilizing_awaiting_tow  -- broken but charge-safe: it is going nowhere without a tow
    --                                 anyway, so let the plug finish. BOUNDED budget, never open.
    --   critical_not_immobilizing  -- short budget, acted on quickly.
    --   major                      -- original budget.
    -- NO DEADLOCK: every class still exits on service-window-complete, left-service-state,
    -- technician approval (this row is inserted HIGH priority and is visible immediately), or a
    -- bounded budget expiry. The tow/tech path is never closed, only sequenced.
    v_defer_class := CASE WHEN v_immob            THEN 'immobilizing_awaiting_tow'
                          WHEN v_sev='critical'   THEN 'critical_not_immobilizing'
                          ELSE 'major' END;
    INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
           requested_at, decide_after, expires_at, priority)
    SELECT 'indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
           v_pay || jsonb_build_object('gate_mode','deferred_awaiting_tech',
                                       'defer_class', v_defer_class,
                                       'immobilizing', v_immob,
                                       'service_incompatible', v_si,
                                       'fault_class', v_fault_class),
           now(), now(), now() + interval '30 minutes',
           CASE WHEN v_sev='critical' OR v_immob THEN 'high' ELSE 'normal' END
    WHERE NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals a
                       WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
                         AND a.status = 'pending')
    RETURNING approval_id INTO v_approval;
    IF v_approval IS NULL THEN
      -- AUDIT-STAMP RESCUE: the INSERT was suppressed because a pending indepot_reassign
      -- already exists for this vehicle. The decision IS still audited -- by THAT row -- so
      -- return its id instead of NULL. MEASURED (live run 4921c87d): 24 of 45 deferrals lost
      -- their audit stamp this way; phase 10/11 never hit it because no other writer left
      -- pending approvals behind.
      SELECT a.approval_id INTO v_approval FROM ottoq_ops_approvals a
       WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
         AND a.status = 'pending' ORDER BY a.requested_at DESC LIMIT 1;
    END IF;
    RETURN jsonb_build_object('allowed', false, 'mode', 'deferred_awaiting_tech',
                              'defer_class', v_defer_class,
                              'immobilizing', v_immob, 'service_incompatible', v_si,
                              'fault_class', v_fault_class,
                              'approval_id', v_approval, 'state', v_veh.current_state::text);
  END IF;

  -- Everything else (optimization / congestion / operator request) defers, as before.
  INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id,
         payload, requested_at, decide_after, expires_at, priority)
  SELECT 'indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
         v_pay, now(), now(), now() + interval '30 minutes', 'normal'
  WHERE NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals a
                     WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
                       AND a.status = 'pending')
  RETURNING approval_id INTO v_approval;
    IF v_approval IS NULL THEN
    -- AUDIT-STAMP RESCUE: the INSERT was suppressed because a pending indepot_reassign
    -- already exists for this vehicle. The decision IS still audited -- by THAT row -- so
    -- return its id instead of NULL. MEASURED (live run 4921c87d): 24 of 45 deferrals lost
    -- their audit stamp this way; phase 10/11 never hit it because no other writer left
    -- pending approvals behind.
    SELECT a.approval_id INTO v_approval FROM ottoq_ops_approvals a
     WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
       AND a.status = 'pending' ORDER BY a.requested_at DESC LIMIT 1;
  END IF;
  RETURN jsonb_build_object('allowed', false, 'mode', 'awaiting_tech_approval',
                            'approval_id', v_approval, 'state', v_veh.current_state::text);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_stall_seat_is_exclusive()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF NEW.current_vehicle_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.current_vehicle_id IS DISTINCT FROM OLD.current_vehicle_id)
  THEN
    -- Release every OTHER stall still claiming this vehicle. Physically a car is
    -- in one place; the unique index says so, and until now nothing made it true.
    UPDATE public.stalls s
       SET current_vehicle_id = NULL,
           status = CASE WHEN s.status = 'occupied' THEN 'available' ELSE s.status END
     WHERE s.current_vehicle_id = NEW.current_vehicle_id
       AND s.id <> NEW.id;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_trg_reassignment_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
    DECLARE
      v_guard jsonb;
      v_vehicle_id uuid;
      v_sim_run_id uuid;
      v_state text;
      v_granted text;
      v_cur uuid;      -- 0547: the car's own stall
      v_tether uuid;   -- 0547: the stall the car is tethered to
    BEGIN
      IF NEW.current_vehicle_id IS NULL AND OLD.current_vehicle_id IS NOT NULL THEN
        v_vehicle_id := OLD.current_vehicle_id;

        -- ── (1) ONLY WORK IN PROGRESS IS PROTECTED ──────────────────────────────
        -- Exactly ottoq_indepot_reassignment_guard's own v_mid set. A vehicle in a
        -- holding state (staged_awaiting_service, charge_complete_holding,
        -- service_complete_holding, staged_for_departure, ...) has nothing to cut
        -- short, so vacating its stall is not a re-route and needs no approval.
        -- ::text on purpose: an unknown label can only fail to match, never raise.
        SELECT v.current_state::text, v.current_stall_id, v.robotic_tether_stall_id
          INTO v_state, v_cur, v_tether FROM vehicles v WHERE v.id = v_vehicle_id;
        IF v_state IS NULL OR v_state NOT IN ('in_wash_bay','in_detail_bay','in_service_bay',
                                              'charging_dcfc','charging_l2') THEN
          RETURN NEW;
        END IF;

        -- ── (1b) 0547 (G276): A CHARGER ITS CAR HAS LEFT FOR A BAY IS FREE ──────
        -- A car in a bay is not charging, so the charger it came from holds no work
        -- in progress. Reading the state alone made such a car look mid-work at the
        -- charger it had left: the pointer was put back, the charger read available
        -- with a car that was elsewhere, and nothing could offer it (G121). The car
        -- is still at the charger only if it names it itself, by its current_stall_id
        -- or its tether. A car in a bay keeps its bay, even with its own pointer
        -- empty (0535 §1).
        IF v_state IN ('in_wash_bay','in_detail_bay','in_service_bay')
           AND OLD.stall_type::text IN ('dcfc','l2')
           AND v_cur IS DISTINCT FROM OLD.id AND v_tether IS DISTINCT FROM OLD.id THEN
          RETURN NEW;
        END IF;

        -- ── (2) THE GATE DOES NOT SECOND-GUESS ITSELF ───────────────────────────
        -- A fault handler that already asked and was granted carries a transaction-local
        -- grant. Without this, the trigger re-asks with 'automated_reassignment', gets
        -- the catch-all defer, and reverses a decision the gate itself just made --
        -- which is what would strand a faulted vehicle mid-bay with no technician to
        -- release it.
        v_granted := current_setting('ottoq.reassign_ok', true);
        IF v_granted IS NOT NULL AND position(v_vehicle_id::text in v_granted) > 0 THEN
          RETURN NEW;
        END IF;

        SELECT sim_run_id INTO v_sim_run_id
          FROM ottoq_sim_runs
         WHERE depot_id = NEW.depot_id AND status = 'running'
         ORDER BY started_at DESC LIMIT 1;
        IF v_sim_run_id IS NOT NULL THEN
          v_guard := ottoq_indepot_reassignment_guard(
            v_vehicle_id, v_sim_run_id,
            'automated_reassignment',
            jsonb_build_object('from_stall', OLD.id)
          );
          IF (v_guard->>'allowed')::boolean IS FALSE THEN
            NEW.current_vehicle_id := OLD.current_vehicle_id;
          END IF;
        END IF;
      END IF;
      RETURN NEW;
    END;
    $function$;

CREATE OR REPLACE FUNCTION public.update_timestamp()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$;

-- live: the three BEFORE UPDATE triggers on stalls, fired in name order as live
CREATE TRIGGER trg_ottoq_stall_seat_is_exclusive BEFORE INSERT OR UPDATE OF current_vehicle_id ON public.stalls
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_stall_seat_is_exclusive();
CREATE TRIGGER trg_reassignment_guard BEFORE UPDATE ON public.stalls
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_trg_reassignment_guard();
CREATE TRIGGER trg_stalls_updated BEFORE UPDATE ON public.stalls
  FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
