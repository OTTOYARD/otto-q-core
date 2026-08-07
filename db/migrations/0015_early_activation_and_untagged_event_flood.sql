-- migration-version: 20260807013120
-- migration-name:    early_activation_and_untagged_event_flood
--
-- ============================================================================
-- 0015  EARLY ACTIVATION (Vehicle-First) + STOP THE UNTAGGED EVENT FLOOD
-- ============================================================================
--
-- PART A -- A READY CAR NEVER WAITS ON A FORECAST.
--
--   The brief said: "0011 makes the return signal reserve a bay ~30 sim-min before
--   arrival. 26 holds created, 0 bound", cause = "the reserved window and the
--   vehicle's readiness are essentially uncorrelated".
--
--   The window gate is real and it is in ottoq_activate_due_bay_reservations:
--       AND lower(b.during) <= p_clock
--   but it is NOT what killed those 26 holds, and fixing it ALONE would not have
--   bound a single one. Read from the 0014 witness table, not from a source filter:
--
--       old_source='return_signal_prearrival', held -> released, inside_window=FALSE : 21
--       old_source='return_signal_prearrival', held -> superseded, inside_window=F   :  2
--
--   Every one of them died OUTSIDE its own window -- i.e. before the window ever
--   opened, so activation never got a turn. The killer is named in the reconcile
--   ledger (public.bay_reservation_reconcile_2026_08_02, 30-day window):
--
--       released  replanned_no_window       (all blockers)            : 96
--       released  replanned_defer_cap       deploy_gate:need_service  :  3
--       deferred  vehicle_not_yet_releasable deploy_gate:need_service : 52  (+10 relocated)
--
--   and ottoq_decide_tick calls them in this order:
--       line 39  ottoq_activate_present_bookings
--       line 45  ottoq_reconcile_bay_reservations      <-- gets first refusal
--       line 47  ottoq_release_vacated_spaces -> ottoq_activate_due_bay_reservations
--
--   So reconcile shreds the hold every tick before activation can see it. And its
--   BLOCKER 3 is a circular deadlock in plain sight: twin's deploy gate pins a car
--   in staging with remedy='need_service' BECAUSE must-do work is open; reconcile
--   then pushes that car's SERVICE BAY reservation away BECAUSE the car is gated.
--   The gate holds the car for want of the service; the reconcile withholds the
--   service for want of the gate clearing. Nobody moves. That is the doctrine
--   violation, and it is bigger than the window check.
--
--   THE CHANGE, precisely:
--
--   (A1) new ottoq.ottoq_vehicle_bay_ready(run, vehicle, clock) -> boolean.
--        TRUE only when the vehicle has NO unfinished charge leg (the identical
--        predicate reconcile already calls BLOCKER 1, keyed off planned_end_sim
--        because charge-leg status is not trustworthy). TOTAL: any error -> FALSE,
--        and FALSE only ever means "fall back to today's behaviour".
--
--   (A2) ottoq_activate_due_bay_reservations -- the window condition is NARROWED,
--        NOT DELETED. Before:
--            AND lower(b.during) <= p_clock          -- not before the forecast
--            AND upper(b.during) >  p_clock
--        After:
--            AND upper(b.during) >  p_clock          -- UNCHANGED: a lapsed hold never seats
--            AND ( lower(b.during) <= p_clock                                  -- (i) in window
--                  OR ottoq.ottoq_vehicle_bay_ready(p_sim_run_id, b.vehicle_id, p_clock) )  -- (ii) ready
--
--        "Not before the vehicle physically exists at the depot" is NOT lost by
--        dropping the lower bound, because the loop's own vehicle predicate --
--        v.home_depot_id = p_depot_id AND v.current_state IN (arrived_at_gate,
--        staged_awaiting_service, charge_complete_holding, service_complete_holding)
--        -- already asserts the car is standing in this depot, idle, not in another
--        bay and not in a fault state. Branch (ii) adds the one thing that predicate
--        does not cover: the car must not owe an unfinished charge leg, because a car
--        that is (or is about to be) plugged in cannot also be in a bay. So the
--        condition became "not before the vehicle is ready", exactly as asked.
--
--        THE WINDOW IS REBASED, NOT IGNORED. On an early seat the booking's `during`
--        is moved to [p_clock, p_clock + original duration) -- duration preserved to
--        the microsecond. That does four things at once:
--          * the row stops lying (state='active' with a window that starts later),
--          * ottoq_bay_binding_witness.inside_window reads TRUE and stays honest,
--          * the no-show grace, which measures from lower(during), stops running
--            against a car that is already in the bay,
--          * and DISPLACEMENT IS ADJUDICATED BY THE DATABASE, not by hand: the rebase
--            UPDATE is wrapped so exclusion_violation on
--            ottoq_stall_bookings_no_overlap{,_v2,_v3} (sim_run_id =, stall_id =,
--            during &&) means some other held/active/done/interrupted booking already
--            owns part of [now, now+dur). We do not push it, we do not drop it -- we
--            DECLINE the early seat, hand the stall reservation straight back, and let
--            this hold wait for its own window. Answer to "a hold activated early whose
--            service runs past a later hold's window": it cannot happen. The later hold
--            is what refuses the early seat in the first place.
--
--        TWO READY CARS, ONE BAY -- who wins and is it stable? Ordering is
--            ORDER BY (lower(b.during) <= p_clock) DESC,  -- due-now always beats early
--                     lower(b.during),                    -- then the earlier forecast
--                     b.booking_id                        -- then a stable, total tiebreak
--        Deterministic and total (booking_id is the PK, so no ties survive). The
--        loser is not harmed: the seat itself is still claimed by the existing
--        ottoq_reserve_stall compare-and-set, so even under concurrency exactly one
--        car takes the stall and the other simply CONTINUEs to the next tick.
--
--   (A3) ottoq_reconcile_bay_reservations -- two surgical changes, nothing else:
--        * VEHICLE-FIRST PRE-EMPTION: if the car is bay-ready, standing here idle,
--          and its booked stall is physically free right now, reconcile LEAVES THE
--          BOOKING COMPLETELY ALONE. No defer, no release. Activation seats it early
--          two calls later in the same tick. A free bay beats a prediction.
--        * BLOCKER 3 NARROWED to remedy='need_charge'. A deploy_gate with
--          remedy='need_service' is the REASON this booking exists; treating it as a
--          blocker is the deadlock above. need_charge is left blocking, deliberately
--          conservatively -- it is arguably already covered by BLOCKER 1 and could be
--          dropped later, but 0015 does not need to prove that to break the deadlock.
--
-- PART B -- THE UNTAGGED FLOOD. Writers FOUND, not inferred from a CONTEXT line.
--
--   Measured over the last 3 days, ottoq_events WHERE sim_run_id IS NULL:
--       vehicle.state_changed  trigger/production  69,917
--       rule.evaluated_pass    app/production      29,178
--       stall.state_changed    trigger/production   7,106
--       rule.evaluated_fail    app/production          41
--       stall.created          trigger/production      30
--   Three writers, identified from pg_trigger and pg_proc.prosrc:
--       public.ottoq_vehicles_state_change()  (trigger trg_ottoq_vehicles_state_change)
--       public.ottoq_stalls_state_change()    (trigger trg_ottoq_stalls_state_change)
--       public.ottoq_evaluate_rule_core()
--   No cancelled-statement CONTEXT line was used to reach that list.
--
--   (B1) THE DIFF KEY HISTOGRAM IS THE WHOLE STORY. Of 69,917 vehicle.state_changed:
--            last_state_change      18,703 / 20,000 sampled
--            current_soc_updated_at 18,245
--            updated_at             17,688
--            current_soc             1,280
--            config                  1,077
--            current_state             989   <-- the state changed 4.9% of the time
--            current_stall_id          578
--        56,544 of 69,917 = 80.9% have a diff of NOTHING BUT the three clock columns
--        {updated_at, current_soc_updated_at, last_state_change}. An event named
--        `vehicle.state_changed` in which no state changed. The trigger already
--        claims to skip "pure-timestamp churn" -- its skip list just never included
--        last_state_change, which is the timestamp OF a state change and is stamped
--        by the twin on rows whose state did not move. Widening that existing list by
--        one name is the whole fix. This is the single write suppressed, and it is
--        information-free by construction: the diff is empty of everything except
--        clocks, so ottoq_event_new_state's fold-forward reconstruction is unaffected
--        (it folds payload->'diff'->k->'to', and none of these rows carry a non-clock k).
--        current_soc is NOT suppressed -- SOC is real signal and the reconstruction
--        depends on it. Suppressing SOC too would have reached 85.9%; we stopped at 80.9%.
--
--   (B2) TAGGING. Both triggers now resolve the live run via the new
--        ottoq.ottoq_active_sim_run_id() (transaction-memoised into a local GUC, so
--        it costs one indexless lookup per transaction, not one per row) and write
--        data_source='twin' + sim_run_id=<run> when a run is live. Sim-generated
--        events stop masquerading as production, which also means retention and
--        ottoq_purge_prior_runs can finally see them.
--
--   (B3) rule.evaluated_pass -- 29,178 events, ZERO of which carry information that
--        is not already durably stored. ottoq_evaluate_rule_core writes the full
--        evaluation to ottoq_rule_evaluations (rule_code, rule_version, passed,
--        reason, severity, enforcement, enforcement_taken, parameters_used, context,
--        result_payload, correlation_id, duration_ms) and THEN writes an events row
--        whose payload is a strict subset of those same columns, and THEN issues a
--        third write (UPDATE ... SET linked_event_id) to stitch them back together.
--        0015 keeps the evaluation row -- the audit record is untouched and complete
--        -- and stops emitting the events row for a PASS on a non-shadow rule. Every
--        FAIL still emits. Every shadow-tier evaluation still emits (that is the
--        entire point of shadow). system.catalog_miss still emits. Three writes
--        become one for the expected case; the exceptional case is unchanged.
--
--   NOT TOUCHED, deliberately: the shield, cron 12, cron 10/11, the retention purge,
--   the append-only guard. Nothing is dropped. No VACUUM FULL.
--
-- PART C -- ottoq_svc_to_stall_type. CONFIRMED DEAD: a pg_proc.prosrc scan over
--   every function in ottoq/twin/public returns no caller. MIGRATION_LOG.md is
--   corrected in the same commit rather than left claiming it is THE resolver.
--   The gate-discovered-needs forward hold is NOT built here (see the report).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- HOUSE RULE 1: SNAPSHOT BEFORE YOU REPLACE. Every function this file touches,
-- captured with its md5, before it is touched. Nothing is DROPped anywhere in
-- this file; every change is CREATE OR REPLACE.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0015_early_activation_and_untagged_event_flood_pre', 'function',
       n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname = 'ottoq'  AND p.proname IN ('ottoq_activate_due_bay_reservations',
                                               'ottoq_reconcile_bay_reservations'))
    OR (n.nspname = 'public' AND p.proname IN ('ottoq_vehicles_state_change',
                                               'ottoq_stalls_state_change',
                                               'ottoq_evaluate_rule_core'));

