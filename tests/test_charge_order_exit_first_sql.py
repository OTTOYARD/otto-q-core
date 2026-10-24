"""db/migrations/0781, EXECUTED: the charge line serves first the cars a charge sends home (G501).

WHY THIS EXISTS. 0781 changes who OTTO-Q's seat charges next once a person turns charge_order_exit_first on: a car whose
turn in the service bays is hours away yields its place to its own owner's cars whose charge is their way out, until its
turn comes within its charge and a margin, and never to another owner's car: each owner's cars hold the places they held
without the dial. Every claim in its header that a test can execute is executed here, on the scratch
PostgreSQL and the miniature depot of tests/test_agent_charge_order_sql.py taken through 0642 as
tests/test_charge_order_floor_sql.py takes it, whose keys, kernel's order, cockpits' queue, learning read, check's state
and simulator and agent's board are the live bodies (md5 asserted below, as read from the live catalog on 2026-10-24),
with the live decide tick loaded from tests/fixtures/exit_first_decide_live.sql (md5 asserted):
  - 0781 applies whole on the live bodies, its checks run (V2 and V3 on the miniature run), it is classified
    FALSE/FALSE, and it refuses a run running, a body it was not written against and a second apply;
  - the bay line: per lane, work the depot took away first, then arrival; the work ahead of each car, the bays' current
    work by its active booking, a bay in maintenance not counted, a car in the lane's bay not in its line;
  - the keys: at the default 0642's keys exactly and no exit key or rank; with the dial, exit_key 1 exactly for a car
    whose turn in the bays is its minutes of charge and the margin away, 0 for every other car the clock times, and
    exit_rank each car's place in the line;
  - the kernel's order, the cockpits' queue and the learning read agree, immediate dispatch and the floor first; with
    two owners each owner's cars hold the places they held without the dial, and a car yields only to its own owner's;
  - the cursor reads the rank with the other keys, sorts by it after the agent's keys and before the floor, and records
    the exit key, the turn and the rank only when the rank is set;
  - the check: a state without the key is the state before 0781 and simulates exactly as before; with it the state
    carries each car's turn in the bays and each car's owner, and the simulator has a car yield to its own owner's cars
    while bx - t - om >= the margin, rejoin once it is not, take back its place once its owner has no car to yield to,
    and keeps the floor first;
  - the board says how the kernel orders and which cars yield;
  - the pre-images restore every body.
A module template carries the miniature depot through 0642 and the live decide tick, and each test clones it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import math
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402
import test_agent_charger_faults_sql as cf  # noqa: E402  (hand lines for the simulator)
import test_charge_order_floor_sql as fl  # noqa: E402  (0619-0642, the chain to the live charge line)

ROOT = base.ROOT
M0781 = os.path.join(ROOT, "db", "migrations", "0781_the_charge_line_serves_first_the_cars_a_charge_sends_home.sql")
DECIDE = os.path.join(ROOT, "tests", "fixtures", "exit_first_decide_live.sql")
NAME = "0781_the_charge_line_serves_first_the_cars_a_charge_sends_home"
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_vid, _dial, _sim, _line, _car = base._vid, base._dial, cf._sim, cf._line, cf._car

KEYS = "public.ottoq_charge_order_keys(uuid,uuid,timestamp with time zone)"
KORDER = "public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)"
QUEUE = "public.ottoq_depot_queue(uuid,uuid)"
LEARN = "public.ottoq_run_learning(uuid,integer,boolean)"
STATE = "public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)"
SCHED = "public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)"
BOARD = "public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)"
TICK = "public.ottoq_decide_tick(uuid)"
LIVE = {  # md5 of prosrc, read from the live catalog on 2026-10-24 (17:53:58 UTC for the decide tick); 0781's P1 pins them
    KEYS: "877318ab6ad7f7cf193ddd3e17938a1d",
    KORDER: "100476a9bfa33e48b7495f6921979301",
    QUEUE: "c84852a2e3f385d12b8ce4a77ada094a",
    LEARN: "3f4aa75740ef67f9e0c9ea6079ac58e0",
    STATE: "c05f29bc7da1068acf1dfc1bad362ba5",
    SCHED: "0c4c8d2c5ecdcb84fd97d78dfa4c85a5",
    BOARD: "03cbb1a2e3b75a82874de01f7cf635ba",
    TICK: "2b3d0cbf5cdb13ca24f0de788073dc46",
}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_x781_tpl_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, arb.ARB_STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        base._world(d)
        base._through_0618(d)
        fl._through_0642(d)
        rc, err = d.file(DECIDE)
        assert rc == 0, f"the live decide tick did not load: {err}"
        _admin(f"ALTER DATABASE {name} WITH IS_TEMPLATE true")
        yield name
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"ALTER DATABASE {name} WITH IS_TEMPLATE false"], capture_output=True)
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


@pytest.fixture()
def db(template):
    name = f"ottoq_x781_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    d = base.Db(name)
    try:
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _md5(d, fn):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')")


def _apply(d):
    d.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    rc, err = d.file(M0781)
    assert rc == 0, f"0781 did not apply: {err}"
    return err


def _exit_on(d, margin=None):
    _dial(d, "charge_order_exit_first", 1)
    if margin is not None:
        _dial(d, "charge_order_exit_margin_min", margin)


def _name(d, vid):
    return base.NAMES.get(vid) or d.val(f"SELECT display_name FROM public.vehicles WHERE id = '{vid}'")


def _bay(d, code, kind, status="available"):
    sid = _vid(code)
    d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_type, stall_code, display_name, status, relative_y)
              VALUES ('{sid}', '{DEPOT}', '{kind}', '{code}', '{code}', '{status}', {len(code)})""")
    return sid


