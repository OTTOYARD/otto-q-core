"""db/migrations/0784, EXECUTED: the kernel takes an agent's charge order only when no owner is worse off (G504).

WHY THIS EXISTS. The check (0620) judged an agent's charge order by the depot's totals, so it took orders that made one
fleet's cars wait longer or finish later so another fleet's did better: of the 29 orders it took at the twin depot in
the ten days to 2026-10-25, 23 left an owner worse off in its own expected future (db/checks/0472). 0784 has the
simulator sum each owner's cars as it sums the line and the verdict refuse an order any owner would pay for, behind a
person's dial (CLAUDE.md rule 14). Executed here on the miniature depot of tests/test_agent_charge_order_sql.py carried
through 0642 and 0781 (tests/test_charge_order_exit_first_sql.py), whose state, simulator, verdict and board are the
live bodies after 0781 (md5 asserted):
  - 0784 applies, its checks run, it is classified FALSE/FALSE, and it refuses a run running, a world without 0781, a
    body it was not written against and a second apply;
  - at the default the state, the board, the simulator and the verdict read as before, key for key;
  - with the dial the state carries the guard and every car's owner, and the simulator's totals are the sums of its
    owners', over the cars now and their next visits;
  - end to end on one charger: an order that makes one fleet's car wait 30 minutes more past its contract so another
    fleet's car is ready by its due time is refused, 'worse_for_an_owner', where 0620's verdict takes it; with both cars
    one fleet's it is taken;
  - the board says the check judges each owner;
  - the pre-images restore every body.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)
import test_agent_charger_faults_sql as cf  # noqa: E402  (hand lines for the simulator)
import test_agent_outflow_sql as of  # noqa: E402  (a hand line whose cars leave and come back)
import test_charge_order_exit_first_sql as xf  # noqa: E402  (the miniature depot through 0642 and 0781)

ROOT = base.ROOT
M0784 = os.path.join(ROOT, "db", "migrations", "0784_the_check_takes_an_agents_order_only_when_no_owner_is_worse_off.sql")
NAME = "0784_the_check_takes_an_agents_order_only_when_no_owner_is_worse_off"
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_dial, _vid, _sim, _line, _car = base._dial, base._vid, cf._sim, cf._line, cf._car

STATE = "public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)"
SCHED = "public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)"
VERDICT = "public.ottoq_charge_order_verdict_v2(jsonb,numeric)"
BOARD = "public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)"
AFTER_0781 = {  # md5 of prosrc after 0781 (the verdict is 0620's, live on 2026-10-24); 0784's P1 pins them
    STATE: "c87de055e62f61b282bdb796f5cc53b6",
    SCHED: "4b40a03a7ac3383f654fdc104bcd6bbe",
    VERDICT: "394b3dc25ba60e8eccaa49f20474688c",
    BOARD: "2233be29c1338eeed76e9ae94c129273",
}
SUMS = ("on_time", "late_sum", "flow_sum", "breach_sum", "flow2_sum", "breach2_sum")

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_x784_tpl_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    xf._admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, xf.arb.ARB_STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        base._world(d)
        base._through_0618(d)
        xf.fl._through_0642(d)
        rc, err = d.file(xf.DECIDE)
        assert rc == 0, f"the live decide tick did not load: {err}"
        xf._apply(d)                                                     # 0781, its run completed
        xf._admin(f"ALTER DATABASE {name} WITH IS_TEMPLATE true")
        yield name
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"ALTER DATABASE {name} WITH IS_TEMPLATE false"], capture_output=True)
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


@pytest.fixture()
def db(template):
    name = f"ottoq_x784_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    xf._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    d = base.Db(name)
    try:
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _apply(d):
    rc, err = d.file(M0784)
    assert rc == 0, f"0784 did not apply: {err}"
    return err


def _state(d):
    return d.json(f"SELECT public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}')")


def _board(d):
    return d.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')")


def _verdict(d, state, order, futures=12, seed="s"):
    return d.json(f"""SELECT public.ottoq_charge_order_verdict_v2(
                        public.ottoq_charge_line_rollout($j${json.dumps(state)}$j$::jsonb, $o${json.dumps(order)}$o$::jsonb,
                                                         {futures}, '{seed}'), 0.8)""")


def _keyed(state, owners=None, mw=30):
    """The kernel's keys as the state carries them (0642), and with owners the guard (0784)."""
    s = dict(state, order_minutes=True, floor_min=90)
    s["cars"] = [dict(c, om=max(min(c["md"], c["ml"]), 1), mw=mw) for c in state["cars"]]
    if owners is not None:
        s.update(owner_guard=True, owners=owners)
    return s