-- ---------------------------------------------------------------------------
-- A1. Readiness. TOTAL by construction: never throws, FALSE means "no early seat".
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ottoq.ottoq_vehicle_bay_ready(
  p_sim_run_id uuid, p_vehicle_id uuid, p_clock timestamptz)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
DECLARE v_charge_end timestamptz;
BEGIN
  IF p_sim_run_id IS NULL OR p_vehicle_id IS NULL OR p_clock IS NULL THEN
    RETURN false;
  END IF;

  -- BLOCKER 1, verbatim from ottoq_reconcile_bay_reservations: an unfinished charge
  -- leg. Keyed off planned_end_sim rather than status because charge legs frequently
  -- never close (75 'active' vs 1 'done' in the phase-11 cert) -- status lies here.
  SELECT max(l.planned_end_sim) INTO v_charge_end
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = p_sim_run_id
     AND l.vehicle_id = p_vehicle_id
     AND l.leg_type IN ('charge_l2','charge_dcfc')
     AND l.status IN ('planned','active','in_progress')
     AND l.actual_end_sim IS NULL
     AND l.planned_end_sim > p_clock;

  RETURN v_charge_end IS NULL;
EXCEPTION WHEN OTHERS THEN
  RETURN false;   -- unknown readiness never seats a car early
