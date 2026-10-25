"""db/migrations/0767, EXECUTED: a routine cabin clean that a charger fault cut short is done by the arm at the car's
next post.

WHY THIS EXISTS. Chase, 2026-10-23: "cars should be cleaned via overhead arm while they charge always regardless" (0765,
G484). On run 78c0624c car 12cb06f0's routine clean began at CANOPY-03 W-23 at sim 14:18:27, the charger faulted at
14:20:09 and let the car go, the completion step cancelled the routine (0764: it was not a need), and the car charged 25
minutes on CANOPY-03 E-29 with no clean: the starter records the routine once a visit, as it begins, so a routine cut
short read as decided and was never begun again. Executed here, on the scratch PostgreSQL, over 0765's test world (0758's
fixture with 0758, 0764 and 0765 applied: the live starter and completion step, md5 asserted) with 0767 run whole:
  - at 0 and at 1 the same world is byte-identical with and without 0767;
  - before 0767, at 2, a routine a fault cut short is never begun again on the car's next post: the gap;
  - at 2 the completion step hands the car to the starter at its next post, whose arm cleans it as a routine, with its
    own leg and the hold, its record naming both posts, and the clean completes and is not repeated; a routine cut short
    twice is done at the third post;
  - a car off any post is not decided until it charges again; a needed tidy cut short is the next arm's by 0758's
    branch, as before 0767; an immediate turnaround stays recorded once;
  - 0767 applies as declared, with Windows line endings too, and refuses a second apply, a body it did not read, a
    database without 0765 and a dial not as 0765 left it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)
import test_stall_cabin_robot_sql as arm  # noqa: E402  (0758's fixture, world and helpers)
import test_every_car_cabin_clean_sql as e764  # noqa: E402  (0764's file and premises)
import test_every_charge_is_cleaned_sql as e765  # noqa: E402  (0765's file, fixture and helpers)

ROOT = base.ROOT
M0767 = os.path.join(ROOT, "db", "migrations",
                     "0767_a_cabin_clean_a_charger_fault_cut_short_is_done_at_the_cars_next_post.sql")
RUN = arm.RUN
T0 = arm.T0
START, ADVANCE = arm.START, arm.ADVANCE
# what 0765 left and live carries (prosrc md5, read on live 2026-10-24 04:05 UTC), and what 0767 leaves (V3)
LIVE = {START: "5b98fb1dbd54fb0baf9f39f77ca2660c", ADVANCE: "fb7cde232a1b8311eb2f768c812f4c9a"}
AFTER = {START: "25052205e0b6aa2c74504652b840869c", ADVANCE: "99f6aa09e973fcb914ae67f1328c0d49"}
L0765 = e765.L0765
L0767 = "0767_a_cabin_clean_a_charger_fault_cut_short_is_done_at_the_cars_next_post"
CHARGE = e764.CHARGE
TIDY = arm.TIDY

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


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
        rc, err = d.file(e765.FIXTURE)
        assert rc == 0, f"{os.path.basename(e765.FIXTURE)} did not load: {err}"
        e765._apply(d)
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


def _apply(d, path=M0767):
    rc, err = d.file(path)
    assert rc == 0, f"0767 did not apply: {err}"


def _fault_and_replug(d, car, to_stall, at):
    """A charger fault: the session ends faulted, the car is moved off its post; then the re-queued car plugs into the
    next post with a new active session, as the twin's charge line does."""
    d.val(f"UPDATE public.ocpp_sessions SET status = 'faulted' WHERE vehicle_id = '{car}' AND status = 'active'")
    d.val(f"UPDATE public.vehicles SET current_stall_id = NULL, current_state = 'arrived_at_gate' WHERE id = '{car}'")
    e765._advance(d, at)                       # the cycle has run out off the post: the routine is cancelled
    d.val(f"""UPDATE public.vehicles SET current_stall_id = '{arm._id(to_stall)}', current_state = 'charging_dcfc'
              WHERE id = '{car}'""")
    d.val(f"""INSERT INTO public.ocpp_sessions (depot_id, stall_id, vehicle_id, status, started_at, soc_start, sim_run_id)
              VALUES ('{base.DEPOT}', '{arm._id(to_stall)}', '{car}', 'active', '{at}', 40, '{RUN}')""")


def _routines(d, car):
    return [t for t in e765._tidies(d, car) if t.get("arm_routine")]


# ── the premises ─────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_premises_are_the_live_bodies(db):
    for fn, m in LIVE.items():
        assert arm._md5(db, fn) == m, fn


def test_it_applies_as_declared(db):
    _apply(db)
    assert (arm._md5(db, START), arm._md5(db, ADVANCE)) == (AFTER[START], AFTER[ADVANCE])
    cat = db.json("""SELECT to_jsonb(c) FROM public.ottoq_policy_param_catalog c WHERE param_key = 'stall_cabin_robot'""")
    assert (cat["default_value"], cat["min_value"], cat["max_value"]) == (0, 0, 2) and not cat["agent_writable"]
    assert "0765 (G484), 0767 (G486):" in cat["description"]
    assert "again at the car's next post when a charger fault" in cat["description"]
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0767_pre'") == "2"
    assert db.val(f"""SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage
                      WHERE name = '{L0767}'""") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_policy_params WHERE param_key = 'stall_cabin_robot'") == "0"