def _work(d, car, atoms, arrived_min=None):
    """Replace the car's open visit's atoms (charge first, then these bay atoms), and its arrival."""
    arr = "NULL" if arrived_min is None else f"'{T}'::timestamptz - interval '{arrived_min} minutes'"
    d.val(f"""UPDATE public.ottoq_visit_needs SET atoms = $a${json.dumps([{"svc": "charge", "est_min": 48}] + atoms)}$a$::jsonb,
                                                 arrived_at = {arr}
               WHERE vehicle_id = '{_vid(car)}' AND sim_run_id = '{RUN}'""")


def _svc(svc, est, **kw):
    return dict({"svc": svc, "est_min": est, "status": "pending", "must_do": True, "concurrency": "bay",
                 "requires_bay": "service_bay"}, **kw)


def _wash(est, **kw):
    return dict({"svc": "exterior_wash", "est_min": est, "status": "pending", "must_do": True, "concurrency": "bay",
                 "requires_bay": "wash_bay"}, **kw)


def _bays(d):
    """The miniature depot's bays and work: three service bays (one in maintenance), one wash bay; Q in a service bay
    with 25 minutes left on its active booking; D's repair was taken away (first in line); P, A, C and I owe service
    work, C a wash too; B owes no bay work."""
    s1 = _bay(d, "SVC1", "service_bay")
    _bay(d, "SVC2", "service_bay")
    _bay(d, "SVC3", "service_bay", status="maintenance")
    _bay(d, "W1", "wash_bay")
    q = base._car(d, "Q", 90, 0, state="in_service_bay")
    d.val(f"""INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_by)
              VALUES ('{RUN}', '{s1}', '{q}', 'service',
                      tstzrange('{T}'::timestamptz - interval '15 minutes', '{T}'::timestamptz + interval '25 minutes'),
                      'active', 'otto_q_enacted')""")
    _work(d, "Q", [_svc("mechanical_pm", 40, status="in_progress")], arrived_min=60)
    _work(d, "D", [_svc("fault_repair", 200, reopened_at="2026-10-07T14:00:00+00:00")], arrived_min=10)
    _work(d, "P", [_svc("mechanical_pm", 40)], arrived_min=120)
    _work(d, "A", [_svc("mechanical_pm", 40)], arrived_min=40)
    _work(d, "C", [_svc("sensor_calibration", 60), _wash(10)], arrived_min=20)
    _work(d, "I", [_svc("mechanical_pm", 40)], arrived_min=5)
    _work(d, "B", [], arrived_min=35)


def _line_rows(d):
    return {(_name(d, r["v"]), r["lane"]): r for r in d.json(f"""
        SELECT COALESCE(jsonb_agg(jsonb_build_object('v', l.vehicle_id, 'lane', l.lane, 'pos', l.pos, 'open', l.open_min,
                                                     'ahead', l.ahead_min, 'bays', l.bays, 'eta', l.eta_min)), '[]')
          FROM public.ottoq_bay_line('{RUN}', '{DEPOT}', '{T}') l""")}


