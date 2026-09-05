-- =====================================================================
-- 0111  Round 15: the bar met, and the coin that was not a coin
-- =====================================================================
-- Round 15 ran 21:02-22:43 UTC on 2026-09-04 (4:02-5:43 PM CT), seven
-- pairs on the flagship, after 0194 (20:55) and 0195 (21:00) applied.
-- Read 01:35 UTC 09-05 (the session was disconnected from 22:50).
--
-- 1. THE MATRIX
--
--   #  fired  column                 equal  h_cmd     h_dec     h_evt     h_bkg     h_nrg     vs round 14
--   1  21:02  busy_day/314159/12t    NO     cf74d080  1788ee1c  25cf62c5  eaff0912  4afd1004  IDENTICAL, both arms
--   2  21:15  busy_day/171717/12t    yes    80183641  6e116d5b  4f8b2970  b1d72a62  625014b7  identical
--   3  21:28  busy_day/171717/12t    yes    80183641  6e116d5b  4f8b2970  b1d72a62  625014b7  identical
--   4  21:41  normal_day/171717/12t  yes    af8b5e6d  3a8719f8  7872892a  2c7e0a3a  de3b353e  identical
--   5  21:54  busy_day/424242/12t    yes    adf745a2  05bc65e6  67ee1af6  84a9b51c  0cac7e0b  MOVED (was 63f1dbe1)
--   6  22:07  busy_day/171717/24t    yes    38465601  09769827  5c9a64cd  3b52ea78  7606aaf2  identical
--   7  22:28  busy_day/424242/24t    yes    997e2c37  fd484142  99b6ee3f  f597a790  f2b72ada  MOVED (was ec2fd827)
--
--   Second arm of #1: f2bd5208 -- also identical to round 14's second arm.
--
-- 2. THE BAR (0194 prediction 3): MET
--    Pairs 2 and 3 are the same column run twice, 13 minutes apart, with
--    a full pair between them and another before them. Their end-state
--    fingerprints agree on every section:
--      visit_needs.vis ed5f06fd  bookings.vis fd9378b0  legs.vis 89c1b62c
--      dispatches.vis 6cfbdb45   chargers.world 143b5bd7
--    No two pairs of any column had ever agreed on endst before 0194.
--    Q1 re-derives it from the rows.
--
-- 3. 0194 PREDICTION VERDICTS
--    1. engine canons unchanged from round 14 -- HELD for columns 2, 3, 4
--       and 6; columns 5 and 7 moved, but 0195 applied in the same window
--       and 0195 predicted movement wherever an order-sensitive tie
--       existed, so the two migrations cannot be separated on this
--       round. Recorded as CONFOUNDED, not as a failure of 0194.
--    2. boot chargers.world equal within and across pairs -- HELD for
--       eleven of fourteen arms (c83d7288). The three exceptions
--       (9c25b338: pair 1 first arm, pair 6 second arm, pair 7 both)
--       are exactly the arms whose predecessor was a 24-tick run.
--       Cause: five flagship chargers no stall points at, outside
--       0194's reset population; the world tick writes their heartbeat,
--       and a 24-tick run leaves 2026-09-02 on them. Fixed in 0196.
--    3. endst equal across the two 171717/12t pairs -- MET (section 2).
--    4/5. stamps in the sim window -- Q2 checks the round-15 rows.
--
-- 4. 0195 PREDICTION VERDICTS
--    1. busy_day/314159/12t green with a new canon -- FAILED. Red, and
--       BOTH canons identical to round 14 by arm position.
--    2. every other column green -- HELD.
--    3. fewer swallowed-23505 lines per arm than 4/6 -- FAILED: 4 and 6
--       again (log census: 33acab66 4, 9686b690 6; pairs 2/3: 7/7, 7/7;
--       pair 4: 9/9; pair 5: 9/9 first arm).
--    0195's order fix is correct -- the cursor is now total across runs,
--    and columns 5 and 7 moved under it -- but it was not this column's
--    cause. The proof that the two arms walked the batch in different
--    orders (0195 A2) stands; the inference that the order decided the
--    outcome did not survive the test it was published to face.
--
-- 5. THE COIN THAT WAS NOT A COIN (the 0196 conviction)
--    Identical canons per arm position across two rounds means the
--    divergence is a deterministic function of being the SECOND arm:
--    something the first arm leaves that the second reads, that is not
--    in any table. public.ottoq_indepot_reassignment_guard, on every
--    'outside_walls' yes, calls public.ottoq_mark_reassign_granted, which
--    appends the vehicle id to set_config('ottoq.reassign_ok', ..., true)
--    -- transaction-local. public.ottoq_trg_reassignment_guard reads it
--    first and lets a listed car vacate a mid-work bay without asking.
--    Under pg_cron the list dies with the tick; under
--    ottoq_determinism_pair both arms and every tick share one
--    transaction. The second arm starts with every grant the first arm
--    stamped, so a stall the first arm's guard kept is released in the
--    second, the bay-seating tick that threw 23505 in the first does not
--    throw in the second, and the arms fork -- the same way every time.
--    Same shape, no fork: twin.ottoq_sim_prime_deployment's
--    ottoq.skip_wash_bump = '1' stays set for every tick of both arms,
--    so no certification run has ever bumped a wash cycle (Q3 shows the
--    writer, the reader, and the absence of any reset).
--    Fix (0196, applied 01:37 UTC): the tick clears both flags first.
--
-- 6. RECORDED, NOT YET FIXED
--    a. The grant is not keyed by run (hardening; 0196 header).
--    b. ottoq_enact_space_assignment's own 23505s (0110 section 5a).
--    c. The seven 0129 leg cursors in ottoq_decide_tick (0110 5d).
--    d. Per-seat subtransactions in ottoq_activate_due_bay_reservations
--       (0110 5b).
-- =====================================================================

