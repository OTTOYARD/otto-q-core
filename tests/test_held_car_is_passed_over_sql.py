"""db/migrations/0761, EXECUTED: a car held at its charger is passed over by the bay doors.

WHY THIS EXISTS. On the live run c6ec017d (2026-10-20, the twin depot, stall_cabin_robot on) decide section (4b) seated
car ca2624fc in a wash bay at sim 9:45:13 AM CT, three seconds before its fast charger's cleaning arm was home, and the
tidy was thrown away (G479). 0760 keeps such a car's stall, but (4b) and (5), the two doors that read cars waiting in
staging, never read 0758's hold, and once the charge arm's tether has run out the interlock lets any move through. And
every one of the run's 12 refused moves was that interlock, filed on the decision row as a bare exception (G472).
Executed here, on the scratch PostgreSQL, against the bodies 0761 reads, as live (tests/fixtures/
held_car_passed_over_stub.sql, prosrc md5 asserted as read on 2026-10-20):
  - the two doors' insertions, taken from 0761 as written, pass over a car its stall's cleaning arm is at work in, and
    a car a data transfer holds, whatever the dial reads; and with bay_walkin_waits_for_the_arm, a car the charge arm
    still holds, by the interlock's own test;
  - every other car is read as before: the arm at work on another stall, or done; a closed visit; another run's visit;
    a tether that has run out, or runs out at the clock; a staging stall; no work at all;
  - each insertion sits before its anchor's last line, as 0761's V1 and V3 assume;
  - the assignment's patch, run from 0761, leaves the body it was written to leave; an interlock refusal reads as
    before at the dial's default and carries its message with the dial; a refusal writes nothing; a car nothing holds
    is seated as before.
The decide's own patch is proven on its live body by 0761's V1 at apply; the decide is not loaded here.
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
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)

ROOT = base.ROOT
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "held_car_passed_over_stub.sql")
M0761 = os.path.join(ROOT, "db", "migrations", "0761_a_car_held_at_its_charger_is_passed_over_by_the_bay_doors.sql")
ASSIGN = ("ottoq.ottoq_enact_space_assignment(uuid,uuid,uuid,text,text,timestamp with time zone,"
          "timestamp with time zone,uuid,text)")
LIVE = {  # prosrc md5, read from the live catalog on 2026-10-20; 0761's P1 pins the same
    ASSIGN: "8334b01ae1fe40a3c67da111b93faee4",
    "ottoq.ottoq_uplink_transfer_holds(uuid,uuid)": "dfd5d9d7b68066b2e933f5056bcaaceb",
    "public.ottoq_vehicle_is_tethered(uuid,timestamp with time zone)": "306c42afd9c974881402fdfc579ecf15",
    "public.ottoq_arm_interlock_guard()": "ac1e1c702521e4b2e0708ebef513071c",
    "public.ottoq_policy_get(uuid,text,numeric)": "72b658f3a9c5a7ec0fae15aecc907f38",
}
DIAL = "bay_walkin_waits_for_the_arm"
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "a0000000-0000-0000-0000-000000000761"
OTHER_RUN = "a0000000-0000-0000-0000-000000007610"
T = "2026-09-01 14:45:13+00"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0761-{name}"))


def _text():
    with open(M0761) as f:
        return f.read()


def _between(text, start, end):
    return text[text.index(start):text.index(end)]


def _tagged(text, tag):
    """The dollar-quoted string $tag$...$tag$ in 0761."""
    m = re.search(re.escape(f"${tag}$") + r"(.*?)" + re.escape(f"${tag}$"), text, re.S)
    assert m, f"0761 has no ${tag}$ string"
    return m.group(1)


def _insertion(old, new):
    """0761 places each door's insertion before its anchor's last line: new = head + insertion + tail."""
    tail = old.rstrip("\n").rsplit("\n", 1)[-1] + "\n"
    head = old[:len(old) - len(tail)]
    ins = new[len(head):len(new) - len(tail)]
    return head, ins, tail


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_hcp_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        rc, err = d.file(FIXTURE)
        assert rc == 0, f"the fixture did not load: {err}"
        d.val(f"""INSERT INTO public.ottoq_sim_runs VALUES ('{RUN}', '{DEPOT}', 'running', '{T}'::timestamptz - interval '2 hours',
                                                          '{T}')""")
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_hcp_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _dial(d, value):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
              VALUES ('depot', '{DEPOT}', '{DIAL}', {value}, 'test')
              ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value""")


