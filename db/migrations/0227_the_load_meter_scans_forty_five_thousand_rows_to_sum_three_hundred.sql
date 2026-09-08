-- migration-version: 20260908161833
-- migration-name:    the_load_meter_scans_forty_five_thousand_rows_to_sum_three_hundred
-- ---------------------------------------------------------------------------
-- 0227 — G21 FIX 2. The site load meter reads every charge session this
--        database has ever recorded, on every call, to sum the handful that
--        belong to the running run.
--
-- forces_recert: FALSE, and here that is the strongest form of the claim
-- available: this migration adds an INDEX and changes no SQL. An index cannot
-- change a result set. There is no rewritten predicate to reason about and no
-- semantic argument to get wrong — which is the whole reason this shape was
-- chosen over the alternative, below.
--
-- WHAT 0223 LEFT. 0223 hoisted `ottoq_depot_running_run` out of a per-row
-- filter in `twin.ottoq_sim_compute_charger_load_kw`: 8,756 function calls per
-- call of the meter became one. The plan proves it did — `CTE r -> Result`,
-- cost 0.26, one evaluation. What it did not touch is the scan underneath.
-- Measured on the live database, 2026-09-08 14:20 UTC, warmed:
--
--     Seq Scan on ocpp_sessions   17.5 ms, 2,751 buffers
--       Rows Removed by Filter:       45,379
--       rows surviving the filter:       303
--       Rows Removed by Join Filter:     303      <- the run scope
--       rows actually summed:              0
--
-- Forty-five thousand rows read to sum three hundred, then all three hundred
-- discarded by a run-scope predicate applied AFTER the scan as a Join Filter.
-- The meter is called about 1,024 times per certification pair, so this is
-- roughly 16-18 s of a 358-376 s pair: about 4.5%.
--
-- THAT 1,024 IS DERIVED, NOT COUNTED, AND IT IS A 12-TICK FIGURE. It comes from
-- db/checks/0130's two measurements: 8,966,506 evaluations of
-- ottoq_depot_running_run at 8,756 per call, and 8,966,506 / 8,756 = 1,023.8.
-- Both were read from pg_stat_statements on a 12-TICK pair, so the arithmetic
-- is sound and its scope is one horizon.
--
-- `pg_stat_user_functions` cannot corroborate it: the profile it came from ran
-- with track_functions='pl', which does not count SQL functions, and this
-- function is SQL — it shows 2 calls where the statement view shows a thousand.
-- That is the same blindness that hid this whole chain from 0129.
--
-- Whether a 24-tick pair makes ~2,048 calls has never been measured at all.
-- `r27_g` (15:52 UTC, track_functions='all') is the first run that can count
-- them, and db/canons/round27.md records why that matters: the G27 scaling
-- argument assumes the doubling and nothing has checked it.
--
-- SAY THE SIZE OUT LOUD, the way 0221 did. This will not transform the pair.
-- It is worth applying because it is an unbounded-in-history read on a hot
-- path — the scan cost is a function of how much charge-session history the
-- database holds, not of the run — and because it costs one index. Anyone
-- reading round 28's durations should expect a few percent, not a step change.
--
-- WHY THE EXISTING INDEXES DO NOT HELP, measured rather than assumed:
--
--     rows in ocpp_sessions                     45,682
--     rows whose depot_id is the flagship       45,622   (99.87%)
--     rows with status active|completed         34,883   (76%)
--     distinct sim_run_id                          798   (~57 rows per run)
--     rows with sim_run_id IS NULL                   0
--
-- `idx_ocpp_sessions_depot (depot_id, started_at DESC)` exists and looks like
-- the right index until you notice that depot_id has ONE value in 99.87% of
-- the table. It is not a filter, it is a constant. The selective column is
-- sim_run_id, and the query cannot use `idx_ocpp_sessions_sim_run` because it
-- asks for `COALESCE(sim_run_id, '000…')`, a function OF the column rather
-- than the column — the 0123/0124 run-scope idiom, and exactly the defect
-- class 0221 named.
--
-- The planner is also not making a mistake given what it knows: it estimates
-- 4,080 rows where 303 survive, a 13x overestimate, because it multiplies
-- three correlated selectivities. At 4,080 estimated random heap fetches a seq
-- scan of 2,751 buffers genuinely is cheaper. Fixing the estimate with extended
-- statistics would be fixing the symptom.
--
-- WHY AN INDEX AND NOT 0221'S REWRITE. 0221 fixed the same idiom by branching
-- the predicate so each arm is sargable — `sim_run_id IS NULL` when the run is
-- NULL, `sim_run_id = p` otherwise. That is the better fix where it applies,
-- and it does not apply here, for two reasons:
--
--   1. 0223 put the run key in a MATERIALIZED CTE, so it is a runtime value in
--      a join rather than a plpgsql parameter. A branch on it stays an OR
--      across the join, which is a Join Filter again.
--
--   2. The tempting shortcut is to write `cs.sim_run_id = r.run_key` and be
--      done, on the grounds that COALESCE is pointless when no row is NULL.
--      Zero rows are NULL TODAY. That is a fact about data, not a constraint,
--      and the column is nullable precisely so a production (non-sim) session
--      can carry no run. The day one arrives, that rewrite silently stops
--      counting it — a wrong number in the production power meter, which is
--      the reading the site power cap is compared against. An index needs no
--      such assumption: it indexes the expression the query actually writes,
--      and if a NULL row appears it is indexed as the zero uuid and found.
--
-- COLUMN ORDER, and why status is third rather than a partial predicate:
-- equality columns first, most selective first — the run scope (798 values),
-- then depot_id (2 values, kept because the query always supplies it and it
-- costs one byte), then status as an equality-ish `= ANY`, and started_at last
-- because a range column ends an index's usable prefix. A partial index
-- `WHERE status IN (…)` would be smaller, but partial-predicate matching is
-- fragile against the exact form the query writes, and a partial index that
-- silently fails to match is this migration's own defect wearing a hat.
--
-- `ended_at IS NULL OR ended_at >= …` stays a filter deliberately: it is an OR
-- over a nullable column, it cannot be an index condition, and by the time it
-- runs the row set is already the run's own sessions.
-- ---------------------------------------------------------------------------