def _keys(d):
    """Each car's keys by name: w, m, f, mk (0642) and, from 0781, x, eta and r (the rank). Read whole, so it reads
    before 0781 too."""
    out = {}
    for r in d.json(f"""SELECT COALESCE(jsonb_agg(to_jsonb(k)), '[]')
                         FROM public.ottoq_charge_order_keys('{RUN}', '{DEPOT}', '{T}') k"""):
        row = {"w": r["wait_min"], "m": r["minutes"], "f": r["floor_key"], "mk": r["minutes_key"]}
        if "exit_key" in r:
            row.update(x=r["exit_key"], eta=r["bay_eta_min"], r=r["exit_rank"])
        out[_name(d, r["vehicle_id"])] = row
    return out


def _kernel(d):
    return [_name(d, v) for v in d.json(f"""
        SELECT COALESCE(jsonb_agg(vehicle_id ORDER BY kernel_pos), '[]')
          FROM public.ottoq_charge_queue_kernel_order('{RUN}', '{DEPOT}', '{T}')""")]


def _immediate(d):
    return {_name(d, v) for v in d.json(f"""
        SELECT COALESCE(jsonb_agg(vehicle_id), '[]')
          FROM public.ottoq_charge_queue_kernel_order('{RUN}', '{DEPOT}', '{T}') WHERE immediate""")}


OTHER = "44444444-4444-4444-4444-444444444444"     # a second fleet at the depot


def _owners(d, others):
    """The cars named in others are the second fleet's; every other car is the first's (base.OPERATOR)."""
    d.val(f"INSERT INTO public.fleet_operators (id, name) VALUES ('{OTHER}', 'Waymo TN') ON CONFLICT (id) DO NOTHING")
    d.val(f"UPDATE public.vehicles SET fleet_operator_id = '{base.OPERATOR}'")
    for c in others:
        d.val(f"UPDATE public.vehicles SET fleet_operator_id = '{OTHER}' WHERE id = '{_vid(c)}'")


def _exchange(order, k, owner, imm):
    """0781's rank by hand: the order without the key, with each owner's cars below the floor and not immediate
    reordered among the places that owner's cars hold, its cars whose exit key is 0 first, each group in that order."""
    out, places = list(order), {}
    for pos, c in enumerate(order):
        if c not in imm and k[c]["f"] is None:
            places.setdefault(owner[c], []).append(pos)
    for pos in places.values():
        cars = sorted((order[p] for p in pos), key=lambda c: (k[c]["x"] or 0, order.index(c)))
        for p, c in zip(pos, cars):
            out[p] = c
    return out


def _cockpit(d):
    return [_name(d, v) for v in d.json(f"""
        SELECT COALESCE(jsonb_agg(vehicle_id ORDER BY queue_position), '[]')
          FROM public.ottoq_depot_queue('{DEPOT}', '{RUN}') WHERE queue_kind = 'charge'""")]


def _learning(d):
    return [_name(d, e["vehicle_id"]) for e in sorted(
        d.json(f"SELECT public.ottoq_run_learning('{RUN}', 20, true) #> '{{queue,head}}'") or [], key=lambda e: e["pos"])]


def _readers(d):
    return {"keys": _keys(d), "kernel": _kernel(d), "cockpit": _cockpit(d), "learning": _learning(d),
            "state": d.json(f"SELECT public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}')"),
            "board": d.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')")}


# ── it applies on the live bodies ─────────────────────────────────────────────────────────────────────────────────────

def test_the_chain_is_the_live_charge_line_and_the_live_decide_tick(db):
    for fn, want in LIVE.items():
        assert _md5(db, fn) == want, fn


def test_0781_applies_its_checks_run_and_it_refuses_twice(db):
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0781)
    assert rc != 0 and "0781 P0: a run is running" in err, err
    err = _apply(db)
    assert "0781 V1: 7 bodies are their pre-images with their anchors replaced; the keys carry 0642's grants" in err, err
    assert "0781 V2: at the defaults, run a0000000" in err and "read as before" in err, err
    assert "0781 V3: with the dial at 1 on run a0000000: 6 of 6 waiting cars timed, all keyed" in err, err
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{NAME}'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0781_pre'") == "8"
    assert db.json("""SELECT jsonb_object_agg(param_key, jsonb_build_array(default_value, min_value, max_value, agent_writable))
                        FROM public.ottoq_policy_param_catalog
                       WHERE param_key IN ('charge_order_exit_first', 'charge_order_exit_margin_min')""") == {
        "charge_order_exit_first": [0, 0, 1, False], "charge_order_exit_margin_min": [30, 0, 240, False]}
    # the dial row V3 wrote rolled back with its sub-block
    assert db.val("SELECT count(*) FROM public.ottoq_policy_params WHERE param_key LIKE 'charge_order_exit%'") == "0"
    rc, err = db.file(M0781)
    assert rc != 0 and "0781 P1: already applied" in err, err


