"""db/migrations/0627, EXECUTED: the futures call cars home the way the kernel does.

WHY THIS EXISTS. 0626's first self-review ranked the arrivals first: the check's futures called every working car home at
one reserve, the median the depot's returns show, while the kernel's own recall decision calls each car home at its own
reserve rung (its reserve plus the run's margin) and calls some home sooner, on stale telemetry or a rider's flag (G363).
0627 reads the rung, samples the other calls home, and spreads each arrival by the drive's own minutes. Every claim in its
header that a test can execute is executed here, on the scratch PostgreSQL and the miniature depot of
tests/test_agent_charge_order_sql.py, through 0619-0626 as tests/test_agent_self_review_sql.py applies them:
  - it applies, its checks run, its dial is a person's, and it refuses a body or a recall rule it was not written against;
  - the rung is the reserve the recall decision reads plus the run's margin, exactly where the decision itself turns the
    car home, and nothing for an implementation without that rung;
  - a car at work is forecast home at its own rung, its spread the drain's and the drive's in minutes; with the dial at 0,
    0620's forecast exactly;
  - the fit learns the drives and every key 0624 computed is as it was;
  - the state carries each car's rung and the other calls home, the outflow sends each car out to its own rung, and with
    the dial at 0 both are 0626's exactly;
  - the draw drives the other call's own trip; a sampled future calls a car home early, back with the charge it did not
    use, while the expected future keeps each car's median; without a recall block, a rung or a trip_o the schedule is
    0626's, key for key, on random lines;
  - where an arrival fell in its forecast, with the other calls home beside the reserve, and the normal's own
    probability;
  - the self-review places each arrival in the forecast its order made and marks the old orders' arrivals built; its
    writer's md5 covers the z;
  - V1-V3 on d9d49732 in miniature: the fit through its start, the gate passing on a world the rule describes and
    holding back on one it does not, and the rung held to the recall decision's own record.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import math
import os
import random
import re
import sys
import tempfile
import uuid
from statistics import NormalDist

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622 and their helpers)
import test_agent_outflow_sql as out  # noqa: E402  (0623 and its helpers)
import test_agent_dwell_class_sql as dw  # noqa: E402  (0624 and its helpers)
import test_agent_self_review_sql as sr  # noqa: E402  (0626 and its helpers)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0627 = os.path.join(ROOT, "db", "migrations", "0627_the_futures_call_cars_home_the_way_the_kernel_does.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
GATE = "d9d49732-cf28-42c3-aac9-9c3f606a2c92"
_vid, _dial, _file, _j, _n = base._vid, base._dial, arb._file, out._j, out._n
ND = NormalDist()

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

NOTE = (" These orders were made before the futures called each car home at its own reserve rung, with the other calls "
        "home beside it, so this is history until new orders are graded.")
ACT = ("Grade the next armed run's orders: the futures now call each car home at its own reserve rung, with the other "
       "calls home beside it.")


def _apply(d):
    return _file(d, M0627)


def _through_0627(d):
    sr._through_0626(d)
    return _apply(d)


def _q(d, sql):
    """One value as JSON; NULL as None."""
    return d.json(f"SELECT COALESCE(to_jsonb(({sql})), 'null'::jsonb)")


def _mix_time(u, hz, trip, esd, lam, trip_o):
    """The arrival the forecast with the other calls home puts at probability u: the inverse of
    F(t) = 1 - (1 - Phi(ln((t - trip) / hz) / esd)) * exp(-lam * max(t - trip_o, 0)), by bisection on ln(t - trip)."""
    def f(x):
        t = trip + math.exp(x)
        return 1 - (1 - ND.cdf((x - math.log(hz)) / esd)) * math.exp(-lam * max(t - trip_o, 0))
    lo, hi = math.log(1e-9), math.log(hz) + 9 * esd
    for _ in range(200):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if f(mid) < u else (lo, mid)
    return trip + math.exp((lo + hi) / 2)


def _graded(d, oid, state, inbound_real, run=RUN, at_min=0):
    """A graded order: its snapshot (the check's state as given) and its hindsight row (the inbound cars' arrivals)."""
    rz = {"observed_min": 90, "cars": {}, "inbound": inbound_real, "appeared": [], "chargers": {}, "back": []}
    at = f"'{T}'::timestamptz + interval '{at_min} minutes'"
    return (f"""INSERT INTO public.ottoq_charge_order_snapshots (order_id, sim_run_id, depot_id, sim_clock, seed, futures,
                                                                 win_frac, state, agent_order, code_md5)
                VALUES ({oid}, '{run}', '{DEPOT}', {at}, 'hand', 12, 0.8, $j${json.dumps(state)}$j$::jsonb, '{{}}', 'hand');
                INSERT INTO public.ottoq_charge_order_hindsight (order_id, sim_run_id, depot_id, sim_clock, window_min,
                  observed_min, status, reason, taken, decision, futures, wins, need, p_win, expected, hindsight, outcome,
                  moves, forecast, fidelity, realized, code_md5)
                VALUES ({oid}, '{run}', '{DEPOT}', {at}, 90, 90, 'accepted', 'wins_most_futures', true, true, 12, 12, 10, 1,
                        '{{"cmp": 1}}', '{{"cmp": 1}}', 'right_take', '{{}}', '{{}}', '{{}}',
                        $j${json.dumps(rz)}$j$::jsonb, 'hand');""")


def _run_sql(d, statements):
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as fh:
        fh.write("\n".join(statements) + "\n")
    try:
        _file(d, fh.name)
    finally:
        os.unlink(fh.name)


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0627_applies_and_its_checks_run(db):
    err = _through_0627(db)
    assert "0627 V1: 0 stored simulations and comparisons (0 snapshots x 2 futures) unchanged" in err, err
    assert "0627 V1: 0 graded arrivals of the 21 days, each z as 0621's" in err, err
    assert "0627 V1: run d9d49732 is not here; the fit is executed by the tests" in err, err
    assert "0627 V2: run d9d49732 is not here; the gate is executed by the tests" in err, err
    assert "0627 V3: the rung equals the recall decision's own record on 0 of 0 decisions, across 0 runs" in err, err
    assert "0627 V3: the fit at apply has no reserve returns to learn the drives from" in err, err
    assert re.search(r"0627 V3 on running run a0000000-0000-0000-0000-000000000614: state \d+ ms, recall <NULL>, "
                     r"forecast cars with a rung 0 of 0", err), err
    dial = db.json("""SELECT jsonb_build_array(min_value, max_value, default_value, agent_writable)
                        FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_recall_rule'""")
    assert dial == [0, 1, 1, False], dial
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0627_%'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0627_pre'") == "8"
    priv = db.json("""SELECT jsonb_build_object(
        'rung_anon', has_function_privilege('anon', 'public.ottoq_recall_threshold_soc(uuid,uuid,timestamptz)', 'EXECUTE'),
        'rung_auth', has_function_privilege('authenticated',
                       'public.ottoq_recall_threshold_soc(uuid,uuid,timestamptz)', 'EXECUTE'),
        'rung_service', has_function_privilege('service_role',
                          'public.ottoq_recall_threshold_soc(uuid,uuid,timestamptz)', 'EXECUTE'),
        'cdf', has_function_privilege('anon', 'public.ottoq_normal_cdf(double precision)', 'EXECUTE'),
        'z', has_function_privilege('anon', 'public.ottoq_inbound_arrival_z(jsonb,jsonb,double precision)', 'EXECUTE'))""")
    # the rung reads a car's contract as the reserve it reads does (ottoq_effective_reserve_soc): never anonymously
    assert priv == {"rung_anon": False, "rung_auth": True, "rung_service": True, "cdf": True, "z": True}, priv


