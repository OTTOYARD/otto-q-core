"""db/migrations/0750, EXECUTED: every bay seat ends in its itinerary leg and its service record.

WHY THIS EXISTS. An SDR is issued when an itinerary leg turns done, and a bay leg turned done at the bay exit only if the
seat had opened it. The decide seats most bay cars through a command, the twin's confirm walk names no leg, and so on the
twin depot's runs since 2026-10-16 SDRs covered 10.7% of completed washes, 17.7% of details and 31.7% of service-bay
jobs, while the planned legs stayed planned until the car deployed and were then skipped (G464, db/checks/0454). 0750's
public.ottoq_close_bay_seat_legs, called at the bay exit, closes them. Every claim in 0750's header about it is executed
here, on the scratch PostgreSQL, against the function exactly as 0750 writes it, through the live leg helpers, the live
leg trigger and the live SDR emitter (tests/fixtures/bay_exit_leg_stub.sql, md5 asserted):
  - at the dial's default nothing is closed or recorded;
  - a walk-in wash closes the wash leg the planner tagged with the wash, with the seat's start and the work's end, its
    stall and its deviation, and the booking that covered the seat learns the leg, so the SDR names the seat and the
    booking;
  - a seat with no planned leg records one of its bay's type, tagged with its first credited bay service, and closes it;
  - a seat the service flow already closed a leg for is not recorded twice, and the same exit called twice records once;
  - a detail that did the wash too closes both legs; a service seat closes the leg of each service it credited, and not
    the leg of a service it did not;
  - with no active itinerary nothing is recorded and none is created; a seat never starts after its end;
  - a booking that already names a leg, or stands in another stall, is left alone;
  - public.ottoq_bay_seat_record_coverage counts each closed seat against a done bay leg and a bay SDR inside it;
  - no API role but service_role can call either function.
The service flow's patch is proven on its live body by 0750's V1 at apply, and the whole path on live by its V3.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import subprocess
import sys
import tempfile
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "bay_exit_leg_stub.sql")
M0750 = os.path.join(ROOT, "db", "migrations", "0750_every_bay_seat_ends_in_its_leg_and_its_service_record.sql")
DEPOT = base.DEPOT
RUN = "a0000000-0000-0000-0000-000000000750"
T = "2026-09-01 15:00:00+00"
LIVE = {"ottoq_itin_leg_close": "6c33d450e023f83882cbb95f0f4b150f", "ottoq_itin_leg_open": "69effd4b79c76a99b2cb019410172164",
        "ottoq_trg_leg_done_sdr": "8aa4c329836bdb7e0588defe75404498", "ottoq_emit_sdr": "25e9cbb1a3040668fa47125dd43d02c3"}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0750-{name}"))


def _functions_sql():
    """0750's dial and its two functions, exactly as the migration writes them."""
    with open(M0750) as f:
        text = f.read()
    return text[text.index("-- ── (a) the dial ──"):text.index("-- ── (c) STEP 1 of the service flow ──")]


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_bxt_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
            f.write(_functions_sql())
            path = f.name
        try:
            rc, err = d.file(path)
        finally:
            os.remove(path)
        assert rc == 0, f"0750's functions did not create: {err}"
        d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_start, sim_clock_current)
                  VALUES ('{RUN}', '{DEPOT}', 'running', '{T}'::timestamptz - interval '4 hours',
                          '{T}'::timestamptz - interval '4 hours', '{T}')""")
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_bx_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _dial(d, value=1):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{RUN}', 'bay_exit_closes_its_leg', {value}, 'test', now())
              ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value""")


