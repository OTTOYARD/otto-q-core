"""db/migrations/0755, EXECUTED: a parked car leaves its stall before the bay calendar seats it.

WHY THIS EXISTS. Each tick the decide seats the cars whose bay reservation is due (ottoq.ottoq_activate_due_bay_reservations).
It moves the car and stamps it in the bay in one statement, so the triggers that free the car's old stall see a car already
in a bay leaving a stall: trg_reassignment_guard asks the in-depot gate, the gate defers an automated reassignment, the old
stall keeps the car, and the bay's claim on it trips idx_stalls_one_vehicle_per_stall (23505). The call then ends, every seat
with it (G471). 0743's test world leaves the stall triggers out, and there the same car is seated; this one carries them, as
live (tests/fixtures/bay_activation_guard_stub.sql, md5 asserted as read on 2026-10-18), on top of 0743's fixture. Every
claim in 0755's header that a test can execute is executed here:
  - on the live bodies a car parked on a staging stall, its wash reservation due and its bay free, is not seated, and the
    call fails on the one-stall index, as the server log says 235 calls did in a day; so does a car leaving a service bay for
    its wash, and with 0743's dial the refusal costs that seat and is recorded, and the car is still not seated;
  - a car off a charger with no arm holding it is seated before and after, so the defect is the parked car's;
  - 0755 needs 0743, applies after it, its checks run, it leaves the body it was written to leave, and a second apply is
    refused; it refuses a body it was not written against;
  - at the dial's default nothing changes;
  - with the dial the parked car is seated, its parking freed, one stall names it, and the gate is never asked;
  - with the dial the arm interlock still refuses a car the arm holds (alone, the call still ends; with 0743's dial too,
    that car waits and the parked one is seated), and a tether past its time that nothing has cleared no longer pins its
    charger;
  - the guard still keeps a car that is mid-work;
  - the pre-image puts 0743's body back.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)
import test_bay_activation_per_seat_sql as t43  # noqa: E402  (0743's fixture, world and helpers)

ROOT = base.ROOT
GUARD = os.path.join(ROOT, "tests", "fixtures", "bay_activation_guard_stub.sql")
M0755 = os.path.join(ROOT, "db", "migrations", "0755_a_parked_car_leaves_its_stall_before_the_calendar_seats_it.sql")
RUN, T, DEPOT, ACT = t43.RUN, t43.T, t43.DEPOT, t43.ACT
_id, _car, _hold, _mate, _state, _bay, _activate = t43._id, t43._car, t43._hold, t43._mate, t43._state, t43._bay, t43._activate

# the live bodies the guard fixture carries (md5 of prosrc, read from the live catalog on 2026-10-18)
LIVE = {
    "public.ottoq_stall_seat_is_exclusive()": "7ce8d314e45733b164b7ad183990f043",
    "public.ottoq_trg_reassignment_guard()": "b45ed80258565075f6cacc1e841d76c4",
    "public.update_timestamp()": "da5ac28a58c8b4bb30209bf0d3d7082c",
    "public.ottoq_indepot_reassignment_guard(uuid,uuid,text,jsonb)": "3a4e4a7a4288b31006bb1dbf966093fb",
    "public.ottoq_mark_reassign_granted(uuid)": "aca59505e95aacdf81e8b7fcf5206437",
}
AFTER_0743 = t43.AFTER_0743
SEED = 686364201590009433

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_bfp_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    t43._admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, t43.FIXTURE, GUARD):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        # arm 95's sweep and cell, as live (0755 no longer reads or copies them: its sweep was taken out, rule 12)
        d.val(f"""INSERT INTO public.ottoq_throughput_sweeps (sweep_code, title, depot_id, scenario, sim_start, ticks,
                                                              sim_min_per_tick, seeds, replicates, priority, arm_budget_s, status)
                  VALUES ('answer_normal_2026_10_17', 'answer in tick', '{DEPOT}', 'normal_day', '2026-09-01 11:00:00+00',
                          144, 5, ARRAY[{SEED}]::bigint[], 1, 15, 5400, 'active')""")
        d.val("""INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
                 SELECT sweep_id, 'dcfc40.otto_q.answer_in_tick', 3, 'otto_q', 'dcfc40',
                        '{"twin_answer_in_tick": 1, "deploy_peak_fraction": 0.9}'::jsonb
                   FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'answer_normal_2026_10_17'""")
        yield name
    finally:
        t43._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_bf_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    t43._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        t43._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply_0743(d):
    rc, err = d.file(t43.M0743)
    assert rc == 0, f"0743 did not apply: {err}"


def _apply(d):
    _apply_0743(d)
    rc, err = d.file(M0755)
    assert rc == 0, f"0755 did not apply: {err}"


def _dial(d, key, value):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{RUN}', '{key}', {value}, 'test', now())""")


