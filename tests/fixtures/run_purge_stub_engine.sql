-- tests/fixtures/run_purge_stub_engine.sql
--
-- A stub engine for db/migrations/0645 and 0646, EXECUTED by tests/test_run_purge_sql.py. It holds the tables the
-- two retention procedures read and write, at the columns they touch and nothing else, and four bodies copied from
-- the live catalog on 2026-10-09 and md5-pinned there:
--   ottoq_certification_rig_matches(text,boolean)          2f160edeed2ac43a4f1b1174173b77da
--   ottoq_certification_in_flight(boolean)                 34b51e8ef7e0fae40ad34b30858bcb1d
--   ottoq_retention_purge_runs(integer,integer,interval,boolean)    890d2de189d638c1622a53efc863fb66 (before 0645)
--   ottoq_retention_purge_worker(integer,integer,interval,text[])   dff3b880934e2b84d07f771118a3e884 (before 0646)
-- so each migration's P1 guard meets the definition it was written against, and the purge that runs here is the
-- purge production runs. cron.job holds the four jobs whose commands the round guard reads, word for word.

CREATE SCHEMA IF NOT EXISTS cron;
CREATE TABLE cron.job (jobid bigint PRIMARY KEY, jobname text, schedule text, command text, active boolean DEFAULT true);
CREATE FUNCTION cron.alter_job(job_id bigint, schedule text DEFAULT NULL, command text DEFAULT NULL,
                               database text DEFAULT NULL, username text DEFAULT NULL, active boolean DEFAULT NULL)
RETURNS void LANGUAGE sql AS $$
  UPDATE cron.job j SET schedule = COALESCE($2, j.schedule), command = COALESCE($3, j.command),
                        active = COALESCE($6, j.active)
   WHERE j.jobid = $1;
$$;
INSERT INTO cron.job (jobid, jobname, schedule, command, active) VALUES
  (11, 'ottoq-retention-nightly', '0 8 * * *',
   'CALL public.ottoq_retention_purge_worker(90, 2000, ''48 hours'', ARRAY[''ottoq_events'',''ottoq_rule_evaluations'',''ottoq_incident_reports'']);', true),
  (13, 'ottoq-cert-battery', '* * * * *', 'SET statement_timeout = 0; SELECT public.ottoq_cert_battery_step();', false),
  (625, 'ottoq-run-purge-nightly', '0 9 * * *', 'CALL public.ottoq_retention_purge_runs(300, 2000, ''48 hours'', false);', true),
  (746, 'ottoq-recert-runner', '* * * * *',
   E'\nSET statement_timeout = 0;\nDO $runner$\nDECLARE c record;\nBEGIN\n  IF NOT pg_try_advisory_xact_lock(hashtext(''ottoq_recert_runner'')::bigint) THEN RETURN; END IF;\n  PERFORM public.ottoq_determinism_pair(p_seed => c.seed);\nEND $runner$;\n', true);

CREATE TABLE public.ottoq_sim_runs (sim_run_id uuid PRIMARY KEY, run_by text, status text, started_at timestamptz,
                                    ended_at timestamptz, depot_id uuid, purged_at timestamptz);
CREATE TABLE public.ottoq_run_archives (sim_run_id uuid PRIMARY KEY);
CREATE TABLE public.ottoq_run_scope_registry (table_schema text, table_name text, column_name text, class text,
                                              note text, registered_at timestamptz DEFAULT now());
