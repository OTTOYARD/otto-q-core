"""db/migrations/0766, EXECUTED: the agent's board reads the arrival forecast without writing it, so the agent's read
takes no lock on the run's row and a world step stops waiting for it.

WHY THIS EXISTS. On run 78c0624c (2026-10-24, busy_day, the twin depot) the world steps that began within 9 s of an agent
pass took a mean 5,693 ms against 1,504 for the rest. Sampled on live, the metronome waited on the run's row behind
PostgREST running public.ottoq_agent_board: the board calls public.ottoq_predict_arrivals, which records an
'ottoq.arrival_forecast' event whose key check (fk_ottoq_events_sim_run) holds the run's row FOR KEY SHARE until the
board's transaction ends, about 6.6 s later, and the world step's first statement takes that row FOR UPDATE (G490: that
lock stays). Executed here, on the scratch PostgreSQL, over tests/fixtures/agent_scouts_wake_stub.sql with 0703, 0704 and
0709 applied (which leave the board byte for byte the live one) and tests/fixtures/arrival_forecast_stub.sql (the live
ottoq_predict_arrivals byte for byte, and an event writer whose insert takes the run's row by its key, as live's does):
  - before 0766, a board read held open with a car due home makes a world step's FOR UPDATE on the run's row wait out
    its lock timeout; after it, the same read takes the row at once, writes no event and takes no transaction id;
  - the board's value is byte for byte what it was;
  - ottoq_predict_arrivals returns and records exactly what it did, on a fleet that spans every SoC band, target and
    inlet case and every dispatch window edge, and the new read equals it at every horizon;
  - the read is not the browser's: neither anon nor authenticated may run it;
  - 0766 applies as declared, with Windows line endings too, and refuses a second apply, a definition it did not read and
    a database without 0709.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import time
import uuid

import pytest

import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
SCOUTS_STUB = os.path.join(ROOT, "tests", "fixtures", "agent_scouts_wake_stub.sql")
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "arrival_forecast_stub.sql")
PRIOR = [os.path.join(ROOT, "db", "migrations", f) for f in (
    "0703_every_agent_pass_keeps_what_it_saw_and_what_it_changed.sql",
    "0704_every_car_has_a_deterministic_scout_and_the_agent_reads_what_they_find.sql",
    "0709_the_agents_return_wave_counts_this_runs_cars_not_every_run_ever.sql")]
M0766 = os.path.join(ROOT, "db", "migrations", "0766_the_agents_board_reads_the_arrival_forecast_without_writing_it.sql")
L0766 = "0766_the_agents_board_reads_the_arrival_forecast_without_writing_it"
L0709 = "0709_the_agents_return_wave_counts_this_runs_cars_not_every_run_ever"
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "a0000000-0000-0000-0000-000000000766"
OP = "33333333-3333-3333-3333-333333333766"
T = "2026-10-23 14:00:00+00"
BOARD = "public.ottoq_agent_board(uuid)"
PREDICT = "public.ottoq_predict_arrivals(uuid,timestamp with time zone,uuid,integer)"
FORECAST = "public.ottoq_arrival_forecast(uuid,timestamp with time zone,uuid,integer)"
# the live definitions, read 2026-10-24 (pg_get_functiondef md5), and the bodies 0766 leaves (prosrc md5, V7)
LIVE = {BOARD: "d130f89abfff0e93aac5416b3f4d98aa", PREDICT: "b9e952538e34007310156ccf7f6979f4"}
AFTER = {BOARD: "cc155a31209fd8e89260028d24a9715f", PREDICT: "535c1600093266e53b2e743ad3667073",
         FORECAST: "70317860cba9f347bac7571a53ba11ac"}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0766-{name}"))


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


class Db(base.Db):
    def background(self, sql, app):
        env = {**os.environ, "PGAPPNAME": app}
        return subprocess.Popen(["psql", *base._conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1",
                                 "-c", sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)

    def wait_sleeping(self, app, timeout=15.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.val(f"""SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE datname = current_database()
                                             AND application_name = '{app}' AND wait_event = 'PgSleep')""") == "t":
                return
            time.sleep(0.05)
        raise AssertionError(f"timed out waiting for {app} to hold its transaction open")


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_brw_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = Db(name)
    try:
        for path in (SCOUTS_STUB, *PRIOR, FIXTURE):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        _world(d)
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_brw_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


# each car: (name, soc, target_soc, inlet_max_kw, battery_kwh, dispatch status, minutes until it is due home)
FLEET = [
    ("low", 22, None, 104, 90, "returning", 12),       # under 35: 0.90 of a 104 kW inlet
    ("mid", 41, None, None, None, "active", 25),       # 35-55: 0.80 of the 150 kW default; the 75 kWh default pack
    ("upper", 63, 80, 250, 78, "returning", 40),       # 55-75 against its own target of 80
    ("top", 88, None, 400, 100, "active", 55),         # 75 and over: 0.25, the inlet capped at 250
    ("full", 99.5, None, 250, 75, "returning", 20),    # within 1 of its target: due home, no charge wanted
    ("edge_back", 30, None, 150, 75, "returning", -4), # due 4 minutes ago: still counted (the window opens 5 back)
    ("too_late", 30, None, 150, 75, "returning", -6),  # due 6 minutes ago: not counted
    ("far", 30, None, 150, 75, "active", 90),          # beyond 60 minutes, inside 120
    ("done", 30, None, 150, 75, "completed", 10),      # a dispatch that is over
]


def _world(d):
    d.val(f"INSERT INTO fleet_operators VALUES ('{OP}', 'Op')")
    d.val(f"""INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_current, sim_clock_start,
                                          started_at, last_tick_at, run_by, scenario_code, random_seed, policy)
              VALUES ('{RUN}', '{DEPOT}', 'running', 120, '{T}', '2026-10-23 13:00:00+00', now(), now(),
                      'operator_demo', 'busy_day', 42, 'otto_q')""")
    for name, soc, target, inlet, pack, status, due in FLEET:
        d.val(f"""INSERT INTO vehicles (id, fleet_operator_id, home_depot_id, display_name, current_soc, current_state,
                                        target_soc, inlet_max_kw, battery_capacity_kwh)
                  VALUES ('{_id(name)}', '{OP}', '{DEPOT}', '{name}', {soc}, 'en_route_to_depot',
                          {target if target is not None else 'NULL'}, {inlet if inlet is not None else 'NULL'},
                          {pack if pack is not None else 'NULL'})""")
        d.val(f"""INSERT INTO ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, status, scheduled_return_at)
                  VALUES ('{_id(name)}', '{RUN}', '{T}'::timestamptz - interval '2 hours', '{status}',
                          '{T}'::timestamptz + interval '{due} minutes')""")


def _apply(d, path=M0766):
    rc, err = d.file(path)
    assert rc == 0, f"0766 did not apply: {err}"


def _def_md5(d, fn):
    return d.val(f"SELECT md5(pg_get_functiondef('{fn}'::regprocedure))")


def _src_md5(d, fn):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')")


def _events(d):
    return int(d.val("SELECT count(*) FROM public.ottoq_events"))


def _predict(d, horizon=60):
    return d.val(f"SELECT row(p.*)::text FROM public.ottoq_predict_arrivals('{DEPOT}', '{T}', '{RUN}', {horizon}) p")


def _forecast(d, horizon=60):
    return d.val(f"SELECT row(f.*)::text FROM public.ottoq_arrival_forecast('{DEPOT}', '{T}', '{RUN}', {horizon}) f")


def _last_payload(d):
    return d.val("SELECT payload::text FROM public.ottoq_events ORDER BY event_seq DESC LIMIT 1")


def _world_step_lock(d):
    """The world step's first statement, under a 1 s lock timeout: (returncode, stderr, seconds)."""
    t0 = time.time()
    rc, _, err = d.run(f"SET lock_timeout = '1s'; "
                       f"SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}' FOR UPDATE")
    return rc, err, time.time() - t0


