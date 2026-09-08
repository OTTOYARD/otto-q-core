-- ---------------------------------------------------------------------------
-- 0130 — G21. The site load meter re-derives "which run is running" ONCE PER
--        CHARGE-SESSION ROW: 8,966,506 evaluations of a constant, in one pair.
--
-- Measured 2026-09-08 ~11:58 UTC against gxdrcyphqjzjsuhxuqtg, from the
-- snapshots r25_g took at 10:52 (public.g19_stmt_before, public.g19_fn_before)
-- and that 0129 only half-read. 0129 used the STATEMENT view with a >3 s filter
-- and stopped once the fingerprint accounted for 694 of 700.7 s. It never
-- opened the FUNCTION view, and it never asked which statement had the most
-- CALLS rather than the most seconds. Both questions had an answer waiting.
--
-- This is not a new capture. It is the same capture, read properly.
-- ---------------------------------------------------------------------------

-- Q1. THE STATEMENT NOBODY RANKED: the most-executed statement in the pair.
--
--       calls        secs   statement
--   8,966,506       108.8   SELECT sim_run_id FROM ottoq_sim_runs
--                             WHERE depot_id = p_depot_id AND status = $2
--                             ORDER BY started_at DESC LIMIT $3
--   2,413,581         9.2   SELECT param_value FROM ottoq_policy_params ... scope 'run'
--   2,412,619         7.6   SELECT depot_id FROM ottoq_sim_runs WHERE sim_run_id=...
--   2,410,293         9.1   SELECT param_value FROM ottoq_policy_params ... scope 'depot'
--   2,409,075         9.2   SELECT param_value FROM ottoq_policy_params ... scope 'global'
--
--   Nine million executions of one statement, in one 12-tick pair. Rank by
--   total_exec_time (which is what 0129 did) and it is sixth; rank by calls and
--   it is first by a factor of four.
SELECT s.calls - COALESCE(b.calls,0) AS calls,
       round(((s.total_exec_time - COALESCE(b.total_exec_time,0))/1000)::numeric,1) AS secs,
       left(regexp_replace(s.query,'\s+',' ','g'), 150) AS q
FROM pg_stat_statements s
LEFT JOIN public.g19_stmt_before b ON b.queryid = s.queryid
WHERE (s.calls - COALESCE(b.calls,0)) > 100000
ORDER BY (s.calls - COALESCE(b.calls,0)) DESC;

-- Q2. THE FUNCTION VIEW, WHICH 0129 NEVER OPENED. r25_g ran with
--     track_functions='pl' and every other session on this database leaves it
--     at 'none', so this delta is that one pair and nothing else — confirmed by
--     ottoq_determinism_pair showing calls = 1.
--
--       calls        total_s  self_s  function
--           1          700.7   255.7  ottoq_determinism_pair      <- the fingerprint, now 0222
--         616          125.0   124.9  ottoq_l2_propose_stall_assignment
--   2,413,581          105.9   105.9  ottoq_policy_get
--       1,304           62.9    62.9  ottoq_eval_en_001_grid_capacity
--      14,076           81.7    16.8  ottoq_evaluate_rule_core
--          24          355.2     5.2  ottoq_decide_tick           <- 350 s of it is callees
--          24          106.1    10.6  ottoq_enact_inspection_seam
--       1,376            5.1     5.1  ottoq_validate_assignment   <- 0127's carrier, again ~1%
--
--     SQL-language functions are NOT counted by track_functions='pl'. Every
--     hop in the chain Q3 names is a SQL function, which is exactly why this
--     cost has been invisible to every profile taken on this task.
SELECT f.funcname,
       f.calls - COALESCE(b.calls,0) AS calls,
       round(((f.total_time - COALESCE(b.total_time,0))/1000)::numeric,1) AS total_s,
       round(((f.self_time  - COALESCE(b.self_time ,0))/1000)::numeric,1) AS self_s
FROM pg_stat_user_functions f
LEFT JOIN public.g19_fn_before b ON b.funcid = f.funcid
WHERE (f.total_time - COALESCE(b.total_time,0)) > 1000
ORDER BY (f.self_time - COALESCE(b.self_time,0)) DESC LIMIT 12;

