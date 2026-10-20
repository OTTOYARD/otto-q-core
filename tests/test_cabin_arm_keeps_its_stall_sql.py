"""db/migrations/0760, EXECUTED: a car the cleaning arm is cleaning keeps its stall when the charge arm lets go.

WHY THIS EXISTS. On the live run c6ec017d (2026-10-20, the twin depot, stall_cabin_robot on) car ca2624fc's charge reached
100% while the fast charger's cleaning arm was still in its cabin. The charge arm demated, and the tether sweep
(public.ottoq_release_expired_tethers) cleared the car's stall and freed the stall in the same tick, 15 seconds before the
arm was home. With the car on no stall, 0758's hold no longer applied: decide section (4b) took the car (first written
here as the bay calendar; the run's decision rows say (4b)), and the tidy was put back to pending, nothing credited
(G479). (4b) never read the hold either; 0761 closes that door (tests/test_held_car_is_passed_over_sql.py). 0760 keeps an expired demate tether while its stall's arm is at work in the car.
Executed here, on the scratch PostgreSQL, against the sweep as live (tests/fixtures/release_expired_tethers_stub.sql,
prosrc md5 asserted as read on 2026-10-20), with 0760 run whole:
  - before 0760 the sweep takes the car off the stall mid-clean (the defect, reproduced);
  - after it, the car keeps its stall and the stall keeps the car while the arm works, and the first sweep after the
    arm's work is done releases both exactly as before;
  - a car with no arm at work, an arm at work on another stall, a technician's tidy, a finished clean, a closed visit,
    a charging tether's lapse and an inbound tether all sweep as before;
  - 0760 applies, leaves the body it was written to leave (the body less its insertion is its pre-image), stores the
    pre-image, and refuses a second apply, a body it did not read and a database without 0758.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)

ROOT = base.ROOT
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "release_expired_tethers_stub.sql")
M0760 = os.path.join(ROOT, "db", "migrations",
                     "0760_a_car_the_cleaning_arm_is_cleaning_keeps_its_stall_when_the_charge_arm_lets_go.sql")
SWEEP = "public.ottoq_release_expired_tethers(timestamp with time zone)"
LIVE = "e93c55436dca059c95b6462873b704ba"  # prosrc md5, read from the live catalog on 2026-10-20
NAME = "0760_a_car_the_cleaning_arm_is_cleaning_keeps_its_stall_when_the_charge_arm_lets_go"
RUN = "a0000000-0000-0000-0000-000000000760"
NOW = "2026-09-01 14:45:01+00"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0760-{name}"))


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        rc, err = d.file(FIXTURE)
        assert rc == 0, f"the fixture did not load: {err}"
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
    rc, err = d.file(M0760)
    assert rc == 0, f"0760 did not apply: {err}"


def _md5(d):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{SWEEP}')")


def _stall(d, code):
    sid = _id(code)
    d.val(f"INSERT INTO public.stalls (id, status) VALUES ('{sid}', 'occupied')")
    return sid


def _car(d, name, stall, direction="demate", expired=True, atoms=(), visit_status="in_progress"):
    """A car on `stall` whose charge arm's tether (direction) has run out (or not), and its visit with `atoms`."""
    vid = _id(name)
    until = f"'{NOW}'::timestamptz - interval '1 second'" if expired else f"'{NOW}'::timestamptz + interval '1 minute'"
    d.val(f"""INSERT INTO public.vehicles (id, current_stall_id, robotic_tether_until, robotic_tether_stall_id,
                                           robotic_tether_direction, robotic_tether_phase)
              VALUES ('{vid}', '{stall}', {until}, '{stall}', '{direction}',
                      '{"clear" if direction == "demate" else direction}')""")
    d.val(f"UPDATE public.stalls SET current_vehicle_id = '{vid}' WHERE id = '{stall}'")
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, status, atoms)
              VALUES ('{vid}', '{RUN}', '{visit_status}', '{json.dumps(list(atoms))}'::jsonb)""")
    return vid


def _arm_tidy(stall, status="in_progress"):
    return {"svc": "interior_tidy", "must_do": True, "concurrency": "cabin", "status": status,
            "performed_by": "stall_cabin_robot", "robot_stall_id": stall,
            "started_at": "2026-09-01T14:39:28+00:00", "ends_at": "2026-09-01T14:45:16+00:00"}


def _sweep(d, at=NOW):
    return int(d.val(f"SELECT public.ottoq_release_expired_tethers('{at}'::timestamptz)"))


def _where(d, vid, stall):
    """(the car's stall, its tether stall, its tether direction, the stall's car, the stall's status)"""
    return tuple(d.val(f"""SELECT concat_ws('|', COALESCE(v.current_stall_id::text, '-'),
                                              COALESCE(v.robotic_tether_stall_id::text, '-'),
                                              COALESCE(v.robotic_tether_direction, '-'),
                                              COALESCE(s.current_vehicle_id::text, '-'), s.status)
                             FROM public.vehicles v, public.stalls s
                            WHERE v.id = '{vid}' AND s.id = '{stall}'""").split("|"))


def _released(vid, stall):
    return ("-", "-", "-", "-", "available")


def _held(vid, stall):
    return (stall, stall, "demate", vid, "occupied")


# ── the fixture is the sweep as live ──

def test_the_fixture_carries_the_live_sweep(db):
    assert _md5(db) == LIVE


# ── the defect, reproduced on the live body ──

def test_before_0760_the_sweep_takes_the_car_off_its_stall_mid_clean(db):
    s = _stall(db, "DCFC-08")
    v = _car(db, "ca2624fc", s, atoms=[_arm_tidy(s)])
    assert _sweep(db) == 1
    assert _where(db, v, s) == _released(v, s)


# ── after 0760 ──

def test_after_0760_the_car_keeps_its_stall_while_the_arm_works(db):
    _apply(db)
    s = _stall(db, "DCFC-08")
    v = _car(db, "ca2624fc", s, atoms=[{"svc": "charge", "status": "done"}, _arm_tidy(s)])
    assert _sweep(db) == 0
    assert _where(db, v, s) == _held(v, s)
    # and again on the next tick, while the arm is still at work
    assert _sweep(db, "2026-09-01 14:45:10+00") == 0
    assert _where(db, v, s) == _held(v, s)


def test_after_0760_the_first_sweep_after_the_arm_is_done_releases_the_car_as_before(db):
    _apply(db)
    s = _stall(db, "DCFC-08")
    v = _car(db, "ca2624fc", s, atoms=[_arm_tidy(s)])
    assert _sweep(db) == 0
    db.val(f"""UPDATE public.ottoq_visit_needs
                  SET atoms = jsonb_set(atoms, '{{0,status}}', '"done"')
                WHERE vehicle_id = '{v}'""")
    assert _sweep(db, "2026-09-01 14:45:20+00") == 1
    assert _where(db, v, s) == _released(v, s)


@pytest.mark.parametrize("case", ["no_arm_work", "arm_on_another_stall", "technicians_tidy", "arm_done",
                                  "visit_closed", "arm_pending"])
def test_after_0760_a_car_the_arm_is_not_cleaning_on_that_stall_is_released_as_before(db, case):
    _apply(db)
    s = _stall(db, "DCFC-08")
    other = _stall(db, "DCFC-07")
    atoms = {
        "no_arm_work": [{"svc": "charge", "status": "done"}],
        "arm_on_another_stall": [_arm_tidy(other)],
        "technicians_tidy": [{**_arm_tidy(s), "performed_by": "general_tech", "robot_stall_id": None}],
        "arm_done": [_arm_tidy(s, status="done")],
        "visit_closed": [_arm_tidy(s)],
        "arm_pending": [{**_arm_tidy(s), "status": "pending"}],
    }[case]
    v = _car(db, f"car-{case}", s, atoms=atoms, visit_status="complete" if case == "visit_closed" else "in_progress")
    assert _sweep(db) == 1
    assert _where(db, v, s) == _released(v, s)


def test_after_0760_a_malformed_visit_does_not_stop_the_sweep(db):
    """The sweep swallows its own errors and returns 0, so a predicate that raised on one malformed visit would release
    no tether at all. A visit whose atoms are not an array is read as having none."""
    _apply(db)
    s = _stall(db, "DCFC-08")
    v = _car(db, "odd", s, atoms=[])
    db.val(f"UPDATE public.ottoq_visit_needs SET atoms = '{{\"svc\": \"interior_tidy\"}}'::jsonb WHERE vehicle_id = '{v}'")
    s2 = _stall(db, "DCFC-09")
    v2 = _car(db, "plain", s2, atoms=[{"svc": "charge", "status": "done"}])
    assert _sweep(db) == 2
    assert _where(db, v, s) == _released(v, s)
    assert _where(db, v2, s2) == _released(v2, s2)


@pytest.mark.parametrize("direction", ["charging", "mate"])
def test_after_0760_a_charging_or_inbound_tether_lapses_as_before(db, direction):
    """Only a demate releases the stall, before and after 0760; a charging or inbound tether's lapse clears the tether
    and keeps the car where it is, with the arm at work or not."""
    for applied in (False, True):
        name = f"x_{direction}_{int(applied)}"
        if applied:
            _apply(db)
        s = _stall(db, f"DC-{name}")
        v = _car(db, name, s, direction=direction, atoms=[_arm_tidy(s)])
        assert _sweep(db) >= 1
        assert _where(db, v, s) == (s, "-", "-", v, "occupied")


def test_after_0760_a_tether_not_yet_expired_is_left_alone(db):
    _apply(db)
    s = _stall(db, "DCFC-08")
    v = _car(db, "fresh", s, expired=False, atoms=[_arm_tidy(s)])
    assert _sweep(db) == 0
    assert _where(db, v, s) == _held(v, s)


def test_after_0760_the_sweep_counts_only_what_it_released(db):
    """Two cars at once: the one the arm is cleaning is kept, the other is released, and the count says one."""
    _apply(db)
    s1, s2 = _stall(db, "DCFC-01"), _stall(db, "DCFC-02")
    kept = _car(db, "kept", s1, atoms=[_arm_tidy(s1)])
    gone = _car(db, "gone", s2, atoms=[{"svc": "charge", "status": "done"}])
    assert _sweep(db) == 1
    assert _where(db, kept, s1) == _held(kept, s1)
    assert _where(db, gone, s2) == _released(gone, s2)


# ── the file itself ──

def test_0760_applies_leaves_its_body_and_stores_the_preimage(db):
    _apply(db)
    after = _md5(db)
    assert after != LIVE
    assert db.val(f"SELECT count(*) FROM public.ottoq_cert_lineage WHERE name = '{NAME}' AND NOT forces_recert "
                  "AND NOT forces_dial_restart") == "1"
    pre = db.val("SELECT def_md5 = md5(definition) AND definition LIKE '%robotic_tether_until <= v_now%' "
                 "AND definition NOT LIKE '%0760%' FROM public.ottoq_schema_snapshots WHERE label = '0760_pre'")
    assert pre == "t"
    # the stored body carries the insertion once (V1, inside the file, proved the rest is the live body)
    assert db.val(f"""SELECT (length(prosrc) - length(replace(prosrc, '0760 (G479)', ''))) / length('0760 (G479)')
                        FROM pg_proc WHERE oid = to_regprocedure('{SWEEP}')""") == "1"


def test_0760_refuses_a_second_apply(db):
    _apply(db)
    rc, err = db.file(M0760)
    assert rc != 0 and "0760 P1: already applied" in err


def test_0760_refuses_a_body_it_did_not_read(db):
    db.val(f"""CREATE OR REPLACE FUNCTION public.ottoq_release_expired_tethers(p_now timestamptz DEFAULT NULL)
               RETURNS integer LANGUAGE sql AS $$ SELECT 0 $$""")
    rc, err = db.file(M0760)
    assert rc != 0 and "0760 P1: public.ottoq_release_expired_tethers is not the body read" in err
    assert db.val(f"SELECT count(*) FROM public.ottoq_cert_lineage WHERE name = '{NAME}'") == "0"


def test_0760_refuses_a_database_without_0758(db):
    db.val("DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0758%'")
    rc, err = db.file(M0760)
    assert rc != 0 and "0760 P1: 0758 is not applied" in err
    assert _md5(db) == LIVE