-- Q1 -- the inter-pair bar: the two 171717/12t pairs' endst sections.
SELECT to_char(r.started_at,'HH24:MI') AS fired,
       left(j->'arm_a'->'endst'->'visit_needs'->'vis'->>'h',8) AS visit_needs,
       left(j->'arm_a'->'endst'->'bookings'->'vis'->>'h',8)    AS bookings,
       left(j->'arm_a'->'endst'->'legs'->'vis'->>'h',8)        AS legs,
       left(j->'arm_a'->'endst'->'dispatches'->'vis'->>'h',8)  AS dispatches,
       left(j->'arm_a'->'endst'->'chargers'->'world'->>'h',8)  AS chargers,
       j->>'equal' AS equal
  FROM (SELECT DISTINCT ON (validation_notes::jsonb->'arm_a'->>'run') started_at, validation_notes::jsonb AS j
          FROM ottoq_sim_runs
         WHERE started_at BETWEEN '2026-09-04 21:00+00' AND '2026-09-04 23:00+00'
           AND validation_notes ~ '^\s*\{' AND validation_notes::jsonb ? 'arm_a'
         ORDER BY validation_notes::jsonb->'arm_a'->>'run', started_at) r
 WHERE j->>'scenario' = 'busy_day' AND j->>'seed' = '171717' AND j->>'ticks' = '12'
 ORDER BY r.started_at;

-- Q2 -- 0194 predictions 4 and 5 on round-15 rows: every reopen stamp in
--       the sim window, every run_stopped release at the run's sim end.
WITH runs AS (
  SELECT sim_run_id, sim_clock_current FROM ottoq_sim_runs
   WHERE started_at BETWEEN '2026-09-04 21:00+00' AND '2026-09-04 23:00+00' AND validation_notes ~ '^\s*\{')
SELECT 'reopen_stamps_outside_sim_window' AS check_name,
       count(*) FILTER (WHERE (a->>'reopened_at')::timestamptz NOT BETWEEN '2026-09-01 02:00+00' AND '2026-09-03 02:00+00'
                           OR (a->>'cut_short_at')::timestamptz NOT BETWEEN '2026-09-01 02:00+00' AND '2026-09-03 02:00+00') AS violations,
       count(*) AS stamps_seen
  FROM ottoq_visit_needs vn JOIN runs r ON r.sim_run_id = vn.sim_run_id, jsonb_array_elements(vn.atoms) a
 WHERE a ? 'reopened_at' OR a ? 'cut_short_at'
UNION ALL
SELECT 'run_stopped_release_not_at_sim_end',
       count(*) FILTER (WHERE b.released_at <> r.sim_clock_current), count(*)
  FROM ottoq_stall_bookings b JOIN runs r ON r.sim_run_id = b.sim_run_id
 WHERE b.release_reason = 'run_stopped';

-- Q3 -- the flag: writer, reader, and (before 0196) no reset anywhere.
SELECT n.nspname||'.'||p.proname AS fn,
       (SELECT count(*) FROM regexp_matches(pg_get_functiondef(p.oid), 'reassign_ok', 'g')) AS mentions,
       (pg_get_functiondef(p.oid) ~ 'set_config\(''ottoq\.reassign_ok'', '''', true\)') AS clears_it
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','twin','ottoq') AND p.prokind IN ('f','p')
   AND pg_get_functiondef(p.oid) LIKE '%reassign_ok%'
 ORDER BY 1;

-- Q4 -- the red pair reproduced by arm position across two rounds.
SELECT to_char(r.started_at,'MM-DD HH24:MI') AS fired, j->>'equal' AS equal,
       left(j->'arm_a'->>'h_cmd',8) AS arm_a_cmd, left(j->'arm_b'->>'h_cmd',8) AS arm_b_cmd,
       left(j->'arm_a'->>'h_dec',8) AS arm_a_dec, left(j->'arm_b'->>'h_dec',8) AS arm_b_dec
  FROM (SELECT DISTINCT ON (validation_notes::jsonb->'arm_a'->>'run') started_at, validation_notes::jsonb AS j
          FROM ottoq_sim_runs
         WHERE started_at > '2026-09-04 19:00+00' AND validation_notes ~ '^\s*\{' AND validation_notes::jsonb ? 'arm_a'
         ORDER BY validation_notes::jsonb->'arm_a'->>'run', started_at) r
 WHERE j->>'seed' = '314159' AND j->>'ticks' = '12'
 ORDER BY r.started_at;
