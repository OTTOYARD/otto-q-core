"""db/migrations/0792, EXECUTED: a faulted post lets its car go, whatever the cleaning arm is doing (G506).

WHY THIS EXISTS. On demo run 8c0b2e04 (2026-11-02, the twin depot, stall_cabin_robot on) two cars whose fast chargers
faulted while the post's cleaning arm was in their cabin were held on the dead post 309 and 339 s, until the 5.8-minute
clean ran out: 0760's hold in public.ottoq_release_expired_tethers keeps an expired demate tether while the stall's arm
is at work, and never asks why the charge ended. Chase saw it in the twin: "a faulted charger station was given a
vehicle to charge/clean".
Executed here, on the scratch PostgreSQL, against the sweep as live: the fixture of 0760's test with 0760 applied
reproduces the live body (prosrc md5 bad69ddf, read 2026-11-03 04:00 UTC); then 0792 runs whole:
  - before 0792 a car whose charger faulted mid-clean keeps its stall (the defect, reproduced);
  - after it, that car is released when its demate window ends, and its stall with it;
  - 0760's hold stands for a charge that ended normally, for a charger in any other state, and for a stall with no
    charger; a car with no arm at work is released as before; charging and inbound tethers lapse as before;
  - two cars in one sweep, one on a faulted post and one on a healthy post, are released and kept respectively;
  - 0792 applies, leaves the body it was written to leave, stores the pre-image, and refuses a second apply, a body it
    did not read and a database without 0760.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)
import test_cabin_arm_keeps_its_stall_sql as c760  # noqa: E402  (0760's fixture, cars and tidies)

ROOT = base.ROOT
M0792 = os.path.join(ROOT, "db", "migrations",
                     "0792_a_faulted_post_lets_its_car_go_whatever_the_cleaning_arm_is_doing.sql")
SWEEP = c760.SWEEP
LIVE = "bad69ddf41e763b91e7f18c3d28d7d02"  # prosrc md5 of the sweep after 0760, read from the live catalog 2026-11-03
NAME = "0792_a_faulted_post_lets_its_car_go_whatever_the_cleaning_arm_is_doing"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

# the two tables the new predicate joins, as live (only the columns it reads)
CHARGERS = """
ALTER TABLE public.stalls ADD COLUMN IF NOT EXISTS ocpp_charger_id uuid;
CREATE TABLE IF NOT EXISTS public.ottoq_ocpp_chargers (charger_id uuid PRIMARY KEY, station_state text NOT NULL);
"""


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0792-{name}"))


@pytest.fixture(scope="module")
def template():
    """0760's fixture, the chargers table, and 0760 applied: the sweep as live tonight."""
    name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        rc, err = d.file(c760.FIXTURE)
        assert rc == 0, f"the fixture did not load: {err}"
        rc, _, err = d.run(CHARGERS)
        assert rc == 0, f"the chargers table did not load: {err}"
        rc, err = d.file(c760.M0760)
        assert rc == 0, f"0760 did not apply: {err}"
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
    rc, err = d.file(M0792)
    assert rc == 0, f"0792 did not apply: {err}"


def _post(d, code, state="Available"):
    """A fast-charger stall (occupied) on its own charger in `state`; state None: a stall with no charger."""
    sid = c760._stall(d, f"0792-{code}")
    if state is not None:
        cid = _id(f"charger-{code}")
        d.val(f"INSERT INTO public.ottoq_ocpp_chargers (charger_id, station_state) VALUES ('{cid}', '{state}')")
        d.val(f"UPDATE public.stalls SET ocpp_charger_id = '{cid}' WHERE id = '{sid}'")
    return sid


def _fault(d, stall):
    d.val(f"""UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted'
               WHERE charger_id = (SELECT ocpp_charger_id FROM public.stalls WHERE id = '{stall}')""")


_sweep, _where, _released, _held, _arm_tidy = c760._sweep, c760._where, c760._released, c760._held, c760._arm_tidy


def _md5(d):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{SWEEP}')")


# ── the scratch sweep is the live sweep ──

def test_the_scratch_sweep_is_the_live_sweep(db):
    assert _md5(db) == LIVE


# ── the defect, reproduced on the live body ──

def test_before_0792_a_car_whose_charger_faulted_mid_clean_keeps_the_dead_post(db):
    s = _post(db, "DCFC-22")
    v = c760._car(db, "2cd2cbf3", s, atoms=[{"svc": "charge", "status": "in_progress"}, _arm_tidy(s)])
    _fault(db, s)
    assert _sweep(db) == 0
    assert _where(db, v, s) == _held(v, s)


# ── after 0792 ──

def test_after_0792_a_car_whose_charger_faulted_mid_clean_is_released_when_its_demate_ends(db):
    _apply(db)
    s = _post(db, "DCFC-22")
    v = c760._car(db, "2cd2cbf3", s, atoms=[{"svc": "charge", "status": "in_progress"}, _arm_tidy(s)])
    _fault(db, s)
    assert _sweep(db) == 1
    assert _where(db, v, s) == _released(v, s)


