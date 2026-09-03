-- 0082  The 48-tick answer, and the clock that leaked. Read 7:40 PM CT, 2026-09-02.
--
--
-- §1  The open question is answered: the deferral is by design
-- -------------------------------------------------------------
-- 0081 §4 left exactly one thing open - is planning an asset's work ~330 minutes
-- after its return correct deferral, or starvation invisible at 12 ticks? A
-- 12-tick run ends at 09-01 08:00 and cannot contain a plan for 08:00+. A
-- 48-tick run reaches 09-02 02:00 and does.
--
-- Pair fired 6:55 PM CT, seed 171717, busy_day, flagship, 48 ticks:
--   sim_run_seq 1773/1774, outcome passed, arms equal, end state equal.
--   canons  beab1640 / dc07844d / 72be4b59 / 1f746041
--
-- On that run, of 129 returns, 6 had their first planned work at or after the
-- 12-tick horizon - the exact population that read as "unserved" at 12 ticks:
--
--   6 of 6 WENT ACTIVE.  0 never active.
--
-- So the deferral is honoured the moment the horizon contains it. 0081's
-- conclusion - stranding is zero - now holds on a horizon that can actually test
-- it, and the remaining question is a POLICY to expose, not a bug to fix.
--
-- A detail worth keeping: the average wait for those six was 15 MINUTES, not the
-- 330 their plan suggested. The planned time is a NOT-BEFORE, not a promise; the
-- engine seats earlier when a point frees. That is the opposite of starvation.
--
-- DETERMINISM AT 48 TICKS is a new result in its own right - four times the
-- longest previously certified horizon, passing and equal on the first attempt.
-- It is one pair, so the column is pairs_seen 1 / green false, which is correct
-- and not a regression.
--
--
-- §2  Chasing a discrepancy instead of explaining it found phantom returns
-- ------------------------------------------------------------------------
-- The 48-tick run reported returns_deferred_beyond_horizon = 7. A LONGER horizon
-- should contain more of the plan and defer LESS, so 7 was backwards. I had
-- predicted it would shrink; it grew.
--
-- All 7 carried actual_return_at = 09-02 23:55 UTC on a run whose sim clock
-- reached 09-02 02:00 - a return stamped ~22 hours after the run ended. The
-- timestamps name themselves:
--
--   pair            fired (wall UTC)      latest actual_return_at   phantoms
--   1773/1774 48t   09-03 00:07 / 00:21        09-02 23:55             7
--   1769/1770 24t   09-02 23:06 / 23:13        09-02 23:01             3
--   1771/1772 24t   09-02 23:22 / 23:29        09-01 11:00             0
--   1765..1768 12t  09-02 22:40 - 22:56        09-01 06:30 / 07:30     0
--
-- 09-02 23:55 is exactly when the h48 job fired. 09-02 23:01 is exactly when the
-- 6:01 PM CT pair fired. This is transaction now() in a SIM-CLOCK column -
-- twin.ottoq_sim_seed_fleet carries
--     actual_return_at = COALESCE(actual_return_at, NOW())
-- and the count grows with horizon (0 / 3 / 7 at 12 / 24 / 48 ticks) because a
-- longer run leaves more assets still deployed when it stops.
--
-- WHY THE PAIR HARNESS CANNOT SEE IT. ottoq_determinism_pair runs both arms in
-- ONE transaction and now() is transaction start time - constant across the
-- arms. A wall-clock value that would differ between two separately fired runs
-- is pinned to one value inside a pair, so it can never make the arms disagree.
-- The harness's own single-transaction design is what conceals it. That is worth
-- knowing about every future wall-clock leak, not just this one.
--
--
-- §3  What it is NOT - stated from evidence, not from argument
-- -------------------------------------------------------------
-- It is not a determinism defect and no canon needs re-taking.
--
-- The busy_day/171717/24t canons reproduced EXACTLY across pairs fired 81
-- minutes apart - 4:40 PM CT (1759/1760) and 6:01 PM CT (1769/1770), different
-- wall clocks and therefore different now() values, identical
-- ec5c38aa / 8221f656 / 096b099e / da9c269c (db/canons/round8.md). The
-- fingerprint already ignores this column; that is the id- and
-- timestamp-blindness 0137 and 0139 built, doing its job.
--
-- The temptation was to call a wall clock in a sim column a determinism finding
-- and re-open round 8. The canons say otherwise, and the canons were committed
-- this afternoon precisely so a claim like that could be checked in one query
-- instead of argued.
--
--
-- §4  Fixed here, and deliberately not fixed here
-- ------------------------------------------------
-- FIXED (0172, KPI, applied): a dispatch whose return postdates the run's clock
-- did not return during the run. Not served, not unserved, not deferred - not a
-- return. Excluded. Verified after applying:
--
--   seq        ticks  p95    measured  unserved  deferred (was)
--   1773/1774   48    210.0     122        0        0  (7)
--   1769/1770   24    210.0     116        0        0  (3)
--   1771/1772   24    244.5     118        0        0  (0)
--   1765/1766   12    240.0     115        0        1  (1)   <- genuine
--   1767/1768   12    150.0     117        0        0  (0)
--
-- returns_measured is unchanged everywhere - only phantoms left. The single
-- remaining deferral on 1765/1766 is a real end-of-horizon arrival, which is
-- what that column is for.
--
-- NOT FIXED, and named rather than smuggled: twin.ottoq_sim_seed_fleet should
-- stamp the sim clock, not NOW(). That moves seeded world state, so it is
-- forces_recert = true and belongs to its own round. It is the first item for
-- round 9, alongside 0169.
--
--
-- §5  Standing
-- -------------
--   * stranding count: ZERO at 12, 24 and 48 ticks
--   * six of six columns green (round 8); 48t is a new column at 1 pair
--   * KPI 5 corrections today: 0167 (measured the calendar, not the physical
--     start), 0168 (recomputed every run), 0170 (counted the horizon), 0171
--     (aggregate unbounded by its own return), 0172 (counted returns that never
--     happened). Five in one day on one KPI. Each was found by a number that
--     did not behave the way a healthy engine's number should, and none by
--     reading the code first.
--
--
-- §6  Queries
-- ------------