-- Q3. THE CHAIN, measured end to end. Every arrow is a SQL function except the
--     first and last, so only the ends are visible to the function profiler:
--
--       ottoq_eval_en_001_grid_capacity        1,304 calls    62.9 s self   [plpgsql]
--         -> public.ottoq_depot_current_demand_kw              (untracked)  [sql]
--           -> twin.ottoq_sim_compute_charger_load_kw
--                                              1,024 calls   195.4 s        [sql]
--             -> public.ottoq_depot_running_run
--                                          8,966,506 calls   108.8 s        [sql]
--
--     8,966,506 / 1,024 = **8,756 evaluations per call**, of a value that does
--     not vary within the call.
SELECT s.calls - COALESCE(b.calls,0) AS calls,
       round(((s.total_exec_time - COALESCE(b.total_exec_time,0))/1000)::numeric,1) AS secs,
       left(regexp_replace(s.query,'\s+',' ','g'), 110) AS q
FROM pg_stat_statements s
LEFT JOIN public.g19_stmt_before b ON b.queryid = s.queryid
WHERE s.query ILIKE '%ocpp_sessions%' AND (s.calls - COALESCE(b.calls,0)) > 500
ORDER BY (s.total_exec_time - COALESCE(b.total_exec_time,0)) DESC;

-- Q4. WHY IT IS PER-ROW. twin.ottoq_sim_compute_charger_load_kw:
--
--       AND COALESCE(cs.sim_run_id, '00000000-…'::uuid)
--         = COALESCE(ottoq_depot_running_run(p_depot_id), '00000000-…'::uuid);
--
--     The call is on the RIGHT of a WHERE-clause comparison whose LEFT side
--     carries a Var, so it is a filter expression evaluated once per candidate
--     row. Postgres pre-evaluates IMMUTABLE expressions at plan time; this one
--     is STABLE, and STABLE only promises a fixed answer within one statement —
--     it does not buy caching.
--
--     And ottoq_depot_running_run cannot be inlined away: it is
--     `LANGUAGE sql STABLE SET search_path TO …`, and a SQL function carrying a
--     SET clause is not inlinable. The proof is in the numbers rather than the
--     manual — an inlined function has no body statement of its own to record,
--     and this one recorded 8,966,506 executions.
SELECT p.proname, l.lanname, p.provolatile,
       (p.proconfig IS NOT NULL) AS has_set_clause
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN pg_language l ON l.oid=p.prolang
WHERE (n.nspname,p.proname) IN (('public','ottoq_depot_running_run'),
                                ('twin','ottoq_sim_compute_charger_load_kw'),
                                ('public','ottoq_depot_current_demand_kw'));

-- Q5. THE ROW SET IT IS PAID FOR. 8,756 rows survive the depot + status + time
--     predicates and reach the run filter. Not one of them needs the function
--     re-run.
SELECT count(*) AS rows_at_flagship,
       count(*) FILTER (WHERE status IN ('active','completed')) AS act_or_done,
       count(*) FILTER (WHERE sim_run_id IS NULL) AS null_sim_run_id
FROM public.ocpp_sessions
WHERE depot_id = '11111111-1111-1111-1111-111111111111';
--     -> 44,312 / 33,879 / 0   (2026-09-08 11:58 UTC)
--
--     Note the zero. No charge session at the flagship depot has a NULL
--     sim_run_id, so today the left-hand COALESCE protects nothing and costs
--     everything. That is an argument for FIX 2, not licence to drop it: the
--     column is nullable and a production-feed row would be NULL.

-- Q6. WHAT IT IS WORTH. 195.4 s of the 700.7 s pair 0129 profiled — 28%. After
--     0222 the same pair runs 537 s (round 26 a, measured), so the load meter is
--     now ~36% of it, and the hoistable constant alone is ~109 s, ~20%.
--
--     THE FIX, and why it cannot change a number: put the call in a
--     `WITH r AS MATERIALIZED (SELECT ottoq_depot_running_run(p_depot_id) …)`
--     and join it. One evaluation instead of 8,756. STABLE is precisely the
--     declaration that those 8,756 answers were the same answer — if that were
--     false the function would already be returning different values to
--     different rows of the same sum, and the meter would be wrong today.
--
--     The pattern is not new here: ottoq.ottoq_stall_free_between already wraps
--     its three ottoq_policy_get calls in `WITH g AS MATERIALIZED` for exactly
--     this reason. The load meter was written without it.
--
--     Applied as migration 0223, AFTER round 26 completes — never a migration
--     while a pair is in flight (scripts/APPLYING.md, the P- block).

