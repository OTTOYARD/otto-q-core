"""db/migrations/0658, the public key's default deny, EXECUTED on a stub of the grants it was written against.

WHY THIS EXISTS. G394: the public key (anon) could read 383 of 432 public tables and write some of them, and every new
table handed it SELECT. 0658 takes every grant postgres made it in public and twin, gives back SELECT on the fifteen
relations the cockpits read, and stops new tables and sequences from granting it. A grant change cannot be proved by
reading it, so this suite runs the file and then asks the database, as the public key, what it can do:

  * the fifteen answer a read and nothing else postgres owns does, including what 0429 named (events, bookings, visit
    needs, staff);
  * nothing is writable and no sequence is usable;
  * a table created after the file is closed to the public key, and one a later file opens is open;
  * a SECURITY DEFINER cockpit RPC still answers over a table the public key lost, and the one that runs as its caller
    still answers;
  * PostGIS's three, granted by supabase_admin, are reported and left alone, because postgres cannot revoke another
    grantor's grant;
  * the file refuses a second run, and its restore statements put every grant and default privilege back exactly.

Loads tests/fixtures/public_key_stub.sql. SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
from test_v2_door_sql import _drop, _new_db, _server_up  # noqa: E402

STUB = os.path.join(ROOT, "tests", "fixtures", "public_key_stub.sql")
MIG = os.path.join(ROOT, "db", "migrations", "0658_the_public_key_reads_only_what_a_cockpit_shows.sql")

ALLOW = sorted(["ottoq_arbiter_assessments", "ottoq_calibration_datasets", "ottoq_calibration_distributions",
                "ottoq_charge_clock_fits", "ottoq_comms_messages", "ottoq_decisions", "ottoq_depot_tariffs",
                "ottoq_determinism_canon", "ottoq_external_proposals", "ottoq_feed_plans", "ottoq_intelligence_ledger",
                "ottoq_proposal_disposition_ledger", "ottoq_rules", "ottoq_variability_catalog", "ottoq_vehicle_classes"])
POSTGIS = ["geography_columns", "geometry_columns", "spatial_ref_sys"]

#: every anon grant on a relation in public or twin, as "schema.rel:PRIV,PRIV"; the before/after of the rollback
ANON_GRANTS = """
SELECT coalesce(string_agg(n.nspname || '.' || c.relname || ':' || p.privs, ' ' ORDER BY n.nspname, c.relname), '')
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN LATERAL (SELECT string_agg(a.privilege_type || '/' || pg_get_userbyid(a.grantor), ',' ORDER BY a.privilege_type) AS privs
                        FROM aclexplode(c.relacl) a WHERE a.grantee = 'anon'::regrole) p
 WHERE n.nspname IN ('public', 'twin') AND p.privs IS NOT NULL
"""
DEFAULT_ACL = """
SELECT coalesce(string_agg(d.defaclobjtype::text || ':' || a.privilege_type, ',' ORDER BY d.defaclobjtype, a.privilege_type), '')
  FROM pg_default_acl d, aclexplode(d.defaclacl) a
 WHERE d.defaclrole = 'postgres'::regrole AND d.defaclnamespace = 'public'::regnamespace AND a.grantee = 'anon'::regrole
