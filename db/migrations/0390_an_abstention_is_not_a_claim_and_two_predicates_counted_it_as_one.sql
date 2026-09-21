-- migration-version: 20260921000517
-- migration-name:    an_abstention_is_not_a_claim_and_two_predicates_counted_it_as_one
--
-- 0390  AN ABSTENTION IS NOT A CLAIM — AND THE PROPOSER'S OWN "I CANNOT SERVE THIS VEHICLE
--       THIS TICK" WAS DENYING THAT VEHICLE BOTH A RETRY AND A FIRST-REFUSAL SEAT.
--
-- `forces_recert` **TRUE**. It changes the decision frame (so `frame_hash` moves) and changes
-- which vehicles are armed for first refusal (so engine behaviour moves). Both are exactly
-- what a canon is supposed to notice. Job 746 re-certifies automatically.
--
-- ══ 1. WHAT AN ABSTENTION MEANS, ESTABLISHED BY `0361` NOT BY ME ════════════
--
-- `0361` taught the disposer to recognise an abstaining proposal and quoted the rationale
-- CP-SAT actually writes on one:
--
--     "planned to start at +111 min on l2 95fe1b50-..., beyond this tick's 30-min
--      window; re-offered when due"
--
-- That is a rolling re-solve declining to offer a plan that is not due yet — the behaviour
-- CLAUDE.md 2.5 asks for. `0361`'s own words: *"correct behaviour ... not a failure."* On the
-- wave run `c8f678fb` **213 of `forward_lex`'s 610 rows (35%) are abstentions.**
--
-- ══ 2. TWO PREDICATES COUNTED IT AS AN ANSWER ══════════════════════════════
--
-- **(a) The decision frame.** `ottoq_build_decision_frame`'s `prp` lateral sets
-- `has_live_holds_tick_proposal` from *any* pending proposal whose source declares
-- `holds_tick`, with no abstention test. `proposer/forward_proposer.py`'s `vehicle_is_held`
-- reads that key and withholds the vehicle. **So the proposer's own abstention suppressed its
-- next attempt at the same vehicle — the exact opposite of "re-offered when due."**
--
-- **(b) First-refusal arming.** `ottoq_cuopt_first_refusal_arm` excludes any vehicle with a
-- pending `holds_tick` proposal, under the comment *"cuOpt has already answered for this
-- vehicle => let the cursor enact it now."* For a real plan that is right. For an abstention
-- nobody has answered, so the exclusion **denied the vehicle the seat a later plan would
-- need** — the proposer was penalising the vehicles it was least able to serve.
--
-- Measured on `c8f678fb`: of the 213 abstention rows, **192 ended `superseded` /
-- `entity_decided_by_other_proposal`** — they sat `pending` long enough for the entity to be
-- decided, which is precisely the window in which they were masquerading as claims.
--
-- **This is `0290`'s follow-up, and it is NOT `0288` §6's withdrawn remedy.** That one wanted
-- to arm holds FOR vehicles with pending proposals, inverting the arm's intent. This does the
-- opposite and much smaller thing: it stops a NON-claim from counting as one, leaving the
-- pre-proposal-reservation design exactly as `0361`/`0259` built it.
--
-- ══ 3. THE TEST IS CAST-FREE ON PURPOSE ════════════════════════════════════
--
--     COALESCE(proposal->>'abstain', '') NOT IN ('true', 't', '1')
--
-- Verbatim the idiom `ottoq_dispose_external_proposals` already uses (`0361`), inverted. No
-- `::boolean`, so a malformed `abstain` value cannot raise inside the frame builder or the
-- arm — `0384`'s lesson, which was a detector that raised on the data it existed to find. A
-- missing or unparseable key reads as NOT abstaining, i.e. as a claim, which is today's
-- behaviour: **the change can only ever ADD eligibility, never remove it.**

BEGIN;

-- ══ P0. PREFLIGHT ══════════════════════════════════════════════════════════
DO $p0$
BEGIN
  IF to_regprocedure('public.ottoq_build_decision_frame(uuid,uuid)') IS NULL
     OR to_regprocedure('public.ottoq_cuopt_first_refusal_arm(uuid,bigint)') IS NULL THEN
    RAISE EXCEPTION '0390 P0: one of the two target functions is absent' USING ERRCODE='42883';
  END IF;
  --: the idiom this file reuses must still be the one the disposer uses, or the two halves
  --: of the system would be testing abstention differently.
  IF NOT EXISTS (SELECT 1 FROM pg_proc
                  WHERE proname = 'ottoq_dispose_external_proposals'
                    AND prosrc LIKE '%abstain%IN (''true'', ''t'', ''1'')%') THEN
    RAISE EXCEPTION '0390 P0: ottoq_dispose_external_proposals no longer carries 0361''s abstention idiom; re-derive before reusing it'
      USING ERRCODE='22023';
  END IF;
