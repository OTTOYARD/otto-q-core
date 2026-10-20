"""db/migrations/0743, EXECUTED: the bay calendar seats each car on its own, and waits for a car the robotic arm still holds.

WHY THIS EXISTS. Each tick the decide seats the cars whose bay reservation is due (ottoq.ottoq_activate_due_bay_reservations).
Before 0743 it seated them all or none: one error ended the call and took every seat it had made with it. A car just off
its charger is ready for its bay at once while the arm still holds it, and moving it trips the arm interlock, which
raises, so a tick with such a car seated nobody (G457). Every claim in 0743's header that a test can execute is executed
here, on the scratch PostgreSQL, against the live bodies of the activation and everything it calls or fires
(tests/fixtures/bay_activation_stub.sql, md5 asserted as read on 2026-10-17):
  - before 0743, a car the arm holds stops every seat in the call, and once its arm lets go the same call seats both;
  - 0743 applies, its checks run, it leaves the body it was written to leave, and a second apply is refused;
  - at the dial's default the call is still all or nothing, exactly as before;
  - with the dial, the held car waits and the other is seated; on the next tick, its demate done, it is seated too;
  - with the dial, one refused seat (any error) costs that seat only: the others stand, its stall reservation is undone,
    and the refusal is recorded once with its SQLSTATE and message; at the default the same refusal costs every seat;
  - one such error is real: a tether past its time that nothing has cleared still pins the car's old stall
    (sync_stall_occupancy keeps a stall the tether names), so the move would give it two stalls and the one-stall index
    refuses it (23505); with the dial that costs that seat and is recorded;
  - the pre-image in ottoq_schema_snapshots puts the live body back.
A module template carries the base stub and the fixture, and each test clones it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)

ROOT = base.ROOT
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "bay_activation_stub.sql")
M0743 = os.path.join(ROOT, "db", "migrations", "0743_the_bay_calendar_seats_each_car_on_its_own.sql")
DEPOT = base.DEPOT
RUN = "a0000000-0000-0000-0000-000000000743"
T = "2026-10-17 13:00:00+00"

ACT = "ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)"
# the live bodies the fixture carries (md5 of prosrc, read from the live catalog on 2026-10-17)
LIVE = {
    ACT: "4fb04e0a5f2d5d16b24fda2f9990f2d1",
    "ottoq.ottoq_vehicle_bay_ready(uuid,uuid,timestamp with time zone)": "f52356da4a33742998c3fc69695e7bb9",
    "ottoq.ottoq_uplink_transfer_holds(uuid,uuid)": "e586ee275d120d70d637e3d87b2330a1",
    "public.ottoq_reserve_stall(uuid,uuid,timestamp with time zone,integer)": "ac95d032dd8c3deb4d4334cc51cc3c47",
    "public.ottoq_vehicle_is_tethered(uuid,timestamp with time zone)": "306c42afd9c974881402fdfc579ecf15",
    "public.sync_stall_occupancy()": "db14b363098b4445beee896be55bc49a",
    "public.ottoq_arm_interlock_guard()": "ac1e1c702521e4b2e0708ebef513071c",
}
AFTER_0743 = "80d42bc1a54521582a14948f6951a891"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0743-{name}"))


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_bap_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, FIXTURE):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_ba_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply(d):
    rc, err = d.file(M0743)
    assert rc == 0, f"0743 did not apply: {err}"


def _md5(d, fn):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')")


def _world(d):
    """A depot with three wash bays, a fast charger and staging; a running run whose clock is T."""
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_start, sim_clock_current)
              VALUES ('{RUN}', '{DEPOT}', 'running', '{T}'::timestamptz - interval '6 hours',
                      '{T}'::timestamptz - interval '6 hours', '{T}')""")
    for i, (code, kind) in enumerate([("WSH-1", "wash_bay"), ("WSH-2", "wash_bay"), ("WSH-3", "wash_bay"),
                                       ("CHG-1", "dcfc"), ("STG-1", "staging"), ("STG-2", "staging"),
                                       ("STG-3", "staging")]):
        d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, display_name, status, distance_from_entrance)
                  VALUES ('{_id(code)}', '{DEPOT}', '{code}', '{kind}', '{code}', 'available', {i})""")


def _car(d, name, state, stall):
    """A car standing at a stall; the stall points at it, as the live sync trigger leaves it."""
    vid = _id(name)
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, display_name, current_state, current_stall_id,
                                           last_state_change, config)
              VALUES ('{vid}', '{DEPOT}', 'autonomous', '{name}', '{state}', '{_id(stall)}',
                      '{T}'::timestamptz - interval '20 minutes', '{{}}')""")
    d.val(f"UPDATE public.stalls SET current_vehicle_id = '{vid}', status = 'occupied' WHERE id = '{_id(stall)}'")
    return vid


