-- migration-version: APPLIED-NO-LEDGER-ROW
-- migration-name:    an_evidence_table_is_not_dropped_by_accident
-- (applied by Chase in the Supabase dashboard's SQL editor, which writes no supabase_migrations row; the APPLIED footer
--  at the end of this file is the record. See task G18.)
--
-- 0749  **An evidence table is not dropped by accident.** (G463)
--       0748 made an evidence table refuse TRUNCATE. A DROP TABLE takes the table and its rows with it, and nothing in
--       the database refused one: 102 of the 202 tables the run-scope registry classes as evidence, registered together
--       as "certification / scratch evidence: deliberately outlives its run", are gone, and nothing recorded what dropped
--       them. This file makes the database refuse a DROP that takes an evidence table, or the registry itself, unless the
--       transaction unlocks it on purpose. It changes no row, no read, no write and no decision, and nothing the engine
--       runs drops a table the registry names.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-17 between 8:24 and 8:47 PM CT; db/checks/0453 §4, queries (6)-(8)) ═══════
--
--   The registry's 102 missing evidence tables were all registered at 2026-08-08 18:22 UTC with one note; 59 of them are
--   in the 2026-08-04 baseline (db/baseline/tables.sql). No file in this repo drops one, and the database keeps no record
--   of DDL: its six event triggers are Supabase's own (the PostgREST schema watch and the extension grants).
--   No function body drops a table but two PostGIS helpers and public.ottoq_baseline_fifo, which drops its own temporary
--   tables (_stall, _work); no cron command drops anything. So no path the engine runs drops a registered table.
--   postgres, though not a superuser here, may create an event trigger: probed in a transaction that rolled back, and
--   read back after it, no trigger left.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_evidence_no_drop(): an event-trigger function on sql_drop. When the objects a statement drops
--       include a table the registry classes as evidence, or the registry itself, it refuses the statement with SQLSTATE
--       42501, naming each one, unless ottoq.evidence_drop_unlock is 'on' in the transaction. A DROP SCHEMA ... CASCADE
--       or a DROP of several tables that reaches one is refused whole. Temporary tables and every other object pass.
--       SECURITY DEFINER, because an event trigger runs with the privileges of the role that issued the statement
--       (Supabase, "PostgreSQL Event Triggers without superuser access", 2025-05-08,
--       https://supabase.com/blog/event-triggers-wo-superuser): as an ordinary function it refused the DROP of any role
--       that cannot read the registry, its own tables included (tests/test_evidence_no_drop_sql.py, the platform role).
--   (b) The event trigger ottoq_evidence_no_drop on sql_drop, calling it.
--   Not changed: which tables are evidence (the registry, written only by migrations since 0748), and the 102 registry
--   rows whose table is already gone. Not covered: a rename or a move to another schema, which takes a table out of its
--   registered name without dropping it (nothing refuses that; the drop that follows is then not refused either), and
--   DDL run by a superuser or by one of the platform's reserved roles, for which Supabase's supautils skips the event
--   triggers its users create (the same source). A column dropped from an evidence table is not refused: that is a
--   schema change a migration may need, and it says so in its own file.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the registry exists; no event trigger or function of this file exists. P2 not already
--   applied. V1 the event trigger is enabled on sql_drop and calls this file's function. V2 a probe table registered as
--   evidence is refused a DROP with 42501 and named, a DROP of it with another table is refused whole, a probe
--   registered as engine is dropped, and with the unlock the evidence probe is dropped too (all inside a block rolled
--   back by its own exception). Executed whole by tests/test_evidence_no_drop_sql.py on the live grants and registry.
--
--   APPLY WITH A PERSON AT THE CONNECTOR. V2 drops probe tables, and the Supabase connector holds a statement with a
--   DROP for a person's approval, 60 seconds, then gives up (MIGRATION_LOG, 0647). That is what happened to this file's
--   live dry run, twice, on 2026-10-17 between 8:36 and 8:47 PM CT: neither statement reached the database (its own log
--   shows none of them), and nothing was left behind. What did reach it, rolled back: the function and the event
--   trigger created as written (8:43 PM CT), and a DROP of a probe table registered as evidence refused in 5 ms with this
--   file's refusal (8:43 PM CT). A DROP the trigger lets through has run only on the scratch database.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. No function the engine runs is changed, no row is written but the
--   lineage row, and no atom reads an event trigger.
--
-- ROLLBACK: at once, with no DROP for the connector to hold: ALTER EVENT TRIGGER ottoq_evidence_no_drop DISABLE. Then,
--   with a person at the connector: DROP EVENT TRIGGER ottoq_evidence_no_drop; DROP FUNCTION public.ottoq_evidence_no_drop();
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0749_an_evidence_table_is_not_dropped_by_accident'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0749 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the registry, nothing of this file ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_run_scope_registry') IS NULL THEN
    RAISE EXCEPTION '0749 P1: the run-scope registry is missing';
  END IF;
  IF to_regprocedure('public.ottoq_evidence_no_drop()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_event_trigger WHERE evtname = 'ottoq_evidence_no_drop') THEN
    RAISE EXCEPTION '0749 P1: the function or the event trigger of this file already exists';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0749_an_evidence_table_is_not_dropped_by_accident') THEN
    RAISE EXCEPTION '0749 P2: already applied';
  END IF;
END $once$;

-- ── (a) the refusal ──
CREATE FUNCTION public.ottoq_evidence_no_drop()
RETURNS event_trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE v_hit text;
BEGIN
  --: a DROP that takes an evidence table, or the registry that names them, is refused unless unlocked (0749).
  --: SECURITY DEFINER: an event trigger runs as the role that issued the statement, and a role that cannot read the
  --: registry (a platform role dropping its own table) must not have its DROP fail here.
  IF COALESCE(current_setting('ottoq.evidence_drop_unlock', true), '') = 'on' THEN
    RETURN;
  END IF;
  SELECT string_agg(d.schema_name || '.' || d.object_name, ', ' ORDER BY d.schema_name, d.object_name) INTO v_hit
    FROM pg_event_trigger_dropped_objects() d
   WHERE d.object_type = 'table' AND d.schema_name = 'public' AND d.object_name = 'ottoq_run_scope_registry';
  IF v_hit IS NULL THEN
    IF to_regclass('public.ottoq_run_scope_registry') IS NULL THEN
      RETURN;                                    -- no registry, so nothing is classed as evidence
    END IF;
    SELECT string_agg(DISTINCT d.schema_name || '.' || d.object_name, ', ' ORDER BY d.schema_name || '.' || d.object_name) INTO v_hit
      FROM pg_event_trigger_dropped_objects() d
      JOIN public.ottoq_run_scope_registry g
        ON g.class = 'evidence' AND g.table_schema = d.schema_name AND g.table_name = d.object_name
     WHERE d.object_type = 'table' AND NOT d.is_temporary;
  END IF;
  IF v_hit IS NOT NULL THEN
    RAISE EXCEPTION 'evidence is not dropped (0749): %. Set ottoq.evidence_drop_unlock=on in the transaction to override, and say why in a migration.',
      v_hit
      USING ERRCODE = '42501';
  END IF;
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_evidence_no_drop() FROM PUBLIC, anon, authenticated, service_role;

-- ── (b) the event trigger ──
CREATE EVENT TRIGGER ottoq_evidence_no_drop ON sql_drop
  EXECUTE FUNCTION public.ottoq_evidence_no_drop();

-- ── V1: enabled, on sql_drop, calling this file's function ──
DO $v1$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_event_trigger
                  WHERE evtname = 'ottoq_evidence_no_drop' AND evtevent = 'sql_drop' AND evtenabled IN ('O', 'A')
                    AND evtfoid = 'public.ottoq_evidence_no_drop()'::regprocedure) THEN
    RAISE EXCEPTION '0749 V1: the event trigger is not enabled on sql_drop with this file''s function';
  END IF;