def _car(d, name, itinerary=True):
    vid = _id(name)
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, display_name, current_state, last_state_change,
                                           vehicle_class_code)
              VALUES ('{vid}', '{DEPOT}', 'autonomous', '{name}', 'in_wash_bay', '{T}', 'robotaxi')""")
    if itinerary:
        d.val(f"""INSERT INTO public.ottoq_vehicle_itineraries (itinerary_id, sim_run_id, depot_id, vehicle_id, created_by,
                                                                sim_created_at)
                  VALUES ('{_id(name + '-itin')}', '{RUN}', '{DEPOT}', '{vid}', 'flow_contract_m4',
                          '{T}'::timestamptz - interval '3 hours')""")
    return vid


def _stall(d, code, kind="wash_bay"):
    sid = _id(code)
    d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_type, stall_code, display_name)
              VALUES ('{sid}', '{DEPOT}', '{kind}', '{code}', '{code}') ON CONFLICT (id) DO NOTHING""")
    return sid


def _leg(d, car, seq, leg_type, atom, status="planned", start_min=60, minutes=10):
    lid = _id(f"{car}-leg-{seq}")
    d.val(f"""INSERT INTO public.ottoq_itinerary_legs (leg_id, itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
                                                       planned_start_sim, planned_end_sim, planned_duration_s,
                                                       duration_basis, status)
              VALUES ('{lid}', (SELECT itinerary_id FROM public.ottoq_vehicle_itineraries WHERE vehicle_id = '{car}'),
                      '{RUN}', '{car}', {seq}, '{leg_type}',
                      '{T}'::timestamptz + interval '{start_min} minutes',
                      '{T}'::timestamptz + interval '{start_min + minutes} minutes', {minutes * 60},
                      jsonb_build_object('kind', 'flow_contract', 'atom', {f"'{atom}'" if atom else 'NULL'}), '{status}')""")
    return lid


def _booking(d, car, stall, purpose, start_min, minutes, leg=None, state="active"):
    bid = _id(f"{car}-{stall}-{start_min}")
    d.val(f"""INSERT INTO public.ottoq_stall_bookings (booking_id, sim_run_id, stall_id, vehicle_id, leg_id, purpose,
                                                       during, state, booked_at, booked_by, source)
              VALUES ('{bid}', '{RUN}', '{stall}', '{car}', {f"'{leg}'" if leg else 'NULL'}, '{purpose}',
                      tstzrange('{T}'::timestamptz + interval '{start_min} minutes',
                                '{T}'::timestamptz + interval '{start_min + minutes} minutes', '[)'),
                      '{state}', now(), 'otto_q_enacted', 'needs_card')""")
    return bid


def _exit(d, car, state, seat_min, end_min, stall, credited):
    arr = "ARRAY[" + ", ".join(f"'{c}'" for c in credited) + "]::text[]"
    stall_sql = f"'{stall}'" if stall else "NULL"
    return int(d.val(f"""SELECT public.ottoq_close_bay_seat_legs('{RUN}', '{DEPOT}', '{car}', '{state}',
                          '{T}'::timestamptz + interval '{seat_min} minutes',
                          '{T}'::timestamptz + interval '{end_min} minutes', {stall_sql}, {arr})"""))


def _at(minutes):
    return f"('{T}'::timestamptz + interval '{minutes} minutes')"


def test_the_live_bodies_and_the_dial(db):
    for fn, md5 in LIVE.items():
        assert db.val(f"SELECT md5(prosrc) FROM pg_proc WHERE proname = '{fn}'") == md5, fn
    assert db.val("""SELECT default_value || '/' || min_value || '/' || max_value || '/' || COALESCE(agent_writable, false)
                       FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_exit_closes_its_leg'""") == "0/0/1/false"


def test_at_the_default_nothing_is_closed_or_recorded(db):
    car, bay = _car(db, "a"), _stall(db, "WSH-01")
    leg = _leg(db, car, 1, "wash", "exterior_wash")
    _booking(db, car, bay, "wash", 0, 9)
    assert _exit(db, car, "in_wash_bay", 0, 5, bay, ["exterior_wash"]) == 0
    assert db.val(f"SELECT status FROM public.ottoq_itinerary_legs WHERE leg_id = '{leg}'") == "planned"
    assert db.val("SELECT count(*) FROM public.ottoq_service_detail_records") == "0"
    assert db.val("SELECT count(*) FROM public.ottoq_itinerary_legs") == "1"