def test_a_paste_with_windows_line_endings_applies_to_the_same_body(db, tmp_path):
    with open(M0767, "rb") as f:
        text = f.read()
    assert b"\r" not in text
    crlf = tmp_path / "0767_crlf.sql"
    crlf.write_bytes(text.replace(b"\n", b"\r\n"))
    rc, err = db.file(str(crlf))
    assert rc == 0, f"0767 with CRLF did not apply: {err}"
    assert (arm._md5(db, START), arm._md5(db, ADVANCE)) == (AFTER[START], AFTER[ADVANCE])


# ── at 0 and 1 nothing moves ─────────────────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("value", [0, 1])
def test_at_0_and_1_the_same_world_is_byte_identical(template, value):
    states = []
    for with_0767 in (False, True):
        name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
        arm._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
        try:
            d = base.Db(name)
            if with_0767:
                _apply(d)
            if value:
                arm._dial(d, value)
            e765._scenario(d)
            car = e765._car(d, "faulted", "DC-1", [CHARGE])
            e765._advance(d, "2026-09-01 14:12:00+00", left=30)
            _fault_and_replug(d, car, "DC-2", "2026-09-01 14:20:00+00")
            e765._advance(d, "2026-09-01 14:21:00+00", left=30)
            states.append(e765._state(d))
        finally:
            arm._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
    assert states[0] == states[1]
    assert "arm_routine" not in states[1]


# ── the gap, at 2 before 0767 ────────────────────────────────────────────────────────────────────────────────────────

def test_before_0767_a_routine_a_fault_cut_short_is_never_begun_again(db):
    arm._dial(db, 2)
    car = e765._car(db, "faulted", "DC-1", [CHARGE])
    e765._advance(db, T0, left=30)
    [t] = _routines(db, car)
    assert (t["status"], t["robot_stall_id"]) == ("in_progress", arm._id("DC-1"))
    _fault_and_replug(db, car, "DC-2", "2026-09-01 14:06:00+00")
    [t] = _routines(db, car)
    assert t["status"] == "cancelled" and t["interrupted"][0]["reason"] == "left_the_cabin_robot"
    for clock in ("2026-09-01 14:07:00+00", "2026-09-01 14:20:00+00"):
        e765._advance(db, clock, left=30)
    assert [t["status"] for t in _routines(db, car)] == ["cancelled"]
    assert e765._meta(db, car)["arm_routine"]["stall_id"] == arm._id("DC-1")


# ── at 2 the next post's arm cleans it ───────────────────────────────────────────────────────────────────────────────

def test_the_next_posts_arm_cleans_the_car_and_the_record_names_both_posts(db):
    _apply(db)
    arm._dial(db, 2)
    car = e765._car(db, "faulted", "DC-1", [CHARGE])
    e765._advance(db, T0, left=30)
    _fault_and_replug(db, car, "DC-2", "2026-09-01 14:06:00+00")
    e765._advance(db, "2026-09-01 14:07:00+00", left=30)
    first, second = _routines(db, car)
    assert first["status"] == "cancelled" and first["robot_stall_id"] == arm._id("DC-1")
    assert (second["status"], second["performed_by"], second["robot_stall_id"]) == \
        ("in_progress", "stall_cabin_robot", arm._id("DC-2"))
    meta = e765._meta(db, car)["arm_routine"]
    assert (meta["outcome"], meta["stall_id"]) == ("cleaned", arm._id("DC-2"))
    assert (meta["after"]["outcome"], meta["after"]["stall_id"]) == ("cleaned", arm._id("DC-1"))
    legs = e765._legs(db, car)
    assert [(l["status"], l["to_stall_id"]) for l in legs] == [("skipped", arm._id("DC-1")), ("active", arm._id("DC-2"))]
    # the hold: the car stays on its post until the arm is home
    assert db.val(f"SELECT ottoq.ottoq_uplink_transfer_holds('{car}', '{RUN}')") == "t"


def test_the_second_clean_completes_and_is_not_repeated(db):
    _apply(db)
    arm._dial(db, 2)
    car = e765._car(db, "faulted", "DC-1", [CHARGE])
    e765._advance(db, T0, left=30)
    _fault_and_replug(db, car, "DC-2", "2026-09-01 14:06:00+00")
    e765._advance(db, "2026-09-01 14:07:00+00", left=30)
    for clock in ("2026-09-01 14:13:00+00", "2026-09-01 14:20:00+00", "2026-09-01 14:30:00+00"):
        e765._advance(db, clock, left=30)
    assert [t["status"] for t in _routines(db, car)] == ["cancelled", "done"]
    assert [l["status"] for l in e765._legs(db, car)] == ["skipped", "done"]