END $p0$;

-- ══ P1a. THE FRAME: an abstention no longer sets has_live_holds_tick_proposal ═
CREATE OR REPLACE FUNCTION public.ottoq_build_decision_frame(p_depot_id uuid, p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH g AS (
    --: 0265. ONE gate read and ONE clock read per frame build. The clock is the
    --: selector's own expression: sim when the run has one, wall only when there
    --: is no run at all. Measured 2026-09-13: all 40 flagship charge stalls are
    --: heartbeat-stale against now() and fresh against the sim clock, so reading
    --: the wall clock here would make every stall look dead.
    SELECT COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_frame_facts', 0), 0)::int AS facts,
           COALESCE((SELECT r.sim_clock_current FROM ottoq_sim_runs r
                      WHERE r.sim_run_id = p_sim_run_id), now()) AS clk
  )
  SELECT jsonb_build_object(
    'vehicles', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', v.id, 'state', v.current_state, 'soc', ROUND(v.current_soc::numeric,2),
        'stall_id', v.current_stall_id, 'inlet_type', v.inlet_type,
        'inlet_max_kw', v.inlet_max_kw, 'fleet_operator_id', v.fleet_operator_id,
        'make', v.make, 'platform', v.platform, 'svc_step', v.config->>'svc_step',
        'target_soc', v.target_soc, 'min_soc_threshold', v.min_soc_threshold,
        --: 0209/L-41: THE JOIN KEY. ottoq_vehicle_classes is keyed by
        --: vehicle_class_code, not by platform, so without this the frame could
        --: not be joined to the class table the proposer README names. Nullable
        --: by construction: a vehicle whose class is unrecorded gets NULL and
        --: the bridge abstains on it, which is the honest answer and not a
        --: guessed battery.
        'vehicle_class_code', v.vehicle_class_code
      ) || CASE WHEN g.facts >= 1 THEN jsonb_build_object(
        --: 0265/L-60. A staged vehicle usually already holds a reservation the
        --: frame did not show, so a proposer planned for vehicles that were never
        --: going to be re-decided. Both lookups are RUN-SCOPED (the 0145 class).
        --:
        --: 0287. Those two facts were TYPE-BLIND, and that made them wrong for
        --: the population the kernel most wants planned. A vehicle on a staging
        --: stall under a temp_hold answered has_live_booking = true, so the
        --: proposer skipped it -- while ottoq_cuopt_first_refusal_arm, which
        --: disqualifies only a live dcfc/l2 RESERVATION, was at that same moment
        --: holding a one-tick seat open for it. Measured on run c288555a: 19
        --: holds, 18 of them carrying nothing but a staging booking, 0 answered
        --: (db/checks/0221). The five keys below let the consumer tell a parking
        --: spot from a service assignment, and say WHICH ledger knows it.
        'reserved_stall_id',   rsv.stall_id,
        'reserved_stall_type', rsv.stall_type,
        'has_live_booking', EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                                     WHERE b.vehicle_id = v.id
                                       AND b.state IN ('held','active')
                                       AND COALESCE(b.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                           = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)),
        'live_booking_stall_types', COALESCE(bkg.types, '[]'::jsonb),
        --: THE KERNEL'S LEDGER: stalls.reserved_by, the expression
        --: ottoq_cuopt_first_refusal_arm itself evaluates.
        'holds_charge_reservation', COALESCE(rsv.is_charge, false),
        --: THE CALENDAR'S LEDGER: ottoq_stall_bookings, which CLAUDE.md 2.3
        --: calls the calendar. These two DO disagree -- 0221 section B found a
        --: vehicle the kernel called unplaced while the calendar held an L2 for
        --: it -- so both are published rather than one being quietly preferred.
        'holds_charge_booking', COALESCE(bkg.has_charge, false),
        --: THE UNION, not the intersection: if either ledger says this vehicle
        --: has a charge place, treat it as placed. That is the safe direction,
        --: and it is what keeps the one genuinely-placed vehicle skipped while
        --: freeing the eighteen that held only a parking spot.
        'holds_charge_place', (COALESCE(rsv.is_charge, false) OR COALESCE(bkg.has_charge, false)),
        --: 0366 (G81). THE OVERSTAY, PUBLISHED. True when this vehicle
        --: physically occupies a CHARGE stall for which no booking covers the
        --: clock -- i.e. ottoq_release_expired_bookings has already stamped
        --: release_reason = 'window_elapsed_occupied' and the asset never left.
        --: Measured 162 times against 143 clean expiries on run 3fb415d8, with
        --: a DCFC held 188 minutes past its window.
        --:
        --: holds_charge_place answers "do I hold a BOOKED charge place" and is
        --: correctly false here; this answers "am I sitting in one anyway". A
        --: consumer that conflates them re-offers a stall to a vehicle already
        --: drawing power (G80). Deliberately a SEPARATE key: overwriting
        --: holds_charge_place would change proposer behaviour silently.
        --: g.clk is the run's sim clock; `during` is a SIM range (0357) and a
        --: now() comparison here is G77.
        'occupies_charge_stall_unbooked', EXISTS (
          SELECT 1 FROM public.stalls s_ov
           WHERE s_ov.current_vehicle_id = v.id
             AND s_ov.stall_type::text IN ('l2', 'dcfc')
             AND NOT EXISTS (
               SELECT 1 FROM public.ottoq_stall_bookings b_ov
                WHERE b_ov.sim_run_id = p_sim_run_id
                  AND b_ov.stall_id   = s_ov.id
                  AND b_ov.vehicle_id = v.id
                  AND b_ov.state IN ('held', 'active')
                  AND b_ov.during @> g.clk)),
        --: 0292 / G60. HAVE I ALREADY PLANNED THIS VEHICLE? Measured on run
        --: 91139ad8: 26 of 48 forward_lex proposals had an earlier holds_tick
        --: proposal for the same vehicle, and 35 of 48 ended superseded across
        --: only 18 vehicles -- the proposer overwriting its own pending plans
        --: about one tick after making them.
        --:
        --: This is a VERBATIM COPY of the clause in
        --: ottoq_cuopt_first_refusal_arm that already declines to open a seat
        --: for such a vehicle: (stall_assignment, vehicle, pending, a source
        --: declaring holds_tick), run-scoped, AND EXPIRY-BLIND, because the arm
        --: is expiry-blind here and publishing a narrower question than the
        --: kernel asks is precisely the G54 defect. P1 pins that clause.
        --:
        --: So the kernel has already decided it does not need this vehicle
        --: planned. The frame is only telling the proposer what the kernel knows.
        'has_live_holds_tick_proposal', COALESCE(prp.has_any, false),
        --: WHICH source holds it, for diagnosis: a vehicle skipped because
        --: another proposer answered for it is a different story from one
        --: skipped because of its own previous plan, and the count of each is
        --: the thing to watch after this lands.
        'live_holds_tick_proposal_sources', COALESCE(prp.sources, '[]'::jsonb)
      ) ELSE '{}'::jsonb END
      ORDER BY v.id)
      FROM vehicles v
      --: 0287. ONE lookup per vehicle per ledger, not one per fact. Both
      --: laterals are gated on g.facts inside their own WHERE so a facts-off
      --: frame does no extra work at all.
      LEFT JOIN LATERAL (
        SELECT s2.id AS stall_id, s2.stall_type::text AS stall_type,
               (s2.stall_type::text IN ('dcfc','l2')) AS is_charge
          FROM stalls s2, g g2
         WHERE g2.facts >= 1
           AND s2.depot_id = p_depot_id AND s2.reserved_by = v.id
           AND COALESCE(s2.reservation_expires_at, 'infinity'::timestamptz) > g2.clk
         ORDER BY s2.id LIMIT 1
      ) rsv ON true
      LEFT JOIN LATERAL (
        SELECT jsonb_agg(DISTINCT s3.stall_type::text ORDER BY s3.stall_type::text) AS types,
               bool_or(s3.stall_type::text IN ('dcfc','l2')) AS has_charge
          FROM ottoq_stall_bookings b3
          JOIN stalls s3 ON s3.id = b3.stall_id, g g3
         WHERE g3.facts >= 1
           AND b3.vehicle_id = v.id
           AND b3.state IN ('held','active')
           AND COALESCE(b3.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
               = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
      ) bkg ON true
      --: 0292. The third ledger: the proposal book. Gated on g.facts like the
      --: other two, and matched on p_sim_run_id with NO coalescing to the nil
      --: uuid -- the arm compares `= p_sim_run_id` directly, so a frame built
      --: with no run at all yields NULL, the EXISTS is false, and every vehicle
      --: stays plannable. That is the current behaviour and the safe direction:
      --: when the run is unknown, do not silently suppress planning.
      LEFT JOIN LATERAL (
        SELECT bool_or(true) AS has_any,
               jsonb_agg(DISTINCT ep.source ORDER BY ep.source) AS sources
          FROM public.ottoq_external_proposals ep, g g4
         WHERE g4.facts >= 1
           AND ep.sim_run_id     = p_sim_run_id
           AND ep.action_context = 'stall_assignment'
           AND ep.entity_type    = 'vehicle'
           AND ep.entity_id      = v.id
           AND ep.status         = 'pending'
           --: 0390. AN ABSTENTION IS NOT A CLAIM. `0361` established what an abstaining
           --: row means -- *"planned to start at +111 min ... beyond this tick's 30-min
           --: window; re-offered when due"* -- so a vehicle carrying only an abstention
           --: has NOT been answered for, and telling the proposer it has contradicts
           --: 0361's own "re-offered when due". Cast-free test, the same idiom
           --: ottoq_dispose_external_proposals uses, so a malformed value cannot raise.
           AND COALESCE(ep.proposal->>'abstain', '') NOT IN ('true', 't', '1')
           AND ep.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp
                              WHERE pp.holds_tick)
      ) prp ON true
      WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
    ), '[]'::jsonb),
    'stalls', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', s.id, 'type', s.stall_type, 'status', s.status,
        'vehicle_id', s.current_vehicle_id, 'connector_type', s.connector_type,
        'connector_max_kw', s.connector_max_kw,
        --: 0209/L-42: WHICH PLUGS THIS POINT ACCEPTS. connector_type alone is
        --: not the rule: the L1 shield passes a 'Multi' stall iff the vehicle's
        --: inlet is in THIS list, and every charging stall at the flagship depot
        --: is Multi. Without the list the frame could express only the
        --: exact-match half of a rule the engine already enforces.
        'supported_inlet_types', s.supported_inlet_types
      ) || CASE WHEN g.facts >= 1 THEN jsonb_build_object(
        --: 0265/L-61. The three facts the selector refuses on and the frame did
        --: not carry, plus the join key that makes a stall selectable at all.
        'ocpp_charger_id', s.ocpp_charger_id,
        'reserved_by', s.reserved_by,
        'reservation_expires_at', s.reservation_expires_at,
        'reservation_live', (s.reserved_by IS NOT NULL
                             AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > g.clk),
        'charger_state', c.station_state,
        'charger_heartbeat_at', c.last_heartbeat_at,
        'charger_fresh', (c.last_heartbeat_at IS NOT NULL
                          AND c.last_heartbeat_at >= g.clk - interval '90 seconds'),
        --: VEHICLE-BLIND on purpose: the selector also accepts a stall reserved
        --: for the proposal's OWN vehicle, which this object cannot know. So
        --: offerable=false means no proposal can win it; offerable=true means a
        --: proposal for a vehicle with no competing reservation can.
        'offerable', (s.current_vehicle_id IS NULL
                      AND s.ocpp_charger_id IS NOT NULL
                      AND c.station_state = 'Available'
                      AND c.last_heartbeat_at IS NOT NULL
                      AND c.last_heartbeat_at >= g.clk - interval '90 seconds'
                      AND (s.reserved_by IS NULL
                           OR COALESCE(s.reservation_expires_at, '-infinity'::timestamptz) <= g.clk))
      ) ELSE '{}'::jsonb END
      ORDER BY s.id)
      FROM stalls s
      LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
      WHERE s.depot_id = p_depot_id
    ), '[]'::jsonb),
    'sessions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cs.id, 'stall_id', cs.stall_id, 'vehicle_id', cs.vehicle_id,
        'status', cs.status, 'started_at', cs.started_at,
        'power_kw', ((cs.last_meter_value->>'power_kw'))::numeric
      ) ORDER BY cs.id)
      FROM ocpp_sessions cs WHERE cs.depot_id = p_depot_id AND cs.status = 'active'
    ), '[]'::jsonb),
    'energy', (
      SELECT jsonb_build_object(
        'grid_import_kw', se.grid_import_kw, 'total_ev_charging_kw', se.total_ev_charging_kw,
        'building_load_kw', se.building_load_kw, 'peak_demand_kw_15min', se.peak_demand_kw_15min,
        'tariff', se.current_tariff_label, 'at', se.timestamp
      )
      FROM site_energy_snapshots se WHERE se.depot_id = p_depot_id
        AND se.sim_run_id = p_sim_run_id
      ORDER BY se.timestamp DESC LIMIT 1
    ),
    'bess', (
      SELECT jsonb_build_object(
        'soc_pct', b.current_soc_pct, 'power_kw', b.current_power_kw,
        'state', b.current_state, 'temp_c', b.current_temperature_c, 'soh_pct', b.current_soh_pct
      )
      FROM ottoq_bess_units b WHERE b.depot_id = p_depot_id LIMIT 1
    )
  ) || CASE WHEN g.facts >= 1 THEN jsonb_build_object(
    --: 0265. The consumer must not have to guess which clock the verdicts used.
    --: 0287. facts_version 2 adds the five vehicle place-facts. charge_stall_types
    --: travels with it so the consumer reads WHICH types the publisher counted
    --: as a charge place rather than keeping its own copy of the list -- the
    --: copy is what diverged in the first place.
    --: 0292. facts_version 3 adds the two proposal-book facts, and
    --: holds_tick_sources travels with them for the same reason: the consumer
    --: reads the vocabulary from the publisher instead of hard-coding a list
    --: that can drift out of ottoq_proposer_precedence.
    'selector', jsonb_build_object('facts_version', 3, 'clock', g.clk,
                                   'heartbeat_window_s', 90,
                                   'charge_stall_types', jsonb_build_array('dcfc','l2'),
                                   'holds_tick_sources',
                                     COALESCE((SELECT jsonb_agg(pp.source ORDER BY pp.source)
                                                 FROM public.ottoq_proposer_precedence pp
                                                WHERE pp.holds_tick), '[]'::jsonb),
                                   'authority', 'public.ottoq_l2_external_proposal')
  ) ELSE '{}'::jsonb END
  FROM g;
