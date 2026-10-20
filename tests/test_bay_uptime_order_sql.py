"""db/migrations/0747, EXECUTED: the bay line serves first the car that will be back in service soonest.

WHY THIS EXISTS. Decide section (4b) seated the wash, detail and service bays urgency first, by the most urgent of all a
car's needs, so an urgent repair went ahead of a car one short service from earning. Its shortest-job term read 0 on
99.7% of normal-day bay decisions (G461). Chase, 2026-10-17: an urgent issue brings the car home at once and is fitted
in around the cars that rejoin service soonest; it does not supersede a standard or timely service. 0747 puts one key
first in (4b)'s two orders, public.ottoq_bay_uptime_order_key, NULL at the dial's default. Every claim in 0747's header
about the key is executed here, on the scratch PostgreSQL, against the key exactly as 0747 writes it, with the live
service catalog (service_cadence_policy's lanes and default minutes, as read on 2026-10-17):
  - at the dial's default the key is NULL for every car, so (4b)'s order is today's;
  - with the dial a safety emergency goes first (a severity-1 fault, or the twin's hazard classes, an HV battery
    thermal event or a charge-system fault), then any car past the wait floor (the longest first), then resumed work,
    then cars with no open fault repair before cars with one, then the least must-do work left;
  - the twin's other in-depot faults (a sensor suite fault, an immobilizing steering and brake fault) are urgent repairs,
    fitted in, not emergencies;
  - the work left counts the car's own visit in this run, only must-do work not done, only the work that holds a space
    (charge, wash, detail, service bay), and a missing estimate takes the catalog's default;
  - the wait floor is a dial, and a repair that has waited past it goes ahead of everything but an emergency;
  - a severity-1 car whose next bay need is a wash is not an emergency for the wash bay; its open repair still counts.
The decide's patch is proven on its live body by 0747's V1 at apply.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import sys
import tempfile
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)

ROOT = base.ROOT
M0747 = os.path.join(ROOT, "db", "migrations", "0747_the_bay_line_serves_the_car_that_rejoins_service_soonest.sql")
DEPOT = base.DEPOT
RUN = "a0000000-0000-0000-0000-000000000747"
OTHER = "a0000000-0000-0000-0000-000000007470"
T = "2026-09-01 15:00:00+00"

# the live service catalog's lanes and default minutes (service_cadence_policy, read 2026-10-17)
CATALOG = [("charge", "anchor", 10, 25), ("item_retrieval", "cabin", 12, 4), ("triage_check", "cabin", 15, 3),
           ("interior_inspection", "cabin", 20, 4), ("interior_tidy", "cabin", 25, 5), ("sensor_clean", "exterior", 25, 5),
           ("perimeter_walkaround", "exterior", 27, 12), ("fault_repair", "service_bay", 30, 76),
           ("exterior_wash", "wash_bay", 40, 10), ("interior_deep_clean", "detail", 45, 20),
           ("software_update", "digital", 50, 30), ("data_offload", "digital", 52, 27),
           ("sensor_calibration", "service_bay", 55, 60), ("mechanical_pm", "service_bay", 60, 40),
           ("cosmetic_repair", "service_bay", 70, 60), ("remote_diagnostics", "digital", 75, 5),
           ("readiness_check", "gate", 90, 3)]

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0747-{name}"))


def _key_sql():
    """0747's dials and its key, exactly as the migration writes them."""
    with open(M0747) as f:
        text = f.read()
    return text[text.index("-- ── (a) the dials ──"):text.index("-- ── (c) decide section (4b) ──")]


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_upt_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        rc, err = d.file(base.STUB)
        assert rc == 0, f"base stub did not load: {err}"
        d.val("""CREATE TABLE IF NOT EXISTS public.vehicle_need_profile (vehicle_id uuid PRIMARY KEY, drawn_for_run uuid,
                   worst_fault_severity smallint, open_fault_codes text[], next_deploy_at timestamptz)""")
        d.val("""CREATE TABLE IF NOT EXISTS public.service_cadence_policy (svc text PRIMARY KEY, lane text,
                   sequence_order integer, is_active boolean, est_min_default numeric)""")
        d.val("INSERT INTO public.service_cadence_policy VALUES " + ", ".join(
            f"('{s}', '{lane}', {seq}, true, {est})" for s, lane, seq, est in CATALOG))
        with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
            f.write(_key_sql())
            path = f.name
        try:
            rc, err = d.file(path)
        finally:
            os.remove(path)
        assert rc == 0, f"0747's key did not create: {err}"
        d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_start, sim_clock_current)
                  VALUES ('{RUN}', '{DEPOT}', 'running', '{T}'::timestamptz - interval '4 hours',
                          '{T}'::timestamptz - interval '4 hours', '{T}')""")
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_up_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _dial(d, key, value):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{RUN}', '{key}', {value}, 'test', now())
              ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value""")