def test_0781_refuses_a_body_it_was_not_written_against(db):
    src = db.json(f"SELECT to_json(pg_get_functiondef('{KORDER}'::regprocedure))")
    rc, out, err = db.run(src.replace("-- 0614: the charge line", "-- 0614 (edited): the charge line", 1))
    assert rc == 0, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0781)
    assert rc != 0 and "0781 P1: the kernel's own order" in err and "is not the body this file patches" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0781_pre'") == "0"


# ── the bay line ──────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_bay_line_is_work_taken_away_first_then_arrival_over_the_bays(db):
    _apply(db)
    _bays(db)
    line = _line_rows(db)
    svc = {c: r for (c, lane), r in line.items() if lane == "service_bay"}
    # D's repair was taken away: first. Then by arrival: P (120 min ago), A (40), C (20), I (5). Q is in a bay: not in
    # line, its 25 minutes left are ahead of everyone; SVC3 is in maintenance: two bays.
    assert sorted(svc, key=lambda c: svc[c]["pos"]) == ["D", "P", "A", "C", "I"]
    assert all(r["bays"] == 2 for r in svc.values())
    assert {c: float(r["ahead"]) for c, r in svc.items()} == {"D": 25, "P": 225, "A": 265, "C": 305, "I": 365}
    assert {c: float(r["eta"]) for c, r in svc.items()} == {"D": 12.5, "P": 112.5, "A": 132.5, "C": 152.5, "I": 182.5}
    assert {c: float(r["open"]) for c, r in svc.items()} == {"D": 200, "P": 40, "A": 40, "C": 60, "I": 40}
    # the wash lane: C alone, one bay, nothing in it
    assert {c: (r["pos"], float(r["ahead"]), r["bays"], float(r["eta"]))
            for (c, lane), r in line.items() if lane == "wash_bay"} == {"C": (1, 0, 1, 0)}
    assert ("B", "service_bay") not in line and ("Q", "service_bay") not in line


def test_the_bay_line_reads_only_this_runs_open_unfinished_bay_work(db):
    _apply(db)
    _bays(db)
    # A's work done, C's calibration under way, I's visit closed, P's visit another run's: none of it is in the line
    _work(db, "A", [_svc("mechanical_pm", 40, status="done")], arrived_min=40)
    _work(db, "C", [_svc("sensor_calibration", 60, status="in_progress"), _wash(10)], arrived_min=20)
    db.val(f"UPDATE public.ottoq_visit_needs SET status = 'closed' WHERE vehicle_id = '{_vid('I')}'")
    db.val(f"UPDATE public.ottoq_visit_needs SET sim_run_id = '{uuid.uuid4()}' WHERE vehicle_id = '{_vid('P')}'")
    line = _line_rows(db)
    assert sorted(line) == [("C", "wash_bay"), ("D", "service_bay")]
    # and a car in a wash bay is out of the wash line but still in the service line it owes
    db.val(f"UPDATE public.vehicles SET current_state = 'in_wash_bay' WHERE id = '{_vid('C')}'")
    _work(db, "C", [_svc("sensor_calibration", 60), _wash(10)], arrived_min=20)
    assert sorted(_line_rows(db)) == [("C", "service_bay"), ("D", "service_bay")]


# ── the keys ──────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_at_the_default_the_keys_and_every_reader_are_0642s(db):
    _bays(db)
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    before = _readers(db)
    _apply(db)
    after = _readers(db)
    for k in before["keys"].values():
        assert "x" not in k and "eta" not in k
    for c, k in after["keys"].items():
        assert k["x"] is None and k["eta"] is None and k["r"] is None
        assert {f: k[f] for f in ("w", "m", "f", "mk")} == {f: before["keys"][c][f] for f in ("w", "m", "f", "mk")}
    for r in ("kernel", "cockpit", "learning", "state", "board"):
        assert after[r] == before[r], r
    assert "exit_first" not in after["state"] and "owners" not in after["state"]
    assert all("bx" not in c for c in after["state"]["cars"])
    assert "exit_first" not in after["board"]["kernel_order"]


