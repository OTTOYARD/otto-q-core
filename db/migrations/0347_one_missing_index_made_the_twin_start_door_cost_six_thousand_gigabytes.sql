-- migration-version: 20260919163943
-- migration-name:    one_missing_index_made_the_twin_start_door_cost_six_thousand_gigabytes
--
-- 0347  THE PURGE IS NOT BLOCKED ANY MORE. IT IS QUADRATIC. ONE UNINDEXED
--       FOREIGN-KEY CHILD COLUMN TURNS ONE TABLE'S PURGE INTO 61 MINUTES.
--
-- 0344 removed the FK that made ottoq_purge_prior_runs raise. 0345 gave step (4)
-- a real dependency order. Both were necessary; neither started a run. Driven
-- server-side through pg_cron so no client timeout could mask the outcome:
--
--   cron jobid 727, 2026-09-19 16:01:00 UTC, ran 16m48s, did not finish:
--   ERROR: canceling statement due to user request
--   CONTEXT: SQL statement "SELECT 1 FROM ONLY "public"."ottoq_ops_approvals" x
--            WHERE $1 OPERATOR(pg_catalog.=) "visit_id" FOR KEY SHARE OF x"
--            SQL statement "DELETE FROM public.ottoq_visit_needs
--                           WHERE sim_run_id = ANY($1)"
--            PL/pgSQL function ottoq_purge_prior_runs(uuid) line 93
--            PL/pgSQL function ottoq_start_demo_run(...) line 47
--
-- Read that context inside out. It is not an error in the purge. It is the
-- referential-integrity trigger Postgres fires for EVERY parent row deleted,
-- and it is the plan for that trigger that is wrong.
--
-- ── THE MEASUREMENT ─────────────────────────────────────────────────────────
--
-- public.ottoq_ops_approvals has three indexes -- pkey(approval_id),
-- (depot_id,status,approval_type), (vehicle_id,created_at DESC) -- and NONE on
-- visit_id, which is the referencing column of
-- ottoq_ops_approvals_visit_id_fkey -> public.ottoq_visit_needs. So the FK
-- trigger's probe has no access path:
--
--   EXPLAIN (ANALYZE, BUFFERS)
--   SELECT 1 FROM ONLY public.ottoq_ops_approvals x WHERE $1 = x.visit_id;
--
--   Seq Scan on ottoq_ops_approvals x  (cost=0.00..7348.44 rows=1)
--                                      (actual time=30.362..30.362 rows=0)
--     Rows Removed by Filter: 59229
--     Buffers: shared hit=6604
--   Execution Time: 30.447 ms
--
-- 30 ms, warm, per deleted parent row. ottoq_visit_needs holds 122,734
-- run-scoped rows. 122,734 x 30.4 ms = 3,732 s = 62 minutes, for ONE of the
-- purge's engine tables, and the purge is synchronous inside the start path.
--
-- The projection is not a model; job 727 is the experiment. In 16m48s of FK
-- probing it had cleared on the order of 33,000 rows -- 1,008 s / 30.4 ms =
-- 33,158 -- which is 27% of 122,734. Extrapolated, 62 minutes. The arithmetic
-- and the observation agree to within the noise of a single cron run.
--
-- Worst case over the whole purge path, parent rows at risk x child relation
-- size, restricted to FKs whose referencing column set has no leading index:
--
--   parent             rows     unindexed child        size    worst-case scan
--   ottoq_visit_needs  122,734  ottoq_ops_approvals    52 MB   6,184 GB
--   ottoq_sim_runs       1,245  ottoq_ops_approvals    52 MB      63 GB
--
-- No other engine-class table on the purge path has an unindexed FK child.
-- (`vehicles` does -- ottoq_stall_bookings.vehicle_id, 398 MB -- but vehicles is
-- registered class 'stamp', which the purge UPDATEs to NULL and never DELETEs,
-- so those 167 GB are not on this path. Left unfixed deliberately: it is not
-- this migration's defect and an index there is a separate judgement.)
--
-- ── WHY THIS WAS INVISIBLE ──────────────────────────────────────────────────
--
-- Nothing reports it. The purge does not raise, the plan is not logged, and
-- 30 ms is a perfectly healthy number for a single query. The defect only
-- exists multiplied by a row count that lives in a different table, and it
-- only became load-bearing when the purge started actually reaching that table
-- -- which 0344 and 0345 are what made possible. Each fix uncovered the next.
-- Third in that chain, and this one is the arithmetic rather than a constraint.
--
-- ── WHAT THIS MIGRATION DOES, AND WHAT IT DELIBERATELY DOES NOT ─────────────
--
-- DOES: two btree indexes on ottoq_ops_approvals, (visit_id) and (sim_run_id),
-- the two referencing columns the purge deletes parents of. Data is untouched;
-- A4 asserts the row count is identical before and after.
--
-- DOES NOT: bound the start-path purge. That is the larger finding and it is
-- filed, not fixed here. Measured today, ottoq_start_demo_run must delete
-- ~6.4 MILLION rows across 35 engine tables over 5,000 rows each -- 2,385,592
-- in ottoq_decisions alone -- synchronously, before it creates a run. Indexing
-- removes the quadratic term; it does not make the start door O(1). A start
-- whose cost grows with all history is a landmine that regrows, and three of
-- those tables (ottoq_recall_decisions, ottoq_events, ottoq_rule_evaluations)
-- also fire a per-row DELETE trigger. The backlog exists BECAUSE the purge has
-- never once succeeded; once it does, steady state is one run's worth. So the
-- order is deliberate: make it finish, observe what finishing costs, then bound
-- it against the real number instead of a guessed one. Tracked as G65.
--
-- ── MEASURED AFTER, same probe, same session ────────────────────────────────
--
--   Index Only Scan using idx_ops_approvals_visit_id on ottoq_ops_approvals x
--     (cost=0.29..2.51 rows=1) (actual time=0.082..0.083 rows=0)
--     Index Cond: (visit_id = '000...'::uuid)
--     Heap Fetches: 0
--     Buffers: shared hit=1 read=1
--   Execution Time: 0.159 ms
--
--   before -> after      factor
--   30.447 ms   0.159 ms   191x        execution
--   7348.44     2.51     2,927x        planner cost
--   6,604       2        3,302x        buffers touched
--
-- So ottoq_visit_needs's share of the purge: 62 minutes -> 19.5 seconds. Heap
-- Fetches: 0 means the FK probe is answered from the index alone and never
-- visits the table, which is the whole point -- the probe asks only whether a
-- referencing row exists.
--
-- A NOTE ON THE 0347 ORDERING INCIDENT, because it cost 21 minutes and would
-- cost them again. The first apply of this file TIMED OUT. Cause: cron jobid
-- 728, an instrumented start probe scheduled `* * * * *` with
-- `SET statement_timeout = 0`, was at that moment 20 minutes into the very
-- unindexed purge this file fixes, holding a lock on ottoq_ops_approvals that
-- CREATE INDEX must have. The index build queued behind the slow thing it
-- exists to make fast. Unschedule the probe FIRST, then cancel its backend,
-- then build. An unbounded server-side retry loop is not a free instrument: it
-- can hold the door shut against its own fix.
--
-- NOT CONCURRENTLY, and that is a choice. CREATE INDEX CONCURRENTLY cannot run
-- inside a transaction block, and every migration here is transactional so a
-- failed assertion rolls the whole file back. ottoq_ops_approvals is 52 MB /
-- 59,236 rows; the build takes about a second under a SHARE lock that blocks
-- writers to this one table for that second. Buying transactional safety with
-- one second of write latency on a 52 MB table is the right trade.

BEGIN;

-- ── P1  PRECONDITION: the defect is present, exactly as described ───────────
DO $$
DECLARE v_plan jsonb; v_node text;
BEGIN
  IF to_regclass('public.ottoq_ops_approvals') IS NULL THEN
    RAISE EXCEPTION '0347 P1: public.ottoq_ops_approvals is absent; this migration has no subject';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ottoq_ops_approvals_visit_id_fkey'
      AND conrelid = 'public.ottoq_ops_approvals'::regclass
      AND confrelid = 'public.ottoq_visit_needs'::regclass
  ) THEN
    RAISE EXCEPTION '0347 P1: the FK this migration indexes for does not exist; refusing to add an index nothing asked for';
  END IF;

  -- The probe the FK trigger runs. Must currently be a Seq Scan, or the premise
  -- of this whole file is stale and it should not be applied unread.
  EXECUTE $q$EXPLAIN (FORMAT JSON) SELECT 1 FROM ONLY public.ottoq_ops_approvals x
              WHERE '00000000-0000-0000-0000-000000000000'::uuid = x.visit_id$q$
    INTO v_plan;
  v_node := v_plan -> 0 -> 'Plan' ->> 'Node Type';
  IF v_node IS DISTINCT FROM 'Seq Scan' THEN
    RAISE EXCEPTION '0347 P1: the FK probe already plans as %, not Seq Scan -- premise stale, review before applying', v_node;
  END IF;

  RAISE NOTICE '0347 P1: ok: FK probe plans as Seq Scan over % live rows',
    (SELECT n_live_tup FROM pg_stat_user_tables WHERE relid='public.ottoq_ops_approvals'::regclass);
