"""db/migrations/0634, EXECUTED: a car's drain is timed only from a dispatch the depot saw begin.

WHY THIS EXISTS. The return fit learns each class's drain from its reserve returns: the battery a car left with, the
battery at its recall, over the minutes between. A run's first cars are already at work when it starts; the twin primes
them with a dispatch back-dated part of the way into its trip and sets their battery at the start, so their drain counted
the back-dated minutes as driving and came out slow, and the futures brought cars home early (G371). 0634 times a drain
only from a dispatch that began at or after its run's start, counts work from the later of the two, marks the fit
forecast_v 2, and the arrival spread reads the orders of the newest forecast once they alone are usable. Every claim in
its header that a test can execute is executed here, on the scratch PostgreSQL and the miniature depot of
tests/test_agent_charge_order_sql.py, through 0619-0633 as tests/test_agent_arrival_spread_sql.py applies them:
  - it applies, its checks run, and it refuses an engine before 0633, a body it was not written against and a run
    running;
  - the fit: a reserve return that began before its run's start times no drain, its class's level and the depot's are
    the seen returns' alone, n_primed counts it, and other calls home are per hour of work the depot saw;
  - with no car out before its run, every key is 0633's;
  - the arrival spread reads the newest forecast's orders once they alone are usable, and every order until then;
  - the gate, on a run whose cars drained as the seen returns say, passes and says by how much; on one whose cars
    drained as the back-dated returns said, it holds back;
  - the self-review: orders made before forecast_v 2 are history for the arrivals once the depot's model has it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import math
import os
import re
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622)
import test_agent_air_clock_sql as ac  # noqa: E402  (0630-0632)
import test_agent_arrival_spread_sql as asp  # noqa: E402  (0633 and its graded forecasts)
import test_agent_drain_class_sql as dc  # noqa: E402  (0628's cars and levels)
import test_agent_recall_rule_sql as rr  # noqa: E402  (0627's graded orders)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0634 = os.path.join(ROOT, "db", "migrations", "0634_a_drain_is_timed_only_from_a_dispatch_the_depot_saw_begin.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
EV = "e1000000-0000-0000-0000-000000000634"                     # the evidence run: ended before the gate run began
GR = "e3000000-0000-0000-0000-000000000634"                     # the gate run: its orders graded
_file = arb._file

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

NOTE = (" These orders were made before the futures timed each car's drain only from a dispatch the depot saw begin, so "
        "this is history until new orders are graded.")
ACT = ("Grade the next armed run's orders: the futures now drain each car at the rate its returns show from dispatches "
       "the depot saw begin.")


def _apply(d):
    return _file(d, M0634)


def _through_0633(d):
    asp._through_0632(d)
    err = asp._apply(d)
    assert "0633 V4" in err, err


def _params(d, through="now()"):
    return d.json(f"SELECT public.ottoq_return_model_params('{DEPOT}', {through}, interval '21 days')")


def _model(d):
    return d.json(f"SELECT public.ottoq_learned_estimate('{DEPOT}', 'return_v1')")


def _refit(d, through="now()"):
    d.val(f"SELECT public.ottoq_fit_return_model('{DEPOT}', {through}, interval '21 days', 'test')")
    return _model(d)


# ── the evidence: reserve returns seen from their start, and returns primed before their run began ───────────────────

def _ev_run(d, run=EV, start=True, ended="now() - interval '1 hour'"):
    """A fine-tick run that started at T in sim time (sim_clock_start T, or none with start=False) and has ended."""
    sc = f"'{T}'" if start else "NULL"
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_start, sim_clock_current,
                                                 started_at, ended_at, run_by, policy)
              VALUES ('{run}', '{DEPOT}', 'completed', 200, {sc}, '{T}'::timestamptz + interval '180 minutes',
                      now() - interval '4 hours', {ended}, 'operator_demo', 'otto_q')""")