def _hold(d, car, bay, start_min=-1, minutes=18):
    """A wash reservation the forward planner made an hour ago, in its window now."""
    return d.val(f"""INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state,
                                                              booked_at, booked_by, booked_at_sim)
                     VALUES ('{RUN}', '{_id(bay)}', '{car}', 'wash',
                             tstzrange('{T}'::timestamptz + interval '{start_min} minutes',
                                       '{T}'::timestamptz + interval '{start_min + minutes} minutes', '[)'),
                             'held', '{T}'::timestamptz - interval '60 minutes', 'otto_q',
                             '{T}'::timestamptz - interval '60 minutes')
                     RETURNING booking_id""")


def _mate(d, car, stall, until_min=3):
    d.val(f"""UPDATE public.vehicles SET robotic_tether_until = '{T}'::timestamptz + interval '{until_min} minutes',
                     robotic_tether_stall_id = '{_id(stall)}', robotic_tether_direction = 'demate',
                     robotic_tether_phase = 'demate'
               WHERE id = '{car}'""")


def _release_arm(d, car):
    d.val(f"""UPDATE public.vehicles SET robotic_tether_until = NULL, robotic_tether_stall_id = NULL,
                     robotic_tether_direction = NULL, robotic_tether_phase = NULL WHERE id = '{car}'""")


def _activate(d, clock=T):
    return int(d.val(f"SELECT ottoq.ottoq_activate_due_bay_reservations('{RUN}', '{DEPOT}', '{clock}')"))


def _dial(d, value):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{RUN}', 'bay_activation_per_seat', {value}, 'test', now())""")


def _state(d, car):
    return d.val(f"SELECT current_state::text || ' ' || COALESCE((SELECT stall_code FROM public.stalls s WHERE s.id = v.current_stall_id), '-') "
                 f"FROM public.vehicles v WHERE v.id = '{car}'")


def _bay(d, code):
    return d.val(f"""SELECT COALESCE((SELECT display_name FROM public.vehicles WHERE id = s.current_vehicle_id), '-') || ' '
                            || COALESCE((SELECT display_name FROM public.vehicles WHERE id = s.reserved_by), '-')
                       FROM public.stalls s WHERE s.id = '{_id(code)}'""")


def _a_held_car_and_a_ready_one(d):
    """A is just off the charger and the arm still holds it; B is staged and ready. Both hold a wash bay now."""
    _world(d)
    a = _car(d, "car-A", "charge_complete_holding", "CHG-1")
    b = _car(d, "car-B", "staged_awaiting_service", "STG-1")
    _mate(d, a, "CHG-1", until_min=3)
    _hold(d, a, "WSH-1")
    _hold(d, b, "WSH-2")
    return a, b


def test_the_fixture_is_the_live_bodies(db):
    for fn, md5 in LIVE.items():
        assert _md5(db, fn) == md5, fn


def test_before_0743_a_car_the_arm_holds_stops_every_seat_in_the_call(db):
    a, b = _a_held_car_and_a_ready_one(db)
    assert _activate(db) == 0
    assert _state(db, b) == "staged_awaiting_service STG-1"          # ready, its bay empty, and not seated
    assert _state(db, a) == "charge_complete_holding CHG-1"
    assert _bay(db, "WSH-1") == "- -" and _bay(db, "WSH-2") == "- -"   # nothing occupied, nothing left reserved
    assert db.val("SELECT count(*) FROM public.ottoq_stall_bookings WHERE state = 'held'") == "2"
    assert db.val("SELECT count(*) FROM public.test_bay_commands") == "0"
    # the arm lets go: the same call seats both
    _release_arm(db, a)
    assert _activate(db) == 2
    assert _state(db, a) == "in_wash_bay WSH-1" and _state(db, b) == "in_wash_bay WSH-2"
    assert _bay(db, "CHG-1") == "- -" and _bay(db, "STG-1") == "- -"   # the sync trigger freed what they left
    assert db.val("SELECT string_agg(verb, ',' ORDER BY verb) FROM public.test_bay_commands") == "enter_wash,enter_wash"


