"""db/migrations/0635, EXECUTED: the futures take chargers down as the depot's chargers fail.

WHY THIS EXISTS. The kernel's check on an agent's charge order rolls the charge line forward in sampled futures, and no
future ever took a charger down: a fault inside the window surprised every one of them, and a charger down at the order
never came back. 0635 learns each kind of charger's fault rate per minute of charging and its repair curve every night
(charge_fault_v1), the state carries them behind a person's dial with the chargers down at the order, and the simulator
draws from them: in a sampled future a charge faults at its kind's rate, its car rejoins the line owing the rest (rule
9), the charger is down for a drawn repair, and a charger down at the order comes back after what is left of its repair.
Every claim in its header that a test can execute is executed here, on the scratch PostgreSQL and the miniature depot of
tests/test_agent_charge_order_sql.py, through 0619-0634 as tests/test_agent_drain_seen_sql.py applies them:
  - it applies, its checks run, and it refuses an engine before 0634, a body it was not written against and a run
    running; on a depot with something to say, its fit, its out-of-sample reading and its rollout speak;
  - the draws, by arithmetic: the minutes of charging to a fault, and the repair still to go for a charger down so long;
  - the fit: each kind's hazard per charging minute and repair quantiles, the fine-tick runs when they hold 30 faults,
    usable from 30 faults and 30 repairs, the depot's evidence alone, nothing after the moment it is fitted through;
  - the state carries the faults and the chargers down at the order (how long each has been down on the run's own
    clock, or at least since the run began) behind the dial; with the dial at 0 or no usable fit, 0634's state;
  - the simulator: without the block, 0634's result key for key; with it, a charger down at the order comes back at the
    curve's conditional median in the expected future and at its own draw in a sampled one; a drawn fault is 0621's down
    window exactly; a charge under way that a fault cuts puts its car back in line owing the rest, and that car is never
    counted as a return; both sides of a comparison meet the same faults; no hazard draws nothing; a hazard with no
    repair curve draws nothing; an extreme hazard still ends;
  - the realizer replays real faults in place of the state's;
  - the self-review: orders made without faults in their futures are history once the depot has a usable fault fit,
    and orders that carried them say what is left.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import hashlib
import json
import math
import os
import re
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622)
import test_agent_drain_seen_sql as ds  # noqa: E402  (0634 and the chain through it)
import test_agent_self_review_sql as sr  # noqa: E402  (graded orders and their Shapley split, by hand)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0635 = os.path.join(ROOT, "db", "migrations", "0635_the_futures_take_chargers_down_as_the_depots_chargers_fail.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
EV = "f1000000-0000-0000-0000-000000000635"                      # a fine-tick evidence run
CO = "f2000000-0000-0000-0000-000000000635"                      # a coarse-tick evidence run
FD = "44444444-4444-4444-4444-444444444444"                      # a depot with no charges but these tests'
ELSEWHERE = "22222222-2222-2222-2222-222222222222"               # another depot
_file = arb._file
_vid = base._vid

RQ = [10 + 10 * i for i in range(21)]                            # a repair curve, linear 10..210: median 110
RQSQL = "ARRAY[" + ", ".join(str(x) for x in RQ) + "]::float8[]"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

NOTE = (" These orders were made before the futures took chargers down as the depot's chargers fail, so this is history "
        "until new orders are graded.")
ACT = ("Grade the next armed run's orders: the futures now draw charger faults at the depot's own rate and bring each "
       "charger back after its repair.")


def _apply(d):
    return _file(d, M0635)


def _through_0634(d):
    ds._through_0633(d)
    err = ds._apply(d)
    assert "0634 V4" in err, err


def _hu(key):
    """ottoq_hash_uniform, in Python: the first 32 bits of md5(key), centred in their cell."""
    return (int(hashlib.md5(key.encode()).hexdigest()[:8], 16) + 0.5) / 4294967296.0


def _lam(key):
    """-ln(1 - u): a fault comes after this many minutes of charging at a hazard of one a minute."""
    return -math.log(1 - _hu(key))


def _params(d, through="now()", depot=DEPOT):
    return d.json(f"SELECT public.ottoq_charge_fault_params('{depot}', {through}, interval '21 days')")


def _model(d, depot=DEPOT):
    return d.json(f"SELECT public.ottoq_charge_fault_model('{depot}')")


# ── the evidence: charges and the faults that ended them ──────────────────────────────────────────────────────────────

def _charges(d, tag, run, kind, n, minutes, faults, repairs=(), tick=0.5, recorded="now() - interval '2 hours'",
             depot=DEPOT, occurred=None):
    """n charges of `minutes` each on `kind` chargers in `run`, at `tick` minutes a tick, recorded at `recorded`; the
    first `faults` ended in a fault, and the first len(repairs) of those have a fault event recording that repair (a
    number, or a string as the event carries it)."""
    d.val(f"""INSERT INTO public.ottoq_charge_duration_ledger (session_id, recorded_at, source_kind, sim_run_id, depot_id,
                                                                charger_type, duration_min, stopped_reason, tick_minutes)
              SELECT md5('{tag}:' || g)::uuid, {recorded}, 'twin', '{run}', '{depot}', '{kind}', {minutes},
                     CASE WHEN g <= {faults} THEN 'fault.connector_cable' ELSE 'completed' END, {tick}
                FROM generate_series(1, {n}) g""")
    if repairs:
        vals = ", ".join(f"({i + 1}, '{json.dumps(r)}'::jsonb)" for i, r in enumerate(repairs))
        d.val(f"""INSERT INTO public.ottoq_events (actor_type, event_type, event_category, entity_type, entity_id, payload,
                                                   payload_hash, sim_run_id, sim_clock_at, occurred_at)
                  SELECT 'twin', 'charge.session_faulted', 'charging', 'ocpp_session', md5('{tag}:' || v.g)::uuid,
                         jsonb_build_object('repair_minutes', v.r, 'auto_rerouted', true), 'h', '{run}', '{T}',
                         {occurred or recorded}
                    FROM (VALUES {vals}) v(g, r)""")


def _evidence(d, depot=DEPOT):
    """Fast charges: a fine-tick run, 200 of 30 minutes, 36 ended by a fault with repairs 10..45; a coarse run's 100,
    50 of them faulted, is left out since the fine runs hold 30. L2: the fine run holds 10 faults, too few, so every run
    counts: 100 of 30 minutes with 10 faults and 200 of 100 minutes with 25, repairs 60 and 120."""
    _charges(d, "d", EV, "dcfc", 200, 30, 36, [10 + i for i in range(36)], depot=depot)
    _charges(d, "dc", CO, "dcfc", 100, 30, 50, [500] * 50, tick=30, depot=depot)
    _charges(d, "l", EV, "l2", 100, 30, 10, [60] * 10, depot=depot)
    _charges(d, "lc", CO, "l2", 200, 100, 25, [120] * 25, tick=30, depot=depot)


def _fit_row(d, by_kind, usable=True):
    """A fit, by hand: by_kind as ottoq_charge_fault_params writes it."""
    return int(d.val(f"""INSERT INTO public.ottoq_charge_fault_fits (depot_id, model, n_evidence, n_runs, usable, params,
                                                                     code_md5, note)
                         VALUES ('{DEPOT}', 'charge_fault_v1', 100, 3, {str(usable).lower()},
                                 $j${json.dumps({"by_kind": by_kind})}$j$::jsonb, 'test', 'test')
                         RETURNING fit_id"""))


KIND_OK = {"h": 0.002, "rq": RQ, "faults": 40, "repairs": 40, "usable": True}
KIND_THIN = {"h": 0.001, "rq": RQ, "faults": 12, "repairs": 12, "usable": False}


# ── the simulator, by hand ────────────────────────────────────────────────────────────────────────────────────────────

def _sim(d, state, order=None, k=0, seed="s", trace=True):
    o = "NULL" if order is None else f"$o${json.dumps(order)}$o$::jsonb"
    return d.json(f"SELECT public.ottoq_charge_line_schedule($j${json.dumps(state)}$j$::jsonb, {o}, {k}, '{seed}', "
                  f"{str(trace).lower()})")


def _line(cars, chargers, faults=None, ttl=0, **extra):
    st = {"ttl_min": ttl, "pin_min": 90, "horizon_min": 480, "cars": cars, "inbound": [], "chargers": chargers}
    if faults is not None:
        st["faults"] = faults
    st.update(extra)
    return st


def _car(cid, md=30, ml=120, g=40, soc=60, w=5, **kw):
    return dict({"id": cid, "md": md, "ml": ml, "sd": 0, "sl": 0, "g": g, "soc": soc, "w": w}, **kw)


def _repair(d, u_key, down=0, q=RQSQL):
    return float(d.val(f"SELECT public.ottoq_fault_repair_draw({q}, public.ottoq_hash_uniform('{u_key}'), {down})"))


def _seed(pred, prefix):
    """The first seed '<prefix><i>' for which pred(seed) holds: the hash draws are fixed, so a test picks the seed whose
    draws make its future readable rather than asserting on a draw it cannot see."""
    for i in range(2000):
        s = f"{prefix}{i}"
        if pred(s):
            return s
    raise AssertionError(f"no seed found for {prefix}")


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0635_applies_and_its_checks_run(db):
    _through_0634(db)
    err = _apply(db)
    assert ("0635 V1: a fault at h 0.002 comes at a median 346.6 minutes of charging; a repair on the depot's fast curve "
            "30 fresh, 68.5 more after 30 minutes down, 30 past its longest; the simulator, the state, the realizer and "
            "the dial as meant") in err, err
    assert "0635 V2: 0 stored simulations (0 states x both sides x futures 0 and 3) unchanged" in err, err
    assert re.search(r"0635 V3: charge_fault_v1 fit \d+ in [\d.]+ s, usable false: none", err), err
    assert "0635 V3: no run has 20 graded orders; the out-of-sample reading is executed by the tests" in err, err
    assert "0635 V4: no usable fault fit; the state and the rollout are executed by the tests" in err, err
    assert re.search(r"0635 V5: the self-review in \d+ ms; its faults areas: none", err), err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0635_the_futures_take_chargers_down_as_the_depots_chargers_fail'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0635_pre'") == "4"
    assert db.val("SELECT schedule FROM cron.job WHERE jobname = 'ottoq-learn-charge-faults-nightly'") == "24 11 * * *"
    assert db.val("""SELECT default_value::text || '/' || min_value || '/' || max_value || '/' || agent_writable
                       FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_faults'""") == "1/0/1/false"
    # the fits: append-only evidence, readable by the cockpits, written only through the fit
    assert db.val("SELECT count(*) FROM public.ottoq_charge_fault_fits") == "1"
    rc, _, e = db.run("UPDATE public.ottoq_charge_fault_fits SET note = 'edited'")
    assert rc != 0 and "ottoq_charge_fault_fits is append-only: UPDATE refused" in e, e
    rc, _, e = db.run("DELETE FROM public.ottoq_charge_fault_fits")
    assert rc != 0 and "append-only: DELETE refused" in e, e
    assert db.val("SET ottoq.learned_estimates_unlock = 'on'; UPDATE public.ottoq_charge_fault_fits SET note = 'why' "
                  "RETURNING note") == "why"
    for priv, want in (("has_table_privilege('anon', 'public.ottoq_charge_fault_fits', 'SELECT')", "true"),
                       ("has_table_privilege('anon', 'public.ottoq_charge_fault_fits', 'INSERT')", "false"),
                       ("has_function_privilege('anon', 'public.ottoq_fault_repair_draw(float8[],float8,float8)', 'EXECUTE')",
                        "true"),
                       ("has_function_privilege('anon', 'public.ottoq_charge_fault_model(uuid)', 'EXECUTE')", "true")):
        assert db.val(f"SELECT {priv}::text") == want, priv