-- Q7. THE SECOND ORDER, recorded and NOT fixed here. ottoq_policy_get is called
--     2,413,581 times per pair for 105.9 s. Its three-tier lookup is four index
--     probes; the plpgsql call overhead is the other 70 s. The call sites are
--     spread across 65 functions and the biggest single consumer has not been
--     isolated. Do not guess at it — this task has spent four guesses on G19
--     already. Instrument a pair for it the way r25_g was instrumented, then
--     act. Recorded as the next question, not as a finding.
--
--     TWO THINGS ELIMINATED BY MEASUREMENT, so the next investigator does not
--     spend them again:
--
--     (a) THE SQL-WRAPPER ROUTE IS NOT IT. Eight SQL-language functions call
--         ottoq_policy_get and are inlinable into their callers. Their combined
--         traffic in this pair: ottoq.ottoq_stall_free_between 4,640 calls
--         (3,858 + 396 + 214 + 172 across four call sites) at 3 policy_get each
--         = ~14k, and it already wraps them in `WITH g AS MATERIALIZED` so that
--         is 3 per CALL and not 3 per row; ottoq_target_soc_cap 710;
--         ottoq_is_depot_night 420; ottoq_default_target_soc ~640 across five
--         sites. Total under 17,000 — **0.7% of 2,413,581.**
--
--     (b) THE STATEMENT VIEW CANNOT ANSWER THIS, and that is not a gap in the
--         capture. Every statement whose text mentions ottoq_policy_get sums to
--         ~10,000 calls in this pair. The reason is structural: plpgsql
--         evaluates SIMPLE EXPRESSIONS — `IF f(x) >= 1 THEN`, `v := f(x)` —
--         directly through the executor rather than as SPI statements, so they
--         never reach pg_stat_statements at all. A function called only from
--         simple expressions is INVISIBLE to the statement view and visible
--         only to pg_stat_user_functions, which is exactly the pair of readings
--         we have. So the caller must be found by function-level accounting or
--         by reading the loops, not by ranking statements.
--
--     (c) THE PLPGSQL CALL SITES ARE 1% OF IT. Joining the 65 callers to their
--         own per-pair call counts and multiplying by the number of
--         ottoq_policy_get sites in each body:
--
--           38 plpgsql callers ran, 7,956 invocations in total
--           naive expectation at one execution per site per call:  26,038
--           actual:                                            2,413,581
--
--         The top contributors are ottoq_recall_naive_threshold_v1 (650 calls x
--         16 sites = 10,400), ottoq.ottoq_book_stall (3,408 x 2 = 6,816) and
--         ottoq_arm_timings (252 x 9 = 2,268). Everything tracked, added up,
--         is **1.1%** of the traffic.
--
--     So 98.9% comes from one of exactly two places, and this file names both
--     rather than picking one:
--
--       (i)  a LOOP inside one of those plpgsql bodies, which makes the site
--            count a lower bound rather than the upper bound assumed above; or
--       (ii) one of the seven remaining SQL-language helpers, INLINED into a
--            query over a large row set — inlining leaves no statement trace and
--            no function-stat row, so it would be invisible to both views while
--            multiplying its sites by the row count.
--
--     Both are checkable. Neither is checked here. The arithmetic to beat is
--     2,413,581 / 24 ticks = 100,566 per tick, and note that (ii) is the same
--     shape as the finding this whole file is about: a helper evaluated once per
--     row of something large, to answer a question that does not vary.
SELECT f.funcname, f.calls - COALESCE(b.calls,0) AS calls,
       round(((f.self_time - COALESCE(b.self_time,0))/1000)::numeric,1) AS self_s
