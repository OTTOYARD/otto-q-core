"""db/migrations/0835, EXECUTED: a bay held for a car on its way in is not "idle with a car ready" (G541, second half).

WHY THIS EXISTS. The agent's board (0783, public.ottoq_depot_constraint) counted a bay busy by the cars whose state is
in that bay, and a ready car as any car in the bay's line that owes no charge. On 16 of 81 consulted boards on three
runs the wash bays read idle with a car ready; on 9 of the 16 a booking already on the calendar began within 1.1
minutes. Executed here on 0783's own harness (tests/test_depot_constraint_sql.py: the miniature depot through 0642 and
0781, 0783 applied from its file, so the function is the live definition, md5 pinned by 0835's P1):
  - 0835 applies, its checks run, it is classified FALSE/FALSE, the function's attributes hold, it refuses a second
    apply, a running run, a changed definition and a world without 0783, and CRLF line endings give the same body;
  - with nothing held and no car out of place, every count is what 0783 gave;
  - a bay a booking brings a car to within 10 minutes is held, not idle with a car ready, and that car is not ready;
    a booking further off holds nothing;
  - a bay a held booking covers now is busy though no car's state is in it; busy never exceeds the bays up;
  - a car in another bay, or in an emergency state, is not ready; nor is the car a bay is held for, for another bay;
  - a busy bay with its next car due is busy, not held; a released or done booking takes no bay; a car standing
    in a bay does;
  - the pre-image restores the function.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import sys
import tempfile

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402
import test_charge_order_exit_first_sql as xf  # noqa: E402
import test_depot_constraint_sql as tc  # noqa: E402  (0783's harness, shared on purpose)
from test_depot_constraint_sql import db, template  # noqa: F401,E402

ROOT = base.ROOT
NAME = "0835_a_bay_held_for_a_car_on_its_way_in_is_not_idle_with_a_car_ready"
M0835 = os.path.join(ROOT, "db", "migrations", NAME + ".sql")
FN = "public.ottoq_depot_constraint(uuid,uuid,timestamp with time zone)"
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_vid = base._vid
COUNTS = ("busy_now", "idle_now", "held_for_car_due", "idle_with_car_ready")

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _ready(d):
    """0783 applied and 0781's bays: SVC1 (Q in it, 25 minutes left), SVC2 idle, SVC3 in maintenance, W1 idle."""
    tc._apply(d)
    xf._bays(d)


def _apply(d):
    rc, err = d.file(M0835)
    assert rc == 0, f"0835 did not apply: {err}"
    return err


def _res(d):
    return {r["resource"]: r for r in tc._constraint(d)["resources"]}


def _full(d, car):
    d.val(f"UPDATE public.vehicles SET current_soc = 100 WHERE id = '{_vid(car)}'")


def _book(d, stall, car, start_min, end_min, state="held", purpose="service"):
    d.val(f"""INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_by)
              VALUES ('{RUN}', '{_vid(stall)}', '{_vid(car)}', '{purpose}',
                      tstzrange('{T}'::timestamptz + interval '{start_min} minutes',
                                '{T}'::timestamptz + interval '{end_min} minutes'), '{state}', 'otto_q')""")


def _attrs(d):
    return d.val(f"SELECT coalesce(proacl::text, chr(45)) || prosecdef::text || provolatile::text || "
                 f"coalesce(proconfig::text, chr(45)) FROM pg_proc WHERE oid = '{FN}'::regprocedure")


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0835_applies_keeps_the_functions_attributes_and_refuses_twice(db):
    _ready(db)
    before = _attrs(db)
    err = _apply(db)
    assert "0835 V2 PASSED" in err, err
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{NAME}'") == "falsefalse"
    assert _attrs(db) == before
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0835_pre'") == "1"
    rc, err = db.file(M0835)
    assert rc != 0 and "0835 P2: already applied" in err


def test_0835_applies_with_windows_line_endings_to_the_same_body(db):
    _ready(db)
    with open(M0835, newline="") as f:
        sql = f.read()
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, newline="") as t:
        t.write(sql.replace("\n", "\r\n"))
    try:
        rc, err = db.file(t.name)          # V3 holds the body to the md5 the tests ran
        assert rc == 0, err
    finally:
        os.unlink(t.name)


