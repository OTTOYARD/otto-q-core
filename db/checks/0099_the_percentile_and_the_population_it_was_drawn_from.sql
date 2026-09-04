-- =====================================================================
-- 0099  The percentile and the population it was drawn from
-- =====================================================================
-- KPI 5 was the last of the five this campaign had not audited. It has
-- the same defect as the other four, arriving by a different route.
--
-- SECTION 1 — THE NUMBER
-- ---------------------------------------------------------------------
-- Run 9291ec6d: 94 dispatches, 50 with a return time past the run's
-- horizon and therefore dropped from the population.
--
--   p95_time_to_service_min   1.2      returns_measured   21
--
-- A p95 of 1.2 minutes is an excellent number, computed over 21 of that
-- run's 94 dispatches. The ones excluded are exactly those STILL OUT when
-- the run ended - the dispatches most likely to have had a long
-- time-to-service, or none at all. Removing them cannot raise the
-- percentile. It can only lower it.
--
-- Not a wrong formula this time. A silently trimmed population. Same
-- consequence: a KPI that looks good because its worst cases are gone.
--
-- SECTION 2 — THE EXCLUSION IS CORRECT; ITS INVISIBILITY IS NOT
-- ---------------------------------------------------------------------
-- The gate - actual_return_at IS NOT NULL AND <= sim_clock_current - is
-- RIGHT. A dispatch that never came home has no time-to-service and
-- inventing one would be worse. After 0181 such a dispatch carries NULL
-- and is excluded for the honest reason rather than the wall-clock one,
-- but it is still excluded.
--
-- What was missing is any way to SEE it. returns_unserved and
-- returns_deferred_beyond_horizon count only rows already inside the
-- `pairs` CTE; by construction neither can ever account for a dispatch
-- that never entered it. A reader saw returns_measured = 21 with no way
-- to learn that 94 dispatches existed.
--
-- Measured across all 601 runs with a horizon:
--
--   runs                                              601
--   runs with at least one past-horizon dispatch       52
--   dispatches dropped by the horizon gate            345   (0.51%)
--   worst single run                               100.0%   dropped
--
-- FOUR RUNS HAVE EVERY DISPATCH DROPPED - b54929ce (91), f653bef9 (44),
-- 3eeb5dc5 (25), e8a0ba01 (12). They did not appear in the view at all,
-- so the CLI reported p95 null. Null is the honest value and it arrived
-- silently: nothing distinguished "91 dispatches, none measurable" from
-- "no dispatches".
--
-- SECTION 3 — WHAT 0188 AND 0189 CHANGED
-- ---------------------------------------------------------------------
-- Four columns, and the view driven from per-run totals so an
-- entirely-excluded run APPEARS with a NULL percentile and a stated
-- total. 0189 carries them through ottoq_kpi_five, because 0185 already
-- established that a diagnostic which does not reach the one command
-- shipping the number is half a fix.
--
--   run 85034701   p95 244.5 min   118 of 118 dispatches   100.0%
--   run 9291ec6d   p95   1.2 min    44 of  94 dispatches    46.8%
--   run b54929ce   p95    null       0 of  91 dispatches     0.0%
--
-- Those three lines are the whole argument. Read without the population,
-- 9291ec6d's 1.2 minutes is the best result of the three and 85034701's
-- 244.5 is the worst. Read with it, 244.5 is the only figure measured
-- over a whole fleet, and 1.2 is what survives after the half of the run
-- most likely to have been slow was removed.
--
-- NO EXISTING VALUE MOVED. 597 rows before, 601 after - the four
-- additions are exactly the runs that used to vanish. Checksum over the
-- seven original columns of all 597 pre-existing rows is identical:
-- e6c7983378589856da7f66ca53398fab.
--
-- One consumer change, stated rather than discovered later: those four
-- runs previously returned NULL for returns_unserved through
-- ottoq_kpi_five and now return 0. p95, p50 and max stay NULL - a
-- percentile over an empty set is undefined, not zero - while the counts
-- coalesce to 0, because "zero returns measured" is a fact and NULL there
-- would be a second silence.
--
-- SECTION 4 — THE CAMPAIGN, CLOSED ON ALL FIVE
-- ---------------------------------------------------------------------
--   KPI 1  asset_hours_available_per_day    0182, 0186   11.75x its ceiling
--   KPI 2  service_point_turns              0183          3.72x
--   KPI 3  peak_site_kw                     clean w.r.t. this class
--   KPI 4  touch_events_per_turn            0184, 0187    4.1x low
--   KPI 5  p95_time_to_service              0188, 0189    population trimmed
--
-- Every correction is reversible from the payload alone, and every
-- reversal identity is asserted in the checks: 0092, 0093, 0094, 0097,
-- 0098 and this file.
--
-- SECTION 5 — STILL OPEN
-- ---------------------------------------------------------------------
-- - ~5.4 s of the CLI's 6.9 s is unattributed (0098 §4). Not guessed at.
-- - KPI 5's plan: Index Scan on ottoq_itinerary_legs by vehicle_id with
--   sim_run_id filtered afterwards, 3,065 rows discarded per loop across
--   118 loops, 356 ms per read, read four times. A composite
--   (sim_run_id, vehicle_id) index would fix it. 0187 showed what happens
--   when an index question is settled in a hurry, so it gets its own
--   migration and its own before/after.
-- - KPI 1's date_trunc resolves in the SESSION timezone; day keys are
--   zone-dependent. Needs a canonical bucket zone - definitional.
-- - KPI 2's points_used denominator - definitional, undecided on purpose.
-- - KPI 4's turns filter is still an inline COPY of KPI 2's.
-- - CLAUDE.md Part 3 row counts are stale (ottoq_events 20,799 -> ~2.49M).
-- - The rules-layer gap: 9 of 29 active rules never evaluate, 6 of them
--   block-severity, because the engine announces decisions but never
--   state transitions.
-- =====================================================================

