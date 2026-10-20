"""db/migrations/0744, EXECUTED: a bay hold follows a charge that runs past its plan, instead of holding an empty bay.

WHY THIS EXISTS. The reconcile (ottoq.ottoq_reconcile_bay_reservations) moves a due bay hold whose car cannot be there
yet, and one of its tests is an unfinished charge leg, read only by the leg's planned end. A charge that runs past its
plan is invisible to it, so the hold sat on its empty bay through its window and the no-show grace (G458: 24 of 34 wash
no-shows on four arms, charges a mean 17-42 minutes past plan). Every claim in 0744's header that a test can execute is
executed here, on the scratch PostgreSQL, against the live reconcile (tests/fixtures/bay_activation_stub.sql, md5
asserted as read on 2026-10-17):
  - before 0744, a hold whose car is charging past its plan is left on its bay;
  - 0744 applies, its checks run, it leaves the body it was written to leave, and a second apply is refused;
  - at the dial's default the hold is still left on its bay;
  - with the dial, it is blocked one service length ahead and deferred as any blocked hold is, and logged as such;
  - a charge still planned to end later, and a car that is not charging, are reconciled exactly as before;
  - the defer cap still releases a hold whose charge runs on;
  - the pre-image in ottoq_schema_snapshots puts the live body back.
A module template carries the base stub and the fixture, and each test clones it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402
import test_bay_activation_per_seat_sql as bap  # noqa: E402  (the 0743 world: depot, bays, cars, holds, template)

ROOT = base.ROOT
M0744 = os.path.join(ROOT, "db", "migrations", "0744_a_bay_hold_follows_a_charge_that_runs_past_its_plan.sql")
REC = "ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)"
LIVE_REC = "f6d8b538c30d7fa1198c5165fe9dd152"
AFTER_0744 = "75485e67a20dbb022fe23f817743d213"
RUN, DEPOT, T = bap.RUN, bap.DEPOT, bap.T
_id = bap._id

template = bap.template   # the same module template (base stub + fixture)
db = bap.db

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _apply(d):
    rc, err = d.file(M0744)
    assert rc == 0, f"0744 did not apply: {err}"


def _charging(d, name, planned_end_min, state="charging_dcfc"):
    """A car on the fast charger whose charge leg was planned to end at T + planned_end_min, not yet closed."""
    car = bap._car(d, name, state, "CHG-1")
    d.val(f"""INSERT INTO public.ottoq_itinerary_legs (sim_run_id, vehicle_id, seq, leg_type, status, planned_start_sim,
                                                       planned_end_sim, actual_start_sim)
              VALUES ('{RUN}', '{car}', 1, 'charge_dcfc', 'active', '{T}'::timestamptz - interval '60 minutes',
                      '{T}'::timestamptz + interval '{planned_end_min} minutes', '{T}'::timestamptz - interval '55 minutes')""")
    return car


def _reconcile(d, clock=T):
    return int(d.val(f"SELECT ottoq.ottoq_reconcile_bay_reservations('{RUN}', '{DEPOT}', '{clock}')"))


def _dial(d, value):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{RUN}', 'bay_hold_follows_charge', {value}, 'test', now())""")


def _window(d, booking):
    """The hold as minutes from T, its state and its bay."""
    return d.val(f"""SELECT round(extract(epoch FROM lower(b.during) - '{T}'::timestamptz) / 60) || '..'
                            || round(extract(epoch FROM upper(b.during) - '{T}'::timestamptz) / 60) || ' ' || b.state || ' '
                            || s.stall_code
                       FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
                      WHERE b.booking_id = '{booking}'""")


def _log(d):
    return d.json("""SELECT COALESCE(jsonb_agg(jsonb_build_object('action', action, 'reason', reason, 'blocked_by', blocked_by,
                                                               'defer_seq', defer_seq) ORDER BY id), '[]')
                       FROM public.bay_reservation_reconcile_2026_08_02 WHERE action IN ('deferred', 'released')""")


def _overrun(d):
    bap._world(d)
    a = _charging(d, "car-A", planned_end_min=-10)          # planned to end ten minutes ago, still charging
    hold = bap._hold(d, a, "WSH-1")                         # its wash, due now, on an empty bay
    return a, hold


def test_the_fixture_carries_the_live_reconcile(db):
    assert bap._md5(db, REC) == LIVE_REC


def test_before_0744_a_charge_past_its_plan_leaves_its_hold_on_the_empty_bay(db):
    a, hold = _overrun(db)
    assert _reconcile(db) == 0
    assert _window(db, hold) == "-1..17 held WSH-1"
    assert _log(db) == []
    assert bap._bay(db, "WSH-1") == "- -"                  # empty, and held all the same