def _stall(d, code, kind):
    sid = _id(code)
    d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, status)
              VALUES ('{sid}', '{DEPOT}', '{code}', '{kind}', 'available')""")
    return sid


def _car(d, name, stall, atoms=(), run=RUN, visit_status="in_progress", tether_s=None):
    """A car waiting in staging on `stall`; its visit holds `atoms`; a charge-arm tether runs `tether_s` past T."""
    vid = _id(name)
    until = "NULL" if tether_s is None else f"'{T}'::timestamptz + interval '{tether_s} seconds'"
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, current_depot_id, current_state, current_stall_id,
                                           robotic_tether_until, robotic_tether_stall_id, robotic_tether_direction,
                                           robotic_tether_phase)
              VALUES ('{vid}', '{DEPOT}', '{DEPOT}', 'staged_awaiting_service', '{stall}', {until},
                      {"NULL" if tether_s is None else f"'{stall}'"}, {"NULL" if tether_s is None else "'demate'"},
                      {"NULL" if tether_s is None else "'unlatch'"})""")
    d.val(f"UPDATE public.stalls SET current_vehicle_id = '{vid}', status = 'occupied' WHERE id = '{stall}'")
    if atoms:
        d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, status, atoms)
                  VALUES ('{vid}', '{run}', '{visit_status}', '{json.dumps(list(atoms))}'::jsonb)""")
    return vid


def _arm_tidy(stall, status="in_progress"):
    return {"svc": "interior_tidy", "must_do": True, "concurrency": "cabin", "status": status,
            "performed_by": "stall_cabin_robot", "robot_stall_id": stall,
            "started_at": "2026-09-01T14:39:28+00:00", "ends_at": "2026-09-01T14:45:16+00:00"}


def _world(d):
    """One car of every kind the doors meet, by name."""
    s = {n: _stall(d, n, k) for n, k in [("DCFC-01", "dcfc"), ("DCFC-02", "dcfc"), ("DCFC-03", "dcfc"),
                                         ("DCFC-04", "dcfc"), ("DCFC-05", "dcfc"), ("DCFC-06", "dcfc"),
                                         ("DCFC-07", "dcfc"), ("DCFC-08", "dcfc"), ("L2-01", "l2"),
                                         ("STG-01", "staging"), ("STG-02", "staging")]}
    return {
        "arm_at_work": _car(d, "arm_at_work", s["DCFC-01"], [{"svc": "charge", "status": "done"}, _arm_tidy(s["DCFC-01"])]),
        "arm_done": _car(d, "arm_done", s["DCFC-02"], [_arm_tidy(s["DCFC-02"], status="done")]),
        "arm_on_another_stall": _car(d, "arm_on_another_stall", s["DCFC-03"], [_arm_tidy(s["DCFC-01"])]),
        "tether_live": _car(d, "tether_live", s["DCFC-04"], [{"svc": "charge", "status": "done"}], tether_s=3),
        "tether_run_out": _car(d, "tether_run_out", s["DCFC-05"], [{"svc": "charge", "status": "done"}], tether_s=-12),
        "tether_ends_at_the_clock": _car(d, "tether_ends_at_the_clock", s["DCFC-08"], [], tether_s=0),
        "transfer_pending": _car(d, "transfer_pending", s["L2-01"],
                                 [{"svc": "data_offload", "needs_uplink": True, "status": "pending"}]),
        "nothing": _car(d, "nothing", s["STG-01"]),
        "other_runs_visit": _car(d, "other_runs_visit", s["DCFC-06"], [_arm_tidy(s["DCFC-06"])], run=OTHER_RUN),
        "visit_closed": _car(d, "visit_closed", s["DCFC-07"], [_arm_tidy(s["DCFC-07"])], visit_status="complete"),
        "arm_atom_on_staging": _car(d, "arm_atom_on_staging", s["STG-02"], [_arm_tidy(s["STG-02"])]),
    }


def _door(d, seq):
    """The cars door `seq` (1 = (4b)'s candidates, 2 = (5)'s cursor) reads, with 0761's insertion as written."""
    text = _text()
    _, ins, _ = _insertion(_tagged(text, f"o{seq}"), _tagged(text, f"n{seq}"))
    alias = "pk" if seq == 1 else "v"
    out = d.val(f"""SELECT COALESCE(string_agg({alias}.id::text, ',' ORDER BY {alias}.id), '')
                      FROM (SELECT v.id, v.id AS vehicle_id FROM public.vehicles v) {alias}
                      CROSS JOIN (SELECT '{RUN}'::uuid AS p_sim_run_id, '{T}'::timestamptz AS v_clock) z
                     WHERE true {ins}""")
    return set(out.split(",")) - {""}