def test_0835_refuses_a_world_without_0783_a_running_run_and_a_changed_definition(db):
    rc, err = db.file(M0835)                                             # 0783 is not applied here yet
    assert rc != 0 and "0835 P1: 0783 is not applied" in err
    tc._apply(db)
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0835)
    assert rc != 0 and "0835 P0: a run is running" in err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    db.val(f"ALTER FUNCTION {FN} COST 101")
    rc, err = db.file(M0835)
    assert rc != 0 and "0835 P1: public.ottoq_depot_constraint is not the definition" in err
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0835_pre'") == "0"


# ── the counts, by hand ───────────────────────────────────────────────────────────────────────────────────────────────

def test_with_nothing_held_every_count_is_what_0783_gave(db):
    _ready(db)
    _full(db, "A")                                                       # A is ready for the idle service bay
    before = tc._constraint(db)
    _apply(db)
    after = tc._constraint(db)
    assert {k: v for k, v in after.items() if k != "resources"} == {k: v for k, v in before.items() if k != "resources"}
    for a, b in zip(after["resources"], before["resources"]):
        if a["resource"] == "posts":
            assert a == b and "held_for_car_due" not in a
        else:
            assert a.pop("held_for_car_due") == 0
            assert a == b
    res = _res(db)
    assert {k: res["service_bay"][k] for k in COUNTS} == {"busy_now": 1, "idle_now": 1, "held_for_car_due": 0,
                                                          "idle_with_car_ready": 1}


def test_a_bay_a_booked_car_reaches_within_ten_minutes_is_held_and_that_car_is_not_ready(db):
    _ready(db)
    _full(db, "A")
    _apply(db)
    _book(db, "SVC2", "A", 3, 43)                                        # the calendar has seated A; it is on its way in
    svc = _res(db)["service_bay"]
    assert {k: svc[k] for k in COUNTS} == {"busy_now": 1, "idle_now": 1, "held_for_car_due": 1, "idle_with_car_ready": 0}
    _full(db, "P")                                                       # a second ready car, and no bay left for it
    svc = _res(db)["service_bay"]
    assert svc["held_for_car_due"] == 1 and svc["idle_with_car_ready"] == 0
    assert svc["queued_cars"] == 5                                       # the line is not this migration's to change


def test_a_booking_further_off_holds_nothing_and_a_released_one_never_does(db):
    _ready(db)
    _full(db, "A")
    _apply(db)
    _book(db, "SVC2", "A", 10.5, 50)                                     # past the 10 minutes
    _book(db, "SVC2", "P", 2, 9, state="released")
    _book(db, "SVC2", "I", 2, 9, state="superseded")
    svc = _res(db)["service_bay"]
    assert {k: svc[k] for k in COUNTS} == {"busy_now": 1, "idle_now": 1, "held_for_car_due": 0, "idle_with_car_ready": 1}
    db.val("UPDATE public.ottoq_stall_bookings SET during = tstzrange(lower(during) - interval '30 seconds', upper(during)) "
           f"WHERE vehicle_id = '{_vid('A')}' AND state = 'held'")       # exactly 10 minutes: held
    svc = _res(db)["service_bay"]
    assert svc["held_for_car_due"] == 1 and svc["idle_with_car_ready"] == 0


def test_a_bay_a_held_booking_covers_now_is_busy_though_no_cars_state_is_in_it(db):
    _ready(db)
    xf._work(db, "B", [xf._wash(10)], arrived_min=35)
    _full(db, "B")
    _full(db, "C")
    _apply(db)
    wash = _res(db)["wash_bay"]
    assert {k: wash[k] for k in COUNTS} == {"busy_now": 0, "idle_now": 1, "held_for_car_due": 0, "idle_with_car_ready": 1}
    _book(db, "W1", "B", -1, 9, purpose="wash")                          # B's wash has begun on the calendar
    wash = _res(db)["wash_bay"]
    assert {k: wash[k] for k in COUNTS} == {"busy_now": 1, "idle_now": 0, "held_for_car_due": 0, "idle_with_car_ready": 0}
    assert wash["queued_cars"] == 2                                      # B and C still owe a wash