def _adds_up(out):
    """Each total the simulator carries against the sum of its owners' (to rounding)."""
    by = out["by_owner"]
    for k in SUMS:
        if k in out:
            assert abs(float(out[k]) - sum(float(v[k]) for v in by.values())) <= 0.01 * len(by), (k, out[k], by)
        else:
            assert all(k not in v for v in by.values()), k


ONE = [{"id": "f", "k": "dcfc", "free": 0}]


def _pair(**kw):
    """One fast charger. G has waited 50 minutes and is the kernel's first; E has waited 10 and is due in 40. In the
    kernel's order G charges first and E is ready at 60, 20 minutes late; in the agent's order E is ready at 30, on time,
    and G waits 30 minutes more, 50 past its 30-minute contract wait instead of 20."""
    return _line([_car("g", md=30, ml=90, g=40, soc=60, w=50), _car("e", md=30, ml=90, g=40, soc=60, w=10, due=40)],
                 ONE, ttl=60, **kw)


AGENT = {"e": {"rank": 1, "kind": "dcfc"}}


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_chain_is_the_live_check_after_0781(db):
    for fn, want in AFTER_0781.items():
        assert xf._md5(db, fn) == want, fn


def test_0784_applies_its_checks_run_and_it_refuses_twice(db):
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0784)
    assert rc != 0 and "0784 P0: a run is running" in err, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    err = _apply(db)
    assert "0784 V1: 4 bodies are their pre-images with their anchors replaced" in err, err
    assert "0784 V2: at the default, run a0000000" in err and "read as before" in err, err
    assert "0784 V3: the verdict refuses an order an owner would pay for, which 0620's takes" in err, err
    assert "the expected future's totals is the sum of its 1 owners'" in err, err
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{NAME}'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0784_pre'") == "4"
    assert db.json("""SELECT jsonb_build_array(default_value, min_value, max_value, agent_writable)
                        FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_owner_guard'""") == [
        0, 0, 1, False]
    assert db.val("SELECT count(*) FROM public.ottoq_policy_params WHERE param_key = 'agent_charge_order_owner_guard'") == "0"
    rc, err = db.file(M0784)
    assert rc != 0 and "0784 P1: already applied" in err, err


def test_0784_refuses_a_world_without_0781_and_a_body_it_was_not_written_against(db):
    db.val("UPDATE public.ottoq_cert_lineage SET name = name || '_away' "
           "WHERE name = '0781_the_charge_line_serves_first_the_cars_a_charge_sends_home'")
    rc, err = db.file(M0784)
    assert rc != 0 and "0784 P1: 0781 is not applied" in err, err
    db.val("UPDATE public.ottoq_cert_lineage SET name = left(name, length(name) - 5) WHERE name LIKE '0781_%_away'")
    src = db.json(f"SELECT to_json(pg_get_functiondef('{VERDICT}'::regprocedure))")
    rc, out, err = db.run(src.replace("-- 0620: take the agent's order", "-- 0620 (edited): take the agent's order", 1))
    assert rc == 0, err
    rc, err = db.file(M0784)
    assert rc != 0 and "0784 P1: the verdict (0620)" in err and "is not the body this file patches" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0784_pre'") == "0"


# ── at the default nothing moves ──────────────────────────────────────────────────────────────────────────────────────

