"""db/migrations/0633, EXECUTED: the futures spread each arrival as the depot's returns show.

WHY THIS EXISTS. 0633 has the return fit (return_v1) learn the spread of the check's own arrival forecasts from its graded
orders: per log-spaced horizon bin, the robust second moment of the error about the forecast's median, and a floor, a
part with the horizon and a part with its square, each zero or more, fitted to it. The inbound forecast spreads each car
at work by it (ottoq_return_arrival_sd) behind a person's dial. Every claim in its header that a test can execute is
executed here, on the scratch PostgreSQL and the miniature depot of tests/test_agent_charge_order_sql.py, through
0619-0632 as tests/test_agent_air_clock_sql.py applies them, with graded forecasts planted from a known spread
(floor 0.25, walk 0.01, drift 0.0009: an error in minutes with variance 0.25 + 0.01 h + 0.0009 h^2 at h minutes to the
rung, drawn deterministically) for 150 returns at 8 horizons:
  - it applies, its checks run, the dial is a person's, every reader may call the spread, and it refuses an engine
    before 0632, a body it was not written against and a run running;
  - the fit recovers the planted spread, and the futures' own reader finds 80% inside the band at every horizon;
  - a world whose errors carry no horizon gets a floor and nothing else;
  - fewer than 30 returns, no usable spread, and the forecast is 0628's;
  - the forecast spreads a car at work by the fit at its horizon, and the dial at 0 or a fit without it is 0628's;
  - a fit through a past moment reads the grades that stood by then, and only forecasts made by 0628's drain or later;
  - the self-review: orders made with a return model that had no spread are history for the arrivals once it has one.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import math
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622 and the planted fleet)
import test_agent_regrade_sql as rg  # noqa: E402  (0630, and the engine through 0628)
import test_agent_fault_cut_sql as fc  # noqa: E402  (0631)
import test_agent_air_clock_sql as ac  # noqa: E402  (0632 and its planted air fleet)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0633 = os.path.join(ROOT, "db", "migrations", "0633_the_futures_spread_each_arrival_as_the_returns_show.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_vid, _file, _dial = base._vid, arb._file, base._dial

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

SPREAD = (0.25, 0.01, 0.0009)                       # floor, walk, drift: the planted variance in minutes^2
HORIZONS = (0.6, 1.5, 3, 6, 12, 25, 45, 80)


def _apply(d):
    return _file(d, M0633)


def _through_0632(d):
    ac._through_0631(d)
    ac._plant(d)
    arb._fit(d)
    ac._apply(d)


def _graded(d, returns=150, spread=SPREAD, horizons=HORIZONS, dr=True, graded_ago="1 hour", recall=True, base_id=900000):
    """Graded orders, one forecast each: return j forecast at each horizon h (the car due at its rung h minutes after the
    order, home 1.2 minutes later), and home off that by an error whose variance is the planted spread at h (a
    deterministic normal draw): the forecast first, the arrival about it, as a forecaster meets them. Each order is made
    at the moment that brings its car home at the return's one arrival, T + 3j minutes, so the 8 forecasts of a return
    are one return, as a car's are. Each snapshot names the return model the order was made with (the depot's as it
    stands) and, with `recall`, carries a recall block (0627) with no other calls home."""
    fl, wk, dfr = spread
    hz = ", ".join(f"({h})" for h in horizons)
    rid = d.val(f"SELECT COALESCE((public.ottoq_learned_estimate('{DEPOT}', 'return_v1') ->> 'estimate_id'), '0')")
    d.val(f"""
      CREATE TEMP TABLE _g AS
      SELECT {base_id} + j * 100 + k AS order_id, md5('arr-car-' || j)::uuid AS car,
             '{T}'::timestamptz + make_interval(mins => j * 3) - make_interval(secs => (h + e.e + 1.2) * 60) AS clock,
             h, h AS h_fc, h + e.e AS h_act
        FROM generate_series(1, {returns}) j
        CROSS JOIN LATERAL (SELECT row_number() OVER () AS k, x.h FROM (VALUES {hz}) x(h)) hh
        CROSS JOIN LATERAL (SELECT sqrt({fl} + {wk} * h + {dfr} * h * h)
                                   * public.ottoq_normal_quantile(LEAST(GREATEST(public.ottoq_hash_uniform('arr:' || j || ':' || h), 1e-6), 1 - 1e-6)) AS e) e;
      INSERT INTO public.ottoq_charge_order_snapshots (order_id, sim_run_id, depot_id, sim_clock, seed, futures, win_frac,
                                                       state, agent_order, code_md5, recorded_at)
      SELECT g.order_id, '{RUN}', '{DEPOT}', g.clock, 'test', 12, 0.5,
             jsonb_build_object('models', jsonb_build_object('return', {rid}::bigint),
                                'inbound', jsonb_build_array(jsonb_build_object(
                                  'id', g.car, 'src', 'forecast', 'eta', round((g.h_fc + 1.2)::numeric, 3), 'trip', 1.2,
                                  'esd', 0.04, 'thr', 30) || CASE WHEN {str(dr).lower()} THEN '{{"dr": 0.7}}'::jsonb ELSE '{{}}'::jsonb END))
               || CASE WHEN {str(recall).lower()} THEN '{{"recall": {{"v": 1, "lam": 0, "trip_o": 1.2}}}}'::jsonb ELSE '{{}}'::jsonb END,
             '[]'::jsonb, 'test', now() - interval '{graded_ago}' - interval '1 minute'
        FROM _g g;
      INSERT INTO public.ottoq_charge_order_hindsight (order_id, sim_run_id, depot_id, sim_clock, window_min, observed_min,
                                                       status, reason, taken, decision, expected, hindsight, outcome,
                                                       forecast, fidelity, realized, code_md5, graded_at)
      SELECT g.order_id, '{RUN}', '{DEPOT}', g.clock, 90, 90, 'refused', 'same_as_kernel', false, false, '{{}}', '{{}}',
             'no_decision', '{{}}', '{{}}',
             jsonb_build_object('inbound', jsonb_build_object(g.car::text, jsonb_build_object(
               'eta', round((g.h_act + 1.2)::numeric, 3), 'arrived', true))), 'test', now() - interval '{graded_ago}'
        FROM _g g;
      DROP TABLE _g;""")


def _model(d):
    return d.json(f"SELECT public.ottoq_learned_estimate('{DEPOT}', 'return_v1')")


def _refit(d, through="now()"):
    d.val(f"SELECT public.ottoq_fit_return_model('{DEPOT}', {through}, interval '21 days', 'test')")
    return _model(d)


def _sd(d, m, h):
    v = d.val(f"SELECT public.ottoq_return_arrival_sd($j${json.dumps(m)}$j$::jsonb, {h})")
    return None if v in ("", None) else float(v)


# ── the migration ─────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0633_applies_and_its_checks_run(db):
    _through_0632(db)
    _graded(db)
    err = _apply(db)
    assert "0633 V1: the spread reads 0.0670 at 10 minutes and 1.2699 at 0.1 on a planted fit" in err, err
    assert "0633 V2: on return_v1 estimate" in err and "(no arrival) the spread is NULL, so its forecast is 0628's" in err, err
    assert "0633 V3: return_v1 estimate" in err and "the graded forecasts by horizon, the old spread against the new" in err, err
    assert "0633 V4: the self-review" in err, err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0633_the_futures_spread_each_arrival_as_the_returns_show'") == "falsefalse"
    assert db.val("SELECT default_value::text || agent_writable::text FROM public.ottoq_policy_param_catalog "
                  "WHERE param_key = 'agent_charge_order_arrival_spread'") in ("1false", "1.0false")
    assert db.val("SELECT has_function_privilege('anon', 'public.ottoq_return_arrival_sd(jsonb,numeric)', 'EXECUTE')::text") \
        == "true"
    a = _model(db)["params"]["arrival"]
    assert a["usable"] and a["returns"] == 150 and a["orders"] == a["forecasts"] and len(a["bins"]) >= 4, a
    assert a["forecasts"] == 1200 and a["orders"] == 1200, a          # 150 returns, each forecast at 8 horizons


def test_0633_refuses_an_engine_before_0632_a_body_it_was_not_written_against_and_a_run_running(db):
    ac._through_0631(db)
    rc, err = db.file(M0633)
    assert rc != 0 and "0633 P1: public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean) is not " \
                       "the body measured" in err, err
    ac._plant(db)
    arb._fit(db)
    ac._apply(db)
    db.val(r"""DO $x$ BEGIN
                    EXECUTE regexp_replace(pg_get_functiondef('public.ottoq_charge_line_inbound(uuid,uuid,timestamp with time zone,numeric,jsonb)'::regprocedure),
                                           '\$function\$\n', E'$function$\n  -- a later change\n');
                  END $x$""")
    rc, err = db.file(M0633)
    assert rc != 0 and "0633 P1: public.ottoq_charge_line_inbound(uuid,uuid,timestamp with time zone,numeric,jsonb) is " \
                       "not the body measured" in err, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0633)
    assert rc != 0 and "0633 P0: a run is running" in err, err


# ── the fit ───────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0633_the_fit_recovers_the_planted_spread_and_the_band_holds_80_percent(db):
    _through_0632(db)
    _graded(db)
    _apply(db)
    m = _model(db)
    a = m["params"]["arrival"]
    fl, wk, dfr = (float(a["floor"]), float(a["walk"]), float(a["drift"]))
    for h in HORIZONS:                      # the fitted variance within 30% of the planted, at every horizon: a bin's
        planted = SPREAD[0] + SPREAD[1] * h + SPREAD[2] * h * h          # robust variance on 150 returns is good to ~15%,
        assert abs((fl + wk * h + dfr * h * h) / planted - 1) < 0.3, (h, a)    # and each forecast is binned by its own horizon
    # the futures' own reader, on these forecasts with the fitted spread: 80% inside the band at every horizon
    rows = db.json(f"""
      SELECT jsonb_agg(jsonb_build_object('h', x.h, 'in', x.inside) ORDER BY x.h) FROM (
        SELECT min((ib.value ->> 'eta')::numeric - 1.2) AS h,
               avg((abs(public.ottoq_inbound_arrival_z(
                      ib.value || jsonb_build_object('esd', public.ottoq_return_arrival_sd($j${json.dumps(m)}$j$::jsonb,
                                                                                            (ib.value ->> 'eta')::numeric - 1.2)),
                      s.state -> 'recall', (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8)) <= 1.2816)::int) AS inside
          FROM public.ottoq_charge_order_grades h
          JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
          CROSS JOIN LATERAL jsonb_array_elements(s.state -> 'inbound') ib
         GROUP BY (h.order_id % 100)) x""")
    for r in rows:
        assert 0.65 <= float(r["in"]) <= 0.93, rows
    assert abs(sum(float(r["in"]) for r in rows) / len(rows) - 0.80) < 0.06, rows


def test_0633_errors_that_carry_no_horizon_get_a_floor_and_nothing_else(db):
    _through_0632(db)
    _graded(db, spread=(0.3, 0, 0))
    _apply(db)
    a = _model(db)["params"]["arrival"]
    assert a["usable"] and abs(float(a["floor"]) - 0.3) < 0.08, a
    assert float(a["walk"]) * 80 + float(a["drift"]) * 80 * 80 < 0.12, a


def test_0633_too_few_returns_is_no_spread_and_the_forecast_is_0628s(db):
    _through_0632(db)
    _graded(db, returns=20)
    _apply(db)
    m = _model(db)
    assert not m["params"]["arrival"]["usable"] and m["params"]["arrival"]["returns"] == 20, m["params"]["arrival"]
    assert _sd(db, m, 10) is None


def test_0633_the_forecast_spreads_a_car_at_work_by_the_fit_and_the_dial_turns_it_off(db):
    _through_0632(db)
    _graded(db)
    _apply(db)
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running', ended_at = NULL WHERE sim_run_id = '{RUN}'")
    base._car(db, "W", 70, 0, state="deployed")
    db.val(f"DELETE FROM public.ottoq_visit_needs WHERE vehicle_id = '{_vid('W')}'")
    db.val(f"""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                            planned_duration_min, status)
               VALUES ('{_vid('W')}', '{RUN}', '{T}'::timestamptz - interval '40 minutes',
                       '{T}'::timestamptz + interval '1 hour', 30, 'active')""")
    fitted = _model(db)["params"]["arrival"]
    m = {"usable": True, "estimate_id": 1,
         "params": {"threshold_soc": 50, "drain_pct_per_min": 0.5, "drain_log_sd": 0.05, "trip_min": 2, "trip_sd_min": 0.2,
                    "arrival": fitted}}
    plain = dict(m, params={k: v for k, v in m["params"].items() if k != "arrival"})

    def w(model):
        return db.json(f"""SELECT to_jsonb(x) FROM public.ottoq_charge_line_inbound('{RUN}', '{DEPOT}', '{T}', 180,
                             $j${json.dumps(model)}$j$::jsonb) x WHERE x.vehicle_id = '{_vid('W')}'""")

    with_fit, without = w(m), w(plain)
    hz = float(with_fit["eta_min"]) - float(with_fit["trip_min"])
    assert with_fit["source"] == "forecast" and hz > 0, with_fit
    assert abs(float(with_fit["eta_log_sd"]) - _sd(db, m, hz)) < 0.002, (with_fit, hz)       # hz read back from
    assert abs(float(without["eta_log_sd"]) - math.sqrt(0.05 ** 2 + (0.2 / max(hz, 0.25)) ** 2)) < 0.002, (without, hz)
    assert {k: v for k, v in with_fit.items() if k != "eta_log_sd"} == {k: v for k, v in without.items() if k != "eta_log_sd"}
    _dial(db, "agent_charge_order_arrival_spread", 0)
    assert w(m) == without


def test_0633_a_past_fit_reads_the_grades_that_stood_then_and_only_forecasts_by_0628s_drain(db):
    _through_0632(db)
    _graded(db, graded_ago="2 hours")                           # graded two hours ago
    _graded(db, dr=False, base_id=800000)                       # made before 0628's drain: never read
    _apply(db)
    a = _model(db)["params"]["arrival"]
    assert a["forecasts"] == 1200 and a["returns"] == 150, a   # those by 0628's drain, not the ones before it
    past = db.json(f"SELECT public.ottoq_return_model_params('{DEPOT}', now() - interval '3 hours', interval '21 days')")
    assert past["arrival"]["forecasts"] == 0 and not past["arrival"]["usable"], past["arrival"]


# ── the self-review ───────────────────────────────────────────────────────────────────────────────────────────────────

def test_0633_the_review_marks_orders_made_without_the_spread_as_history(db):
    _through_0632(db)
    _graded(db)                       # made with the depot's return model as it stood: no spread
    _apply(db)                        # the refit learns it from them
    assert _model(db)["params"]["arrival"]["usable"]
    v = db.json(f"SELECT public.ottoq_arbiter_self_assessment_v3('{DEPOT}', now() - interval '7 days', false)")
    arr = [a for a in v["improvement_areas"] if a.get("part") == "arrivals"]
    assert arr, v["improvement_areas"]
    for a in arr:
        assert a["status"] == "built", a
        assert "spread each arrival as the check's own graded forecasts show" in a["finding"], a["finding"]
        assert a["action"].startswith("Grade the next armed run's orders: the futures now spread each arrival"), a["action"]