HELD_ALWAYS = {"arm_at_work", "transfer_pending"}
HELD_BY_THE_DIAL = {"tether_live"}


# ── the fixture is the five bodies as live ──

def test_the_fixture_carries_the_live_bodies(db):
    for fn, md5 in LIVE.items():
        assert db.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')") == md5, fn


# ── the two doors ──

@pytest.mark.parametrize("seq", [1, 2])
def test_each_insertion_sits_before_its_anchors_last_line(seq):
    text = _text()
    old, new = _tagged(text, f"o{seq}"), _tagged(text, f"n{seq}")
    head, ins, tail = _insertion(old, new)
    assert head + ins + tail == new
    assert ins.strip() and "ottoq_uplink_transfer_holds" in ins and DIAL in ins


@pytest.mark.parametrize("seq", [1, 2])
@pytest.mark.parametrize("dial", [None, 0, 1])
def test_a_door_passes_over_a_held_car_and_reads_every_other_as_before(db, seq, dial):
    cars = _world(db)
    if dial is not None:
        _dial(db, dial)
    passed_over = HELD_ALWAYS | (HELD_BY_THE_DIAL if dial == 1 else set())
    assert _door(db, seq) == {cars[n] for n in cars if n not in passed_over}


@pytest.mark.parametrize("seq", [1, 2])
def test_a_car_is_read_again_once_the_arm_is_home(db, seq):
    cars = _world(db)
    _dial(db, 1)
    assert cars["arm_at_work"] not in _door(db, seq)
    db.val(f"""UPDATE public.ottoq_visit_needs SET atoms = jsonb_set(atoms, '{{1,status}}', '"done"')
                WHERE vehicle_id = '{cars["arm_at_work"]}'""")
    db.val(f"UPDATE public.vehicles SET robotic_tether_until = NULL WHERE id = '{cars['tether_live']}'")
    assert {cars["arm_at_work"], cars["tether_live"]} <= _door(db, seq)


@pytest.mark.parametrize("seq", [1, 2])
def test_the_tether_test_is_the_interlocks(db, seq):
    """A tether that ends at the clock has run out for the interlock (until <= the run's clock lets the move through),
    so the door reads the car; one second later and both hold it."""
    cars = _world(db)
    _dial(db, 1)
    assert cars["tether_ends_at_the_clock"] in _door(db, seq)
    db.val(f"""UPDATE public.vehicles SET robotic_tether_until = '{T}'::timestamptz + interval '1 second'
                WHERE id = '{cars["tether_ends_at_the_clock"]}'""")
    assert cars["tether_ends_at_the_clock"] not in _door(db, seq)


# ── the assignment's catch-all ──

def _patch_assignment(d):
    text = _text()
    sql = ("BEGIN;\n" + _between(text, "-- ── (a) the dial ──", "-- ── (b) decide sections")
           + _between(text, "-- ── (c) the assignment's catch-all", "-- ── V1:") + "COMMIT;\n")
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
        f.write(sql)
        path = f.name
    try:
        rc, err = d.file(path)
    finally:
        os.unlink(path)
    assert rc == 0, f"0761's assignment patch did not run: {err}"


def _assign(d, car):
    return d.json(f"""SELECT ottoq.ottoq_enact_space_assignment('{RUN}', '{DEPOT}', '{car}', 'wash_bay', 'wash',
                                                                '{T}'::timestamptz, '{T}'::timestamptz + interval '25 minutes',
                                                                NULL, 'needs_card')""")


def _bay_world(d):
    bay = _stall(d, "WSH-01", "wash_bay")
    dcfc = _stall(d, "DCFC-08", "dcfc")
    stg = _stall(d, "STG-01", "staging")
    return bay, dcfc, stg


