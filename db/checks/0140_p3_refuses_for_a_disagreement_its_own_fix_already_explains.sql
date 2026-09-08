-- ---------------------------------------------------------------------------
-- RESOLVED 2026-09-08 15:40 UTC — 0225's P3 was rewritten on this file's
-- findings, before 0225 was ever applied. The title below is kept in the past
-- tense it was written in, because the measurement is what it is and the file
-- is the record of it. What changed: P3 now asks whether any column green
-- under nine atoms stops being green under fourteen, keyed exactly as
-- ottoq_cert_matrix keys, computed once and read twice, with an A5 that
-- reports streak movement that does not cost green. The replacement has NOT
-- yet been dry-run; that is the remaining blocker on the apply window.
-- ---------------------------------------------------------------------------
-- 0140 — 0225 WILL REFUSE TO APPLY, and the refusal is half right.
--
--        Dry-run of 0225's P3 against the recert floor that 0226 installs
--        (2026-09-07 21:36:53) — the combination the apply window actually
--        creates, and one that has never been evaluated because 0226 is not
--        applied yet. **Two of the seven columns trip it.** One is a fixture
--        that the certification does not judge and P3 should never have been
--        looking at. The other is a real disagreement with a complete
--        explanation, on a flagship column, that P3 reports as if it were
--        unexplained.
--
--        This is the apply-window reasoning working exactly as written. The
--        runbook says 0226 goes first "deliberately: a lower floor makes
--        0225's P3 a much harder test." The test is harder and it fails.
--
-- Measured 2026-09-08 15:28-15:30 UTC, between round 27 columns e and f, no
-- pair in flight. Read-only.
-- ---------------------------------------------------------------------------

