"""db/migrations/0623, EXECUTED: the check sees cars leave and come back.

WHY THIS EXISTS. The first morning self-review (0621/0622) named the depot's own outflow as the check's largest blind
spot: every car that came home inside an order's window unseen had left the depot after the order. 0623 gives the
check's simulator departures (the learned dwell after a charge), the time out (the learned drain to the reserve, or
another call home first) and the return owing a charge, and compares each car over its visit now and its next. Every
claim in its header that a test can execute is executed here, on the scratch PostgreSQL and the miniature depot of
tests/test_agent_charge_order_sql.py (two fast chargers, three L2, six cars), through 0619-0622 as
tests/test_agent_arbiter_sql.py applies them:

  - it applies, its checks run, its dial is a person's, its grants keep the readers of the ledgers to the service role;
  - without an outflow block the schedule and the comparison return 0622's results, key for key, on random lines, and
    a stored order reads and grades as it did;
  - the draws are pure and the dwell grid reads both ways;
  - one car's departure and return, its real durations kept, the cut respected, a car past the evidence staying;
  - the fit learns the dwell by Kaplan-Meier with the parked cars censored, from fine-tick runs when they hold 30;
  - the state carries the outflow and the dial takes it away;
  - the schedule sends cars out and brings them back, a fault undoes a departure, a return past the horizon owes its
    charge, and the comparison counts each car over both visits;
  - hindsight reads who left and came back, and the grade grades the outflow forecast.

It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import math
import os
import random
import subprocess
import sys
import tempfile
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622 and their helpers)

ROOT = base.ROOT
M0623 = os.path.join(ROOT, "db", "migrations", "0623_the_check_sees_cars_leave_and_come_back.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_vid, _dial, _order, _file = base._vid, base._dial, base._order, arb._file

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

# the dwell grid return_v1 fitted on the twin depot through d9d49732's start (0623 §1): 0, 0.05, ..., 0.95
Q = [0.00, 0.00, 0.16, 0.35, 0.39, 0.45, 0.54, 0.83, 1.12, 3.60, 7.28, 11.18, 16.36, 21.33, 27.99, 37.68, 57.91,
     88.23, 144.49, 251.12]
FMAX, MAX = 0.964, 390.64
DWELL = {"q": Q, "f_max": FMAX, "max_min": MAX, "median_min": 7.28, "n": 100, "left": 90, "censored": 10,
         "population": "fine_ticks"}
QSQL = "ARRAY[" + ", ".join(str(x) for x in Q) + "]::float8[]"


@pytest.fixture()
def db():
    name = f"ottoq_out_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        for path in (base.STUB, arb.ARB_STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        base._world(d)
        base._through_0618(d)
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _apply(d):
    return _file(d, M0623)


def _through_0623(d):
    arb._through_0622(d)
    return _apply(d)


def _return_model(d, dwell=DWELL, **params):
    """A usable return_v1 for the depot: called home at 50%, 0.5% a minute, a 2-minute drive, and the dwell grid."""
    p = {"threshold_soc": 50, "drain_pct_per_min": 0.5, "drain_log_sd": 0.2, "trip_min": 2, "other_share": 0.1,
         "other_per_work_hour": 0}
    p.update(params)
    if dwell is not None:
        p["dwell"] = dwell
    return int(d.val(f"""INSERT INTO public.ottoq_learned_estimates (depot_id, model, n_evidence, n_runs, usable, params,
                                                                     code_md5, note)
                         VALUES ('{DEPOT}', 'return_v1', 100, 5, true, $j${json.dumps(p)}$j$::jsonb, 'test', 'test')
                         RETURNING estimate_id"""))


def _j(x):
    return "NULL" if x is None else f"$j${json.dumps(x)}$j$::jsonb"


def _n(x):
    return "NULL" if x is None else repr(float(x))


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0623_applies_and_its_checks_run(db):
    arb._through_0622(db)
    md5_before = db.val("SELECT public.ottoq_hindsight_code_md5()")
    err = _apply(db)
    assert ("0623 V1: 0 stored simulations and comparisons (0 snapshots x 2 futures) and 0 graded orders read as "
            "before") in err, err
    assert "0623 V2: run d9d49732 is not here" in err, err
    assert "0623 V3: return_v1 estimate" in err and "dwell from 0 charges (0 left, 0 still parked)" in err, err
    assert "0623 V3 on running run a0000000-0000-0000-0000-000000000614" in err and "outflow <NULL>" in err, err
    dial = db.json("""SELECT jsonb_build_array(min_value, max_value, default_value, agent_writable)
                        FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_outflow'""")
    assert dial == [0, 1, 1, False], dial
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0623_%'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0623_pre'") == "8"
    priv = db.json("""SELECT jsonb_build_object(
        'uniform', has_function_privilege('anon', 'public.ottoq_hash_uniform(text)', 'EXECUTE'),
        'normal', has_function_privilege('anon', 'public.ottoq_normal_quantile(double precision)', 'EXECUTE'),
        'errors', has_function_privilege('anon', 'public.ottoq_charge_order_forecast_errors(jsonb,jsonb,jsonb)', 'EXECUTE'),
        'params', has_function_privilege('anon', 'public.ottoq_return_model_params(uuid,timestamptz,interval)', 'EXECUTE'),
        'outflow', has_function_privilege('authenticated',
                     'public.ottoq_charge_line_outflow(uuid,uuid,timestamptz,jsonb,jsonb,jsonb,jsonb)', 'EXECUTE'),
        'outflow_service', has_function_privilege('service_role',
                     'public.ottoq_charge_line_outflow(uuid,uuid,timestamptz,jsonb,jsonb,jsonb,jsonb)', 'EXECUTE'))""")
    assert priv == {"uniform": True, "normal": True, "errors": True, "params": False, "outflow": False,
                    "outflow_service": True}, priv
    # the grader's md5 now covers the outflow's code
    assert db.val("SELECT public.ottoq_hindsight_code_md5()") not in ("", md5_before)