def test_0635_refuses_an_engine_before_0634_a_body_it_was_not_written_against_and_a_run_running(db):
    ds._through_0633(db)
    rc, err = db.file(M0635)
    assert rc != 0 and "0635 P1: public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean) is not " \
                       "the body measured" in err, err
    ds._apply(db)
    db.val(r"""DO $x$ BEGIN
                    EXECUTE regexp_replace(pg_get_functiondef('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure),
                                           '\$function\$\n', E'$function$\n  -- a later change\n');
                  END $x$""")
    rc, err = db.file(M0635)
    assert rc != 0 and "0635 P1: public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean) is not the body " \
                       "measured" in err, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0635)
    assert rc != 0 and "0635 P0: a run is running" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0635_%'") == "0"
    assert db.val("SELECT to_regclass('public.ottoq_charge_fault_fits') IS NULL") == "t"


def test_0635_its_checks_hold_on_a_depot_with_something_to_say(db):
    _through_0634(db)
    _evidence(db)
    # twenty graded orders on the run, and a stored order with the agent's order on the real line
    for k in range(20):
        sr._graded(db, 9700 + k)
    db.val(f"""INSERT INTO public.ottoq_charge_order_snapshots (order_id, sim_run_id, depot_id, sim_clock, seed, futures,
                                                                win_frac, state, agent_order, code_md5)
               VALUES (9999, '{RUN}', '{DEPOT}', '{T}', 'v4', 12, 0.5,
                       public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}'),
                       '{{"{_vid('C')}": {{"rank": 1, "kind": "dcfc"}}, "{_vid('D')}": {{"rank": 2, "kind": "dcfc"}}}}',
                       'hand')""")
    # the run's own fast charges, after its first order: 20 of 30 minutes, two of them faulted
    _charges(db, "run", RUN, "dcfc", 20, 30, 2, [20, 40], recorded="now() + interval '1 hour'")
    err = _apply(db)
    assert "0635 V2: 32 stored simulations (8 states x both sides x futures 0 and 3) unchanged" in err, err
    m = re.search(r"0635 V3: charge_fault_v1 fit (\d+) in [\d.]+ s, usable true: (.*)", err)
    assert m, err
    # the miniature depot's earlier fixtures charged too (none of them faulted), so the rates are over their minutes as well
    assert re.match(r"dcfc \d\.\d{4} an hour of charging \(36 faults, 36 repairs, median 27\.50 minutes, p90 41\.50\); "
                    r"l2 \d\.\d{4} an hour of charging \(35 faults, 35 repairs, median 120\.00 minutes, p90 120\.00\)$",
                    m.group(2)), m.group(2)
    q = db.json(f"""SELECT jsonb_build_object('hours', round(sum(l.duration_min) / 60.0, 1),
                             'expected', round((sum(l.duration_min) * (public.ottoq_charge_fault_params('{DEPOT}',
                                 (SELECT min(s.recorded_at) FROM public.ottoq_charge_order_snapshots s WHERE s.sim_run_id = '{RUN}'),
                                 interval '21 days') #>> '{{by_kind,dcfc,h}}')::numeric), 1))
                      FROM public.ottoq_charge_duration_ledger l
                     WHERE l.sim_run_id = '{RUN}' AND l.charger_type = 'dcfc' AND l.duration_min > 0""")
    assert (f"0635 V3: out of sample on run a0000000 (the fit through its first order): dcfc: {q['hours']} charging hours "
            f"expected {q['expected']} faults, 2 came;") in err, (q, err)
    assert re.search(r"0635 V4: order 9999 \([\d.]+ s for both rollouts\): without faults \d+ won, \d+ tied, \d+ lost of "
                     r"\d+; with them \d+ won, \d+ tied, \d+ lost \(faults drawn in its 3rd future: kernel \d+, agent \d+\)",
                     err), err
    assert re.search(r"0635 V5: the self-review in \d+ ms; its faults areas: none", err), err
    assert _model(db)["fit_id"] == int(m.group(1)) and _model(db)["usable"] is True


