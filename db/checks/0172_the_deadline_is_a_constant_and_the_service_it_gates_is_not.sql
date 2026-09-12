-- ===========================================================================
-- 0172  THE DEADLINE IS A CONSTANT AND THE SERVICE IT GATES IS NOT
-- ===========================================================================
-- Measured 2026-09-12 04:05-04:20 UTC (2026-09-11 11:05 PM CT), read-only, while
-- round 37 was firing. Groundwork for db/checks/0171 step 1 (tardy_minutes), which
-- is the intent's first-ranked floor.
--
-- PINNED RUN: 1d1b43de-5541-4e52-8333-580fae3297b7
--   busy_day/171717/48t, the 16:10 UTC pair of 2026-09-09 -- the column that failed
--   0193's bar (db/checks/0169). 48 ticks = 1,440 sim minutes = 24 h. 116 autonomous
--   vehicles at the flagship depot.
--
-- EVERY NUMBER BELOW IS FROM THAT RUN ID. Said explicitly because of the second
-- trap below.
--
-- ---------------------------------------------------------------------------
-- WHAT I NEARLY SHIPPED, AND WHY IT WOULD HAVE BEEN WRONG
-- ---------------------------------------------------------------------------
--
-- The tardiness proxy -- for each need with a deadline, the first dispatch of that
-- vehicle at or after its arrival, tardy = max(0, ready - due) -- produced:
--
--   urgency             with_due  beyond_horizon  never_ready  scorable  LATE
--   immediate_dispatch        56               3           31        22    22
--   overnight_hold            38               0            3        35    32
--   total tardiness 11,550 sim-minutes; max 945 min (15.75 h)
--
-- 54 of 57 scorable deadlines missed. 95%. Zero on time in the immediate class.
-- That is a headline number, it is reproducible, it carries a run ID -- and as
-- evidence about the scheduler IT IS WORTHLESS. Here is why.
--
-- ---------------------------------------------------------------------------
-- THE DEADLINE IS NOT DERIVED FROM THE WORK
-- ---------------------------------------------------------------------------
--
-- dispatch_due_at minus arrived_at, the window the vehicle has to be served in:
--
--   immediate_dispatch   n=56   min 45   avg 45   max 45      <-- A CONSTANT
--   overnight_hold       n=38   min 360  avg 497  max 540
--
-- All fifty-six immediate_dispatch deadlines are exactly arrival + 45 minutes.
-- Identical. The deadline does not consult the service bundle the vehicle needs.
--
-- Now the work, from the same run's calendar (ottoq_stall_bookings.during):
--
--   purpose          bookings   min    avg    max    total minutes
--   charge_dcfc           222    15     73    212           16,117
--   charge_l2             441     9     84    495           36,887
--   perimeter_hold        118    60    382    510           45,025
--   temp_hold             885     1     16     60           13,818
--   service                31     2     40     86            1,228
--   detail                 42     1     21     31              878
--   wash                  113     6      9     11            1,008
--   inspect               124     3      3      5              423
--   staging                15    13     46    200              687
--
-- A DC FAST CHARGE ALONE AVERAGES 73 MINUTES AND REACHES 212. The deadline that
-- gates it is 45 minutes, flat, for every vehicle in the class.
--
-- So "54 of 57 late" is very largely the statement "a DCFC takes longer than 45
-- minutes". That is physics and a scenario parameter, not a scheduling failure. A
-- scheduler cannot beat a deadline shorter than the single dominant operation, and
-- MINIMISING TARDINESS AGAINST THIS DEADLINE WOULD REWARD SKIPPING THE CHARGE --
-- the one behaviour the whole L1 shield exists to prevent. db/checks/0146 recorded
-- the same shape from the other side: greedy "wins" on throughput by checking
-- nothing. An objective term is only as meaningful as the constraint it is measured
-- against.
--
-- (Noted in passing, not pursued: charge_dcfc avg 73 / max 212 min sits outside
-- CLAUDE.md 2.4's declared 20-45 min DCFC range. Either the catalog figure or the
-- twin's duration model is wrong. Separately, perimeter_hold consumes 45,025
-- booked minutes -- more than either charging purpose -- across 118 bookings
-- averaging 6.4 hours. Whether that is intended is not established here.)
--
-- ---------------------------------------------------------------------------
-- SO WHAT READINESS NEEDS BEFORE IT CAN BE THE FIRST-RANKED FLOOR
-- ---------------------------------------------------------------------------
--
-- 0171 step 1 said "tardy_minutes, run-scoped" and verified the substrate exists.
-- It does. What it did not check is whether the DEADLINE is a credible target, and
-- it is not yet. Before tardy_minutes can be scored:
--
--   (a) dispatch_due_at must be derived from the required bundle (earliest feasible
--       ready time given the operations the asset needs and the points that can do
--       them), OR
--   (b) it must be declared a SOFT target and tardiness reported alongside an
--       explicit infeasibility count -- "n of m deadlines were unachievable at
--       arrival" -- so a miss attributable to an impossible window is never
--       silently counted as a scheduling miss.
--
-- (b) is cheaper and more honest and should come first: it needs no change to the
-- scenario generator and it makes the existing number interpretable. (a) is the
-- real fix and belongs with the duration model.
--
-- EITHER WAY, ONE RULE HOLDS: a tardiness figure must never be published without
-- the feasibility denominator beside it. That is the 0189 population discipline and
-- BUILD_QUEUE 8d's lesson -- a ratio looks alarming until you ask what the
-- denominator means.
--
-- ---------------------------------------------------------------------------
-- TWO TRAPS FOUND ON THE WAY, BOTH OF WHICH PRODUCED A WRONG NUMBER FIRST
-- ---------------------------------------------------------------------------
--
-- 1. TWO CLOCKS IN ONE ROW. ottoq_visit_needs carries both domains:
--      created_at         WALL clock   2026-09-09 16:10  (when the run executed)
--      arrived_at         SIM clock    2026-09-01 02:00
--      dispatch_due_at    SIM clock    2026-09-01 02:45 .. 2026-09-02 02:45
--    and ottoq_vehicle_dispatches the same: created_at wall, dispatched_at sim.
--    My first proxy joined dispatched_at (sim) against created_at (wall). Sim time
--    here is eight days BEHIND wall time, so the predicate was never true and the
--    query returned 0 scorable needs out of 91 -- a clean, plausible, entirely
--    false answer. Any metric crossing these two columns silently returns nothing.
--    USE arrived_at, NEVER created_at, for anything measured in sim time.
--
-- 2. "THE MOST RECENT CERT RUN" IS A MOVING TARGET. Mid-measurement, round 37's
--    04:05 grid pair landed and became the newest cert_harness run, so an
--    unpinned `ORDER BY started_at DESC LIMIT 1` silently switched my sample from a
--    116-vehicle flagship 48t run to a grid fixture -- and the need counts fell
--    from 94 to 3 with no error. Every number in this file is pinned to an explicit
--    sim_run_id for that reason. The project rule is "no number ships without a run
--    ID"; this is the same rule applied one step earlier -- no number is MEASURED
--    without pinning one.
-- ===========================================================================

-- The measurement, pinned and re-runnable.
WITH pin(run) AS (VALUES ('1d1b43de-5541-4e52-8333-580fae3297b7'::uuid))
SELECT vn.urgency,
       count(*) AS needs_with_due,
       round(min(extract(epoch from vn.dispatch_due_at - vn.arrived_at)/60)) AS window_min,
       round(avg(extract(epoch from vn.dispatch_due_at - vn.arrived_at)/60)) AS window_avg,
       round(max(extract(epoch from vn.dispatch_due_at - vn.arrived_at)/60)) AS window_max
  FROM public.ottoq_visit_needs vn, pin
 WHERE vn.sim_run_id = pin.run AND vn.dispatch_due_at IS NOT NULL
 GROUP BY 1
UNION ALL
SELECT 'BOOKED: '||k.purpose, count(*),
       round(min(extract(epoch from (upper(k.during)-lower(k.during)))/60)),
       round(avg(extract(epoch from (upper(k.during)-lower(k.during)))/60)),
       round(max(extract(epoch from (upper(k.during)-lower(k.during)))/60))
  FROM public.ottoq_stall_bookings k, pin
 WHERE k.sim_run_id = pin.run
 GROUP BY k.purpose
 ORDER BY 1;