def test_0623_refuses_a_schedule_it_was_not_written_against(db):
    arb._through_0622(db)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_charge_line_schedule(p_state jsonb, p_order jsonb, p_scenario integer,
                p_seed text, p_trace boolean) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$ SELECT '{}'::jsonb $f$""")
    rc, err = db.file(M0623)
    assert rc != 0 and "0623 P1" in err and "the schedule" in err, err


# ── without an outflow, nothing moves ─────────────────────────────────────────────────────────────────────────────────

def test_0623_without_an_outflow_the_schedule_and_the_comparison_are_0622s_on_random_lines(db):
    rng = random.Random(623)
    cases = [arb._rand_case(rng, i) for i in range(120)]
    arb._through_0622(db)
    db.val("CREATE TABLE public.t0623 (i int, sc int, state jsonb, ord jsonb, k jsonb, c jsonb)")
    rows = ", ".join(f"({i}, {sc}, $j${json.dumps(st)}$j$::jsonb, {_j(o)}, NULL, NULL)"
                     for i, (st, o) in enumerate(cases) for sc in (0, 1, 2))
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as fh:
        fh.write(f"INSERT INTO public.t0623 VALUES {rows};\n")
    try:
        _file(db, fh.name)
    finally:
        os.unlink(fh.name)
    db.val("""UPDATE public.t0623 SET k = public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true),
                                      c = public.ottoq_charge_line_compare(
                                            public.ottoq_charge_line_simulate(state, NULL, sc, 'rand'),
                                            public.ottoq_charge_line_simulate(state, ord, sc, 'rand'))""")
    _apply(db)
    bad = db.json("""SELECT COALESCE(jsonb_agg(jsonb_build_object('i', i, 'sc', sc)), '[]'::jsonb) FROM public.t0623
                      WHERE k IS DISTINCT FROM public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true)
                         OR c IS DISTINCT FROM public.ottoq_charge_line_compare(
                                                 public.ottoq_charge_line_simulate(state, NULL, sc, 'rand'),
                                                 public.ottoq_charge_line_simulate(state, ord, sc, 'rand'))""")
    assert bad == [], bad[:5]
    assert db.val("SELECT count(*) FROM public.t0623") == "360"


def test_0623_a_stored_order_without_an_outflow_reads_and_grades_as_before(db):
    oid = arb._a_morning(db)                                   # 0619-0621, a return_v1 with no dwell: no outflow
    _file(db, arb.M0622)
    snap = db.json(f"SELECT state FROM public.ottoq_charge_order_snapshots WHERE order_id = {oid}")
    assert "outflow" not in snap
    before = db.json(f"SELECT public.ottoq_charge_order_realized({oid}, 90)")
    err = _apply(db)
    assert "0623 V1: 2 stored simulations and comparisons (1 snapshots x 2 futures)" in err, err
    after = db.json(f"SELECT public.ottoq_charge_order_realized({oid}, 90)")
    assert after == before and "returns" not in after
    exp = db.json(f"SELECT public.ottoq_charge_line_schedule(state, NULL, 0, seed, true) FROM "
                  f"public.ottoq_charge_order_snapshots WHERE order_id = {oid}")
    fe2 = db.json(f"SELECT public.ottoq_charge_order_forecast_errors($j${json.dumps(snap)}$j$::jsonb, "
                  f"$j${json.dumps(after)}$j$::jsonb)")
    fe3 = db.json(f"SELECT public.ottoq_charge_order_forecast_errors($j${json.dumps(snap)}$j$::jsonb, "
                  f"$j${json.dumps(after)}$j$::jsonb, $j${json.dumps(exp)}$j$::jsonb)")
    assert fe3 == fe2 and "outflow" not in fe3
    g = db.json(f"SELECT public.ottoq_charge_order_grade({oid}, 90)")
    assert g["order_id"] == oid and "outflow" not in g["forecast"], g["forecast"]


# ── the draws ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0623_the_draws_are_pure_and_read_the_dwell_both_ways(db):
    _through_0623(db)
    u = db.json("""SELECT jsonb_build_object('a', public.ottoq_hash_uniform('k'), 'b', public.ottoq_hash_uniform('k'),
                                             'min', min(x), 'max', max(x), 'mean', avg(x))
                     FROM (SELECT public.ottoq_hash_uniform('key' || g) AS x FROM generate_series(1, 4000) g) s""")
    assert u["a"] == u["b"] and 0 < u["min"] < 0.01 and 0.99 < u["max"] < 1 and abs(u["mean"] - 0.5) < 0.02, u
    nq = db.json("""SELECT jsonb_build_array(public.ottoq_normal_quantile(0.5), public.ottoq_normal_quantile(0.975),
                                             public.ottoq_normal_quantile(0.001), public.ottoq_normal_quantile(0),
                                             public.ottoq_normal_quantile(1))""")
    assert nq[0] == 0 and abs(nq[1] - 1.959963985) < 1e-6 and abs(nq[2] + 3.090232306) < 1e-6 and nq[3:] == [None, None]
    # probability -> minutes -> probability, off the point mass at 0
    us = [round(0.10 + 0.05 * k, 2) for k in range(18)] + [0.955, 0.96]
    rt = db.json(f"""SELECT jsonb_agg(jsonb_build_array(u, public.ottoq_outflow_dwell_cdf(q, {FMAX}, {MAX},
                                         public.ottoq_outflow_dwell_quantile(q, {FMAX}, {MAX}, u))) ORDER BY u)
                       FROM (SELECT {QSQL} AS q) g, unnest(ARRAY{us}::float8[]) u""")
    for p, back in rt:
        assert abs(back - p) < 1e-9, (p, back)
    # minutes -> probability -> minutes, off the ties
    ts = [0.2, 2.0, 5.0, 9.0, 30.0, 100.0, 300.0]
    tr = db.json(f"""SELECT jsonb_agg(jsonb_build_array(t, public.ottoq_outflow_dwell_quantile(q, {FMAX}, {MAX},
                                         public.ottoq_outflow_dwell_cdf(q, {FMAX}, {MAX}, t))) ORDER BY t)
                       FROM (SELECT {QSQL} AS q) g, unnest(ARRAY{ts}::float8[]) t""")
    for t, back in tr:
        assert abs(back - t) < 1e-6, (t, back)
    pts = db.json(f"""SELECT jsonb_build_object(
                         'median', public.ottoq_outflow_dwell_quantile({QSQL}, {FMAX}, {MAX}, 0.5),
                         'at_fmax', public.ottoq_outflow_dwell_quantile({QSQL}, {FMAX}, {MAX}, {FMAX}),
                         'past', public.ottoq_outflow_dwell_quantile({QSQL}, {FMAX}, {MAX}, 0.99),
                         'f_median', public.ottoq_outflow_dwell_cdf({QSQL}, {FMAX}, {MAX}, 7.28),
                         'f_zero', public.ottoq_outflow_dwell_cdf({QSQL}, {FMAX}, {MAX}, 0),
                         'f_last', public.ottoq_outflow_dwell_cdf({QSQL}, {FMAX}, {MAX}, {MAX}),
                         'f_after', public.ottoq_outflow_dwell_cdf({QSQL}, {FMAX}, {MAX}, 1000))""")
    assert pts == {"median": 7.28, "at_fmax": None, "past": None, "f_median": 0.5, "f_zero": 0, "f_last": FMAX,
                   "f_after": FMAX}, pts


def _draw(d, ready, e, sdep, scenario=0, ud=0.5, uo=None, zd=0, real=None, cut=None, lam=0, q=None, fmax=FMAX,
          mx=MAX, seed="s", car="c1"):
    qs = QSQL if q is None else "ARRAY[" + ", ".join(str(x) for x in q) + "]::float8[]"
    return d.json(f"""SELECT COALESCE(to_jsonb(public.ottoq_charge_line_return_draw(
                         ARRAY[50, 0.5, 0.2, 2, {lam}, {fmax}, {mx}]::float8[], {qs},
                         ARRAY[100, 49, 30, 200, 0.1, 0.1]::float8[], {_n(ready)}, {_n(e)}, {_n(sdep)}, {scenario},
                         '{seed}', '{car}', {_n(ud)}, {_n(uo)}, {_n(zd)}, {_j(real)}, {_n(cut)})), 'null'::jsonb)""")


def test_0623_one_cars_departure_and_return(db):
    _through_0623(db)
    # a car parked 10 minutes leaves after its dwell past those 10, works 100 minutes to the reserve, drives 2
    r = _draw(db, 0, 10, 100)
    dep, eta, soc, md, ml = r
    assert dep > 0 and abs(eta - dep - 102) < 1e-9 and soc == 49 and md == 30 and ml == 200, r
    f10 = float(db.val(f"SELECT public.ottoq_outflow_dwell_cdf({QSQL}, {FMAX}, {MAX}, 10)"))
    want = float(db.val(f"SELECT public.ottoq_outflow_dwell_quantile({QSQL}, {FMAX}, {MAX}, {f10} + 0.5 * (1 - {f10}))"))
    assert abs(dep - (want - 10)) < 1e-9, (dep, want)
    # the drain at one spread faster: exp(0.2) times, so 50 points take 81.9 minutes
    r1 = _draw(db, 0, 10, 100, zd=1)
    assert abs(r1[1] - r1[0] - (50 / (0.5 * math.exp(0.2)) + 2)) < 1e-9 and r1[0] == dep, r1
    # a sampled future draws each by the car's own hash: the same every time, and not the expected future's
    s1, s2 = _draw(db, 0, 10, 100, scenario=3, ud=None, zd=None), _draw(db, 0, 10, 100, scenario=3, ud=None, zd=None)
    assert s1 == s2 and s1 != _draw(db, 0, 10, 100, scenario=3, ud=None, zd=None, car="c2")
    # another call home first: at 0.01 a minute, half of all cars are called within ln 2 / 0.01 minutes
    r2 = _draw(db, 0, 10, 100, lam=0.01, uo=0.5)
    assert abs(r2[1] - r2[0] - (math.log(2) / 0.01 + 2)) < 1e-6, r2
    # what happened, kept as durations: it really left 14 minutes after its charge ended and was out 66
    rr = _draw(db, 0, 10, 100, real={"ce": -10, "left": 4, "eta": 70, "soc": 52})
    assert rr[:3] == [4, 70, 52] and abs(rr[3] - 30 * 48 / 51) < 1e-9, rr
    # a car charging now whose charge really ended at 20 and left at 23: 3 minutes after the charge the check modelled
    rc = _draw(db, 25, 0, None, real={"ce": 20, "left": 23}, cut=90)
    assert rc[0] == 28 and abs(rc[1] - 130) < 1e-9, rc
    # not gone by the cut: it stayed at least until the cut
    assert _draw(db, 0, 10, 100, real={"ce": -10}, cut=90)[0] >= 90
    # gone and not back by the cut: out at least until the cut
    rg = _draw(db, 0, 10, 60, real={"ce": -10, "left": 20}, cut=90)
    assert rg[0] == 20 and rg[1] == 90, rg
    # parked past every departure the evidence saw: it stays
    assert _draw(db, 0, 400, 100) is None


# ── the fit ───────────────────────────────────────────────────────────────────────────────────────────────────────────

def _charged_and_left(d, run, n, end_min, left_after, tag):
    """n completed charges ending at T + end_min, each car leaving left_after minutes later (None: never)."""
    for k in range(n):
        vid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0623-{tag}-{k}"))
        sid = str(uuid.uuid4())
        d.val(f"""INSERT INTO public.ocpp_sessions (id, depot_id, stall_id, vehicle_id, charge_point_id, transaction_id,
                                                    evse_id, connector_id, status, started_at, ended_at, soc_start,
                                                    soc_end, stopped_reason, sim_run_id)
                  VALUES ('{sid}', '{DEPOT}', '{_vid('L1')}', '{vid}', 'L1', '{sid}', 1, 1, 'completed',
                          '{T}'::timestamptz + interval '{end_min - 30} minutes',
                          '{T}'::timestamptz + interval '{end_min} minutes', 40, 100, 'completed', '{run}')""")
        if left_after is not None:
            d.val(f"""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at,
                                                                   scheduled_return_at, planned_duration_min, status)
                      VALUES ('{vid}', '{run}', '{T}'::timestamptz + interval '{end_min + left_after} minutes',
                              '{T}'::timestamptz + interval '{end_min + left_after + 60} minutes', 60, 'active')""")


def test_0623_the_fit_learns_the_dwell_with_the_parked_cars_censored(db):
    _through_0623(db)
    # the run's clock is at T: twelve cars leave at once, ten after 5 minutes, nine after 20, nine are still parked
    for n, left, tag in ((12, 0, "a"), (10, 5, "b"), (9, 20, "c"), (9, None, "d")):
        _charged_and_left(db, RUN, n, -120, left, tag)
    dw = db.json(f"SELECT public.ottoq_return_model_params('{DEPOT}', now(), interval '21 days') -> 'dwell'")
    # Kaplan-Meier: 12 of 40 go at 0 (0.30), 10 of the 28 left at 5 (0.55), 9 of the 18 left at 20 (0.775); the nine
    # parked never count as leaving, so the curve stops at 0.775
    assert (dw["n"], dw["left"], dw["censored"], dw["f_max"], dw["max_min"], dw["median_min"], dw["population"]) == \
        (40, 31, 9, 0.775, 20, 5, "all_ticks"), dw
    assert dw["q"] == [0] * 7 + [5] * 5 + [20] * 4 + [None] * 4, dw["q"]
    # a fine-tick run (a minute a tick) with 30 departures is the population once it holds them
    fine = "a0000000-0000-0000-0000-000000000623"
    db.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_start,
                                                  sim_clock_current, started_at, run_by, policy)
               VALUES ('{fine}', '{DEPOT}', 'completed', 100, '{T}'::timestamptz - interval '100 minutes', '{T}', now(),
                       'operator_demo', 'otto_q')""")
    _charged_and_left(db, fine, 30, -50, 1, "f")
    dw = db.json(f"SELECT public.ottoq_return_model_params('{DEPOT}', now(), interval '21 days') -> 'dwell'")
    assert (dw["n"], dw["left"], dw["f_max"], dw["median_min"], dw["population"]) == (30, 30, 1, 1, "fine_ticks"), dw
    # the nightly fit writes it beside 0619's keys
    eid = db.val(f"SELECT public.ottoq_fit_return_model('{DEPOT}', NULL, interval '21 days', 'test')")
    est = db.json(f"SELECT public.ottoq_learned_estimate('{DEPOT}', 'return_v1')")
    assert str(est["estimate_id"]) == eid and est["params"]["dwell"] == dw and "threshold_soc" in est["params"], est


