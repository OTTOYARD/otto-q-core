-- migration-version: PENDING
-- migration-name:    0287_the_two_halves_disagree_about_what_already_placed_means
--
-- 0287  THE FRAME PUBLISHES WHICH KIND OF PLACE, AND WHOSE LEDGER SAYS SO
--
-- Evidence: db/checks/0221. Run c288555a, 19 first-refusal holds, 0 answered,
-- and the cause is not that the proposer left -- it fired eight times, armed,
-- on schedule. The two halves disagree about what "already has a place" means:
--
--   ottoq_cuopt_first_refusal_arm   unplaced unless a live reservation on a
--                                   DCFC or L2 stall
--   vehicle_is_held (forward_lex)   placed if ANY reservation or ANY
--                                   held/active booking, ANY stall type
--
-- So the kernel holds a seat open for exactly the population the proposer has
-- decided not to look at. 18 of the 19 held vehicles were carrying nothing but
-- a STAGING booking -- temp_hold, perimeter_hold, inspect -- which is a parking
-- spot, not a service assignment.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS FILE CHANGES, AND WHAT IT DELIBERATELY DOES NOT
--
-- CHANGES: ottoq_build_decision_frame publishes the FACTS the proposer needs to
-- tell the two apart, inside the block proposer_frame_facts already gates:
--
--   reserved_stall_type        the type of the reserved stall, or NULL
--   live_booking_stall_types   the distinct stall types of its held/active
--                              bookings, sorted, or []
--   holds_charge_reservation   a live reservation on a dcfc/l2 stall
--                              -- THE KERNEL'S LEDGER
--   holds_charge_booking       a held/active booking on a dcfc/l2 stall
--                              -- THE CALENDAR'S LEDGER
--   holds_charge_place         the UNION of the two
--
-- and selector.facts_version goes 1 -> 2, with charge_stall_types beside it so
-- the consumer can read WHICH types the publisher counted rather than assuming.
--
-- UNION, NOT INTERSECTION, and 0221 section B is why. The two ledgers do not
-- agree: of the four charge bookings covering a hold's arm instant, released_at
-- says exactly one was still live -- a1111111, a vehicle the KERNEL called
-- unplaced while the calendar said it held an L2. Taking the union keeps that
-- one correctly skipped and frees the other eighteen. Intersection would have
-- handed a1111111 a second place.
--
-- DOES NOT CHANGE: the decide path. ottoq_cuopt_first_refusal_arm keeps its own
-- predicate and its own literal. One vehicle is thin evidence for editing the
-- decide path, and the honest move is to publish both ledgers so the
-- disagreement is visible instead of silent (filed G56). P1 PINS that literal,
-- so if the arm predicate's charge-type list ever changes, this file's
-- derivation is stale and it refuses to apply.
--
-- DOES NOT CHANGE: has_live_booking and reserved_stall_id keep their exact
-- version-1 meaning. A2 recomputes reserved_stall_id with the ORIGINAL scalar
-- expression and requires it equal the new lateral's answer for every vehicle
-- at the flagship depot, so the refactor is proven, not asserted.
--
-- ---------------------------------------------------------------------------
-- THE RANGE, READ OFF THE CONSUMER (the 0282 rule, applied to a list)
--
-- The charge-type list is NOT chosen here. It is read off
-- public.ottoq_cuopt_first_refusal_arm:
--
--     AND s.stall_type::text IN ('dcfc','l2')
--
-- The site has five stall types -- dcfc, l2, service_bay, staging, wash_bay --
-- and only the first two disqualify a vehicle from a first-refusal seat. The
-- proposer independently assigns only charge stalls (its charge_kinds gate), so
-- both consumers agree on the list; what they disagreed about was whether the
-- OTHER three types count. They do not.
--
-- ---------------------------------------------------------------------------
-- ONE LATENT TRAP CLOSED ON THE WAY PAST, AND IT IS NOT A LIVE BUG TODAY
--
-- All three facts blocks are gated `CASE WHEN g.facts = 1` -- an EQUALITY.
-- Setting proposer_frame_facts to 2, the obvious way to ask for "more facts",
-- would turn the whole block OFF and hand the proposer a blind frame, which
-- 0218 taught the loop to refuse. It cannot happen through ottoq_policy_set
-- today, because the catalog declares max_value 1 (A4 proves the clamp), but
-- it can happen through a direct INSERT -- and 0286 found a live row written
-- exactly that way. This file widens all three gates to `>= 1`. Every live row
-- is 1, so nothing changes today; A4 proves the widened gate would also honour
-- a 2 written around the setter.
--
-- The dial stays a GATE with max 1. The contract version lives in
-- selector.facts_version, which is a property of this function, not a dial --
-- so the catalog ceiling is not widened and must not be.
--
-- ---------------------------------------------------------------------------
-- forces_recert = false, AND THE ARGUMENT IS MEASURABLE
--
-- proposer_frame_facts has NO global row and the function's own default is 0
-- (P3 asserts both). A certification arm sets no policy rows for it, so
-- g.facts = 0, so every block this file touches evaluates to '{}'::jsonb and
-- the frame a cert arm sees is byte-identical to the one it saw before. A1
-- proves that directly: the whole frame, built with facts off, digests the same
-- before and after.
--
-- The one caller inside a certified path is ottoq_capture_decision_snapshot,
-- whose content_hash is NOT one of the fourteen enforced atoms (CLAUDE.md 2.9a)
-- and which, with facts off, receives an unchanged frame regardless.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0287 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0287 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0287 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0287 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P0. THE FRAME IS THE ONE THIS FILE WAS WRITTEN AGAINST ---------------------
DO $p0$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame' AND p.pronargs = 2;
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0287 P0: public.ottoq_build_decision_frame(uuid,uuid) does not exist';
  END IF;
  IF position('''facts_version'', 1' in v_src) = 0 THEN
    RAISE EXCEPTION '0287 P0: the frame does not declare facts_version 1; this file '
                    'bumps 1 -> 2 and must not run against another version';
  END IF;
  IF position('''reserved_stall_id''' in v_src) = 0
     OR position('''has_live_booking''' in v_src) = 0 THEN
    RAISE EXCEPTION '0287 P0: the two 0265 vehicle facts are not both present; this '
                    'file extends them and does not invent them';
  END IF;
  IF position('CASE WHEN g.facts = 1 THEN' in v_src) = 0 THEN
    RAISE EXCEPTION '0287 P0: the facts gate is no longer written as an equality; the '
                    'widening this file performs was derived from that shape';
  END IF;
  RAISE NOTICE '0287 P0: frame is at facts_version 1 with both 0265 facts and an = 1 gate';
END $p0$;

-- P1. THE CHARGE-TYPE LIST, READ OFF THE KERNEL'S OWN PREDICATE --------------
-- This is the whole derivation. If the decide path ever counts a third type as
-- a charge place, ('dcfc','l2') here is stale and this file must be re-read.
DO $p1$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_first_refusal_arm';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0287 P1: public.ottoq_cuopt_first_refusal_arm does not exist';
  END IF;
  IF position('s.stall_type::text IN (''dcfc'',''l2'')' in v_src) = 0 THEN
    RAISE EXCEPTION '0287 P1: the arm predicate no longer disqualifies exactly '
                    'dcfc and l2; holds_charge_* is derived from that list and '
                    'must be re-read off the new one';
  END IF;
  IF position('s.reserved_by = v.id' in v_src) = 0 THEN
    RAISE EXCEPTION '0287 P1: the arm predicate no longer reads stalls.reserved_by; '
                    'holds_charge_reservation is a publication of that expression';
  END IF;
  RAISE NOTICE '0287 P1: the kernel still reads reserved_by and still means dcfc + l2';
END $p1$;

-- P2. THE SITE STILL HAS MORE THAN CHARGE STALLS -----------------------------
-- If every stall were a charge stall the two predicates would be equivalent and
-- this file would be pointless. It is not: 0221 measured 18 staging holds.
DO $p2$
DECLARE v_types text[]; v_staging int;
BEGIN
  SELECT array_agg(DISTINCT stall_type::text ORDER BY stall_type::text) INTO v_types
    FROM public.stalls;
  IF NOT (v_types @> ARRAY['dcfc','l2','staging']) THEN
    RAISE EXCEPTION '0287 P2: the site no longer has all of dcfc, l2 and staging (%)',
                    v_types;
  END IF;
  SELECT count(*) INTO v_staging FROM public.stalls
   WHERE stall_type::text NOT IN ('dcfc','l2');
  IF v_staging = 0 THEN
    RAISE EXCEPTION '0287 P2: every stall is a charge stall, so the two predicates '
                    'are equivalent and this file changes nothing';
  END IF;
  RAISE NOTICE '0287 P2: % non-charge stalls exist; the distinction is real', v_staging;
END $p2$;

-- P3. THE forces_recert=false ARGUMENT, AS A PRECONDITION --------------------
DO $p3$
DECLARE v_global int; v_nonone int; v_src text;
BEGIN
  SELECT count(*) INTO v_global FROM public.ottoq_policy_params
   WHERE param_key = 'proposer_frame_facts' AND scope_type = 'global';
  IF v_global > 0 THEN
    RAISE EXCEPTION '0287 P3: a GLOBAL proposer_frame_facts row exists, so a '
                    'certification arm would see the facts block and the '
                    'forces_recert=false argument does not hold';
  END IF;
  SELECT count(*) INTO v_nonone FROM public.ottoq_policy_params
   WHERE param_key = 'proposer_frame_facts' AND param_value <> 1;
  IF v_nonone > 0 THEN
    RAISE EXCEPTION '0287 P3: % live proposer_frame_facts row(s) are not 1; the '
                    'claim that widening = 1 to >= 1 changes nothing today is false',
                    v_nonone;
  END IF;
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame' AND p.pronargs = 2;
  IF position('''proposer_frame_facts'', 0)' in v_src) = 0 THEN
    RAISE EXCEPTION '0287 P3: the frame no longer defaults proposer_frame_facts to 0; '
                    'a cert arm would then see facts and this file would force recert';
  END IF;
  RAISE NOTICE '0287 P3: no global row, every live row is 1, the default is still 0';
