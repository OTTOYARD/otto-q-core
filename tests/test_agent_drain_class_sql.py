"""db/migrations/0628, EXECUTED: the futures drain each car at its own rate.

WHY THIS EXISTS. 0627 called each working car home at its own reserve rung, and what it left of the arrivals' error is the
drain: the futures drained every car at the depot's one rate, and the classes of car drain differently (G365). 0628
learns the drain in levels, the charge clock's own: each class of car, shrunk toward the depot's, and each model within
it, shrunk toward its class's, each with its own spread. A fit through a past moment reads only the runs that had ended
by then (G367). The self-review reports the arrivals by class, and splits each tail by its own dispatches, so that a
late tail carried by the drive home is named as such (G368). Every claim in its header that a test can execute is
executed here, on the scratch PostgreSQL and the miniature depot of tests/test_agent_charge_order_sql.py, through
0619-0627 as tests/test_agent_recall_rule_sql.py applies them:
  - it applies, its checks run, its dial is a person's, and it refuses a body it was not written against;
  - the drain a car is forecast at: its model's level within its class, else its class's, else the depot's;
  - the fit learns each class's drain and each model's within it, shrunk by n / (n + 20) with the robust spread, none
    under 10 returns, and every key 0627 computed is as it was;
  - a fit through a past moment reads only the runs that had ended by then; a fit through now() reads what it read;
  - a car at work is forecast at its own level's drain and spread; with the dial at 0, 0627's forecast exactly;
  - the state carries a car's own drain, the outflow sends each car out at its own, and with the dial at 0 both are
    0627's exactly;
  - the simulator gives back an early-called car's charge at its own drain and works an outflow car down at its own;
    without them, 0627's schedule on random lines;
  - the self-review reports the arrivals by class, names a class that runs one way, and marks it built, open, or
    open within the class; it splits each tail by the drive home, names the drive or the battery, and never leaves an
    area without an action;
  - V1-V4 on d9d49732 in miniature: the fit through its start reads only the runs ended by then, the gate passes on a
    world the class drain describes and holds back on one it does not.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import math
import os
import random
import re
import sys
import uuid
from datetime import datetime, timedelta, timezone
from statistics import NormalDist

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622 and their helpers)
import test_agent_outflow_sql as out  # noqa: E402  (0623 and its helpers)
import test_agent_self_review_sql as sr  # noqa: E402  (0626 and its helpers)
import test_agent_recall_rule_sql as rr  # noqa: E402  (0627 and its helpers)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0628 = os.path.join(ROOT, "db", "migrations", "0628_the_futures_drain_each_car_at_its_own_rate.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
GATE = rr.GATE
EVID = "e1000000-0000-0000-0000-000000000628"                    # a run ended before the gate run began
LATE = "e2000000-0000-0000-0000-000000000628"                    # a run under way when it began, ended after
_vid, _dial, _file, _j, _n, _q = base._vid, base._dial, arb._file, out._j, out._n, rr._q
ND = NormalDist()

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

CLS_NOTE = (" These orders were made before the futures drained each car at its own class's rate, so this is history "
            "until new orders are graded.")
CLS_ACT = ("Grade the next armed run's orders: the futures now drain each car at its own class's rate, and its model's "
           "within the class.")


def _apply(d):
    return _file(d, M0628)


def _through_0628(d):
    rr._through_0627(d)
    return _apply(d)


# ── the levels, as the fit computes them ──────────────────────────────────────────────────────────────────────────────

def _med(xs):
    xs = sorted(xs)
    n = len(xs)
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2


def _mad(xs, m):
    return 1.4826 * _med([abs(x - m) for x in xs])


def _levels(rows, k=20, floor=10):
    """drain_by from [(cls, mdl, log drain)], every reserve return (cls None: a car with no vehicle row, the depot's
    only)."""
    lds = [ld for _, _, ld in rows]
    dm = _med(lds)
    ds = _mad(lds, dm)
    by = {}
    for c in sorted({c for c, _, _ in rows if c is not None}):
        cl = [ld for cc, _, ld in rows if cc == c]
        if len(cl) < floor:
            continue
        n = len(cl)
        m, s, w = _med(cl), None, n / (n + k)
        s = _mad(cl, m)
        cm, cs = dm + w * (m - dm), math.sqrt(w * s * s + (1 - w) * ds * ds)
        models = {}
        for mdl in sorted({mm for cc, mm, _ in rows if cc == c}):
            ml = [ld for cc, mm, ld in rows if cc == c and mm == mdl]
            if len(ml) < floor:
                continue
            n2 = len(ml)
            m2, w2 = _med(ml), n2 / (n2 + k)
            s2 = _mad(ml, m2)
            models[mdl] = {"drain": math.exp(cm + w2 * (m2 - cm)), "log_sd": math.sqrt(w2 * s2 * s2 + (1 - w2) * cs * cs),
                           "n": n2, "w": w2}
        by[c] = {"drain": math.exp(cm), "log_sd": cs, "n": n, "w": w, "models": models}
    return {"m": dm, "s": ds, "by": by}


def _close(got, want, tol=1.5e-4):
    """drain_by as the fit rounds it (4 places, w 3) against the levels computed here."""
    assert set(got) == set(want), (set(got), set(want))
    for c, w in want.items():
        g = got[c]
        assert g["n"] == w["n"] and abs(g["w"] - w["w"]) < 1.5e-3, (c, g, w)
        assert abs(g["drain"] - w["drain"]) < tol and abs(g["log_sd"] - w["log_sd"]) < tol, (c, g, w)
        assert set(g["models"]) == set(w["models"]), (c, g["models"], w["models"])
        for mdl, wm in w["models"].items():
            gm = g["models"][mdl]
            assert gm["n"] == wm["n"] and abs(gm["w"] - wm["w"]) < 1.5e-3, (mdl, gm, wm)
            assert abs(gm["drain"] - wm["drain"]) < tol and abs(gm["log_sd"] - wm["log_sd"]) < tol, (mdl, gm, wm)


def _no_ids(state):
    """A state without the estimate ids it read (a model refitted between two readings has a new id)."""
    s = rr._no_ids(state)
    if isinstance(s.get("recall"), dict):
        s["recall"].pop("return_model", None)
    return s


def _car_row(vid, name, cls, make, model, soc=60, state="deployed"):
    cls_sql = "NULL" if cls is None else f"'{cls}'"
    return (f"('{vid}', '{base.OPERATOR}', '{DEPOT}', 'autonomous', '{name}', {soc}, 75, 'NACS', 250, '{state}', '{T}', "
            f"{cls_sql}, '{make}', '{model}')")


CAR_COLS = ("INSERT INTO public.vehicles (id, fleet_operator_id, home_depot_id, category, display_name, current_soc, "
            "battery_capacity_kwh, inlet_type, inlet_max_kw, current_state, last_state_change, vehicle_class_code, make, "
            "model) VALUES ")


def _fleet_returns(d, spec, run=RUN, created="now()", tag="f"):
    """Reserve returns by cars of known class, make and model. spec: [(cls, make, model, [log drain, ...])], one car per
    drain, each worked 60 minutes down from 98% at that drain and driving home 2 minutes. Returns [(cls, mdl, ld)] with
    ld as the fit reads it (from the recorded battery at the decision, to the microsecond of a percent)."""
    cars, disp, rows = [], [], []
    for cls, make, model, lds in spec:
        for i, ld in enumerate(lds):
            vid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0628-{tag}-{cls}-{make}-{model}-{i}"))
            cars.append(_car_row(vid, f"{tag}{i}", cls, make, model))
            soc_dec = round(98 - 60 * math.exp(ld), 6)
            disp.append(f"""('{vid}', '{run}', '{T}'::timestamptz, '{T}'::timestamptz + interval '62 minutes', 30, 98,
                            '{T}'::timestamptz + interval '60 minutes', '{T}'::timestamptz + interval '62 minutes',
                            'low_soc_reserve', '{{"soc_at_decision": {soc_dec:.6f}}}'::jsonb, 'returned', {created})""")
            rows.append((cls, f"{cls}/{make} {model}", math.log((98 - soc_dec) / 60)))
    d.val(CAR_COLS + ", ".join(cars))
    d.val("""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                          planned_duration_min, soc_at_dispatch_pct, returning_started_at,
                                                          actual_return_at, return_trigger, return_evidence, status,
                                                          created_at) VALUES """ + ", ".join(disp))
    return rows


def _spread(center, n, step):
    """n log drains about ln(center): -2, -1, 0, 1, 2 steps, in turn."""
    return [math.log(center) + step * ((i % 5) - 2) for i in range(n)]


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0628_applies_and_its_checks_run(db):
    err = _through_0628(db)
    assert "0628 V1: 0 stored simulations and comparisons (0 snapshots x 2 futures) unchanged" in err, err
    assert "0628 V1: the fit through now() keeps 0627's 22 keys and adds the drains by class: none" in err, err
    assert "0628 V1: run d9d49732 is not here; the fit through its start is executed by the tests" in err, err
    assert "0628 V2: run d9d49732 is not here; the gate is executed by the tests" in err, err
    assert re.search(r"0628 V3: return_v1 estimate \d+ \(usable false\): the depot's drain null \(spread null\), by "
                     r"class: none", err), err
    assert re.search(r"0628 V3 on running run a0000000-0000-0000-0000-000000000614: state \d+ ms, forecast cars with their "
                     r"own drain 0 of 0, outflow cars with theirs 0 of 0", err), err
    assert re.search(r"0628 V4: the review in \d+ ms, 0 areas \(0 open\); arrivals 0 \(0 returns\)", err), err
    dial = db.json("""SELECT jsonb_build_array(min_value, max_value, default_value, agent_writable)
                        FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_drain_by_class'""")
    assert dial == [0, 1, 1, False], dial
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0628_%'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0628_pre'") == "6"
    priv = db.json("""SELECT jsonb_agg(has_function_privilege(r, 'public.ottoq_return_car_drain(jsonb,jsonb)', 'EXECUTE')
                                       ORDER BY r)
                        FROM unnest(ARRAY['anon', 'authenticated', 'service_role']) r""")
    assert priv == [True, True, True], priv