FROM pg_stat_user_functions f
LEFT JOIN public.g19_fn_before b ON b.funcid = f.funcid
WHERE (f.calls - COALESCE(b.calls,0)) > 20000
ORDER BY 2 DESC;

-- Q8. THE PLAN AFTER THE HOIST, run 2026-09-08 12:09 UTC before drafting 0223,
--     so the migration is written against a plan that was seen rather than one
--     that was expected:
--
--       Aggregate  (cost=3785.51..3785.52 rows=1 width=32)
--         CTE r
--           ->  Result  (cost=0.00..0.26 rows=1 width=16)        <- ONE evaluation
--         ->  Nested Loop  (cost=0.00..3785.23 rows=1 width=123)
--               Join Filter: (r.run_key = COALESCE(cs.sim_run_id, '000…000'::uuid))
--               ->  Seq Scan on ocpp_sessions cs  (cost=0.00..3785.20 rows=1)
--                     Filter: (status = ANY ('{active,completed}') AND depot_id = …
--                              AND started_at <= now() AND (ended_at IS NULL OR …))
--               ->  CTE Scan on r  (cost=0.00..0.02 rows=1 width=16)
--
--     The function appears in no Filter, no Index Cond and no Join Filter: the
--     per-row cost is now a uuid comparison. That is the whole of 0223.
--
--     AND THE PLAN NAMES THE NEXT PROBLEM IN THE SAME BREATH: `Seq Scan on
--     ocpp_sessions`, 44,372 rows. There are eleven indexes on this table and
--     the query uses none of them. idx_ocpp_sessions_active_run is
--     (depot_id, sim_run_id) WHERE status='active' — an exact fit for the
--     predicate except that 0155 widened the status set to include 'completed'
--     (correctly: a session that ended during this tick still delivered power),
--     which put the query outside the partial index. That is the remaining
--     ~87 s and it is FIX 2. It needs an index, so it is a separate migration
--     and a separate prediction: one pair should judge one claim.

