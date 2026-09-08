-- migration-version: PENDING
-- migration-name:    the_approach_band_scans_every_run_to_answer_about_one
--
-- G29. `public.ottoq_approach_band` resolves three policy parameters for EVERY
-- sim run that has ever existed, to obtain three constants for the one run being
-- executed. One word fixes it.
--
-- THE FINDING (db/checks/0144, measured by r28_g at track_functions='all'):
--
--   ottoq_policy_get   4,894,867 calls   199,648 ms self   in ONE 12-tick pair
--
-- The pair took 330 s, so that is 60.5% of its entire wall clock in one function,
-- and 85.96% of all function calls made. The caller is not among the 64 in
-- db/evidence/policy_get_static_census.md -- all of them at their theoretical
-- maximum sum to 42,461, which is 115x short. It is this view.
--
-- WHY IT COSTS WHAT IT COSTS. The CTE reads `FROM ottoq_sim_runs rr WHERE
-- rr.depot_id IS NOT NULL` with no run scope, and is declared MATERIALIZED --
-- which is precisely the keyword that forbids the planner pushing a predicate
-- into it. The only real consumer, ottoq_approach_zone, already asks for a single
-- row by both keys:
--
--   FROM ottoq_approach_band b
--    WHERE b.vehicle_id = p_vehicle_id AND b.sim_run_id = p_sim_run_id
--    LIMIT 1
--
-- so the run scope is available and simply cannot reach the scan.
--
-- MEASURED, on the live database, on a REPRESENTATIVE key (see the trap below):
--
--   | plan                     | rows scanned | buffers | exec time  |
--   |--------------------------|--------------|---------|------------|
--   | AS MATERIALIZED (live)   |          807 |  22,048 | 103.475 ms |
--   | AS NOT MATERIALIZED      |            1 |      25 |   0.756 ms |
--
--   137x faster. 882x fewer buffers. The plan changes from
--     Seq Scan on ottoq_sim_runs rr (rows=807, 806 removed by filter)
--   to
--     Index Scan using ottoq_sim_runs_pkey (rows=1)
--
-- THE MEASUREMENT TRAP, RECORDED BECAUSE I WALKED INTO IT. The first EXPLAIN used
-- a key obtained by `SELECT ... FROM ottoq_approach_band LIMIT 1`, which returns
-- whatever the CTE emits FIRST. That key cost 3 rows and 2.5 ms and would have
-- said there was no problem at all. A CTE is filled lazily into a tuplestore, so
-- an outer LIMIT lets it stop early -- the cost is proportional to the run's
-- POSITION in physical scan order, not to the row count. A certification arm's
-- run is created fresh and therefore sits at the END: the run measured above has
-- 806 rows before it. Always measure this view with a recently created run.
--
-- CORRECTNESS, PROVEN RATHER THAN ARGUED. For one run across all 120 of its
-- vehicle rows, all 12 semantic output columns, compared BOTH directions:
--
--   live_rows 120 | cand_rows 120 | in_live_not_cand 0 | in_cand_not_live 0
--
-- Set-equal. This is expected structurally -- the CTE computes per-run constants,
-- and filtering to one run yields the same constants for that run -- but
-- "expected structurally" is not evidence and the EXCEPT is.
--
-- WHAT THIS CHANGES ABOUT THE VIEW'S CONTRACT, stated because it is a real
-- difference and not only an optimisation. Under MATERIALIZED the three
-- ottoq_policy_get calls happen ONCE PER RUN. Inlined, they become part of the
-- surrounding expression and are evaluated where used. For the current consumer,
-- which filters to one run and one vehicle, that is 3 calls instead of 2,493. For
-- a hypothetical consumer that scans the view UNFILTERED, inlining could evaluate
-- them per output row rather than per run, which would be worse. There is no such
-- consumer today -- ottoq_approach_zone filters by both keys, and
-- ottoq_readmit_resumed_visits mentions the view only inside a comment -- but any
-- future unfiltered consumer must re-measure this.
--
-- NOT CLAIMED: that this explains round 28's 24t:12t cost ratio moving from 1.53
-- to 2.34-2.59. It is the right shape, but ottoq_sim_runs grew only ~4% between
-- those rounds. db/checks/0144 declines to explain the ratio and so does this.
--
-- forces_recert: FALSE -- the output is provably identical, so no canon can move.
-- A recertification round runs anyway and the canons are checked, because
-- "provably identical on one run" is not "provably identical on every scenario".

