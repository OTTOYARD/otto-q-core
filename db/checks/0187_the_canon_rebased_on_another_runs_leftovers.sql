-- ---------------------------------------------------------------------------
-- 0187 — G46: THE CANON REBASED BECAUSE SOMEBODY ELSE'S ROWS MOVED
--
-- Round 41 (2026-09-13 01:55-04:10 UTC, ten pairs, jobids 588-597) passed 10/10
-- internally, 20/20 arms, and agrees with round 40 on THIRTEEN of fourteen atoms
-- in ALL NINE columns. One atom moved, in the six flagship columns, and it moved
-- by one number:
--
--    endst.legs.fgn.n : 13  (rounds 39, 40)  ->  9  (round 41)
--
-- 'fgn' is defined by db/migrations/0125 as "OTHER runs' leftover rows still in
-- live states (the cross-run hazard set)". So the atom that moved is a count of
-- rows that do not belong to the certification run at all.
--
-- Consequence: ottoq_cert_matrix takes the newest pair as the canon and walks
-- backwards while every atom matches. A change in a foreign row count therefore
-- (a) breaks the streak -- six flagship columns went from consecutive_passes 2
-- and green, to 1 and not green -- and (b) SILENTLY INSTALLS A NEW CANON that
-- carries the new residue count. No engine code changed between the rounds that
-- could do this: 0261 and 0262 are the only migrations in the gap and h_prop /
-- h_defr (the atoms either could move) are byte-identical.
--
-- This file is the measurement, not the fix. Run it read-only.
-- ---------------------------------------------------------------------------

-- 1. THE ATOM DIFF, ROUND OVER ROUND. Expect: exactly one column name, 'endst',
--    in the six flagship rows; empty for both grid rows and for the 48t row
--    (whose rn=2 pair is round 41's own first 48t pair).
WITH pair AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at)
         r.depot_id, r.started_at AS t0, (r.validation_notes::jsonb) AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'cert_harness'
     AND r.started_at >= public.ottoq_cert_recert_floor()
     AND r.validation_status IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb) -> 'arm_a') = 'object'
   ORDER BY r.depot_id, r.started_at, r.sim_run_id
), k AS (
  SELECT t0, (j->>'seed')::bigint AS seed, (j->>'ticks')::int AS ticks,
         j->>'scenario' AS scen,
         j->'arm_a'->>'fp' fp, j->'arm_a'->>'h_cmd' cmd, j->'arm_a'->>'h_dec' dec,
         j->'arm_a'->>'h_evt' evt, j->'arm_a'->>'h_bkg' bkg, j->'arm_a'->>'h_nrg' nrg,
         j->'arm_a'->>'h_prop' prop, j->'arm_a'->>'h_defr' defr, j->'arm_a'->>'h_cal' cal,
         j->'arm_a'->>'h_rule' rule, j->'arm_a'->>'h_rcl' rcl, j->'arm_a'->>'h_sdr' sdr,
         md5((j->'arm_a'->'endst')::text) endst
    FROM pair
), r AS (SELECT k.*, row_number() OVER (PARTITION BY seed,ticks,scen ORDER BY t0 DESC) rn FROM k)
SELECT a.scen||'/'||a.seed||'/'||a.ticks||'t' AS col,
       to_char(a.t0,'MM-DD HH24:MI') AS newest, to_char(b.t0,'MM-DD HH24:MI') AS previous,
       concat_ws(',',
         CASE WHEN a.fp  IS DISTINCT FROM b.fp  THEN 'fp'  END,
         CASE WHEN a.cmd IS DISTINCT FROM b.cmd THEN 'cmd' END,
         CASE WHEN a.dec IS DISTINCT FROM b.dec THEN 'dec' END,
         CASE WHEN a.evt IS DISTINCT FROM b.evt THEN 'evt' END,
         CASE WHEN a.bkg IS DISTINCT FROM b.bkg THEN 'bkg' END,
         CASE WHEN a.nrg IS DISTINCT FROM b.nrg THEN 'nrg' END,
         CASE WHEN a.prop IS DISTINCT FROM b.prop THEN 'prop' END,
         CASE WHEN a.defr IS DISTINCT FROM b.defr THEN 'defr' END,
         CASE WHEN a.cal IS DISTINCT FROM b.cal THEN 'cal' END,
         CASE WHEN a.rule IS DISTINCT FROM b.rule THEN 'rule' END,
         CASE WHEN a.rcl IS DISTINCT FROM b.rcl THEN 'rcl' END,
         CASE WHEN a.sdr IS DISTINCT FROM b.sdr THEN 'sdr' END,
         CASE WHEN a.endst IS DISTINCT FROM b.endst THEN 'endst' END) AS moved
  FROM r a JOIN r b ON b.seed=a.seed AND b.ticks=a.ticks AND b.scen=a.scen AND b.rn=a.rn+1
 WHERE a.rn = 1 ORDER BY 1;