-- §2 — the size of the exclusion, per run
WITH d AS (
  SELECT r.sim_run_id, count(*) AS dispatches,
         count(*) FILTER (WHERE v.actual_return_at > r.sim_clock_current) AS past_horizon,
         count(*) FILTER (WHERE v.actual_return_at IS NOT NULL
                            AND v.actual_return_at <= r.sim_clock_current) AS admitted
    FROM public.ottoq_vehicle_dispatches v
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = v.sim_run_id
   WHERE r.sim_clock_current IS NOT NULL GROUP BY r.sim_run_id
)
SELECT count(*) AS runs,
       count(*) FILTER (WHERE past_horizon > 0) AS runs_with_past_horizon,
       count(*) FILTER (WHERE admitted = 0)     AS runs_with_nothing_measurable,
       sum(past_horizon)                        AS dropped_rows,
       round(100.0*sum(past_horizon)/NULLIF(sum(dispatches),0),2) AS pct_dropped
  FROM d;

-- §3 — the three runs that make the argument
SELECT sim_run_id, p95_time_to_service_min AS p95, returns_measured,
       dispatches_total, dispatches_admitted, dispatches_returned_past_horizon,
       round(100.0*dispatches_admitted/NULLIF(dispatches_total,0),1) AS pct_measured
  FROM public.ottoq_kpi_p95_time_to_service
 WHERE sim_run_id IN ('85034701-a556-4853-b148-b8d40c35b490',
                      '9291ec6d-12b2-4d44-b4f9-35d47f08e9da',
                      'b54929ce-ce93-46bf-8f85-04d77c5484ad')
 ORDER BY pct_measured DESC;

-- §3 — no existing value moved. Must equal e6c7983378589856da7f66ca53398fab.
SELECT count(*) AS rows_with_admitted,
       md5(string_agg(sim_run_id::text||'|'||coalesce(p95_time_to_service_min::text,'N')||'|'||returns_measured||'|'||
                      returns_unserved||'|'||coalesce(p50_time_to_service_min::text,'N')||'|'||
                      coalesce(max_time_to_service_min::text,'N')||'|'||returns_deferred_beyond_horizon,
                      E'\n' ORDER BY sim_run_id)) AS checksum_of_prior_rows
  FROM public.ottoq_kpi_p95_time_to_service WHERE dispatches_admitted > 0;

-- §3 — 0189: the population reaches the CLI
SELECT public.ottoq_kpi_five('9291ec6d-12b2-4d44-b4f9-35d47f08e9da'::uuid) #> '{audit,p95_time_to_service_min}' AS kpi5_audit_block;