END $p3$;

-- P4. CAPTURE THE FACTS-OFF FRAME BEFORE THE CHANGE --------------------------
-- A1 and A5 compare against this. The scratch run id has no policy rows, so
-- ottoq_policy_get falls through to the function default of 0.
--
-- CARRIED IN A SESSION GUC, not a temp table, and the reason is a real hazard:
-- a temp table created with ON COMMIT DROP vanishes at the end of the statement
-- when the caller does NOT wrap the file in an explicit transaction, and one
-- created without it survives into a pooled connection and collides on a
-- re-run. set_config(..., is_local => false) has neither failure mode: it
-- persists for the session across commits and dies with the connection, and it
-- is not DDL, so this file creates and destroys nothing.
--
-- AND THE INSTRUMENT IS CHECKED BEFORE IT IS USED. A1 compares a digest taken
-- here against one taken after the replace, so it silently assumes the world
-- did not move in between -- and three cron jobs are active on this database
-- (ottoq-depot-tick every 2 min, ottoq-demo-metronome every minute,
-- ottoq-run-governor every 2 min). With no run in flight they should no-op, but
-- "should" is not a measurement: P4 digests the frame TWICE and refuses to
-- continue if the two disagree. A moving world makes A1 inconclusive, not
-- wrong, and an inconclusive assertion that reports PASS is the defect class
-- this whole repo exists to avoid.
DO $p4$
DECLARE v_md5 text; v_md5b text;
BEGIN
  v_md5 := md5(public.ottoq_build_decision_frame(
                 '11111111-1111-1111-1111-111111111111'::uuid,
                 '00000000-0000-0000-0000-0000028700bb'::uuid)::text);
  v_md5b := md5(public.ottoq_build_decision_frame(
                  '11111111-1111-1111-1111-111111111111'::uuid,
                  '00000000-0000-0000-0000-0000028700bb'::uuid)::text);
  IF v_md5 IS NULL THEN
    RAISE EXCEPTION '0287 P4: could not digest the facts-off frame';
  END IF;
  IF v_md5 IS DISTINCT FROM v_md5b THEN
    RAISE EXCEPTION '0287 P4: two back-to-back builds of the SAME facts-off frame '
                    'already disagree (% vs %). Something is mutating depot state '
                    'right now, so A1 could not tell a real change from drift. '
                    'Quiesce and re-apply.', left(v_md5,12), left(v_md5b,12);
  END IF;
  PERFORM set_config('ottoq.m0287_before', v_md5, false);
  RAISE NOTICE '0287 P4: facts-off frame stable across two builds, digested (%)',
               left(v_md5,12);
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
        'holds_charge_place', (COALESCE(rsv.is_charge, false) OR COALESCE(bkg.has_charge, false))
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
    'selector', jsonb_build_object('facts_version', 2, 'clock', g.clk,
                                   'heartbeat_window_s', 90,
                                   'charge_stall_types', jsonb_build_array('dcfc','l2'),
                                   'authority', 'public.ottoq_l2_external_proposal')
  ) ELSE '{}'::jsonb END
  FROM g;