def test_0628_refuses_a_body_it_was_not_written_against(db):
    rr._through_0627(db)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_charge_line_inbound(p_sim_run_id uuid, p_depot_id uuid,
                p_clock timestamptz, p_window_min numeric DEFAULT 180, p_return_model jsonb DEFAULT NULL)
              RETURNS TABLE(vehicle_id uuid, eta_min numeric, soc_at_arrival numeric, source text, eta_log_sd numeric,
                            trip_min numeric)
              LANGUAGE sql STABLE AS $f$ SELECT NULL::uuid, 0::numeric, 0::numeric, ''::text, 0::numeric, 0::numeric
                                        WHERE false $f$""")
    rc, err = db.file(M0628)
    assert rc != 0 and "0628 P1" in err and "the inbound forecast (0627)" in err, err


def test_0628_refuses_what_it_would_create_already_there(db):
    rr._through_0627(db)
    db.val("""INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable,
                                                             affects, description)
              VALUES ('agent_charge_order_drain_by_class', 0, 1, 1, false, 'x', 'x')""")
    rc, err = db.file(M0628)
    assert rc != 0 and "0628 P1: something this file creates already exists" in err, err


# ── the drain a car is forecast at ────────────────────────────────────────────────────────────────────────────────────

def test_0628_a_cars_drain_is_its_models_then_its_classs_then_the_depots(db):
    _through_0628(db)
    rt = {"usable": True, "params": {"drain_pct_per_min": 0.7, "drain_log_sd": 0.09, "drain_by": {
        "c1": {"drain": 0.75, "log_sd": 0.05, "n": 40, "w": 0.667,
               "models": {"c1/M A": {"drain": 0.76, "log_sd": 0.04, "n": 20, "w": 0.5},
                          "c1/M S": {"drain": 0.74, "n": 12, "w": 0.375}}},
        "c2": {"drain": 0.6, "n": 30, "w": 0.6, "models": {}}}}}

    def drain(est, cls, mdl):
        who = None if cls is None else {"cls": cls, "mdl": mdl, "veh": "x"}
        return _q(db, f"SELECT public.ottoq_return_car_drain({_j(est)}, {_j(who)})")

    assert drain(rt, "c1", "c1/M A") == {"dr": 0.76, "dsd": 0.04, "lvl": "model"}
    assert drain(rt, "c1", "c1/M S") == {"dr": 0.74, "dsd": 0, "lvl": "model"}        # a level with no spread: none
    assert drain(rt, "c1", "c1/M B") == {"dr": 0.75, "dsd": 0.05, "lvl": "class"}     # a model the fit has no level for
    assert drain(rt, "c2", "c2/X") == {"dr": 0.6, "dsd": 0, "lvl": "class"}
    assert drain(rt, "c3", "c3/X") == {"dr": 0.7, "dsd": 0.09, "lvl": "depot"}        # a class the fit has no level for
    assert drain(rt, None, None) == {"dr": 0.7, "dsd": 0.09, "lvl": "depot"}
    p = rt["params"]
    for params in ({k: v for k, v in p.items() if k != "drain_by"}, dict(p, drain_by=None), dict(p, drain_by=[1])):
        assert drain({"params": params}, "c1", "c1/M A") == {"dr": 0.7, "dsd": 0.09, "lvl": "depot"}, params
    assert drain({"params": {}}, "c1", "c1/M A") == {"dr": None, "dsd": 0, "lvl": "depot"}
    assert drain(None, "c1", "c1/M A") == {"dr": None, "dsd": 0, "lvl": "depot"}
    # a level whose drain is not a number is not a level
    bad = dict(p, drain_by={"c1": {"drain": "0.75", "models": {"c1/M A": {"drain": None}}}})
    assert drain({"params": bad}, "c1", "c1/M A") == {"dr": 0.7, "dsd": 0.09, "lvl": "depot"}


# ── the fit ───────────────────────────────────────────────────────────────────────────────────────────────────────────

FIT = f"SELECT public.ottoq_return_model_params('{DEPOT}', NULL, interval '21 days')"


def test_0628_the_fit_learns_each_class_and_model_shrunk_and_keeps_every_key_0627_computed(db):
    rr._through_0627(db)
    rows = _fleet_returns(db, [("cls_a", "Acme", "One", _spread(0.6, 15, 0.02)),
                               ("cls_a", "Acme", "Two", _spread(0.66, 12, 0.03)),
                               ("cls_b", "Bee", "Big", _spread(0.8, 20, 0.025)),
                               ("cls_c", "Cee", "Small", _spread(0.5, 6, 0.01))])          # under 10: no level
    arb._returns(db, 8)                         # 8 returns of cars the depot has no row for: the depot's level only
    rows += [(None, None, math.log((98 - 50) / 70))] * 8
    before = db.json(FIT)
    _apply(db)
    after = db.json(FIT)
    assert set(after) - set(before) == {"drain_by"} and {k: after[k] for k in before} == before, set(after) ^ set(before)
    want = _levels(rows)
    _close(after["drain_by"], want["by"])
    # the depot's own drain is its 0627 key, unmoved: the levels are shrunk toward it
    assert abs(after["drain_pct_per_min"] - round(math.exp(want["m"]), 4)) < 1.5e-4, (after["drain_pct_per_min"], want)
    assert abs(after["drain_log_sd"] - round(want["s"], 4)) < 1.5e-4, (after["drain_log_sd"], want)
    a = after["drain_by"]["cls_a"]
    # each level sits between its own median and its parent's: the class between its own and the depot's, the model
    # between its own and its class's
    own_a = math.exp(_med([ld for c, _, ld in rows if c == "cls_a"]))
    own_two = math.exp(_med([ld for _, m, ld in rows if m == "cls_a/Acme Two"]))
    assert min(own_a, math.exp(want["m"])) < a["drain"] < max(own_a, math.exp(want["m"])), (a, own_a, want["m"])
    two = a["models"]["cls_a/Acme Two"]["drain"]
    assert min(own_two, a["drain"]) < two < max(own_two, a["drain"]), (two, own_two, a)
    assert set(after["drain_by"]) == {"cls_a", "cls_b"}, after["drain_by"]
    # the nightly fit writes it
    db.val(f"SELECT public.ottoq_fit_return_model('{DEPOT}', NULL, interval '21 days', 'test')")
    est = db.json(f"SELECT public.ottoq_learned_estimate('{DEPOT}', 'return_v1')")
    assert est["usable"] and est["params"]["drain_by"] == after["drain_by"], est
    # with no class of 10 returns, a JSON null
    db.val("DELETE FROM public.ottoq_vehicle_dispatches WHERE vehicle_id IN (SELECT id FROM public.vehicles "
           "WHERE vehicle_class_code IN ('cls_a', 'cls_b'))")
    assert db.json(FIT)["drain_by"] is None


def test_0628_a_fit_through_a_past_moment_reads_only_the_runs_ended_by_then(db):
    rr._through_0627(db)
    db.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_current, started_at,
                                                  ended_at, run_by, policy)
               VALUES ('{EVID}', '{DEPOT}', 'completed', 100, '{T}', now() - interval '3 days', now() - interval '2 days',
                       'operator_demo', 'otto_q'),
                      ('{LATE}', '{DEPOT}', 'completed', 100, '{T}', now() - interval '1 day',
                       now() - interval '2 hours', 'operator_demo', 'otto_q')""")
    _fleet_returns(db, [("cls_a", "Acme", "One", _spread(0.6, 30, 0.02))], run=EVID,
                   created="now() - interval '60 hours'", tag="e")
    # LATE's first dispatches carry its start to the microsecond, and their returns came after it (G367)
    _fleet_returns(db, [("cls_a", "Acme", "One", _spread(0.9, 12, 0.02))], run=LATE,
                   created="now() - interval '1 day'", tag="l")
    cut = "now() - interval '1 day'"
    past = f"SELECT public.ottoq_return_model_params('{DEPOT}', {cut}, interval '21 days')"
    now_ = f"SELECT public.ottoq_return_model_params('{DEPOT}', now(), interval '21 days')"
    b_past, b_now, b_null = db.json(past), db.json(now_), db.json(FIT)
    assert b_past["n_returns_all_ticks"] == 42 and b_now["n_returns_all_ticks"] == 42, (b_past, b_now)
    _apply(db)
    a_past, a_now, a_null = db.json(past), db.json(now_), db.json(FIT)
    assert a_past["n_returns_all_ticks"] == 30 and a_past["n_drain"] == 30, a_past
    assert abs(a_past["drain_pct_per_min"] - 0.6) < 1e-4 and a_past["drain_by"]["cls_a"]["n"] == 30, a_past
    # through now(), or through nothing: what 0627 read, and the drains by class beside it
    for b, a in ((b_now, a_now), (b_null, a_null)):
        assert {k: a[k] for k in b} == b and a["drain_by"]["cls_a"]["n"] == 42, a


