-- =====================================================================
-- 0108  The 48-tick pair is red, and I cannot yet say why
-- =====================================================================
-- 0107 said prediction 3 was untestable at 12 ticks and scheduled a
-- 48-tick pair to test it properly. That pair FAILED. Not the behaviour
-- prediction -- the DETERMINISM one. Both arms completed 48 ticks and
-- disagree on every canon.
--
-- Pair: job 345, busy_day / 171717 / 48t / flagship, 15:44 UTC
-- (10:44 AM CT). Arms 3226179e (A) and efd467d4 (B).
--
--   canon   arm A                             arm B                             equal
--   fp      92b02f8bb837f8ce6442bba60ab31bb4  92b02f8bb837f8ce6442bba60ab31bb4  YES
--   h_cmd   dc91108ff31ea154b8a7f5c3b30b6cb8  58bea588205308e1ddd4c1829a7c3b98  no
--   h_dec   b3659725156d1b1307dcfc5c9da010b8  79c5d6fbb32cf9f76d73d7b8d88bf8f4  no
--   h_bkg   dd2d71b6427c94f9459931844419775f  860fa17d37ba7e420939470eacfe8d7c  no
--   h_nrg   b646f507ab1ae2552711e854d26f8c7d  d7682636e053e5d90db69d9abc7a65a9  no
--   endst   d6e9e3ee7847847a31c9107bd96214f4  7b89147a47fbdba62ee827d658e0468d  no
--
--   equal = false, outcome = failed, both arms complete = true,
--   both ticks = 48, both end clocks = 2026-09-02T02:00:00+00.
--
-- Both arms had the full horizon. This is NOT the 0107 mistake repeated:
-- nothing here is a partial round. The boot fingerprint is identical, so
-- the two arms started from the same world and diverged during the run.
--
-- *** RESOLUTION (2026-09-04, same day, see db/migrations/0193) *** The
-- cause is named and fixed. It is none of the five migrations. It is an
-- unscoped read in ottoq.ottoq_sim_prearrival_contracts -- the inbound
-- ETA taken as MAX(scheduled_return_at) over ottoq_vehicle_dispatches
-- with no sim_run_id -- so the second arm read the first arm's
-- unreturned 23:00 dispatch for vehicle 0003 and planned its first legs
-- 22 hours out, where they could never be "late". The arms are
-- byte-identical for 59 decisions and fork on exactly that amend_plan.
-- 0181 created the residue class (honest teardown leaves NULL returns);
-- 0192 made the fleet cycle enough for a 48-tick first arm to leave
-- 20-31 such rows; the read itself is older than both. The decision
-- below not to revert 0192 was right for a reason better than the one
-- given: 0192 was never the author. Also recorded in 0193: the repeat
-- pair scheduled below PASSED, and that pass was contamination on both
-- arms, not determinism.
--
-- =====================================================================
-- WHAT I SAID I WOULD DO, AND WHY I AM NOT DOING IT
-- =====================================================================
-- 0192's published prediction 2 reads: "Both arms of every pair still
-- agree. If any pair DISAGREES after this, the guard introduced
-- nondeterminism and must be reverted, not tuned."
--
-- A pair disagrees. By the letter of that rule I should revert 0192 now.
-- I am not going to, and the reason is that THE RULE'S PREMISE IS FALSE.
-- It was written assuming 0192 was the only engine change since this
-- coordinate was last green. It is not. From ottoq_cert_lineage, between
-- the last green 48-tick pair and this red one there are FIVE
-- forces_recert = true migrations, not one:
--
--   2026-09-03 02:55  the_engine_can_say_it_found_nothing_but_not_that_it_never_looked
--   2026-09-03 07:52  the_recorder_wrote_a_status_the_table_refused
--   2026-09-03 11:39  the_cold_start_guard_looked_at_every_depot
--   2026-09-03 17:16  the_watermark_sweep_cleared_every_depot
--   2026-09-04 15:00  0192_an_atom_that_can_be_required_must_be_retirable
--
-- 0192 is one suspect of five. Reverting it would be a one-in-five guess
-- that also restores a KNOWN larger defect -- a depot that parks its
-- entire fleet for twenty hours (0106) -- to fix a determinism failure
-- it may not have caused. That is a worse position than the one we are
-- in, chosen on no evidence.
--
-- So the rule is not being honoured literally, and that is a departure I
-- am recording rather than performing quietly. What IS being honoured is
-- its purpose: 0192 is not certified, the deterministic core is not
-- green, and nothing ships off this coordinate until it is.
--
-- =====================================================================
-- WHY THIS COORDINATE WAS NEVER GOING TO BE INNOCENT
-- =====================================================================
-- The six certification columns are all 12-tick and 24-tick. 48 ticks is
-- NOT one of them. Full history of 48-tick pairs, ever:
--
--   2026-09-02 23:55   cd8e0796 + ed6ad879   equal = TRUE
--   2026-09-04 15:44   3226179e + efd467d4   equal = FALSE
--
-- Two pairs. That is the entire record. So this coordinate has been
-- green exactly once, on 2026-09-02, BEFORE all five recert migrations
-- above -- and was never re-run against any of the first four. Round 13
-- re-certified 12t and 24t after those four and passed 24 of 24; nobody
-- re-ran 48t, because it is not a certification column.
--
-- Which means: the 48-tick coordinate has been UNVERIFIED for four
-- engine changes, and today is the first time anyone looked. The failure
-- may predate 0192 entirely.
--
-- Note what this also implicates: cd8e0796 and ed6ad879 -- the Sep-2
-- green pair -- are the exact runs 0105 and 0106 were written from. Those
-- findings are unaffected (they are about what the engine DID, and both
-- arms agreed then), but they are the last 48-tick evidence we have that
-- reproduces.
--
-- =====================================================================
-- THE ONE FACT THAT NARROWS IT, AND THE ONE THAT DOES NOT
-- =====================================================================
-- NARROWS IT: the 12-tick pair run 24 minutes before this one, at the
-- same scenario/seed/depot, WITH 0192 LIVE, passed on all six canons
-- (0107). So whatever diverges does not diverge in the first 12 ticks.
-- It is horizon-dependent.
--
-- DOES NOT NARROW IT: 0192's guard cannot itself be a randomness source.
-- ottoq_atoms_guard is IMMUTABLE, reads no clock, no random source and
-- no row outside its argument, and A3/A4 proved it total and stable. But
-- "the guard is not random" does NOT mean "the guard did not cause
-- this": by unblocking redeployment it makes the depot do strictly more
-- work over a long horizon, and more work means more opportunities for a
-- PRE-EXISTING nondeterminism to be reached. Exposure and authorship are
-- different claims and the evidence to date separates neither.
--
-- =====================================================================
-- NEXT, AND IN THIS ORDER
-- =====================================================================
-- 1. REPEAT (running: job r14_probe_0192_48t_b, 16:29 UTC). Same
--    coordinate, 0192 still live. If it fails again with DIFFERENT arm
--    hashes than this run, the divergence is live and ongoing. If it
--    passes, the failure is intermittent, which is a different and worse
--    problem than a deterministic one.
-- 2. BISECT BY HORIZON, NOT BY MIGRATION. 12t passes and 48t fails, so
--    run 24t and 36t at this coordinate to find where it breaks. That
--    localises the divergence to a stretch of sim time, which is far
--    cheaper than reverting five migrations one at a time.
-- 3. ONLY THEN attribute. If a horizon exists where it is green with
--    0192 live, 0192 is not the author and the fix belongs at the site
--    the bisect names.
--
-- Predictions 3, 4 and 5 of 0192 remain UNTESTED. A pair that disagrees
-- with itself cannot be used to measure dispatch counts, utilisation or
-- time-to-service, and no number from run 3226179e or efd467d4 may be
-- quoted for any purpose. That is the rule that made this failure
-- visible and it applies to me here.
--
-- =====================================================================
-- QUERIES
-- =====================================================================

