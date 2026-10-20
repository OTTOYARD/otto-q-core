"""db/migrations/0758, EXECUTED: a fast charger's cleaning arm cleans the cabin while the car charges.

WHY THIS EXISTS. Chase, 2026-10-19: an overhead robot arm at each robotic fast-charger stall cleans the cabin while the
car charges, "several minutes on each side" against a 15-30 minute charge. Until 0758 the interior tidy was always a
technician's (the general_tech pool, 10 at the twin depot): on arm 108, 23 of the run's 71 tidies started during a fast
charge, a mean 9.3 minutes after it began, all by technicians. 0758 puts the arm behind a dial (stall_cabin_robot).
Executed here, on the scratch PostgreSQL, against the live starter, hold, completion step, snapshot and depot cards
(tests/fixtures/stall_cabin_robot_stub.sql, md5 asserted as read on 2026-10-19), with 0758 run whole:
  - at the default nothing moves: the same world run through the starter and the completion step before 0758 and after
    it leaves byte-identical visits;
  - with the dial, a fast-charging car's must-do tidy starts at once with no technician, runs the arm's cycle (5.8
    minutes at the defaults), records its stall, and leaves the technician pool to the others; it completes at ends_at,
    closing its leg and crediting the ledger, and the car is held on its stall while it runs;
  - with the dial, a car on a standard charger, a charge with less than the cycle left, a tidy that is not must-do, and a
    car with no active session are left to the technicians, as before;
  - a car moved off the arm's stall before the cycle ended has its tidy reset to pending, nothing credited, the
    interruption recorded, and its readiness check waits for it;
  - 0758 applies, leaves the bodies it was written to leave (each body less its changes is its pre-image), stores the
    pre-images, catalogues the three dials, queues the research wing's pair, and refuses a second apply, a body it did
    not read and a database without 0757.
A module template carries the base stub and the fixture, and each test clones it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)

ROOT = base.ROOT
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "stall_cabin_robot_stub.sql")
M0758 = os.path.join(ROOT, "db", "migrations",
                     "0758_a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges.sql")
DEPOT = base.DEPOT
RUN = "a0000000-0000-0000-0000-000000000758"
T0 = "2026-09-01 14:00:00+00"
START = "public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)"
HOLD = "ottoq.ottoq_uplink_transfer_holds(uuid,uuid)"
ADVANCE = "twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)"
SNAP = "public.ottoq_twin_snapshot(uuid)"
CARDS = "public.ottoq_depot_cards(uuid,uuid)"
# the live bodies the fixture carries (md5 of prosrc, read from the live catalog on 2026-10-19), and what 0758 leaves
LIVE = {START: "f7d87d5db9cf120e6e94ed802525882b", HOLD: "e586ee275d120d70d637e3d87b2330a1",
        ADVANCE: "3e8eb3f4babb8d3005cf383e0372f9e9", SNAP: "ea1a4a9a28762aaf8958f05ccdc2dcc3",
        CARDS: "c4530de93479b56241defb705fc09a63",
        "public.ottoq_depot_staffing_count(uuid,text)": "b8814784deaea5ef2121f7bb6632dcc9"}
AFTER = {START: "ce0a831c29f421948d2d44f966cff233", HOLD: "dfd5d9d7b68066b2e933f5056bcaaceb",
         ADVANCE: "c1741376dc7e9d9597b5e8a15aed42e5", SNAP: "9677506f209abc4db0c39bc1fbb0a440",
         CARDS: "8257d524058e30d39d453475f5941f84"}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0758-{name}"))


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, FIXTURE):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        d.val("""INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
                 VALUES ('0757_a_bay_seat_that_finished_early_is_done', false, false, 'test premise', now())""")
        _world(d)
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply(d):
    rc, err = d.file(M0758)
    assert rc == 0, f"0758 did not apply: {err}"


def _md5(d, fn):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')")


def _world(d):
    """The twin depot in sim mode, a running run, two fast chargers, a standard charger, and two technicians."""
    d.val(f"INSERT INTO public.depots (id, feed_mode) VALUES ('{DEPOT}', 'sim')")
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_start,
                                                 sim_clock_current, tick_count, random_seed)
              VALUES ('{RUN}', '{DEPOT}', 'running', now() - interval '1 hour', '2026-09-01 11:00+00', '{T0}', 36, 42)""")
    d.val(f"INSERT INTO public.ottoq_depot_staffing (depot_id, role, headcount) VALUES ('{DEPOT}', 'general_tech', 2)")
    for i, (code, kind, kw) in enumerate([("DC-1", "dcfc", 350), ("DC-2", "dcfc", 350), ("L2-1", "l2", 19)]):
        ch = _id(f"charger-{code}")
        d.val(f"INSERT INTO public.ottoq_ocpp_chargers (charger_id, depot_id, max_kw) VALUES ('{ch}', '{DEPOT}', {kw})")
        d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, display_name, status,
                                             distance_from_entrance, ocpp_charger_id)
                  VALUES ('{_id(code)}', '{DEPOT}', '{code}', '{kind}', '{code}', 'occupied', {i}, '{ch}')""")


TIDY = {"svc": "interior_tidy", "must_do": True, "deferrable": False, "est_min": 5, "concurrency": "cabin"}
CHARGE = {"svc": "charge", "must_do": True, "est_min": 30, "concurrency": "anchor"}


def _car(d, name, stall, state="charging_dcfc", session="active", tidy=None, extra=()):
    """A car on a charger with its session, and its visit: the charge under way and the interior tidy pending."""
    vid = _id(name)
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, current_depot_id, category, display_name, current_state,
                                           current_stall_id, current_soc, battery_capacity_kwh, inlet_max_kw,
                                           last_state_change, config)
              VALUES ('{vid}', '{DEPOT}', '{DEPOT}', 'autonomous', '{name}', '{state}', '{_id(stall)}', 40, 75, 250,
                      '{T0}'::timestamptz - interval '10 minutes', '{{}}')""")
    if session:
        d.val(f"""INSERT INTO public.ocpp_sessions (depot_id, stall_id, vehicle_id, status, started_at, soc_start,
                                                    sim_run_id)
                  VALUES ('{DEPOT}', '{_id(stall)}', '{vid}', '{session}', '{T0}'::timestamptz - interval '5 minutes', 38,
                          '{RUN}')""")
    atoms = [dict(CHARGE, status="in_progress"), dict(TIDY, **(tidy or {}))] + list(extra)
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, status, atoms,
                                                    meta, created_at)
              VALUES ('{vid}', '{RUN}', '{DEPOT}', '{T0}'::timestamptz - interval '15 minutes', 'v-{name}', 'open',
                      '{json.dumps(atoms)}'::jsonb, '{{}}', now())""")
    return vid


def _dial(d, value=1, key="stall_cabin_robot"):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{RUN}', '{key}', {value}, 'test', now())""")