def _returns(d, spec, run=EV, created="now() - interval '2 hours'", tag="s"):
    """Reserve returns by cars of a class (cls None: no vehicle class). spec: [(cls, make, model, [(drain, primed), ...])]:
    a seen car leaves at T + 10 minutes with 98%, a primed one has its dispatch stamped 40 minutes before T and its
    battery, 98%, set at T; each works 50 minutes from when its battery was set, at its drain, and drives home 2
    minutes. Returns [(cls, mdl, ld, primed)], ld the log drain over the minutes it truly worked."""
    cars, disp, rows = [], [], []
    for cls, make, model, items in spec:
        for i, (dr, primed) in enumerate(items):
            vid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0634-{tag}-{cls}-{make}-{model}-{i}"))
            cars.append(dc._car_row(vid, f"{tag}{i}", cls, make, model))
            set_at = 0 if primed else 10                       # minutes after T the battery was set (98%)
            out_at = -40 if primed else 10                     # the dispatch's stamp
            soc_dec = round(98 - 50 * dr, 6)
            dec_at = set_at + 50
            disp.append(f"""('{vid}', '{run}', '{T}'::timestamptz + interval '{out_at} minutes',
                            '{T}'::timestamptz + interval '{dec_at + 2} minutes', 30, 98,
                            '{T}'::timestamptz + interval '{dec_at} minutes', '{T}'::timestamptz + interval '{dec_at + 2} minutes',
                            'low_soc_reserve', '{{"soc_at_decision": {soc_dec:.6f}}}'::jsonb, 'returned', {created})""")
            rows.append((cls, None if cls is None else f"{cls}/{make} {model}", math.log((98 - soc_dec) / 50), primed))
    d.val(dc.CAR_COLS + ", ".join(cars))
    d.val("""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                          planned_duration_min, soc_at_dispatch_pct, returning_started_at,
                                                          actual_return_at, return_trigger, return_evidence, status,
                                                          created_at) VALUES """ + ", ".join(disp))
    return rows


def _others(d, n_seen, n_primed, run=EV, created="now() - interval '2 hours'"):
    """Other calls home (a fault): seen ones out from T + 10 for 30 minutes, primed ones stamped 40 minutes before T and
    called at T + 20. Returns the work the depot saw, in hours."""
    d.val(f"""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                           planned_duration_min, soc_at_dispatch_pct, returning_started_at,
                                                           actual_return_at, return_trigger, return_evidence, status,
                                                           created_at)
              SELECT gen_random_uuid(), '{run}', '{T}'::timestamptz + make_interval(mins => CASE WHEN g <= {n_seen} THEN 10 ELSE -40 END),
                     '{T}'::timestamptz + interval '60 minutes', 30, 90,
                     '{T}'::timestamptz + make_interval(mins => CASE WHEN g <= {n_seen} THEN 40 ELSE 20 END),
                     '{T}'::timestamptz + make_interval(mins => CASE WHEN g <= {n_seen} THEN 43 ELSE 23 END),
                     'fault_detected', '{{}}', 'returned', {created}
                FROM generate_series(1, {n_seen + n_primed}) g""")
    return (n_seen * 30 + n_primed * 20) / 60.0


