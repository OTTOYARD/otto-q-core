"""db/migrations/0785, EXECUTED: a car on a charger comes to its bay when the charge it is on ends.

WHY THIS EXISTS. The bay yield (0553) frees a bay for a car waiting now when every hold in the way belongs to a car that
cannot be there before the waiting car would finish. For a car on a charger it asked ottoq.ottoq_bay_hold_car_eta, which
answered with the latest planned end over every open charge leg of the car. At an all-fast-charger depot the itinerary
still plans a standard charge that never runs (G459), so a car minutes from full read as hours away: on run 763734d4 car
7ec698b8, at 94% on a fast charger with its leg ending in 13 minutes, lost its service-bay hold at 13:40:58 to a car
waiting now, found no slot and waited eight hours with its fault repair owed (G505; db/checks/0473 §8 (f)).
Every claim in 0785's header that a test can execute is executed here, on the scratch PostgreSQL, against the live
bodies (tests/fixtures/bay_hold_yield_stub.sql, md5 asserted as read on 2026-10-25):
  - before 0785, the car on a fast charger with a phantom standard leg reads as due when that leg ends, and its hold
    gives way to a car waiting now; with the calendar full behind that ETA, the hold is released;
  - 0785 applies, its checks run (V2 and V3 over the run's cars), it leaves the body it was written to leave, refuses a
    body it was not written against, and refuses a second apply;
  - at the dial's default nothing changes;
  - with the dial, the car is due when the charge it is on ends, and keeps its hold; a leg of the other kind is never
    read, even when its planned start has passed;
  - with the dial, a car whose charge genuinely runs past the waiting car still gives way, as 0553 meant; without a
    begun leg the session's own pace answers, as before; with no pace, no ETA, and no yield;
  - the pre-image puts the live body back.
A module template carries the stubs, and each test clones it. It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)
import test_bay_activation_per_seat_sql as t43  # noqa: E402  (the bay fixture and the admin helper)

ROOT = base.ROOT
M0785 = os.path.join(ROOT, "db", "migrations",
                     "0785_a_car_on_a_charger_comes_to_its_bay_when_the_charge_it_is_on_ends.sql")
NAME = "0785_a_car_on_a_charger_comes_to_its_bay_when_the_charge_it_is_on_ends"
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "bay_hold_yield_stub.sql")
RUN = "a0000000-0000-0000-0000-000000000785"
T = "2026-10-25 13:40:00+00"
DEPOT = base.DEPOT

ETA = "ottoq.ottoq_bay_hold_car_eta(uuid,uuid,timestamp with time zone,numeric)"
YIELD = "ottoq.ottoq_yield_bay_holds(uuid,uuid,text,timestamp with time zone,timestamp with time zone,uuid)"
# the live catalog, read 2026-10-25 22:49 UTC (md5 of prosrc), both as 0553 left them
LIVE = {ETA: "12670129429dc811e86eabb69ee38456", YIELD: "fd2c5cfefaf6a469b94ec596d521b7a7"}
# and as 0785 leaves the ETA (md5 of prosrc), to read back on live after the apply
AFTER_0785 = "f0d4f149f9c804615c8889e5885f4540"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0785-{name}"))


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_bhe_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    t43._admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, t43.FIXTURE, FIXTURE):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        yield name
    finally:
        t43._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_bh_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    t43._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        t43._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply(d):
    rc, err = d.file(M0785)
    assert rc == 0, f"0785 did not apply: {err}"


def _md5(d, fn):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')")


def _at(minutes):
    return f"'{T}'::timestamptz + interval '{minutes} minutes'"


def _world(d):
    """The twin depot's run at clock T; one service bay, a fast and a standard charger, staging."""
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_start, sim_clock_current)
              VALUES ('{RUN}', '{DEPOT}', 'running', {_at(-40)}, {_at(-40)}, '{T}')""")
    for i, (code, kind) in enumerate([("SVC-1", "service_bay"), ("CHG-1", "dcfc"), ("CHG-2", "l2"),
                                       ("STG-1", "staging"), ("STG-2", "staging")]):
        d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, display_name, status, distance_from_entrance)
                  VALUES ('{_id(code)}', '{DEPOT}', '{code}', '{kind}', '{code}', 'available', {i})""")


