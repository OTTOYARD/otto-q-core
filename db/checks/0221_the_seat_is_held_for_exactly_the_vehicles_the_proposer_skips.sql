-- 0221  THE SEAT IS HELD FOR EXACTLY THE VEHICLES THE PROPOSER SKIPS
--
-- Read-only. 2026-09-14, ~02:40 AM CT (07:40 UTC). Run c288555a (seed 171717,
-- 20 ticks, run_by=proposer_live, armed by the loop itself per 0218).
--
-- 0219 filed G54 as "the right of first refusal holds a seat for a proposer
-- that left" and shaped the fix as a LIVENESS CHECK: stop holding a seat for a
-- proposer that has not shown up. 0284 built the instrument and measured
-- answered_pct = 0.0 on two runs.
--
-- THAT DIAGNOSIS WAS WRONG, AND THIS FILE REPLACES IT. The proposer had not
-- left. It fired eight times during that run, on schedule, armed, with a
-- version-1 facts frame. It skipped the held vehicles ON PURPOSE, because the
-- kernel and the proposer do not mean the same thing by "already has a place".
--
-- ---------------------------------------------------------------------------
-- THE TWO PREDICATES, SIDE BY SIDE
--
-- KERNEL -- public.ottoq_cuopt_first_refusal_arm decides who gets a seat held:
--
--     AND NOT EXISTS (SELECT 1 FROM stalls s
--                      WHERE s.reserved_by = v.id
--                        AND s.stall_type::text IN ('dcfc','l2')      <== CHARGE
--                        AND COALESCE(s.reservation_expires_at, v_sim) >= v_sim)
--
--   A vehicle parked on a STAGING stall still counts as unplaced, because a
--   staging hold is a parking spot, not a service assignment. The kernel is
--   about to decide it -- that is what arming the hold MEANS.
--
-- PROPOSER -- proposer/forward_proposer.py::vehicle_is_held decides who it
-- will plan for:
--
--     if vehicle.get("reserved_stall_id"): return True
--     return bool(vehicle.get("has_live_booking"))
--
--   ANY reservation, ANY held-or-active booking, on ANY stall type. A staging
--   temp_hold makes the vehicle invisible.
--
-- So the kernel holds a seat open for a population the proposer has already
-- decided not to look at. Not one of those holds was ever answerable.
--
-- ---------------------------------------------------------------------------
-- THE MEASUREMENT
--
-- A. THE FIRE LOG. Eight fires, every one armed (3 of 3 keys), every one with
--    frame_facts_version = 1, every one inside the run:
--
--      fire  tick  serviceable  n_vehicles_held  n_rows  status
--        13     1            7                7       0  empty
--        14     3           13               13       0  empty
--        15     6           12               12       0  empty
--        16     9            0                0       0  empty
--        17    11            6                0       6  SUBMITTED
--        18    14            3                3       0  empty
--        19    17            7                7       0  empty
--        20    19            2                2       0  empty
--
--    n_vehicles_held EQUALS the serviceable population in all seven empty
--    fires, and the ONE fire that produced proposals is the one where it was
--    zero. The proposer was not idle and not broken: at every other fire, every
--    vehicle it could have planned for was filtered by vehicle_is_held.
--
--    Fire 17 is the control. Six vehicles, none held, CP-SAT solved both passes
--    OPTIMAL in 0.045 s deterministic time (OR-Tools 9.15.6755), six proposals
--    submitted, four enacted. The machinery works when it is allowed to see.
--
-- B. WHAT WAS HOLDING THEM. Every deferral this run armed, joined to the
--    booking covering its own armed_at_sim instant:
--
--      19 deferral rows, ticks 4..20
--      18 of 19 had a booking covering the arm instant on a STAGING stall:
--         purpose temp_hold (14), perimeter_hold (3), inspect (1)
--       1 of 19 (ec5d2c18, tick 8) had no booking at all
--       3 of the 18 ALSO had a charge (l2) booking whose window covered the
--         instant -- 4 rows across those 3 vehicles
--
--    THE FIRST DRAFT OF THIS FILE SAID ZERO CHARGE BOOKINGS. It was wrong, and
--    the correction is worth more than the original claim, because sorting the
--    four rows out is what exposed a SECOND disagreement. `state` is not
--    historised, so "was it live at the arm instant" is answered by
--    released_at, which this run records on the sim clock:
--
--      veh       armed_at_sim  l2 booking released_at   live at arm?
--      aee7a860  08:00         08:00                    no, released at it
--      cadd7c81  09:00         08:00                    no, released before
--      cadd7c81  09:00         09:00                    no, released at it
--      a1111111  09:00         10:00                    YES -- still live
--
--    So exactly ONE of nineteen (a1111111) held a live charge place when the
--    kernel armed a first-refusal seat for it. And the kernel armed it anyway,
--    because the two sides do not merely disagree about STALL TYPE -- they read
--    DIFFERENT LEDGERS:
--
--      kernel    stalls.reserved_by + reservation_expires_at  (the reservation)
--      proposer  ottoq_stall_bookings.state in (held,active)  (the calendar)
--
--    A vehicle whose stall reservation has lapsed while its calendar booking is
--    still held reads unplaced to one and placed to the other. CLAUDE.md 2.3
--    calls ottoq_stall_bookings "the calendar", so the calendar is the
--    authority and arming a1111111 was the kernel's error, not the proposer's.
--    One vehicle is thin evidence for changing the decide path, so 0287 does not
--    touch the arm predicate; it publishes BOTH ledgers as separate facts and
--    takes their UNION for the held test, which keeps a1111111 correctly skipped
--    and frees the other eighteen. Filed as G56.
--
--    The staging bookings were in state held/active at that moment -- the states
--    has_live_booking tests -- and are terminal now only because the run has
--    since ended. So has_live_booking answered TRUE for 18 of the 19 vehicles
--    the kernel had just declared unplaced, and 17 of those 18 had nothing but
--    a parking spot.
--
-- C. THE ANSWER RATE, RE-DERIVED. ottoq_first_refusal_outcomes (0284) reports
--    19 holds, 19 unanswered, answered_pct 0.0 for this run; 25/25 for
--    97769e7e. Same numbers as 0219 and 0284. What is new is the cause.
--
-- ---------------------------------------------------------------------------
-- WHY 0265 WROTE THE WIDER PREDICATE, AND WHY IT IS STILL HALF RIGHT
--
-- The frame builder's own comment:
--
--   0265/L-60. A staged vehicle usually already holds a reservation the frame
--   did not show, so a proposer planned for vehicles that were never going to
--   be re-decided.
--
-- For a vehicle holding a live DCFC or L2 reservation that is exactly true: the
-- decide path will not ask again, and a proposal for it expires unread. 0265
-- closed a real leak. What it did not do is separate the two populations:
--
--   holds a CHARGE place   -> will not be re-decided  -> skip (0265 correct)
--   holds a STAGING place  -> IS about to be decided  -> skip (0265 wrong)
--
-- and the deferral ledger is the engine's own evidence for the second line. A
-- vehicle only gets a deferral row because ottoq_cuopt_first_refusal_arm looked
-- at it and said "this one is unplaced and I am holding it for a proposer."
--
-- ---------------------------------------------------------------------------
-- THE SHAPE OF THE FIX (0287)
--
-- The frame carries FACTS; the proposer decides. So the frame gains, inside the
-- existing proposer_frame_facts block:
--
--   reserved_stall_type        the type of the reserved stall, or NULL
--   live_booking_stall_types   the distinct types of its held/active bookings
--   holds_charge_reservation   a live reservation on a dcfc/l2 stall -- the
--                              KERNEL's ledger, published
--   holds_charge_booking       a held/active booking on a dcfc/l2 stall -- the
--                              CALENDAR's ledger, published
--   holds_charge_place         the UNION of the two. Union, not intersection:
--                              if either ledger says the vehicle has a charge
--                              place, treat it as placed. That is the safe
--                              direction, and it is what keeps a1111111 (B)
--                              correctly skipped while freeing the other 18.
--
-- and selector.facts_version goes 1 -> 2 so a consumer can tell which contract
-- it received. vehicle_is_held then reads holds_charge_place when the frame
-- declares version 2, and falls back to the version-1 test otherwise -- the
-- same "never a guess" rule 0265 itself wrote.
--
-- ONE MORE DEFECT FOUND WHILE READING, FIXED IN THE SAME FILE. The facts gate
-- is written `CASE WHEN g.facts = 1` -- an EQUALITY. Setting
-- proposer_frame_facts to 2, the obvious way to ask for more facts, turns the
-- whole block OFF and hands the proposer a blind frame, which 0218 taught the
-- loop to refuse. Every live row is 1 today so nothing is affected now; 0287
-- widens it to >= 1, the same shape 0286 catalogued enforce_site_charge_cap as.
--
-- ---------------------------------------------------------------------------
-- THE PATTERN, SIXTH INSTANCE. 0218 listed five: apparatus built correctly,
-- switch left off, nobody named to flip it. This one is the variant: apparatus
-- built correctly ON BOTH SIDES, and the two sides given definitions that do
-- not meet. Nothing is off. Both halves do exactly what they say. The seat is
-- held, the proposer fires, and the two never intersect -- which is why it
-- reads as "the proposer left" until you join the two ledgers on the vehicle.