-- Q9. A PROPOSAL, NOT A FINDING, and labelled so on purpose.
--
--     0221 made the 0123/0124 run-scope predicate sargable in ONE function by
--     rewriting COALESCE(col, nil) = COALESCE(param, nil) into an explicit
--     plpgsql branch. Thirty-two more functions carry the same shape, and
--     rewriting thirty-two decide-path functions is thirty-two chances to move
--     an atom.
--
--     There may be a change that needs no function edits at all. Postgres can
--     use an index built ON THE EXPRESSION: an index on
--     (depot_id, COALESCE(sim_run_id, '000…000'::uuid), started_at) matches the
--     predicate exactly as written, so the existing COALESCE becomes sargable
--     with zero code change and therefore zero risk to any hashed output. The
--     same trick would have served ottoq_stall_bookings.
--
--     THIS HAS NOT BEEN TESTED. The test is one CREATE INDEX and one EXPLAIN,
--     and it was not run here because a round was in flight and building an
--     index mid-round changes plans under the pairs being timed. It is written
--     down as the next experiment, with its own failure mode stated: an
--     expression index is only usable if the query's expression matches the
--     index's expression TEXTUALLY after normalisation — a different sentinel
--     literal, a different cast, or a COALESCE with the arguments the other way
--     round all miss.
--
--     Whether they ARE uniform was measured first, 2026-09-08 12:23 UTC — and
--     it is the part of this proposal that came out better than expected.
--
--     THE CENSUS: **40 functions, 99 sites** carry a COALESCE over something
--     named sim_run_id. 0221's header says 33 functions; the difference is that
--     this count also catches the parameter side, and the split is the finding:
--
--       COALESCE(p_sim_run_id, '000…000'::uuid)          42   PARAMETER side
--       COALESCE(vn.sim_run_id,  '000…000'::uuid)        25   ottoq_visit_needs
--       COALESCE(n.sim_run_id,   '000…000'::uuid)         8   ottoq_visit_needs
--       COALESCE(vn2.sim_run_id, '000…000'::uuid)         4   ottoq_visit_needs
--       COALESCE(d.sim_run_id,   '000…000'::uuid)         2
--       COALESCE(ottoq_visit_needs.sim_run_id, …)         2   ottoq_visit_needs
--       COALESCE(cs.sim_run_id,  '000…000'::uuid)         2   ocpp_sessions (this file)
--       COALESCE(v_e.sim_run_id, c_nil)                   2   plpgsql constant
--       COALESCE(e.sim_run_id,   c_nil)                   1   plpgsql constant
--       COALESCE(vn3.sim_run_id, '000…000'::uuid)         1   ottoq_visit_needs
--       COALESCE(vn.sim_run_id,'000…000'::uuid)           1   no space after the comma
--
--     Three things fall out of that table:
--
--     1. **Forty-two of the ninety-nine are free.** COALESCE over a PARAMETER
--        is a constant per call — it is not a function of a column and defeats
--        no index. Only the ~57 column-side sites are the defect. An estimate
--        of this sweep that counts all 99 is wrong by nearly a factor of two,
--        in the direction that makes the work look bigger than it is.
--     2. **The literal IS uniform** — `'00000000-0000-0000-0000-000000000000'::uuid`
--        everywhere except one missing space (which normalises away) and three
--        sites using a plpgsql constant `c_nil`, which an expression index
--        cannot match at all and which would need their own treatment.
--     3. **One table dominates**: 41 of the ~57 column-side sites are
--        ottoq_visit_needs, under six different aliases. So the sweep is not
--        thirty-two function rewrites. It is plausibly two or three expression
--        indexes — ottoq_visit_needs first — and the aliases are irrelevant,
--        because an index matches the EXPRESSION, not the alias.
--
--     Still a proposal. The census says the shape is favourable; it does not
--     say the planner will use the index, and this project has twice had a fix
--     that measured beautifully and bought zero seconds on a pair. One index,
--     one EXPLAIN, one pair — in that order, and after 0223 is judged.
--
--     The census query, so the count can be re-run rather than believed:
SELECT n.nspname||'.'||p.proname AS fn,
       (length(p.prosrc) - length(replace(p.prosrc, 'COALESCE(', '')))/10 AS coalesce_total,
       (SELECT count(*) FROM regexp_matches(p.prosrc,
          'COALESCE\(\s*\w+\.?\w*sim_run_id\s*,', 'g')) AS run_scope_coalesces
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','twin','ottoq')
  AND p.prosrc ~ 'COALESCE\(\s*\w+\.?\w*sim_run_id\s*,'
ORDER BY 3 DESC, 1;

-- Q10. THE TWO BIGGEST REMAINING FUNCTIONS IN THE PROFILE ARE BOTH THIS METER.
--
--      `self_time` in pg_stat_user_functions excludes time spent in TRACKED
--      callees. Every hop of the load-meter chain is a SQL function and SQL
--      functions are not tracked by track_functions='pl' — so the meter's cost
--      does not appear as a function of its own. It appears as the SELF TIME OF
--      WHOEVER CALLED IT. Adding up everything that calls
--      ottoq_depot_current_demand_kw:
--
--        function                              calls   self_s
--        ottoq_l2_propose_stall_assignment       616    124.9
--        ottoq_eval_en_001_grid_capacity       1,304     62.9
--        twin.ottoq_sim_advance_site_energy       24      5.1
--        twin.ottoq_sim_advance_grid              24      4.4
--        ottoq_eval_en_004_demand_response       944      0.1   <- short-circuits
--        ------------------------------------------------------
--        total                                          197.3
--
--      against the meter's own statement, measured independently in Q3:
--
--        twin.ottoq_sim_compute_charger_load_kw 1,024    195.4
--
--      **197.3 against 195.4 — within one percent.** Two numbers taken from two
--      different pgstat views, by two different accounting rules, on the same
--      pair. Which says something sharper than either alone: after the boot
--      fingerprint, the two largest self-times in this engine's profile are
--      not the proposer and not the grid rule. They are the site load meter,
--      seen from its two busiest callers, and those callers have almost no
--      cost of their own.
--
--      Stated as CONSISTENT WITH rather than PROVEN, because it leans on
--      self_time attribution across untracked SQL functions, which is exactly
--      the mechanism that hid this cost for months. The per-caller split of the
--      1,024 meter calls is NOT determined by these numbers and is not claimed:
--      1,968 calls reach a call site and only 1,024 reach the meter, so roughly
--      half of eval_en_001's invocations return before they get there, and
--      which half is unmeasured.
--
--      What it means for the work: 0223 removes ~109 s of the 195 s. FIX 2 —
--      the Seq Scan in Q8 — is most of the rest. Together they are ~36% of a
--      537 s pair, which is the same size G19 was, in the same place nobody
--      was looking.
SELECT f.funcname,
       f.calls - COALESCE(b.calls,0) AS calls,
       round(((f.total_time - COALESCE(b.total_time,0))/1000)::numeric,1) AS total_s,
       round(((f.self_time  - COALESCE(b.self_time ,0))/1000)::numeric,1) AS self_s