END
$fn$;

COMMENT ON FUNCTION ottoq.ottoq_vehicle_bay_ready(uuid,uuid,timestamptz) IS
  '0015: is this vehicle physically free to be seated in a bay RIGHT NOW? TRUE only '
  'when it owes no unfinished charge leg. Used to narrow the bay-reservation window '
  'gate from "not before the forecast" to "not before the vehicle is ready".';


-- ---------------------------------------------------------------------------
-- A2. EARLY ACTIVATION.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ottoq.ottoq_activate_due_bay_reservations(
  p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_res record; v_n int := 0; v_prev uuid; v_state text; v_verb text;
        v_early int := 0; v_declined int := 0; v_rebased boolean;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  FOR v_res IN
    SELECT b.booking_id, b.vehicle_id, b.stall_id, b.purpose, b.leg_id,
           s.stall_type::text AS stall_type,
           (lower(b.during) <= p_clock)   AS in_window,
           (upper(b.during) - lower(b.during)) AS dur
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls   s ON s.id = b.stall_id
      JOIN public.vehicles v ON v.id = b.vehicle_id
     WHERE b.sim_run_id = p_sim_run_id
       AND b.state      = 'held'
       AND s.depot_id   = p_depot_id
       AND s.stall_type IN ('wash_bay'::stall_type,'detail_bay'::stall_type,'service_bay'::stall_type)
       AND s.status NOT IN ('maintenance','closed')
       -- ══════════════════ 0015: THE WINDOW GATE, NARROWED ══════════════════
       -- UNCHANGED: a hold whose window has already lapsed never seats. The grace
       -- sweep in ottoq_release_vacated_spaces owns that row.
       AND upper(b.during) >  p_clock
       -- WAS: AND lower(b.during) <= p_clock   ("not before the forecast")
       -- NOW: in window, OR the car is ready. VEHICLE-FIRST -- a free bay beats a
       -- prediction. The physical-presence guarantee the lower bound used to give is
       -- carried entirely by the v.current_state predicate below, which already means
       -- "standing in this depot, idle, not in another bay, not faulted"; readiness
       -- adds the one thing it misses -- no unfinished charge leg.
       AND ( lower(b.during) <= p_clock
             OR ottoq.ottoq_vehicle_bay_ready(p_sim_run_id, b.vehicle_id, p_clock) )
       -- the bay is physically free for this car
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = b.vehicle_id)
       -- the car is HOME and IDLE. Never interrupt live work; never touch a fault state.
       -- This is also the in-depot reassignment gate: a car that is IN a bay, charging,
       -- deployed or faulted is not in this list, so 0015 can never re-route it.
       AND v.home_depot_id = p_depot_id
       AND v.current_state IN ('arrived_at_gate'::vehicle_state,
                               'staged_awaiting_service'::vehicle_state,
                               'charge_complete_holding'::vehicle_state,
                               'service_complete_holding'::vehicle_state)
     -- CONTENTION ORDER: due-now beats early; then earliest forecast; then the PK,
     -- so the order is total and stable across ticks.
     ORDER BY (lower(b.during) <= p_clock) DESC, lower(b.during), b.booking_id
  LOOP
    -- CAS the stall. If someone else took it first, leave the reservation alone and
    -- let the existing grace/replan path deal with it -- we never force.
    CONTINUE WHEN NOT public.ottoq_reserve_stall(v_res.stall_id, v_res.vehicle_id, p_clock, 900);

    -- ══════════════ 0015: REBASE THE WINDOW ON AN EARLY SEAT ══════════════
    -- Duration preserved exactly. The exclusion constraints adjudicate displacement:
    -- if any other held/active/done/interrupted booking on this stall already owns
    -- part of [now, now+dur) we DECLINE the early seat outright -- we never push and
    -- never drop the other booking -- and hand the stall reservation back.
    v_rebased := true;
    IF NOT v_res.in_window THEN
      BEGIN
        UPDATE public.ottoq_stall_bookings
           SET during = tstzrange(p_clock, p_clock + v_res.dur, '[)')
         WHERE booking_id = v_res.booking_id AND state = 'held';
      EXCEPTION WHEN exclusion_violation THEN
        v_rebased := false;
      END;
    END IF;

    IF NOT v_rebased THEN
      UPDATE public.stalls
         SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
       WHERE id = v_res.stall_id
         AND reserved_by = v_res.vehicle_id
         AND current_vehicle_id IS NULL;
      v_declined := v_declined + 1;
      CONTINUE;
    END IF;

    v_state := CASE
                 WHEN v_res.stall_type = 'service_bay' THEN 'in_service_bay'
                 WHEN v_res.purpose    = 'detail'      THEN 'in_detail_bay'
                 WHEN v_res.stall_type = 'detail_bay'  THEN 'in_detail_bay'
                 ELSE 'in_wash_bay' END;
    v_verb  := CASE WHEN v_state = 'in_service_bay' THEN 'enter_service' ELSE 'enter_wash' END;

    -- Close out whatever space the car is vacating (same contract as enact_space_assignment).
    SELECT vv.current_stall_id INTO v_prev FROM public.vehicles vv WHERE vv.id = v_res.vehicle_id;
    IF v_prev IS NOT NULL AND v_prev <> v_res.stall_id THEN
      UPDATE public.ottoq_stall_bookings
         SET state = 'done', released_at = p_clock,
             release_reason = 'vehicle_moved_to_next_leg',
             during = tstzrange(lower(during),
                        GREATEST(lower(during) + interval '1 second',
                                 LEAST(upper(during), p_clock)), '[)')
       WHERE sim_run_id = p_sim_run_id AND stall_id = v_prev
         AND vehicle_id = v_res.vehicle_id AND state IN ('held','active');
    END IF;

    -- OCCUPY.
    UPDATE public.vehicles
       SET current_stall_id = v_res.stall_id,
           current_state    = v_state::vehicle_state,
           last_state_change = p_clock
     WHERE id = v_res.vehicle_id;
    UPDATE public.stalls
       SET current_vehicle_id = v_res.vehicle_id, status = 'occupied'
     WHERE id = v_res.stall_id;

    -- The reservation is now a REAL occupancy, and is stamped so provenance can see
    -- that it was activated rather than booked fresh -- and, from 0015, whether the
    -- free bay beat the forecast.
    UPDATE public.ottoq_stall_bookings
       SET state = 'active', booked_by = 'otto_q_enacted',
           source = CASE WHEN v_res.in_window THEN 'bay_reservation_activated'
                         ELSE 'bay_reservation_activated_early' END
     WHERE booking_id = v_res.booking_id;

    IF v_res.leg_id IS NOT NULL THEN
      -- keep the leg in lockstep with the (possibly rebased) booking: ottoq_stall_free_between
      -- reads planned_end_sim, so a booking and its leg must never disagree.
      UPDATE public.ottoq_itinerary_legs
         SET to_stall_id = v_res.stall_id, status = 'active',
             planned_start_sim = CASE WHEN v_res.in_window THEN planned_start_sim ELSE p_clock END,
             planned_end_sim   = CASE WHEN v_res.in_window THEN planned_end_sim   ELSE p_clock + v_res.dur END,
             actual_start_sim  = COALESCE(actual_start_sim, p_clock)
       WHERE leg_id = v_res.leg_id AND status = 'planned';
    END IF;

    BEGIN
      PERFORM public.ottoq_emit_vehicle_command(
        p_sim_run_id, p_depot_id, v_res.vehicle_id, v_verb,
        jsonb_build_object('stall_id',   v_res.stall_id,
                           'booking_id', v_res.booking_id,
                           'leg_id',     v_res.leg_id,
                           'purpose',    v_res.purpose,
                           'via',        CASE WHEN v_res.in_window
                                              THEN 'bay_reservation_activated'
                                              ELSE 'bay_reservation_activated_early' END), p_clock);
    EXCEPTION WHEN OTHERS THEN NULL;  -- an un-emitted command must never cost the move
    END;

    IF NOT v_res.in_window THEN v_early := v_early + 1; END IF;
    v_n := v_n + 1;
  END LOOP;

  -- ONE summary event per tick (event-write amplification is the known tick-cost driver).
  IF v_early > 0 OR v_declined > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'bay_reservation_early_activation',
        p_event_type := 'ottoq.bay_reservation_activated_early', p_entity_type := 'depot',
        p_entity_id := p_depot_id,
        p_payload := jsonb_build_object(
          'seated_early', v_early, 'declined_would_displace', v_declined, 'seated_total', v_n,
          'note','a ready car took a free bay ahead of its forecast window; declined means a '
                 'later booking on that stall already owned the time, so the early seat was refused'),
        p_severity := 'info',
        p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  RETURN v_n;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_activate_due_bay_reservations: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN 0;