def _car(d, name, waited, atoms, severity=99, run=RUN):
    """A car staged waiting `waited` minutes, its fault severity drawn, and its visit's atoms in `run`."""
    vid = _id(name)
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, display_name, current_state, last_state_change, config)
              VALUES ('{vid}', '{DEPOT}', 'autonomous', '{name}', 'staged_awaiting_service',
                      '{T}'::timestamptz - interval '{waited} minutes', '{{}}')
              ON CONFLICT (id) DO NOTHING""")
    d.val(f"""INSERT INTO public.vehicle_need_profile (vehicle_id, drawn_for_run, worst_fault_severity)
              VALUES ('{vid}', '{run}', {severity}) ON CONFLICT (vehicle_id) DO NOTHING""")
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, status, atoms)
              VALUES ('{vid}', '{run}', '{DEPOT}', 'in_progress', '{json.dumps(atoms)}'::jsonb)""")
    return vid


def _atom(svc, est=None, done=False, must=True):
    a = {"svc": svc, "must_do": must, "status": "done" if done else "pending"}
    if est is not None:
        a["est_min"] = est
    return a


def _key(d, vid, svc, resume=False):
    return d.json(f"""SELECT COALESCE(to_json(public.ottoq_bay_uptime_order_key('{RUN}', '{vid}', '{svc}',
                                                                                {str(resume).lower()}, '{T}')), 'null')""")


def test_at_the_default_the_key_is_null(db):
    vid = _car(db, "a", 20, [_atom("mechanical_pm", 24)])
    assert _key(db, vid, "mechanical_pm") is None
    sev1 = _car(db, "e", 5, [_atom("fault_repair", 101)], severity=1)
    assert _key(db, sev1, "fault_repair") is None


def test_the_order_is_emergency_floor_resume_repair_last_then_shortest(db):
    _dial(db, "bay_order_uptime_first", 1)
    cars = {
        "pm": (_car(db, "pm", 20, [_atom("mechanical_pm", 24)]), "mechanical_pm", False),
        "urgent": (_car(db, "urgent", 30, [_atom("fault_repair", 101)], severity=2), "fault_repair", False),
        "emergency": (_car(db, "emergency", 5, [_atom("fault_repair", 101)], severity=1), "fault_repair", False),
        "aged": (_car(db, "aged", 100, [_atom("sensor_calibration", 60)]), "sensor_calibration", False),
        "resumed": (_car(db, "resumed", 10, [_atom("interior_deep_clean", 21)]), "interior_deep_clean", True),
        "wash": (_car(db, "wash", 10, [_atom("exterior_wash", 8)]), "exterior_wash", False),
        "aged_repair": (_car(db, "aged_repair", 120, [_atom("fault_repair", 80)], severity=3), "fault_repair", False),
    }
    keys = {k: _key(db, vid, svc, res) for k, (vid, svc, res) in cars.items()}
    order = sorted(keys, key=lambda k: [float(x) for x in keys[k]])
    assert order == ["emergency", "aged_repair", "aged", "resumed", "wash", "pm", "urgent"], keys
    # the urgent repair is behind the standard service it would have beaten on urgency
    assert keys["urgent"][4] == 1 and keys["pm"][4] == 0
    assert [float(x) for x in keys["aged_repair"][1:3]] == [0, -120]