# ── a car at work ─────────────────────────────────────────────────────────────────────────────────────────────────────

BY = {"cls_a": {"drain": 0.4, "log_sd": 0.05, "n": 40, "w": 0.667,
                "models": {"cls_a/Acme One": {"drain": 0.42, "log_sd": 0.04, "n": 20, "w": 0.5}}},
      "cls_b": {"drain": 0.7, "log_sd": 0.06, "n": 30, "w": 0.6, "models": {}}}
KEYS = {"W": ("cls_a", "Acme", "One"), "V": ("cls_a", "Acme", "Two"), "U": ("cls_b", "Bee", "Big"),
        "H": ("cls_b", "Bee", "Big")}


def _classes(d, keys=KEYS):
    for name, (cls, make, model) in keys.items():
        d.val(f"""UPDATE public.vehicles SET vehicle_class_code = '{cls}', make = '{make}', model = '{model}'
                   WHERE id = '{_vid(name)}'""")


def _fc(hz, dr, dsd, rung, soc, asd=0.5, trip=2):
    """The forecast of a car at work: home after its time to the rung and the drive, at the rung less the drive."""
    return (round(hz + trip, 2), round(min(soc, rung) - dr * trip, 1), round(math.sqrt(dsd ** 2 + (asd / max(hz, 0.25)) ** 2), 4))