# ── the state ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def _parked_and_charging(d):
    """L, charged to 100% and parked since 12 minutes before T; Y charging on L3 since 30 minutes before T."""
    for name, soc, state in (("L", 100, "charge_complete_holding"), ("Y", 60, "charging_l2")):
        base._car(d, name, soc, 0, state=state)
        d.val(f"DELETE FROM public.ottoq_visit_needs WHERE vehicle_id = '{_vid(name)}'")
    arb._session(d, "L", "L1", -60, -12, soc_start=40)
    d.val(f"UPDATE public.ocpp_sessions SET soc_end = 100 WHERE vehicle_id = '{_vid('L')}'")
    d.val(f"UPDATE public.stalls SET current_vehicle_id = '{_vid('Y')}' WHERE stall_code = 'L3'")
    arb._session(d, "Y", "L3", -30, None, status="active", soc_start=60)


def test_0623_the_state_carries_the_outflow_and_the_dial_takes_it_away(db):
    _through_0623(db)
    _parked_and_charging(db)
    # no usable return model with a dwell: the state is 0622's
    assert "outflow" not in arb._state(db)
    _return_model(db, dwell=None)
    assert "outflow" not in arb._state(db)
    eid = _return_model(db)
    s = arb._state(db)
    o = s["outflow"]
    assert (o["v"], o["return_model"], o["window_min"], o["thr"], o["drain"], o["trip"], o["lam"]) == \
        (1, eid, 90, 50, 0.5, 2, 0), o
    assert o["dwell"] == {"q": Q, "f_max": FMAX, "max_min": MAX, "median_min": 7.28}, o["dwell"]
    assert o["leaving"] == [{"id": _vid("L"), "e": 12, "sdep": 100}], o["leaving"]
    busy = [c for c in s["chargers"] if c.get("car")]
    assert [(c["id"], c["car"]) for c in busy] == [(_vid("L3"), _vid("Y"))], s["chargers"]
    line = {c["id"] for c in s["cars"]}
    assert set(o["ret"]) == line | {_vid("L"), _vid("Y")}, sorted(o["ret"])
    rl = o["ret"][_vid("L")]
    assert (rl["tg"], float(rl["rs"]), rl["dok"], rl["lok"]) == (100, 49, True, True), rl
    assert 0 < float(rl["rmd"]) < float(rl["rml"]), rl
    # the run's dial at 0: 0622's check exactly
    _dial(db, "agent_charge_order_outflow", 0)
    s0 = arb._state(db)
    assert "outflow" not in s0 and not any(c.get("car") for c in s0["chargers"])
    assert {k: v for k, v in s.items() if k not in ("outflow", "chargers")} == \
        {k: v for k, v in s0.items() if k not in ("outflow", "chargers")}


