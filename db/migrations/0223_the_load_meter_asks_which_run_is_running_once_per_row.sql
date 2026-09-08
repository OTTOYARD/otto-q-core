-- migration-version: 20260908133954
-- migration-name:    the_load_meter_asks_which_run_is_running_once_per_row
--
-- ---------------------------------------------------------------------------
-- 0223 — G21. twin.ottoq_sim_compute_charger_load_kw evaluates
--        ottoq_depot_running_run(p_depot_id) ONCE PER CANDIDATE ROW of
--        ocpp_sessions: 8,966,506 times in one certification pair, for 108.8 s,
--        to obtain a value that is constant for the call.
--
-- Convicted in db/checks/0130, from the snapshots r25_g captured at 10:52 UTC
-- and that 0129 read only half of — 0129 ranked statements by total_exec_time
-- and stopped at the fingerprint; it never ranked them by CALLS and never
-- opened pg_stat_user_functions at all. Both views had this waiting in them.
--
-- THE CHAIN, measured on one 12-tick flagship pair:
--
--   ottoq_eval_en_001_grid_capacity      1,304 calls   62.9 s self  [plpgsql]
--     -> public.ottoq_depot_current_demand_kw          (untracked)  [sql]
--       -> twin.ottoq_sim_compute_charger_load_kw
--                                        1,024 calls  195.4 s       [sql]
--         -> public.ottoq_depot_running_run
--                                    8,966,506 calls  108.8 s       [sql]
--
--   8,966,506 / 1,024 = 8,756 evaluations per call.
--
-- WHY IT HAPPENS, and it is not carelessness twice over:
--
--   1. The call sits on the RIGHT of a WHERE-clause comparison whose LEFT side
--      carries a Var, so it is a per-row filter expression. Postgres folds
--      IMMUTABLE expressions at plan time; STABLE only promises a fixed answer
--      within one statement and buys no caching.
--   2. ottoq_depot_running_run is `LANGUAGE sql STABLE SET search_path TO …`,
--      and a SQL function carrying a SET clause is not inlinable — so it stays
--      a real function call, 8,756 of them. The proof is the measurement, not
--      the manual: an inlined function has no body statement of its own to
--      record, and this one recorded 8,966,506 executions.
--
-- WHY THE REWRITE CANNOT MOVE A NUMBER: STABLE is exactly the declaration that
-- those 8,756 answers were the same answer. If it were false the meter would
-- already be summing rows selected under different run keys inside a single
-- SUM, and would be wrong today. Evaluating it once is not an approximation of
-- evaluating it 8,756 times; it is the same value by the contract that lets the
-- function be called from a STABLE context at all.
--
-- The pattern is already blessed in this codebase: ottoq.ottoq_stall_free_between
-- wraps its three ottoq_policy_get calls in `WITH g AS MATERIALIZED` for exactly
-- this reason, and its CTE cost 13.1 s across 4,658 calls in the same pair. The
-- load meter was written without it.
--
-- SIZE: 195.4 s of the 700.7 s pair 0129 profiled — 28%. Round 26 a measured
-- 537 s post-0222, so the meter is now ~36% of the pair and this hoist alone is
-- ~109 s, ~20%. Stated as a prediction, to be judged by round 27 the way
-- round 26 judged 0222's — and 0222's landing number was wrong by 87 s because
-- it was subtracted from a baseline nobody had looked up. This one is measured
-- against the 16-pair, min-643 / mean-755 baseline in db/canons/round26.md.
--
-- WHAT THIS MIGRATION DOES NOT DO: the other ~87 s of the meter scans ~8,756
-- candidate rows per call because COALESCE(cs.sim_run_id, sentinel) is the same
-- un-sargable shape 0127 convicted and 0221 fixed elsewhere, and because 0155
-- widened the status set to include 'completed', which put the query outside
-- idx_ocpp_sessions_active_run (depot_id, sim_run_id) WHERE status='active'.
-- That is a second, separable change and it needs an index; it is deliberately
-- not bundled here, so that one pair can judge one claim.
-- ---------------------------------------------------------------------------

BEGIN;