def test_0628_a_car_at_work_is_forecast_at_its_own_levels_drain_and_spread(db):
    rr._through_0627(db)
    rr._working(db, [("W", 70, None), ("V", 70, 15), ("U", 36, None), ("Z", 30, None)])
    _classes(db)
    params = dict(rr.RT, drain_by=BY)
    before = rr._inbound(db, params)                                 # 0627 reads no drain_by: the depot's drain
    _apply(db)
    got = rr._inbound(db, params)
    want = {"W": _fc((70 - 35) / 0.42, 0.42, 0.04, 35, 70),           # its model's level
            "V": _fc((70 - 30) / 0.4, 0.4, 0.05, 30, 70),             # its class's: the fit has no level for its model
            "U": _fc((36 - 35) / 0.7, 0.7, 0.06, 35, 36),             # its class's
            "Z": _fc(0, 0.5, 0.1, 35, 30)}                            # no class: the depot's, 0627's forecast
    for name, (eta, soc, sd) in want.items():
        e, s, x, src = got[name]
        assert src == "forecast" and abs(e - eta) < 0.006 and abs(s - soc) < 0.06 and abs(x - sd) < 6e-5, \
            (name, got[name], want[name])
    assert got["Z"] == before["Z"], (got["Z"], before["Z"])
    # driving home: its battery falls at its own class's rate on the way in (6 minutes at 0.7)
    assert got["H"][0] == 6 and abs(got["H"][1] - 25.8) < 0.06 and got["H"][3] == "returning", got["H"]
    assert before["H"] == (6, 27, 0, "returning"), before["H"]
    # a model the depot's cars drain slower than the depot carries them home later; one that drains faster, sooner
    assert got["W"][0] > before["W"][0] and got["U"][0] < before["U"][0] + 1e-9, (got, before)
    # the run's dial at 0: 0627's forecast exactly
    _dial(db, "agent_charge_order_drain_by_class", 0)
    assert rr._inbound(db, params) == before


# ── the state, the outflow and the simulator ──────────────────────────────────────────────────────────────────────────

def test_0628_the_state_carries_each_cars_own_drain_and_the_dial_restores_0627s(db):
    rr._through_0627(db)
    rr._working(db, [("W", 70, None), ("V", 70, 15), ("U", 36, None), ("Z", 30, None)])
    _classes(db)
    out._return_model(db, dwell=None, **dict(rr.RT, drain_by=BY))
    before = arb._state(db)
    _apply(db)
    out._return_model(db, dwell=None, **dict(rr.RT, drain_by=BY))    # the fit at apply wrote one of its own: this is latest
    s = arb._state(db)
    inb = {base.NAMES[c["id"]]: c for c in s["inbound"]}
    assert {n: inb[n].get("dr") for n in inb} == {"W": 0.42, "V": 0.4, "U": 0.7, "Z": None, "H": None}, inb
    assert abs(inb["W"]["eta"] - round(35 / 0.42 + 2, 2)) < 0.006, inb["W"]
    assert s["recall"]["drain"] == 0.5, s["recall"]                  # the block keeps the depot's drain beside them
    _dial(db, "agent_charge_order_drain_by_class", 0)
    s0 = arb._state(db)
    assert not any("dr" in c for c in s0["inbound"]) and _no_ids(s0) == _no_ids(before)


def test_0628_the_outflow_sends_each_car_out_at_its_own_drain(db):
    rr._through_0627(db)
    out._parked_and_charging(db)                                  # L charged and parked; Y charging on an L2
    _classes(db, {"L": ("cls_a", "Acme", "One")})
    out._return_model(db, trip_other_min=4, drain_by=BY)
    before = arb._state(db)
    _apply(db)
    out._return_model(db, trip_other_min=4, drain_by=BY)
    o = arb._state(db)["outflow"]
    rl, ry = o["ret"][_vid("L")], o["ret"][_vid("Y")]
    # L at its model's 0.42 and 0.04, back at its rung of 35 less its own drain over the drive; Y has no class
    assert (rl["dr"], rl["dsd"], rl["rs"]) == (0.42, 0.04, 34.16), rl
    assert "dr" not in ry and ry["rs"] == 34, ry
    # it drains slower than the depot's 0.5, so it comes back with more charge and owes less
    assert rl["rmd"] <= before["outflow"]["ret"][_vid("L")]["rmd"], (rl, before["outflow"]["ret"][_vid("L")])
    assert o["drain"] == 0.5 and o["dsd"] == 0.2, o                # the depot's beside them
    _dial(db, "agent_charge_order_drain_by_class", 0)
    s0 = arb._state(db)
    assert not any("dr" in r for r in s0["outflow"]["ret"].values()) and _no_ids(s0) == _no_ids(before)