def _start(d, car, clock=T0, left=None):
    """The starter, in one session so a test can say how much charge is left (the estimate's stand-in reads it)."""
    pre = f"SET test.charge_left_min = '{left}'; " if left is not None else ""
    rc, out, err = d.run(f"{pre}SELECT public.ottoq_start_concurrent_atoms('{car}', '{clock}')")
    assert rc == 0 and "WARNING" not in err, err
    return int(out[-1])


def _advance(d, clock):
    rc, out, err = d.run(f"SELECT twin.ottoq_sim_advance_visit_atoms('{RUN}', '{clock}')")
    assert rc == 0 and "WARNING" not in err, err
    return int(out[-1])


def _tidy(d, car):
    return d.json(f"""SELECT a FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                       WHERE n.vehicle_id = '{car}' AND a->>'svc' = 'interior_tidy'""")


def _atom(d, car, svc):
    return d.json(f"""SELECT a FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                       WHERE n.vehicle_id = '{car}' AND a->>'svc' = '{svc}'""")


def _holds(d, car):
    return d.val(f"SELECT ottoq.ottoq_uplink_transfer_holds('{car}', '{RUN}')") == "t"


def _visits(d):
    return d.val("SELECT jsonb_agg(atoms ORDER BY visit_key)::text FROM public.ottoq_visit_needs")