-- === THE QUERIES, AS RUN ====================================================

-- Q1. The fire log for the run: how many were serviceable, how many held.
SELECT f.tick_seq, f.status,
       f.n_in_serviceable_state,
       (f.fire->>'n_vehicles_held')::int AS n_vehicles_held,
       f.n_rows, (f.fire->'arming'->>'verdict') AS arming,
       (f.fire->>'frame_facts_version')::int AS facts_version
  FROM public.ottoq_proposer_fire_log f
 WHERE f.sim_run_id = (SELECT sim_run_id FROM public.ottoq_sim_runs
                        ORDER BY started_at DESC LIMIT 1)
 ORDER BY f.tick_seq;

-- Q2. Every hold, and the booking that was covering it at the instant it armed.
--     `during @> armed_at_sim` is the honest test: the booking window against
--     the SIM clock the deferral itself recorded, not the wall clock.
SELECT left(d.vehicle_id::text,8) AS veh, d.armed_at_tick AS t,
       s.stall_type::text AS booked_stall_type, b.purpose, b.state
  FROM public.ottoq_cuopt_deferrals d
  LEFT JOIN public.ottoq_stall_bookings b
         ON b.vehicle_id = d.vehicle_id
        AND b.sim_run_id = d.sim_run_id
        AND b.during @> d.armed_at_sim
  LEFT JOIN public.stalls s ON s.id = b.stall_id
 WHERE d.sim_run_id = (SELECT sim_run_id FROM public.ottoq_sim_runs
                        ORDER BY started_at DESC LIMIT 1)
 ORDER BY d.armed_at_tick, veh;

