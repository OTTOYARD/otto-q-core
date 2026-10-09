"""db/migrations/0639, EXECUTED: the futures hold a charger for the car the depot's calendar names.

WHY THIS EXISTS. The kernel's check on an agent's charge order rolls the charge line forward and seats the next car on
each charger the moment it frees. The kernel does not: its calendar books chargers ahead for named cars, and its
assignment gate refuses a charger held for another car to everyone else. The state carried no calendar, so the futures
gave held chargers to the wrong cars, and every forecast and every grade inherited the error (G380). Every claim in
0639's header that a test can execute is executed here, on the scratch PostgreSQL and the miniature depot of
tests/test_agent_charge_order_sql.py, through 0619-0638 as tests/test_agent_review_memory_sql.py applies them:
  - it applies, its checks run, and it refuses an engine before 0638, a run running and a second apply;
  - the holds: the charge bookings the run's calendar held at a moment for a named car, read from the calendar's own
    sim-clock columns, so a past moment reads as it stood; not a charge under way, not one booked later or released
    before, not another run's, not a bay, not past the horizon; open-ended as open-ended;
  - the state carries them behind the dial, with its chargers and its line untouched; at 0, 0638's state exactly;
  - the simulator: without the list, 0638's result key for key; with it, a held charger goes to no other car inside its
    window and to its own car as any free charger, an agent's order cannot take it either, a car's holds end when it is
    seated anywhere, a hold for a car the futures do not model is counted and left out, a hold's end is a moment the
    line is read again, an inbound car's hold waits for it, and a sampled future reads the same holds;
  - the realizer carries the state's holds into the hindsight replay;
  - the self-review: neither area lists holds among what the simulator does not model, and v3 says how many graded
    orders were made before the futures read them.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import re
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402
import test_agent_review_memory_sql as rm  # noqa: E402  (0638 and the chain through it)
import test_agent_charger_faults_sql as cf  # noqa: E402  (hand lines for the simulator)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0639 = os.path.join(ROOT, "db", "migrations", "0639_the_futures_hold_a_charger_for_the_car_the_calendar_names.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
ELSEWHERE_RUN = "b0000000-0000-0000-0000-000000000639"
HOLDS_DEPOT = "77777777-7777-7777-7777-777777777777"            # a depot whose graded orders all read the holds
_file = arb._file
_vid = base._vid
_sim, _line, _car = cf._sim, cf._line, cf._car

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

V1 = ("0639 V1: one L2 and two cars: no hold, a 0 and b 20; held for b, b 0 and a 60; held for b from minute 5, a 0 and "
      "b 20; held for a car not in the line, counted and left out; held for a, as without; an empty list, as without plus "
      "its counts; b seated on the fast charger frees its L2 hold at once (a 0 on the L2); held for a car that cannot use "
      "it, a at the hold's end (30); the state and the dial as meant")


def _apply(d):
    return _file(d, M0639)


def _through_0638(d):
    err = rm._through_0638(d)
    assert "0638 V1" in err, err


def _through_0639(d):
    _through_0638(d)
    return _apply(d)


def _book(d, stall, car, lo, hi, *, state="held", booked=-10, released=None, purpose=None, run=RUN):
    """A booking on `stall` for `car` from lo to hi minutes after T (hi None: open-ended), booked `booked` minutes after T
    on the run's clock and released `released` minutes after T (None: not released)."""
    purpose = purpose or ("charge_dcfc" if stall.startswith("F") else "charge_l2")
    hi_sql = "NULL" if hi is None else f"'{T}'::timestamptz + interval '{hi} minutes'"
    rel = "NULL" if released is None else f"'{T}'::timestamptz + interval '{released} minutes'"
    return d.val(f"""INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state,
                                                             booked_at, booked_at_sim, released_at)
                     VALUES ('{run}', '{_vid(stall)}', '{_vid(car)}', '{purpose}',
                             tstzrange('{T}'::timestamptz + interval '{lo} minutes', {hi_sql}), '{state}', now(),
                             '{T}'::timestamptz + interval '{booked} minutes', {rel})
                     RETURNING booking_id""")


