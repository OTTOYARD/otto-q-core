"""db/migrations/0790, EXECUTED with concurrent sessions: the stop door takes the live run's row before the run's
proposals, the order the metronome's beat takes them in. And why the tick's own FOR UPDATE is left as it is.

WHY THIS EXISTS. (G440) ottoq_sim_stop_and_reset disposed the run's proposals and only then locked the run's row, the
reverse of the beat's order, and deadlocked with CALL ottoq_demo_metronome(50) twice on 2026-10-14. (G490) The world step
and both charger-fault doors take the live run's row FOR UPDATE, the one row lock a foreign-key check (FOR KEY SHARE)
waits on, so an insert from another session that references the live run waits for the beat to commit (on c5f4ff34, 36 of
239 agent decision inserts waited a mean 4.14 s). The first draft of 0790 weakened that lock too; it is withdrawn,
because the wait is what keeps ottoq_decide_tick's A3 close (its line 1228) right. Both claims are about concurrent
sessions, so they are tested with concurrent sessions, on a stub carrying the eleven live definitions involved byte for
byte (md5-pinned) and decide_tick's A3 verbatim (tests/fixtures/tick_lock_stub.sql):
  - before 0790 the live metronome and the live stop door deadlock (one of them gets 40P01), and after it the door waits
    for the beat and finishes, and the beat's enactments stand;
  - after it the stop door gives up on the row at the 8 s mark_stopped always gave it, having touched nothing, and every
    other statement of the teardown runs under the lock_timeout it ran under before;
  - the door's lock does not make a key check wait, before or after, and a writer that supersedes and then inserts
    finishes beside the door as it did before 0790 (and deadlocks with it if the door took FOR UPDATE instead);
  - the door takes the row first only on a running run: a stop on a stopped or paused run arriving inside the prior-run
    purge (which deletes a run's rows by dynamic SQL and the run's row last) finishes beside it before and after 0790,
    where locking any run's row (0790's first version) or mark_stopped's running-or-paused deadlocks with it; a stop on
    a running run and the demo start's abort-then-purge deadlock before 0790 and serialize after; a stop on a paused
    run and that demo start deadlock before and after (0790 leaves a paused run as it was);
  - and where that is not enough (G491, open): the purge chooses its runs once and never locks them, so a run it chose
    while paused and that is resumed before it deletes the runs' rows is deleted while running. A stop on that run
    finishes beside a lone purge before 0790, the run deleted and nothing marked, and deadlocks with it after;
  - G490 is unchanged: a key check still waits while the world step or either fault door holds the row, before and after;
  - and why: with the tick's FOR UPDATE, a proposer's batch through the live submit door, resubmitting for a car the
    beat has just enacted, deadlocks, and whichever side PostgreSQL aborts, the evidence ledger records no proposal the
    kernel did not take (each side is forced by deadlock_timeout, and the race is also run at the server's 1 s, as
    live); with the withdrawn FOR NO KEY UPDATE (applied here to a throwaway database only), the batch commits mid-beat
    and the ledger records the stall the kernel never chose. The interleaving is constructed: it is of the class of the
    17:34:06 UTC deadlock in the log (forward_lex's batch, its key check waiting on the beat), not that event, whose
    beat-side edge was not logged and was not decide_tick line 1228 (0790 §1 (b));
  - one session gets the same rows with and without 0790 (the lineage's FALSE/FALSE);
  - 0790 refuses a second apply, a pair in flight, a key-column UPDATE in the catalog, a writer of the proposals that also
    takes the run's row, a prior-run purge that would choose a running run, a metronome that commits between its world
    and decide steps, and a patch that changes more than it says, and a refusal rolls the whole file back.
A deadlock test never names the side PostgreSQL aborts unless it forces it: the documentation says which one "is
difficult to predict and should not be relied upon" (PostgreSQL 16, 13.3.4). It SKIPS where no scratch PostgreSQL is
reachable.
"""
import json
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
STUB = os.path.join(ROOT, "tests", "fixtures", "tick_lock_stub.sql")
M0790 = os.path.join(ROOT, "db", "migrations", "0790_the_stop_door_takes_the_runs_row_before_the_proposals.sql")
LIVE = {
    "public.ottoq_sim_stop_and_reset(uuid,text)": "bc8ee182436dfcd6bd53f62547ad5d5e",
    "public.ottoq_sim_advance_tick_world(uuid)": "3e0ddbb1b097587bc2c0e9135d7895aa",
    "public.ottoq_twin_inject_charger_fault(uuid,uuid,numeric,text)": "0cd92ef247e8959fda68b2e6087bd944",
    "twin.ottoq_report_charger_fault(uuid,text,text,text)": "a4339948b3520016e9979dc13faac605",
    "public.ottoq_sim_mark_stopped(uuid,text)": "d3325a7e94bc2791c5ebad11ae61a85d",
    "public.ottoq_dispose_external_proposals(uuid,bigint,timestamptz,boolean)": "5ed4b74688e95d22736f3e4c6123e6a6",
    "public.ottoq_demo_metronome(integer)": "d02b6af9e3fa622267247f7277ef7057",
    "public.ottoq_caller_identity()": "9fc609c3613e62a79e40c2399b3f893d",
    "public.ottoq_submit_external_proposal(uuid,uuid,text,text,uuid,jsonb,text,integer)":
        "d19f166c1e280cb9bdc186f936f28d7c",
    "public.ottoq_proposer_submit_batch(uuid,uuid,text,jsonb,jsonb,integer)": "8c78997969489b3c8e097eba41fadc13",
    "public.ottoq_capture_proposal_disposition()": "2d16c05a77ab1ad9b81780105fbfd78b",
}
# ottoq_decide_tick's A3 (pg_get_functiondef lines 1231-1248, its PL/pgSQL lines 1226-1243), read live 2026-10-14
A3_MD5 = "7bef452bd6193d52db9a57ef018e25df"
STOP = "public.ottoq_sim_stop_and_reset(uuid,text)"
# the door's early lock as 0790 writes it: a running run's row only (§3)
LOCK_STMT = "PERFORM 1 FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id AND status = 'running' FOR NO KEY UPDATE;"
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "07240000-0000-0000-0000-000000000001"
CHARGER = "07240000-0000-0000-0000-0000000000c1"
STALL = "07240000-0000-0000-0000-0000000000a1"
STALL_B = "07240000-0000-0000-0000-0000000000a2"
CAR = "07240000-0000-0000-0000-0000000000b1"
SESSION = "07240000-0000-0000-0000-0000000000d1"
DOOR_APP = "ottoq_0790_door"
AGENT_APP = "ottoq_0790_agent_batch"
WRITER_APP = "ottoq_0790_writer"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _cmd(name, sql):
    return ["psql", *base._conn_args(), "-d", name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql]


