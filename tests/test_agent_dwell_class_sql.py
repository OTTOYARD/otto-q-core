"""db/migrations/0624, EXECUTED: the check reads each car's open work.

WHY THIS EXISTS. 0623 gave the check's simulator the depot's own outflow, and timed every charged car's departure on
one curve over all of them. Behind that curve sit cars that leave at once and cars that wait for a bay, and the curve
scored each car's chance of leaving worse than the base rate (G356). 0624 reads what each car has left to do and gives
each kind its own learned curve on its own clock. Every claim in its header that a test can execute is executed here,
on the scratch PostgreSQL and the miniature depot of tests/test_agent_charge_order_sql.py, through 0619-0623 as
tests/test_agent_outflow_sql.py applies them:

  - it applies, its checks run, its dial is a person's, and it refuses a body it was not written against;
  - the class rule: boot without a visit, bay while a must-do service in a bay is open, clear otherwise;
  - the fit learns each class's curve with the parked cars censored, 'new' is the visit cars together, and every key
    0623 computed is as it was;
  - the state reads each car's class at the clock, starts a parked clear car's clock when its work was done, leaves out
    a class too thin to use, and the dial takes it all away;
  - the draw starts a car's dwell clock when its work was done, and without that is 0623's;
  - the schedule draws each car on its class's curve, spreads the draws within each class, and without classes is
    0623's, key for key, on random lines;
  - the grader grades each car on its class's curve with the pooled curve's score beside it, and without classes is
    0623's.

It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import random
import sys
import tempfile
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622 and their helpers)
import test_agent_outflow_sql as out  # noqa: E402  (0623 and its helpers)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0624 = os.path.join(ROOT, "db", "migrations", "0624_the_check_reads_each_cars_open_work.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_vid, _dial, _file, _j, _n = base._vid, base._dial, arb._file, out._j, out._n

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _apply(d):
    return _file(d, M0624)


def _through_0624(d):
    out._through_0623(d)
    return _apply(d)


def _ts(d, minutes):
    """T plus minutes, as the text a visit's atom carries."""
    return d.val(f"SELECT to_char(('{T}'::timestamptz + interval '{minutes} minutes') AT TIME ZONE 'UTC', "
                 f"'YYYY-MM-DD\"T\"HH24:MI:SS\"+00:00\"')")


def _visit(d, vid, arrived_min, atoms, run=RUN):
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, visit_key, status, urgency, target_soc,
                                                    atoms, arrived_at, created_at)
              VALUES ('{vid}', '{run}', '{DEPOT}', 'v{uuid.uuid4().hex[:6]}', 'open', 'standard', 100,
                      $j${json.dumps(atoms)}$j$::jsonb, '{T}'::timestamptz + interval '{arrived_min} minutes',
                      '{T}'::timestamptz + interval '{arrived_min} minutes')""")


def _bay(done=None, closed=None, must=True, svc="exterior_wash", conc="bay"):
    a = {"svc": svc, "must_do": must, "concurrency": conc, "est_min": 12}
    if done is not None:
        a["done_at"] = done
    if closed is not None:
        a["closed_at"] = closed
    return a


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0624_applies_and_its_checks_run(db):
    out._through_0623(db)
    md5_before = db.val("SELECT public.ottoq_hindsight_code_md5()")
    err = _apply(db)
    assert "0624 V1: 0 stored simulations and comparisons (0 snapshots x 2 futures) unchanged" in err, err
    assert "0624 V2: run d9d49732 is not here" in err, err
    assert "0624 V3: return_v1 estimate" in err, err
    assert "0624 V3 on running run a0000000-0000-0000-0000-000000000614" in err, err
    dial = db.json("""SELECT jsonb_build_array(min_value, max_value, default_value, agent_writable)
                        FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_dwell_class'""")
    assert dial == [0, 1, 1, False], dial
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0624_%'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0624_pre'") == "5"
    priv = db.json("""SELECT jsonb_build_object(
        'cls', has_function_privilege('anon', 'public.ottoq_dwell_class(jsonb,timestamptz)', 'EXECUTE'),
        'params', has_function_privilege('anon', 'public.ottoq_return_model_params(uuid,timestamptz,interval)', 'EXECUTE'),
        'outflow', has_function_privilege('authenticated',
                     'public.ottoq_charge_line_outflow(uuid,uuid,timestamptz,jsonb,jsonb,jsonb,jsonb)', 'EXECUTE'),
        'outflow_service', has_function_privilege('service_role',
                     'public.ottoq_charge_line_outflow(uuid,uuid,timestamptz,jsonb,jsonb,jsonb,jsonb)', 'EXECUTE'))""")
    assert priv == {"cls": True, "params": False, "outflow": False, "outflow_service": True}, priv
    # the grader's md5 covers the bodies that changed
    assert db.val("SELECT public.ottoq_hindsight_code_md5()") not in ("", md5_before)


