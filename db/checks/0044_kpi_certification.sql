-- 0044 KPI CERTIFICATION BATTERY — read-only; safe anywhere.
-- First executed against the C3 scratch instance 2026-08-19.

-- K1. The five views + assembly fn + reproducibility key exist.
SELECT 'K1 objects' AS check,
       CASE WHEN to_regclass('public.ottoq_kpi_asset_hours_available_per_day') IS NOT NULL
             AND to_regclass('public.ottoq_kpi_service_point_turns')            IS NOT NULL
             AND to_regclass('public.ottoq_kpi_peak_site_kw')                   IS NOT NULL
             AND to_regclass('public.ottoq_kpi_touch_events_per_turn')          IS NOT NULL
             AND to_regclass('public.ottoq_kpi_p95_time_to_service')            IS NOT NULL
             AND EXISTS (SELECT 1 FROM pg_proc WHERE proname='ottoq_kpi_five')
             AND EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_name='ottoq_run_archives' AND column_name='config_hash')
            THEN 'PASS' ELSE 'FAIL' END AS verdict;

-- K2. Determinism: two calls, identical bytes, for every archived run.
SELECT 'K2 determinism' AS check,
       count(*) AS runs_checked,
       CASE WHEN bool_and(ottoq_kpi_five(sim_run_id)::text = ottoq_kpi_five(sim_run_id)::text)
            THEN 'PASS' ELSE 'FAIL' END AS verdict
  FROM ottoq_run_archives;

-- K3. The reproducibility key is complete on stamped archives.
-- K3 COULD NOT FAIL. The verdict tested `count(*)` -- the TOTAL number of archives -- so an
-- empty table gave 'PASS(empty)' and ANY rows gave 'PASS'. There was no FAIL branch at all, and
-- the `unstamped` column it computes was never consulted by the verdict beside it. A run archive
-- missing its config_hash is exactly what this check exists to catch, and it certified the
-- opposite. K2 immediately above is written correctly, which is how this survived review.
-- Empty is now its own verdict rather than a silent pass: a certification that goes green on a
-- system where nothing has happened is the failure mode this whole file exists to prevent.
--
-- FIRST RUN AFTER THE FIX (production, 2026-08-27): archives 155, unstamped 153, verdict FAIL.
-- Nothing regressed -- the check simply started reporting what was already true. The cause and
-- the forward fix are 0074_the_archive_carries_its_key.sql: the stamping helper was defined and
-- never called, and the config is purged with the run, so the hash must be taken at archive time.
-- The 153 existing rows cannot be repaired (their configs are gone) and must NOT be backfilled
-- with invented hashes. EXPECT THIS RED until those rows age out. A green K3 before then would
-- mean someone fabricated a key, which is the failure this check is for.
SELECT 'K3 repro_key' AS check,
       count(*) AS archives,
       count(*) FILTER (WHERE config_hash IS NULL) AS unstamped,
       CASE WHEN count(*) = 0 THEN 'EMPTY(no archives to certify)'
            WHEN count(*) FILTER (WHERE config_hash IS NULL) = 0 THEN 'PASS'
            ELSE 'FAIL' END AS verdict
  FROM ottoq_run_archives;

-- K4. KPI-3 recomputation vs the twin-maintained 15-min column (info row —
-- large divergence means one of the two writers is wrong; investigate).
SELECT 'K4 peak_crosscheck' AS check, v.sim_run_id,
       v.peak_site_kw_15min AS recomputed,
       (SELECT max(peak_demand_kw_15min) FROM site_energy_snapshots s
         WHERE s.sim_run_id = v.sim_run_id) AS twin_maintained
  FROM ottoq_kpi_peak_site_kw v;