# ── the fixture ──────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_fixture_is_the_live_bodies(db):
    for fn, m in LIVE.items():
        assert _md5(db, fn) == m, fn


# ── at the default nothing moves ─────────────────────────────────────────────────────────────────────────────────────

def _scenario(d):
    """Three cars and three passes of the starter and the completion step, the last after every tidy's end."""
    cars = [_car(d, "dc-a", "DC-1"), _car(d, "dc-b", "DC-2"), _car(d, "l2-c", "L2-1", state="charging_l2")]
    for c in cars:
        _start(d, c)
    _advance(d, "2026-09-01 14:05:00+00")
    _advance(d, "2026-09-01 14:10:00+00")
    return cars


def test_at_the_default_0758_leaves_the_visits_byte_identical(template):
    names = [f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}" for _ in range(2)]
    for n in names:
        _admin(f"CREATE DATABASE {n} TEMPLATE {template}")
    try:
        before, after = base.Db(names[0]), base.Db(names[1])
        _apply(after)
        _scenario(before)
        _scenario(after)
        assert _visits(before) == _visits(after)
        assert (before.val("SELECT count(*) FROM public._test_leg_closes")
                == after.val("SELECT count(*) FROM public._test_leg_closes"))
        # two technicians, three tidies: the third waits for one, and starts when the first two are done
        tidies = [a for v in json.loads(_visits(after)) for a in v if a["svc"] == "interior_tidy"]
        assert sorted(a["status"] for a in tidies) == ["done", "done", "in_progress"]
        assert all("performed_by" not in a for a in tidies)
    finally:
        for n in names:
            _admin(f"DROP DATABASE IF EXISTS {n} WITH (FORCE)")


# ── with the dial ────────────────────────────────────────────────────────────────────────────────────────────────────

def test_with_the_dial_the_arm_starts_a_fast_charging_cars_tidy_at_once_and_runs_its_cycle(db):
    _apply(db)
    _dial(db)
    car = _car(db, "dc-a", "DC-1")
    assert _start(db, car) == 1
    t = _tidy(db, car)
    assert t["status"] == "in_progress"
    assert t["performed_by"] == "stall_cabin_robot"
    assert t["robot_stall_id"] == _id("DC-1")
    assert float(t["robot_cycle_min"]) == pytest.approx(5.8)
    # 2 x 2.5 + 0.8 = 5.8 minutes = 348 seconds from the pass's clock
    span = db.val(f"""SELECT extract(epoch FROM (('{json.dumps(t)}'::jsonb ->> 'ends_at')::timestamptz
                                              - ('{json.dumps(t)}'::jsonb ->> 'started_at')::timestamptz))""")
    assert float(span) == 348
    assert db.val(f"SELECT ('{json.dumps(t)}'::jsonb ->> 'started_at')::timestamptz = '{T0}'::timestamptz") == "t"


def test_with_the_dial_the_arms_work_takes_no_technician(db):
    _apply(db)
    _dial(db)
    a = _car(db, "dc-a", "DC-1")
    b = _car(db, "l2-b", "L2-1", state="charging_l2")
    c = _car(db, "dc-c", "DC-2")
    db.val(f"UPDATE public.ocpp_sessions SET status = 'Completed' WHERE vehicle_id = '{c}'")   # c: a technician's job
    for car in (a, b, c):
        _start(db, car)
    # two technicians: b and c take them, and the arm's work on a is counted against neither
    assert _tidy(db, a)["performed_by"] == "stall_cabin_robot"
    assert _tidy(db, b)["status"] == "in_progress" and "performed_by" not in _tidy(db, b)
    assert _tidy(db, c)["status"] == "in_progress" and "performed_by" not in _tidy(db, c)


def test_with_the_dial_the_arms_cycle_follows_its_two_dials(db):
    _apply(db)
    _dial(db)
    _dial(db, 3.0, "cabin_robot_side_min")
    _dial(db, 1.0, "cabin_robot_motion_min")
    car = _car(db, "dc-a", "DC-1")
    _start(db, car)
    assert float(_tidy(db, car)["robot_cycle_min"]) == pytest.approx(7.0)