CREATE FUNCTION public.ottoq_check_run_scope_registry() RETURNS TABLE(severity text, table_name text, column_name text)
LANGUAGE sql AS $$ SELECT NULL::text, NULL::text, NULL::text WHERE false $$;
CREATE TABLE public.ottoq_retention_engine_allowlist (table_name text PRIMARY KEY, added_at timestamptz NOT NULL DEFAULT now(), note text NOT NULL);
CREATE TABLE public.ottoq_retention_policy (policy_key text PRIMARY KEY, enabled boolean NOT NULL DEFAULT true,
                                            keep_interval interval NOT NULL DEFAULT '7 days', day_aligned boolean NOT NULL DEFAULT true,
                                            notes text, updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.ottoq_retention_state (table_name text PRIMARY KEY, cursor_block bigint, pass_deleted bigint, updated_at timestamptz);
CREATE TABLE public.ottoq_schema_snapshots (snapshot_id bigserial PRIMARY KEY, taken_at timestamptz NOT NULL DEFAULT now(),
                                            label text NOT NULL, object_kind text NOT NULL, schema_name text NOT NULL,
                                            object_name text NOT NULL, definition text NOT NULL, def_md5 text NOT NULL);
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean, note text, classified_at timestamptz,
                                        forces_dial_restart boolean);
CREATE TABLE public.ottoq_charge_order_snapshots (order_id bigserial PRIMARY KEY, sim_run_id uuid);