# ── the draws ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0635_the_draws_by_arithmetic(db):
    _through_0634(db)
    _apply(db)
    f = lambda h, u: float(db.val(f"SELECT public.ottoq_fault_draw_minutes({h}, {u})"))  # noqa: E731
    # half the charges at a hazard of 0.01 a minute fault within ln 2 / 0.01 minutes; none with no hazard
    assert abs(f(0.01, 0.5) - math.log(2) / 0.01) < 1e-9 and abs(f(0.02, 0.9) - math.log(10) / 0.02) < 1e-9
    assert f(0, 0.5) == math.inf and f(-1, 0.5) == math.inf and f("NULL", 0.5) == math.inf and f(0.01, "NULL") == math.inf
    assert abs(f(0.01, 1) + math.log(1e-6) / 0.01) < 1e-6                     # a certain draw stays finite
    r = lambda u, a, q=RQSQL: db.val(f"SELECT public.ottoq_fault_repair_draw({q}, {u}, {a})")  # noqa: E731
    # fresh: the curve's quantile at u
    near = lambda x, y: abs(float(x) - y) < 1e-9  # noqa: E731
    assert all(near(r(u, 0), want) for u, want in ((0, 10), (0.25, 60), (0.5, 110), (1, 210)))
    # down 50 minutes on a curve whose share at or below 50 is 0.2: the median of what is left is the quantile at 0.6
    # (130), so 80 more; a quarter of the way into what is left, the quantile at 0.4 (90), so 40 more
    assert near(r(0.5, 50), 80) and near(r(0.25, 50), 40)
    # never under half a minute: at u 0 a charger down 50 is due back now
    assert near(r(0, 50), 0.5)
    # down less than the shortest repair: the curve as fresh, less the minutes down
    assert near(r(0.5, 5), 105)
    # down as long as the longest repair seen: the curve's median again
    assert near(r(0.5, 210), 110) and near(r(0.9, 999), 110)
    # a flat start (the shortest repair, 10, is the curve's lowest 15%): down exactly 10, the rest of the curve above it
    flat = "ARRAY[10,10,10,10,13,16.5,19,22.1,25.8,28,30,38.2,48.2,65.2,81,98.5,118.4,150.8,175.4,238.7,626]::float8[]"
    assert near(r(0.5, 10, flat), 33.2) and near(r(0.5, 9.999, flat), 20.001)
    # more probability, more repair: monotone in u for every time down
    for a in (0, 25, 50, 150):
        xs = [float(r(u / 10, a)) for u in range(11)]
        assert xs == sorted(xs), (a, xs)
    # no curve, or too short a one: NULL
    assert r(0.5, 0, "NULL") == "" and r(0.5, 0, "ARRAY[30]::float8[]") == ""