END $v1$;

-- ── V2: an evidence probe is refused and named, together with another table too; an engine probe is dropped; the unlock
--        drops the evidence probe (everything rolled back in its block) ──
DO $v2$
DECLARE v_state text; v_msg text; v_n int := 0;
BEGIN
  BEGIN
    CREATE TABLE public.ottoq_0749_probe_evidence (sim_run_id uuid);
    CREATE TABLE public.ottoq_0749_probe_engine (sim_run_id uuid);
    INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
    VALUES ('public', 'ottoq_0749_probe_evidence', 'sim_run_id', 'evidence', '0749 V2 probe, rolled back'),
           ('public', 'ottoq_0749_probe_engine', 'sim_run_id', 'engine', '0749 V2 probe, rolled back');
    BEGIN
      DROP TABLE public.ottoq_0749_probe_evidence;
      RAISE EXCEPTION '0749 V2: DROP of an evidence table was not refused';
    EXCEPTION WHEN insufficient_privilege THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    END;
    IF v_state IS DISTINCT FROM '42501' OR v_msg NOT LIKE 'evidence is not dropped (0749): public.ottoq_0749_probe_evidence.%' THEN
      RAISE EXCEPTION '0749 V2: the refusal was % (%), not this file''s', v_state, v_msg;
    END IF;
    BEGIN
      DROP TABLE public.ottoq_0749_probe_engine, public.ottoq_0749_probe_evidence;
      RAISE EXCEPTION '0749 V2: a DROP of two tables, one of them evidence, was not refused';
    EXCEPTION WHEN insufficient_privilege THEN
      v_n := v_n + 1;
    END;
    IF to_regclass('public.ottoq_0749_probe_engine') IS NULL OR to_regclass('public.ottoq_0749_probe_evidence') IS NULL THEN
      RAISE EXCEPTION '0749 V2: a refused DROP took a table';
    END IF;
    DROP TABLE public.ottoq_0749_probe_engine;
    PERFORM set_config('ottoq.evidence_drop_unlock', 'on', true);
    DROP TABLE public.ottoq_0749_probe_evidence;
    PERFORM set_config('ottoq.evidence_drop_unlock', '', true);
    IF to_regclass('public.ottoq_0749_probe_engine') IS NOT NULL OR to_regclass('public.ottoq_0749_probe_evidence') IS NOT NULL
       OR v_n <> 1 THEN
      RAISE EXCEPTION '0749 V2: the engine probe or the unlocked evidence probe was not dropped';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OT749', MESSAGE = 'probe passed';
  EXCEPTION WHEN SQLSTATE 'OT749' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry WHERE table_name LIKE 'ottoq_0749_probe%')
     OR COALESCE(current_setting('ottoq.evidence_drop_unlock', true), '') = 'on' THEN
    RAISE EXCEPTION '0749 V2: the probe was not rolled back, or the unlock outlived it';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0749_an_evidence_table_is_not_dropped_by_accident', false, false,
        'G463. Event trigger ottoq_evidence_no_drop on sql_drop (public.ottoq_evidence_no_drop): a DROP that takes a table the '
        'run-scope registry classes as evidence, or the registry itself, is refused with 42501 unless '
        'ottoq.evidence_drop_unlock=on in the transaction. No engine function, row or atom changes; nothing the engine runs '
        'drops a registered table.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-24 01:24:45 UTC (8:24 PM CT on 2026-10-23), no ledger row ══════════════════════════════════════════
