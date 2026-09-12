-- migration-version: 20260909134546
-- migration-name: 0250_the_engine_class_is_not_a_delete_list_and_it_holds_the_moat
-- ===========================================================================
-- 0250  THE engine CLASS IS NOT A DELETE LIST, AND IT HOLDS THE MOAT
-- ===========================================================================
-- probe:          db/checks/0165
-- forces_recert:  FALSE
--
-- WHAT 0247/0249 GOT WRONG, MEASURED
--
-- The purge loops ottoq_run_scope_registry WHERE class='engine' -- 47 tables --
-- and deletes every row belonging to a run older than the keep window. Measured
-- 2026-09-09 13:50 UTC against the live doomed set of 729 runs, that loop would
-- have deleted:
--
--   cuopt_invocation_log           14,746 of  17,492   84.3%
--   ottoq_service_detail_records  168,398 of 220,378   76.4%
--   space_conflict_ledger         248,849 of 265,074   93.9%
--   site_energy_snapshots          11,540
--   ottoq_recall_decisions              0 of  66,294   (0% TODAY -- the ledger is
--                                                       two days old; tomorrow it
--                                                       is not zero)
--
-- Each of those is named in CLAUDE.md as something that must not be lost:
--
--   * Rule 6: "cuOpt claims must be ledger-backed ... cuopt_invocation_log exists
--     precisely to make 'never invoked' distinguishable from 'invoked N times,
--     abstained M.'" Deleting 84% of it destroys the only thing that sentence
--     can be derived from.
--   * 2.6, the strategic instruction of the entire build: "Every completed
--     operation terminates in an SDR, structurally." 76% of the SDRs are in the
--     doomed set.
--   * Rule 6 again: space_conflict_ledger "records every calendar claim
--     overruled by physical reality. Never remove either side." 94%.
--   * KPI 3 (peak_site_kw) has site_energy_snapshots as its sole base table.
--
-- AND IT WOULD HAVE ABORTED ANYWAY. ottoq_ops_approvals.visit_id references
-- ottoq_visit_needs with NO ACTION, and 4,379 approval rows point at visit_needs
-- rows owned by doomed runs. Size-descending puts ottoq_visit_needs (244 MB,
-- rank 11) long before ottoq_ops_approvals (40 MB, rank 22), so the DELETE would
-- raise a foreign-key violation and kill the pass -- after ten tables had
-- already committed.
--
-- THE ROOT CAUSE, WHICH IS A CLASSIFICATION ERROR AND NOT A CODING ONE
--
-- class='engine' means "these rows die with their run", and it was written for
-- ottoq_purge_prior_runs -- a DEMO RESET, where losing everything except one run
-- is the entire point. Borrowing that class as the delete list for a RETENTION
-- purge silently promoted "safe to wipe when starting a demo" into "safe to
-- delete every night forever". They are not the same predicate and the registry
-- never claimed they were.
--
-- WHAT ACTUALLY RAN, AND WHAT IT COST
--
-- Two passes executed before this was caught, and they reached exactly two
-- tables: ottoq_rule_evaluations (drained of doomed rows) and ottoq_events
-- (partially). Both are already on the nightly wall-clock worker's list at a
-- 7-day keep, so the only loss beyond what that worker would have taken anyway
-- is the replayability of runs aged 2-7 days. No moat table was reached.
--
-- That is luck standing on a deliberate choice, and it should be recorded as
-- both: the size-descending order added in 0247's own review is what put the
-- multi-gigabyte working tables first and left every small moat ledger to the
-- end of a budget that expired. The ordering was chosen to stop the calendar
-- being starved, not to protect the moat. It protected the moat.
--
-- THE FIX: AN ALLOW-LIST, NOT A DENY-LIST
--
-- A retention purge deletes only what someone has affirmatively said may be
-- deleted. That is fail-closed by construction: an engine table added tomorrow
-- is not purged until a human classifies it, rather than being purged until
-- someone notices. A deny-list has the opposite default and is how this defect
-- would come back.
--
-- The seed list is the MINIMUM that closes G23, and nothing else. Anything
-- arguable -- ottoq_decisions (the propose/dispose audit trail CLAUDE.md Part 3
-- quotes), ottoq_visit_needs, ottoq_vehicle_commands -- is deliberately absent
-- and needs its own decision, on its own evidence, in its own migration.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The allow-list.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ottoq_retention_engine_allowlist (
  table_name text PRIMARY KEY,
  added_at   timestamptz NOT NULL DEFAULT now(),
  note       text NOT NULL
);

