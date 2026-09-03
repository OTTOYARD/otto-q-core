-- 0081  The stranding count is zero. Read 7:15 PM CT, 2026-09-02.
--
-- Closes the thread 0079 §4 opened and 0080 half-diagnosed. Three measurements,
-- each smaller than the last, each because the previous one counted something
-- the engine was never asked to do:
--
--   32   0079 §4   every return with no service operation active afterwards
--   16   0080 §1   minus those arriving on the run's FINAL TICK
--    0   here      minus those whose work was PLANNED BEYOND the run's end
--
-- THE ENGINE IS NOT STRANDING ASSETS. Over the last 25 runs, every return whose
-- work fell due inside the horizon got that work started. Zero exceptions.
--
--
-- §1  What settles it
-- --------------------
-- The contrast between served and unserved returns, on where their work was
-- PLANNED relative to the run's end:
--
--                       work planned inside horizon   avg min, return -> planned
--     served   (2894)        2886   (99.7%)                    66
--     unserved (16)             0   (0%)                      330
--
-- Perfect separation and a five-fold difference in lead time. The unserved
-- assets were not failed by the scheduler; their work was planned for later than
-- the run lasted, and the run stopped first. On a 12-tick run 02:00 -> 08:00,
-- work planned at 08:00 was never due.
--
-- A KPI that GROWS WHEN YOU SHORTEN THE RUN measures the instrument, not the
-- system. That is the same defect p95_time_to_service had before 0167, when it
-- could only ever return 0. Two of the five canonical KPIs have now been caught
-- describing the harness instead of the engine, both today, both found only by
-- asking what the number would have to look like if the engine were healthy.
--
-- 0170 splits the count: returns_unserved is work due inside the horizon and not
-- delivered; returns_deferred_beyond_horizon is everything else. The horizon
-- cases are not hidden - the two columns still sum to the old 32, so nobody has
-- to take the smaller number on trust.
--
--
-- §2  0170 published a prediction and missed it - which found a real bug
-- ----------------------------------------------------------------------
-- 0170 predicted: after applying, unserved 0 and deferred 32.
-- Measured after applying: unserved 12, deferred 20. Total 32, so the accounting
-- held and the SPLIT was wrong.
--
-- Cause, convicted rather than guessed: 0170 computed
--     min(l.planned_start_sim)
-- over every service leg of the VEHICLE in the run, unbounded - while the
-- aggregate immediately above it was correctly bounded by
--     FILTER (WHERE l.actual_start_sim >= d.actual_return_at)
--
-- The row is a DISPATCH, one return, not a vehicle. A vehicle returning twice in
-- a run has two rows, and the second inherited the first's plan timestamp, which
-- predates it and so read as "due inside the horizon and never delivered."
--
-- Measured on the 12 misclassified rows: 12 of 12 were vehicles with more than
-- one return; 12 of 12 had a plan timestamp predating the return being
-- described; 12 of 12 had NO planned work after that return at all.
--
-- 0171 bounds the plan lookup by the same return that bounds the activity
-- lookup. After it: unserved 0, deferred 32, total 32 - the prediction, met.
--
-- THE PREDICTION IS WHY THE BUG WAS FOUND. A migration that had merely claimed
-- "this reclassifies horizon cases" would have shipped with 12 rows silently
-- misfiled, and the next reader would have inherited a stranding count of 12
-- with no way to know it was an artefact. Write the number down before you
-- measure it.
--
--
-- §3  The pattern, third instance today
-- --------------------------------------
-- Three times today I wrote a read that reached past the entity it described:
--   * 0078 §5.3 - read vehicles.current_state (live shared state) to
--     characterise a single past run. Corrected before it reached a conclusion.
--   * 0080 §4.4 - the same reflex mid-diagnosis; it reported four assets
--     "offline" and would have ended the investigation with the wrong answer.
--   * 0170     - an aggregate unbounded by the return it belongs to.
--
-- This is the family 0145 and 0146 fixed in the engine: a read not scoped to the
-- thing it is about. The engine's instances were subtle and took days to find.
-- Mine keep being one missing FILTER clause, which is worth saying plainly
-- because the fix is cheap and the habit is not: when a row describes an event,
-- every aggregate on that row is bounded by the event.
--
--
-- §4  What remains open
-- ----------------------
-- Exactly one question survives from 0080 §3, and it is a design question rather
-- than a defect:
--
--   Is planning an asset's work 330 minutes after its return CORRECT?
--
-- For an asset that returned with high SoC needing only inspect and
-- interior_tidy, deferring behind charge demand may be exactly right - CLAUDE.md
-- 2.3 gives every asset a required-ready-time, and work planned before that time
-- is early, not late. If so this is a POLICY worth exposing (as 0159 exposed the
-- wait-vs-slower-charger choice), not a bug to patch.
--
-- It cannot be answered from these runs: a 12-tick horizon ends before the plan
-- does. Answering it needs a run long enough to contain the plan - a 48-tick
-- horizon on the flagship - which is a new certification column, not a fix.
--
-- 0080 §2's "the engine parks them and never promotes them" was a partial
-- reading, and this supersedes it. The parks expire because the work is not due
-- yet, not because promotion is broken. The evidence in 0080 was real; the
-- inference from it was one step too far, and no fix was built on it.
--
--
-- §5  Queries
-- ------------

