-- ---------------------------------------------------------------------------
-- 0139 — G21b, convicted without the instrumented pair. The three busiest
--        indexes in this database — by a factor of thirteen over the fourth —
--        are the probes of one 793-character function, and 99.33% of the
--        busiest one's probes return nothing.
--
--        `ottoq_policy_get(run, key, default)` is a STABLE plpgsql function
--        that resolves a parameter through three tiers: run, then depot, then
--        global. It is called **2,416,924 times per certification pair**
--        (`scratchpad/g27_fn_before.txt`, r25_g) for 105.9 s. 0130 Q7 recorded
--        that and deliberately stopped, on the grounds that the next step was
--        an instrumented pair rather than a hypothesis. It turns out the
--        catalog's own lifetime counters settle it, and they settle it more
--        precisely than a single pair could.
--
-- Measured 2026-09-08 15:19-15:23 UTC, no pair in flight (`pg_stat_activity` empty
-- of non-idle backends), between round 27 columns e and f. Read-only.
-- `pg_stat_database.stats_reset` is NULL, so every counter below is lifetime.
-- ---------------------------------------------------------------------------

-- Q1. THE HEADLINE. Rank every index in the database by scan count.
--
--     RESULT — the top three, and then the cliff:
--
--       relname             index                            idx_scan  tup/scan
--       ------------------- ------------------------------ ----------  --------
--       ottoq_policy_params ottoq_policy_params_pkey       4,410,253,521  0.0067
--       ottoq_sim_runs      ottoq_sim_runs_pkey            1,534,228,825  1.6654
--       ottoq_sim_runs      ottoq_one_running_run_per_depot  817,677,890 19.1453
--       ------------------------------------------------- CLIFF -------------
--       vehicles            vehicles_pkey                    117,013,814 14.6007
--       ottoq_stall_bookings ..._live_stall_idx               89,813,947 32.0252
--       stalls              stalls_pkey                       76,857,973 12.2030
--
--     The first two are `ottoq_policy_get`'s own probes (Q2 proves it). The
--     third is `ottoq_depot_running_run`'s — that is G21, the load meter,
--     already convicted in 0130 and half-fixed by 0223. So the three busiest
--     indexes in this database are two functions asking the same two questions
--     over and over, and the fourth-place index is **13x** behind the third.
--
--     6,762,160,241 of the 7,631,027,889 index scans this database has ever
--     done are those three lines: **88.61%**, exact, not an estimate.
SELECT relname, indexrelname, idx_scan, idx_tup_read,
       round(idx_tup_read::numeric / NULLIF(idx_scan,0), 4) AS tuples_per_scan
  FROM pg_stat_user_indexes
 ORDER BY idx_scan DESC
 LIMIT 8;

-- Q2. THE ARITHMETIC THAT NAMES THE CALLER, AND IT CLOSES TO 4%.
--
--     The function body is four lookups in the worst case:
--
--       1. ottoq_policy_params  WHERE scope_type='run'    AND scope_id=p_sim_run_id
--       2. ottoq_sim_runs       WHERE sim_run_id=p_sim_run_id     -- to get the depot
--       3. ottoq_policy_params  WHERE scope_type='depot'  AND scope_id=v_depot
--       4. ottoq_policy_params  WHERE scope_type='global' AND scope_id=<zero uuid>
--
--     Steps 1, 3 and 4 hit `ottoq_policy_params_pkey`; step 2 hits
--     `ottoq_sim_runs_pkey`. If the modal call misses at the run tier AND at
--     the depot tier and is answered by the global tier, the ratio of the two
--     counters is exactly 3.0.
--
--     OBSERVED: 4,410,253,521 / 1,534,228,825 = **2.875**.
--
--     Within 4% of 3. The residual is in the right direction and has an
--     obvious cause: the calls that DO hit at the run tier return at step 1
--     having probed params once and sim_runs not at all, which pulls the ratio
--     below 3. So the modal path is confirmed: **three params probes and one
--     sim_runs probe per call, two of the three params probes finding
--     nothing.** That is what a 0.0067 tuples-per-scan average on a 2,131-row
--     table means, stated as a mechanism instead of as a ratio.
--
--     CROSS-CHECK FROM THE OTHER SIDE, and it is the one that makes this a
--     conviction rather than an inference. 2,416,924 calls per pair (r25_g,
--     12 ticks) x ~600 pairs of database history = ~1.45e9 calls. The
--     sim_runs_pkey counter says 1.53e9 scans. Those are the same number.
--     So essentially every one of the 1.53 BILLION primary-key probes of
--     `ottoq_sim_runs` this database has ever performed is `ottoq_policy_get`
--     asking which depot a run belongs to — a value that is immutable for the
--     life of the run.
SELECT (SELECT idx_scan FROM pg_stat_user_indexes
         WHERE indexrelname='ottoq_policy_params_pkey')      AS params_probes,
       (SELECT idx_scan FROM pg_stat_user_indexes
         WHERE indexrelname='ottoq_sim_runs_pkey')           AS sim_runs_probes,
       round((SELECT idx_scan FROM pg_stat_user_indexes
               WHERE indexrelname='ottoq_policy_params_pkey')::numeric
           / (SELECT idx_scan FROM pg_stat_user_indexes
               WHERE indexrelname='ottoq_sim_runs_pkey'), 3) AS ratio,
       3.0                                                   AS predicted_if_global_tier_answers;