# ── the fit ───────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0635_the_fit_learns_each_kinds_rate_per_charging_minute_and_its_repair_curve(db):
    _through_0634(db)
    _apply(db)
    _evidence(db, FD)                                            # a depot whose only charges are these
    # what it must not read: another depot's faults, a charge of no minutes, a bay, a repair that is not a number
    _charges(db, "x", EV, "dcfc", 50, 30, 50, [5] * 50, depot=ELSEWHERE)
    _charges(db, "z", EV, "dcfc", 10, 0, 10, [5] * 10, depot=FD)
    _charges(db, "b", EV, "wash_bay", 10, 30, 10, [5] * 10, depot=FD)
    db.val(f"""INSERT INTO public.ottoq_events (actor_type, event_type, event_category, entity_type, entity_id, payload,
                                                payload_hash, sim_run_id, occurred_at)
               VALUES ('twin', 'charge.session_faulted', 'charging', 'ocpp_session', md5('d:1')::uuid,
                       '{{"repair_minutes": "soon"}}', 'h', '{EV}', now() - interval '2 hours')""")
    p = _params(db, depot=FD)
    dk, lk = p["by_kind"]["dcfc"], p["by_kind"]["l2"]
    assert (dk["faults"], dk["charge_min"], dk["h"], dk["repairs"], dk["runs"], dk["population"], dk["usable"]) == \
        (36, 6000, 0.006, 36, 1, "fine_ticks", True), dk
    assert len(dk["rq"]) == 21 and (dk["rq"][0], dk["rq"][10], dk["rq"][18], dk["rq"][20]) == (10, 27.5, 41.5, 45), dk["rq"]
    # L2: the fine run's 10 faults are too few, so both runs count, at both runs' charging minutes
    assert (lk["faults"], lk["charge_min"], lk["h"], lk["repairs"], lk["runs"], lk["population"], lk["usable"]) == \
        (35, 23000, round(35 / 23000, 7), 35, 2, "all_ticks", True), lk
    assert (lk["rq"][0], lk["rq"][20]) == (60, 120), lk["rq"]
    assert (p["n_faults"], p["n_runs"], p["min_n"]) == (71, 2, 30), p
    # nothing after the moment it is fitted through: a charge recorded after it is not read, and a repair whose event
    # came after it is not read either
    _charges(db, "late", CO, "l2", 50, 100, 40, [90] * 40, tick=30, recorded="now() - interval '10 minutes'", depot=FD)
    _charges(db, "lr", CO, "l2", 10, 100, 10, [45] * 10, tick=30, recorded="now() - interval '3 hours'",
             occurred="now() - interval '30 minutes'", depot=FD)
    early = _params(db, "now() - interval '1 hour'", depot=FD)["by_kind"]["l2"]
    assert (early["faults"], early["repairs"], early["charge_min"]) == (45, 35, 24000), early
    late = _params(db, depot=FD)["by_kind"]["l2"]
    assert (late["faults"], late["repairs"], late["charge_min"]) == (85, 85, 29000), late
    # the other depot reads its own: 50 faults, its own curve, all fine-tick
    other = _params(db, depot=ELSEWHERE)["by_kind"]["dcfc"]
    assert (other["faults"], other["rq"][10], other["usable"]) == (50, 5, True), other
    # fit and read: the latest fit is the model, usable when a kind is; its md5 covers what it reads
    fid = int(db.val(f"SELECT public.ottoq_fit_charge_fault_model('{FD}', now(), interval '21 days', 'test')"))
    m = _model(db, FD)
    assert (m["fit_id"], m["model"], m["usable"], m["n_evidence"], m["n_runs"]) == (fid, "charge_fault_v1", True, 121, 2), m
    assert m["params"]["by_kind"]["dcfc"]["h"] == 0.006
    assert db.val(f"SELECT length(code_md5) FROM public.ottoq_charge_fault_fits WHERE fit_id = {fid}") == "32"
    # the latest fit is the model, whatever it says: a thin one is unusable, and the model says so
    _fit_row(db, {"dcfc": KIND_THIN}, usable=False)
    assert _model(db)["usable"] is False and _model(db, FD)["fit_id"] == fid
    rc, _, e = db.run("SELECT public.ottoq_charge_fault_params(NULL, now(), interval '21 days')")
    assert rc != 0 and "a depot is required" in e, e