$function$;

COMMENT ON FUNCTION public.ottoq_build_decision_frame(uuid, uuid) IS
'0287: the decision frame. Gated by proposer_frame_facts (>= 1), the vehicle
block carries five place-facts -- reserved_stall_type, live_booking_stall_types,
holds_charge_reservation (the reservation ledger), holds_charge_booking (the
booking calendar) and their union holds_charge_place -- so a consumer can tell a
staging parking spot from a charge assignment. Before 0287 the two facts were
type-blind and the proposer skipped exactly the vehicles the kernel was holding
a first-refusal seat for (db/checks/0221). selector.facts_version = 2.';

-- ---------------------------------------------------------------------------
-- A1. WITH FACTS OFF, THE FRAME IS BYTE-IDENTICAL TO THE ONE BEFORE THE CHANGE.
-- This is the forces_recert=false argument, executed rather than argued.
DO $a1$
DECLARE v_before text; v_after text;
BEGIN
  v_before := NULLIF(current_setting('ottoq.m0287_before', true), '');
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'A1 FAILED: P4 did not record a before-digest, so this assertion '
                    'would pass vacuously. Run the file as one session.';
  END IF;
  v_after := md5(public.ottoq_build_decision_frame(
                   '11111111-1111-1111-1111-111111111111'::uuid,
                   '00000000-0000-0000-0000-0000028700bb'::uuid)::text);
  IF v_before IS DISTINCT FROM v_after THEN
    RAISE EXCEPTION 'A1 FAILED: the facts-off frame changed (% -> %). A certification '
                    'arm would see a different frame and this file DOES force recert',
                    left(v_before,12), left(v_after,12);
  END IF;
  RAISE NOTICE 'A1 OK: facts-off frame unchanged (%), so a cert arm sees nothing new',
               left(v_after,12);
