"""db/migrations/0723, EXECUTED: a charge's closing frames name the charger that sent them (the 0697 follow-up).

WHY THIS EXISTS. twin.ottoq_sim_stop_charge_session sent TransactionEvent Ended and the closing StatusNotification
through twin.ottoq_sim_emit_ocpp(p_session_id, NULL, ...), so both frames carried charger_id NULL (run 458156c8: 455
of 455 each), while the start and advance steps send from the charger the session's stall maps to. 0697's relay reads
the frame log through an inner join on the charger, so it could deliver every frame of a twin charge except the two
that end it. Executed here on the live stop and emit bodies (md5 2281c70b..., 3a421ca5...), every callee a stub:
  - before 0723 both closing frames carry NULL on every path, and 0697's own join drops them;
  - after it both carry the charger the Started frame was sent from, on every path the stop step has (a plain L2
    close, a DCFC close behind a latched arm, a fault that re-queues the car, a fault that does not), a charger that
    is gone leaves NULL without raising, a stall naming a charger that does not exist (only possible if the stall's
    key were dropped) closes with NULL rather than a frame the log's key refuses, and a session already closed sends
    nothing;
  - nothing else the step does moves: the same script run with and without 0723 leaves every table it touches the
    same, apart from those frames' charger;
  - 0723 refuses a second apply, a pair in flight, a start step that no longer sends from its stall's charger, and a
    patch that changes more than it says (its V2), and a refusal rolls the whole file back.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
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
STUB = os.path.join(ROOT, "tests", "fixtures", "stop_charge_session_stub.sql")
M0694 = os.path.join(ROOT, "db", "migrations", "0694_the_twins_chargers_speak_ocpp_2_0_1.sql")
M0697 = os.path.join(ROOT, "db", "migrations", "0697_the_charger_back_end_hears_the_twins_chargers_through_a_relay.sql")
M0723 = os.path.join(ROOT, "db", "migrations", "0723_a_charges_closing_frames_name_the_charger_that_sent_them.sql")
STOP_SIG = "twin.ottoq_sim_stop_charge_session(uuid,text,timestamptz,text,uuid)"
EMIT_SIG = "twin.ottoq_sim_emit_ocpp(uuid,uuid,uuid,uuid,timestamptz,text,text,jsonb)"
STOP_MD5 = "2281c70b3b5d7cc39f3026bf2b09b4cd"
EMIT_MD5 = "3a421ca5eaa88616bd0b41acaf7c22d9"
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "07230000-0000-0000-0000-000000000001"
OPERATOR = "07230000-0000-0000-0000-0000000000f0"
T0 = "2026-10-14 13:00:00+00"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0723-{name}"))


CHARGERS = {"L2-01": 19.2, "L2-02": 19.2, "L2-03": 19.2, "L2-04": 19.2, "DCFC-01": 350}
CARS = ["car-a", "car-b", "car-c", "car-d", "car-e", "car-f"]


def _helpers_sql():
    src = open(M0694, encoding="utf-8").read()
    fns = re.findall(r'^(CREATE FUNCTION (?:twin\.ottoq_ocpp201_|ottoq\.ottoq_ocpp_meter_soc).*?\$fn\$.*?\$fn\$;)',
                     src, re.S | re.M)
    assert len(fns) == 6, f"expected the six helpers of 0694, found {len(fns)}"
    return "\n".join(fns)


def _relay_join():
    """0697's own FROM/JOIN/WHERE, read from the file, with its parameters bound to the twin depot from the head."""
    src = open(M0697, encoding="utf-8").read()
    m = re.search(r"(FROM public\.ottoq_ocpp_messages m\s+JOIN public\.ottoq_ocpp_chargers c ON c\.charger_id = m\.charger_id"
                  r"\s+WHERE m\.message_seq > p_after AND c\.depot_id = v_depot AND m\.data_source = v_ds"
                  r"\s+AND m\.direction = 'cs_to_csms')", src)
    assert m, "0697's pull no longer reads the frame log through this join"
    return (m.group(1).replace("p_after", "0").replace("v_depot", f"'{DEPOT}'::uuid").replace("v_ds", "'twin'"))


