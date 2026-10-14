"""db/migrations/0724, EXECUTED with concurrent sessions: the live run's row is locked without its key, and the stop door
takes it first.

WHY THIS EXISTS. (G442) The world step and both charger-fault doors took the live run's ottoq_sim_runs row FOR UPDATE,
the one row lock a foreign-key check (FOR KEY SHARE) waits on, so every insert from another session that referenced the
live run waited for the metronome's beat to commit: on c5f4ff34 the 36 agent decision inserts that began inside a world
step waited a mean 4.14 s against 0.29 s for the rest. (G440) ottoq_sim_stop_and_reset disposed the run's proposals and
only then locked the run's row, the reverse of the beat's order, and deadlocked with CALL ottoq_demo_metronome(50) twice
on 2026-10-14. Both claims are about concurrent sessions, so they are tested with concurrent sessions, on a stub that
carries the seven live definitions involved byte for byte (md5-pinned; tests/fixtures/tick_lock_stub.sql):
  - before 0724 a key check waits while the world step or either fault door holds the row, and after it does not;
  - after it two world steps, a world step and either door, a plain UPDATE, a key UPDATE and a DELETE still wait;
  - before 0724 the live metronome and the live stop door deadlock (one of them gets 40P01), and after it the door waits
    for the beat and finishes, and the beat's enactments stand;
  - after it the stop door gives up on the row at the 8 s mark_stopped always gave it, having touched nothing, and every
    other statement of the teardown runs under the lock_timeout it ran under before;
  - one session gets the same rows with and without 0724 (the lineage's FALSE/FALSE);
  - 0724 refuses a second apply, a pair in flight, a key-column UPDATE in the catalog, a metronome that commits between
    its world and decide steps, and a patch that changes more than it says, and a refusal rolls the whole file back.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "tick_lock_stub.sql")
M0724 = os.path.join(ROOT, "db", "migrations",
                     "0724_the_runs_row_is_locked_without_its_key_and_taken_first_by_the_stop_door.sql")
LIVE = {
    "public.ottoq_sim_advance_tick_world(uuid)": "3e0ddbb1b097587bc2c0e9135d7895aa",
    "public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)": "0cd92ef247e8959fda68b2e6087bd944",
    "twin.ottoq_report_charger_fault(uuid,text,text,text)": "a4339948b3520016e9979dc13faac605",
    "public.ottoq_sim_stop_and_reset(uuid,text)": "bc8ee182436dfcd6bd53f62547ad5d5e",
    "public.ottoq_sim_mark_stopped(uuid,text)": "d3325a7e94bc2791c5ebad11ae61a85d",
    "public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean)": "5ed4b74688e95d22736f3e4c6123e6a6",
    "public.ottoq_demo_metronome(integer)": "d02b6af9e3fa622267247f7277ef7057",
}
PATCHED = list(LIVE)[:4]
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "07240000-0000-0000-0000-000000000001"
CHARGER = "07240000-0000-0000-0000-0000000000c1"
STALL = "07240000-0000-0000-0000-0000000000a1"
CAR = "07240000-0000-0000-0000-0000000000b1"
SESSION = "07240000-0000-0000-0000-0000000000d1"
DOOR_APP = "ottoq_0724_door"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _cmd(name, sql):
    return ["psql", *base._conn_args(), "-d", name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql]


class Db(base.Db):
    def background(self, sql, app):
        env = {**os.environ, "PGAPPNAME": app}
        return subprocess.Popen(_cmd(self.name, sql), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                env=env)

    def wait_for(self, predicate_sql, what, timeout=15.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.val(predicate_sql) == "t":
                return
            time.sleep(0.05)
        raise AssertionError(f"timed out waiting for {what}")

    def wait_sleeping(self, app):
        self.wait_for(f"SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = '{app}' "
                      f"AND wait_event = 'PgSleep')", f"{app} to hold its locks and sleep")


def _new(tag):
    name = f"ottoq_tl_{tag}_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1",
                    "-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    rc, err = d.file(STUB)
    assert rc == 0, f"stub did not load: {err}"
    d.val(f"INSERT INTO public.depots VALUES ('{DEPOT}', 'sim')")
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, run_by, sim_clock_start, sim_clock_current,
                                                 sim_clock_end, tick_count, payload)
              VALUES ('{RUN}', '{DEPOT}', 'running', 'operator_demo', '2026-10-14 13:00+00', '2026-10-14 13:00+00',
                      '2026-10-14 22:00+00', 1, '{{"playback_mode": "fixed"}}')""")
    d.val(f"""INSERT INTO public.ottoq_ocpp_chargers (charger_id, depot_id, station_state, last_heartbeat_at)
              VALUES ('{CHARGER}', '{DEPOT}', 'Available', '2026-10-14 13:00+00')""")
    d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, status, ocpp_charger_id, current_vehicle_id)
              VALUES ('{STALL}', '{DEPOT}', 'DCFC-01', 'dcfc', 'occupied', '{CHARGER}', '{CAR}')""")
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, current_state, current_stall_id, current_soc)
              VALUES ('{CAR}', '{DEPOT}', 'autonomous', 'charging', '{STALL}', 60)""")
    d.val(f"""INSERT INTO public.ocpp_sessions (id, stall_id, vehicle_id, status, sim_run_id)
              VALUES ('{SESSION}', '{STALL}', '{CAR}', 'active', '{RUN}')""")
    for i in range(3):
        d.val(f"""INSERT INTO public.ottoq_external_proposals (sim_run_id, entity_id, source, proposal)
                  VALUES ('{RUN}', gen_random_uuid(), 'forward_lex', '{{"stall_id": "{STALL}"}}')""")
    return d