def test_a_walk_in_wash_closes_its_planned_leg_and_the_record_names_the_seat(db):
    _dial(db)
    car, bay = _car(db, "a"), _stall(db, "WSH-01")
    leg = _leg(db, car, 1, "wash", "exterior_wash", start_min=60, minutes=10)
    bk = _booking(db, car, bay, "wash", 0, 9)
    assert _exit(db, car, "in_wash_bay", 0, 5, bay, ["exterior_wash", "sensor_clean"]) == 1
    row = db.val(f"""SELECT status || '|' || (actual_start_sim = {_at(0)}) || '|' || (actual_end_sim = {_at(5)}) || '|'
                            || (to_stall_id = '{bay}') || '|' || deviation_s || '|' || (duration_basis ->> 'closed_at_bay_exit')
                       FROM public.ottoq_itinerary_legs WHERE leg_id = '{leg}'""")
    assert row == "done|true|true|true|-3900|0750", row          # 5 minutes in against a plan ending at 70
    assert db.val(f"SELECT leg_id || '|' || leg_source FROM public.ottoq_stall_bookings WHERE booking_id = '{bk}'") \
        == f"{leg}|bay_exit_0750"
    sdr = db.val(f"""SELECT operation_code || '|' || (started_at = {_at(0)}) || '|' || (ended_at = {_at(5)}) || '|'
                            || booking_id || '|' || stall_id || '|' || duration_min || '|' || source_kind || '|' || data_source
                            || '|' || asset_class_code
                       FROM public.ottoq_service_detail_records WHERE leg_id = '{leg}'""")
    assert sdr == f"wash|true|true|{bk}|{bay}|5.00|itinerary_leg|twin|robotaxi", sdr
    assert db.val("SELECT count(*) FROM public.ottoq_events WHERE event_type = 'sdr_issued'") == "1"


def test_a_seat_with_no_planned_leg_records_one_of_its_bays_type(db):
    _dial(db)
    car, bay = _car(db, "a"), _stall(db, "WSH-02")
    _leg(db, car, 1, "charge_dcfc", None, status="done")
    _leg(db, car, 2, "inspect", "readiness_check")
    bk = _booking(db, car, bay, "detail", 30, 25)
    assert _exit(db, car, "in_detail_bay", 30, 47, bay, ["interior_tidy", "interior_deep_clean"]) == 1
    row = db.val("""SELECT seq || '|' || leg_type || '|' || status || '|' || (duration_basis ->> 'kind') || '|'
                           || (duration_basis ->> 'atom') || '|' || deviation_s || '|' || planned_duration_s
                      FROM public.ottoq_itinerary_legs WHERE leg_type = 'detail'""")
    assert row == "3|detail|done|bay_seat|interior_deep_clean|0|1020", row
    assert db.val("SELECT status FROM public.ottoq_itinerary_legs WHERE leg_type = 'inspect'") == "planned"
    assert db.val(f"""SELECT operation_code || '|' || duration_min || '|' || booking_id FROM public.ottoq_service_detail_records""") \
        == f"detail|17.00|{bk}"