def test_0627_refuses_a_body_it_was_not_written_against(db):
    sr._through_0626(db)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_charge_line_inbound(p_sim_run_id uuid, p_depot_id uuid,
                p_clock timestamptz, p_window_min numeric DEFAULT 180, p_return_model jsonb DEFAULT NULL)
              RETURNS TABLE(vehicle_id uuid, eta_min numeric, soc_at_arrival numeric, source text, eta_log_sd numeric,
                            trip_min numeric)
              LANGUAGE sql STABLE AS $f$ SELECT NULL::uuid, 0::numeric, 0::numeric, ''::text, 0::numeric, 0::numeric
                                        WHERE false $f$""")
    rc, err = db.file(M0627)
    assert rc != 0 and "0627 P1" in err and "the inbound forecast (0620)" in err, err


def test_0627_refuses_a_recall_decision_whose_rung_it_does_not_read(db):
    sr._through_0626(db)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_recall_naive_threshold_v1(p_vehicle_id uuid, p_sim_run_id uuid,
                p_sim_clock_now timestamptz, p_horizon_min numeric, p_soc_pct numeric)
              RETURNS TABLE(should_return boolean, return_trigger text) LANGUAGE plpgsql STABLE AS $f$
              DECLARE v_soc numeric := p_soc_pct; v_reserve numeric;
              BEGIN
                v_reserve := ottoq_effective_reserve_soc(p_vehicle_id, p_sim_clock_now);
                IF v_soc <= v_reserve THEN RETURN QUERY SELECT true, 'low_soc_reserve'; RETURN; END IF;
                RETURN QUERY SELECT false, NULL::text;
              END $f$""")
    rc, err = db.file(M0627)
    assert rc != 0 and "0627 P1: the recall decision's reserve rung is not its reserve plus the run's margin" in err, err


# ── the rung ──────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0627_the_rung_is_where_the_recall_decision_itself_turns_the_car_home(db):
    _through_0627(db)
    x = _vid("X")

    def rung(run=RUN, vid=x):
        return _q(db, f"SELECT public.ottoq_recall_threshold_soc('{vid}', '{run}', '{T}')")

    def turns_home(soc):
        return db.val(f"""SELECT should_return FROM public.ottoq_recall_naive_threshold_v1('{x}', '{RUN}', '{T}', 60,
                                                                                         {soc})""") == "t"

    def holds(want):
        got = rung()
        assert got == want, (got, want)
        # the recall decision, given the battery, turns the car home at the rung and not a hundredth above it
        assert turns_home(got) and not turns_home(got + 0.01), got

    holds(35)                                                     # no reserve of its own: 20, and the margin of 15
    db.val(f"UPDATE public.vehicles SET min_soc_threshold = 15 WHERE id = '{x}'")
    holds(30)                                                     # its own reserve of 15
    _dial(db, "reserve_margin_pct", 30)
    holds(45)                                                     # the run's margin
    db.val(f"UPDATE public.ottoq_fleet_operator_slas SET return_reserve_soc_pct = 25 "
           f"WHERE fleet_operator_id = '{base.OPERATOR}'")
    holds(55)                                                     # its operator's contract
    assert rung(run=str(uuid.uuid4())) == 40                       # a run that sets no margin: the default 15
    # an implementation with no such rung, or one retired, decides no reserve rung: nothing to read
    for impl in (2, 3, 9):
        _dial(db, "recall_implementation_id", impl)
        assert rung() is None, impl
    _dial(db, "recall_implementation_id", 1)
    assert rung() == 55 and rung(vid=str(uuid.uuid4())) is None   # and a car the depot does not know has none


# ── a car at work ─────────────────────────────────────────────────────────────────────────────────────────────────────

RT = {"threshold_soc": 50, "drain_pct_per_min": 0.5, "drain_log_sd": 0.1, "trip_min": 2, "other_share": 0.1,
      "other_per_work_hour": 0.12, "trip_sd_min": 0.5, "trip_other_min": 4}


def _working(d, cars):
    """Cars out at work for the run since 40 minutes before T, each (name, battery, its own reserve or None), and H
    driving home, due in 6 minutes at 30%."""
    for name, soc, reserve in cars:
        base._car(d, name, soc, 0, state="deployed")
        d.val(f"DELETE FROM public.ottoq_visit_needs WHERE vehicle_id = '{_vid(name)}'")
        if reserve is not None:
            d.val(f"UPDATE public.vehicles SET min_soc_threshold = {reserve} WHERE id = '{_vid(name)}'")
        d.val(f"""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                               planned_duration_min, status)
                  VALUES ('{_vid(name)}', '{RUN}', '{T}'::timestamptz - interval '40 minutes',
                          '{T}'::timestamptz + interval '1 hour', 30, 'active')""")
    base._car(d, "H", 30, 0, state="deployed")
    d.val(f"DELETE FROM public.ottoq_visit_needs WHERE vehicle_id = '{_vid('H')}'")
    d.val(f"""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                           planned_duration_min, status)
              VALUES ('{_vid('H')}', '{RUN}', '{T}'::timestamptz - interval '60 minutes',
                      '{T}'::timestamptz + interval '6 minutes', 30, 'returning')""")