def test_at_the_default_the_state_board_simulator_and_verdict_read_as_before(db):
    xf._bays(db)
    lines = [_keyed(_pair()), _keyed(xf.fl.HAND[0]), _keyed(xf.fl.HAND[1]), _keyed(of._out_state())]
    runs = [(st, o, k) for st in lines for o in (None, AGENT) for k in (0, 2)]
    before = dict(state=_state(db), board=_board(db), sims=[_sim(db, st, o, k) for st, o, k in runs],
                  verdicts=[_verdict(db, st, AGENT) for st in lines])
    _apply(db)
    assert _state(db) == before["state"] and "owner_guard" not in before["state"]
    assert _board(db) == before["board"] and "owner_guard" not in before["board"]["check"]
    assert [_sim(db, st, o, k) for st, o, k in runs] == before["sims"]
    assert [_verdict(db, st, AGENT) for st in lines] == before["verdicts"]
    assert all("by_owner" not in s for s in before["sims"]) and all("owners" not in v for v in before["verdicts"])


# ── with the dial: each owner's cars ──────────────────────────────────────────────────────────────────────────────────

def test_with_the_dial_the_state_carries_the_guard_and_every_cars_owner(db):
    _apply(db)
    _dial(db, "agent_charge_order_owner_guard", 1)
    st = _state(db)
    owners = db.json(f"""SELECT jsonb_object_agg(id::text, fleet_operator_id) FROM public.vehicles
                          WHERE home_depot_id = '{DEPOT}' AND category = 'autonomous'""")
    assert st["owner_guard"] is True and st["owners"] == owners
    assert "exit_first" not in st                                       # 0781's key is its own dial
    # with 0781's key on too, the owners are carried once, the same
    _dial(db, "charge_order_exit_first", 1)
    st2 = _state(db)
    assert st2["owner_guard"] is True and st2["exit_first"] is True and st2["owners"] == owners
    # the simulator on the depot's own state: its totals are its one owner's
    out = _sim(db, st2)
    assert set(out["by_owner"]) == {base.OPERATOR}
    _adds_up(out)


def test_the_simulator_sums_each_owner_as_it_sums_the_line_over_both_visits(db):
    _apply(db)
    for st, owners in ((_keyed(_pair()), {"g": "W", "e": "T"}),
                       (_keyed(xf.fl.HAND[0]), {"a": "W", "b": "T", "c": "W", "d": "Z"}),
                       (_keyed(xf.fl.HAND[1]), {"a": "W", "b": "T"}),        # c has no owner: 'none'
                       (_keyed(of._out_state()), {"a": "W", "y": "T", "l": "T"})):
        for order in (None, AGENT):
            out = _sim(db, dict(st, owner_guard=True, owners=owners), order)
            unowned = any(c["id"] not in owners for c in st["cars"] + st.get("inbound", []))
            assert set(out["by_owner"]) == set(owners.values()) | ({"none"} if unowned else set())
            _adds_up(out)
    # the outflow: A's first charge is its fleet's, and the two returns that were never in the line carry no contract
    # wait; every return counts in its own fleet's minutes in the depot
    out = _sim(db, dict(_keyed(of._out_state()), owner_guard=True, owners={"a": "W", "y": "T", "l": "T"}))
    by = out["by_owner"]
    assert float(out["flow_sum"]) == 40 and float(out["flow2_sum"]) == 250
    assert (float(by["W"]["flow_sum"]), float(by["W"]["flow2_sum"])) == (40, 70)        # A: 40, then back 147-177
    assert (float(by["T"]["flow_sum"]), float(by["T"]["flow2_sum"])) == (0, 180)        # L 150, Y 30


# ── the verdict, end to end ───────────────────────────────────────────────────────────────────────────────────────────