END $$;

-- Row count before, so A4 can prove an index migration moved no data.
CREATE TEMP TABLE _0347_before ON COMMIT DROP AS
SELECT count(*) AS n FROM public.ottoq_ops_approvals;

-- ── THE FIX ────────────────────────────────────────────────────────────────
-- Referencing column of ottoq_ops_approvals_visit_id_fkey -> ottoq_visit_needs.
-- Without this, deleting one visit_needs row costs a 52 MB scan.
CREATE INDEX IF NOT EXISTS idx_ops_approvals_visit_id
  ON public.ottoq_ops_approvals USING btree (visit_id);

COMMENT ON INDEX public.idx_ops_approvals_visit_id IS
  '0347: referencing column of ottoq_ops_approvals_visit_id_fkey. Exists so the '
  'FK trigger fired by DELETE on ottoq_visit_needs has an access path. Without '
  'it that probe was a 30 ms seq scan per deleted parent row, making '
  'ottoq_purge_prior_runs cost 62 minutes on this one table (cron jobid 727, '
  '2026-09-19). Do not drop without re-reading db/migrations/0347.';

-- Referencing column of fk_ottoq_ops_approvals_sim_run -> ottoq_sim_runs. The
-- purge deletes ottoq_sim_runs rows too (1,245 of them today), so the same
-- trigger runs per run; and the purge's own
-- DELETE FROM ottoq_ops_approvals WHERE sim_run_id = ANY(...) gets a path.
CREATE INDEX IF NOT EXISTS idx_ops_approvals_sim_run_id
  ON public.ottoq_ops_approvals USING btree (sim_run_id);