END $a1$;

-- A2. WITH FACTS ON, THE NEW KEYS APPEAR, THE VERSION IS 2, AND THE REFACTORED
--     reserved_stall_id STILL EQUALS THE ORIGINAL SCALAR EXPRESSION.
DO $a2$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028700bb'::uuid;
        v_depot uuid := '11111111-1111-1111-1111-111111111111'::uuid;
        v_frame jsonb; v_n int; v_mismatch int; v_clk timestamptz;
BEGIN
  INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
  VALUES ('run', v_scratch, 'proposer_frame_facts', 1, '0287_proof', now())
  ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
    SET param_value = 1, updated_by = '0287_proof', updated_at = now();

  v_frame := public.ottoq_build_decision_frame(v_depot, v_scratch);

  IF (v_frame->'selector'->>'facts_version')::int <> 2 THEN
    RAISE EXCEPTION 'A2 FAILED: facts_version is %, expected 2',
                    v_frame->'selector'->>'facts_version';
  END IF;
  IF v_frame->'selector'->'charge_stall_types' <> jsonb_build_array('dcfc','l2') THEN
    RAISE EXCEPTION 'A2 FAILED: charge_stall_types is %, expected ["dcfc","l2"]',
                    v_frame->'selector'->'charge_stall_types';
  END IF;

  SELECT count(*) INTO v_n FROM jsonb_array_elements(v_frame->'vehicles') e
   WHERE e ? 'holds_charge_place' AND e ? 'holds_charge_reservation'
     AND e ? 'holds_charge_booking' AND e ? 'reserved_stall_type'
     AND e ? 'live_booking_stall_types' AND e ? 'reserved_stall_id'
     AND e ? 'has_live_booking';
  IF v_n <> jsonb_array_length(v_frame->'vehicles') OR v_n = 0 THEN
    RAISE EXCEPTION 'A2 FAILED: only % of % vehicles carry all seven place-facts',
                    v_n, jsonb_array_length(v_frame->'vehicles');
  END IF;

  --: THE REFACTOR, PROVEN. reserved_stall_id now comes from a lateral; recompute
  --: it here with the ORIGINAL correlated scalar expression and require equality
  --: for every vehicle. A refactor nobody checked is a rewrite.
  SELECT COALESCE((SELECT r.sim_clock_current FROM public.ottoq_sim_runs r
                    WHERE r.sim_run_id = v_scratch), now()) INTO v_clk;
  SELECT count(*) INTO v_mismatch
    FROM jsonb_array_elements(v_frame->'vehicles') e
    JOIN public.vehicles v ON v.id = (e->>'id')::uuid
   WHERE (e->>'reserved_stall_id') IS DISTINCT FROM
         (SELECT s2.id::text FROM public.stalls s2
           WHERE s2.depot_id = v_depot AND s2.reserved_by = v.id
             AND COALESCE(s2.reservation_expires_at, 'infinity'::timestamptz) > v_clk
           ORDER BY s2.id LIMIT 1);
  IF v_mismatch > 0 THEN
    RAISE EXCEPTION 'A2 FAILED: the lateral disagrees with the original expression '
                    'for % vehicle(s)', v_mismatch;
  END IF;
  RAISE NOTICE 'A2 OK: version 2, seven facts on all % vehicles, lateral matches the '
               'original expression exactly', v_n;