def test_a_leg_the_service_flow_closed_is_not_recorded_twice(db):
    """The service flow's own seats open their leg at entry and close it at the exit before 0750's call."""
    _dial(db)
    car, bay = _car(db, "a"), _stall(db, "WSH-03")
    _leg(db, car, 1, "wash", "exterior_wash")
    _booking(db, car, bay, "wash", 0, 9)
    assert db.val(f"""SELECT public.ottoq_itin_leg_open('{RUN}', '{DEPOT}', '{car}', {_at(0)}, 'wash', '{bay}', {_at(9)},
                                                       '{{"kind": "distribution"}}'::jsonb, 'twin_service_flow') IS NOT NULL""") == "t"
    assert db.val(f"SELECT public.ottoq_itin_leg_close('{RUN}', '{car}', ARRAY['wash','detail','service'], {_at(6)})") == "1"
    assert _exit(db, car, "in_wash_bay", 0, 6, bay, ["exterior_wash"]) == 0
    assert db.val("SELECT count(*) FROM public.ottoq_service_detail_records") == "1"
    assert db.val("SELECT count(*) FROM public.ottoq_itinerary_legs") == "1"
    # and a seat 0750 recorded is recorded once however often its exit is read
    car2 = _car(db, "b")
    assert _exit(db, car2, "in_wash_bay", 20, 25, bay, ["exterior_wash"]) == 1
    assert _exit(db, car2, "in_wash_bay", 20, 25, bay, ["exterior_wash"]) == 0
    assert db.val(f"SELECT count(*) FROM public.ottoq_service_detail_records WHERE vehicle_id = '{car2}'") == "1"


def test_a_detail_that_did_the_wash_closes_both_legs(db):
    _dial(db)
    car, bay = _car(db, "a"), _stall(db, "WSH-01")
    wash = _leg(db, car, 1, "wash", "exterior_wash", start_min=60)
    detail = _leg(db, car, 2, "detail", "interior_deep_clean", start_min=70)
    assert _exit(db, car, "in_detail_bay", 0, 18, bay, ["interior_deep_clean", "exterior_wash", "interior_tidy"]) == 2
    assert db.val(f"""SELECT string_agg(l.leg_type || ':' || l.status || ':' || d.operation_code, ',' ORDER BY l.seq)
                        FROM public.ottoq_itinerary_legs l JOIN public.ottoq_service_detail_records d USING (leg_id)
                       WHERE l.leg_id IN ('{wash}', '{detail}')""") == "wash:done:wash,detail:done:detail"


def test_a_service_seat_closes_the_leg_of_each_service_it_credited_and_no_other(db):
    _dial(db)
    car, bay = _car(db, "a"), _stall(db, "SVC-01", "service_bay")
    pm = _leg(db, car, 1, "service", "mechanical_pm", start_min=60, minutes=40)
    cal = _leg(db, car, 2, "service", "sensor_calibration", start_min=100, minutes=60)
    cos = _leg(db, car, 3, "service", "cosmetic_repair", start_min=160, minutes=60)
    assert _exit(db, car, "in_service_bay", 0, 45, bay, ["mechanical_pm", "sensor_calibration"]) == 2
    assert db.val(f"""SELECT string_agg(leg_id::text || ':' || status, ',' ORDER BY seq) FROM public.ottoq_itinerary_legs""") \
        == f"{pm}:done,{cal}:done,{cos}:planned"
    assert db.val("SELECT string_agg(operation_code, ',') FROM public.ottoq_service_detail_records") \
        == "generic_service,generic_service"


def test_without_an_active_itinerary_nothing_is_recorded_and_none_is_created(db):
    _dial(db)
    car, bay = _car(db, "a", itinerary=False), _stall(db, "WSH-01")
    assert _exit(db, car, "in_wash_bay", 0, 5, bay, ["exterior_wash"]) == 0
    assert db.val("SELECT count(*) FROM public.ottoq_vehicle_itineraries") == "0"
    assert db.val("SELECT count(*) FROM public.ottoq_itinerary_legs") == "0"
    # nor for a run the dial is not on in, a car the seat is not, or a state that is not a bay
    car2 = _car(db, "b")
    assert _exit(db, car2, "staged_awaiting_service", 0, 5, bay, ["exterior_wash"]) == 0
    assert db.val(f"""SELECT public.ottoq_close_bay_seat_legs(NULL, '{DEPOT}', '{car2}', 'in_wash_bay', {_at(0)}, {_at(5)},
                                                              NULL, ARRAY['exterior_wash'])""") == "0"