COMMENT ON INDEX public.idx_ops_approvals_sim_run_id IS
  '0347: referencing column of fk_ottoq_ops_approvals_sim_run. Serves both the '
  'FK trigger fired by DELETE on ottoq_sim_runs and the purge''s own delete of '
  'this table by sim_run_id.';

-- ── A1  the indexes exist and are valid ────────────────────────────────────
DO $$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(want, ', ') INTO v_missing
  FROM (VALUES ('idx_ops_approvals_visit_id'), ('idx_ops_approvals_sim_run_id')) w(want)
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = w.want AND i.indisvalid AND i.indisready
      AND i.indrelid = 'public.ottoq_ops_approvals'::regclass
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0347 A1: index missing or not valid: %', v_missing;
  END IF;
END $$;

-- ── A2  THE POINT OF THE FILE: the FK probe no longer scans the table ──────
-- Asserted on the PLAN, not on a wall clock. A timing assertion inside a
-- migration is the G15 defect class -- it fails on a busy machine and passes on
-- an idle one, and it would be testing the host rather than the schema. The
-- plan is the thing that changed.
DO $$
DECLARE v_plan jsonb; v_node text; v_idx text;
BEGIN
  EXECUTE $q$EXPLAIN (FORMAT JSON) SELECT 1 FROM ONLY public.ottoq_ops_approvals x
              WHERE '00000000-0000-0000-0000-000000000000'::uuid = x.visit_id$q$
    INTO v_plan;
  v_node := v_plan -> 0 -> 'Plan' ->> 'Node Type';
  v_idx  := v_plan -> 0 -> 'Plan' ->> 'Index Name';

  IF v_node = 'Seq Scan' THEN
    RAISE EXCEPTION '0347 A2: the FK probe still plans as a Seq Scan after the index -- the index does not serve the constraint';
  END IF;
  IF v_idx IS DISTINCT FROM 'idx_ops_approvals_visit_id' THEN
    RAISE EXCEPTION '0347 A2: the FK probe plans as % but on index % -- expected idx_ops_approvals_visit_id',
      v_node, COALESCE(v_idx, '<none>');
  END IF;
  RAISE NOTICE '0347 A2: ok: FK probe now plans as % on %', v_node, v_idx;