def test_with_the_dial_a_car_yields_exactly_when_its_turn_is_its_charge_and_the_margin_away(db):
    _apply(db)
    _bays(db)
    _exit_on(db)
    k = _keys(db)
    line = _line_rows(db)
    eta = {}
    for (c, lane), r in line.items():
        eta[c] = max(eta.get(c, 0), float(r["eta"]))
    assert set(k) == {"A", "B", "C", "D", "I", "P"}
    for c, r in k.items():
        assert r["m"] is not None                                        # every car here is timed
        want_eta = eta.get(c)
        assert (None if r["eta"] is None else float(r["eta"])) == want_eta, c
        assert r["x"] == (1 if want_eta is not None and want_eta - float(r["m"]) >= 30 else 0), c
    # B owes no bay work; D's turn is 12.5 minutes away: neither yields
    assert k["B"]["x"] == 0 and k["B"]["eta"] is None and k["D"]["x"] == 0
    # the floor and minutes are untouched by the dial
    assert k["P"]["f"] is not None and all(k[c]["f"] is None for c in "ABCDI")
    for c in k:
        assert float(k[c]["mk"]) == pytest.approx((float(k[c]["w"]) + float(k[c]["m"])) / float(k[c]["m"]), rel=1e-9)
    # a wider margin: fewer cars yield, never more
    yield30 = {c for c, r in k.items() if r["x"] == 1}
    _dial(db, "charge_order_exit_margin_min", 80)
    yield80 = {c for c, r in _keys(db).items() if r["x"] == 1}
    assert yield80 < yield30 and {"A", "C"} <= yield30, (yield30, yield80)


def test_a_car_the_clock_cannot_time_carries_no_exit_key(db):
    _apply(db)
    _bays(db)
    _exit_on(db)
    db.val(f"UPDATE public.vehicles SET battery_capacity_kwh = NULL WHERE id = '{_vid('A')}'")
    k = _keys(db)
    assert k["A"]["m"] is None and k["A"]["x"] is None and k["A"]["eta"] is None and k["A"]["mk"] is None


# ── every reader orders the line by the same keys ─────────────────────────────────────────────────────────────────────

def test_the_kernels_order_the_cockpits_queue_and_the_learning_read_agree(db):
    _apply(db)
    _bays(db)
    _exit_on(db)
    k = _keys(db)
    # immediate dispatch first (I), then the floor (P, 120 minutes), then the cars whose charge is their exit by minutes,
    # then the cars the bays will hold by minutes
    rest = [c for c in "ABCD"]
    want = ["I", "P"] + sorted([c for c in rest if k[c]["x"] == 0], key=lambda c: -float(k[c]["mk"])) \
        + sorted([c for c in rest if k[c]["x"] == 1], key=lambda c: -float(k[c]["mk"]))
    assert _kernel(db) == want
    assert _cockpit(db) == want
    assert _learning(db) == want
    assert {c: k[c]["r"] for c in k} == {c: want.index(c) + 1 for c in want}   # the rank is the place
    # the dial changed the order: at 0 the bays' cars are ordered by minutes among the rest
    _dial(db, "charge_order_exit_first", 0)
    off = ["I", "P"] + sorted(rest, key=lambda c: -float(k[c]["mk"]))
    assert _kernel(db) == off and _cockpit(db) == off and _learning(db) == off
    assert want != off


def test_with_two_owners_a_car_yields_only_to_its_own_owners_cars(db):
    _apply(db)
    _bays(db)
    _owners(db, ["A", "B"])                      # A and B are the second fleet's; C, D, I and P stay the first's
    off = _kernel(db)
    _exit_on(db)
    k = _keys(db)
    imm = _immediate(db)
    assert imm == {"I"} and k["A"]["x"] == 1 and k["C"]["x"] == 1 and k["B"]["x"] == 0 and k["D"]["x"] == 0
    owner = {c: ("other" if c in "AB" else "first") for c in k}
    want = _exchange(off, k, owner, imm)
    assert _kernel(db) == want and _cockpit(db) == want and _learning(db) == want
    assert {c: k[c]["r"] for c in k} == {c: want.index(c) + 1 for c in want}
    # every owner's cars hold the places they held without the dial: B goes before A, D before C, and no car of one
    # fleet moves into a place the other's held
    for o in ("first", "other"):
        assert [i for i, c in enumerate(want) if owner[c] == o] == [i for i, c in enumerate(off) if owner[c] == o], o
    assert want.index("B") < want.index("A") and want.index("D") < want.index("C")
    # with A and C alone in their fleet, both yielding, nothing moves: neither yields to B or D, the first fleet's
    _owners(db, ["A", "C"])
    _dial(db, "charge_order_exit_first", 0)
    off2 = _kernel(db)
    _dial(db, "charge_order_exit_first", 1)
    assert _kernel(db) == off2 == _cockpit(db) == _learning(db)
    # and one fleet for every car is the order of the test above: the exit-bound cars first among the four
    _owners(db, [])
    one = _kernel(db)
    assert [c for c in one if c not in ("I", "P")][:2] in (["B", "D"], ["D", "B"]), one


