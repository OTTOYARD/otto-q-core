-- =====================================================================
-- 0114  Round 18: nothing moved, and that was the prediction
-- =====================================================================
-- Round 18 ran 17:40-19:23 UTC on 2026-09-05 (12:40-2:23 PM CT), seven
-- pairs on the flagship, after 0197 applied at 17:35 UTC. Read 03:08 UTC
-- 09-06. Every pair passed, every arm completed, and every hash, end
-- state and boot fingerprint is byte-identical to round 17 in every
-- column. 0197 changed the decide path; it did not change a single
-- decision the certified rounds make, exactly as its footer predicted.
--
-- 1. THE MATRIX
--
--   #  fired  column                 equal  h_cmd     h_evt     endst     boot_ch   vs round 17
--   1  17:40  busy_day/314159/12t    yes    cf74d080  25cf62c5  d0870a7a  e06b403e  identical, every field
--   2  17:53  busy_day/171717/12t    yes    80183641  4f8b2970  31887429  e06b403e  identical, every field
--   3  18:06  normal_day/171717/12t  yes    af8b5e6d  0beff613  ccb2e2c1  e06b403e  identical, every field
--   4  18:19  normal_day/171717/12t  yes    af8b5e6d  0beff613  ccb2e2c1  e06b403e  identical (= pair 3 on every field)
--   5  18:32  busy_day/424242/12t    yes    adf745a2  67ee1af6  5ec725ad  e06b403e  identical, every field
--   6  18:45  busy_day/171717/24t    yes    38465601  61d5ff27  9b986ebb  e06b403e  identical, every field
--   7  19:08  busy_day/424242/24t    yes    997e2c37  2c51bb4c  7076e486  e06b403e  identical, every field
--
--   "every field" = h_cmd, h_dec, h_evt, h_bkg, h_nrg, endst (full text)
--   and boot (full text), compared per column against round 17's first
--   pair (Q2). endst above is the first 8 of md5 over the endst text.
--   Pair wall time: 12-tick 9-12 min; 24-tick 20 and 15 min.
--
-- 2. THE 0197 PREDICTIONS
--
--    1. seven of seven green, both arms complete           -- MET
--    2. NO canon moves; every value equals round 17         -- MET, 7 of 7
--       columns, 7 of 7 fields each (Q2). The refusal branch 0197
--       introduced was never reached, as the round-16/17 log census said
--       it would not be.
--    3. zero 'ROLLED BACK, calendar refused' warnings       -- MET
--       Postgres log census 17:39-19:30 UTC:
--         ROLLED BACK, calendar refused              0
--         ottoq_record_enacted_booking: booking REFUSED  0
--         ottoq_record_enacted_booking: FAILED           0
--         ottoq_enact_space_assignment: FAILED         130  (80 P0001 arm
--                                                           interlock, 50
--                                                           23505 one-vehicle-
--                                                           per-stall)
--         ottoq_reconcile_displace_stale_claim: FAILED  84  (82 23505, 2 P0001)
--       All 214 FAILED lines are raises inside a handled block, i.e.
--       subtransactions that rolled themselves back -- the same class
--       0197 measured at 254 over rounds 16+17. The new rollback branch
--       is a different message and it did not fire.
--    4. normal_day/171717/12t twins agree on every field   -- MET (Q3)
--
-- 3. WHERE THE CERTIFICATION STANDS AFTER 0197
--
--    six columns green                     rounds 16, 17, 18
--    inter-pair reproducible               THREE columns now:
--                                            busy_day/171717/12t   r15, r16
--                                            busy_day/314159/12t   r17
--                                            normal_day/171717/12t r18
--    canons stable                         171717/12t, normal_day, 171717/24t: r14-r18
--                                          424242/12t, 424242/24t: r15-r18
--                                          314159/12t: r16-r18
--    decide path changed by 0197           yes, and provably without
--                                          effect on any certified decision
--
-- 4. RECORDED, NOT DONE (G13 grows by one line)
--
--    The displace path hits the one-vehicle-per-stall unique index 82
--    times per round, the same way ottoq_enact_space_assignment does 50
--    times. Both are caught and rolled back. Both mean the pre-checks
--    (ottoq_reserve_stall CAS, the "no vehicle physically in this stall"
--    predicate) are not preventing the attempt; the index is doing the
--    work. Recorded in task G13 with the 96 from rounds 16+17.
--
-- =====================================================================
-- Q1 -- the matrix, re-derived from the rows
-- =====================================================================
SELECT to_char(r.started_at,'HH24:MI') AS fired, left(r.sim_run_id::text,8) AS run,
       v->>'scenario' AS scenario, v->>'seed' AS seed, v->>'ticks' AS ticks,
       v->>'equal' AS equal, v->>'outcome' AS outcome,
       left(v->'arm_a'->>'h_cmd',8) AS h_cmd, left(v->'arm_a'->>'h_dec',8) AS h_dec,
       left(v->'arm_a'->>'h_evt',8) AS h_evt, left(v->'arm_a'->>'h_bkg',8) AS h_bkg,
       left(v->'arm_a'->>'h_nrg',8) AS h_nrg,
       left(v->'arm_a'->'boot'->'chargers'->'world'->>'h',8) AS boot_ch_a,
       left(v->'arm_b'->'boot'->'chargers'->'world'->>'h',8) AS boot_ch_b,
       left(md5(v->'arm_a'->>'endst'),8) AS endst_a, left(md5(v->'arm_b'->>'endst'),8) AS endst_b,
       v->'arm_a'->>'complete' AS done_a, v->'arm_b'->>'complete' AS done_b