def test_0744_applies_and_a_second_apply_is_refused(db):
    _apply(db)
    assert bap._md5(db, REC) == AFTER_0744
    assert db.val("""SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage
                      WHERE name = '0744_a_bay_hold_follows_a_charge_that_runs_past_its_plan'""") == "falsefalse"
    assert db.val("""SELECT default_value || '/' || min_value || '/' || max_value || '/' || COALESCE(agent_writable, false)
                       FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_hold_follows_charge'""") == "0/0/1/false"
    cell = db.json("""SELECT jsonb_build_object('cell', c.cell_code, 'buildout', c.buildout_code, 'params', c.fixed_params,
                                                 'priority', s.priority, 'budget', s.arm_budget_s, 'seeds', s.seeds)
                        FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                       WHERE s.sweep_code = 'bayhold_normal_2026_10_17'""")
    assert cell == {"cell": "dcfc40.otto_q.bay_hold_follows_charge", "buildout": "dcfc40", "priority": 16, "budget": 3000,
                    "seeds": [686364201590009433],
                    "params": {"deploy_peak_fraction": 0.90, "bay_hold_follows_charge": 1}}
    rc, err = db.file(M0744)
    assert rc != 0 and "0744 P" in err


def test_0744_refuses_a_body_it_was_not_written_against(db):
    db.val("""CREATE OR REPLACE FUNCTION ottoq.ottoq_reconcile_bay_reservations(p_sim_run_id uuid, p_depot_id uuid,
                                                                               p_clock timestamp with time zone)
              RETURNS integer LANGUAGE sql AS $$ SELECT 0 $$""")
    rc, err = db.file(M0744)
    assert rc != 0 and "0744 P1" in err


def test_at_the_default_the_hold_is_still_left_on_its_bay(db):
    _apply(db)
    a, hold = _overrun(db)
    assert _reconcile(db) == 0
    assert _window(db, hold) == "-1..17 held WSH-1"
    assert _log(db) == []


def test_with_the_dial_the_hold_steps_a_service_length_ahead(db):
    _apply(db)
    a, hold = _overrun(db)
    _dial(db, 1)
    assert _reconcile(db) == 1
    # blocked one service length (18 minutes) ahead, plus the 3-minute taxi: the bay is free for 21 minutes
    assert _window(db, hold) == "21..39 held WSH-1"
    assert _log(db) == [{"action": "deferred", "reason": "vehicle_not_yet_releasable", "blocked_by": "charging_past_plan",
                         "defer_seq": 1}]
    assert db.val("""SELECT payload->>'deferred' FROM public.test_bay_events
                      WHERE event_type = 'ottoq.bay_reservation_replanned'""") == "1"


def test_with_the_dial_a_charge_still_planned_ahead_is_blocked_as_before(db):
    _apply(db)
    bap._world(db)
    a = _charging(db, "car-A", planned_end_min=30)          # the leg's own plan still says 30 minutes
    hold = bap._hold(db, a, "WSH-1")
    _dial(db, 1)
    assert _reconcile(db) == 1
    assert _window(db, hold) == "33..51 held WSH-1"           # the leg's end plus the taxi, exactly as before 0744
    assert _log(db)[0]["blocked_by"] == "charging"


def test_with_the_dial_a_car_that_is_not_charging_is_untouched(db):
    _apply(db)
    bap._world(db)
    b = bap._car(db, "car-B", "staged_awaiting_service", "STG-1")
    hold = bap._hold(db, b, "WSH-2")
    _dial(db, 1)
    assert _reconcile(db) == 0                                  # ready and its bay free: left for the activation
    assert _window(db, hold) == "-1..17 held WSH-2"
    assert _log(db) == []


def test_with_the_dial_the_defer_cap_still_releases_a_charge_that_runs_on(db):
    _apply(db)
    a, hold = _overrun(db)
    db.val(f"""INSERT INTO public.bay_reservation_reconcile_2026_08_02 (sim_run_id, booking_id, vehicle_id, action, reason,
                                                                          defer_seq)
               SELECT '{RUN}', '{hold}', '{a}', 'deferred', 'vehicle_not_yet_releasable', g FROM generate_series(1, 8) g""")
    _dial(db, 1)
    assert _reconcile(db) == 1
    assert _window(db, hold).endswith("released WSH-1")
    assert db.val(f"SELECT release_reason FROM public.ottoq_stall_bookings WHERE booking_id = '{hold}'") == "replanned_defer_cap"
    assert _log(db)[-1] == {"action": "released", "reason": "replanned_defer_cap", "blocked_by": "charging_past_plan",
                            "defer_seq": 8}


def test_the_pre_image_puts_the_live_body_back(db):
    _apply(db)
    db.val("""DO $$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0744_pre'); END $$""")
    assert bap._md5(db, REC) == LIVE_REC