def _graded_at(d, returns, spread, base_id, tag, shift_h):
    """asp._graded's graded forecasts (one forecast per order, return j at 8 horizons, the error's variance the planted
    spread at h), with their own cars ('<tag>-car-j') and shifted shift_h hours, so a later set is its own returns."""
    fl, wk, dfr = spread
    hz = ", ".join(f"({h})" for h in asp.HORIZONS)
    rid = d.val(f"SELECT COALESCE((public.ottoq_learned_estimate('{DEPOT}', 'return_v1') ->> 'estimate_id'), '0')")
    d.val(f"""
      CREATE TEMP TABLE _g AS
      SELECT {base_id} + j * 100 + k AS order_id, md5('{tag}-car-' || j)::uuid AS car,
             '{T}'::timestamptz + interval '{shift_h} hours' + make_interval(mins => j * 3)
               - make_interval(secs => (h + e.e + 1.2) * 60) AS clock,
             h, h + e.e AS h_act
        FROM generate_series(1, {returns}) j
        CROSS JOIN LATERAL (SELECT row_number() OVER () AS k, x.h FROM (VALUES {hz}) x(h)) hh
        CROSS JOIN LATERAL (SELECT sqrt({fl} + {wk} * h + {dfr} * h * h)
                                   * public.ottoq_normal_quantile(LEAST(GREATEST(public.ottoq_hash_uniform('{tag}:' || j || ':' || h), 1e-6), 1 - 1e-6)) AS e) e;
      INSERT INTO public.ottoq_charge_order_snapshots (order_id, sim_run_id, depot_id, sim_clock, seed, futures, win_frac,
                                                       state, agent_order, code_md5, recorded_at)
      SELECT g.order_id, '{RUN}', '{DEPOT}', g.clock, 'test', 12, 0.5,
             jsonb_build_object('models', jsonb_build_object('return', {rid}::bigint),
                                'inbound', jsonb_build_array(jsonb_build_object(
                                  'id', g.car, 'src', 'forecast', 'eta', round((g.h + 1.2)::numeric, 3), 'trip', 1.2,
                                  'esd', 0.04, 'thr', 30, 'dr', 0.7)),
                                'recall', jsonb_build_object('v', 1, 'lam', 0, 'trip_o', 1.2)),
             '[]'::jsonb, 'test', now() - interval '61 minutes'
        FROM _g g;
      INSERT INTO public.ottoq_charge_order_hindsight (order_id, sim_run_id, depot_id, sim_clock, window_min, observed_min,
                                                       status, reason, taken, decision, expected, hindsight, outcome,
                                                       forecast, fidelity, realized, code_md5, graded_at)
      SELECT g.order_id, '{RUN}', '{DEPOT}', g.clock, 90, 90, 'refused', 'same_as_kernel', false, false, '{{}}', '{{}}',
             'no_decision', '{{}}', '{{}}',
             jsonb_build_object('inbound', jsonb_build_object(g.car::text, jsonb_build_object(
               'eta', round((g.h_act + 1.2)::numeric, 3), 'arrived', true))), 'test', now() - interval '1 hour'
        FROM _g g;
      DROP TABLE _g;""")


def _spread(center, n, step, primed=False):
    return [(center * math.exp(step * ((i % 5) - 2)), primed) for i in range(n)]


def _med(xs):
    return dc._med(xs)


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0634_applies_and_its_checks_run(db):
    _through_0633(db)
    err = _apply(db)
    assert ("0634 V1: the return fit times drains from dispatches the depot saw begin; the arrival spread reads the "
            "newest forecast's orders; the fit's md5 covers the spread; the self-review knows") in err, err
    assert "0634 V2: no run has 20 graded orders forecasting cars by 0628's drain; the gate is executed by the tests" in err, err
    assert re.search(r"0634 V3: return_v1 estimate \d+ in [\d.]+ s, usable false", err), err
    assert "0634 V4: the self-review in" in err, err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0634_a_drain_is_timed_only_from_a_dispatch_the_depot_saw_begin'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0634_pre'") == "4"
    m = _model(db)
    assert m["params"]["forecast_v"] == 2 and m["params"]["n_primed"] == 0, m["params"]
    assert m["params"]["arrival"]["forecast_v_newest"] is None and m["params"]["arrival"]["forecast_v"] is None
    assert db.val("SELECT has_function_privilege('anon', 'public.ottoq_return_arrival_fit(uuid,timestamptz,timestamptz)', "
                  "'EXECUTE')::text") == "true"
    # the fit's code md5 now covers what it reads for the arrival spread: a change there changes it
    assert db.val("""SELECT strpos(pg_get_functiondef('public.ottoq_fit_return_model(uuid,timestamptz,interval,text)'::regprocedure),
                                   'ottoq_variance_curve_fit(float8[],float8[],float8[])') > 0""") == "t"