class Db(base.Db):
    def background(self, sql, app, deadlock_timeout=None):
        env = {**os.environ, "PGAPPNAME": app}
        if deadlock_timeout:   # this session's own, set at connection start (a superuser's setting, as on scratch and CI)
            env["PGOPTIONS"] = f"-c deadlock_timeout={deadlock_timeout}"
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

    def wait_locked(self, app):
        self.wait_for(f"SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = '{app}' "
                      f"AND wait_event_type = 'Lock')", f"{app} to wait on a lock")


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


def _apply(d, path=M0790):
    return d.file(path)


def _applied(d):
    rc, err = _apply(d)
    assert rc == 0, err
    assert "0790 V1-V3 PASSED" in err and "0790 V4 PASSED" in err, err
    return d


def _phase(d, phase):
    if phase == "after":
        _applied(d)


def _swap(d, sig, old, new):
    """Rewrite one statement of a function on this throwaway database, the anchor asserted to occur exactly once."""
    d.val(f"""DO $x$ DECLARE v text := pg_get_functiondef('{sig}'::regprocedure);
              BEGIN
                IF (length(v) - length(replace(v, $o${old}$o$, ''))) / length($o${old}$o$) <> 1 THEN
                  RAISE EXCEPTION 'anchor not found once in {sig}';
                END IF;
                EXECUTE replace(v, $o${old}$o$, $n${new}$n$);
              END $x$""")


HOLDERS = {
    # each takes the live run's row and then sleeps inside its transaction, as a beat or a door does
    "world_step": f"SELECT count(*) FROM public.ottoq_sim_advance_tick_world('{RUN}')",
    "cockpit_fault_door": f"SELECT public.ottoq_twin_inject_charger_fault('{RUN}')",
    "tech_fault_door": f"SELECT twin.ottoq_report_charger_fault('{CHARGER}')",
}


def _hold(d, holder, seconds=3):
    app = f"ottoq_0790_{holder}"
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


def test_0790_the_stub_carries_the_live_bodies(db):
    for sig, md5 in LIVE.items():
        assert db.val(f"SELECT md5(pg_get_functiondef('{sig}'::regprocedure))") == md5, sig
    assert db.val("SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgname = 'ottoq_capture_proposal_disposition_trg'") \
        == ("CREATE TRIGGER ottoq_capture_proposal_disposition_trg AFTER UPDATE OF status ON public.ottoq_external_proposals "
            "FOR EACH ROW EXECUTE FUNCTION ottoq_capture_proposal_disposition()")
    # the decide stand-in carries decide_tick's A3 verbatim, and its dispose call (line 1244) after it
    a3 = ("WITH s AS (SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure), "
          "b AS (SELECT strpos(prosrc, '  -- A3: close') a, strpos(prosrc, '  PERFORM public.ottoq_dispose_external_proposals("
          "p_sim_run_id, v_tick, v_clock, false);') z, prosrc FROM s) SELECT md5(substr(prosrc, a, z - a - 1)) FROM b "
          "WHERE a > 0 AND z > a")
    assert db.val(a3) == A3_MD5
    # the live proposal door supersedes the car's pending proposal and then inserts the new one (the writer below)
    assert db.val("SELECT strpos(prosrc, 'UPDATE public.ottoq_external_proposals') > 0 AND "
                  "strpos(prosrc, 'UPDATE public.ottoq_external_proposals') < strpos(prosrc, "
                  "'INSERT INTO public.ottoq_external_proposals') FROM pg_proc "
                  "WHERE oid = 'public.ottoq_submit_external_proposal(uuid,uuid,text,text,uuid,jsonb,text,integer)'"
                  "::regprocedure") == "t"


