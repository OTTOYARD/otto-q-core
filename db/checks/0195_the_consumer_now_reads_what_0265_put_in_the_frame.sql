-- 0195  THE CONSUMER NOW READS WHAT 0265 PUT IN THE FRAME
--
-- 0265 (applied 2026-09-13, version 20260913122605) made ottoq_build_decision_frame
-- carry the facts the proposal selector filters on. A producer nobody reads is not a
-- fix, and 0265's own step 9 named the other half: the proposer must consume them.
-- This is that half, plus the measurement that says the two agree.
--
-- WHAT CHANGED ON THE CONSUMER SIDE (proposer/forward_proposer.py, bridge/*.py):
--
--   1. stall_is_free() now CONJOINS the door's verdict with the shield's.
--      Before: status == 'available' AND no current vehicle  (the shield's half).
--      After : that, AND `offerable` when the frame carries it (the door's half).
--      NOT a substitution, and this is the subtle part -- `offerable` does not read
--      stalls.status, and neither does the selector, so a stall in `maintenance` on a
--      free healthy unreserved charger is offerable and the DOOR would take a
--      proposal for it. The SHIELD is what refuses that one. Trading a refusal at the
--      door for a refusal at the shield is not progress, so a point must pass both.
--
--   2. stall_block_reason() names WHY, in the selector's own vocabulary:
--      occupied / status_<x> / no_charger / charger_<state> / charger_stale /
--      reserved. Most specific first, exactly one per stall. 0186's diagnosis --
--      "31 occupied, 7 reserved, 2 faulted, 0 offerable" -- was the single most
--      useful line either live D3 run produced and it took a hand query to get it.
--      It is now on every fire record as `stalls_blocked`, on the proposed path and
--      on the empty path alike.
--
--   3. vehicle_is_held() closes L-60, which the docstring had been ASSERTING and the
--      code could not perform. _serviceable_in already said the population an
--      out-of-process proposer can be heard on is unreserved arrivals; the frame
--      carried neither reservations nor bookings, so the narrowing was words. 0265
--      carries reserved_stall_id and has_live_booking per vehicle and the proposer
--      now skips both. Skipped and COUNTED (`n_vehicles_held`), never silently
--      absent: ~200 abstention rows a tick for vehicles nobody asked about is noise
--      in the proposals table, not evidence.
--
--   4. frame_facts_version() feature-detects 0265's `selector` block. The bridge
--      records it beside the three counts, because 0 held under version 1 is a
--      measurement and 0 held under no version is a blindness, and a fire record
--      that cannot tell them apart publishes the second as the first.
--
--   5. The LLM proposer's digest SHOWS offerable/reservation_live/charger_state and
--      does not enforce them. Law 2 keeps every charge-capable stall in the digest,
--      taken ones included -- an unsafe-but-well-formed proposal must remain
--      possible. What changes is that the model can see which stalls the selector
--      would discard instead of naming one and having the row die unread.
--
-- ABSENCE IS THE OLD BEHAVIOUR IN ALL FIVE. The facts appear only behind
-- ottoq_policy_get(run,'proposer_frame_facts',0), so every certification arm and
-- every pre-0265 fixture sees a frame without them and is read exactly as before.
-- The consumer never guesses a verdict the frame did not give it.

-- ---------------------------------------------------------------------------
-- M1. THE CLOCK IS LOAD-BEARING, MEASURED RATHER THAN RESTATED.
--     0265 says <clk> is the SIM clock and that a consumer comparing heartbeats to
--     the wall clock abstains on the entire depot. Measured 2026-09-13 against
--     now(): all 40 flagship charge stalls came back charger_fresh=false and
--     offerable=false -- a proposer reading that frame would have refused the site
--     with "not one is offerable this tick (1 charger_faulted, 39 charger_stale)".
--     Against the twin's own clock (2026-09-02T02:00:00Z, the frozen world time the
--     heartbeats are stamped in) the same 40 rows come back 39 offerable.
--     The wall clock does not make the proposer wrong quietly; it makes it silent.
-- ---------------------------------------------------------------------------
WITH g AS (SELECT '2026-09-02T02:00:00+00'::timestamptz AS clk),
r AS (
  SELECT s.current_vehicle_id, s.status, s.ocpp_charger_id, s.reserved_by,
         c.station_state, c.last_heartbeat_at,
         (s.reserved_by IS NOT NULL
          AND COALESCE(s.reservation_expires_at,'infinity'::timestamptz) > g.clk) AS reservation_live,
         (c.last_heartbeat_at IS NOT NULL
          AND c.last_heartbeat_at >= g.clk - interval '90 seconds') AS charger_fresh,
         (s.current_vehicle_id IS NULL AND s.ocpp_charger_id IS NOT NULL
          AND c.station_state = 'Available' AND c.last_heartbeat_at IS NOT NULL
          AND c.last_heartbeat_at >= g.clk - interval '90 seconds'
          AND (s.reserved_by IS NULL
               OR COALESCE(s.reservation_expires_at,'-infinity'::timestamptz) <= g.clk)) AS offerable
  FROM stalls s
  LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id, g
  WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
    AND s.stall_type IN ('dcfc','l2'))
SELECT CASE WHEN offerable THEN 'FREE'
            WHEN current_vehicle_id IS NOT NULL THEN 'occupied'
            WHEN status <> 'available' THEN 'status_'||lower(status)
            WHEN ocpp_charger_id IS NULL THEN 'no_charger'
            WHEN station_state <> 'Available' THEN 'charger_'||lower(station_state)
            WHEN NOT charger_fresh THEN 'charger_stale'
            WHEN reservation_live THEN 'reserved'
            ELSE 'not_offerable' END AS reason,
       count(*) AS n
FROM r GROUP BY 1 ORDER BY 2 DESC;
--
-- MEASURED 2026-09-13, depot 11111111 (flagship), clock = the twin's world time:
--
--   reason           |  n
--   -----------------+----
--   FREE             | 39
--   charger_faulted  |  1
--
-- and the identical 40 rows through proposer/forward_proposer.stall_block_reason:
--
--   python: {'FREE': 39, 'charger_faulted': 1}
--   sql   : {'FREE': 39, 'charger_faulted': 1}
--
-- THE AGREEMENT THAT MATTERS IS THE ONE STALL, NOT THE THIRTY-NINE. Stall
-- 70fa3080 is BOTH faulted (station_state 'Faulted') and stale (heartbeat 01:30,
-- thirty minutes behind the clock). Both branches are true; each side returns
-- `charger_faulted` because both check the state before the freshness. A reason
-- vocabulary whose order differed between producer and consumer would attribute
-- the same refusal two ways depending on who was asked, and the fire record would
-- disagree with the hand query it exists to replace.
--
-- WHERE THE TWO DELIBERATELY DISAGREE, stated so nobody later reads the agreement
-- above as broader than it is: for a stall with offerable=true and a status the
-- shield refuses, the SQL above says FREE and the Python says status_<x>. No such
-- stall exists at the flagship depot today (all 40 are status 'available'), so this
-- measurement does not exercise it. It is the conjunction of note 1, and the Python
-- is the one that is right for a PROPOSER: the SQL here reproduces the selector,
-- and the selector is only half the gauntlet a proposal has to run.

-- ---------------------------------------------------------------------------
-- M2. WHAT THE FIRE RECORD NOW CARRIES that it did not before 0265's consumer.
--     Nothing to run here -- these are the keys, so a reader of
--     ottoq_proposer_fire_log knows what is new and from when.
--
--       n_charge_stalls       int      the denominator "planned on N of M" needs
--       stalls_blocked        jsonb    {reason: count}, the 0186 line
--       n_vehicles_held       int      in a serviceable state, already holding a
--                                      place, therefore not planned for
--       frame_facts_version   int|null 1 = the frame carried 0265's facts;
--                                      null = it did not, and the three counts
--                                      above are the shield-only view
--
--     AND ONE CORRECTION TO AN ALREADY-PUBLISHED COUNT, because the consumer
--     forced it out into the open. `n_stalls_busy` used to count over EVERY stall
--     in the frame with the shield-only test. That agreed with the proposer's own
--     `stalls_busy` (charge-capable stalls only) by luck: a staging stall is
--     `available` with no vehicle, so it read free and fell out of both.
--
--     Under 0265 it does not. The facts are emitted for EVERY stall at the depot,
--     and a staging stall has no `ocpp_charger_id` -- so it is correctly not
--     offerable, and under the old definition all 232 staging stalls at the
--     flagship depot would have joined this count the moment the gate went on.
--     A published ledger number would have moved from a handful to ~260 with
--     nothing whatever changing in the world.
--
--     `n_stalls_busy` is therefore now defined over charge-capable stalls, which
--     is what its own L-58 comment always described ("planned on 17 of 40") and
--     what the proposer has always meant by it. The two numbers now have one
--     definition instead of two that happened to coincide.
--     `bridge/test_proposer_bridge.py::test_turning_the_facts_gate_on_does_not_move_the_busy_count`
--     pins it: same world, gate off and gate on, same number.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- WHAT THIS DOES NOT CLOSE. G47 is still open and this does not close it: the
-- proposer is still ASKED after the local path has taken the resource (0188), and
-- seeing the resource is gone sooner is not the same as being asked sooner. This
-- is 0188's option (b), visibility -- the proposer now says WHICH scarcity it hit
-- instead of saying nothing useful. Option (c), reordering the tick, remains
-- Chase's call and is not taken here.
-- ---------------------------------------------------------------------------