-- 6.1 did deferred work execute once the horizon contained it? (expect 6 / 6 / 0)
WITH d AS (
  SELECT dd.vehicle_id, dd.actual_return_at,
         (SELECT min(l.planned_start_sim) FROM ottoq_itinerary_legs l
           WHERE l.sim_run_id=dd.sim_run_id AND l.vehicle_id=dd.vehicle_id
             AND l.leg_type NOT IN ('taxi','stage') AND l.planned_start_sim >= dd.actual_return_at) AS planned,
         (SELECT min(l.actual_start_sim) FROM ottoq_itinerary_legs l
           WHERE l.sim_run_id=dd.sim_run_id AND l.vehicle_id=dd.vehicle_id
             AND l.leg_type NOT IN ('taxi','stage') AND l.actual_start_sim >= dd.actual_return_at) AS active
    FROM ottoq_vehicle_dispatches dd
   WHERE dd.sim_run_id=(SELECT sim_run_id FROM ottoq_sim_runs WHERE sim_run_seq=1773)
     AND dd.actual_return_at IS NOT NULL)
SELECT count(*) AS returns_total,
       count(*) FILTER (WHERE planned >= '2026-09-01 08:00+00'::timestamptz) AS planned_past_12t,
       count(*) FILTER (WHERE planned >= '2026-09-01 08:00+00'::timestamptz AND active IS NOT NULL) AS went_active,
       count(*) FILTER (WHERE planned >= '2026-09-01 08:00+00'::timestamptz AND active IS NULL) AS never_active,
       round(avg(EXTRACT(epoch FROM active-actual_return_at)/60.0)
             FILTER (WHERE planned >= '2026-09-01 08:00+00'::timestamptz)::numeric,0) AS avg_actual_wait_min
  FROM d;

-- 6.2 the phantom-return census - wall clock against sim clock
SELECT r.sim_run_seq, r.tick_count,
       to_char(r.last_tick_at AT TIME ZONE 'UTC','MM-DD HH24:MI') AS wall_clock_ran,
       to_char(r.sim_clock_current AT TIME ZONE 'UTC','MM-DD HH24:MI') AS sim_reached,
       to_char(max(d.actual_return_at) AT TIME ZONE 'UTC','MM-DD HH24:MI') AS latest_return,
       count(*) FILTER (WHERE d.actual_return_at > r.sim_clock_current) AS phantom_returns
  FROM ottoq_sim_runs r JOIN ottoq_vehicle_dispatches d USING (sim_run_id)
 WHERE r.sim_run_seq BETWEEN 1765 AND 1774 AND d.actual_return_at IS NOT NULL
 GROUP BY 1,2,3,4 ORDER BY 1 DESC;

-- 6.3 the KPI after 0172 (expect unserved 0 everywhere, deferred only where real)
SELECT r.sim_run_seq, r.tick_count, v.p95_time_to_service_min AS p95,
       v.returns_measured AS measured, v.returns_unserved AS unserved,
       v.returns_deferred_beyond_horizon AS deferred
  FROM public.ottoq_kpi_p95_time_to_service v JOIN ottoq_sim_runs r USING (sim_run_id)
 WHERE r.sim_run_seq BETWEEN 1765 AND 1774 ORDER BY r.sim_run_seq DESC;
