"""db/migrations/0567, EXECUTED against a stub engine: a charger build-out lives only inside the test day that uses it.

WHY THIS EXISTS. 0567 lets a test day run on 15 or 20 robotic fast chargers by converting L2 spaces inside the day's own
transaction, and taking them back out before it ends. Three things must hold for that to be safe on the one depot every
demo and every canon uses: the conversion changes exactly what it says, the restore puts back exactly what it found, and
a transaction that forgets to restore cannot commit. And a day that ran on a build-out must still score correctly after
the restore has turned its converted spaces back into L2. tests/fixtures/site_buildout_stub.sql grows the throughput stub
to the depot 0567's P1 reads; each test below pins one of those claims.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_throughput_scorecard_sql.py.
"""
import json
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "throughput_stub_engine.sql")
STUB_BO = os.path.join(ROOT, "tests", "fixtures", "site_buildout_stub.sql")
M0565 = os.path.join(ROOT, "db", "migrations", "0565_a_scorecard_that_counts_cars_served.sql")
M0566 = os.path.join(ROOT, "db", "migrations", "0566_the_scorecard_reads_the_step_a_run_actually_took.sql")
M0567 = os.path.join(ROOT, "db", "migrations", "0567_a_charger_build_out_lives_only_inside_a_test_day.sql")

TWIN = "11111111-1111-1111-1111-111111111111"
BENCH = "22222222-2222-2222-2222-222222222222"
RUN = "a0000000-0000-0000-0000-000000000001"
LIVE_RUN = "a0000000-0000-0000-0000-000000000002"
BUILDOUT_RUN = "a0000000-0000-0000-0000-00000000000b"
L2_01 = "d0000000-0000-0000-0000-000000000201"
L2_30 = "d0000000-0000-0000-0000-00000000c0c2"

# The stub keeps one run live (the throughput backfill must skip it), and apply refuses under a live run by design.
# A test that applies parks it for the length of its own transaction and puts it back before COMMIT.
PARK = f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{LIVE_RUN}';"
UNPARK = f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{LIVE_RUN}';"

SNAPSHOT = f"""
SELECT md5(string_agg(t, E'\\n' ORDER BY t)) FROM (
  SELECT to_jsonb(s)::text AS t FROM public.stalls s WHERE s.depot_id = '{TWIN}'
  UNION ALL SELECT to_jsonb(c)::text FROM public.ottoq_ocpp_chargers c WHERE c.depot_id = '{TWIN}'
  UNION ALL SELECT to_jsonb(k)::text FROM public.ottoq_service_point_capabilities k
  UNION ALL SELECT to_jsonb(d)::text FROM public.depots d) z
"""


def _conn_args():
    if os.environ.get("PGHOST"):
        return ["-h", os.environ["PGHOST"], "-p", os.environ.get("PGPORT", "5432"),
                "-U", os.environ.get("PGUSER", "postgres")]
    return ["-h", "/var/tmp", "-p", "55432", "-U", "postgres"]


def _server_up():
    if not shutil.which("psql"):
        return False
    p = subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-Atc", "select 1"], capture_output=True, text=True)
    return p.returncode == 0


pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


class Db:
    def __init__(self, name):
        self.name = name

    def run(self, sql):
        """One psql session; returns (returncode, stdout lines, stderr)."""
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                           capture_output=True, text=True)
        return p.returncode, [l for l in p.stdout.splitlines() if l.strip()], p.stderr

    def val(self, sql):
        rc, out, err = self.run(sql)
        if rc != 0:
            raise AssertionError(f"SQL failed: {err}\n--- sql ---\n{sql}")
        return out[-1] if out else ""

    def json(self, sql):
        return json.loads(self.val(sql))

    def fails(self, sql):
        rc, _, err = self.run(sql)
        assert rc != 0, f"expected failure, but it succeeded:\n{sql}"
        return err

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr


@pytest.fixture(scope="module")
def db():
    name = f"ottoq_sbo_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        for path in (STUB, STUB_BO, M0565, M0566):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        d.stored_0566 = d.json(f"SELECT scorecard FROM public.ottoq_throughput_scores_latest WHERE sim_run_id = '{RUN}'")
        d.snapshot_before = d.val(SNAPSHOT)
        rc, err = d.file(M0567)
        assert rc == 0, f"0567 did not apply: {err}"
        d.apply_notices = err
        yield d
    finally:
        subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def test_applying_changes_nothing_on_the_depot_and_a_second_apply_is_refused(db):
    assert db.val(SNAPSHOT) == db.snapshot_before
    rc, err = db.file(M0567)
    # P1 refuses first (the scorecard is no longer 0566's body); P2 would refuse a half-applied state
    assert rc != 0 and ("0567 P1" in err or "0567 P2" in err)


