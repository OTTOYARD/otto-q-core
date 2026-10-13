"""db/migrations/0713, EXECUTED: one agent pass holds its claim for as long as a pass can take.

WHY THIS EXISTS. ottoq_agent_chain_claim lets a new agent pass in once the previous pass has written its decision or once
its claim is older than agent_chain_inflight_timeout_s. 0338 set that lease to 45 s for a 29 s model call; edge v23 later
gave a pass a 90 s model budget and a 30 s solver window, and on run 176b2912 58 of 79 passes started while another was
still running (G423). And the lease's default lives in the claim's own literal, because ottoq_policy_get never reads the
catalog's default_value (G429). Executed here on a stub whose claim is the live definition byte for byte:
  - the getter ignores the catalog default (the premise);
  - before 0713 a pass claimed 60 s ago and still running lets the next one in (the defect, reproduced);
  - after it that pass holds the claim; a crashed pass's claim expires at 130 s; a finished pass releases it at once;
  - a person's run-scoped lease still wins; 0714 brings the catalog row in step, and refuses to before 0713.
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
STUB = os.path.join(ROOT, "tests", "fixtures", "agent_chain_claim_stub.sql")
M0713 = os.path.join(ROOT, "db", "migrations", "0713_one_agent_pass_holds_its_claim_for_as_long_as_a_pass_can_take.sql")
M0714 = os.path.join(ROOT, "db", "migrations", "0714_the_lease_catalog_row_says_what_the_claim_does.sql")
RUN = "a0000000-0000-0000-0000-000000000713"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture()
def db():
    name = f"ottoq_claim_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        d.val(f"INSERT INTO ottoq_sim_runs VALUES ('{RUN}', gen_random_uuid(), 'running', 10, '{{}}')")
        d.val(f"INSERT INTO ottoq_policy_params VALUES ('run', '{RUN}', 'agent_solver_chain_enabled', 1, 't', now())")
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _claim(d):
    return d.json(f"SELECT public.ottoq_agent_chain_claim('{RUN}', 'test')")


def _in_flight_for(d, seconds, tick=10):
    """The previous pass claimed `tick` this many seconds ago; the run has moved on one tick."""
    d.val(f"""UPDATE ottoq_sim_runs SET tick_count = {tick + 1},
                     payload = jsonb_build_object('agent_chain_claim', jsonb_build_object(
                       'tick_seq', {tick}, 'claimed_at', clock_timestamp() - interval '{seconds} seconds', 'source', 't'))
               WHERE sim_run_id = '{RUN}'""")


def test_0713_the_getter_never_reads_the_catalog_default(db):
    db.val("UPDATE ottoq_policy_param_catalog SET default_value = 999 WHERE param_key = 'agent_chain_inflight_timeout_s'")
    assert db.val(f"SELECT public.ottoq_policy_get('{RUN}', 'agent_chain_inflight_timeout_s', 7)") == "7"


def test_0713_before_it_a_pass_still_running_lets_the_next_one_in(db):
    _in_flight_for(db, 60)
    assert _claim(db)["claimed"] is True                                  # the overlap: 60 s > 45 s


def test_0713_a_running_pass_holds_the_claim_a_crashed_one_expires_and_a_finished_one_releases(db):
    rc, err = db.file(M0713)
    assert rc == 0 and "0713 V1 PASSED" in err, err
    _in_flight_for(db, 60)
    r = _claim(db)
    assert r["claimed"] is False and r["reason"] == "agent_run_in_flight" and r["retry_after_s"] == 130, r
    _in_flight_for(db, 125)
    assert _claim(db)["claimed"] is False                                 # a pass can take ~125 s
    _in_flight_for(db, 140)
    assert _claim(db)["claimed"] is True                                  # a crashed pass expires
    _in_flight_for(db, 20)
    db.val(f"""INSERT INTO ottoq_decisions VALUES ('{RUN}', 10, 'orchestrator_agent',
                                                   '{{"agent_chain_trigger_tick": 10}}')""")
    assert _claim(db)["claimed"] is True                                  # a finished pass releases at once


def test_0713_a_persons_run_scoped_lease_still_wins_and_0714_brings_the_catalog_in_step(db):
    db.file(M0713)
    assert db.val("SELECT default_value::int FROM ottoq_policy_param_catalog "
                  "WHERE param_key = 'agent_chain_inflight_timeout_s'") == "45"          # documents 45, runs 130 (G429)
    rc, err = db.file(M0714)
    assert rc == 0 and "0714 V1 PASSED" in err, err
    assert db.val("SELECT default_value::int || '/' || max_value::int FROM ottoq_policy_param_catalog "
                  "WHERE param_key = 'agent_chain_inflight_timeout_s'") == "130/180"
    db.val(f"INSERT INTO ottoq_policy_params VALUES ('run', '{RUN}', 'agent_chain_inflight_timeout_s', 30, 'person', now())")
    _in_flight_for(db, 60)
    assert _claim(db)["claimed"] is True


def test_0714_refuses_before_0713(db):
    rc, err = db.file(M0714)
    assert rc != 0 and "0714 P1" in err, err