# ── G440: the stop door and the metronome ──

def _metronome_and_door(d):
    """The live metronome's beat holds the run's row and reaches its decide step; the live stop door is called as the
    operator start calls it; the decide step then writes the run's proposals once the door is waiting on a lock."""
    d.val(f"UPDATE public.t_decide SET door = '{DOOR_APP}'")
    m = d.background("CALL public.ottoq_demo_metronome(4)", "ottoq_0790_metronome")
    d.wait_for("SELECT EXISTS (SELECT 1 FROM pg_stat_activity "
               "WHERE application_name = 'ottoq_0790_metronome_in_decide')", "the metronome to reach its decide step")
    door = d.background(f"SET lock_timeout = '15s'; "
                        f"SELECT public.ottoq_sim_stop_and_reset('{RUN}', 'superseded by busy_day')", DOOR_APP)
    door_out, door_err = door.communicate(timeout=60)
    m_out, m_err = m.communicate(timeout=60)
    assert m.returncode == 0, m_err
    return door.returncode, door_out, door_err, m_err


def test_0790_before_the_stop_door_and_the_metronome_deadlock(db):
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


def test_0790_after_the_stop_door_waits_for_the_beat_and_finishes(db):
    _applied(db)
    door_rc, door_out, door_err, m_err = _metronome_and_door(db)
    assert door_rc == 0, door_err
    assert json.loads(door_out.splitlines()[-1]) == {"released": True, "marked_stopped": True}
    assert "deadlock" not in m_err and "deadlock" not in door_err
    assert db.val("SELECT count(*) FROM public.t_tick_failures") == "0"
    # the beat committed first, so its enactments stand and the stop found nothing left to expire
    assert db.json("SELECT jsonb_object_agg(status, n) FROM (SELECT status, count(*) n "
                   "FROM public.ottoq_external_proposals GROUP BY 1) x") == {"enacted": 3}
    assert db.json("SELECT jsonb_object_agg(status, n) FROM (SELECT status, count(*) n "
                   "FROM public.ottoq_proposal_disposition_ledger GROUP BY 1) x") == {"enacted": 3}
    run = db.json(f"SELECT jsonb_build_object('status', status, 'ticks', tick_count, 'reason', failure_reason) "
                  f"FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}'")
    assert run == {"status": "completed", "ticks": 2, "reason": "superseded by busy_day"}


def test_0790_after_the_stop_door_gives_up_on_the_row_at_eight_seconds_having_touched_nothing(db):
    _applied(db)
    app = "ottoq_0790_long_beat"
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
def test_0790_the_teardown_runs_under_the_lock_timeout_it_ran_under_before(db, phase):
    _phase(db, phase)
    out = db.val(f"SET lock_timeout = '15s'; SELECT public.ottoq_sim_stop_and_reset('{RUN}', 'operator_stop')")
    assert json.loads(out) == {"released": True, "marked_stopped": True}
    notes = db.json("SELECT jsonb_object_agg(fn, note) FROM public.t_calls "
                    "WHERE fn IN ('ottoq_promote_proposal_candidates', 'ottoq_sim_release_depot')")
    # the rescue step under the caller's 15 s, the release under the 8 s mark_stopped sets, both before and after
    assert notes == {"ottoq_promote_proposal_candidates": "15s", "ottoq_sim_release_depot": "8s"}, notes
    assert db.val("SELECT count(*) FROM public.ottoq_external_proposals WHERE status = 'expired' "
                  "AND disposition_reason = 'run_finalized'") == "3"


# ── §3: the door's mode, against the inserts that reference the run ──

@pytest.mark.parametrize("phase", ["before", "after"])
def test_0790_a_key_check_does_not_wait_for_the_stop_door(db, phase):
    _phase(db, phase)
    app = "ottoq_0790_held_stop"
    p = db.background(f"BEGIN; SELECT public.ottoq_sim_stop_and_reset('{RUN}', 'operator_stop'); "
                      f"SELECT pg_sleep(3); COMMIT;", app)
    db.wait_sleeping(app)
    rc1, err1, took1 = _try(db, DECISION)
    rc2, err2, took2 = _try(db, PROPOSAL)
    p.communicate(timeout=30)
    assert p.returncode == 0
    assert rc1 == 0 and rc2 == 0, (err1, err2)
    assert took1 < 0.8 and took2 < 0.8, (took1, took2)


