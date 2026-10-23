"""db/migrations/0765, EXECUTED: every car that charges on a robotic post is cleaned by the post's arm, however short
the charge and however the car came to charge.

WHY THIS EXISTS. Chase, 2026-10-23, with 0764 on: "cars should be cleaned via overhead arm while they charge always
regardless", while the alert cleanings still occur and are noted. On 3389e651 0764 cleaned every charging car whose
visit had no tidy, but skipped a charge with less than the arm's 5.8-minute cycle left (and 0758 left a needed tidy on
such a charge to a technician), and a car topped off with no visit was never seen by its arm: its visit came only when
the charge ended. 13 of the 14 tidies technicians did by sim 14:31 were on such cars.
Executed here, on the scratch PostgreSQL, over 0764's test world (0758's fixture with 0758 and 0764 applied, the bodies
md5 asserted as read on live) and tests/fixtures/every_charge_cleaned_stub.sql (the live pre-arrival contracts and leg
door, md5 asserted, and a service-list generator that writes the ledger as the live derivation does), with 0765 run
whole:
  - at 0 and at 1 the same world leaves byte-identical visits, legs, itineraries and calls with and without 0765;
  - before 0765, at 2, a short charge is skipped, a needed tidy on one goes to a technician, and a topped-off car has
    no list: the gaps;
  - at 2 a short charge is cleaned by the arm, holds its car past the charge and finishes; a needed tidy on a short
    charge is the arm's; an owner's immediate turnaround on a short charge is recorded once and not held, its needed
    tidy still the arm's, and on a long charge it is cleaned;
  - a topped-off car gets its list once, from the generator with the run and no itinerary planned, and is cleaned
    through the completion step's own pass, its leg on the charge orchestrator's itinerary (or a new one the leg door
    starts), at the post, closed by its id; a car with a list, with a visit, on a standard charger, done charging or
    en route (BACKSTOP 1's, unchanged) is not the backstop's, and nothing happens where the depot's feed is not sim;
  - the routine's leg binds no stall booking;
  - 0765 applies as declared and refuses a second apply, a body it did not read, a database without 0764 and a dial
    not as 0764 left it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)
import test_stall_cabin_robot_sql as arm  # noqa: E402  (0758's fixture, world and helpers)
import test_every_car_cabin_clean_sql as e764  # noqa: E402  (0764's file and premises)

ROOT = base.ROOT
M0765 = os.path.join(ROOT, "db", "migrations",
                     "0765_every_charge_is_cleaned_however_short_and_a_topped_off_car_has_its_visit_as_it_plugs_in.sql")
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "every_charge_cleaned_stub.sql")
DEPOT = base.DEPOT
RUN = arm.RUN
T0 = arm.T0
START, ADVANCE = arm.START, arm.ADVANCE
PREARRIVAL = "ottoq.ottoq_sim_prearrival_contracts(uuid,timestamp with time zone)"
LEG_OPEN = ("public.ottoq_itin_leg_open(uuid,uuid,uuid,timestamp with time zone,text,uuid,timestamp with time zone,"
            "jsonb,text)")
# what 0764 left and what the live engine carries, as read on live on 2026-10-23 (0765's premises)
LIVE = {START: "002247aab125626b56e1424d79cfaa05", ADVANCE: "fb7cde232a1b8311eb2f768c812f4c9a",
        PREARRIVAL: "d612cbeb5cd4f839f988b1451240dd5c", LEG_OPEN: "69effd4b79c76a99b2cb019410172164"}
L0764 = "0764_every_car_that_charges_gets_the_overhead_arms_cabin_clean"
L0765 = "0765_every_charge_is_cleaned_however_short_and_a_topped_off_car_has_its_visit_as_it_plugs_in"
CHARGE = e764.CHARGE
TIDY = arm.TIDY

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0765-{name}"))


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    arm._admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, arm.FIXTURE):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        d.val("""INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
                 VALUES ('0757_a_bay_seat_that_finished_early_is_done', false, false, 'test premise', now())""")
        arm._world(d)
        arm._apply(d)
        d.val("ALTER TABLE public.ottoq_vehicle_itineraries ADD COLUMN visit_id uuid")
        d.val(f"""INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
                  VALUES ('{e764.L0763}', true, true, 'test premise', now())""")
        e764._apply(d)
        rc, err = d.file(FIXTURE)
        assert rc == 0, f"{os.path.basename(FIXTURE)} did not load: {err}"
        yield name
    finally:
        arm._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    arm._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        arm._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply(d):
    rc, err = d.file(M0765)
    assert rc == 0, f"0765 did not apply: {err}"


def _car(d, name, stall, atoms=None, state="charging_dcfc", session="active", itinerary="visit", urgency="standard",
         config=None):
    """A car on a stall with its session; its visit with the given atoms (no visit when atoms is None, as for a car the
    charge orchestrator topped off); and its active itinerary with a charge leg: the visit's ('visit'), the charge
    orchestrator's with no visit ('orchestrator'), or none (None)."""
    vid = _id(name)
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, current_depot_id, category, display_name, current_state,
                                           current_stall_id, current_soc, battery_capacity_kwh, inlet_max_kw,
                                           last_state_change, config)
              VALUES ('{vid}', '{DEPOT}', '{DEPOT}', 'autonomous', '{name}', '{state}', '{arm._id(stall)}', 88, 75, 250,
                      '{T0}'::timestamptz - interval '10 minutes', '{json.dumps(config or {})}')""")
    if session:
        d.val(f"""INSERT INTO public.ocpp_sessions (depot_id, stall_id, vehicle_id, status, started_at, soc_start,
                                                    sim_run_id)
                  VALUES ('{DEPOT}', '{arm._id(stall)}', '{vid}', '{session}', '{T0}'::timestamptz - interval '5 minutes',
                          86, '{RUN}')""")
    visit = None
    if atoms is not None:
        visit = _id(f"visit-{name}")
        d.val(f"""INSERT INTO public.ottoq_visit_needs (visit_id, vehicle_id, sim_run_id, depot_id, arrived_at, visit_key,
                                                        urgency, status, atoms, meta, created_at)
                  VALUES ('{visit}', '{vid}', '{RUN}', '{DEPOT}', '{T0}'::timestamptz - interval '15 minutes', 'v-{name}',
                          '{urgency}', 'open', '{json.dumps(atoms)}'::jsonb, '{{}}', now())""")
    if itinerary:
        itin = _id(f"itin-{name}")
        by = "twin_charge_orchestrator" if itinerary == "orchestrator" else "planner"
        d.val(f"""INSERT INTO public.ottoq_vehicle_itineraries (itinerary_id, vehicle_id, sim_run_id, depot_id, status,
                                                                created_by, sim_created_at, visit_id)
                  VALUES ('{itin}', '{vid}', '{RUN}', '{DEPOT}', 'active', '{by}',
                          '{T0}'::timestamptz - interval '15 minutes',
                          {f"'{visit}'" if itinerary == 'visit' and visit else 'NULL'})""")
        d.val(f"""INSERT INTO public.ottoq_itinerary_legs (itinerary_id, vehicle_id, sim_run_id, seq, leg_type,
                                                           duration_basis, status, to_stall_id)
                  VALUES ('{itin}', '{vid}', '{RUN}', 1, 'charge_dcfc', '{{}}', 'active', '{arm._id(stall)}')""")
    return vid


def _advance(d, clock, left=None):
    """The completion step, in one session so a test can say how much charge is left (the estimate reads it)."""
    pre = f"SET test.charge_left_min = '{left}'; " if left is not None else ""
    rc, out, err = d.run(f"{pre}SELECT twin.ottoq_sim_advance_visit_atoms('{RUN}', '{clock}')")
    assert rc == 0 and "WARNING" not in err, err
    return int(out[-1])


def _prearrival(d, clock=T0, urgency=None, extra=None):
    """The pre-arrival contracts, in one session so a test can say what the generator's list holds."""
    pre = f"SET test.manifest_urgency = '{urgency}'; " if urgency else ""
    if extra is not None:
        pre += f"SET test.manifest_extra = '{json.dumps(extra)}'; "
    rc, out, err = d.run(f"{pre}SELECT ottoq.ottoq_sim_prearrival_contracts('{RUN}', '{clock}')")
    assert rc == 0 and "WARNING" not in err, err
    return int(out[-1])


