-- =====================================================================
-- 0072  Round 6: six green with the proposer in the loop. 0051 closed.
--       0150-0152 applied. The lineage join was silently forcing recert.
-- =====================================================================
-- Written 7:20 AM CT Sep 2. The 9:40 PM CT check-in did not run until
-- 7:08 AM CT; nothing below depended on the hour it ran.
--
-- §1  Round 6 (7:05-9:04 PM CT Sep 1) - first round scored with h_nrg
-- --------------------------------------------------------------------
-- 12 pairs, 12 passed, every arm complete, h_nrg present and EQUAL on
-- every pair. Matrix read at 7:08 AM CT (before 0152): six columns
-- green, history PP on each.
--
--   at CT        column                  h_cmd     h_dec     h_bkg     h_nrg
--   7:05 / 7:14  busy_day/171717/12t     713ed6e3  6f47615f  ecc4d20c  ec12a252
--   7:23 / 7:32  busy_day/314159/12t     0e775f07  ab2d72c9  72d75139  a72cda18
--   7:41 / 7:50  busy_day/424242/12t     9a0a8e68  d5a2769b  ffe66a8c  31f5182e
--   7:59 / 8:08  normal_day/171717/12t   2aaebae4  77b5cc15  f3920554  f8a266b8
--   8:22 / 8:36  busy_day/171717/24t     ac55218a  31ac9d4e  b9ff1e0d  909e0b5c
--   8:50 / 9:04  busy_day/424242/24t     8572fcf7  dd0c832e  4ea4ce75  613aa77c
--
-- Pair wall time: 12-tick 5.4-7.5 min, 24-tick 9.8-12.7 min. Per tick
-- on the 427-stall flagship: 7-16 s, ~120 decisions per tick.
--
-- These six canons are the PROPOSER-IN-THE-LOOP baseline (0071): every
-- arm carried 57-58 one-tick deferral holds. Round 7 (post-0152) is
-- compared against them in 0073.
--
-- §2  0051 CLOSED - peak_site_kw reproduces
-- -----------------------------------------
-- Same instrument 0051 used (ottoq_kpi_five), all 12 round-5 pairs,
-- 24 runs, computed by cron at 9:20 PM CT into the scratch table
-- public.cert0051_recheck_kpi (dropped 7:15 AM CT after recording).
--
--   at CT  column                  peak_site_kw a / b   demand a / b   hours(09-01) a / b   turns a / b  touch a / b  p95 a / b
--   1:45   busy_day/171717/12t     516.0 / 516.0        357.6 / 357.6  209.18 / 209.18      4.71 / 4.71  0.052/0.052  0.0/0.0
--   1:57   busy_day/171717/12t     516.0 / 516.0        357.6 / 357.6  209.18 / 209.18      4.71 / 4.71  0.052/0.052  0.0/0.0
--   2:09   busy_day/314159/12t     494.4 / 494.4        421.7 / 421.7  215.00 / 215.00      4.15 / 4.15  0.052/0.052  0.0/0.0
--   2:21   busy_day/314159/12t     494.4 / 494.4        421.7 / 421.7  215.00 / 215.00      4.15 / 4.15  0.052/0.052  0.0/0.0
--   2:33   busy_day/424242/12t     579.2 / 579.2        344.9 / 344.9  202.17 / 202.17      4.82 / 4.82  0.052/0.052  0.0/0.0
--   2:45   busy_day/424242/12t     579.2 / 579.2        344.9 / 344.9  202.17 / 202.17      4.82 / 4.82  0.052/0.052  0.0/0.0
--   2:57   normal_day/171717/12t   489.8 / 489.8        436.2 / 436.2  227.18 / 227.18      4.48 / 4.48  0.069/0.069  0.0/0.0
--   3:09   normal_day/171717/12t   489.8 / 489.8        436.2 / 436.2  227.18 / 227.18      4.48 / 4.48  0.069/0.069  0.0/0.0
--   3:25   busy_day/171717/24t     516.0 / 516.0        357.6 / 357.6  233.01 / 233.01      6.56 / 6.56  0.065/0.065  0.0/0.0
--   3:51   busy_day/171717/24t     516.0 / 516.0        357.6 / 357.6  233.88 / 233.88      6.56 / 6.56  0.065/0.065  0.0/0.0
--   4:17   busy_day/424242/24t     579.2 / 579.2        344.9 / 344.9  205.17 / 205.17      6.50 / 6.50  0.061/0.061  0.0/0.0
--   4:43   busy_day/424242/24t     579.2 / 579.2        344.9 / 344.9  205.17 / 205.17      6.50 / 6.50  0.061/0.061  0.0/0.0
--
-- All five KPIs identical between arms on 12 of 12. The only keys that
-- differ between arms are sim_run_id (expected) and run_key.config_hash
-- (see §6a). Dated notes appended beneath 0050's CORRECTION banner and
-- at the end of 0051; the banner itself is untouched.
--
-- Note the inter-pair reading too: the two pairs of each column agree
-- on every KPI except busy_day/171717/24t asset_hours (233.01 vs 233.88
-- between the 3:25 and 3:51 pairs). Both arms within each pair agree,
-- so the pair verdict is unaffected; the inter-pair delta on that one
-- column is recorded here and not explained. Round 7 will show whether
-- it persists on the quiesced engine.
--
-- §3  The lineage join was silently forcing re-certification
-- ----------------------------------------------------------
-- ottoq_cert_recert_floor() joins supabase_migrations.schema_migrations
-- .name = ottoq_cert_lineage.name and treats a MISSING lineage row as
-- forces_recert (COALESCE(l.forces_recert, true) - the safe default).
-- 0146-0149 wrote their lineage rows WITH the file-number prefix
-- ('0146_the_load_sum_reads_only_its_own_run_and_depot') while
-- apply_migration stores the name without it. Every one of the four was
-- therefore treated as forcing. Consequence: 0149 (a reader, classified
-- false) moved the floor to 6:50 PM CT instead of 0148's 6:49 PM. No
-- pair started between 6:49 and 6:50, so no verdict changed - but 0150
-- and 0151 (classified false) would have moved the floor and voided
-- round 6's green had they been applied under the prefixed names.
--
-- Fixed 7:10 AM CT: the four rows renamed to the stored convention
-- (UPDATE guarded on the stripped name existing in schema_migrations
-- and not colliding). Floor after the fix, before 0152: 6:49 PM CT.
-- 0150-0152 written to the same convention before applying.
-- RULE: a lineage row's name is the apply_migration name, which never
-- carries the file number. (The floor function's safe default did its
-- job - it erred toward re-certifying, never toward skipping it.)
--
-- §4  0150, 0151, 0152 applied 7:13 AM CT Sep 2
-- ---------------------------------------------
--   0150 twin.ottoq_sim_build_arrival_payload  bf33897a -> 9e5ff532  forces_recert=false
--   0151 public.ottoq_fleet_pending_commands   ce45cfa5 -> f11f0fb6  forces_recert=false
--        returns 4 rows now (production only); 0066 measured 174 (170 sim + 4 prod)
--   0152 public.ottoq_determinism_pair         3345bee3 -> db43d136  forces_recert=TRUE
--        global rows: cuopt_propose_enabled=0, cuopt_first_refusal_max_defers=0
--        (updated_by 0152_deterministic_only); catalog default 0; new catalog row
--        for max_defers; marker '0152_cert_quiesce' present 3x in the pair body;
--        ottoq_policy_get(NULL, key, 1) = 0 for both keys.
-- Floor moved to 7:13:34 AM CT. Round 6's six columns read stale=true,
-- green=false from that moment - intended: round 7 re-earns green on the
-- engine the claim is about.
--
-- §5  Round 7 scheduled
-- ---------------------
-- r7_a1..r7_f2, 12:40-14:39 UTC (7:40-9:39 AM CT), same pair arguments
-- and pinned sim start as round 6. Expected on every arm: two run-scoped
-- policy rows by 0152_cert_quiesce, 0 ottoq_cuopt_deferrals rows,
-- cuopt_invocation_log = sql_gate/policy_disabled only. The canon WILL
-- move (the holds are gone). Check-in armed for 10:10 AM CT; result in
-- 0073.
--
-- §6  Open items
-- --------------
--  a. run_key.config_hash is md5(ottoq_sim_runs.payload). The payload
--     carries boot_draw.drawn_at (wall clock), so config_hash differed
--     between the arms of every certified pair (12 of 12 in §2), exactly
--     as 0051 first noted. The reproducibility KEY (policy_name, pack_id,
--     scenario_seed, config_hash) is not itself reproducible. Fix: hash a
--     canonical config projection (scenario, seed, policy, depot, the
--     effective policy params) - a labeling fix, forces_recert=false.
--     Correct ottoq_kpi_five's provenance text ("the twin battery it
--     models is not yet deterministic") at the same time; it is stale.
--  b. Task #47: every streak restarts at the 0152 floor. Bar proposed:
--     8 consecutive corrected passes (~10% by chance at 1-in-4).
--  c. Inter-pair asset_hours delta on busy_day/171717/24t (§2).
--  d. The harness is too slow for the iteration loop (Chase, Sep 1-2).
--     A stripped-down point-A-to-point-B fixture is the next build.
--
-- §7  Queries
-- -----------

