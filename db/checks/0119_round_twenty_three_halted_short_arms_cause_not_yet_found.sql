-- ---------------------------------------------------------------------------
-- 0119 — ROUND 23 HALTED after two pairs. The arms stop short of their tick
--        count, and I have NOT identified why. This file records what is
--        established and what is not, so the next session does not re-walk it.
--
-- WHAT HAPPENED. Round 23 was scheduled at the 0208 floor (2026-09-07
-- 21:36:53 UTC) as nine pairs, jobs 443-451. The first two both came back
-- INCONCLUSIVE with short arms:
--
--   21:45  171717/24t  arms reached  9 and 10 ticks of 24
--   22:10  314159/12t  arms reached  9 and 11 ticks of 12
--
-- ottoq_determinism_pair caps each arm's TICK LOOP at p_arm_budget_s (240 s)
-- of wall clock:
--     EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) >= p_arm_budget_s;
-- An arm that hits the cap before p_ticks is short, and 0143 correctly calls
-- that inconclusive rather than a failure. So the verdicts are honest; the
-- engine simply did not get through the ticks in the time allowed.
--
-- Jobs 445-451 (c3..c9) were unscheduled rather than burning seven more pairs
-- on a cause nobody understood. c3 was already in flight and self-unschedules.
--
-- THE SLOWDOWN IS REAL AND IT IS A STEP, NOT A DRIFT. Per-tick cost implied by
-- ticks-completed against the 240 s cap:
--
--   171717/24t   round 22 (18:35)  24 ticks in <=240 s  ->  <=10 s/tick
--   171717/24t   round 23 (21:45)   9 ticks in  240 s   ->  ~26 s/tick
--
-- and across four days of arms on this depot, EVERY arm reached its full tick
-- count on 09-03, 09-04, 09-05 and 09-06, and on 09-07 through round 22. The
-- first short arm in the window is round 23's first pair.
--
-- WHAT IS RULED OUT.
--
--   * 0208 is NOT the cause, despite applying 9 minutes before the first short
--     pair. ottoq_hash_rule_evaluations is called by ottoq_determinism_pair
--     alone (pg_proc scan for callers: one hit), once per arm, OUTSIDE the
--     tick loop, and it measures 251 ms on a full flagship arm. It cannot
--     spend 60% of a 240 s tick-loop budget. The timing is coincidence, and
--     writing it down as such is the point -- the correlation is seductive.
--
--   * The standing cron jobs are not the cause. ottoq-depot-tick,
--     ottoq-demo-metronome and ottoq-run-governor all run in 0.02-0.04 s and
--     their durations are flat across the whole window.
--
--   * My own analytical queries are not the cause. That was the leading
--     hypothesis when only the 24-tick pair had come back short; the 12-tick
--     pair at 22:10 came back short too, while I was deliberately off the
--     database. One pair could have been starved; two in a row, one of them
--     with no competing load, is the engine.
--
-- WHAT IS SUSPECTED, WITH THE NUMBER ATTACHED, AND NOT YET PROVEN.
--
--   ottoq_rule_evaluations   5,451,275 rows   4,932 MB   last autovacuum 09-06 08:01
--   ottoq_events             2,632,425 rows   3,440 MB   last autovacuum 09-07 08:02
--   ottoq_decisions          1,628,663 rows   1,838 MB   last autovacuum 09-04 22:07
--   ottoq_stall_bookings       769,290 rows     866 MB   12.2% DEAD TUPLES
--
-- Each flagship arm writes ~8,000 rule evaluations into the first of those.
-- Insert cost against a 4.9 GB table with its indexes, plus 12% dead tuples on
-- the bookings table the decide path reads and writes every tick, is the
-- obvious candidate for a per-tick cost that rises as the certification itself
-- grows the tables. It also explains why this is the failure mode of a LONG
-- day of rounds rather than a code change.
--
-- But a growth story predicts a DRIFT and what is observed is a STEP between
-- 21:03 and 21:45. Those are not the same shape, and until that is reconciled
-- the growth story is a hypothesis, not a finding. Autovacuum ran on
-- ottoq_vehicle_commands and ottoq_energy_commands at 21:25:30, inside the
-- window; whether that is related is unknown.
--
-- THE MEASUREMENT THAT WOULD SETTLE IT, and which was not run because it
-- mutates state and a pair was in flight:
--
--   1. Time ottoq_sim_advance_tick directly on a scratch run at the flagship
--      depot -- per-tick wall cost, and where it goes (the twin's own tick
--      instrumentation, or auto_explain on the tick path).
--   2. Run the grid fixture pair (0153, a tiny depot-shaped world). If the
--      grid pair's wall time is unchanged, the slowdown is proportional to
--      flagship DATA VOLUME and the growth story survives; if the grid pair
--      slowed too, it is the engine or the box and the growth story dies.
--   3. VACUUM (ANALYZE) ottoq_stall_bookings and ottoq_rule_evaluations, then
--      re-run one 12-tick pair. A recovery pins bloat as the mechanism.
--
-- DO NOT raise p_arm_budget_s to make the round pass. The budget was sized
-- when ticks were cheaper; raising it hides the regression and buys a green
-- matrix that means less than the one it replaces. Find the cost first.
--
-- STANDING: round 22 remains the last complete round and its canons in
-- db/canons/round22.md are the current reference. Round 23 produced two
-- inconclusive pairs and no canon. The 0208 recertification floor
-- (2026-09-07 21:36:53 UTC) stands unmet -- canon_rule has not been
-- re-established on any column, so 0208's prediction is UNJUDGED.
-- ---------------------------------------------------------------------------