"""

pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _as_anon(db, sql):
    """Run one statement as the public key; (ok, message)."""
    rc, out, err = db.run(f"BEGIN; SET LOCAL ROLE anon; {sql}; ROLLBACK;", check=False)
    return rc == 0, (err or out)


@pytest.fixture(scope="module")
def db():
    d = _new_db()
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        d.before_grants = d.val(ANON_GRANTS)
        d.before_default = d.val(DEFAULT_ACL)
        rc, err = d.file(MIG)
        assert rc == 0, f"0658 did not apply on the stub: {err}"
        yield d
    finally:
        _drop(d)


def test_the_stub_starts_where_the_engine_did(db):
    # the public key held grants on far more than the fifteen, and new tables granted it SELECT
    assert db.before_grants.count(":") > len(ALLOW)
    assert "ottoq_events:" in db.before_grants and "INSERT/postgres" in db.before_grants
    assert "r:SELECT" in db.before_default and "S:USAGE" in db.before_default


def test_the_public_key_reads_the_fifteen_and_nothing_else_postgres_owns(db):
    readable = db.val("""
        SELECT string_agg(c.relname, ',' ORDER BY c.relname) FROM pg_class c
         WHERE c.relnamespace IN ('public'::regnamespace, 'twin'::regnamespace) AND c.relkind IN ('r','p','v','m','f')
           AND has_table_privilege('anon', c.oid, 'SELECT')""").split(",")
    assert sorted(set(readable) - set(POSTGIS)) == ALLOW
    for rel in ALLOW:
        ok, msg = _as_anon(db, f"SELECT count(*) FROM public.{rel}")
        assert ok, f"{rel}: {msg}"
    for rel in ("ottoq_events", "ottoq_stall_bookings", "ottoq_visit_needs", "ottoq_sim_runs", "staff_users", "stalls",
                "depots", "ottoq_model_call_ledger", "ottoq_open_stalls", "ottoq_schema_snapshots"):
        ok, msg = _as_anon(db, f"SELECT count(*) FROM public.{rel}")
        assert not ok and "permission denied" in msg, f"{rel} still answers the public key"


def test_the_public_key_writes_nothing_and_uses_no_sequence(db):
    for sql in ("INSERT INTO public.ottoq_events (event_type) VALUES ('x')", "DELETE FROM public.stalls",
                "UPDATE public.ottoq_rules SET rule_code = rule_code", "INSERT INTO public.ottoq_open_stalls (id) VALUES (gen_random_uuid())",
                "SELECT nextval('public.ottoq_events_event_id_seq')"):
        ok, msg = _as_anon(db, sql)
        assert not ok and "permission denied" in msg, f"the public key may still: {sql}"
    grants = db.val(ANON_GRANTS).split()
    postgres_granted = [g for g in grants if "/postgres" in g]
    assert all(g.split(":")[1] == "SELECT/postgres" for g in postgres_granted), postgres_granted
    assert sorted(g.split(":")[0].split(".")[1] for g in postgres_granted) == ALLOW


def test_a_new_table_is_closed_until_a_migration_opens_it(db):
    assert db.val(DEFAULT_ACL) == ""
    db.run("CREATE TABLE public.ottoq_new_feature (id bigserial PRIMARY KEY)")
    ok, msg = _as_anon(db, "SELECT count(*) FROM public.ottoq_new_feature")
    assert not ok and "permission denied" in msg
    # service_role and authenticated keep their defaults
    assert db.val("SELECT has_table_privilege('service_role', 'public.ottoq_new_feature', 'INSERT')") == "t"
    assert db.val("SELECT has_table_privilege('authenticated', 'public.ottoq_new_feature', 'SELECT')") == "t"
    db.run("GRANT SELECT ON public.ottoq_new_feature TO anon")
    ok, msg = _as_anon(db, "SELECT count(*) FROM public.ottoq_new_feature")
    assert ok, msg
    db.run("DROP TABLE public.ottoq_new_feature")


def test_the_cockpit_rpcs_still_answer_the_public_key(db):
    ok, msg = _as_anon(db, "SELECT public.ottoq_depot_cards(NULL, NULL)")
    assert ok, msg                    # SECURITY DEFINER, over ottoq_events, which the public key lost
    ok, msg = _as_anon(db, "SELECT count(*) FROM public.ottoq_shield_probe_posture()")
    assert ok, msg                    # runs as its caller; reads only the catalog


def test_postgis_keeps_what_supabase_admin_granted(db):
    grants = db.val(ANON_GRANTS)
    for rel in POSTGIS:
        assert f"public.{rel}:" in grants and "/supabase_admin" in grants


def test_it_refuses_a_second_run(db):
    rc, err = db.file(MIG)
    assert rc != 0 and "0658 P1" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0658%'") == "1"


def test_the_restore_statements_put_every_grant_back(db):
    # one GRANT per relation postgres had granted the public key, and one default privilege per object type
    relations = sum(1 for g in db.before_grants.split() if "/postgres" in g)
    assert int(db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0658_pre'")) == relations + 2
    db.run("""DO $restore$ DECLARE r record; BEGIN
                FOR r IN SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0658_pre' ORDER BY snapshot_id LOOP
                  EXECUTE r.definition;
                END LOOP; END $restore$""")
    assert db.val(ANON_GRANTS) == db.before_grants
    assert db.val(DEFAULT_ACL) == db.before_default