COMMENT ON TABLE public.ottoq_retention_engine_allowlist IS
  '0250: the ONLY tables ottoq_retention_purge_runs may delete from. Membership '
  'is an affirmative decision with a reason, never a default. class=''engine'' in '
  'ottoq_run_scope_registry is a necessary condition, not a sufficient one -- it '
  'was written for the demo reset (ottoq_purge_prior_runs) and includes the cuOpt '
  'ledger, the SDR settlement rail and the space-conflict ledger.';

INSERT INTO public.ottoq_retention_engine_allowlist (table_name, note) VALUES
  ('ottoq_stall_bookings',
   'G23''s target. 66% of every heap block this database has ever read, 84% of it '
   'owned by runs that ended days ago. The pair reads it run-scoped -- '
   'ottoq_determinism_pair: FROM ottoq_stall_bookings k WHERE k.sim_run_id = v_run '
   '-- so purging other runs cannot move h_bkg (0164 Q2). Cost of purging: KPI 2 '
   'and KPI 4 can no longer be recomputed for a purged run, and it cannot be '
   'replayed.'),
  ('ottoq_events',
   'Already deleted nightly by ottoq_retention_purge_worker at a 7-day wall-clock '
   'keep; 96% of its lifetime rows are already gone. Adding it here deletes the '
   'same class of row by run rather than by age. No new loss class.'),
  ('ottoq_rule_evaluations',
   'Same as ottoq_events: already on the nightly worker at a 7-day keep. The L1 '
   'shield''s evaluation log is regenerable working state, and h_rule is run-scoped.'),
  ('ottoq_itinerary_legs',
   'Run-scoped movement working state. No inbound foreign key from any table.'),
  ('ottoq_variability_cards',
   'The twin''s per-run variability draws. Regenerable from (seed, entity, '
   'sim-seconds) by construction -- twin.ottoq_sim_seeded_random is a pure hash '
   'with no sequence -- so these rows are a cache of a function, not evidence.'),
  ('ottoq_bay_binding_witness',
   'Per-tick bay-binding observations, 1.46M rows for 380 MB. Working state; no '
   'KPI and no verdict atom reads it.'),
  ('ottoq_comms_messages',
   'Simulated comms traffic. Working state; nothing downstream reads it after the '
   'run ends.')