def _tidies(d, car):
    return d.json(f"""SELECT COALESCE(jsonb_agg(a ORDER BY o), '[]') FROM public.ottoq_visit_needs n,
                              jsonb_array_elements(n.atoms) WITH ORDINALITY AS x(a, o)
                       WHERE n.vehicle_id = '{car}' AND n.status IN ('open', 'in_progress')
                         AND a->>'svc' = 'interior_tidy'""")


def _meta(d, car):
    """The open visit's meta, {} when the car has no open visit."""
    return d.json(f"""SELECT COALESCE((SELECT meta FROM public.ottoq_visit_needs
                                        WHERE vehicle_id = '{car}' AND status IN ('open', 'in_progress')), '{{}}')""")


def _legs(d, car):
    return d.json(f"""SELECT COALESCE(jsonb_agg(to_jsonb(l) ORDER BY l.seq), '[]') FROM public.ottoq_itinerary_legs l
                       WHERE l.vehicle_id = '{car}' AND l.leg_type = 'interior_tidy'""")


def _calls(d, table, car=None):
    where = f" WHERE vehicle_id = '{car}'" if car else ""
    return int(d.val(f"SELECT count(*) FROM public.{table}{where}"))


def _state(d):
    return d.val("""SELECT jsonb_build_object(
                      'visits', (SELECT jsonb_agg(jsonb_build_object('v', vehicle_id, 'k', visit_key, 'atoms', atoms,
                                                                     'meta', meta, 'status', status)
                                                  ORDER BY vehicle_id, visit_key, status)
                                   FROM public.ottoq_visit_needs),
                      'legs', (SELECT jsonb_agg(jsonb_build_object('v', vehicle_id, 'seq', seq, 'type', leg_type,
                                                                   'status', status, 'stall', to_stall_id)
                                                ORDER BY vehicle_id, seq)
                                 FROM public.ottoq_itinerary_legs),
                      'itineraries', (SELECT count(*) FROM public.ottoq_vehicle_itineraries),
                      'manifests', (SELECT jsonb_agg(vehicle_id ORDER BY vehicle_id) FROM public._test_manifests),
                      'plans', (SELECT jsonb_agg(vehicle_id ORDER BY vehicle_id) FROM public._test_plans),
                      'cars', (SELECT jsonb_agg(jsonb_build_object('v', id, 'config', config) ORDER BY id)
                                 FROM public.vehicles))::text""")