def _inbound(d, params=RT):
    rows = d.json(f"""SELECT jsonb_agg(to_jsonb(i)) FROM public.ottoq_charge_line_inbound('{RUN}', '{DEPOT}', '{T}', 180,
                        {_j({"usable": True, "params": params})}) i""")
    return {base.NAMES[r["vehicle_id"]]: (r["eta_min"], r["soc_at_arrival"], r["eta_log_sd"], r["source"]) for r in rows}


def _sd(hz, dsd=0.1, asd=0.5):
    return math.sqrt(dsd ** 2 + (asd / max(hz, 0.25)) ** 2)


def test_0627_a_car_at_work_is_forecast_home_at_its_own_rung(db):
    sr._through_0626(db)
    _working(db, [("W", 70, None), ("V", 70, 15), ("U", 36, None), ("Z", 30, None)])
    before = _inbound(db)
    _apply(db)
    got = _inbound(db)
    # W at 70% turns home at 35 (20 and the margin of 15): 70 minutes of work and the drive of 2, home at 34%. V carries a
    # reserve of 15: 80 minutes, home at 29%. U is 2 minutes from its rung, Z already below it: the drive alone
    want = {"W": (72, 34, _sd(70)), "V": (82, 29, _sd(80)), "U": (4, 34, _sd(2)), "Z": (2, 29, _sd(0))}
    for name, (eta, soc, sd) in want.items():
        e, s, x, src = got[name]
        assert (e, s, src) == (eta, soc, "forecast") and abs(x - sd) < 5e-5, (name, got[name], want[name])
    # the drive's own minutes widen a forecast in proportion to how short the wait is: a car 2 minutes from its rung is
    # not forecast to the second
    assert got["U"][2] > 2.5 * got["W"][2]
    assert got["H"] == (6, 27, 0, "returning"), got["H"]
    # with no drive spread learned, the drain's alone
    assert {n: v[2] for n, v in _inbound(db, dict(RT, trip_sd_min=None)).items() if n != "H"} == \
        {"W": 0.1, "V": 0.1, "U": 0.1, "Z": 0.1}
    # the run's dial at 0: 0620's forecast exactly, at the one reserve the returns show
    _dial(db, "agent_charge_order_recall_rule", 0)
    assert _inbound(db) == before
    assert before["W"] == (42, 49, 0.1, "forecast") and before["V"] == (42, 49, 0.1, "forecast"), before


# ── the fit ───────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0627_the_fit_learns_the_drives_and_keeps_every_key_0624_computed(db):
    sr._through_0626(db)
    for trip, n in ((1.0, 10), (1.5, 20), (2.5, 10)):            # 40 reserve returns, their drives 1.5 minutes +- 0.25
        arb._returns(db, n, trip_min=trip)
    arb._returns(db, 12, trigger="comms_stale", soc0=90, soc_dec=70, work_min=30, trip_min=4)
    arb._returns(db, 6, trigger="rider_flag_cleaning", soc0=90, soc_dec=60, work_min=50, trip_min=8)
    sql = f"SELECT public.ottoq_return_model_params('{DEPOT}', NULL, interval '21 days')"
    before = db.json(sql)
    _apply(db)
    after = db.json(sql)
    added = {"trip_sd_min", "trip_other_min", "trip_other_p90_min", "other_by_trigger"}
    assert set(after) - set(before) == added and {k: after[k] for k in before} == before, set(after) ^ set(before)
    # the drive home's own spread at the reserve: 1.4826 x the median distance of each drive from 1.5 (0.25)
    assert after["trip_sd_min"] == 0.371 and after["trip_min"] == 1.5, after
    # the drive after another call: wherever the work took the car
    assert (after["trip_other_min"], after["trip_other_p90_min"]) == (4, 8), after
    hours = (40 * 70 + 12 * 30 + 6 * 50) / 60
    assert after["other_by_trigger"] == {"comms_stale": {"n": 12, "per_work_hour": round(12 / hours, 4)},
                                         "rider_flag_cleaning": {"n": 6, "per_work_hour": round(6 / hours, 4)}}, after
    # the nightly fit writes them
    db.val(f"SELECT public.ottoq_fit_return_model('{DEPOT}', NULL, interval '21 days', 'test')")
    est = db.json(f"SELECT public.ottoq_learned_estimate('{DEPOT}', 'return_v1')")
    assert est["usable"] and {k: est["params"][k] for k in added} == {k: after[k] for k in added}, est


# ── the state and the outflow ─────────────────────────────────────────────────────────────────────────────────────────

def _no_ids(state):
    """A state without the estimate ids it read (a model refitted between two readings has a new id)."""
    s = json.loads(json.dumps(state))
    s.get("models", {}).pop("return", None)
    if isinstance(s.get("outflow"), dict):
        s["outflow"].pop("return_model", None)
    return s


def test_0627_the_state_carries_each_cars_rung_and_the_other_calls_home(db):
    sr._through_0626(db)
    _working(db, [("W", 70, None), ("V", 70, 15)])
    out._return_model(db, dwell=None, **RT)
    before = arb._state(db)
    _apply(db)
    eid = out._return_model(db, dwell=None, **RT)                 # the fit at apply wrote one of its own: this is latest
    s = arb._state(db)
    inb = {base.NAMES[c["id"]]: c for c in s["inbound"]}
    assert (inb["W"]["eta"], inb["W"]["thr"], inb["V"]["eta"], inb["V"]["thr"]) == (72, 35, 82, 30), inb
    assert "thr" not in inb["H"]                                  # driving home: nothing to forecast
    assert s["recall"] == {"v": 1, "return_model": eid, "lam": 0.002, "trip_o": 4, "drain": 0.5, "asd": 0.5}, s["recall"]
    # without the drive after another call learned, the reserve's drive; with no other call, a rate of 0
    eid2 = out._return_model(db, dwell=None, **dict(RT, trip_other_min=None, other_per_work_hour=None))
    assert arb._state(db)["recall"] == {"v": 1, "return_model": eid2, "lam": 0, "trip_o": 2, "drain": 0.5, "asd": 0.5}
    # a return model the fit could not use carries no recall block
    db.val(f"""INSERT INTO public.ottoq_learned_estimates (depot_id, model, n_evidence, n_runs, usable, params, code_md5, note)
               VALUES ('{DEPOT}', 'return_v1', 3, 1, false, $j${json.dumps(RT)}$j$::jsonb, 'test', 'test')""")
    assert "recall" not in arb._state(db)
    # the run's dial at 0: 0626's state exactly
    out._return_model(db, dwell=None, **RT)
    _dial(db, "agent_charge_order_recall_rule", 0)
    s0 = arb._state(db)
    assert "recall" not in s0 and not any("thr" in c for c in s0["inbound"])
    assert _no_ids(s0) == _no_ids(before)