ON CONFLICT (table_name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. The purge, loop restricted to the allow-list, plus a structural FK guard.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_runs(
  IN p_time_budget_s integer DEFAULT 60,
  IN p_micro_batch   integer DEFAULT 2000,
  IN p_keep          interval DEFAULT '48:00:00'::interval,
  IN p_dry_run       boolean  DEFAULT false)
LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_keep    interval;
  v_cut     timestamptz;
  v_t0      timestamptz := clock_timestamp();
  v_n       bigint;
  v_total   bigint := 0;
  v_doomed  uuid[];
  v_block   int;
  v_pairs   int;
  v_bad     text;
  v_reg     record;   -- 0249: not `r`; it shadowed the sr alias below
BEGIN
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running - skipped';
    RETURN;
  END IF;

  SELECT count(*) FILTER (WHERE severity = 'block') INTO v_block
    FROM public.ottoq_check_run_scope_registry();
  IF v_block > 0 THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION 'purge refused: % blocking run-scope defect(s).', v_block;
  END IF;

  -- 0250 GUARD 1: every allow-listed table must still be class='engine'. The
  -- allow-list narrows the registry; it may never widen it.
  SELECT string_agg(a.table_name, ', ') INTO v_bad
    FROM public.ottoq_retention_engine_allowlist a
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                      WHERE g.table_name = a.table_name AND g.class = 'engine'
                        AND g.table_schema = 'public');
  IF v_bad IS NOT NULL THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION 'purge refused: allow-listed but not class=engine: %', v_bad;
  END IF;

  -- 0250 GUARD 2: THE DEFECT THAT WOULD HAVE ABORTED A PASS MID-FLIGHT, MADE
  -- STRUCTURALLY IMPOSSIBLE. Refuse if any allow-listed table is the parent of a
  -- NO ACTION or RESTRICT foreign key. ottoq_ops_approvals.visit_id ->
  -- ottoq_visit_needs is exactly that shape, with 4,379 rows pointing at doomed
  -- visit_needs; a size-ordered loop reaches the parent first and dies on the
  -- constraint after ten tables have committed. Refusing up front means the
  -- ordering problem cannot arise at all, and a future addition with such a
  -- child fails loudly at the gate instead of half-way through a delete.
  -- Every table on today's list is clean: their only inbound keys are SET NULL.
  SELECT string_agg(DISTINCT c.confrelid::regclass::text || ' <- ' || c.conrelid::regclass::text, ', ')
    INTO v_bad
    FROM pg_constraint c
    JOIN public.ottoq_retention_engine_allowlist a
      ON a.table_name = c.confrelid::regclass::text
   WHERE c.contype = 'f' AND c.confdeltype IN ('a', 'r');
  IF v_bad IS NOT NULL THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION 'purge refused: allow-listed table is the parent of a NO ACTION/RESTRICT FK: %', v_bad;
  END IF;

  -- pg_stat_activity is the only authority on a pair in flight.
  -- pid <> pg_backend_pid() is load-bearing: without it this query's own text
  -- matches the pattern it searches for.
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND query ILIKE '%ottoq_determinism_pair%';
  IF v_pairs > 0 THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE NOTICE 'retention purge: % certification pair(s) in flight - skipped', v_pairs;
    RETURN;
  END IF;

  SELECT keep_interval INTO v_keep
    FROM public.ottoq_retention_policy WHERE policy_key = 'engine_rows' AND enabled;
  v_keep := COALESCE(v_keep, p_keep);
  v_cut  := now() - v_keep;

  SELECT array_agg(sr.sim_run_id) INTO v_doomed
    FROM public.ottoq_sim_runs sr
   WHERE sr.status <> 'running'
     AND COALESCE(sr.run_by,'') <> 'production_live'
     AND sr.started_at < v_cut
     AND EXISTS (SELECT 1 FROM public.ottoq_run_archives a WHERE a.sim_run_id = sr.sim_run_id);

  IF v_doomed IS NULL OR cardinality(v_doomed) = 0 THEN
    RAISE NOTICE 'retention purge (runs): nothing older than % is archived and finished', v_keep;
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RETURN;
  END IF;

  RAISE NOTICE 'retention purge (runs): keep %, cut %, % doomed run(s), dry_run=%',
               v_keep, v_cut, cardinality(v_doomed), p_dry_run;

  -- THE LOOP: the INTERSECTION of the registry's engine class and the allow-list.
  -- Biggest first so the calendar is never starved behind alphabetical neighbours
  -- (0247's own review); self-correcting, because a drained table yields its place.
  FOR v_reg IN
    SELECT g.table_name AS t, g.column_name AS c
      FROM public.ottoq_run_scope_registry g
      JOIN public.ottoq_retention_engine_allowlist a ON a.table_name = g.table_name
     WHERE g.class = 'engine' AND g.table_schema = 'public'
       AND to_regclass('public.' || g.table_name) IS NOT NULL
     ORDER BY pg_total_relation_size(('public.' || g.table_name)::regclass) DESC, g.table_name
  LOOP
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);

      IF p_dry_run THEN
        EXECUTE format('SELECT count(*) FROM public.%1$I WHERE %2$I = ANY($1)', v_reg.t, v_reg.c)
          INTO v_n USING v_doomed;
        RAISE NOTICE '  dry run: % would lose % row(s)', v_reg.t, v_n;
        v_total := v_total + v_n;
        EXIT;
      END IF;

      PERFORM set_config('ottoq.retention', 'on', true);

      EXECUTE format(
        'DELETE FROM public.%1$I WHERE ctid IN '
        '(SELECT ctid FROM public.%1$I WHERE %2$I = ANY($1) LIMIT $2)',
        v_reg.t, v_reg.c) USING v_doomed, p_micro_batch;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;

      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END LOOP;

  IF NOT p_dry_run THEN
    PERFORM set_config('ottoq.retention', 'on', true);
    UPDATE public.ottoq_retention_state
       SET pass_deleted = pass_deleted + v_total, updated_at = now()
     WHERE table_name = 'engine_rows';
    IF NOT FOUND THEN
      INSERT INTO public.ottoq_retention_state (table_name, cursor_block, pass_deleted, updated_at)
      VALUES ('engine_rows', cardinality(v_doomed), v_total, now())
      ON CONFLICT (table_name) DO NOTHING;
    END IF;
    COMMIT;
  END IF;

  RAISE NOTICE 'retention purge (runs): % row(s) % across % run(s)',
               v_total, CASE WHEN p_dry_run THEN 'MATCHED (dry run)' ELSE 'deleted' END,
               cardinality(v_doomed);
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
END;
$procedure$;

