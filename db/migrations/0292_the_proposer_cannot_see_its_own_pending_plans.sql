-- migration-version: 20260914090954
-- migration-name:    0292_the_proposer_cannot_see_its_own_pending_plans
--
-- 0292  THE PROPOSER CANNOT SEE ITS OWN PENDING PLANS
--
-- G60. Same shape as 0287, one layer further in: a decision the proposer must
-- make about a fact it was never given. 0287 was "has this vehicle already got
-- a place?". This one is "have I already planned this vehicle?".
--
-- ---------------------------------------------------------------------------
-- WHAT WAS MEASURED
--
-- Run 91139ad8 (seed 848484, 32 ticks, the first run on the tick-following
-- loop) wrote 48 forward_lex proposals. Of those, 26 had an EARLIER proposal
-- for the SAME vehicle from a holds_tick source at a strictly earlier tick --
-- and 35 of the 48 ended 'superseded', spread over only 18 distinct vehicles.
-- The timer-driven run 36e5cc68, same seed, recorded 23 proposals and ZERO
-- with an earlier same-vehicle row.
--
--   run       props   with an earlier holds_tick row for the same vehicle
--   36e5cc68     23   0
--   91139ad8     48   26
--
-- So roughly half the extra volume the tick-following loop produced is the
-- proposer re-planning vehicles it had already planned. 0224 measured the
-- outcome of that volume: proposals 23 -> 48 and enactments 8 -> 9.
--
-- 26 IS AN UPPER BOUND, not the number this fix would have skipped, and the
-- difference cannot be recovered. ottoq_external_proposals.status is CURRENT,
-- not historised, and there is no resolved_at column, so whether the earlier
-- row was still 'pending' at the moment the later one was written is not
-- reconstructable. Same limit db/checks/0221 hit on ottoq_stall_bookings.state,
-- and it is why the real evidence for this change has to be a live before/after
-- on a new run rather than an archaeology of an old one.
--
-- ---------------------------------------------------------------------------
-- AND THE KERNEL ALREADY AGREES. This is the part that makes the fix obvious.
--
-- public.ottoq_cuopt_first_refusal_arm will NOT open a seat for a vehicle that
-- already has a live pending proposal from a holds_tick source. Its own clause,
-- read verbatim out of live prosrc:
--
--     AND NOT EXISTS (SELECT 1 FROM public.ottoq_external_proposals p
--                      WHERE p.sim_run_id     = p_sim_run_id
--                        AND p.action_context = 'stall_assignment'
--                        AND p.entity_type    = 'vehicle'
--                        AND p.entity_id      = v.id
--                        AND p.status         = 'pending'
--                        AND p.source IN (SELECT pp.source
--                                           FROM public.ottoq_proposer_precedence pp
--                                          WHERE pp.holds_tick))
--
-- The kernel has already decided it does not need that vehicle planned. The
-- proposer plans it anyway, because the frame never told it. This file makes
-- the frame tell it, and it publishes THE KERNEL'S OWN PREDICATE rather than a
-- reasonable-looking equivalent -- which is exactly the mistake G54 was.
--
-- NOTE WHAT THE PREDICATE DOES NOT TEST: expires_at. The whole function
-- contains one expires_at and it is on stalls.reservation_expires_at, not on a
-- proposal. So 'live' here means status='pending' and nothing else. Publishing
-- an expiry-aware version would be a different question than the one the kernel
-- asks, and that is how the last mismatch started.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS FILE DOES NOT DO, deliberately:
--
--   - It does not slow the loop down. Tick-following is correct (0224: the seat
--     is one tick wide by construction), and reverting it would trade a real
--     mechanism for a symptom.
--   - It does not change the arm, the decide path, or any proposal lifecycle.
--     Nothing disposes differently after this file. The only behaviour that can
--     change is which vehicles a PROPOSER chooses to spend effort on, and only
--     once the Python side consumes the new key.
--   - It does not claim a throughput gain. 0224 predicted one for tick-following
--     and did not get one; this file states its prediction (fewer proposals for
--     the same or more enactments) and leaves it to be measured on a new run.
--
-- forces_recert=false, and the argument is the same as 0287's, RE-MEASURED
-- rather than remembered (P2): proposer_frame_facts has no global row and the
-- frame builder's own caller default is 0, so a certification arm -- which sets
-- no policy row -- gets facts=0 and never reaches the block this file edits.
-- A1 proves it by digest rather than by argument.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0292 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0292 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0292 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0292 P-: nothing in flight';
END $inflight$;

