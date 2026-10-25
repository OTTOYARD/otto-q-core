"""db/migrations/0780, EXECUTED: a car that owes no charge is ready for its bay, whatever its plan says.

WHY THIS EXISTS. The bay calendar asks whether a car is still charging by reading its itinerary: any charge leg planned,
active or in progress, not closed, with its planned end ahead (ottoq.ottoq_vehicle_bay_ready, and the reconcile's
BLOCKER 1, its verbatim twin). At an all-fast-charger depot the itinerary plans a standard charge that never runs (G459),
so a car at 100% waiting for its service bay reads as charging: it is not seated when its bay frees, and its hold is
released three minutes before its slot (G500: on run 78c0624c, 12 of 12 'charging' blocks were cars that owed nothing).
Every claim in 0780's header that a test can execute is executed here, on the scratch PostgreSQL, against the live
bodies (tests/fixtures/bay_activation_stub.sql and bay_activation_guard_stub.sql, brought to the live catalog by 0743,
0755 and 0744, md5 asserted as read on 2026-10-24):
  - before 0780, a full car with a leftover charge leg is not seated when its bay is free, and the reconcile moves its
    hold for a charge it does not owe;
  - 0780 applies, its checks run, it leaves the bodies it was written to leave, refuses a body it was not written
    against, and refuses a second apply;
  - at the dial's default nothing changes;
  - with the dial, the full car is seated the tick its bay frees, ahead of its slot, and the reconcile leaves its hold
    alone, whether its bay is free or another car is in it;
  - with the dial, a car that owes a charge, and a car on a charger, are blocked exactly as before;
  - the helper reads G244's one rule: below the car's one target less one, on a charger, or unknown;
  - the pre-images put the live bodies back.
A module template carries the stubs and the three applies, and each test clones it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)
import test_bay_activation_per_seat_sql as t43  # noqa: E402  (0743's fixture, world and helpers)
import test_bay_activation_frees_parking_sql as t55  # noqa: E402  (0755's guard fixture)
import test_bay_hold_follows_charge_sql as t44  # noqa: E402  (0744's migration)

ROOT = base.ROOT
M0780 = os.path.join(ROOT, "db", "migrations",
                     "0780_a_car_that_owes_no_charge_is_ready_for_its_bay_whatever_its_plan_says.sql")
NAME = "0780_a_car_that_owes_no_charge_is_ready_for_its_bay_whatever_its_plan_says"
RUN, T, DEPOT = t43.RUN, t43.T, t43.DEPOT
OPERATOR = "00000000-0000-0000-0000-0000000a0780"
_id, _state, _bay = t43._id, t43._state, t43._bay

READY = "ottoq.ottoq_vehicle_bay_ready(uuid,uuid,timestamp with time zone)"
REC = "ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)"
ACT = t43.ACT
# the live catalog, read 2026-10-24 (md5 of prosrc): 0743 then 0755 leave the activation, 0744 the reconcile
LIVE = {READY: "f52356da4a33742998c3fc69695e7bb9", REC: "75485e67a20dbb022fe23f817743d213",
        ACT: "6cd5d62340e49985723335013ea58214"}
# and as 0780 leaves them, read back from the live catalog after the apply (2026-10-24 16:38:30 UTC, ledger 20261024163830)
AFTER_0780 = {READY: "3e22ca9a550c0fa0573bb138d56936ce", REC: "2df40fc616882808b4a9b0d1952ff99b",
              "ottoq.ottoq_vehicle_owes_charge_now(uuid,timestamp with time zone)": "2fc1c5b5ac8f19096bb82dd7ad7a5ecb"}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_bre_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    t43._admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, t43.FIXTURE, t55.GUARD, t43.M0743, t55.M0755, t44.M0744):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        yield name
    finally:
        t43._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_br_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    t43._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        t43._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply(d):
    rc, err = d.file(M0780)
    assert rc == 0, f"0780 did not apply: {err}"
    return err


def _dial(d, key, value):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{RUN}', '{key}', {value}, 'test', now())
              ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value""")