def test_the_live_round_trip_waits_for_a_quiet_depot(db):
    # The stub keeps a run live, so V2 must say it skipped rather than convert under it.
    assert "0567 V2: a run is live at the twin depot" in db.apply_notices
    assert "0567 V3:" in db.apply_notices


def test_apply_converts_exactly_the_named_spaces(db):
    out = db.json(f"""
      BEGIN; {PARK}
      CREATE TEMP TABLE receipt ON COMMIT DROP AS SELECT public.ottoq_site_buildout_apply('{TWIN}', 'dcfc20') AS r;
      SELECT jsonb_build_object(
        'receipt', (SELECT r FROM receipt),
        'census',  public.ottoq_site_buildout_census('{TWIN}'),
        'l2_01',   (SELECT to_jsonb(s) FROM public.stalls s WHERE s.id = '{L2_01}'),
        'l2_30',   (SELECT to_jsonb(s) FROM public.stalls s WHERE s.id = '{L2_30}'),
        'charger', (SELECT to_jsonb(c) FROM public.ottoq_ocpp_chargers c JOIN public.stalls s ON s.ocpp_charger_id = c.charger_id
                     WHERE s.id = '{L2_01}'),
        'caps',    (SELECT jsonb_object_agg(operation_code, n) FROM (SELECT operation_code, count(*) n
                      FROM public.ottoq_service_point_capabilities GROUP BY 1) z));
      ROLLBACK;""")
    r, c = out["receipt"], out["census"]
    assert r["buildout_code"] == "dcfc20" and r["dcfc_posts"] == 20
    assert [x["stall_code"] for x in r["converted"]] == [f"NASH-L2-STALL-{i:02d}" for i in range(1, 11)]
    assert c == {"depot_id": TWIN, "dcfc": 20, "l2": 1, "dcfc_max_concurrent_kw": 3600, "service_max_kw": 4363,
                 "applied": "dcfc20"}
    s = out["l2_01"]
    assert s["stall_type"] == "dcfc" and float(s["connector_max_kw"]) == 350
    assert s["fiducial_marker_id"] == "FID-BO-L2-STALL-01-A" and s["uwb_beacon_id"] == "UWB-BO-L2-STALL-01"
    assert s["zone"] == "dcfc_zone"
    assert s["equipment_config"] == {"charger_kw": 350, "canopy_code": "CANOPY-02", "canopy_side": "W",
                                     "robotic_arm": True, "buildout": "dcfc20"}
    assert s["stall_code"] == "NASH-L2-STALL-01"          # the space keeps its name and place
    assert out["l2_30"]["stall_type"] == "l2"              # a space the build-out does not name is untouched
    ch = out["charger"]
    assert float(ch["max_kw"]) == 350 and ch["vendor"] == "ABB" and ch["model"] == "Terra HP 350"
    # 20 charge_l2 capability rows became charge_dcfc; interior_tidy is not a charge and stays
    assert out["caps"] == {"charge_dcfc": 20, "interior_tidy": 10}
    # rolled back: the depot is as built
    assert db.val(SNAPSHOT) == db.snapshot_before


def test_restore_puts_back_exactly_what_it_found_and_the_transaction_commits(db):
    out = db.json(f"""
      BEGIN; {PARK}
      SELECT public.ottoq_site_buildout_apply('{TWIN}', 'dcfc15');
      CREATE TEMP TABLE receipt ON COMMIT DROP AS SELECT public.ottoq_site_buildout_restore('{TWIN}') AS r;
      SELECT jsonb_build_object('restore', (SELECT r FROM receipt),
                                'census', public.ottoq_site_buildout_census('{TWIN}'));
      {UNPARK}
      COMMIT;""")
    assert out["restore"] == {"restored": True, "buildout_code": "dcfc15", "depot_id": TWIN,
                              "spaces": 5, "chargers": 5, "capabilities": 10}
    assert out["census"]["applied"] is None and out["census"]["dcfc"] == 10
    assert db.val(SNAPSHOT) == db.snapshot_before
    assert db.val("SELECT count(*) FROM public.ottoq_site_buildout_active") == "0"