def _new(tag):
    name = f"ottoq_sc_{tag}_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1",
                    "-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    rc, err = d.file(STUB)
    assert rc == 0, f"stub did not load: {err}"
    with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False) as f:
        f.write(_helpers_sql())
    try:
        rc, err = d.file(f.name)
    finally:
        os.remove(f.name)
    assert rc == 0, f"0694's helpers did not load: {err}"
    d.val(f"INSERT INTO public.depots VALUES ('{DEPOT}')")
    d.val(f"""INSERT INTO public.ottoq_sim_runs VALUES ('{RUN}', '{DEPOT}', 'completed', '{T0}', '{T0}')""")
    for code, kw in CHARGERS.items():
        d.val(f"""INSERT INTO public.ottoq_ocpp_chargers (charger_id, depot_id, ocpp_identifier, station_state,
                                                         station_state_changed_at, max_kw)
                  VALUES ('{_id('chg-' + code)}', '{DEPOT}', 'NASH-{code}', 'Available', '{T0}', {kw})""")
        d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, ocpp_charger_id)
                  VALUES ('{_id(code)}', '{DEPOT}', '{code}', '{'dcfc' if code.startswith('DCFC') else 'l2'}',
                          '{_id('chg-' + code)}')""")
    for code in ("STG-01", "STG-02"):
        d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_code, stall_type)
                  VALUES ('{_id(code)}', '{DEPOT}', '{code}', 'staging')""")
    for car in CARS:
        d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, current_depot_id, fleet_operator_id, display_name,
                                              battery_capacity_kwh, current_soc, target_soc, current_state,
                                              last_state_change, config)
                  VALUES ('{_id(car)}', '{DEPOT}', '{DEPOT}', '{OPERATOR}', '{car}', 75, 50, 100, 'arrived_at_gate',
                          '{T0}', '{{}}')""")
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


def _at(minutes):
    return f"'{T0}'::timestamptz + interval '{minutes} minutes'"


def _start(d, car, stall, minutes=0):
    return d.val(f"SELECT twin.ottoq_sim_start_charge_session('{_id(car)}', '{_id(stall)}', '{RUN}', NULL, {_at(minutes)})")


def _stop(d, sid, reason, minutes, message="NULL"):
    d.val(f"SELECT twin.ottoq_sim_stop_charge_session('{sid}', '{reason}', {_at(minutes)}, {message}, '{RUN}')")


def _script(d):
    """Every path the stop step has, in one fixed order. Returns {path: session id}."""
    s = {}
    # 1. an L2 charge that completes, with its charge booking still active
    s["l2_completed"] = _start(d, "car-a", "L2-01")
    d.val(f"""INSERT INTO public.ottoq_stall_bookings (booking_id, sim_run_id, stall_id, vehicle_id, purpose, during, state)
              VALUES ('{_id('bkg-a')}', '{RUN}', '{_id('L2-01')}', '{_id('car-a')}', 'charge_l2',
                      tstzrange({_at(0)}, {_at(120)}, '[)'), 'active')""")
    d.val(f"SELECT count(*) FROM twin.ottoq_sim_advance_charge_sessions('{RUN}', {_at(10)})")
    d.val(f"UPDATE public.vehicles SET current_soc = 90 WHERE id = '{_id('car-a')}'")
    _stop(d, s["l2_completed"], "completed", 20)
    # 2. a DCFC charge whose arm latched: the close holds the stall on a demate tether
    s["dcfc_tethered"] = _start(d, "car-b", "DCFC-01")
    d.val(f"""INSERT INTO twin.arm_cycles (cycle_id, sim_run_id, stall_id, vehicle_id, session_id, direction, outcome, started_at, ended_at)
              VALUES ('{_id('mate-b')}', '{RUN}', '{_id('DCFC-01')}', '{_id('car-b')}', '{s['dcfc_tethered']}', 'mate',
                      'latched', {_at(0)}, {_at(1)})""")
    d.val(f"UPDATE public.vehicles SET current_soc = 95 WHERE id = '{_id('car-b')}'")
    _stop(d, s["dcfc_tethered"], "completed", 30)
    # 3. a fault with the car well under target: the car is released and re-queued through a temp hold
    s["fault_requeued"] = _start(d, "car-c", "L2-02")
    d.val(f"UPDATE public.vehicles SET current_soc = 40 WHERE id = '{_id('car-c')}'")
    _stop(d, s["fault_requeued"], "fault.connector_cable", 15, "'cable fault'")
    # 4. a fault with the car near target: no re-queue
    s["fault_kept"] = _start(d, "car-d", "L2-01", 25)
    d.val(f"UPDATE public.vehicles SET current_soc = 97 WHERE id = '{_id('car-d')}'")
    _stop(d, s["fault_kept"], "fault.station_hardware", 40)
    # 5. the stall's charger is gone by the time the charge ends (the stall's key and the frame log's go to NULL)
    s["charger_gone"] = _start(d, "car-e", "L2-03")
    d.val(f"DELETE FROM public.ottoq_ocpp_chargers WHERE charger_id = '{_id('chg-L2-03')}'")
    _stop(d, s["charger_gone"], "completed", 35)
    # 6. a session already closed elsewhere: the step only makes sure the plug was released, and sends nothing
    _stop(d, s["l2_completed"], "completed", 45)
    return s


DUMP = """
SELECT jsonb_build_object(
  'sessions', (SELECT jsonb_agg(to_jsonb(x) - 'updated_at' - 'created_at' ORDER BY x.id) FROM public.ocpp_sessions x),
  'frames',   (SELECT jsonb_agg(to_jsonb(x) - 'message_id' - 'message_seq' - 'message_at' - 'created_at' - 'charger_id'
                                ORDER BY x.message_seq) FROM public.ottoq_ocpp_messages x),
  'vehicles', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.vehicles x),
  'stalls',   (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.stalls x),
  'chargers', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.charger_id) FROM public.ottoq_ocpp_chargers x),
  'bookings', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.booking_id) FROM public.ottoq_stall_bookings x),
  'arm',      (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.cycle_id) FROM twin.arm_cycles x),
  'calls',    (SELECT jsonb_agg(jsonb_build_object('fn', x.fn, 'args', x.args) ORDER BY x.seq) FROM public.t_calls x))