def _drop(d):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                    f"DROP DATABASE IF EXISTS {d.name} WITH (FORCE)"], capture_output=True)


@pytest.fixture()
def db():
    d = _new("t")
    try:
        yield d
    finally:
        _drop(d)


def _apply(d, path=M0724):
    return d.file(path)


def _applied(d):
    rc, err = _apply(d)
    assert rc == 0, err
    assert "0724 V1-V3 PASSED" in err and "0724 V4 PASSED" in err, err
    return d


HOLDERS = {
    # each takes the live run's row and then sleeps inside its transaction, as a beat or a door does
    "world_step": f"SELECT count(*) FROM public.ottoq_sim_advance_tick_world('{RUN}')",
    "cockpit_fault_door": f"SELECT public.ottoq_twin_inject_charger_fault('{RUN}')",
    "tech_fault_door": f"SELECT twin.ottoq_report_charger_fault('{CHARGER}')",
}


def _hold(d, holder, seconds=3):
    app = f"ottoq_0724_{holder}"
    p = d.background(f"BEGIN; {HOLDERS[holder]}; SELECT pg_sleep({seconds}); COMMIT;", app)
    d.wait_sleeping(app)
    return p


def _try(d, sql, timeout="1s"):
    t0 = time.time()
    rc, _, err = d.run(f"SET lock_timeout = '{timeout}'; {sql}")
    return rc, err, time.time() - t0


DECISION = f"INSERT INTO public.ottoq_decisions (sim_run_id, resolved_action_context) VALUES ('{RUN}', 'orchestrator_agent')"
PROPOSAL = (f"INSERT INTO public.ottoq_external_proposals (sim_run_id, entity_id, source) "
            f"VALUES ('{RUN}', gen_random_uuid(), 'llm_advisor')")


def test_0724_the_stub_carries_the_live_bodies(db):
    for sig, md5 in LIVE.items():
        assert db.val(f"SELECT md5(pg_get_functiondef('{sig}'::regprocedure))") == md5, sig


@pytest.mark.parametrize("holder", list(HOLDERS))
def test_0724_before_a_key_check_waits_for_the_row_holder(db, holder):
    p = _hold(db, holder)
    rc, err, took = _try(db, DECISION)
    p.communicate(timeout=30)
    assert p.returncode == 0
    # the agent's decision insert waited on the run's row, in the key check, until its lock_timeout ran out
    assert rc != 0 and "canceling statement due to lock timeout" in err, err
    assert 'relation "ottoq_sim_runs"' in err and "FOR KEY SHARE" in err, err
    assert took >= 0.9


