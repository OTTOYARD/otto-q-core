-- =====================================================================
-- 0197  An assignment the calendar refused is not an assignment
-- =====================================================================
-- forces_recert = TRUE. This changes the decide path: two functions that
-- could leave a vehicle and a stall pointing at each other with nothing
-- on the calendar behind it now roll that occupancy back instead. The
-- refusal branch did NOT fire in rounds 16 or 17 (measured below), so
-- the prediction is that no canon moves -- but the path changed, and a
-- changed decide path is recertified, not asserted to be equivalent.
--
-- THE DEFECT
-- ---------------------------------------------------------------------
-- ottoq.ottoq_enact_space_assignment reserves a stall, then:
--
--   UPDATE public.vehicles SET current_stall_id = v_stall ...
--   UPDATE public.stalls   SET current_vehicle_id = p_vehicle_id,
--                              status = 'occupied' ...
--   v_bkg := ottoq.ottoq_record_enacted_booking(...);
--   RETURN jsonb_build_object('assigned', true, ...,
--                             'booked', v_bkg IS NOT NULL, ...);
--
-- ottoq_record_enacted_booking returns NULL on three ordinary,
-- non-raising paths: the stall row is gone; ottoq_book_stall refuses
-- (the EXCLUDE constraint on ottoq_stall_bookings); or its own outer
-- handler swallows anything else. None of those raise into the caller,
-- so nothing rolls back, and the function returns assigned=true with
-- booked=false while both occupancy pointers stand.
--
-- Being inside one transaction does not make this atomic. Atomicity
-- comes from the failure PROPAGATING; a swallowed failure that returns
-- NULL leaves the transaction healthy and the writes committed with it.
--
-- Every caller reads 'assigned' and none reads 'booked' (A2 pins the
-- census at four call sites in public.ottoq_decide_tick,
-- ottoq.ottoq_bind_unbooked_bay_occupants and
-- ottoq.ottoq_enact_inspection_seam), so the refusal is invisible
-- upstream: the tick proceeds as though the space were held.
--
-- ottoq.ottoq_reconcile_displace_stale_claim carries the same shape and
-- is worse: by the time it calls the recorder it has already superseded
-- other vehicles' claims on that stall and handed their planned legs
-- back to the planner. A NULL there left the displacement done and the
-- replacement unbooked.
--
-- WHAT THIS COSTS, STATED PLAINLY
-- ---------------------------------------------------------------------
-- The company's standing rule is "assignment plus verification, always":
-- ottoq_stall_bookings makes double-booking physically impossible via
-- its EXCLUDE constraint, and space_conflict_ledger records every
-- calendar claim overruled by physical reality. Occupancy written past
-- a refused booking is outside both. It is a car in a stall that the
-- calendar does not know about, that no EXCLUDE defends against a second
-- car, and that no KPI can trace to a decision. The guarantee is not
-- that the calendar cannot be overlapped -- it demonstrably cannot -- it
-- is that occupancy and calendar cannot disagree. That second half was
-- not enforced.
--
-- THE FIX
-- ---------------------------------------------------------------------
-- In both functions the world-changing statements -- the release of the
-- vacated hold, the two occupancy pointers, the calendar row and the leg
-- binding (and, in the displace path, the supersede of the losing claims
-- and the conflict-ledger row) -- move inside ONE plpgsql subtransaction.
-- A NULL from the recorder raises SQLSTATE OQ197 inside that block, which
-- rolls back every write in it, and the handler returns
-- assigned=false, reason='booking_refused'. The physical reservation is
-- dropped on the way out so the stall is not held for its 900-second TTL
-- against an assignment that never happened.
--
-- 'booked' stays in the success payload and is now always true, because
-- assigned=true can no longer mean anything else. A caller that reads it
-- keeps working; a caller that ignored it is now correct by construction.
--
-- WHAT THE ROUNDS SAY ABOUT THE BLAST RADIUS
-- ---------------------------------------------------------------------
-- Postgres log census over rounds 16 and 17 (2026-09-05 01:38-05:25 UTC,
-- 28 arms):
--
--   ottoq_record_enacted_booking: booking REFUSED       0
--   ottoq_record_enacted_booking: FAILED                0
--   ottoq_record_enacted_booking: stall not found       0
--   ottoq_record_enacted_booking: could not widen       4   (returns the
--                                                           adopted id,
--                                                           not NULL)
--   ottoq_enact_space_assignment: FAILED              254   (158 P0001
--     arm-interlock, 96 23505 on idx_stalls_one_vehicle_per_stall)
--
-- The 254 are RAISES, and a plpgsql block with an EXCEPTION handler is a
-- subtransaction, so those already rolled their own occupancy back. They
-- are not this defect; they are the reason it was hard to see. The
-- silent-NULL branch fired zero times in the certified rounds, which is
-- why the canons are predicted to hold.
--
-- Two things the census makes visible and this migration does NOT fix,
-- recorded so they are not mistaken for closed:
--   * 96 times in two rounds the code tried to seat a second vehicle in
--     an occupied stall and only the unique index stopped it. The
--     ottoq_reserve_stall CAS plus ottoq_stall_free_between are not
--     preventing the attempt; the index is doing the work.
--   * The Benchmark depot (22222222-...) is resting with 64 of its 160
--     stalls occupied and ZERO bookings of any state behind them (A4).
--     That is seeding residue on a depot the certification does not use,
--     not a booking refusal -- A4 proves the distinction rather than
--     assuming it.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. ottoq.ottoq_enact_space_assignment
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ottoq.ottoq_enact_space_assignment(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_stall_type text, p_purpose text, p_clock timestamp with time zone, p_until timestamp with time zone DEFAULT NULL::timestamp with time zone, p_leg_id uuid DEFAULT NULL::uuid, p_source text DEFAULT 'needs_card'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_cand RECORD; v_stall uuid; v_prev uuid; v_bkg uuid; v_until timestamptz; v_got boolean := false;
  v_pref uuid; v_honoured boolean := false;
  v_zones text[] := NULL;
  v_refused boolean := false; /* 0197 */
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_vehicle_id IS NULL
     OR p_stall_type IS NULL OR p_clock IS NULL THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'malformed');
  END IF;

  -- ══════════════════════ CHARGE-PATH FIREWALL ══════════════════════
  IF p_stall_type IN ('dcfc','l2') THEN
    RAISE WARNING 'ottoq_enact_space_assignment: REFUSED charge stall_type % (run=%, vehicle=%, source=%) - charging is section (3) only',
      p_stall_type, p_sim_run_id, p_vehicle_id, p_source;
    RETURN jsonb_build_object('assigned', false, 'reason', 'charge_path_firewall');
  END IF;

  -- ══════════════════ BUILD 3: INSPECTION IS ZONE-ADDRESSED ══════════════════
  -- The depot's 14 inspection stalls per depot are NOT distinguishable by stall_type:
  -- stall_kind='inspection' but stall_type='staging', identical to the 86 staging stalls.
  -- The ONLY discriminator in the schema is zone='arrival_inspection'. Without this the
  -- inspect purpose would scatter across ordinary staging and inspection capacity would
  -- stay unreachable -- which is exactly why 177 inspect legs never got a space.
  -- Scoped strictly to p_purpose='inspect': every other purpose keeps v_zones NULL and
  -- therefore behaves byte-for-byte as before.
  IF p_purpose = 'inspect' THEN
    v_zones := ARRAY['arrival_inspection'];
  END IF;

  v_until := GREATEST(COALESCE(p_until, p_clock + interval '30 minutes'), p_clock + interval '1 minute');

  -- ══ HONOUR THE FORWARD RESERVATION (only when it covers NOW) ══
  -- The forward calendar is only trustworthy if the reservation is what actually gets
  -- taken -- but only once its window has opened. `lower(b.during) <= p_clock` is the
  -- load-bearing clause: without it a vehicle can be admitted at 16:00 against a bay it
  -- does not hold until 18:40, which is a double-booking wearing a reservation's clothes.
  IF p_leg_id IS NOT NULL THEN
    SELECT b.stall_id INTO v_pref
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls s ON s.id = b.stall_id
     WHERE b.sim_run_id = p_sim_run_id
       AND b.leg_id     = p_leg_id
       AND b.vehicle_id = p_vehicle_id
       AND b.state IN ('held','active')
       AND lower(b.during) <= p_clock
       AND upper(b.during) >  p_clock
       AND s.depot_id   = p_depot_id
       AND s.stall_type::text = p_stall_type
       -- BUILD 3: an inspect reservation must be honoured only on an INSPECTION stall,
       -- otherwise the zone restriction above could be bypassed by a stale staging hold.
       AND (v_zones IS NULL OR s.zone = ANY (v_zones))
       AND s.status NOT IN ('maintenance','closed')
     ORDER BY b.booked_at DESC,
              /* 0063: booked_at defaults to now() — ONE real-clock value per statement —
                 and up to 15 bookings for a single vehicle share it (measured across the
                 re-cert #16 arms: 261 tie groups). Alone it is heap order, and this pick
                 chooses WHICH stall is reserved on the very next line, so it is the
                 reservation-churn seam. Content keys first, booking_id last so the order
                 is TOTAL (the 0062 principle: never trade a random-but-total order for a
                 content order that ties). */
              lower(b.during) DESC, upper(b.during) DESC, s.id, b.purpose, b.booking_id DESC LIMIT 1;

    IF v_pref IS NOT NULL AND public.ottoq_reserve_stall(v_pref, p_vehicle_id, p_clock, 900) THEN
      v_stall := v_pref; v_got := true; v_honoured := true;
    END IF;
  END IF;

  -- CHOOSE. ONE search. A candidate must be BOTH calendar-free for the window
  -- (ottoq_stall_free_between) AND physically free (the ottoq_reserve_stall CAS).
  IF NOT v_got THEN
    FOR v_cand IN
      SELECT f.stall_id
        FROM ottoq.ottoq_stall_free_between(
               p_sim_run_id, p_depot_id, p_clock, v_until, p_stall_type, NULL, 10, v_zones) f
    LOOP
      IF public.ottoq_reserve_stall(v_cand.stall_id, p_vehicle_id, p_clock, 900) THEN
        v_stall := v_cand.stall_id; v_got := true; EXIT;
      END IF;
    END LOOP;
  END IF;

  IF NOT v_got THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'no_free_space',
                              'stall_type', p_stall_type, 'purpose', p_purpose);
  END IF;

  -- RELEASE what the vehicle is vacating.
  SELECT v.current_stall_id INTO v_prev FROM public.vehicles v WHERE v.id = p_vehicle_id;

  -- ═══════════════ 0197: ASSIGNMENT IS ALL OR NOTHING ═══════════════
  -- Everything that changes the world sits in ONE subtransaction: the release
  -- of the vacated hold, both occupancy pointers, the calendar row, the leg
  -- binding. ottoq_record_enacted_booking returns NULL without raising when
  -- the stall is gone, when ottoq_book_stall refuses on the EXCLUDE, or when
  -- its own handler swallows something -- so the NULL is turned into a raise
  -- HERE, inside the block, and every write above it goes back with it.
  -- Before this the function returned assigned=true with booked=false and left
  -- the vehicle and the stall pointing at each other with nothing on the
  -- calendar behind them: occupancy no EXCLUDE defends and no KPI can trace.
  BEGIN /* 0197 */
    IF v_prev IS NOT NULL AND v_prev <> v_stall THEN
      UPDATE public.ottoq_stall_bookings
         SET state = 'done', released_at = p_clock, release_reason = 'vehicle_moved_to_next_leg',
             during = tstzrange(lower(during),
                                GREATEST(lower(during) + interval '1 second',
                                         LEAST(upper(during), p_clock)), '[)')
       WHERE sim_run_id = p_sim_run_id AND stall_id = v_prev
         AND vehicle_id = p_vehicle_id AND state IN ('held','active');
    END IF;

    -- OCCUPY.
    UPDATE public.vehicles SET current_stall_id = v_stall WHERE id = p_vehicle_id;
    UPDATE public.stalls SET current_vehicle_id = p_vehicle_id, status = 'occupied' WHERE id = v_stall;

    -- CALENDAR — the P0 atomic path, same transaction, against the EXACT stall taken.
    v_bkg := ottoq.ottoq_record_enacted_booking(
               p_sim_run_id, v_stall, p_vehicle_id, p_clock,
               p_leg_id, p_clock, v_until, p_purpose, p_source);

    IF v_bkg IS NULL THEN
      RAISE EXCEPTION 'calendar refused the enacted booking' USING ERRCODE = 'OQ197'; /* 0197 */
    END IF;

    IF p_leg_id IS NOT NULL THEN
      UPDATE public.ottoq_itinerary_legs SET to_stall_id = v_stall
       WHERE leg_id = p_leg_id AND status = 'planned';
    END IF;
  EXCEPTION WHEN SQLSTATE 'OQ197' THEN
    v_refused := true; /* 0197 */
  END;

  IF v_refused THEN /* 0197 */
    -- The subtransaction took the occupancy back with it. Drop the physical
    -- reservation too: otherwise the stall stays held for its 900-second TTL
    -- against an assignment that never happened.
    UPDATE public.stalls
       SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
     WHERE id = v_stall AND reserved_by = p_vehicle_id;
    RAISE WARNING 'ottoq_enact_space_assignment: ROLLED BACK, calendar refused run=% vehicle=% stall=% type=% purpose=% source=%',
      p_sim_run_id, p_vehicle_id, v_stall, p_stall_type, p_purpose, p_source;
    RETURN jsonb_build_object('assigned', false, 'reason', 'booking_refused',
                              'stall_id', v_stall, 'stall_type', p_stall_type,
                              'purpose', p_purpose, 'source', p_source, 'leg_id', p_leg_id);
  END IF;

  RETURN jsonb_build_object('assigned', true, 'stall_id', v_stall, 'booking_id', v_bkg,
                            'booked', true, 'purpose', p_purpose,
                            'stall_type', p_stall_type, 'until', v_until,
                            'released_stall_id', v_prev, 'source', p_source,
                            'leg_id', p_leg_id, 'honoured_reservation', v_honoured);

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_enact_space_assignment: FAILED sqlstate=% msg=% run=% vehicle=% type=% purpose=% source=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_vehicle_id, p_stall_type, p_purpose, p_source;
  RETURN jsonb_build_object('assigned', false, 'reason', 'exception', 'sqlstate', SQLSTATE);