def test_0743_applies_and_a_second_apply_is_refused(db):
    _apply(db)
    assert _md5(db, ACT) == AFTER_0743
    assert db.val("""SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage
                      WHERE name = '0743_the_bay_calendar_seats_each_car_on_its_own'""") == "falsefalse"
    assert db.val("""SELECT default_value || '/' || min_value || '/' || max_value || '/' || COALESCE(agent_writable, false)
                       FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_activation_per_seat'""") == "0/0/1/false"
    assert db.val("""SELECT category FROM public.ottoq_event_types_catalog
                      WHERE event_type = 'ottoq.bay_reservation_seat_refused'""") == "system_event"
    cell = db.json("""SELECT jsonb_build_object('cell', c.cell_code, 'buildout', c.buildout_code, 'params', c.fixed_params,
                                                 'priority', s.priority, 'seeds', s.seeds, 'scenario', s.scenario)
                        FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                       WHERE s.sweep_code = 'bayseat_normal_2026_10_17'""")
    assert cell == {"cell": "dcfc40.otto_q.bay_per_seat", "buildout": "dcfc40", "priority": 16, "scenario": "normal_day",
                    "seeds": [686364201590009433], "params": {"deploy_peak_fraction": 0.90, "bay_activation_per_seat": 1}}
    rc, err = db.file(M0743)
    assert rc != 0 and "0743 P" in err


def test_0743_refuses_a_body_it_was_not_written_against(db):
    db.val(f"""CREATE OR REPLACE FUNCTION ottoq.ottoq_activate_due_bay_reservations(p_sim_run_id uuid, p_depot_id uuid,
                                                                                   p_clock timestamp with time zone)
               RETURNS integer LANGUAGE sql AS $$ SELECT 0 $$""")
    rc, err = db.file(M0743)
    assert rc != 0 and "0743 P1" in err
    assert db.val("SELECT count(*) FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_activation_per_seat'") == "0"


def test_at_the_default_the_call_is_all_or_nothing_as_before(db):
    _apply(db)
    a, b = _a_held_car_and_a_ready_one(db)
    assert _activate(db) == 0
    assert _state(db, b) == "staged_awaiting_service STG-1"
    assert _bay(db, "WSH-2") == "- -"
    assert db.val("SELECT count(*) FROM public.test_bay_events WHERE event_type = 'ottoq.bay_reservation_seat_refused'") == "0"


def test_with_the_dial_the_held_car_waits_and_the_other_is_seated(db):
    _apply(db)
    a, b = _a_held_car_and_a_ready_one(db)
    _dial(db, 1)
    assert _activate(db) == 1
    assert _state(db, b) == "in_wash_bay WSH-2"
    assert _state(db, a) == "charge_complete_holding CHG-1"          # left where the arm holds it
    assert _bay(db, "WSH-1") == "- -"                                # its bay neither taken nor reserved
    assert db.val(f"SELECT state FROM public.ottoq_stall_bookings WHERE vehicle_id = '{a}'") == "held"
    assert db.val("SELECT count(*) FROM public.test_bay_events WHERE event_type = 'ottoq.bay_reservation_seat_refused'") == "0"
    # the next tick: the world step has cleared the finished demate (public.ottoq_release_expired_tethers, at <= its time,
    # as the interlock reads it), and the calendar seats the car straight from its charger
    t5 = "2026-10-17 13:05:00+00"
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_current = '{t5}' WHERE sim_run_id = '{RUN}'")
    _release_arm(db, a)
    assert _activate(db, t5) == 1
    assert _state(db, a) == "in_wash_bay WSH-1"
    assert _bay(db, "CHG-1") == "- -"