def test_0635_a_fault_with_too_few_repairs_is_not_usable(db):
    _through_0634(db)
    _apply(db)
    _charges(db, "d", EV, "dcfc", 200, 30, 36, [20] * 29)        # 36 faults, 29 repairs
    dk = _params(db)["by_kind"]["dcfc"]
    assert (dk["faults"], dk["repairs"], dk["usable"]) == (36, 29, False), dk
    fid = int(db.val(f"SELECT public.ottoq_fit_charge_fault_model('{DEPOT}', now(), interval '21 days', 'test')"))
    assert _model(db)["fit_id"] == fid and _model(db)["usable"] is False
    # no usable fit: the state carries no faults
    assert "faults" not in db.json(f"SELECT public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}')")


# ── the state ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def _state(d):
    return d.json(f"SELECT public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}')")


def test_0635_the_state_carries_the_depots_faults_and_the_chargers_down_behind_the_dial(db):
    _through_0634(db)
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_start = '{T}'::timestamptz - interval '60 minutes' "
           f"WHERE sim_run_id = '{RUN}'")
    # F2 went down 20 minutes before the order, on this run's clock; L3 carries a stamp from another run's clock
    db.val(f"""UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted',
                      station_state_changed_at = '{T}'::timestamptz - interval '20 minutes' WHERE charger_id = '{_vid('F2')}'""")
    db.val(f"""UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted',
                      station_state_changed_at = '{T}'::timestamptz + interval '3 days' WHERE charger_id = '{_vid('L3')}'""")
    before = _state(db)
    _apply(db)
    assert _state(db) == before                                   # no fit: 0634's state
    fid = _fit_row(db, {"dcfc": KIND_OK, "l2": KIND_THIN})        # only the fast chargers' faults are usable
    st = _state(db)
    assert {k: v for k, v in st.items() if k != "faults"} == before
    f = st["faults"]
    assert set(f) == {"v", "model", "dcfc", "down"} and (f["v"], f["model"]) == (1, fid), f
    assert f["dcfc"] == {"h": 0.002, "rq": RQ}, f["dcfc"]
    assert f["down"] == [{"id": _vid("F2"), "k": "dcfc", "a": 20, "lb": False}], f["down"]
    fid2 = _fit_row(db, {"dcfc": KIND_OK, "l2": dict(KIND_OK, h=0.0007)})
    f = _state(db)["faults"]
    assert f["model"] == fid2 and f["l2"] == {"h": 0.0007, "rq": RQ}
    # L3's stamp is not this run's: it has been down at least since the run began, 60 minutes
    assert sorted(f["down"], key=lambda x: x["k"]) == [{"id": _vid("F2"), "k": "dcfc", "a": 20, "lb": False},
                                                       {"id": _vid("L3"), "k": "l2", "a": 60, "lb": True}], f["down"]
    # the chargers list never reads a down charger as free
    assert {c["id"] for c in st["chargers"]} == {_vid(c) for c in ("F1", "L1", "L2")}, st["chargers"]
    # a person turns it off for this run: 0634's state exactly
    base._dial(db, "agent_charge_order_faults", 0)
    assert _state(db) == before


# ── the simulator ─────────────────────────────────────────────────────────────────────────────────────────────────────

def _hand_states():
    """States 0634's simulator reads, none with a faults block: a busy line, a down window (0621), a live agent window."""
    cars = [_car("a", md=30, g=40, soc=60, w=5), _car("b", md=25, g=30, soc=40, w=20), _car("c", md=45, ml=200, g=70, w=1),
            _car("d", md=20, g=15, soc=85, w=40, lok=False)]
    ch = [{"id": "F1", "k": "dcfc", "free": 0, "sd": 0}, {"id": "F2", "k": "dcfc", "free": 35, "sd": 0.2, "car": "u"},
          {"id": "L1", "k": "l2", "free": 0, "sd": 0}]
    dn = [dict(ch[0], dn=[[12, 70]]), ch[1], ch[2]]
    return [_line(cars, ch), _line(cars, dn), _line(cars, ch, ttl=30)]


ORDER = {"c": {"rank": 1, "kind": "dcfc"}, "a": {"rank": 2, "kind": "l2"}}


