"""db/migrations/0764, EXECUTED: every car that charges on a robotic post has its cabin cleaned by the post's arm.

WHY THIS EXISTS. Chase, 2026-10-23, watching the first demo run on the 30-post depot: "I don't see the overhead arms
working and doors opening". 0758's arm takes a car's interior tidy, and the twin derives one for about a visit in four;
the triage clears a third of those. On b5e80522 the arms worked on about one charge in sixteen. Chase chose "Clean every
car": every car that charges gets the arm's clean during the charge. 0764 puts it behind stall_cabin_robot = 2.
Executed here, on the scratch PostgreSQL, over 0758's fixture with 0758 applied (the live starter and completion step,
md5 asserted as read on live on 2026-10-23), with 0764 run whole:
  - at 0 and at 1 the same world leaves byte-identical visits and legs with and without 0764;
  - at 2 a charging car with no tidy, and one whose tidy the triage cleared, are cleaned by the arm through the
    completion step's own pass: an interior_tidy in progress, by the arm, arm_routine, with its own active leg; it
    takes no technician, holds the car, and at ends_at is done, its leg closed by its id and the ledger credited;
  - a tidy waiting on the triage is waited for, and once confirmed is the arm's by 0758's path, with no second clean;
    a needed tidy is 0758's;
  - a charge shorter than the arm's cycle is recorded once and skipped; no active session decides nothing; a standard
    charger is left alone;
  - a routine clean whose car left the post is cancelled, its leg skipped, the interruption recorded, nothing credited;
  - a visit with no itinerary is still cleaned (its completion falls to ottoq_close_atom_leg, which finds no leg);
  - 0764 applies as declared and refuses a second apply, a body it did not read, a database without 0763 and a dial
    not as 0758 left it.
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

ROOT = base.ROOT
M0764 = os.path.join(ROOT, "db", "migrations", "0764_every_car_that_charges_gets_the_overhead_arms_cabin_clean.sql")
DEPOT = base.DEPOT
RUN = arm.RUN
T0 = arm.T0
START, ADVANCE = arm.START, arm.ADVANCE
# what 0758 left, as read on live on 2026-10-23 (0764's premises)
LIVE = {START: "ce0a831c29f421948d2d44f966cff233", ADVANCE: "c1741376dc7e9d9597b5e8a15aed42e5"}
L0763 = "0763_canopy_c_is_restriped_and_the_twin_depot_has_no_standard_chargers"
CHARGE = {"svc": "charge", "must_do": True, "est_min": 30, "concurrency": "anchor", "status": "in_progress"}
INSPECT = {"svc": "interior_inspection", "must_do": True, "est_min": 4, "concurrency": "cabin"}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0764-{name}"))


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
        # the live itineraries name their visit (0758's fixture carries only what 0758's functions read)
        d.val("ALTER TABLE public.ottoq_vehicle_itineraries ADD COLUMN visit_id uuid")
        d.val(f"""INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
                  VALUES ('{L0763}', true, true, 'test premise', now())""")
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
    rc, err = d.file(M0764)
    assert rc == 0, f"0764 did not apply: {err}"


def _car(d, name, stall, atoms, state="charging_dcfc", session="active", itinerary=True):
    """A car on a stall with its session, its visit (the given atoms) and, unless told not to, its active itinerary
    with a charge leg."""
    vid = _id(name)
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, current_depot_id, category, display_name, current_state,
                                           current_stall_id, current_soc, battery_capacity_kwh, inlet_max_kw,
                                           last_state_change, config)
              VALUES ('{vid}', '{DEPOT}', '{DEPOT}', 'autonomous', '{name}', '{state}', '{arm._id(stall)}', 40, 75, 250,
                      '{T0}'::timestamptz - interval '10 minutes', '{{}}')""")
    if session:
        d.val(f"""INSERT INTO public.ocpp_sessions (depot_id, stall_id, vehicle_id, status, started_at, soc_start,
                                                    sim_run_id)
                  VALUES ('{DEPOT}', '{arm._id(stall)}', '{vid}', '{session}', '{T0}'::timestamptz - interval '5 minutes',
                          38, '{RUN}')""")
    visit = _id(f"visit-{name}")
    d.val(f"""INSERT INTO public.ottoq_visit_needs (visit_id, vehicle_id, sim_run_id, depot_id, arrived_at, visit_key,
                                                    status, atoms, meta, created_at)
              VALUES ('{visit}', '{vid}', '{RUN}', '{DEPOT}', '{T0}'::timestamptz - interval '15 minutes', 'v-{name}',
                      'open', '{json.dumps(atoms)}'::jsonb, '{{}}', now())""")
    if itinerary:
        itin = _id(f"itin-{name}")
        d.val(f"""INSERT INTO public.ottoq_vehicle_itineraries (itinerary_id, vehicle_id, sim_run_id, status,
                                                                sim_created_at, visit_id)
                  VALUES ('{itin}', '{vid}', '{RUN}', 'active', '{T0}'::timestamptz - interval '15 minutes', '{visit}')""")
        d.val(f"""INSERT INTO public.ottoq_itinerary_legs (itinerary_id, vehicle_id, sim_run_id, seq, leg_type,
                                                           duration_basis, status, to_stall_id)
                  VALUES ('{itin}', '{vid}', '{RUN}', 1, 'charge_dcfc', '{{}}', 'active', '{arm._id(stall)}')""")
    return vid


