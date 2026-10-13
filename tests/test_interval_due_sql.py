"""db/migrations/0715, EXECUTED: a car with preventive maintenance or calibration due gets it before it leaves.

WHY THIS EXISTS. CLAUDE.md rule 9 names preventive maintenance and calibration among the services finished before a car
leaves. The visit planner added those atoms only when the twin's observer drew them, so a car recalled because its
interval was due could get a visit with neither and leave (G218 / G181; 0704's scouts, db/checks/0440 §13). Executed here
on a stub engine whose planner is the live ottoq.ottoq_derive_visit_needs byte for byte (md5 cd5c513b):
  - before 0715 a car with PM due and no PM drawn gets a visit with no PM (the defect, reproduced);
  - after it the due interval puts its atom on the visit, required, not deferrable, not carried over, tagged;
  - an atom the observer drew is upgraded when due and left as drawn when not; never duplicated;
  - a car with nothing due gets nothing new; the car's own interval wins, the run's dial stands in when it has none.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "derive_visit_needs_stub.sql")
M0715 = os.path.join(ROOT, "db", "migrations", "0715_a_car_with_maintenance_or_calibration_due_gets_it_before_it_leaves.sql")
RUN = "a0000000-0000-0000-0000-000000000715"
DEPOT = "11111111-1111-1111-1111-111111111111"
CAR = "c0000000-0000-0000-0000-000000000715"
T = "2026-10-13 15:00:00+00"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture()
def db():
    name = f"ottoq_interval_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        d.val(f"INSERT INTO ottoq_sim_runs VALUES ('{RUN}', '{DEPOT}')")
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _car(d, km_since=0, h_since=0, pm_km=78, cal_h=4.85, soc=100):
    cfg = {}
    if pm_km is not None:
        cfg["pm_interval_km"] = pm_km
    if cal_h is not None:
        cfg["calib_interval_h"] = cal_h
    d.val(f"""INSERT INTO vehicles VALUES ('{CAR}', NULL, {soc}, 75, 150, '{json.dumps(cfg)}')""")
    d.val(f"""INSERT INTO ottoq_vehicle_wear VALUES ('{CAR}', '{RUN}', 0, {1000 + km_since}, 1000,
                                                   {50 + h_since}, 50, now())""")


def _derive_raw(d, obs=None):
    o = {"observer": "test"} | (obs or {})
    return d.json(f"""SELECT ottoq.ottoq_derive_visit_needs('{CAR}', '{RUN}', '{RUN}', '{T}', '{DEPOT}',
                                                         '{json.dumps(o)}'::jsonb)""")


def _derive(d, obs=None):
    return {a["svc"]: a for a in _derive_raw(d, obs)}


def test_0715_the_live_planner_is_the_one_in_the_stub(db):
    assert db.val("SELECT md5(pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,"
                  "uuid,jsonb)'::regprocedure))") == "cd5c513bb164a14614003e308009a347"


def test_0715_before_it_a_car_with_pm_due_and_none_drawn_gets_no_pm(db):
    _car(db, km_since=100)
    assert "mechanical_pm" not in _derive(db)                                   # the defect


def test_0715_a_due_interval_puts_its_work_on_the_visit_required(db):
    rc, err = db.file(M0715)
    assert rc == 0 and "0715 V1 PASSED" in err, err
    _car(db, km_since=100, h_since=5)
    atoms = _derive(db)
    for svc in ("mechanical_pm", "sensor_calibration"):
        a = atoms[svc]
        assert a["must_do"] is True and a["deferrable"] is False and a["carryover_eligible"] is False, a
        assert a["interval_due"] is True and a["requires_bay"] == "service_bay", a
    assert atoms["mechanical_pm"]["est_min"] == 40 and atoms["sensor_calibration"]["est_min"] == 60
    # and the ledger row the departure test reads carries them
    stored = db.json(f"SELECT atoms FROM ottoq_visit_needs WHERE vehicle_id = '{CAR}' AND status = 'open'")
    assert {a["svc"] for a in stored} >= {"mechanical_pm", "sensor_calibration"}


def test_0715_a_drawn_atom_is_upgraded_when_due_and_left_as_drawn_when_not(db):
    db.file(M0715)
    _car(db, km_since=100, h_since=1)                                            # PM due, calibration not
    raw = _derive_raw(db, {"mechanical_pm": True, "sensor_calibration": True})
    svcs = [a["svc"] for a in raw]
    assert svcs.count("mechanical_pm") == 1 and svcs.count("sensor_calibration") == 1, svcs   # never two
    atoms = {a["svc"]: a for a in raw}
    assert atoms["mechanical_pm"]["deferrable"] is False and atoms["mechanical_pm"]["interval_due"] is True
    assert atoms["sensor_calibration"]["deferrable"] is True and "interval_due" not in atoms["sensor_calibration"]


def test_0715_nothing_due_adds_nothing_and_the_runs_dial_stands_in_for_a_missing_interval(db):
    db.file(M0715)
    _car(db, km_since=50, h_since=1)
    atoms = _derive(db)
    assert "mechanical_pm" not in atoms and "sensor_calibration" not in atoms
    db.val(f"DELETE FROM ottoq_visit_needs; DELETE FROM vehicles; DELETE FROM ottoq_vehicle_wear")
    _car(db, km_since=100, h_since=1, pm_km=None, cal_h=None)                   # no interval of its own: 8000 / 250
    assert "mechanical_pm" not in _derive(db)
    db.val(f"INSERT INTO ottoq_policy_params VALUES ('run', '{RUN}', 'pm_interval_km', 90, 'test', now())")
    assert _derive(db)["mechanical_pm"]["interval_due"] is True