# ── the schedule and the comparison ───────────────────────────────────────────────────────────────────────────────────

RET = {"tg": 100, "rs": 49, "rmd": 30, "rml": 150, "rsd": 0, "rsl": 0, "dok": True, "lok": True}


def _out_state(horizon=480, dn=None):
    """One car in the line at 30% (40 minutes on the fast charger), Y on the L2 until minute 10, L parked 5 minutes. A
    charged car leaves 5 minutes after its charge (every quantile is 5), works 100 minutes to the reserve and drives 2."""
    f = {"id": "f", "k": "dcfc", "free": 0}
    if dn is not None:
        f["dn"] = dn
    return {"ttl_min": 0, "pin_min": 90, "horizon_min": horizon,
            "cars": [{"id": "a", "w": 0, "g": 70, "imm": False, "soc": 30, "due": None, "md": 40, "ml": 200}],
            "inbound": [],
            "chargers": [f, {"id": "l3", "k": "l2", "free": 10, "car": "y"}],
            "outflow": {"v": 1, "window_min": 90, "thr": 50, "drain": 0.5, "dsd": 0, "trip": 2, "lam": 0,
                        "dwell": {"q": [5] * 20, "f_max": 1, "max_min": 5, "median_min": 5},
                        "ret": {"a": RET, "y": RET, "l": RET}, "leaving": [{"id": "l", "e": 5, "sdep": 100}]}}


