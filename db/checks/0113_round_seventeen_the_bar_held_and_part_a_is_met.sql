-- =====================================================================
-- 0113  Round 17: the bar held, and part A of the roadmap is met
-- =====================================================================
-- Round 17 ran 03:36-05:19 UTC on 2026-09-05 (10:36 PM-12:19 AM CT),
-- seven pairs on the flagship, NO migration applied between rounds 16
-- and 17. Read 05:31 UTC. Every pair passed, every arm completed, and
-- every hash, end state and boot fingerprint is byte-identical to round
-- 16 in every column. Two consecutive rounds of the six-column matrix
-- now agree with each other on every field the verdict carries.
--
-- 1. THE MATRIX
--
--   #  fired  column                 equal  h_cmd     h_dec     h_evt     h_bkg     h_nrg     endst     vs round 16
--   1  03:36  busy_day/314159/12t    yes    cf74d080  1788ee1c  25cf62c5  eaff0912  4afd1004  d0870a7a  identical
--   2  03:49  busy_day/314159/12t    yes    cf74d080  1788ee1c  25cf62c5  eaff0912  4afd1004  d0870a7a  identical (= pair 1 on every field)
--   3  04:02  busy_day/171717/12t    yes    80183641  6e116d5b  4f8b2970  b1d72a62  625014b7  31887429  identical
--   4  04:15  normal_day/171717/12t  yes    af8b5e6d  3a8719f8  0beff613  2c7e0a3a  de3b353e  ccb2e2c1  identical
--   5  04:28  busy_day/424242/12t    yes    adf745a2  05bc65e6  67ee1af6  84a9b51c  0cac7e0b  5ec725ad  identical
--   6  04:41  busy_day/171717/24t    yes    38465601  09769827  61d5ff27  3b52ea78  7606aaf2  9b986ebb  identical
--   7  05:04  busy_day/424242/24t    yes    997e2c37  fd484142  2c51bb4c  f597a790  f2b72ada  7076e486  identical
--
--   (endst is the first 8 of md5 over the end-state fingerprint text.)
--   Boot chargers.world: e06b403e on all fourteen arms.
--   Swallowed-23505 log lines per arm: 4/4, 4/4, 7/7, 9/9, 9/9, 11/11,
--   9/9 -- equal within every pair and equal to round 16 per column.
--   Pair wall time: 12-tick 9-11 min; 24-tick 17 and 15 min.
--
-- 2. THE BAR (published in 0112 section 5 before the round ran)
--
--    a. seven of seven green, both arms complete      -- MET
--    b. the two 314159/12t pairs agree on every field -- MET (Q2: every
--       verdict key equal but 'run'). This is the inter-pair bar shown
--       on a second column, and on the newest canon.
--    c. h_cmd, h_dec, h_bkg, h_nrg identical to r16    -- MET, 6 of 6 (Q3)
--    d. h_evt identical to round 16                    -- MET, 6 of 6 (Q3).
--       Round 16's h_evt movement was attributed to the wash trigger
--       going live; a second movement here would have refuted that. It
--       did not move.
--    e. endst identical to round 16; e06b403e x14      -- MET (Q3, Q1)
--
-- 3. TASK #56 PART A, ITEM BY ITEM
--
--    "all six certification columns green"
--        Rounds 16 and 17, seven of seven each.
--    "AND inter-pair reproducible"
--        171717/12t twins: rounds 15 and 16. 314159/12t twins: round
--        17. Two columns, three rounds.
--    "with h_nrg in the verdict"
--        Since 0148; equal on every pair of every round since.
--    "every canon stable across at least two rounds"
--        171717/12t, normal_day, 171717/24t: rounds 14-17.
--        424242/12t, 424242/24t: rounds 15-17.
--        314159/12t: rounds 16-17.
--    "the 0066 findings closed"
--        arrival-payload odometer: 0150 applied 7:13 AM CT Sep 2 (0072
--        section 4). Live (Q5): the SUM(miles_driven) in
--        twin.ottoq_sim_build_arrival_payload is predicated on the
--        dispatch's own sim_run_id.
--        ottoq_fleet_pending_commands: 0151 applied same time. Live
--        (Q5): the function returns only rows with sim_run_id IS NULL,
--        i.e. production commands.
--    "peak_site_kw reproducible (0050 correction, 0051)"
--        Closed in round 6 (0072 section 2): 0144 reset, 0146/0147
--        deterministic BESS dispatch, 0148 h_nrg. The remaining item
--        0072 named -- the run key hashed the outcome -- closed by 0167.
--        Re-measured here on rounds 16 and 17 (Q4): ottoq_kpi_five is
--        identical between the two arms of every pair on every key but
--        sim_run_id, and identical across the two rounds per column.
--
--          column                 peak_site_kw  asset_hours   turns   touch  p95_min
--          busy_day/314159/12t    818.2         162.50        1.53    0.142  195.0
--          busy_day/171717/12t    918.4         155.50        1.63    0.195  210.0
--          normal_day/171717/12t  1093.8        173.50        1.75    0.192  150.0
--          busy_day/424242/12t    677.5         150.50        1.57    0.173  240.0
--          busy_day/171717/24t    918.4         209.96        2.43    0.211  201.0
--          busy_day/424242/24t    677.5         204.32        2.37    0.216  240.0
--
--        Every one of those numbers has four run IDs behind it (two arms
--        x two rounds, six for 314159/12t), and one config_hash per
--        column (d011095c, 7ed47c7e, c220d06b, 3f53e000, 462bd796,
--        28b2db3c) shared by every run in the column.
--
--    VERDICT: the bar as written in task #56 part A is met.
--
-- 4. WHAT "MET" COVERS, AND WHAT IT DOES NOT
--
--    Covers: the flagship depot (427 stalls, 116 vehicles), two
--    scenarios, three seeds, 12 and 24 ticks, the local decide path
--    with the cuOpt proposer quiesced for the arm (0152, applied 7:13
--    AM CT Sep 2). Within that envelope the engine reproduces its
--    commands, decisions, bookings, energy commands, event stream and
--    end state byte-for-byte across arms, across pairs, and across
--    rounds, and the five KPIs with them.
--
--    Does not cover: the proposer in the loop (part B brings it back
--    under the deferral pattern with its proposals hashed into the
--    verdict), a second depot, 48 ticks (0193 ran two 48-tick pairs
--    once; not part of the standing matrix), and anything the four
--    recorded-not-done items touch (grant list keyed by run;
--    enact_space_assignment 23505s; the seven 0129 leg cursors; per-seat
--    subtransactions). None of the four produced a fork in 17 rounds,
--    which is evidence they are latent, not evidence they are absent.
--
-- 5. RECORDED, NOT DONE (carried from 0112, unchanged)
--    - grant list keyed by run (hardening; 0196 clears it per tick).
--    - ottoq_enact_space_assignment 23505s swallowed by the outer handler.
--    - the seven 0129 leg cursors ordered on per-run UUIDs.
--    - per-seat subtransactions in the bay-activation loop.
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
WHERE r.started_at >= '2026-09-05 03:35+00' AND r.started_at < '2026-09-05 05:30+00'
  AND r.validation_notes LIKE '{%equal%'
  AND r.sim_run_id::text LIKE (v->'arm_a'->>'run')||'%'
