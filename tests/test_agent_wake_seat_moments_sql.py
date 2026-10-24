"""db/migrations/0769, EXECUTED: the agent's wake gate also wakes it when a charger is free with a car waiting, or a car
in the line's head has a dispatch due time.

WHY THIS EXISTS. On run 78c0624c (2026-10-24, busy_day, the twin depot) the kernel's check took 8 of the agent's 131
charge orders, and those 8 came when a mean 4.13 chargers were free and 3.1 cars of the line's head had a due time; the 81
it recorded as the kernel's own order came at 0.28 and 0.6. Replayed on 14 other runs' recorded boards, waking on those two
moments as well caught 16 of the 22 taken orders with 49.3% of the model's tokens, against 6 for the gate as it was.
Executed here over tests/fixtures/agent_scouts_wake_stub.sql with 0703, 0704, 0705, 0710 and 0711 applied, which leave
public.ottoq_agent_wake byte for byte the live one (prosrc md5 3ce4f3f5, asserted), and the columns the new counts read
added as live has them:
  - a free charger wakes the agent only with a car waiting, and a charger is free exactly as the agent's board counts one
    (a booking covering the moment, a live reservation, a stale heartbeat, a fault or a car on the stall each make it not
    free);
  - a car with a dispatch due time wakes it only from the kernel's first 24, only on this run's open visit, and only on
    the car's newest such visit;
  - in shadow the gate still wakes on every pass, and the record now says why it would;
  - nothing it did before changes: without the two moments it wakes and sleeps where 0711 did;
  - 0769 applies as declared, with Windows line endings too, and refuses a second apply, a body it did not read and a
    database without 0711.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import tempfile

import pytest

import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)
import test_agent_scouts_wake_sql as w  # noqa: E402  (the stub engine and its helpers)
from test_agent_scouts_wake_sql import db  # noqa: F401,E402  (the fixture: a fresh database with the stub loaded)

ROOT = base.ROOT
M0769 = os.path.join(ROOT, "db", "migrations", "0769_the_agent_wakes_when_a_charger_is_free_or_a_car_in_line_is_due.sql")
L0769 = "0769_the_agent_wakes_when_a_charger_is_free_or_a_car_in_line_is_due"
L0711 = "0711_the_wake_gate_wakes_on_a_change_that_matters_not_on_every_wobble"
WAKE = "public.ottoq_agent_wake(uuid)"
LIVE = "3ce4f3f5bc2070ad5778ad1b5fb002b8"        # live's prosrc, read 2026-10-24 04:55 UTC
AFTER = "353f108cb90369892c18a72537d2619b"                         # the body 0769 leaves (V3)
RUN, T, DEPOT, _id = w.RUN, w.T, w.DEPOT, w._id

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

# the columns the two counts read, as live has them (information_schema, read 2026-10-24)
LIVE_COLUMNS = """
ALTER TABLE public.stalls ADD COLUMN reservation_expires_at timestamptz;
ALTER TABLE public.ottoq_ocpp_chargers ADD COLUMN last_heartbeat_at timestamptz;
ALTER TABLE public.ottoq_visit_needs ADD COLUMN dispatch_due_at timestamptz, ADD COLUMN visit_key text;
CREATE TABLE public.ottoq_stall_bookings (booking_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stall_id uuid,
  sim_run_id uuid, vehicle_id uuid, state text, during tstzrange);