def _hold_a_board_read(d, app):
    p = d.background(f"BEGIN; SELECT public.ottoq_agent_board('{RUN}') IS NOT NULL; SELECT pg_sleep(3); COMMIT;", app)
    d.wait_sleeping(app)
    return p


# ── the premises ─────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_premises_are_the_live_definitions(db):
    for fn, m in LIVE.items():
        assert _def_md5(db, fn) == m, fn


def test_it_applies_as_declared(db):
    _apply(db)
    for fn, m in AFTER.items():
        assert _src_md5(db, fn) == m, fn
    assert db.val(f"""SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage
                      WHERE name = '{L0766}'""") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0766_pre'") == "2"
    assert db.val(f"SELECT proacl::text FROM pg_proc WHERE oid = '{FORECAST}'::regprocedure") == \
        "{postgres=X/postgres,service_role=X/postgres}"
    assert db.val(f"SELECT provolatile FROM pg_proc WHERE oid = '{FORECAST}'::regprocedure") == "s"


def test_a_paste_with_windows_line_endings_applies_to_the_same_bodies(db, tmp_path):
    with open(M0766, "rb") as f:
        text = f.read()
    assert b"\r" not in text
    crlf = tmp_path / "0766_crlf.sql"
    crlf.write_bytes(text.replace(b"\n", b"\r\n"))
    rc, err = db.file(str(crlf))
    assert rc == 0, f"0766 with CRLF did not apply: {err}"
    for fn in (BOARD, PREDICT):
        assert _src_md5(db, fn) == AFTER[fn], fn


