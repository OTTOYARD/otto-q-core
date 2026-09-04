-- =====================================================================
-- 0093  The sweep of the other four KPIs
-- =====================================================================
-- 0092 fixed KPI 1 (0182) and the write behind it (0181). This is the
-- sweep the campaign owes after any convicted defect: does the same
-- class live in the other canonical KPIs? It does, in KPI 2, and larger.
--
-- SECTION 1 — THE SWEEP
-- ---------------------------------------------------------------------
--   view                            joins run   knows horizon
--   ottoq_kpi_asset_hours...        yes         yes    (0182)
--   ottoq_kpi_p95_time_to_service   yes         yes
--   ottoq_kpi_peak_site_kw          no          no
--   ottoq_kpi_peak_site_kw_demand   no          no
--   ottoq_kpi_service_point_turns   no          no     <- DEFECT
--   ottoq_kpi_touch_events_per_turn no          no     <- not audited
--
-- "Does not join the run" is not automatically the defect. Both
-- peak_site_kw views read site_energy_snapshots filtered by sim_run_id,
-- and a snapshot is written per tick, so no row can exist past the
-- horizon and no time bound is needed. Those two are CLEAN with respect
-- to this class. (Separate and still open: db/checks/0050's correction
-- banner - peak_site_kw is not reproducible. Different defect.)
--
-- Noted, not fixed: both peak views window by (sim_run_id, depot_id) and
-- then take max() across the whole run, so on a multi-depot run
-- "peak_site_kw" is the peak of the busiest single depot, not the site
-- total. Every run today is one depot, so no number is currently wrong.
--
-- SECTION 2 — KPI 2, CONVICTED
-- ---------------------------------------------------------------------
--   turns counted today                 488,594
--   occupancies that actually completed  131,372
--   overstatement factor                    3.72x
--
-- ottoq_kpi_service_point_turns counted
--   state IN ('done','released','interrupted')
-- as turns_completed. 'released' is not a completed turn. It is the
-- state a booking ends in when it ends WITHOUT one:
--
--   state     release_reason              rows     ends past horizon
--   done      window_elapsed_occupied  115,486             0
--   done      bay_exit_transition       10,727             0
--   done      vehicle_moved_to_next_leg  5,159             0
--   released  window_elapsed           251,588             0
--   released  run_stopped               88,298        87,860
--   released  no_show_grace_elapsed     14,838            87
--   released  replanned_no_window        2,009             1
--   released  replanned_vehicle_absent     264            23
--
-- TWO INDEPENDENT LINES OF EVIDENCE, AGREEING:
--
-- (1) The reason codes. The schema itself distinguishes 'window_elapsed'
--     from 'window_elapsed_occupied' - a reservation that was kept from
--     one that was not - and the KPI counted both.
--     'no_show_grace_elapsed' is a no-show by name. And 'run_stopped'
--     is the 0181 defect one table over: the teardown closing bookings
--     that were still live. 87,860 of those 88,298 (99.5%) have a
--     booking window ENDING PAST their run's horizon, which is what
--     proves they were in flight when time ran out rather than merely
--     closed late.
--
-- (2) The leg linkage, conditioned on a booking naming a leg at all:
--       done/window_elapsed_occupied  72,574 of 72,641 started = 99.9%
--       released/window_elapsed        4,322 of 23,009 started = 18.8%
--     Stated as a RATE among rows that carry a leg_id, not as a count of
--     turns. leg_id is populated on a minority of bookings (9% of
--     window_elapsed, 63% of window_elapsed_occupied), and a missing
--     leg_id is not evidence of a missing occupancy. The comparison is
--     valid; a headcount drawn from it would not be.
--
-- SECTION 3 — 0183, AND WHAT IT MEASURED
-- ---------------------------------------------------------------------
-- turns_completed now counts state = 'done'. 'interrupted' also leaves
-- the numerator: 0127 established it is live in-flight state, and the
-- teardown sweeps held/active/interrupted into released. 0 rows carry it
-- today, so no number moves - it stops the definition being wrong the
-- first time a run is measured mid-flight.
--
-- The grid-fixture pair, before and after:
--
--   bookings_seen                15
--   turns_completed               2   (was 15)
--   points_used                  10
--   turns_per_point_per_day    0.20   (was 1.50)  <- 7.5x on this run
--   bookings_not_a_turn          13
--     released_by_teardown       10
--     released_never_occupied     3
--
-- turns_completed + bookings_not_a_turn = 15 = bookings_seen, so the
-- pre-0183 number is exactly reconstructible from the view. That is what
-- makes this a correction rather than a smaller number.
--
-- SECTION 4 — WHAT IS NOT CLAIMED
-- ---------------------------------------------------------------------
-- - points_used is UNCHANGED and still counts every stall with any
--   booking that day, including ones that never turned. So the
--   denominator is inflated while the numerator was inflated too - two
--   errors in opposite directions, and fixing only the numerator moves
--   the ratio further than either alone. Left alone on purpose: "per
--   point" has a real definitional choice under it (per booked point,
--   per turned point, or per point INSTALLED at the depot, which is what
--   a throughput claim usually means and needs the depot's stall count,
--   not the booking table). Choosing one silently inside a defect fix
--   would smuggle a product decision into a correction.
--   points_with_a_turn is exposed so the choice can be made on evidence.
--
-- - ottoq_kpi_touch_events_per_turn WAS NOT AUDITED. Its name contains
--   "per turn", so it plausibly shares KPI 2's denominator, but that is
--   a guess and is recorded here as one. It is the next thing to read.
--
-- - KPI 5's denominator over the 345 historical past-horizon dispatch
--   rows (0092 §5d) is still not re-examined.
--
-- - The diagnostics from 0182 and 0183 still do not reach
--   ottoq_kpi_five, which projects only the headline columns. Three of
--   the five KPIs now carry an audit trail no one can see from the one
--   command that ships the number.
-- =====================================================================