END $a2$;

-- A3. THE UNION IS A UNION, AND THE TYPE FILTER ACTUALLY FILTERS.
DO $a3$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028700bb'::uuid;
        v_frame jsonb; v_bad int; v_typed int;
BEGIN
  v_frame := public.ottoq_build_decision_frame(
               '11111111-1111-1111-1111-111111111111'::uuid, v_scratch);

  SELECT count(*) INTO v_bad FROM jsonb_array_elements(v_frame->'vehicles') e
   WHERE (e->>'holds_charge_place')::boolean
         IS DISTINCT FROM ((e->>'holds_charge_reservation')::boolean
                           OR (e->>'holds_charge_booking')::boolean);
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'A3 FAILED: holds_charge_place is not the union of the two '
                    'ledgers for % vehicle(s)', v_bad;
  END IF;

  --: THE POINT OF THE WHOLE FILE: a vehicle may hold a place and NOT hold a
  --: charge place. If that count is zero at this depot the facts are
  --: indistinguishable from the version-1 ones and prove nothing, so say so
  --: rather than passing quietly.
  SELECT count(*) INTO v_typed FROM jsonb_array_elements(v_frame->'vehicles') e
   WHERE ((e->>'reserved_stall_id') IS NOT NULL OR (e->>'has_live_booking')::boolean)
     AND NOT (e->>'holds_charge_place')::boolean;
  IF v_typed = 0 THEN
    RAISE WARNING '0287 A3: no vehicle at this depot currently holds a NON-charge '
                  'place, so the new facts happen to agree with the old ones right '
                  'now. The union and the type filter are still proven above; this '
                  'is a statement about the depot at this instant, not about the '
                  'change. db/checks/0221 measured 18 such vehicles during a run.';
  ELSE
    RAISE NOTICE 'A3 OK: % vehicle(s) hold a place that is NOT a charge place -- '
                 'exactly the population version 1 could not express', v_typed;
  END IF;
  RAISE NOTICE 'A3 OK: holds_charge_place is the union for every vehicle';
END $a3$;

-- A4. THE GATE. The setter cannot reach 2 (the catalog clamps), and a 2 written
--     around the setter now still yields facts instead of a blind frame.
DO $a4$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028700bb'::uuid;
        v_r jsonb; v_frame jsonb;
