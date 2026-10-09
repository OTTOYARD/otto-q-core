"""db/migrations/0642, EXECUTED: the kernel serves a car that has waited 90 minutes first, and orders the rest by
minutes of charge (G384).

WHY THIS EXISTS. 0642 changes who OTTO-Q's seat charges next on every run, so every claim in its header that a test can
execute is executed here, on the scratch PostgreSQL and the miniature depot of tests/test_agent_charge_order_sql.py,
through 0619-0641 as tests/test_agent_holds_sql.py applies them:
  - it applies, its checks run, it is classified TRUE/TRUE, and it refuses a run running and a second apply;
  - the keys: a car at or past the floor first, the longest wait first, then (wait + minutes) / minutes on the charge
    clock; the minutes are the check's own (the state's om, car for car), the contract wait is the owner's; with the
    dials at 0 the keys are gone and the kernel's order is 0545's ratio in points again;
  - the kernel's order, the cockpits' queue and the board's queue read all order the line by the same keys, and a
    baseline seat ignores them; the cursor reads them once per tick, before 0545's ratio, and records them;
  - the check's simulator: a state without the keys simulates exactly as before 0642; with them it orders the line as
    the kernel does, by the state's minutes and never a sampled future's draw, and reports the minutes past each car's
    contract wait; the comparison weighs that after lateness and before minutes in the depot, and without it compares
    exactly as before;
  - the agent's board says how the kernel orders.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402
import test_agent_holds_sql as ho  # noqa: E402  (0639-0641 and the chain through them)
import test_agent_charger_faults_sql as cf  # noqa: E402  (hand lines for the simulator)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0642 = os.path.join(ROOT, "db", "migrations",
                     "0642_the_kernel_serves_a_long_wait_first_and_times_its_line_in_minutes.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
NAME = "0642_the_kernel_serves_a_long_wait_first_and_times_its_line_in_minutes"
_vid, _dial, _file = base._vid, base._dial, arb._file
_sim, _line, _car = cf._sim, cf._line, cf._car

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _through_0641(d):
    err = ho._through_0639(d)
    assert "0639 V1" in err, err
    for m in (ho.M0640, ho.M0641):
        _file(d, m)


def _through_0642(d):
    _through_0641(d)
    return _file(d, M0642)


def _wait(d, name, minutes):
    d.val(f"UPDATE public.vehicles SET last_state_change = '{T}'::timestamptz - interval '{minutes} minutes' "
          f"WHERE display_name = '{name}'")


def _names(d, sql):
    return d.json(f"SELECT COALESCE(jsonb_agg(v.display_name ORDER BY x.o), '[]') FROM ({sql}) x(id, o) "
                  "JOIN public.vehicles v ON v.id = x.id")


def _kernel(d):
    return _names(d, f"SELECT vehicle_id, kernel_pos FROM public.ottoq_charge_queue_kernel_order('{RUN}', '{DEPOT}', '{T}')")


def _cockpit(d):
    return _names(d, f"SELECT vehicle_id, queue_position FROM public.ottoq_depot_queue('{DEPOT}', '{RUN}') "
                     "WHERE queue_kind = 'charge'")


def _learning(d):
    return _names(d, f"""SELECT (e.value ->> 'vehicle_id')::uuid, (e.value ->> 'pos')::int
                           FROM jsonb_array_elements(public.ottoq_run_learning('{RUN}', 20, true) #> '{{queue,head}}') e""")


def _keys(d):
    return {r["car"]: r for r in d.json(f"""
        SELECT COALESCE(jsonb_agg(jsonb_build_object('car', v.display_name, 'w', round(k.wait_min, 2), 'm', k.minutes,
                                                     'f', k.floor_key, 'mk', k.minutes_key)), '[]')
          FROM public.ottoq_charge_order_keys('{RUN}', '{DEPOT}', '{T}') k JOIN public.vehicles v ON v.id = k.vehicle_id""")}


def _points(d):
    """0545's order in points, computed here: immediate dispatch, then (wait + points owed) / points owed, battery, id."""
    return _names(d, f"""SELECT v.id, row_number() OVER (
                             ORDER BY (vn.urgency = 'immediate_dispatch') DESC,
                                      (extract(epoch FROM ('{T}'::timestamptz - v.last_state_change)) / 60.0
                                       + GREATEST(100 - v.current_soc, 1)) / GREATEST(100 - v.current_soc, 1) DESC,
                                      v.current_soc, v.id)
                           FROM public.vehicles v JOIN public.ottoq_visit_needs vn ON vn.vehicle_id = v.id
                          WHERE v.current_state = 'arrived_at_gate' AND v.home_depot_id = '{DEPOT}'""")


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0642_applies_its_checks_run_and_it_refuses_twice(db):
    _through_0641(db)
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0642)
    assert rc != 0 and "0642 P0: a run is running" in err, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    err = _file(db, M0642)
    assert "0642 V1: eight bodies stored as patched" in err, err
    assert "0642 V2: 0 stored states" in err, err
    assert "0642 V3: no stored order; the keys are executed by the tests" in err, err
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{NAME}'") == "truetrue"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0642_pre'") == "8"
    assert db.json("""SELECT jsonb_object_agg(param_key, jsonb_build_array(default_value, min_value, max_value, agent_writable))
                        FROM public.ottoq_policy_param_catalog
                       WHERE param_key IN ('charge_wait_floor_min', 'charge_order_minutes')""") == {
        "charge_wait_floor_min": [90, 0, 480, False], "charge_order_minutes": [1, 0, 1, False]}
    rc, err = db.file(M0642)
    assert rc != 0 and "0642 P1: already applied" in err, err