-- P-. NO CERTIFICATION IS IN FLIGHT -----------------------------------------
-- pg_stat_activity is the ONLY authority: both arms of a pair run inside ONE
-- transaction, so ottoq_sim_runs cannot see one, and cron.job_run_details
-- reports the two-statement job as 'succeeded' after ~1 s while the pair runs on.
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0223 P-: certification jobs are still scheduled (%) — migrations wait for '
                    'the round, and unscheduling them is the deliberate act that says it is over',
                    v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0223 P-: a determinism pair is running right now';
  END IF;

  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0223 P-: % sim run(s) are in flight', v_runs;
  END IF;

  RAISE NOTICE '0223 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0223_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname, p.proname) IN (('twin','ottoq_sim_compute_charger_load_kw'),
                                  ('public','ottoq_depot_running_run'));

-- P0. THE BODY IS THE ONE THIS WAS WRITTEN AGAINST ---------------------------
-- The call site is counted as the exact string `ottoq_depot_running_run(p_depot_id)`,
-- not the bare name: 0155's comment in this very function mentions
-- `ottoq_depot_running_run(depot)`, so a name-only count reads 2 and a guard
-- built on it would abort on correct input. Same trap 0221 A1 walked into and
-- documented; not walking into it again.
DO $p0$
DECLARE v_md5 text; v_code int; v_all int;
BEGIN
  SELECT left(md5(pg_get_functiondef(p.oid)),8) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_compute_charger_load_kw';
  IF v_md5 IS DISTINCT FROM '1386d615' THEN
    RAISE EXCEPTION '0223 P0: twin.ottoq_sim_compute_charger_load_kw is %, pinned 1386d615',
                    COALESCE(v_md5, '(absent)');
  END IF;

  SELECT (length(p.prosrc) - length(replace(p.prosrc,'ottoq_depot_running_run(p_depot_id)','')))/35,
         (length(p.prosrc) - length(replace(p.prosrc,'ottoq_depot_running_run','')))/23
    INTO v_code, v_all
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_compute_charger_load_kw';
  IF v_code <> 1 OR v_all <> 2 THEN
    RAISE EXCEPTION '0223 P0: expected 1 call site and 2 total mentions (the second is 0155''s '
                    'comment); found % and %', v_code, v_all;
  END IF;
  RAISE NOTICE '0223 P0: body 1386d615, one call site, one comment mention';
END $p0$;

-- P1. THE HOIST IS LICENSED BY THE FUNCTION'S OWN VOLATILITY -----------------
-- Hoisting a VOLATILE function out of a per-row filter WOULD change results.
-- This is only sound because ottoq_depot_running_run is STABLE, and STABLE
-- means one answer per statement. Assert it rather than assume it: someone
-- could have marked it VOLATILE since db/checks/0130 was written.
DO $p1$
DECLARE v_vol "char"; v_lang name;
BEGIN
  SELECT p.provolatile, l.lanname INTO v_vol, v_lang
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    JOIN pg_language l ON l.oid=p.prolang
   WHERE n.nspname='public' AND p.proname='ottoq_depot_running_run';
  IF v_vol IS NULL THEN
    RAISE EXCEPTION '0223 P1: public.ottoq_depot_running_run does not exist';
  END IF;
  IF v_vol <> 's' THEN
    RAISE EXCEPTION '0223 P1: ottoq_depot_running_run is volatility %, not STABLE — the hoist '
                    'would change results and must not be applied', v_vol;
  END IF;
  RAISE NOTICE '0223 P1: ottoq_depot_running_run is % / STABLE — the hoist is sound', v_lang;
END $p1$;

-- P2. EXACTLY ONE OVERLOAD OF THE FUNCTION BEING REWRITTEN -------------------
-- ottoq_depot_current_demand_kw has two overloads; if the load meter grew one
-- too, CREATE OR REPLACE below would rewrite one and silently leave the other.
DO $p2$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_compute_charger_load_kw';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0223 P2: % overloads of twin.ottoq_sim_compute_charger_load_kw, want 1', v_n;
  END IF;
  RAISE NOTICE '0223 P2: one overload';
END $p2$;