-- P0. SNAPSHOT + md5 GUARD ---------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots (taken_at, label, object_kind, schema_name, object_name, definition, def_md5)
SELECT now(), '0292_pre', 'function', 'public', 'ottoq_build_decision_frame(uuid,uuid)',
       pg_get_functiondef('public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure));

DO $p0$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef('public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure))
    INTO v_md5;
  IF v_md5 <> 'f49ac2d36e9a4291dff37fd8fbd5d668' THEN
    RAISE EXCEPTION '0292 P0: ottoq_build_decision_frame is not the definition this file was '
                    'written against (live md5 %). Someone changed it since; re-read it and '
                    'rebase this file rather than overwriting their change', v_md5;
  END IF;
  RAISE NOTICE '0292 P0: the live definition is the one this file edits';
END $p0$;

-- P1. THE KERNEL'S PREDICATE IS STILL THE KERNEL'S PREDICATE ------------------
-- The load-bearing precondition. The fact published below is a COPY of the
-- clause in ottoq_cuopt_first_refusal_arm. If that clause is edited, the copy
-- is a divergence -- which is the whole G54 defect -- and this refuses to apply.
DO $p1$
DECLARE v_src text; v_n int;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_first_refusal_arm';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0292 P1: ottoq_cuopt_first_refusal_arm does not exist';
  END IF;
  IF position('AND p.action_context = ''stall_assignment''' in v_src) = 0
     OR position('AND p.entity_type    = ''vehicle''' in v_src) = 0
     OR position('AND p.status         = ''pending''' in v_src) = 0
     OR position('WHERE pp.holds_tick' in v_src) = 0 THEN
    RAISE EXCEPTION '0292 P1: the arm no longer disqualifies a vehicle on (stall_assignment, '
                    'vehicle, pending, holds_tick). The fact this file publishes is a copy of '
                    'that clause and must be re-read from the arm, not patched here';
  END IF;
  -- and it still does NOT test the proposal's expiry: exactly one expires_at in
  -- the function, and it is on the STALL reservation.
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'expires_at', 'g');
  IF v_n <> 1 OR position('s.reservation_expires_at' in v_src) = 0 THEN
    RAISE EXCEPTION '0292 P1: the arm now has % expires_at references. If it started testing '
                    'a PROPOSAL expiry, the published fact is answering a narrower question '
                    'than the kernel asks and must be widened to match', v_n;
  END IF;
  RAISE NOTICE '0292 P1: the arm''s clause is unchanged, and still expiry-blind on proposals';
END $p1$;

-- P2. THE forces_recert=false ARGUMENT, RE-MEASURED --------------------------
DO $p2$
DECLARE v_global int; v_src text;
BEGIN
  SELECT count(*) INTO v_global FROM public.ottoq_policy_params
   WHERE param_key = 'proposer_frame_facts' AND scope_type = 'global';
  IF v_global <> 0 THEN
    RAISE EXCEPTION '0292 P2: a GLOBAL proposer_frame_facts row exists (% of them). A cert arm '
                    'would then see the facts block and this file WOULD force a recert', v_global;
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame' AND p.pronargs = 2;
  IF position('ottoq_policy_get(p_sim_run_id, ''proposer_frame_facts'', 0), 0)::int AS facts' in v_src) = 0 THEN
    RAISE EXCEPTION '0292 P2: the frame''s facts gate is no longer COALESCE(policy_get(...,0),0). '
                    'The forces_recert=false argument rests on that default being 0';
  END IF;
  RAISE NOTICE '0292 P2: no global facts row, caller default still 0 -- a cert arm sees facts=0';
END $p2$;

-- P3. NOT ALREADY APPLIED ----------------------------------------------------
DO $p3$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame' AND p.pronargs = 2;
  IF position('''facts_version'', 2' in v_src) = 0 THEN
    RAISE EXCEPTION '0292 P3: the frame does not declare facts_version 2; this file bumps 2 -> 3';
  END IF;
  IF position('has_live_holds_tick_proposal' in v_src) > 0 THEN
    RAISE EXCEPTION '0292 P3: the frame already publishes has_live_holds_tick_proposal';
  END IF;
  RAISE NOTICE '0292 P3: at facts_version 2, the new key absent';
END $p3$;

-- P4. THE FACTS-OFF FRAME IS STABLE ENOUGH TO DIGEST -------------------------
-- Three cron jobs touch this database, so a digest taken once proves nothing.
-- Take it TWICE and refuse if the world moved between them; A1 then requires
-- the post-replace digest to equal it.
CREATE TEMP TABLE IF NOT EXISTS t0292_baseline (k text primary key, v text);
DO $p4$
DECLARE v_a text; v_b text; v_depot uuid := '11111111-1111-1111-1111-111111111111'::uuid;
BEGIN
  SELECT md5(public.ottoq_build_decision_frame(v_depot, NULL)::text) INTO v_a;
  SELECT md5(public.ottoq_build_decision_frame(v_depot, NULL)::text) INTO v_b;
  IF v_a IS NULL OR v_a <> v_b THEN
    RAISE EXCEPTION '0292 P4: the facts-off frame changed between two reads (% vs %). '
                    'A digest comparison across the replace would be meaningless; wait for a '
                    'quiet moment and re-run', v_a, v_b;
  END IF;
  DELETE FROM t0292_baseline WHERE k IN ('facts_off','arm_md5');
  INSERT INTO t0292_baseline VALUES ('facts_off', v_a);
  --: and the arm's own digest, so A4 can prove this file did not touch the
  --: decide path rather than merely asserting it did not.
  INSERT INTO t0292_baseline
  SELECT 'arm_md5', md5(pg_get_functiondef(p.oid))
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_first_refusal_arm';
  IF NOT EXISTS (SELECT 1 FROM t0292_baseline WHERE k = 'arm_md5') THEN
    RAISE EXCEPTION '0292 P4: could not digest ottoq_cuopt_first_refusal_arm';
  END IF;
  RAISE NOTICE '0292 P4: facts-off frame digest % is stable across two reads', v_a;
END $p4$;

-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- A1. THE FACTS-OFF FRAME IS BYTE-IDENTICAL. This is the forces_recert=false
--     evidence, and it is a digest rather than an argument.
DO $a1$
DECLARE v_now text; v_was text; v_depot uuid := '11111111-1111-1111-1111-111111111111'::uuid;
BEGIN
  SELECT v INTO v_was FROM t0292_baseline WHERE k = 'facts_off';
  SELECT md5(public.ottoq_build_decision_frame(v_depot, NULL)::text) INTO v_now;
  IF v_was IS NULL THEN
    RAISE EXCEPTION 'A1 FAILED: P4 recorded no baseline, so there is nothing to compare';
  END IF;
  IF v_now <> v_was THEN
    RAISE EXCEPTION 'A1 FAILED: the facts-off frame changed (% -> %). A certification arm '
                    'builds exactly that frame, so this file WOULD force a recert and its '
                    'lineage classification is wrong', v_was, v_now;
  END IF;
  RAISE NOTICE 'A1 OK: facts-off frame unchanged at %', v_now;
END $a1$;

-- A2. THE FACTS-ON FRAME CARRIES THE NEW KEYS AND SAYS SO.
DO $a2$
DECLARE
  v_run uuid := '91139ad8-441c-4c68-8f03-b00f15a89cdd'::uuid;
  v_depot uuid := '11111111-1111-1111-1111-111111111111'::uuid;
  v_frame jsonb; v_ver int; v_srcs jsonb; v_missing int;
BEGIN
  v_frame := public.ottoq_build_decision_frame(v_depot, v_run);
  v_ver := (v_frame->'selector'->>'facts_version')::int;
  IF v_ver <> 3 THEN
    RAISE EXCEPTION 'A2 FAILED: facts_version is %, expected 3', v_ver;
  END IF;
  v_srcs := v_frame->'selector'->'holds_tick_sources';
  IF v_srcs IS NULL OR jsonb_array_length(v_srcs) <> (SELECT count(*) FROM public.ottoq_proposer_precedence WHERE holds_tick) THEN
    RAISE EXCEPTION 'A2 FAILED: holds_tick_sources is %, which does not match the % rows in '
                    'ottoq_proposer_precedence', v_srcs,
                    (SELECT count(*) FROM public.ottoq_proposer_precedence WHERE holds_tick);
  END IF;
  SELECT count(*) INTO v_missing FROM jsonb_array_elements(v_frame->'vehicles') e
   WHERE NOT (e ? 'has_live_holds_tick_proposal') OR NOT (e ? 'live_holds_tick_proposal_sources');
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'A2 FAILED: % vehicles in the facts-on frame are missing the new keys', v_missing;
  END IF;
  RAISE NOTICE 'A2 OK: facts_version 3, holds_tick_sources %, every vehicle carries both keys', v_srcs;
END $a2$;

-- A3. THE PUBLISHED FACT AGREES WITH THE KERNEL, VEHICLE BY VEHICLE.
--
-- The assertion this whole file exists for. It evaluates the ARM'S clause
-- independently, against the same vehicle population the frame uses, and
-- requires zero disagreements. If the copy in the frame had drifted from the
-- original by so much as the expiry test, this would catch it.
--
-- AND IT REFUSES TO PASS VACUOUSLY. A comparison where every answer is false on
-- both sides proves nothing -- it is satisfied by a fact hard-coded to false.
-- Run 91139ad8 has 4 pending holds_tick proposals on 4 distinct vehicles, so at
-- least one true is required and the number is checked, not assumed.
DO $a3$
DECLARE
  v_run uuid := '91139ad8-441c-4c68-8f03-b00f15a89cdd'::uuid;
  v_depot uuid := '11111111-1111-1111-1111-111111111111'::uuid;
  v_frame jsonb; v_disagree int; v_true int; v_vehicles int; v_detail text;
BEGIN
  v_frame := public.ottoq_build_decision_frame(v_depot, v_run);
  WITH published AS (
    SELECT (e->>'id')::uuid AS vehicle_id,
           (e->>'has_live_holds_tick_proposal')::boolean AS said
      FROM jsonb_array_elements(v_frame->'vehicles') e
  ), kernel AS (
    SELECT p.vehicle_id, p.said,
           EXISTS (SELECT 1 FROM public.ottoq_external_proposals ep
                    WHERE ep.sim_run_id     = v_run
                      AND ep.action_context = 'stall_assignment'
                      AND ep.entity_type    = 'vehicle'
                      AND ep.entity_id      = p.vehicle_id
                      AND ep.status         = 'pending'
                      AND ep.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp
                                         WHERE pp.holds_tick)) AS truth
      FROM published p
  )
  SELECT count(*), count(*) FILTER (WHERE said <> truth), count(*) FILTER (WHERE truth),
         string_agg(vehicle_id::text || ' said=' || said || ' truth=' || truth, ', ')
           FILTER (WHERE said <> truth)
    INTO v_vehicles, v_disagree, v_true, v_detail
    FROM kernel;
  IF v_vehicles = 0 THEN
    RAISE EXCEPTION 'A3 FAILED: the frame reported no vehicles, so nothing was compared';
  END IF;
  IF v_disagree > 0 THEN
    RAISE EXCEPTION 'A3 FAILED: the published fact disagrees with the kernel''s own clause on '
                    '% of % vehicles: %', v_disagree, v_vehicles, v_detail;
  END IF;
  IF v_true = 0 THEN
    RAISE EXCEPTION 'A3 FAILED: not one of the % vehicles has a live pending holds_tick '
                    'proposal, so the agreement is vacuous -- a fact hard-coded to false would '
                    'pass this. Run 91139ad8 had 4 when this file was written; pick a run that '
                    'still does', v_vehicles;
  END IF;
  RAISE NOTICE 'A3 OK: % vehicles compared against the arm''s own clause, 0 disagreements, '
               '% of them genuinely held', v_vehicles, v_true;
END $a3$;

-- A4. NOTHING DISPOSES DIFFERENTLY.
--
-- The first draft of this assertion could not fail: it checked that the file
-- had not snapshotted the arm, which is a statement about the file, not about
-- the database. Replaced with a digest taken in P4 and compared here, so it
-- would actually catch this file changing the decide path.
DO $a4$
DECLARE v_was text; v_now text;
BEGIN
  SELECT v INTO v_was FROM t0292_baseline WHERE k = 'arm_md5';
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_now
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_first_refusal_arm';
  IF v_was IS NULL OR v_now IS NULL THEN
    RAISE EXCEPTION 'A4 FAILED: no arm digest to compare (before %, after %)', v_was, v_now;
  END IF;
  IF v_was <> v_now THEN
    RAISE EXCEPTION 'A4 FAILED: ottoq_cuopt_first_refusal_arm changed during this file '
                    '(% -> %). This file publishes a COPY of the arm''s clause and must not '
                    'touch the arm itself', v_was, v_now;
  END IF;
  RAISE NOTICE 'A4 OK: the decide path is byte-identical at %; only the frame changed', v_now;
END $a4$;

DROP TABLE IF EXISTS t0292_baseline;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0292_the_proposer_cannot_see_its_own_pending_plans', false,
 'G60. public.ottoq_build_decision_frame gains two vehicle facts at facts_version 3: has_live_holds_tick_proposal and live_holds_tick_proposal_sources, plus holds_tick_sources on the selector so the consumer reads the source vocabulary from the publisher instead of keeping its own copy. The boolean is a VERBATIM COPY of the clause in public.ottoq_cuopt_first_refusal_arm that already declines to open a first-refusal seat for a vehicle with a live pending proposal from a holds_tick source -- (stall_assignment, vehicle, pending, holds_tick), run-scoped, and deliberately EXPIRY-BLIND because the arm is; publishing a narrower question than the kernel asks is the G54 defect and P1 pins the arm''s clause including the absence of a proposal expiry test. Measured on run 91139ad8 (the first run on the tick-following loop): 26 of 48 forward_lex proposals had an earlier holds_tick proposal for the same vehicle, and 35 of 48 ended superseded across only 18 vehicles, against 23 proposals and ZERO such rows on the timer-driven run 36e5cc68 at the same seed. 26 is an UPPER bound and the exact number is unrecoverable -- ottoq_external_proposals.status is current, not historised, with no resolved_at column -- so the real evidence must be a live before/after, not archaeology. Nothing disposes differently: the arm, the decide path and the proposal lifecycle are untouched, and behaviour changes only once proposer/forward_proposer.py consumes the key. A1 is the forces_recert=false evidence as a digest rather than an argument: the facts-off frame is byte-identical across the replace, taken twice before to prove it was stable enough to compare. A3 evaluates the arm''s clause independently over the same vehicle population and requires zero disagreements AND at least one genuine true, so a fact hard-coded to false cannot pass it.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

-- ===========================================================================
-- APPLIED 20260914090954. P-, P0-P4 and A1-A4 all passed.
--
-- Verified read-only afterwards, against run 91139ad8 at the flagship depot:
--
--   selector.facts_version            3
--   selector.holds_tick_sources       ["cuopt","cuopt_fallback","forward_lex","llm_advisor"]
--   vehicles in the frame             116
--   has_live_holds_tick_proposal      4    -- exactly the 4 pending rows that
--                                             run still carries, on 4 distinct
--                                             vehicles
--   facts-off frame has a selector    false  -- the block is still gated
--   ottoq_cuopt_first_refusal_arm     6fcb5196eb947a83afa44380d24bec65,
--                                     unchanged across the whole file
--   cert lineage forces_recert        false
--
-- A3 is the one that carries weight: 116 vehicles compared, published fact
-- against an independent evaluation of the arm's own clause, ZERO
-- disagreements, and 4 of them genuinely held -- so the agreement is not the
-- vacuous kind a constant false would produce.
--
-- NOTHING HAS CHANGED YET IN BEHAVIOUR, and that is by design. The frame now
-- carries the fact; proposer/forward_proposer.py does not read it. Until that
-- lands, this file is publication only. The claim to make after it does is a
-- live before/after on a new run -- fewer proposals for the same or more
-- enactments -- and NOT the 26-of-48 figure, which is an upper bound over
-- history that cannot be turned into a count of avoided work.
-- ===========================================================================
