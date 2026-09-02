-- 0078  Round 8: six columns, one pair each, all passed. Read 5:21 PM CT, 2026-09-02.
--
-- The first full re-certification since the five forces_recert migrations
-- applied today (0155 twin meter, 0156 power-aware proposer, 0159 downgrade
-- policy, 0162/0163 declared faults). Before this round, everything built
-- today was proven on the 20-second grid fixture and on one flagship column.
--
--
-- §1  The round
-- --------------
-- Flagship depot 11111111, pinned sim start 2026-09-01 02:00 UTC, proposer
-- quiesced by 0152. Ten arms, five pairs, plus the two pairs already read in
-- 0077 §2.
--
--   seq        column                       outcome  equal  canons (cmd/dec/bkg/nrg)
--   1748/1749  busy_day   171717  12t       passed   true   04177a2a 5328154a 0bf42b3c 8dcf8918
--   1751/1752  busy_day   171717  12t       passed   true   04177a2a 5328154a 0bf42b3c 8dcf8918
--   1753/1754  busy_day   314159  12t       passed   true   773fd6dc ad492891 4274369c 2b271f2f
--   1755/1756  busy_day   424242  12t       passed   true   16aabc27 bb7105f3 5a227276 0cac7e0b
--   1757/1758  normal_day 171717  12t       passed   true   78ece09b c36a99c1 2838c66c 5512b237
--   1759/1760  busy_day   171717  24t       passed   true   ec5c38aa 8221f656 096b099e da9c269c
--   1761/1762  busy_day   424242  24t       passed   true   ac1dc757 b7cbd48c 37ed2670 c5ef0ab3
--
-- Every pair: all four canons equal between arms, end-state fingerprint equal.
-- No arm inconclusive, no deviation to convict.
--
-- ottoq_cert_matrix at the recert floor:
--
--   column                      pairs  passes  green
--   busy_day   171717  12t        2      2     TRUE
--   busy_day   171717  24t        1      1     false
--   busy_day   314159  12t        1      1     false
--   busy_day   424242  12t        1      1     false
--   busy_day   424242  24t        1      1     false
--   normal_day 171717  12t        1      1     false
--
-- SIX of six columns have a passing pair at the new floor. ONE is green.
-- Green requires two consecutive passes, which is the point: round 7's lesson
-- was that a single passing pair is not evidence of a stable canon, only of a
-- self-consistent one. Pass 2 fired 5:25/5:37/5:49/6:01/6:19 PM CT as
-- s8a..s8e, same arguments.
--
--
-- §2  What can and cannot be said about the canons
-- -------------------------------------------------
-- Only ONE column has a recorded pre-fix canon to compare against: 0075 §4
-- captured busy_day/171717/12t at round 7 as 04177a2a / 1c9ace35 / 0bf42b3c /
-- e6425186. Against that, h_cmd and h_bkg held and h_dec and h_nrg moved -
-- exactly the shape 0156 (new rationale keys) and 0155 (the meter) predict,
-- and the reading in 0077 §2.
--
-- For the other five columns there is NO recorded round-7 canon in the repo.
-- Their round-8 values are therefore a NEW BASELINE, not a comparison. It
-- would have been easy to look at five passing rows and say "no carrier was
-- introduced today"; that claim is not available from this evidence for five
-- of the six columns, and is not made. What IS established for them: within
-- each pair, two independent arms produced byte-identical command, decision,
-- booking and energy streams and an identical end state.
--
-- Gap worth closing: the matrix carries canon history, but the repo records a
-- pre-fix canon for one column only. Every round should commit all six, or
-- the next engine change will be un-diffable on five of them for the same
-- reason.
--
--
-- §3  Two instrument notes
-- -------------------------
--  a. Pair overlap. ottoq_determinism_pair runs BOTH ARMS IN ONE TRANSACTION,
--     so no run rows are visible until it commits - r8a sat 279s with no rows
--     and no wait event, which reads like a hang and is not one. The original
--     8/14-minute slots left ~2 minutes of margin against a ~6.7-minute pair;
--     they were widened to 12/18 before r8b could fire. Verified afterwards:
--     r8a committed before r8b started, and pg_stat_activity never showed two
--     pairs at once. Two overlapping pairs on one depot would have produced a
--     contaminated round that still LOOKED like a round.
--
--     Live check while a pair is open:
--       SELECT count(*), max(EXTRACT(epoch FROM now()-query_start))
--         FROM pg_stat_activity
--        WHERE state='active' AND query LIKE 'SET statement_timeout%';
--     Do NOT match on '%determinism_pair%' - that pattern matches the probing
--     query's own text and reports one pair too many. It did, and was caught
--     only because the count was one higher than the schedule allowed.
--
--  b. A same-statement count reads the pre-statement snapshot. The five
--     cron.unschedule calls all returned true while a subquery in the SAME
--     statement still counted 5 jobs. Nothing was wrong; the subquery saw the
--     snapshot taken at statement start. Confirm a delete in a SEPARATE
--     statement or the confirmation is worthless.
--
--
-- §4  Still open
-- ---------------
--  a. Pass 2 (s8a..s8e) must land before five of six columns are green.
--  b. db/migrations/0168 is committed and merged as a FILE but deliberately
--     NOT applied. Applying it adds a migration and moves ottoq_engine_hash(),
--     which 0167 stamps onto every archived run; doing that between pass 1 and
--     pass 2 would split one round across two engines. It goes in after pass 2.
--  c. 0076 §13 - the three per-tick work caps in ottoq_decide_tick bind
--     silently. The open question there (does the LIMIT 20 seating cap
--     actually bind on these runs?) is now answerable against ten fresh arms.
--  d. Task #47 unchanged. normal_day/171717/12t now has one passing pair at
--     the floor; the proposed bar of 8 consecutive corrected passes is not met
--     and is still not closed unilaterally.
--
--
-- §5  Queries
-- ------------