@pytest.mark.parametrize("holder", list(HOLDERS))
def test_0724_after_a_key_check_does_not_wait_for_the_row_holder(db, holder):
    _applied(db)
    p = _hold(db, holder)
    rc1, err1, took1 = _try(db, DECISION)
    rc2, err2, took2 = _try(db, PROPOSAL)
    p.communicate(timeout=30)
    assert p.returncode == 0
    assert rc1 == 0 and rc2 == 0, (err1, err2)
    assert took1 < 0.8 and took2 < 0.8, (took1, took2)
    # the world step has run its own UPDATE of the row by the time it sleeps (non-key: still no wait above)
    if holder == "world_step":
        assert db.val(f"SELECT tick_count FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}'") == "2"


def test_0724_after_ticks_doors_updates_and_deletes_still_wait_for_the_world_step(db):
    _applied(db)
    p = _hold(db, "world_step", seconds=8)
    waits = {
        "a second world step": f"SELECT count(*) FROM public.ottoq_sim_advance_tick_world('{RUN}')",
        "the cockpit fault door": f"SELECT public.ottoq_twin_inject_charger_fault('{RUN}')",
        "the tech fault door": f"SELECT twin.ottoq_report_charger_fault('{CHARGER}')",
        "a plain UPDATE": f"UPDATE public.ottoq_sim_runs SET notes = 'x' WHERE sim_run_id = '{RUN}'",
        "a key UPDATE": f"UPDATE public.ottoq_sim_runs SET sim_run_seq = sim_run_seq + 1000 WHERE sim_run_id = '{RUN}'",
        "a DELETE": f"DELETE FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}'",
    }
    try:
        for what, sql in waits.items():
            rc, err, _ = _try(db, sql, "500ms")
            assert rc != 0 and "canceling statement due to lock timeout" in err, (what, err)
            assert 'relation "ottoq_sim_runs"' in err, (what, err)
        # and a key share does not
        rc, err, took = _try(db, f"SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}' FOR KEY SHARE", "500ms")
        assert rc == 0 and took < 0.4, err
    finally:
        p.communicate(timeout=30)
    assert p.returncode == 0


def _metronome_and_door(d):
    """The live metronome's beat holds the run's row and reaches its decide step; the live stop door is called as the
    operator start calls it; the decide step then writes the run's proposals once the door is waiting on a lock."""
    d.val(f"UPDATE public.t_decide SET door = '{DOOR_APP}'")
    m = d.background("CALL public.ottoq_demo_metronome(4)", "ottoq_0724_metronome")
    d.wait_for("SELECT EXISTS (SELECT 1 FROM pg_stat_activity "
               "WHERE application_name = 'ottoq_0724_metronome_in_decide')", "the metronome to reach its decide step")
    door = d.background(f"SET lock_timeout = '15s'; "
                        f"SELECT public.ottoq_sim_stop_and_reset('{RUN}', 'superseded by busy_day')", DOOR_APP)
    door_out, door_err = door.communicate(timeout=60)
    m_out, m_err = m.communicate(timeout=60)
    assert m.returncode == 0, m_err
    return door.returncode, door_out, door_err, m_err


def test_0724_before_the_stop_door_and_the_metronome_deadlock(db):
    door_rc, _, door_err, m_err = _metronome_and_door(db)
    failures = db.json("SELECT COALESCE(jsonb_agg(jsonb_build_array(phase, message, sqlstate)), '[]') "
                       "FROM public.t_tick_failures")
    door_lost = door_rc != 0 and "deadlock detected" in door_err
    beat_lost = failures == [["decide", "deadlock detected", "40P01"]] and "deadlock detected" in m_err
    # either side can lose, as on 2026-10-14 (16:40:04 the door, 16:42:42 the metronome's decide), and exactly one does
    assert door_lost != beat_lost, (door_rc, door_err, failures, m_err)
    if door_lost:
        assert failures == []
        assert db.val(f"SELECT status FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}'") == "running"