def _holds(d, at_min=0, horizon=480):
    return d.json(f"SELECT public.ottoq_charge_line_holds('{RUN}', '{T}'::timestamptz + interval '{at_min} minutes', {horizon})")


def _h(stall, car, a, b):
    return {"c": _vid(stall), "v": _vid(car), "a": a, "b": b}


def _state(d):
    return d.json(f"SELECT public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}')")


def _seats(v, kind=False):
    return {s["id"]: ([s["s0"], s["k0"]] if kind else s["s0"]) for s in v["seats"]}


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0639_applies_and_its_checks_run(db):
    err = _through_0639(db)
    assert V1 in err, err
    assert "0639 V2: 0 stored simulations (0 states x both sides x futures 0 and 3) unchanged" in err, err
    assert "0639 V3: no stored order; the state is executed by the tests" in err, err
    assert "0639 V4: no run has 20 graded full-window orders; the replay is executed by the tests" in err, err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0639_the_futures_hold_a_charger_for_the_car_the_calendar_names'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0639_pre'") == "4"
    assert db.val("""SELECT default_value::text || '/' || min_value || '/' || max_value || '/' || agent_writable
                       FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_holds'""") == "1/0/1/false"
    assert db.val("SELECT has_function_privilege('authenticated', "
                  "'public.ottoq_charge_line_holds(uuid,timestamptz,numeric)', 'EXECUTE')") == "t"


def test_0639_refuses_an_engine_before_0638_a_run_running_and_a_second_apply(db):
    rm._through_0637(db)
    rc, err = db.file(M0639)
    assert rc != 0 and "0639 P1: 0638 is not applied; apply 0630-0638 first" in err, err
    rm._apply(db)
    status = db.val(f"SELECT status FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}'")
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0639)
    assert rc != 0 and "0639 P0: a run is running" in err, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = '{status}' WHERE sim_run_id = '{RUN}'")
    _apply(db)
    rc, err = db.file(M0639)
    assert rc != 0 and ("0639 P1: public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone) is not the body "
                        "measured") in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_holds'") == "1"


def _graded_world(d, n=20):
    """n graded full-window orders on the run, a minute apart: one L2 (L1) and two cars, A waiting longer; the calendar holds
    L1 for B over every order; what really happened is B first and A after B's hour."""
    _book(d, "L1", "B", -5, 100)
    st = {"ttl_min": 0, "pin_min": 90, "horizon_min": 480, "inbound": [],
          "chargers": [{"id": _vid("L1"), "k": "l2", "free": 0, "sd": 0}],
          "cars": [_car(_vid("A"), md=20, ml=20, g=40, soc=60, w=40), _car(_vid("B"), md=60, ml=60, g=40, soc=60, w=0)]}
    rz = {"observed_min": 90, "inbound": {}, "appeared": [], "chargers": {}, "back": [],
          "cars": {_vid("A"): {"s0": 60, "k0": "l2", "m": 20, "cen": False, "end": "completed"},
                   _vid("B"): {"s0": 0, "k0": "l2", "m": 60, "cen": False, "end": "completed"}}}
    for k in range(n):
        at = f"'{T}'::timestamptz + interval '{k} minutes'"
        d.val(f"""INSERT INTO public.ottoq_charge_order_snapshots (order_id, sim_run_id, depot_id, sim_clock, seed, futures,
                                                                   win_frac, state, agent_order, code_md5)
                  VALUES ({9800 + k}, '{RUN}', '{DEPOT}', {at}, 'hand', 12, 0.8, $j${json.dumps(st)}$j$::jsonb, '{{}}',
                          'hand')""")
        d.val(f"""INSERT INTO public.ottoq_charge_order_hindsight (order_id, sim_run_id, depot_id, sim_clock, window_min,
                    observed_min, status, reason, taken, decision, futures, wins, need, p_win, expected, hindsight, outcome,
                    moves, forecast, fidelity, realized, code_md5)
                  VALUES ({9800 + k}, '{RUN}', '{DEPOT}', {at}, 90, 90, 'refused', 'kernel_order', false, true, 12, 0, 10,
                          0.0, '{{"cmp": 1}}', '{{"cmp": 1}}', 'right_refusal', '{{}}'::text[], '{{}}', '{{}}',
                          $j${json.dumps(rz)}$j$::jsonb, 'hand')""")