def test_a_build_out_left_applied_cannot_commit(db):
    err = db.fails(f"""
      BEGIN; {PARK}
      SELECT public.ottoq_site_buildout_apply('{TWIN}', 'dcfc20');
      {UNPARK}
      COMMIT;""")
    assert "is still applied to depot" in err
    # the whole transaction rolled back: the depot is as built, and the live run is still live
    assert db.val(SNAPSHOT) == db.snapshot_before
    assert db.val(f"SELECT status FROM public.ottoq_sim_runs WHERE sim_run_id = '{LIVE_RUN}'") == "running"
    assert db.val(f"SELECT stall_type FROM public.stalls WHERE id = '{L2_01}'") == "l2"


def test_apply_refuses_under_a_live_run(db):
    assert "a run is live at depot" in db.fails(f"SELECT public.ottoq_site_buildout_apply('{TWIN}', 'dcfc20')")


def test_apply_refuses_what_it_cannot_do_exactly(db):
    assert "no build-out nope" in db.fails(f"BEGIN; {PARK} SELECT public.ottoq_site_buildout_apply('{TWIN}', 'nope'); ROLLBACK;")
    assert "belongs to depot" in db.fails(
        f"BEGIN; {PARK} SELECT public.ottoq_site_buildout_apply('{BENCH}', 'dcfc20'); ROLLBACK;")
    assert "already applied to depot" in db.fails(f"""
      BEGIN; {PARK}
      SELECT public.ottoq_site_buildout_apply('{TWIN}', 'dcfc15');
      SELECT public.ottoq_site_buildout_apply('{TWIN}', 'dcfc20');
      ROLLBACK;""")
    # a build-out naming a space that is not an L2 charger
    assert "names spaces that are not L2 chargers" in db.fails(f"""
      BEGIN; {PARK}
      INSERT INTO public.ottoq_site_buildouts (buildout_code, depot_id, title, dcfc_posts, convert_l2,
                                               dcfc_max_concurrent_kw, service_max_kw, basis)
      VALUES ('bad_space', '{TWIN}', 'x', 11, ARRAY['NASH-DCFC-STALL-01'], 1, 1, '{{}}');
      SELECT public.ottoq_site_buildout_apply('{TWIN}', 'bad_space');
      ROLLBACK;""")
    # a build-out whose count does not add up
    assert "declares 12 fast chargers" in db.fails(f"""
      BEGIN; {PARK}
      INSERT INTO public.ottoq_site_buildouts (buildout_code, depot_id, title, dcfc_posts, convert_l2,
                                               dcfc_max_concurrent_kw, service_max_kw, basis)
      VALUES ('bad_count', '{TWIN}', 'x', 12, ARRAY['NASH-L2-STALL-01'], 1, 1, '{{}}');
      SELECT public.ottoq_site_buildout_apply('{TWIN}', 'bad_count');
      ROLLBACK;""")
    assert db.val(SNAPSHOT) == db.snapshot_before


def test_restore_with_nothing_applied_is_a_receipt_not_an_error(db):
    out = db.json(f"SELECT public.ottoq_site_buildout_restore('{TWIN}')")
    assert out["restored"] is False and out["why"] == "no build-out is applied"


def test_apply_and_restore_leave_the_callers_actor_as_they_found_it(db):
    out = db.json(f"""
      BEGIN; {PARK}
      SELECT set_config('ottoq.actor_type', 'depot_supervisor', true), set_config('ottoq.actor_id', 'caller', true);
      SELECT public.ottoq_site_buildout_apply('{TWIN}', 'dcfc10');
      SELECT jsonb_build_object('after_apply', current_setting('ottoq.actor_type') || '/' || current_setting('ottoq.actor_id'));
      ROLLBACK;""")
    assert out["after_apply"] == "depot_supervisor/caller"


def test_dcfc10_is_a_receipt_that_changes_nothing(db):
    out = db.json(f"""
      BEGIN; {PARK}
      CREATE TEMP TABLE receipt ON COMMIT DROP AS SELECT public.ottoq_site_buildout_apply('{TWIN}', 'dcfc10') AS r;
      SELECT jsonb_build_object('r', (SELECT r FROM receipt), 'c', public.ottoq_site_buildout_census('{TWIN}'));
      ROLLBACK;""")
    assert out["r"]["converted"] == [] and out["r"]["dcfc_posts"] == 10
    assert out["c"]["dcfc"] == 10 and out["c"]["applied"] == "dcfc10"