def test_0635_without_faults_the_simulator_is_0634s_key_for_key(db):
    _through_0634(db)
    world = _state(db)
    states = _hand_states() + [world]
    calls = [(s, o, k, t) for s in states for o in (None, ORDER) for k in (0, 1, 3) for t in (True, False)]
    before = [_sim(db, s, o, k, "seed", t) for s, o, k, t in calls]
    _apply(db)
    after = [_sim(db, s, o, k, "seed", t) for s, o, k, t in calls]
    assert after == before
    # and a faults block that cannot fault (no hazard, nothing down) changes nothing but its two counts
    for (s, o, k, t), b in zip(calls, before):
        out = _sim(db, dict(s, faults={"v": 1, "model": 1, "dcfc": {"h": 0, "rq": RQ}, "l2": {"h": 0, "rq": RQ},
                                       "down": []}), o, k, "seed", t)
        assert (out.pop("faults_drawn"), out.pop("requeued")) == (0, 0) and out == b


def test_0635_a_charger_down_at_the_order_comes_back_after_the_rest_of_its_repair(db):
    _through_0634(db)
    _apply(db)
    car = [_car("c", lok=False)]                                   # it can only take a fast charger, and none is up
    flt = lambda a: {"v": 1, "model": 1, "dcfc": {"h": 0.002, "rq": RQ}, "down": [{"id": "D1", "k": "dcfc", "a": a}]}  # noqa: E731
    # the expected future: the curve's conditional median, 80 more minutes for a charger down 50; 110 for a fresh one
    out = _sim(db, _line(car, [], flt(50)))
    assert (out["seats"][0]["s0"], out["seats"][0]["r"], out["faults_drawn"], out["requeued"]) == (80, 110, 0, 0), out
    assert _sim(db, _line(car, [], flt(None)))["seats"][0]["s0"] == 110
    # a sampled future: its own draw, given how long it has been down
    for k in (1, 2, 5):
        back = _repair(db, f"s:{k}:D1:back", 50)
        assert abs(_sim(db, _line(car, [], flt(50)), k=k)["seats"][0]["s0"] - back) <= 0.006, k
    # without the block it never comes back, as before 0635: the car is never seated
    assert _sim(db, _line(car, []))["seated"] == 0
    # a down charger of a kind with no curve is not modelled at all
    out = _sim(db, _line([_car("c", dok=False)], [], {"v": 1, "model": 1, "dcfc": {"h": 0.002, "rq": RQ},
                                                      "down": [{"id": "L9", "k": "l2", "a": 5}]}))
    assert (out["seated"], out["chargers"]) == (0, 0), out


def test_0635_a_drawn_fault_is_0621s_down_window(db):
    _through_0634(db)
    _apply(db)
    # one fast charger and one car owing 30 minutes on it; the seed whose second seat on F1 does not fault inside the
    # 20 minutes the car still owes, at a hazard that puts the first seat's fault at minute 10
    seed = _seed(lambda s: _lam(f"{s}:1:F1:fault:2") >= 2.5 * _lam(f"{s}:1:F1:fault:1"), "dw")
    h = _lam(f"{seed}:1:F1:fault:1") / 10
    flt = {"v": 1, "model": 1, "dcfc": {"h": h, "rq": RQ}, "down": []}
    cars = [_car("c", md=30, lok=False)]
    out = _sim(db, _line(cars, [{"id": "F1", "k": "dcfc", "free": 0, "sd": 0}], flt), k=1, seed=seed)
    # the same future as 0621 reads it: F1 down from the fault for the drawn repair, computed by the same functions
    win = db.json(f"""SELECT jsonb_build_array(jsonb_build_array(x.a, x.a + x.r))
                        FROM (SELECT public.ottoq_fault_draw_minutes({h!r}, public.ottoq_hash_uniform('{seed}:1:F1:fault:1')) AS a,
                                     public.ottoq_fault_repair_draw({RQSQL}, public.ottoq_hash_uniform('{seed}:1:F1:repair:1'), 0) AS r) x""")
    assert abs(win[0][0] - 10) < 1e-9, win
    ref = _sim(db, _line(cars, [{"id": "F1", "k": "dcfc", "free": 0, "sd": 0, "dn": win}]), k=1, seed=seed)
    assert (out.pop("faults_drawn"), out.pop("requeued")) == (1, 0)
    assert out == ref
    s = out["seats"][0]
    assert (s["s0"], s["k0"], s["x"]) == (0, "dcfc", 1) and abs(s["r"] - (win[0][1] + 20)) <= 0.006, s
    # the expected future draws no fault: the car charges through
    out0 = _sim(db, _line(cars, [{"id": "F1", "k": "dcfc", "free": 0, "sd": 0}], flt), k=0, seed=seed)
    assert (out0["seats"][0]["r"], out0["seats"][0]["x"], out0["faults_drawn"]) == (30, 0, 0), out0