def test_0639_its_checks_speak_on_a_depot_with_graded_orders(db):
    _through_0638(db)
    _graded_world(db)
    err = _apply(db)
    assert "0639 V2: 32 stored simulations (8 states x both sides x futures 0 and 3) unchanged" in err, err
    assert re.search(r"0639 V3: the state at order 9819 \(run a0000000, sim 14:59\) in [\d.]+ s carries the 1 charge "
                     r"bookings the calendar held then for named cars \(1 on L2s\)", err), err
    assert re.search(r"0639 V4: run a0000000 \(its latest 20 full-window graded orders, [\d.]+ s\): the replay given what "
                     r"happened placed a plug-in a mean 40\.00 minutes from the real one without the calendar's holds and "
                     r"0\.00 with them \(cars at the depot 40\.00 -> 0\.00, cars coming home <NULL> -> <NULL>\); compared "
                     r"40 -> 40, missed 0 -> 0, invented 0 -> 0; 20 holds read, 0 on cars the futures do not model", err), err


# ── the holds ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_holds_are_what_the_calendar_held_at_the_moment(db):
    _through_0639(db)
    assert _holds(db) == []
    _book(db, "L1", "A", 15, 75)                                         # held ahead: from 15 to 75
    _book(db, "L2", "B", -5, 55, booked=-20)                             # held over the moment: from 0
    _book(db, "L3", "C", 10, 70, state="superseded", booked=-30, released=-1)   # released before the moment
    _book(db, "F1", "D", 10, 70, state="superseded", booked=-30, released=30)   # superseded after it: held then
    _book(db, "F2", "P", 20, 80, booked=5)                               # booked after the moment
    _book(db, "L1", "C", -30, 30, state="active", booked=-40)            # a charge under way
    _book(db, "L3", "A", -60, -1, state="done", booked=-70)              # over before the moment
    _book(db, "L3", "D", 500, 560, booked=-5)                            # past the horizon
    _book(db, "L3", "B", 5, 20, purpose="service")                       # not a charge
    _book(db, "L3", "A", 100, None, booked=-5)                           # open-ended
    _book(db, "L2", "A", 5, 60, run=ELSEWHERE_RUN)                       # another run's
    _book(db, "L1", "I", 30, 90, state="released", booked=-15, released=10)     # released after the moment: held then
    assert _holds(db) == [_h("L2", "B", 0, 55), _h("F1", "D", 10, 70), _h("L1", "A", 15, 75), _h("L1", "I", 30, 90),
                          _h("L3", "A", 100, None)], _holds(db)
    # a longer horizon reaches the far one
    assert _h("L3", "D", 500, 560) in _holds(db, horizon=600)
    # a past moment reads as it stood: 25 minutes earlier, only what was booked by then and not yet released
    earlier = sorted(_holds(db, at_min=-25), key=lambda x: x["c"])
    assert earlier == sorted([_h("L3", "C", 35, 95), _h("F1", "D", 35, 95)], key=lambda x: x["c"]), earlier
    # a minute after the moment, I's hold is still held; eleven minutes after it, it is gone
    assert _h("L1", "I", 29, 89) in _holds(db, at_min=1)
    assert all(h["v"] != _vid("I") for h in _holds(db, at_min=11))