def test_0627_the_outflow_sends_each_car_out_to_its_own_rung(db):
    sr._through_0626(db)
    out._parked_and_charging(db)                                  # L charged and parked; Y charging on an L2
    db.val(f"UPDATE public.vehicles SET min_soc_threshold = 15 WHERE id = '{_vid('L')}'")
    out._return_model(db, trip_other_min=4)
    before = arb._state(db)
    _apply(db)
    out._return_model(db, trip_other_min=4)
    o = arb._state(db)["outflow"]
    rl, ry = o["ret"][_vid("L")], o["ret"][_vid("Y")]
    # each comes back from its own rung: L (reserve 15) at 30 less the drive, Y at 35 less it; 0623 brought both to 49
    assert (rl["thr"], rl["rs"], ry["thr"], ry["rs"]) == (30, 29, 35, 34), (rl, ry)
    assert all(r["thr"] == 35 and r["rs"] == 34 for k, r in o["ret"].items() if k not in (_vid("L"), _vid("Y")))
    # and owes more charge for it
    b = before["outflow"]["ret"]
    assert rl["rmd"] > b[_vid("L")]["rmd"] and rl["rml"] > b[_vid("L")]["rml"], (rl, b[_vid("L")])
    assert o["trip_o"] == 4 and o["thr"] == 50, o                 # the block keeps the returns' own reserve beside them
    # the run's dial at 0: 0626's outflow exactly
    _dial(db, "agent_charge_order_recall_rule", 0)
    s0 = arb._state(db)
    assert "trip_o" not in s0["outflow"] and not any("thr" in r for r in s0["outflow"]["ret"].values())
    assert _no_ids(s0) == _no_ids(before)


# ── the draw and the schedule ─────────────────────────────────────────────────────────────────────────────────────────

def _draw(d, lam, uo, trip_o=None):
    """0623's car (parked 10 minutes, charged to 100, called home at 50 at 0.5% a minute, a 2-minute drive), the
    eighth slot the drive after another call."""
    p_out = f"ARRAY[50, 0.5, 0.2, 2, {lam}, {out.FMAX}, {out.MAX}" + ("" if trip_o is None else f", {trip_o}") + "]::float8[]"
    return d.json(f"""SELECT to_jsonb(public.ottoq_charge_line_return_draw({p_out}, {out.QSQL},
                         ARRAY[100, 49, 30, 200, 0.1, 0.1]::float8[], 0, 10, 100, 0, 's', 'c1', 0.5, {_n(uo)}, 0,
                         NULL, NULL))""")


def test_0627_the_draw_drives_the_other_calls_own_trip(db):
    _through_0627(db)
    te = math.log(2) / 0.01                                       # the other call, before the reserve's 100 minutes
    r7, r8 = _draw(db, 0.01, 0.5), _draw(db, 0.01, 0.5, trip_o=6)
    assert abs(r7[1] - r7[0] - (te + 2)) < 1e-6 and abs(r8[1] - r8[0] - (te + 6)) < 1e-6, (r7, r8)
    # it leaves when it would have, and comes back with what the longer drive left
    assert r8[0] == r7[0] and abs(r8[2] - (100 - 0.5 * (te + 6))) < 1e-6, r8
    # the reserve first: the reserve's own drive, whatever the other call's
    r = _draw(db, 0.001, 0.5, trip_o=6)
    assert abs(r[1] - r[0] - 102) < 1e-6 and r[2] == 49, r
    # an empty eighth slot is none at all
    assert _draw(db, 0.01, 0.5, trip_o="NULL") == r7


def test_0627_a_car_the_outflow_sends_out_turns_home_at_its_own_rung_and_drives_trip_o(db):
    _through_0627(db)
    s = out._out_state()
    plain = {x["id"]: x for x in arb._sched(db, s)["return_seats"]}
    assert (plain["l"]["dep"], plain["l"]["a"], plain["l"]["soc"]) == (0, 102, 49), plain["l"]
    # L's own rung is 40: it works from 100% down to 40, 120 minutes, drives 2, and is back at 39%
    s["outflow"]["ret"]["l"] = dict(out.RET, thr=40)
    rung = {x["id"]: x for x in arb._sched(db, s)["return_seats"]}
    assert (rung["l"]["dep"], rung["l"]["a"], rung["l"]["soc"]) == (0, 122, 39), rung["l"]
    # another call first, at 1 in 50 minutes: each car is called home at the same moment either way, and then drives the
    # other call's 6 minutes, not the reserve's 2
    s = out._out_state()
    s["outflow"]["lam"] = 0.02
    two = {x["id"]: x for x in arb._sched(db, s)["return_seats"]}
    s["outflow"]["trip_o"] = 6
    six = {x["id"]: x for x in arb._sched(db, s)["return_seats"]}
    assert set(two) == set(six) == {"a", "l", "y"}, (two, six)
    for c in two:
        assert six[c]["dep"] == two[c]["dep"] and abs(six[c]["a"] - two[c]["a"] - 4) < 0.011, (c, two[c], six[c])


def _one_coming_home(recall=None):
    """One car at work forecast home in 60 minutes (a 2-minute drive) at 34%, owing 66 points, 33 minutes on a fast
    charger; one fast charger free."""
    s = {"ttl_min": 0, "pin_min": 90, "horizon_min": 480, "cars": [],
         "inbound": [{"id": "w", "src": "forecast", "eta": 60, "trip": 2, "esd": 0.1, "soc": 34, "g": 66, "imm": False,
                      "w": 0, "md": 33, "ml": 165, "sd": 0, "sl": 0, "dok": True, "lok": True}],
         "chargers": [{"id": "f", "k": "dcfc", "free": 0}]}
    if recall is not None:
        s["recall"] = recall
    return s