def _scenario(d):
    """A charging car with no tidy, one with a needed tidy, a topped-off car with no visit and one with an immediate
    turnaround, all on fast chargers; the backstops and the step's passes, on short then long charges."""
    _car(d, "plain", "DC-1", [CHARGE])
    _car(d, "needed", "DC-2", [CHARGE, dict(TIDY)])
    _car(d, "topoff", "DC-1", None, itinerary="orchestrator")
    _car(d, "rush", "DC-2", [CHARGE], urgency="immediate_dispatch")
    for c, left in (("2026-09-01 14:00:00+00", 3), ("2026-09-01 14:05:00+00", 30), ("2026-09-01 14:10:00+00", 30)):
        _prearrival(d, c)
        _advance(d, c, left=left)


# ── the fixture ──────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_premises_are_the_live_bodies(db):
    for fn, m in LIVE.items():
        assert arm._md5(db, fn) == m, fn


def test_it_applies_as_declared(db):
    _apply(db)
    cat = db.json("""SELECT to_jsonb(c) FROM public.ottoq_policy_param_catalog c WHERE param_key = 'stall_cabin_robot'""")
    assert (cat["default_value"], cat["min_value"], cat["max_value"]) == (0, 0, 2)
    assert "0765 (G484)" in cat["description"] and not cat["agent_writable"]
    assert "ottoq.ottoq_sim_prearrival_contracts" in cat["affects"]
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0765_pre'") == "2"
    assert db.val(f"""SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage
                      WHERE name = '{L0765}'""") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_policy_params WHERE param_key = 'stall_cabin_robot'") == "0"
    # the completion step and the leg door are as they were
    assert arm._md5(db, ADVANCE) == LIVE[ADVANCE] and arm._md5(db, LEG_OPEN) == LIVE[LEG_OPEN]