ORDER BY r.started_at;
-- expect seven rows, equal = true on each, e06b403e in both boot columns.

-- =====================================================================
-- Q2 -- the twins (pairs 1 and 2): every verdict field equal
-- =====================================================================
SELECT a.k, (a.v = b.v) AS equal
FROM (SELECT key AS k, value::text AS v FROM ottoq_sim_runs, jsonb_each((validation_notes::jsonb)->'arm_a')
      WHERE sim_run_id::text LIKE '4296e65d%') a
JOIN (SELECT key AS k, value::text AS v FROM ottoq_sim_runs, jsonb_each((validation_notes::jsonb)->'arm_a')
      WHERE sim_run_id::text LIKE '55fc0c0c%') b USING (k)
WHERE a.k <> 'run'
ORDER BY 1;
-- expect equal = true on every row.

-- =====================================================================
-- Q3 -- round 17 against round 16, per column: every hash and the end
--       state equal
-- =====================================================================
WITH v AS (
  SELECT CASE WHEN r.started_at >= '2026-09-05 03:35+00' THEN 'r17' ELSE 'r16' END AS rnd,
         (x.v->>'scenario')||'/'||(x.v->>'seed')||'/'||(x.v->>'ticks')||'t' AS col,
         r.started_at, x.v->'arm_a' AS a
  FROM ottoq_sim_runs r CROSS JOIN LATERAL (SELECT r.validation_notes::jsonb AS v) x
  WHERE r.started_at >= '2026-09-05 01:38+00' AND r.started_at < '2026-09-05 05:30+00'
    AND r.validation_notes LIKE '{%equal%'
    AND r.sim_run_id::text LIKE (x.v->'arm_a'->>'run')||'%'),