def _car(d, name, state, stall, soc):
    vid = _id(name)
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, display_name, current_state, current_stall_id,
                                           current_soc, last_state_change, config)
              VALUES ('{vid}', '{DEPOT}', 'autonomous', '{name}', '{state}', '{_id(stall)}', {soc},
                      {_at(-10)}, '{{}}')""")
    d.val(f"UPDATE public.stalls SET current_vehicle_id = '{vid}', status = 'occupied' WHERE id = '{_id(stall)}'")
    return vid


def _leg(d, car, kind, status, start_min, end_min, began=None):
    began_sql = "NULL" if began is None else _at(began)
    d.val(f"""INSERT INTO public.ottoq_itinerary_legs (sim_run_id, vehicle_id, seq, leg_type, status, planned_start_sim,
                                                       planned_end_sim, actual_start_sim)
              VALUES ('{RUN}', '{car}', 1, '{kind}', '{status}', {_at(start_min)}, {_at(end_min)}, {began_sql})""")


def _session(d, car, started_min, soc_start):
    d.val(f"""INSERT INTO public.ocpp_sessions (vehicle_id, sim_run_id, status, started_at, soc_start)
              VALUES ('{car}', '{RUN}', 'active', {_at(started_min)}, {soc_start})""")


def _hold(d, car, bay, start_min, minutes, purpose="service"):
    return d.val(f"""INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state,
                                                              booked_at, booked_by, booked_at_sim)
                     VALUES ('{RUN}', '{_id(bay)}', '{car}', '{purpose}',
                             tstzrange({_at(start_min)}, {_at(start_min + minutes)}, '[)'), 'held',
                             {_at(-40)}, 'otto_q', {_at(-40)})
                     RETURNING booking_id""")


def _the_depot_of_run_763734d4(d, dcfc_end=13, phantom_start=520, phantom_end=571):
    """H holds the service bay 19 minutes from now and is on a fast charger at 94%, its leg ending dcfc_end minutes from
    now; its plan also carries a standard charge from phantom_start to phantom_end. W is staged and waits for the bay
    now, for a 40-minute job."""
    _world(d)
    h = _car(d, "car-H", "charging_dcfc", "CHG-1", 94)
    w = _car(d, "car-W", "staged_awaiting_service", "STG-1", 100)
    _leg(d, h, "charge_dcfc", "active", -9, dcfc_end, began=-9)
    _leg(d, h, "charge_l2", "planned", phantom_start, phantom_end)
    _session(d, h, -9, 86)
    booking = _hold(d, h, "SVC-1", 19, 89)
    return h, w, booking


def _eta(d, car, clock=None):
    clock = clock or T
    return d.val(f"SELECT ottoq.ottoq_bay_hold_car_eta('{RUN}', '{car}', '{clock}', 3)")


def _at_text(d, minutes):
    return d.val(f"SELECT ({_at(minutes)})::text")


def _yield(d, w, minutes=40):
    return int(d.val(f"SELECT ottoq.ottoq_yield_bay_holds('{RUN}', '{DEPOT}', 'service_bay', '{T}', {_at(minutes)}, '{w}')"))


def _hold_now(d, booking):
    return d.val(f"""SELECT state || ' ' || lower(during)::text || ' ' || COALESCE(release_reason, '-')
                       FROM public.ottoq_stall_bookings WHERE booking_id = '{booking}'""")


def _log(d):
    return d.val("""SELECT COALESCE(string_agg(action || ':' || reason || ':' || blocked_by, ',' ORDER BY id), '-')
                      FROM public.bay_reservation_reconcile_2026_08_02""")


def _dial(d, value):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{RUN}', 'bay_hold_eta_reads_charge', {value}, 'test', now())""")


def test_the_fixture_is_the_live_bodies(db):
    for fn, md5 in LIVE.items():
        assert _md5(db, fn) == md5, fn


def test_before_0785_a_phantom_leg_makes_a_car_minutes_from_full_give_its_bay_away(db):
    h, w, booking = _the_depot_of_run_763734d4(db)
    assert _eta(db, h) == _at_text(db, 574)                       # the standard leg's end (571) and the taxi, 9.5 hours
    assert _yield(db, w) == 1
    assert _hold_now(db, booking) == f"held {_at_text(db, 574)} -"  # moved nine and a half hours out
    assert _log(db) == "deferred:yielded_to_a_car_waiting_now:yield:charging_dcfc"


def test_before_0785_on_a_full_calendar_the_hold_is_released(db):
    h, w, booking = _the_depot_of_run_763734d4(db)
    blocker = _car(db, "car-B", "staged_awaiting_service", "STG-2", 100)
    _hold(db, blocker, "SVC-1", 500, 400)                         # the bay is held from 8:20 to 15:00 from now
    assert _yield(db, w) == 1
    assert _hold_now(db, booking).startswith("released ") and _hold_now(db, booking).endswith(" replanned_no_window")
    assert _log(db) == "released:replanned_no_window:yield:charging_dcfc"


def test_0785_applies_and_a_second_apply_is_refused(db):
    _the_depot_of_run_763734d4(db)
    _apply(db)
    assert _md5(db, YIELD) == LIVE[YIELD]                         # the yield itself is not touched
    assert _md5(db, ETA) == AFTER_0785
    assert db.val(f"""SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage
                       WHERE name = '{NAME}'""") == "falsefalse"
    assert db.val("""SELECT default_value::text || min_value::text || max_value::text || agent_writable::text
                       FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_hold_eta_reads_charge'""") == "001false"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0785_pre'") == "1"
    assert db.val("SELECT count(*) FROM public.ottoq_policy_params WHERE param_key = 'bay_hold_eta_reads_charge'") == "0"
    rc, err = db.file(M0785)
    assert rc != 0 and "0785 P1" in err