-- 5.1 the current split (expect unserved 0, deferred 32, over the last 25 runs)
SELECT count(*) AS runs, sum(returns_measured) AS measured,
       sum(returns_unserved) AS unserved,
       sum(returns_deferred_beyond_horizon) AS deferred_beyond_horizon,
       count(*) FILTER (WHERE returns_unserved > 0) AS runs_with_stranding
  FROM public.ottoq_kpi_p95_time_to_service
 WHERE sim_run_id IN (SELECT sim_run_id FROM ottoq_sim_runs ORDER BY sim_run_seq DESC LIMIT 25);

-- 5.2 the contrast that settles §1 - served vs unserved, where work was planned
WITH runs AS (SELECT sim_run_id, sim_clock_current FROM ottoq_sim_runs ORDER BY sim_run_seq DESC LIMIT 25),
d AS (SELECT r.sim_clock_current, dd.vehicle_id, dd.sim_run_id, dd.actual_return_at,
             (SELECT min(l.actual_start_sim) FROM ottoq_itinerary_legs l
               WHERE l.sim_run_id=dd.sim_run_id AND l.vehicle_id=dd.vehicle_id
                 AND l.leg_type NOT IN ('taxi','stage')
                 AND l.actual_start_sim >= dd.actual_return_at) AS active,
             (SELECT min(l.planned_start_sim) FROM ottoq_itinerary_legs l
               WHERE l.sim_run_id=dd.sim_run_id AND l.vehicle_id=dd.vehicle_id
                 AND l.leg_type NOT IN ('taxi','stage')
                 AND l.planned_start_sim >= dd.actual_return_at) AS planned
        FROM ottoq_vehicle_dispatches dd JOIN runs r USING (sim_run_id)
       WHERE dd.actual_return_at IS NOT NULL)
SELECT CASE WHEN active IS NOT NULL THEN 'served' ELSE 'unserved' END AS bucket,
       count(*) AS n,
       count(*) FILTER (WHERE planned <  sim_clock_current) AS planned_inside_horizon,
       count(*) FILTER (WHERE planned >= sim_clock_current) AS planned_beyond_end,
       round(avg(EXTRACT(epoch FROM planned - actual_return_at)/60.0)::numeric,0) AS avg_min_to_planned
  FROM d WHERE planned IS NOT NULL GROUP BY 1 ORDER BY 1;

-- 5.3 §4's open question needs a horizon that contains the plan.
--     Average return -> planned work is 330 min for the deferred cases; a
--     12-tick run spans 360 min total. 48 ticks (24 h) is the column that would
--     answer it. NOT run here - it is a new certification column and belongs to
--     a round, not to a diagnostic.