-- (no explicit BEGIN/COMMIT: apply_migration supplies the transaction,
--  matching 0226-0228. The whole file is therefore one atomic unit.)

-- ---------------------------------------------------------------------------
-- P-  NEVER APPLY WHILE A CERTIFICATION PAIR IS IN FLIGHT.
--     pg_stat_activity is the ONLY authority. ottoq_sim_runs cannot see one
--     (both arms are one transaction) and cron.job_run_details reports an
--     in-flight two-statement job as 'succeeded' in ~1 s -- observed twice on
--     2026-09-08 during round 28, on columns e and f.
-- ---------------------------------------------------------------------------
DO $P$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid()
     AND state = 'active' AND query LIKE '%ottoq_determinism_pair%';
  IF n > 0 THEN
    RAISE EXCEPTION 'P- REFUSED: % certification pair(s) in flight', n;
  END IF;
END $P$;

-- ---------------------------------------------------------------------------
-- P0  The object is the view this migration was written against.
-- ---------------------------------------------------------------------------
DO $P0$
DECLARE k "char";
BEGIN
  SELECT relkind INTO k FROM pg_class WHERE oid = 'public.ottoq_approach_band'::regclass;
  IF k IS DISTINCT FROM 'v' THEN
    RAISE EXCEPTION 'P0 REFUSED: ottoq_approach_band has relkind %, expected v', k;
  END IF;
END $P0$;

-- ---------------------------------------------------------------------------
-- P1  The body is byte-for-byte what was measured. If anyone changed this view
--     since 2026-09-08 19:2x UTC, every number above is about a different object.
-- ---------------------------------------------------------------------------
DO $P1$
DECLARE h text; n int;
BEGIN
  h := md5(pg_get_viewdef('public.ottoq_approach_band'::regclass, true));
  IF h <> 'b310756eb984fa60a2b5daaf8b42537a' THEN
    RAISE EXCEPTION 'P1 REFUSED: viewdef md5 is %, pinned b310756eb984fa60a2b5daaf8b42537a', h;
  END IF;
  n := (length(pg_get_viewdef('public.ottoq_approach_band'::regclass, true))
        - length(replace(pg_get_viewdef('public.ottoq_approach_band'::regclass, true),'AS MATERIALIZED','')))
       / length('AS MATERIALIZED');
  IF n <> 1 THEN
    RAISE EXCEPTION 'P1 REFUSED: expected exactly 1 "AS MATERIALIZED", found %', n;
  END IF;
END $P1$;

-- ---------------------------------------------------------------------------
-- THE CHANGE. Catalog-derived, single anchored substitution -- the body is read
-- from pg_get_viewdef and one token is replaced, so no part of 5,493 characters
-- is retyped and no transcription error is possible. CREATE OR REPLACE (not
-- DROP+CREATE) because the column list is unchanged, which preserves every
-- dependent object and every grant.
-- ---------------------------------------------------------------------------
DO $CHG$
DECLARE old_body text; new_body text;
BEGIN
  old_body := pg_get_viewdef('public.ottoq_approach_band'::regclass, true);
  new_body := replace(old_body, 'AS MATERIALIZED', 'AS NOT MATERIALIZED');

  IF length(new_body) - length(old_body) <> 4 THEN
    RAISE EXCEPTION 'CHG REFUSED: substitution changed % characters, expected exactly 4 ("NOT ")',
                    length(new_body) - length(old_body);
  END IF;

  EXECUTE 'CREATE OR REPLACE VIEW public.ottoq_approach_band AS ' || new_body;
END $CHG$;