def _writer_and_door(d):
    """A proposal writer in the live door's order (supersede the car's pending proposal, then insert the new one) holds
    the superseded row; the stop door starts and waits on that row in its dispose; the writer then inserts."""
    old = d.val(f"""INSERT INTO public.ottoq_external_proposals (sim_run_id, entity_id, source, proposal)
                    VALUES ('{RUN}', '{CAR}', 'llm_advisor', '{{"stall_id": "{STALL}"}}') RETURNING proposal_id""")
    w = d.background(f"BEGIN; SET lock_timeout = '15s'; "
                     f"UPDATE public.ottoq_external_proposals SET status = 'superseded', "
                     f"disposition_reason = 'newer_proposal_same_entity', disposed_at = clock_timestamp() "
                     f"WHERE sim_run_id = '{RUN}' AND entity_id = '{CAR}' AND status = 'pending'; "
                     f"SELECT pg_sleep(2); "
                     f"INSERT INTO public.ottoq_external_proposals (sim_run_id, entity_id, source, proposal) "
                     f"VALUES ('{RUN}', '{CAR}', 'llm_advisor', '{{\"stall_id\": \"{STALL_B}\"}}'); COMMIT;", WRITER_APP)
    d.wait_sleeping(WRITER_APP)
    door = d.background(f"SET lock_timeout = '15s'; SELECT public.ottoq_sim_stop_and_reset('{RUN}', 'operator_stop')",
                        DOOR_APP)
    d.wait_locked(DOOR_APP)
    w_out, w_err = w.communicate(timeout=60)
    door_out, door_err = door.communicate(timeout=60)
    rows = d.json(f"""SELECT jsonb_agg(jsonb_build_array(CASE WHEN proposal_id = '{old}' THEN 'old'
                                                             WHEN entity_id = '{CAR}' THEN 'new' ELSE 'other' END,
                                                        status, disposition_reason))
                      FROM public.ottoq_external_proposals""")
    return w.returncode, w_err, door.returncode, door_err, sorted(rows, key=json.dumps)


@pytest.mark.parametrize("phase", ["before", "after"])
def test_0790_a_writer_that_supersedes_and_then_inserts_finishes_beside_the_door_as_before(db, phase):
    _phase(db, phase)
    w_rc, w_err, door_rc, door_err, rows = _writer_and_door(db)
    assert w_rc == 0 and door_rc == 0, (w_err, door_err)
    assert db.val(f"SELECT status FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}'") == "completed"
    # the same rows either way: the old proposal superseded by the writer (the dispose skips it on recheck), the three
    # others expired, and the new one, committed after the dispose read the table, left pending (as it was before 0790)
    assert rows == [["new", "pending", None], ["old", "superseded", "newer_proposal_same_entity"],
                    ["other", "expired", "run_finalized"], ["other", "expired", "run_finalized"],
                    ["other", "expired", "run_finalized"]], rows


def test_0790_the_door_taking_for_update_would_deadlock_with_that_writer(db):
    """Why NO KEY: FOR UPDATE on the door makes the writer's key check wait for the door while the door's dispose waits on
    the writer's superseded row."""
    _applied(db)
    _swap(db, STOP, LOCK_STMT, LOCK_STMT.replace("FOR NO KEY UPDATE;", "FOR UPDATE;"))
    w_rc, w_err, door_rc, door_err, _ = _writer_and_door(db)
    lost = [x for x, rc, err in (("writer", w_rc, w_err), ("door", door_rc, door_err))
            if rc != 0 and "deadlock detected" in err]
    assert len(lost) == 1, (w_err, door_err)


# ── §3: only a running run's row, against the two prior-run removers ──