def test_with_the_dial_a_spent_tether_nothing_has_cleared_costs_that_seat_only(db):
    """Past its time but not yet cleared, a tether still pins the old stall: sync_stall_occupancy keeps a stall the tether
    names, so the move would give the car two stalls and the one-stall index refuses it. Before 0743 that refusal cost
    every seat in the call; with the dial it costs this one, and says so."""
    _apply(db)
    a, b = _a_held_car_and_a_ready_one(db)
    _dial(db, 1)
    t5 = "2026-10-17 13:05:00+00"
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_current = '{t5}' WHERE sim_run_id = '{RUN}'")
    assert _activate(db, t5) == 1                                    # B seated; A, its arm spent at 13:03, refused
    assert _state(db, b) == "in_wash_bay WSH-2"
    assert _state(db, a) == "charge_complete_holding CHG-1"
    assert _bay(db, "WSH-1") == "- -" and _bay(db, "CHG-1") == "car-A -"
    ev = db.json("""SELECT jsonb_agg(payload) FROM public.test_bay_events
                     WHERE event_type = 'ottoq.bay_reservation_seat_refused'""")
    assert len(ev) == 1 and [r["vehicle_id"] for r in ev[0]["refused"]] == [a]
    assert ev[0]["refused"][0]["sqlstate"] == "23505"                # unique_violation: idx_stalls_one_vehicle_per_stall


def _a_refusal_for(d, car):
    """Any error a seat can raise: this one refuses to move one car."""
    d.val(f"""CREATE FUNCTION public.test_refuse_one() RETURNS trigger LANGUAGE plpgsql AS $$
              BEGIN
                IF NEW.id = '{car}' AND OLD.current_stall_id IS DISTINCT FROM NEW.current_stall_id THEN
                  RAISE EXCEPTION 'test: this car cannot move' USING ERRCODE = 'P0001';
                END IF;
                RETURN NEW;
              END $$""")
    d.val("""CREATE TRIGGER test_refuse_one BEFORE UPDATE ON public.vehicles FOR EACH ROW
             EXECUTE FUNCTION public.test_refuse_one()""")


def _two_ready_cars_one_refused(d):
    _world(d)
    b = _car(d, "car-B", "staged_awaiting_service", "STG-1")
    c = _car(d, "car-C", "staged_awaiting_service", "STG-2")
    _hold(d, b, "WSH-2")
    _hold(d, c, "WSH-3")
    _a_refusal_for(d, c)
    return b, c


def test_with_the_dial_one_refused_seat_costs_that_seat_only(db):
    _apply(db)
    b, c = _two_ready_cars_one_refused(db)
    _dial(db, 1)
    assert _activate(db) == 1
    assert _state(db, b) == "in_wash_bay WSH-2"
    assert _state(db, c) == "staged_awaiting_service STG-2"
    assert _bay(db, "WSH-3") == "- -"                                # its stall reservation undone with the seat
    assert db.val(f"SELECT state FROM public.ottoq_stall_bookings WHERE vehicle_id = '{c}'") == "held"
    ev = db.json("""SELECT jsonb_agg(payload) FROM public.test_bay_events
                     WHERE event_type = 'ottoq.bay_reservation_seat_refused'""")
    assert len(ev) == 1 and ev[0]["seated_total"] == 1 and len(ev[0]["refused"]) == 1
    r = ev[0]["refused"][0]
    assert r["vehicle_id"] == c and r["stall_id"] == _id("WSH-3") and r["sqlstate"] == "P0001"
    assert "this car cannot move" in r["message"]
    assert db.val("SELECT string_agg(verb, ',') FROM public.test_bay_commands") == "enter_wash"


def test_at_the_default_the_same_refusal_costs_every_seat(db):
    _apply(db)
    b, c = _two_ready_cars_one_refused(db)
    assert _activate(db) == 0
    assert _state(db, b) == "staged_awaiting_service STG-1"
    assert _bay(db, "WSH-2") == "- -"
    assert db.val("SELECT count(*) FROM public.test_bay_commands") == "0"


def test_the_pre_image_puts_the_live_body_back(db):
    _apply(db)
    db.val("""DO $$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0743_pre'); END $$""")
    assert _md5(db, ACT) == LIVE[ACT]