-- Q1. P3, DRY-RUN AT THE FLOOR 0226 INSTALLS.
--
--     RESULT — `would_refuse` on two rows:
--
--       scenario    seed    ticks  pairs  d_rule d_rcl d_sdr d_endst refuse
--       ----------- ------- -----  -----  ------ ----- ----- ------- ------
--       busy_day    171717    24      3      1     1     1      1     no
--       busy_day    424242    24      2      1     1     1      1     no
--       busy_day    171717    12      3      1     1     1      1     no
--       busy_day    314159    12      6      1     1   **2**    1   **YES**
--       busy_day    424242    12      3      1     1     1      1     no
--       normal_day  171717    12      3      1     1     1      1     no
--       grid_smoke  424242     6      4    **2** **2**   0    **2**  **YES**
--
--     P3 raises on the first row it finds, so the migration stops. Neither
--     column is one 0225 is trying to protect, and the two failures are
--     unrelated to each other.
SELECT scen, seed, ticks, n_pairs, d_rule, d_rcl, d_sdr, d_endst,
       (d_rule>1 OR d_rcl>1 OR d_sdr>1 OR d_endst>1) AS would_refuse
  FROM (
    SELECT j->>'scenario' AS scen, j->>'seed' AS seed, j->>'ticks' AS ticks,
           count(*)                                         AS n_pairs,
           count(DISTINCT j->'arm_a'->>'h_rule')            AS d_rule,
           count(DISTINCT j->'arm_a'->>'h_rcl')             AS d_rcl,
           count(DISTINCT j->'arm_a'->>'h_sdr')             AS d_sdr,
           count(DISTINCT md5((j->'arm_a'->'endst')::text)) AS d_endst
      FROM (SELECT DISTINCT r.started_at, r.depot_id, r.validation_notes::jsonb AS j
              FROM public.ottoq_sim_runs r
             WHERE r.run_by='cert_harness'
               AND r.started_at >= '2026-09-07 21:36:53+00'::timestamptz
               AND r.validation_status='passed'
               AND r.validation_notes IS NOT NULL
               AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object') p
     GROUP BY 1,2,3) x
 ORDER BY ticks::int DESC, scen, seed;

-- Q2. FAILURE ONE: `grid_smoke/424242/6t` — P3 IS LOOKING WHERE IT SHOULD NOT.
--
--     `grid_smoke` is the tiny 6-tick fixture from 0153, built so a pair runs
--     in seconds. It is not one of the six certification columns, it has never
--     been one, and `ottoq_cert_matrix` keys it as its own row where its
--     variation harms nothing.
--
--     Its `d_sdr = 0` is the tell. A count of DISTINCT over all-NULL is zero,
--     not one — every grid_smoke pair predates h_sdr entirely. So P3 is
--     refusing on a scenario whose atoms are half not-yet-invented.
--
--     THE UNDERLYING DEFECT IS STRUCTURAL, not specific to grid_smoke: P3
--     groups by `(scenario, seed, ticks)` while the matrix keys by
--     `(depot, seed, ticks, scenario)`. The inner query selects `r.depot_id`
--     and then drops it at `GROUP BY 1,2,3`. Two depots running the same
--     scenario/seed/ticks with legitimately different atoms would be collapsed
--     into one row and P3 would refuse for a disagreement the matrix does not
--     recognise as one. That is inert today only because 0138 established the
--     Benchmark depot has zero runs — so a second lane would activate it.
--
--     P3 must key exactly as the matrix keys, and should judge only the
--     columns the matrix judges.

-- Q3. FAILURE TWO: `busy_day/314159/12t` — A REAL DISAGREEMENT, FULLY EXPLAINED.
--
--     Six pairs above the proposed floor, and the h_sdr column tells a story:
--
--       fired (UTC)     status   h_sdr arm_a   h_sdr arm_b
--       --------------  -------  ------------  ------------
--       09-08 07:29:00  passed   NULL          NULL
--       09-08 07:49:00  passed   NULL          NULL
--       09-08 08:25:00  passed   **0df9a909**  **65ec044e**   <- ARMS DISAGREE
--       09-08 10:52:00  passed   a1f79c20      a1f79c20
--       09-08 11:35:00  passed   a1f79c20      a1f79c20
--       09-08 13:55:00  passed   a1f79c20      a1f79c20
--
--     A pair whose two arms produced DIFFERENT SDR hashes, and it PASSED.
--     Read cold that is alarming. It is not, and the reason is dated:
--
--       * 0219 moved h_sdr **from measured to enforced** — its own P2 refuses
--         if `h_sdr is already enforced`. Before 0219, a disagreement on h_sdr
--         could not fail a pair, by construction. That is the blind-spot
--         promotion doctrine (0139/0206/0217): measure first, enforce after a
--         flagship round shows the arms agree.
--       * **0218 was applied 2026-09-08 08:43:04 UTC** — its own body carries
--         that timestamp as a filter bound. 0218 is
--         `h_sdr hashed a signature computed over a run-scoped id`: the exact
--         defect that would make two arms of one pair hash differently.
--       * The 08:25:00 pair fired **eighteen minutes before 0218 landed**.
--
--     So the sequence is coherent and, read forwards, is the doctrine
--     succeeding: h_sdr was measured, the measurement exposed an arm-unstable
--     hash, 0218 fixed the cause, 0219 then enforced the atom, and every pair
--     since agrees. **The 08:25 disagreement is not a hole in enforcement; it
--     is the evidence that motivated the fix.**
--
--     Recorded because the opposite conclusion was available and would have
--     been wrong: "an enforced atom disagreed and the pair passed" is a
--     five-alarm sentence, and it is not what happened.
SELECT DISTINCT to_char(r.started_at,'MM-DD HH24:MI:SS') AS fired,
       r.validation_status AS st,
       left((r.validation_notes::jsonb)->'arm_a'->>'h_sdr',8) AS h_sdr_a,
       left((r.validation_notes::jsonb)->'arm_b'->>'h_sdr',8) AS h_sdr_b,
       left((r.validation_notes::jsonb)->'arm_a'->>'fp',8)    AS fp
  FROM public.ottoq_sim_runs r
 WHERE r.run_by='cert_harness'
   AND r.started_at >= '2026-09-07 21:36:53+00'::timestamptz
   AND r.validation_status='passed'
   AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
   AND (r.validation_notes::jsonb)->>'scenario'='busy_day'
   AND (r.validation_notes::jsonb)->>'seed'='314159'
   AND (r.validation_notes::jsonb)->>'ticks'='12'
 ORDER BY 1;

-- Q4. AND P3 IS STRICTER THAN ITS OWN STATED PURPOSE.
--
--     P3's error message says: "Applying now would break their streaks and the
--     change would be blamed."
--
--     Trace what would actually happen to `busy_day/314159/12t` if 0225 landed
--     with the 08:25 pair in the window. The matrix's streak is
--     `bool_and(on_canon) OVER (... ORDER BY rn ROWS UNBOUNDED PRECEDING)`
--     where rn=1 is the NEWEST pair. Counting back from 13:55:
--
--       rn=1  13:55  a1f79c20 = canon        -> on canon
--       rn=2  11:35  a1f79c20 = canon        -> on canon
--       rn=3  10:52  a1f79c20 = canon        -> on canon
--       rn=4  08:25  0df9a909 <> canon       -> BREAKS
--       rn=5  07:49  NULL, tolerated (0199 form)
--       rn=6  07:29  NULL, tolerated
--
--     `consecutive_passes` would go from 6 to **3**. `green` requires >= 2.
--     **The column stays green.** The streak shortens; it does not break in
--     the sense the message claims, and nothing regresses.
--
--     So P3's bar — "no disagreement anywhere in the window" — is stricter
--     than the property it exists to protect, which is "no column loses
--     green". It refuses a change that would cost three streak rows on one
--     column, for a disagreement that predates its own fix by eighteen
--     minutes and cannot recur.

-- ---------------------------------------------------------------------------
-- WHAT THIS CHANGES, AND WHAT IT DOES NOT
--
-- 0225 MUST BE REVISED BEFORE THE APPLY WINDOW. Three defects in P3, in
-- descending order of seriousness:
--
--   1. **P3 does not key as the matrix keys.** It groups by
--      (scenario, seed, ticks) and drops depot_id, which it selects and then
--      discards. The matrix keys by (depot, seed, ticks, scenario). Inert
--      today only because there is one depot with runs; a second lane
--      activates it. FIX: group by depot too.
--   2. **P3 judges scenarios the matrix does not certify.** grid_smoke is a
--      fixture. FIX: restrict to the certification columns, or accept that a
--      fixture's variation is not a reason to refuse.
--   3. **P3's bar is stricter than its purpose.** It refuses on any
--      disagreement rather than on a disagreement that would drop a column
--      below green. FIX: either test the property it names, or keep the strict
--      bar and say so honestly in the message — but not claim a streak break
--      that would not happen.
--
-- WHAT IS *NOT* WRONG, and must not be "fixed":
--   * The 08:25 h_sdr disagreement. It is correct history: the measured phase
--     doing its job before 0218 and 0219. Nothing about it should be edited,
--     purged, or floored away to make P3 pass. A migration that becomes
--     applicable by hiding evidence is worse than one that refuses.
--   * P3 existing at all. It caught something real on its first hard test.
--     0134's caution was right to be enforced rather than remembered.
--
-- NOT ESTABLISHED:
--   * ~~Whether 0219's enforcement decision explicitly considered the 08:25
--     pair.~~ **ESTABLISHED 15:40 UTC, and the answer is emphatic.** 0219's
--     header names that pair, by both hashes, under its own heading:
--
--         "WHY THE 314159/12t COLUMN NEEDS A SECOND PAIR. Round 25's first
--          pair ran at 08:25, BEFORE 0218, so the h_sdr stored in its verdict
--          is the contaminated one (0df9a909 / 65ec044e). Recomputing
--          ottoq_hash_sdrs over those two arms today gives aad2d1be on both,
--          but the stored verdict is a point-in-time record and P1 reads what
--          was stored, not what recomputes. That column must be re-run after
--          0218 before this file can apply."
--
--     So 0219 did not merely avoid the pair — it identified it, proved the
--     disagreement was in the stored record rather than in the SDRs (both arms
--     recompute to `aad2d1be`), and made re-running that column a precondition
--     of its own application. **The 08:25 pair was fully diagnosed and closed
--     four hours before P3 refused on it.** P3 was refusing on a settled
--     matter, which sharpens rather than softens the case for the rewrite.
--   * ~~Whether the same three P3 defects exist in any other drafted
--     migration's preconditions.~~ **SWEPT 15:36 UTC, and it is clean.** Every
--     other precondition and assertion in 0226, 0227 and 0228 is a catalog-shape
--     check — an md5 pin, a regex occurrence count, an EXPLAIN plan shape — not
--     a judgement over a data window, so the mis-keying class cannot arise.
--     The one exception is **0226 A4**, which does read `ottoq_cert_matrix`:
--     it is correctly scoped to the flagship depot
--     (`depot='11111111-...'`), asserts a positive outcome (at least two
--     columns stop being stale) rather than an absence, and so has neither the
--     dropped-key nor the stricter-than-purpose fault. 0225's P3 was the only
--     one.
-- ---------------------------------------------------------------------------