BEGIN
  v_r := public.ottoq_policy_set('run', v_scratch, 'proposer_frame_facts', 2, '0287_proof');
  IF COALESCE((v_r->>'applied')::numeric, -1) <> 1
     OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
    RAISE EXCEPTION 'A4 FAILED: the setter should clamp 2 to 1 and say so: %', v_r;
  END IF;

  --: Around the setter, the way 0286 found a live row had been written.
  UPDATE public.ottoq_policy_params SET param_value = 2, updated_by = '0287_proof'
   WHERE scope_type = 'run' AND scope_id = v_scratch AND param_key = 'proposer_frame_facts';
  v_frame := public.ottoq_build_decision_frame(
               '11111111-1111-1111-1111-111111111111'::uuid, v_scratch);
  IF v_frame->'selector' IS NULL THEN
    RAISE EXCEPTION 'A4 FAILED: a value of 2 still produces a BLIND frame; the gate '
                    'was not widened';
  END IF;
  IF (v_frame->'selector'->>'facts_version')::int <> 2 THEN
    RAISE EXCEPTION 'A4 FAILED: facts present but version is %',
                    v_frame->'selector'->>'facts_version';
  END IF;
  RAISE NOTICE 'A4 OK: setter clamps 2 to 1; a 2 written around it no longer blinds '
               'the frame';
END $a4$;

-- A5. FACTS OFF IS STILL OFF, AND THE SCRATCH IS GONE.
DO $a5$
DECLARE v_scratch uuid := '00000000-0000-0000-0000-0000028700bb'::uuid;
        v_n int; v_frame jsonb; v_before text; v_after text;
BEGIN
  DELETE FROM public.ottoq_policy_params WHERE updated_by = '0287_proof';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A5 FAILED: expected to remove exactly 1 scratch row, removed %', v_n;
  END IF;

  v_frame := public.ottoq_build_decision_frame(
               '11111111-1111-1111-1111-111111111111'::uuid, v_scratch);
  IF v_frame ? 'selector' THEN
    RAISE EXCEPTION 'A5 FAILED: the frame still carries a selector block with the '
                    'gate removed';
  END IF;
  v_before := NULLIF(current_setting('ottoq.m0287_before', true), '');
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'A5 FAILED: no before-digest recorded; this assertion would pass '
                    'vacuously';
  END IF;
  v_after := md5(v_frame::text);
  IF v_before IS DISTINCT FROM v_after THEN
    RAISE EXCEPTION 'A5 FAILED: the facts-off frame is not what it was before the '
                    'scratch row existed (% vs %)', left(v_before,12), left(v_after,12);
  END IF;
  RAISE NOTICE 'A5 OK: scratch removed, facts-off frame back to its original digest';
END $a5$;


-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0287_the_two_halves_disagree_about_what_already_placed_means', false,
 'ottoq_build_decision_frame publishes five vehicle place-facts inside the existing proposer_frame_facts block -- reserved_stall_type, live_booking_stall_types, holds_charge_reservation (stalls.reserved_by, the kernel ledger), holds_charge_booking (ottoq_stall_bookings, the calendar) and their UNION holds_charge_place -- and selector.facts_version goes 1 to 2 with charge_stall_types beside it. Evidence db/checks/0221: on run c288555a the kernel armed 19 first-refusal seats and the proposer answered none, because vehicle_is_held treated ANY reservation or booking of ANY stall type as a place while ottoq_cuopt_first_refusal_arm disqualifies only a live dcfc/l2 reservation; 18 of the 19 carried nothing but a staging temp_hold. The dcfc/l2 list is READ OFF the arm predicate and P1 pins that literal. UNION not intersection because the two ledgers genuinely disagree -- 0221 found one vehicle the kernel called unplaced while the calendar held an L2 for it (filed G56); the union keeps that one skipped. The decide path is NOT touched. has_live_booking and reserved_stall_id keep their version-1 meaning and A2 proves the refactored reserved_stall_id equals the original scalar expression for every vehicle. All three facts gates widened from = 1 to >= 1: a latent trap where turning the dial up to 2 turned the block off entirely, currently masked by the catalog ceiling of 1 (A4 proves both halves). forces_recert=false is EXECUTED, not argued: A1 digests the whole facts-off frame before and after the replace and requires equality, and P3 asserts there is no global proposer_frame_facts row and the function default is still 0, so a certification arm sees an unchanged frame.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