FROM pg_stat_user_functions f
LEFT JOIN public.g19_fn_before b ON b.funcid = f.funcid
WHERE f.funcname IN ('ottoq_l2_propose_stall_assignment','ottoq_eval_en_001_grid_capacity',
                     'ottoq_eval_en_004_demand_response','ottoq_sim_advance_grid',
                     'ottoq_sim_advance_site_energy')
  AND (f.calls - COALESCE(b.calls,0)) > 0
ORDER BY 4 DESC;

-- Q11. WHAT FIX 2 WOULD RISK, surveyed before drafting it rather than after.
--
--      FIX 2 is an index. An index cannot change a result SET, but it can
--      change a PLAN, and a plan change reorders rows — which changes the
--      answer of any query that takes LIMIT without a total ORDER BY. That is
--      not hypothetical here: 0216 was exactly that bug, on the SDR booking
--      pick, and it moved a hash.
--
--      So: which functions touch ocpp_sessions AND take a LIMIT?
--
--        function                              LIMITs  ORDER BYs
--        ottoq_twin_run_list                        8          4
--        ottoq_twin_snapshot                        7          9
--        ottoq_energy_orchestrate                   5          4
--        ottoq_build_decision_frame                 2          4
--        twin.ottoq_sim_auto_charge_assign_tick     2          3
--        ottoq_score_run                            2          3
--        twin.ottoq_sim_advance_site_energy         2          2
--        ottoq_forecast_net_load                    1          3
--        ottoq_run_blackbox                         1          1
--        ottoq_inbound_forecast                     1          1
--        ottoq_tick_invariance_metrics              1          0   <- no ORDER BY at all
--        ottoq_nl_status_brief                      1          0   <- no ORDER BY at all
--
--      Two functions contain a LIMIT and no ORDER BY anywhere in the body.
--      Neither is on the tick or decide path by name — one is a metrics view,
--      one a natural-language brief — but "by name" is not evidence, and
--      counting LIMITs against ORDER BYs across a whole function body does NOT
--      establish which clause belongs to which query. Telling those apart needs
--      a plpgsql parser, which is finding G12, which is still open. So this is
--      a candidate list, not a verdict.
--
--      What it changes about FIX 2: nothing yet, and that is the point of
--      running the survey first. The index is still worth ~87 s; it is now
--      known to be a change whose blast radius includes twelve functions rather
--      than one, and the migration that makes it will have to say so and let a
--      round judge it. Along with an assertion FIX 2 can actually carry: run
--      the meter's own probes twice in the migration, once with enable_indexscan
--      and enable_bitmapscan off, and require the same answer — which proves the
--      index changes nothing for THE QUERY IT IS FOR, and proves nothing about
--      the other eleven.
SELECT n.nspname||'.'||p.proname AS fn,
       (SELECT count(*) FROM regexp_matches(p.prosrc,'limit\s+[0-9]','gi')) AS limit_clauses,
       (SELECT count(*) FROM regexp_matches(p.prosrc,'order\s+by','gi')) AS order_bys
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','twin','ottoq')
  AND p.prosrc LIKE '%ocpp_sessions%' AND p.prosrc ~* 'limit\s+[0-9]'
ORDER BY 2 DESC;