def _tidies(d, car):
    return d.json(f"""SELECT COALESCE(jsonb_agg(a ORDER BY o), '[]') FROM public.ottoq_visit_needs n,
                              jsonb_array_elements(n.atoms) WITH ORDINALITY AS x(a, o)
                       WHERE n.vehicle_id = '{car}' AND a->>'svc' = 'interior_tidy'""")


def _meta(d, car):
    return d.json(f"SELECT meta FROM public.ottoq_visit_needs WHERE vehicle_id = '{car}'")


def _legs(d, car):
    return d.json(f"""SELECT COALESCE(jsonb_agg(to_jsonb(l) ORDER BY l.seq), '[]') FROM public.ottoq_itinerary_legs l
                       WHERE l.vehicle_id = '{car}' AND l.leg_type = 'interior_tidy'""")


def _state(d):
    return d.val("""SELECT jsonb_build_object(
                      'visits', (SELECT jsonb_agg(jsonb_build_object('k', visit_key, 'atoms', atoms, 'meta', meta,
                                                                     'status', status) ORDER BY visit_key)
                                   FROM public.ottoq_visit_needs),
                      'legs', (SELECT jsonb_agg(jsonb_build_object('v', vehicle_id, 'seq', seq, 'type', leg_type,
                                                                   'status', status) ORDER BY vehicle_id, seq)
                                 FROM public.ottoq_itinerary_legs))::text""")


def _scenario(d):
    """A car with no tidy, one with a cleared tidy, and one with a needed tidy, all on fast chargers; three passes."""
    _car(d, "plain", "DC-1", [CHARGE])
    _car(d, "cleared", "DC-2", [CHARGE, dict(arm.TIDY, status="cancelled", triage_verdict="clear")])
    for c in ("2026-09-01 14:00:00+00", "2026-09-01 14:05:00+00", "2026-09-01 14:10:00+00"):
        arm._advance(d, c)


# ── the fixture ──────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_premises_are_the_live_bodies(db):
    for fn, m in LIVE.items():
        assert arm._md5(db, fn) == m, fn


def test_it_applies_as_declared(db):
    _apply(db)
    cat = db.json("""SELECT to_jsonb(c) FROM public.ottoq_policy_param_catalog c WHERE param_key = 'stall_cabin_robot'""")
    assert (cat["default_value"], cat["min_value"], cat["max_value"]) == (0, 0, 2)
    assert "0764 (G483)" in cat["description"] and not cat["agent_writable"]
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0764_pre'") == "2"
    assert db.val("""SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage
                     WHERE name = '0764_every_car_that_charges_gets_the_overhead_arms_cabin_clean'""") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_policy_params WHERE param_key = 'stall_cabin_robot'") == "0"


# ── at 0 and 1 nothing moves ─────────────────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("value", [0, 1])
def test_at_0_and_1_the_same_world_is_byte_identical(template, value):
    states = []
    for with_0764 in (False, True):
        name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
        arm._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
        try:
            d = base.Db(name)
            if with_0764:
                _apply(d)
            if value:
                arm._dial(d, value)
            _scenario(d)
            states.append(_state(d))
        finally:
            arm._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
    assert states[0] == states[1]
    assert "arm_routine" not in states[1]


# ── at 2 the arm cleans every car that charges ───────────────────────────────────────────────────────────────────────