-- Q3. The one-line summary: of the vehicles the kernel held, how many held a
--     CHARGE place (which would justify the proposer skipping them)?
SELECT count(*) FILTER (WHERE bt.types IS NULL)                       AS held_with_no_booking,
       count(*) FILTER (WHERE bt.types @> ARRAY['staging'])           AS held_by_staging,
       count(*) FILTER (WHERE bt.types && ARRAY['dcfc','l2'])         AS held_by_charge,
       count(*)                                                       AS total_holds
  FROM public.ottoq_cuopt_deferrals d
  LEFT JOIN LATERAL (
    SELECT array_agg(DISTINCT s.stall_type::text) AS types
      FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
     WHERE b.vehicle_id = d.vehicle_id AND b.sim_run_id = d.sim_run_id
       AND b.during @> d.armed_at_sim) bt ON true
 WHERE d.sim_run_id = (SELECT sim_run_id FROM public.ottoq_sim_runs
                        ORDER BY started_at DESC LIMIT 1);
-- measured: held_with_no_booking=1, held_by_staging=18, held_by_charge=3,
--           total_holds=19.  held_by_charge and held_by_staging OVERLAP: the
--           three charge-booking vehicles each also hold a staging booking.

-- Q3b. Which of those charge bookings was actually LIVE when the seat was
--      armed. `state` is current, not historical, so released_at is the only
--      honest test -- and in this run it is recorded on the sim clock, the same
--      clock armed_at_sim uses.
SELECT left(d.vehicle_id::text,8) AS veh, d.armed_at_tick AS t, d.armed_at_sim,
       b.purpose, b.state, b.released_at, b.release_reason,
       (b.released_at IS NULL OR b.released_at > d.armed_at_sim) AS live_at_arm
  FROM public.ottoq_cuopt_deferrals d
  JOIN public.ottoq_stall_bookings b
    ON b.vehicle_id = d.vehicle_id AND b.sim_run_id = d.sim_run_id
   AND b.during @> d.armed_at_sim
  JOIN public.stalls s ON s.id = b.stall_id
 WHERE s.stall_type::text IN ('dcfc','l2')
   AND d.sim_run_id = (SELECT sim_run_id FROM public.ottoq_sim_runs
                        ORDER BY started_at DESC LIMIT 1)
 ORDER BY d.armed_at_tick;
-- measured: 4 rows, 3 vehicles, exactly ONE live_at_arm = true (a1111111,
-- armed 09:00, released 10:00). See section B: that one is G56, not this file's
-- defect -- the kernel read the reservation, the calendar said otherwise.

-- Q4. The gate that turns off when you turn it up. Every live row is 1.
SELECT scope_type, param_value, updated_by
  FROM public.ottoq_policy_params WHERE param_key = 'proposer_frame_facts'
 ORDER BY updated_at;
-- measured: 3 rows, all run-scoped, all 1, all written by the loop's arming.
-- No global row: the default in ottoq_build_decision_frame is 0, which is why
-- a certification arm (which sets nothing) sees no facts block at all -- and
-- that is 0287's forces_recert=false argument.