def _world(d):
    """0743's world (three wash bays, a fast charger, staging), a service bay, the live dials the twin depot runs with
    (0743's per-seat activation, 0755's parked car leaving its stall, 0744's hold following a charge), and an owner."""
    t43._world(d)
    d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, display_name, status, distance_from_entrance)
              VALUES ('{_id('SVC-1')}', '{DEPOT}', 'SVC-1', 'service_bay', 'SVC-1', 'available', 9)""")
    d.val(f"""INSERT INTO public.ottoq_fleet_operator_slas (fleet_operator_id, status, version, effective_from,
                                                            max_queue_wait_minutes, max_charge_target_pct)
              VALUES ('{OPERATOR}', 'active', 1, '2026-01-01', 30, 100)""")
    for key in ("bay_activation_per_seat", "bay_activation_frees_parking", "bay_hold_follows_charge"):
        _dial(d, key, 1)


def _car(d, name, state, stall, soc):
    vid = t43._car(d, name, state, stall)
    d.val(f"UPDATE public.vehicles SET current_soc = {soc}, fleet_operator_id = '{OPERATOR}' WHERE id = '{vid}'")
    return vid


def _legs(d, car, charged_on_fast=True):
    """What the itinerary leaves a car at an all-fast-charger depot: the fast charge it really had, closed, and the
    standard charge the fixed rule planned (G459), never started, its planned end hours ahead."""
    if charged_on_fast:
        d.val(f"""INSERT INTO public.ottoq_itinerary_legs (sim_run_id, vehicle_id, seq, leg_type, status, planned_start_sim,
                                                           planned_end_sim, actual_start_sim, actual_end_sim)
                  VALUES ('{RUN}', '{car}', 7, 'charge_dcfc', 'done', '{T}'::timestamptz - interval '4 hours',
                          '{T}'::timestamptz - interval '3 hours 20 minutes', '{T}'::timestamptz - interval '4 hours',
                          '{T}'::timestamptz - interval '3 hours 18 minutes')""")
    d.val(f"""INSERT INTO public.ottoq_itinerary_legs (sim_run_id, vehicle_id, seq, leg_type, status, planned_start_sim,
                                                       planned_end_sim)
              VALUES ('{RUN}', '{car}', 1, 'charge_l2', 'planned', '{T}'::timestamptz + interval '175 minutes',
                      '{T}'::timestamptz + interval '400 minutes')""")


def _hold(d, car, bay, start_min, minutes=40, purpose="service"):
    """A hold the forward planner made four hours ago."""
    return d.val(f"""INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state,
                                                              booked_at, booked_by, booked_at_sim)
                     VALUES ('{RUN}', '{_id(bay)}', '{car}', '{purpose}',
                             tstzrange('{T}'::timestamptz + interval '{start_min} minutes',
                                       '{T}'::timestamptz + interval '{start_min + minutes} minutes', '[)'),
                             'held', '{T}'::timestamptz - interval '4 hours', 'otto_q',
                             '{T}'::timestamptz - interval '4 hours')
                     RETURNING booking_id""")


def _window(d, booking):
    return d.val(f"""SELECT round(extract(epoch FROM lower(b.during) - '{T}'::timestamptz) / 60) || '..'
                            || round(extract(epoch FROM upper(b.during) - '{T}'::timestamptz) / 60) || ' ' || b.state || ' '
                            || s.stall_code || ' ' || COALESCE(b.source, '-')
                       FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
                      WHERE b.booking_id = '{booking}'""")


def _log(d):
    return d.json("""SELECT COALESCE(jsonb_agg(jsonb_build_object('action', action, 'reason', reason, 'blocked_by', blocked_by)
                                       ORDER BY id), '[]')
                       FROM public.bay_reservation_reconcile_2026_08_02""")


def _ready(d, car):
    return d.val(f"SELECT ottoq.ottoq_vehicle_bay_ready('{RUN}', '{car}', '{T}')::text")


def _owes(d, car, clock=T):
    return d.val(f"SELECT ottoq.ottoq_vehicle_owes_charge_now('{car}', '{clock}')::text")


def _activate(d):
    return int(d.val(f"SELECT ottoq.ottoq_activate_due_bay_reservations('{RUN}', '{DEPOT}', '{T}')"))


def _reconcile(d):
    return int(d.val(f"SELECT ottoq.ottoq_reconcile_bay_reservations('{RUN}', '{DEPOT}', '{T}')"))


def _full_car_and_its_hold(d, start_min=20):
    """05b0de6f on 78c0624c, in miniature: charged to 100% hours ago, parked in staging, a preventive maintenance owed on a
    service bay that is free now, held for it from start_min minutes."""
    _world(d)
    car = _car(d, "car-F", "staged_awaiting_service", "STG-1", 100)
    _legs(d, car)
    return car, _hold(d, car, "SVC-1", start_min)


# ── the template is the live catalog ──────────────────────────────────────────────────────────────────────────────────

def test_the_template_carries_the_live_bodies(db):
    for fn, md5 in LIVE.items():
        assert t43._md5(db, fn) == md5, fn


# ── before 0780 ───────────────────────────────────────────────────────────────────────────────────────────────────────

def test_before_0780_a_full_car_with_a_leftover_charge_leg_waits_by_its_empty_bay(db):
    car, hold = _full_car_and_its_hold(db)
    assert _ready(db, car) == "false"                       # the plan says it is still charging
    assert _activate(db) == 0
    assert _state(db, car) == "staged_awaiting_service STG-1"
    assert _bay(db, "SVC-1") == "- -"                        # the depot's wall stands empty
    assert _window(db, hold) == "20..60 held SVC-1 -"


def test_before_0780_the_reconcile_moves_a_full_cars_hold_for_a_charge_it_does_not_owe(db):
    car, hold = _full_car_and_its_hold(db, start_min=2)      # inside the reconcile's three-minute reach
    assert _reconcile(db) == 1
    assert _log(db) == [{"action": "deferred", "reason": "vehicle_not_yet_releasable", "blocked_by": "charging"}]
    assert _window(db, hold).startswith("403..443 held")   # to the leftover leg's end and the taxi


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0780_applies_and_a_second_apply_is_refused(db):
    _world(db)
    _car(db, "car-F", "staged_awaiting_service", "STG-1", 100)
    err = _apply(db)
    assert "0780 V2: the helper agrees with G244's rule on" in err, err
    assert db.val(f"""SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage
                       WHERE name = '{NAME}'""") == "falsefalse"
    assert db.val("""SELECT default_value || '/' || min_value || '/' || max_value || '/' || COALESCE(agent_writable, false)
                       FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_ready_reads_energy'""") == "0/0/1/false"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0780_pre'") == "2"
    for fn, md5 in AFTER_0780.items():
        assert t43._md5(db, fn) == md5, fn                    # the bodies the live catalog carries since the apply
    for role, can in (("service_role", "true"), ("authenticated", "false"), ("anon", "false")):
        assert db.val(f"""SELECT has_function_privilege('{role}',
                            'ottoq.ottoq_vehicle_owes_charge_now(uuid,timestamp with time zone)', 'EXECUTE')::text""") == can
    rc, err = db.file(M0780)
    assert rc != 0 and "0780 P1: ottoq.ottoq_vehicle_bay_ready is not the body" in err, err   # its own patch, read back