LOCKS = {
    # the door's early lock under 0790, and the two predicates it does not use (on a throwaway database only)
    "after": None,
    "any_run": "PERFORM 1 FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id FOR NO KEY UPDATE;",   # 0790's first version
    "mark_stopped": ("PERFORM 1 FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id AND status IN ('running','paused') "
                     "FOR NO KEY UPDATE;"),                                                          # mark_stopped's own
}
KEEP = "07240000-0000-0000-0000-00000000ffff"   # the new run a demo start keeps; nothing else is kept
REMOVERS = {
    # the prior-run purge on its own: the run's rows by dynamic SQL, then (once the door waits) the run's row
    "purge": f"BEGIN; SET lock_timeout = '20s'; SELECT public.ottoq_purge_prior_runs('{KEEP}'); COMMIT;",
    # the demo start's order: ottoq_start_demo_run's first statement (live md5 45c9519e, read 2026-10-15 00:16:48 UTC)
    # marks every running and paused run aborted, and its last step is the purge; the hook holds it in between
    "demo_start": (f"BEGIN; SET lock_timeout = '20s'; "
                   f"UPDATE ottoq_sim_runs SET status = 'aborted' WHERE COALESCE(run_by,'') <> 'production_live' "
                   f"AND status IN ('running','paused'); "
                   f"SELECT public.t_hold_for_door(); "
                   f"SELECT public.ottoq_purge_prior_runs('{KEEP}'); COMMIT;"),
}
REMOVER_APP = "ottoq_0790_remover"
# the twin app's resume (edge-functions/otto-twin-control resumeRun: .update({status: 'running', next_tick_due_at})
# .eq('sim_run_id', id).eq('status', 'paused')). The purge has not locked the run, so it goes straight through, and so
# does ottoq_resume_run's UPDATE (live md5 b693dc33), which carries no status predicate at all (G492)
RESUME = (f"UPDATE public.ottoq_sim_runs SET status = 'running', next_tick_due_at = now() "
          f"WHERE sim_run_id = '{RUN}' AND status = 'paused' RETURNING status")


def _prior_run_and_door(d, status, remover):
    """A stop door on a run in `status` arrives while `remover` is between its first write and its next: the remover waits
    (t_hold_for_door) until the door waits on a lock, then goes on. 'resumed' is a run that is paused when the remover
    chooses its runs and is resumed while the remover is at the hook, before the door is called (G491)."""
    d.val(f"UPDATE public.ottoq_sim_runs SET status = '{'paused' if status == 'resumed' else status}' "
          f"WHERE sim_run_id = '{RUN}'")
    d.val(f"UPDATE public.t_decide SET door = '{DOOR_APP}'")
    r = d.background(REMOVERS[remover], REMOVER_APP)
    d.wait_for(f"SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = '{REMOVER_APP}_holding')",
               "the remover to reach the hook")
    if status == "resumed":
        assert d.val(RESUME) == "running"     # chosen while paused, running now: the purge never looks at it again
    door = d.background(f"SET lock_timeout = '15s'; SELECT public.ottoq_sim_stop_and_reset('{RUN}', 'operator_stop')",
                        DOOR_APP)
    r_out, r_err = r.communicate(timeout=60)
    door_out, door_err = door.communicate(timeout=60)
    return r.returncode, r_err, door.returncode, door_out, door_err


# (run status, remover, the door's lock) -> deadlock? Before 0790 the door takes no lock before its dispose.
PRIOR_RUN_CASES = [
    ("completed", "purge", "before", False),
    ("completed", "purge", "after", False),
    ("completed", "purge", "any_run", True),          # the deadlock 0790's first version added (a reviewer's, reproduced)
    ("paused", "purge", "before", False),
    ("paused", "purge", "after", False),
    ("paused", "purge", "mark_stopped", True),        # why not mark_stopped's predicate: the purge takes paused runs
    # G491, OPEN: the purge chooses its runs once and never locks them, so a run it chose while paused and that is
    # resumed before its last statement is deleted while running. Before 0790 the door finishes beside it and marks
    # nothing; after it the door takes the now-running run's row first, and that is a cycle with a lone purge
    ("resumed", "purge", "before", False),
    ("resumed", "purge", "after", True),
    ("running", "demo_start", "before", True),
    ("running", "demo_start", "after", False),        # the demo start takes the run's row first, the beat's order
    ("paused", "demo_start", "before", True),
    ("paused", "demo_start", "after", True),          # left where it was: the two removers take a paused run in
    ("paused", "demo_start", "mark_stopped", False),  # opposite orders, so no door order is safe against both
]


@pytest.mark.parametrize("status,remover,lock,deadlock", PRIOR_RUN_CASES,
                         ids=[f"{s}-{r}-{l}" for s, r, l, _ in PRIOR_RUN_CASES])
def test_0790_the_door_takes_the_row_first_only_on_a_running_run(db, status, remover, lock, deadlock):
    if lock != "before":
        _applied(db)
    if LOCKS.get(lock):
        _swap(db, STOP, LOCK_STMT, LOCKS[lock])
    r_rc, r_err, door_rc, door_out, door_err = _prior_run_and_door(db, status, remover)
    lost = [x for x, rc, err in (("remover", r_rc, r_err), ("door", door_rc, door_err)) if rc != 0]
    if deadlock:
        # one side gets 40P01, and which one is PostgreSQL's (13.3.4); the other commits
        assert len(lost) == 1, (r_err, door_err)
        assert "deadlock detected" in (r_err if lost == ["remover"] else door_err), (r_err, door_err)
    else:
        assert lost == [], (r_err, door_err)
        # the remover took the run, so the door marked nothing (and the release is the stub's); for 'resumed' that is a
        # running run deleted (G491)
        assert json.loads(door_out.splitlines()[-1]) == {"released": True, "marked_stopped": False}
        assert db.val("SELECT count(*) FROM public.ottoq_sim_runs") == "0"