END
$function$;


-- ---------------------------------------------------------------------------
-- A3. RECONCILE: stop shredding the hold the ready car is about to use, and break
--     the deploy_gate:need_service deadlock.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ottoq.ottoq_reconcile_bay_reservations(
  p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_taxi   numeric; v_max_defer int; v_horizon numeric;
  v_step   int := 10;      -- forward walk granularity when the new window collides
  v_maxsh  int := 240;     -- bounded walk budget per booking per tick
  v_b      RECORD;
  v_dur    interval; v_eta timestamptz; v_blk text; v_block_at timestamptz; v_try timestamptz;
  v_ok     boolean; v_shift int; v_seq int;
  v_def    int := 0; v_rel int := 0; v_moved int := 0; v_left int := 0;
  v_alt    RECORD; v_newstall uuid;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_reservation_reconcile_enabled',1),1) < 1
    THEN RETURN 0; END IF;

  v_taxi      := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_taxi_min',3),3),0);
  v_max_defer := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_defer_max',8),8),1)::int;
  v_horizon   := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_defer_horizon_min',480),480),30);

  FOR v_b IN
    SELECT b.booking_id, b.vehicle_id, b.stall_id, b.purpose, b.leg_id,
           lower(b.during) AS lo, upper(b.during) AS hi,
           v.current_state::text AS vstate, v.config AS vcfg,
           s.depot_id AS depot_id, s.stall_type AS stall_type,
           (s.current_vehicle_id IS NULL
            AND (s.reserved_by IS NULL OR s.reserved_by = b.vehicle_id)
            AND s.status NOT IN ('maintenance','closed'))  AS stall_free_now
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls   s ON s.id = b.stall_id
      JOIN public.vehicles v ON v.id = b.vehicle_id
     WHERE b.sim_run_id = p_sim_run_id
       AND b.state = 'held'
       AND s.depot_id = p_depot_id
       AND s.stall_type IN ('wash_bay'::stall_type,'service_bay'::stall_type)
       AND lower(b.during) <= p_clock + make_interval(mins => v_taxi::int)
       AND v.current_stall_id IS DISTINCT FROM b.stall_id
     ORDER BY lower(b.during)
  LOOP
    v_dur := v_b.hi - v_b.lo;
    v_block_at := NULL; v_blk := NULL;

    -- ══════════ 0015 VEHICLE-FIRST PRE-EMPTION -- MUST BE THE FIRST TEST ══════════
    -- The car is standing here, idle, owes no charge leg, and its own booked bay is
    -- physically empty. There is nothing to reconcile: ottoq_activate_due_bay_reservations
    -- seats it later in THIS SAME TICK (decide_tick line 45 reconcile, line 47 activate).
    -- Deferring or releasing it here is precisely how 96 holds died `replanned_no_window`
    -- while the bays they pointed at sat empty. Leave it completely alone.
    IF v_b.stall_free_now
       AND v_b.vstate IN ('arrived_at_gate','staged_awaiting_service',
                          'charge_complete_holding','service_complete_holding')
       AND ottoq.ottoq_vehicle_bay_ready(p_sim_run_id, v_b.vehicle_id, p_clock)
    THEN
      v_left := v_left + 1;
      CONTINUE;
    END IF;

    -- ── the vehicle is not even in the depot: the reservation is dead.
    IF v_b.vstate IN ('offline','deployed','en_route_to_deployment','out_of_service','tow_requested') THEN
      UPDATE public.ottoq_stall_bookings
         SET state='released', released_at=p_clock, release_reason='replanned_vehicle_absent'
       WHERE booking_id = v_b.booking_id AND state='held';
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,defer_seq)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,v_b.stall_id,v_b.purpose,p_clock,
              'released','replanned_vehicle_absent',v_b.vstate,v_b.lo,v_b.hi,NULL);
      v_rel := v_rel + 1;
      CONTINUE;
    END IF;

    -- ── BLOCKER 1: an unfinished charge leg. Keyed off planned_end_sim rather than
    --    leg status, because charge legs frequently never close.
    SELECT max(l.planned_end_sim) INTO v_try
      FROM public.ottoq_itinerary_legs l
     WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_b.vehicle_id
       AND l.leg_type IN ('charge_l2','charge_dcfc')
       AND l.status IN ('planned','active','in_progress')
       AND l.actual_end_sim IS NULL
       AND l.planned_end_sim > p_clock;
    IF v_try IS NOT NULL THEN v_block_at := v_try; v_blk := 'charging'; END IF;

    -- ── BLOCKER 2: still standing in a different bay.
    IF v_b.vstate IN ('in_wash_bay','in_detail_bay','in_service_bay') THEN
      v_try := GREATEST(COALESCE(NULLIF(v_b.vcfg->>'service_ends_at','null')::timestamptz, p_clock), p_clock);
      IF v_block_at IS NULL OR v_try > v_block_at THEN v_block_at := v_try; END IF;
      v_blk := COALESCE(v_blk||'+','') || 'in_other_bay';
    END IF;

    -- ── BLOCKER 3: NARROWED BY 0015 TO remedy='need_charge'.
    --    twin.ottoq_sim_advance_service_flow pins a vehicle in staging with
    --    config.deploy_gate. remedy='need_service' means MUST-DO WORK IS OPEN --
    --    which is the very reason this bay booking exists. Blocking the booking on
    --    that gate made the gate un-clearable: the gate holds the car for want of the
    --    service, the reconcile withholds the service for want of the gate clearing.
    --    MEASURED: 52 defers + 10 relocations + 9 `replanned_no_window` releases +
    --    3 `replanned_defer_cap` releases attributed to deploy_gate:need_service alone.
    --    need_charge still blocks (conservative: it is arguably already covered by
    --    BLOCKER 1, but 0015 does not need that to be true).
    IF v_b.vcfg ? 'deploy_gate'
       AND COALESCE(v_b.vcfg#>>'{deploy_gate,remedy}','') = 'need_charge' THEN
      v_try := p_clock + make_interval(mins => v_taxi::int);
      IF v_block_at IS NULL OR v_try > v_block_at THEN v_block_at := v_try; END IF;
      v_blk := COALESCE(v_blk||'+','') || 'deploy_gate:need_charge';
    END IF;

    IF v_block_at IS NULL THEN CONTINUE; END IF;

    v_eta := v_block_at + make_interval(mins => v_taxi::int);
    IF v_eta <= v_b.lo THEN CONTINUE; END IF;

    SELECT count(*) INTO v_seq
      FROM public.bay_reservation_reconcile_2026_08_02 r
     WHERE r.booking_id = v_b.booking_id AND r.action = 'deferred';

    IF v_seq >= v_max_defer OR v_eta > v_b.lo + make_interval(mins => v_horizon::int) THEN
      UPDATE public.ottoq_stall_bookings
         SET state='released', released_at=p_clock,
             release_reason = CASE WHEN v_seq >= v_max_defer
                                   THEN 'replanned_defer_cap' ELSE 'replanned_beyond_horizon' END
       WHERE booking_id = v_b.booking_id AND state='held';
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,defer_seq,eta)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,v_b.stall_id,v_b.purpose,p_clock,'released',
              CASE WHEN v_seq >= v_max_defer THEN 'replanned_defer_cap' ELSE 'replanned_beyond_horizon' END,
              v_blk,v_b.lo,v_b.hi,v_seq,v_eta);
      v_rel := v_rel + 1;
      CONTINUE;
    END IF;

    -- ── DEFER: slide the window to when the vehicle can ACTUALLY be there.
    v_ok := false; v_shift := 0; v_newstall := NULL;
    WHILE NOT v_ok AND v_shift <= v_maxsh LOOP
      v_try := v_eta + make_interval(mins => v_shift);
      BEGIN
        UPDATE public.ottoq_stall_bookings
           SET during = tstzrange(v_try, v_try + v_dur, '[)')
         WHERE booking_id = v_b.booking_id AND state = 'held';
        v_ok := true; v_newstall := v_b.stall_id;
      EXCEPTION WHEN exclusion_violation THEN
        FOR v_alt IN
          SELECT s2.id
            FROM public.stalls s2
           WHERE s2.depot_id   = v_b.depot_id
             AND s2.stall_type = v_b.stall_type
             AND s2.status NOT IN ('maintenance','closed')
             AND s2.id <> v_b.stall_id
           ORDER BY s2.distance_from_entrance NULLS LAST, s2.id
        LOOP
          BEGIN
            UPDATE public.ottoq_stall_bookings
               SET stall_id = v_alt.id, during = tstzrange(v_try, v_try + v_dur, '[)')
             WHERE booking_id = v_b.booking_id AND state = 'held';
            v_ok := true; v_newstall := v_alt.id;
            EXIT;
          EXCEPTION WHEN exclusion_violation THEN
            NULL;
          END;
        END LOOP;
        IF NOT v_ok THEN v_shift := v_shift + v_step; END IF;
      END;
    END LOOP;

    IF v_ok THEN
      IF v_newstall IS DISTINCT FROM v_b.stall_id THEN v_moved := v_moved + 1; END IF;
      IF v_b.leg_id IS NOT NULL THEN
        UPDATE public.ottoq_itinerary_legs
           SET planned_start_sim = v_try, planned_end_sim = v_try + v_dur
         WHERE leg_id = v_b.leg_id AND status = 'planned';
      END IF;
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,new_from,new_to,defer_seq,eta)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,COALESCE(v_newstall,v_b.stall_id),v_b.purpose,p_clock,'deferred',
              CASE WHEN v_newstall IS DISTINCT FROM v_b.stall_id
                   THEN 'vehicle_not_yet_releasable_relocated_bay'
                   ELSE 'vehicle_not_yet_releasable' END,
              v_blk,v_b.lo,v_b.hi,v_try,v_try+v_dur,v_seq+1,v_eta);
      v_def := v_def + 1;
    ELSE
      UPDATE public.ottoq_stall_bookings
         SET state='released', released_at=p_clock, release_reason='replanned_no_window'
       WHERE booking_id = v_b.booking_id AND state='held';
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,defer_seq,eta)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,v_b.stall_id,v_b.purpose,p_clock,'released',
              'replanned_no_window',v_blk,v_b.lo,v_b.hi,v_seq,v_eta);
      v_rel := v_rel + 1;
    END IF;
  END LOOP;

  IF v_def > 0 OR v_rel > 0 OR v_left > 0 THEN
   BEGIN
    PERFORM public.ottoq_record_event(
      p_actor_type := 'ottoq_engine', p_actor_id := 'bay_reservation_reconcile',
      p_event_type := 'ottoq.bay_reservation_replanned', p_entity_type := 'depot',
      p_entity_id := p_depot_id,
      p_payload := jsonb_build_object('deferred',v_def,'released',v_rel,'relocated',v_moved,
        'left_for_early_activation',v_left,
        'taxi_min',v_taxi,'defer_max',v_max_defer,'horizon_min',v_horizon,
        'note','a reservation is honoured or re-planned; it is never left to rot. '
               'left_for_early_activation = the car is ready and its bay is free, so '
               'reconcile stood down and activation seats it this same tick'),
      p_severity := CASE WHEN v_rel > 0 THEN 'warning' ELSE 'info' END,
      p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
   EXCEPTION WHEN OTHERS THEN
     RAISE WARNING 'bay_reservation_reconcile: summary event not written (%): %', SQLSTATE, SQLERRM;
   END;
  END IF;

  RETURN v_def + v_rel;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_reconcile_bay_reservations: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN 0;
END
$function$;


-- ===========================================================================
-- PART B
-- ===========================================================================

-- B2a. Which run is live? Memoised transaction-locally so 70k trigger firings
--      cost ONE lookup, not 70k. TOTAL: never throws, NULL means "no run".
CREATE OR REPLACE FUNCTION ottoq.ottoq_active_sim_run_id()
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'twin','ottoq','public','extensions'
AS $fn$
DECLARE v_txt text; v_id uuid;
BEGIN
  v_txt := NULLIF(current_setting('ottoq.sim_run_id', true), '');
  IF v_txt IS NOT NULL THEN
    IF v_txt = 'none' THEN RETURN NULL; END IF;
    RETURN v_txt::uuid;
  END IF;

  SELECT r.sim_run_id INTO v_id
    FROM public.ottoq_sim_runs r
   WHERE r.status = 'running'
   ORDER BY r.started_at DESC
   LIMIT 1;

  PERFORM set_config('ottoq.sim_run_id', COALESCE(v_id::text, 'none'), true);
  RETURN v_id;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END
$fn$;

COMMENT ON FUNCTION ottoq.ottoq_active_sim_run_id() IS
  '0015: the live sim run, memoised into the transaction-local GUC ottoq.sim_run_id. '
  'Lets the row triggers tag sim-generated events with the run instead of writing them '
  'as untagged production. Returns NULL when nothing is running.';


-- B1 + B2. The vehicles trigger: widen the existing pure-clock skip by one name, and tag.
CREATE OR REPLACE FUNCTION public.ottoq_vehicles_state_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_payload      JSONB;
  v_diff         JSONB;
  v_actor_type   TEXT := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
  v_actor_id     TEXT := NULLIF(current_setting('ottoq.actor_id', TRUE), '');
  v_event_type   TEXT;
  v_run          UUID;
BEGIN
  v_run := ottoq.ottoq_active_sim_run_id();

  IF TG_OP = 'INSERT' THEN
    v_event_type := 'vehicle.created';
    v_payload := jsonb_build_object('new', to_jsonb(NEW));
    PERFORM ottoq_record_event(
      p_actor_type        := v_actor_type,
      p_actor_id          := v_actor_id,
      p_event_type        := v_event_type,
      p_entity_type       := 'vehicle',
      p_entity_id         := NEW.id,
      p_fleet_operator_id := NEW.fleet_operator_id,
      p_payload           := v_payload,
      p_new_state         := to_jsonb(NEW),
      p_ingest_source     := 'trigger',
      p_data_source       := CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END,
      p_sim_run_id        := v_run
    );
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF to_jsonb(OLD) = to_jsonb(NEW) THEN
      RETURN NEW;
    END IF;
    v_diff := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW));
    -- ══════════════════════════ 0015 ══════════════════════════
    -- Skip pure-timestamp churn: only clock columns moved, no state change.
    -- `last_state_change` ADDED. It is the timestamp OF a state change, and the twin
    -- stamps it on rows whose state did not move -- which is why 56,544 of 69,917
    -- `vehicle.state_changed` rows (80.9%) carried a diff of nothing but these three
    -- clock keys. An event asserting a state change in which nothing changed state is
    -- information-free, and dropping it cannot affect ottoq_event_new_state()'s
    -- fold-forward reconstruction, which only ever reads non-clock diff keys.
    -- `current_soc` is deliberately NOT in this list: SOC is real signal.
    IF NOT EXISTS (
      SELECT 1 FROM jsonb_object_keys(v_diff) AS k
       WHERE k <> ALL (ARRAY['updated_at','current_soc_updated_at','last_state_change'])
    ) THEN
      RETURN NEW;
    END IF;
    v_event_type := 'vehicle.state_changed';
    v_payload := jsonb_build_object('diff', v_diff);
    PERFORM ottoq_record_event(
      p_actor_type        := v_actor_type,
      p_actor_id          := v_actor_id,
      p_event_type        := v_event_type,
      p_entity_type       := 'vehicle',
      p_entity_id         := NEW.id,
      p_fleet_operator_id := NEW.fleet_operator_id,
      p_payload           := v_payload,
      p_new_state         := to_jsonb(NEW),
      p_ingest_source     := 'trigger',
      p_data_source       := CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END,
      p_sim_run_id        := v_run
    );
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$function$;


