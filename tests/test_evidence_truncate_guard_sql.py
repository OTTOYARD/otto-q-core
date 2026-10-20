"""db/migrations/0748, EXECUTED: an evidence table refuses TRUNCATE, and only a migration says what is evidence.

WHY THIS EXISTS. The run-scope registry's evidence class promises that a table outlives every run, and the live ledgers
among it refuse UPDATE and DELETE by row trigger. A TRUNCATE fires no row trigger, and the project's default privileges
gave service_role TRUNCATE on 93 of the 100 evidence tables; the registry, the list that says what is evidence, was
writable by the same key (G456). 0748 is applied here as written, the whole file, on the scratch PostgreSQL, against the
live shape it reads (tests/fixtures/evidence_truncate_stub.sql: the 100 tables by name, their registry rows and grants,
the default privileges postgres holds in public, and the two refusers already guarding three of them, by their live
bodies, md5 asserted as read on 2026-10-17):
  - every evidence table and the registry refuse TRUNCATE as the owner, by this file's message or the guard they already
    had, and as service_role by privilege; a TRUNCATE ... CASCADE that reaches one is refused whole;
  - a transaction that sets ottoq.evidence_truncate_unlock=on may truncate, and the unlock lasts the transaction only;
  - every grant but TRUNCATE is as it was, the registry is read by service_role and written by no API role;
  - registering a table as evidence guards it at once, by insert or by a change of class, and an engine row does not;
  - the assert is empty after the file and names each kind of drift; the guard refuses a table whose trigger was
    disabled on purpose;
  - P0 refuses while a rig or a run is going, P1 while the evidence set is not the 100 measured, and a refused apply
    leaves nothing behind;
  - no API role can call any of the new functions: a migration runs them.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)

ROOT = base.ROOT
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "evidence_truncate_stub.sql")
M0748 = os.path.join(ROOT, "db", "migrations",
                     "0748_an_evidence_table_refuses_truncate_and_only_a_migration_says_what_is_evidence.sql")
LINEAGE = "0748_an_evidence_table_refuses_truncate_and_only_a_migration_says_what_is_evidence"
SET_MD5 = "5819248fb39a693829e5835fcd8c5fd3"
# the live bodies the fixture carries (md5 of prosrc, read from the live catalog on 2026-10-17)
LIVE = {
    "public.ottoq_agent_no_truncate()": "f76a3f6186dc2b936fcfd66fa4e09d73",
    "public.ottoq_feed_plan_promotions_append_only()": "170825410d889b1cbce6a3d7bb919188",
}
ALREADY_GUARDED = ("public.ottoq_agent_requests", "public.ottoq_owner_commands", "public.ottoq_feed_plan_promotions")
NEW_FUNCTIONS = ("public.ottoq_evidence_no_truncate()", "public.ottoq_evidence_truncate_guarded(regclass)",
                 "public.ottoq_guard_evidence_table(regclass)", "public.ottoq_run_scope_registry_guards_evidence()",
                 "public.ottoq_assert_evidence_truncate_guard()")
EVIDENCE = """SELECT DISTINCT to_regclass(quote_ident(table_schema) || '.' || quote_ident(table_name)) AS rel
                FROM public.ottoq_run_scope_registry
               WHERE class = 'evidence' AND to_regclass(quote_ident(table_schema) || '.' || quote_ident(table_name)) IS NOT NULL"""

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_evt_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        rc, err = d.file(FIXTURE)
        assert rc == 0, f"the fixture did not load: {err}"
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_ev_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply(d):
    return d.file(M0748)


def _applied(d):
    rc, err = _apply(d)
    assert rc == 0, f"0748 did not apply: {err}"


def _refused(d, sql, needle):
    rc, _, err = d.run(sql)
    assert rc != 0, f"not refused: {sql}"
    assert needle in err, f"refused for another reason: {err}"


def _grants(d):
    """Every grant but TRUNCATE the three API roles hold on the evidence tables and the registry."""
    return d.json(f"""SELECT json_object_agg(rel::text || ':' || r, p ORDER BY rel::text, r) FROM (
        SELECT e.rel, r.r,
               ARRAY[has_table_privilege(r.r, e.rel, 'SELECT'), has_table_privilege(r.r, e.rel, 'INSERT'),
                     has_table_privilege(r.r, e.rel, 'UPDATE'), has_table_privilege(r.r, e.rel, 'DELETE'),
                     has_table_privilege(r.r, e.rel, 'REFERENCES'), has_table_privilege(r.r, e.rel, 'TRIGGER')] AS p
          FROM ({EVIDENCE} UNION SELECT 'public.ottoq_run_scope_registry'::regclass) e
         CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) r(r)) x""")


def test_the_fixture_is_the_live_shape(db):
    for fn, md5 in LIVE.items():
        assert db.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')") == md5, fn
    assert db.val(f"""SELECT count(*) || ' ' || md5(string_agg(t, ',' ORDER BY t COLLATE "C")) FROM (
                        SELECT DISTINCT table_schema || '.' || table_name AS t FROM public.ottoq_run_scope_registry
                         WHERE class = 'evidence'
                           AND to_regclass(quote_ident(table_schema) || '.' || quote_ident(table_name)) IS NOT NULL) s""") \
        == f"100 {SET_MD5}"
    assert db.val(f"SELECT count(*) FROM ({EVIDENCE}) e WHERE has_table_privilege('service_role', e.rel, 'TRUNCATE')") == "93"
    assert db.val(f"""SELECT count(*) FROM ({EVIDENCE}) e
                       WHERE has_table_privilege('anon', e.rel, 'TRUNCATE')
                          OR has_table_privilege('authenticated', e.rel, 'TRUNCATE')""") == "0"
    assert db.val("SELECT has_table_privilege('service_role', 'public.ottoq_run_scope_registry', 'INSERT')") == "t"
    # the registry lists three evidence tables that no longer exist; nothing here truncates yet
    assert db.val("""SELECT count(*) FROM (SELECT DISTINCT table_name FROM public.ottoq_run_scope_registry
                       WHERE class = 'evidence' AND to_regclass('public.' || quote_ident(table_name)) IS NULL
                         AND table_schema = 'public') s""") == "3"


def test_the_file_applies_and_every_evidence_table_refuses_truncate(db):
    before = _grants(db)
    _applied(db)
    assert db.val("SELECT count(*) FROM public.ottoq_assert_evidence_truncate_guard()") == "0"
    rels = db.val(f"SELECT string_agg(rel::text, ' ' ORDER BY rel::text) FROM ({EVIDENCE}) e").split() \
        + ["ottoq_run_scope_registry"]
    assert len(rels) == 101
    for rel in rels:
        rc, _, err = db.run(f"TRUNCATE {rel}")
        assert rc != 0 and ("TRUNCATE refused" in err or "append-only evidence (0716)" in err), (rel, err)
        rc, _, err = db.run(f"SET ROLE service_role; TRUNCATE {rel}")
        assert rc != 0 and "permission denied" in err, (rel, err)
    # this file's message names the table, schema first
    _refused(db, "TRUNCATE proof_0015.tick_samples", "proof_0015.tick_samples keeps every row: TRUNCATE refused (0748)")
    # the three already guarded keep their own guard and gain no second
    for rel in ALREADY_GUARDED:
        assert db.val(f"""SELECT count(*) FROM pg_trigger WHERE tgrelid = '{rel}'::regclass
                           AND tgname = 'ottoq_evidence_no_truncate_trg'""") == "0", rel
    assert db.val("SELECT count(*) FROM pg_trigger WHERE tgname = 'ottoq_evidence_no_truncate_trg'") == "98"
    # an engine table that exists is left as it was
    assert db.val("SELECT has_table_privilege('service_role', 'public.cuopt_invocation_log', 'TRUNCATE')") == "t"
    assert db.val("SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.cuopt_invocation_log'::regclass") == "0"
    # every grant but TRUNCATE is as it was, but the registry's writes
    after = _grants(db)
    moved = {k for k in before if before[k] != after[k]}
    assert moved == {"ottoq_run_scope_registry:service_role"}, moved
    assert after["ottoq_run_scope_registry:service_role"] == [True, False, False, False, True, True]
    # the pre-image holds each table's grants, the lineage row is false/false
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0748_pre' AND object_kind = 'grant'") \
        == "101"
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{LINEAGE}'") == "falsefalse"


def test_the_unlock_lets_a_transaction_truncate_and_lasts_that_transaction(db):
    _applied(db)
    out = db.val("""BEGIN;
                    SET LOCAL ottoq.evidence_truncate_unlock = on;
                    TRUNCATE public.ottoq_model_call_ledger;
                    SELECT count(*) FROM public.ottoq_model_call_ledger;
                    ROLLBACK;""")
    assert out == "0"
    assert db.val("SELECT count(*) FROM public.ottoq_model_call_ledger") == "1"
    # set for one transaction, it is gone in the next
    _refused(db, """BEGIN; SET LOCAL ottoq.evidence_truncate_unlock = on; COMMIT;
                    TRUNCATE public.ottoq_model_call_ledger""", "TRUNCATE refused (0748)")
    # the agent ledgers' own unlock does not open an evidence table, nor this one theirs
    _refused(db, "BEGIN; SET LOCAL ottoq.agent_ledger_unlock = on; TRUNCATE public.ottoq_model_call_ledger; ROLLBACK",
             "TRUNCATE refused (0748)")
    _refused(db, "BEGIN; SET LOCAL ottoq.evidence_truncate_unlock = on; TRUNCATE public.ottoq_owner_commands; ROLLBACK",
             "ottoq_owner_commands keeps every row: TRUNCATE refused. Set ottoq.agent_ledger_unlock=on")


def test_a_cascade_that_reaches_an_evidence_table_is_refused_whole(db):
    db.val("""CREATE TABLE public.t_parent (id uuid PRIMARY KEY);
              INSERT INTO public.t_parent VALUES ('a0000000-0000-0000-0000-000000000748');
              ALTER TABLE public.ottoq_model_call_ledger
                ADD CONSTRAINT t_parent_fk FOREIGN KEY (sim_run_id) REFERENCES public.t_parent (id)""")
    _applied(db)
    _refused(db, "TRUNCATE public.t_parent CASCADE", "ottoq_model_call_ledger keeps every row")
    assert db.val("SELECT count(*) FROM public.t_parent") == "1"
    assert db.val("SELECT count(*) FROM public.ottoq_model_call_ledger") == "1"


def test_registering_a_table_as_evidence_guards_it_at_once(db):
    _applied(db)
    db.val("""CREATE TABLE public.t_new_ledger (sim_run_id uuid, run_b uuid);
              CREATE TABLE public.t_new_engine (sim_run_id uuid)""")
    # it takes TRUNCATE for service_role from the default privileges, as a new table does live
    assert db.val("SELECT has_table_privilege('service_role', 'public.t_new_ledger', 'TRUNCATE')") == "t"
    db.val("""INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
              VALUES ('public', 't_new_ledger', 'sim_run_id', 'evidence', 'test'),
                     ('public', 't_new_engine', 'sim_run_id', 'engine', 'test'),
                     ('public', 't_not_yet_created', 'sim_run_id', 'evidence', 'test')""")
    assert db.val("SELECT public.ottoq_evidence_truncate_guarded('public.t_new_ledger')") == "t"
    assert db.val("""SELECT has_table_privilege('service_role', 'public.t_new_ledger', 'TRUNCATE')::text
                            || has_table_privilege('service_role', 'public.t_new_ledger', 'INSERT')::text""") == "falsetrue"
    assert db.val("SELECT public.ottoq_evidence_truncate_guarded('public.t_new_engine')") == "f"
    assert db.val("SELECT has_table_privilege('service_role', 'public.t_new_engine', 'TRUNCATE')") == "t"
    # a second evidence column of the same table adds no second trigger
    db.val("""INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
              VALUES ('public', 't_new_ledger', 'run_b', 'evidence', 'test')""")
    assert db.val("SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.t_new_ledger'::regclass") == "1"
    # reclassified to evidence, the engine table is guarded
    db.val("UPDATE public.ottoq_run_scope_registry SET class = 'evidence' WHERE table_name = 't_new_engine'")
    assert db.val("SELECT public.ottoq_evidence_truncate_guarded('public.t_new_engine')") == "t"
    _refused(db, "TRUNCATE public.t_new_engine", "public.t_new_engine keeps every row")
    # a table registered before it exists is the assert's; created later, it is named until it is guarded
    assert db.val("SELECT count(*) FROM public.ottoq_assert_evidence_truncate_guard()") == "0"
    db.val("CREATE TABLE public.t_not_yet_created (sim_run_id uuid)")
    assert db.val("SELECT string_agg(problem, '; ' ORDER BY problem) FROM public.ottoq_assert_evidence_truncate_guard() "
                  "WHERE table_name = 't_not_yet_created'") == "no refusing BEFORE TRUNCATE trigger; service_role holds TRUNCATE"
    assert db.val("SELECT public.ottoq_guard_evidence_table('public.t_not_yet_created')") == "guarded"
    assert db.val("SELECT public.ottoq_guard_evidence_table('public.t_not_yet_created')") == "already_guarded"
    assert db.val("SELECT count(*) FROM public.ottoq_assert_evidence_truncate_guard()") == "0"


def test_only_a_migration_writes_the_registry(db):
    _applied(db)
    assert db.val("SET ROLE service_role; SELECT count(*) > 100 FROM public.ottoq_run_scope_registry") == "t"
    for sql in ("INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class) "
                "VALUES ('public', 'x', 'y', 'engine')",
                "UPDATE public.ottoq_run_scope_registry SET class = 'engine' WHERE table_name = 'ottoq_model_call_ledger'",
                "DELETE FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_model_call_ledger'",
                "TRUNCATE public.ottoq_run_scope_registry"):
        _refused(db, f"SET ROLE service_role; {sql}", "permission denied")
        _refused(db, f"SET ROLE authenticated; {sql}", "permission denied")
    assert db.val("SELECT class FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_model_call_ledger'") == "evidence"


def test_the_assert_names_each_drift_and_the_guard_refuses_a_disabled_trigger(db):
    _applied(db)
    db.val("""DROP TRIGGER ottoq_evidence_no_truncate_trg ON public.ottoq_ab_runs;
              GRANT TRUNCATE ON public.ottoq_challenger_findings TO service_role;
              ALTER TABLE public.ottoq_run_dial_ledger DISABLE TRIGGER ottoq_evidence_no_truncate_trg;
              GRANT INSERT ON public.ottoq_run_scope_registry TO authenticated""")
    got = db.val("SELECT string_agg(table_name || ': ' || problem, ' | ' ORDER BY table_name, problem) "
                 "FROM public.ottoq_assert_evidence_truncate_guard()")
    assert got == ("ottoq_ab_runs: no refusing BEFORE TRUNCATE trigger | "
                   "ottoq_challenger_findings: service_role holds TRUNCATE | "
                   "ottoq_run_dial_ledger: no refusing BEFORE TRUNCATE trigger | "
                   "ottoq_run_scope_registry: authenticated may write the registry"), got
    # the dropped trigger is put back, the disabled one is refused: someone chose that
    assert db.val("SELECT public.ottoq_guard_evidence_table('public.ottoq_ab_runs')") == "guarded"
    _refused(db, "SELECT public.ottoq_guard_evidence_table('public.ottoq_run_dial_ledger')",
             "carries ottoq_evidence_no_truncate_trg disabled")
    assert db.val("SELECT public.ottoq_guard_evidence_table('public.ottoq_challenger_findings')") == "already_guarded"
    assert db.val("SELECT has_table_privilege('service_role', 'public.ottoq_challenger_findings', 'TRUNCATE')") == "f"
    # a view is not a table, and is passed over
    db.val("CREATE VIEW public.t_view AS SELECT 1 AS x")
    assert db.val("SELECT public.ottoq_guard_evidence_table('public.t_view')") == "not_a_table"


def test_the_premises_refuse_and_a_refused_apply_leaves_nothing(db):
    # P0: a rig in flight, then a run ticking
    for setup, needle in (("ALTER DATABASE {db} SET ottoq.simulate_certification_in_flight = 'on'", "0748 P0: a pair"),
                          ("INSERT INTO public.ottoq_sim_runs VALUES ('a0000000-0000-0000-0000-000000000748', 'running')",
                           "0748 P0: a run is ticking"),
                          ("INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class) "
                           "VALUES ('public', 'cuopt_invocation_log', 'tick_seq', 'evidence')",
                           "0748 P1: the evidence tables are not the 100 measured (101 now")):
        db.val(setup.format(db=db.name))
        rc, err = _apply(db)
        assert rc != 0 and needle in err, err
        db.val(f"ALTER DATABASE {db.name} RESET ottoq.simulate_certification_in_flight")
        db.val("DELETE FROM public.ottoq_sim_runs; DELETE FROM public.ottoq_run_scope_registry WHERE column_name = 'tick_seq' "
               "AND table_name = 'cuopt_invocation_log'")
        for fn in NEW_FUNCTIONS:
            assert db.val(f"SELECT to_regprocedure('{fn}') IS NULL") == "t", fn
        assert db.val("SELECT count(*) FROM pg_trigger WHERE tgname = 'ottoq_evidence_no_truncate_trg'") == "0"
        assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots") == "0"
    # a paused run does not tick, and does not hold the file
    db.val("INSERT INTO public.ottoq_sim_runs VALUES ('a0000000-0000-0000-0000-000000000748', 'paused')")
    _applied(db)
    # P2: once applied, a second apply is refused before it touches anything
    rc, err = _apply(db)
    assert rc != 0 and "0748 P1: a function or trigger of this file already exists" in err, err


def test_no_api_role_calls_the_new_functions(db):
    _applied(db)
    for fn in NEW_FUNCTIONS:
        for role in ("anon", "authenticated", "service_role"):
            assert db.val(f"SELECT has_function_privilege('{role}', '{fn}', 'EXECUTE')") == "f", (role, fn)
    _refused(db, "SET ROLE service_role; SELECT public.ottoq_guard_evidence_table('public.cuopt_invocation_log')",
             "permission denied for function ottoq_guard_evidence_table")
    _refused(db, "SET ROLE service_role; SELECT count(*) FROM public.ottoq_assert_evidence_truncate_guard()",
             "permission denied for function ottoq_assert_evidence_truncate_guard")