# ── at 0 and 1 nothing moves ─────────────────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("value", [0, 1])
def test_at_0_and_1_the_same_world_is_byte_identical(template, value):
    states = []
    for with_0765 in (False, True):
        name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
        arm._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
        try:
            d = base.Db(name)
            if with_0765:
                _apply(d)
            if value:
                arm._dial(d, value)
            _scenario(d)
            states.append(_state(d))
        finally:
            arm._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
    assert states[0] == states[1]
    assert "arm_routine" not in states[1] and '"manifests": null' in states[1]


# ── the gaps, at 2 before 0765 ───────────────────────────────────────────────────────────────────────────────────────

def test_before_0765_a_short_charge_and_a_topped_off_car_are_not_cleaned_by_the_arm(db):
    arm._dial(db, 2)
    short = _car(db, "short", "DC-1", [CHARGE])
    needed = _car(db, "needed", "DC-2", [CHARGE, dict(TIDY)])
    topoff = _car(db, "topoff", "DC-1", None, itinerary="orchestrator")
    _prearrival(db, T0)
    _advance(db, T0, left=3)
    assert _tidies(db, short) == []
    assert _meta(db, short)["arm_routine"]["outcome"] == "charge_shorter_than_the_cycle"
    [t] = _tidies(db, needed)
    assert t["status"] == "in_progress" and "performed_by" not in t     # a technician's
    assert _calls(db, "_test_manifests", topoff) == 0 and _meta(db, topoff) == {}


# ── at 2 the arm cleans however short the charge ─────────────────────────────────────────────────────────────────────

def test_a_short_charge_is_cleaned_and_its_car_held_until_the_arm_is_home(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "short", "DC-1", [CHARGE])
    _advance(db, T0, left=3)
    [t] = _tidies(db, car)
    assert (t["status"], t["performed_by"], t["robot_stall_id"], t["arm_routine"]) == \
        ("in_progress", "stall_cabin_robot", arm._id("DC-1"), True)
    assert t["ends_at"].startswith("2026-09-01T14:05:48")
    m = _meta(db, car)["arm_routine"]
    assert (m["outcome"], m["charge_left_min"], m["cycle_min"]) == ("cleaned", 3, 5.8)
    [leg] = _legs(db, car)
    assert leg["leg_id"] == t["robot_leg_id"] and leg["itinerary_id"] == _id("itin-short")
    assert (leg["status"], leg["seq"], leg["to_stall_id"]) == ("active", 2, arm._id("DC-1"))
    assert float(leg["planned_duration_s"]) == 348
    assert leg["duration_basis"] == {"atom": "interior_tidy", "kind": "stall_cabin_robot", "arm_routine": True,
                                     "concurrent_with": "charge"}
    assert arm._holds(db, car)
    # the charge ends at 14:03 with the arm still in the cabin: the car stays on its post until the arm is home
    db.val(f"""UPDATE public.ocpp_sessions SET status = 'completed', ended_at = '2026-09-01 14:03:00+00'
                WHERE vehicle_id = '{car}'""")
    db.val(f"UPDATE public.vehicles SET current_state = 'charge_complete_holding' WHERE id = '{car}'")
    _advance(db, "2026-09-01 14:04:00+00")
    assert _tidies(db, car)[0]["status"] == "in_progress" and arm._holds(db, car)
    _advance(db, "2026-09-01 14:06:00+00")
    [t] = _tidies(db, car)
    assert (t["status"], t["done_at"]) == ("done", t["ends_at"])
    [leg] = _legs(db, car)
    assert leg["status"] == "done" and leg["actual_end_sim"].startswith("2026-09-01T14:05:48")
    assert db.val(f"SELECT count(*) FROM public._test_credits WHERE vehicle_id = '{car}' AND svc = 'interior_tidy'") == "1"
    assert not arm._holds(db, car)


def test_a_needed_tidy_on_a_short_charge_is_the_arms(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "needed", "DC-1", [CHARGE, dict(TIDY)])
    _advance(db, T0, left=3)
    [t] = _tidies(db, car)
    assert (t["status"], t["performed_by"], t["robot_stall_id"]) == ("in_progress", "stall_cabin_robot", arm._id("DC-1"))
    assert "arm_routine" not in t and _legs(db, car) == [] and "arm_routine" not in _meta(db, car)