-- 7.1 the matrix
SELECT depot, seed, ticks, scenario, pairs_seen, consecutive_passes, green, stale, inconclusive_pairs, history,
       left(canon_cmd,8) AS cmd, left(canon_dec,8) AS dec, left(canon_bkg,8) AS bkg, left(canon_nrg,8) AS nrg,
       to_char(last_pair_at AT TIME ZONE 'America/Chicago','HH12:MI') AS last_ct
  FROM public.ottoq_cert_matrix('2026-09-01 23:00:00+00'::timestamptz)
 ORDER BY scenario, seed, ticks;

-- 7.2 the lineage join, as the floor sees it (expect every row to carry a classification)
SELECT m.version, m.name, l.forces_recert
  FROM supabase_migrations.schema_migrations m
  LEFT JOIN public.ottoq_cert_lineage l ON l.name = m.name
 WHERE m.version >= '20260901000000'
 ORDER BY m.version;

-- 7.3 the floor
SELECT to_char(public.ottoq_cert_recert_floor() AT TIME ZONE 'America/Chicago','YYYY-MM-DD HH12:MI:SS AM') AS floor_ct;

-- 7.4 the 0051 recheck (the scratch table is gone; this is the shape that produced §2)
--   INSERT INTO cert0051_recheck_kpi ... SELECT started_at, col, arm, run, public.ottoq_kpi_five(run)
--   then per pair: (to_jsonb(kpi) - 'sim_run_id') compared key by key between arm a and arm b.
