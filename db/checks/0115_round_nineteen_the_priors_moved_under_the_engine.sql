-- =====================================================================
-- 0115  Round 19: the priors moved under the engine
-- =====================================================================
-- Round 19 ran 03:43-05:27 UTC on 2026-09-06 (10:43 PM-12:27 AM CT),
-- seven pairs on the flagship, the first round after 0198 (03:21 UTC)
-- and 0199 (03:39 UTC), and the second round after 0197 at the floor
-- 0199 corrected. Read 15:18 UTC 09-06 (10:18 AM CT; the check-in fired
-- at 05:37 UTC and this session picked it up ten hours late).
--
-- Every pair PASSED: both arms complete, every hash equal between arms,
-- h_prop and h_defr present in every arm for the first time. And FOUR
-- of six canons MOVED against round 18. Both statements are true and
-- the second is the finding.
--
-- 1. THE MATRIX
--
--   #  fired  column                 equal  h_cmd     h_bkg     h_nrg     h_prop    endst     vs r18
--   1  03:43  busy_day/314159/12t    yes    cf74d080  eaff0912  4afd1004  2b86847e  d0870a7a  identical, every field
--   2  03:56  busy_day/171717/12t    yes    80183641  b1d72a62  625014b7  2574c54f  31887429  identical, every field
--   3  04:09  normal_day/171717/12t  yes    634a8781  97056af3  b3a22762  940d3890  e4543944  MOVED: cmd dec evt bkg nrg endst
--   4  04:22  normal_day/171717/12t  yes    634a8781  97056af3  b3a22762  940d3890  e4543944  = pair 3 on every field
--   5  04:35  busy_day/424242/12t    yes    adf745a2  c4df69ab  481f8320  029cad7d  0838b39d  MOVED: bkg nrg endst (cmd dec evt same)
--   6  04:48  busy_day/171717/24t    yes    5dd1816d  38ffdbe8  5b96f9b9  2574c54f  89d7b898  MOVED: cmd dec evt bkg nrg endst
--   7  05:11  busy_day/424242/24t    yes    997e2c37  1e5f1875  fd6cfd0a  bea94486  84fd8d3f  MOVED: bkg nrg endst (cmd dec evt same)
--
--   boot chargers.world e06b403e on all fourteen arms, equal to round 18:
--   every arm booted the same world. h_defr d41d8cd9 on all fourteen.
--   Pair wall time: 12-tick 565-756 s; 24-tick 1084 and 959 s.
--
-- 2. THE CARRIER, CONVICTED
--
--   cron job 2, ottoq-twin-ingest-weekly, schedule '0 4 * * 0' (Sundays
--   04:00 UTC). 2026-09-06 is a Sunday. job_run_details: started
--   04:05:25 UTC, succeeded. net._http_response ids 83201-83202, both
--   04:05:25, both 200:
--     eia   fetched 8784  refit grid_demand_mw   (n 8784, mean 19664.02)
--           profile hourly_grid_demand_shape refit
--     noaa  fetched 722   refit ambient_temp_c   (n 722,  mean 17.28)
--           precip 361    refit precip_mm        (n 361,  mean 2.73)
--   ottoq_calibration_distributions.fitted_at: three rows at 04:05:26-29;
--   the previous fits were 07-10 and 05-28. ottoq_calibration_profiles:
--   one row at 04:05:30. ottoq_calibration_datasets.ingested_at moved
--   for eia_grid and noaa_nws.
--
--   Pair 2 fired 03:56:00 and ran 565 s: its transaction closed at
--   04:05:25, the same second the ingest started. Pairs 1 and 2 match
--   round 18 on every field. Pair 3 fired 04:09, after the refit, and it
--   and every pair after it moved. The twin samples ambient temperature,
--   precipitation and grid demand from exactly those fitted grids
--   (ottoq_sample_calibrated inside ottoq_twin_deal); a different prior
--   is a different card, a different card is a different charge
--   acceptance and a different energy picture, and from there the
--   decisions cascade.
--
--   First divergence, normal_day (pair 3 vs the round-18 pair):
--     ticks 1-3 identical (63/122/135 decisions, same hash)
--     tick 4: two vehicles swapped stalls. 8eeaaef3 took 70fa3080 (r19)
--             instead of 55fe979e (r18) and bc55d859 the reverse; its
--             rationale SoC reads 79 in r19 and 78 in r18 -- the world
--             had already drifted by one percent before the first
--             different decision. Manifests for both vehicles identical
--             in both rounds. Proposal content identical in both rounds.
--   First divergence, busy_day/424242/12t (energy stream):
--     ticks 1-3 identical; tick 4 bess_setpoint/charge_cap reasons carry
--     desired_ev_kw 331 (r18) vs 330 (r19), same temp_c 28.04, same LMP,
--     same demand target. One kilowatt of EV demand, then everything.
--
--   What this is NOT: not 0198 (the proposal rows are identical in
--   content; only declared_source was added), not 0199 (harness only,
--   pinned), not 0200 (not applied). No policy param, feed plan, rule,
--   scenario or vehicle row changed between the rounds; no other run
--   touched the flagship in the window.
--
-- 3. THE 0199 PREDICTIONS
--
--    1. seven of seven pass, both arms complete              MET
--    2. every hash equals round 18                           NOT MET for
--       pairs 3-7 (four columns). The cause is outside the engine and
--       is named above. 0199 changed no engine function (its A0 pin
--       stands), and pairs 1-2 -- the only ones that ran on the same
--       priors as round 18 -- are byte-identical to it.
--    3. h_prop equals the retro values                       NOT MET, and
--       could not have been: 0198 began recording declared_source on
--       proposals submitted through the submitter (ottoq_service_priority
--       rows; greedy_constrained writes directly and stays NULL), and
--       0199 hashes it. Hashing round-19 pair 1 with declared_source
--       blanked gives b32df53d, the retro value, exactly. The live
--       values are the first proposal canons. The retro values in
--       0199's footer and db/canons/round14-18 are pre-0198 row shapes.
--    4. six columns green with canon_prop populated          PARTLY:
--       canon_prop/canon_defr populated on all six. Green on three:
--       171717/12t and 314159/12t (pre-refit, second pass after 0197)
--       and normal_day (its two post-refit twins agree). Not green on
--       171717/24t, 424242/12t, 424242/24t: their round-19 value is the
--       first at the new priors.
--
-- 4. WHAT THE CERTIFICATE SAYS NOW
--
--    The engine is deterministic: fourteen arms, seven equal pairs,
--    twins equal on every field. The engine is also reproducible across
--    rounds WHEN ITS INPUTS ARE: the two pairs that ran on unchanged
--    priors reproduced round 18 to the byte, five rounds running. What
--    the instrument could not do is name a prior change: the
--    reproducibility key is scenario + seed + policy + depot, and the
--    calibration grids the twin draws from are not in it. G14 (task)
--    puts a calibration fingerprint in the boot image, the arm and the
--    matrix, and stops the ingest from running under a certification.
--    Until that lands and a round runs on it, "canon stable r14-r19" is
--    true only for the two columns that ran before 04:05:25 UTC.
--
-- 5. RECORDED, NOT DONE
--
--    The ingest job started 5 min 25 s late, in the same second the
--    pair-2 transaction closed. pg_cron ran it after the long pair
--    rather than alongside it; a future guard must not assume the
--    ingest fires at :00.
--    The calibration datasets carry no version; a run cannot say which
--    priors it ran on. G14 (c).
--
-- =====================================================================
-- Q1 -- the matrix, re-derived from the rows
-- =====================================================================
SELECT to_char(r.started_at,'HH24:MI') AS fired, left(r.sim_run_id::text,8) AS run,
       v->>'scenario' AS scenario, v->>'seed' AS seed, v->>'ticks' AS ticks,
       v->>'equal' AS equal, v->>'outcome' AS outcome,
       left(v->'arm_a'->>'h_cmd',8) AS h_cmd, left(v->'arm_a'->>'h_bkg',8) AS h_bkg,
       left(v->'arm_a'->>'h_nrg',8) AS h_nrg, left(v->'arm_a'->>'h_prop',8) AS h_prop_a, left(v->'arm_b'->>'h_prop',8) AS h_prop_b,
       left(v->'arm_a'->>'h_defr',8) AS h_defr, left(md5(v->'arm_a'->>'endst'),8) AS endst_a, left(md5(v->'arm_b'->>'endst'),8) AS endst_b,
       left(v->'arm_a'->'boot'->'chargers'->'world'->>'h',8) AS boot_a,
       v->'arm_a'->>'complete' AS done_a, v->'arm_b'->>'complete' AS done_b
