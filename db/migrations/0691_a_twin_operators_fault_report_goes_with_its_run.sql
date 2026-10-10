-- migration-version: 20261010111503
-- migration-name:    a_twin_operators_fault_report_goes_with_its_run
--
-- 0691  **A fault an operator reports through the v2 door with a twin or replay key goes with its run, like every other
--        row the twin makes.** (G411, found 2026-10-10 preparing the twin's sending side, docs/TWIN_SENDING_SIDE.md.)
--
-- ══ §1 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   ottoq.ottoq_v2_apply takes a com.ottoyard.vehicle.fault.summary as an open row in public.exceptions, stamped with
--   the key's data source and nothing else. public.exceptions has no run column, so a twin operator's fault report
--   would outlive its run: the demo-run purge (ottoq_purge_prior_runs) clears a run's rows by the run-scope registry,
--   and exceptions is not in it. Every other row a twin key's event makes is run-scoped (the packet, the inbox row, the
--   cursor). None has been written yet (read 2026-10-10: no exception carries metadata door = v2), and the twin's
--   operators are about to start sending faults (stage 2 of the sending side), so it is fixed before the first one.
--
-- ══ §2 WHAT THIS CHANGES ═══════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.exceptions.sim_run_id, nullable, a plain foreign key to ottoq_sim_runs (no cascade, as the registry's
--       check requires), a partial index, and a run-scope registry row, class engine. Production and shadow rows keep
--       NULL and are never purged.
--   (b) The door's fault branch stamps it: the run the key's event was taken on, for a twin or replay key; NULL
--       otherwise.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════
--
--   No twin path sends a fault summary yet, so no run writes a row this file changes. The two readers of exceptions in
--   the engine (public.has_blocking_exception, with no caller in the database, and SLA.007's evaluator) count rows by
--   vehicle and task, not by run. V1 takes one fault report from sim-a on a stopped run marked running inside a
--   rolled-back block and checks the row carries the run; V2 checks the registry raises no blocking defect, so the
--   purge still runs.
--
-- ══ §4 ROLLBACK ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0691_pre'; delete the registry row. The column
--   stays (dropping it needs a person at the connector's prompt) and is harmless unset.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0691 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0690_the_dispatch_ledger_counts_the_miles_the_car_drove') THEN
    RAISE EXCEPTION '0691 P1: 0690 is not classified; apply in order';
  END IF;
  IF md5(pg_get_functiondef('ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'::regprocedure))
       <> '0f0439ee73a80bf47b1474364346f5ff' THEN
    RAISE EXCEPTION '0691 P1: ottoq.ottoq_v2_apply is not the definition this file patches';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'exceptions' AND column_name = 'sim_run_id')
     OR EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry WHERE table_schema = 'public' AND table_name = 'exceptions') THEN
    RAISE EXCEPTION '0691 P1: exceptions already carries a run column or a registry row';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0691 P1: a run is live; apply between runs';
  END IF;
END $premises$;

-- ── snapshot ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0691_pre', 'function', 'ottoq', 'ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)', d.def, md5(d.def)
  FROM (SELECT pg_get_functiondef('ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'::regprocedure) AS def) d;

-- ── (a) the run column ──
ALTER TABLE public.exceptions
  ADD COLUMN sim_run_id uuid REFERENCES public.ottoq_sim_runs (sim_run_id);
COMMENT ON COLUMN public.exceptions.sim_run_id IS
  '0691: the run a twin or replay key''s fault report was taken on (NULL for production and shadow). Run-scoped: '
  'the demo-run purge clears a prior run''s rows through ottoq_run_scope_registry.';
CREATE INDEX exceptions_sim_run_id_idx ON public.exceptions (sim_run_id) WHERE sim_run_id IS NOT NULL;
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'exceptions', 'sim_run_id', 'engine',
        '0691: a twin or replay key''s fault report through the v2 door. Goes with its run; production rows carry NULL.');

-- ── (b) the door stamps it ──
DO $p_apply$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'::regprocedure);
  a text[] := ARRAY[
$a01$    INSERT INTO public.exceptions (vehicle_id, depot_id, exception_type, severity, status, title, description, metadata, data_source)
$a01$,
$a02$            k.data_source)
    RETURNING id INTO v_exc;
$a02$];
  b text[] := ARRAY[
$b01$    INSERT INTO public.exceptions (vehicle_id, depot_id, exception_type, severity, status, title, description, metadata, data_source,
                                   sim_run_id)  -- 0691: a twin or replay key's fault report goes with its run
$b01$,
$b02$            k.data_source, CASE WHEN v_run_scoped THEN p_engine_run END)
    RETURNING id INTO v_exc;
$b02$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '0f0439ee73a80bf47b1474364346f5ff' THEN
    RAISE EXCEPTION '0691: the door''s apply is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0691: anchor % of the door''s apply occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'ed2895cacce4fe27325f7648ed2f208a' THEN
    RAISE EXCEPTION '0691: the door''s apply, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'::regprocedure))
       <> 'ed2895cacce4fe27325f7648ed2f208a' THEN
    RAISE EXCEPTION '0691: the door''s apply did not read back as written';
  END IF;
END $p_apply$;