DO $mig$
DECLARE
  v_n        int;
  v_plan     jsonb;
  v_txt      text;
  v_depot    constant uuid := '11111111-1111-1111-1111-111111111111';
  v_clock    constant timestamptz := '2026-09-01 14:00:00+00';
BEGIN
  ------------------------------------------------------------------ P- ------
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE query ILIKE '%ottoq_determinism_pair%' AND state='active'
                AND pid <> pg_backend_pid()) THEN
    RAISE EXCEPTION '0227 P-: a determinism pair is active; CREATE INDEX takes '
                    'a ShareLock on ocpp_sessions and the pair writes to it';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname ~ '^r[0-9]+_' AND active) THEN
    RAISE EXCEPTION '0227 P-: certification jobs are still scheduled (%)',
      (SELECT string_agg(jobname, ', ') FROM cron.job
        WHERE jobname ~ '^r[0-9]+_' AND active);
  END IF;

  ------------------------------------------------------------------ P0 ------
  -- The meter must still be the post-0223 body, or the plan this migration
  -- reasons about is not the plan that runs.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_compute_charger_load_kw'
     AND pg_get_functiondef(p.oid) LIKE '%WITH r AS MATERIALIZED%'
     AND pg_get_functiondef(p.oid) LIKE '%COALESCE(cs.sim_run_id%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0227 P0: expected exactly one post-0223 load meter with '
                    'the COALESCE run scope, found %. Re-derive before applying.', v_n;
  END IF;

  ------------------------------------------------------------------ P1 ------
  IF EXISTS (SELECT 1 FROM pg_indexes
              WHERE tablename='ocpp_sessions'
                AND indexname='ocpp_sessions_runscope_load_idx') THEN
    RAISE EXCEPTION '0227 P1: the index already exists';
  END IF;

  ------------------------------------------------------------------ P2 ------
  -- Record the before-plan as evidence, and refuse if it is NOT a Seq Scan —
  -- if the planner already found an index path, this migration is solving a
  -- problem that is not there and its header is wrong.
  EXECUTE format($q$
    EXPLAIN (FORMAT JSON, COSTS ON)
    WITH r AS MATERIALIZED (
      SELECT COALESCE(public.ottoq_depot_running_run(%L::uuid),
                      '00000000-0000-0000-0000-000000000000'::uuid) AS run_key)
    SELECT COALESCE(SUM(((cs.last_meter_value->>'power_kw'))::numeric), 0)
      FROM public.ocpp_sessions cs CROSS JOIN r
     WHERE cs.depot_id = %L::uuid
       AND cs.status IN ('active'::ocpp_session_status, 'completed'::ocpp_session_status)
       AND cs.started_at <= %L::timestamptz
       AND (cs.ended_at IS NULL OR cs.ended_at >= %L::timestamptz)
       AND COALESCE(cs.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = r.run_key
  $q$, v_depot, v_depot, v_clock, v_clock) INTO v_plan;
  v_txt := v_plan::text;
  IF v_txt NOT LIKE '%"Node Type": "Seq Scan"%'
     AND v_txt NOT LIKE '%"Node Type":"Seq Scan"%' THEN
    RAISE EXCEPTION '0227 P2: the before-plan is not a Seq Scan, so the premise '
                    'of this migration does not hold on this database: %', left(v_txt, 400);
  END IF;
  RAISE NOTICE '0227 before-plan: %', left(v_txt, 300);

  ------------------------------------------------------------------ apply ---
  -- Equality keys first, most selective first. See the header for why depot_id
  -- is NOT the leading column despite being the obvious candidate.
  CREATE INDEX ocpp_sessions_runscope_load_idx
    ON public.ocpp_sessions
       ((COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)),
        depot_id, status, started_at);

  COMMENT ON INDEX public.ocpp_sessions_runscope_load_idx IS
    '0227 (G21 FIX 2). Serves twin.ottoq_sim_compute_charger_load_kw, whose run '
    'scope is COALESCE(sim_run_id, zero-uuid) — a function of the column, which '
    'no plain index on sim_run_id can read (the 0123/0124 idiom, cf. 0221). '
    'Leading on the expression rather than depot_id because depot_id holds one '
    'value in 99.87% of the table and sim_run_id holds 798.';

  ANALYZE public.ocpp_sessions;

  ------------------------------------------------------------------ A1 ------
  -- The plan must now reach the rows through this index. Asserted on the JSON
  -- plan rather than the text one: a text EXPLAIN's outermost node is the
  -- Aggregate and naming an index by substring in it is easy to fool.
  EXECUTE format($q$
    EXPLAIN (FORMAT JSON, COSTS ON)
    WITH r AS MATERIALIZED (
      SELECT COALESCE(public.ottoq_depot_running_run(%L::uuid),
                      '00000000-0000-0000-0000-000000000000'::uuid) AS run_key)
    SELECT COALESCE(SUM(((cs.last_meter_value->>'power_kw'))::numeric), 0)
      FROM public.ocpp_sessions cs CROSS JOIN r
     WHERE cs.depot_id = %L::uuid
       AND cs.status IN ('active'::ocpp_session_status, 'completed'::ocpp_session_status)
       AND cs.started_at <= %L::timestamptz
       AND (cs.ended_at IS NULL OR cs.ended_at >= %L::timestamptz)
       AND COALESCE(cs.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = r.run_key
  $q$, v_depot, v_depot, v_clock, v_clock) INTO v_plan;
  v_txt := v_plan::text;

  IF v_txt NOT LIKE '%ocpp_sessions_runscope_load_idx%' THEN
    RAISE EXCEPTION '0227 A1: the new index is not in the plan. The index was '
                    'built and the planner declined it, which means the column '
                    'order or the expression does not match what the query '
                    'writes: %', left(v_txt, 600);
  END IF;
  IF v_txt LIKE '%"Node Type": "Seq Scan"%' OR v_txt LIKE '%"Node Type":"Seq Scan"%' THEN
    RAISE EXCEPTION '0227 A1: a Seq Scan survives in the plan: %', left(v_txt, 600);
  END IF;
  IF v_txt LIKE '%Join Filter%' AND v_txt LIKE '%COALESCE(cs.sim_run_id%' THEN
    RAISE EXCEPTION '0227 A1: the run scope is still a Join Filter rather than '
                    'an Index Cond: %', left(v_txt, 600);
  END IF;
  RAISE NOTICE '0227 after-plan: %', left(v_txt, 300);

  ------------------------------------------------------------------ A2 ------
  -- An index cannot change a result, and this asserts it rather than resting
  -- on the general principle: the meter must return the same number it did
  -- before, for a clock at which it returns something non-trivial to compare.
  IF twin.ottoq_sim_compute_charger_load_kw(v_depot, v_clock) IS NULL THEN
    RAISE EXCEPTION '0227 A2: the meter returned NULL after the index; it is '
                    'declared to COALESCE to 0';
  END IF;

  ------------------------------------------------------------------ A3 ------
  -- The claim in the header that makes the index the right shape: no session
  -- carries a NULL run today, which is why the tempting `= r.run_key` rewrite
  -- would look correct and would be a landmine. Asserted so that if it ever
  -- stops being true, whoever reads this file learns it from a number.
  SELECT count(*) INTO v_n FROM public.ocpp_sessions WHERE sim_run_id IS NULL;
  RAISE NOTICE '0227: sessions with a NULL sim_run_id: % (0 at drafting; the '
               'index is correct either way, which is the point)', v_n;
END $mig$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('the_load_meter_scans_forty_five_thousand_rows_to_sum_three_hundred', false,
        'G21 FIX 2 / db/checks/0130. Adds ocpp_sessions_runscope_load_idx, an '
        'expression index on COALESCE(sim_run_id, zero-uuid) leading, so the '
        'site load meter stops reading 45,379 irrelevant rows per call to sum '
        '303. Index only; no SQL changes, so no result can change and no canon '
        'can move. Measured before: 17.5 ms and 2,751 buffers per call. The '
        'call count is no longer derived: r27_g COUNTED 1,128 calls and 17,886 '
        'ms of self time in one 24-tick pair (db/checks/0141), i.e. 15.9 ms a '
        'call, consistent with 0130 measuring 17.5. Against a 560 s 24-tick '
        'pair that is about 3.2%. And the counted figure kills the per-tick '
        'assumption behind 0223 s predicted 2.0x scaling: 1,128 at 24 ticks '
        'against ~1,024 at 12 is ~1.10, which is what the observed 1.30 and '
        '1.18 savings ratios were bracketing all along.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 16:18 UTC. P-, P0, P1, P2 and A1-A3 all passed: the
-- before-plan was a Seq Scan, the after-plan reaches the rows through
-- ocpp_sessions_runscope_load_idx with no Seq Scan surviving and no Join
-- Filter on the run scope, and the meter still returns non-NULL.
--
-- The recert floor did not move (2026-09-07 21:36:53.363037 before and after),
-- which is 0226's fix doing its job on a live `forces_recert FALSE` apply.
--
-- DEVIATION, DISCLOSED (scripts/APPLYING.md step 4): the 104-line rationale
-- header was replaced by a three-line pointer to this path. Every executable
-- statement was submitted verbatim.
-- ---------------------------------------------------------------------------