first_of AS (SELECT DISTINCT ON (rnd, col) rnd, col, a FROM v ORDER BY rnd, col, started_at)
SELECT r16.col,
       (r16.a->>'h_cmd') = (r17.a->>'h_cmd') AS cmd_eq,
       (r16.a->>'h_dec') = (r17.a->>'h_dec') AS dec_eq,
       (r16.a->>'h_evt') = (r17.a->>'h_evt') AS evt_eq,
       (r16.a->>'h_bkg') = (r17.a->>'h_bkg') AS bkg_eq,
       (r16.a->>'h_nrg') = (r17.a->>'h_nrg') AS nrg_eq,
       (r16.a->>'endst') = (r17.a->>'endst') AS endst_eq,
       (r16.a->>'boot')  = (r17.a->>'boot')  AS boot_eq
FROM first_of r16 JOIN first_of r17 ON r17.col = r16.col AND r16.rnd = 'r16' AND r17.rnd = 'r17'
ORDER BY 1;
-- expect six rows, true in every column.

-- =====================================================================
-- Q4 -- the five KPIs: identical between arms and across rounds 16/17
--       on every key but sim_run_id
-- =====================================================================
WITH pairs AS (
  SELECT CASE WHEN r.started_at >= '2026-09-05 03:35+00' THEN 'r17' ELSE 'r16' END AS rnd,
         (x.v->>'scenario')||'/'||(x.v->>'seed')||'/'||(x.v->>'ticks')||'t' AS col,
         to_char(r.started_at,'HH24:MI') AS t,
         (x.v->'arm_a'->>'run')::uuid AS a, (x.v->'arm_b'->>'run')::uuid AS b
  FROM ottoq_sim_runs r CROSS JOIN LATERAL (SELECT r.validation_notes::jsonb AS v) x
  WHERE r.started_at >= '2026-09-05 01:38+00' AND r.started_at < '2026-09-05 05:30+00'
    AND r.validation_notes LIKE '{%equal%'
    AND r.sim_run_id::text LIKE (x.v->'arm_a'->>'run')||'%'),
k AS (SELECT p.*, public.ottoq_kpi_five(p.a) - 'sim_run_id' AS ka,
                  public.ottoq_kpi_five(p.b) - 'sim_run_id' AS kb FROM pairs p)
SELECT col, rnd, t, (ka = kb) AS arms_equal,
       left(md5(ka::text),8) AS kpi_md5,
       ka->>'peak_site_kw' AS peak_kw, ka->>'asset_hours_available_per_day' AS asset_hours,
       ka->>'service_point_turns_per_point_per_day' AS turns, ka->>'touch_events_per_turn' AS touch,
       ka->>'p95_time_to_service_min' AS p95_min, ka->'run_key'->>'config_hash' AS config_hash
FROM k ORDER BY col, rnd, t;
-- expect arms_equal = true on all fourteen rows, and kpi_md5 (and config_hash)
-- constant within each column across both rounds.

-- =====================================================================
-- Q5 -- the 0066 fixes, live
-- =====================================================================
SELECT 'arrival_payload_odometer' AS fix, m[1] AS line
FROM regexp_matches(pg_get_functiondef('twin.ottoq_sim_build_arrival_payload'::regproc),
                    '([^\n]*(?:miles_driven|sim_run_id)[^\n]*)', 'g') m
UNION ALL
SELECT 'fleet_pending_commands', m[1]
FROM regexp_matches(pg_get_functiondef('public.ottoq_fleet_pending_commands'::regproc),
                    '([^\n]*(?:sim_run_id)[^\n]*)', 'g') m;
-- expect: the odometer SUM carries a sim_run_id predicate (0150);
--         the fleet API filters c.sim_run_id IS NULL (0151).