def _seat(d, state, sc):
    return d.json(f"SELECT public.ottoq_charge_line_schedule({_j(state)}, NULL, {sc}, 's', true) -> 'seats' -> 0")


def test_0627_a_sampled_future_calls_a_car_home_early_and_the_expected_one_keeps_its_median(db):
    _through_0627(db)
    rc = {"v": 1, "lam": 0.02, "trip_o": 3, "drain": 0.5}
    # the expected future: the car's median arrival, recall block or none
    for st in (_one_coming_home(), _one_coming_home(rc)):
        seat = _seat(db, st, 0)
        assert (seat["a"], seat["s0"], seat["r"]) == (60, 60, 93), seat
    draws = db.json("""SELECT jsonb_agg(jsonb_build_array(public.ottoq_hash_normal('s:' || k || ':w:arrival'),
                                                          public.ottoq_hash_uniform('s:' || k || ':w:early')) ORDER BY k)
                         FROM generate_series(1, 30) k""")
    early = 0
    for k, (z, u) in enumerate(draws, 1):
        reserve = 2 + 58 * math.exp(0.1 * z)                      # the reserve's arrival, sampled as 0620 samples it
        te = -math.log(1 - min(u, 0.999999)) / 0.02 + 3           # another call home, then its drive
        a, md = reserve, 33.0
        if te < reserve:                                          # first: it worked less and is back with more charge
            early += 1
            owe = max(66 - 0.5 * max(60 - te, 0), 1)
            a, md = te, 33 * owe / 66
        seat = _seat(db, _one_coming_home(rc), k)
        assert abs(seat["a"] - a) < 0.006 and abs(seat["s0"] - a) < 0.006 and abs(seat["r"] - seat["s0"] - md) < 0.011, \
            (k, seat, a, md)
        # without the block, or with no other call, the reserve's arrival and the whole charge
        for st in (_one_coming_home(), _one_coming_home(dict(rc, lam=0))):
            s2 = _seat(db, st, k)
            assert abs(s2["a"] - reserve) < 0.006 and abs(s2["r"] - s2["s0"] - 33) < 0.011, (k, s2, reserve)
    assert 0 < early < 30, early                                 # both happen in thirty futures


def test_0627_without_a_recall_block_a_rung_or_a_trip_o_the_schedule_is_0626s_on_random_lines(db):
    """Random lines, each with an outflow block (half with the dwell by class), some inbound cars carrying their rung
    (it is in their eta already, and the simulator does not read it): the schedule, traced, in the expected future and
    two sampled ones, as 0626 returned it. Then a recall block: the expected future is unchanged and sampled ones move."""
    rng = random.Random(627)
    cases = []
    for i in range(80):
        st, o = arb._rand_case(rng, i)
        for e in st["inbound"]:
            if rng.random() < 0.5:
                e["thr"] = rng.choice([30, 45, 50])
        ids = [c["id"] for c in st["cars"]] + [c["id"] for c in st["inbound"]]
        busy = [c for c in st["chargers"] if c["free"] > 0]
        if busy and ids and rng.random() < 0.5:
            busy[0]["car"] = rng.choice(ids)
        parked = [f"p{i}_{k}" for k in range(rng.randint(0, 3))]
        ret = {cid: dict(out.RET, rs=rng.choice([40, 49]), rmd=rng.randint(15, 45), rml=rng.randint(60, 240))
               for cid in ids + parked}
        classes = rng.random() < 0.5
        if classes:
            for cid in ret:
                ret[cid]["dc"] = rng.choice(["clear", "bay", "boot", "new"])
        st["outflow"] = {"v": 2 if classes else 1, "window_min": 90, "thr": 50, "drain": rng.choice([0.4, 0.7]),
                         "dsd": rng.choice([0, 0.1]), "trip": 1.5, "lam": rng.choice([0, 0.002, 0.02]),
                         "dwell": {"q": out.Q, "f_max": out.FMAX, "max_min": out.MAX, "median_min": 7.28},
                         "ret": ret,
                         "leaving": [{"id": p, "e": rng.choice([0, 3, 40]), "sdep": 100, "o": rng.choice([0, 2])}
                                     for p in parked]}
        if classes:
            st["outflow"]["dwell_by"] = {k: {x: v[x] for x in ("q", "f_max", "max_min", "median_min", "left")}
                                         for k, v in dw.BY.items()}
        cases.append((st, o))
    sr._through_0626(db)
    db.val("CREATE TABLE public.t0627 (i int, sc int, state jsonb, ord jsonb, k jsonb)")
    _run_sql(db, ["INSERT INTO public.t0627 VALUES " + ", ".join(
        f"({i}, {sc}, $j${json.dumps(st)}$j$::jsonb, {_j(o)}, NULL)" for i, (st, o) in enumerate(cases) for sc in (0, 1, 2))
        + ";"])
    db.val("UPDATE public.t0627 SET k = public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true)")
    _apply(db)
    bad = db.json("""SELECT COALESCE(jsonb_agg(jsonb_build_object('i', i, 'sc', sc)), '[]'::jsonb) FROM public.t0627
                      WHERE k IS DISTINCT FROM public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true)""")
    assert bad == [], bad[:5]
    n = db.json("""SELECT jsonb_build_array(count(*), count(*) FILTER (WHERE jsonb_array_length(k -> 'return_seats') > 0),
                                            count(*) FILTER (WHERE state #> '{outflow,dwell_by}' IS NOT NULL))
                     FROM public.t0627""")
    assert n[0] == 240 and n[1] > 100 and 60 < n[2] < 180, n      # the outflow and its classes are exercised
    db.val("""UPDATE public.t0627 SET state = state || '{"recall": {"v": 1, "lam": 0.03, "trip_o": 2, "drain": 0.5}}'""")
    moved = db.json("""SELECT jsonb_build_object(
                         'expected', count(*) FILTER (WHERE sc = 0 AND k IS DISTINCT FROM
                                                      public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true)),
                         'sampled', count(*) FILTER (WHERE sc > 0 AND k IS DISTINCT FROM
                                                     public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true)))
                         FROM public.t0627""")
    assert moved["expected"] == 0 and moved["sampled"] >= 20, moved


# ── where an arrival fell in its forecast ─────────────────────────────────────────────────────────────────────────────