# ── G490: the tick's FOR UPDATE is unchanged, and the reason ──

@pytest.mark.parametrize("phase", ["before", "after"])
@pytest.mark.parametrize("holder", list(HOLDERS))
def test_0790_a_key_check_still_waits_for_the_tick_and_the_fault_doors(db, holder, phase):
    _phase(db, phase)
    p = _hold(db, holder)
    rc, err, took = _try(db, DECISION)
    p.communicate(timeout=30)
    assert p.returncode == 0
    # the agent's decision insert waits on the run's row, in the key check, until its lock_timeout runs out (G490)
    assert rc != 0 and "canceling statement due to lock timeout" in err, err
    assert 'relation "ottoq_sim_runs"' in err and "FOR KEY SHARE" in err, err
    assert took >= 0.9


KERNEL_STALL = "enacted_action ->> 'stall_id'"
PROPOSAL_STALL = "proposal ->> 'stall_id'"


def _ab(col):
    """A stall as the mid-beat test names it: 'A', the one P_old named and the kernel took, or 'B', the resubmission's."""
    return f"CASE {col} WHEN '{STALL}' THEN 'A' WHEN '{STALL_B}' THEN 'B' END"


def _mid_beat(d, batch_deadlock_timeout=None, beat_deadlock_timeout=None):
    """The live metronome's beat enacts the car from its pending proposal P_old (stall A, llm_advisor); a proposer's
    batch, through the live ottoq_proposer_submit_batch, then resubmits P_new (stall B) for the same car while the beat
    is in flight; then the beat's A3 runs. A constructed interleaving (0790 §1 (b)). Each session's deadlock_timeout is
    the server's (1 s, as live) unless one is given."""
    d.val(f"""INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id,
                                                           source, proposal, status, expires_at)
              VALUES ('{RUN}', '{DEPOT}', 'stall_assignment', 'vehicle', '{CAR}', 'llm_advisor',
                      '{{"stall_id": "{STALL}"}}', 'pending', now() + interval '1 hour')""")
    d.val(f"UPDATE public.t_decide SET agent = '{AGENT_APP}'")
    m = d.background("CALL public.ottoq_demo_metronome(4)", "ottoq_0790_metronome", beat_deadlock_timeout)
    d.wait_for("SELECT EXISTS (SELECT 1 FROM pg_stat_activity "
               "WHERE application_name = 'ottoq_0790_metronome_in_decide')", "the metronome to enact")
    rows = json.dumps([{"action_context": "stall_assignment", "entity_type": "vehicle", "entity_id": CAR,
                        "proposal": {"stall_id": STALL_B}}])
    a = d.background(f"SELECT public.ottoq_proposer_submit_batch('{RUN}', '{DEPOT}', 'llm_advisor', '{rows}'::jsonb, "
                     f"'{{}}'::jsonb, 60)", AGENT_APP, batch_deadlock_timeout)
    a_out, a_err = a.communicate(timeout=60)
    m_out, m_err = m.communicate(timeout=60)
    # both sessions end cleanly either way: the batch catches its own error, and the metronome records a failed step
    assert a.returncode == 0 and m.returncode == 0, (a_err, m_err)
    return {
        "batch": json.loads(a_out.splitlines()[-1]),
        "failures": d.json("SELECT COALESCE(jsonb_agg(jsonb_build_array(phase, message, sqlstate) ORDER BY seq), '[]') "
                           "FROM public.t_tick_failures"),
        "m_err": m_err,
        "kernel": d.json(f"SELECT COALESCE(jsonb_agg({_ab(KERNEL_STALL)}), '[]') FROM public.ottoq_decisions "
                         f"WHERE entity_id = '{CAR}' AND outcome_status = 'enacted'"),
        "enacted": d.val("SELECT count(*) FROM public.ottoq_decisions WHERE outcome_status = 'enacted'"),
        "ticks": d.val(f"SELECT tick_count FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}'"),
        "ledger": d.json(f"SELECT COALESCE(jsonb_agg(jsonb_build_array({_ab('stall_id::text')}, status, disposition_reason) "
                         f"ORDER BY disposition_id), '[]') FROM public.ottoq_proposal_disposition_ledger "
                         f"WHERE entity_id = '{CAR}'"),
        "proposals": d.json(f"SELECT COALESCE(jsonb_agg(jsonb_build_array({_ab(PROPOSAL_STALL)}, status, disposition_reason) "
                            f"ORDER BY created_at), '[]') FROM public.ottoq_external_proposals WHERE entity_id = '{CAR}'"),
    }