-- §1 — the sweep
SELECT c.relname AS kpi_view,
       (pg_get_viewdef(c.oid) ILIKE '%ottoq_sim_runs%')    AS joins_the_run,
       (pg_get_viewdef(c.oid) ILIKE '%sim_clock_current%') AS knows_the_horizon
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relkind IN ('v','m') AND c.relname LIKE 'ottoq_kpi_%'
 ORDER BY 1;

-- §2 line (1) — the reason-code taxonomy
SELECT b.state, COALESCE(b.release_reason,'(null)') AS release_reason, count(*) AS rows,
       count(*) FILTER (WHERE upper(b.during) >
         (SELECT r.sim_clock_current FROM public.ottoq_sim_runs r WHERE r.sim_run_id=b.sim_run_id)) AS ends_past_horizon
  FROM public.ottoq_stall_bookings b
 GROUP BY 1,2 ORDER BY 3 DESC;

-- §2 line (2) — the leg linkage, as a rate among rows that carry a leg_id
SELECT b.state, COALESCE(b.release_reason,'(null)') AS release_reason,
       count(*) FILTER (WHERE b.leg_id IS NOT NULL)           AS names_a_leg,
       count(*) FILTER (WHERE l.actual_start_sim IS NOT NULL) AS that_leg_started,
       round(100.0*count(*) FILTER (WHERE l.actual_start_sim IS NOT NULL)
             / NULLIF(count(*) FILTER (WHERE b.leg_id IS NOT NULL),0), 1) AS pct_of_named_legs_started
  FROM public.ottoq_stall_bookings b
  LEFT JOIN public.ottoq_itinerary_legs l ON l.leg_id = b.leg_id
 WHERE b.state IN ('done','released','interrupted')
 GROUP BY 1,2 ORDER BY 3 DESC;

-- §2 headline — the overstatement factor
SELECT count(*) FILTER (WHERE state IN ('done','released','interrupted')) AS turns_counted_before_0183,
       count(*) FILTER (WHERE state = 'done')                             AS occupancies_that_completed,
       round(count(*) FILTER (WHERE state IN ('done','released','interrupted'))::numeric
             / NULLIF(count(*) FILTER (WHERE state='done'),0), 2)         AS overstatement_factor
  FROM public.ottoq_stall_bookings;

-- §3 — the fixture pair after 0183. turns_completed + bookings_not_a_turn
-- must equal bookings_seen, or the correction is not reconstructible.
SELECT sim_run_id, turns_completed, points_used, turns_per_point_per_day,
       bookings_not_a_turn, released_by_teardown, released_never_occupied,
       points_with_a_turn, bookings_seen,
       (turns_completed + bookings_not_a_turn = bookings_seen) AS old_number_reconstructible
  FROM public.ottoq_kpi_service_point_turns
 WHERE sim_run_id IN ('cebe53e1-3c55-4699-ae20-701bbcbb3561',
                      'd2f80255-3bba-49f4-b5e5-054d181dea24')
 ORDER BY 1;
