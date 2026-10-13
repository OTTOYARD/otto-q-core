"""db/migrations/0701, the signing key and the engine's destructive doors closed to the browser roles, EXECUTED on a stub.

WHY THIS EXISTS. G421: public.ottoq_resolve_signing_secret returned the HMAC key that signs every event, SDR and audit
bundle to any signed-in caller, the three signers signed whatever a caller asked, and purge, run-start and audit writers
were callable the same way; the resolver also believed two settings before Vault and cached the key for a whole pooled
session; and every new public function was born executable by anon, authenticated and PUBLIC. A grant change cannot be
proved by reading it, so this suite runs the file on a stub carrying the LIVE bodies of the resolver and the three
signers and asks the database, as each role, what it can do:

  * before: a signed-in caller reads the key and signs; a planted setting changes the system's signature;
  * after: the browser roles are refused the key, the signers, the purge and the writers, while service_role and a
    SECURITY DEFINER engine caller still sign, byte for byte as before;
  * the cache lives for one transaction only, under a name no earlier version wrote, and a planted setting (old names,
    the new name, a stale stamp) is never believed;
  * a function created later is closed to anon, authenticated and PUBLIC in public, keeps service_role in twin and
    ottoq, keeps PUBLIC in extensions, and is the owner's alone in a new schema;
  * the file refuses a hotfixed resolver, an unread SECURITY INVOKER path to a target, and a second run; and its
    restore statements put the resolver, every grant and every default privilege back exactly.

Loads tests/fixtures/signing_grants_stub.sql. SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
from test_v2_door_sql import _drop, _new_db, _server_up  # noqa: E402

STUB = os.path.join(ROOT, "tests", "fixtures", "signing_grants_stub.sql")
MIG = os.path.join(ROOT, "db", "migrations", "0701_a_signed_in_user_cannot_read_the_signing_key_or_sign_or_purge.sql")

pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

SIGN_EVENT = ("public.ottoq_sign_event('00000000-0000-4000-8000-000000000701', '2026-10-13 00:00:00+00', 'system', "
              "'probe', 'probe', NULL, md5('t'), 'system:v1')")
CACHE = "'ottoq.sigcache_' || md5('system:v1')"

#: every EXECUTE grant on a public function, as "fn(args):grantee"; the before/after of the rollback
FN_GRANTS = """
SELECT coalesce(string_agg(p.oid::regprocedure::text || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
                           ' ' ORDER BY p.oid::regprocedure::text, a.grantee), '')
  FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
 WHERE p.pronamespace = 'public'::regnamespace
"""
DEFAULT_ACL = """
SELECT coalesce(string_agg(CASE WHEN d.defaclnamespace = 0 THEN '(global)' ELSE d.defaclnamespace::regnamespace::text END || ':'
                           || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END || '=' || a.privilege_type,
                           ' ' ORDER BY 1), '')
  FROM pg_default_acl d CROSS JOIN LATERAL aclexplode(d.defaclacl) a
 WHERE d.defaclrole = 'postgres'::regrole AND d.defaclobjtype = 'f'
"""
CENSUS = """
SELECT count(*) FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace AND p.prosecdef AND p.provolatile = 'v' AND p.prokind = 'f'
   AND p.prorettype <> 'trigger'::regtype
   AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))