def test_0785_refuses_a_body_it_was_not_written_against(db):
    db.val(f"""DO $x$ BEGIN
                 EXECUTE replace(pg_get_functiondef('{ETA}'::regprocedure), '-- 0553 (G283)', '-- 0553  (G283)');
               END $x$""")
    rc, err = db.file(M0785)
    assert rc != 0 and "0785 P1" in err and "md5 12670129" in err
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0785%'") == "0"


def test_at_the_default_nothing_changes(db):
    h, w, booking = _the_depot_of_run_763734d4(db)
    _apply(db)
    assert _eta(db, h) == _at_text(db, 574)
    assert _yield(db, w) == 1
    assert _hold_now(db, booking) == f"held {_at_text(db, 574)} -"


def test_with_the_dial_the_car_is_due_when_its_charge_ends_and_keeps_its_hold(db):
    h, w, booking = _the_depot_of_run_763734d4(db)
    _apply(db)
    _dial(db, 1)
    assert _eta(db, h) == _at_text(db, 16)                        # its fast charge ends at 13, and the taxi
    assert _yield(db, w) == 0                                     # 16 is before the waiting car would finish at 40
    assert _hold_now(db, booking) == f"held {_at_text(db, 19)} -"
    assert _log(db) == "-"


def test_with_the_dial_a_leg_of_the_other_kind_is_never_read_even_once_its_start_has_passed(db):
    # the flow contract re-times the standard leg forward; here its planned start has passed and it ends in 6 hours
    h, w, booking = _the_depot_of_run_763734d4(db, phantom_start=-5, phantom_end=360)
    _apply(db)
    assert _eta(db, h) == _at_text(db, 363)                       # the default reads the standard leg
    _dial(db, 1)
    assert _eta(db, h) == _at_text(db, 16)
    assert _yield(db, w) == 0


def test_with_the_dial_a_charge_that_runs_past_the_waiting_car_still_gives_way(db):
    h, w, booking = _the_depot_of_run_763734d4(db, dcfc_end=60)
    _apply(db)
    _dial(db, 1)
    assert _eta(db, h) == _at_text(db, 63)
    assert _yield(db, w) == 1                                     # 0553's rule, read on the charge the car is on
    assert _hold_now(db, booking) == f"held {_at_text(db, 63)} -"
    assert _log(db) == "deferred:yielded_to_a_car_waiting_now:yield:charging_dcfc"


def test_with_the_dial_and_no_begun_leg_the_sessions_pace_answers(db):
    _world(db)
    h = _car(db, "car-H", "charging_dcfc", "CHG-1", 94)
    w = _car(db, "car-W", "staged_awaiting_service", "STG-1", 100)
    _leg(db, h, "charge_l2", "planned", 520, 571)                 # only the phantom leg
    _session(db, h, -10, 84)                                      # 10 points in 10 minutes: 5 left to 99
    booking = _hold(db, h, "SVC-1", 19, 89)
    _apply(db)
    assert _eta(db, h) == _at_text(db, 574)                       # the default still reads the phantom leg
    _dial(db, 1)
    assert _eta(db, h) == _at_text(db, 8)
    assert _yield(db, w) == 0
    assert _hold_now(db, booking) == f"held {_at_text(db, 19)} -"


def test_with_the_dial_no_pace_means_no_eta_and_no_yield(db):
    _world(db)
    h = _car(db, "car-H", "charging_dcfc", "CHG-1", 94)
    w = _car(db, "car-W", "staged_awaiting_service", "STG-1", 100)
    _leg(db, h, "charge_l2", "planned", 520, 571)
    _session(db, h, -1, 93.5)                                     # half a point so far: no pace yet
    booking = _hold(db, h, "SVC-1", 19, 89)
    _apply(db)
    _dial(db, 1)
    assert _eta(db, h) == ""                                      # NULL, which never yields a hold
    assert _yield(db, w) == 0
    assert _hold_now(db, booking) == f"held {_at_text(db, 19)} -"


def test_with_the_dial_a_car_on_a_standard_charger_reads_its_standard_leg(db):
    _world(db)
    h = _car(db, "car-H", "charging_l2", "CHG-2", 70)
    _leg(db, h, "charge_l2", "active", -30, 25, began=-30)
    _leg(db, h, "charge_dcfc", "planned", 300, 330)               # a later fast charge it is not on
    _apply(db)
    assert _eta(db, h) == _at_text(db, 333)
    _dial(db, 1)
    assert _eta(db, h) == _at_text(db, 28)


def test_the_pre_image_puts_the_live_body_back(db):
    _the_depot_of_run_763734d4(db)
    _apply(db)
    db.val("""DO $x$ DECLARE r record; BEGIN
                FOR r IN SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0785_pre' LOOP
                  EXECUTE r.definition;
                END LOOP;
              END $x$""")
    assert _md5(db, ETA) == LIVE[ETA]