def test_0624_refuses_an_outflow_it_was_not_written_against(db):
    out._through_0623(db)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_charge_line_outflow(p_sim_run_id uuid, p_depot_id uuid,
                p_clock timestamptz, p_state jsonb, p_ct jsonb, p_rt jsonb, p_ev jsonb)
              RETURNS jsonb LANGUAGE sql STABLE AS $f$ SELECT p_state $f$""")
    rc, err = db.file(M0624)
    assert rc != 0 and "0624 P1" in err and "the outflow" in err, err


# ── the class rule ────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0624_the_class_rule(db):
    _through_0624(db)

    def cls(atoms):
        return db.val(f"SELECT public.ottoq_dwell_class({_j(atoms)}, '{T}'::timestamptz)")
    before, after = _ts(db, -10), _ts(db, 10)
    assert cls(None) == "boot"                                            # no visit: in the depot since the run began
    assert cls([]) == "clear"
    assert cls([_bay()]) == "bay"                                         # a must-do wash still to do
    assert cls([_bay(done=after)]) == "bay"                               # done after the clock: open at it
    assert cls([_bay(done=before)]) == "clear"
    assert cls([_bay(closed=before)]) == "clear"                          # closed counts as finished
    assert cls([_bay(must=False)]) == "clear"                             # not required: nothing holds the car
    assert cls([_bay(conc="cabin", svc="interior_reset")]) == "clear"     # work done in place, not in a bay
    assert cls([_bay(done=before), _bay(svc="cosmetic_repair")]) == "bay"
    assert db.val("SELECT public.ottoq_dwell_class('{}'::jsonb, now())") == "clear"


# ── the fit ───────────────────────────────────────────────────────────────────────────────────────────────────────────

def _visits_for(d, tag, n, atoms_fn):
    for k in range(n):
        vid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0623-{tag}-{k}"))
        _visit(d, vid, -160, atoms_fn(k))


def test_0624_the_fit_learns_the_dwell_by_class_and_keeps_0623s_keys(db):
    out._through_0623(db)
    # charges ending at minute -120 (the run's clock is at 0): twenty clear cars, half leaving at once and half after a
    # minute (half of them had their wash done before the charge); twelve owing a wash, eight leaving a minute after it
    # was done at -100 and four still parked; six with no visit, leaving after 5 minutes
    done_before, done_after = _ts(db, -125), _ts(db, -100)
    for n, left, tag in ((10, 0, "c0"), (10, 1, "c1"), (8, 21, "b"), (4, None, "bp"), (6, 5, "o")):
        out._charged_and_left(db, RUN, n, -120, left, tag)
    _visits_for(db, "c0", 10, lambda k: [])
    _visits_for(db, "c1", 10, lambda k: [_bay(done=done_before)])
    _visits_for(db, "b", 8, lambda k: [_bay(done=done_after)])
    _visits_for(db, "bp", 4, lambda k: [_bay()])
    old = db.json(f"SELECT public.ottoq_return_model_params('{DEPOT}', now(), interval '21 days')")
    _apply(db)
    new = db.json(f"SELECT public.ottoq_return_model_params('{DEPOT}', now(), interval '21 days')")
    # every key 0623 computed, as it computed it
    assert {k: v for k, v in new.items() if k != "dwell_by"} == old
    by = new["dwell_by"]
    assert sorted(by) == ["bay", "boot", "clear", "new"], sorted(by)

    def head(c):
        return (c["n"], c["left"], c["censored"], c["f_max"], c["max_min"], c["median_min"], c["population"])
    # clear: 10 at 0, 10 at 1 (the curve reaches 0.5 at 0, so the grid's 0.5 is 0)
    assert head(by["clear"]) == (20, 20, 0, 1, 1, 0, "all_ticks"), by["clear"]
    assert by["clear"]["q"] == [0] * 11 + [1] * 9, by["clear"]["q"]
    # bay: 8 of 12 at 21, four censored at the run's clock: the curve stops at 2/3
    assert head(by["bay"]) == (12, 8, 4, 0.6667, 21, 21, "all_ticks"), by["bay"]
    assert by["bay"]["q"] == [21] * 14 + [None] * 6, by["bay"]["q"]
    assert head(by["boot"]) == (6, 6, 0, 1, 5, 5, "all_ticks"), by["boot"]
    # new: the visit cars together, 10 at 0, 10 at 1, 8 at 21 of 32
    assert head(by["new"]) == (32, 28, 4, 0.875, 21, 1, "all_ticks"), by["new"]
    # the pooled curve still pools everyone: its median is the 20th of 38 cars, at a minute
    assert (new["dwell"]["n"], new["dwell"]["left"], new["dwell"]["median_min"]) == (38, 34, 1), new["dwell"]
    # the nightly fit writes it
    eid = db.val(f"SELECT public.ottoq_fit_return_model('{DEPOT}', NULL, interval '21 days', 'test')")
    est = db.json(f"SELECT public.ottoq_learned_estimate('{DEPOT}', 'return_v1')")
    assert str(est["estimate_id"]) == eid and est["params"]["dwell_by"] == by, est["params"].keys()


# ── the state ─────────────────────────────────────────────────────────────────────────────────────────────────────────

LIN = [float(i) for i in range(20)]             # a grid on which the minutes are 20 x the probability, to 19 at 0.95


def _grid(q, fmax, mx, left=90):
    return {"q": q, "f_max": fmax, "max_min": mx, "median_min": None, "n": 100, "left": left, "censored": 100 - left,
            "population": "fine_ticks"}


BY = {"clear": _grid([1.0] * 20, 1, 1), "bay": _grid([30.0] * 20, 1, 30), "boot": _grid([10.0] * 20, 1, 10),
      "new": _grid(LIN, 0.95, 19)}


def _return_model_by(d, by=None):
    """A usable return_v1 with 0623's dwell and, when given, the dwell by class."""
    p = {"threshold_soc": 50, "drain_pct_per_min": 0.5, "drain_log_sd": 0.2, "trip_min": 2, "other_share": 0.1,
         "other_per_work_hour": 0, "dwell": out.DWELL}
    if by is not None:
        p["dwell_by"] = by
    return int(d.val(f"""INSERT INTO public.ottoq_learned_estimates (depot_id, model, n_evidence, n_runs, usable, params,
                                                                     code_md5, note)
                         VALUES ('{DEPOT}', 'return_v1', 100, 5, true, $j${json.dumps(p)}$j$::jsonb, 'test', 'test')
                         RETURNING estimate_id"""))


