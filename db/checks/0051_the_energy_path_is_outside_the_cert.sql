-- 0051 — THE ENERGY PATH IS OUTSIDE THE CERTIFICATION (found 2026-08-31, post-round-3)
-- ============================================================================================
-- WHAT PROMPTED IT. With all six columns green (0050 round 3), the obvious next question was
-- whether the certification reaches the NUMBERS, not just the event streams: do the two arms of
-- a certified pair produce identical KPIs? `ottoq_kpi_five()` exists (C6, migration 0044), so
-- this is one query. It should have been asked before the record was written; it was not.
--
-- THE ANSWER: NO — on all six columns. Four of the five KPIs are byte-identical between arms
-- (asset_hours_available_per_day, service_point_turns_per_point_per_day, touch_events_per_turn,
-- p95_time_to_service_min). Two things differ:
--     peak_site_kw   424242/24t arm A 524.9  vs  arm B 416.3   (a 26% gap)
--     run_key.config_hash                    25675cc4… vs 8b94351e…
-- on runs whose commands, decisions, events, bookings AND world fingerprint are byte-identical.
--
-- ROOT CAUSE, LOCALISED TO ONE FIELD IN ONE SNAPSHOT. Diffing the two arms' 24 site_energy_
-- snapshots rows (identical timestamps, identical count) leaves exactly ONE differing row —
-- sim 08:00 — and within it the whole delta is one column:
--     d_grid -474.30  ==  d_bess -474.30 ;  d_ev 0.00, d_bldg 0.00, d_solar 0.00
-- twin.ottoq_sim_advance_site_energy computes
--     v_grid_kw := v_chargers_kw + v_building_kw - v_solar_ac_kw + v_bess_kw
-- and reads v_bess_kw as
--     SELECT COALESCE(SUM(current_power_kw),0) FROM ottoq_bess_units WHERE depot_id = …
-- `ottoq_bess_units.current_power_kw` is WORLD state — the battery's instantaneous power — and
-- it is carried between runs. Verified against the catalog, all four are zero:
--     ottoq_tick_invariance_reset_fleet  … does NOT touch bess
--     ottoq_world_fingerprint            … does NOT cover bess
--     ottoq_run_boot_draw                … does NOT reset bess
--     ottoq_sim_release_depot            … does NOT clear bess at teardown
-- So arm B boots with whatever power level arm A's battery was left at. This is verbatim the
-- V7 residue class (db/checks/0049): state mutable in-run, absent from fingerprint AND boot
-- reset AND teardown. It never surfaced because the determinism pair hashes commands,
-- decisions, events and bookings plus a vehicles/stalls fingerprint — the energy tables are
-- outside every one of those surfaces.
--
-- A SECOND, INDEPENDENT DEFECT FOUND IN THE SAME READ (not the cause of the above, but the same
-- disease and worse in kind): the solar read is not run-scoped either —
--     SELECT COALESCE(SUM(ac_power_kw),0) FROM ottoq_solar_output, latest
--      WHERE depot_id = p_depot_id AND sim_clock_at = latest.t
-- Measured on the flagship depot at sim 2026-09-01 08:00: 860 rows from 215 DISTINCT sim runs
-- share that timestamp, and this SUM adds all of them. Every historical run's solar output is
-- being summed into the current run's site balance. It did not move the numbers above only
-- because those hours are dark (summed_kw = 0.0); at midday it is a large silent inflation of
-- solar, i.e. a silent DEFLATION of grid import — the direction that flatters the product.
-- Also unscoped and untiebroken in the same function: the ambient-temperature read
--     … FROM ottoq_weather_snapshots WHERE depot_id = … AND sim_clock_at <= …
--       ORDER BY sim_clock_at DESC LIMIT 1
-- — no run filter and no tiebreak, so with several runs' rows at one sim_clock_at the pick is
-- heap order (the 0129/0130 class, in the energy path).
--
-- WHY THIS MATTERS MORE THAN ITS SIZE. peak_site_kw is not an incidental metric: it is the
-- demand-charge number, and the anti-correlation curve (brief C8) is the shared-infrastructure
-- economics argument built ON it. Of the five canonical KPIs it is the one most likely to be
-- quoted to a customer or an investor, and it is the one the certification does not cover.
--
-- THE RECORD IS CORRECTED, NOT ARGUED WITH. db/checks/0050's round-3 verdict closed with
-- "every number it emits carries a run ID that regenerates it." That sentence is FALSE for
-- peak_site_kw and was false when written. It is struck there and replaced with the true,
-- narrower claim. The green matrix itself stands unchanged — it certifies the scheduler, and
-- every one of its hashes still regenerates — but its SCOPE was overstated by one sentence.
--
-- THE FIX (proposed, NOT applied here — it is behaviour-changing and costs a full
-- re-certification ladder, so it is the founder's call to spend):
--   1. Run-scope the energy reads in twin.ottoq_sim_advance_site_energy: solar SUM and the
--      weather pick gain the run filter (0124's idiom), and the weather pick gains a tiebreak.
--   2. Reset ottoq_bess_units.current_power_kw (and its SoC/mode siblings) in
--      ottoq_tick_invariance_reset_fleet, exactly as 0115 did for vehicles.target_soc.
--   3. Extend ottoq_world_fingerprint to cover the BESS row set, per that function's own rule
--      ("extend only alongside the probe that justifies it") — this check is that probe.
--   4. Extend the determinism pair to hash an energy stream (grid_import/solar/bess per tick)
--      so this class can never again be invisible to the gate.
--   5. Re-run the six-column ladder; expect one transition pair per column.
-- Until then the honest position: the SCHEDULER is certified; peak_site_kw is NOT reproducible
-- and no number derived from it should ship.

-- Evidence, re-runnable. Expected TODAY: false in the kpis_identical column for every row.
WITH arms(col, a, b) AS (VALUES
  ('424242/24t','b8988981-6624-4b4e-9ba4-8d139093c5ee','f6c3bdbf-0b25-4e75-a07d-dfd536a858bf'),
  ('171717/24t','819891b0-5675-4bf5-955f-d3dc18e26411','67ddc2a5-af4a-4a4c-ab45-9aa51538a1ae'),
  ('424242/12t','78c988e8-89fe-4a74-9a2b-10edc845b5ec','2b2120ae-a3a4-49d9-8422-192052bf81e6'),
  ('171717/12t','58322855-1739-4ddd-b830-a9809272f5d1','1e9e82ca-ead7-4a59-b592-994f01bd7868'),
  ('314159/12t','9a166bcf-d453-4f80-abd5-60c75e9fb033','59e8371e-6197-4735-8398-01400e06eed7'),
  ('normal_day','bf154fc7-4397-4f8f-ae62-991051474d23','c7e4de35-10c7-4e2b-a200-2fdfc0c71242')
)
SELECT col,
       (public.ottoq_kpi_five(a::uuid) - 'sim_run_id') = (public.ottoq_kpi_five(b::uuid) - 'sim_run_id') AS kpis_identical,
       public.ottoq_kpi_five(a::uuid)->>'peak_site_kw' AS peak_kw_arm_a,
       public.ottoq_kpi_five(b::uuid)->>'peak_site_kw' AS peak_kw_arm_b
FROM arms ORDER BY col;
