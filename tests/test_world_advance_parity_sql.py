"""db/migrations/0718, EXECUTED: production's world step runs the three phases the certified world runs (G436).

WHY THIS EXISTS. twin.ottoq_world_advance, the world step of a production session, is a hand-made copy of the
certified public.ottoq_sim_advance_tick_world and never called three of its phases: the owner-orders step (rule 9: an
owner's service order would be held an hour and then dropped), the arm cycles, and the tether release (each fast charge
would leave its charger held by a car that has left it). Executed here on the live definition (md5 3489fb13...), with
every callee a stub that records the order it was called in:
  - before 0718 the tick calls none of the three; after it, each once, where the certified world calls it;
  - nothing else in the tick's call order moves;
  - 0718 refuses a second apply, a production session in flight, and a pair in flight;
  - its parity check (V3) refuses a file that leaves a phase out.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import re
import subprocess
import sys
import tempfile
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "world_advance_stub.sql")
M0718 = os.path.join(ROOT, "db", "migrations", "0718_production_runs_the_world_phases_the_twin_certifies.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "07180000-0000-0000-0000-000000000001"
NEW = ["ottoq_owner_orders_tick", "ottoq_arm_advance_cycles", "ottoq_release_expired_tethers"]

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture()
def db():
    name = f"ottoq_wa_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        d.val(f"INSERT INTO public.depots VALUES ('{DEPOT}', 'sim')")
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _production(d, status="running"):
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, run_by, status, started_at, last_tick_at, payload)
              VALUES ('{RUN}', '{DEPOT}', 'production_live', '{status}', now() - interval '1 hour',
                      now() - interval '2 minutes', '{{}}')""")


def _tick(d):
    d.val("TRUNCATE public.t_calls RESTART IDENTITY")
    d.val("SELECT count(*) FROM twin.ottoq_world_advance()")
    return [r for r in d.run("SELECT fn FROM public.t_calls ORDER BY seq")[1]]


def test_0718_the_tick_calls_the_three_phases_where_the_certified_world_does(db):
    _production(db)
    before = _tick(db)
    assert not set(NEW) & set(before), before
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'stopped' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0718)
    assert rc == 0 and "0718 V1-V3 PASSED" in err, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    after = _tick(db)
    for fn in NEW:
        assert after.count(fn) == 1, (fn, after)
    # where the certified world calls each one
    assert after.index("ottoq_owner_orders_tick") < after.index("ottoq_sim_advance_visit_atoms")
    assert after.index("ottoq_arm_advance_cycles") < after.index("ottoq_sim_reconcile_charge_sessions")
    assert after.index("ottoq_sim_recover_chargers") < after.index("ottoq_release_expired_tethers") \
        < after.index("ottoq_reconcile_charger_states")
    # and nothing else moved
    assert [f for f in after if f not in NEW] == before
    assert after[0] == "ottoq_owner_orders_tick" and after[-1] == "ottoq_sim_decide_and_dispatch"


def test_0718_a_phase_that_raises_does_not_abort_the_tick(db):
    _production(db, status="stopped")
    rc, err = db.file(M0718)
    assert rc == 0, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_release_expired_tethers(timestamptz) RETURNS integer
              LANGUAGE plpgsql AS $s$BEGIN RAISE EXCEPTION 'boom'; END$s$""")
    calls = _tick(db)
    assert calls[-1] == "ottoq_sim_decide_and_dispatch", calls
    assert db.val(f"SELECT tick_count FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}'") == "1"


def test_0718_refuses_a_second_apply_a_live_session_and_a_pair_in_flight(db):
    _production(db)
    rc, err = db.file(M0718)
    assert rc != 0 and "0718 P1: a production session is running" in err, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'stopped' WHERE sim_run_id = '{RUN}'")
    db.val("UPDATE public.t_inflight SET n = 1")
    rc, err = db.file(M0718)
    assert rc != 0 and "0718 P0" in err, err
    db.val("UPDATE public.t_inflight SET n = 0")
    rc, err = db.file(M0718)
    assert rc == 0, err
    rc, err = db.file(M0718)
    assert rc != 0 and "0718 P1: twin.ottoq_world_advance is not the definition" in err, err


def test_0718_parity_refuses_a_file_that_leaves_a_phase_out(db):
    # the same file with the tether release taken out of the insertion and out of V1 and V2's expectations
    src = open(M0718).read()
    cut = re.sub(r"  BEGIN PERFORM public\.ottoq_release_expired_tethers\(v_now\);\n"
                 r"  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance tether release: %', SQLERRM; END;\n", "", src)
    cut = cut.replace("OR (SELECT count(*) FROM regexp_matches(v_src, 'ottoq_release_expired_tethers\\s*\\(', 'g')) <> 1", "")
    cut = cut.replace("AND v_p3 < v_q3 AND v_p3 > strpos(v_src, 'ottoq_sim_recover_chargers(')", "")
    assert cut != src and cut.count("PERFORM public.ottoq_release_expired_tethers") == 0
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write(cut)
    try:
        rc, err = db.file(f.name)
    finally:
        os.unlink(f.name)
    assert rc != 0 and "0718 V3 FAILED" in err and "ottoq_release_expired_tethers" in err, err
    # and the refusal rolled the whole file back
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage") == "0"
    assert db.val("SELECT md5(pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure))") == \
        "3489fb1392073751df4f601d45dc7731"