-- B2. The stalls trigger: tag, and add reserved_at to the existing clock skip list
--     (same class as reservation_expires_at, which is already there).
CREATE OR REPLACE FUNCTION public.ottoq_stalls_state_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_payload      JSONB;
  v_diff         JSONB;
  v_actor_type   TEXT := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
  v_actor_id     TEXT := NULLIF(current_setting('ottoq.actor_id', TRUE), '');
  v_event_type   TEXT;
  v_run          UUID;
BEGIN
  v_run := ottoq.ottoq_active_sim_run_id();

  IF TG_OP = 'INSERT' THEN
    v_event_type := 'stall.created';
    PERFORM ottoq_record_event(
      p_actor_type    := v_actor_type,
      p_actor_id      := v_actor_id,
      p_event_type    := v_event_type,
      p_entity_type   := 'stall',
      p_entity_id     := NEW.id,
      p_depot_id      := NEW.depot_id,
      p_payload       := jsonb_build_object('new', to_jsonb(NEW)),
      p_new_state     := to_jsonb(NEW),
      p_ingest_source := 'trigger',
      p_data_source   := CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END,
      p_sim_run_id    := v_run
    );
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF to_jsonb(OLD) = to_jsonb(NEW) THEN RETURN NEW; END IF;
    v_diff := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW));
    IF NOT EXISTS (
      SELECT 1 FROM jsonb_object_keys(v_diff) AS k
       WHERE k <> ALL (ARRAY['updated_at','reservation_expires_at','reserved_at'])
    ) THEN
      RETURN NEW;
    END IF;
    v_event_type := 'stall.state_changed';
    v_payload := jsonb_build_object('diff', v_diff);
    PERFORM ottoq_record_event(
      p_actor_type     := v_actor_type,
      p_actor_id       := v_actor_id,
      p_event_type     := v_event_type,
      p_entity_type    := 'stall',
      p_entity_id      := NEW.id,
      p_depot_id       := NEW.depot_id,
      p_payload        := v_payload,
      p_new_state      := to_jsonb(NEW),
      p_ingest_source  := 'trigger',
      p_data_source    := CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END,
      p_sim_run_id     := v_run
    );
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$function$;