def test_an_immediate_turnaround_on_a_short_charge_is_recorded_once_and_not_held(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "rush", "DC-1", [CHARGE], urgency="immediate_dispatch")
    _advance(db, T0, left=3)
    assert _tidies(db, car) == [] and _legs(db, car) == [] and not arm._holds(db, car)
    m = _meta(db, car)["arm_routine"]
    assert (m["outcome"], m["charge_left_min"], m["cycle_min"], m["stall_id"]) == \
        ("immediate_turnaround", 3, 5.8, arm._id("DC-1"))
    # decided: a longer estimate later does not reopen it
    _advance(db, "2026-09-01 14:01:00+00", left=30)
    assert _tidies(db, car) == [] and _meta(db, car)["arm_routine"] == m


def test_an_immediate_turnaround_is_cleaned_on_a_long_charge(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "rush-long", "DC-1", [CHARGE], urgency="immediate_dispatch")
    _advance(db, T0, left=30)
    [t] = _tidies(db, car)
    assert (t["performed_by"], t["arm_routine"]) == ("stall_cabin_robot", True)
    assert _meta(db, car)["arm_routine"] == {"at": "2026-09-01T14:00:00+00:00", "outcome": "cleaned",
                                             "stall_id": arm._id("DC-1")}


def test_an_immediate_turnarounds_needed_tidy_on_a_short_charge_is_the_arms(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "rush-needed", "DC-1", [CHARGE, dict(TIDY)], urgency="immediate_dispatch")
    _advance(db, T0, left=3)
    [t] = _tidies(db, car)
    assert (t["status"], t["performed_by"]) == ("in_progress", "stall_cabin_robot")
    assert "arm_routine" not in t and "arm_routine" not in _meta(db, car)


# ── at 2 a topped-off car has its visit as it plugs in ──────────────────────────────────────────────────────────────

def test_a_topped_off_car_gets_its_list_once_and_is_cleaned_on_the_orchestrators_itinerary(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "topoff", "DC-1", None, itinerary="orchestrator")
    assert _prearrival(db, T0) == 1
    assert db.json(f"""SELECT jsonb_build_object('run', sim_run_id, 'seed', seed) FROM public._test_manifests
                       WHERE vehicle_id = '{car}'""") == {"run": RUN, "seed": None}
    assert _calls(db, "_test_plans") == 0
    assert db.val(f"""SELECT jsonb_typeof(config->'service_manifest') FROM public.vehicles WHERE id = '{car}'""") == "array"
    assert db.val(f"""SELECT count(*) FROM public.ottoq_visit_needs WHERE vehicle_id = '{car}' AND sim_run_id = '{RUN}'
                        AND status = 'open'""") == "1"
    # the completion step's own pass hands it to the starter, and the post's arm cleans it
    _advance(db, T0)
    [t] = _tidies(db, car)
    assert (t["status"], t["performed_by"], t["arm_routine"]) == ("in_progress", "stall_cabin_robot", True)
    [leg] = _legs(db, car)
    assert leg["leg_id"] == t["robot_leg_id"] and leg["itinerary_id"] == _id("itin-topoff")
    assert (leg["seq"], leg["to_stall_id"], leg["status"]) == (2, arm._id("DC-1"), "active")
    # once a stay: the list is there now, so the backstop does not ask again
    assert _prearrival(db, "2026-09-01 14:01:00+00") == 0
    assert _calls(db, "_test_manifests", car) == 1
    _advance(db, "2026-09-01 14:06:00+00")
    assert _tidies(db, car)[0]["status"] == "done"
    [leg] = _legs(db, car)
    assert leg["status"] == "done" and leg["actual_end_sim"].startswith("2026-09-01T14:05:48")
    assert db.val(f"SELECT count(*) FROM public._test_leg_closes WHERE vehicle_id = '{car}'") == "0"


def test_a_topped_off_car_with_no_itinerary_gets_one_from_the_leg_door(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "bare", "DC-1", None, itinerary=None)
    _prearrival(db, T0)
    _advance(db, T0)
    [leg] = _legs(db, car)
    itin = db.json(f"""SELECT to_jsonb(i) FROM public.ottoq_vehicle_itineraries i WHERE i.vehicle_id = '{car}'""")
    assert leg["itinerary_id"] == itin["itinerary_id"] and leg["seq"] == 1
    assert (itin["status"], itin["created_by"], itin["depot_id"], itin["sim_run_id"]) == \
        ("active", "stall_cabin_robot", DEPOT, RUN)
    assert itin["sim_created_at"].startswith("2026-09-01T14:00:00")
    assert _tidies(db, car)[0]["robot_leg_id"] == leg["leg_id"]