def test_0628_an_early_call_gives_back_what_the_car_did_not_use_at_its_own_drain(db):
    _through_0628(db)
    rc = {"v": 1, "lam": 0.02, "trip_o": 3, "drain": 0.5}
    st = rr._one_coming_home(rc)
    st["inbound"][0]["dr"] = 0.25
    draws = db.json("""SELECT jsonb_agg(jsonb_build_array(public.ottoq_hash_normal('s:' || k || ':w:arrival'),
                                                          public.ottoq_hash_uniform('s:' || k || ':w:early')) ORDER BY k)
                         FROM generate_series(1, 30) k""")
    early = 0
    for k, (z, u) in enumerate(draws, 1):
        reserve = 2 + 58 * math.exp(0.1 * z)
        te = -math.log(1 - min(u, 0.999999)) / 0.02 + 3
        seat = rr._seat(db, st, k)
        if te < reserve:
            early += 1
            md = 33 * max(66 - 0.25 * max(60 - te, 0), 1) / 66      # it worked less, at its own 0.25 a minute
            assert abs(seat["r"] - seat["s0"] - md) < 0.011, (k, seat, md)
        # and without its own drain, 0627's: the recall block's
        s2 = rr._seat(db, rr._one_coming_home(rc), k)
        if te < reserve:
            assert abs(s2["r"] - s2["s0"] - 33 * max(66 - 0.5 * max(60 - te, 0), 1) / 66) < 0.011, (k, s2)
        else:
            assert s2 == seat, (k, s2, seat)
    assert 0 < early < 30, early
    assert rr._seat(db, st, 0) == rr._seat(db, rr._one_coming_home(rc), 0)  # the expected future: no early call


def test_0628_a_car_the_outflow_sends_out_works_down_at_its_own_drain(db):
    _through_0628(db)
    s = out._out_state()
    plain = {x["id"]: x for x in arb._sched(db, s)["return_seats"]}
    assert (plain["l"]["dep"], plain["l"]["a"], plain["l"]["soc"]) == (0, 102, 49), plain["l"]
    # L drains at 0.25: it works from 100% down to its reserve of 50 in 200 minutes, drives 2, and is back at 49.5%
    s["outflow"]["ret"]["l"] = dict(out.RET, dr=0.25, dsd=0)
    own = {x["id"]: x for x in arb._sched(db, s)["return_seats"]}
    assert (own["l"]["dep"], own["l"]["a"], own["l"]["soc"]) == (0, 202, 49.5), own["l"]
    assert all((own[c]["dep"], own[c]["a"], own[c]["soc"]) == (plain[c]["dep"], plain[c]["a"], plain[c]["soc"])
               for c in ("y", "a")), (own, plain)
    # its own spread moves a sampled future and not the expected one
    s["outflow"]["ret"]["l"] = dict(out.RET, dr=0.5, dsd=0.4)
    wide = {x["id"]: x for x in arb._sched(db, s)["return_seats"]}
    assert wide["l"] == plain["l"], (wide["l"], plain["l"])
    moved = sum(db.json(f"""SELECT public.ottoq_charge_line_schedule({_j(s)}, NULL, {k}, 's', true) -> 'return_seats'""")
                != db.json(f"""SELECT public.ottoq_charge_line_schedule({_j(out._out_state())}, NULL, {k}, 's', true)
                               -> 'return_seats'""") for k in range(1, 9))
    assert moved >= 4, moved


def test_0628_without_a_cars_own_drain_the_schedule_is_0627s_on_random_lines(db):
    rng = random.Random(628)
    cases = []
    for i in range(60):
        st, o = arb._rand_case(rng, i)
        ids = [c["id"] for c in st["cars"]] + [c["id"] for c in st["inbound"]]
        ret = {cid: dict(out.RET, rs=rng.choice([40, 49]), rmd=rng.randint(15, 45), rml=rng.randint(60, 240),
                         thr=rng.choice([35, 50])) for cid in ids}
        st["outflow"] = {"v": 1, "window_min": 90, "thr": 50, "drain": rng.choice([0.4, 0.7]), "dsd": rng.choice([0, 0.1]),
                         "trip": 1.5, "lam": rng.choice([0, 0.02]), "trip_o": 3,
                         "dwell": {"q": out.Q, "f_max": out.FMAX, "max_min": out.MAX, "median_min": 7.28},
                         "ret": ret, "leaving": []}
        if rng.random() < 0.6:
            st["recall"] = {"v": 1, "lam": rng.choice([0.01, 0.03]), "trip_o": 2, "drain": 0.5}
        cases.append((st, o))
    rr._through_0627(db)
    db.val("CREATE TABLE public.t0628 (i int, sc int, state jsonb, ord jsonb, k jsonb)")
    rr._run_sql(db, ["INSERT INTO public.t0628 VALUES " + ", ".join(
        f"({i}, {sc}, $j${json.dumps(st)}$j$::jsonb, {_j(o)}, NULL)" for i, (st, o) in enumerate(cases) for sc in (0, 1, 2))
        + ";"])
    db.val("UPDATE public.t0628 SET k = public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true)")
    _apply(db)
    bad = db.json("""SELECT COALESCE(jsonb_agg(jsonb_build_object('i', i, 'sc', sc)), '[]'::jsonb) FROM public.t0628
                      WHERE k IS DISTINCT FROM public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true)""")
    assert bad == [], bad[:5]
    n = db.json("""SELECT jsonb_build_array(count(*), count(*) FILTER (WHERE jsonb_array_length(k -> 'return_seats') > 0))
                     FROM public.t0628""")
    assert n[0] == 180 and n[1] > 60, n                           # the outflow is exercised
    # each car carrying its own drain: the outflow moves, in the expected future and the sampled ones
    db.val("""UPDATE public.t0628 SET state = jsonb_set(state, '{outflow,ret}',
                (SELECT jsonb_object_agg(r.key, r.value || '{"dr": 0.25, "dsd": 0}') FROM jsonb_each(state #> '{outflow,ret}') r))
              WHERE jsonb_typeof(state #> '{outflow,ret}') = 'object' AND state #> '{outflow,ret}' <> '{}'""")
    moved = db.val("""SELECT count(*) FROM public.t0628
                       WHERE k IS DISTINCT FROM public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true)""")
    assert int(moved) >= n[1] // 2, (moved, n)