# ── the keys ──────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_keys_are_the_floor_then_minutes_and_the_minutes_are_the_checks_own(db):
    _through_0642(db)
    k = _keys(db)
    assert set(k) == {"A", "B", "C", "D", "I", "P"}                      # X is out at work
    assert k["P"]["f"] == 120 and all(k[c]["f"] is None for c in "ABCDI")  # only P has waited 90 minutes
    for c in k:
        assert k[c]["mk"] == pytest.approx((k[c]["w"] + k[c]["m"]) / k[c]["m"], rel=1e-9)
    # the minutes are the state's om, car for car: the check orders its futures by the kernel's own numbers
    st = db.json(f"SELECT public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}')")
    om = {base.NAMES.get(c["id"]) or db.val(f"SELECT display_name FROM public.vehicles WHERE id = '{c['id']}'"):
          (c["om"], c.get("mw")) for c in st["cars"]}
    assert om == {c: (pytest.approx(k[c]["m"], rel=1e-12), 30) for c in om}
    assert st["order_minutes"] is True and st["floor_min"] == 90
    # each minute is the shorter clock time of the two kinds, as the state times them
    for c in st["cars"]:
        assert c["om"] == pytest.approx(max(min(c["md"], c["ml"]), 1), rel=1e-12)
    # the inbound cars carry them too (none at work here is due home, so the list is empty and the keys say so)
    assert all("om" in c for c in st["inbound"])


def test_the_dials_turn_each_key_off_and_both_off_is_the_order_in_points(db):
    _through_0642(db)
    _wait(db, "C", 100)                                                  # C past the floor too, longer than P? no: 100 < 120
    assert _kernel(db)[:3] == ["I", "P", "C"]                            # floored, the longest wait first
    _dial(db, "charge_wait_floor_min", 0)
    assert all(r["f"] is None for r in _keys(db).values())
    _dial(db, "charge_order_minutes", 0)
    assert _keys(db) == {}                                               # both off: no car carries a key
    assert _kernel(db) == _points(db)                                    # and the order is 0545's in points
    _dial(db, "charge_wait_floor_min", 90)
    k = _keys(db)
    assert all(r["mk"] is None for r in k.values()) and k["C"]["f"] == 100 and k["P"]["f"] == 120


# ── every reader orders the line by the same keys ─────────────────────────────────────────────────────────────────────

def test_the_kernels_order_the_cockpits_queue_and_the_boards_read_agree(db):
    _through_0642(db)
    # a line where the floor and the minutes reorder 0545's points: D (85%) and B (60%) have waited past 90 minutes,
    # B longer; the rest below the floor go by minutes
    _wait(db, "D", 95)
    _wait(db, "B", 110)
    _wait(db, "P", 30)
    k = _keys(db)
    below = sorted((c for c in "ACP"), key=lambda c: -k[c]["mk"])
    want = ["I", "B", "D"] + below
    assert _kernel(db) == want
    assert _cockpit(db) == want
    assert _learning(db) == want
    assert want != _points(db)                                           # the keys changed the order
    # a baseline seat ignores them: fifo by arrival, as before 0642
    _dial(db, "proposer_seat", 1)
    assert _cockpit(db) == _names(db, f"""SELECT v.id, row_number() OVER (ORDER BY (vn.urgency = 'immediate_dispatch') DESC,
                                                                                v.last_state_change, v.current_soc, v.id)
                                            FROM public.vehicles v JOIN public.ottoq_visit_needs vn ON vn.vehicle_id = v.id
                                           WHERE v.current_state = 'arrived_at_gate'""")


