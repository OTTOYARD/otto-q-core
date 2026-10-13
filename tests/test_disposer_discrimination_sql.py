"""db/migrations/0708, EXECUTED: the promotion gate can ask whether the check tells a winning order from a losing one.

WHY THIS EXISTS. docs/AGENT_ARCHITECTURE.md lets an additional agent reach production only when the agent-order check
discriminates (its AUC interval excludes 0.5), and nothing computed an AUC: G389, the study's AV-1 and 0440 §2 each did it
by hand over different denominators. Executed here against values computed independently in Python:
  - the AUC is the Mann-Whitney statistic, ties between a won and a lost order counting one half;
  - the interval is Hanley & McNeil's, and `discriminates` is its lower end above 0.5;
  - Brier is against the base rate; neutral takes and undecided grades are left out and counted;
  - runs and distinct (scenario, seed) keys are counted, so repeated seeds read as one key (0339);
  - with fewer than 2 orders on a side the AUC is null, not a number.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import math
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "disposer_discrimination_stub.sql")
M0708 = os.path.join(ROOT, "db", "migrations",
                     "0708_the_promotion_gate_can_ask_whether_the_check_tells_a_winning_order_from_a_losing_one.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN_A = "0708aaaa-0000-0000-0000-00000000000a"
RUN_B = "0708aaaa-0000-0000-0000-00000000000b"
RUN_C = "0708aaaa-0000-0000-0000-00000000000c"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture()
def db():
    name = f"ottoq_disc_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        d.val(f"""INSERT INTO public.ottoq_sim_runs VALUES
                  ('{RUN_A}', 'busy_day', 305838298283560562, now() - interval '3 hours'),
                  ('{RUN_B}', 'busy_day', 305838298283560562, now() - interval '2 hours'),
                  ('{RUN_C}', 'busy_day', 686364201590009433, now() - interval '1 hour')""")
        rc, err = d.file(M0708)
        assert rc == 0 and "0708 V1-V3 PASSED" in err, err
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _grade(d, run, p, outcome, decision=True):
    pv = "NULL" if p is None else p
    d.val(f"""INSERT INTO public.ottoq_charge_order_grades (sim_run_id, depot_id, decision, p_win, outcome)
              VALUES ('{run}', '{DEPOT}', {str(decision).lower()}, {pv}, '{outcome}')""")


def _ref(won, lost):
    """Mann-Whitney AUC with half ties, Hanley-McNeil SE, Brier vs base: computed here, not in SQL."""
    pairs = sum(1.0 if w > l else 0.5 if w == l else 0.0 for w in won for l in lost)
    a = pairs / (len(won) * len(lost))
    q1, q2 = a / (2 - a), 2 * a * a / (1 + a)
    se = math.sqrt(max(0.0, (a * (1 - a) + (len(won) - 1) * (q1 - a * a) + (len(lost) - 1) * (q2 - a * a))
                       / (len(won) * len(lost))))
    ys = [1] * len(won) + [0] * len(lost)
    ps = list(won) + list(lost)
    ybar = sum(ys) / len(ys)
    brier = sum((p - y) ** 2 for p, y in zip(ps, ys)) / len(ys)
    base_ = sum((ybar - y) ** 2 for y in ys) / len(ys)
    return a, se, brier, base_


def _call(d):
    return d.json(f"SELECT public.ottoq_disposer_discrimination('{DEPOT}', '-infinity', 'infinity')")


def test_0708_auc_interval_and_brier_match_an_independent_computation(db):
    won = [0.9, 0.8, 0.75, 0.6, 0.6, 0.55, 0.4]
    lost = [0.7, 0.6, 0.5, 0.45, 0.3, 0.2]
    for i, p in enumerate(won):
        _grade(db, RUN_A if i % 2 else RUN_B, p, "missed_win" if i % 3 else "right_take")
    for i, p in enumerate(lost):
        _grade(db, RUN_C, p, "right_refusal" if i % 3 else "wrong_take")
    _grade(db, RUN_C, 0.95, "neutral_take")
    _grade(db, RUN_C, None, "no_decision", decision=False)
    r = _call(db)
    a, se, brier, base_ = _ref(won, lost)
    assert r["won"] == 7 and r["lost"] == 6 and r["ties_left_out"] == 1, r
    assert abs(r["auc"] - round(a, 4)) < 1e-9 and abs(r["auc_se"] - round(se, 4)) < 1e-9, (r, a, se)
    assert r["auc_ci95"] == [round(max(0, a - 1.96 * se), 4), round(min(1, a + 1.96 * se), 4)], r
    assert r["discriminates"] == ((a - 1.96 * se) > 0.5), r
    assert abs(r["brier"] - round(brier, 4)) < 1e-9 and abs(r["brier_base"] - round(base_, 4)) < 1e-9, r
    # two runs on one seed are one key (0339)
    assert r["runs"] == 3 and r["distinct_keys"] == 2, r
    assert len(r["by_run"]) == 3


def test_0708_a_check_that_separates_cleanly_discriminates_and_one_that_cannot_does_not(db):
    for i in range(20):
        _grade(db, RUN_A, 0.8 + i / 1000, "missed_win")
        _grade(db, RUN_C, 0.2 + i / 1000, "right_refusal")
    r = _call(db)
    assert r["auc"] == 1.0 and r["discriminates"] is True and r["brier_skill"] > 0, r
    # every order the same p_win: no separation at all, AUC exactly one half
    db.val("UPDATE public.ottoq_charge_order_grades SET p_win = 0.5")
    r = _call(db)
    assert r["auc"] == 0.5 and r["discriminates"] is False, r


def test_0708_too_few_on_a_side_is_null_not_a_number(db):
    _grade(db, RUN_A, 0.9, "missed_win")
    _grade(db, RUN_A, 0.7, "right_take")
    _grade(db, RUN_C, 0.2, "right_refusal")
    r = _call(db)
    assert r["auc"] is None and r["discriminates"] is None and r["why_null"], r
    assert r["won"] == 2 and r["lost"] == 1


def test_0708_another_depot_and_the_window_are_respected(db):
    _grade(db, RUN_A, 0.9, "missed_win")
    _grade(db, RUN_A, 0.8, "missed_win")
    _grade(db, RUN_C, 0.2, "right_refusal")
    _grade(db, RUN_C, 0.1, "right_refusal")
    db.val("""INSERT INTO public.ottoq_charge_order_grades (sim_run_id, depot_id, decision, p_win, outcome, graded_at)
              VALUES (NULL, '22222222-2222-2222-2222-222222222222', true, 0.9, 'right_refusal', now()),
                     (NULL, '11111111-1111-1111-1111-111111111111', true, 0.9, 'right_refusal', now() - interval '60 days')""")
    r = db.json(f"SELECT public.ottoq_disposer_discrimination('{DEPOT}')")
    assert r["won"] == 2 and r["lost"] == 2 and r["auc"] == 1.0, r


def test_0708_a_lead_of_one_standard_error_is_not_enough(db):
    # AUC 0.67 with a standard error of 0.123: one SE above 0.5, but the 95% interval reaches 0.43
    won = [0.62, 0.58, 0.55, 0.53, 0.51, 0.49, 0.47, 0.66, 0.6, 0.44]
    lost = [round(x + 0.02, 2) for x in [0.5, 0.48, 0.46, 0.45, 0.43, 0.52, 0.57, 0.41, 0.39, 0.61]]
    for p in won:
        _grade(db, RUN_A, p, "missed_win")
    for p in lost:
        _grade(db, RUN_C, p, "right_refusal")
    r = _call(db)
    a, se, _, _ = _ref(won, lost)
    assert abs(r["auc"] - round(a, 4)) < 1e-9 and a - se > 0.5 > a - 1.96 * se, (r, a, se)
    assert r["discriminates"] is False and r["auc_ci95"][0] < 0.5, r