FROM ottoq_sim_runs r CROSS JOIN LATERAL (SELECT r.validation_notes::jsonb AS v) x
WHERE r.started_at >= '2026-09-06 03:42+00' AND r.started_at < '2026-09-06 05:40+00'
  AND r.validation_notes LIKE '{%equal%' AND r.sim_run_id::text LIKE (v->'arm_a'->>'run')||'%'
ORDER BY r.started_at;
-- expect seven rows, equal = true, h_prop_a = h_prop_b, e06b403e boot on each.

-- =====================================================================
-- Q2 -- round 19 against round 18, per column, every field
-- =====================================================================
WITH v AS (
  SELECT CASE WHEN r.started_at >= '2026-09-06 03:42+00' THEN 'r19' ELSE 'r18' END AS rnd,
         (x.v->>'scenario')||'/'||(x.v->>'seed')||'/'||(x.v->>'ticks')||'t' AS col, r.started_at, x.v->'arm_a' AS a
  FROM ottoq_sim_runs r CROSS JOIN LATERAL (SELECT r.validation_notes::jsonb AS v) x
  WHERE ((r.started_at >= '2026-09-05 17:39+00' AND r.started_at < '2026-09-05 19:30+00')
      OR (r.started_at >= '2026-09-06 03:42+00' AND r.started_at < '2026-09-06 05:40+00'))
    AND r.validation_notes LIKE '{%equal%' AND r.sim_run_id::text LIKE (x.v->'arm_a'->>'run')||'%'),
