"""db/migrations/0793, EXECUTED: the research wing's findings, and the feed the twin's Research tab reads.

WHY THIS EXISTS. Chase, 2026-11-03, on the frontier plan's lab: "feed the results into a 'Research' tab in the twin",
then "Okay BEGIN". 0793 adds public.ottoq_research_findings and public.ottoq_research_feed(depot). Executed here on the
scratch PostgreSQL against a stub of the two things its guards read (ottoq_certification_in_flight, ottoq_cert_lineage):
  - the feed answers an empty list, then the depot's findings newest first within a phase, never a retracted one and
    never another depot's;
  - anon reaches the feed and not the table, for reading or writing;
  - a slug, phase, item, kind or status outside its pattern is refused;
  - a second apply stops at P1 and changes nothing.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
M0793 = os.path.join(ROOT, "db", "migrations",
                     "0793_the_research_wing_writes_its_findings_where_the_twin_can_read_them.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
OTHER = "22222222-2222-2222-2222-222222222222"

STUB = """
SET check_function_bodies = off;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql AS 'SELECT 0';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL,
  classified_at timestamptz NOT NULL, forces_dial_restart boolean);
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
-- Supabase's defaults: every new table and function in public is granted to the API roles, so 0793's REVOKEs are
-- what is tested, not an empty default.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;
"""

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture()
def db():
    name = f"ottoq_research_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, _, err = d.run(STUB)
        assert rc == 0, f"stub did not load: {err}"
        rc, err = d.file(M0793)
        assert rc == 0, f"0793 did not apply: {err}"
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _finding(d, slug, phase="P0", item="E2", status="measured", depot=DEPOT, updated="now()"):
    d.val(f"""INSERT INTO public.ottoq_research_findings
                (slug, depot_id, phase, item, kind, status, title, summary, metrics, evidence, run_ids, measured_at,
                 updated_at)
              VALUES ('{slug}', '{depot}', '{phase}', '{item}', 'measurement', '{status}', 'A title for {slug}',
                      'A plain summary for {slug}.', '{{"auc": 0.65}}', 'db/checks/0475', ARRAY['8c0b2e04'], now(),
                      {updated})""")


def _feed(d, depot=DEPOT):
    return d.json(f"SELECT public.ottoq_research_feed('{depot}')")


def test_the_feed_starts_empty_and_the_lineage_row_is_false_false(db):
    j = _feed(db)
    assert j["findings"] == []
    assert j["depot_id"] == DEPOT
    row = db.val("SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                 "WHERE name = '0793_the_research_wing_writes_its_findings_where_the_twin_can_read_them'")
    assert row == "false/false"


def test_the_feed_answers_this_depots_live_findings_newest_first_within_a_phase(db):
    _finding(db, "p0-older", updated="now() - interval '1 hour'")
    _finding(db, "p0-newer", updated="now()")
    _finding(db, "p1-first", phase="P1", item="E1")
    _finding(db, "p0-retracted", status="retracted")
    _finding(db, "p0-other-depot", depot=OTHER)
    slugs = [f["slug"] for f in _feed(db)["findings"]]
    assert slugs == ["p0-newer", "p0-older", "p1-first"]
    first = _feed(db)["findings"][0]
    assert first["metrics"] == {"auc": 0.65}
    assert first["run_ids"] == ["8c0b2e04"]
    assert first["evidence"] == "db/checks/0475"
    assert [f["slug"] for f in _feed(db, OTHER)["findings"]] == ["p0-other-depot"]


def test_anon_reaches_the_feed_and_not_the_table(db):
    _finding(db, "p0-visible")
    out = db.val("SET ROLE anon; SELECT jsonb_array_length(public.ottoq_research_feed()->'findings')")
    assert out.strip().splitlines()[-1] == "1"
    for sql in ("SET ROLE anon; SELECT count(*) FROM public.ottoq_research_findings",
                "SET ROLE authenticated; SELECT count(*) FROM public.ottoq_research_findings",
                "SET ROLE anon; INSERT INTO public.ottoq_research_findings (slug, phase, item, kind, status, title, "
                "summary) VALUES ('p0-sneak', 'P0', 'E1', 'lab', 'built', 'sneaked in here', 'sneaked in here')"):
        rc, _, err = db.run(sql)
        assert rc != 0 and "permission denied" in err, (sql, err)


@pytest.mark.parametrize("col,bad", [
    ("slug", "'Bad Slug'"), ("phase", "'Phase0'"), ("item", "'E'"), ("kind", "'guess'"), ("status", "'done'"),
])
def test_a_value_outside_its_pattern_is_refused(db, col, bad):
    vals = {"slug": "'p0-ok'", "phase": "'P0'", "item": "'E2'", "kind": "'measurement'", "status": "'measured'"}
    vals[col] = bad
    rc, _, err = db.run(
        "INSERT INTO public.ottoq_research_findings (slug, phase, item, kind, status, title, summary) VALUES ("
        + ", ".join(vals[k] for k in ("slug", "phase", "item", "kind", "status"))
        + ", 'a valid title', 'a valid summary')")
    assert rc != 0 and "violates check constraint" in err, err


def test_a_second_apply_stops_at_p1_and_changes_nothing(db):
    _finding(db, "p0-kept")
    rc, err = db.file(M0793)
    assert rc != 0 and "0793 P1: already applied" in err, err
    assert [f["slug"] for f in _feed(db)["findings"]] == ["p0-kept"]