def test_the_cursor_reads_the_keys_once_a_tick_before_0545_and_records_them(db):
    _through_0642(db)
    src = db.json("SELECT to_json(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure")
    assert src.count("public.ottoq_charge_order_keys(p_sim_run_id, v_depot, v_clock)") == 1
    keys = src.index("(v_ok -> v.id::text ->> 0)::numeric DESC NULLS LAST")
    assert src.index("CASE WHEN v_seat = 2 THEN v.current_soc END ASC") < keys
    assert keys < src.index("(v_ok -> v.id::text ->> 1)::numeric DESC NULLS LAST") < src.index("CASE WHEN v_seat = 0 THEN")
    assert keys > src.index("public.ottoq_agent_charge_order_key(v_ao_order, v.id, v_ao_mode)")   # after the agent's keys
    assert "'charge_order', jsonb_build_object(" in src and "IF v_seat = 0 THEN\n    BEGIN\n      SELECT COALESCE(jsonb_object_agg(k.vehicle_id::text" in src


# ── the check's simulator ─────────────────────────────────────────────────────────────────────────────────────────────

HAND = [
    _line([_car("a", md=60, ml=200, g=40, soc=60, w=100), _car("b", md=10, ml=30, g=10, soc=90, w=95),
           _car("c", md=5, ml=20, g=5, soc=95, w=10), _car("d", md=100, ml=300, g=70, soc=30, w=0)],
          [{"id": "f", "k": "dcfc", "free": 0}]),
    _line([_car("a", md=40, ml=150, g=50, soc=50, w=30), _car("b", md=20, ml=40, g=10, soc=90, w=5, imm=True, due=30),
           _car("c", md=30, ml=90, g=20, soc=80, w=12)],
          [{"id": "f", "k": "dcfc", "free": 0}, {"id": "l", "k": "l2", "free": 15}]),
]


def _keyed(state, floor=90, minutes=True, mw=30):
    s = dict(state, order_minutes=minutes, floor_min=floor)
    s["cars"] = [dict(c, om=max(min(c["md"], c["ml"]), 1), mw=mw) for c in state["cars"]]
    return s


def _order_of(r):
    return [s["id"] for s in sorted(r["seats"], key=lambda s: (s["s0"] if s["s0"] is not None else 1e9, s["id"]))]


def test_without_the_keys_the_simulator_and_the_comparison_are_0641s(db):
    _through_0641(db)
    runs = [(st, o, k) for st in HAND for o in (None, {"c": {"rank": 1, "kind": "dcfc"}}) for k in (0, 3)]
    before = [_sim(db, st, o, k) for st, o, k in runs]
    cmp_before = db.json(f"SELECT public.ottoq_charge_line_compare($a${cf.json.dumps(before[0])}$a$::jsonb, "
                         f"$b${cf.json.dumps(before[1])}$b$::jsonb)")
    _file(db, M0642)
    after = [_sim(db, st, o, k) for st, o, k in runs]
    assert after == before
    assert db.json(f"SELECT public.ottoq_charge_line_compare($a${cf.json.dumps(after[0])}$a$::jsonb, "
                   f"$b${cf.json.dumps(after[1])}$b$::jsonb)") == cmp_before


def test_with_the_keys_the_line_is_the_floor_then_minutes(db):
    _through_0642(db)
    st = HAND[0]
    # 0545's points, read again each time a charger frees: at 0, b (95+10)/10 = 10.5 before a (100+40)/40 = 3.5; at 10,
    # c (20+5)/5 = 5.0 has overtaken a (110+40)/40 = 3.75 -- a car owing 5 points rises eight times as fast as one owing
    # 40, which is G384: b, c, a, d
    assert _order_of(_sim(db, st)) == ["b", "c", "a", "d"]
    # the floor at 90, the longest wait first, then minutes: a (100), b (95); c (10+5)/5 = 3, d (0+100)/100 = 1
    r = _sim(db, _keyed(st))
    assert _order_of(r) == ["a", "b", "c", "d"]
    assert [s["s0"] for s in sorted(r["seats"], key=lambda s: s["id"])] == [0, 60, 70, 75]
    # minutes alone: b (95+10)/10 = 10.5, c 3, a (100+60)/60 = 2.67, d 1
    assert _order_of(_sim(db, _keyed(st, floor=0))) == ["b", "c", "a", "d"]
    # the floor alone, 0545's points below it
    assert _order_of(_sim(db, _keyed(st, minutes=False))) == ["a", "b", "c", "d"]
    # an agent's live order: the pin (90) first, in the kernel's own order (the floor: a, then b), then its ranking
    r = _sim(db, dict(_keyed(st), ttl_min=480), {"d": {"rank": 1, "kind": "dcfc"}, "c": {"rank": 2, "kind": "dcfc"}})
    assert _order_of(r) == ["a", "b", "d", "c"]