first_of AS (SELECT DISTINCT ON (rnd, col) rnd, col, started_at, a FROM v ORDER BY rnd, col, started_at)
SELECT r19.col, to_char(r19.started_at,'HH24:MI') AS r19_fired,
       (r18.a->>'h_cmd')=(r19.a->>'h_cmd') AS cmd_eq, (r18.a->>'h_dec')=(r19.a->>'h_dec') AS dec_eq,
       (r18.a->>'h_evt')=(r19.a->>'h_evt') AS evt_eq, (r18.a->>'h_bkg')=(r19.a->>'h_bkg') AS bkg_eq,
       (r18.a->>'h_nrg')=(r19.a->>'h_nrg') AS nrg_eq, (r18.a->>'endst')=(r19.a->>'endst') AS endst_eq,
       (r18.a->>'boot')=(r19.a->>'boot') AS boot_eq
FROM first_of r19 JOIN first_of r18 ON r18.col = r19.col AND r18.rnd='r18' AND r19.rnd='r19'
ORDER BY r19.started_at;
-- expect: the two columns fired before 04:05 true everywhere; the rest false
-- on bkg/nrg/endst at least; boot_eq true on all six.

-- =====================================================================
-- Q3 -- the refit, in the ledger
-- =====================================================================
SELECT jobid, start_time, end_time, status FROM cron.job_run_details WHERE jobid = 2 ORDER BY start_time DESC LIMIT 3;
SELECT dataset_code, variable_name, segment, sample_count, round(mean_value,3) AS mean_value, fitted_at
  FROM ottoq_calibration_distributions WHERE fitted_at >= '2026-09-06 04:00+00' ORDER BY fitted_at;
SELECT dataset_code, profile_name, profile_kind, fitted_at
  FROM ottoq_calibration_profiles WHERE fitted_at >= '2026-09-06 04:00+00';
-- expect the run at 04:05:25, three distributions and one profile refit at 04:05:26-30.

-- =====================================================================
-- Q4 -- the first different decision, normal_day, tick 4
-- =====================================================================
WITH a AS (SELECT action_context||'|'||entity_id::text||'|'||outcome_status||'|'||COALESCE(enacted_action->>'verb', proposed_action->>'verb','-')||'|'||COALESCE(proposed_action->>'stall_id','-') k, d.*
             FROM ottoq_decisions d WHERE sim_run_id='293baa0b-7bd4-4c0a-98fa-ac725f1aeead' AND tick_seq=4),
     b AS (SELECT action_context||'|'||entity_id::text||'|'||outcome_status||'|'||COALESCE(enacted_action->>'verb', proposed_action->>'verb','-')||'|'||COALESCE(proposed_action->>'stall_id','-') k, d.*
             FROM ottoq_decisions d WHERE sim_run_id='3bbbe05a-2242-4194-b1c4-2964080c8c7a' AND tick_seq=4)
SELECT 'only_r18' side, a.k, a.proposed_action->'rationale'->>'soc' AS soc FROM a WHERE NOT EXISTS (SELECT 1 FROM b WHERE b.k=a.k)
UNION ALL
SELECT 'only_r19', b.k, b.proposed_action->'rationale'->>'soc' FROM b WHERE NOT EXISTS (SELECT 1 FROM a WHERE a.k=b.k)
ORDER BY 2, 1;
-- expect four rows: two vehicles, two stalls, swapped; SoC 78 vs 79 on 8eeaaef3.