def test_0634_refuses_an_engine_before_0633_a_body_it_was_not_written_against_and_a_run_running(db):
    asp._through_0632(db)
    rc, err = db.file(M0634)
    assert rc != 0 and "0634 P1: public.ottoq_return_model_params(uuid,timestamp with time zone,interval) is not the body " \
                       "measured" in err, err
    asp._apply(db)
    db.val(r"""DO $x$ BEGIN
                    EXECUTE regexp_replace(pg_get_functiondef('public.ottoq_return_arrival_fit(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure),
                                           '\$function\$\n', E'$function$\n  -- a later change\n');
                  END $x$""")
    rc, err = db.file(M0634)
    assert rc != 0 and "0634 P1: public.ottoq_return_arrival_fit(uuid,timestamp with time zone,timestamp with time zone) " \
                       "is not the body measured" in err, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0634)
    assert rc != 0 and "0634 P0: a run is running" in err, err


# ── the fit ───────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0634_a_drain_is_timed_only_from_a_dispatch_the_depot_saw_begin(db):
    _through_0633(db)
    _ev_run(db)
    rows = _returns(db, [("cls_a", "Acme", "One", _spread(0.72, 40, 0.02) + _spread(0.72, 20, 0.02, primed=True)),
                         ("cls_b", "Bee", "Big", _spread(0.60, 30, 0.02) + _spread(0.60, 15, 0.02, primed=True))])
    seen_h = _others(db, 12, 8)
    before = _params(db)
    _apply(db)
    after = _model(db)["params"]
    # before: the primed returns read their back-dated 40 minutes as driving, so their drain read 50/90 of what it was
    seen = [ld for _, _, ld, p in rows if not p]
    assert abs(math.log(float(after["drain_pct_per_min"])) - _med(seen)) < 2e-4, (after["drain_pct_per_min"], math.exp(_med(seen)))
    assert float(before["drain_pct_per_min"]) < float(after["drain_pct_per_min"]) * 0.97, (before, after)
    assert after["n_drain"] == 70 and after["n_primed"] == 35 and before["n_drain"] == 105, (after["n_drain"], after["n_primed"])
    assert float(after["drain_log_sd"]) < float(before["drain_log_sd"]), (before["drain_log_sd"], after["drain_log_sd"])
    # each class's level is its seen returns' alone, shrunk toward the depot's as 0628's levels are
    want = dc._levels([(c, m, ld) for c, m, ld, p in rows if not p])
    dc._close(after["drain_by"], want["by"])
    # every other call home is per hour of the work the depot saw: the seen ones' 30 minutes, the primed ones' 20 from
    # their run's start, and every reserve return's from the later of its dispatch and its run's start (50 minutes)
    work_h = seen_h + len(rows) * 50 / 60.0
    assert abs(float(after["other_per_work_hour"]) - 20 / work_h) < 1e-4, (after["other_per_work_hour"], 20 / work_h)
    # the threshold, the drive home and the dwell are 0633's
    for k in ("threshold_soc", "threshold_p10", "trip_min", "trip_p90_min", "trip_sd_min", "n_low_soc", "n_returns",
              "dwell", "dwell_by", "other_triggers"):
        assert after[k] == before[k], (k, before[k], after[k])


def test_0634_with_no_car_out_before_its_run_every_key_is_0633s(db):
    _through_0633(db)
    _ev_run(db, start=False)                                    # no run start: nothing is primed
    _returns(db, [("cls_a", "Acme", "One", _spread(0.72, 40, 0.02)), ("cls_b", "Bee", "Big", _spread(0.60, 30, 0.02))])
    _others(db, 12, 0)
    asp._graded(db, returns=60)                                 # and graded orders, so the arrival spread has some
    before = _params(db)
    _apply(db)
    after = _params(db)
    assert after["forecast_v"] == 2 and after["n_primed"] == 0, after
    assert {k: v for k, v in after.items() if k not in ("forecast_v", "n_primed", "arrival")} == \
           {k: v for k, v in before.items() if k != "arrival"}
    assert {k: v for k, v in after["arrival"].items() if k not in ("forecast_v", "forecast_v_newest", "from")} == \
           {k: v for k, v in before["arrival"].items() if k != "from"}
    # the orders were all made by forecast 1, which alone is usable: it reads them, and says so
    assert after["arrival"]["forecast_v"] == 1 and after["arrival"]["forecast_v_newest"] == 1, after["arrival"]