# ── the lock ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_before_0766_a_board_read_holds_the_runs_row_and_a_world_step_waits(db):
    p = _hold_a_board_read(db, "ottoq_0766_board_before")
    rc, err, took = _world_step_lock(db)
    p.communicate(timeout=30)
    assert p.returncode == 0
    assert rc != 0 and "canceling statement due to lock timeout" in err, err
    assert 'relation "ottoq_sim_runs"' in err, err
    assert took >= 0.9
    assert _events(db) == 1   # the board's arrival forecast, written by a read


def test_after_0766_the_same_read_holds_nothing_and_the_world_step_takes_the_row_at_once(db):
    _apply(db)
    p = _hold_a_board_read(db, "ottoq_0766_board_after")
    rc, err, took = _world_step_lock(db)
    p.communicate(timeout=30)
    assert p.returncode == 0
    assert rc == 0, err
    assert took < 0.9
    assert _events(db) == 0


def test_after_0766_the_board_takes_no_transaction_id(db):
    _apply(db)
    out = db.val(f"BEGIN; SELECT public.ottoq_agent_board('{RUN}') IS NOT NULL; "
                 f"SELECT coalesce(txid_current_if_assigned()::text, 'none'); COMMIT;")
    assert out == "none"


# ── nothing else moves ───────────────────────────────────────────────────────────────────────────────────────────────

def test_the_boards_value_is_byte_for_byte_what_it_was(db):
    before = db.val(f"SELECT public.ottoq_agent_board('{RUN}')::text")
    _apply(db)
    after = db.val(f"SELECT public.ottoq_agent_board('{RUN}')::text")
    assert before == after
    assert json.loads(after)["energy"]["forecast_charge_kw_60m"] > 0


@pytest.mark.parametrize("horizon", [30, 60, 120])
def test_predict_arrivals_returns_and_records_exactly_what_it_did(db, horizon):
    rows_before, payload_before = _predict(db, horizon), _last_payload(db)
    _apply(db)
    rows_after, payload_after = _predict(db, horizon), _last_payload(db)
    assert rows_before == rows_after
    assert payload_before == payload_after
    assert _events(db) == 2


@pytest.mark.parametrize("horizon", [30, 60, 120])
def test_the_read_equals_predict_arrivals_and_writes_nothing(db, horizon):
    _apply(db)
    n = _events(db)
    assert _forecast(db, horizon) == _predict(db, horizon)
    assert _events(db) == n + 1   # the one event is predict_arrivals'
    db.val(f"SELECT count(*) FROM public.ottoq_arrival_forecast('{DEPOT}', '{T}', '{RUN}', {horizon})")
    assert _events(db) == n + 1


def test_the_fleet_spans_the_cases_it_names(db):
    """The world is what the parametrised tests need it to be: every band, the defaults, the window's edges."""
    _apply(db)
    assert _forecast(db, 60) == "(6,5,536,193)"
    assert _forecast(db, 120) == "(7,6,671,245)"


@pytest.mark.parametrize("role", ["anon", "authenticated"])
def test_the_read_is_not_the_browsers(db, role):
    _apply(db)
    rc, _, err = db.run(f"SET ROLE {role}; SELECT * FROM public.ottoq_arrival_forecast('{DEPOT}', '{T}', '{RUN}', 60)")
    assert rc != 0 and "permission denied for function ottoq_arrival_forecast" in err, err


# ── refusals ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_it_refuses_a_second_apply(db):
    _apply(db)
    rc, err = db.file(M0766)
    assert rc != 0 and "0766 P1" in err   # the board is no longer the definition it was written against


@pytest.mark.parametrize("fn", [BOARD, PREDICT])
def test_it_refuses_a_definition_it_did_not_read(db, fn):
    db.val(f"""DO $x$ BEGIN EXECUTE replace(pg_get_functiondef('{fn}'::regprocedure), 'BEGIN', E'BEGIN\\n  -- edited');
               END $x$""")
    rc, err = db.file(M0766)
    assert rc != 0 and "0766 P1: a function this file patches" in err


def test_it_refuses_a_database_without_0709(db):
    db.val(f"DELETE FROM public.ottoq_cert_lineage WHERE name = '{L0709}'")
    rc, err = db.file(M0766)
    assert rc != 0 and "0709 is not classified" in err