$function$;

-- ══ P1b. THE ARM: an abstention no longer counts as an answer ══════════════
CREATE OR REPLACE FUNCTION public.ottoq_cuopt_first_refusal_arm(p_sim_run_id uuid, p_tick bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_sim timestamptz; v_cap int; v_ids uuid[]; v_n int := 0;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;

  -- STARVATION BOUND + OFF SWITCH, both policy-tunable per run.
  v_cap := GREATEST(0, ottoq_policy_get(p_sim_run_id, 'cuopt_first_refusal_max_defers', 1)::int);
  IF v_cap = 0 THEN RETURN 0; END IF;

  SELECT depot_id, COALESCE(sim_clock_current, now()) INTO v_depot, v_sim
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;

  SELECT COALESCE(array_agg(v.id), ARRAY[]::uuid[]) INTO v_ids
    FROM vehicles v
   WHERE v.home_depot_id = v_depot
     AND v.category = 'autonomous'
     -- Zone A/outside-the-walls only. Mirrors ottoq_cuopt_defer_arm's own guard.
     AND v.current_state = 'arrived_at_gate'
     AND v.current_stall_id IS NULL
     AND v.current_soc < 85
     -- greedy has already reserved a charge stall for it => nothing left to optimise
     AND NOT EXISTS (SELECT 1 FROM stalls s
                      WHERE s.reserved_by = v.id
                        AND s.stall_type::text IN ('dcfc','l2')
                        AND COALESCE(s.reservation_expires_at, v_sim) >= v_sim)
     -- THE BOUND: never hold a vehicle that is already armed/spent, and never
     -- more than v_cap times in the whole run.
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_cuopt_deferrals d
                      WHERE d.sim_run_id = p_sim_run_id AND d.vehicle_id = v.id
                        AND (d.state <> 'clear' OR d.defer_count >= v_cap))
     -- cuOpt has already answered for this vehicle => let the cursor enact it now
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_external_proposals p
                      WHERE p.sim_run_id     = p_sim_run_id
                        AND p.action_context = 'stall_assignment'
                        AND p.entity_type    = 'vehicle'
                        AND p.entity_id      = v.id
                        AND p.status         = 'pending'
                        --: 0390. AN ABSTENTION IS NOT AN ANSWER. Without this the
                        --: proposer's own "I cannot serve this vehicle this tick"
                        --: removed the vehicle from first-refusal arming, denying it
                        --: the very seat a later proposal would need. Cast-free test,
                        --: 0361's idiom.
                        AND COALESCE(p.proposal->>'abstain', '') NOT IN ('true','t','1')
                        -- 0259: any source that declares holds_tick counts as an answer.
                        AND p.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp
                                          WHERE pp.holds_tick));

  IF v_ids IS NULL OR array_length(v_ids,1) IS NULL THEN RETURN 0; END IF;

  v_n := public.ottoq_cuopt_defer_arm(p_sim_run_id, p_tick, v_ids, NULL);

  BEGIN
    PERFORM public.cuopt_log_gate(
      p_sim_run_id, 'first_refusal_arm', array_length(v_ids,1),
      jsonb_build_object('armed', v_n, 'offered', array_length(v_ids,1),
                         'tick', p_tick, 'max_defers', v_cap),
      clock_timestamp(), 'p7_first_refusal');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  -- Fail OPEN: a ledger hiccup must never change how the engine assigns.
  RAISE WARNING 'ottoq_cuopt_first_refusal_arm: % (run=%, tick=%)', SQLERRM, p_sim_run_id, p_tick;
  RETURN 0;