-- ---------------------------------------------------------------------------
-- A1  The keyword is gone and its replacement is present, exactly once each.
-- ---------------------------------------------------------------------------
DO $A1$
DECLARE body text; n_not int; n_mat int;
BEGIN
  body := pg_get_viewdef('public.ottoq_approach_band'::regclass, true);
  n_not := (length(body) - length(replace(body,'AS NOT MATERIALIZED',''))) / length('AS NOT MATERIALIZED');
  n_mat := (length(body) - length(replace(body,'AS MATERIALIZED',''))) / length('AS MATERIALIZED');
  IF n_not <> 1 THEN RAISE EXCEPTION 'A1 FAILED: % occurrences of AS NOT MATERIALIZED, expected 1', n_not; END IF;
  -- 'AS MATERIALIZED' is a substring of 'AS NOT MATERIALIZED'? No: "AS NOT MAT..."
  -- does not contain "AS MAT...". So this must now be zero.
  IF n_mat <> 0 THEN RAISE EXCEPTION 'A1 FAILED: % bare AS MATERIALIZED remain, expected 0', n_mat; END IF;
END $A1$;

-- ---------------------------------------------------------------------------
-- A2  The column list is untouched -- name, position and type. A view feeding
--     the decide path must not change shape.
-- ---------------------------------------------------------------------------
DO $A2$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_approach_band';
  IF n <> 20 THEN RAISE EXCEPTION 'A2 FAILED: view now has % columns, expected 20', n; END IF;
END $A2$;

-- ---------------------------------------------------------------------------
-- A3  The consumer's query shape no longer sequentially scans ottoq_sim_runs.
--     Asserted on the JSON plan, because the text plan's outermost node is a
--     Limit and is easy to fool. Uses the newest run with a depot, which is
--     where a freshly created certification arm sits -- the representative case,
--     not the favourable one.
-- ---------------------------------------------------------------------------
DO $A3$
DECLARE plan json; v_run uuid; v_veh uuid; n_seq int;   -- json, not jsonb: EXPLAIN (FORMAT JSON) returns json and the cast to jsonb is not implicit in assignment
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE depot_id IS NOT NULL ORDER BY started_at DESC LIMIT 1;
  SELECT id INTO v_veh FROM public.vehicles
   WHERE home_depot_id = (SELECT depot_id FROM public.ottoq_sim_runs WHERE sim_run_id = v_run)
   LIMIT 1;

  EXECUTE format(
    'EXPLAIN (FORMAT JSON, COSTS OFF) SELECT zone FROM public.ottoq_approach_band
      WHERE vehicle_id = %L::uuid AND sim_run_id = %L::uuid LIMIT 1', v_veh, v_run)
    INTO plan;

  SELECT count(*) INTO n_seq
    FROM jsonb_path_query(plan::jsonb, '$.**."Node Type"') nt
   WHERE nt #>> '{}' = 'Seq Scan';

  IF n_seq > 0 THEN
    RAISE EXCEPTION 'A3 FAILED: % Seq Scan node(s) remain in the consumer plan; the predicate did not push into the CTE', n_seq;
  END IF;
END $A3$;

-- ---------------------------------------------------------------------------
-- LINEAGE. forces_recert FALSE: the output is provably identical (EXCEPT both
-- directions, 120 rows, 12 semantic columns), so no verdict atom can move.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'the_approach_band_scans_every_run_to_answer_about_one',
  now(),
  false,
  'G29 / db/checks/0144. ottoq_approach_band''s first CTE was declared MATERIALIZED '
  'and read ottoq_sim_runs with no run scope, resolving three policy parameters for '
  'every run that ever existed -- 4,894,867 ottoq_policy_get calls and 199,648 ms of '
  'self time in one 12-tick pair, 60.5% of the pair. MATERIALIZED is the keyword that '
  'forbids pushing the consumer''s sim_run_id predicate into the CTE. Removing it turns '
  'a 807-row Seq Scan into a 1-row primary-key Index Scan: 103.475 ms -> 0.756 ms, '
  '22,048 -> 25 buffers. forces_recert FALSE because output is set-equal both '
  'directions across 120 rows and 12 columns; a recertification round runs anyway.'
);