def test_a_build_out_day_scores_from_its_own_record_after_the_restore(db):
    sc = db.json(f"SELECT public.ottoq_throughput_scorecard('{BUILDOUT_RUN}')")
    assert sc["scorecard_version"] == "0567"
    assert sc["run"]["site_buildout"] == "dcfc20"
    fc = sc["fast_chargers"]
    assert fc["at_depot"] == 20                     # the day's census, not today's 10
    assert fc["sessions"] == 2                      # the built charger and converted L2-STALL-01
    assert float(fc["turns_per_charger_per_day"]) == 0.1
    assert sc["l2_sessions"] == 1                   # only L2-STALL-30, which was L2 that day too
    assert any("build-out dcfc20" in c for c in sc["caveats"])
    # 0566 read today's stall table and got it wrong, which is why the day carries its own record
    old = db.json(f"SELECT scorecard FROM public.ottoq_throughput_scores_latest WHERE sim_run_id = '{BUILDOUT_RUN}'")
    assert old["fast_chargers"]["at_depot"] == 10 and old["fast_chargers"]["sessions"] == 1 and old["l2_sessions"] == 2


def test_a_day_without_a_build_out_scores_as_0566_did(db):
    sc = db.json(f"SELECT public.ottoq_throughput_scorecard('{RUN}')")
    assert sc["run"]["site_buildout"] is None
    assert sc["fast_chargers"]["at_depot"] == 10
    new = {k: v for k, v in sc.items() if k != "scorecard_version"}
    new["run"] = {k: v for k, v in new["run"].items() if k != "site_buildout"}
    old = {k: v for k, v in db.stored_0566.items() if k != "scorecard_version"}
    assert new == old
    assert not any("build-out" in c for c in sc["caveats"])


def test_grants(db):
    def can(role, fn):
        return db.val(f"SELECT has_function_privilege('{role}', '{fn}', 'EXECUTE')") == "t"
    apply_fn, restore_fn, census_fn = ("public.ottoq_site_buildout_apply(uuid,text)",
                                       "public.ottoq_site_buildout_restore(uuid)", "public.ottoq_site_buildout_census(uuid)")
    assert not can("anon", apply_fn) and not can("authenticated", apply_fn) and can("service_role", apply_fn)
    assert not can("anon", restore_fn) and not can("authenticated", restore_fn) and can("service_role", restore_fn)
    assert not can("anon", census_fn) and can("authenticated", census_fn)
    assert db.val("SELECT has_table_privilege('authenticated', 'public.ottoq_site_buildouts', 'SELECT')") == "t"
    assert db.val("SELECT has_table_privilege('authenticated', 'public.ottoq_site_buildout_active', 'SELECT')") == "f"


def test_the_numbers_carry_their_source_and_the_lineage_forces_nothing(db):
    rows = db.json("""SELECT jsonb_object_agg(buildout_code, jsonb_build_array(dcfc_posts, dcfc_max_concurrent_kw,
                             service_max_kw, basis->'source'->>'url')) FROM public.ottoq_site_buildouts""")
    url = "https://inchargeus.com/wp-content/uploads/2025/02/InCharge_Specsheet_Terra-High-Power_v1.4.pdf"
    assert rows == {"dcfc10": [10, 1800, 2500, url], "dcfc15": [15, 2700, 3431.5, url],
                    "dcfc20": [20, 3600, 4363, url], "dcfc20_grid_today": [20, 1800, 2500, url]}
    assert db.val("""SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage
                     WHERE name = '0567_a_charger_build_out_lives_only_inside_a_test_day'""") == "false/false"


def test_on_a_quiet_depot_the_migration_itself_round_trips_dcfc20_and_leaves_nothing():
    # V2 runs its round trip only between runs. Here the stub's live run is finished before 0567 applies, so V2 must
    # convert, check and restore on the stub depot, then roll its own work back.
    name = f"ottoq_sbq_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        for path in (STUB, STUB_BO):
            rc, err = d.file(path)
            assert rc == 0, err
        d.val(PARK)
        for path in (M0565, M0566):
            rc, err = d.file(path)
            assert rc == 0, err
        before = d.val(SNAPSHOT)
        rc, err = d.file(M0567)
        assert rc == 0, err
        assert "0567 V2: dcfc20 applied and restored on the live twin depot" in err
        assert d.val(SNAPSHOT) == before
        assert d.val("SELECT count(*) FROM public.ottoq_site_buildout_active") == "0"
    finally:
        subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)