def _the_depot_with_work(d):
    """0623's L (charged to 100% and parked since -12) and Y (charging on L3 since -30), now with visits: L's in-place
    reset done at -5, after its charge; Y owing a wash. In the line, A owes a wash and B has nothing open; the other
    line cars' visits have not arrived (no visit at the clock). W is out at work since -40, coming home."""
    out._parked_and_charging(d)
    _visit(d, _vid("L"), -90, [_bay(conc="cabin", svc="interior_reset", done=_ts(d, -5))])
    _visit(d, _vid("Y"), -60, [_bay()])
    d.val(f"UPDATE public.ottoq_visit_needs SET arrived_at = '{T}'::timestamptz - interval '30 minutes', "
          f"atoms = $j${json.dumps([_bay()])}$j$::jsonb WHERE vehicle_id = '{_vid('A')}'")
    d.val(f"UPDATE public.ottoq_visit_needs SET arrived_at = '{T}'::timestamptz - interval '30 minutes', atoms = '[]' "
          f"WHERE vehicle_id = '{_vid('B')}'")
    base._car(d, "W", 70, 0, state="deployed")
    d.val(f"DELETE FROM public.ottoq_visit_needs WHERE vehicle_id = '{_vid('W')}'")
    d.val(f"""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                           planned_duration_min, status)
              VALUES ('{_vid('W')}', '{RUN}', '{T}'::timestamptz - interval '40 minutes',
                      '{T}'::timestamptz + interval '20 minutes', 60, 'returning')""")