"""


def _frames(d, sid):
    """A session's station frames in order: (type, eventType or connectorStatus, charger)."""
    rows = d.json(f"""SELECT COALESCE(jsonb_agg(jsonb_build_array(m.message_type,
                                       COALESCE(m.payload ->> 'eventType', m.payload ->> 'connectorStatus'), m.charger_id)
                                     ORDER BY m.message_seq), '[]')
                        FROM public.ottoq_ocpp_messages m WHERE m.ocpp_session_id = '{sid}'""")
    return [tuple(r) for r in rows]


def _closing(frames):
    return [f for f in frames if (f[0], f[1]) in (("TransactionEvent", "Ended"), ("StatusNotification", "Available"))]


def _relayed(d):
    return set(d.json(f"SELECT COALESCE(jsonb_agg(DISTINCT m.message_id::text), '[]') {_relay_join()}"))


def _apply(d, path=M0723):
    return d.file(path)


def test_0723_the_stub_carries_the_live_bodies(db):
    assert db.val(f"SELECT md5(pg_get_functiondef('{STOP_SIG}'::regprocedure))") == STOP_MD5
    assert db.val(f"SELECT md5(pg_get_functiondef('{EMIT_SIG}'::regprocedure))") == EMIT_MD5


def test_0723_before_the_closing_frames_name_no_charger_and_the_relay_drops_them(db):
    s = _script(db)
    open_paths = {k: v for k, v in s.items()}
    for path, sid in open_paths.items():
        frames = _frames(db, sid)
        closing = _closing(frames)
        assert len(closing) == 2, (path, frames)
        assert all(f[2] is None for f in closing), (path, frames)          # the defect, on every path
    # the opening frames name the charger, the closing ones do not, and 0697's join keeps only the named ones
    relayed = _relayed(db)
    ended = set(db.json("""SELECT jsonb_agg(m.message_id::text) FROM public.ottoq_ocpp_messages m
                            WHERE m.payload ->> 'eventType' = 'Ended' OR m.payload ->> 'connectorStatus' = 'Available'"""))
    started = set(db.json("""SELECT jsonb_agg(m.message_id::text) FROM public.ottoq_ocpp_messages m
                              WHERE m.payload ->> 'eventType' = 'Started'"""))
    assert len(ended) == 10 and not (ended & relayed)
    assert len(started) == 5 and len(started & relayed) == 4             # car-e's charger was deleted under it