def test_a_seat_never_starts_after_its_end(db):
    _dial(db)
    car, bay = _car(db, "a"), _stall(db, "WSH-01")
    assert _exit(db, car, "in_wash_bay", 10, 4, bay, ["exterior_wash"]) == 1
    assert db.val(f"""SELECT (actual_start_sim = {_at(4)}) || '|' || (actual_end_sim = {_at(4)})
                        FROM public.ottoq_itinerary_legs""") == "true|true"
    assert db.val("SELECT duration_min FROM public.ottoq_service_detail_records") == "0.00"


def test_a_booking_that_names_a_leg_or_stands_elsewhere_is_left_alone(db):
    _dial(db)
    car, bay, other = _car(db, "a"), _stall(db, "WSH-01"), _stall(db, "WSH-02")
    leg = _leg(db, car, 1, "wash", "exterior_wash")
    elsewhere = _booking(db, car, other, "wash", 0, 9)
    assert _exit(db, car, "in_wash_bay", 0, 5, bay, ["exterior_wash"]) == 1
    assert db.val(f"SELECT leg_id IS NULL FROM public.ottoq_stall_bookings WHERE booking_id = '{elsewhere}'") == "t"
    assert db.val(f"SELECT booking_id IS NULL FROM public.ottoq_service_detail_records WHERE leg_id = '{leg}'") == "t"
    # a booking already naming another leg keeps it
    car2 = _car(db, "b")
    named = _booking(db, car2, bay, "wash", 30, 9, leg=_id("some-other-leg"))
    assert _exit(db, car2, "in_wash_bay", 30, 35, bay, ["exterior_wash"]) == 1
    assert db.val(f"SELECT leg_id FROM public.ottoq_stall_bookings WHERE booking_id = '{named}'") == _id("some-other-leg")


def test_the_census_counts_each_seat_against_a_done_leg_and_a_record(db):
    _dial(db)
    a, b, c = _car(db, "a"), _car(db, "b"), _car(db, "c")
    bay, svc = _stall(db, "WSH-01"), _stall(db, "SVC-01", "service_bay")

    def seat(car, bay_state, enter_min, leave_min):
        for frm, to, at in (("staged_awaiting_service", bay_state, enter_min), (bay_state, "staged_awaiting_service", leave_min)):
            db.val(f"""INSERT INTO public.ottoq_events (event_type, entity_type, entity_id, sim_run_id, sim_clock_at, payload)
                       VALUES ('vehicle.state_changed', 'vehicle', '{car}', '{RUN}', {_at(at)},
                               jsonb_build_object('diff', jsonb_build_object(
                                 'current_state', jsonb_build_object('from', '{frm}', 'to', '{to}'),
                                 'last_state_change', jsonb_build_object('to', {_at(at)}))))""")
    seat(a, "in_wash_bay", 0, 5)          # recorded by 0750
    seat(b, "in_wash_bay", 10, 15)        # not recorded (the dial was off for it)
    seat(c, "in_service_bay", 0, 40)      # recorded by 0750
    seat(a, "in_wash_bay", 50, 60)        # a second seat of the same car, not recorded
    assert _exit(db, a, "in_wash_bay", 0, 4, bay, ["exterior_wash"]) == 1
    assert _exit(db, c, "in_service_bay", 0, 38, svc, ["mechanical_pm"]) == 1
    rows = db.val(f"""SELECT string_agg(bay || ':' || seats || ':' || with_done_leg || ':' || with_sdr, ',' ORDER BY bay)
                        FROM public.ottoq_bay_seat_record_coverage('{RUN}')""")
    assert rows == "in_service_bay:1:1:1,in_wash_bay:3:1:1", rows


def test_no_api_role_but_service_role_calls_either_function(db):
    for fn in ("public.ottoq_close_bay_seat_legs(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,uuid,text[])",
               "public.ottoq_bay_seat_record_coverage(uuid)"):
        for role, allowed in (("anon", "f"), ("authenticated", "f"), ("service_role", "t")):
            assert db.val(f"SELECT has_function_privilege('{role}', '{fn}', 'EXECUTE')") == allowed, (fn, role)