-- 1. The two inconclusive verdicts, with the tick counts that make them so.
WITH v AS (
  SELECT r.started_at, r.random_seed, r.tick_count, r.scenario_code,
         r.validation_notes::jsonb AS vn
    FROM public.ottoq_sim_runs r
   WHERE r.started_at >= '2026-09-07 21:36:53+00'
     AND r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND r.validation_notes IS NOT NULL)
SELECT started_at, random_seed AS seed, tick_count AS ticks_reached,
       scenario_code AS scen, vn->>'equal' AS equal, vn->>'outcome' AS outcome
  FROM v WHERE vn ? 'equal' ORDER BY started_at, tick_count;

-- 2. Every arm on this depot for four days: the step is on 09-07, in round 23.
--    Expect min_ticks = 12 on 09-03..09-06 and 9 on 09-07.
SELECT date_trunc('day', r.started_at) AS day,
       r.random_seed AS seed, r.scenario_code AS scen,
       count(*) AS arms, min(r.tick_count) AS min_ticks, max(r.tick_count) AS max_ticks
  FROM public.ottoq_sim_runs r
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
   AND r.status = 'completed'
   AND r.started_at > now() - interval '5 days'
   AND r.validation_notes IS NOT NULL
 GROUP BY 1,2,3 ORDER BY 2,3,1;

-- 3. THE EXONERATION OF 0208: exactly one caller, and it is the pair function.
--    If this ever returns a function that runs inside a tick, revisit.
SELECT n.nspname||'.'||p.proname AS caller
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.prosrc ILIKE '%ottoq_hash_rule_evaluations%'
   AND p.proname <> 'ottoq_hash_rule_evaluations'
 ORDER BY 1;

-- 4. The standing jobs are flat across the window (0.02-0.04 s), so they are
--    not competing for the tick loop.
SELECT j.jobname, date_trunc('hour', d.start_time) AS hr, count(*) AS runs,
       round(avg(EXTRACT(epoch FROM (d.end_time - d.start_time)))::numeric, 3) AS avg_secs
  FROM cron.job_run_details d JOIN cron.job j ON j.jobid = d.jobid
 WHERE d.start_time > now() - interval '8 hours'
   AND j.jobname IN ('ottoq-depot-tick','ottoq-demo-metronome','ottoq-run-governor')
 GROUP BY 1,2 ORDER BY 1,2;

-- 5. The suspect, with its numbers. Re-read before the next round: if
--    ottoq_rule_evaluations keeps growing and autovacuum keeps falling behind,
--    this is where the tick cost is going.
SELECT relname, n_live_tup, n_dead_tup,
       CASE WHEN n_live_tup > 0 THEN round(100.0*n_dead_tup/n_live_tup, 1) END AS dead_pct,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       last_autovacuum
  FROM pg_stat_user_tables
 WHERE relname IN ('ottoq_rule_evaluations','ottoq_events','ottoq_decisions',
                   'ottoq_stall_bookings','ottoq_vehicle_commands')
 ORDER BY pg_total_relation_size(relid) DESC;