-- B2c. stall.state_changed carries avg 1,174 B of new_state on top of a 288 B diff --
--      a full re-photograph of the stall row on every change, exactly the pattern 0006
--      already fixed for vehicles. Its chain cut is a data-driven list; widen it. The
--      snapshot stays READABLE via public.ottoq_event_new_state(event_id), which folds
--      the diffs forward from the day's anchor. Emergency stop is unchanged: set
--      enabled=false on this row.
UPDATE public.ottoq_write_slimming_policy
   SET chain_event_types = ARRAY['vehicle.state_changed','stall.state_changed'],
       updated_at        = now(),
       notes             = notes || ' 0015: stall.state_changed added to the chain cut '
                                 || '(measured 1,174 B of redundant new_state per row).'
 WHERE policy_key = 'ottoq_events'
   AND NOT ('stall.state_changed' = ANY (chain_event_types));


-- B3. rule.evaluated_pass: keep the audit row, stop the duplicate event + the stitch UPDATE.
CREATE OR REPLACE FUNCTION public.ottoq_evaluate_rule_core(
  p_rule_code text, p_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid,
  p_context jsonb DEFAULT '{}'::jsonb, p_action_context text DEFAULT NULL::text,
  p_fleet_operator_id uuid DEFAULT NULL::uuid, p_depot_id uuid DEFAULT NULL::uuid,
  p_triggered_by_event_id uuid DEFAULT NULL::uuid, p_override_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(passed boolean, reason text, enforcement_taken text, evaluation_id uuid,
              severity text, enforcement text, suggested_action text, rule_version integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rule        ottoq_rules%ROWTYPE;
  v_params      JSONB;
  v_result      ottoq_rule_result;
  v_started_at  TIMESTAMPTZ := clock_timestamp();
  v_eval_id     UUID := gen_random_uuid();
  v_event_id    UUID;
  v_enforcement TEXT;
  v_severity    TEXT;
  v_taken       TEXT;
  v_correlation UUID;
  v_dynamic_sql TEXT;
  v_run         UUID;
BEGIN
  v_run := ottoq.ottoq_active_sim_run_id();

  SELECT * INTO v_rule FROM ottoq_rules
   WHERE rule_code = p_rule_code AND status IN ('active','shadow')
   ORDER BY version DESC LIMIT 1;

  IF NOT FOUND THEN
    v_event_id := ottoq_record_event(
      p_actor_type := 'ottoq_engine', p_event_type := 'system.catalog_miss',
      p_entity_type := COALESCE(p_entity_type, 'system'), p_entity_id := p_entity_id,
      p_payload := jsonb_build_object('missing_rule_code', p_rule_code), p_severity := 'warning',
      p_data_source := CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END,
      p_sim_run_id := v_run);
    RETURN QUERY SELECT TRUE, 'rule_not_found'::text, 'allowed'::text, v_eval_id,
                        'info'::text, 'log_only'::text, NULL::text, 0;
    RETURN;
  END IF;

  v_params := ottoq_resolve_rule_parameters(p_rule_code, p_fleet_operator_id, p_depot_id, NULL);

  BEGIN
    v_dynamic_sql := format('SELECT * FROM %I($1,$2,$3,$4)', v_rule.evaluator_function);
    EXECUTE v_dynamic_sql INTO v_result USING p_entity_type, p_entity_id, p_context, v_params;
  EXCEPTION WHEN OTHERS THEN
    v_event_id := ottoq_record_event(
      p_actor_type := 'ottoq_engine', p_event_type := 'system.catalog_miss',
      p_entity_type := COALESCE(p_entity_type, 'system'), p_entity_id := p_entity_id,
      p_payload := jsonb_build_object('rule_code', p_rule_code, 'evaluator_error', SQLERRM,
                     'sqlstate', SQLSTATE, 'enforcement', v_rule.enforcement, 'severity', v_rule.severity,
                     'fail_closed', (v_rule.enforcement = 'block')),
      p_severity := 'critical',
      p_data_source := CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END,
      p_sim_run_id := v_run);

    -- WIRE-2: a BLOCK-tier rule that THROWS fails CLOSED (the safety posture);
    -- non-block advisory rules keep log-and-pass.
    IF v_rule.enforcement = 'block' THEN
      RETURN QUERY SELECT FALSE, ('evaluator_error_failclosed: ' || SQLERRM)::text, 'blocked'::text, v_eval_id,
                          COALESCE(v_rule.severity,'critical'), v_rule.enforcement, 'fix_evaluator_or_supply_context'::text, v_rule.version;
    ELSE
      RETURN QUERY SELECT TRUE, ('evaluator_error: ' || SQLERRM)::text, 'logged'::text, v_eval_id,
                          COALESCE(v_rule.severity,'warning'), v_rule.enforcement, NULL::text, v_rule.version;
    END IF;
    RETURN;
  END;

  v_enforcement := v_rule.enforcement;
  v_severity    := COALESCE(v_result.severity_override, v_rule.severity);

  IF v_result.passed THEN
    v_taken := CASE WHEN v_enforcement = 'shadow' THEN 'shadow_pass' ELSE 'allowed' END;
  ELSE
    v_taken := CASE
      WHEN p_override_id IS NOT NULL THEN 'overridden'
      WHEN v_enforcement = 'block'    THEN 'blocked'
      WHEN v_enforcement = 'warn'     THEN 'warned'
      WHEN v_enforcement = 'log_only' THEN 'logged'
      WHEN v_enforcement = 'shadow'   THEN 'shadow_fail'
      ELSE 'logged'
    END;
  END IF;

  v_correlation := NULLIF(current_setting('ottoq.correlation_id', TRUE), '')::UUID;

  IF current_setting('ottoq.dryrun', true) = 'on' THEN
    RETURN QUERY SELECT v_result.passed, v_result.reason, v_taken, v_eval_id, v_severity, v_enforcement, v_result.suggested_action, v_rule.version;
    RETURN;
  END IF;  -- MPC fork: evaluate but do not persist

  -- THE AUDIT RECORD. UNCHANGED, and it is the complete one: rule_code, version,
  -- passed, reason, severity, enforcement, enforcement_taken, parameters_used,
  -- context, result_payload, correlation_id, duration_ms.
  INSERT INTO ottoq_rule_evaluations (
    evaluation_id, evaluated_at, duration_ms, rule_code, rule_version,
    triggered_by_event_id, action_context, entity_type, entity_id,
    fleet_operator_id, depot_id, passed, reason, severity, enforcement, enforcement_taken,
    parameters_used, context, result_payload, override_id, correlation_id
  ) VALUES (
    v_eval_id, NOW(), EXTRACT(MILLISECOND FROM (clock_timestamp() - v_started_at))::INTEGER,
    p_rule_code, v_rule.version, p_triggered_by_event_id, p_action_context,
    p_entity_type, p_entity_id, p_fleet_operator_id, p_depot_id,
    v_result.passed, v_result.reason, v_severity, v_enforcement, v_taken,
    v_params, p_context, COALESCE(v_result.payload, '{}'::jsonb), p_override_id, v_correlation
  );

  -- ══════════════════════════ 0015 ══════════════════════════
  -- 29,178 `rule.evaluated_pass` events in 3 days, every one of them a strict subset
  -- of the row we just wrote, plus a third write to stitch them together. A rule that
  -- passed is the expected case and carries no signal the evaluation row lacks. So:
  -- emit the event for a FAIL (always), or for ANY shadow-tier evaluation (a shadow
  -- rule's whole purpose is to be observed in the event stream). Skip it for a pass on
  -- a non-shadow rule -- and skip the linked_event_id UPDATE with it. The audit trail
  -- is not thinned: ottoq_rule_evaluations still has one row per evaluation, pass or fail.
  IF (NOT v_result.passed) OR v_enforcement = 'shadow' THEN
    v_event_id := ottoq_record_event(
      p_actor_type := 'ottoq_engine',
      p_event_type := CASE WHEN v_result.passed THEN 'rule.evaluated_pass' ELSE 'rule.evaluated_fail' END,
      p_entity_type := COALESCE(p_entity_type, 'system'), p_entity_id := p_entity_id,
      p_fleet_operator_id := p_fleet_operator_id, p_depot_id := p_depot_id,
      p_payload := jsonb_build_object(
        'rule_code', p_rule_code, 'rule_version', v_rule.version,
        'passed', v_result.passed, 'reason', v_result.reason,
        'enforcement_taken', v_taken, 'severity', v_severity,
        'action_context', p_action_context, 'override_id', p_override_id,
        'result_payload', v_result.payload),
      p_severity := v_severity, p_parent_event_id := p_triggered_by_event_id,
      p_correlation_id := v_correlation,
      p_data_source := CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END,
      p_sim_run_id := v_run);

    UPDATE ottoq_rule_evaluations re SET linked_event_id = v_event_id WHERE re.evaluation_id = v_eval_id;
  END IF;

  RETURN QUERY SELECT v_result.passed, v_result.reason, v_taken, v_eval_id,
                      v_severity, v_enforcement, v_result.suggested_action, v_rule.version;
END;
$function$;

COMMIT;