END
$function$;

-- ---------------------------------------------------------------------
-- 2. ottoq.ottoq_reconcile_displace_stale_claim
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ottoq.ottoq_reconcile_displace_stale_claim(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_stall_type text, p_purpose text, p_clock timestamp with time zone, p_until timestamp with time zone DEFAULT NULL::timestamp with time zone, p_leg_id uuid DEFAULT NULL::uuid, p_source text DEFAULT 'bay_reconcile_displace'::text, p_tick bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_from timestamptz; v_until timestamptz;
  v_stall uuid; v_bkg uuid; v_state text; v_disp jsonb := '[]'::jsonb;
  v_ids uuid[]; v_n int := 0;
  v_refused boolean := false; v_cas_lost boolean := false; /* 0197 */
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_vehicle_id IS NULL
     OR p_stall_type IS NULL OR p_clock IS NULL THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'malformed');
  END IF;

  -- ══ FIREWALL: bay reconciliation ONLY. Not charging, not staging, not parking.
  IF p_stall_type NOT IN ('wash_bay','service_bay','detail_bay') THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'displace_firewall_non_bay',
                              'stall_type', p_stall_type);
  END IF;

  -- ══ REALITY CHECK: this authority exists only because the car IS there.
  -- If the vehicle is not physically in a bay this is a plan, not a fact, and a
  -- plan has no right to displace anything.
  SELECT v.current_state::text INTO v_state
    FROM public.vehicles v
   WHERE v.id = p_vehicle_id AND v.home_depot_id = p_depot_id;

  IF v_state IS NULL OR v_state NOT IN ('in_wash_bay','in_detail_bay','in_service_bay') THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'not_physically_present',
                              'vehicle_state', v_state);
  END IF;

  v_from  := p_clock;
  v_until := GREATEST(COALESCE(p_until, p_clock + interval '30 minutes'),
                      p_clock + interval '1 minute');

  -- ══ CHOOSE the stall whose claim is weakest, among stalls NOBODY IS IN.
  -- A genuinely free stall (0 active, 0 held) sorts first, so this is also a
  -- safe fallback and not only a displacement path.
  SELECT s.id INTO v_stall
    FROM public.stalls s
   WHERE s.depot_id = p_depot_id
     AND s.stall_type::text = p_stall_type
     AND s.status NOT IN ('maintenance','closed')
     AND NOT EXISTS (
           SELECT 1 FROM public.vehicles vx
            WHERE vx.current_stall_id = s.id
              AND vx.current_state IN ('in_wash_bay'::vehicle_state,
                                       'in_detail_bay'::vehicle_state,
                                       'in_service_bay'::vehicle_state))
   ORDER BY
     (SELECT count(*) FROM public.ottoq_stall_bookings b
       WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
         AND b.state = 'active' AND b.during && tstzrange(v_from, v_until, '[)')) ASC,
     (SELECT count(*) FROM public.ottoq_stall_bookings b
       WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
         AND b.state = 'held' AND b.during && tstzrange(v_from, v_until, '[)')) ASC,
     s.distance_from_entrance NULLS LAST, s.stall_code
   LIMIT 1;

  IF v_stall IS NULL THEN
    -- Genuine over-admission: the twin put more cars in bays than the depot has
    -- bays, and every bay has a real car in it. Nothing to displace.
    RETURN jsonb_build_object('assigned', false, 'reason', 'no_physically_free_stall',
                              'stall_type', p_stall_type);
  END IF;

  -- ══ CAPTURE the losing claims BEFORE overwriting them (RETURNING would hand
  -- back the new state, and the old state is the audit-relevant fact).
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'booking_id', b.booking_id, 'vehicle_id', b.vehicle_id,
           'leg_id', b.leg_id, 'state', b.state, 'booked_by', b.booked_by,
           'during', to_jsonb(b.during))), '[]'::jsonb),
         COALESCE(array_agg(b.booking_id), ARRAY[]::uuid[])
    INTO v_disp, v_ids
    FROM public.ottoq_stall_bookings b
   WHERE b.sim_run_id = p_sim_run_id
     AND b.stall_id   = v_stall
     AND b.state IN ('held','active')
     AND b.during && tstzrange(v_from, v_until, '[)')
     AND b.vehicle_id <> p_vehicle_id;

  -- ═══════════════ 0197: DISPLACEMENT IS ALL OR NOTHING ═══════════════
  -- This path supersedes OTHER vehicles' claims and hands their planned legs
  -- back before it books its own. If the calendar then refuses, the old state
  -- must come back with it -- otherwise a refused reconciliation leaves the
  -- losers displaced, the winner unbooked and the conflict ledger silent.
  BEGIN /* 0197 */
    IF array_length(v_ids,1) > 0 THEN
      UPDATE public.ottoq_stall_bookings b
         SET state = 'superseded', released_at = p_clock,
             release_reason = 'displaced_by_physical_occupant'
       WHERE b.booking_id = ANY (v_ids);

      -- Hand the displaced legs back to the planner. PLANNED only — an active or
      -- in_progress leg is never touched, which is what keeps this out of the
      -- reassignment gate's territory.
      UPDATE public.ottoq_itinerary_legs l
         SET to_stall_id = NULL
       WHERE l.leg_id IN (SELECT (e->>'leg_id')::uuid FROM jsonb_array_elements(v_disp) e
                           WHERE NULLIF(e->>'leg_id','') IS NOT NULL)
         AND l.leg_id IS DISTINCT FROM p_leg_id
         AND l.status = 'planned';
    END IF;

    -- ══ Clear the stale PHYSICAL claim. Proven safe: we established above that no
    -- vehicle is physically in this stall.
    UPDATE public.stalls
       SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL
     WHERE id = v_stall;

    IF NOT public.ottoq_reserve_stall(v_stall, p_vehicle_id, p_clock, 900) THEN
      RAISE EXCEPTION 'reserve CAS lost' USING ERRCODE = 'OQ198'; /* 0197 */
    END IF;

    -- ══ OCCUPY. Only the PRESENT vehicle's pointer is written.
    UPDATE public.vehicles SET current_stall_id = v_stall WHERE id = p_vehicle_id;
    UPDATE public.stalls SET current_vehicle_id = p_vehicle_id, status = 'occupied'
     WHERE id = v_stall;

    v_bkg := ottoq.ottoq_record_enacted_booking(
               p_sim_run_id, v_stall, p_vehicle_id, p_clock,
               p_leg_id, v_from, v_until, p_purpose, p_source);

    IF v_bkg IS NULL THEN
      RAISE EXCEPTION 'calendar refused the enacted booking' USING ERRCODE = 'OQ197'; /* 0197 */
    END IF;

    IF p_leg_id IS NOT NULL THEN
      UPDATE public.ottoq_itinerary_legs SET to_stall_id = v_stall
       WHERE leg_id = p_leg_id AND status = 'planned';
    END IF;

    -- ══ FIRST-CLASS CONFLICT RECORD. One row per displaced claim. This is the
    -- point of the exercise: a displacement that is not recorded is indistinguish-
    -- able from a bug, and "zero double-bookings" would again be a statement about
    -- writes that never happened rather than about conflicts that were resolved.
    BEGIN
      INSERT INTO public.space_conflict_ledger
        (sim_run_id, depot_id, sim_clock, tick_seq, stall_id, stall_type,
         conflict_kind, resolution, present_vehicle_id, present_vehicle_state,
         displaced_vehicle_id, displaced_booking_id, displaced_state,
         displaced_during, displaced_leg_id, displaced_booked_by,
         new_booking_id, detail)
      SELECT p_sim_run_id, p_depot_id, p_clock, p_tick, v_stall, p_stall_type,
             'stale_claim_displaced', 'reality_outranks_plan',
             p_vehicle_id, v_state,
             NULLIF(e->>'vehicle_id','')::uuid,
             NULLIF(e->>'booking_id','')::uuid,
             e->>'state',
             tstzrange(((e->'during')->>'lower')::timestamptz,
                       ((e->'during')->>'upper')::timestamptz, '[)'),
             NULLIF(e->>'leg_id','')::uuid,
             e->>'booked_by',
             v_bkg,
             jsonb_build_object('source', p_source, 'purpose', p_purpose,
                                'window_from', v_from, 'window_to', v_until,
                                'booked', true)
        FROM jsonb_array_elements(v_disp) e;
      GET DIAGNOSTICS v_n = ROW_COUNT;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'displace_stale_claim: conflict ledger write FAILED % % (stall=%, vehicle=%)',
        SQLSTATE, SQLERRM, v_stall, p_vehicle_id;
    END;
  EXCEPTION
    WHEN SQLSTATE 'OQ197' THEN v_refused  := true; /* 0197 */
    WHEN SQLSTATE 'OQ198' THEN v_cas_lost := true; /* 0197 */
  END;

  IF v_cas_lost THEN /* 0197 */
    -- The subtransaction rolled the supersedes and the claim-clear back with it:
    -- we lost the race, so nothing about this stall changed.
    RETURN jsonb_build_object('assigned', false, 'reason', 'reserve_cas_lost',
                              'stall_id', v_stall);
  END IF;

  IF v_refused THEN /* 0197 */
    UPDATE public.stalls
       SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
     WHERE id = v_stall AND reserved_by = p_vehicle_id;
    RAISE WARNING 'ottoq_reconcile_displace_stale_claim: ROLLED BACK, calendar refused run=% vehicle=% stall=% type=% purpose=% source=%',
      p_sim_run_id, p_vehicle_id, v_stall, p_stall_type, p_purpose, p_source;
    RETURN jsonb_build_object('assigned', false, 'reason', 'booking_refused',
                              'stall_id', v_stall, 'stall_type', p_stall_type,
                              'purpose', p_purpose, 'source', p_source);
  END IF;

  RETURN jsonb_build_object('assigned', true, 'stall_id', v_stall, 'booking_id', v_bkg,
                            'booked', true, 'displaced', v_n,
                            'displaced_claims', v_disp, 'purpose', p_purpose,
                            'stall_type', p_stall_type, 'until', v_until,
                            'source', p_source, 'leg_id', p_leg_id);