# ── the arrival spread reads the forecast as it stands ────────────────────────────────────────────────────────────────

def test_0634_the_arrival_spread_reads_the_newest_forecasts_orders_once_they_alone_are_usable(db):
    _through_0633(db)
    asp._graded(db, returns=150)                                # made by forecast 1 (0633's model): the planted spread
    _apply(db)                                                  # the depot's model is forecast 2 from here
    a = _model(db)["params"]["arrival"]
    assert a["usable"] and a["forecast_v"] == 1 and a["forecast_v_newest"] == 1, a
    v1 = (float(a["floor"]), float(a["walk"]), float(a["drift"]))
    # a few orders made by forecast 2, with a flat spread of 1.0: too few alone, so every order is read
    _graded_at(db, 20, (1.0, 0, 0), 700000, "v2a", 12)
    a = _refit(db)["params"]["arrival"]
    assert a["forecast_v"] is None and a["forecast_v_newest"] == 2 and a["returns"] == 170, a
    assert a["from"] == "graded forecasts made by 0628's drain or later", a
    # enough of them: forecast 2's orders alone, and their spread is theirs
    _graded_at(db, 150, (1.0, 0, 0), 500000, "v2b", 24)
    a = _refit(db)["params"]["arrival"]
    assert a["forecast_v"] == 2 and a["from"] == "graded forecasts made by the newest forecast among them", a
    assert a["returns"] == 170, a                               # the 20 and the 150, each its own car's return
    assert abs(float(a["floor"]) - 1.0) < 0.25 and float(a["walk"]) * 80 + float(a["drift"]) * 6400 < 0.5, (a, v1)


# ── the gate ──────────────────────────────────────────────────────────────────────────────────────────────────────────