-- Q3. WHY THE MISSES ARE STRUCTURAL AND NOT A DATA ACCIDENT.
--
--     RESULT:
--       scope_type   rows   distinct scopes   distinct keys
--       ----------   ----   ---------------   -------------
--       run          2045               733              23
--       depot          40                 3              19
--       global         46                 1              46
--
--     Read that as: the global tier is the only tier that carries all 46 keys.
--     The depot tier carries 19 of them, for 3 depots. The run tier carries
--     2,045/733 = **2.8 keys for the average run**.
--
--     So for a run asking about any of the ~43 keys it has no run-scoped
--     override for — which is almost every key, almost every time — the answer
--     is at the global tier, and getting there costs a miss at the run tier, a
--     probe of ottoq_sim_runs, and a miss at the depot tier. The 99.33% miss
--     rate is not a pathology in the data. It is what a three-tier fallback
--     does when the population lives in the bottom tier, and it would look
--     like this on a correctly-populated table too.
SELECT scope_type, count(*) AS rows, count(DISTINCT scope_id) AS scopes,
       count(DISTINCT param_key) AS keys
  FROM public.ottoq_policy_params
 GROUP BY 1
 ORDER BY 1;

-- Q4. THE READ:WRITE RATIO, AND THE TRAP UNDERNEATH IT.
--
--     RESULT: 3,102 inserts, 16,948 updates, 32 deletes, 2,131 live rows,
--     against 4,410,253,521 index scans. **Roughly 220,000 reads per write.**
--
--     That ratio is the whole argument for memoizing, and it is exactly the
--     argument that would have been wrong. Q5 says why.
SELECT n_tup_ins, n_tup_upd, n_tup_del, n_live_tup, seq_scan, idx_scan,
       round(idx_scan::numeric / NULLIF(n_tup_ins+n_tup_upd+n_tup_del,0)) AS reads_per_write
  FROM pg_stat_user_tables
 WHERE relname='ottoq_policy_params';

-- Q5. THE TRAP: THE TABLE IS WRITTEN **DURING** A RUN, BY THE MPC.
--
--     Seven functions write `ottoq_policy_params`. Five write it at boot or
--     setup time and would be harmless. Two do not:
--
--       public.ottoq_mpc_lookahead          INSERT + DELETE
--       public.ottoq_mpc_energy_lookahead   INSERT + DELETE
--
--     The MPC lookahead bridge writes AND DELETES policy parameters inside a
--     running tick. So the obvious fix — memoize (run, key) for the life of
--     the run, which the 220,000:1 read:write ratio invites — is **unsafe**,
--     and unsafe in the worst way: it would be correct on every scenario that
--     does not engage the MPC and silently stale on the ones that do. Note
--     that `energy_mpc_follow` is itself a policy parameter, so a stale cache
--     could hold the switch that decides whether the thing writing the cache
--     runs at all.
--
--     This is recorded BEFORE any fix is drafted, deliberately. It is the
--     precondition a fix has to satisfy, and it is the reason this file exists
--     rather than a migration.
SELECT n.nspname||'.'||p.proname AS fn,
       (p.prosrc ~* 'INSERT INTO[[:space:]]+(public\.)?ottoq_policy_params') AS does_insert,
       (p.prosrc ~* 'DELETE FROM[[:space:]]+(public\.)?ottoq_policy_params') AS does_delete
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','twin','ottoq')
   AND (p.prosrc ~* 'INSERT INTO[[:space:]]+(public\.)?ottoq_policy_params'
     OR p.prosrc ~* 'DELETE FROM[[:space:]]+(public\.)?ottoq_policy_params')
 ORDER BY 1;