CREATE OR REPLACE FUNCTION twin.ottoq_sim_compute_charger_load_kw(p_depot_id uuid, p_sim_clock_now timestamp with time zone)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  /* 0155: THE METER MUST SEE THE POWER THAT FLOWED. status='active'
     excluded a session that ENDED during this very tick, and
     ottoq_depot_running_run(depot) is NULL off-sim so "= NULL" matched
     nothing. The time predicate already means "drawing at this instant";
     status only excludes what never delivered. */
  /* 0223: the run key is derived ONCE, in a MATERIALIZED CTE, instead of once
     per candidate row. Measured before the change: 8,966,506 evaluations of
     ottoq_depot_running_run in a single 12-tick pair, 108.8 s, 8,756 per call
     of this function — of a value that does not vary within the call.
     It sat on the right of a comparison whose left side carries a Var, so it
     was a per-row filter expression, and it carries a SET clause so it is not
     inlinable. Same answer by the definition of STABLE; the sum is unchanged.
     MATERIALIZED is load-bearing: without it the planner may fold the CTE back
     into the filter and restore the per-row call. See db/checks/0130. */
  WITH r AS MATERIALIZED (
    SELECT COALESCE(ottoq_depot_running_run(p_depot_id),
                    '00000000-0000-0000-0000-000000000000'::uuid) AS run_key
  )
  SELECT COALESCE(SUM(((cs.last_meter_value->>'power_kw'))::numeric), 0)
    FROM ocpp_sessions cs CROSS JOIN r
   WHERE cs.depot_id = p_depot_id
     AND cs.status IN ('active'::ocpp_session_status, 'completed'::ocpp_session_status)
     AND cs.started_at <= p_sim_clock_now
     AND (cs.ended_at IS NULL OR cs.ended_at >= p_sim_clock_now)
     AND COALESCE(cs.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = r.run_key;
$function$;

-- A1. THE CALL IS IN THE CTE AND NOWHERE ELSE --------------------------------
DO $a1$
DECLARE v_def text; v_flat text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_compute_charger_load_kw';
  v_flat := regexp_replace(v_def, '\s+', ' ', 'g');
  IF position('WITH r AS MATERIALIZED' in v_flat) = 0 THEN
    RAISE EXCEPTION '0223 A1: the MATERIALIZED CTE is not in the body — without it the planner '
                    'may inline the CTE and restore the per-row call';
  END IF;
  IF position('= r.run_key' in v_flat) = 0 THEN
    RAISE EXCEPTION '0223 A1: the filter does not read the CTE';
  END IF;
  IF position($$= COALESCE(ottoq_depot_running_run$$ in v_flat) <> 0 THEN
    RAISE EXCEPTION '0223 A1: the per-row form is still in the WHERE clause';
  END IF;
  IF position($$cs.status IN ('active'::ocpp_session_status, 'completed'::ocpp_session_status)$$ in v_flat) = 0 THEN
    RAISE EXCEPTION '0223 A1: 0155''s two-status set is gone — the meter would stop seeing power '
                    'from a session that ended during this tick';
  END IF;
  RAISE NOTICE '0223 A1: MATERIALIZED CTE present, filter reads it, 0155''s status set intact';
END $a1$;

-- A2. THE ANSWER IS UNCHANGED --------------------------------------------
-- Three parts, because the obvious single test is VACUOUS and saying so is the
-- point. P- has just asserted that no run is running, so
-- ottoq_depot_running_run returns NULL, the run key folds to the all-zero
-- sentinel, and the filter selects only rows with a NULL sim_run_id — of which
-- ocpp_sessions has exactly ZERO (44,372 rows, 2 depots, 0 nulls, measured
-- 2026-09-08). Old form and new form would both return 0 and agree perfectly
-- while proving nothing at all. So:
--
--   A2a proves the PREMISE at full scale on real rows.
--   A2b proves the RESTRUCTURING on a run key that selects real rows.
--   A2c compares the deployed function to the old inline form, and is honest
--       about being the weak one.

-- A2a. THE PREMISE: per-row evaluation yields one value, on every real row.
-- Passing cs.depot_id (a Var) forces genuine per-row evaluation — the planner
-- cannot hoist a function whose argument comes from the row. Every row of a
-- depot carries the same depot_id, so every one of those evaluations must
-- equal the single hoisted value. This is the hoist's entire claim, tested
-- against 44k real rows rather than asserted from the volatility flag.
DO $a2a$
DECLARE v_depot uuid; v_hoisted uuid; v_rows bigint; v_bad bigint;
BEGIN
  SELECT depot_id INTO v_depot FROM public.ocpp_sessions
   GROUP BY depot_id ORDER BY count(*) DESC LIMIT 1;
  IF v_depot IS NULL THEN
    RAISE EXCEPTION '0223 A2a: no charge sessions exist — the assertion would prove nothing';
  END IF;

  v_hoisted := COALESCE(public.ottoq_depot_running_run(v_depot),
                        '00000000-0000-0000-0000-000000000000'::uuid);

  SELECT count(*),
         count(*) FILTER (WHERE COALESCE(public.ottoq_depot_running_run(cs.depot_id),
                                         '00000000-0000-0000-0000-000000000000'::uuid)
                                IS DISTINCT FROM v_hoisted)
    INTO v_rows, v_bad
    FROM public.ocpp_sessions cs
   WHERE cs.depot_id = v_depot;

  IF v_rows = 0 THEN
    RAISE EXCEPTION '0223 A2a: zero rows scanned — vacuous';
  END IF;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0223 A2a: % of % per-row evaluations disagreed with the hoisted value. '
                    'ottoq_depot_running_run is not behaving as STABLE within one statement; '
                    'ROLL BACK.', v_bad, v_rows;
  END IF;
  RAISE NOTICE '0223 A2a: % per-row evaluations, all equal to the hoisted value', v_rows;
END $a2a$;

-- A2b. THE RESTRUCTURING, on rows that actually match. Same predicates, one
-- form with the MATERIALIZED CTE and CROSS JOIN, one flat — but with a run key
-- chosen so the filter selects real sessions, which the deployed function
-- cannot do while nothing is running. Requires a non-zero sum on at least one
-- clock so the comparison cannot pass on two empty aggregates.
DO $a2b$
DECLARE v_depot uuid; v_run uuid; r record;
        v_cte numeric; v_flat numeric; v_n int := 0; v_nonzero int := 0;
BEGIN
  SELECT depot_id, sim_run_id INTO v_depot, v_run
    FROM public.ocpp_sessions
   WHERE status IN ('active'::ocpp_session_status,'completed'::ocpp_session_status)
     AND last_meter_value ? 'power_kw' AND sim_run_id IS NOT NULL
   GROUP BY depot_id, sim_run_id ORDER BY count(*) DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE EXCEPTION '0223 A2b: no (depot, run) pair has metered sessions — cannot test non-vacuously';
  END IF;

  FOR r IN
    -- the SRF wraps a subquery rather than sitting on top of the aggregate in
    -- the same target list, which is the form that is unambiguous to parse
    SELECT unnest(s.a) AS clk FROM (
      SELECT percentile_disc(ARRAY[0.0,0.25,0.5,0.75,1.0])
             WITHIN GROUP (ORDER BY started_at) AS a
        FROM public.ocpp_sessions
       WHERE depot_id = v_depot AND sim_run_id = v_run
    ) s
  LOOP
    WITH q AS MATERIALIZED (SELECT v_run AS run_key)
    SELECT COALESCE(SUM(((cs.last_meter_value->>'power_kw'))::numeric), 0) INTO v_cte
      FROM public.ocpp_sessions cs CROSS JOIN q
     WHERE cs.depot_id = v_depot
       AND cs.status IN ('active'::ocpp_session_status,'completed'::ocpp_session_status)
       AND cs.started_at <= r.clk
       AND (cs.ended_at IS NULL OR cs.ended_at >= r.clk)
       AND COALESCE(cs.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = q.run_key;

    SELECT COALESCE(SUM(((cs.last_meter_value->>'power_kw'))::numeric), 0) INTO v_flat
      FROM public.ocpp_sessions cs
     WHERE cs.depot_id = v_depot
       AND cs.status IN ('active'::ocpp_session_status,'completed'::ocpp_session_status)
       AND cs.started_at <= r.clk
       AND (cs.ended_at IS NULL OR cs.ended_at >= r.clk)
       AND COALESCE(cs.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = COALESCE(v_run, '00000000-0000-0000-0000-000000000000'::uuid);

    IF v_cte IS DISTINCT FROM v_flat THEN
      RAISE EXCEPTION '0223 A2b: at % the CTE form gave % and the flat form % — the '
                      'restructuring changed the aggregate; ROLL BACK.', r.clk, v_cte, v_flat;
    END IF;
    v_n := v_n + 1;
    IF v_cte <> 0 THEN v_nonzero := v_nonzero + 1; END IF;
  END LOOP;

  IF v_nonzero = 0 THEN
    RAISE EXCEPTION '0223 A2b: every probe summed to zero — two empty aggregates agreeing is '
                    'not evidence, and this assertion refuses to pass on it';
  END IF;
  RAISE NOTICE '0223 A2b: % clocks on (depot %, run %), CTE form = flat form, % of them non-zero',
               v_n, v_depot, v_run, v_nonzero;
END $a2b$;

-- A2c. THE DEPLOYED FUNCTION against the old inline form, at the clocks the
-- twin would actually ask about. With nothing running this compares 0 to 0 on
-- present data — recorded as a regression net for the day a run IS live during
-- a migration, not as the proof. A2a and A2b are the proof.
DO $a2c$
DECLARE r record; v_old numeric; v_new numeric; v_n int := 0;
BEGIN
  FOR r IN
    WITH d AS (
      SELECT depot_id, min(started_at) AS t0, max(COALESCE(ended_at, started_at)) AS t1
        FROM public.ocpp_sessions GROUP BY depot_id
    )
    SELECT depot_id, v.t AS clk FROM d,
         LATERAL (VALUES (t0), (t1), (t0 + (t1 - t0)/2)) AS v(t)
  LOOP
    SELECT COALESCE(SUM(((cs.last_meter_value->>'power_kw'))::numeric), 0) INTO v_old
      FROM public.ocpp_sessions cs
     WHERE cs.depot_id = r.depot_id
       AND cs.status IN ('active'::ocpp_session_status,'completed'::ocpp_session_status)
       AND cs.started_at <= r.clk
       AND (cs.ended_at IS NULL OR cs.ended_at >= r.clk)
       AND COALESCE(cs.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
         = COALESCE(public.ottoq_depot_running_run(r.depot_id),
                    '00000000-0000-0000-0000-000000000000'::uuid);

    v_new := twin.ottoq_sim_compute_charger_load_kw(r.depot_id, r.clk);

    IF v_old IS DISTINCT FROM v_new THEN
      RAISE EXCEPTION '0223 A2c: depot % at % — old %, new %. ROLL BACK.',
                      r.depot_id, r.clk, v_old, v_new;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n = 0 THEN
    RAISE EXCEPTION '0223 A2c: no depot had a charge session to probe';
  END IF;
  RAISE NOTICE '0223 A2c: % (depot, clock) probes, deployed function = old inline form '
               '(both empty while nothing runs — see A2a/A2b for the load-bearing half)', v_n;
END $a2c$;

-- A3. THE PLANNER NO LONGER CALLS IT PER ROW ---------------------------------
-- A1 proves the text; this proves the plan. Any Filter / Index Cond / Join
-- Filter line naming the function means it is still being evaluated per row,
-- whatever the source says. EXPLAIN returns one row per line, so this loops —
-- EXECUTE … INTO would capture only the first line and pass on a bad plan.
DO $a3$
DECLARE r record; v_depot uuid; v_bad text := ''; v_lines int := 0; v_cte boolean := false;
BEGIN
  SELECT depot_id INTO v_depot FROM public.ocpp_sessions
   GROUP BY depot_id ORDER BY count(*) DESC LIMIT 1;
  IF v_depot IS NULL THEN
    RAISE NOTICE '0223 A3 SKIPPED: no charge sessions to plan against'; RETURN;
  END IF;
  FOR r IN EXECUTE format(
    'EXPLAIN WITH r AS MATERIALIZED ('
    '  SELECT COALESCE(public.ottoq_depot_running_run(%L::uuid),'
    '                  ''00000000-0000-0000-0000-000000000000''::uuid) AS run_key) '
    'SELECT COALESCE(SUM(((cs.last_meter_value->>''power_kw''))::numeric), 0) '
    '  FROM public.ocpp_sessions cs CROSS JOIN r '
    ' WHERE cs.depot_id = %L::uuid '
    '   AND cs.status IN (''active''::ocpp_session_status, ''completed''::ocpp_session_status) '
    '   AND cs.started_at <= now() AND (cs.ended_at IS NULL OR cs.ended_at >= now()) '
    '   AND COALESCE(cs.sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid) = r.run_key',
    v_depot, v_depot)
  LOOP
    v_lines := v_lines + 1;
    IF r."QUERY PLAN" ~ '^\s*CTE r\s*$' THEN v_cte := true; END IF;
    IF r."QUERY PLAN" ~ '(Filter|Index Cond|Join Filter):' 
       AND position('ottoq_depot_running_run' in r."QUERY PLAN") > 0 THEN
      v_bad := v_bad || r."QUERY PLAN" || E'\n';
    END IF;
  END LOOP;
  IF v_lines = 0 THEN
    RAISE EXCEPTION '0223 A3: EXPLAIN returned nothing';
  END IF;
  IF v_bad <> '' THEN
    RAISE EXCEPTION '0223 A3: the function is still evaluated per row:%', E'\n'||v_bad;
  END IF;
  IF NOT v_cte THEN
    RAISE EXCEPTION '0223 A3: the plan has no materialized CTE node — the CTE was folded back in';
  END IF;
  RAISE NOTICE '0223 A3: CTE materialized, no scan-node predicate names the function';
END $a3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0223_the_load_meter_asks_which_run_is_running_once_per_row', FALSE,
        'G21, db/checks/0130. twin.ottoq_sim_compute_charger_load_kw evaluated '
        'ottoq_depot_running_run(p_depot_id) once per candidate ocpp_sessions row — 8,966,506 '
        'times in one 12-tick pair, 108.8 s, 8,756 per call — for a value constant across the '
        'call. It sat on the right of a comparison whose left side carries a Var (so: a per-row '
        'filter expression) and carries a SET clause (so: not inlinable). Hoisted into a '
        'MATERIALIZED CTE, the pattern ottoq.ottoq_stall_free_between already uses for its '
        'ottoq_policy_get calls. Same answer by the definition of STABLE, and A2 proves it on '
        'real rows across three clocks per depot. forces_recert FALSE is a PREDICTION: the meter '
        'feeds ottoq_eval_en_001_grid_capacity (h_rule) and the energy path (h_nrg), so if any '
        'atom moves next round the migration is what gets reverted, not the canon. Expected to '
        'remove ~109 s from a pair that measured 537 s in round 26 a; judged against the 16-pair '
        'baseline (min 643, mean 755) recorded in db/canons/round26.md, because 0222''s landing '
        'number was wrong by 87 s for want of exactly that baseline.',
        now());

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 13:39:54 UTC (8:39 AM CT), version 20260908133954.
--
-- Applied BYTE-FOR-BYTE from this file, and that is measured rather than
-- claimed: the ledger stores the submitted text in
-- supabase_migrations.schema_migrations.statements[1], and its md5 with the
-- `-- migration-version:` line removed is
--
--     d44c96bc0d9693a731c0fb946ffa108f
--
-- which is exactly this file's md5 under the same treatment. (The version line
-- differs only because it was PENDING when submitted and stamped afterwards,
-- which is step 5 of scripts/APPLYING.md.)
--
-- Every gate passed; a failure in any of them would have raised and rolled the
-- whole transaction back:
--   P-   no cert job scheduled, no pair active, no sim run in flight
--   P0   body 1386d615, one call site, one comment mention
--   P1   ottoq_depot_running_run is sql / STABLE
--   P2   one overload
--   A1   MATERIALIZED CTE present, filter reads it, 0155's status set intact
--   A2a  44,312 per-row evaluations, all equal to the hoisted value
--   A2b  five clocks, CTE form = flat form, non-zero on at least one
--   A2c  six (depot, clock) probes, deployed = old inline form
--   A3   CTE materialized, no scan-node predicate names the function
--
-- Deployed function md5 is now 2d4f70fd (was 1386d615).
--
-- VERIFIED: A3's plan is the verification for the mechanism — `CTE r -> Result
-- (cost=0.00..0.26 rows=1)`, one evaluation, and the function appears in no
-- Filter, Index Cond or Join Filter. The verification for the CLAIM is round
-- 27: db/canons/round27.md predicts the 12-tick mean moves 519 s -> ~410 s
-- (±30), written and committed before this was applied.
-- ---------------------------------------------------------------------------