FROM ottoq_sim_runs r
CROSS JOIN LATERAL (SELECT r.validation_notes::jsonb AS v) x
WHERE r.started_at >= '2026-09-05 17:39+00' AND r.started_at < '2026-09-05 19:30+00'
  AND r.validation_notes LIKE '{%equal%'
  AND r.sim_run_id::text LIKE (v->'arm_a'->>'run')||'%'
ORDER BY r.started_at;
-- expect seven rows, equal = true on each, e06b403e in both boot columns.

-- =====================================================================
-- Q2 -- round 18 against round 17, per column, every field
-- =====================================================================
WITH v AS (
  SELECT CASE WHEN r.started_at >= '2026-09-05 17:39+00' THEN 'r18' ELSE 'r17' END AS rnd,
         (x.v->>'scenario')||'/'||(x.v->>'seed')||'/'||(x.v->>'ticks')||'t' AS col,
         r.started_at, x.v->'arm_a' AS a
  FROM ottoq_sim_runs r CROSS JOIN LATERAL (SELECT r.validation_notes::jsonb AS v) x
  WHERE r.started_at >= '2026-09-05 03:35+00' AND r.started_at < '2026-09-05 19:30+00'
    AND r.validation_notes LIKE '{%equal%'
    AND r.sim_run_id::text LIKE (x.v->'arm_a'->>'run')||'%'),
first_of AS (SELECT DISTINCT ON (rnd, col) rnd, col, a FROM v ORDER BY rnd, col, started_at)
SELECT r18.col,
       (r17.a->>'h_cmd') = (r18.a->>'h_cmd') AS cmd_eq,
       (r17.a->>'h_dec') = (r18.a->>'h_dec') AS dec_eq,
       (r17.a->>'h_evt') = (r18.a->>'h_evt') AS evt_eq,
       (r17.a->>'h_bkg') = (r18.a->>'h_bkg') AS bkg_eq,
       (r17.a->>'h_nrg') = (r18.a->>'h_nrg') AS nrg_eq,
       (r17.a->>'endst') = (r18.a->>'endst') AS endst_eq,
       (r17.a->>'boot')  = (r18.a->>'boot')  AS boot_eq
FROM first_of r18 JOIN first_of r17 ON r17.col = r18.col AND r17.rnd = 'r17' AND r18.rnd = 'r18'
ORDER BY 1;
-- expect six rows, true in every column.

-- =====================================================================
-- Q3 -- the normal_day twins (pairs 3 and 4): every verdict field equal
-- =====================================================================
WITH t AS (
  SELECT r.started_at, r.validation_notes::jsonb v
  FROM ottoq_sim_runs r
  WHERE r.started_at BETWEEN '2026-09-05 18:05+00' AND '2026-09-05 18:20+00'
    AND r.validation_notes LIKE '{%equal%'
    AND r.sim_run_id::text LIKE ((r.validation_notes::jsonb)->'arm_a'->>'run')||'%'
    AND (r.validation_notes::jsonb)->>'scenario' = 'normal_day'),
p AS (SELECT (array_agg(v ORDER BY started_at))[1] a, (array_agg(v ORDER BY started_at))[2] b, count(*) n FROM t)
SELECT n AS twins_found, k, (a->'arm_a'->k)::text = (b->'arm_a'->k)::text AS equal
FROM p, jsonb_object_keys(p.a->'arm_a') k
WHERE k <> 'run' ORDER BY k;
-- expect twins_found = 2 and equal = true on every row.

-- The swallowed-refusal census is a Supabase log query (ClickHouse), not SQL here:
--   select countIf(event_message like '%ROLLED BACK, calendar refused%'),
--          countIf(event_message like 'ottoq_record_enacted_booking: booking REFUSED%'),
--          countIf(event_message like 'ottoq_enact_space_assignment: FAILED%'),
--          countIf(event_message like 'ottoq_reconcile_displace_stale_claim: FAILED%')
--   from logs where source='postgres_logs'   -- window 2026-09-05T17:39Z .. 19:30Z
-- Round 18: 0, 0, 130, 84.