-- Q6. WHERE THE CALLS COME FROM — STATIC CENSUS, AND ITS LIMIT.
--
--     RESULT: **64 functions** across public/twin/ottoq mention
--     `ottoq_policy_get`, **179 times** statically. 2,416,924 calls a pair over
--     179 static sites is ~13,500 calls per site — so the count is not spread,
--     it is a handful of sites inside per-vehicle or per-stall loops.
--
--     The static census CANNOT name them. `ottoq_recall_naive_threshold_v1`
--     leads on mentions (16) and has no loop at all; `ottoq_decide_tick` has 9
--     mentions and both a loop and a FOR-SELECT. Mentions are not calls.
--
--     THIS IS THE QUESTION r27_g ANSWERS. Its `pg_stat_user_functions` diff
--     (baseline in `scratchpad/g27_fn_before.txt`, re-verified pristine at
--     15:16 UTC) gives per-function call counts over one complete pair. Divide
--     each caller's call count by its static mention count and the dominant
--     consumer falls out. That is one measurement serving three findings now:
--     G27, G23(b) and G21b.
WITH callers AS (
  SELECT n.nspname AS sch, p.proname AS fn,
         (length(p.prosrc) - length(replace(p.prosrc,'ottoq_policy_get','')))
           / length('ottoq_policy_get') AS mentions,
         p.prosrc AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc LIKE '%ottoq_policy_get%'
     AND p.proname <> 'ottoq_policy_get'
)
SELECT sch, fn, mentions,
       (src ~* '\mLOOP\M')                AS body_has_loop,
       (src ~* 'FOR[[:space:]]+\w+[[:space:]]+IN[[:space:]]+SELECT') AS body_has_for_select
  FROM callers
 ORDER BY mentions DESC, fn
 LIMIT 20;

-- ---------------------------------------------------------------------------
-- WHAT THIS DOES AND DOES NOT ESTABLISH
--
-- ESTABLISHED:
--   * The three busiest indexes in the database are two functions' repeated
--     lookups: 6,762,160,241 of 7,631,027,889 lifetime index scans —
--     **88.61%** — with the fourth-placed index 13x behind the third.
--   * `ottoq_policy_get` performs three `ottoq_policy_params` probes and one
--     `ottoq_sim_runs` probe on the modal call; two of the three params probes
--     find nothing. Proven two ways that agree to 4%: the counter ratio
--     (2.875 vs a predicted 3.0) and the per-pair call count scaled by history
--     (1.45e9 predicted vs 1.53e9 counted).
--   * Every one of the 1.53e9 primary-key probes of `ottoq_sim_runs` is this
--     function re-deriving a run's depot — a value immutable for the run's life.
--     Same defect class as G19 and G21: a constant re-derived per call.
--   * A whole-run memo is UNSAFE. The MPC lookahead writes and deletes policy
--     params mid-tick (Q5).
--
-- NOT ESTABLISHED, and not to be implied:
--   * WHICH callers make the 2.4M calls. 64 functions, 179 static sites, and
--     mentions are demonstrably not calls (Q6). r27_g settles it.
--   * What fraction of the 105.9 s is probe cost versus plpgsql call overhead.
--     44 microseconds per call across four probes on fully-cached tiny tables
--     suggests overhead dominates — which would mean the fix is to CALL IT
--     LESS, not to make it cheaper. Suggests. Not measured.
--   * Any saving. No fix is drafted here and none should be until r27_g lands,
--     for the reason 0130 gave and this file has not earned the right to skip:
--     four wrong guesses were already spent on G19.
-- ---------------------------------------------------------------------------