def _call(d, clock=T):
    """The activation, with the server's warnings: the only trace a refused call leaves."""
    rc, out, err = d.run(f"SELECT ottoq.ottoq_activate_due_bay_reservations('{RUN}', '{DEPOT}', '{clock}')")
    assert rc == 0, err
    return int(out[-1]), err


def _world(d):
    """0743's world (three wash bays, a fast charger, staging) and a service bay."""
    t43._world(d)
    d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, display_name, status, distance_from_entrance)
              VALUES ('{_id('SVC-1')}', '{DEPOT}', 'SVC-1', 'service_bay', 'SVC-1', 'available', 9)""")


def _parked(d):
    """B is staged on a staging stall and its wash reservation on WSH-2 is due now; the bay is free."""
    _world(d)
    b = _car(d, "car-B", "staged_awaiting_service", "STG-1")
    _hold(d, b, "WSH-2")
    return b


def _names(d, car):
    return d.val(f"SELECT count(*) FROM public.stalls WHERE current_vehicle_id = '{car}'")


def test_the_fixture_is_the_live_bodies(db):
    for fn, md5 in {**t43.LIVE, **LIVE}.items():
        assert t43._md5(db, fn) == md5, fn
    assert db.val("""SELECT string_agg(tgname, ',' ORDER BY tgname) FROM pg_trigger
                      WHERE tgrelid = 'public.stalls'::regclass AND NOT tgisinternal""") \
        == "trg_ottoq_stall_seat_is_exclusive,trg_reassignment_guard,trg_stalls_updated"


def test_on_the_live_bodies_a_parked_car_is_not_seated_and_the_call_fails_on_the_one_stall_index(db):
    b = _parked(db)
    n, warn = _call(db)
    assert n == 0
    assert "sqlstate=23505" in warn and "idx_stalls_one_vehicle_per_stall" in warn
    assert _state(db, b) == "staged_awaiting_service STG-1"            # ready, its bay empty, and not seated
    assert _bay(db, "STG-1") == "car-B -" and _bay(db, "WSH-2") == "- -"
    assert db.val(f"SELECT state FROM public.ottoq_stall_bookings WHERE vehicle_id = '{b}'") == "held"
    assert db.val("SELECT count(*) FROM public.ottoq_ops_approvals") == "0"   # the gate's deferral rolled back with it
    assert db.val("SELECT count(*) FROM public.test_bay_commands") == "0"


def test_so_is_a_car_leaving_a_service_bay_for_its_wash(db):
    _world(db)
    c = _car(db, "car-C", "service_complete_holding", "SVC-1")
    _hold(db, c, "WSH-3")
    n, warn = _call(db)
    assert n == 0 and "sqlstate=23505" in warn
    assert _state(db, c) == "service_complete_holding SVC-1"


def test_with_0743s_dial_the_refusal_costs_that_seat_and_the_car_is_still_not_seated(db):
    _apply_0743(db)
    b = _parked(db)
    _dial(db, "bay_activation_per_seat", 1)
    n, _ = _call(db)
    assert n == 0
    assert _state(db, b) == "staged_awaiting_service STG-1"
    ev = db.json("""SELECT jsonb_agg(payload) FROM public.test_bay_events
                     WHERE event_type = 'ottoq.bay_reservation_seat_refused'""")
    assert len(ev) == 1 and [r["vehicle_id"] for r in ev[0]["refused"]] == [b]
    assert ev[0]["refused"][0]["sqlstate"] == "23505"


def test_a_car_off_a_charger_no_arm_holds_is_seated_before_and_after(db):
    _world(db)
    a = _car(db, "car-A", "charge_complete_holding", "CHG-1")
    _hold(db, a, "WSH-1")
    assert _call(db)[0] == 1                                           # the guard lets a charger go (0547, G276)
    assert _state(db, a) == "in_wash_bay WSH-1" and _bay(db, "CHG-1") == "- -"


def test_0755_needs_0743(db):
    rc, err = db.file(M0755)
    assert rc != 0 and "0755 P1" in err and "0743 is not applied" in err
    assert db.val("SELECT count(*) FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_activation_frees_parking'") == "0"


def test_0755_applies_after_0743_and_a_second_apply_is_refused(db):
    _apply(db)
    assert t43._md5(db, ACT) not in (AFTER_0743, t43.LIVE[ACT])
    assert db.val("""SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage
                      WHERE name = '0755_a_parked_car_leaves_its_stall_before_the_calendar_seats_it'""") == "falsefalse"
    assert db.val("""SELECT default_value || '/' || min_value || '/' || max_value || '/' || COALESCE(agent_writable, false)
                       FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_activation_frees_parking'""") == "0/0/1/false"
    # no sweep is queued: CLAUDE.md rule 12 stops the test program while the build goes on (0755 §2(c))
    assert db.val("SELECT count(*) FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'bayfree_normal_2026_10_18'") == "0"
    assert db.val("SELECT count(*) FROM public.ottoq_throughput_sweep_cells WHERE fixed_params ? 'bay_activation_frees_parking'") == "0"
    rc, err = db.file(M0755)
    assert rc != 0 and "0755 P" in err