def test_the_backstop_leaves_alone_what_is_not_a_topped_off_car(db):
    _apply(db)
    arm._dial(db, 2)
    listed = _car(db, "listed", "DC-1", None, config={"service_manifest": []})
    visited = _car(db, "visited", "DC-2", [CHARGE])
    standard = _car(db, "standard", "L2-1", None, state="charging_l2")
    done = _car(db, "done", "DC-1", None, state="charge_complete_holding", session=None)
    inbound = _car(db, "inbound", "DC-2", None, state="en_route_to_depot", session=None, itinerary=None)
    assert _prearrival(db, T0) == 1
    # only the car en route, by BACKSTOP 1 as before, with its itinerary planned
    assert _calls(db, "_test_manifests") == 1 and _calls(db, "_test_manifests", inbound) == 1
    assert _calls(db, "_test_plans") == 1 and _calls(db, "_test_plans", inbound) == 1
    for car in (listed, visited, standard, done):
        assert _calls(db, "_test_manifests", car) == 0


def test_the_backstop_is_the_twins_alone(db):
    _apply(db)
    arm._dial(db, 2)
    db.val(f"UPDATE public.depots SET feed_mode = 'live' WHERE id = '{DEPOT}'")
    car = _car(db, "topoff", "DC-1", None, itinerary="orchestrator")
    assert _prearrival(db, T0) == 0 and _calls(db, "_test_manifests", car) == 0


def test_the_routines_leg_binds_no_booking(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "booked", "DC-1", [CHARGE])
    db.val(f"""INSERT INTO public.ottoq_stall_bookings (booking_id, sim_run_id, stall_id, vehicle_id, purpose, during,
                                                         state, leg_source)
               VALUES ('{_id("booking")}', '{RUN}', '{arm._id("DC-1")}', '{car}', 'charge_dcfc',
                       tstzrange('{T0}'::timestamptz - interval '5 minutes', '{T0}'::timestamptz + interval '40 minutes'),
                       'active', 'none')""")
    _advance(db, T0)
    assert _tidies(db, car)[0]["arm_routine"] is True
    assert db.val(f"SELECT leg_id IS NULL FROM public.ottoq_stall_bookings WHERE booking_id = '{_id('booking')}'") == "t"


# ── refusals ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_it_refuses_a_second_apply(db):
    _apply(db)
    rc, err = db.file(M0765)
    assert rc != 0 and "0765 P" in err


@pytest.mark.parametrize("fn,message", [
    ("public.ottoq_start_concurrent_atoms(p_vehicle uuid, p_clock timestamp with time zone) RETURNS integer",
     "a function this file patches"),
    ("ottoq.ottoq_sim_prearrival_contracts(p_sim_run_id uuid, p_clock timestamp with time zone) RETURNS integer",
     "a function this file patches"),
    ("twin.ottoq_sim_advance_visit_atoms(p_sim_run_id uuid, p_clock timestamp with time zone) RETURNS integer",
     "a function this file relies on"),
])
def test_it_refuses_a_body_it_did_not_read(db, fn, message):
    db.val(f"CREATE OR REPLACE FUNCTION {fn} LANGUAGE sql AS $$ SELECT 0 $$")
    rc, err = db.file(M0765)
    assert rc != 0 and f"0765 P1: {message}" in err


def test_it_refuses_a_database_without_0764(db):
    db.val(f"DELETE FROM public.ottoq_cert_lineage WHERE name = '{L0764}'")
    rc, err = db.file(M0765)
    assert rc != 0 and "0764 is not applied" in err


def test_it_refuses_a_dial_not_as_0764_left_it(db):
    db.val("UPDATE public.ottoq_policy_param_catalog SET max_value = 3 WHERE param_key = 'stall_cabin_robot'")
    rc, err = db.file(M0765)
    assert rc != 0 and "not catalogued 0..2 as 0764 left it" in err