"""
RESOLVER_MD5 = "SELECT md5(pg_get_functiondef('public.ottoq_resolve_signing_secret(text)'::regprocedure))"


def _as(db, role, sql):
    """Run one statement as a role; (ok, last line, message)."""
    rc, out, err = db.run(f"BEGIN; SET LOCAL ROLE {role}; {sql}; ROLLBACK;", check=False)
    return rc == 0, out, (err or out)


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
        d.before = {
            "sig": d.val(f"SELECT {SIGN_EVENT}"),
            "grants": d.val(FN_GRANTS),
            "default": d.val(DEFAULT_ACL),
            "census": int(d.val(CENSUS)),
            "resolver": d.val(RESOLVER_MD5),
        }
        d.before["auth_key"] = _as(d, "authenticated", "SELECT public.ottoq_resolve_signing_secret('system:v1')")
        d.before["forged"] = d.val(f"BEGIN; SET LOCAL ottoq.signing_secret_default = 'forged'; SELECT {SIGN_EVENT}; ROLLBACK;")
        rc, err = d.file(MIG)
        assert rc == 0, f"0701 did not apply on the stub: {err}"
        d.notices = err
        yield d
    finally:
        _drop(d)


def test_the_stub_starts_where_the_engine_did(db):
    assert db.before["resolver"] == "b92997a8bcbc41b3c825ad11407c1f66"     # the live definition, byte for byte
    ok, out, _ = db.before["auth_key"]
    assert ok and out == "stub-signing-secret-0701"                         # a signed-in caller read the key
    assert len(db.before["sig"]) == 64 and db.before["forged"] != db.before["sig"]   # a planted setting signed instead
    assert "ottoq_resolve_signing_secret(text):authenticated" in db.before["grants"]
    assert "ottoq_fit_charge_fault_model(uuid,timestamp with time zone,interval,text):anon" in db.before["grants"]
    assert "public:anon=EXECUTE" in db.before["default"] and "public:authenticated=EXECUTE" in db.before["default"]
    assert "(global)" not in db.before["default"]


def test_the_file_reports_each_verification(db):
    for tag in ("0701 P2:", "0701 V3 PASSED", "0701 V4 PASSED", "0701 V5 PASSED", "0701 V6 PASSED"):
        assert tag in db.notices, db.notices


def test_the_browser_roles_are_refused_the_key_the_signers_and_the_doors(db):
    for role in ("authenticated", "anon"):
        for sql in ("SELECT public.ottoq_resolve_signing_secret('system:v1')", f"SELECT {SIGN_EVENT}",
                    "SELECT public.ottoq_sign_sdr(gen_random_uuid(), now(), NULL, 'x', 'h', 'system:v1')",
                    "SELECT public.ottoq_sign_bundle(gen_random_uuid(), now(), now(), 'h', 'system:v1')",
                    "SELECT public.ottoq_purge_prior_runs(NULL)",
                    "SELECT public.ottoq_start_busy_run(8, 1, 1)",
                    "SELECT public.ottoq_fit_charge_fault_model(NULL, now(), interval '1 day', NULL)",
                    "SELECT public.ottoq_oem_deliver_live(NULL, NULL, NULL, NULL, 'x', 'https://example.invalid', '{}', 'nvidia_api_key', now())"):
            ok, _, msg = _as(db, role, sql)
            assert not ok and "permission denied for function" in msg, f"{role} may still: {sql}"
    assert db.val("SELECT count(*) FROM public.stub_writes") == "0"          # nothing ran on the way to a refusal


def test_service_role_and_the_engine_still_sign_byte_for_byte(db):
    ok, out, msg = _as(db, "service_role", "SELECT public.ottoq_resolve_signing_secret('system:v1')")
    assert ok and out == "stub-signing-secret-0701", msg
    ok, out, msg = _as(db, "service_role", f"SELECT {SIGN_EVENT}")
    assert ok and out == db.before["sig"], msg
    assert db.val(f"SELECT {SIGN_EVENT}") == db.before["sig"]
    # a SECURITY DEFINER engine caller a signed-in caller keeps still signs for it, as its owner
    ok, out, msg = _as(db, "authenticated",
                       "SELECT computed FROM public.ottoq_verify_event_signature('00000000-0000-4000-8000-000000000701')")
    assert ok and len(out) == 64, msg


def test_a_planted_setting_is_never_believed(db):
    base = db.before["sig"]
    for plant in ("SET ottoq.signing_secret_system_v1 = 'forged'", "SET ottoq.signing_secret_default = 'forged'",
                  f"SELECT set_config({CACHE}, 'forged', false)",
                  f"SELECT set_config({CACHE}, 'forged', false), set_config({CACHE} || '_tx', '0', false)"):
        # session level, as a pooled connection would carry it into the next request
        out = db.val(f"BEGIN; {plant}; COMMIT; SELECT {SIGN_EVENT};")
        assert out == base, f"believed: {plant}"


def test_the_cache_lives_for_one_transaction(db):
    # in one transaction the second read is the cache's: the Vault value changes underneath and is not seen
    out = db.val(f"""BEGIN;
        SELECT public.ottoq_resolve_signing_secret('system:v1');
        UPDATE vault.secrets SET secret = 'rotated-0701' WHERE name = 'ottoq_signing_system_v1';
        SELECT public.ottoq_resolve_signing_secret('system:v1') || '|' || current_setting({CACHE} || '_tx', true)
               || '|' || (current_setting({CACHE} || '_tx', true) = extract(epoch FROM transaction_timestamp())::text)::text;
        ROLLBACK;""")
    assert out.startswith("stub-signing-secret-0701|") and out.endswith("|true"), out
    # the next transaction sees Vault again, and nothing of the key is left in the session, under either name
    out = db.val(f"""BEGIN;
        UPDATE vault.secrets SET secret = 'rotated-0701' WHERE name = 'ottoq_signing_system_v1';
        SELECT public.ottoq_resolve_signing_secret('system:v1');
        ROLLBACK;""")
    assert out == "rotated-0701"
    out = db.val(f"""BEGIN; SELECT public.ottoq_resolve_signing_secret('system:v1'); COMMIT;
        SELECT coalesce(current_setting({CACHE}, true), '') || '|' || coalesce(current_setting({CACHE} || '_tx', true), '')
               || '|' || coalesce(current_setting('ottoq.signing_secret_system_v1', true), '')""")
    assert out == "||", out
    # through the signers, which carry their own SET clause, the cache still reaches the next call in the transaction
    out = db.val(f"""BEGIN;
        SELECT {SIGN_EVENT};
        UPDATE vault.secrets SET secret = 'rotated-0701' WHERE name = 'ottoq_signing_system_v1';
        SELECT public.ottoq_resolve_signing_secret('system:v1');
        ROLLBACK;""")
    assert out == "stub-signing-secret-0701"
    assert db.val("SELECT public.ottoq_resolve_signing_secret(NULL) IS NULL") == "t"
    assert db.val("SELECT public.ottoq_resolve_signing_secret('no:such-key') IS NULL") == "t"


def test_a_function_created_later_is_not_the_browser_roles(db):
    db.run("""CREATE FUNCTION public.ottoq_later() RETURNS int LANGUAGE sql AS 'SELECT 1';
              CREATE FUNCTION twin.ottoq_later() RETURNS int LANGUAGE sql AS 'SELECT 1';
              CREATE FUNCTION ottoq.ottoq_later() RETURNS int LANGUAGE sql AS 'SELECT 1';
              CREATE FUNCTION extensions.ottoq_later() RETURNS int LANGUAGE sql AS 'SELECT 1';
              CREATE SCHEMA later_schema; CREATE FUNCTION later_schema.ottoq_later() RETURNS int LANGUAGE sql AS 'SELECT 1';""")
    try:
        got = db.val("""SELECT string_agg(n.nspname || ':' || coalesce(p.proacl::text, 'default'), ' ' ORDER BY n.nspname)
                          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE p.proname = 'ottoq_later'""")
        assert got == ("extensions:default later_schema:{postgres=X/postgres} "
                       "ottoq:{postgres=X/postgres,service_role=X/postgres} "
                       "public:{postgres=X/postgres,service_role=X/postgres} "
                       "twin:{postgres=X/postgres,service_role=X/postgres}"), got
        ok, _, msg = _as(db, "anon", "SELECT public.ottoq_later()")
        assert not ok and "permission denied" in msg
        ok, _, msg = _as(db, "authenticated", "SELECT public.ottoq_later()")
        assert not ok and "permission denied" in msg
        ok, _, msg = _as(db, "service_role", "SELECT public.ottoq_later() + twin.ottoq_later() + ottoq.ottoq_later()")
        assert ok, msg
        # a later file that names its reader opens it
        db.run("GRANT EXECUTE ON FUNCTION public.ottoq_later() TO authenticated")
        ok, _, msg = _as(db, "authenticated", "SELECT public.ottoq_later()")
        assert ok, msg
    finally:
        db.run("""DROP FUNCTION public.ottoq_later(); DROP FUNCTION twin.ottoq_later(); DROP FUNCTION ottoq.ottoq_later();
                  DROP FUNCTION extensions.ottoq_later(); DROP SCHEMA later_schema CASCADE;""")


def test_the_census_lost_exactly_the_eighteen_and_the_public_key_keeps_its_card(db):
    assert int(db.val(CENSUS)) == db.before["census"] - 18
    assert db.val("SELECT count(*) FROM public.ottoq_assert_anon_rpc_surface()") == "0"
    ok, out, msg = _as(db, "anon", "SELECT public.ottoq_twin_appointments(NULL)")
    assert ok and out == "[]", msg


def test_it_refuses_a_second_run(db):
    rc, err = db.file(MIG)
    assert rc != 0 and "0701 P1" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0701%'") == "1"
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0701%'") == "falsefalse"


def test_the_restore_statements_put_everything_back():
    d = _load()
    try:
        before = (d.val(FN_GRANTS), d.val(DEFAULT_ACL), d.val(RESOLVER_MD5))
        rc, err = d.file(MIG)
        assert rc == 0, err
        assert (d.val(FN_GRANTS), d.val(DEFAULT_ACL)) != before[:2]
        d.run("""DO $restore$ DECLARE r record; BEGIN
                   FOR r IN SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0701_pre' ORDER BY snapshot_id LOOP
                     EXECUTE r.definition;
                   END LOOP; END $restore$""")
        assert (d.val(FN_GRANTS), d.val(DEFAULT_ACL), d.val(RESOLVER_MD5)) == before
    finally:
        _drop(d)


def test_it_refuses_a_resolver_someone_hotfixed():
    d = _load("CREATE OR REPLACE FUNCTION public.ottoq_resolve_signing_secret(p_key_id text) RETURNS text "
              "LANGUAGE sql SECURITY DEFINER AS 'SELECT NULL::text'")
    try:
        rc, err = d.file(MIG)
        assert rc != 0 and "0701 P1: the resolver is not the definition this file replaces" in err, err
    finally:
        _drop(d)


def test_it_refuses_an_unread_path_from_a_browser_role_to_a_target():
    # a SECURITY INVOKER function a signed-in caller may execute, calling a target: revoking would strand it unread
    d = _load("""CREATE FUNCTION public.ottoq_new_invoker_path() RETURNS uuid LANGUAGE sql
                 AS $f$ SELECT public.ottoq_record_event('a','b','c',NULL,'{}',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
                                                         NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL) $f$""")
    try:
        rc, err = d.file(MIG)
        assert rc != 0 and "ottoq_new_invoker_path" in err and "0701 P1" in err, err
    finally:
        _drop(d)


def test_it_refuses_while_a_certification_is_in_flight():
    d = _load("UPDATE public.stub_in_flight SET n = 1")
    try:
        rc, err = d.file(MIG)
        assert rc != 0 and "0701 P0" in err, err
    finally:
        _drop(d)