-- the engine tables: the seven 0250 allow-listed, keyed on sim_run_id, plus the anchors and incidents cron 11 walks
CREATE TABLE public.ottoq_rule_evaluations   (evaluation_id bigserial PRIMARY KEY, sim_run_id uuid, evaluated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.ottoq_events             (event_id bigserial PRIMARY KEY, sim_run_id uuid, event_type text, occurred_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.ottoq_stall_bookings     (booking_id bigserial PRIMARY KEY, sim_run_id uuid, state text NOT NULL DEFAULT 'done');
CREATE TABLE public.ottoq_variability_cards  (id bigserial PRIMARY KEY, sim_run_id uuid);
CREATE TABLE public.ottoq_comms_messages     (id bigserial PRIMARY KEY, sim_run_id uuid);
CREATE TABLE public.ottoq_bay_binding_witness(id bigserial PRIMARY KEY, sim_run_id uuid);
CREATE TABLE public.ottoq_itinerary_legs     (leg_id bigserial PRIMARY KEY, sim_run_id uuid, status text NOT NULL DEFAULT 'done');
CREATE TABLE public.ottoq_event_state_anchor (anchor_day date, sim_run_id uuid);
CREATE TABLE public.ottoq_incident_reports   (incident_report_id bigserial PRIMARY KEY, triggered_at timestamptz);

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class)
SELECT 'public', t, 'sim_run_id', 'engine'
  FROM unnest(ARRAY['ottoq_rule_evaluations','ottoq_events','ottoq_stall_bookings','ottoq_variability_cards',
                    'ottoq_comms_messages','ottoq_bay_binding_witness','ottoq_itinerary_legs']) t;
INSERT INTO public.ottoq_retention_engine_allowlist (table_name, added_at, note)
SELECT t, '2026-09-09 13:45:46+00', '0250 seed'
  FROM unnest(ARRAY['ottoq_rule_evaluations','ottoq_events','ottoq_stall_bookings','ottoq_variability_cards',
                    'ottoq_comms_messages','ottoq_bay_binding_witness','ottoq_itinerary_legs']) t;
INSERT INTO public.ottoq_retention_policy (policy_key, enabled, keep_interval, day_aligned, notes) VALUES
  ('engine_rows', true, interval '48 hours', false, 'Keep window for RUN-SCOPED engine rows.'),
  ('events',      true, interval '7 days',   true,  'Wall-clock walk.');
INSERT INTO public.ottoq_retention_state (table_name, cursor_block, pass_deleted, updated_at) VALUES
  ('engine_rows', 0, 0, now()), ('ottoq_events', 0, 0, now());

-- four bodies, verbatim from the live catalog
CREATE OR REPLACE FUNCTION public.ottoq_certification_rig_matches(p_query text, p_with_dial boolean DEFAULT true)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'pg_catalog'
AS $function$
  -- 0513 (G243). pg_stat_activity keeps the first 1 kB of a query (track_activity_query_size), and the recert runner
  -- (cron 746) names ottoq_determinism_pair past it (G194). Its advisory-lock key, ottoq_recert_runner, is in its
  -- first 100 characters, so that is what identifies it.
  -- 0579 (G305): the overnight sweep is matched by its CALL, so a read of ottoq_throughput_sweep_arms or a write of the
  -- throughput_sweep_runner_enabled dial is not taken for an arm.
  SELECT COALESCE(p_query, '') ILIKE ANY (ARRAY['%ottoq_determinism_pair%', '%ottoq_ab_pair%', '%ottoq_recert_runner%'])
      OR (COALESCE(p_with_dial, true)
          AND (COALESCE(p_query, '') ILIKE ANY (ARRAY['%ottoq_dial_pair%', '%ottoq_dial_experiment_runner%'])
               OR COALESCE(p_query, '') ~* 'ottoq_throughput_sweep_(runner|arm)\s*\('));
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_certification_in_flight(p_with_dial boolean DEFAULT true)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  -- 0513 (G243). SECURITY DEFINER: only a pg_read_all_stats member reads another role's query text, and the
  -- calibration tables are written by service_role, which is not one. The caller is never counted.
  -- ottoq.simulate_certification_in_flight = on adds one, so the guards can be proven without a second backend. It
  -- can only report a rig, never hide one.
  SELECT (SELECT count(*)::int FROM pg_stat_activity a
           WHERE a.pid <> pg_backend_pid() AND a.state IS DISTINCT FROM 'idle'
             AND public.ottoq_certification_rig_matches(a.query, p_with_dial))
       + CASE WHEN current_setting('ottoq.simulate_certification_in_flight', true) = 'on' THEN 1 ELSE 0 END;
$function$;

CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_runs(IN p_time_budget_s integer DEFAULT 60, IN p_micro_batch integer DEFAULT 2000, IN p_keep interval DEFAULT '48:00:00'::interval, IN p_dry_run boolean DEFAULT false)
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
  v_stamped boolean := false;   -- 0251
  -- 0294 (G63): was a record variable driven by a query cursor loop over the
  -- registry. A procedure may not COMMIT while a cursor is open, so the COMMIT
  -- below raised 2D000 on every firing this job ever had and it never purged a
  -- row. The registry is read into arrays before the loop instead; the removed
  -- shape is quoted in db/checks/0226, deliberately not here -- A1 greps this
  -- source for it and a comment would satisfy the grep.
  v_tabs    text[];
  v_cols    text[];
  v_i       int;
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

  -- 0250 GUARD 1: the allow-list narrows the registry; it may never widen it.
  SELECT string_agg(a.table_name, ', ') INTO v_bad
    FROM public.ottoq_retention_engine_allowlist a
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                      WHERE g.table_name = a.table_name AND g.class = 'engine'
                        AND g.table_schema = 'public');
  IF v_bad IS NOT NULL THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE EXCEPTION 'purge refused: allow-listed but not class=engine: %', v_bad;
  END IF;

  -- 0250 GUARD 2: no allow-listed table may parent a NO ACTION/RESTRICT FK.
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

  -- 0269 (G23): A SCHEDULED ROUND, not merely a running pair.
  -- db/checks/0202: a round is ten pairs on 14-minute slots and a pair runs
  -- 130-270 s, so for most of a round nothing is in pg_stat_activity and the
  -- guard below sees an idle system. A purge landing in one of those gaps moves
  -- the residue canon BETWEEN two pairs of the same round. Placed here, after
  -- the run-scope check and both allow-list guards, so those three refusals stay
  -- reachable; skips rather than raises, because this runs from cron.
  -- Round jobs are matched by IMMINENCE (+/- 3 h of their own date-pinned fire
  -- time), never by existence: nothing unschedules them after they fire, so an
  -- existence test would disable the purge permanently after the first round.
  -- An unrecognised schedule shape blocks -- unrecognised means unsafe.
  IF EXISTS (
      SELECT 1 FROM cron.job j
       WHERE (j.active AND (j.command ILIKE '%ottoq_determinism_pair%'
                         OR j.command ILIKE '%ottoq_cert_battery_step%'))
          OR (j.jobname ~ '^r[0-9]+_' AND
              CASE WHEN j.schedule ~ '^[0-9]+ [0-9]+ [0-9]+ [0-9]+ \*$'
                   THEN make_timestamptz(extract(year from now())::int,
                                         split_part(j.schedule,' ',4)::int,
                                         split_part(j.schedule,' ',3)::int,
                                         split_part(j.schedule,' ',2)::int,
                                         split_part(j.schedule,' ',1)::int, 0, 'UTC')
                        BETWEEN now() - interval '3 hours' AND now() + interval '3 hours'
                   ELSE true END)) THEN
    PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
    RAISE NOTICE 'retention purge: a certification round is scheduled - skipped';
    RETURN;
  END IF;

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

  -- 0294 (G63): READ THE REGISTRY INTO ARRAYS, THEN LOOP BY INDEX. The previous
  -- version iterated this same query with a record cursor, which holds a portal
  -- open across the COMMIT below -- PL/pgSQL forbids that, and it is the whole
  -- defect. The ORDER BY is preserved character for character: largest table
  -- first is what makes p_time_budget_s spend itself where it matters.
  SELECT array_agg(g.table_name  ORDER BY pg_total_relation_size(('public.' || g.table_name)::regclass) DESC, g.table_name),
         array_agg(g.column_name ORDER BY pg_total_relation_size(('public.' || g.table_name)::regclass) DESC, g.table_name)
    INTO v_tabs, v_cols
    FROM public.ottoq_run_scope_registry g
    JOIN public.ottoq_retention_engine_allowlist a ON a.table_name = g.table_name
   WHERE g.class = 'engine' AND g.table_schema = 'public'
     AND to_regclass('public.' || g.table_name) IS NOT NULL;

  FOR v_i IN 1 .. COALESCE(array_length(v_tabs, 1), 0) LOOP
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);

      IF p_dry_run THEN
        EXECUTE format('SELECT count(*) FROM public.%1$I WHERE %2$I = ANY($1)', v_tabs[v_i], v_cols[v_i])
          INTO v_n USING v_doomed;
        RAISE NOTICE '  dry run: % would lose % row(s)', v_tabs[v_i], v_n;
        v_total := v_total + v_n;
        EXIT;
      END IF;

      PERFORM set_config('ottoq.retention', 'on', true);

      EXECUTE format(
        'DELETE FROM public.%1$I WHERE ctid IN '
        '(SELECT ctid FROM public.%1$I WHERE %2$I = ANY($1) LIMIT $2)',
        v_tabs[v_i], v_cols[v_i]) USING v_doomed, p_micro_batch;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;

      -- 0251: STAMP ON THE FIRST ROW ACTUALLY DELETED, IN THE SAME TRANSACTION
      -- as that delete, so the marker and the deletion commit together. From
      -- this moment the run's KPIs are not whole and ottoq_kpi_five must say so.
      -- Stamping before the loop would over-claim on a pass that deletes
      -- nothing; stamping at the end would leave a budget-cut pass unmarked,
      -- which is the common case and the dangerous one.
      IF v_n > 0 AND NOT v_stamped THEN
        UPDATE public.ottoq_sim_runs
           SET purged_at = now()
         WHERE sim_run_id = ANY(v_doomed) AND purged_at IS NULL;
        v_stamped := true;
      END IF;

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

CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_worker(IN p_time_budget_s integer DEFAULT 60, IN p_micro_batch integer DEFAULT 2000, IN p_keep interval DEFAULT '48:00:00'::interval, IN p_tables text[] DEFAULT ARRAY['ottoq_events'::text])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_keep      interval;
  v_aligned   boolean;
  v_cut       timestamptz;
  v_t0        timestamptz := clock_timestamp();
  v_n         bigint;
  v_total     bigint := 0;
  v_from      timestamptz;
  v_batch_ts  timestamptz;
  v_drained   boolean := false;
  v_live      uuid[];
BEGIN
  -- forward-compatible resolution without a SET clause (see migration notes):
  -- a routine with SET cannot COMMIT, and this procedure commits per iteration.
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running - skipped';
    RETURN;
  END IF;

  -- (2) policy wins over the caller's argument; fall back to it if no row.
  SELECT keep_interval, day_aligned INTO v_keep, v_aligned
    FROM public.ottoq_retention_policy WHERE policy_key = 'events' AND enabled;
  v_keep    := COALESCE(v_keep, p_keep);
  v_aligned := COALESCE(v_aligned, true);

  -- (3) day-aligned cut: delete only COMPLETE days older than the window.
  v_cut := now() - v_keep;
  IF v_aligned THEN
    v_cut := date_trunc('day', v_cut AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  END IF;

  -- (4) runs whose data may never be touched.
  SELECT COALESCE(array_agg(sim_run_id), '{}'::uuid[]) INTO v_live
    FROM public.ottoq_sim_runs
   WHERE status = 'running' OR COALESCE(run_by, '') = 'production_live';

  RAISE NOTICE 'retention purge: keep %, cut %, % protected run(s)',
               v_keep, v_cut, cardinality(v_live);

  -- ---------------------------------------------------------------------------
  -- EVENTS: oldest-first walk ordered by occurred_at — THE SAME COLUMN THE DELETE
  -- IS PREDICATED ON.
  --
  -- 0006 walked this table in event_seq order and stopped when a batch deleted
  -- nothing and its newest timestamp was inside the keep window. That stopping rule
  -- is an inference: "seq order is time order". It is false here -- occurred_at is
  -- the SIM clock and runs start at a random time of day, so a run whose clock sits
  -- behind the previous one writes old-timestamped rows at high event_seq. Measured
  -- 2026-08-05: 18 inversions in 23,697 adjacent pairs. Demonstrated end-to-end: with
  -- a 30-day-old row present and the real 7-day policy, the old worker processed one
  -- window, deleted 0, exited, and left the old row in place.
  --
  -- Ordering by occurred_at removes the inference entirely. There is nothing to
  -- guess: the loop ends when there are no rows older than the cut, which is the
  -- definition of finished rather than a proxy for it. It also needs no cursor --
  -- deleted rows are gone, so the next call naturally resumes at the oldest
  -- survivor. A pass cut short by the time budget costs nothing but time.
  -- ---------------------------------------------------------------------------
  IF 'ottoq_events' = ANY (p_tables) THEN
    v_from := '-infinity'::timestamptz;   -- start at the left edge of the index

    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);  -- re-arm each txn (COMMIT resets it)

      -- STEP 1 — pick this window's UPPER TIMESTAMP by reading exactly
      -- p_micro_batch index entries. This is a bounded, ordered slice of
      -- ottoq_events_occurred_at_retention_idx: O(batch), never O(heap).
      SELECT max(w.occurred_at) INTO v_batch_ts
        FROM (SELECT e.occurred_at
                FROM public.ottoq_events e
               WHERE e.occurred_at >= v_from
                 AND e.occurred_at <  v_cut
               ORDER BY e.occurred_at
               LIMIT p_micro_batch) w;

      -- No row at all older than the cut. That is not an inference about ordering --
      -- there is simply nothing left. THE ONLY EXIT THAT MEANS "DONE".
      IF v_batch_ts IS NULL THEN
        v_drained := true;
        COMMIT;
        EXIT;
      END IF;

      -- STEP 2 — delete the whole CLOSED TIMESTAMP RANGE [v_from, v_batch_ts].
      -- The window is a range of TIME, not a count of rows, and that is deliberate:
      -- it guarantees every row sharing v_batch_ts is inside this delete even if the
      -- LIMIT above cut the group in half. Without that, advancing the watermark past
      -- v_batch_ts could step over a deletable row that happened to share a
      -- microsecond with p_micro_batch protected ones. Many events DO share one
      -- occurred_at here -- it is the sim clock, and a tick writes 60-120 events at
      -- the same value -- so this is a real case, not a theoretical one.
      -- The window is therefore at most p_micro_batch plus the tail of one timestamp
      -- group; a group is bounded by one tick's event count, well under the batch.
      DELETE FROM public.ottoq_events e
       WHERE e.occurred_at >= v_from
         AND e.occurred_at <= v_batch_ts
         AND e.occurred_at <  v_cut
         AND (e.sim_run_id IS NULL OR NOT (e.sim_run_id = ANY (v_live)));
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;

      -- STEP 3 — advance. Everything at or below v_batch_ts and older than the cut
      -- has now been deleted or is protected, so stepping one microsecond past it
      -- (timestamptz resolution) cannot skip anything. v_from strictly increases
      -- every iteration, so the walk always terminates.
      v_from := v_batch_ts + interval '1 microsecond';

      -- Observability only. cursor_block is a bigint that nothing reads back to make
      -- a decision; it now carries the walk's time watermark as epoch seconds so a
      -- human can see where the pass got to. Never dropped, never repurposed away.
      UPDATE public.ottoq_retention_state
         SET cursor_block = floor(extract(epoch FROM v_from))::bigint,
             pass_deleted = pass_deleted + v_n,
             updated_at   = now()
       WHERE table_name = 'ottoq_events';
      IF NOT FOUND THEN
        INSERT INTO public.ottoq_retention_state (table_name, cursor_block, pass_deleted, updated_at)
        VALUES ('ottoq_events', floor(extract(epoch FROM v_from))::bigint, v_n, now())
        ON CONFLICT (table_name) DO NOTHING;
      END IF;

      COMMIT;  -- each window's work is permanent regardless of later failures
    END LOOP;

    -- End-of-pass housekeeping, moved here from 0006's early exit. It now fires only
    -- when the backlog is GENUINELY drained; the old placement could unschedule the
    -- backlog job while old rows remained, which is the whole bug in miniature.
    IF v_drained THEN
      PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'ottoq-retention-backlog';
      UPDATE public.ottoq_retention_state
         SET pass_deleted = 0, updated_at = now() WHERE table_name = 'ottoq_events';
      COMMIT;
    ELSE
      RAISE NOTICE 'retention purge: events pass stopped on the % s budget with work remaining; the next call resumes at the oldest survivor.', p_time_budget_s;
    END IF;

    -- Anchors follow their day. Because the cut is day-aligned, every event that
    -- could have folded onto one of these anchors has already gone.
    PERFORM set_config('ottoq.retention', 'on', true);
    DELETE FROM public.ottoq_event_state_anchor
     WHERE anchor_day < (v_cut AT TIME ZONE 'UTC')::date
       AND (sim_run_id IS NULL OR NOT (sim_run_id = ANY (v_live)));
    COMMIT;
  END IF;

  -- ---------------------------------------------------------------------------
  -- The two small tables. Same batching, same budget, unchanged from 0006 -- both
  -- already walk by their own timestamp column, so neither had the defect.
  -- ---------------------------------------------------------------------------
  IF 'ottoq_rule_evaluations' = ANY (p_tables) THEN
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);
      DELETE FROM public.ottoq_rule_evaluations WHERE evaluation_id IN (
        SELECT evaluation_id FROM public.ottoq_rule_evaluations
         WHERE evaluated_at < v_cut LIMIT p_micro_batch);
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END IF;

  IF 'ottoq_incident_reports' = ANY (p_tables) THEN
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);
      DELETE FROM public.ottoq_incident_reports WHERE incident_report_id IN (
        SELECT incident_report_id FROM public.ottoq_incident_reports
         WHERE triggered_at < v_cut LIMIT p_micro_batch);
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END IF;

  RAISE NOTICE 'retention purge: % rows deleted this call', v_total;
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
END;
$procedure$;