# ── the self-review ───────────────────────────────────────────────────────────────────────────────────────────────────

def _by_class_orders(d, oid0, carried=False):
    """12 orders of 26 arrivals: 300 forecast home at the normal quantiles of their spread (class cls_y), and 12 cars of
    class cls_x each home 3 minutes after its forecast, well inside it."""
    inb, real = sr._arrivals(300, 0, 0)
    for e in inb:
        e["cls"] = "cls_y"
    for i in range(12):
        cid = f"x-{i}"
        inb.append({"id": cid, "src": "forecast", "eta": 42, "trip": 2, "esd": 0.1, "cls": "cls_x"})
        real[cid] = {"arrived": True, "eta": 45}
    if carried:
        for e in inb:
            e["dr"] = 0.5
    for k in range(12):
        sr._graded(d, oid0 + k, inbound=inb[26 * k:26 * (k + 1)], real_inbound=real)


def test_0628_the_review_reports_each_classs_arrivals_and_names_one_that_runs_one_way(db):
    _through_0628(db)
    _by_class_orders(db, 9600)
    r = sr._review(db)
    t = r["arrival_tails"]
    assert (t["n"], t["returns"], t["below_band"], t["above_band"]) == (312, 312, 0.096, 0.096), t
    bx, by = t["by_class"]["cls_x"], t["by_class"]["cls_y"]
    assert (bx["n"], bx["returns"], bx["mean_minutes"], bx["returns_late"], bx["returns_early"]) == (12, 12, 3, 12, 0), bx
    assert by["returns"] == 300 and abs(by["mean_minutes"]) < 1, by
    a = sr._areas(r)["arrival_by_class"]
    sr._plain(a)
    assert (a["kind"], a["part"], a["status"], a["title"]) == \
        ("capability_gap", "arrivals", "open", "cls x cars come home later than it forecasts"), a
    assert a["finding"] == ("cls x cars came home a mean 3.00 minutes after their forecast (12 of 12 returns). "
                            "The futures drained every car at the depot's one rate."), a["finding"]
    assert a["action"] == "Learn the drain per class of car, pooled toward the depot's, and forecast each car at its own."
    assert "arrival_spread" not in sr._areas(r)                   # the bulk is the futures' own: no tails
    # once the fit has a drain by class, these orders are history
    out._return_model(db, dwell=None, drain_by=BY)
    b = sr._areas(sr._review(db))["arrival_by_class"]
    assert b["status"] == "built" and b["finding"].endswith(CLS_NOTE) and b["action"] == CLS_ACT, b


def test_0628_the_review_looks_within_the_class_once_the_orders_carried_its_drain(db):
    _through_0628(db)
    out._return_model(db, dwell=None, drain_by=BY)
    _by_class_orders(db, 9700, carried=True)
    a = sr._areas(sr._review(db))["arrival_by_class"]
    sr._plain(a)
    assert a["status"] == "open" and a["action"] == \
        "Look within the class: give the drain a level for what the class does not explain.", a
    assert a["finding"].endswith("The futures already drain each car at its own class's rate, so something within the "
                                 "class moves it: its model, the day's air, or the car itself."), a["finding"]


def _late_tail_orders(d, drive=None, ids="car"):
    """12 orders carrying the other calls home (so their arrivals are not history): 300 arrivals at the normal quantiles
    of their spread, and 6 cars 8 spreads late. drive: the late ones' drive home in minutes, from their dispatches (None:
    no dispatch to read)."""
    inb, real = sr._arrivals(300, 0, 0)
    late = []
    for i in range(6):
        cid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0628-late-{i}")) if ids == "car" else f"late-{i}"
        act = round(2 + 40 * math.exp(0.8), 4)
        inb.append({"id": cid, "src": "forecast", "eta": 42, "trip": 2, "esd": 0.1})
        real[cid] = {"arrived": True, "eta": act}
        late.append((cid, act))
    if drive is not None:
        d.val("""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                              planned_duration_min, returning_started_at, actual_return_at,
                                                              return_trigger, status) VALUES """
              + ", ".join(f"""('{cid}', '{RUN}', '{T}'::timestamptz - interval '60 minutes', '{T}', 30,
                               '{T}'::timestamptz + make_interval(secs => {(act - drive) * 60}),
                               '{T}'::timestamptz + make_interval(secs => {act * 60}), 'low_soc_reserve', 'returned')"""
                          for cid, act in late))
    st = {"ttl_min": 3, "pin_min": 90, "horizon_min": 480, "cars": [], "chargers": [],
          "recall": {"v": 1, "lam": 0, "trip_o": 2, "drain": 0.5, "asd": 0}}
    rr._run_sql(d, [rr._graded(d, 9800 + k, dict(st, inbound=inb[k::12]), real) for k in range(12)])


def test_0628_the_review_names_the_drive_home_when_it_carries_the_late_tail(db):
    _through_0628(db)
    _late_tail_orders(db, drive=42)                                # 40 minutes longer than the forecast's 2
    r = sr._review(db)
    lt = r["arrival_tails"]["late"]
    assert (lt["n"], lt["returns"], lt["with_drive"], lt["mean_drive_minutes"], lt["mean_minutes"]) == \
        (6, 6, 6, 40, 49), lt
    a = sr._areas(r)["arrival_spread"]
    sr._plain(a)
    assert (a["kind"], a["status"], a["title"]) == \
        ("capability_gap", "open", "A few cars take far longer to drive home than its futures sample"), a
    assert "The late ones are 6 returns." in a["finding"] and a["finding"].endswith(
        " Their drive home took a mean 40.0 minutes longer than the depot's typical drive, which the futures give every "
        "car."), a["finding"]
    assert a["action"] == "Forecast each car's drive home from where it is, not the depot's typical drive.", a