def test_0723_after_every_closing_path_names_the_charger_the_charge_was_started_on(db):
    rc, err = _apply(db)
    assert rc == 0, err
    assert "0723 V1 PASSED" in err and "0723 V2-V3 PASSED" in err, err
    s = _script(db)
    for path, sid in s.items():
        frames = _frames(db, sid)
        closing = _closing(frames)
        assert len(closing) == 2, (path, frames)
        started = [f for f in frames if f[:2] == ("TransactionEvent", "Started")]
        assert len(started) == 1, (path, frames)
        if path == "charger_gone":
            # the charger was deleted: the stall's key went NULL, so the frames carry NULL, as before, and nothing raised
            assert all(f[2] is None for f in frames), (path, frames)
            continue
        stall_charger = db.val(f"""SELECT st.ocpp_charger_id FROM public.ocpp_sessions o
                                    JOIN public.stalls st ON st.id = o.stall_id WHERE o.id = '{sid}'""")
        assert started[0][2] == stall_charger, (path, frames)
        assert all(f[2] == stall_charger for f in frames), (path, frames)  # one transaction, one station
    # every closing frame of a charger that still exists is now kept by 0697's join
    relayed = _relayed(db)
    kept = set(db.json(f"""SELECT jsonb_agg(m.message_id::text) FROM public.ottoq_ocpp_messages m
                           WHERE (m.payload ->> 'eventType' = 'Ended' OR m.payload ->> 'connectorStatus' = 'Available')
                             AND m.ocpp_session_id <> '{s['charger_gone']}'"""))
    assert len(kept) == 8 and kept <= relayed
    # the already-closed stop sent nothing: each session has exactly one Ended
    assert db.val("""SELECT count(*) FROM public.ottoq_ocpp_messages WHERE payload ->> 'eventType' = 'Ended'""") == "5"


def test_0723_a_stall_naming_a_charger_that_does_not_exist_closes_with_null_not_a_refused_frame(db):
    # Live, stalls.ocpp_charger_id is a foreign key to the charger (ON DELETE SET NULL), so this cannot happen there. If
    # that key were ever dropped, the plain stall lookup would hand the frame log an id its own foreign key refuses, and
    # the close would abort. 0723 reads the charger through the charger table, so the frame carries NULL instead.
    rc, err = _apply(db)
    assert rc == 0, err
    sid = _start(db, "car-f", "L2-04")
    db.val("ALTER TABLE public.stalls DROP CONSTRAINT stalls_ocpp_charger_id_fkey")
    db.val(f"UPDATE public.stalls SET ocpp_charger_id = '{_id('no-such-charger')}' WHERE id = '{_id('L2-04')}'")
    _stop(db, sid, "completed", 20)
    closing = _closing(_frames(db, sid))
    assert len(closing) == 2 and all(f[2] is None for f in closing), closing
    assert db.val(f"SELECT status FROM public.ocpp_sessions WHERE id = '{sid}'") == "completed"
    # the plain lookup the join replaces would have been refused by the frame log's key
    rc, _, err = db.run(f"""INSERT INTO public.ottoq_ocpp_messages (ocpp_session_id, charger_id, direction, message_type, payload)
                            VALUES ('{sid}', (SELECT ocpp_charger_id FROM public.stalls WHERE id = '{_id('L2-04')}'),
                                    'cs_to_csms', 'StatusNotification', '{{}}')""")
    assert rc != 0 and "ottoq_ocpp_messages_charger_id_fkey" in err, err