def _gate_world(d, follows="seen", orders=20, per=10):
    """The evidence run (ended an hour ago): 40 seen reserve returns of one class at drains about 0.72 (5 levels, 3% apart)
    and 20 primed ones, whose back-dated 40 minutes read them at 50/90 of theirs; the gate run's `orders` graded orders,
    recorded after it, each forecasting `per` of those cars at work at the drain the fit gave as it stood (the seen and
    the primed together) with the car's battery 20 to 48 points above a 40% rung; each car home at the drain the seen
    returns show, 0.72 (follows='seen'), or at the drain the forecast used (follows='old'), plus a 2-minute drive."""
    _ev_run(d)
    rows = _returns(d, [("cls_a", "Acme", "One", _spread(0.72, 40, 0.03) + _spread(0.72, 20, 0.03, primed=True))], tag="g")
    old = _params(d)
    dr_old = float(old["drain_by"]["cls_a"]["models"]["cls_a/Acme One"]["drain"])
    cars = [str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0634-g-cls_a-Acme-One-{i}")) for i in range(per)]
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_start, sim_clock_current,
                                                 started_at, ended_at, run_by, policy)
              VALUES ('{GR}', '{DEPOT}', 'completed', 100, '{T}', '{T}', now() - interval '30 minutes',
                      now() - interval '5 minutes', 'operator_demo', 'otto_q')""")
    sql, errs = [], []
    for k in range(orders):
        inbound, real = [], {}
        for j, vid in enumerate(cars):
            up = 20 + (7 * k + 11 * j) % 29                      # battery above the rung
            hz_old = up / dr_old
            hz_true = up / (0.72 if follows == "seen" else dr_old)
            inbound.append({"id": vid, "src": "forecast", "eta": round(hz_old + 2, 3), "trip": 2, "esd": 0.05,
                            "thr": 40, "dr": dr_old})
            real[vid] = {"arrived": True, "eta": round(hz_true + 2, 3)}
            errs.append((hz_old, hz_true))
        state = {"models": {"return": 1}, "inbound": inbound, "recall": {"v": 1, "lam": 0, "trip_o": 2}}
        sql.append(rr._graded(d, 9800 + k, state, real, run=GR, at_min=10 * k))
    rr._run_sql(d, sql)
    return dr_old, errs


def test_0634_the_gate_passes_on_a_run_whose_cars_drained_as_the_seen_returns_say(db):
    _through_0633(db)
    dr_old, errs = _gate_world(db, "seen")
    err = _apply(db)
    m = re.search(r"0634 V2: run e3000000 through its first order \([^)]*\): the depot's drain ([\d.]+) -> ([\d.]+) "
                  r"\((\d+) -> (\d+) timed, (\d+) began before their run\), other calls home per hour of work \S+ -> \S+; "
                  r"(\d+) forecast arrivals re-made at each car's drain \(median ratio ([\d.]+) to the forecast's; the fit "
                  r"as it stood ([\d.]+)\): mean absolute error ([\d.]+) -> ([\d.]+) minutes, median error past 30 minutes "
                  r"(\S+) -> (\S+) \((\d+) arrivals\)", err)
    assert m, err
    assert (int(m.group(3)), int(m.group(4)), int(m.group(5))) == (60, 40, 20), m.groups()
    assert int(m.group(6)) == len(errs) and abs(float(m.group(8)) - 1) < 1e-3, m.groups()    # the fit as it stood is the forecast's
    assert abs(float(m.group(2)) - 0.72) < 1e-4 and abs(float(m.group(7)) - 0.72 / dr_old) < 2e-3, m.groups()
    assert dr_old < 0.71, dr_old                                # the primed returns' slow reading moved the fit
    mae_old = sum(abs(t - o) for o, t in errs) / len(errs)
    assert abs(float(m.group(9)) - mae_old) < 2e-3 and float(m.group(10)) < 0.01, m.groups()   # the seen drain is exact
    assert float(m.group(11)) < 0 and abs(float(m.group(12))) < 0.01, m.groups()             # early, then on time
    assert "0634 V3: return_v1 estimate" in err and "0634 V4" in err, err


def test_0634_the_gate_holds_back_on_a_run_whose_cars_drained_as_the_back_dated_returns_said(db):
    _through_0633(db)
    _gate_world(db, "old")
    rc, err = db.file(M0634)
    m = re.search(r"0634 V2: the gate holds back: error ([\d.]+) -> ([\d.]+), median past 30 minutes (\S+) -> (\S+)", err)
    assert rc != 0 and m, err
    assert float(m.group(1)) < 0.01 < float(m.group(2)), m.groups()
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0634_%'") == "0"


# ── the self-review ───────────────────────────────────────────────────────────────────────────────────────────────────

def test_0634_the_review_marks_orders_made_before_forecast_2_as_history(db):
    _through_0633(db)
    asp._graded(db, returns=150)                                # made with forecast 1
    db.val(f"SELECT public.ottoq_fit_return_model('{DEPOT}', now(), interval '21 days', 'test')")   # 0633's spread from them
    _graded_at(db, 150, asp.SPREAD, 600000, "v1b", 12)         # made with a usable spread, still forecast 1
    _apply(db)                                                  # the depot's model is forecast 2
    v = db.json(f"SELECT public.ottoq_arbiter_self_assessment_v3('{DEPOT}', now() - interval '7 days', false)")
    arr = [a for a in v["improvement_areas"] if a.get("part") == "arrivals"]
    assert arr, v["improvement_areas"]
    for a in arr:
        assert a["status"] == "built" and a["finding"].endswith(NOTE) and a["action"] == ACT, a