def test_0628_the_review_names_the_battery_when_the_drive_was_as_forecast(db):
    _through_0628(db)
    _late_tail_orders(db, drive=2)
    a = sr._areas(sr._review(db))["arrival_spread"]
    sr._plain(a)
    assert a["title"] == "A few cars come home far from their forecast", a
    assert a["finding"].endswith(" Their drive home was as forecast; their battery lasted longer than its forecast."), a
    assert a["action"] == "Find what slows the late ones' drain: a level the drain does not have yet.", a


def test_0628_no_area_of_the_review_is_left_without_an_action(db):
    _through_0628(db)
    _late_tail_orders(db, ids="name")                              # nothing to split the late ones by
    r = sr._review(db)
    assert r["arrival_tails"]["late"]["with_drive"] == 0, r["arrival_tails"]["late"]
    a = sr._areas(r)["arrival_spread"]
    assert a["action"] == "Find what the cars that came home far from their forecast share.", a
    assert all(x["action"].strip(" .") for x in r["improvement_areas"]), r["improvement_areas"]


# ── V1-V4 on d9d49732 in miniature ────────────────────────────────────────────────────────────────────────────────────

V2 = re.compile(r"0628 V2: (\d+) forecast arrivals, (\d+) returns \((\d+) due at the order\): absolute error ([\d.]+) -> "
                r"([\d.]+) minutes, pinball ([\d.]+) -> ([\d.]+), inside the 80% band ([\d.]+) -> ([\d.]+), below it "
                r"([\d.]+) -> ([\d.]+), above it ([\d.]+) -> ([\d.]+); past 3 spreads late (\d+) -> (\d+) \((\d+) -> (\d+) "
                r"returns; their drive home a mean (\S+) minutes longer than the forecast's, the rest's (\S+)\), early (\d+) "
                r"-> (\d+); more than 5 minutes late (\d+) -> (\d+), early (\d+) -> (\d+); mean minutes off by class: (.*); "
                r"drained at: (.*)")


def _gate_world(d, follows="class", orders=10, per=12):
    """d9d49732 in miniature: the evidence run (ended before the gate run began: two classes of car, one model each,
    40 reserve returns apiece, drains about 0.4 and 0.6, drives of 2 minutes), a run under way when it began and ended
    after (12 returns the fit through its start must not read, G367), and the gate run's `orders` graded orders of `per`
    cars at work, with the recall decision's record of each car's battery. follows='class': each car came home as its
    model's drain forecasts it, at an even spread of quantiles; 'depot': as the depot's one drain forecasts it."""
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_current, started_at,
                                                 ended_at, run_by, policy)
              VALUES ('{EVID}', '{DEPOT}', 'completed', 100, '{T}', now() - interval '3 hours', now() - interval '2 hours',
                      'operator_demo', 'otto_q'),
                     ('{LATE}', '{DEPOT}', 'completed', 100, '{T}', now() - interval '4 hours',
                      now() - interval '10 minutes', 'operator_demo', 'otto_q'),
                     ('{GATE}', '{DEPOT}', 'completed', 100, '{T}', now() - interval '1 hour',
                      now() - interval '20 minutes', 'operator_demo', 'otto_q')""")
    rows = _fleet_returns(d, [("cls_a", "Acme", "One", _spread(0.4, 40, 0.03)),
                              ("cls_b", "Bee", "Big", _spread(0.6, 40, 0.03))], run=EVID,
                          created="now() - interval '150 minutes'", tag="g")
    d.val(f"""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                           planned_duration_min, soc_at_dispatch_pct, returning_started_at,
                                                           actual_return_at, return_trigger, return_evidence, status,
                                                           created_at)
              SELECT gen_random_uuid(), '{LATE}', '{T}', '{T}'::timestamptz + interval '62 minutes', 30, 98,
                     '{T}'::timestamptz + interval '60 minutes', '{T}'::timestamptz + interval '62 minutes',
                     'low_soc_reserve', '{{"soc_at_decision": 50}}', 'returned', now() - interval '90 minutes'
                FROM generate_series(1, 12)""")
    lv = _levels(rows)
    dr0, ds0 = round(math.exp(lv["m"]), 4), round(lv["s"], 4)
    cars = [(str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0628-g-{cls}-{make}-{model}-{i}")), f"{cls}/{make} {model}", cls)
            for cls, make, model in (("cls_a", "Acme", "One"), ("cls_b", "Bee", "Big")) for i in range(12)]
    perm = list(range(orders * per))
    random.Random(628).shuffle(perm)
    out_rows, sql = [], []
    t0 = datetime.fromisoformat(T.replace("+00", "+00:00"))
    for k in range(orders):
        inbound, real = [], {}
        for j in range(per):
            vid, mdl, cls = cars[(j // 2 + k) % 12] if j % 2 == 0 else cars[12 + (j // 2 + k) % 12]
            m = lv["by"][cls]["models"][mdl]
            dr1, ds1 = round(m["drain"], 4), round(m["log_sd"], 4)
            soc0 = 55 + (7 * k + 11 * j) % 30
            hz0, hz1 = (soc0 - 35) / dr0, (soc0 - 35) / dr1
            u = (perm[k * per + j] + 0.5) / (orders * per)
            act = 2 + (hz1 * math.exp(ds1 * ND.inv_cdf(u)) if follows == "class" else hz0 * math.exp(ds0 * ND.inv_cdf(u)))
            inbound.append({"id": vid, "src": "forecast", "eta": hz0 + 2, "trip": 2, "esd": 0.1, "soc": 33, "g": 67,
                            "imm": False, "w": 0, "md": 30, "ml": 150, "sd": 0, "sl": 0})
            real[vid] = {"arrived": True, "eta": act}
            at = t0 + timedelta(minutes=10 * k) + timedelta(seconds=act * 60 + 30)
            out_rows.append({"act": act, "hz0": hz0, "hz1": hz1, "sd0": ds0, "sd1": ds1, "cls": cls,
                             "ret": f"{vid}@{at.strftime('%Y-%m-%d %H:%M')}"})
            sql.append(f"""INSERT INTO public.ottoq_recall_decisions (sim_run_id, vehicle_id, depot_id, decided_at_sim,
                                                                      implementation, should_return, inputs, soc_override)
                           VALUES ('{GATE}', '{vid}', '{DEPOT}', '{T}'::timestamptz + interval '{10 * k - 1} minutes',
                                   'naive_threshold_v1', false, '{{"reserve": 20, "reserve_margin": 15}}', {soc0});""")
        state = {"ttl_min": 0, "pin_min": 90, "horizon_min": 480, "cars": [], "inbound": inbound,
                 "chargers": [{"id": "f", "k": "dcfc", "free": 0}]}
        sql.append(rr._graded(d, 9900 + k, state, real, run=GATE, at_min=10 * k))
    rr._run_sql(d, sql)
    return out_rows, rows


def _gate_expect(rows):
    """V2's numbers, computed here: each arrival on the depot's drain and on its model's."""
    n = len(rows)
    us = [x / 10 for x in range(1, 10)]

    def side(hz, sd):
        z = [math.log((r["act"] - 2) / r[hz]) / r[sd] for r in rows]
        mae = sum(abs(r["act"] - 2 - r[hz]) for r in rows) / n
        pin = sum((u * (r["act"] - q) if r["act"] >= q else (1 - u) * (q - r["act"]))
                  for r in rows for u in us
                  for q in [2 + r[hz] * math.exp(ND.inv_cdf(u) * r[sd])]) / (n * len(us))
        return {"mae": mae, "pin": pin, "band": sum(abs(x) <= 1.2816 for x in z) / n, "late": sum(x > 3 for x in z),
                "early": sum(x < -3 for x in z), "late_ret": len({r["ret"] for r, x in zip(rows, z) if x > 3}),
                "mlate": sum(r["act"] - 2 - r[hz] > 5 for r in rows), "mearly": sum(r["act"] - 2 - r[hz] < -5 for r in rows)}
    return {"n": n, "returns": len({r["ret"] for r in rows}), "old": side("hz0", "sd0"), "new": side("hz1", "sd1")}