-- ---------------------------------------------------------------------------
-- 3. Assertions.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_src text; v_n int; v_bad text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_runs';

  -- A1. 0164 still holds: no DELETE against the run ledger.
  IF v_src ~* 'DELETE\s+FROM\s+(public\.)?ottoq_sim_runs' THEN
    RAISE EXCEPTION 'A1 FAILED: DELETE against ottoq_sim_runs (0164)';
  END IF;

  -- A2. The loop joins the allow-list. Without this join the deny-list default
  --     is back and so is every number in this file's header.
  IF v_src !~ 'ottoq_retention_engine_allowlist' THEN
    RAISE EXCEPTION 'A2 FAILED: the purge loop no longer joins the allow-list';
  END IF;

  -- A3. THE MOAT IS NOT ON THE LIST, BY NAME. These are the tables CLAUDE.md
  --     names as unloseable; a future edit that adds one fails here.
  SELECT string_agg(table_name, ', ') INTO v_bad
    FROM public.ottoq_retention_engine_allowlist
   WHERE table_name IN ('cuopt_invocation_log','ottoq_service_detail_records',
                        'space_conflict_ledger','ottoq_recall_decisions',
                        'site_energy_snapshots','ottoq_external_proposals',
                        'ottoq_cuopt_deferrals','ottoq_run_archives','ottoq_sim_runs');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'A3 FAILED: moat table(s) on the retention allow-list: %', v_bad;
  END IF;

  -- A4. Every allow-listed table is class=engine and exists.
  SELECT string_agg(a.table_name, ', ') INTO v_bad
    FROM public.ottoq_retention_engine_allowlist a
   WHERE to_regclass('public.' || a.table_name) IS NULL
      OR NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                      WHERE g.table_name = a.table_name AND g.class = 'engine');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'A4 FAILED: allow-listed but missing or not class=engine: %', v_bad;
  END IF;

  -- A5. No allow-listed table is the parent of a NO ACTION/RESTRICT FK -- the
  --     condition GUARD 2 enforces at run time, asserted now so the seed list
  --     is known clean rather than merely guarded.
  SELECT string_agg(DISTINCT c.confrelid::regclass::text, ', ') INTO v_bad
    FROM pg_constraint c
    JOIN public.ottoq_retention_engine_allowlist a
      ON a.table_name = c.confrelid::regclass::text
   WHERE c.contype = 'f' AND c.confdeltype IN ('a','r');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'A5 FAILED: allow-listed table parents a NO ACTION/RESTRICT FK: %', v_bad;
  END IF;

  SELECT count(*) INTO v_n FROM public.ottoq_retention_engine_allowlist;
  RAISE NOTICE 'A1-A5 PASSED; % table(s) on the retention allow-list of 47 engine tables', v_n;

  -- A6. Still nothing scheduled.
  SELECT count(*) INTO v_n FROM cron.job WHERE command ILIKE '%ottoq_retention_purge_runs%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A6 FAILED: % cron job(s) call the purge', v_n;
  END IF;
END $$;