END;
$function$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0390_an_abstention_is_not_a_claim_and_two_predicates_counted_it_as_one', true,
  'Adds a cast-free abstention filter to the two predicates that read pending holds_tick '
  'proposals: the decision frame''s has_live_holds_tick_proposal lateral, and '
  'ottoq_cuopt_first_refusal_arm''s exclusion. TRUE because the frame is digested into '
  'frame_hash and because the set of vehicles armed for first refusal changes -- both are '
  'engine behaviour a canon exists to notice, so every column is correctly invalidated and '
  'job 746 re-certifies. The change can only ADD eligibility: a missing or unparseable '
  'abstain key still reads as a claim, which is today''s behaviour, so no vehicle eligible '
  'today becomes ineligible. Grounded in 0361, which established that an abstaining row means '
  '"planned beyond this tick''s window; re-offered when due" -- a vehicle carrying only an '
  'abstention has not been answered for, and both predicates were treating it as though it '
  'had been. Measured on run c8f678fb: 213 of forward_lex''s 610 rows were abstentions and '
  '192 of those sat pending until the entity was decided by something else.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ══ P2. POSTFLIGHT — assert the filter landed AND invoke both ══════════════
DO $p2$
DECLARE v_frame jsonb; v_run uuid; v_missing text := ''; v_armed int;
BEGIN
  IF (SELECT count(*) FROM pg_proc
        WHERE proname = 'ottoq_build_decision_frame' AND pronargs = 2
          AND prosrc LIKE '%abstain%NOT IN%') <> 1 THEN
    v_missing := v_missing || 'frame ';
  END IF;
  IF (SELECT count(*) FROM pg_proc
        WHERE proname = 'ottoq_cuopt_first_refusal_arm'
          AND prosrc LIKE '%abstain%NOT IN%') <> 1 THEN
    v_missing := v_missing || 'arm ';
  END IF;
  IF v_missing <> '' THEN
    RAISE EXCEPTION '0390 P2: abstention filter absent from: %', v_missing USING ERRCODE='23514';
  END IF;

  SELECT sr.sim_run_id INTO v_run FROM public.ottoq_sim_runs sr
   WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY sr.started_at DESC LIMIT 1;

  --: INVOKE, do not string-match only. 0381 shipped a body that raised 42703 while three
  --: source assertions passed, because plpgsql resolves columns at execution time.
  SELECT public.ottoq_build_decision_frame('11111111-1111-1111-1111-111111111111', v_run)
    INTO v_frame;
  IF v_frame IS NULL OR NOT (v_frame ? 'vehicles') THEN
    RAISE EXCEPTION '0390 P2: the patched frame builder returned no vehicles block'
      USING ERRCODE='23514';
  END IF;
  RAISE NOTICE '0390 P2: frame builds — % vehicles, % stalls',
    jsonb_array_length(v_frame->'vehicles'), jsonb_array_length(v_frame->'stalls');

  --: the arm is safe to invoke on a settled run: it returns 0 when nothing qualifies and
  --: fails OPEN by its own design.
  v_armed := public.ottoq_cuopt_first_refusal_arm(v_run, 0::bigint);
  RAISE NOTICE '0390 P2: first_refusal_arm returned % on a settled run', v_armed;
END $p2$;

COMMIT;