def test_a_routine_cut_short_twice_is_done_at_the_third_post(db):
    _apply(db)
    arm._dial(db, 2)
    car = e765._car(db, "twice", "DC-1", [CHARGE])
    e765._advance(db, T0, left=30)
    _fault_and_replug(db, car, "DC-2", "2026-09-01 14:06:00+00")
    e765._advance(db, "2026-09-01 14:07:00+00", left=30)
    _fault_and_replug(db, car, "DC-1", "2026-09-01 14:13:00+00")
    e765._advance(db, "2026-09-01 14:14:00+00", left=30)
    assert [t["status"] for t in _routines(db, car)] == ["cancelled", "cancelled", "in_progress"]
    meta = e765._meta(db, car)["arm_routine"]
    assert meta["stall_id"] == arm._id("DC-1") and meta["after"]["stall_id"] == arm._id("DC-2")
    assert meta["after"]["after"]["stall_id"] == arm._id("DC-1")


def test_a_car_off_any_post_is_not_decided_until_it_charges_again(db):
    _apply(db)
    arm._dial(db, 2)
    car = e765._car(db, "waiting", "DC-1", [CHARGE])
    e765._advance(db, T0, left=30)
    db.val(f"UPDATE public.ocpp_sessions SET status = 'faulted' WHERE vehicle_id = '{car}' AND status = 'active'")
    db.val(f"UPDATE public.vehicles SET current_stall_id = NULL, current_state = 'arrived_at_gate' WHERE id = '{car}'")
    for clock in ("2026-09-01 14:06:00+00", "2026-09-01 14:10:00+00"):
        e765._advance(db, clock, left=30)
        arm._start(db, car, clock)
    assert [t["status"] for t in _routines(db, car)] == ["cancelled"]
    assert e765._meta(db, car)["arm_routine"]["stall_id"] == arm._id("DC-1")
    assert "after" not in e765._meta(db, car)["arm_routine"]


def test_a_needed_tidy_cut_short_is_the_next_arms_by_0758s_branch_as_before(db):
    _apply(db)
    arm._dial(db, 2)
    car = e765._car(db, "needed", "DC-1", [CHARGE, dict(TIDY)])
    e765._advance(db, T0, left=30)
    [t] = e765._tidies(db, car)
    assert t["performed_by"] == "stall_cabin_robot" and not t.get("arm_routine")
    _fault_and_replug(db, car, "DC-2", "2026-09-01 14:06:00+00")
    e765._advance(db, "2026-09-01 14:07:00+00", left=30)
    [t] = e765._tidies(db, car)   # one atom, back to pending and taken again: no routine is added
    assert (t["status"], t["performed_by"], t["robot_stall_id"]) == ("in_progress", "stall_cabin_robot", arm._id("DC-2"))
    assert t["interrupted"][0]["reason"] == "left_the_cabin_robot"
    assert "arm_routine" not in e765._meta(db, car)


def test_an_immediate_turnaround_stays_recorded_once(db):
    _apply(db)
    arm._dial(db, 2)
    car = e765._car(db, "rush", "DC-1", [CHARGE], urgency="immediate_dispatch")
    e765._advance(db, T0, left=3)
    assert e765._meta(db, car)["arm_routine"]["outcome"] == "immediate_turnaround"
    _fault_and_replug(db, car, "DC-2", "2026-09-01 14:06:00+00")
    e765._advance(db, "2026-09-01 14:07:00+00", left=3)
    assert _routines(db, car) == []
    meta = e765._meta(db, car)["arm_routine"]
    assert meta["outcome"] == "immediate_turnaround" and "after" not in meta


# ── refusals ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_it_refuses_a_second_apply(db):
    _apply(db)
    rc, err = db.file(M0767)
    assert rc != 0 and "0767 P" in err


@pytest.mark.parametrize("fn", [START, ADVANCE])
def test_it_refuses_a_body_it_did_not_read(db, fn):
    db.val(f"""DO $x$ BEGIN EXECUTE replace(pg_get_functiondef('{fn}'::regprocedure), 'BEGIN', E'BEGIN\\n  -- edited');
               END $x$""")
    rc, err = db.file(M0767)
    assert rc != 0 and "0767 P1: a function this file patches" in err


def test_it_refuses_a_database_without_0765(db):
    db.val(f"DELETE FROM public.ottoq_cert_lineage WHERE name = '{L0765}'")
    rc, err = db.file(M0767)
    assert rc != 0 and "0765 is not applied" in err


def test_it_refuses_a_dial_not_as_0765_left_it(db):
    db.val("UPDATE public.ottoq_policy_param_catalog SET max_value = 3 WHERE param_key = 'stall_cabin_robot'")
    rc, err = db.file(M0767)
    assert rc != 0 and "not catalogued 0..2 as 0765 left it" in err