def test_busy_is_never_more_than_the_bays_up_and_a_car_in_a_bay_is_counted_once(db):
    _ready(db)
    _apply(db)
    db.val(f"UPDATE public.stalls SET current_vehicle_id = '{_vid('Q')}' WHERE id = '{_vid('SVC1')}'")
    assert _res(db)["service_bay"]["busy_now"] == 1                      # Q by state, by pointer and by booking: one bay
    db.val(f"UPDATE public.vehicles SET current_state = 'in_service_bay' WHERE id IN ('{_vid('D')}', '{_vid('P')}')")
    _book(db, "SVC2", "A", 2, 40)
    svc = _res(db)["service_bay"]                                        # three cars by state on two bays up
    assert {k: svc[k] for k in COUNTS} == {"busy_now": 2, "idle_now": 0, "held_for_car_due": 0, "idle_with_car_ready": 0}


def test_a_car_in_another_bay_or_in_an_emergency_state_is_not_ready(db):
    _ready(db)
    _full(db, "C")                                                       # C owes service work and a wash
    _apply(db)
    assert _res(db)["wash_bay"]["idle_with_car_ready"] == 1
    db.val(f"UPDATE public.vehicles SET current_state = 'in_service_bay' WHERE id = '{_vid('C')}'")
    assert _res(db)["wash_bay"]["idle_with_car_ready"] == 0              # C is in a service bay: the wash bay waits
    for state in ("emergency_staged", "tow_requested", "out_of_service"):
        db.val(f"UPDATE public.vehicles SET current_state = '{state}' WHERE id = '{_vid('C')}'")
        assert _res(db)["wash_bay"]["idle_with_car_ready"] == 0, state
    db.val(f"UPDATE public.vehicles SET current_state = 'staged_awaiting_service' WHERE id = '{_vid('C')}'")
    assert _res(db)["wash_bay"]["idle_with_car_ready"] == 1


def test_the_car_a_bay_is_held_for_is_not_ready_for_another_idle_bay(db):
    _ready(db)
    _full(db, "A")
    _apply(db)
    db.val(f"UPDATE public.stalls SET status = 'available' WHERE id = '{_vid('SVC3')}'")   # a third bay, idle
    _book(db, "SVC2", "A", 3, 43)
    svc = _res(db)["service_bay"]                                        # SVC2 is A's; SVC3 is idle and no other car is ready
    assert {k: svc[k] for k in COUNTS} == {"busy_now": 1, "idle_now": 2, "held_for_car_due": 1, "idle_with_car_ready": 0}
    _full(db, "P")
    assert _res(db)["service_bay"]["idle_with_car_ready"] == 1           # P is ready for SVC3


def test_a_busy_bay_with_the_next_car_due_is_busy_not_held(db):
    _ready(db)
    _full(db, "A")
    _apply(db)
    _book(db, "SVC1", "P", 5, 45)                                        # the next car on Q's bay; SVC2 stays idle
    svc = _res(db)["service_bay"]
    assert {k: svc[k] for k in COUNTS} == {"busy_now": 1, "idle_now": 1, "held_for_car_due": 0, "idle_with_car_ready": 1}


def test_a_released_booking_takes_no_bay_and_a_car_standing_in_one_does(db):
    _ready(db)
    _apply(db)
    _book(db, "W1", "C", -5, 5, state="released", purpose="wash")
    _book(db, "W1", "C", -5, 5, state="done", purpose="wash")
    assert _res(db)["wash_bay"]["busy_now"] == 0
    db.val(f"UPDATE public.stalls SET current_vehicle_id = '{_vid('I')}' WHERE id = '{_vid('SVC2')}'")
    svc = _res(db)["service_bay"]                                        # I stands in SVC2; its state has not moved yet
    assert svc["busy_now"] == 2 and svc["idle_now"] == 0


def test_the_pre_image_restores_the_function(db):
    _ready(db)
    before = xf._md5(db, FN)
    _apply(db)
    assert xf._md5(db, FN) != before
    rc, out, err = db.run(db.json("SELECT to_json(definition) FROM public.ottoq_schema_snapshots WHERE label = '0835_pre'"))
    assert rc == 0, err
    assert xf._md5(db, FN) == before