# which side's deadlock check runs first after the cycle closes: (the batch's deadlock_timeout, the beat's). "either" is
# the server's 1 s on both, as live (read 2026-10-14 23:59:36 UTC), where the batch, which begins waiting first, usually
# looks first and loses, and a beat whose wait begins over a second later turns it round. "batch" and "beat" force each
# side, with room to spare: the side given the shorter timeout looks first, after the other is already waiting. (At
# 17:34:06 UTC on live the batch, forward_lex's, looked first and lost; that deadlock's beat-side edge is not known, so
# it is of this class, not this interleaving: 0790 §1 (b).)
VICTIMS = {"either": (None, None), "batch": ("2s", "5s"), "beat": ("5s", None)}


@pytest.mark.parametrize("victim", list(VICTIMS))
@pytest.mark.parametrize("phase", ["before", "after"])
def test_0790_with_the_ticks_for_update_a_mid_beat_resubmission_deadlocks_and_the_ledger_stays_right(db, phase, victim):
    _phase(db, phase)
    r = _mid_beat(db, *VICTIMS[victim])
    # the constructed cycle: the batch's insert waits on the run's row and A3 waits on the row the batch superseded
    batch_lost = r["batch"]["status"] == "error" and (r["batch"]["error"] or "").startswith("40P01")
    beat_lost = r["failures"] == [["decide", "deadlock detected", "40P01"]]
    assert batch_lost != beat_lost, r                       # exactly one side is aborted
    assert victim == "either" or (victim == "batch") == batch_lost, r
    assert r["ticks"] == "2"                                 # either way the beat's world step commits
    # the invariant: the ledger records no proposal the kernel did not take
    assert ["B", "enacted", "enacted_by_kernel"] not in r["ledger"], r
    if batch_lost:
        # its one sub-transaction rolls back, so nothing it wrote stands, and the beat's enactments stand
        assert r["failures"] == [] and r["batch"]["submitted"] == 0, r
        assert r["kernel"] == ["A"] and r["enacted"] == "4", r
        assert r["ledger"] == [["A", "enacted", "enacted_by_kernel"]], r
        assert r["proposals"] == [["A", "enacted", "enacted_by_kernel"]], r
    else:
        # the beat's decide rolls back with every enactment of that tick; the batch commits after the beat, and the new
        # proposal waits for the next beat
        assert "metronome decide" in r["m_err"] and "deadlock detected" in r["m_err"], r["m_err"]
        assert r["batch"]["status"] == "submitted" and r["batch"]["submitted"] == 1, r
        assert r["kernel"] == [] and r["enacted"] == "0", r
        assert r["ledger"] == [["A", "superseded", "newer_proposal_same_entity"]], r
        assert r["proposals"] == [["A", "superseded", "newer_proposal_same_entity"], ["B", "pending", None]], r


def test_0790_the_withdrawn_for_no_key_update_on_the_tick_mislabels_the_evidence(db):
    """The first draft's half, applied to this throwaway database only: the batch commits mid-beat, and A3 marks the
    proposal the kernel never evaluated as the one it enacted."""
    _applied(db)
    _swap(db, "public.ottoq_sim_advance_tick_world(uuid)",
          "WHERE sim_run_id=p_sim_run_id FOR UPDATE;", "WHERE sim_run_id=p_sim_run_id FOR NO KEY UPDATE;")
    r = _mid_beat(db)
    assert r["failures"] == [], r["m_err"]                   # no deadlock: nothing waits
    assert r["batch"]["status"] == "submitted" and r["batch"]["error"] is None, r["batch"]
    assert r["kernel"] == ["A"]
    assert r["ledger"] == [["A", "superseded", "newer_proposal_same_entity"], ["B", "enacted", "enacted_by_kernel"]], \
        r["ledger"]


# ── FALSE/FALSE ──

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
  'ledger', (SELECT jsonb_agg(jsonb_build_array(x.status, x.disposition_reason) ORDER BY x.status, x.disposition_reason)
               FROM public.ottoq_proposal_disposition_ledger x),
  'tick_log', (SELECT jsonb_agg(jsonb_build_array(x.tick_seq, x.sim_clock_before, x.sim_clock_after, x.sim_advance_s)
                                ORDER BY x.tick_seq) FROM public.ottoq_tick_clock_log x),
  'wear', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.tick_seq) FROM public.ottoq_wear_tick_status x))
