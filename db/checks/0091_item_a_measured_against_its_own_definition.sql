-- =====================================================================
-- 0091  Item A, measured against its own definition
-- =====================================================================
-- Task #56 defines item A - "DETERMINISTIC CORE DONE" - as a list of
-- named conditions. This file measures each one instead of asserting it,
-- because two of them turned out to be stale in the task text and I
-- nearly did duplicate work on both.
--
-- The method that caught them, twice in one afternoon: READ THE SOURCE,
-- NOT THE TASK LIST. CLAUDE.md rule 5 - "before building anything, check
-- whether it exists. Duplicating an existing capability is a failure."
--
-- CRITERION 1 - six columns green, inter-pair reproducible, h_nrg in the
--               verdict.
--   MET. Round 12: 12 pairs, 6 columns, 2 each, all four hashes
--   single-valued per column, zero non-passing. db/canons/round12.md.
--
-- CRITERION 2 - every canon stable across at least two rounds.
--   MET, and exceeded: THREE boundaries (8 -> 10 -> 11 -> 12) for the
--   four columns unchanged since round 8; two for the 424242 pair that
--   0179 established.
--
-- CRITERION 3 - the 0066 findings closed (arrival-payload odometer,
--               ottoq_fleet_pending_commands).
--   MET, and it was ALREADY MET before I looked - the task text was
--   stale. Verified two ways rather than by reading the source alone:
--     * ottoq_fleet_pending_commands carries `AND c.sim_run_id IS NULL`
--     * the odometer SUM carries a sim_run_id predicate, and the paired
--       webhook comparison that read 43/43 DIFFERING in 0066 now reads
--       43 paired / 43 both-non-null / 0 differing / max delta 0.00.
--       Non-vacuous by 0066 §6's own rule: the comparison had rows AND
--       non-null values on both sides, on the real key (odometer_mi).
--
-- CRITERION 4 - task #47 closed on a stated evidence bar, not two passes.
--   MET. 8 consecutive pairs on canon c36a99c1, zero non-passing,
--   distinct_full_canons = 1 (all four hashes, stronger than the bar
--   asked), across three engine states. db/checks/0088.
--
-- CRITERION 5 - peak_site_kw reproducible (0050's CORRECTION banner,
--               0051). "A KPI that cannot ship until it is."
--   MET, and ALREADY MET before I looked - the second stale item. 0050
--   carries a RESOLUTION NOTE (2026-09-02 7:20 AM CT) recording that
--   0144 + 0146 + 0147 + 0148 closed it, re-measured on all 12 round-5
--   pairs: peak_site_kw identical between arms 12 of 12, and all five
--   KPIs identical 12 of 12.
--   The CORRECTION banner itself STANDS and is not struck - it is a
--   point-in-time record, and 0050's own rule forbids rewriting one.
--
-- CRITERION 6 - the run key is itself reproducible. 0050's resolution
--               note left this open: config_hash was md5(payload) and so
--               carried the boot draw's wall-clock drawn_at, meaning
--               "the reproducibility KEY is not yet reproducible".
--   MET. 0167 replaced it with ottoq_run_config_hash over an explicit
--   config_key (scenario, seed, policy, depot, ticks, tick interval, sim
--   clock start, time scale, resolved params) - no payload, no
--   wall clock. Measured on round 12 below: config_hash is
--   SINGLE-VALUED per column while boot drawn_at still varies 2-3 ways.
--   That contrast is the proof: the wall clock still moves, and the key
--   no longer moves with it.
WITH arms AS (
  SELECT r.scenario_code, r.random_seed, r.tick_count,
         r.payload->'boot_draw'->>'drawn_at' AS boot_drawn_at,
         public.ottoq_run_config_hash(r.sim_run_id) AS cfg_hash
    FROM ottoq_sim_runs r
   WHERE r.run_by='cert_harness' AND r.started_at >= '2026-09-03 17:18:00+00'
     AND r.validation_notes IS NOT NULL)
SELECT scenario_code, random_seed AS seed, tick_count AS ticks, count(*) AS runs,
       count(DISTINCT cfg_hash)      AS distinct_config_hash,   -- must be 1
       count(DISTINCT boot_drawn_at) AS distinct_boot_drawn_at  -- expected > 1
  FROM arms GROUP BY 1,2,3 ORDER BY 1,2,3;

-- =====================================================================
-- WHAT REMAINS - none of it named by item A's own definition
-- =====================================================================
-- Every criterion item A names is met. What follows was found by this
-- campaign, not by A's definition, and is recorded so "A is met" is not
-- read as "nothing is open".
--
-- 1. twin.ottoq_sim_seed_fleet - TWO live defects, in BOTH overloads
--    (p_depot_id,p_seed) and (p_depot_id,p_seed,p_hour). Verified live
--    today, not inferred:
--      * 0066 §5 asymmetry: the dispatch abort has NO twin guard while
--        the ocpp reset beside it is twin-only by token convention. A
--        twin seed would abort a PRODUCTION dispatch at that depot.
--        This is the most consequential open item - it is
--        production-facing, not a certification concern.
--      * the clock leak: COALESCE(actual_return_at, NOW()).
--    One function, one migration, one forces_recert round.
--
-- 2. The odometer is fixed but UNHASHED. The harness hashes no webhook
--    table, so the next regression there is invisible again - the same
--    blind-spot shape 0139 closed for endst and 0148 for the energy
--    stream. Promote it into the verdict.
--
-- 3. The pg_cron stall: a cert pair stops the scheduler for its whole
--    duration (effect established join-free, db/checks/0090 §3). The
--    duration hypothesis is REFUTED (§5, the 90 s sleeper). Mechanism
--    unnamed.
--
-- 4. Nine of 29 active rules never evaluate, six of them block-severity,
--    because the engine never announces the state-transition actions
--    they are scoped to. docs/DECISION_BOUNDARY.md.
--
-- 0066 §4 (the ocpp orphan sweep) stays LATENT: real mechanism, zero
-- active rows, and 0066 says explicitly not to report it as live.
SELECT n.nspname||'.'||p.proname AS fn,
       pg_get_function_identity_arguments(p.oid) AS args,
       (p.prosrc ~ 'COALESCE\(actual_return_at, NOW\(\)\)') AS clock_leak_live,
       (p.prosrc ~ 'ottoq_vehicle_dispatches')              AS touches_dispatches,
       (p.prosrc ~ 'sim_run_id')                            AS mentions_sim_run_id
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='twin' AND p.proname='ottoq_sim_seed_fleet'
 ORDER BY args;
