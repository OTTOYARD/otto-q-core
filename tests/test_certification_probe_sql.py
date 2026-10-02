"""db/migrations/0579, EXECUTED with a second backend: the in-flight probe sees an overnight sweep arm.

WHY THIS EXISTS. Every migration's P0, the calibration write guard and the ingest refresh ask
`ottoq_certification_in_flight` whether a rig is running. On 2026-10-01 it read 0 while a sweep arm had held the world for
eighty minutes (G305, db/checks/0414 §5): 0513's patterns predate the sweep. A pattern test alone would not have caught
that, so these tests run the sweep's real cron command in a second backend and ask the probe from a first one:

  * before 0579, the probe does not see it (the defect, reproduced);
  * after 0579, it sees the runner's cron command and a hand-run arm, and only with p_with_dial true;
  * a read of the arms table, which names the sweep without running it, is not counted;
  * 0579 refuses while a rig is in flight, refuses a rig body it did not read, refuses a second time, and its rollback
    snapshot restores 0513's body byte for byte.

tests/fixtures/certification_probe_stub.sql carries 0513's two functions verbatim. It SKIPS where no scratch PostgreSQL
is reachable, like tests/test_throughput_sweep_sql.py.
"""
import os
import shutil
import subprocess
import time
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "certification_probe_stub.sql")
M0579 = os.path.join(ROOT, "db", "migrations", "0579_the_in_flight_probe_sees_an_overnight_sweep_arm.sql")
RIG_0513_MD5 = "f00f680acecfec2f092e470c465269b2"
CRON = "SET statement_timeout = 0; SELECT public.ottoq_throughput_sweep_runner();"


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

    def run(self, sql, env=None):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                           capture_output=True, text=True, env=env)
        return p.returncode, [l for l in p.stdout.splitlines() if l.strip()], p.stderr

    def val(self, sql):
        rc, out, err = self.run(sql)
        if rc != 0:
            raise AssertionError(f"SQL failed: {err}\n--- sql ---\n{sql}")
        return out[-1] if out else ""

    def file(self, path, env=None):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True, env=env)
        return p.returncode, p.stderr

    def in_flight_while(self, sql, with_dial=True):
        """Run `sql` in a second backend that sleeps inside it, and read the probe from this one while it runs."""
        app = "probe_" + uuid.uuid4().hex[:8]
        env = dict(os.environ, PGAPPNAME=app, PGOPTIONS="-c ottoq.stub_sleep_s=6")
        bg = subprocess.Popen(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-c", sql], env=env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.time() + 10
            while time.time() < deadline:
                if self.val(f"SELECT count(*) FROM pg_stat_activity WHERE application_name = '{app}' "
                            "AND state = 'active'") == "1":
                    break
                time.sleep(0.1)
            else:
                raise AssertionError("the second backend never became active")
            return int(self.val(f"SELECT public.ottoq_certification_in_flight({'true' if with_dial else 'false'})"))
        finally:
            bg.wait(timeout=30)


def _make_db(tag):
    name = f"ottoq_{tag}_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    rc, err = d.file(STUB)
    assert rc == 0, f"the stub did not load: {err}"
    return d


def _drop(d):
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q"]
    subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {d.name} WITH (FORCE)"], capture_output=True)


@pytest.fixture()
def fresh():
    d = _make_db("cpf")
    try:
        yield d
    finally:
        _drop(d)


@pytest.fixture(scope="module")
def applied():
    d = _make_db("cpa")
    try:
        rc, err = d.file(M0579)
        assert rc == 0, f"0579 did not apply: {err}"
        yield d
    finally:
        _drop(d)


def test_the_stub_carries_0513s_rig_byte_for_byte(fresh):
    assert fresh.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_certification_rig_matches'") == RIG_0513_MD5


def test_before_0579_the_probe_cannot_see_a_running_sweep_arm(fresh):
    # G305 reproduced: the runner's own cron command, running, and the probe reads nothing.
    assert fresh.in_flight_while(CRON) == 0


def test_after_0579_the_probe_sees_the_runners_cron_command(applied):
    assert applied.in_flight_while(CRON) == 1


def test_the_sweep_is_a_research_rig_not_a_certification(applied):
    assert applied.in_flight_while(CRON, with_dial=False) == 0


def test_after_0579_the_probe_sees_a_hand_run_arm(applied):
    arm = "SELECT public.ottoq_throughput_sweep_arm('8a1e12ae-b64b-4b6e-a82d-370f6f58315c'::uuid, 1, false)"
    assert applied.in_flight_while(arm) == 1


def test_a_read_of_the_arms_table_is_not_an_arm(applied):
    assert applied.in_flight_while("SELECT pg_sleep(4), count(*) FROM public.ottoq_throughput_sweep_arms") == 0


def test_the_window_cron_entries_and_the_rigs_0513_matched_are_unchanged(applied):
    for job in ("ottoq_sweep_window_open", "ottoq_sweep_window_close"):
        assert applied.val("SELECT public.ottoq_certification_rig_matches(command, true) FROM cron.job "
                           f"WHERE jobname = '{job}'") == "f"
    cases = [("SELECT public.ottoq_determinism_pair(p_seed => 1)", "false", "t"),
             ("SELECT public.ottoq_ab_pair(1)", "false", "t"),
             ("SET statement_timeout = 0; SELECT public.ottoq_dial_experiment_runner();", "true", "t"),
             ("SET statement_timeout = 0; SELECT public.ottoq_dial_experiment_runner();", "false", "f"),
             ("SELECT public.ottoq_cron_tick()", "true", "f")]
    for q, dial, want in cases:
        assert applied.val(f"SELECT public.ottoq_certification_rig_matches($q${q}$q$, {dial})") == want, q


def test_0579_is_recorded_once_as_harness_only(applied):
    assert applied.val("SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                       "WHERE name = '0579_the_in_flight_probe_sees_an_overnight_sweep_arm'") == "false/false"
    rc, err = applied.file(M0579)
    assert rc != 0 and "0579 P1: already applied" in err


def test_0579_refuses_while_a_rig_is_in_flight(fresh):
    env = dict(os.environ, PGOPTIONS="-c ottoq.simulate_certification_in_flight=on")
    rc, err = fresh.file(M0579, env=env)
    assert rc != 0 and "0579 P0" in err
    assert fresh.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_certification_rig_matches'") == RIG_0513_MD5


def test_0579_refuses_a_rig_body_it_did_not_read(fresh):
    fresh.val("CREATE OR REPLACE FUNCTION public.ottoq_certification_rig_matches(p_query text, p_with_dial boolean "
              "DEFAULT true) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT false $$")
    rc, err = fresh.file(M0579)
    assert rc != 0 and "0579 P1: ottoq_certification_rig_matches is not the body 0513 wrote" in err


def test_the_rollback_snapshot_restores_0513s_body(fresh):
    rc, err = fresh.file(M0579)
    assert rc == 0, err
    assert fresh.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_certification_rig_matches'") != RIG_0513_MD5
    fresh.val("DO $r$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0579_pre'); "
              "END $r$")
    assert fresh.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_certification_rig_matches'") == RIG_0513_MD5
    assert fresh.in_flight_while(CRON) == 0