"""


def test_0790_one_session_gets_the_same_rows_with_and_without_it():
    """The lineage's FALSE/FALSE: a certified arm runs in one transaction, where the added lock waits on nothing and
    reads nothing. The same script (two world steps, the cockpit's fault injection, a third world step, the stop) in one
    session, before and after 0790."""
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
        assert b["proposals"] == [["expired", "run_finalized"]] * 3
    finally:
        _drop(before)
        _drop(after)


# ── refusals ──

def test_0790_refuses_a_second_apply_and_a_pair_in_flight(db):
    db.val("UPDATE public.t_inflight SET n = 1")
    rc, err = _apply(db)
    assert rc != 0 and "0790 P0" in err, err
    db.val("UPDATE public.t_inflight SET n = 0")
    _applied(db)
    rc, err = _apply(db)
    assert rc != 0 and "0790 P1: public.ottoq_sim_stop_and_reset(uuid,text) is not the definition" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0790%'") == "1"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0790_pre'") == "1"


def _unchanged(d):
    for sig, md5 in LIVE.items():
        assert d.val(f"SELECT md5(pg_get_functiondef('{sig}'::regprocedure))") == md5, sig
    assert d.val("SELECT count(*) FROM public.ottoq_cert_lineage") == "0"
    assert d.val("SELECT count(*) FROM public.ottoq_schema_snapshots") == "0"


def test_0790_refuses_when_an_update_assigns_a_key_column(db):
    db.val("""CREATE FUNCTION public.t_renumber(p uuid) RETURNS void LANGUAGE plpgsql AS $s$
              BEGIN UPDATE ottoq_sim_runs SET payload = '{}', sim_run_seq = 7 WHERE sim_run_id = p; END $s$""")
    rc, err = _apply(db)
    assert rc != 0 and "0790 P2: 1 UPDATE(s) of ottoq_sim_runs assign a key column (public.t_renumber)" in err, err
    _unchanged(db)


def test_0790_refuses_when_a_proposal_writer_also_takes_the_runs_row(db):
    db.val("""CREATE FUNCTION public.t_propose_then_touch(p uuid) RETURNS void LANGUAGE plpgsql AS $s$
              BEGIN
                UPDATE public.ottoq_external_proposals SET status = 'superseded' WHERE sim_run_id = p AND status = 'pending';
                UPDATE ottoq_sim_runs SET notes = 'x' WHERE sim_run_id = p;
              END $s$""")
    rc, err = _apply(db)
    assert rc != 0 and ("0790 P2: public.t_propose_then_touch write(s) the run's proposals and also update(s) or "
                        "lock(s) ottoq_sim_runs") in err, err
    _unchanged(db)


def test_0790_refuses_when_the_prior_run_purge_would_choose_a_running_run(db):
    """The purge writes a run's rows and then deletes the run's row, the reverse of the door's order on a running run, so
    the door's early lock needs the purge never to choose a running run. That is not sufficient: the purge does not lock
    the runs it chose, and a run resumed after the choice still meets the door in the reverse order (G491, pinned by
    the 'resumed' cases above)."""
    db.val("""DO $x$ DECLARE v text := pg_get_functiondef('public.ottoq_purge_prior_runs(uuid)'::regprocedure);
              BEGIN
                IF strpos(v, E'\\n     AND status <> ''running'';') = 0 THEN RAISE EXCEPTION 'anchor not found'; END IF;
                EXECUTE replace(v, E'\\n     AND status <> ''running'';', ';');
              END $x$""")
    rc, err = _apply(db)
    assert rc != 0 and "0790 P2: the prior-run purge no longer chooses only runs that are not running" in err, err
    _unchanged(db)


def test_0790_refuses_when_the_metronome_commits_between_its_world_and_decide_steps(db):
    db.val("""DO $x$ BEGIN
                EXECUTE replace(pg_get_functiondef('public.ottoq_demo_metronome(integer)'::regprocedure),
                                '      IF v_advanced IS NOT NULL THEN', '      COMMIT;' || chr(10) || '      IF v_advanced IS NOT NULL THEN');
              END $x$""")
    rc, err = _apply(db)
    assert rc != 0 and "0790 P2: the metronome no longer runs the world step and then the decide step" in err, err
    for sig, md5 in LIVE.items():
        if sig != "public.ottoq_demo_metronome(integer)":
            assert db.val(f"SELECT md5(pg_get_functiondef('{sig}'::regprocedure))") == md5, sig
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage") == "0"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots") == "0"


def test_0790_v1_refuses_a_patch_that_changes_more_than_it_says(db):
    src = open(M0790, encoding="utf-8").read()
    anchor = ("FOR NO KEY UPDATE;\n  PERFORM set_config('lock_timeout', v_lock_prev, true);\n"
              "  PERFORM public.ottoq_dispose_external_proposals(p_sim_run_id, NULL, NULL, true);\n$n$;")
    assert src.count(anchor) == 1
    cut = src.replace(anchor, anchor.replace("FOR NO KEY UPDATE;", "FOR NO KEY UPDATE SKIP LOCKED;"))
    with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False) as f:
        f.write(cut)
    try:
        rc, err = _apply(db, f.name)
    finally:
        os.unlink(f.name)
    assert rc != 0 and "0790 V1 FAILED: public.ottoq_sim_stop_and_reset" in err, err
    _unchanged(db)
