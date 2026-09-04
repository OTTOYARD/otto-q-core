-- =====================================================================
-- 0109  The engine repeats itself; the world it boots from did not
-- =====================================================================
-- Three things happened after 0193 and this file records all three,
-- with the queries that reproduce each number.
--
-- 1. THE 0193 PROOF PASSED. Two consecutive 48-tick pairs at
--    busy_day/171717/flagship, run back to back and non-overlapping:
--
--      pair  job  fired (UTC)  wall   equal  fp        h_cmd     h_dec     h_evt     h_bkg     h_nrg
--      P1    350  17:47:00     2014s  true   92b02f8b  dc91108f  b3659725  3fad6a78  dd2d71b6  b646f507
--      P2    351  18:20:34     1548s  true   92b02f8b  dc91108f  b3659725  3fad6a78  dd2d71b6  b646f507
--
--    Equal within each pair, equal across the two pairs, and equal to
--    the FIRST-EXECUTED arm of the 15:44 pair that 0108 recorded as red
--    (efd467d4: the arm that created the residue rather than reading
--    it). The second pair ran with strictly more residue than the first
--    (the first pair's own 20-31 unreturned dispatches per arm) and did
--    not notice, which is what "scoped" means. 0193 predictions 1-3
--    hold: 63 tick-1 decisions per arm, amend_plan for vehicle 0003 in
--    every arm, vehicle 0003's first legs planned in the 02:00-03:00
--    window. Prediction 4 (the 12-tick canon changes from 15:20's
--    value) was WRONG, and pleasantly: see 2.
--
-- 2. ROUND 14 (six columns, post-0192+0193). Column 1 at 19:06 UTC:
--
--      busy_day/171717/12t  equal=true  h_cmd 80183641  h_dec 6e116d5b
--                           h_evt 4f8b2970  h_bkg b1d72a62  h_nrg 625014b7
--
--    Byte-identical to the 15:20 pair on every engine canon. 0193
--    changed nothing a 12-tick run does, because a 12-tick arm ends at
--    08:00 sim, before any car is re-dispatched, before any unreturned
--    dispatch could be read. The 12-tick canon therefore did NOT move
--    between 0192 and 0193; 0193 prediction 4 assumed it would.
--
--    The full round (fired 19:06-20:30 UTC, read 20:53 UTC):
--
--      c1 busy_day/171717/12t   19:06  equal=TRUE   h_cmd 80183641  h_dec 6e116d5b  h_evt 4f8b2970  h_bkg b1d72a62  h_nrg 625014b7
--      c2 busy_day/314159/12t   19:26  equal=FALSE  cf74d080 vs f2bd5208 -- fork at decision 505, db/checks/0110, fixed by 0195
--      c3 normal_day/171717/12t 19:40  equal=TRUE   h_cmd af8b5e6d  h_dec 3a8719f8  h_evt 7872892a  h_bkg 2c7e0a3a  h_nrg de3b353e
--      c4 busy_day/424242/12t   19:54  equal=TRUE   h_cmd 63f1dbe1  h_dec a0f541c2  h_evt 0cd28481  h_bkg 5a227276  h_nrg 0cac7e0b
--      c5 busy_day/171717/24t   20:08  equal=TRUE   h_cmd 38465601  h_dec 09769827  h_evt 5c9a64cd  h_bkg 3b52ea78  h_nrg 7606aaf2
--      c6 busy_day/424242/24t   20:30  equal=TRUE   h_cmd ec2fd827  h_dec e8367a52  h_evt ce532fe2  h_bkg f283c927  h_nrg e30295d3
--
--    Five of six green within the pair. c3, c4 and both 24-tick columns
--    moved their canons from round 13 (0192 unparked the fleet); c4 kept
--    h_bkg and h_nrg (5a227276, 0cac7e0b) exactly. c2 is the one column
--    where the booking_id coin in the bay-activation cursor landed on
--    different faces in the two arms; 0110 is the conviction and 0195
--    the fix. Every arm of the round logged the swallowed 23505 from
--    ottoq_activate_due_bay_reservations, and the counts match in both
--    arms of every green pair and differ (4 vs 6) in the red one (0110,
--    section 5c).
--
--    Job 347 (17:15 UTC, busy_day/171717/24t) is VOID and excluded from
--    every canon: 0193 was applied at 17:22 while it ran, so its two
--    arms executed different function bodies. Its equal=false is a
--    measurement of my sequencing, not of the engine. Process rule,
--    now written down: never apply a migration while cron.job holds a
--    pair or pg_stat_activity shows an ottoq_determinism_pair backend.
--
-- 3. THE INTER-PAIR BAR, AND WHY endst NEVER MET IT. Every pair above
--    agrees with itself on endst, and no two pairs of the same column
--    have ever agreed with each other on it. The diff is now exact.
--
--    a. visit_needs.vis. The 15:20 and 19:06 arms of busy_day/171717/12t
--       (5dbc3de9, 9a82a2ff), joined on (vehicle_id, visit_key) and
--       compared on every column the vn CTE hashes: 116 of 116 rows
--       match; 1 row differs; in that row 1 atom differs; in that atom
--       1 key differs: reopened_at = 2026-09-04T15:20:00.118941 versus
--       2026-09-04T19:06:00.14789 -- the two transactions' start
--       instants. ottoq_reopen_visit_atoms stamps it with now() (Q3).
--    b. chargers.world. The reset never owned last_fault_at (45 of 45
--       flagship chargers non-null, 31 distinct values, 2026-07-23 to
--       2026-09-02) or last_heartbeat_at. The boot chargers.world hash
--       of each pair's first arm equals the PREVIOUS pair's second-arm
--       boot hash, forming a chain through the whole round-13 matrix
--       (2becc634 -> 19555b3b -> c9436794 -> 98eedf46 -> dc3e8f34 ->
--       3d7f62ad -> 2becc634 ...): each arm boots from the world the
--       arm before it left (Q4). Round 14 pair 1 booted bce038e9 in
--       arm A and bb34f348 in arm B.
--    c. bookings.vis. Differs across the two 48-tick pairs (80e01fbb vs
--       fa54dff4) and across NO 12- or 24-tick pairs (Q5): a 48-tick
--       run ends at 02:00 the next day with overnight bookings still
--       held, and ottoq_sim_release_depot (reached through the
--       natural-completion finalizer) releases them with
--       released_at = now(). Shorter runs end with nothing open.
--
--    None of a-c is read by the decide path; all three are hashed by
--    the end-state fingerprint; last_heartbeat_at is additionally the
--    liveness gate five decide-path functions read at boot. Fixed at
--    the writers, not by narrowing the fingerprint:
--    db/migrations/0194, applied only after this round finished.
--
--    What "endst never matched between pairs" was NOT: evidence of a
--    nondeterministic engine. Every engine canon of every column in
--    the round-13 matrix matches across pairs (Q2). The world the
--    engine booted from was contaminated, equally for both arms,
--    differently for each pair.
-- =====================================================================

-- Q1 -- the two 48-tick proof pairs, within and across.
WITH n AS (
  SELECT r.started_at, r.validation_notes::jsonb AS j
    FROM ottoq_sim_runs r
   WHERE r.validation_notes::jsonb->>'ticks' = '48'
     AND r.started_at BETWEEN '2026-09-04 17:40+00' AND '2026-09-04 19:00+00'
)
SELECT DISTINCT ON (j->'arm_a'->>'run')
       to_char(started_at, 'HH24:MI') AS fired,
       j->>'equal' AS equal,
       left(j->'arm_a'->>'fp', 8)    AS fp,
       left(j->'arm_a'->>'h_cmd', 8) AS h_cmd, left(j->'arm_a'->>'h_dec', 8) AS h_dec,
       left(j->'arm_a'->>'h_evt', 8) AS h_evt, left(j->'arm_a'->>'h_bkg', 8) AS h_bkg,
       left(j->'arm_a'->>'h_nrg', 8) AS h_nrg,
       left(j->'arm_a'->'endst'->'bookings'->'vis'->>'h', 8)    AS end_bk,
       left(j->'arm_a'->'endst'->'visit_needs'->'vis'->>'h', 8) AS end_vn,
       left(j->'arm_a'->'endst'->'chargers'->'world'->>'h', 8)  AS end_ch
  FROM n ORDER BY j->'arm_a'->>'run', started_at;

-- Q2 -- every flagship pair since round 13 began: engine canons and
--       endst sections, one row per pair, oldest first. Read down a
--       column: h_cmd/h_dec/h_evt/h_bkg/h_nrg repeat per
--       (scenario, seed, ticks); end_vn never does; end_bk repeats for
--       12t/24t and not for 48t; boot_ch chains.
WITH n AS (
  SELECT r.started_at, r.validation_notes::jsonb AS j
    FROM ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND r.validation_notes ~ '^\s*\{' AND r.validation_notes::jsonb ? 'arm_a'
     AND r.started_at >= '2026-09-03 13:00+00'
)
SELECT DISTINCT ON (j->'arm_a'->>'run')
       to_char(started_at, 'MM-DD HH24:MI') AS fired,
       j->>'scenario' AS scn, j->>'seed' AS seed, j->>'ticks' AS t, j->>'equal' AS eq,
       left(j->'arm_a'->>'h_cmd', 8) AS h_cmd, left(j->'arm_a'->>'h_dec', 8) AS h_dec,
       left(j->'arm_a'->>'h_evt', 8) AS h_evt, left(j->'arm_a'->>'h_bkg', 8) AS h_bkg,
       left(j->'arm_a'->>'h_nrg', 8) AS h_nrg,
       left(j->'arm_a'->'boot'->'chargers'->'world'->>'h', 8) AS boot_ch_a,
       left(j->'arm_b'->'boot'->'chargers'->'world'->>'h', 8) AS boot_ch_b,
       left(j->'arm_a'->'endst'->'bookings'->'vis'->>'h', 8)    AS end_bk,
       left(j->'arm_a'->'endst'->'visit_needs'->'vis'->>'h', 8) AS end_vn,
       left(j->'arm_a'->'endst'->'chargers'->'world'->>'h', 8)  AS end_ch
  FROM n ORDER BY j->'arm_a'->>'run', started_at;

-- Q3 -- the whole visit_needs channel between two arms of the same
--       column: rows matched, rows differing, and the keys that differ
--       at the top level and inside atoms. Expected: 116 / 1 / none /
--       reopened_at.
WITH a AS (SELECT vn.*, to_jsonb(vn) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta' AS j
             FROM ottoq_visit_needs vn WHERE vn.sim_run_id = '5dbc3de9-ce06-4f16-8d46-9b0724c7a186'),
     b AS (SELECT vn.*, to_jsonb(vn) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta' AS j
             FROM ottoq_visit_needs vn WHERE vn.sim_run_id = '9a82a2ff-0383-4de1-9151-b695620c5bd9'),
     m AS (SELECT a.vehicle_id, a.j AS ja, b.j AS jb FROM a JOIN b ON b.vehicle_id = a.vehicle_id AND b.visit_key = a.visit_key),
     top AS (SELECT k.key FROM m, jsonb_each(m.ja) k WHERE m.jb->k.key IS DISTINCT FROM k.value AND k.key <> 'atoms'),
     atom AS (SELECT ka.key, ka.value AS va, (eb.el)->ka.key AS vb
                FROM m
                JOIN LATERAL jsonb_array_elements(m.ja->'atoms') WITH ORDINALITY ea(el, ord) ON true
                JOIN LATERAL jsonb_array_elements(m.jb->'atoms') WITH ORDINALITY eb(el, ord) ON eb.ord = ea.ord
                JOIN LATERAL jsonb_each(ea.el) ka ON true
               WHERE (eb.el)->ka.key IS DISTINCT FROM ka.value)
SELECT (SELECT count(*) FROM m) AS rows_matched,
       (SELECT count(*) FROM m WHERE ja <> jb) AS rows_differing,
       (SELECT array_agg(DISTINCT key) FROM top) AS top_level_keys_differing,
       (SELECT jsonb_agg(jsonb_build_object('key', key, 'a', va, 'b', vb)) FROM atom) AS atom_keys_differing;

-- Q4 -- the charger residue the reset never owned, and the boot chain.
SELECT count(*) AS chargers,
       count(last_fault_at) AS fault_at_nonnull, count(DISTINCT last_fault_at) AS fault_at_distinct,
       min(last_fault_at) AS fault_at_min, max(last_fault_at) AS fault_at_max,
       count(DISTINCT last_heartbeat_at) AS heartbeat_distinct, max(last_heartbeat_at) AS heartbeat
  FROM ottoq_ocpp_chargers WHERE depot_id = '11111111-1111-1111-1111-111111111111';

WITH n AS (
  SELECT r.started_at, r.validation_notes::jsonb AS j
    FROM ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND r.validation_notes ~ '^\s*\{' AND r.validation_notes::jsonb ? 'arm_a'
     AND r.started_at >= '2026-09-03 13:00+00'
), p AS (
  SELECT DISTINCT ON (j->'arm_a'->>'run') started_at,
         j->'arm_a'->'boot'->'chargers'->'world'->>'h' AS boot_a,
         j->'arm_b'->'boot'->'chargers'->'world'->>'h' AS boot_b
    FROM n ORDER BY j->'arm_a'->>'run', started_at
)
SELECT count(*) AS pairs,
       count(*) FILTER (WHERE boot_a = lag(boot_b) OVER (ORDER BY started_at)) AS first_arm_boots_from_previous_pairs_second_arm
  FROM p;
-- (the window function needs a subquery to be counted; kept inline for
--  readability -- run as: SELECT count(*) FILTER (...) FROM (SELECT
--  boot_a, lag(boot_b) OVER (ORDER BY started_at) AS prev FROM p) q
--  WHERE boot_a = prev)

-- Q5 -- bookings.vis agrees across pairs exactly when the run ends with
--       nothing open: count distinct end_bk per (scenario, seed, ticks).
WITH n AS (
  SELECT r.started_at, r.validation_notes::jsonb AS j
    FROM ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND r.validation_notes ~ '^\s*\{' AND r.validation_notes::jsonb ? 'arm_a'
     AND r.started_at >= '2026-09-03 13:00+00' AND r.validation_notes::jsonb->>'equal' = 'true'
), p AS (
  SELECT DISTINCT ON (j->'arm_a'->>'run') j->>'scenario' AS scn, j->>'seed' AS seed, (j->>'ticks')::int AS t,
         j->'arm_a'->>'h_cmd' AS h_cmd,
         j->'arm_a'->'endst'->'bookings'->'vis'->>'h' AS end_bk,
         j->'arm_a'->'endst'->'visit_needs'->'vis'->>'h' AS end_vn
    FROM n ORDER BY j->'arm_a'->>'run', started_at
)
SELECT scn, seed, t, h_cmd IS NOT NULL AS has_canon, count(*) AS pairs,
       count(DISTINCT end_bk) AS distinct_end_bk, count(DISTINCT end_vn) AS distinct_end_vn
  FROM p GROUP BY scn, seed, t, h_cmd ORDER BY t, scn, seed, h_cmd;

-- Q6 -- job 347: the void pair. Both arms began before 0193 applied
--       (17:22:xx UTC); the pair's verdict is not evidence either way.
SELECT r.sim_run_id, r.started_at, r.tick_count, r.validation_notes::jsonb->>'equal' AS equal
  FROM ottoq_sim_runs r
 WHERE r.started_at BETWEEN '2026-09-04 17:14+00' AND '2026-09-04 17:16+00'
 ORDER BY r.started_at, r.sim_run_id;