END $$;

-- ── A3  the purge guard is unchanged: an index is not a registry change ────
DO $$
DECLARE v_bad int;
BEGIN
  SELECT count(*) INTO v_bad
  FROM public.ottoq_check_run_scope_registry() r
  WHERE r.severity = 'blocking';
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0347 A3: run-scope registry reports % blocking defect(s); an index migration must not cause one', v_bad;
  END IF;
END $$;

-- ── A4  no data moved ──────────────────────────────────────────────────────
DO $$
DECLARE v_before bigint; v_after bigint;
BEGIN
  SELECT n INTO v_before FROM _0347_before;
  SELECT count(*) INTO v_after FROM public.ottoq_ops_approvals;
  IF v_before IS DISTINCT FROM v_after THEN
    RAISE EXCEPTION '0347 A4: ottoq_ops_approvals went from % rows to % -- an index migration touched data', v_before, v_after;
  END IF;
  RAISE NOTICE '0347 A4: ok: % rows, unchanged', v_after;
END $$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────
-- forces_recert FALSE, and this is the one classification an index migration
-- must actually argue rather than assume. An index CAN change output: it changes
-- the scan, and a query with an unstable sort or an unordered LIMIT can return a
-- different set of rows because of it. That is the 0220 / G20 defect class.
--
-- So the claim is narrow and checked. A btree index can only serve a query whose
-- predicate or ordering references its LEADING column. The leading columns here
-- are visit_id and sim_run_id. Every routine that reads ottoq_ops_approvals was
-- enumerated over pg_proc (14 of them), and the two on the certified decide path
-- were read line by line:
--
--   ottoq_decide_tick line 115:  AND NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals ap ...)
--       A boolean existence test. Order-independent by construction -- an index
--       can change how fast it is answered, never what it answers.
--
--   ottoq_decide_indepot_approvals lines 23-40:  ... WHERE depot_id = $1
--       AND status='pending' AND approval_type='indepot_reassign'
--       ORDER BY ap.requested_at LIMIT 200
--       Neither visit_id nor sim_run_id appears in the predicate or the sort, so
--       neither new index is a candidate. Confirmed on the plan, which picks the
--       pre-existing idx_ops_approvals_pending(depot_id,status,approval_type)
--       and sorts above it:
--         Limit -> Sort (Sort Key: requested_at)
--               -> Index Scan using idx_ops_approvals_pending
--
-- NOTED WHILE THERE, NOT FIXED HERE, because it is latent rather than live:
-- that ORDER BY requested_at LIMIT 200 is an UNSTABLE sort -- requested_at is
-- not unique, so which of a set of tied rows lands inside the 200 is whatever
-- the scan happened to produce, and each row that lands gets a verdict WRITTEN.
-- It is not reachable today: measured now, one depot has pending rows at all,
-- its maximum is 2, and 0 rows share a requested_at with another. It becomes a
-- real nondeterminism the day a depot carries more than 200 pending
-- indepot_reassign approvals with a tie at the boundary. The fix when it is
-- wanted is a unique tiebreaker -- ORDER BY ap.requested_at, ap.approval_id.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0347_one_missing_index_made_the_twin_start_door_cost_six_thousand_gigabytes', false,
  'Two btree indexes on public.ottoq_ops_approvals -- (visit_id) and (sim_run_id) -- the referencing columns of ottoq_ops_approvals_visit_id_fkey and fk_ottoq_ops_approvals_sim_run. Without the first, the FK trigger Postgres fires for every parent row deleted from ottoq_visit_needs planned as a 30.4 ms seq scan of a 52 MB table, so ottoq_purge_prior_runs cost 62 minutes on that table alone and ottoq_start_demo_run -- which calls it synchronously -- could not complete; cron jobid 727 spent 16m48s inside that probe. Measured after: Index Only Scan, 0.159 ms, 2 buffers (was 6,604). No data changed (A4). forces_recert FALSE is argued not assumed: neither leading column appears in any predicate or ORDER BY of the two certified readers, ottoq_decide_tick reads the table only through an order-independent NOT EXISTS, and ottoq_decide_indepot_approvals'' plan still picks the pre-existing idx_ops_approvals_pending. So no certified query''s result can change.',
  now())
ON CONFLICT(name) DO NOTHING;

COMMIT;