def test_0627_where_an_arrival_fell_in_its_forecast(db):
    _through_0627(db)
    got = db.json("SELECT jsonb_agg(public.ottoq_normal_cdf(x / 4.0) ORDER BY x) FROM generate_series(-28, 28) x")
    assert max(abs(g - ND.cdf(x / 4)) for g, x in zip(got, range(-28, 29))) < 1e-7
    assert (_q(db, "SELECT public.ottoq_normal_cdf(NULL)"), _q(db, "SELECT public.ottoq_normal_cdf(40)"),
            _q(db, "SELECT public.ottoq_normal_cdf(-40)")) == (None, 1, 0)
    # the inverse of the normal quantile
    back = db.json("""SELECT jsonb_agg(public.ottoq_normal_cdf(public.ottoq_normal_quantile(p / 100.0)) ORDER BY p)
                        FROM generate_series(1, 99) p""")
    assert max(abs(v - p / 100) for v, p in zip(back, range(1, 100))) < 1e-6

    def z(e, rc, act):
        return _q(db, f"SELECT public.ottoq_inbound_arrival_z({_j(e)}, {_j(rc)}, {_n(act)})")

    e = {"eta": 42, "trip": 2, "esd": 0.1}
    cap = ND.inv_cdf(1 - 1e-9)                                    # 5.998: the probability carries no more digits
    for act in (12, 20, 42, 60, 90):
        zr = math.log((act - 2) / 40) / 0.1
        # without the other calls, 0621's z exactly
        assert abs(z(e, None, act) - zr) < 1e-9 and abs(z(e, {"lam": 0, "trip_o": 4}, act) - zr) < 1e-9, act
        # with them: home by then unless both the reserve and every other call come later, so never later than the
        # reserve alone puts it, and past 6 spreads about 6
        f = 1 - (1 - ND.cdf(zr)) * math.exp(-0.02 * max(act - 4, 0))
        want = ND.inv_cdf(min(max(f, 1e-9), 1 - 1e-9))
        assert abs(z(e, {"lam": 0.02, "trip_o": 4}, act) - want) < 1e-4 and want >= min(zr, cap), (act, want, zr)
    assert abs(z(e, {"lam": 0.02, "trip_o": 4}, 90) - cap) < 1e-6           # 7.9 spreads late, alone: a tail either way
    # a car home before another call's drive could be over is placed by the reserve alone; without trip_o, the
    # reserve's drive is the other call's
    near = {"eta": 6, "trip": 2, "esd": 0.5}
    assert abs(z(near, {"lam": 0.02, "trip_o": 4}, 3) - math.log(1 / 4) / 0.5) < 5e-5
    f = 1 - (1 - ND.cdf(math.log(1 / 4) / 0.5)) * math.exp(-0.02 * 1)
    assert abs(z(near, {"lam": 0.02}, 3) - ND.inv_cdf(f)) < 1e-4
    # nothing to place it in: no spread, due at the drive, no forecast, or home no later than the drive
    for bad in ({"eta": 42, "trip": 2, "esd": 0}, {"eta": 2, "trip": 2, "esd": 0.1}, {"trip": 2, "esd": 0.1}):
        assert z(bad, None, 30) is None, bad
    assert z(e, None, 2) is None and z(e, None, None) is None


# ── the self-review ───────────────────────────────────────────────────────────────────────────────────────────────────

def test_0627_the_review_marks_the_old_orders_arrivals_built(db):
    _through_0627(db)
    inb, real = sr._arrivals(300, 6, 6)
    for k in range(12):
        sr._graded(db, 9600 + k, inbound=inb[26 * k:26 * (k + 1)], real_inbound=real)
    r = sr._review(db)
    t = r["arrival_tails"]
    assert (t["n"], t["early"]["n"], t["late"]["n"]) == (312, 6, 6), t          # no order carried the other calls: 0621's
    a = sr._areas(r)["arrival_spread"]
    sr._plain(a)
    assert (a["kind"], a["part"], a["status"], a["title"]) == \
        ("capability_gap", "arrivals", "built", "A few cars come home far from their forecast"), a
    assert a["finding"].endswith(NOTE) and a["action"] == ACT, a
    assert a["rank"] == len(r["improvement_areas"]) or all(x["status"] == "built" for x in r["improvement_areas"]
                                                           if x["rank"] > a["rank"]), r["improvement_areas"]


def test_0627_the_review_marks_arrivals_built_when_only_the_shapley_split_names_them(db):
    _through_0627(db)
    inb, real = sr._arrivals(120, 0, 0)                           # arrivals the futures sample well: no tails
    for k in range(12):
        sr._graded(db, 9800 + k, inbound=inb[10 * k:10 * (k + 1)], real_inbound=real)
        sr._attribution(db, 9800 + k, {"arrivals": 1.0} if k < 6 else {"faults": 1.0})
    areas = sr._areas(sr._review(db))
    a, f = areas["forecast_arrivals"], areas["forecast_faults"]
    sr._plain(a)
    assert (a["status"], a["impact"], f["status"]) == ("built", 0.5, "open") and a["rank"] > f["rank"], (a, f)
    assert a["finding"].endswith(NOTE) and a["action"] == ACT, a


def test_0627_the_review_places_each_arrival_in_the_forecast_its_order_made(db):
    _through_0627(db)
    rc = {"v": 1, "lam": 0.02, "trip_o": 3, "drain": 0.5, "asd": 0}
    inb, real = [], {}
    for i in range(300):                                          # arrivals as that forecast says they come: each at
        cid = f"car-{i}"                                          # its own quantile of the reserve and the other calls
        inb.append({"id": cid, "src": "forecast", "eta": 42, "trip": 2, "esd": 0.1})
        real[cid] = {"arrived": True, "eta": _mix_time((i + 0.5) / 300, 40, 2, 0.1, 0.02, 3)}
    st = {"ttl_min": 3, "pin_min": 90, "horizon_min": 480, "cars": [], "chargers": []}
    # graded without the other calls (0621's z): the cars called home first read as a tail far early
    _run_sql(db, [_graded(db, 9600 + k, dict(st, inbound=inb[25 * k:25 * (k + 1)]), real) for k in range(12)])
    t0 = sr._review(db)["arrival_tails"]
    assert t0["n"] == 300 and t0["early"]["n"] >= 60, t0
    cut = db.val("SELECT max(graded_at) FROM public.ottoq_charge_order_hindsight")
    # the same arrivals graded on orders that carried them: each falls where the forecast put it
    _run_sql(db, [_graded(db, 9650 + k, dict(st, inbound=inb[25 * k:25 * (k + 1)], recall=rc), real) for k in range(12)])
    r = sr._review(db, since=f"'{cut}'::timestamptz + interval '1 microsecond'")
    t = r["arrival_tails"]
    assert (t["n"], t["early"]["n"], t["late"]["n"], t["in_80pct_band"]) == (300, 0, 0, 0.8), t
    assert abs(t["bulk"]["mean_z"]) < 0.01 and abs(t["bulk"]["sd_z"] - 1) < 0.05, t["bulk"]
    assert not any(a["part"] == "arrivals" for a in r["improvement_areas"]), r["improvement_areas"]