def test_a_charging_car_with_no_tidy_is_cleaned_by_the_arm_through_the_steps_own_pass(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "plain", "DC-1", [CHARGE])
    arm._advance(db, T0)
    [t] = _tidies(db, car)
    assert (t["status"], t["performed_by"], t["robot_stall_id"], t["arm_routine"]) == \
        ("in_progress", "stall_cabin_robot", arm._id("DC-1"), True)
    assert t["robot_cycle_min"] == 5.8 and t["must_do"] is True
    assert t["ends_at"].startswith("2026-09-01T14:05:48")
    [leg] = _legs(db, car)
    assert leg["leg_id"] == t["robot_leg_id"]
    assert (leg["status"], leg["seq"], leg["to_stall_id"]) == ("active", 2, arm._id("DC-1"))
    assert leg["duration_basis"] == {"atom": "interior_tidy", "kind": "stall_cabin_robot", "arm_routine": True,
                                     "concurrent_with": "charge"}
    assert float(leg["planned_duration_s"]) == 348
    m = _meta(db, car)["arm_routine"]
    assert (m["outcome"], m["stall_id"]) == ("cleaned", arm._id("DC-1"))
    assert arm._holds(db, car)
    # done at ends_at: its own leg closed by its id, the ledger credited, close_atom_leg not asked
    arm._advance(db, "2026-09-01 14:06:00+00")
    [t] = _tidies(db, car)
    assert (t["status"], t["done_at"]) == ("done", t["ends_at"])
    [leg] = _legs(db, car)
    assert leg["status"] == "done" and leg["actual_end_sim"].startswith("2026-09-01T14:05:48")
    assert float(leg["deviation_s"]) == 0
    assert db.val(f"SELECT count(*) FROM public._test_credits WHERE vehicle_id = '{car}' AND svc = 'interior_tidy'") == "1"
    assert db.val(f"SELECT count(*) FROM public._test_leg_closes WHERE vehicle_id = '{car}' AND svc = 'interior_tidy'") == "0"
    assert not arm._holds(db, car)
    # once a visit: the next passes add nothing
    arm._advance(db, "2026-09-01 14:10:00+00")
    assert len(_tidies(db, car)) == 1 and len(_legs(db, car)) == 1


def test_a_tidy_the_triage_cleared_still_gets_the_arm(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "cleared", "DC-1", [CHARGE, dict(arm.TIDY, status="cancelled", triage_verdict="clear",
                                                    cleared_by_triage=True)])
    arm._advance(db, T0)
    cleared, routine = _tidies(db, car)
    assert cleared["status"] == "cancelled" and "performed_by" not in cleared
    assert (routine["status"], routine["performed_by"], routine["arm_routine"]) == ("in_progress", "stall_cabin_robot", True)


def test_the_routine_takes_no_technician(db):
    """Two technicians, three charging cars with no tidy and one on a standard charger with a needed tidy: the arms
    clean the three, and the technicians still have both places for the fourth."""
    _apply(db)
    arm._dial(db, 2)
    cars = [_car(db, f"r{i}", s, [CHARGE]) for i, s in enumerate(["DC-1", "DC-2"])]
    l2 = _car(db, "l2", "L2-1", [CHARGE, dict(arm.TIDY)], state="charging_l2")
    arm._advance(db, T0)
    for c in cars:
        assert _tidies(db, c)[0]["performed_by"] == "stall_cabin_robot"
    [t] = _tidies(db, l2)
    assert t["status"] == "in_progress" and "performed_by" not in t
    assert "arm_routine" not in (_meta(db, l2) or {})


def test_a_tidy_waiting_on_the_triage_is_waited_for_then_the_arms_by_0758(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "uncertain", "DC-1", [CHARGE, dict(arm.TIDY, confirm_required=True, confidence=0.6)])
    arm._start(db, car)
    [t] = _tidies(db, car)
    assert t.get("status", "pending") == "pending" and "arm_routine" not in (_meta(db, car) or {})
    # the triage confirms it (as the completion step writes a confirm)
    db.val(f"""UPDATE public.ottoq_visit_needs n SET atoms = (
                 SELECT jsonb_agg(CASE WHEN a->>'svc' = 'interior_tidy'
                                       THEN a || '{{"confirm_required": false, "triage_verdict": "confirm"}}'::jsonb
                                       ELSE a END ORDER BY o)
                   FROM jsonb_array_elements(n.atoms) WITH ORDINALITY AS x(a, o))
               WHERE n.vehicle_id = '{car}'""")
    arm._start(db, car)
    [t] = _tidies(db, car)
    assert (t["status"], t["performed_by"]) == ("in_progress", "stall_cabin_robot")
    assert "arm_routine" not in t and "robot_leg_id" not in t
    assert "arm_routine" not in (_meta(db, car) or {}) and _legs(db, car) == []


