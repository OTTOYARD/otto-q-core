"""db/migrations/0719, EXECUTED: a production start takes the world from research work, as the operator door does (G437).

WHY THIS EXISTS. pg_cron runs one job at a time here, so a research arm holding the world blocks the production tick
for as long as it runs (G141; the sweep held 43.25 of the last 168 hours, the longest arm 2 h 26 m). The operator door
cancels every running check and takes the world lock before it starts a run; ottoq_production_start did neither.
Executed here on the live definition (md5 c0ae7ec6...), with a second session standing in for a research arm:
  - a backend holding the world lock inside its statement (as every research arm does) is cancelled, its lock is
    released by its rollback, and the session starts and says what it interrupted;
  - a hand-run pair that holds no lock is cancelled too;
  - with nothing running, the start is what it was, plus an empty `interrupted`;
  - the helper is the service role's only; 0719 refuses a second apply and a check in flight;
  - V2 refuses a helper whose cancel predicate drifts from the operator door's.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import subprocess
import sys
import tempfile
import time
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "production_start_stub.sql")
M0719 = os.path.join(ROOT, "db", "migrations", "0719_production_start_takes_the_world_as_the_operator_door_does.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture()
def db():
    name = f"ottoq_ps_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        d.val(f"INSERT INTO public.depots VALUES ('{DEPOT}', 'sim')")
        d.val("INSERT INTO public.ottoq_scenarios (scenario_code) VALUES ('production')")
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _arm(d, sql):
    """A second session standing in for a research arm; returns once it is visibly running."""
    p = subprocess.Popen(["psql", *base._conn_args(), "-d", d.name, "-q", "-At", "-c", sql],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for _ in range(100):
        n = d.val("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND state = 'active' "
                  "AND query ~ 'pg_sleep' AND pid <> pg_backend_pid()")
        if n == "1":
            return p
        time.sleep(0.05)
    p.kill()
    raise AssertionError("the arm never started")


def test_0719_a_start_cancels_the_arm_holding_the_world_and_says_so(db):
    rc, err = db.file(M0719)
    assert rc == 0 and "0719 V1-V4 PASSED" in err, err
    arm = _arm(db, "SELECT pg_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint), pg_sleep(60)")
    t0 = time.time()
    out = db.json("SELECT public.ottoq_production_start()")
    took = time.time() - t0
    _, arm_err = arm.communicate(timeout=10)
    assert "canceling statement due to user request" in arm_err, arm_err
    assert out["ok"] is True, out
    assert len(out["interrupted"]) == 1, out
    hit = out["interrupted"][0]
    assert hit["kind"] == "recertification pair" and hit["cancelled"] is True and hit["by"] == "production_start", hit
    assert took < 10, f"the start waited {took:.1f} s"
    assert db.val("SELECT count(*) FROM public.ottoq_sim_runs WHERE run_by = 'production_live' AND status = 'running'") == "1"
    ev = db.json("SELECT payload FROM public.t_events WHERE event_type = 'production.session_started'")
    assert ev["interrupted"] == out["interrupted"], ev


def test_0719_a_hand_run_pair_with_no_lock_is_cancelled_too(db):
    rc, err = db.file(M0719)
    assert rc == 0, err
    arm = _arm(db, "SELECT 'ottoq_determinism_pair(' AS hand_run, pg_sleep(60)")
    out = db.json("SELECT public.ottoq_production_start()")
    _, arm_err = arm.communicate(timeout=10)
    assert "canceling statement due to user request" in arm_err, arm_err
    assert out["ok"] is True and [i["kind"] for i in out["interrupted"]] == ["determinism pair"], out


def test_0719_with_nothing_running_the_start_is_what_it_was(db):
    before = db.json("SELECT public.ottoq_production_start()")
    db.val("UPDATE public.ottoq_sim_runs SET status = 'stopped'")
    rc, err = db.file(M0719)
    assert rc == 0, err
    after = db.json("SELECT public.ottoq_production_start()")
    assert after.pop("interrupted") == [], after
    for k in ("sim_run_id",):
        before.pop(k), after.pop(k)
    assert after == before
    # a run already running at the depot is still refused, before anything is cancelled
    again = db.json("SELECT public.ottoq_production_start()")
    assert again["ok"] is False and again["error"] == "depot_already_has_running_run" and "interrupted" not in again


def test_0719_the_helper_is_the_service_roles_and_the_file_refuses_what_it_should(db):
    db.val("UPDATE public.t_inflight SET n = 1")
    rc, err = db.file(M0719)
    assert rc != 0 and "0719 P0" in err, err
    db.val("UPDATE public.t_inflight SET n = 0")
    rc, err = db.file(M0719)
    assert rc == 0, err
    assert db.val("SELECT has_function_privilege('anon', 'public.ottoq_world_yield_to_start(text)', 'EXECUTE')") == "f"
    assert db.val("SELECT has_function_privilege('authenticated', 'public.ottoq_world_yield_to_start(text)', 'EXECUTE')") == "f"
    assert db.val("SELECT has_function_privilege('service_role', 'public.ottoq_world_yield_to_start(text)', 'EXECUTE')") == "t"
    rc, err = db.file(M0719)
    assert rc != 0 and "0719 P1: ottoq_production_start is not the definition" in err, err


def test_0719_v2_refuses_a_helper_whose_cancel_predicate_drifts(db):
    src = open(M0719).read()
    # the helper (and only the helper: V2's literal is untouched) stops sparing a migration's session
    head, tail = src.split("-- ══ V ══", 1)
    cut = head.replace("       AND COALESCE(a.query, '') !~* 'migration-version:'\n", "", 1) + "-- ══ V ══" + tail
    assert cut != src
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write(cut)
    try:
        rc, err = db.file(f.name)
    finally:
        os.unlink(f.name)
    assert rc != 0 and "0719 V2 FAILED" in err, err
    assert db.val("SELECT to_regprocedure('public.ottoq_world_yield_to_start(text)') IS NULL") == "t"