def test_the_futures_order_by_the_kernels_minutes_never_a_sampled_draw(db):
    _through_0642(db)
    # three free chargers and four cars: who is seated first is the kernel's order, whatever a future draws for md
    st = _line([_car("a", md=50, ml=50, g=40, soc=60, w=20, sd=1.5, sl=1.5),
                _car("b", md=20, ml=20, g=10, soc=90, w=5, sd=1.5, sl=1.5),
                _car("c", md=40, ml=40, g=30, soc=70, w=15, sd=1.5, sl=1.5),
                _car("d", md=90, ml=90, g=70, soc=30, w=10, sd=1.5, sl=1.5)],
               [{"id": "f1", "k": "dcfc", "free": 0}, {"id": "f2", "k": "dcfc", "free": 0}, {"id": "f3", "k": "dcfc", "free": 0}])
    want = {s["id"] for s in _sim(db, _keyed(st, floor=0))["seats"] if s["s0"] == 0}
    assert want == {"a", "b", "c"}                                       # (w+om)/om: b 1.25, c 1.375, a 1.4, d 1.11
    for k in range(1, 9):
        assert {s["id"] for s in _sim(db, _keyed(st, floor=0), None, k)["seats"] if s["s0"] == 0} == want


def test_the_simulator_reports_the_minutes_past_each_cars_contract_wait(db):
    _through_0642(db)
    st = _line([_car("a", md=30, ml=90, g=30, soc=70, w=20), _car("b", md=30, ml=90, g=30, soc=70, w=10),
                _car("c", md=30, ml=90, g=30, soc=70, w=0)], [{"id": "f", "k": "dcfc", "free": 0}])
    s = _keyed(st, floor=0)
    s["cars"][2] = {k: v for k, v in s["cars"][2].items() if k != "mw"}      # c has no contract wait
    r = _sim(db, s)
    # a seated at 0 (waited 20), b at 30 (40: 10 past), c at 60 (60, held to none)
    assert r["breach_sum"] == 10 and r["breach_n"] == 1
    # a car not seated within the horizon is past its contract to the horizon: c, held to 30 now, waits at least 45
    r2 = _sim(db, dict(_keyed(st, floor=0), horizon_min=45))
    assert r2["breach_sum"] == 10 + 15 and r2["breach_n"] == 2
    assert [x["s0"] for x in sorted(r2["seats"], key=lambda x: x["id"])] == [0, 30, None]
    assert "breach_sum" not in _sim(db, st)                                 # without the keys, no breach is reported


def test_the_comparison_weighs_the_contract_after_lateness_and_before_the_depot(db):
    _through_0642(db)

    def cmp(k, a):
        return db.json(f"SELECT public.ottoq_charge_line_compare($a${cf.json.dumps(k)}$a$::jsonb, $b${cf.json.dumps(a)}$b$::jsonb)")

    k = {"on_time": 1, "late_sum": 10, "flow_sum": 500, "breach_sum": 80}
    assert cmp(k, dict(k, breach_sum=60, flow_sum=520)) | {} == {"cmp": 1, "by": "contract_wait", "d_on_time": 0,
                                                                 "d_late": 0, "d_flow": 20, "d_breach": -20}
    assert cmp(k, dict(k, breach_sum=100, flow_sum=400))["by"] == "contract_wait"
    assert cmp(k, dict(k, breach_sum=100, flow_sum=400))["cmp"] == -1
    assert cmp(k, dict(k, late_sum=0, breach_sum=200))["by"] == "lateness"       # lateness first
    assert cmp(k, dict(k, breach_sum=80.5, flow_sum=490))["by"] == "flow"        # within a minute: the depot decides
    # with the outflow on both sides, both visits' breach decides
    k2 = dict(k, flow2_sum=900, breach2_sum=120)
    assert cmp(k2, dict(k2, breach_sum=90, breach2_sum=100))["d_breach"] == -20
    # without breach on both sides, 0623's comparison exactly: no d_breach, the depot decides
    old = cmp({"on_time": 1, "late_sum": 10, "flow_sum": 500}, {"on_time": 1, "late_sum": 10, "flow_sum": 480, "breach_sum": 0})
    assert old == {"cmp": 1, "by": "flow", "d_on_time": 0, "d_late": 0, "d_flow": -20}


def test_the_board_says_how_the_kernel_orders(db):
    _through_0642(db)
    b = db.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')")
    assert b["kernel_order"] == {"floor_min": 90, "by": "charge_minutes"}
    _dial(db, "charge_order_minutes", 0)
    _dial(db, "charge_wait_floor_min", 60)
    b = db.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')")
    assert b["kernel_order"] == {"floor_min": 60, "by": "points"}