@pytest.mark.parametrize("case", ["standard_charger", "short_charge", "not_must_do", "no_active_session", "dial_zero"])
def test_with_the_dial_other_tidies_are_left_to_the_technicians(db, case):
    _apply(db)
    _dial(db, 0 if case == "dial_zero" else 1)
    if case == "standard_charger":
        car = _car(db, "l2-a", "L2-1", state="charging_l2")
    elif case == "not_must_do":
        car = _car(db, "dc-a", "DC-1", tidy={"must_do": False})
    elif case == "no_active_session":
        car = _car(db, "dc-a", "DC-1", session="Completed")
    else:
        car = _car(db, "dc-a", "DC-1")
    _start(db, car, left=3 if case == "short_charge" else None)
    t = _tidy(db, car)
    assert "performed_by" not in t and "robot_stall_id" not in t
    assert t["status"] == "in_progress"       # a free technician takes it, as before 0758


def test_a_short_charge_at_the_boundary(db):
    _apply(db)
    _dial(db)
    a = _car(db, "dc-a", "DC-1")
    b = _car(db, "dc-b", "DC-2")
    _start(db, a, left=5.8)    # exactly the cycle: the arm takes it
    _start(db, b, left=5.7)    # a tenth short: the technicians do
    assert _tidy(db, a)["performed_by"] == "stall_cabin_robot"
    assert "performed_by" not in _tidy(db, b)


def test_the_arms_work_completes_at_its_end_and_holds_the_car_until_then(db):
    _apply(db)
    _dial(db)
    car = _car(db, "dc-a", "DC-1")
    assert not _holds(db, car)
    _start(db, car)
    assert _holds(db, car)
    _advance(db, "2026-09-01 14:05:00+00")            # 5 of 5.8 minutes: still at work
    assert _tidy(db, car)["status"] == "in_progress"
    assert _holds(db, car)
    _advance(db, "2026-09-01 14:10:00+00")            # past the end
    t = _tidy(db, car)
    assert t["status"] == "done"
    assert t["done_at"] == t["ends_at"]
    assert not _holds(db, car)
    assert db.val(f"SELECT count(*) FROM public._test_leg_closes WHERE vehicle_id = '{car}' AND svc = 'interior_tidy'") == "1"
    assert db.val(f"SELECT count(*) FROM public._test_credits WHERE vehicle_id = '{car}' AND svc = 'interior_tidy'") == "1"


def test_a_car_moved_off_the_arms_stall_has_its_tidy_reset_and_nothing_credited(db):
    _apply(db)
    _dial(db)
    car = _car(db, "dc-a", "DC-1")
    _start(db, car)
    started = _tidy(db, car)["started_at"]
    # a charger fault moves it to the other fast charger before the cycle ends (a path the hold does not cover)
    db.val(f"UPDATE public.vehicles SET current_stall_id = '{_id('DC-2')}' WHERE id = '{car}'")
    assert not _holds(db, car)                         # the hold reads the stall the car stands on
    _advance(db, "2026-09-01 14:10:00+00")
    t = _tidy(db, car)
    assert t["status"] == "pending"
    for k in ("performed_by", "robot_stall_id", "robot_cycle_min", "started_at", "ends_at"):
        assert k not in t, k
    assert t["interrupted"][-1]["reason"] == "left_the_cabin_robot"
    assert t["interrupted"][-1]["stall_id"] == _id("DC-1")
    assert t["interrupted"][-1]["started_at"] == started
    assert db.val(f"SELECT count(*) FROM public._test_credits WHERE vehicle_id = '{car}'") == "0"
    assert db.val(f"SELECT count(*) FROM public._test_leg_closes WHERE vehicle_id = '{car}'") == "0"