def test_a_car_of_no_fleet_shares_one_fleets_places_with_the_others_of_none(db):
    _apply(db)
    _bays(db)
    db.val("UPDATE public.vehicles SET fleet_operator_id = NULL")
    _exit_on(db)
    k = _keys(db)
    _dial(db, "charge_order_exit_first", 0)
    off = _kernel(db)
    _dial(db, "charge_order_exit_first", 1)
    assert _kernel(db) == _exchange(off, k, {c: None for c in k}, _immediate(db)) != off


def test_the_floor_still_serves_a_long_wait_first_whatever_its_turn_in_the_bays(db):
    _apply(db)
    _bays(db)
    _exit_on(db)
    k = _keys(db)
    gated = [c for c in "AC" if k[c]["x"] == 1]
    assert gated, k
    db.val(f"UPDATE public.vehicles SET last_state_change = '{T}'::timestamptz - interval '150 minutes' "
           f"WHERE id = '{_vid(gated[0])}'")
    k = _keys(db)
    assert k[gated[0]]["x"] == 1 and float(k[gated[0]]["f"]) == 150
    assert _kernel(db)[:3] == ["I", gated[0], "P"]                       # floored, the longest wait first


# ── the cursor ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_cursor_reads_the_rank_with_the_others_and_sorts_by_it_before_the_floor(db):
    _apply(db)
    src = db.json(f"SELECT to_json(prosrc) FROM pg_proc WHERE oid = '{TICK}'::regprocedure")
    assert src.count("public.ottoq_charge_order_keys(p_sim_run_id, v_depot, v_clock)") == 1
    # at the default every rank is NULL and each car carries 0642's two keys; with the rank, all five
    assert ("CASE WHEN k.exit_rank IS NULL THEN jsonb_build_array(k.floor_key, k.minutes_key)\n"
            "                    ELSE jsonb_build_array(k.floor_key, k.minutes_key, k.exit_key, k.bay_eta_min, k.exit_rank) END"
            in src)
    assert "WHERE k.floor_key IS NOT NULL OR k.minutes_key IS NOT NULL OR k.exit_rank IS NOT NULL;" in src
    agent = src.index("public.ottoq_agent_charge_order_key(v_ao_order, v.id, v_ao_mode)")
    baseline = src.index("CASE WHEN v_seat = 2 THEN v.current_soc END ASC,")
    rank = src.index("(v_ok -> v.id::text ->> 4)::numeric ASC NULLS LAST")
    floor = src.index("(v_ok -> v.id::text ->> 0)::numeric DESC NULLS LAST")
    minutes = src.index("(v_ok -> v.id::text ->> 1)::numeric DESC NULLS LAST")
    assert agent < baseline < rank < floor < minutes < src.index("CASE WHEN v_seat = 0 THEN")
    # the record: the keys as before, and the exit key, the turn and the rank only when the rank is set
    rec = src.index("IF v_ok -> v_req.vehicle_id::text ->> 4 IS NOT NULL THEN")
    assert src.index("'floor_key', v_ok -> v_req.vehicle_id::text -> 0, 'minutes_key'") < rec
    for f in ("'exit_key', v_ok -> v_req.vehicle_id::text -> 2,", "'bay_eta_min', v_ok -> v_req.vehicle_id::text -> 3,",
              "'exit_rank', v_ok -> v_req.vehicle_id::text -> 4"):
        assert f in src[rec:rec + 500], f


# ── the check's state and simulator ───────────────────────────────────────────────────────────────────────────────────

def _order_of(r):
    return [s["id"] for s in sorted(r["seats"], key=lambda s: (s["s0"] if s["s0"] is not None else 1e9, s["id"]))]


def _keyed(state, floor=90, exit_first=False, margin=30, owners=None):
    s = dict(state, order_minutes=True, floor_min=floor)
    s["cars"] = [dict(c, om=max(min(c["md"], c["ml"]), 1), mw=30) for c in state["cars"]]
    if exit_first:
        s.update(exit_first=True, exit_margin_min=margin)
        if owners is not None:
            s["owners"] = owners
    return s