# ── the state ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def _plant(d):
    _book(d, "L1", "A", 15, 75)                                          # on a free L2, for a car in the line
    _book(d, "L2", "B", -5, 55, booked=-20)                              # over the moment: L2 is out of the list
    _book(d, "F1", "D", 10, 70, state="superseded", booked=-30, released=30)
    _book(d, "L3", "X", 20, 80)                                          # for a car out at work: not in the line


def test_the_state_carries_the_holds_behind_the_dial_and_nothing_else_moves(db):
    _through_0638(db)
    _plant(db)
    before = _state(db)
    assert "holds" not in before
    _apply(db)
    st = _state(db)
    assert {k: v for k, v in st.items() if k != "holds"} == before
    assert st["holds"] == _holds(db) and len(st["holds"]) == 4, st["holds"]
    # the charger held over the moment is out of the list, as it was; the line is the kernel's, as it was
    assert _vid("L2") not in {c["id"] for c in st["chargers"]}
    # the simulator reads two of them (A's and D's), counts X's, and skips B's (its charger is not in the list)
    out = _sim(db, st, None, 0, "s", False)
    assert (out["holds"], out["holds_unmodelled"]) == (2, 1), out
    # a person turns it off for this run: 0638's state exactly
    base._dial(db, "agent_charge_order_holds", 0)
    assert _state(db) == before


# ── the simulator ─────────────────────────────────────────────────────────────────────────────────────────────────────

ONE_L2 = [{"id": "l", "k": "l2", "free": 0, "sd": 0}]
TWO = [_car("a", md=20, ml=20, g=40, soc=60, w=40), _car("b", md=60, ml=60, g=40, soc=60, w=0)]


def _hand_states():
    cars = [_car("a", md=30, g=40, soc=60, w=5), _car("b", md=25, g=30, soc=40, w=20), _car("c", md=45, ml=200, g=70, w=1),
            _car("d", md=20, g=15, soc=85, w=40, lok=False)]
    ch = [{"id": "F1", "k": "dcfc", "free": 0, "sd": 0}, {"id": "F2", "k": "dcfc", "free": 35, "sd": 0.2, "car": "u"},
          {"id": "L1", "k": "l2", "free": 0, "sd": 0}]
    dn = [dict(ch[0], dn=[[12, 70]]), ch[1], ch[2]]
    return [_line(cars, ch), _line(cars, dn), _line(cars, ch, ttl=30), _line(TWO, ONE_L2)]


ORDER = {"c": {"rank": 1, "kind": "dcfc"}, "a": {"rank": 2, "kind": "l2"}}


def test_without_holds_the_simulator_is_0638s_key_for_key(db):
    _through_0638(db)
    _plant(db)
    states = _hand_states() + [_state(db)]
    calls = [(s, o, k, t) for s in states for o in (None, ORDER) for k in (0, 1, 3) for t in (True, False)]
    before = [_sim(db, s, o, k, "seed", t) for s, o, k, t in calls]
    _apply(db)
    after = [_sim(db, s, o, k, "seed", t) for s, o, k, t in calls]
    assert after == before
    # an empty list is the same line, plus its counts
    empty = [_sim(db, dict(s, holds=[]), o, k, "seed", t) for s, o, k, t in calls]
    assert empty == [dict(b, holds=0, holds_unmodelled=0) for b in before]