def test_0624_the_state_reads_each_cars_class_and_the_dial_takes_it_away(db):
    _through_0624(db)
    _the_depot_with_work(db)
    # a return model without the classes: 0623's state, key for key
    _return_model_by(db, None)
    s0 = arb._state(db)
    assert s0["outflow"]["v"] == 1 and "dwell_by" not in s0["outflow"], s0["outflow"].keys()
    assert not any("dc" in r for r in s0["outflow"]["ret"].values())
    assert not any("o" in x for x in s0["outflow"]["leaving"])
    # with them: each car's class at the clock
    thin = dict(BY, boot=_grid([10.0] * 20, 1, 10, left=12))           # 12 departures: too thin to use
    eid = _return_model_by(db, thin)
    s = arb._state(db)
    o = s["outflow"]
    assert (o["v"], o["return_model"]) == (2, eid), o
    assert sorted(o["dwell_by"]) == ["bay", "clear", "new"], sorted(o["dwell_by"])
    assert o["dwell_by"]["bay"] == {"q": [30] * 20, "f_max": 1, "max_min": 30, "median_min": None, "left": 90}
    dc = {base.NAMES.get(k, k): v["dc"] for k, v in o["ret"].items()}
    assert dc["L"] == "clear" and dc["Y"] == "bay" and dc["A"] == "bay" and dc["B"] == "clear", dc
    assert {dc[n] for n in ("C", "D", "P", "I")} == {"boot"}, dc
    if _vid("W") in o["ret"]:                                          # W is modelled when the line reads it home
        assert dc["W"] == "new", dc
    # L's clock starts when its reset was done, 7 minutes after its charge ended 12 minutes ago
    assert o["leaving"] == [{"id": _vid("L"), "e": 12, "sdep": 100, "o": 7}], o["leaving"]
    # everything else is 0623's
    assert {k: v for k, v in o.items() if k not in ("v", "dwell_by", "ret", "leaving", "return_model")} == \
        {k: v for k, v in s0["outflow"].items() if k not in ("v", "ret", "leaving", "return_model")}
    assert {k: {x: y for x, y in v.items() if x != "dc"} for k, v in o["ret"].items()} == s0["outflow"]["ret"]
    # the run's dial at 0: 0623's state exactly
    _dial(db, "agent_charge_order_dwell_class", 0)
    sd = arb._state(db)
    assert sd["outflow"]["v"] == 1 and "dwell_by" not in sd["outflow"] and sd["outflow"]["leaving"] == s0["outflow"]["leaving"]
    assert sd["outflow"]["ret"] == s0["outflow"]["ret"]


def test_0624_a_car_out_at_work_is_a_new_visit(db):
    """W left at -40 and has not come back: whatever its last visit owed, its next visit's work is not known."""
    _through_0624(db)
    _the_depot_with_work(db)
    _visit(db, _vid("W"), -200, [_bay()])                              # an old visit, before it left
    _return_model_by(db, BY)
    cl = db.json(f"""SELECT jsonb_object_agg(k, v ->> 'dc') FROM jsonb_each(
                       public.ottoq_charge_line_outflow('{RUN}', '{DEPOT}', '{T}',
                         jsonb_build_object('cars', '[]'::jsonb, 'chargers', '[]'::jsonb,
                                            'inbound', jsonb_build_array(jsonb_build_object('id', '{_vid('W')}'))),
                         public.ottoq_charge_clock_model('{DEPOT}'),
                         public.ottoq_learned_estimate('{DEPOT}', 'return_v1'), NULL) #> '{{outflow,ret}}') r(k, v)""")
    # W is out at work; L, charged and parked (the outflow reads it from the ledger), is here and clear
    assert cl == {_vid("W"): "new", _vid("L"): "clear"}, cl
    # once it is back, its new visit decides
    _visit(db, _vid("W"), -3, [])
    cl = db.json(f"""SELECT jsonb_object_agg(k, v ->> 'dc') FROM jsonb_each(
                       public.ottoq_charge_line_outflow('{RUN}', '{DEPOT}', '{T}',
                         jsonb_build_object('cars', '[]'::jsonb, 'chargers', '[]'::jsonb,
                                            'inbound', jsonb_build_array(jsonb_build_object('id', '{_vid('W')}'))),
                         public.ottoq_charge_clock_model('{DEPOT}'),
                         public.ottoq_learned_estimate('{DEPOT}', 'return_v1'), NULL) #> '{{outflow,ret}}') r(k, v)""")
    assert cl == {_vid("W"): "clear", _vid("L"): "clear"}, cl


