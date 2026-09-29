"""db/migrations/0564, EXECUTED against a stub engine: a manual start from the depot simulation always interrupts a
running check.

WHY THIS EXISTS. On 2026-09-28 every cockpit Start (8 of 8) failed after ~8.2 s: a recertification pair held the twin
depot's world rows in one transaction, the start needed the same rows, and the API role's 8 s lock_timeout cancelled
it. The fix cancels the check, and its claims are about CONCURRENT sessions -- which backend gets cancelled, which is
left alone, and that no check can start in the gap -- so they are tested with real concurrent sessions, not by reading
source. tests/fixtures/operator_start_stub_engine.sql reproduces the conflict: its pair writes the world row and sleeps,
its start writes the same row.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_agent_gateway_sql.py. It uses
$PGHOST/$PGPORT/$PGUSER/$PGPASSWORD when PGHOST is set, else the local cluster on /var/tmp:55432.
"""
import json
import os
import shutil
import subprocess
import time
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "operator_start_stub_engine.sql")
M0564 = os.path.join(ROOT, "db", "migrations", "0564_a_manual_start_interrupts_a_running_check.sql")

# The cockpit calls the door through PostgREST as service_role, under the authenticator's lock_timeout and
# service_role's statement_timeout (read live 2026-09-28: 8 s and 20 s).
API = "SET lock_timeout = '8s'; SET statement_timeout = '20s'; SET ROLE service_role;\n"
START = "SELECT ottoq_operator_start_run('busy_day')"


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

    def _cmd(self, sql):
        return ["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql]

    def run(self, sql, check=True):
        p = subprocess.run(self._cmd(sql), capture_output=True, text=True)
        out = [l for l in p.stdout.splitlines() if l.strip()]
        if check and p.returncode != 0:
            raise AssertionError(f"SQL failed ({p.returncode}): {p.stderr}\n--- sql ---\n{sql}")
        return p.returncode, (out[-1] if out else ""), p.stderr

    def val(self, sql):
        return self.run(sql)[1]

    def json(self, sql):
        return json.loads(self.val(sql))

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr

    def background(self, sql, appname="scratch"):
        """Start SQL in its own session and return the process; the caller waits for it to be running."""
        env = {**os.environ, "PGAPPNAME": appname}
        return subprocess.Popen(self._cmd(sql), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)

    def wait_active(self, marker, timeout=10.0):
        """Block until a backend is active on a query carrying `marker` (and past its first write)."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            n = self.val(f"SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND query LIKE '%{marker}%' "
                         f"AND pid <> pg_backend_pid() AND wait_event = 'PgSleep'")
            if n == "1":
                return
            time.sleep(0.1)
        raise AssertionError(f"the background session carrying {marker} never reached its sleep")


@pytest.fixture(scope="module")
def db():
    name = f"ottoq_ops_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub engine did not load: {err}"
        rc, err = d.file(M0564)
        assert rc == 0, f"0564 did not apply: {err}"
        yield d
    finally:
        subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _marker():
    return f"bg_{uuid.uuid4().hex[:10]}"


def test_a_second_apply_refuses(db):
    rc, err = db.file(M0564)
    assert rc != 0 and "0564 P2" in err, err


def test_only_service_role_can_call_it(db):
    fn = "'public.ottoq_operator_start_run(text,bigint,text,timestamptz)'"
    assert db.val(f"SELECT has_function_privilege('service_role', {fn}, 'EXECUTE')") == "t"
    assert db.val(f"SELECT has_function_privilege('anon', {fn}, 'EXECUTE')") == "f"
    assert db.val(f"SELECT has_function_privilege('authenticated', {fn}, 'EXECUTE')") == "f"


def test_the_lineage_row_forces_no_sweep(db):
    row = db.json("SELECT row_to_json(l) FROM ottoq_cert_lineage l "
                  "WHERE name = '0564_a_manual_start_interrupts_a_running_check'")
    assert row["forces_recert"] is False and row["forces_dial_restart"] is False


def test_with_nothing_running_it_just_starts(db):
    res = db.json(API + START)
    assert res["ok"] is True and res["sim_run_id"] and res["interrupted"] == []
    notes = db.val(f"SELECT notes FROM ottoq_sim_runs WHERE sim_run_id = '{res['sim_run_id']}'")
    assert "interrupted" not in notes


def test_it_interrupts_the_recertification_runner(db):
    m = _marker()
    runner = db.background(
        f"/* {m} */ DO $runner$ BEGIN\n"
        "  IF NOT pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint) THEN RETURN; END IF;\n"
        "  PERFORM public.ottoq_determinism_pair(p_seed => 171717, p_ticks => 48, p_scenario => 'busy_day',\n"
        "                                        p_arm_budget_s => 30);\n"
        "END $runner$;", appname="pg_cron")
    db.wait_active(m)
    t0 = time.time()
    res = db.json(API + START)
    took = time.time() - t0
    _, err = runner.communicate(timeout=30)

    assert res["ok"] is True and res["sim_run_id"]
    assert took < 5, f"the start took {took:.1f} s: it waited for the pair instead of interrupting it"
    assert len(res["interrupted"]) == 1, res
    hit = res["interrupted"][0]
    assert hit["kind"] == "recertification pair" and hit["cancelled"] is True and hit["application"] == "pg_cron", hit
    assert runner.returncode != 0 and "canceling statement due to user request" in err, err
    notes = db.val(f"SELECT notes FROM ottoq_sim_runs WHERE sim_run_id = '{res['sim_run_id']}'")
    assert "operator start interrupted recertification pair" in notes and "re-runs after this run ends" in notes


def test_it_interrupts_a_pair_run_by_hand(db):
    m = _marker()
    pair = db.background(f"/* {m} */ SELECT public.ottoq_determinism_pair(424242, 24, 'busy_day', NULL, NULL, 30)")
    db.wait_active(m)
    res = db.json(API + START)
    _, err = pair.communicate(timeout=30)
    assert [(h["kind"], h["cancelled"]) for h in res["interrupted"]] == [("determinism pair", True)], res
    assert pair.returncode != 0 and "canceling statement due to user request" in err, err


def test_it_interrupts_a_dial_experiment(db):
    # The dial runner yields to a live run, and the tests above leave theirs running: end them, as a real world
    # would be before a dial pair could start.
    db.run("UPDATE ottoq_sim_runs SET status = 'completed' WHERE status IN ('running','paused')")
    m = _marker()
    dial = db.background(f"/* {m} */ SELECT public.ottoq_dial_experiment_runner()")
    db.wait_active(m)
    res = db.json(API + START)
    _, err = dial.communicate(timeout=30)
    assert [(h["kind"], h["cancelled"]) for h in res["interrupted"]] == [("dial experiment pair", True)], res
    assert dial.returncode != 0, err


def test_it_leaves_a_migration_and_a_monitor_alone(db):
    # A migration names the pairs in its P0 and may even call one in a rolled-back V-block; a monitor names them in an
    # ILIKE. Neither is a check, and neither may be cancelled by a cockpit button.
    m1, m2 = _marker(), _marker()
    migration = db.background(f"-- migration-version: PENDING\n/* {m1} ottoq_determinism_pair( */ SELECT pg_sleep(3)")
    monitor = db.background(f"/* {m2} */ SELECT pg_sleep(3) "
                            "WHERE 'x' NOT ILIKE '%ottoq_determinism_pair%' AND 'y' NOT ILIKE '%ottoq_recert_runner%'")
    db.wait_active(m1)
    db.wait_active(m2)
    res = db.json(API + START)
    migration.communicate(timeout=30)
    monitor.communicate(timeout=30)
    assert res["interrupted"] == [], res
    assert migration.returncode == 0 and monitor.returncode == 0


def test_no_check_can_start_before_the_run_is_live(db):
    # The runner fires every minute; between the cancel and this run's commit it must find the world held.
    m = _marker()
    start = db.background(f"/* {m} */ BEGIN; SET ROLE service_role; {START}; SELECT pg_sleep(3); COMMIT;")
    db.wait_active(m)
    assert db.val("SELECT pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint)") == "f"
    start.communicate(timeout=30)
    assert start.returncode == 0
    assert db.val("SELECT pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint)") == "t"