-- MEASURED 2026-09-13 04:35 UTC:
--   busy_day/171717/12t    02:16 vs 21:26   endst
--   busy_day/171717/24t    02:58 vs 22:08   endst
--   busy_day/171717/48t    04:10 vs 03:38   (none)
--   busy_day/314159/12t    02:02 vs 21:12   endst
--   busy_day/424242/12t    02:44 vs 21:54   endst
--   busy_day/424242/24t    03:18 vs 22:28   endst
--   grid_smoke/239001/6t   01:55 vs 21:05   (none)
--   grid_smoke/424242/6t   01:58 vs 21:08   (none)
--   normal_day/171717/12t  02:30 vs 21:40   endst

-- 2. WHICH SECTION OF endst. Expect one row per flagship column, key 'legs'.
WITH pair AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at) r.started_at AS t0, (r.validation_notes::jsonb) AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by='cert_harness' AND r.started_at >= public.ottoq_cert_recert_floor()
     AND r.validation_status IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
   ORDER BY r.depot_id, r.started_at, r.sim_run_id
), k AS (SELECT t0, (j->>'seed')::bigint seed, (j->>'ticks')::int ticks, j->>'scenario' scen,
                j->'arm_a'->'endst' e FROM pair),
  r AS (SELECT k.*, row_number() OVER (PARTITION BY seed,ticks,scen ORDER BY t0 DESC) rn FROM k)
SELECT a.scen||'/'||a.seed||'/'||a.ticks||'t' col, x.key AS section,
       a.e->x.key AS newest, b.e->x.key AS previous
  FROM r a JOIN r b ON b.seed=a.seed AND b.ticks=a.ticks AND b.scen=a.scen AND b.rn=2
  CROSS JOIN LATERAL jsonb_object_keys(a.e) AS x(key)
 WHERE a.rn=1 AND (a.e->x.key) IS DISTINCT FROM (b.e->x.key)
 ORDER BY 1,2;
-- MEASURED: six rows, section 'legs' every time,
--   newest   {"fgn": {"h": "e2bd0e4a63dd26624def4368aff5c7ba", "n": 9},  "vis": {...}}
--   previous {"fgn": {"h": "d2ad01ee1d4004edb1c80f77545bfcb3", "n": 13}, "vis": {...}}
-- The 'vis' half (the run's OWN legs) is identical in every column. bookings.fgn,
-- visit_needs.fgn and dispatches.fgn are 0 in every pair of rounds 39, 40 and 41.

-- 3. WHOSE ROWS ARE THEY. Expect: 9 rows, one run, completed 2026-08-29.
SELECT l.sim_run_id, r.run_by, r.status AS run_status,
       to_char(r.started_at,'YYYY-MM-DD HH24:MI') AS run_started, l.status AS leg_status, count(*) AS n
  FROM public.ottoq_itinerary_legs l
  JOIN public.vehicles v ON v.id = l.vehicle_id
                        AND v.home_depot_id = '11111111-1111-1111-1111-111111111111'
  LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = l.sim_run_id
 WHERE l.status IN ('planned','active','in_progress')
 GROUP BY 1,2,3,4,5 ORDER BY n DESC;
-- MEASURED: 9291ec6d-12b2-4d44-b4f9-35d47f08e9da | operator_demo | completed
--           | 2026-08-29 03:35 | planned | 9
-- A run that COMPLETED two weeks ago still holds nine legs in a live state. Nothing
-- closes a finished run's legs (G13's janitor gap, first measurement on flagship).