def test_0723_nothing_else_the_stop_step_does_moves():
    before, after = _new("b"), _new("a")
    try:
        rc, err = _apply(after)
        assert rc == 0, err
        _script(before)
        _script(after)
        b = before.json(DUMP)
        a = after.json(DUMP)
        for k in b:
            assert a[k] == b[k], k
        # and the only column that differs is the closing frames' charger
        cb = before.json("""SELECT jsonb_agg(charger_id ORDER BY message_seq) FROM public.ottoq_ocpp_messages""")
        ca = after.json("""SELECT jsonb_agg(charger_id ORDER BY message_seq) FROM public.ottoq_ocpp_messages""")
        kinds = after.json("""SELECT jsonb_agg(COALESCE(payload ->> 'eventType', payload ->> 'connectorStatus', message_type)
                                               ORDER BY message_seq) FROM public.ottoq_ocpp_messages""")
        moved = [k for k, x, y in zip(kinds, cb, ca) if x != y]
        assert len(cb) == len(ca) and sorted(set(moved)) == ["Available", "Ended"] and len(moved) == 8, moved
    finally:
        _drop(before)
        _drop(after)


def test_0723_refuses_a_second_apply_and_a_pair_in_flight(db):
    db.val("UPDATE public.t_inflight SET n = 1")
    rc, err = _apply(db)
    assert rc != 0 and "0723 P0" in err, err
    db.val("UPDATE public.t_inflight SET n = 0")
    rc, err = _apply(db)
    assert rc == 0, err
    rc, err = _apply(db)
    assert rc != 0 and "0723 P1: twin.ottoq_sim_stop_charge_session is not the definition" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0723%'") == "1"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0723_pre'") == "1"


def test_0723_refuses_when_the_start_step_no_longer_sends_from_its_stalls_charger(db):
    db.val("""DO $x$ BEGIN
                EXECUTE regexp_replace(pg_get_functiondef('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure),
                                       'v_session_id, v_charger\\.charger_id,', 'v_session_id, NULL,');
              END $x$""")
    rc, err = _apply(db)
    assert rc != 0 and "0723 P1: the start step no longer sends its frames from its stall's charger (2 of 3 emits)" in err, err
    assert db.val(f"SELECT md5(pg_get_functiondef('{STOP_SIG}'::regprocedure))") == STOP_MD5


def test_0723_v2_refuses_a_patch_that_changes_more_than_it_says(db):
    src = open(M0723, encoding="utf-8").read()
    anchor = "the charger the closing frames are sent from\n$n$;"
    assert src.count(anchor) == 1
    cut = src.replace(anchor, "the charger the closing frames are sent from\n  v_extra int;\n$n$;")
    with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False) as f:
        f.write(cut)
    try:
        rc, err = _apply(db, f.name)
    finally:
        os.unlink(f.name)
    assert rc != 0 and "0723 V2 FAILED" in err, err
    # and the refusal rolled the whole file back
    assert db.val(f"SELECT md5(pg_get_functiondef('{STOP_SIG}'::regprocedure))") == STOP_MD5
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0723%'") == "0"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0723_pre'") == "0"