def test_0755_refuses_a_body_it_was_not_written_against(db):
    _apply_0743(db)
    db.val("""CREATE OR REPLACE FUNCTION ottoq.ottoq_activate_due_bay_reservations(p_sim_run_id uuid, p_depot_id uuid,
                                                                                  p_clock timestamp with time zone)
              RETURNS integer LANGUAGE sql AS $$ SELECT 0 $$""")
    rc, err = db.file(M0755)
    assert rc != 0 and "0755 P1" in err and "80d42bc1" in err
    assert db.val("SELECT count(*) FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_activation_frees_parking'") == "0"


def test_at_the_default_nothing_changes(db):
    _apply(db)
    b = _parked(db)
    n, warn = _call(db)
    assert n == 0 and "sqlstate=23505" in warn
    assert _state(db, b) == "staged_awaiting_service STG-1"


def test_with_the_dial_the_parked_car_is_seated_and_its_parking_freed(db):
    _apply(db)
    b = _parked(db)
    _dial(db, "bay_activation_frees_parking", 1)
    n, warn = _call(db)
    assert n == 1, warn
    assert _state(db, b) == "in_wash_bay WSH-2"
    assert _bay(db, "WSH-2") == "car-B car-B" and _bay(db, "STG-1") == "- -"
    assert _names(db, b) == "1"                                        # one stall names it
    assert db.val(f"SELECT state || ' ' || booked_by FROM public.ottoq_stall_bookings WHERE vehicle_id = '{b}'") \
        == "active otto_q_enacted"
    assert db.val("SELECT count(*) FROM public.ottoq_ops_approvals") == "0"   # the gate was never asked
    assert db.val("SELECT string_agg(verb, ',') FROM public.test_bay_commands") == "enter_wash"


def test_with_the_dial_a_car_leaving_a_service_bay_is_seated_for_its_wash(db):
    _apply(db)
    _world(db)
    c = _car(db, "car-C", "service_complete_holding", "SVC-1")
    _hold(db, c, "WSH-3")
    _dial(db, "bay_activation_frees_parking", 1)
    assert _call(db)[0] == 1
    assert _state(db, c) == "in_wash_bay WSH-3" and _bay(db, "SVC-1") == "- -" and _names(db, c) == "1"