def test_0724_after_the_stop_door_waits_for_the_beat_and_finishes(db):
    _applied(db)
    door_rc, door_out, door_err, m_err = _metronome_and_door(db)
    assert door_rc == 0, door_err
    assert json.loads(door_out.splitlines()[-1]) == {"released": True, "marked_stopped": True}
    assert "deadlock" not in m_err and "deadlock" not in door_err
    assert db.val("SELECT count(*) FROM public.t_tick_failures") == "0"
    # the beat committed first, so its enactments stand and the stop found nothing left to expire
    assert db.json("SELECT jsonb_object_agg(status, n) FROM (SELECT status, count(*) n "
                   "FROM public.ottoq_external_proposals GROUP BY 1) x") == {"enacted": 3}
    run = db.json(f"SELECT jsonb_build_object('status', status, 'ticks', tick_count, 'reason', failure_reason) "
                  f"FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}'")
    assert run == {"status": "completed", "ticks": 2, "reason": "superseded by busy_day"}


def test_0724_after_the_stop_door_gives_up_on_the_row_at_eight_seconds_having_touched_nothing(db):
    _applied(db)
    app = "ottoq_0724_long_beat"
    p = db.background(f"BEGIN; SELECT count(*) FROM public.ottoq_sim_advance_tick_world('{RUN}'); "
                      f"SELECT pg_sleep(10); COMMIT;", app)
    db.wait_sleeping(app)
    rc, err, took = _try(db, f"SELECT public.ottoq_sim_stop_and_reset('{RUN}', 'operator_stop')", "15s")
    p.communicate(timeout=30)
    assert rc != 0 and "canceling statement due to lock timeout" in err and 'relation "ottoq_sim_runs"' in err, err
    assert "FOR NO KEY UPDATE" in err, err                    # at the door's own lock, not mark_stopped's UPDATE
    assert 7.5 <= took < 11, took                              # mark_stopped's 8 s, not the caller's 15 s
    # it touched nothing before the row: no rescue step, no proposal disposed, no release
    assert db.val("SELECT count(*) FROM public.t_calls WHERE fn IN ('ottoq_promote_proposal_candidates', "
                  "'ottoq_sim_release_depot')") == "0"
    assert db.val("SELECT count(*) FROM public.ottoq_external_proposals WHERE status = 'pending'") == "3"


@pytest.mark.parametrize("phase", ["before", "after"])
def test_0724_the_teardown_runs_under_the_lock_timeout_it_ran_under_before(db, phase):
    if phase == "after":
        _applied(db)
    out = db.val(f"SET lock_timeout = '15s'; SELECT public.ottoq_sim_stop_and_reset('{RUN}', 'operator_stop')")
    assert json.loads(out) == {"released": True, "marked_stopped": True}
    notes = db.json("SELECT jsonb_object_agg(fn, note) FROM public.t_calls "
                    "WHERE fn IN ('ottoq_promote_proposal_candidates', 'ottoq_sim_release_depot')")
    # the rescue step under the caller's 15 s, the release under the 8 s mark_stopped sets, both before and after
    assert notes == {"ottoq_promote_proposal_candidates": "15s", "ottoq_sim_release_depot": "8s"}, notes
    assert db.val("SELECT count(*) FROM public.ottoq_external_proposals WHERE status = 'expired' "
                  "AND disposition_reason = 'run_finalized'") == "3"


DUMP = """
SELECT jsonb_build_object(
  'runs', (SELECT jsonb_agg(to_jsonb(x) - 'last_tick_at' - 'next_tick_due_at' - 'ended_at' - 'started_at' - 'sim_run_seq'
                            ORDER BY x.sim_run_id) FROM public.ottoq_sim_runs x),
  'calls', (SELECT jsonb_agg(jsonb_build_array(x.fn, x.note) ORDER BY x.seq) FROM public.t_calls x),
  'sessions', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.ocpp_sessions x),
  'stalls', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.stalls x),
  'chargers', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.charger_id) FROM public.ottoq_ocpp_chargers x),
  'vehicles', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.vehicles x),
  'proposals', (SELECT jsonb_agg(jsonb_build_array(x.status, x.disposition_reason) ORDER BY x.status, x.disposition_reason)
                  FROM public.ottoq_external_proposals x),
  'tick_log', (SELECT jsonb_agg(jsonb_build_array(x.tick_seq, x.sim_clock_before, x.sim_clock_after, x.sim_advance_s)
                                ORDER BY x.tick_seq) FROM public.ottoq_tick_clock_log x),
  'wear', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.tick_seq) FROM public.ottoq_wear_tick_status x))
"""