def test_after_0792_the_tether_still_runs_its_window_on_a_faulted_post(db):
    """The fault does not cut the robot's demate short: a tether not yet expired keeps the car, as before."""
    _apply(db)
    s = _post(db, "DCFC-02")
    v = c760._car(db, "ca2624fc", s, expired=False, atoms=[_arm_tidy(s)])
    _fault(db, s)
    assert _sweep(db) == 0
    assert _where(db, v, s) == _held(v, s)


@pytest.mark.parametrize("state", ["Available", "Occupied", "Charging", "Unavailable", None])
def test_after_0792_the_cleaning_arm_still_holds_its_car_on_a_post_that_did_not_fault(db, state):
    """0760's hold stands wherever the charger is not Faulted, including a stall with no charger at all."""
    _apply(db)
    s = _post(db, f"DCFC-{state}", state=state)
    v = c760._car(db, f"held-{state}", s, atoms=[{"svc": "charge", "status": "done"}, _arm_tidy(s)])
    assert _sweep(db) == 0
    assert _where(db, v, s) == _held(v, s)


def test_after_0792_a_faulted_post_with_no_arm_at_work_releases_its_car_as_before(db):
    _apply(db)
    s = _post(db, "DCFC-18")
    v = c760._car(db, "c3333333", s, atoms=[{"svc": "charge", "status": "in_progress"}])
    _fault(db, s)
    assert _sweep(db) == 1
    assert _where(db, v, s) == _released(v, s)


def test_after_0792_a_fault_on_another_post_does_not_release_a_car_its_own_arm_is_cleaning(db):
    _apply(db)
    s, other = _post(db, "DCFC-07"), _post(db, "DCFC-08")
    v = c760._car(db, "kept", s, atoms=[_arm_tidy(s)])
    _fault(db, other)
    assert _sweep(db) == 0
    assert _where(db, v, s) == _held(v, s)


@pytest.mark.parametrize("direction", ["charging", "mate"])
def test_after_0792_a_charging_or_inbound_tether_lapses_as_before_on_a_faulted_post(db, direction):
    """Only a demate releases the stall; a charging or inbound tether's lapse clears the tether and keeps the car."""
    _apply(db)
    s = _post(db, f"DC-{direction}")
    v = c760._car(db, f"x-{direction}", s, direction=direction, atoms=[_arm_tidy(s)])
    _fault(db, s)
    assert _sweep(db) >= 1
    assert _where(db, v, s) == (s, "-", "-", v, "occupied")


def test_after_0792_one_sweep_releases_the_faulted_posts_car_and_keeps_the_healthy_posts(db):
    _apply(db)
    bad, good = _post(db, "DCFC-22"), _post(db, "DCFC-23")
    gone = c760._car(db, "gone", bad, atoms=[_arm_tidy(bad)])
    kept = c760._car(db, "kept2", good, atoms=[_arm_tidy(good)])
    _fault(db, bad)
    assert _sweep(db) == 1
    assert _where(db, gone, bad) == _released(gone, bad)
    assert _where(db, kept, good) == _held(kept, good)


def test_after_0792_the_released_car_is_not_kept_by_the_next_sweep_either(db):
    """Released once, the car is off the post; a later sweep has nothing to do with it."""
    _apply(db)
    s = _post(db, "DCFC-29")
    v = c760._car(db, "5ea53696", s, atoms=[_arm_tidy(s)])
    _fault(db, s)
    assert _sweep(db) == 1
    assert _sweep(db, "2026-09-01 14:46:01+00") == 0
    assert _where(db, v, s) == _released(v, s)


# ── the file itself ──

def test_0792_applies_leaves_its_body_and_stores_the_preimage(db):
    _apply(db)
    assert _md5(db) != LIVE
    assert db.val(f"SELECT count(*) FROM public.ottoq_cert_lineage WHERE name = '{NAME}' AND NOT forces_recert "
                  "AND NOT forces_dial_restart") == "1"
    pre = db.val("SELECT def_md5 = md5(definition) AND definition LIKE '%0760 (G479)%' "
                 "AND definition NOT LIKE '%0792%' FROM public.ottoq_schema_snapshots WHERE label = '0792_pre'")
    assert pre == "t"
    assert db.val(f"""SELECT (length(prosrc) - length(replace(prosrc, '0792 (G506)', ''))) / length('0792 (G506)')
                        FROM pg_proc WHERE oid = to_regprocedure('{SWEEP}')""") == "1"


def test_0792_refuses_a_second_apply(db):
    _apply(db)
    rc, err = db.file(M0792)
    assert rc != 0 and "0792 P1: already applied" in err


def test_0792_refuses_a_body_it_did_not_read(db):
    db.val(f"""CREATE OR REPLACE FUNCTION {SWEEP.replace('(timestamp with time zone)', '')}(p_now timestamptz DEFAULT NULL)
               RETURNS integer LANGUAGE sql AS $$ SELECT 0 $$""")
    rc, err = db.file(M0792)
    assert rc != 0 and "0792 P1: public.ottoq_release_expired_tethers is not the body read" in err


def test_0792_refuses_a_database_without_0760(db):
    db.val("DELETE FROM public.ottoq_cert_lineage "
           "WHERE name = '0760_a_car_the_cleaning_arm_is_cleaning_keeps_its_stall_when_the_charge_arm_lets_go'")
    rc, err = db.file(M0792)
    assert rc != 0 and "0792 P1: 0760 is not applied" in err