def test_0623_the_schedule_sends_cars_out_and_brings_them_back(db):
    _through_0623(db)
    r = arb._sched(db, _out_state())
    seats = {x["id"]: x for x in r["return_seats"]}
    # L leaves now and is back at 102; Y leaves at 15, back at 117; A, charged at 40, leaves at 45, back at 147. Each
    # comes back at 49% owing 51 points: L takes the free L2 (102-252), Y the fast charger (117-147), A then the fast
    # charger again (147-177)
    assert {k: (v["dep"], v["a"], v["soc"], v["k0"], v["s0"], v["r"], v["past"]) for k, v in seats.items()} == {
        "l": (0, 102, 49, "l2", 102, 252, False), "y": (15, 117, 49, "dcfc", 117, 147, False),
        "a": (45, 147, 49, "dcfc", 147, 177, False)}, seats
    assert (r["returns"], r["returns_past_horizon"], r["returns_seated"], r["stays"], r["window_min"]) == \
        (3, 0, 3, 0, 90), r
    # each car over both visits: A's first charge (40), then each return from its arrival to ready (150, 30, 30)
    assert (float(r["flow_sum"]), float(r["flow2_sum"])) == (40, 250), r
    # minutes out inside the window: L 90, Y 75, A 45
    assert float(r["out_min"]) == 210, r
    # past the horizon a return owes its charge and never waits: A is back at 147 > 120
    h = arb._sched(db, _out_state(horizon=120))
    hs = {x["id"]: x for x in h["return_seats"]}
    assert (h["returns"], h["returns_past_horizon"]) == (3, 1) and hs["a"]["past"] is True and hs["a"]["r"] is None, hs
    # the fast charger fails at 20 while A is on it: A's departure is undone, it finishes on the L2 (half its charge,
    # 100 minutes, 20-120), and only then leaves (125) and comes back (227)
    fl = arb._sched(db, _out_state(dn=[[20, 60]]))
    fs = {x["id"]: x for x in fl["return_seats"]}
    assert (fs["a"]["dep"], fs["a"]["a"], fl["returns"]) == (125, 227, 3), fs
    first = {x["id"]: x for x in fl["seats"]}["a"]
    assert (first["k0"], first["k"], first["r"], first["x"]) == ("dcfc", "l2", 120, 1), first


