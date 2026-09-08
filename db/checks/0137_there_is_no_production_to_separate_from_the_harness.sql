-- ---------------------------------------------------------------------------
-- 0137 — G26, and the framing is wrong in the finding's own title.
--
--        "Production and the proof harness share one database" implies two
--        tenants of comparable weight. They are not comparable. Measured
--        2026-09-08 14:44 UTC:
--
--            sim runs, total                          809
--            of those, run_by = 'cert_harness'        799   (98.8%)
--            depots with feed_mode 'sim'                3
--            depots with feed_mode 'external'           2  — 1 stall each
--            all tables in public/ottoq/twin         14.8 GB
--
--        Together with G16 and G22 (db/checks/0131, 0132), which established
--        that **98,800 of the 98,834 production-labelled rows in the signed
--        event stream are certification harness**, the picture is not two
--        tenants sharing a database. It is one tenant — the proof harness —
--        and a guest.
--
--        So the question is not "how do we separate them". It is "where should
--        production live, when there is one", and that is a much easier
--        question with a much cheaper answer.
--
-- Written while round 27 was running, catalog and light aggregate reads only.
-- ---------------------------------------------------------------------------

-- Q1. THE WEIGHTS, so the framing rests on numbers rather than on impression.
SELECT
  (SELECT count(*) FROM public.ottoq_sim_runs)                             AS sim_runs_total,
  (SELECT count(*) FROM public.ottoq_sim_runs WHERE run_by='cert_harness') AS cert_harness_runs,
  (SELECT count(*) FROM public.ottoq_run_archives)                         AS run_archives,
  (SELECT count(*) FROM public.depots WHERE feed_mode='sim')               AS sim_depots,
  (SELECT count(*) FROM public.depots WHERE feed_mode='external')          AS external_depots,
  (SELECT round(sum(pg_total_relation_size(c.oid))/1024.0/1024/1024,1)
     FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','ottoq','twin') AND c.relkind='r')        AS gb_all_tables;
--   -> 809 | 799 | 968 | 3 | 2 | 14.8

-- Q2. AND WHAT THE TWO 'external' DEPOTS ACTUALLY ARE.
SELECT d.name, d.feed_mode,
       (SELECT count(*) FROM public.stalls s WHERE s.depot_id = d.id) AS stalls
  FROM public.depots d WHERE d.feed_mode = 'external' ORDER BY d.name;
--   -> OTTOYARD Hardware Lab                          | external | 1
--      P2 Ledger-Only Proof Rig (retired test fixture) | external | 1
--
--   One hardware lab bench and one retired fixture. That is the entire
--   non-simulated footprint of this database.

-- Q3. WHY IT STILL MATTERS, because "there is no production" is not a reason
--     to do nothing. Three real costs, all of them independent of how small
--     the production side is today:
--
--     (a) A pair holds the flagship depot inside ONE transaction for 6-13
--         minutes, six or seven pairs a round, several rounds a day, on the
--         database the API serves. `db/checks/0133` could not settle whether
--         that shows up as an 8-20 second tail on live requests, because at
--         5.6 calls a minute the signal cannot be separated from noise. That
--         question is unanswered, not answered "no".
--
--     (b) It is the structural reason G16 and G22 could put harness rows into
--         the production-labelled signed stream at all. 0228 fixes the
--         labelling; only separation makes the mistake unavailable.
--
--     (c) It is why G12 — CI cannot run the SQL — is hard. There is no
--         database CI is allowed to touch, because the only one that has the
--         schema is the one serving the product.
--
--     The cost of (a) grows the moment there is a real tenant. The cost of (b)
--     and (c) is being paid now.

-- Q4. THE THREE OPTIONS, COSTED. This is the decision, and it is Chase's.
--
--     OPTION 1 — A SEPARATE SUPABASE PROJECT FOR THE TWIN.
--       What: the certification harness, the twin, and every sim depot move to
--       a new project. otto-q-core keeps the schema, the engine functions, and
--       whatever production there is.
--       Cost: one project; a schema-sync discipline between the two (the
--       migrations already exist as files, so this is a replay, not a rewrite);
--       and re-pointing the cert cron.
--       Buys: (a) completely — a pair cannot touch the API's database. (b)
--       completely — a harness row cannot reach the production event stream
--       because it is not in that database. (c) completely — CI gets a
--       database it may break, which is exactly what G12 needs.
--       Risk: two schemas that can drift. Mitigated by the fact that drift is
--       already checked (`scripts/check-drift.sql`) and would simply run twice.
--
--     OPTION 2 — A SEPARATE SCHEMA IN THE SAME PROJECT.
--       Cost: lowest. No new project, no sync.
--       Buys: (b) partially — the labelling mistake is still possible, just
--       less likely. Buys nothing for (a): same connection pool, same buffer
--       cache, same disk, same 6-13 minute transaction. Buys nothing for (c).
--       Honest verdict: this is the option that looks like progress and moves
--       almost nothing. Named so it can be rejected on purpose rather than
--       chosen for being cheap.
--
--     OPTION 3 — LEAVE IT, AND MEASURE FIRST.
--       Cost: the `load/` harness (G24) run against this database with and
--       without a pair in flight. That number does not exist yet — the harness
--       is built and calibrated but has never been run, because it needs a host
--       with a direct OTTOQ_DB_URL.
--       Buys: the answer to (a), which is currently a guess in both directions.
--       Honest verdict: this is not an alternative to 1, it is the thing that
--       should happen BEFORE 1, and it is cheap. **"What does a vehicle see
--       while the proof harness is running" is a number we can have this week,
--       and it is the number that makes the case for option 1 or dissolves it.**
--
-- Q5. THE RECOMMENDATION, stated plainly because a costed list with no
--     recommendation is a way of not deciding:
--
--       Run the load harness first (option 3), with and without a pair, and
--       publish both numbers with run IDs. Then take option 1 if the pair
--       shows up in the tail, and take it anyway if G12 stays blocked, because
--       "CI has no database" is a real cost being paid every day and option 1
--       is the only one of the three that ends it.
--
--       Do not take option 2. It is the one that feels responsible and changes
--       nothing about the transaction that is actually the problem.
SELECT 'see Q1-Q5; this file changes nothing and decides nothing' AS status;
