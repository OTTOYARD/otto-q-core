-- 0144  G21b SOLVED. Sixty percent of a certification pair is one function,
--       called 99.88% unnecessarily, from a MATERIALIZED CTE in a view.
--
-- STATUS: FINDING. No fix applied. The fix is drafted in prose at the bottom and
-- must go through APPLYING.md with an EXPLAIN proof before it is written.
--
-- INSTRUMENT: r28_g, a 12-tick pair at track_functions='all', 2026-09-08 18:25
-- UTC, 330 s. Baseline db/evidence/r28_g_fn_baseline.md (all 304 rows, captured
-- 16:23:39, re-verified counter-by-counter at 17:10 across three intervening
-- pairs with nothing moving). After-capture db/evidence/r28_g_fn_after.md.
-- Diffed by scripts/fn-delta.py.
--
-- =========================================================================
-- Q1. THE HEADLINE
-- =========================================================================
--
--   ottoq_policy_get   4,894,867 calls   199,648.5 ms self   in ONE 12-tick pair
--
-- That is 85.96% of all 5,694,271 function calls in the pair, and 35x the next
-- function (twin.ottoq_sim_seeded_random at 139,987).
--
-- The pair took 330 s. 199,648 ms of self time is **60.5% of the pair's entire
-- wall clock**, in one function.
--
-- Per call: 199,648.5 / 4,894,867 = 40.8 microseconds. db/checks/0139 measured
-- 44 us and concluded "overhead dominates, which would mean the fix is to CALL
-- IT LESS, not to make it cheaper." That conclusion is confirmed, and this check
-- supplies the missing half: WHERE to stop calling it.

-- =========================================================================
-- Q2. THE CALLER IS NOT IN THE 64-CALLER CENSUS, AND THAT IS THE FINDING
-- =========================================================================
--
-- db/evidence/policy_get_static_census.md lists all 64 functions whose source
-- mentions ottoq_policy_get, 179 mentions total. Multiplying each caller's
-- MEASURED per-pair invocation count by its mention count -- an upper bound
-- assuming every mention fires on every invocation -- gives:
--
--   SUM over all 64 callers ......................    42,461
--   ottoq_policy_get calls actually made .......... 4,894,867
--   ratio ......................................... 115.3x
--
-- **Every known plpgsql caller, at its theoretical maximum, accounts for 0.87%
-- of the calls.** 0139 refused to name a caller from the static census and said
-- the shape was "a function called from SQL the profiler cannot attribute".
-- That is now measured rather than suspected, and the census is retired as an
-- instrument for this question. Four wrong guesses were spent on G19 reasoning
-- from static structure; this is the fifth avoided.
WITH callers AS (
  SELECT n.nspname AS sch, p.proname AS fn,
         (length(p.prosrc) - length(replace(p.prosrc,'ottoq_policy_get','')))
           / length('ottoq_policy_get') AS mentions
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc LIKE '%ottoq_policy_get%'
     AND p.proname <> 'ottoq_policy_get'
)
SELECT count(*) AS caller_functions, sum(mentions) AS static_mention_sites
  FROM callers;

-- =========================================================================
-- Q3. WHERE IT ACTUALLY IS: one view, found by censusing SQL objects
-- =========================================================================
--
-- Searching views, column defaults, check constraints, index expressions, RLS
-- policies and trigger WHEN clauses for the function name returns exactly ONE
-- object in the whole database:
--
--   VIEW  public.ottoq_approach_band   3 mentions
--
-- Its first CTE:
--
--   WITH r AS MATERIALIZED (
--       SELECT rr.sim_run_id, rr.depot_id, rr.sim_clock_current,
--           GREATEST(ottoq_policy_get(rr.sim_run_id,'approach_freeze_minutes',10),0),
--           GREATEST(ottoq_policy_get(rr.sim_run_id,'approach_horizon_minutes',30),1),
--           GREATEST(ottoq_policy_get(rr.sim_run_id,'approach_stale_heartbeat_sec',90),1)
--         FROM ottoq_sim_runs rr
--        WHERE rr.depot_id IS NOT NULL        -- <-- no run scope. EVERY run, ever.
--   )
--
-- It resolves three policy parameters for **every sim run that has ever
-- existed**, to obtain three constants for the one run being executed.
SELECT kind, obj, mentions FROM (
  SELECT 'VIEW'::text AS kind,
         c.relnamespace::regnamespace::text || '.' || c.relname AS obj,
         (length(pg_get_viewdef(c.oid)) - length(replace(pg_get_viewdef(c.oid),'ottoq_policy_get','')))
           / length('ottoq_policy_get') AS mentions
    FROM pg_class c
   WHERE c.relkind IN ('v','m')
     AND c.relnamespace::regnamespace::text IN ('public','twin','ottoq')
     AND pg_get_viewdef(c.oid) LIKE '%ottoq_policy_get%'
) s ORDER BY mentions DESC;