-- Q1 — the failing verdict, both arms, every canon.
WITH n AS (SELECT validation_notes::jsonb AS j FROM ottoq_sim_runs
            WHERE sim_run_id='3226179e-8940-44ad-bfa4-ae3f954ed13e')
SELECT j->>'equal' AS equal, j->>'outcome' AS outcome,
       j->'arm_a'->>'complete' AS a_complete, j->'arm_b'->>'complete' AS b_complete,
       j->'arm_a'->>'ticks' AS a_ticks, j->'arm_b'->>'ticks' AS b_ticks,
       j->'arm_a'->>'clock' AS a_clock, j->'arm_b'->>'clock' AS b_clock,
       j->'arm_a'->>'fp'    AS a_fp,    j->'arm_b'->>'fp'    AS b_fp,
       j->'arm_a'->>'h_cmd' AS a_cmd,   j->'arm_b'->>'h_cmd' AS b_cmd,
       j->'arm_a'->>'h_dec' AS a_dec,   j->'arm_b'->>'h_dec' AS b_dec,
       j->'arm_a'->>'h_bkg' AS a_bkg,   j->'arm_b'->>'h_bkg' AS b_bkg,
       j->'arm_a'->>'h_nrg' AS a_nrg,   j->'arm_b'->>'h_nrg' AS b_nrg,
       md5((j->'arm_a'->'endst')::text) AS a_endst,
       md5((j->'arm_b'->'endst')::text) AS b_endst
  FROM n;