def test_0724_one_session_gets_the_same_rows_with_and_without_it():
    """The lineage's FALSE/FALSE: a certified arm runs in one transaction, where a lock's mode changes nothing read or
    written. The same script (two world steps, the cockpit's fault injection, a third world step, the stop) in one
    session, before and after 0724."""
    before, after = _new("b"), _new("a")
    try:
        _applied(after)
        script = (f"BEGIN; SET LOCAL lock_timeout = '15s'; "
                  f"SELECT count(*) FROM public.ottoq_sim_advance_tick_world('{RUN}'); "
                  f"SELECT count(*) FROM public.ottoq_sim_advance_tick_world('{RUN}'); "
                  f"SELECT public.ottoq_twin_inject_charger_fault('{RUN}', NULL, 45, 'test'); "
                  f"SELECT count(*) FROM public.ottoq_sim_advance_tick_world('{RUN}'); "
                  f"SELECT public.ottoq_sim_stop_and_reset('{RUN}', 'operator_stop'); COMMIT;")
        for d in (before, after):
            d.val(script)
        b, a = before.json(DUMP), after.json(DUMP)
        for k in b:
            assert a[k] == b[k], k
        assert b["runs"][0]["status"] == "completed" and b["runs"][0]["tick_count"] == 4
        assert b["chargers"][0]["station_state"] == "Faulted"
    finally:
        _drop(before)
        _drop(after)


def test_0724_refuses_a_second_apply_and_a_pair_in_flight(db):
    db.val("UPDATE public.t_inflight SET n = 1")
    rc, err = _apply(db)
    assert rc != 0 and "0724 P0" in err, err
    db.val("UPDATE public.t_inflight SET n = 0")
    _applied(db)
    rc, err = _apply(db)
    assert rc != 0 and "0724 P1: public.ottoq_sim_advance_tick_world(uuid) is not the definition" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0724%'") == "1"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0724_pre'") == "4"


def _unchanged(d):
    for sig in PATCHED:
        assert d.val(f"SELECT md5(pg_get_functiondef('{sig}'::regprocedure))") == LIVE[sig], sig
    assert d.val("SELECT count(*) FROM public.ottoq_cert_lineage") == "0"
    assert d.val("SELECT count(*) FROM public.ottoq_schema_snapshots") == "0"


def test_0724_refuses_when_an_update_assigns_a_key_column(db):
    db.val("""CREATE FUNCTION public.t_renumber(p uuid) RETURNS void LANGUAGE plpgsql AS $s$
              BEGIN UPDATE ottoq_sim_runs SET payload = '{}', sim_run_seq = 7 WHERE sim_run_id = p; END $s$""")
    rc, err = _apply(db)
    assert rc != 0 and "0724 P2: 1 UPDATE(s) of ottoq_sim_runs assign a key column (public.t_renumber)" in err, err
    _unchanged(db)


def test_0724_refuses_when_the_metronome_commits_between_its_world_and_decide_steps(db):
    db.val("""DO $x$ BEGIN
                EXECUTE replace(pg_get_functiondef('public.ottoq_demo_metronome(integer)'::regprocedure),
                                '      IF v_advanced IS NOT NULL THEN', '      COMMIT;' || chr(10) || '      IF v_advanced IS NOT NULL THEN');
              END $x$""")
    rc, err = _apply(db)
    assert rc != 0 and "0724 P2: the metronome no longer runs the world step and then the decide step" in err, err
    _unchanged(db)


def test_0724_v1_refuses_a_patch_that_changes_more_than_it_says(db):
    src = open(M0724, encoding="utf-8").read()
    anchor = "     FOR NO KEY UPDATE;   -- 0724 (G442): the mode the tick takes; the order above is unchanged\n$n$;\n  v_report_a"
    assert src.count(anchor) == 1
    cut = src.replace(anchor, "     FOR NO KEY UPDATE SKIP LOCKED;   -- 0724 (G442): the mode the tick takes; the order "
                              "above is unchanged\n$n$;\n  v_report_a")
    with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False) as f:
        f.write(cut)
    try:
        rc, err = _apply(db, f.name)
    finally:
        os.unlink(f.name)
    assert rc != 0 and "0724 V1 FAILED: public.ottoq_twin_inject_charger_fault" in err, err
    _unchanged(db)
