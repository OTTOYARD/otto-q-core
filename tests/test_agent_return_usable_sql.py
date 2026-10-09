"""db/migrations/0637, EXECUTED: the futures read the latest return model that was usable.

WHY THIS EXISTS. The check's futures forecast every car at work home with the depot's return model, refitted every
night, and every reader took the newest fit whatever it said about itself: a night whose refit found too few returns to
be usable would leave the futures forecasting no car at work until the evidence grew back, and nothing would say so
(G377). 0637's reader takes the latest usable fit, names a newer one it passed over, and the four readers (the state, the
inbound forecast, the agent's board, the self-review) read it. Every claim in its header that a test can execute is
executed here, on the scratch PostgreSQL and the miniature depot of tests/test_agent_charge_order_sql.py, through
0619-0636 as tests/test_agent_clock_spread_sql.py applies them:
  - it applies, its checks run, and it refuses an engine before 0636 and a run running;
  - the reader: the latest usable fit, `passed_over` for a newer one that was not; with the latest usable, exactly the
    newest fit; with only unusable fits, the newest; with none, NULL;
  - the state reads the usable model where it read the unusable one, and with the latest fit usable it reads exactly as
    before;
  - the self-review names the fit it passed over, in words.
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
import test_agent_clock_spread_sql as cs  # noqa: E402  (0636 and the chain through it)
import test_agent_self_review_sql as sr  # noqa: E402  (the review's words)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0637 = os.path.join(ROOT, "db", "migrations", "0637_the_futures_read_the_latest_return_model_that_was_usable.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
ELSEWHERE = "77777777-7777-7777-7777-777777777777"
_file = arb._file

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

PARAMS = {"threshold_soc": 50, "drain_pct_per_min": 0.5, "drain_log_sd": 0.1, "trip_min": 2, "other_share": 0.1}


def _apply(d):
    return _file(d, M0637)


def _through_0636(d):
    cs._through_0635(d)
    err = cs._apply(d)
    assert "0636 V5" in err, err


def _fit(d, usable, n=100, depot=DEPOT, params=PARAMS, ago="0 minutes"):
    return int(d.val(f"""INSERT INTO public.ottoq_learned_estimates (depot_id, model, fitted_at, n_evidence, n_runs, usable,
                                                                   params, code_md5, note)
                         VALUES ('{depot}', 'return_v1', now() - interval '{ago}', {n}, 5, {str(usable).lower()},
                                 $j${json.dumps(params)}$j$::jsonb, 'test', 'test')
                         RETURNING estimate_id"""))


def _model(d, depot=DEPOT):
    v = d.val(f"SELECT public.ottoq_return_model('{depot}')")
    return json.loads(v) if v else None


def _newest(d, depot=DEPOT):
    v = d.val(f"SELECT public.ottoq_learned_estimate('{depot}', 'return_v1')")
    return json.loads(v) if v else None


def _state(d):
    return d.json(f"SELECT public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}')")


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0637_applies_and_its_checks_run(db):
    _through_0636(db)
    err = _apply(db)
    assert re.search(r"0637 V1: the twin depot's return model is fit \d+ \(latest fit \d+, usable \w+\); every reader reads it",
                     err), err
    assert re.search(r"0637 V2: (no stored order to read|with the latest return fit usable|the twin depot's latest return fit "
                     r"is not usable)", err), err
    assert re.search(r"0637 V3: the self-review in \d+ ms; its return model area: ", err), err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0637_the_futures_read_the_latest_return_model_that_was_usable'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0637_pre'") == "4"
    assert db.val("""SELECT count(*) FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace
                      WHERE s.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ 'ottoq_learned_estimate\\([^)]*return_v1'""") == "0"
    assert db.val("SELECT has_function_privilege('anon', 'public.ottoq_return_model(uuid)', 'EXECUTE')::text") == "true"


def test_0637_refuses_an_engine_before_0636_and_a_run_running(db):
    cs._through_0635(db)
    rc, err = db.file(M0637)
    assert rc != 0 and "0637 P1: public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean) is not " \
                       "the body measured" in err, err
    cs._apply(db)
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0637)
    assert rc != 0 and "0637 P0: a run is running" in err, err
    assert db.val("SELECT to_regprocedure('public.ottoq_return_model(uuid)') IS NULL") == "t"


# ── the reader ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0637_the_reader_takes_the_latest_usable_fit_and_names_a_newer_one_it_passed_over(db):
    _through_0636(db)
    _apply(db)
    # no fit at a depot: NULL; only an unusable one: it, with nothing passed over
    assert _model(db, ELSEWHERE) is None
    thin = _fit(db, False, n=12, depot=ELSEWHERE)
    m = _model(db, ELSEWHERE)
    assert m == _newest(db, ELSEWHERE) and m["estimate_id"] == thin and "passed_over" not in m
    # a usable fit, the newest: exactly the newest fit
    good = _fit(db, True, n=400, depot=ELSEWHERE, ago="1 day")
    assert _model(db, ELSEWHERE) == _newest(db, ELSEWHERE) and _model(db, ELSEWHERE)["estimate_id"] == good
    # a newer one that is not usable: the usable one, and the newer named
    worse = _fit(db, False, n=9, depot=ELSEWHERE)
    m = _model(db, ELSEWHERE)
    assert m["estimate_id"] == good and m["usable"] is True and m["params"] == PARAMS, m
    assert m["passed_over"]["estimate_id"] == worse and m["passed_over"]["n_evidence"] == 9, m
    assert {k: v for k, v in m.items() if k != "passed_over"} == \
        db.json(f"""SELECT jsonb_build_object('estimate_id', e.estimate_id, 'model', e.model, 'fitted_at', e.fitted_at,
                                             'usable', e.usable, 'n_evidence', e.n_evidence, 'n_runs', e.n_runs, 'params', e.params)
                      FROM public.ottoq_learned_estimates e WHERE e.estimate_id = {good}""")
    # a usable one after it: that one, nothing passed over
    best = _fit(db, True, n=500, depot=ELSEWHERE)
    assert _model(db, ELSEWHERE)["estimate_id"] == best and "passed_over" not in _model(db, ELSEWHERE)


# ── the state reads it ────────────────────────────────────────────────────────────────────────────────────────────────

def test_0637_the_state_reads_the_usable_model_where_it_read_the_unusable_one(db):
    _through_0636(db)
    good = _fit(db, True, n=400, ago="1 day")
    same = _state(db)                                           # before 0637, with the newest fit usable
    _fit(db, False, n=9)
    before = _state(db)                                         # before 0637, the newest fit unusable
    assert before["models"]["return_usable"] is False and "recall" not in before
    _apply(db)
    after = _state(db)
    assert after["models"]["return"] == good and after["models"]["return_usable"] is True, after["models"]
    assert after == same, {k: (after.get(k), same.get(k)) for k in set(after) | set(same) if after.get(k) != same.get(k)}


def test_0637_with_the_latest_fit_usable_every_reader_reads_as_before(db):
    _through_0636(db)
    _fit(db, True, n=400)
    st = _state(db)
    board = db.val(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')::text")
    _apply(db)
    assert _state(db) == st
    assert db.val(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')::text") == board


# ── the self-review ───────────────────────────────────────────────────────────────────────────────────────────────────

def test_0637_the_review_names_the_fit_it_passed_over(db):
    _through_0636(db)
    _apply(db)
    for k in range(3):
        sr._graded(db, 9500 + k)
    _fit(db, True, n=400, ago="1 day")
    v = db.json(f"SELECT public.ottoq_arbiter_self_assessment_v3('{DEPOT}', now() - interval '7 days', false)")
    assert not [a for a in v["improvement_areas"] if a["area"] == "return_model_passed_over"]
    worse = _fit(db, False, n=9)
    v = db.json(f"SELECT public.ottoq_arbiter_self_assessment_v3('{DEPOT}', now() - interval '7 days', false)")
    a = [a for a in v["improvement_areas"] if a["area"] == "return_model_passed_over"]
    assert len(a) == 1, v["improvement_areas"]
    a = a[0]
    sr._plain(a)
    assert (a["status"], a["kind"], a["title"]) == ("open", "capability_gap", "The return model's latest fit was not usable"), a
    assert re.match(r"The fit of \d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC found 9 returns, too few to be usable, so the futures "
                    r"forecast cars at work by the fit of \d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC, the latest that was\. ", a["finding"]), a
    assert a["evidence"]["estimate_id"] == worse and a["action"].startswith("Keep the returns as evidence"), a