def test_0623_the_comparison_counts_each_car_over_two_visits(db):
    _through_0623(db)

    def cmp(k, a):
        return db.json(f"SELECT public.ottoq_charge_line_compare({_j(k)}, {_j(a)})")
    k = {"on_time": 0, "late_sum": 0, "flow_sum": 100, "flow2_sum": 300, "out_min": 50}
    a = {"on_time": 0, "late_sum": 0, "flow_sum": 90, "flow2_sum": 310, "out_min": 60}
    # faster now, slower over both visits: the agent's order loses on flow
    assert cmp(k, a) == {"cmp": -1, "by": "flow", "d_on_time": 0, "d_late": 0, "d_flow": 10, "d_flow1": -10,
                         "d_out": 10}
    # a side without both visits is compared as 0620 compared it
    assert cmp({x: v for x, v in k.items() if x != "flow2_sum"}, a) == \
        {"cmp": 1, "by": "flow", "d_on_time": 0, "d_late": 0, "d_flow": -10}
    # on time still comes first (rule 9)
    assert cmp(k, dict(a, on_time=1))["cmp"] == 1 and cmp(k, dict(a, on_time=1))["by"] == "on_time"


# ── hindsight ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0623_hindsight_reads_who_left_and_came_back_and_grades_the_forecast(db):
    _through_0623(db)
    _parked_and_charging(db)
    _return_model(db)
    rec = _order(db, [("C", "dcfc")])
    assert rec["ok"] and rec["order_id"], rec
    oid = rec["order_id"]
    snap = db.json(f"""SELECT jsonb_build_object('state', state, 'seed', seed, 'agent_order', agent_order)
                         FROM public.ottoq_charge_order_snapshots WHERE order_id = {oid}""")
    assert snap["state"]["outflow"]["leaving"][0]["id"] == _vid("L"), snap["state"]["outflow"]
    # after the order: L leaves at 4 and is back at 70 with 52%; Y finishes at 20, leaves at 25 and is not back by
    # the cut; the run's clock reaches minute 100, so the window is 90
    d_l, d_y = _vid("L"), _vid("Y")
    db.val(f"""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                            planned_duration_min, status, actual_return_at, soc_at_return_pct)
               VALUES ('{d_l}', '{RUN}', '{T}'::timestamptz + interval '4 minutes', '{T}'::timestamptz + interval '70 minutes',
                       66, 'returned', '{T}'::timestamptz + interval '70 minutes', 52),
                      ('{d_y}', '{RUN}', '{T}'::timestamptz + interval '25 minutes', '{T}'::timestamptz + interval '140 minutes',
                       115, 'active', NULL, NULL)""")
    db.val(f"""UPDATE public.ocpp_sessions SET status = 'completed', stopped_reason = 'completed', soc_end = 100,
                      ended_at = '{T}'::timestamptz + interval '20 minutes' WHERE vehicle_id = '{d_y}'""")
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_current = '{T}'::timestamptz + interval '100 minutes' "
           f"WHERE sim_run_id = '{RUN}'")
    real = db.json(f"SELECT public.ottoq_charge_order_realized({oid}, 90)")
    assert real["returns"][d_l] == {"ce": -12, "left": 4, "eta": 70, "soc": 52}, real["returns"][d_l]
    assert real["returns"][d_y] == {"ce": 20, "left": 25}, real["returns"][d_y]
    assert not ({d_l, d_y} & {x["id"] for x in real["appeared"]}), real["appeared"]
    # the outflow forecast against it: two dwells seen and both gone, L's 16 minutes past the 12 it had been parked
    exp = db.json(f"SELECT public.ottoq_charge_line_schedule(state, NULL, 0, seed, true) "
                  f"FROM public.ottoq_charge_order_snapshots WHERE order_id = {oid}")
    fe = db.json(f"SELECT public.ottoq_charge_order_forecast_errors({_j(snap['state'])}, {_j(real)}, {_j(exp)})")
    o = fe["outflow"]
    assert (o["dwell"]["seen"], o["dwell"]["left"], o["dwell"]["pit_n"], o["real"]) == (2, 2, 2, 1), o
    assert 0 < float(o["dwell"]["p_left"]) < 2 and 0 <= float(o["dwell"]["pit_sum"]) <= 2, o["dwell"]
    # realize puts what happened in the outflow's place for the appeared part
    full = db.json(f"""SELECT public.ottoq_charge_line_realize({_j(snap['state'])}, {_j(real)},
                                                                ARRAY['appeared'])""")
    assert full["outflow"]["real"] == real["returns"] and full["outflow"]["cut"] == 90, full["outflow"].keys()
    # the grade passes the expected future of the order that ran and keeps the outflow's errors
    g = db.json(f"SELECT public.ottoq_charge_order_grade({oid}, 90)")
    assert g["order_id"] == oid and g["forecast"]["outflow"]["dwell"]["seen"] == 2, g["forecast"]
    assert "return_seats" not in g["expected"] and "return_seats" not in g["hindsight"], g["expected"].keys()