-- 4. WHAT DID *NOT* LEAVE RESIDUE -- last night's own runs. Every D2/D3 run closed
--    its legs. So the four legs that vanished between round 40 and round 41 were
--    closed by a later run's supersede, not created by the demos.
SELECT r.run_by, l.sim_run_id, to_char(r.started_at,'MM-DD HH24:MI') started,
       l.status AS leg_status, count(*) n
  FROM public.ottoq_itinerary_legs l
  JOIN public.vehicles v ON v.id=l.vehicle_id
                        AND v.home_depot_id='11111111-1111-1111-1111-111111111111'
  JOIN public.ottoq_sim_runs r ON r.sim_run_id=l.sim_run_id
 WHERE r.run_by IN ('proposer_demo','ab_harness') AND r.started_at >= '2026-09-12 23:00+00'
 GROUP BY 1,2,3,4 ORDER BY 3 DESC, 4;
-- MEASURED: every row 'amended' or 'done'. ccf48af1 41 amended + 50 done;
-- af2def1b 15 amended; eight ab_harness runs 17-18 amended each. Zero live.

-- 5. THE STREAK DAMAGE, stated plainly.
SELECT depot, scenario, seed, ticks, pairs_seen, consecutive_passes, green, history
  FROM public.ottoq_cert_matrix(public.ottoq_cert_recert_floor())
 ORDER BY ticks DESC, scenario, seed;
-- MEASURED: history 'PPP' or 'PPPPPP' everywhere -- every pair above the floor passed --
-- yet consecutive_passes is 1 and green false in the six flagship 12t/24t columns,
-- because the canon moved under them. grid: 3/3 green. 48t: 2, green (both of its
-- round-41 pairs sit on the new residue count).

-- ---------------------------------------------------------------------------
-- WHAT THIS MEANS, AND WHAT IT DOES NOT MEAN
--
-- It does NOT mean the engine is nondeterministic: 20/20 arms passed, and the
-- thirteen atoms the engine computes are byte-identical across three rounds and
-- nine columns. 0261 and 0262 are acquitted (db/canons/round41.md).
--
-- It DOES mean the streak arithmetic cannot currently tell "the engine changed"
-- from "somebody else's rows changed". With demo runs on the flagship depot now
-- routine (D3), that is a gate which will cry wolf and then quietly re-baseline.
--
-- TWO CANDIDATE FIXES, neither applied here:
--
--  (a) RETIRE THE RESIDUE, THEN ASSERT IT STAYS ZERO. Close the nine stale legs
--      (scoped UPDATE: legs whose run is not running, depot-scoped, status ->
--      the terminal value the supersede path already uses), then have the pair
--      report a non-zero foreign residue as 'inconclusive' rather than passing.
--      ottoq_cert_matrix already excludes inconclusive pairs from the canon and
--      counts them separately, so the plumbing exists. Cost: one migration and
--      a one-time recert (the boot fingerprint will move once).
--
--  (b) SPLIT THE ATOM. Keep fgn for arm-vs-arm equality inside the pair, where
--      it is correct and cheap, and judge the CANON on the run's own sections,
--      reporting fgn beside the verdict. Cheaper, no recert -- but it creates a
--      reported-not-judged signal, which is exactly the trap G25 (db/checks/0225)
--      was opened for. If this is chosen, the report must be loud: a non-zero
--      fgn has to appear in the round's judging output, not only in the jsonb.
--
-- Either way: a foreign-residue change must never be able to silently rebase a
-- canon. Round 42 is not scheduled until this is decided.
-- ---------------------------------------------------------------------------