# ── the draw ──────────────────────────────────────────────────────────────────────────────────────────────────────────

def _draw(d, ready, e, sdep, o=None, q=None, fmax=out.FMAX, mx=out.MAX, real=None, cut=None, ud=0.5, scenario=0):
    qs = out.QSQL if q is None else "ARRAY[" + ", ".join(str(x) for x in q) + "]::float8[]"
    car = "ARRAY[100, 49, 30, 200, 0.1, 0.1" + ("" if o is None else f", {o}") + "]::float8[]"
    return d.json(f"""SELECT COALESCE(to_jsonb(public.ottoq_charge_line_return_draw(
                         ARRAY[50, 0.5, 0.2, 2, 0, {fmax}, {mx}]::float8[], {qs}, {car}, {_n(ready)}, {_n(e)}, {_n(sdep)},
                         {scenario}, 's', 'c1', {_n(ud)}, NULL, 0, {_j(real)}, {_n(cut)})), 'null'::jsonb)""")


def test_0624_the_draw_starts_a_cars_clock_when_its_work_was_done(db):
    _through_0624(db)
    # without p_car[7], or with it at 0, 0623's draw on every path
    for args in ((0, 10, 100), (25, 0, None), (0, 400, 100)):
        assert _draw(db, *args) == _draw(db, *args, o=0), args
    for kw in ({"real": {"ce": -10, "left": 4, "eta": 70, "soc": 52}}, {"real": {"ce": -10}, "cut": 90},
               {"real": {"ce": 20, "left": 23}, "cut": 90}, {"scenario": 3, "ud": None}):
        assert _draw(db, 0, 10, 100, **kw) == _draw(db, 0, 10, 100, o=0, **kw), kw
    # parked 10 minutes, its work done 3 minutes ago (7 after its charge) on a curve where every car leaves at 5: its
    # clock has run 3 minutes, so it leaves 2 from now; from its charge's end it would be past the curve and stay
    five = [5.0] * 20
    assert _draw(db, 0, 10, 100, q=five, fmax=1, mx=5) is None
    r = _draw(db, 0, 10, 100, o=7, q=five, fmax=1, mx=5)
    assert r is not None and r[0] == 2 and r[1] == 2 + 102, r
    # what really happened is the charge-end frame's: the clock changes nothing there
    assert _draw(db, 0, 10, 100, o=7, q=five, fmax=1, mx=5, real={"ce": -10, "left": 4, "eta": 70, "soc": 52})[:3] == \
        [4, 70, 52]
    # not gone by the cut: at least that long on its clock
    assert _draw(db, 0, 10, 100, o=7, q=LIN, fmax=0.95, mx=19, real={"ce": -10}, cut=10)[0] >= 10
    assert _draw(db, 0, 10, 100, o=7, q=LIN, fmax=0.95, mx=19, real={"ce": -10}, cut=30) is None   # past the curve


# ── the schedule ──────────────────────────────────────────────────────────────────────────────────────────────────────

RET = out.RET


def _class_state(leaving=None, dc=None):
    """0623's _out_state with the dwell by class: A (in the line, fast charger 0-40), Y (on the L2 until 10), L (parked
    5 minutes)."""
    s = out._out_state()
    s["outflow"]["dwell_by"] = {k: {x: v[x] for x in ("q", "f_max", "max_min", "median_min", "left")} for k, v in BY.items()}
    dc = dc or {"a": "clear", "y": "bay", "l": "clear"}
    s["outflow"]["ret"] = {k: dict(RET, dc=dc[k]) for k in ("a", "y", "l")}
    if leaving is not None:
        s["outflow"]["leaving"] = leaving
    return s


