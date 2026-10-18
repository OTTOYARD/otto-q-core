-- migration-version: PENDING
-- migration-name:    an_evidence_table_refuses_truncate_and_only_a_migration_says_what_is_evidence
--
-- 0748  **An evidence table refuses TRUNCATE, and only a migration says what is evidence.** (G456)
--       The run-scope registry's evidence class is the promise that a table outlives every run: the purge never deletes
--       from it, and the live ledgers among it carry a trigger refusing UPDATE and DELETE. A TRUNCATE fires no row
--       trigger, and the project's default privileges give service_role (the server key the edge functions use) TRUNCATE
--       on every new table in public, so the promise held only because nothing had asked. The registry itself, the list
--       that says which tables are evidence, was writable by the same key. This file closes both: every evidence table
--       refuses TRUNCATE unless a transaction unlocks it on purpose, no API role holds TRUNCATE on one, no API role may
--       write the registry, and registering a table as evidence guards it in the same statement. It changes no row, no
--       read, no write the engine makes, and no decision.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-17 between 7:54 and 8:07 PM CT; db/checks/0453 queries (1)-(5)) ═════════════
--
--   The registry classes 202 tables as evidence. 100 exist; 102 do not, all in public and all named for the August
--   proof and scratch work (band_*, p0019_*, phase11_*, ...). When and by what they were dropped is not established
--   here: the database keeps no record of DDL.
--   Of the 100:
--     - 93 give service_role TRUNCATE, with DELETE and UPDATE. They took it from the default privileges postgres holds
--       in public (service_role=arwdDxtm), which every table created there takes. No table gives it to anon or
--       authenticated. The other 7: ottoq_agent_requests and ottoq_owner_commands (no grant), 0742's
--       ottoq_ready_promise_updates (select and insert), ottoq_throughput_scores and ottoq_throughput_sweep_arms
--       (select), and the two tables in proof_0015 (no grant).
--     - 3 refuse TRUNCATE by a BEFORE TRUNCATE trigger: ottoq_agent_requests and ottoq_owner_commands
--       (public.ottoq_agent_no_truncate, 0559 and 0605), ottoq_feed_plan_promotions (its own append-only function, 0716).
--     - 23 carry a trigger on UPDATE or DELETE. 77 carry none: 70 frozen snapshots (named for a date, a proof, a
--       certification or a migration, or outside public) and 7 live ledgers whose rows the engine rewrites by design
--       (ottoq_ab_runs 97 updates and 262 deletes over the counters' life, ottoq_challenger_findings 7,501 updates,
--       ottoq_dial_pair_ledger 10 and 54, ottoq_run_dial_ledger 13 and 3, ottoq_dial_promotion_ledger 1 update,
--       ottoq_proposer_fire_log 2 deletes, ottoq_model_artifacts none yet).
--   Nothing truncates any of them: no function body outside the agent guard and an assertion names TRUNCATE (comments
--   stripped), no cron command does, and no edge function or app in the twelve repositories does (the tests do, on
--   scratch databases). No function writes ottoq_run_scope_registry; every row in it was written by a migration, as
--   postgres. service_role may INSERT, UPDATE and DELETE it: one UPDATE of a ledger's class to 'engine' would have let
--   the next demo run's purge delete from it, by registry lookup.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_evidence_no_truncate(): a statement-level trigger function that refuses TRUNCATE with SQLSTATE
--       42501 unless ottoq.evidence_truncate_unlock is 'on' in the transaction (the agent ledgers' guard, with its own
--       unlock). A TRUNCATE ... CASCADE that reaches an evidence table is refused whole.
--   (b) public.ottoq_evidence_truncate_guarded(table): the one test of a guard, read by (c) and (e): an enabled BEFORE
--       TRUNCATE trigger calling one of the three named refusers (this file's, 0559's and 0716's). Named, not inferred
--       from a body.
--   (c) public.ottoq_guard_evidence_table(table): gives a table the trigger `ottoq_evidence_no_truncate_trg` when it is
--       not already guarded, and revokes TRUNCATE on it from PUBLIC, anon, authenticated and service_role. The owner
--       keeps the right, and the trigger stands in its way. It refuses a table carrying the trigger disabled (someone
--       chose that; say why in a migration) and passes over anything that is not a table.
--   (d) A row trigger on ottoq_run_scope_registry, after an insert or a change of class or name to 'evidence', runs (c)
--       on the table if it exists, as the migration's role. A table registered before it is created is the assert's.
--   (e) public.ottoq_assert_evidence_truncate_guard(): every evidence table that exists and is not guarded, or on which
--       anon, authenticated or service_role holds TRUNCATE, and every API role that may write the registry. Empty after
--       this file. All five functions are the owner's alone: a migration runs them, and no API role calls one.
--   (f) (c) on the 100 evidence tables and on the registry: 97 tables and the registry gain the trigger, the three
--       already guarded keep their own, and no API role holds TRUNCATE on any of the 101.
--   (g) The registry: INSERT, UPDATE, DELETE and TRUNCATE revoked from PUBLIC, anon, authenticated and service_role.
--       Reading it is unchanged.
--   Not changed: who may SELECT, INSERT, UPDATE or DELETE an evidence table (7 live ledgers are rewritten by design, and
--   narrowing those rights needs each table's writers read first); the default privileges, so a table created later
--   still takes TRUNCATE for service_role until it is registered; the run_ledger tables (ottoq_sim_runs,
--   ottoq_run_archives); ottoq_cert_lineage (two engine functions write it); the 102 registry rows whose table is gone.
--   A session with session_replication_role = replica fires no ordinary trigger, this one included, as with every
--   guard in this database.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, and no run initializing or running: CREATE TRIGGER holds a share-row-exclusive lock on each
--   ledger until commit, and a tick writes them. P1 the API roles and the registry exist; the evidence tables that exist
--   are the 100 measured (md5 of their sorted names 5819248f); they are plain tables; no function or trigger of this
--   file exists. P2 not already applied. Each table's grants to '0748_pre' in ottoq_schema_snapshots. V1 the assert is
--   empty. V2 every grant other than TRUNCATE on the 101 tables is as it was, none of anon, authenticated and
--   service_role holds TRUNCATE on any, service_role still reads the registry and writes none of it, and 98 tables carry
--   the new trigger, none of them the three already guarded. V3 a TRUNCATE of a frozen evidence table is refused with
--   42501 and names it, and a table registered as evidence is guarded at once while one registered as engine is not
--   (both probes rolled back in their own block). The functions, the unlock, the CASCADE, the registry trigger and the
--   refusal as service_role are executed by tests/test_evidence_truncate_guard_sql.py on the live grants and registry.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. No function the engine runs is changed, no row is written but the
--   pre-image and the lineage row, and no atom reads a trigger or a grant.
--
-- ROLLBACK: for each table carrying ottoq_evidence_no_truncate_trg, DROP TRIGGER ottoq_evidence_no_truncate_trg ON it;
--   DROP TRIGGER ottoq_run_scope_registry_guards_evidence_trg ON public.ottoq_run_scope_registry; DROP FUNCTION
--   public.ottoq_run_scope_registry_guards_evidence(), public.ottoq_assert_evidence_truncate_guard(),
--   public.ottoq_guard_evidence_table(regclass), public.ottoq_evidence_truncate_guarded(regclass),
--   public.ottoq_evidence_no_truncate(); restore each table's grants from the `definition` in ottoq_schema_snapshots WHERE
--   label = '0748_pre' (93 tables: GRANT TRUNCATE ... TO service_role; the registry: GRANT INSERT, UPDATE, DELETE,
--   TRUNCATE ... TO service_role); DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0748_an_evidence_table_refuses_truncate_and_only_a_migration_says_what_is_evidence'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight, no run ticking ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0748 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('initializing', 'running')) THEN
    RAISE EXCEPTION '0748 P0: a run is ticking, and this file locks the ledgers its ticks write';
  END IF;
END $inflight$;

-- ── P1: the roles and the registry, the 100 tables measured, nothing of this file ──
DO $premises$
DECLARE v_n int; v_md5 text;
BEGIN
  IF (SELECT count(*) FROM pg_roles WHERE rolname IN ('anon', 'authenticated', 'service_role')) <> 3
     OR to_regclass('public.ottoq_run_scope_registry') IS NULL THEN
    RAISE EXCEPTION '0748 P1: the API roles or the run-scope registry are missing';
  END IF;
  SELECT count(*), md5(string_agg(t, ',' ORDER BY t COLLATE "C")) INTO v_n, v_md5
    FROM (SELECT DISTINCT g.table_schema || '.' || g.table_name AS t
            FROM public.ottoq_run_scope_registry g
           WHERE g.class = 'evidence'
             AND to_regclass(quote_ident(g.table_schema) || '.' || quote_ident(g.table_name)) IS NOT NULL) s;
  IF v_n <> 100 OR v_md5 IS DISTINCT FROM '5819248fb39a693829e5835fcd8c5fd3' THEN
    RAISE EXCEPTION '0748 P1: the evidence tables are not the 100 measured (% now, md5 %)', v_n, v_md5;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
               JOIN pg_class c ON c.oid = to_regclass(quote_ident(g.table_schema) || '.' || quote_ident(g.table_name))
              WHERE g.class = 'evidence' AND c.relkind <> 'r') THEN
    RAISE EXCEPTION '0748 P1: an evidence table is not a plain table';
  END IF;
  IF to_regprocedure('public.ottoq_evidence_no_truncate()') IS NOT NULL
     OR to_regprocedure('public.ottoq_evidence_truncate_guarded(regclass)') IS NOT NULL
     OR to_regprocedure('public.ottoq_guard_evidence_table(regclass)') IS NOT NULL
     OR to_regprocedure('public.ottoq_run_scope_registry_guards_evidence()') IS NOT NULL
     OR to_regprocedure('public.ottoq_assert_evidence_truncate_guard()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgname IN ('ottoq_evidence_no_truncate_trg',
                                                         'ottoq_run_scope_registry_guards_evidence_trg')) THEN
    RAISE EXCEPTION '0748 P1: a function or trigger of this file already exists';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0748_an_evidence_table_refuses_truncate_and_only_a_migration_says_what_is_evidence') THEN
    RAISE EXCEPTION '0748 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image: each table's grants ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0748_pre', 'grant', n.nspname, c.relname, COALESCE(c.relacl::text, 'NULL (the owner''s defaults only)'),
       md5(COALESCE(c.relacl::text, 'NULL (the owner''s defaults only)'))
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE c.oid IN (SELECT to_regclass(quote_ident(g.table_schema) || '.' || quote_ident(g.table_name))
                   FROM public.ottoq_run_scope_registry g WHERE g.class = 'evidence')
    OR c.oid = 'public.ottoq_run_scope_registry'::regclass;