-- 5.1 every pair verdict this round
WITH v AS (SELECT sim_run_seq, random_seed, scenario_code, tick_count, validation_notes::jsonb AS n
             FROM ottoq_sim_runs WHERE sim_run_seq > 1752 AND validation_notes LIKE '%outcome%')
SELECT sim_run_seq, random_seed AS seed, scenario_code AS scenario, tick_count AS ticks,
       n->>'outcome' AS outcome, n->>'equal' AS equal,
       left(n->'arm_a'->>'h_cmd',8) AS cmd, (n->'arm_a'->>'h_cmd')=(n->'arm_b'->>'h_cmd') AS cmd_eq,
       left(n->'arm_a'->>'h_dec',8) AS dec, (n->'arm_a'->>'h_dec')=(n->'arm_b'->>'h_dec') AS dec_eq,
       left(n->'arm_a'->>'h_bkg',8) AS bkg, (n->'arm_a'->>'h_bkg')=(n->'arm_b'->>'h_bkg') AS bkg_eq,
       left(n->'arm_a'->>'h_nrg',8) AS nrg, (n->'arm_a'->>'h_nrg')=(n->'arm_b'->>'h_nrg') AS nrg_eq,
       (n->'arm_a'->>'endst')=(n->'arm_b'->>'endst') AS endst_eq
  FROM v ORDER BY sim_run_seq;

-- 5.2 the matrix at the floor
SELECT left(depot::text,8) AS depot, seed, ticks, scenario, pairs_seen, consecutive_passes, green,
       left(canon_cmd,8) AS cmd, left(canon_dec,8) AS dec, left(canon_bkg,8) AS bkg, left(canon_nrg,8) AS nrg,
       to_char(last_pair_at AT TIME ZONE 'America/Chicago','HH12:MI AM') AS last_ct
  FROM public.ottoq_cert_matrix(public.ottoq_cert_recert_floor())
 ORDER BY scenario, seed, ticks;

-- 5.3 does the LIMIT 20 seating cap bind? See §6 - answered, cap is not the
--     culprit. This is the query that answered it. (An earlier version of this
--     query in the first commit of 0078 was WRONG: it read vehicles.current_state
--     at query time, which is the END state of the last run to touch the fleet,
--     not a per-tick count. It would have "answered" the question with a number
--     that had nothing to do with any tick.)
WITH runs AS (SELECT sim_run_id, sim_run_seq, tick_count
                FROM ottoq_sim_runs WHERE sim_run_seq IN (1753,1757,1759,1761)),
b AS (SELECT r.sim_run_seq, b.booked_at_sim, count(DISTINCT b.vehicle_id) AS veh
        FROM ottoq_stall_bookings b JOIN runs r USING (sim_run_id)
       WHERE b.booked_by='otto_q_enacted'
         AND b.source IN ('deterministic','greedy_constrained','needs_card','charge_disposition')
       GROUP BY 1,2)
SELECT sim_run_seq, count(*) AS ticks_with_seatings,
       max(veh) AS max_vehicles_seated_one_tick, round(avg(veh),1) AS avg_per_tick,
       count(*) FILTER (WHERE veh >= 20) AS ticks_at_cap
  FROM b GROUP BY 1 ORDER BY 1;


-- §6  ANSWERED: the LIMIT 20 seating cap is not what strands assets
-- ------------------------------------------------------------------
-- 0076 §13 named the three per-tick work caps in ottoq_decide_tick and left
-- one question open: does the LIMIT 20 on the seating loop actually bind on
-- these runs? Measured against four fresh round-8 arms:
--
--   seq   ticks with seatings   max vehicles seated in one tick   avg/tick
--   1753          12                        21                      9.7
--   1757          12                        19                     10.3
--   1759          17                        21                      8.4
--   1761          15                        17                      8.1
--
-- The loop runs at roughly HALF its budget. The cap is slack on almost every
-- tick, so it is not the primary cause of an asset never being served. The
-- stranding in 0077 §5 (3 unserved, 8 stranded) has another cause, and looking
-- for it in the caps would have been wasted work.
--
-- Note the 21 - a single LIMIT 20 loop cannot seat 21 distinct vehicles in one
-- tick, so the source filter above is over-inclusive and admits bookings from
-- at least one other writer. Which means the "2 ticks at cap" figure is NOT
-- evidence the cap bound; it is evidence the attribution is imprecise. The
-- conclusion that survives is the one the averages carry: ~8-10 of 20.
--
-- THREE QUERIES WERE NEEDED TO GET HERE, AND THE FIRST TWO WERE WRONG:
--   1. bookings per tick - 117-132 per tick, far over 20. Invalid: one seated
--      vehicle books several legs.
--   2. DISTINCT vehicles per tick, all sources - 67-75. Invalid: several loops
--      write bookings and the count mixes them.
--   3. DISTINCT vehicles per tick filtered by booked_by/source - the numbers
--      above, and still not clean enough to call the 21.
--
-- That is exactly the instrument gap 0076 §13 describes. A booking does not
-- record which loop seated it and a tick does not record that it was
-- oversubscribed, so answering a simple question about the engine's own
-- throughput took three attempts and ended in a qualified answer. Recording
-- oversubscription is worth building for that reason alone, independent of
-- whether the cap ever binds - it is the difference between measuring the
-- engine and inferring it.