def test_0624_the_schedule_draws_each_car_on_its_class(db):
    _through_0624(db)
    # L's work was done half a minute ago (4.5 after its charge): on the clear curve it leaves at 0.5. Y owes a wash:
    # 30 minutes after its charge ends at 10, it leaves at 40. A, clear, leaves a minute after its fast charge: 41
    r = arb._sched(db, _class_state(leaving=[{"id": "l", "e": 5, "sdep": 100, "o": 4.5}]))
    seats = {x["id"]: (x["dep"], x["dc"]) for x in r["return_seats"]}
    assert seats == {"l": (0.5, "clear"), "y": (40, "bay"), "a": (41, "clear")}, seats
    # a car whose class has no curve takes the pooled one: 0623's 5 minutes
    s = _class_state(dc={"a": "clear", "y": "bay", "l": "boot"})
    del s["outflow"]["dwell_by"]["boot"]
    r = arb._sched(db, s)
    assert {x["id"]: x["dep"] for x in r["return_seats"]}["l"] == 0, r["return_seats"]     # parked 5: its 5 are up
    # the expected future spreads the dwells within each class: four parked clear cars on a curve where the minutes are
    # 20 x the probability take its 1/8, 3/8, 5/8 and 7/8; the one bay car takes its own curve's middle
    st = _class_state()
    st["outflow"]["dwell_by"]["clear"] = {"q": LIN, "f_max": 0.95, "max_min": 19, "median_min": 10, "left": 90}
    st["outflow"]["dwell_by"]["bay"] = {"q": LIN, "f_max": 0.95, "max_min": 19, "median_min": 10, "left": 90}
    st["cars"], st["chargers"] = [], [{"id": "f", "k": "dcfc", "free": 0}]
    st["outflow"]["ret"] = {f"p{k}": dict(RET, dc="clear") for k in range(4)} | {"q": dict(RET, dc="bay")}
    st["outflow"]["leaving"] = [{"id": f"p{k}", "e": 0, "sdep": 100} for k in range(4)] + \
        [{"id": "q", "e": 0, "sdep": 100}]
    r = arb._sched(db, st)
    deps = {x["id"]: x["dep"] for x in r["return_seats"]}
    assert sorted(deps[f"p{k}"] for k in range(4)) == [2.5, 7.5, 12.5, 17.5], deps
    assert deps["q"] == 10, deps
    # 0623 spread all five over one curve: 2, 6, 10, 14, 18
    flat = json.loads(json.dumps(st))
    del flat["outflow"]["dwell_by"]
    flat["outflow"]["dwell"] = {"q": LIN, "f_max": 0.95, "max_min": 19, "median_min": 10}
    assert sorted(x["dep"] for x in arb._sched(db, flat)["return_seats"]) == [2, 6, 10, 14, 18]


def test_0624_without_classes_the_schedule_is_0623s_on_random_lines(db):
    """Random lines, each with 0623's outflow block (some with classes named in ret but no dwell_by): the schedule,
    traced, in the expected future and two sampled ones, as 0623 returned it."""
    rng = random.Random(624)
    cases = []
    for i in range(80):
        st, o = arb._rand_case(rng, i)
        ids = [c["id"] for c in st["cars"]] + [c["id"] for c in st["inbound"]]
        busy = [c for c in st["chargers"] if c["free"] > 0]
        if busy and ids and rng.random() < 0.5:
            busy[0]["car"] = rng.choice(ids)
        parked = [f"p{i}_{k}" for k in range(rng.randint(0, 3))]
        ret = {cid: dict(RET, tg=100, rs=rng.choice([40, 49]), rmd=rng.randint(15, 45), rml=rng.randint(60, 240))
               for cid in ids + parked}
        if rng.random() < 0.5:
            for cid in ret:
                ret[cid]["dc"] = rng.choice(["clear", "bay", "boot", "new"])
        st["outflow"] = {"v": 1, "window_min": 90, "thr": 50, "drain": rng.choice([0.4, 0.7]), "dsd": rng.choice([0, 0.1]),
                         "trip": 1.5, "lam": rng.choice([0, 0.002]),
                         "dwell": {"q": out.Q, "f_max": out.FMAX, "max_min": out.MAX, "median_min": 7.28},
                         "ret": ret,
                         "leaving": [{"id": p, "e": rng.choice([0, 3, 40]), "sdep": 100, "o": rng.choice([0, 2])}
                                     for p in parked]}
        cases.append((st, o))
    out._through_0623(db)
    db.val("CREATE TABLE public.t0624 (i int, sc int, state jsonb, ord jsonb, k jsonb)")
    rows = ", ".join(f"({i}, {sc}, $j${json.dumps(st)}$j$::jsonb, {_j(o)}, NULL)"
                     for i, (st, o) in enumerate(cases) for sc in (0, 1, 2))
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as fh:
        fh.write(f"INSERT INTO public.t0624 VALUES {rows};\n")
    try:
        _file(db, fh.name)
    finally:
        os.unlink(fh.name)
    db.val("UPDATE public.t0624 SET k = public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true)")
    _apply(db)
    bad = db.json("""SELECT COALESCE(jsonb_agg(jsonb_build_object('i', i, 'sc', sc)), '[]'::jsonb) FROM public.t0624
                      WHERE k IS DISTINCT FROM public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true)""")
    assert bad == [], bad[:5]
    n = db.json("""SELECT jsonb_build_array(count(*), count(*) FILTER (WHERE jsonb_array_length(k -> 'return_seats') > 0))
                     FROM public.t0624""")
    assert n[0] == 240 and n[1] > 100, n        # the outflow is exercised, not skipped