-- ── V1: sim-a reports one fault on a stopped run marked running, inside a block that rolls back ──
DO $v1$
DECLARE
  v_run uuid; v_clock timestamptz; v_hash text; v_ref text; v_seq numeric; v_ev jsonb; v_take jsonb; v_msg text;
  v_row record; v_parts text[];
BEGIN
  SELECT r.sim_run_id, r.sim_clock_current INTO v_run, v_clock
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed' AND r.sim_clock_current IS NOT NULL
   ORDER BY r.started_at DESC, r.sim_run_id LIMIT 1;
  SELECT k.key_hash, (SELECT v.display_name FROM public.vehicles v
                       WHERE v.fleet_operator_id = ANY (k.fleet_operator_ids)
                         AND v.home_depot_id = '11111111-1111-1111-1111-111111111111'
                       ORDER BY v.display_name LIMIT 1)
    INTO v_hash, v_ref
    FROM twin.ottoq_twin_operators o JOIN public.ottow_api_keys k ON k.id = o.key_id
   WHERE o.source_name = 'sim-a' AND k.is_active;
  IF v_run IS NULL OR v_hash IS NULL OR v_ref IS NULL THEN
    RAISE EXCEPTION '0691 V1: no stopped twin run, no active sim-a key or no sim-a car to probe with';
  END IF;
  BEGIN
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    SELECT COALESCE(max(c.last_sequence::numeric), 0) + 1 INTO v_seq
      FROM public.ottoq_v2_cursors c
     WHERE c.source_name = 'sim-a' AND c.ce_source = 'urn:ottoq:src:sim-a:' || v_ref AND c.sim_run_id = v_run;
    v_ev := jsonb_build_object(
      'specversion', '1.0', 'id', 'probe-0691', 'source', 'urn:ottoq:src:sim-a:' || v_ref, 'subject', v_ref,
      'type', 'com.ottoyard.vehicle.fault.summary', 'time', ottoq.ottoq_v2_rfc3339(v_clock),
      'datacontenttype', 'application/json',
      'dataschema', 'https://ottoyard.com/schemas/ottoq/contract/0.1/vehicle.fault.summary.json',
      'sequence', lpad(v_seq::text, 20, '0'),
      'data', jsonb_build_object('severity', 'low', 'category', 'sensor_anomaly', 'takes_vehicle_offline', false,
                                 'fault_codes', jsonb_build_array('AV-SN001')));
    PERFORM set_config('ottoq.v2_twin_run', v_run::text, true);
    v_take := public.ottoq_v2_take_events(v_hash, jsonb_build_array(v_ev), false);
    PERFORM set_config('ottoq.v2_twin_run', '', true);
    SELECT e.sim_run_id, e.data_source INTO v_row FROM public.exceptions e WHERE e.metadata ->> 'ce_id' = 'probe-0691';
    RAISE EXCEPTION '0691 PROBED|%|%|%', v_take -> 'results' -> 0 ->> 'disposition', v_row.sim_run_id, v_row.data_source;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg NOT LIKE '0691 PROBED|%' THEN
    RAISE EXCEPTION '0691 V1 failed to run: %', v_msg;
  END IF;
  v_parts := string_to_array(v_msg, '|');
  IF v_parts[2] IS DISTINCT FROM 'applied' OR v_parts[3] IS DISTINCT FROM v_run::text OR v_parts[4] IS DISTINCT FROM 'twin' THEN
    RAISE EXCEPTION '0691 V1 FAILED: %', v_msg;
  END IF;
  RAISE NOTICE '0691 V1 PASSED: sim-a''s fault report on run % was applied and its exception carries the run; all rolled back', v_run;
END $v1$;

-- ── V2: the definition as written, and the purge's own check still passes ──
DO $v2$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_v2_apply(uuid,uuid,timestamptz,text,uuid,timestamptz,jsonb)'::regprocedure))
       <> 'ed2895cacce4fe27325f7648ed2f208a' THEN
    RAISE EXCEPTION '0691 V2 FAILED: the door''s apply is not as written';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block') THEN
    RAISE EXCEPTION '0691 V2 FAILED: the run-scope registry reports a blocking defect, so the purge would refuse';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_check_run_scope_registry() WHERE table_name = 'exceptions') THEN
    RAISE EXCEPTION '0691 V2 FAILED: the registry check names exceptions';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0691_a_twin_operators_fault_report_goes_with_its_run', false, false,
  'G411: public.exceptions gets a run column (registered engine, plain FK), and the v2 door stamps a twin or replay '
  'key''s fault report with its run. No twin path sends a fault summary yet; no atom or dial metric reads exceptions: '
  'FALSE/FALSE.',
  now());

COMMIT;

-- ══ APPLIED 2026-10-10 11:15:03 UTC (6:15 AM CT), version 20261010111503 ═════════════════════════════════════════════
--   Claude, MCP apply_migration, the file as committed in 9eeaa49; the ledger's stored statement is that file byte for
--   byte (md5 206d42909c9f162baa9876904d543d11, 11,276 characters, 12,034 bytes). P1, V1, V2 passed in the apply's
--   transaction. Read after: ottoq.ottoq_v2_apply's definition md5 ed2895cacce4fe27325f7648ed2f208a as written;
--   public.exceptions.sim_run_id is a uuid column registered engine; the registry check reports no blocking defect; no
--   exception carries a run yet; lineage FALSE/FALSE (read 11:15:09 UTC).