ONE = [{"id": "f", "k": "dcfc", "free": 0}]


def test_without_the_key_the_simulator_is_exactly_as_before(db):
    lines = [_keyed(_line([_car("g", md=30, ml=90, g=40, soc=60, w=50, bx=200), _car("e", md=30, ml=90, g=40, soc=60, w=10)],
                          ONE)),
             _keyed(fl.HAND[0]), _keyed(fl.HAND[1], floor=0), fl.HAND[0]]
    runs = [(st, o, k) for st in lines for o in (None, {"e": {"rank": 1, "kind": "dcfc"}}) for k in (0, 3)]
    before = [_sim(db, st, o, k) for st, o, k in runs]
    _apply(db)
    assert [_sim(db, st, o, k) for st, o, k in runs] == before          # a bx without exit_first sorts nothing


def test_with_the_key_a_car_yields_to_a_car_whose_charge_is_its_exit(db):
    _apply(db)
    st = _line([_car("g", md=30, ml=90, g=40, soc=60, w=50, bx=200), _car("e", md=30, ml=90, g=40, soc=60, w=10)], ONE)
    # by minutes, g first: (50 + 30) / 30 against (10 + 30) / 30
    assert _order_of(_sim(db, _keyed(st))) == ["g", "e"]
    # with the key g's turn in the bays is 200 minutes away: it yields, and is charged after e, 170 minutes early
    r = _sim(db, _keyed(st, exit_first=True))
    assert _order_of(r) == ["e", "g"]
    assert {s["id"]: s["s0"] for s in r["seats"]} == {"e": 0, "g": 30}


def test_a_car_rejoins_the_front_once_its_turn_comes_within_its_charge_and_the_margin(db):
    _apply(db)
    st = _line([_car("g", md=30, ml=90, g=40, soc=60, w=20, bx=70),
                _car("e1", md=30, ml=90, g=40, soc=60, w=0), _car("e2", md=30, ml=90, g=40, soc=60, w=0)], ONE)
    # by minutes alone g goes first: (20 + 30) / 30 against 1
    assert _order_of(_sim(db, _keyed(st))) == ["g", "e1", "e2"]
    # at 0: 70 - 0 - 30 = 40 >= 30, g yields; e1 and e2 tie and fall to 0545's ratio, then the id: e1. At 30: 70 - 30 -
    # 30 = 10 < 30, g is a car whose charge is its exit again, and by minutes (50 + 30) / 30 against e2's 2: g
    assert _order_of(_sim(db, _keyed(st, exit_first=True))) == ["e1", "g", "e2"]
    # with a margin of 0 it yields until 70 - t - 30 < 0, t > 40: e1, then e2 at 30, then g at 60
    assert _order_of(_sim(db, _keyed(st, exit_first=True, margin=0))) == ["e1", "e2", "g"]
    # and the floor comes first: g past 90 minutes goes ahead whatever its turn
    st2 = _line([_car("g", md=30, ml=90, g=40, soc=60, w=95, bx=500), _car("e", md=30, ml=90, g=40, soc=60, w=0)], ONE)
    assert _order_of(_sim(db, _keyed(st2, exit_first=True))) == ["g", "e"]
    assert _order_of(_sim(db, _keyed(st2, floor=0, exit_first=True))) == ["e", "g"]


def test_in_the_futures_a_car_yields_only_to_its_own_owners_cars(db):
    _apply(db)
    st = _line([_car("g", md=30, ml=90, g=40, soc=60, w=50, bx=200), _car("e", md=30, ml=90, g=40, soc=60, w=10)], ONE)
    assert _order_of(_sim(db, _keyed(st, exit_first=True, owners={"g": "W", "e": "W"}))) == ["e", "g"]
    # e is another fleet's: g keeps its place
    assert _order_of(_sim(db, _keyed(st, exit_first=True, owners={"g": "W", "e": "T"}))) == ["g", "e"]
    # three cars on one charger, by minutes g (w 50), e (w 30), h (w 10); g's turn in the bays 200 minutes away
    st3 = _line([_car("g", md=30, ml=90, g=40, soc=60, w=50, bx=200), _car("e", md=30, ml=90, g=40, soc=60, w=30),
                 _car("h", md=30, ml=90, g=40, soc=60, w=10)], ONE)
    # one fleet: e and h, whose charge is their exit, first, then g
    assert _order_of(_sim(db, _keyed(st3, exit_first=True, owners={"g": "W", "e": "W", "h": "W"}))) == ["e", "h", "g"]
    # g and h one fleet's, e another's: at 0 g and h trade their fleet's places (first and third), so h is charged
    # first; at 30 g is its fleet's only car in line and takes back its place ahead of e
    assert _order_of(_sim(db, _keyed(st3, exit_first=True, owners={"g": "W", "e": "T", "h": "W"}))) == ["h", "g", "e"]
    # every car its own fleet's: nothing moves
    assert _order_of(_sim(db, _keyed(st3, exit_first=True, owners={"g": "W", "e": "T", "h": "Z"}))) == ["g", "e", "h"]
    # a car the owners do not name is one with the others of none
    assert _order_of(_sim(db, _keyed(st3, exit_first=True, owners={"e": "T"}))) == ["h", "g", "e"]