CREATE TEMP TABLE _0748_grants ON COMMIT DROP AS
SELECT c.oid AS rel, r.rolname,
       has_table_privilege(r.rolname, c.oid, 'SELECT') AS sel, has_table_privilege(r.rolname, c.oid, 'INSERT') AS ins,
       has_table_privilege(r.rolname, c.oid, 'UPDATE') AS upd, has_table_privilege(r.rolname, c.oid, 'DELETE') AS del,
       has_table_privilege(r.rolname, c.oid, 'REFERENCES') AS ref, has_table_privilege(r.rolname, c.oid, 'TRIGGER') AS trg
  FROM pg_class c CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) r(rolname)
 WHERE c.oid IN (SELECT to_regclass(quote_ident(g.table_schema) || '.' || quote_ident(g.table_name))
                   FROM public.ottoq_run_scope_registry g WHERE g.class = 'evidence')
    OR c.oid = 'public.ottoq_run_scope_registry'::regclass;

-- ── (a) the refusal ──
CREATE FUNCTION public.ottoq_evidence_no_truncate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public'
AS $fn$
BEGIN
  --: a row trigger cannot see TRUNCATE, so an evidence table refuses it here (0748)
  IF COALESCE(current_setting('ottoq.evidence_truncate_unlock', true), '') = 'on' THEN
    RETURN NULL;
  END IF;
  RAISE EXCEPTION '%.% keeps every row: TRUNCATE refused (0748). Set ottoq.evidence_truncate_unlock=on in the transaction to override, and say why in a migration.',
    TG_TABLE_SCHEMA, TG_TABLE_NAME
    USING ERRCODE = '42501';