def test_0627_the_reviews_writer_covers_the_arrivals_z(db):
    _through_0627(db)
    inb, real = sr._arrivals(300, 6, 6)
    for k in range(12):
        sr._graded(db, 9600 + k, inbound=inb[26 * k:26 * (k + 1)], real_inbound=real)
    aid = db.val(f"SELECT public.ottoq_arbiter_assess('{DEPOT}', 7)")
    want = db.val("""SELECT md5(pg_get_functiondef('public.ottoq_arbiter_self_assessment(uuid,timestamptz)'::regprocedure)
              || pg_get_functiondef('public.ottoq_arbiter_self_assessment_v3(uuid,timestamptz,boolean)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock_audit_v2(uuid,timestamptz,jsonb)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock_calibration(uuid,timestamptz)'::regprocedure)
              || pg_get_functiondef('public.ottoq_evidence_regime_scan(uuid,timestamptz,jsonb)'::regprocedure)
              || pg_get_functiondef('public.ottoq_review_words(text,text)'::regprocedure)
              || pg_get_functiondef('public.ottoq_inbound_arrival_z(jsonb,jsonb,double precision)'::regprocedure)
              || pg_get_functiondef('public.ottoq_normal_cdf(double precision)'::regprocedure))""")
    assert db.val(f"SELECT code_md5 FROM public.ottoq_arbiter_assessments WHERE assessment_id = {aid}") == want


# ── V1-V3 on d9d49732 in miniature ────────────────────────────────────────────────────────────────────────────────────

LAM, TRIP_O, TRIP_SD = 0.00375, 3.0, 0.148                         # what the fit below learns