-- Q2 — the entire history of 48-tick pairs. Two of them.
SELECT sim_run_id, scenario_code, random_seed, tick_count, depot_id, started_at,
       validation_notes::jsonb->>'equal' AS equal,
       validation_notes::jsonb->'arm_a'->>'fp' AS boot_fp
  FROM ottoq_sim_runs
 WHERE tick_count = 48 AND validation_notes IS NOT NULL
   AND validation_notes::jsonb ? 'equal'
 ORDER BY started_at;

-- Q3 — five recert-forcing migrations since that coordinate was green,
-- not one. This is why the revert rule's premise was false.
SELECT name, forces_recert, classified_at
  FROM public.ottoq_cert_lineage
 WHERE classified_at > '2026-09-02 23:55:00+00' AND forces_recert
 ORDER BY classified_at;

-- Q4 — pair equality by horizon: which tick counts have ever been green.
SELECT tick_count, count(*) AS pair_rows,
       count(*) FILTER (WHERE validation_notes::jsonb->>'equal'='true')  AS equal_true,
       count(*) FILTER (WHERE validation_notes::jsonb->>'equal'='false') AS equal_false,
       min(started_at) AS first_seen, max(started_at) AS last_seen
  FROM ottoq_sim_runs
 WHERE validation_notes IS NOT NULL AND validation_notes::jsonb ? 'equal'
 GROUP BY tick_count ORDER BY tick_count;

-- Q5 — the 12-tick pair 24 minutes earlier, 0192 live, all six equal.
WITH n AS (SELECT validation_notes::jsonb AS j FROM ottoq_sim_runs
            WHERE sim_run_id='5dbc3de9-ce06-4f16-8d46-9b0724c7a186')
SELECT j->>'equal' AS equal,
       (j->'arm_a'->>'h_cmd' = j->'arm_b'->>'h_cmd') AS cmd_equal,
       (j->'arm_a'->>'h_dec' = j->'arm_b'->>'h_dec') AS dec_equal,
       (j->'arm_a'->>'h_bkg' = j->'arm_b'->>'h_bkg') AS bkg_equal,
       (j->'arm_a'->>'h_nrg' = j->'arm_b'->>'h_nrg') AS nrg_equal,
       (md5((j->'arm_a'->'endst')::text) = md5((j->'arm_b'->'endst')::text)) AS endst_equal
  FROM n;
