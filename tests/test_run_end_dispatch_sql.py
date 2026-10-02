"""db/migrations/0582, EXECUTED on the function as the catalog held it: a run that has ended dispatches no car.

WHY THIS EXISTS. On a test day's last tick the world step completes the run, the close-needs trigger supersedes every
open visit, and the decide that followed found no work open on any car, so the departure test let a car go with
services unfinished (G303, night 2's arm 25; CLAUDE.md rule 9). 0582 puts one guard at the top of
`ottoq_sim_decide_and_dispatch`. tests/fixtures/decide_and_dispatch_stub.sql holds that function byte for byte (source
md5 700e3e44...) with nothing behind it, so a run the guard lets through fails on the function's next statement and a run
it stops returns (0, 0):

  * before 0582, a completed run goes on into the decide path (the defect, reproduced);
  * after it, a completed, failed or aborted run returns (0, 0) and writes nothing;
  * an initializing, running or paused run still goes on into the decide path;
  * 0582 refuses while a rig is in flight, refuses a body it did not measure or a trigger that closes needs on other
    statuses, refuses a second time, and its rollback snapshot restores the measured body.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_throughput_sweep_sql.py.
"""
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "decide_and_dispatch_stub.sql")
M0582 = os.path.join(ROOT, "db", "migrations", "0582_a_run_that_has_ended_dispatches_no_car.sql")
MEASURED_MD5 = "700e3e44b85a853d7d551a45d0d2d52b"
DEPOT = "11111111-1111-1111-1111-111111111111"
NEXT_STATEMENT = 'relation "depots" does not exist'


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

    def run_with(self, status):
        rid = str(uuid.uuid4())
        self.val(f"INSERT INTO public.ottoq_sim_runs (sim_run_id, status, depot_id, sim_clock_current, run_by) "
                 f"VALUES ('{rid}', '{status}', '{DEPOT}', '2026-09-01 11:00+00', 'ab_harness')")
        return rid

    def decide(self, rid):
        """(rc, stdout, stderr) of one decide-and-dispatch call on the run."""
        return self.run(f"SELECT out_dispatched || '/' || out_charge_assigned "
                        f"FROM public.ottoq_sim_decide_and_dispatch('{rid}')")


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
    d = _make_db("rdf")
    try:
        yield d
    finally:
        _drop(d)


@pytest.fixture(scope="module")
def applied():
    d = _make_db("rda")
    try:
        # V2 decides the most recent run of each ended status there is; give it one of each
        ended = {s: d.run_with(s) for s in ("completed", "failed", "aborted")}
        rc, err = d.file(M0582)
        assert rc == 0, f"0582 did not apply: {err}"
        d.apply_notices = err
        d.ended = ended
        yield d
    finally:
        _drop(d)


def test_the_stub_carries_the_measured_function_byte_for_byte(fresh):
    assert fresh.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_sim_decide_and_dispatch'") == MEASURED_MD5


def test_before_0582_a_completed_run_is_still_decided(fresh):
    # G303 reproduced: the run's needs are closed, and the decide path runs anyway
    rc, _, err = fresh.decide(fresh.run_with("completed"))
    assert rc != 0 and NEXT_STATEMENT in err


def test_an_ended_run_returns_nothing_and_writes_nothing(applied):
    assert "0582 V2: 3 ended run(s) decided nothing" in applied.apply_notices
    for status in ("completed", "failed", "aborted"):
        rid = applied.run_with(status)
        before = applied.val(f"SELECT to_jsonb(r)::text FROM public.ottoq_sim_runs r WHERE sim_run_id = '{rid}'")
        rc, out, err = applied.decide(rid)
        assert rc == 0, err
        assert out == ["0/0"], status
        assert applied.val(f"SELECT to_jsonb(r)::text FROM public.ottoq_sim_runs r WHERE sim_run_id = '{rid}'") == before


def test_a_live_run_is_decided_as_before(applied):
    for status in ("initializing", "running", "paused"):
        rc, _, err = applied.decide(applied.run_with(status))
        assert rc != 0 and NEXT_STATEMENT in err, status


def test_the_last_tick_in_order_world_completes_trigger_closes_then_decide_stands_down(applied):
    rid = applied.run_with("running")
    applied.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{rid}'")   # the world step
    assert applied.val(f"SELECT status FROM public.stub_closed_runs WHERE sim_run_id = '{rid}'") == "completed"
    rc, out, err = applied.decide(rid)
    assert rc == 0 and out == ["0/0"], err


def test_0582_is_the_measured_body_plus_one_guard_and_is_recorded_once(applied):
    n = applied.val("SELECT (length(prosrc) - length(replace(prosrc, 'IF v_run.status IN (''completed'', ''failed'', "
                    "''aborted'') THEN', ''))) / length('IF v_run.status IN (''completed'', ''failed'', ''aborted'') THEN') "
                    "FROM pg_proc WHERE proname = 'ottoq_sim_decide_and_dispatch'")
    assert n == "1"
    assert applied.val("SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                       "WHERE name = '0582_a_run_that_has_ended_dispatches_no_car'") == "true/true"
    rc, err = applied.file(M0582)
    assert rc != 0 and "0582 P1: already applied" in err


def test_0582_refuses_while_a_rig_is_in_flight(fresh):
    env = dict(os.environ, PGOPTIONS="-c ottoq.simulate_certification_in_flight=on")
    rc, err = fresh.file(M0582, env=env)
    assert rc != 0 and "0582 P0" in err
    assert fresh.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_sim_decide_and_dispatch'") == MEASURED_MD5


def test_0582_refuses_a_body_it_did_not_measure(fresh):
    fresh.val("""DO $$ BEGIN EXECUTE replace(pg_get_functiondef('public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure),
                                         'RETURN NEXT;\nEND;', 'RETURN NEXT;  -- edited\nEND;'); END $$""")
    rc, err = fresh.file(M0582)
    assert rc != 0 and "0582 P1: ottoq_sim_decide_and_dispatch is not the function measured on 2026-10-02" in err


def test_0582_refuses_a_trigger_that_closes_needs_on_other_statuses(fresh):
    fresh.val("DROP TRIGGER ottoq_sim_runs_close_needs ON public.ottoq_sim_runs")
    fresh.val("""CREATE TRIGGER ottoq_sim_runs_close_needs AFTER UPDATE OF status ON public.ottoq_sim_runs FOR EACH ROW
                 WHEN (((old.status = ANY (ARRAY['initializing'::text, 'running'::text, 'paused'::text]))
                        AND (new.status = ANY (ARRAY['completed'::text, 'failed'::text]))))
                 EXECUTE FUNCTION public.ottoq_tg_close_run_needs_on_terminal()""")
    rc, err = fresh.file(M0582)
    assert rc != 0 and "0582 P1: the close-needs trigger does not fire on exactly completed, failed and aborted" in err


def test_the_rollback_snapshot_restores_the_measured_body(fresh):
    rc, err = fresh.file(M0582)
    assert rc == 0, err
    assert fresh.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_sim_decide_and_dispatch'") != MEASURED_MD5
    fresh.val("DO $r$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0582_pre'); "
              "END $r$")
    assert fresh.val("SELECT md5(prosrc) FROM pg_proc WHERE proname = 'ottoq_sim_decide_and_dispatch'") == MEASURED_MD5