def test_a_held_charger_goes_only_to_its_car(db):
    _through_0639(db)
    line = _line(TWO, ONE_L2)
    assert _seats(_sim(db, line)) == {"a": 0, "b": 20}
    held = _sim(db, dict(line, holds=[{"c": "l", "v": "b", "a": 0, "b": 100}]))
    assert _seats(held) == {"a": 60, "b": 0} and (held["holds"], held["holds_unmodelled"]) == (1, 0), held
    # a hold that starts after the moment covers nothing at it
    assert _seats(_sim(db, dict(line, holds=[{"c": "l", "v": "b", "a": 5, "b": 100}]))) == {"a": 0, "b": 20}
    # a hold that ended before b's turn changes nothing either
    assert _seats(_sim(db, dict(line, holds=[{"c": "l", "v": "b", "a": 0, "b": 0}]))) == {"a": 0, "b": 20}
    # an agent's order cannot take a held charger: b is ranked first, and the L2 is held for a
    order = {"b": {"rank": 1, "kind": "l2"}}
    live = dict(line, ttl_min=30)
    assert _seats(_sim(db, live, order)) == {"a": 60, "b": 0}
    assert _seats(_sim(db, dict(live, holds=[{"c": "l", "v": "a", "a": 0, "b": 100}]), order)) == {"a": 0, "b": 20}
    # a sampled future reads the same holds
    noisy = _line([dict(c, sd=0.3, sl=0.3) for c in TWO], ONE_L2, holds=[{"c": "l", "v": "b", "a": 0, "b": 100}])
    for k in (1, 2, 3):
        s = _seats(_sim(db, noisy, None, k, "seed"))
        assert s["b"] == 0 and s["a"] > 0, (k, s)


def test_a_cars_holds_end_when_it_is_seated_and_a_holds_end_is_a_moment(db):
    _through_0639(db)
    # b, low and waiting longest, takes the fast charger at 0: its hold on the L2 ends with it, and a takes the L2 at 0
    two = _line([_car("b", md=20, ml=60, g=40, soc=30, w=40), _car("a", md=30, ml=20, g=40, soc=60, w=0)],
                [{"id": "f", "k": "dcfc", "free": 0, "sd": 0}, {"id": "l", "k": "l2", "free": 0, "sd": 0}])
    assert _seats(_sim(db, dict(two, holds=[{"c": "l", "v": "b", "a": 0, "b": 100}])), kind=True) == \
        {"a": [0, "l2"], "b": [0, "dcfc"]}
    # held for c, which cannot use an L2: a takes it when the hold ends; open-ended, never inside the horizon
    none = _line([_car("a", md=20, ml=20, g=40, soc=60, w=40), _car("c", md=30, ml=30, g=40, soc=60, w=0, lok=False)],
                 ONE_L2)
    assert _seats(_sim(db, dict(none, holds=[{"c": "l", "v": "c", "a": 0, "b": 30}]))) == {"a": 30, "c": None}
    assert _seats(_sim(db, dict(none, holds=[{"c": "l", "v": "c", "a": 0, "b": None}]))) == {"a": None, "c": None}


def test_a_hold_for_a_car_coming_home_waits_for_it_and_one_the_futures_do_not_model_is_counted(db):
    _through_0639(db)
    inbound = [dict(_car("x", md=30, ml=30, g=40, soc=50, w=0), eta=20)]
    line = _line([_car("a", md=20, ml=20, g=40, soc=60, w=40)], ONE_L2, inbound=inbound)
    assert _seats(_sim(db, line)) == {"a": 0, "x": 20}
    held = _sim(db, dict(line, holds=[{"c": "l", "v": "x", "a": 0, "b": 75}]))
    assert _seats(held) == {"a": 50, "x": 20}, held["seats"]
    # holds for a car not in the line and on a charger not in the list: the first counted, the second skipped
    other = _sim(db, dict(line, holds=[{"c": "l", "v": "z", "a": 0, "b": 75}, {"c": "q", "v": "a", "a": 0, "b": 75}]))
    assert (other["holds"], other["holds_unmodelled"]) == (0, 1) and _seats(other) == {"a": 0, "x": 20}, other


# ── the realizer ──────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_realizer_carries_the_states_holds_into_the_replay(db):
    _through_0639(db)
    st = _line(TWO, ONE_L2, holds=[{"c": "l", "v": "b", "a": 0, "b": 100}])
    real = {"observed_min": 90, "cars": {"a": {"s0": 60, "k0": "l2", "m": 20, "cen": False, "end": "completed"},
                                         "b": {"s0": 0, "k0": "l2", "m": 60, "cen": False, "end": "completed"}},
            "inbound": {}, "appeared": [], "chargers": {}, "back": []}
    full = db.json(f"""SELECT public.ottoq_charge_line_realize($j${json.dumps(st)}$j$::jsonb, $j${json.dumps(real)}$j$::jsonb,
                         ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults'])""")
    assert full["holds"] == st["holds"]
    assert _seats(_sim(db, full)) == {"a": 60, "b": 0}


