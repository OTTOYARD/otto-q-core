-- =====================================================================
-- 0112  Round 16: seven of seven, and the flag that moved the wrong hash
-- =====================================================================
-- Round 16 ran 01:39-03:24 UTC on 2026-09-05 (8:39-10:24 PM CT), seven
-- pairs on the flagship, after 0196 applied at 01:37 UTC. Read 03:28 UTC.
-- Every pair passed. Every arm completed. This is the first round since
-- the certification matrix was widened to six columns in which no column
-- is red.
--
-- 1. THE MATRIX
--
--   #  fired  column                 equal  h_cmd     h_dec     h_evt     h_bkg     h_nrg     vs round 15
--   1  01:39  busy_day/314159/12t    yes    cf74d080  1788ee1c  25cf62c5  eaff0912  4afd1004  GREEN (was red twice); = round-15 arm A
--   2  01:52  busy_day/171717/12t    yes    80183641  6e116d5b  4f8b2970  b1d72a62  625014b7  identical
--   3  02:05  busy_day/171717/12t    yes    80183641  6e116d5b  4f8b2970  b1d72a62  625014b7  identical (= pair 2 on every field)
--   4  02:18  normal_day/171717/12t  yes    af8b5e6d  3a8719f8  0beff613  2c7e0a3a  de3b353e  h_evt moved (was 7872892a)
--   5  02:31  busy_day/424242/12t    yes    adf745a2  05bc65e6  67ee1af6  84a9b51c  0cac7e0b  identical
--   6  02:44  busy_day/171717/24t    yes    38465601  09769827  61d5ff27  3b52ea78  7606aaf2  h_evt moved (was 5c9a64cd)
--   7  03:05  busy_day/424242/24t    yes    997e2c37  fd484142  2c51bb4c  f597a790  f2b72ada  h_evt moved (was 99b6ee3f)
--
--   Boot chargers.world: e06b403e on all fourteen arms.
--   Swallowed-23505 log lines per arm (pairs 1-7): 4/4, 7/7, 7/7, 9/9,
--   9/9, 11/11, 9/9. Equal within every pair.
--   Pair 7 followed a 24-tick pair (the round-15 case that carried
--   9c25b338) and booted e06b403e like every other arm.
--
-- 2. 0196 PREDICTION VERDICTS
--
--    1. busy_day/314159/12t green, both arms complete, canon neither
--       cf74d080 nor f2bd5208, equal 23505 counts -- MET on green, MET
--       on completion, MET on equal counts (4/4), FAILED on "neither".
--       The canon is cf74d080: round-14/15 arm A's value, unchanged.
--       That is the shape the 0196 mechanism actually implies and the
--       prediction should have said so: the reassignment grant list is
--       empty when arm A starts and leaks only forward, into arm B. Arm
--       A was never contaminated. The truth was arm A's stream all
--       along; arm B is now the one that changed. Recorded as a failed
--       clause and a corrected mechanism, not as a pass.
--    2. every column's engine canon moves (wash cycles now bump) --
--       FAILED. h_cmd is byte-identical to round 15 in every column that
--       had one (2-7), and h_dec, h_bkg, h_nrg with it. The 0196 footer
--       said a canon that does not move is evidence against the
--       skip_wash_bump half and would be said so. It is said so here.
--       What that half DID do is in section 3: it moved h_evt in three
--       columns and nothing else. "Washes reshape every schedule" was
--       an inference about downstream effect that the data does not
--       support at 12 or 24 ticks; the command stream never saw a wash
--       decision change.
--    3. boot chargers.world identical across all arms, whatever ran
--       before -- MET (fourteen of fourteen, e06b403e).
--    4. busy_day/171717/12t twins agree on every endst section -- MET,
--       and stronger: pairs 2 and 3 agree on every field of the verdict
--       (fp, boot, endst, all five hashes). Second consecutive round the
--       inter-pair bar is met on this column.
--
-- 3. WHAT MOVED BETWEEN ROUNDS 15 AND 16, AND WHY
--
--    Exactly two things moved, both attributable to 0196, both verified
--    against rows (Q3, Q4):
--
--    a. endst.chargers.world moved in every column (e.g. column 2:
--       143b5bd7 -> c8c67c5b). The four vis sections (visit_needs,
--       bookings, legs, dispatches) are byte-identical to round 15 in
--       columns 2 and 6 (Q3). Cause: 0196 gave the fleet reset ownership
--       of last_fault_at / last_heartbeat_at on the five unlinked
--       chargers; they now carry p_as_of at boot instead of whatever the
--       previous run left, and the end-state hash of the charger world
--       moves with them. Expected; this is prediction 3 seen from the
--       other end.
--
--    b. h_evt moved in columns 4, 6, 7 and nowhere else. The moved stream
--       differs from round 15 by extra vehicle.state_changed rows: +1 in
--       column 4 (2362 -> 2363), +59 in column 6 (3069 -> 3128). Q4 pins
--       the column-4 row to one vehicle (73e4a749): in round 15 its
--       cycles_since_wash 0 -> 1 rode inside the deploy UPDATE (one row
--       change: cycles_since_wash + deploy_gate + last_balance_charge_at);
--       in round 16 it is its own UPDATE (cycles_since_wash 0 -> 1 alone,
--       then deploy_gate + last_balance_charge_at without it). That
--       separate statement is public.ottoq_dispatch_bump_wash_cycle
--       firing on the dispatch insert, which the stuck skip_wash_bump
--       flag had suppressed for the whole of every certification arm
--       before 0196. Same value, one more event. Columns 1, 2, 3, 5
--       (busy_day at 12 ticks) insert no new dispatch that reaches the
--       trigger, so their h_evt did not move.
--
--       Consequence worth stating: before 0196 the certification arms
--       ran with the wash-cycle trigger silenced from boot to end, which
--       production never does (each production tick is its own
--       transaction; the flag lives only inside the boot prime). Round
--       16 is the first round whose arms match production on this
--       point. The command canons did not care. The event stream did.
--
--    Nothing else moved. h_cmd, h_dec, h_bkg, h_nrg: seven for seven
--    identical to round 15 (pair 1 to its round-15 arm A).
--
-- 4. WHERE THE DETERMINISTIC CORE STANDS (task #56, part A)
--
--    bar                                    status
--    six columns green                       met (round 16)
--    inter-pair reproducible                 met on 171717/12t, rounds 15 and 16;
--                                            not yet shown on a second column
--    every canon stable across two rounds    columns 2, 4, 6: rounds 14-16
--                                            columns 5, 7: rounds 15-16
--                                            column 1: round 16 only -- ONE round
--    h_nrg in the verdict                    yes (0148)
--
--    Column 1 has a canon for the first time and needs a second round
--    before "stable" can be said of it. Round 17 is scheduled (section
--    5) with column 1 run twice, which tests the inter-pair bar on a
--    second column and the stability of the newest canon in one round.
--
-- 5. ROUND 17, AND THE BAR IT MUST MEET (published before results)
--
--    Scheduled 03:34 UTC (jobs 372-378): 314159/12t at 03:36 and again
--    at 03:49, then 171717/12t 04:02, normal_day 04:15, 424242/12t
--    04:28, 171717/24t 04:41, 424242/24t 05:04. 24-tick pairs took 19
--    minutes this round (02:44-03:03, 03:05-03:23), so the 24-tick
--    spacing is 23 minutes, not 21.
--
--    a. seven of seven green, both arms complete.
--    b. the two 314159/12t pairs agree on every field of the verdict.
--    c. h_cmd, h_dec, h_bkg, h_nrg byte-identical to this round in every
--       column.
--    d. h_evt byte-identical to this round in every column. Section 3b
--       says the round-16 movement was the wash trigger going live; if
--       h_evt moves again with nothing applied, that explanation was
--       wrong and will be said so.
--    e. endst byte-identical to this round in every column, and boot
--       chargers.world e06b403e on all fourteen arms.
--
--    If a-e hold, the six-column matrix is green two rounds running,
--    every canon is stable across at least two rounds, and inter-pair
--    reproducibility is shown on two columns. What then remains before
--    part A closes is not another round: it is the two 0066 run-scoping
--    findings and peak_site_kw reproducibility (db/checks/0050, 0051),
--    each to be checked against what 0181-0190 already shipped.
--
-- 6. RECORDED, NOT DONE (carried from 0111, unchanged)
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
WHERE r.started_at >= '2026-09-05 01:38+00' AND r.started_at < '2026-09-05 03:25+00'
  AND r.validation_notes LIKE '{%equal%'
  AND r.sim_run_id::text LIKE (v->'arm_a'->>'run')||'%'
ORDER BY r.started_at;
-- expect seven rows, equal = true on each, e06b403e in both boot columns.

-- =====================================================================
-- Q2 -- the twins (pairs 2 and 3): every verdict field equal
-- =====================================================================
SELECT a.k, (a.v = b.v) AS equal, left(a.v,8) AS pair2, left(b.v,8) AS pair3
FROM (SELECT key AS k, value::text AS v FROM ottoq_sim_runs, jsonb_each((validation_notes::jsonb)->'arm_a')
      WHERE sim_run_id::text LIKE '9c210514%') a
JOIN (SELECT key AS k, value::text AS v FROM ottoq_sim_runs, jsonb_each((validation_notes::jsonb)->'arm_a')
      WHERE sim_run_id::text LIKE '1a515335%') b USING (k)
WHERE a.k NOT IN ('run')
ORDER BY 1;
-- expect equal = true on every row but 'run'.

-- =====================================================================
-- Q3 -- what moved in endst between rounds (column 2 and column 6):
--       only chargers.world
-- =====================================================================
WITH pairs(col, r15, r16) AS (VALUES ('busy_day/171717/12t','6d51cff8','9c210514'),
                                    ('busy_day/171717/24t','9baffe9d','b6747308'))
SELECT p.col, sec,
       left(a.v->'arm_a'->'endst'->sec->'vis'->>'h',8) AS r15_vis,
       left(b.v->'arm_a'->'endst'->sec->'vis'->>'h',8) AS r16_vis,
       (a.v->'arm_a'->'endst'->sec->'vis'->>'h') = (b.v->'arm_a'->'endst'->sec->'vis'->>'h') AS same,
       left(a.v->'arm_a'->'endst'->'chargers'->'world'->>'h',8) AS r15_chargers,
       left(b.v->'arm_a'->'endst'->'chargers'->'world'->>'h',8) AS r16_chargers
FROM pairs p
JOIN LATERAL (SELECT validation_notes::jsonb v FROM ottoq_sim_runs WHERE sim_run_id::text LIKE p.r15||'%') a ON true
JOIN LATERAL (SELECT validation_notes::jsonb v FROM ottoq_sim_runs WHERE sim_run_id::text LIKE p.r16||'%') b ON true
CROSS JOIN unnest(ARRAY['visit_needs','bookings','legs','dispatches']) AS sec
ORDER BY 1,2;
-- expect same = true on all eight rows; r15_chargers <> r16_chargers.

-- =====================================================================
-- Q4 -- the one extra event in column 4: vehicle 73e4a749, cycles_since_wash
--       0 -> 1 as its own UPDATE in round 16, inside the deploy UPDATE in
--       round 15
-- =====================================================================
SELECT CASE WHEN sim_run_id::text LIKE '4bc2f5dd%' THEN 'round15' ELSE 'round16' END AS round,
       (SELECT string_agg(k, ',' ORDER BY k)
          FROM (SELECT jsonb_object_keys(payload->'diff'->'config'->'to') k
                UNION SELECT jsonb_object_keys(payload->'diff'->'config'->'from')) ks
         WHERE payload->'diff'->'config'->'from'->k IS DISTINCT FROM payload->'diff'->'config'->'to'->k) AS changed_keys,
       count(*) AS n
FROM ottoq_events
WHERE event_type = 'vehicle.state_changed'
  AND entity_id = '73e4a749-9f4f-4586-8c73-7351786ca4a9'
  AND (sim_run_id::text LIKE '4bc2f5dd%' OR sim_run_id::text LIKE 'f75d1f7c%')
GROUP BY 1,2 ORDER BY 1,2;
-- expect: round15 has one row 'cycles_since_wash,deploy_gate,last_balance_charge_at';
--         round16 has 'cycles_since_wash' and 'deploy_gate,last_balance_charge_at' as two rows.

-- =====================================================================
-- Q5 -- the wash trigger and the flag that silenced it
-- =====================================================================
SELECT n.nspname||'.'||p.proname AS fn, m[1] AS line
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
     LATERAL regexp_matches(pg_get_functiondef(p.oid), '([^\n]*skip_wash_bump[^\n]*)', 'g') m
WHERE p.prokind IN ('f','p') AND pg_get_functiondef(p.oid) ILIKE '%skip_wash_bump%'
ORDER BY 1;
-- expect three: the trigger reads it; ottoq_sim_advance_tick clears it (0196);
-- twin.ottoq_sim_prime_deployment sets it for the boot prime only.

-- The swallowed-23505 census is a Supabase log query (ClickHouse), not SQL here:
--   select extract(event_message, 'run=([0-9a-f]{8})') as run8, count()
--   from logs where source='postgres_logs'
--     and event_message like 'ottoq_activate_due_bay_reservations: FAILED%'
--   group by run8   -- window 2026-09-05T01:38Z .. 03:25Z
-- Round 16: 05a343f1 4, 1466cf1e 4, 9c210514 7, ea333eda 7, 1a515335 7, 11dfd458 7,
--           f75d1f7c 9, 1d094b96 9, ae61e0da 9, 922431aa 9, b6747308 11, e70013d4 11,
--           fab1889a 9, a987d9d4 9.