END $fn$;

-- ── (b) the one test of a guard ──
CREATE FUNCTION public.ottoq_evidence_truncate_guarded(p_table regclass)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $fn$
  -- an enabled BEFORE TRUNCATE trigger whose function is one of the named refusers: this file's, the agent ledgers'
  -- (0559) and the feed plan promotions' (0716). tgtype: 2 BEFORE, 32 TRUNCATE.
  SELECT EXISTS (
    SELECT 1
      FROM pg_trigger t
      JOIN pg_proc p ON p.oid = t.tgfoid
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE t.tgrelid = p_table AND NOT t.tgisinternal AND t.tgenabled IN ('O', 'A')
       AND (t.tgtype & 32) <> 0 AND (t.tgtype & 2) <> 0
       AND n.nspname = 'public'
       AND p.proname IN ('ottoq_evidence_no_truncate', 'ottoq_agent_no_truncate', 'ottoq_feed_plan_promotions_append_only'));
$fn$;

-- ── (c) guard one table ──
CREATE FUNCTION public.ottoq_guard_evidence_table(p_table regclass)
RETURNS text
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE v_kind "char"; v_name text; v_out text := 'already_guarded';
BEGIN
  SELECT c.relkind, format('%I.%I', n.nspname, c.relname) INTO v_kind, v_name
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE c.oid = p_table;
  IF v_kind IS NULL OR v_kind NOT IN ('r', 'p') THEN
    RETURN 'not_a_table';
  END IF;
  IF NOT public.ottoq_evidence_truncate_guarded(p_table) THEN
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = p_table AND tgname = 'ottoq_evidence_no_truncate_trg') THEN
      RAISE EXCEPTION '0748: % carries ottoq_evidence_no_truncate_trg disabled; enable it, or say why in a migration', v_name
        USING ERRCODE = '42501';
    END IF;
    EXECUTE format('CREATE TRIGGER ottoq_evidence_no_truncate_trg BEFORE TRUNCATE ON %s '
                   'FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_evidence_no_truncate()', v_name);
    v_out := 'guarded';
  END IF;
  EXECUTE format('REVOKE TRUNCATE ON TABLE %s FROM PUBLIC, anon, authenticated, service_role', v_name);
  RETURN v_out;