def test_an_order_one_fleet_pays_for_is_refused_and_taken_when_no_fleet_pays(db):
    _apply(db)
    # without the guard (0620's verdict): the agent's order puts one more car on time and is taken
    v0 = _verdict(db, _keyed(_pair()), AGENT)
    assert (v0["take"], v0["reason"], v0["expected_by"], v0["wins"]) == (True, "wins_most_futures", "on_time", 12), v0
    assert "owners" not in v0
    # G and E two fleets': G's 30 more minutes past its contract buy E's due time; G's fleet pays, so it is refused
    v = _verdict(db, _keyed(_pair(), owners={"g": "W", "e": "T"}), AGENT)
    assert (v["take"], v["reason"], v["owners_worse"]) == (False, "worse_for_an_owner", 1), v
    assert (v["owners"]["W"]["cmp"], v["owners"]["W"]["by"], float(v["owners"]["W"]["d_breach"])) == (-1, "contract_wait", 30)
    assert (v["owners"]["T"]["cmp"], v["owners"]["T"]["by"]) == (1, "on_time")
    # the depot's totals are as before: the guard judges each fleet and changes nothing else
    assert {k: v[k] for k in ("expected", "expected_by", "wins", "futures", "need")} == \
        {k: v0[k] for k in ("expected", "expected_by", "wins", "futures", "need")}
    # both cars one fleet's: the fleet trades its own car's wait for its own car's due time, and it is taken
    v1 = _verdict(db, _keyed(_pair(), owners={"g": "W", "e": "W"}), AGENT)
    assert (v1["take"], v1["reason"], v1["owners_worse"]) == (True, "wins_most_futures", 0), v1
    # and an order worse for the depot is refused as before, the owners beside it
    vk = _verdict(db, _keyed(_pair(), owners={"g": "W", "e": "T"}), {"g": {"rank": 1, "kind": "dcfc"}})
    assert vk["reason"] == "same_as_kernel" and vk["take"] is False


def test_an_owner_absent_from_one_side_counts_zeros_there(db):
    _apply(db)
    k = {"on_time": 0, "late_sum": 0, "flow_sum": 30, "breach_sum": 0,
         "by_owner": {"A": {"on_time": 0, "late_sum": 0, "flow_sum": 30, "breach_sum": 0}}}
    a = {"on_time": 0, "late_sum": 0, "flow_sum": 20, "breach_sum": 0,
         "by_owner": {"A": {"on_time": 0, "late_sum": 0, "flow_sum": 10, "breach_sum": 0},
                      "B": {"on_time": 0, "late_sum": 0, "flow_sum": 10, "breach_sum": 0}}}
    point = db.json(f"SELECT public.ottoq_charge_line_compare($k${json.dumps(k)}$k$::jsonb, $a${json.dumps(a)}$a$::jsonb)")
    r = {"same_first_seats": False, "futures": 12, "wins": 12, "ties": 0, "losses": 0,
         "point": dict(point, kernel=k, agent=a), "first": {}, "per": []}
    v = db.json(f"SELECT public.ottoq_charge_order_verdict_v2($r${json.dumps(r)}$r$::jsonb, 0.8)")
    # B appears only in the agent's future, with 10 minutes in the depot against none: worse
    assert (v["owners"]["A"]["cmp"], v["owners"]["B"]["cmp"], v["reason"]) == (1, -1, "worse_for_an_owner"), v


# ── the board ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_board_says_the_check_judges_each_owner_only_with_the_dial(db):
    _apply(db)
    before = _board(db)
    assert "owner_guard" not in before["check"]
    _dial(db, "agent_charge_order_owner_guard", 1)
    b = _board(db)
    assert b["check"]["owner_guard"] is True
    assert {k: v for k, v in b["check"].items() if k != "owner_guard"} == before["check"]


# ── it rolls back ─────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_pre_images_restore_every_body(db):
    _apply(db)
    for d in db.json("SELECT jsonb_agg(definition ORDER BY object_name) FROM public.ottoq_schema_snapshots "
                     "WHERE label = '0784_pre'"):
        rc, out, err = db.run(d)
        assert rc == 0, err
    for fn, want in AFTER_0781.items():
        assert xf._md5(db, fn) == want, fn