def test_0780_refuses_a_body_it_was_not_written_against(db):
    db.val("""CREATE OR REPLACE FUNCTION ottoq.ottoq_vehicle_bay_ready(p_sim_run_id uuid, p_vehicle_id uuid,
                                                                     p_clock timestamp with time zone)
              RETURNS boolean LANGUAGE sql AS $$ SELECT true $$""")
    rc, err = db.file(M0780)
    assert rc != 0 and "0780 P1: ottoq.ottoq_vehicle_bay_ready is not the body" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_ready_reads_energy'") == "0"


# ── at the default ────────────────────────────────────────────────────────────────────────────────────────────────────

def test_at_the_default_nothing_changes(db):
    _apply(db)
    car, hold = _full_car_and_its_hold(db)
    assert _ready(db, car) == "false"
    assert _activate(db) == 0
    assert _bay(db, "SVC-1") == "- -"
    db.val(f"UPDATE public.ottoq_stall_bookings SET during = tstzrange('{T}'::timestamptz + interval '2 minutes', "
           f"'{T}'::timestamptz + interval '42 minutes', '[)') WHERE booking_id = '{hold}'")
    assert _reconcile(db) == 1
    assert _log(db)[0]["blocked_by"] == "charging"


# ── with the dial ─────────────────────────────────────────────────────────────────────────────────────────────────────

def test_with_the_dial_a_full_car_is_seated_the_tick_its_bay_frees(db):
    _apply(db)
    car, hold = _full_car_and_its_hold(db)
    _dial(db, "bay_ready_reads_energy", 1)
    assert _ready(db, car) == "true"
    assert _activate(db) == 1
    assert _state(db, car) == "in_service_bay SVC-1"
    assert _bay(db, "SVC-1") == "car-F car-F"
    assert _window(db, hold) == "0..40 active SVC-1 bay_reservation_activated_early"   # its own slot, brought forward
    assert db.val("SELECT verb FROM public.test_bay_commands") == "enter_service"
    assert _bay(db, "STG-1") == "- -"                                                    # 0755: its parking freed