--
--   Chase ran this file in the Supabase dashboard's SQL editor, one of five files in one paste that
--   scripts/editor_paste.py made from the files as they stand at 8403fbc, in this order: 0603, 0714, 0738, 0749, then
--   0755 with its switch after it (the paste's md5 c77bba758ad00d7c9e3bf4f33fc292b3, 54,662 bytes, from the step page
--   "Five Ready Fixes"). The paste checked this file's text, less its BEGIN; and COMMIT; lines, at md5
--   94d1a6aa1100e47e53c2e0117e5b2870 before it ran it (the file then, header PENDING: md5
--   602b586d0a9b98c15a49d1a55fa11310); the header's version and note and this footer are the only text added since.
--   Each file was its own transaction. All five lineage rows carry 01:24:45.340543 UTC, because a transaction begun
--   inside one query message takes that message's arrival as now(). Read back between 01:27 and 01:30 UTC (8:27 and
--   8:30 PM CT; the last query's own now() 01:30:12 UTC). P0, P1, P2, V1 and V2 passed inside its transaction, so on
--   the live database a probe table registered as evidence was refused a DROP with 42501 and named, a DROP of it with
--   an engine probe was refused whole, the engine probe was dropped, and with the unlock the evidence probe was
--   dropped, all rolled back in V2's own block. Read back: the event trigger ottoq_evidence_no_drop enabled on
--   sql_drop, calling public.ottoq_evidence_no_drop(), SECURITY DEFINER, at md5 8c174c34e8697da31112e79c91b0857a (the
--   body in this file, byte for byte), executable by postgres alone; 204 registry rows classed evidence.