-- =========================================================================
-- Q4. THE ARITHMETIC CLOSES EXACTLY
-- =========================================================================
--
--   rows in ottoq_sim_runs with depot_id ...............   831
--   rows the executing arm actually needs ..............     1
--   ottoq_policy_get calls per view evaluation .........  2,493   (831 x 3)
--   calls needed per view evaluation ...................      3
--   WASTE ..............................................  99.88%
--
--   implied view evaluations = 4,894,867 / (3 x 831) ... 1,963.4
--   ottoq_approach_zone invocations this pair .......... 2,336
--   evaluations per invocation ......................... 0.83
--
-- 1,963 against 2,336 is the signature of one evaluation per invocation with a
-- fraction short-circuiting. ottoq_approach_zone is THE consumer.
SELECT (SELECT count(*) FROM public.ottoq_sim_runs WHERE depot_id IS NOT NULL) AS runs_scanned,
       1                                                                       AS runs_needed,
       (SELECT count(*) FROM public.ottoq_sim_runs WHERE depot_id IS NOT NULL) * 3 AS calls_per_evaluation,
       3                                                                       AS calls_required,
       round(1 - 3.0 / ((SELECT count(*) FROM public.ottoq_sim_runs WHERE depot_id IS NOT NULL) * 3), 6) AS waste_fraction;

-- =========================================================================
-- Q5. WHY THE PLANNER CANNOT SAVE IT: MATERIALIZED is an optimisation fence
-- =========================================================================
--
-- The one real consumer asks for a single row and names both keys:
--
--   FROM ottoq_approach_band b
--    WHERE b.vehicle_id = p_vehicle_id AND b.sim_run_id = p_sim_run_id
--    LIMIT 1
--
-- Postgres cannot push `sim_run_id = p_sim_run_id` into a CTE declared
-- MATERIALIZED -- that keyword exists precisely to forbid it. So the view
-- computes 831 runs' policy parameters, materialises 96,121 rows, and the
-- caller discards 96,120 of them.
--
-- **ottoq_readmit_resumed_visits is NOT a second consumer.** Its only mention of
-- the view is inside a COMMENT. The static-census lesson, one more time, in the
-- same check that retires the census.
SELECT n.nspname||'.'||p.proname AS consumer,
       substring(p.prosrc from position('ottoq_approach_band' in p.prosrc) for 160) AS context
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('public','twin','ottoq')
   AND p.prosrc LIKE '%ottoq_approach_band%'
 ORDER BY 1;

-- =========================================================================
-- Q6. G27 CLOSED IN THE SAME MEASUREMENT
-- =========================================================================
--
--   twin.ottoq_sim_compute_charger_load_kw   1,004 calls at 12 ticks
--   (r27_g counted                           1,128 calls at 24 ticks)
--   ratio 24t / 12t = 1.12x
--
-- **Not 2.0x.** 0223's predicted scaling rested on the meter being called once
-- per tick; it is very nearly independent of tick count. G27's live half is
-- closed: the per-call arithmetic did not under-deliver, the assumption
-- underneath it was wrong.
--
-- And db/checks/0130 DERIVED ~1,024 calls at 12 ticks without ever counting
-- them. Measured: 1,004. **The derivation was right to within 2.0%** -- which is
-- worth recording because 0130's derived figure was treated with suspicion for
-- two rounds and did not deserve it.

-- =========================================================================
-- WHAT IS ESTABLISHED, AND WHAT IS NOT
-- =========================================================================
--
-- ESTABLISHED:
--   * 60.5% of a 12-tick certification pair is ottoq_policy_get self time.
--   * 99.88% of those calls resolve policy for runs that are not executing.
--   * The single source is the MATERIALIZED CTE in public.ottoq_approach_band.
--   * The single consumer filters by run and vehicle and takes one row.
--   * The load meter is ~1.12x per tick-doubling, not 2.0x. G27 closed.
--
-- NOT ESTABLISHED, and not to be implied:
--   * **That this explains round 28's 24t:12t ratio moving from 1.53 to 2.34-2.59.**
--     It is the right SHAPE -- cost proportional to a table the runs themselves
--     grow -- but ottoq_sim_runs grew only ~4% between round 27 and round 28
--     (roughly 800 -> 831), which is not obviously enough to move the ratio that
--     far. The mechanism is confirmed; its sufficiency for the superlinearity is
--     a separate question and is NOT answered here.
--   * Any saving. See below: the fix is not written and its saving is not measured.
--
-- THE FIX, IN PROSE, NOT DRAFTED
--
-- The minimal change is to let the run predicate reach the CTE. Candidates, in
-- order of preference, each of which must be proven by EXPLAIN before it is
-- written into a migration:
--
--   1. Drop MATERIALIZED. Cheapest edit; requires proving the planner actually
--      pushes sim_run_id into the CTE and does not instead re-evaluate it per
--      outer row, which would be worse.
--   2. Add a run-scoping predicate inside the CTE. Changes what the view means
--      for any future unfiltered consumer, so it needs a stated contract.
--   3. Replace the view with a function taking p_sim_run_id. Correct by
--      construction, largest blast radius.
--
-- PRE-FLIGHT REQUIREMENTS, because this view is read on the decide path:
--   * EXPLAIN (ANALYZE, BUFFERS) before and after, proving the CTE is no longer
--     computed for 831 runs.
--   * The 12-tick canons for all four flagship columns must be unchanged. The
--     view feeds ottoq_approach_zone, which feeds the decide path; a change in
--     its output would move h_dec and h_cmd. Results should be identical because
--     the consumer already filters to one run -- "should" is not "proven".
--   * Never applied while a round is in flight (pg_stat_activity is the only
--     authority) and never on the same day as a canon comparison without a
--     recertification round after it.