END $fn$;

-- ── (d) registering a table as evidence guards it ──
CREATE FUNCTION public.ottoq_run_scope_registry_guards_evidence()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE v_table regclass;
BEGIN
  --: the registry is written only by migrations, as the tables' owner, so this runs as that owner (0748)
  v_table := to_regclass(quote_ident(NEW.table_schema) || '.' || quote_ident(NEW.table_name));
  IF v_table IS NOT NULL THEN
    PERFORM public.ottoq_guard_evidence_table(v_table);
  END IF;
  RETURN NULL;
END $fn$;

-- ── (e) the assert ──
CREATE FUNCTION public.ottoq_assert_evidence_truncate_guard()
RETURNS TABLE (table_schema text, table_name text, problem text)
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $fn$
  WITH ev AS (
    SELECT DISTINCT g.table_schema, g.table_name,
           to_regclass(quote_ident(g.table_schema) || '.' || quote_ident(g.table_name)) AS rel
      FROM public.ottoq_run_scope_registry g
     WHERE g.class = 'evidence'
    UNION
    SELECT 'public', 'ottoq_run_scope_registry', 'public.ottoq_run_scope_registry'::regclass
  )
  SELECT ev.table_schema, ev.table_name, 'no refusing BEFORE TRUNCATE trigger'
    FROM ev WHERE ev.rel IS NOT NULL AND NOT public.ottoq_evidence_truncate_guarded(ev.rel)
  UNION ALL
  SELECT ev.table_schema, ev.table_name, r.rolname || ' holds TRUNCATE'
    FROM ev CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) r(rolname)
   WHERE ev.rel IS NOT NULL AND has_table_privilege(r.rolname, ev.rel, 'TRUNCATE')
  UNION ALL
  SELECT 'public', 'ottoq_run_scope_registry', r.rolname || ' may write the registry'
    FROM (VALUES ('anon'), ('authenticated'), ('service_role')) r(rolname)
   WHERE has_table_privilege(r.rolname, 'public.ottoq_run_scope_registry', 'INSERT, UPDATE, DELETE')
  ORDER BY 1, 2, 3;
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_evidence_no_truncate() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_evidence_truncate_guarded(regclass) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_guard_evidence_table(regclass) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_run_scope_registry_guards_evidence() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_assert_evidence_truncate_guard() FROM PUBLIC, anon, authenticated, service_role;