def test_the_state_carries_each_cars_turn_in_the_bays_and_the_futures_follow_the_kernel(db):
    _apply(db)
    _bays(db)
    _exit_on(db)
    k = _keys(db)
    st = db.json(f"SELECT public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}')")
    assert st["exit_first"] is True and st["exit_margin_min"] == 30
    cars = db.json(f"""SELECT jsonb_object_agg(id::text, fleet_operator_id) FROM public.vehicles
                        WHERE home_depot_id = '{DEPOT}' AND category = 'autonomous'""")
    assert st["owners"] == cars and set(cars.values()) == {base.OPERATOR}
    bx = {_name(db, c["id"]): c.get("bx") for c in st["cars"]}
    for c, r in k.items():
        if c in bx:
            assert (None if r["eta"] is None else float(r["eta"])) == (None if bx[c] is None else float(bx[c])), c
    # the state's own minutes and turns give the kernel's exit key, car for car
    for c in st["cars"]:
        n = _name(db, c["id"])
        want = 1 if c.get("bx") is not None and float(c["bx"]) - float(c["om"]) >= 30 else 0
        assert want == k[n]["x"], n
    # the expected future seats the line in the kernel's order: with one standard charger down, four are free for six
    # cars, and the four the future seats at once are the kernel's first four; with the dial at 0, the kernel's first
    # four are another four, and so are the future's
    db.val(f"UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted' WHERE charger_id = '{_vid('L3')}'")
    for on, want in ((1, {"I", "P", "B", "D"}), (0, {"I", "P", "B", "A"})):
        _dial(db, "charge_order_exit_first", on)
        st = db.json(f"SELECT public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}')")
        assert len(st["chargers"]) == 4
        seated0 = {_name(db, x["id"]) for x in _sim(db, st)["seats"] if x["s0"] == 0}
        assert seated0 == set(_kernel(db)[:4]) == want, (on, seated0)


# ── the board ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_board_says_how_the_kernel_orders_and_which_cars_yield(db):
    _apply(db)
    _bays(db)
    b = db.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')")
    assert b["kernel_order"] == {"floor_min": 90, "by": "charge_minutes"}
    assert all("bays_in_min" not in c for c in b["cars"])
    _exit_on(db, margin=45)
    k = _keys(db)
    b = db.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')")
    assert b["kernel_order"] == {"floor_min": 90, "by": "charge_minutes", "exit_first": True,
                                 "exit_yields_to": "own_operator", "exit_margin_min": 45}
    imm = _immediate(db)
    cars = {c["name"]: c for c in b["cars"]}
    for n, c in cars.items():
        if k[n]["eta"] is None:
            assert "bays_in_min" not in c and "yields" not in c, n
        else:
            assert c["bays_in_min"] == math.floor(float(k[n]["eta"]) + 0.5), n      # SQL rounds half away from zero
            # a car yields when its key is 1, below the floor and not an immediate dispatch, as the rank has it
            assert c["yields"] is (k[n]["x"] == 1 and k[n]["f"] is None and n not in imm), n
    assert any(c.get("yields") for c in cars.values()) and not cars["P"].get("yields")


# ── it rolls back ─────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_pre_images_restore_every_body(db):
    _apply(db)
    db.val("DROP FUNCTION public.ottoq_charge_order_keys(uuid, uuid, timestamptz)")
    for (d,) in [(x,) for x in db.json("""SELECT jsonb_agg(definition ORDER BY (object_name <> 'ottoq_charge_order_keys'),
                                                                     object_name)
                                             FROM public.ottoq_schema_snapshots WHERE label = '0781_pre'""")]:
        rc, out, err = db.run(d)
        assert rc == 0, err
    for fn, want in LIVE.items():
        assert _md5(db, fn) == want, fn