def test_the_readiness_check_waits_for_a_tidy_that_goes_back_to_pending(db):
    _apply(db)
    _dial(db)
    gone = {"status": "in_progress", "performed_by": "stall_cabin_robot", "robot_stall_id": _id("DC-1"),
            "robot_cycle_min": 5.8, "started_at": "2026-09-01T13:55:00+00:00", "ends_at": "2026-09-01T14:00:48+00:00"}
    car = _car(db, "dc-a", "DC-2", state="staged_for_departure", tidy=gone,
               extra=[{"svc": "readiness_check", "must_do": True, "est_min": 3, "concurrency": "gate"}])
    db.val(f"""UPDATE public.ottoq_visit_needs SET atoms = jsonb_build_array(jsonb_set(atoms->0, '{{status}}', '"done"'))
                                                         || (atoms - 0) WHERE vehicle_id = '{car}'""")
    _advance(db, "2026-09-01 14:05:00+00")
    assert _tidy(db, car)["status"] == "pending"
    assert _atom(db, car, "readiness_check").get("status", "pending") == "pending"


def test_before_0758_that_readiness_check_would_have_closed(db):
    # the same visit on the live bodies: the arm's work is completed where it stands and the check closes with it
    gone = {"status": "in_progress", "performed_by": "stall_cabin_robot", "robot_stall_id": _id("DC-1"),
            "robot_cycle_min": 5.8, "started_at": "2026-09-01T13:55:00+00:00", "ends_at": "2026-09-01T14:00:48+00:00"}
    car = _car(db, "dc-a", "DC-2", state="staged_for_departure", tidy=gone,
               extra=[{"svc": "readiness_check", "must_do": True, "est_min": 3, "concurrency": "gate"}])
    db.val(f"""UPDATE public.ottoq_visit_needs SET atoms = jsonb_build_array(jsonb_set(atoms->0, '{{status}}', '"done"'))
                                                         || (atoms - 0) WHERE vehicle_id = '{car}'""")
    _advance(db, "2026-09-01 14:05:00+00")
    assert _tidy(db, car)["status"] == "done"
    assert _atom(db, car, "readiness_check")["status"] == "done"


# ── 0758 itself ──────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0758_applies_and_leaves_the_bodies_it_was_written_to_leave(db):
    _apply(db)
    for fn, m in AFTER.items():
        assert _md5(db, fn) == m, fn
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0758_pre'") == "5"
    assert db.val("""SELECT string_agg(param_key || '=' || default_value || '[' || min_value || ',' || max_value || ']',
                                        ' ' ORDER BY param_key)
                       FROM public.ottoq_policy_param_catalog
                      WHERE param_key IN ('stall_cabin_robot', 'cabin_robot_side_min', 'cabin_robot_motion_min')
                        AND NOT agent_writable""") == \
        "cabin_robot_motion_min=0.8[0.1,5] cabin_robot_side_min=2.5[0.5,10] stall_cabin_robot=0[0,1]"
    assert db.val("""SELECT string_agg(c.cell_code || ':' || (c.fixed_params ->> 'stall_cabin_robot'), ' ' ORDER BY c.ord)
                       FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                      WHERE s.sweep_code = 'robocabin_normal_2026_10_19' AND s.priority = 18""") == \
        "dcfc10.otto_q.cabin_crews:0 dcfc10.otto_q.cabin_robot:1"
    assert db.val("""SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage
                      WHERE name = '0758_a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges'""") == \
        "falsefalse"


def test_0758_refuses_a_second_apply(db):
    _apply(db)
    rc, err = db.file(M0758)
    assert rc != 0 and "0758 P1" in err      # the dials exist, which P1 names before P2 can
    for fn, m in AFTER.items():
        assert _md5(db, fn) == m, fn


def test_0758_refuses_a_body_it_did_not_read(db):
    db.val("""CREATE OR REPLACE FUNCTION ottoq.ottoq_uplink_transfer_holds(p_vehicle uuid, p_run uuid)
              RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$""")
    rc, err = db.file(M0758)
    assert rc != 0 and "0758 P1: a function this file patches is not the body it was written against" in err
    assert _md5(db, START) == LIVE[START]


def test_0758_refuses_a_database_without_0757(db):
    db.val("DELETE FROM public.ottoq_cert_lineage WHERE name = '0757_a_bay_seat_that_finished_early_is_done'")
    rc, err = db.file(M0758)
    assert rc != 0 and "0758 P1: 0757 is not applied" in err
    assert _md5(db, START) == LIVE[START]