def test_0635_a_charge_under_way_that_a_fault_cuts_puts_its_car_back_in_line(db):
    _through_0634(db)
    _apply(db)
    # F1 is charging car u until minute 40; car c waits for it. The seed whose charge under way faults at minute 10 (by
    # the hazard) and whose next two seats on F1 run through
    seed = _seed(lambda s: _lam(f"{s}:1:F1:fault:1") >= 3.5 * _lam(f"{s}:1:F1:fault:0")
                 and _lam(f"{s}:1:F1:fault:2") >= 2.5 * _lam(f"{s}:1:F1:fault:0"), "uw")
    h = _lam(f"{seed}:1:F1:fault:0") / 10
    flt = {"v": 1, "model": 1, "dcfc": {"h": h, "rq": RQ}, "down": []}
    ch = [{"id": "F1", "k": "dcfc", "free": 40, "sd": 0, "car": "u"}]
    cars = [_car("c", md=20, lok=False)]
    r0 = _repair(db, f"{seed}:1:F1:repair:0")
    out = _sim(db, _line(cars, ch, flt), k=1, seed=seed)
    # u rejoins the line at the fault owing its last 30 minutes, takes F1 back at 10 + r0 (it has waited longer for
    # less), and c follows when u is charged: rule 9, the car whose charger faulted is re-queued to finish
    assert (out["faults_drawn"], out["requeued"], out["cars"], out["seated"]) == (1, 1, 1, 1), out
    s = out["seats"][0]
    assert abs(s["s0"] - (40 + r0)) <= 0.006 and abs(s["r"] - (60 + r0)) <= 0.006 and s["x"] == 0, (s, r0)
    # the expected future, and the line without the block: c takes F1 at 40
    assert _sim(db, _line(cars, ch, flt), k=0, seed=seed)["seats"][0]["s0"] == 40
    assert _sim(db, _line(cars, ch), k=1, seed=seed)["seats"][0]["s0"] == 40
    # with the outflow on, the car back in line is never a return: it is a charge finishing, not a second visit
    out = _sim(db, _line(cars, ch, flt, outflow={"ret": {}, "window_min": 90}), k=1, seed=seed)
    assert (out["requeued"], out["returns"], out["returns_seated"], out["return_seats"]) == (1, 0, 0, []), out
    assert abs(out["seats"][0]["s0"] - (40 + r0)) <= 0.006
    # a charger with no car named on it still goes down, and nobody rejoins the line
    out = _sim(db, _line(cars, [dict(ch[0], car=None)], flt), k=1, seed=seed)
    assert (out["faults_drawn"], out["requeued"]) == (1, 0) and abs(out["seats"][0]["s0"] - (10 + r0)) <= 0.006, out


def test_0635_both_sides_of_a_comparison_meet_the_same_faults(db):
    _through_0634(db)
    _apply(db)
    # two cars alike in everything but their names, one fast charger: the kernel seats a first (by id), the agent b.
    # Each side's n-th seat on F1 meets the same fault, so the two futures are one future with the names swapped
    flt = {"v": 1, "model": 1, "dcfc": {"h": 0.03, "rq": RQ}, "down": []}
    st = _line([_car("a", lok=False), _car("b", lok=False)], [{"id": "F1", "k": "dcfc", "free": 0, "sd": 0}], flt, ttl=600,
               pin_min=100000)
    order = {"b": {"rank": 1, "kind": "dcfc"}, "a": {"rank": 2, "kind": "dcfc"}}
    drawn = 0
    for k in range(1, 13):
        kern, agent = _sim(db, st, None, k, "crn"), _sim(db, st, order, k, "crn")
        assert kern["faults_drawn"] == agent["faults_drawn"] and kern["flow_sum"] == agent["flow_sum"], k
        ks = {x["id"]: x for x in kern["seats"]}
        ag = {x["id"]: x for x in agent["seats"]}
        assert [ks["a"][f] for f in ("s0", "r", "x")] == [ag["b"][f] for f in ("s0", "r", "x")], k
        assert [ks["b"][f] for f in ("s0", "r", "x")] == [ag["a"][f] for f in ("s0", "r", "x")], k
        drawn += kern["faults_drawn"]
    assert drawn > 0                                               # the hazard was felt in some future
    # the same call twice is the same future; the rollout counts every future it ran
    assert _sim(db, st, order, 3, "crn") == _sim(db, st, order, 3, "crn")
    ro = db.json(f"SELECT public.ottoq_charge_line_rollout($j${json.dumps(st)}$j$::jsonb, "
                 f"$o${json.dumps(order)}$o$::jsonb, 12, 'crn')")
    assert ro["wins"] + ro["ties"] + ro["losses"] == ro["futures"] and ro["ties"] == ro["futures"], ro


def test_0635_no_curve_draws_nothing_and_an_extreme_hazard_still_ends(db):
    _through_0634(db)
    _apply(db)
    cars = [_car("c", md=30, ml=60)]
    ch = [{"id": "L1", "k": "l2", "free": 0, "sd": 0}]
    # a rate with no repair curve cannot say how long the charger is down: it draws nothing
    out = _sim(db, _line(cars, ch, {"v": 1, "model": 1, "l2": {"h": 1000}, "down": []}), k=1)
    assert (out["faults_drawn"], out["seats"][0]["r"], out["seats"][0]["x"]) == (0, 60, 0), out
    # every seat faults at once: each fault takes the charger down at least half a minute, so the horizon still ends it
    # (an hour's horizon: some 340 faults over three chargers)
    many = [_car(f"c{i}", md=30, ml=60) for i in range(4)]
    chs = [{"id": f"L{i}", "k": "l2", "free": 0, "sd": 0} for i in range(3)]
    flt = {"v": 1, "model": 1, "l2": {"h": 50, "rq": [0.5] * 21}, "down": []}
    st = json.dumps(_line(many, chs, flt, horizon_min=60))
    out = db.json(f"SET statement_timeout = '20s'; "
                  f"SELECT public.ottoq_charge_line_schedule($j${st}$j$::jsonb, NULL, 2, 's', true)")
    # every fault it drew cut a seated car's charge (the cursor reseats the same car first: equal waits and gaps,
    # then the id), and the line ended at the horizon
    assert out["faults_drawn"] > 100 and sum(x["x"] for x in out["seats"]) == out["faults_drawn"], \
        (out["faults_drawn"], [x["x"] for x in out["seats"]])