@pytest.mark.parametrize("stage", ["before_0761", "dial_on"])
def test_only_the_door_keeps_a_car_the_arm_is_cleaning(db, stage):
    """G479's second door, reproduced as at ca2624fc's 9:45:13: the charge arm's tether has run out, so the interlock
    lets the move through, and the assignment reads no hold, before 0761 or after. Only the doors can pass the car
    over, and with 0761 both do."""
    bay, dcfc, _ = _bay_world(db)
    car = _car(db, "ca2624fc", dcfc, [{"svc": "charge", "status": "done"}, _arm_tidy(dcfc)], tether_s=-12)
    if stage == "dial_on":
        _patch_assignment(db)
        _dial(db, 1)
    assert car not in _door(db, 1) and car not in _door(db, 2)
    out = _assign(db, car)
    assert out["assigned"] is True and out["stall_id"] == bay


def test_the_patch_leaves_the_body_it_was_written_to_leave(db):
    _patch_assignment(db)
    text = _text()
    old, new = _tagged(text, "o3"), _tagged(text, "n3")
    body = db.val(f"SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('{ASSIGN}')")
    assert body is not None
    assert db.val(f"""SELECT md5(replace(prosrc, $x${new}$x$, $x${old}$x$)) FROM pg_proc
                       WHERE oid = to_regprocedure('{ASSIGN}')""") == LIVE[ASSIGN]
    assert db.val(f"SELECT count(*) FROM public.ottoq_policy_param_catalog WHERE param_key = '{DIAL}' "
                  "AND default_value = 0 AND min_value = 0 AND max_value = 1 AND NOT agent_writable") == "1"


@pytest.mark.parametrize("stage", ["before_0761", "dial_default", "dial_off"])
def test_an_interlock_refusal_reads_as_before_without_the_dial(db, stage):
    bay, dcfc, _ = _bay_world(db)
    car = _car(db, "ca2624fc", dcfc, tether_s=3)
    if stage != "before_0761":
        _patch_assignment(db)
    if stage == "dial_off":
        _dial(db, 0)
    assert _assign(db, car) == {"assigned": False, "reason": "exception", "sqlstate": "P0001"}


def test_with_the_dial_an_interlock_refusal_carries_its_message(db):
    bay, dcfc, _ = _bay_world(db)
    car = _car(db, "ca2624fc", dcfc, tether_s=3)
    _patch_assignment(db)
    _dial(db, 1)
    out = _assign(db, car)
    assert {k: out[k] for k in ("assigned", "reason", "sqlstate")} == {"assigned": False, "reason": "exception",
                                                                       "sqlstate": "P0001"}
    assert out["message"].startswith(f"arm interlock: vehicle {car} is held by the arm at stall {dcfc}")
    assert f"refusing to move it to {bay}" in out["message"]


@pytest.mark.parametrize("dial", [0, 1])
def test_a_refusal_writes_nothing(db, dial):
    bay, dcfc, _ = _bay_world(db)
    car = _car(db, "ca2624fc", dcfc, tether_s=3)
    _patch_assignment(db)
    _dial(db, dial)
    _assign(db, car)
    assert db.val(f"SELECT concat_ws('|', COALESCE(reserved_by::text, '-'), COALESCE(current_vehicle_id::text, '-')) "
                  f"FROM public.stalls WHERE id = '{bay}'") == "-|-"
    assert db.val("SELECT count(*) FROM public.ottoq_stall_bookings") == "0"
    assert db.val(f"SELECT current_stall_id FROM public.vehicles WHERE id = '{car}'") == dcfc


@pytest.mark.parametrize("stage", ["before_0761", "dial_off", "dial_on"])
def test_a_car_nothing_holds_is_seated_as_before(db, stage):
    bay, _, stg = _bay_world(db)
    car = _car(db, "walk_in", stg)
    if stage != "before_0761":
        _patch_assignment(db)
        _dial(db, 1 if stage == "dial_on" else 0)
    out = _assign(db, car)
    booking = out.pop("booking_id")
    assert out == {"assigned": True, "stall_id": bay, "booked": True, "purpose": "wash", "stall_type": "wash_bay",
                   "until": out["until"], "released_stall_id": stg, "source": "needs_card", "leg_id": None,
                   "honoured_reservation": False}
    assert db.val(f"SELECT current_stall_id FROM public.vehicles WHERE id = '{car}'") == bay
    assert db.val(f"SELECT stall_id FROM public.ottoq_stall_bookings WHERE booking_id = '{booking}'") == bay