def test_a_needed_tidy_is_0758s(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "needed", "DC-1", [CHARGE, dict(arm.TIDY)])
    arm._advance(db, T0)
    [t] = _tidies(db, car)
    assert (t["status"], t["performed_by"]) == ("in_progress", "stall_cabin_robot")
    assert "arm_routine" not in t and _legs(db, car) == []


def test_a_charge_shorter_than_the_cycle_is_skipped_once(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "short", "DC-1", [CHARGE])
    assert arm._start(db, car, left=3) == 0
    assert _tidies(db, car) == []
    m = _meta(db, car)["arm_routine"]
    assert (m["outcome"], m["charge_left_min"], m["cycle_min"]) == ("charge_shorter_than_the_cycle", 3, 5.8)
    # decided: a longer estimate later does not reopen it, and the step's pass no longer hands the car over
    assert arm._start(db, car, left=30) == 0
    assert _tidies(db, car) == [] and _meta(db, car)["arm_routine"] == m
    arm._advance(db, T0)
    assert _tidies(db, car) == []


def test_no_active_session_decides_nothing(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "nosession", "DC-1", [CHARGE], session=None)
    arm._advance(db, T0)
    assert _tidies(db, car) == [] and "arm_routine" not in (_meta(db, car) or {})


def test_a_standard_charger_is_left_alone(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "l2", "L2-1", [CHARGE], state="charging_l2")
    arm._advance(db, T0)
    arm._start(db, car)
    assert _tidies(db, car) == [] and "arm_routine" not in (_meta(db, car) or {})


def test_a_routine_clean_whose_car_left_the_post_is_cancelled(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "moved", "DC-1", [CHARGE])
    arm._advance(db, T0)
    # a charger fault moves the car to the other post mid-cycle
    db.val(f"UPDATE public.vehicles SET current_stall_id = '{arm._id('DC-2')}' WHERE id = '{car}'")
    arm._advance(db, "2026-09-01 14:06:00+00")
    [t] = _tidies(db, car)
    assert t["status"] == "cancelled"
    assert t["interrupted"][0]["reason"] == "left_the_cabin_robot"
    assert t["interrupted"][0]["stall_id"] == arm._id("DC-1")
    [leg] = _legs(db, car)
    assert leg["status"] == "skipped"
    assert db.val(f"SELECT count(*) FROM public._test_credits WHERE vehicle_id = '{car}'") == "0"


def test_a_visit_with_no_itinerary_is_still_cleaned(db):
    _apply(db)
    arm._dial(db, 2)
    car = _car(db, "noitin", "DC-1", [CHARGE], itinerary=False)
    arm._advance(db, T0)
    [t] = _tidies(db, car)
    assert t["performed_by"] == "stall_cabin_robot" and t["robot_leg_id"] is None
    arm._advance(db, "2026-09-01 14:06:00+00")
    assert _tidies(db, car)[0]["status"] == "done"
    assert db.val(f"SELECT count(*) FROM public._test_leg_closes WHERE vehicle_id = '{car}' AND svc = 'interior_tidy'") == "1"


# ── refusals ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_it_refuses_a_second_apply(db):
    _apply(db)
    rc, err = db.file(M0764)
    assert rc != 0 and "0764 P" in err


def test_it_refuses_a_body_it_did_not_read(db):
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_start_concurrent_atoms(p_vehicle uuid, p_clock timestamp with time zone)
              RETURNS integer LANGUAGE sql AS $$ SELECT 0 $$""")
    rc, err = db.file(M0764)
    assert rc != 0 and "0764 P1: a function this file patches" in err


def test_it_refuses_a_database_without_0763(db):
    db.val(f"DELETE FROM public.ottoq_cert_lineage WHERE name = '{L0763}'")
    rc, err = db.file(M0764)
    assert rc != 0 and "0763 is not applied" in err


def test_it_refuses_a_dial_not_as_0758_left_it(db):
    db.val("UPDATE public.ottoq_policy_param_catalog SET max_value = 3 WHERE param_key = 'stall_cabin_robot'")
    rc, err = db.file(M0764)
    assert rc != 0 and "not catalogued 0..1" in err
