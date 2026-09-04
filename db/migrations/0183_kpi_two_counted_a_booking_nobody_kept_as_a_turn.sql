-- =====================================================================
-- 0183  KPI 2 counted a booking nobody kept as a turn
-- =====================================================================
-- forces_recert = FALSE. View only; sole reader is ottoq_kpi_five.
-- Found by sweeping the other four canonical KPIs for 0182's class.
--
-- THE NUMBER
-- ---------------------------------------------------------------------
--   turns counted today                 488,594
--   occupancies that actually completed 131,372
--   overstatement factor                   3.72x
--
-- ottoq_kpi_service_point_turns - canonical KPI 2,
-- service_point_turns_per_point_per_day - counts
--
--   count(*) FILTER (WHERE state IN ('done','released','interrupted'))
--
-- as turns_completed. 'released' is not a completed turn. It is the
-- state a booking ends in when it ends WITHOUT one, and the reason codes
-- say so plainly:
--
--   state     release_reason              rows      of those with a
--                                                   leg, % that started
--   done      window_elapsed_occupied  115,486            99.9%
--   done      bay_exit_transition       10,727            76.8%
--   done      vehicle_moved_to_next_leg  5,159             -
--   released  window_elapsed           251,588            18.8%
--   released  run_stopped               88,298             9.6%
--   released  no_show_grace_elapsed     14,838            19.4%
--   released  replanned_*                2,289            ~30%
--
-- Two independent lines of evidence, agreeing:
--
--   (1) THE REASON CODES. 'window_elapsed' versus
--       'window_elapsed_occupied' is the schema itself distinguishing a
--       reservation that was kept from one that was not, and the KPI
--       counts both. 'no_show_grace_elapsed' is a no-show by name.
--       'run_stopped' is the teardown closing live bookings - the exact
--       0181 defect, one table over: 88,298 rows, of which 87,860
--       (99.5%) have a booking window ENDING PAST their run's horizon,
--       which is what proves they were still in progress when time ran
--       out rather than merely closed late.
--
--   (2) THE LEG LINKAGE. Conditioned on a booking naming a leg at all,
--       99.9% of done/window_elapsed_occupied legs actually started
--       (72,574 of 72,641) against 18.8% for released/window_elapsed
--       (4,322 of 23,009). leg_id is populated on a minority of rows, so
--       this is a comparison of rates among rows that HAVE one, not a
--       count of turns - stated that way deliberately, because a missing
--       leg_id is not evidence of a missing occupancy.
--
-- THE FIX: turns_completed counts state = 'done'.
--
-- 'interrupted' is dropped from the numerator too. It is an IN-FLIGHT
-- state, not a terminal one - 0127 established that interrupted rows are
-- live state, and the teardown sweeps held/active/interrupted into
-- released. A booking sitting in it has not completed a turn. There are
-- 0 such rows today, so this changes no number; it stops the definition
-- from being wrong the first time a run is measured mid-flight.
--
-- Six columns appended so the exclusion is auditable rather than merely
-- smaller - the 0176 / 0182 pattern: bookings_not_a_turn,
-- released_never_occupied, released_by_teardown, released_no_show,
-- points_with_a_turn, bookings_seen. Anyone who wants the old number
-- back can add turns_completed + bookings_not_a_turn and get it.
--
-- WHAT IS DELIBERATELY NOT CHANGED
-- ---------------------------------------------------------------------
-- points_used stays count(DISTINCT stall_id) over ALL bookings that day,
-- including superseded ones - so the denominator counts points that
-- never turned. That inflates the denominator while the numerator was
-- inflating too, two errors in opposite directions, and fixing only the
-- numerator moves the ratio further than either error alone.
--
-- It is left alone ON PURPOSE. "Turns per point per day" has a real
-- definitional choice underneath it - per point that saw a booking, per
-- point that turned, or per point INSTALLED at the depot (which is what
-- a throughput claim usually means and would require the depot's stall
-- count, not the booking table). Picking one silently inside a defect
-- fix would be smuggling a product decision into a correction.
-- points_with_a_turn is exposed so the gap is visible and the choice can
-- be made on evidence, in its own migration.
-- =====================================================================