def test_with_the_dial_alone_the_arm_interlock_still_refuses_a_car_the_arm_holds(db):
    _apply(db)
    a, b = t43._a_held_car_and_a_ready_one(db)                         # A held by the arm on CHG-1; B parked on STG-1
    _dial(db, "bay_activation_frees_parking", 1)
    n, warn = _call(db)
    assert n == 0 and "arm interlock" in warn                          # the call still ends whole, as before 0743's dial
    assert _state(db, a) == "charge_complete_holding CHG-1" and _bay(db, "CHG-1") == "car-A -"
    assert _state(db, b) == "staged_awaiting_service STG-1"


def test_with_both_dials_the_held_car_waits_and_the_parked_one_is_seated(db):
    _apply(db)
    a, b = t43._a_held_car_and_a_ready_one(db)
    _dial(db, "bay_activation_per_seat", 1)
    _dial(db, "bay_activation_frees_parking", 1)
    assert _call(db)[0] == 1
    assert _state(db, b) == "in_wash_bay WSH-2" and _bay(db, "STG-1") == "- -"
    assert _state(db, a) == "charge_complete_holding CHG-1"            # left where the arm holds it
    assert db.val("SELECT count(*) FROM public.test_bay_events WHERE event_type = 'ottoq.bay_reservation_seat_refused'") == "0"


def test_with_the_dial_a_spent_tether_no_longer_pins_its_charger(db):
    """Past its time but not yet cleared, a tether names the charger: stamped in a bay first, the car leaving it is work cut
    short to the guard, and the charger keeps it (23505, recorded under 0743's dial). Moved first, it is a holding car."""
    _apply(db)
    a, b = t43._a_held_car_and_a_ready_one(db)
    _dial(db, "bay_activation_per_seat", 1)
    t5 = "2026-10-17 13:05:00+00"                                      # the tether ran to 13:03; nothing has cleared it
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_current = '{t5}' WHERE sim_run_id = '{RUN}'")
    assert _call(db, t5)[0] == 0                                       # without 0755's dial both are refused: A, its
    assert _state(db, a) == "charge_complete_holding CHG-1"            # charger pinned, and B, its parking (0743's test
    assert _state(db, b) == "staged_awaiting_service STG-1"            # world seats B; the live triggers do not)
    ev = db.json("""SELECT jsonb_agg(payload) FROM public.test_bay_events
                     WHERE event_type = 'ottoq.bay_reservation_seat_refused'""")
    assert sorted((r["vehicle_id"], r["sqlstate"]) for r in ev[0]["refused"]) == sorted([(a, "23505"), (b, "23505")])
    _dial(db, "bay_activation_frees_parking", 1)
    assert _call(db, t5)[0] == 2                                       # with it, A is seated from its charger, B from
    assert _state(db, a) == "in_wash_bay WSH-1" and _bay(db, "CHG-1") == "- -" and _names(db, a) == "1"
    assert _state(db, b) == "in_wash_bay WSH-2" and _bay(db, "STG-1") == "- -" and _names(db, b) == "1"   # its parking


def test_the_guard_still_keeps_a_car_that_is_mid_work(db):
    _apply(db)
    _world(db)
    w = _car(db, "car-W", "in_wash_bay", "WSH-1")
    db.val(f"UPDATE public.stalls SET current_vehicle_id = NULL WHERE id = '{_id('WSH-1')}'")
    assert _bay(db, "WSH-1") == "car-W -"                              # the gate deferred: the bay keeps its car
    assert db.val(f"SELECT count(*) FROM public.ottoq_ops_approvals WHERE vehicle_id = '{w}' AND status = 'pending'") == "1"


def test_the_pre_image_puts_0743s_body_back(db):
    _apply(db)
    db.val("""DO $$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0755_pre'); END $$""")
    assert t43._md5(db, ACT) == AFTER_0743
