-- 0079  Round 8 complete: six of six green, canons reproduced, 0168 applied.
--       Read 6:40 PM CT, 2026-09-02.
--
--
-- §1  Pass 2 met the strict bar
-- ------------------------------
-- Five pairs (s8a..s8e, 5:25-6:19 PM CT), same arguments as pass 1, flagship
-- depot, pinned sim start 2026-09-01 02:00 UTC.
--
-- Every pair: outcome passed, arms equal, end-state fingerprint equal. AND every
-- column's pass-2 canons matched its pass-1 canons EXACTLY - all four hashes,
-- all five columns:
--
--   seq        column                    cmd/dec/bkg/nrg vs pass 1
--   1763/1764  busy_day   314159  12t    all four match
--   1765/1766  busy_day   424242  12t    all four match
--   1767/1768  normal_day 171717  12t    all four match
--   1769/1770  busy_day   171717  24t    all four match
--   1771/1772  busy_day   424242  24t    all four match
--
-- That is the bar that matters and it is stricter than "passed". A pass-2 pair
-- which is internally equal but carries a DIFFERENT canon than pass 1 is an
-- inter-pair carrier - the failure round 5 was built to catch - and would have
-- been a failure however green the verdict read. None occurred.
--
-- ottoq_cert_matrix at the recert floor: SIX OF SIX GREEN, every column
-- pairs_seen 2, consecutive_passes 2.
--
--   busy_day   171717 12t   04177a2a 5328154a 0bf42b3c 8dcf8918
--   busy_day   171717 24t   ec5c38aa 8221f656 096b099e da9c269c
--   busy_day   314159 12t   773fd6dc ad492891 4274369c 2b271f2f
--   busy_day   424242 12t   16aabc27 bb7105f3 5a227276 0cac7e0b
--   busy_day   424242 24t   ac1dc757 b7cbd48c 37ed2670 c5ef0ab3
--   normal_day 171717 12t   78ece09b c36a99c1 2838c66c 5512b237
--
-- All ten s8 arms plus the five r8 pairs ran with the proposer quiesced (0152),
-- so this certifies the deterministic core alone.
--
-- Cron cleaned: r8a..r8e and s8a..s8e all unscheduled, confirmed in a SEPARATE
-- statement (a subquery in the same statement reads the pre-delete snapshot -
-- 0078 §3b). Zero cert jobs remain; only the six standing jobs.
--
--
-- §2  What this does and does not close
-- --------------------------------------
-- CLOSED - the certification half of roadmap item A:
--   * all six columns green at the current floor
--   * inter-pair reproducible: pass 2 reproduced pass 1 exactly on every column
--   * h_nrg in the verdict, so the energy path cannot hide (task #55)
--   * the whole round ran on the deterministic core with the proposer quiesced
--
-- NOT CLOSED, and not to be claimed:
--   a. Task #47 (normal_day 171717/12t intermittent deviation). That column now
--      has two consecutive corrected passes, not the 8 proposed in 0072 §6b as
--      the bar. The bar was proposed, never agreed. Still not closed
--      unilaterally.
--   b. The 0066 findings (arrival-payload odometer, ottoq_fleet_pending_commands)
--      named in roadmap item A. Status unverified in this round; do not assume
--      today's work touched them.
--   c. "Every canon stable across at least two ROUNDS" - this is two PASSES
--      within one round. Round 9 is the first round that can test the stronger
--      claim, and db/canons/round8.md is what makes it testable on all six
--      columns rather than one.
--
--
-- §3  0168 applied and verified
-- ------------------------------
-- Held back deliberately through both passes so one round would not span two
-- ottoq_engine_hash values (0167 stamps that hash onto every archived run).
-- Applied after the round closed.
--
-- Its own file required the new view be compared to the old correlated form run
-- by run. Applying destroys the old form, so the baseline was captured FIRST,
-- then compared:
--
--   run (seq)   p95    measured  unserved  p50   max     identical after 0168
--   1748        210.0     116        0     30.0  270.0   yes
--   1763        180.0     112        4     30.0  270.0   yes
--   1765        240.0     115        1     30.0  330.0   yes
--   1767        150.0     117        0     30.0  240.0   yes
--   1769        210.0     116        3     30.0  270.0   yes
--   1771        244.5     118        0     30.0  390.0   yes
--
-- Every field identical on all six. And the comparison query JOINED the view -
-- which before 0168 exceeded the 60 s statement timeout with only TWO runs. The
-- performance claim is proven by the query being possible at all.
--
-- The 25-run sweep that timed out at 0167 now returns immediately:
--   25 runs measured, 5 distinct p95 values, min 150.0, max 244.5,
--   ZERO runs reporting p95 = 0.
--
--
-- §4  FINDING - 32 unserved returns across 12 of 25 runs
-- -------------------------------------------------------
-- The same sweep counts returns_unserved: an asset that returned to the depot
-- and never had a single service operation go ACTIVE for the rest of the run.
--
--   32 unserved returns, spread across 12 of 25 runs.
--
-- Before 0167 every one of these scored as served, because a booking existed for
-- them and the old view measured the calendar claim. They are the same class as
-- the 8 stranded in the readiness KPI and the 24 never-reconsidered mid-charge
-- faults in 0076 §12.
--
-- The cause is NOT the per-tick work caps - 0078 §6 ruled those out by
-- measurement (the seating loop runs at 8-10 of its budget of 20). It remains
-- unidentified. This is the next diagnostic, and it is now measurable per run
-- rather than anecdotal, which it was not this morning.
--
--
-- §5  Queries
-- ------------

-- 5.1 pass 2 against pass 1, the strict bar (edit the VALUES to the round's canons)
WITH v AS (SELECT sim_run_seq, random_seed AS seed, scenario_code AS scen, tick_count AS ticks,
                  validation_notes::jsonb AS n
             FROM ottoq_sim_runs WHERE sim_run_seq > 1762 AND validation_notes LIKE '%outcome%')
SELECT sim_run_seq, seed, scen, ticks, n->>'outcome' AS outcome, n->>'equal' AS pair_equal,
       left(n->'arm_a'->>'h_cmd',8) AS cmd, left(n->'arm_a'->>'h_dec',8) AS dec,
       left(n->'arm_a'->>'h_bkg',8) AS bkg, left(n->'arm_a'->>'h_nrg',8) AS nrg
  FROM v ORDER BY sim_run_seq;

-- 5.2 the matrix
SELECT scenario, seed, ticks, pairs_seen, consecutive_passes, green,
       left(canon_cmd,8) AS cmd, left(canon_dec,8) AS dec,
       left(canon_bkg,8) AS bkg, left(canon_nrg,8) AS nrg
  FROM public.ottoq_cert_matrix(public.ottoq_cert_recert_floor())
 ORDER BY scenario, seed, ticks;

-- 5.3 the sweep that could not run before 0168, and the unserved count
SELECT count(*) AS runs_measured, count(DISTINCT p95_time_to_service_min) AS distinct_p95,
       min(p95_time_to_service_min) AS min_p95, max(p95_time_to_service_min) AS max_p95,
       count(*) FILTER (WHERE p95_time_to_service_min = 0) AS still_zero,
       sum(returns_unserved) AS total_unserved,
       count(*) FILTER (WHERE returns_unserved > 0) AS runs_with_unserved
  FROM public.ottoq_kpi_p95_time_to_service
 WHERE sim_run_id IN (SELECT sim_run_id FROM ottoq_sim_runs ORDER BY sim_run_seq DESC LIMIT 25);

-- 5.4 name the unserved assets on one run - the next diagnostic's starting point
SELECT d.vehicle_id, d.actual_return_at
  FROM ottoq_vehicle_dispatches d
 WHERE d.sim_run_id = (SELECT sim_run_id FROM ottoq_sim_runs WHERE sim_run_seq = 1763)
   AND d.actual_return_at IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM ottoq_itinerary_legs l
                    WHERE l.sim_run_id = d.sim_run_id AND l.vehicle_id = d.vehicle_id
                      AND l.leg_type NOT IN ('taxi','stage')
                      AND l.actual_start_sim IS NOT NULL
                      AND l.actual_start_sim >= d.actual_return_at)
 ORDER BY d.actual_return_at;