-- ── (f) guard the evidence tables and the registry, in a fixed order ──
DO $guard$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT to_regclass(quote_ident(g.table_schema) || '.' || quote_ident(g.table_name)) AS rel,
                  g.table_schema COLLATE "C" AS s, g.table_name COLLATE "C" AS t
             FROM public.ottoq_run_scope_registry g
            WHERE g.class = 'evidence'
              AND to_regclass(quote_ident(g.table_schema) || '.' || quote_ident(g.table_name)) IS NOT NULL
           UNION
           SELECT 'public.ottoq_run_scope_registry'::regclass, 'public', 'ottoq_run_scope_registry'
            ORDER BY s, t
  LOOP
    PERFORM public.ottoq_guard_evidence_table(r.rel);
  END LOOP;
END $guard$;

-- ── (g) only a migration writes the registry ──
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.ottoq_run_scope_registry
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER ottoq_run_scope_registry_guards_evidence_trg
  AFTER INSERT OR UPDATE OF class, table_schema, table_name ON public.ottoq_run_scope_registry
  FOR EACH ROW WHEN (NEW.class = 'evidence')
  EXECUTE FUNCTION public.ottoq_run_scope_registry_guards_evidence();

-- ── V1: the assert is empty ──
DO $v1$
DECLARE v text;
BEGIN
  SELECT string_agg(table_schema || '.' || table_name || ': ' || problem, '; ') INTO v
    FROM public.ottoq_assert_evidence_truncate_guard();
  IF v IS NOT NULL THEN
    RAISE EXCEPTION '0748 V1: %', v;
  END IF;
END $v1$;

-- ── V2: every other grant as it was, no API role truncates, the registry read and not written, 98 new triggers ──
DO $v2$
DECLARE v_moved int; v_trunc int; v_new int; v_dup int;
BEGIN
  SELECT count(*) INTO v_moved
    FROM _0748_grants g
   WHERE (g.sel, g.ref, g.trg) IS DISTINCT FROM (has_table_privilege(g.rolname, g.rel, 'SELECT'),
                                                 has_table_privilege(g.rolname, g.rel, 'REFERENCES'),
                                                 has_table_privilege(g.rolname, g.rel, 'TRIGGER'))
      OR (g.rel <> 'public.ottoq_run_scope_registry'::regclass
          AND (g.ins, g.upd, g.del) IS DISTINCT FROM (has_table_privilege(g.rolname, g.rel, 'INSERT'),
                                                      has_table_privilege(g.rolname, g.rel, 'UPDATE'),
                                                      has_table_privilege(g.rolname, g.rel, 'DELETE')));
  SELECT count(*) INTO v_trunc FROM _0748_grants g WHERE has_table_privilege(g.rolname, g.rel, 'TRUNCATE');
  IF v_moved <> 0 OR v_trunc <> 0 THEN
    RAISE EXCEPTION '0748 V2: % grants other than TRUNCATE moved, % API grants of TRUNCATE remain', v_moved, v_trunc;
  END IF;
  IF NOT has_table_privilege('service_role', 'public.ottoq_run_scope_registry', 'SELECT')
     OR has_table_privilege('service_role', 'public.ottoq_run_scope_registry', 'INSERT, UPDATE, DELETE, TRUNCATE') THEN
    RAISE EXCEPTION '0748 V2: service_role does not read the registry, or still writes it';
  END IF;
  SELECT count(*) INTO v_new FROM pg_trigger WHERE tgname = 'ottoq_evidence_no_truncate_trg';
  SELECT count(*) INTO v_dup FROM pg_trigger
   WHERE tgname = 'ottoq_evidence_no_truncate_trg'
     AND tgrelid IN ('public.ottoq_agent_requests'::regclass, 'public.ottoq_owner_commands'::regclass,
                     'public.ottoq_feed_plan_promotions'::regclass);
  IF v_new <> 98 OR v_dup <> 0 THEN
    RAISE EXCEPTION '0748 V2: % tables carry the new trigger (98 expected), % of them already guarded', v_new, v_dup;
  END IF;