# ── the self-review ───────────────────────────────────────────────────────────────────────────────────────────────────

def _graded(d, oid, holds, depot=DEPOT):
    """A graded order whose replay given what happened missed by 12 minutes on 20 cars, its state with or without holds."""
    st = {"ttl_min": 3, "pin_min": 90, "horizon_min": 480, "cars": [], "inbound": [], "chargers": []}
    if holds:
        st["holds"] = []
    d.val(f"""INSERT INTO public.ottoq_charge_order_snapshots (order_id, sim_run_id, depot_id, sim_clock, seed, futures,
                                                               win_frac, state, agent_order, code_md5)
              VALUES ({oid}, '{RUN}', '{depot}', '{T}', 'hand', 12, 0.8, $j${json.dumps(st)}$j$::jsonb, '{{}}', 'hand')""")
    fid = {"both": 20, "sum_abs_err": 240, "sum_err": -100, "within_5_min": 5, "missed": 3, "phantom": 4}
    rz = {"observed_min": 90, "cars": {}, "inbound": {}, "appeared": [], "chargers": {}, "back": []}
    d.val(f"""INSERT INTO public.ottoq_charge_order_hindsight (order_id, sim_run_id, depot_id, sim_clock, window_min,
                observed_min, status, reason, taken, decision, futures, wins, need, p_win, expected, hindsight, outcome,
                moves, forecast, fidelity, realized, code_md5)
              VALUES ({oid}, '{RUN}', '{depot}', '{T}', 90, 90, 'accepted', 'wins_most_futures', true, true, 12, 12, 10,
                      1.0, '{{"cmp": 1}}', '{{"cmp": 1}}', 'right_take', '{{}}'::text[], '{{}}',
                      $j${json.dumps(fid)}$j$::jsonb, $j${json.dumps(rz)}$j$::jsonb, 'hand')""")


def _sim_area(d, fn="v3", depot=DEPOT):
    if fn == "v3":
        r = d.json(f"SELECT public.ottoq_arbiter_self_assessment_v3('{depot}', now() - interval '7 days', false)")
    else:
        r = d.json(f"SELECT public.ottoq_arbiter_self_assessment('{depot}', now() - interval '7 days')")
    return next(a for a in r["improvement_areas"] if a["area"] == "simulator_structure")


def test_the_review_no_longer_lists_holds_and_counts_the_orders_made_before_them(db):
    _through_0639(db)
    for k in range(3):
        _graded(db, 9700 + k, holds=False)
    a = _sim_area(db)
    assert "It does not model bays, the stall pick beyond the kind of charger, or the next order taking over; and 3 of the " \
           "orders graded here were made before it held a charger for the car the depot's calendar names, and no forecast " \
           "can remove that error." in a["finding"], a["finding"]
    assert "holds" not in a["finding"] and a["action"] == \
        "Measure which of the three costs the most, then model that one in the check's simulator.", a
    b = _sim_area(db, "base")
    assert "It does not model bays, the stall pick beyond the kind, or the next order taking over" in b["finding"], b
    assert "holds" not in b["finding"], b
    # orders that read the calendar's holds are not history
    _graded(db, 9710, holds=True)
    assert "and 3 of the orders graded here were made before it held a charger" in _sim_area(db)["finding"]
    for k in range(3):
        _graded(db, 9720 + k, holds=True, depot=HOLDS_DEPOT)
    f = _sim_area(db, depot=HOLDS_DEPOT)["finding"]
    assert "made before it held" not in f and f.endswith("or the next order taking over, and no forecast can remove that "
                                                          "error."), f