def test_the_work_left_is_the_cars_own_space_holding_must_do_work(db):
    _dial(db, "bay_order_uptime_first", 1)
    vid = _car(db, "mix", 15, [_atom("exterior_wash", 8), _atom("interior_deep_clean"),       # no estimate: catalog 20
                                _atom("software_update", 30), _atom("interior_tidy", 5),        # in place: not counted
                                _atom("charge", 25, done=True),                                 # done: not counted
                                _atom("cosmetic_repair", 60, must=False)])                      # not must-do
    # another run's open visit for the same car is not this run's work
    db.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, status, atoms)
               VALUES ('{vid}', '{OTHER}', '{DEPOT}', 'open', '[{{"svc": "mechanical_pm", "must_do": true, "est_min": 40}}]')""")
    key = _key(db, vid, "exterior_wash")
    assert float(key[5]) == 28.0        # 8 + 20
    assert float(key[4]) == 0


def test_the_wait_floor_is_a_dial(db):
    _dial(db, "bay_order_uptime_first", 1)
    urgent = _car(db, "urgent", 30, [_atom("fault_repair", 101)], severity=2)
    pm = _car(db, "pm", 20, [_atom("mechanical_pm", 24)])
    assert [float(x) for x in _key(db, urgent, "fault_repair")][1] == 1
    _dial(db, "bay_wait_floor_min", 30)
    ku, kp = _key(db, urgent, "fault_repair"), _key(db, pm, "mechanical_pm")
    assert [float(x) for x in ku][1:3] == [0, -30]
    assert [float(x) for x in ku] < [float(x) for x in kp]          # past the floor, the repair goes first


def test_the_twins_hazard_classes_are_emergencies_and_its_breakdowns_are_not(db):
    _dial(db, "bay_order_uptime_first", 1)
    thermal = _car(db, "thermal", 2, [dict(_atom("fault_repair", 76), fault_class="hv_battery_thermal",
                                           fault_severity="critical", immobilizing=True, raised_in_depot=True)])
    charge = _car(db, "chargefault", 2, [dict(_atom("fault_repair", 76), fault_class="charge_system_fault",
                                              fault_severity="critical", immobilizing=True, raised_in_depot=True)])
    sensor = _car(db, "sensor", 2, [dict(_atom("fault_repair", 76), fault_class="sensor_suite_fault",
                                         fault_severity="critical", immobilizing=False, raised_in_depot=True)])
    brake = _car(db, "brake", 2, [dict(_atom("fault_repair", 76), fault_class="steering_brake_fault",
                                       fault_severity="critical", immobilizing=True, raised_in_depot=True)])
    assert float(_key(db, thermal, "fault_repair")[0]) == 0
    assert float(_key(db, charge, "fault_repair")[0]) == 0
    for vid in (sensor, brake):                  # urgent, home and parked: fitted in like any repair
        key = _key(db, vid, "fault_repair")
        assert float(key[0]) == 1 and float(key[4]) == 1


def test_a_severity_one_car_is_an_emergency_only_for_its_repair(db):
    _dial(db, "bay_order_uptime_first", 1)
    vid = _car(db, "sev1", 5, [_atom("fault_repair", 101), _atom("exterior_wash", 8)], severity=1)
    assert float(_key(db, vid, "fault_repair")[0]) == 0
    wash = _key(db, vid, "exterior_wash")
    assert float(wash[0]) == 1          # not an emergency for the wash bay
    assert float(wash[4]) == 1          # its open repair still counts