END $v2$;

-- ── V3: the refusal, and the registry guarding a table it is told is evidence (both rolled back in their block) ──
DO $v3$
DECLARE v_state text; v_msg text;
BEGIN
  BEGIN
    TRUNCATE public.p7_band_probe_2026_08_03;
    RAISE EXCEPTION '0748 V3: TRUNCATE of public.p7_band_probe_2026_08_03 was not refused';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS DISTINCT FROM '42501' OR v_msg NOT LIKE 'public.p7_band_probe_2026_08_03 keeps every row%' THEN
    RAISE EXCEPTION '0748 V3: the refusal was % (%), not this file''s', v_state, v_msg;
  END IF;
  BEGIN
    CREATE TABLE public.ottoq_0748_probe_evidence (sim_run_id uuid);
    CREATE TABLE public.ottoq_0748_probe_engine (sim_run_id uuid);
    INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
    VALUES ('public', 'ottoq_0748_probe_evidence', 'sim_run_id', 'evidence', '0748 V3 probe, rolled back'),
           ('public', 'ottoq_0748_probe_engine', 'sim_run_id', 'engine', '0748 V3 probe, rolled back');
    IF NOT public.ottoq_evidence_truncate_guarded('public.ottoq_0748_probe_evidence'::regclass)
       OR has_table_privilege('service_role', 'public.ottoq_0748_probe_evidence', 'TRUNCATE')
       OR NOT has_table_privilege('service_role', 'public.ottoq_0748_probe_evidence', 'INSERT') THEN
      RAISE EXCEPTION '0748 V3: a table registered as evidence was not guarded at once, or lost more than TRUNCATE';
    END IF;
    IF public.ottoq_evidence_truncate_guarded('public.ottoq_0748_probe_engine'::regclass)
       OR NOT has_table_privilege('service_role', 'public.ottoq_0748_probe_engine', 'TRUNCATE') THEN
      RAISE EXCEPTION '0748 V3: a table registered as engine was guarded';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OT748', MESSAGE = 'probe passed';
  EXCEPTION WHEN SQLSTATE 'OT748' THEN
    NULL;
  END;
  IF to_regclass('public.ottoq_0748_probe_evidence') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry WHERE table_name LIKE 'ottoq_0748_probe%') THEN
    RAISE EXCEPTION '0748 V3: the probe was not rolled back';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0748_an_evidence_table_refuses_truncate_and_only_a_migration_says_what_is_evidence', false, false,
        'G456. public.ottoq_evidence_no_truncate (statement-level BEFORE TRUNCATE refusal, unlock '
        'ottoq.evidence_truncate_unlock) on the 97 evidence tables not already guarded and on ottoq_run_scope_registry; '
        'TRUNCATE revoked from PUBLIC, anon, authenticated and service_role on all 100 and the registry; INSERT, UPDATE, '
        'DELETE revoked from them on the registry; a registry row trigger guards a table registered as evidence; '
        'public.ottoq_assert_evidence_truncate_guard() empty. No engine function, row or atom changes.',
        now());

COMMIT;
