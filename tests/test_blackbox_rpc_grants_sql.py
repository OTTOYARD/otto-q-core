"""db/migrations/0720, the Black Box export functions closed to the browser roles, EXECUTED on a stub.

WHY THIS EXISTS. G435 (b), db/checks/0446 §5 (a): public.ottoq_run_blackbox(uuid) and ottoq_run_blackbox_meta(uuid) are
SECURITY DEFINER and executable by `authenticated`, and sign-up is open, so anyone who signs up could pull a whole run and
the engine's source in one call through /rest/v1/rpc without the edge function PR #243 locks. A grant change cannot be
proved by reading it, so this suite runs the file on a stub carrying both LIVE definitions (md5-pinned), both LIVE ACLs,
and the LIVE grants and row-security policies of the relations the stub holds, and asks the database, as each role, what
it can do:

  * before: a signed-in caller gets the whole bundle of a run (the defect, reproduced); the public key does not;
  * after: authenticated and anon are refused both with SQLSTATE 42501, and service_role, the edge function's role,
    still gets the bundle, byte for byte the same data; neither definition moved;
  * the file refuses a second run, a hotfixed definition, a moved ACL, a function or a view that calls the export, and
    a certification in flight; a mention in a comment is not a call;
  * its restore statements put both ACLs back exactly; the lineage row is FALSE/FALSE;
  * WHAT IT LEAVES OPEN, recorded rather than assumed away (G438): the same signed-in caller reads ottoq_decisions,
    ottoq_sim_runs, stalls and ottoq_schema_snapshots as tables, before the file and after it, as on live. What the file
    takes is what only the RPC gave: ottoq_owner_commands (no table grant), vehicles and ocpp_sessions (row security
    gives that caller none) and the current engine source.

Loads tests/fixtures/blackbox_rpc_grants_stub.sql. SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
from test_v2_door_sql import _conn_args, _drop, _new_db, _server_up  # noqa: E402

STUB = os.path.join(ROOT, "tests", "fixtures", "blackbox_rpc_grants_stub.sql")
MIG = os.path.join(ROOT, "db", "migrations", "0720_a_signed_in_user_cannot_call_the_black_box_export_functions.sql")
NAME = "0720_a_signed_in_user_cannot_call_the_black_box_export_functions"

pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

#: pg_get_functiondef md5s of the live definitions, read 2026-10-14 14:49:46 UTC
LIVE_MD5 = {"ottoq_run_blackbox(uuid)": "4f96d37ef15bcf3fac9a79023f99c729",
            "ottoq_run_blackbox_meta(uuid)": "06ec6069b1f08a5ce51a18e2e2764123"}
LIVE_ACL = "{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}"
AFTER_ACL = "{postgres=X/postgres,service_role=X/postgres}"
RUN = "d0000000-0000-4000-8000-000000000720"
BUNDLE = f"SELECT public.ottoq_run_blackbox('{RUN}')"
META = f"SELECT public.ottoq_run_blackbox_meta('{RUN}')"

MD5S = """SELECT string_agg(p.oid::regprocedure::text || '=' || md5(pg_get_functiondef(p.oid)), ' ' ORDER BY p.proname)
            FROM pg_proc p WHERE p.proname IN ('ottoq_run_blackbox', 'ottoq_run_blackbox_meta')"""
#: the ACLs as text, in the catalog's own order (what the live read returned)
ACLS = """SELECT string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, 'NULL'), ' ' ORDER BY p.proname)
            FROM pg_proc p WHERE p.proname IN ('ottoq_run_blackbox', 'ottoq_run_blackbox_meta')"""
#: who holds EXECUTE, as a set (a restored GRANT lands after service_role, so the text's order may differ)
HOLDERS = """SELECT string_agg(h, ' ' ORDER BY h) FROM (
              SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS h
                FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               WHERE p.proname IN ('ottoq_run_blackbox', 'ottoq_run_blackbox_meta')) x"""


def _as(db, role, sql):
    """Run one statement as a role, verbose so the SQLSTATE is printed; (ok, last line of output, stderr)."""
    p = subprocess.run(["psql", *_conn_args(), "-d", db.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose",
                        "-c", f"BEGIN; SET LOCAL ROLE {role}; {sql}; ROLLBACK;"], capture_output=True, text=True)
    out = [l for l in p.stdout.splitlines() if l.strip()]
    return p.returncode == 0, (out[-1] if out else ""), p.stderr


def _refused(db, role, sql):
    ok, _, err = _as(db, role, sql)
    return (not ok) and "42501" in err and "permission denied for function" in err


#: the claims PostgREST sets for a person who has just signed up: role authenticated, a user id no staff, fleet or
#: retail row names
SIGNED_IN = 'SET LOCAL request.jwt.claims TO \'{"role": "authenticated", "sub": "e0000000-0000-4000-8000-000000000720"}\''
#: what a caller reads through /rest/v1/<relation>, one count per relation the stub holds
TABLE_DOOR = {
    "ottoq_decisions": "SELECT count(*) FROM public.ottoq_decisions",
    "ottoq_sim_runs": "SELECT count(*) FROM public.ottoq_sim_runs",
    "stalls": "SELECT count(*) FROM public.stalls",
    "vehicles": "SELECT count(*) FROM public.vehicles",
    "ocpp_sessions": "SELECT count(*) FROM public.ocpp_sessions",
    "ottoq_owner_commands": "SELECT count(*) FROM public.ottoq_owner_commands",
    "ottoq_schema_snapshots(0720_pre functions)":
        "SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0720_pre' AND object_kind = 'function'",
}


def _table_door(db, role, claims=""):
    """{relation: row count, or 'refused' on 42501} as a role, with the JWT claims PostgREST would set."""
    seen = {}
    for rel, sql in TABLE_DOOR.items():
        ok, out, err = _as(db, role, f"{claims}; {sql}" if claims else sql)
        if ok:
            seen[rel] = int(out)
        else:
            assert "42501" in err and "permission denied for table" in err, err
            seen[rel] = "refused"
    return seen


def _load(extra_sql=None):
    d = _new_db()
    rc, err = d.file(STUB)
    assert rc == 0, f"stub did not load: {err}"
    if extra_sql:
        d.run(extra_sql)
    return d


@pytest.fixture(scope="module")
def db():
    d = _load()
    try:
        d.before = {"md5": d.val(MD5S), "acl": d.val(ACLS)}
        d.before["auth_bundle"] = _as(d, "authenticated", BUNDLE)
        d.before["auth_meta"] = _as(d, "authenticated", META)
        d.before["anon_bundle"] = _refused(d, "anon", BUNDLE)
        d.before["anon_meta"] = _refused(d, "anon", META)
        d.before["svc_bundle"] = _as(d, "service_role", BUNDLE)
        d.before["door_signed_in"] = _table_door(d, "authenticated", SIGNED_IN)
        d.before["door_anon"] = _table_door(d, "anon")
        rc, err = d.file(MIG)
        assert rc == 0, f"0720 did not apply on the stub: {err}"
        d.notices = err
        yield d
    finally:
        _drop(d)


def test_the_stub_carries_the_live_definitions_and_acls(db):
    assert db.before["md5"] == " ".join(f"{k}={v}" for k, v in sorted(LIVE_MD5.items()))
    assert db.before["acl"] == f"ottoq_run_blackbox(uuid)={LIVE_ACL} ottoq_run_blackbox_meta(uuid)={LIVE_ACL}"
    assert db.val("SELECT bool_and(prosecdef) FROM pg_proc WHERE proname IN ('ottoq_run_blackbox', 'ottoq_run_blackbox_meta')") == "t"
    # the discovery read the file leaves alone carries the live definition too
    assert db.val("SELECT md5(pg_get_functiondef('public.ottoq_blackbox_latest_run()'::regprocedure))") == \
        "5b9cdeeb55d4793022cc498ba04ee9f8"


def test_before_a_signed_in_caller_pulls_the_whole_run(db):
    ok, out, err = db.before["auth_bundle"]
    assert ok, err
    bundle = json.loads(out)
    assert bundle["sim_run_id"] == RUN and bundle["run"]["depot_id"] == "11111111-1111-1111-1111-111111111111"
    assert len(bundle["data"]["ottoq_decisions"]) == 2 and len(bundle["data"]["vehicles"]) == 2
    assert len(bundle["data"]["stalls"]) == 1 and len(bundle["data"]["ocpp_sessions"]) == 1
    assert len(bundle["data"]["ottoq_owner_commands"]) == 1
    assert "ottoq_run_blackbox" in bundle["executed_code"]              # and the engine's current source with it
    ok, out, err = db.before["auth_meta"]
    assert ok, err
    meta = json.loads(out)
    assert meta["run"]["sim_run_id"] == RUN and "ottoq_decisions" in meta["data_tables"]
    # part of that the same caller cannot get as a table: the RPC was the only door to these, as on live
    door = db.before["door_signed_in"]
    assert door["ottoq_owner_commands"] == "refused"                    # no table grant
    assert door["vehicles"] == 0 and door["ocpp_sessions"] == 0         # row security gives a new sign-up none
    # and part it can: the functions were NOT the whole door (G438), so the file is not quoted as closing run data
    assert door["ottoq_decisions"] == 2 and door["ottoq_sim_runs"] == 1 and door["stalls"] == 1
    # the public key was already refused before the file, as live
    assert db.before["anon_bundle"] and db.before["anon_meta"]


def test_the_file_reports_each_verification(db):
    for tag in ("0720 P2: before: AS authenticated|user authenticated|bundle answered|meta answered",
                "0720 V1 PASSED", "0720 V2 PASSED", "0720 V3 PASSED"):
        assert tag in db.notices, db.notices


def test_after_the_browser_roles_are_refused_42501(db):
    for role in ("authenticated", "anon"):
        for sql in (BUNDLE, META):
            assert _refused(db, role, sql), f"{role} may still: {sql}"
    assert db.val(ACLS) == f"ottoq_run_blackbox(uuid)={AFTER_ACL} ottoq_run_blackbox_meta(uuid)={AFTER_ACL}"
    for role in ("anon", "authenticated"):
        assert db.val(f"SELECT has_function_privilege('{role}', 'public.ottoq_run_blackbox(uuid)', 'EXECUTE')::text || "
                      f"has_function_privilege('{role}', 'public.ottoq_run_blackbox_meta(uuid)', 'EXECUTE')::text") == "falsefalse"


def test_after_the_table_door_stays_open_exactly_as_before_g438(db):
    """What 0720 does NOT close, as on live: a signed-in caller still reads these relations through /rest/v1/<relation>.

    Every count is the same before the file and after it, except that the file's own '0720_pre' snapshot rows, both
    export definitions, become readable to that caller through ottoq_schema_snapshots (row security off on live)."""
    after = _table_door(db, "authenticated", SIGNED_IN)
    before = dict(db.before["door_signed_in"])
    assert before.pop("ottoq_schema_snapshots(0720_pre functions)") == 0
    assert after.pop("ottoq_schema_snapshots(0720_pre functions)") == 2
    assert after == before == {"ottoq_decisions": 2, "ottoq_sim_runs": 1, "stalls": 1, "vehicles": 0,
                               "ocpp_sessions": 0, "ottoq_owner_commands": "refused"}
    # the public key reads only 0658's allowlist entry, before and after
    anon = _table_door(db, "anon")
    assert anon == db.before["door_anon"]
    assert anon["ottoq_decisions"] == 2 and anon["ottoq_sim_runs"] == "refused" and anon["stalls"] == "refused"
    # without the claims (no JWT), auth.role() is NULL, so the role-keyed policy on ottoq_sim_runs returns nothing:
    # the table door depends on the claims PostgREST sets, which is why the suite sets them
    assert _table_door(db, "authenticated")["ottoq_sim_runs"] == 0


def test_after_service_role_still_gets_the_same_bundle(db):
    ok, out, err = _as(db, "service_role", BUNDLE)
    assert ok, err
    after, before = json.loads(out), json.loads(db.before["svc_bundle"][1])
    for b in (after, before):
        b.pop("generated_at")
    assert after == before and len(after["data"]["ottoq_decisions"]) == 2
    ok, out, err = _as(db, "service_role", META)
    assert ok and json.loads(out)["run"]["sim_run_id"] == RUN, err
    # the owner, as the SQL editor and cron run, keeps it
    assert json.loads(db.val(META))["depot_id"] == "11111111-1111-1111-1111-111111111111"


def test_neither_definition_moved_and_the_discovery_read_is_untouched(db):
    assert db.val(MD5S) == db.before["md5"]
    ok, out, err = _as(db, "anon", "SELECT public.ottoq_blackbox_latest_run()")
    assert ok and json.loads(out)["sim_run_id"] == RUN, err


def test_it_refuses_a_second_run_and_classifies_itself_false_false(db):
    rc, err = db.file(MIG)
    assert rc != 0 and "0720 P1: 0720 has run already" in err, err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{NAME}'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0720_pre'") == "4"


def test_the_restore_statements_put_both_acls_back():
    d = _load()
    try:
        before = d.val(HOLDERS)
        rc, err = d.file(MIG)
        assert rc == 0, err
        assert d.val(HOLDERS) == "ottoq_run_blackbox:postgres ottoq_run_blackbox:service_role " \
                                 "ottoq_run_blackbox_meta:postgres ottoq_run_blackbox_meta:service_role"
        assert d.val("SELECT string_agg(object_name, ' ' ORDER BY snapshot_id) FROM public.ottoq_schema_snapshots "
                     "WHERE label = '0720_pre' AND object_kind = 'grant'") == \
            "ottoq_run_blackbox(uuid)::authenticated ottoq_run_blackbox_meta(uuid)::authenticated"
        d.run("""DO $restore$ DECLARE r record; BEGIN
                   FOR r IN SELECT definition FROM public.ottoq_schema_snapshots
                             WHERE label = '0720_pre' AND object_kind = 'grant' ORDER BY snapshot_id LOOP
                     EXECUTE r.definition;
                   END LOOP; END $restore$""")
        assert d.val(HOLDERS) == before and "authenticated" in before and "anon" not in before
        ok, _, err = _as(d, "authenticated", META)
        assert ok, err
    finally:
        _drop(d)


@pytest.mark.parametrize("extra, expect", [
    # someone hotfixed a definition in the SQL editor since the file was written
    ("CREATE OR REPLACE FUNCTION public.ottoq_run_blackbox_meta(p_sim_run_id uuid) RETURNS jsonb LANGUAGE sql STABLE "
     "SECURITY DEFINER AS 'SELECT ''{}''::jsonb'",
     "0720 P1: ottoq_run_blackbox_meta is not the definition this file was written against"),
    # the ACL moved: anon was granted, so this file's premise and its rollback are both wrong
    ("GRANT EXECUTE ON FUNCTION public.ottoq_run_blackbox(uuid) TO anon", "0720 P1: not a postgres-owned SECURITY DEFINER"),
    # a function now calls the export: revoking would break it unread
    ("CREATE FUNCTION public.ottoq_new_caller(p uuid) RETURNS jsonb LANGUAGE sql AS "
     "$f$ SELECT public.ottoq_run_blackbox_meta(p) $f$",
     "0720 P1: a function now calls the export functions; read it before revoking: public.ottoq_new_caller"),
    # by dynamic SQL too, where the name is in a string
    ("CREATE FUNCTION twin.ottoq_new_dynamic_caller(p uuid) RETURNS jsonb LANGUAGE plpgsql AS "
     "$f$ DECLARE r jsonb; BEGIN EXECUTE format('SELECT ottoq_run_blackbox(%L)', p) INTO r; RETURN r; END $f$",
     "twin.ottoq_new_dynamic_caller"),
    # a view a browser role could query: it needs EXECUTE as the reader
    ("CREATE VIEW public.ottoq_new_blackbox_view AS SELECT public.ottoq_run_blackbox_meta(sim_run_id) AS m FROM public.ottoq_sim_runs",
     "0720 P1: an object depends on the export functions"),
    # a certification in flight
    ("UPDATE public.stub_in_flight SET n = 1", "0720 P0:"),
])
def test_it_refuses_when_the_world_is_not_what_it_was_written_against(extra, expect):
    d = _load(extra)
    try:
        acl = d.val(ACLS)
        rc, err = d.file(MIG)
        assert rc != 0 and expect in err, err
        assert d.val(ACLS) == acl                                         # nothing changed on the way to a refusal
        assert d.val("SELECT count(*) FROM public.ottoq_cert_lineage") == "0"
    finally:
        _drop(d)


def test_a_mention_in_a_comment_is_not_a_call():
    d = _load("""CREATE FUNCTION public.ottoq_mentions_it() RETURNS int LANGUAGE plpgsql AS $f$
                 BEGIN
                   -- the edge function calls ottoq_run_blackbox_meta(run) as service_role
                   /* ottoq_run_blackbox(uuid) is the monolithic v1 */
                   RETURN 1;
                 END $f$""")
    try:
        rc, err = d.file(MIG)
        assert rc == 0 and "0720 V3 PASSED" in err, err
    finally:
        _drop(d)