"""


def _md5(d):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = '{WAKE}'::regprocedure")


def _ready(d, apply_0769=True):
    """The stub world (two open chargers, eight cars at the gate, no line yet), the live gate, the live columns."""
    w._world(d)
    w._apply(d, "0703", "0704", "0705", "0710", "0711")
    assert _md5(d) == LIVE
    for stmt in filter(None, (s.strip() for s in LIVE_COLUMNS.split(";"))):
        d.val(stmt)
    d.val(f"UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = '{T}'::timestamptz - interval '30 seconds'")
    if apply_0769:
        rc, err = d.file(M0769)
        assert rc == 0, f"0769 did not apply: {err}"


def _gate_on(d):
    d.val(f"INSERT INTO ottoq_policy_params VALUES ('run', '{RUN}', 'agent_wake_enabled', 1, 'test', now())")


def _line(d, *cars):
    d.val(f"DELETE FROM stub_kernel_line WHERE sim_run_id = '{RUN}'")
    for k, car in enumerate(cars):
        d.val(f"INSERT INTO stub_kernel_line VALUES ('{RUN}', '{_id(car)}', {k + 1}, 5, 50)")


def _visit(d, car, due=None, status="open", run=RUN, created="2026-10-13 14:00:00+00", key="v1"):
    due_sql = f"'{due}'" if due else "NULL"
    d.val(f"""INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, status, created_at, dispatch_due_at,
                                            visit_key)
              VALUES ('{_id(car)}', '{run}', '{DEPOT}', '{status}', '{created}', {due_sql}, '{key}')""")


def _settle(d):
    """A consult on the present state, so only what changes after it can wake the agent."""
    fp = w._wake(d)["fingerprint"]
    w._consult(d, f"k{d.val('SELECT count(*) FROM ottoq_agent_pass_evidence')}", fp)
    return fp


# ── as declared ─────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0769_applies_and_its_assertions_pass(db):
    _ready(db)
    assert _md5(db) == AFTER
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM ottoq_cert_lineage WHERE name = '{L0769}'") \
        == "falsefalse"
    assert db.val("SELECT count(*) FROM ottoq_schema_snapshots WHERE label = '0769_pre'") == "1"
    # still the definer it was, on the same path, read by no one it was not read by
    assert db.val(f"SELECT prosecdef::text || array_to_string(proconfig, ',') FROM pg_proc WHERE oid = '{WAKE}'::regprocedure") \
        == "truesearch_path=twin, ottoq, public, extensions"


def test_0769_applies_from_a_windows_paste_to_the_same_body(db):
    _ready(db, apply_0769=False)
    with open(M0769, encoding="utf-8") as f:
        text = f.read().replace("\n", "\r\n")
    fd, path = tempfile.mkstemp(suffix="_0769_crlf.sql")
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    try:
        rc, err = db.file(path)
    finally:
        os.remove(path)
    assert rc == 0, err
    assert _md5(db) == AFTER


def test_0769_refuses_a_second_apply_a_body_it_did_not_read_and_a_database_without_0711(db):
    _ready(db)
    rc, err = db.file(M0769)
    assert rc != 0 and "0769 P1" in err          # the body is no longer the one it reads
    db.val(f"DELETE FROM ottoq_cert_lineage WHERE name = '{L0769}'")
    db.val(f"""DO $x$ BEGIN EXECUTE (SELECT definition FROM ottoq_schema_snapshots WHERE label = '0769_pre'); END $x$""")
    assert _md5(db) == LIVE                      # the rollback in the header puts the pre-image back
    db.val(f"INSERT INTO ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at) VALUES ('{L0769}', false, false, 'x', now())")
    rc, err = db.file(M0769)
    assert rc != 0 and "0769 P2" in err
    db.val(f"DELETE FROM ottoq_cert_lineage WHERE name IN ('{L0769}', '{L0711}')")
    rc, err = db.file(M0769)
    assert rc != 0 and "0769 P1" in err and "0711" in err


# ── a free charger ──────────────────────────────────────────────────────────────────────────────────────────────────

def test_0769_a_free_charger_wakes_the_agent_only_with_a_car_waiting(db):
    _ready(db)
    _gate_on(db)
    fp = _settle(db)
    assert fp["chargers_free"] == 2 and fp["due_in_line"] == 0, fp
    assert w._wake(db)["wake"] is False                      # two free chargers, nobody waiting: no decision to make
    _line(db, "A")
    r = w._wake(db)
    assert r["wake"] is True and r["reasons"] == ["charger_free"], r
    # a level, not an onset: the next pass with the same free charger and the same car waiting wakes it again
    w._consult(db, "k-next", r["fingerprint"])
    assert w._wake(db)["reasons"] == ["charger_free"]


@pytest.mark.parametrize("case", ["booking", "reservation", "stale_heartbeat", "faulted", "occupied"])
def test_0769_a_charger_is_free_exactly_as_the_board_counts_one(db, case):
    _ready(db)
    _gate_on(db)
    _settle(db)
    _line(db, "A")
    for s in ("F1", "L1"):
        if case == "booking":
            db.val(f"""INSERT INTO ottoq_stall_bookings (stall_id, sim_run_id, vehicle_id, state, during)
                       VALUES ('{_id(s)}', '{RUN}', '{_id('B')}', 'held',
                               tstzrange('{T}'::timestamptz - interval '1 minute', '{T}'::timestamptz + interval '40 minutes'))""")
        elif case == "reservation":
            db.val(f"""UPDATE stalls SET reserved_by = '{_id('B')}',
                                         reservation_expires_at = '{T}'::timestamptz + interval '5 minutes' WHERE id = '{_id(s)}'""")
        elif case == "stale_heartbeat":
            db.val(f"""UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = '{T}'::timestamptz - interval '91 seconds'
                        WHERE charger_id = '{_id(s)}'""")
        elif case == "faulted":
            db.val(f"UPDATE ottoq_ocpp_chargers SET station_state = 'Unavailable' WHERE charger_id = '{_id(s)}'")
        else:
            db.val(f"UPDATE stalls SET current_vehicle_id = '{_id('C')}' WHERE id = '{_id(s)}'")
    r = w._wake(db)
    assert r["fingerprint"]["chargers_free"] == 0 and "charger_free" not in r["reasons"], r


def test_0769_a_booking_that_ended_or_belongs_to_another_run_leaves_the_charger_free(db):
    _ready(db)
    _gate_on(db)
    _settle(db)
    _line(db, "A")
    db.val(f"""INSERT INTO ottoq_stall_bookings (stall_id, sim_run_id, vehicle_id, state, during) VALUES
               ('{_id('F1')}', '{RUN}', '{_id('B')}', 'done',
                tstzrange('{T}'::timestamptz - interval '50 minutes', '{T}'::timestamptz - interval '1 minute')),
               ('{_id('F1')}', gen_random_uuid(), '{_id('B')}', 'held',
                tstzrange('{T}'::timestamptz - interval '1 minute', '{T}'::timestamptz + interval '40 minutes')),
               ('{_id('L1')}', '{RUN}', '{_id('B')}', 'released',
                tstzrange('{T}'::timestamptz - interval '1 minute', '{T}'::timestamptz + interval '40 minutes'))""")
    r = w._wake(db)
    assert r["fingerprint"]["chargers_free"] == 2 and r["reasons"] == ["charger_free"], r


# ── a car with a due time ───────────────────────────────────────────────────────────────────────────────────────────

def test_0769_a_car_in_the_head_with_a_due_time_wakes_the_agent(db):
    _ready(db)
    _gate_on(db)
    db.val("UPDATE ottoq_ocpp_chargers SET station_state = 'Occupied'")     # no charger free, so only the due car can wake it
    _line(db, "A", "B")
    _visit(db, "A")
    _visit(db, "B")
    _settle(db)
    assert w._wake(db)["wake"] is False
    db.val(f"UPDATE ottoq_visit_needs SET dispatch_due_at = '{T}'::timestamptz + interval '45 minutes' WHERE vehicle_id = '{_id('B')}'")
    r = w._wake(db)
    assert r["wake"] is True and r["reasons"] == ["due_in_line"] and r["fingerprint"]["due_in_line"] == 1, r


def test_0769_a_due_car_counts_only_from_the_first_24_this_runs_open_visit_and_its_newest_one(db):
    _ready(db)
    _gate_on(db)
    db.val("UPDATE ottoq_ocpp_chargers SET station_state = 'Occupied'")
    due = "2026-10-13 15:45:00+00"
    # 25 in line: 20 cars with no visit, then B, C, D, E at 21-24 and A at 25. A's visit is due but A is outside the
    # head; B's due visit is another run's; C's is closed; D's due visit is older than its newest open one, which has
    # no due time; E's open visit has none yet
    _line(db, *([f"x{k}" for k in range(20)] + ["B", "C", "D", "E", "A"]))
    _visit(db, "A", due=due)
    _visit(db, "B", due=due, run="b0000000-0000-0000-0000-000000000769")
    _visit(db, "C", due=due, status="closed")
    _visit(db, "D", due=due, created="2026-10-13 13:00:00+00", key="d1")
    _visit(db, "D", created="2026-10-13 14:30:00+00", key="d2")
    _visit(db, "E")
    _settle(db)
    r = w._wake(db)
    assert r["fingerprint"]["due_in_line"] == 0 and r["wake"] is False, r
    db.val(f"UPDATE ottoq_visit_needs SET dispatch_due_at = '{due}' WHERE vehicle_id = '{_id('E')}'")
    r = w._wake(db)                                               # E is 24th: inside the head
    assert r["fingerprint"]["due_in_line"] == 1 and r["reasons"] == ["due_in_line"], r


# ── shadow, and everything before it ────────────────────────────────────────────────────────────────────────────────

def test_0769_in_shadow_the_gate_wakes_every_pass_and_records_why_it_would(db):
    _ready(db)
    _settle(db)
    r = w._wake(db)
    assert r["gate"] == "shadow" and r["wake"] is True and r["would_wake"] is False and r["reasons"] == [], r
    _line(db, "A")
    r = w._wake(db)
    assert r["wake"] is True and r["would_wake"] is True and r["reasons"] == ["charger_free"], r


def test_0769_without_the_two_moments_the_gate_wakes_and_sleeps_where_0711_did(db):
    """0711's own sequence (a wobble, an onset, a jump, a charger flapping) on a depot with no charger free and no car
    due: 0769 adds nothing to it."""
    _ready(db)
    _gate_on(db)
    db.val("UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = NULL")        # never free: the board would not count them
    cars = [_id(n) for n in "ABCDEFGH"]

    def line(n_over):
        db.val(f"DELETE FROM stub_kernel_line WHERE sim_run_id = '{RUN}'")
        for k, c in enumerate(cars):
            db.val(f"INSERT INTO stub_kernel_line VALUES ('{RUN}', '{c}', {k + 1}, {45 if k < n_over else 5}, 50)")

    line(0)
    w._consult(db, "k1", w._wake(db)["fingerprint"])
    assert w._wake(db)["wake"] is False
    line(1)
    r = w._wake(db)
    assert r["wake"] is True and r["reasons"] == ["contract_wait"], r
    w._consult(db, "k2", r["fingerprint"])
    line(2)
    assert w._wake(db)["wake"] is False
    line(6)
    r = w._wake(db)
    assert r["reasons"] == ["contract_wait"], r