EXCEPTION WHEN OTHERS THEN
  -- NO-ABORT GUARANTEE. Reconciliation must never take decide_tick down.
  RAISE WARNING 'ottoq_reconcile_displace_stale_claim: FAILED % % run=% vehicle=% type=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_vehicle_id, p_stall_type;
  RETURN jsonb_build_object('assigned', false, 'reason', 'exception', 'sqlstate', SQLSTATE);
END
$function$;

-- =====================================================================
-- ASSERTIONS
-- =====================================================================
DO $assert$
DECLARE
  v_src text; v_n int; v_keys text[];
  v_depot uuid := 'aacd0bb0-2d02-d101-72cc-33f70e950bc8';  -- Grid Fixture: 4 vehicles, 4 free staging
  v_veh uuid; v_run uuid := '01970000-0000-4000-8000-000000000197';
  v_res jsonb; v_ptr_before uuid; v_ptr_after uuid; v_occ int; v_resv int; v_msg text;
  v_assigned text; v_reason text;
  v_orphans int; v_with_any int;
BEGIN
  -- ── A1. SHAPE. Both functions carry the subtransaction and the raise, and
  --     neither can still report a booking it did not get.
  FOR v_src IN
    SELECT pg_get_functiondef(p.oid)
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'ottoq'
       AND p.proname IN ('ottoq_enact_space_assignment','ottoq_reconcile_displace_stale_claim')
       AND p.prokind = 'f'
  LOOP
    IF v_src ~ '''booked'', v_bkg IS NOT NULL' THEN
      RAISE EXCEPTION '0197 A1 FAILED: a function still reports booked = (v_bkg IS NOT NULL); assigned=true can still mean unbooked';
    END IF;
    v_n := (length(v_src) - length(replace(v_src, 'ERRCODE = ''OQ197''', ''))) / length('ERRCODE = ''OQ197''');
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0197 A1 FAILED: expected exactly one OQ197 raise per function, found %', v_n;
    END IF;
    IF v_src !~ 'EXCEPTION\s+WHEN SQLSTATE ''OQ197'' THEN' AND v_src !~ 'WHEN SQLSTATE ''OQ197'' THEN v_refused' THEN
      RAISE EXCEPTION '0197 A1 FAILED: the OQ197 raise has no handler, so it would escape to the outer catch-all';
    END IF;
    v_n := (length(v_src) - length(replace(v_src, '''assigned'', true', ''))) / length('''assigned'', true');
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0197 A1 FAILED: expected exactly one success return per function, found %', v_n;
    END IF;
  END LOOP;
  RAISE NOTICE '0197 A1: both functions carry one OQ197 raise, one handler and one success return';

  -- ── A2. THE CLASS. A function that writes occupancy AND books is exactly the
  --     two fixed here. A third one appearing later must not inherit the defect
  --     silently, so its arrival refuses this migration.
  SELECT array_agg(n.nspname||'.'||p.proname ORDER BY n.nspname, p.proname) INTO v_keys
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','ottoq','twin')
     AND p.proname NOT LIKE '%\_backup\_%'
     AND pg_get_functiondef(p.oid) ~ 'ottoq_record_enacted_booking'
     AND pg_get_functiondef(p.oid) ~ 'current_vehicle_id\s*=\s*p_vehicle_id';
  IF v_keys IS DISTINCT FROM ARRAY['ottoq.ottoq_enact_space_assignment','ottoq.ottoq_reconcile_displace_stale_claim'] THEN
    RAISE EXCEPTION '0197 A2 FAILED: functions that both write occupancy and book are %, not the two this migration fixes', v_keys;
  END IF;
  -- The one occupancy writer that does NOT book here is the charge path, which
  -- books in section (3) of ottoq_decide_tick. Recorded so that a change to it
  -- is noticed rather than assumed benign.
  SELECT array_agg(n.nspname||'.'||p.proname ORDER BY n.nspname, p.proname) INTO v_keys
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','ottoq','twin')
     AND p.proname NOT LIKE '%\_backup\_%'
     AND pg_get_functiondef(p.oid) ~ 'current_vehicle_id\s*=\s*p_vehicle_id'
     AND pg_get_functiondef(p.oid) !~ 'ottoq_record_enacted_booking';
  IF v_keys IS DISTINCT FROM ARRAY['twin.ottoq_sim_start_charge_session'] THEN
    RAISE EXCEPTION '0197 A2 FAILED: occupancy writers that never book are %, expected only twin.ottoq_sim_start_charge_session', v_keys;
  END IF;
  RAISE NOTICE '0197 A2: two book-and-occupy functions (both fixed), one occupy-only (the charge path)';

  -- ── A3. THE LIVE PROOF, ROLLED BACK. Stub the recorder to refuse, drive a real
  --     assignment on the Grid Fixture depot, and require that NOTHING survives.
  --     Run against the pre-0197 function this same probe returned:
  --       assigned=true reason=- booked=false ptr NULL -> 4b535878
  --       stalls_pointing_at_vehicle=1 stalls_reserved_by_vehicle=1
  --     which is the defect, reproduced on demand. If the probe cannot make the
  --     recorder refuse, or the depot has no free staging stall, this assertion
  --     fails rather than passing vacuously.
  SELECT id, current_stall_id INTO v_veh, v_ptr_before
    FROM public.vehicles WHERE home_depot_id = v_depot ORDER BY id LIMIT 1;
  IF v_veh IS NULL THEN RAISE EXCEPTION '0197 A3 FAILED: probe depot % has no vehicle', v_depot; END IF;

  BEGIN
    CREATE OR REPLACE FUNCTION ottoq.ottoq_record_enacted_booking(p_sim_run_id uuid, p_stall_id uuid, p_vehicle_id uuid, p_clock timestamp with time zone, p_leg_id uuid DEFAULT NULL::uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_purpose text DEFAULT NULL::text, p_source text DEFAULT 'unknown'::text)
      RETURNS uuid LANGUAGE sql AS $stub$ SELECT NULL::uuid $stub$;

    v_res := ottoq.ottoq_enact_space_assignment(
               v_run, v_depot, v_veh, 'staging', 'staging',
               now(), now() + interval '30 minutes', NULL, 'probe_0197');

    SELECT current_stall_id INTO v_ptr_after FROM public.vehicles WHERE id = v_veh;
    SELECT count(*) INTO v_occ  FROM public.stalls WHERE current_vehicle_id = v_veh;
    SELECT count(*) INTO v_resv FROM public.stalls WHERE reserved_by = v_veh;

    RAISE EXCEPTION USING ERRCODE = 'P0197', MESSAGE =
      coalesce(v_res->>'assigned','?')||'|'||coalesce(v_res->>'reason','-')||'|'
      ||coalesce(v_ptr_after::text,'NULL')||'|'||v_occ||'|'||v_resv;
  EXCEPTION WHEN SQLSTATE 'P0197' THEN
    v_msg      := SQLERRM;                        -- the stub is rolled back with the block
    v_assigned := split_part(v_msg, '|', 1);
    v_reason   := split_part(v_msg, '|', 2);
    v_ptr_after:= NULLIF(split_part(v_msg, '|', 3), 'NULL')::uuid;
    v_occ      := split_part(v_msg, '|', 4)::int;
    v_resv     := split_part(v_msg, '|', 5)::int;
  END;

  IF v_assigned <> 'false' THEN
    RAISE EXCEPTION '0197 A3 FAILED: a refused booking still returned assigned=% (reason %)', v_assigned, v_reason;
  END IF;
  IF v_reason <> 'booking_refused' THEN
    RAISE EXCEPTION '0197 A3 FAILED: expected reason booking_refused, got % - the probe did not exercise the refusal path', v_reason;
  END IF;
  IF v_ptr_after IS DISTINCT FROM v_ptr_before THEN
    RAISE EXCEPTION '0197 A3 FAILED: vehicle pointer moved % -> % past a refused booking',
      coalesce(v_ptr_before::text,'NULL'), coalesce(v_ptr_after::text,'NULL');
  END IF;
  IF v_occ <> 0 THEN
    RAISE EXCEPTION '0197 A3 FAILED: % stall(s) still point at the vehicle after a refused booking', v_occ;
  END IF;
  IF v_resv <> 0 THEN
    RAISE EXCEPTION '0197 A3 FAILED: % stall(s) still reserved by the vehicle after a refused booking (the 900s TTL would hold them)', v_resv;
  END IF;
  RAISE NOTICE '0197 A3: refused booking left no occupancy, no pointer and no reservation (probe rolled back)';

  -- ── A4. The Benchmark residue is SEEDING, not a booking refusal. If any of
  --     those occupied stalls carried a booking of any state, they would be
  --     evidence of this defect in the wild and would belong in the fix, not in
  --     a footnote.
  SELECT count(*),
         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                                         WHERE b.stall_id = s.id AND b.vehicle_id = s.current_vehicle_id))
    INTO v_orphans, v_with_any
    FROM public.stalls s
   WHERE s.depot_id = '22222222-2222-2222-2222-222222222222'
     AND s.current_vehicle_id IS NOT NULL;
  IF v_with_any <> 0 THEN
    RAISE EXCEPTION '0197 A4 FAILED: % of % occupied Benchmark stalls DO have a booking row - the residue is not seeding and this migration''s scope is wrong', v_with_any, v_orphans;
  END IF;
  RAISE NOTICE '0197 A4: % occupied Benchmark stalls carry no booking of any state - seeding residue, recorded not fixed', v_orphans;

  RAISE NOTICE '0197: all assertions passed';
END $assert$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0197_an_assignment_the_calendar_refused_is_not_an_assignment', TRUE,
  'ottoq.ottoq_enact_space_assignment and ottoq.ottoq_reconcile_displace_stale_claim wrote both occupancy pointers and then called '
  'ottoq.ottoq_record_enacted_booking, which returns NULL WITHOUT raising on three ordinary paths (stall row gone, ottoq_book_stall '
  'refused on the EXCLUDE, its own outer handler swallowed something). Nothing rolled back, and the functions returned assigned=true '
  'with booked=false; all four call sites read only assigned, so the tick proceeded as though the space were held. A live probe on the '
  'Grid Fixture depot with the recorder stubbed to refuse reproduced it exactly: assigned=true booked=false, vehicle pointer NULL -> '
  '4b535878, one stall pointing at the vehicle and one reserved by it, with nothing on the calendar behind any of it. Fix: every '
  'world-changing statement in both functions moves inside one plpgsql subtransaction; a NULL from the recorder raises OQ197 inside it, '
  'which rolls back the vacated-hold release, both occupancy pointers, the calendar row, the leg binding and (in the displace path) the '
  'supersede of the losing claims and the conflict-ledger row; the caller gets assigned=false, reason=booking_refused, and the physical '
  'reservation is dropped so the stall is not held for its 900s TTL. A3 re-runs that probe and requires nothing to survive. Blast radius '
  'measured before applying: over rounds 16 and 17 (28 arms) the silent-NULL branch fired ZERO times - 0 booking REFUSED, 0 recorder '
  'FAILED, 0 stall-not-found; the 254 ottoq_enact_space_assignment FAILED lines are raises (158 P0001 arm-interlock, 96 23505 on '
  'idx_stalls_one_vehicle_per_stall) and a plpgsql block with a handler is already a subtransaction, so those rolled themselves back. '
  'Not fixed, recorded: 96 attempts in two rounds to seat a second vehicle in an occupied stall stopped only by the unique index (the '
  'reserve CAS and ottoq_stall_free_between are not preventing the attempt); 64 of the Benchmark depot''s 160 stalls resting occupied '
  'with no booking of any state (A4 proves that is seeding residue, not a refusal leak). '
  'forces_recert=TRUE: the decide path changed. Prediction: because the refusal branch fired zero times in rounds 16 and 17, NO canon '
  'moves - every h_cmd, h_dec, h_evt, h_bkg, h_nrg, endst and boot value must match round 17 exactly. A canon that moves means the '
  'branch was reachable in a way the log census did not show, and will be said so.',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;