def _check_v2(m, want):
    g = m.groups()
    assert (int(g[0]), int(g[1]), int(g[2])) == (want["n"], want["returns"], 0), (g[:3], want)
    o, nw = want["old"], want["new"]
    assert abs(float(g[3]) - o["mae"]) < 0.0015 and abs(float(g[4]) - nw["mae"]) < 0.0015, (g[3:5], o, nw)
    assert abs(float(g[5]) - o["pin"]) < 2e-4 and abs(float(g[6]) - nw["pin"]) < 2e-4, (g[5:7], o, nw)
    assert abs(float(g[7]) - o["band"]) < 0.0015 and abs(float(g[8]) - nw["band"]) < 0.0015, (g[7:9], o, nw)
    assert [int(x) for x in (g[13], g[14], g[15], g[16])] == [o["late"], nw["late"], o["late_ret"], nw["late_ret"]], g
    assert (g[17], g[18]) == ("unknown", "unknown"), g[17:19]     # the gate run's own dispatches are not here
    assert [int(x) for x in g[19:25]] == [o["early"], nw["early"], o["mlate"], nw["mlate"], o["mearly"], nw["mearly"]], g


def test_0628_v1_to_v4_on_d9d49732_in_miniature_the_gate_passes_on_a_world_the_class_drain_describes(db):
    rr._through_0627(db)
    rows, ev = _gate_world(db, "class")
    want = _gate_expect(rows)
    assert _q(db, f"SELECT public.ottoq_recall_threshold_soc('{_vid('X')}', '{GATE}', '{T}')") == 35
    err = _apply(db)
    assert "0628 V1: 20 stored simulations and comparisons (10 snapshots x 2 futures) unchanged" in err, err
    assert ("0628 V1: the fit through d9d49732's start reads the 80 returns of the runs ended by then, 12 fewer than "
            "before (the runs not ended: e2000000)") in err, err
    m = V2.search(err)
    assert m, err
    _check_v2(m, want)
    assert m.group(27) == "model 120", m.group(27)
    # the world the class drain describes: it misses by fewer minutes and sits inside its band as its spread says
    assert want["new"]["mae"] < want["old"]["mae"] and want["new"]["band"] == 0.8, want
    assert re.search(r"0628 V3: return_v1 estimate \d+ \(usable true\): the depot's drain [\d.]+ \(spread [\d.]+\), by "
                     r"class: cls_a [\d.]+ \(40 returns, spread [\d.]+; models Acme One [\d.]+ \(40\)\); cls_b [\d.]+ \(40 "
                     r"returns, spread [\d.]+; models Bee Big [\d.]+ \(40\)\)", err), err
    assert re.search(r"0628 V4: the review in \d+ ms, \d+ areas \(\d+ open\); arrivals 120 \(\d+ returns\)", err), err
    assert db.val("SELECT to_regprocedure('public.ottoq_return_car_drain(jsonb,jsonb)') IS NOT NULL") == "t"
    # the fit through the gate run's start learned what the gate used
    fit = db.json(f"""SELECT public.ottoq_return_model_params('{DEPOT}', (SELECT started_at FROM public.ottoq_sim_runs
                                                                           WHERE sim_run_id = '{GATE}'), interval '21 days')""")
    _close(fit["drain_by"], _levels(ev)["by"])


def test_0628_the_gate_holds_back_on_a_world_the_depots_one_drain_describes(db):
    rr._through_0627(db)
    rows, _ = _gate_world(db, "depot")
    want = _gate_expect(rows)
    rc, err = db.file(M0628)
    m = re.search(r"0628 V2: the gate holds back: error ([\d.]+) -> ([\d.]+), pinball ([\d.]+) -> ([\d.]+), band ([\d.]+)",
                  err)
    assert rc != 0 and m, err
    assert abs(float(m.group(1)) - want["old"]["mae"]) < 0.0015 and abs(float(m.group(2)) - want["new"]["mae"]) < 0.0015
    assert abs(float(m.group(3)) - want["old"]["pin"]) < 2e-4 and abs(float(m.group(4)) - want["new"]["pin"]) < 2e-4
    # cars that came home at the depot's one drain put each class's forecast minutes off: the error says so
    assert want["new"]["mae"] > want["old"]["mae"], want
    assert db.val("SELECT to_regprocedure('public.ottoq_return_car_drain(jsonb,jsonb)') IS NULL") == "t"
