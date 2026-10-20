"""db/migrations/0749, EXECUTED: an evidence table is not dropped by accident.

WHY THIS EXISTS. 102 of the 202 tables the run-scope registry classes as evidence are gone, and nothing in the database
refused the DROP that took them or recorded it (G463). 0749 adds an event trigger on sql_drop that refuses a statement
whose dropped objects include an evidence table or the registry itself, unless the transaction unlocks it. It is applied
here as written, the whole file, on the scratch PostgreSQL, against the live shape it reads (tests/fixtures/
evidence_truncate_stub.sql, the 100 evidence tables by name with their registry rows and grants, as read on 2026-10-17):
  - a DROP of an evidence table, of the registry, of a schema holding evidence (CASCADE), or of several tables one of
    which is evidence, is refused whole with 42501, naming what it would have taken;
  - an engine table, an unregistered table, a temporary table and a column of an evidence table can still be dropped;
  - the unlock lasts one transaction;
  - with 0748 applied first, a table registered as evidence cannot be dropped from that moment;
  - a second apply is refused, P0 refuses while a rig is going, and no API role can call the function.
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
M0749 = os.path.join(ROOT, "db", "migrations", "0749_an_evidence_table_is_not_dropped_by_accident.sql")
LINEAGE = "0749_an_evidence_table_is_not_dropped_by_accident"
REFUSED = "evidence is not dropped (0749)"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_edt_{os.getpid()}_{uuid.uuid4().hex[:6]}"
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
    name = f"ottoq_ed_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _applied(d, path=M0749):
    rc, err = d.file(path)
    assert rc == 0, f"{os.path.basename(path)} did not apply: {err}"


def _refused(d, sql, needle):
    rc, _, err = d.run(sql)
    assert rc != 0, f"not refused: {sql}"
    assert needle in err, f"refused for another reason: {err}"


def _exists(d, rel):
    return d.val(f"SELECT to_regclass('{rel}') IS NOT NULL") == "t"


def test_an_evidence_table_the_registry_and_a_schema_holding_evidence_are_not_dropped(db):
    _applied(db)
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{LINEAGE}'") == "falsefalse"
    _refused(db, "DROP TABLE public.ottoq_model_call_ledger",
             f"{REFUSED}: public.ottoq_model_call_ledger. Set ottoq.evidence_drop_unlock=on")
    _refused(db, "DROP TABLE public.ottoq_run_scope_registry", f"{REFUSED}: public.ottoq_run_scope_registry.")
    _refused(db, "DROP SCHEMA proof_0015 CASCADE", f"{REFUSED}: proof_0015.hold_forecast_capture, proof_0015.tick_samples.")
    for rel in ("public.ottoq_model_call_ledger", "public.ottoq_run_scope_registry", "proof_0015.tick_samples",
                "proof_0015.hold_forecast_capture"):
        assert _exists(db, rel), rel
    assert db.val("SELECT count(*) FROM public.ottoq_model_call_ledger") == "1"
    # every one of the 100 is refused
    rels = db.val("""SELECT string_agg(DISTINCT quote_ident(table_schema) || '.' || quote_ident(table_name), ' ')
                       FROM public.ottoq_run_scope_registry
                      WHERE class = 'evidence'
                        AND to_regclass(quote_ident(table_schema) || '.' || quote_ident(table_name)) IS NOT NULL""").split()
    assert len(rels) == 100
    for rel in rels:
        rc, _, err = db.run(f"DROP TABLE {rel} CASCADE")
        assert rc != 0 and REFUSED in err, (rel, err)


def test_a_drop_of_several_tables_one_of_them_evidence_is_refused_whole(db):
    _applied(db)
    db.val("CREATE TABLE public.t_scratch (x int)")
    _refused(db, "DROP TABLE public.t_scratch, public.ottoq_ab_runs", f"{REFUSED}: public.ottoq_ab_runs.")
    assert _exists(db, "public.t_scratch") and _exists(db, "public.ottoq_ab_runs")
    # a CASCADE that would also take what depends on an evidence table is refused, and leaves that standing too
    db.val("CREATE VIEW public.t_view_on_ledger AS SELECT * FROM public.ottoq_model_call_ledger")
    _refused(db, "DROP TABLE public.ottoq_model_call_ledger CASCADE", f"{REFUSED}: public.ottoq_model_call_ledger.")
    assert _exists(db, "public.t_view_on_ledger")
    db.val("DROP VIEW public.t_view_on_ledger")


def test_what_is_not_evidence_is_still_dropped(db):
    _applied(db)
    db.val("DROP TABLE public.cuopt_invocation_log")             # registered, as engine
    assert not _exists(db, "public.cuopt_invocation_log")
    db.val("CREATE TABLE public.t_scratch (x int); DROP TABLE public.t_scratch")
    assert not _exists(db, "public.t_scratch")
    # a temporary table of the same name as an evidence table passes
    assert db.val("""CREATE TEMP TABLE ottoq_model_call_ledger (x int);
                     DROP TABLE pg_temp.ottoq_model_call_ledger;
                     SELECT 'ok'""") == "ok"
    # a column of an evidence table may be dropped: a schema change a migration says why for in its own file
    db.val("ALTER TABLE public.ottoq_model_call_ledger ADD COLUMN t_extra int")
    db.val("ALTER TABLE public.ottoq_model_call_ledger DROP COLUMN t_extra")
    # a table created again under a registered evidence name is evidence again
    db.val("CREATE TABLE public.band_ab_compare_2026_08_01 (sim_run_id uuid)")
    _refused(db, "DROP TABLE public.band_ab_compare_2026_08_01", f"{REFUSED}: public.band_ab_compare_2026_08_01.")


def test_a_role_that_cannot_read_the_registry_still_drops_its_own_table(db):
    """An event trigger runs as the role that issued the statement. The function is SECURITY DEFINER so that a role
    without SELECT on the registry (a platform role dropping its own table) is not refused by a permission error."""
    _applied(db)
    db.val("""DO $r$ BEGIN
                IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 't_platform_role') THEN CREATE ROLE t_platform_role NOLOGIN; END IF;
              END $r$;
              CREATE SCHEMA t_platform AUTHORIZATION t_platform_role;
              REVOKE ALL ON public.ottoq_run_scope_registry FROM t_platform_role""")
    assert db.val("SELECT has_table_privilege('t_platform_role', 'public.ottoq_run_scope_registry', 'SELECT')") == "f"
    assert db.val("""SET ROLE t_platform_role;
                     CREATE TABLE t_platform.own_table (x int);
                     DROP TABLE t_platform.own_table;
                     SELECT to_regclass('t_platform.own_table') IS NULL""") == "t"
    assert db.val("SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_evidence_no_drop()'::regprocedure") == "t"


def test_the_unlock_lasts_one_transaction(db):
    _applied(db)
    assert db.val("""BEGIN;
                     SET LOCAL ottoq.evidence_drop_unlock = on;
                     DROP TABLE public.ottoq_ab_runs;
                     SELECT to_regclass('public.ottoq_ab_runs') IS NULL;
                     ROLLBACK;""") == "t"
    assert _exists(db, "public.ottoq_ab_runs")
    _refused(db, "BEGIN; SET LOCAL ottoq.evidence_drop_unlock = on; COMMIT; DROP TABLE public.ottoq_ab_runs", REFUSED)
    # 0748's TRUNCATE unlock does not open a drop
    _refused(db, "BEGIN; SET LOCAL ottoq.evidence_truncate_unlock = on; DROP TABLE public.ottoq_ab_runs; ROLLBACK", REFUSED)


def test_with_0748_applied_first_a_table_registered_as_evidence_is_kept_at_once(db):
    _applied(db, M0748)
    _applied(db)
    db.val("CREATE TABLE public.t_new_ledger (sim_run_id uuid)")
    db.val("""INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
              VALUES ('public', 't_new_ledger', 'sim_run_id', 'evidence', 'test')""")
    _refused(db, "DROP TABLE public.t_new_ledger", f"{REFUSED}: public.t_new_ledger.")
    _refused(db, "TRUNCATE public.t_new_ledger", "public.t_new_ledger keeps every row: TRUNCATE refused (0748)")
    # reclassified to engine by a migration, it may be dropped again
    db.val("UPDATE public.ottoq_run_scope_registry SET class = 'engine' WHERE table_name = 't_new_ledger'")
    db.val("DROP TABLE public.t_new_ledger")
    assert not _exists(db, "public.t_new_ledger")


def test_a_second_apply_and_a_rig_in_flight_are_refused(db):
    db.val(f"ALTER DATABASE {db.name} SET ottoq.simulate_certification_in_flight = 'on'")
    rc, err = db.file(M0749)
    assert rc != 0 and "0749 P0: a pair" in err, err
    db.val(f"ALTER DATABASE {db.name} RESET ottoq.simulate_certification_in_flight")
    assert db.val("SELECT count(*) FROM pg_event_trigger WHERE evtname = 'ottoq_evidence_no_drop'") == "0"
    assert db.val("SELECT to_regprocedure('public.ottoq_evidence_no_drop()') IS NULL") == "t"
    _applied(db)
    rc, err = db.file(M0749)
    assert rc != 0 and "0749 P1: the function or the event trigger of this file already exists" in err, err


def test_no_api_role_calls_the_function(db):
    _applied(db)
    for role in ("anon", "authenticated", "service_role"):
        assert db.val(f"SELECT has_function_privilege('{role}', 'public.ottoq_evidence_no_drop()', 'EXECUTE')") == "f", role