# ── the grader ────────────────────────────────────────────────────────────────────────────────────────────────────────

def _fe(d, state, real, expected):
    return d.json(f"SELECT public.ottoq_charge_order_forecast_errors({_j(state)}, {_j(real)}, {_j(expected)}) -> 'outflow'")


REAL = {"observed_min": 3, "cars": {}, "inbound": {}, "appeared": [], "chargers": {}, "back": [], "faults": 0,
        "unmodeled_sessions": 0,
        # A's charge ended at the clock and it left at 1; L, parked 10 minutes, its work done half a minute ago, left at
        # 0.2; Y's charge ended at 1 and it was still there at the cut, 3
        "returns": {"a": {"ce": 0, "left": 1}, "l": {"ce": -10, "left": 0.2}, "y": {"ce": 1}}}


def _graded_state():
    s = _class_state(leaving=[{"id": "l", "e": 10, "sdep": 100, "o": 9.5}])
    s["outflow"]["dwell"] = {"q": [5.0] * 20, "f_max": 1, "max_min": 5, "median_min": 5}
    return s


def test_0624_the_grader_grades_each_car_on_its_class_with_the_pooled_curve_beside(db):
    _through_0624(db)
    st = _graded_state()
    o = _fe(db, st, REAL, {"return_seats": []})
    # on the clear curve (a minute) A and L are certain to go and go at once; on the pooled one (5 minutes) A cannot
    # have gone by 3, and L, parked 10, is past the pooled curve's last departure. Y owes a wash (30 minutes): it stays
    assert (o["dwell"]["seen"], o["dwell"]["left"], o["dwell"]["p_left"], o["dwell"]["brier"]) == (3, 2, 2, 0), o["dwell"]
    assert (o["dwell"]["pit_n"], o["dwell"]["pit50"]) == (2, 2), o["dwell"]
    assert (o["dwell_pooled"]["seen"], o["dwell_pooled"]["p_left"], o["dwell_pooled"]["brier"]) == (3, 0, 2), \
        o["dwell_pooled"]
    assert o["dwell_by"] == {
        "clear": {"seen": 2, "left": 2, "p_left": 2, "brier": 0, "brier_pooled": 2, "pit_n": 2, "pit50": 2, "pit80": 2,
                  "pit_sum": 0},
        "bay": {"seen": 1, "left": 0, "p_left": 0, "brier": 0, "brier_pooled": 0, "pit_n": 0, "pit50": 0, "pit80": 0,
                "pit_sum": 0}}, o["dwell_by"]
    # a car whose class has no curve is graded on the pooled one, under "pooled"
    del st["outflow"]["dwell_by"]["bay"]
    assert sorted(_fe(db, st, REAL, {"return_seats": []})["dwell_by"]) == ["clear", "pooled"]


def test_0624_without_classes_the_grader_is_0623s(db):
    out._through_0623(db)
    cases = []
    for k, st in enumerate((out._out_state(), _graded_state())):
        st = json.loads(json.dumps(st))
        st["outflow"].pop("dwell_by", None)
        real = dict(REAL, observed_min=90 if k == 0 else 3)
        exp = arb._sched(db, st)
        cases.append((st, real, exp, _fe(db, st, real, exp)))
    _apply(db)
    for st, real, exp, before in cases:
        assert _fe(db, st, real, exp) == before
        assert arb._sched(db, st) == exp