CREATE OR REPLACE VIEW public.ottoq_kpi_service_point_turns AS
SELECT
  sim_run_id,
  date_trunc('day'::text, lower(during))::date AS day,
  -- 0183: a turn is a completed occupancy, which is state 'done'.
  -- Previously state IN ('done','released','interrupted'): 'released' is
  -- how a booking ends when NO turn happened (window elapsed unoccupied,
  -- no-show, replanned away, or closed by the run teardown), and
  -- 'interrupted' is in-flight. 488,594 -> 131,372 across all history.
  count(*) FILTER (WHERE state = 'done'::text) AS turns_completed,
  count(DISTINCT stall_id) AS points_used,
  round(count(*) FILTER (WHERE state = 'done'::text)::numeric
        / GREATEST(1::bigint, count(DISTINCT stall_id))::numeric, 2) AS turns_per_point_per_day,
  -- 0183 diagnostics: turns_completed + bookings_not_a_turn is the
  -- pre-0183 number, so the correction is reversible by inspection.
  count(*) FILTER (WHERE state <> 'done'::text)                             AS bookings_not_a_turn,
  count(*) FILTER (WHERE release_reason = 'window_elapsed'::text)           AS released_never_occupied,
  count(*) FILTER (WHERE release_reason = 'run_stopped'::text)              AS released_by_teardown,
  count(*) FILTER (WHERE release_reason = 'no_show_grace_elapsed'::text)    AS released_no_show,
  count(DISTINCT stall_id) FILTER (WHERE state = 'done'::text)              AS points_with_a_turn,
  count(*)                                                                  AS bookings_seen
FROM ottoq_stall_bookings b
GROUP BY sim_run_id, (date_trunc('day'::text, lower(during))::date);

COMMENT ON VIEW public.ottoq_kpi_service_point_turns IS
  'Canonical KPI 2 (CLAUDE.md 2.9). A turn is a COMPLETED occupancy of a service point: state = done. 0183: the prior definition counted state IN (done, released, interrupted), and released is precisely how a booking ends when no turn happened - window elapsed unoccupied (251,588 rows), closed by the run teardown (88,298, of which 99.5% had a window ending past their run horizon), no-show (14,838), replanned away (2,289). Overstated by 3.72x across all history: 488,594 reported against 131,372 completed. turns_completed + bookings_not_a_turn reproduces the old number. points_used is unchanged and still counts every stall with any booking that day, including ones that never turned - the per-point denominator is a definitional choice (per booked point, per turned point, or per installed point) and is not decided here; points_with_a_turn exposes the gap.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('kpi_two_counted_a_booking_nobody_kept_as_a_turn', false,
        'public.ottoq_kpi_service_point_turns - canonical KPI 2 - counted state IN (done, released, interrupted) as turns_completed. released is the state a booking ends in when NO turn happened. Measured across all history: 488,594 counted against 131,372 completed occupancies, an overstatement factor of 3.72x. Two independent lines of evidence: (1) the reason codes distinguish window_elapsed from window_elapsed_occupied, and 251,588 unoccupied window-elapsed rows plus 14,838 no-shows plus 2,289 replanned-away plus 88,298 closed by the run teardown were all counted as completed turns - the teardown rows being the 0181 defect one table over, 87,860 of them (99.5%) with a booking window ending past their run horizon, which proves they were in flight when time ran out; (2) conditioned on a booking naming a leg, 99.9% of done/window_elapsed_occupied legs actually started (72,574 of 72,641) against 18.8% of released/window_elapsed (4,322 of 23,009) - a rate comparison among rows that have a leg_id, not a count of turns, since a missing leg_id is not evidence of a missing occupancy. Fixed to state = done; interrupted also dropped as an in-flight state per 0127, which changes no number today (0 rows) but stops the definition being wrong when a run is measured mid-flight. Six diagnostic columns appended per the 0176/0182 pattern so the exclusion is auditable and turns_completed + bookings_not_a_turn reproduces the old number. Deliberately NOT changed: points_used still counts every stall with any booking that day, so the denominator includes points that never turned - the per-point denominator is a real definitional choice (per booked point, per turned point, or per installed point at the depot) and deciding it inside a defect fix would smuggle a product decision into a correction; points_with_a_turn exposes the gap for that decision to be made on evidence. forces_recert=false: view only, sole reader ottoq_kpi_five.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