def test_with_the_dial_the_reconcile_leaves_a_full_cars_hold_alone(db):
    _apply(db)
    car, hold = _full_car_and_its_hold(db, start_min=2)
    _dial(db, "bay_ready_reads_energy", 1)
    assert _reconcile(db) == 0                              # its bay free: left for the activation (0015)
    assert _window(db, hold) == "2..42 held SVC-1 -" and _log(db) == []
    # and with another car in the bay, it is not blocked for a charge it does not owe either
    other = _car(db, "car-O", "staged_awaiting_service", "STG-2", 100)
    db.val(f"UPDATE public.stalls SET current_vehicle_id = '{other}', status = 'occupied' WHERE id = '{_id('SVC-1')}'")
    assert _reconcile(db) == 0
    assert _window(db, hold) == "2..42 held SVC-1 -" and _log(db) == []


def test_with_the_dial_a_car_that_owes_a_charge_is_blocked_as_before(db):
    _apply(db)
    _world(db)
    car = _car(db, "car-L", "staged_awaiting_service", "STG-1", 80)   # cut short by a fault, owing the rest
    _legs(db, car)
    hold = _hold(db, car, "SVC-1", 2)
    _dial(db, "bay_ready_reads_energy", 1)
    assert _ready(db, car) == "false"
    assert _reconcile(db) == 1
    assert _log(db) == [{"action": "deferred", "reason": "vehicle_not_yet_releasable", "blocked_by": "charging"}]
    assert _window(db, hold).startswith("403..443 held")


def test_with_the_dial_a_car_on_a_charger_is_blocked_as_before(db):
    _apply(db)
    _world(db)
    car = _car(db, "car-C", "charging_dcfc", "CHG-1", 100)   # at 100% and still on the post: a charge not yet closed
    db.val(f"""INSERT INTO public.ottoq_itinerary_legs (sim_run_id, vehicle_id, seq, leg_type, status, planned_start_sim,
                                                        planned_end_sim, actual_start_sim)
               VALUES ('{RUN}', '{car}', 1, 'charge_dcfc', 'active', '{T}'::timestamptz - interval '30 minutes',
                       '{T}'::timestamptz + interval '10 minutes', '{T}'::timestamptz - interval '30 minutes')""")
    hold = _hold(db, car, "SVC-1", 2)
    _dial(db, "bay_ready_reads_energy", 1)
    assert _ready(db, car) == "false"
    assert _reconcile(db) == 1
    assert _log(db) == [{"action": "deferred", "reason": "vehicle_not_yet_releasable", "blocked_by": "charging"}]
    assert _window(db, hold).startswith("13..53 held")      # the leg's end and the taxi, as before


# ── the helper ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_helper_reads_g244s_one_rule(db):
    _apply(db)
    _world(db)
    cars = {soc: _car(db, f"car-{soc}", "staged_awaiting_service", f"STG-{i + 1}", soc)
            for i, soc in enumerate((98, 99, 100))}
    assert [_owes(db, cars[s]) for s in (98, 99, 100)] == ["true", "false", "false"]   # below 100 less one owes
    db.val(f"UPDATE public.vehicles SET current_state = 'charging_dcfc' WHERE id = '{cars[100]}'")
    assert _owes(db, cars[100]) == "true"                                                 # on a charger: rule 9
    db.val(f"UPDATE public.vehicles SET current_soc = NULL WHERE id = '{cars[99]}'")
    assert _owes(db, cars[99]) == "true"                                                  # unknown: the old answer
    assert _owes(db, str(uuid.uuid4())) == "true"
    # an owner's lower limit is the car's one target: at 85, a car at 84 owes nothing
    db.val("UPDATE public.ottoq_fleet_operator_slas SET max_charge_target_pct = 85")
    db.val(f"UPDATE public.vehicles SET current_soc = 84, current_state = 'staged_awaiting_service' WHERE id = '{cars[98]}'")
    assert _owes(db, cars[98]) == "false"


def test_the_pre_images_put_the_live_bodies_back(db):
    _apply(db)
    db.val("""DO $$ DECLARE r record; BEGIN
                FOR r IN SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0780_pre' LOOP
                  EXECUTE r.definition;
                END LOOP; END $$""")
    assert t43._md5(db, READY) == LIVE[READY]
    assert t43._md5(db, REC) == LIVE[REC]