def _gate_world(d, follows="rule", orders=10, per=12):
    """d9d49732 in miniature, before 0627: the run (completed, its margin 30); the fit's evidence before its start (80
    reserve returns, their drives 2 minutes, a robust spread of 0.148; 16 calls home on stale telemetry and 8 on a rider's
    flag, a rate of 0.225 an hour of work, a drive of 3 after them); the return model its orders were checked with (home
    at 50%, 0.5% a minute, a drive of 2); 24 cars, half with a reserve of 15; and `orders` graded orders of `per` cars at
    work each, with the recall decision's record of each car's battery at the order. follows='rule': each car came home
    as 0627 forecasts it (its own rung, the other calls, the drive's spread), at an even spread of quantiles; 'old': each
    came home as 0620 forecast it. Returns what each arrival was forecast and when it came."""
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_current, started_at,
                                                 run_by, policy)
              VALUES ('{GATE}', '{DEPOT}', 'completed', 100, '{T}', now() + interval '1 hour', 'operator_demo', 'otto_q')""")
    d.val(f"INSERT INTO public.ottoq_policy_params VALUES ('run', '{GATE}', 'reserve_margin_pct', 30, 'test', now())")
    for trip, n in ((1.8, 20), (2.0, 40), (2.3, 20)):
        arb._returns(d, n, trip_min=trip)
    arb._returns(d, 16, trigger="comms_stale", soc0=90, soc_dec=70, work_min=30, trip_min=3)
    arb._returns(d, 8, trigger="rider_flag_cleaning", soc0=90, soc_dec=60, work_min=40, trip_min=5)
    eid = out._return_model(d, dwell=None, drain_log_sd=0.1)
    cars = [str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0627-gate-{i}")) for i in range(24)]
    reserve = [20 if i % 4 < 2 else 15 for i in range(24)]
    d.val("""INSERT INTO public.vehicles (id, fleet_operator_id, home_depot_id, category, display_name, current_soc,
                                          battery_capacity_kwh, inlet_type, inlet_max_kw, current_state, last_state_change,
                                          min_soc_threshold) VALUES """
          + ", ".join(f"('{v}', '{base.OPERATOR}', '{DEPOT}', 'autonomous', 'G{i}', 60, 75, 'NACS', 250, 'deployed', "
                      f"'{T}', {reserve[i]})" for i, v in enumerate(cars)))
    perm = list(range(orders * per))
    random.Random(627).shuffle(perm)
    rows, sql = [], []
    for k in range(orders):
        inbound, real = [], {}
        for j in range(per):
            i = 2 * j + k % 2
            soc0 = 55 + (7 * k + 11 * j) % 30
            hz_old, hz = (soc0 - 50) / 0.5, max((soc0 - reserve[i] - 30) / 0.5, 0)
            u = (perm[k * per + j] + 0.5) / (orders * per)
            if follows == "rule":
                act = _mix_time(u, hz, 2, math.sqrt(0.01 + (TRIP_SD / max(hz, 0.25)) ** 2), LAM, TRIP_O)
            else:
                act = 2 + hz_old * math.exp(0.1 * ND.inv_cdf(u))
            inbound.append({"id": cars[i], "src": "forecast", "eta": hz_old + 2, "trip": 2, "esd": 0.1, "soc": 49,
                            "g": 51, "imm": False, "w": 0, "md": 30, "ml": 150, "sd": 0, "sl": 0})
            real[cars[i]] = {"arrived": True, "eta": act}
            rows.append({"act": act, "fc": hz_old + 2, "hz_old": hz_old, "hz": hz})
            sql.append(f"""INSERT INTO public.ottoq_recall_decisions (sim_run_id, vehicle_id, depot_id, decided_at_sim,
                                                                      implementation, should_return, inputs, soc_override)
                           VALUES ('{GATE}', '{cars[i]}', '{DEPOT}', '{T}'::timestamptz + interval '{10 * k - 1} minutes',
                                   'naive_threshold_v1', false,
                                   '{{"reserve": {reserve[i]}, "reserve_margin": 30}}', {soc0});""")
        state = {"ttl_min": 0, "pin_min": 90, "horizon_min": 480, "cars": [], "inbound": inbound,
                 "chargers": [{"id": "f", "k": "dcfc", "free": 0}], "models": {"return": eid}}
        sql.append(_graded(d, 9700 + k, state, real, run=GATE, at_min=10 * k))
    _run_sql(d, sql)
    return rows


def _gate_expect(rows):
    """V2's numbers, computed here: each arrival's z on the order's forecast and on 0627's."""
    zo, zn = [], []
    for r in rows:
        zo.append(math.log((r["act"] - 2) / r["hz_old"]) / 0.1)
        esd = math.sqrt(0.01 + (TRIP_SD / max(r["hz"], 0.25)) ** 2)
        f = 1 - (1 - ND.cdf(math.log((r["act"] - 2) / r["hz"]) / esd)) * math.exp(-LAM * max(r["act"] - TRIP_O, 0))
        zn.append(ND.inv_cdf(min(max(f, 1e-9), 1 - 1e-9)))
    n = len(rows)
    return {"n": n, "late": (sum(z > 3 for z in zo), sum(z > 3 for z in zn)),
            "early": (sum(z < -3 for z in zo), sum(z < -3 for z in zn)),
            "mae": (sum(abs(r["act"] - r["fc"]) for r in rows) / n, sum(abs(r["act"] - 2 - r["hz"]) for r in rows) / n),
            "band": (sum(abs(z) <= 1.2816 for z in zo) / n, sum(abs(z) <= 1.2816 for z in zn) / n)}


V2 = re.compile(r"0627 V2: (\d+) forecast arrivals \((\d+) due at the order\): late (\d+) -> (\d+), early (\d+) -> (\d+), "
                r"absolute error ([\d.]+) -> ([\d.]+) minutes, inside the 80% band ([\d.]+) -> ([\d.]+); the tails left: (.*)")


def test_0627_v1_to_v3_on_d9d49732_in_miniature_the_gate_passes_on_a_world_the_rule_describes(db):
    sr._through_0626(db)
    rows = _gate_world(db, "rule")
    want = _gate_expect(rows)
    err = _apply(db)
    assert "0627 V1: 20 stored simulations and comparisons (10 snapshots x 2 futures) unchanged" in err, err
    assert "0627 V1: 120 graded arrivals of the 21 days, each z as 0621's" in err, err
    assert ("0627 V1: the fit through d9d49732's start keeps 0624's 18 keys and adds the drives: trip_sd 0.148 min, "
            "other 3.00 (p90 5.00) min, other calls comms_stale 16/0.1500, rider_flag_cleaning 8/0.0750") in err, err
    m = V2.search(err)
    assert m, err
    g = [int(x) for x in m.groups()[:6]] + [float(x) for x in m.groups()[6:10]]
    assert g[:6] == [120, 0, *want["late"], *want["early"]], (g, want)
    assert abs(g[6] - want["mae"][0]) < 0.0015 and abs(g[7] - want["mae"][1]) < 0.0015, (g, want)
    assert abs(g[8] - want["band"][0]) < 0.0015 and g[9] == 0.8, (g, want)
    assert m.group(11) == "none", m.group(11)
    # the world was built for the rule to matter: the late tail of the reserve-15 cars and the early calls are there
    assert want["late"][0] >= 10 and want["early"][0] >= 5 and want["mae"][1] < want["mae"][0], want
    assert "0627 V3: the rung equals the recall decision's own record on 50 of 50 decisions, across 1 runs" in err, err
    assert re.search(r"0627 V3: return_v1 estimate \d+ \(usable true\): drive spread 0\.148 min, after another call 3\.00 "
                     r"min \(p90 5\.00\), other calls 0\.2250 an hour", err), err
    assert re.search(r"0627 V3 on running run a0000000-0000-0000-0000-000000000614: state \d+ ms, recall \{.*\"lam\": "
                     r"0\.003750.*\}, forecast cars with a rung 0 of 0", err), err


def test_0627_the_gate_holds_back_on_a_world_the_rule_does_not_describe(db):
    sr._through_0626(db)
    rows = _gate_world(db, "old")
    want = _gate_expect(rows)
    rc, err = db.file(M0627)
    m = re.search(r"0627 V2: the gate holds back: late (\d+) -> (\d+), early (\d+) -> (\d+), error ([\d.]+) -> ([\d.]+), "
                  r"band ([\d.]+)", err)
    assert rc != 0 and m, err
    assert [int(x) for x in m.groups()[:4]] == [*want["late"], *want["early"]], (m.groups(), want)
    assert abs(float(m.group(5)) - want["mae"][0]) < 0.0015 and abs(float(m.group(6)) - want["mae"][1]) < 0.0015
    assert abs(float(m.group(7)) - want["band"][1]) < 0.0015, (m.groups(), want)
    # what holds it back is the error: cars that came home at the one reserve the returns show put the rule's forecast
    # ten minutes late on every reserve-15 car. The tails cannot here: the other calls home explain each early arrival,
    # and no car came home later than the rule forecast it
    assert want["late"] == (0, 0) and want["early"] == (0, 0) and want["mae"][1] > 1.5 * want["mae"][0], want
    assert db.val("SELECT to_regprocedure('public.ottoq_recall_threshold_soc(uuid,uuid,timestamptz)') IS NULL") == "t"


def test_0627_v3_holds_the_rung_to_the_recall_decisions_own_record(db):
    sr._through_0626(db)
    x = _vid("X")
    db.val(f"""INSERT INTO public.ottoq_recall_decisions (sim_run_id, vehicle_id, depot_id, decided_at_sim, implementation,
                                                          should_return, inputs, soc_override)
               VALUES ('{RUN}', '{x}', '{DEPOT}', '{T}', 'naive_threshold_v1', true,
                       '{{"reserve": 20, "reserve_margin": 15}}', 34),
                      ('{RUN}', '{x}', '{DEPOT}', '{T}'::timestamptz - interval '1 minute', 'naive_threshold_v1', false,
                       '{{"reserve": 20, "reserve_margin": 30}}', 60)""")
    rc, err = db.file(M0627)
    assert rc != 0 and "0627 V3: the rung differs from the recall decision's own record on 1 of 2 decisions" in err, err