# ── the realizer ──────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0635_the_realizer_replays_real_faults_in_place_of_the_states(db):
    _through_0634(db)
    _apply(db)
    st = _line([_car("c")], [{"id": "F1", "k": "dcfc", "free": 10, "sd": 0}],
               {"v": 1, "model": 1, "dcfc": {"h": 0.002, "rq": RQ}, "down": [{"id": "D1", "k": "dcfc", "a": 50}]})
    real = {"observed_min": 90, "cars": {}, "inbound": {}, "appeared": [], "chargers": {"F1": {"dn": [[5, 60]]}},
            "back": [{"id": "D1", "k": "dcfc", "free": 30, "sd": 0}]}
    def rz(parts):
        return db.json(f"""SELECT public.ottoq_charge_line_realize($j${json.dumps(st)}$j$::jsonb,
                                  $r${json.dumps(real)}$r$::jsonb, ARRAY{parts}::text[])""")
    with_f = rz(["faults"])
    assert "faults" not in with_f and with_f["chargers"] == [{"id": "F1", "k": "dcfc", "free": 10, "sd": 0, "dn": [[5, 60]]},
                                                             {"id": "D1", "k": "dcfc", "free": 30, "sd": 0}], with_f
    assert rz(["running"])["faults"] == st["faults"]
    assert "faults" not in rz(["running", "faults"])
    # replayed with the faults that happened: F1 down 5-60 and D1 back when it really was (30), so the car takes D1
    # at 30; replayed without them, the state's own: F1 up at 10, and D1 due at the curve's median (80)
    c = _sim(db, rz(["faults"]), k=0)
    assert (c["seats"][0]["s0"], c["chargers"]) == (30, 2), c
    c = _sim(db, rz(["running"]), k=0)
    assert (c["seats"][0]["s0"], c["chargers"]) == (10, 2), c


# ── the self-review ───────────────────────────────────────────────────────────────────────────────────────────────────

def _faults_area(d):
    v = d.json(f"SELECT public.ottoq_arbiter_self_assessment_v3('{DEPOT}', now() - interval '7 days', false)")
    a = [x for x in v["improvement_areas"] if x.get("part") == "faults"]
    assert len(a) == 1, v["improvement_areas"]
    sr._plain(a[0])
    return a[0]


def _graded_carrying_faults(d, oid):
    """A graded order whose check drew faults in its futures: its snapshot's state carries the block."""
    st = _line([], [], {"v": 1, "model": 1, "dcfc": {"h": 0.002, "rq": RQ}, "down": []}, ttl=3)
    d.val(f"""INSERT INTO public.ottoq_charge_order_snapshots (order_id, sim_run_id, depot_id, sim_clock, seed, futures,
                                                               win_frac, state, agent_order, code_md5)
              VALUES ({oid}, '{RUN}', '{DEPOT}', '{T}', 'hand', 12, 0.8, $j${json.dumps(st)}$j$::jsonb, '{{}}', 'hand')""")
    d.val(f"""INSERT INTO public.ottoq_charge_order_hindsight (order_id, sim_run_id, depot_id, sim_clock, window_min,
                observed_min, status, reason, taken, decision, futures, wins, need, p_win, expected, hindsight, outcome,
                moves, forecast, fidelity, realized, code_md5)
              VALUES ({oid}, '{RUN}', '{DEPOT}', '{T}', 90, 90, 'accepted', 'wins_most_futures', true, true, 12, 12, 10, 1.0,
                      '{{"cmp": 1}}', '{{"cmp": 1}}', 'right_take', '{{}}'::text[], '{{}}', '{{}}',
                      '{{"observed_min": 90, "cars": {{}}, "inbound": {{}}, "appeared": [], "chargers": {{}}, "back": []}}',
                      'hand')""")
    sr._attribution(d, oid, {"faults": 1.0})


def test_0635_the_review_marks_orders_made_without_faults_as_history_and_says_what_is_left(db):
    _through_0634(db)
    _apply(db)
    for k in range(12):
        sr._graded(db, 9600 + k)
        sr._attribution(db, 9600 + k, {"faults": 1.0})
    # no usable fault fit: the part is open, and asks for the faults
    a = _faults_area(db)
    assert (a["status"], a["title"]) == ("open", "Charger faults it never sampled moved its verdicts"), a
    assert "Its futures never take a charger down" in a["finding"] and not a["finding"].endswith(NOTE), a
    assert a["action"] == "Sample charger faults in the futures at the depot's own fault rate and repair time.", a
    # the depot has a usable fit, and none of the graded orders drew faults: history until new orders are graded
    _fit_row(db, {"dcfc": KIND_OK})
    a = _faults_area(db)
    assert (a["status"], a["title"], a["action"]) == ("built", "Charger faults it never sampled moved its verdicts", ACT), a
    assert a["finding"].endswith(NOTE), a
    # an unusable fit is no fit
    _fit_row(db, {"dcfc": KIND_THIN}, usable=False)
    assert _faults_area(db)["status"] == "open"
    # an order whose futures drew faults is graded: what is left is which charger and when
    _fit_row(db, {"dcfc": KIND_OK})
    _graded_carrying_faults(db, 9650)
    a = _faults_area(db)
    assert (a["status"], a["title"]) == ("open", "Charger faults moved its verdicts"), a
    assert "Its futures take chargers down at the depot's own rate; what is left is which charger and when." in a["finding"], a
    assert not a["finding"].endswith(NOTE) and a["action"] == "More futures sample this better; nothing to rebuild.", a
