"""db/migrations/0619-0621, EXECUTED: the kernel learns how long a charge takes and when a car comes back, checks the
agent's charge order against its own across sampled futures before taking it, and grades its own checks in hindsight.

WHY THIS EXISTS. db/checks/0415 measured that 0618's check let through orders that cost the depot uptime: it projected
the line on a charge clock that runs 35-140% short and saw no car coming back. 0619 learns both from the engine's own
ledgers; 0620 rolls the line forward in the kernel's order and in the agent's under each of several sampled futures and
takes the agent's order only when it wins most of them; 0621 replays each checked order with what actually happened.
Every claim in those headers that a test can execute is executed here, on the scratch PostgreSQL that
tests/test_agent_charge_order_sql.py uses, with the same miniature depot (two fast chargers, three L2, six cars).

It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)

ROOT = base.ROOT
ARB_STUB = os.path.join(ROOT, "tests", "fixtures", "agent_arbiter_stub.sql")
M0619 = os.path.join(ROOT, "db", "migrations",
                     "0619_the_kernel_learns_how_long_a_charge_takes_and_when_a_car_comes_back.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_vid, _dial, _order, _occupy = base._vid, base._dial, base._order, base._occupy

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture()
def db():
    name = f"ottoq_arb_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        for path in (base.STUB, ARB_STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        base._world(d)
        base._through_0618(d)
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _file(d, path):
    rc, err = d.file(path)
    assert rc == 0, f"{os.path.basename(path)} did not apply: {err}"
    return err


def _charges(d, kind, soc_start, n, ratio, tick_minutes, kw=None, stopped="completed"):
    """n completed charges of `kind` from soc_start to 100 that ran `ratio` times 0614's estimate."""
    kw = kw if kw is not None else (150 if kind == "dcfc" else 19.2)
    tick = "NULL" if tick_minutes is None else tick_minutes
    d.val(f"""INSERT INTO public.ottoq_charge_duration_ledger
                (session_id, source_kind, sim_run_id, depot_id, charger_type, charger_kw, vehicle_kw, battery_kwh,
                 soc_start, soc_end, duration_min, stopped_reason, tick_minutes)
              SELECT gen_random_uuid(), 'live', '{RUN}', '{DEPOT}', '{kind}', {kw}, 250, 75, {soc_start}, 100,
                     public.ottoq_charge_minutes_estimate(75, {soc_start}, 100, {kw}, 250) * {ratio}, '{stopped}', {tick}
                FROM generate_series(1, {n})""")


def _returns(d, n, trigger="low_soc_reserve", soc0=98, soc_dec=50, work_min=70, trip_min=1.5, run=RUN):
    d.val(f"""INSERT INTO public.ottoq_vehicle_dispatches
                (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at, planned_duration_min, soc_at_dispatch_pct,
                 returning_started_at, actual_return_at, return_trigger, return_evidence, status)
              SELECT gen_random_uuid(), '{run}', '{T}'::timestamptz, '{T}'::timestamptz + interval '{work_min + trip_min} minutes',
                     30, {soc0}, '{T}'::timestamptz + interval '{work_min} minutes',
                     '{T}'::timestamptz + interval '{work_min + trip_min} minutes', '{trigger}',
                     jsonb_build_object('soc_at_decision', {soc_dec}), 'returned'
                FROM generate_series(1, {n})""")


def _est(d, model, kind, soc_from):
    kw = 150 if kind == "dcfc" else 19.2
    m = "NULL" if model is None else f"$j${json.dumps(model)}$j$::jsonb"
    return float(d.val(f"SELECT public.ottoq_charge_minutes_learned_with({m}, '{kind}', 75, {soc_from}, 100, {kw}, 250)"))


# ── 0619: the learned estimates ──────────────────────────────────────────────────────────────────────────────────────

def test_0619_applies_with_no_evidence_and_says_so(db):
    err = _file(db, M0619)
    assert "0619 V2 charge_time usable=false from 0 charges" in err, err
    assert "0619 V2 return usable=false from 0 returns" in err, err
    job = db.json("SELECT to_jsonb(j) FROM cron.job j WHERE jobname = 'ottoq-learn-estimates-nightly'")
    assert job["schedule"] == "20 11 * * *" and "ottoq_fit_charge_time_model" in job["command"] \
        and "ottoq_fit_return_model" in job["command"] and "11111111-1111-1111-1111-111111111111" in job["command"]
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0619_%'") == "falsefalse"
    # with no usable fit the learned minutes are 0614's own estimate
    assert _est(db, db.json(f"SELECT public.ottoq_learned_estimate('{DEPOT}', 'charge_time_v1')"), "l2", 90) == \
        float(db.val("SELECT public.ottoq_charge_minutes_estimate(75, 90, 100, 19.2, 250)"))


def test_0619_the_charge_time_model_prefers_fine_ticks_and_falls_back_by_cell(db):
    _file(db, M0619)
    _charges(db, "l2", 90, 40, 1.8, 0.2)        # l2 band d: 40 at fine ticks, ratio 1.8 ...
    _charges(db, "l2", 90, 40, 2.5, 5)          # ... and 40 coarse at 2.5: the cell is fitted on the fine ones
    _charges(db, "l2", 30, 10, 1.3, 0.2)        # l2 band a: only 10 fine, so every charge counts: 10 x 1.3, 40 x 1.5
    _charges(db, "l2", 30, 40, 1.5, 5)
    _charges(db, "l2", 60, 5, 9.0, 0.2)         # l2 band b: 5 charges: fitted, not usable
    _charges(db, "dcfc", 30, 35, 1.4, 0.2)      # dcfc band a: 35 fine at 1.4
    _charges(db, "dcfc", 30, 20, 3.0, 0.2, stopped="fault.station_hardware")   # a charge cut by a fault is not evidence
    eid = int(db.val(f"SELECT public.ottoq_fit_charge_time_model('{DEPOT}', NULL, interval '1 day', 'test')"))
    m = db.json(f"SELECT public.ottoq_learned_estimate('{DEPOT}', 'charge_time_v1')")
    cells = m["params"]["cells"]
    assert m["estimate_id"] == eid and m["usable"] is True and m["n_evidence"] == 170, m
    assert (cells["l2:d"]["factor"], cells["l2:d"]["population"], cells["l2:d"]["n"]) == (1.8, "fine_ticks", 40)
    assert (cells["l2:a"]["factor"], cells["l2:a"]["population"], cells["l2:a"]["n"]) == (1.5, "all_ticks", 50)
    assert cells["l2:b"]["usable"] is False and cells["l2:b"]["n"] == 5
    assert (cells["dcfc:a"]["factor"], cells["dcfc:a"]["log_sd"]) == (1.4, 0)
    # l2:* has 55 fine charges (40 x 1.8, 10 x 1.3, 5 x 9.0): fitted on those, median 1.8
    assert (cells["l2:*"]["population"], cells["l2:*"]["n"], cells["l2:*"]["factor"]) == ("fine_ticks", 55, 1.8)
    base_d = float(db.val("SELECT public.ottoq_charge_minutes_estimate(75, 90, 100, 19.2, 250)"))
    base_b = float(db.val("SELECT public.ottoq_charge_minutes_estimate(75, 60, 100, 19.2, 250)"))
    assert _est(db, m, "l2", 90) == round(base_d * 1.8, 1)
    assert _est(db, m, "l2", 60) == round(base_b * 1.8, 1)      # band b not usable: the kind's own factor
    # the depot-reading form reads the same fit
    assert float(db.val(f"SELECT public.ottoq_charge_minutes_learned('{DEPOT}', 'l2', 75, 90, 100, 19.2, 250)")) == \
        round(base_d * 1.8, 1)
    # rule 9: a learned minute is still a minute to the car's full target, and 0 when nothing is owed
    assert _est(db, m, "l2", 100) == 0


COARSE = "a0000000-0000-0000-0000-0000000005c0"


def test_0619_the_return_model_reads_the_reserve_the_drain_and_the_drive(db):
    _file(db, M0619)
    # the test run: 100 ticks over 50 sim-minutes (fine); a second run at the depot: 100 ticks over 500 (5-minute ticks)
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_start = '{T}'::timestamptz - interval '50 minutes' WHERE sim_run_id = '{RUN}'")
    db.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_start, sim_clock_current,
                                                 started_at, run_by, policy)
              VALUES ('{COARSE}', '{DEPOT}', 'completed', 100, '{T}'::timestamptz - interval '500 minutes', '{T}', now(),
                      'throughput_sweep', 'otto_q')""")
    _returns(db, 40)                                                         # 98% -> 50% in 70 minutes, 1.5 home
    _returns(db, 10, trigger="service_interval_due", soc_dec=80, work_min=30, trip_min=4)
    _returns(db, 7, trigger="prime_inbound", soc_dec=80)                     # the fixture's t=0 cars: not evidence
    _returns(db, 40, soc_dec=45, trip_min=5, run=COARSE)                     # at 5-minute ticks a drive reads as 5
    db.val(f"SELECT public.ottoq_fit_return_model('{DEPOT}', NULL, interval '1 day', 'test')")
    r = db.json(f"SELECT public.ottoq_learned_estimate('{DEPOT}', 'return_v1')")
    p = r["params"]
    assert r["usable"] is True and r["n_evidence"] == 50 and p["population"] == "fine_ticks", r
    assert (p["threshold_soc"], p["trip_min"], p["n_low_soc"], p["n_returns"]) == (50, 1.5, 40, 50), p
    assert abs(p["drain_pct_per_min"] - 48 / 70) < 1e-3 and p["drain_log_sd"] == 0, p
    assert p["other_share"] == 0.2 and p["other_triggers"] == {"service_interval_due": 10}, p
    # 10 other returns over 40 x 70 + 10 x 30 = 3,100 working minutes
    assert abs(p["other_per_work_hour"] - 10 / (3100 / 60)) < 1e-3, p
    # what the forecast cannot see, over every run whichever was fitted
    assert (p["n_returns_all_ticks"], p["other_share_all_ticks"]) == (90, round(10 / 90, 4)), p
    # with too few reserve returns at fine ticks, every run is read
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_start = '{T}'::timestamptz - interval '500 minutes' WHERE sim_run_id = '{RUN}'")
    db.val(f"SELECT public.ottoq_fit_return_model('{DEPOT}', NULL, interval '1 day', 'test')")
    p = db.json(f"SELECT public.ottoq_learned_estimate('{DEPOT}', 'return_v1')")["params"]
    assert (p["population"], p["n_low_soc"], p["threshold_soc"]) == ("all_ticks", 80, 47.5), p


def test_0619_a_thin_return_ledger_is_fitted_and_not_usable(db):
    _file(db, M0619)
    _returns(db, 12)
    db.val(f"SELECT public.ottoq_fit_return_model('{DEPOT}', NULL, interval '1 day', 'test')")
    assert db.json(f"SELECT public.ottoq_learned_estimate('{DEPOT}', 'return_v1')")["usable"] is False


def test_0619_the_ledger_is_append_only(db):
    _file(db, M0619)
    rc, _, err = db.run("UPDATE public.ottoq_learned_estimates SET note = 'x'")
    assert rc != 0 and "append-only" in err, err
    rc, _, err = db.run("DELETE FROM public.ottoq_learned_estimates")
    assert rc != 0 and "append-only" in err, err


def test_0619_refuses_an_estimate_it_was_not_written_against(db):
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_charge_minutes_estimate(p_batt_kwh numeric, p_soc_from numeric,
                p_soc_to numeric, p_charger_kw numeric, p_inlet_kw numeric) RETURNS numeric
              LANGUAGE sql IMMUTABLE AS $f$ SELECT 1::numeric $f$""")
    rc, err = db.file(M0619)
    assert rc != 0 and "0619 P1" in err and "ottoq_charge_minutes_estimate" in err, err


# ── 0620: the kernel takes the agent's order only when it wins the expected future and most sampled ones ─────────────

M0620 = os.path.join(ROOT, "db", "migrations", "0620_the_kernel_takes_an_agent_order_only_when_it_wins_most_futures.sql")


def _through_0620(d):
    _file(d, M0619)
    return _file(d, M0620)


def _state(d):
    return d.json(f"SELECT public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}')")


def _omap(order):
    """[(name, kind)] -> the door's map {vehicle_id: {rank, kind}}."""
    return {_vid(n): {"rank": r, "kind": k} for r, (n, k) in enumerate(order, 1)}


def _sim(d, state, order=None, scenario=0, seed="t"):
    o = "NULL" if order is None else f"$j${json.dumps(_omap(order))}$j$::jsonb"
    return d.json(f"SELECT public.ottoq_charge_line_simulate($j${json.dumps(state)}$j$::jsonb, {o}, {scenario}, '{seed}')")


def _rollout(d, state, order, futures=12, seed="t"):
    return d.json(f"""SELECT public.ottoq_charge_order_verdict_v2(public.ottoq_charge_line_rollout(
                        $j${json.dumps(state)}$j$::jsonb, $j${json.dumps(_omap(order))}$j$::jsonb, {futures}, '{seed}'), 0.8)""")


def _spread_model(d, log_sd=0.3):
    """A usable charge_time_v1 for the depot: factor 1 (0614's minutes) with a log spread, so the futures differ."""
    cells = {f"{k}:{b}": {"n": 100, "runs": 5, "usable": True, "population": "fine_ticks", "factor": 1, "log_sd": log_sd,
                          "p10": 0.7, "p90": 1.4} for k in ("dcfc", "l2") for b in ("a", "b", "c", "d", "*")}
    d.val(f"""INSERT INTO public.ottoq_learned_estimates (depot_id, model, n_evidence, n_runs, usable, params, code_md5, note)
              VALUES ('{DEPOT}', 'charge_time_v1', 1000, 5, true, $j${json.dumps({"cells": cells})}$j$::jsonb, 'test', 'test')""")


def test_0620_applies_and_its_checks_run(db):
    err = _through_0620(db)
    assert "0620 V4: no twin run is running" in err or "0620 V4 on run" in err, err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0620_%'") == "falsefalse"
    dials = db.json("""SELECT jsonb_object_agg(param_key, jsonb_build_array(default_value, min_value, max_value, agent_writable))
                         FROM public.ottoq_policy_param_catalog WHERE param_key IN ('agent_charge_order_futures',
                                                                                    'agent_charge_order_win_frac')""")
    assert dials == {"agent_charge_order_futures": [12, 1, 64, False], "agent_charge_order_win_frac": [0.8, 0.5, 1, False]}
    assert db.val("SELECT class FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_charge_order_snapshots'") == "evidence"


def test_0620_the_state_is_the_line_the_chargers_and_the_clock(db):
    _through_0620(db)
    s = _state(db)
    # five free chargers; six cars in the kernel's order with 0614's minutes (no usable fit yet: factor 1.0)
    assert [base.NAMES[c["id"]] for c in s["cars"]] == ["I", "P", "B", "A", "D", "C"], s["cars"]
    assert len(s["chargers"]) == 5 and all(c["free"] == 0 for c in s["chargers"])
    i = s["cars"][0]
    assert (i["imm"], i["md"], i["ml"], i["due"]) == (True, 41, 141, 40), i
    # the order's life in minutes: 15 ticks x the run's minutes a tick (no clock start on this run: 0.25)
    assert (s["tick_min"], s["ttl_min"], s["pin_min"]) == (0.25, 3.75, 90), s
    assert s["inbound"] == [] and s["models"]["return_usable"] is False


def test_0620_the_kernels_line_rolled_forward_by_hand(db):
    # I 41 on a fast charger (due 40: a minute late); P 70, B 94, A 117 on the L2s; D 15 on the other fast charger;
    # C waits for it and is ready at 15 + 45 = 60. 397 minutes in the depot, as 0618's projection had it.
    _through_0620(db)
    k = _sim(db, _state(db))
    assert (k["cars"], k["seated"], k["with_due"], k["on_time"], k["late_sum"], k["flow_sum"]) == (6, 6, 1, 0, 1, 397), k
    assert (k["on_dcfc"], k["on_l2"]) == (3, 3), k


def test_0620_the_kernels_own_order_sent_by_the_agent_changes_nothing(db):
    _through_0620(db)
    v = _rollout(db, _state(db), [("B", "either"), ("A", "either"), ("D", "either"), ("C", "either")])
    assert v["take"] is False and v["reason"] == "same_as_kernel" and v["futures"] == 1, v
    rec = _order(db, [("B", "either"), ("A", "either"), ("D", "either"), ("C", "either")])
    assert rec["status"] == "refused" and rec["projection"]["reason"] == "same_as_kernel", rec
    assert db.json(f"SELECT public.ottoq_agent_charge_order_live('{RUN}', 100)") == {}


def test_0620_low_batteries_sent_to_the_only_free_l2s_lose_the_expected_future(db):
    _through_0620(db)
    _occupy(db, ["F1", "F2"])                    # a car out at work holds each fast charger: only the L2 are offered
    v = _rollout(db, _state(db), [("C", "l2"), ("A", "l2"), ("B", "l2")])
    assert v["take"] is False and v["reason"] == "worse_in_expected_future", v
    assert v["agent"]["flow_sum"] > v["kernel"]["flow_sum"], v


def test_0620_a_car_made_ready_by_its_due_time_on_a_fast_charger_wins_every_future(db):
    _through_0620(db)
    base._car(db, "E", 40, 1)
    db.val(f"UPDATE public.ottoq_visit_needs SET dispatch_due_at = '{T}'::timestamptz + interval '60 minutes' "
           f"WHERE vehicle_id = '{_vid('E')}'")
    _spread_model(db, 0.3)                       # the futures now differ, the same draws on both sides
    v = _rollout(db, _state(db), [("E", "dcfc")])
    assert v["take"] is True and v["reason"] == "wins_most_futures" and v["expected_by"] == "on_time", v
    assert v["wins"] >= v["need"] == 10 and v["futures"] == 12, v
    assert v["agent"]["on_time"] == v["kernel"]["on_time"] + 1, v
    rec = _order(db, [("E", "dcfc")])
    assert rec["status"] == "accepted" and rec["projection"]["reason"] == "wins_most_futures", rec


def test_0620_the_futures_are_seeded_and_shared_by_both_sides(db):
    _through_0620(db)
    _spread_model(db, 0.3)
    s = _state(db)
    k1, k1b, k2 = _sim(db, s, None, 1, "x"), _sim(db, s, None, 1, "x"), _sim(db, s, None, 2, "x")
    assert k1 == k1b and k1 != k2                # a pure function of (state, order, scenario, seed)
    assert _sim(db, s, None, 0, "x") == _sim(db, s, None, 0, "y")   # the expected future draws nothing
    order = [("C", "dcfc"), ("A", "l2")]
    r1 = db.json(f"""SELECT public.ottoq_charge_line_rollout($j${json.dumps(s)}$j$::jsonb,
                       $j${json.dumps(_omap(order))}$j$::jsonb, 12, 'x')""")
    r2 = db.json(f"""SELECT public.ottoq_charge_line_rollout($j${json.dumps(s)}$j$::jsonb,
                       $j${json.dumps(_omap(order))}$j$::jsonb, 12, 'x')""")
    assert r1 == r2 and r1["futures"] == 12 and r1["wins"] + r1["ties"] + r1["losses"] == 12, r1
    # common random numbers: an order equal to the kernel's ties in every future, perturbed or not
    same = db.json(f"""SELECT public.ottoq_charge_line_compare(public.ottoq_charge_line_simulate(s, NULL, 3, 'x'),
                                                               public.ottoq_charge_line_simulate(s, '{{}}'::jsonb, 3, 'x'))
                        FROM (SELECT $j${json.dumps(s)}$j$::jsonb AS s) q""")
    assert same["cmp"] == 0 and same["by"] == "tie", same


def test_0620_cars_coming_home_join_the_line_when_they_arrive(db):
    _through_0620(db)
    # the return model: a working car is called home at 50%, drains 0.5% a minute, drives 2 minutes home
    db.val(f"""INSERT INTO public.ottoq_learned_estimates (depot_id, model, n_evidence, n_runs, usable, params, code_md5, note)
               VALUES ('{DEPOT}', 'return_v1', 100, 5, true, '{{"threshold_soc": 50, "drain_pct_per_min": 0.5,
                       "drain_log_sd": 0.1, "trip_min": 2, "other_share": 0.1}}', 'test', 'test')""")
    w, h = _vid("W"), _vid("H")
    for name, soc in (("W", 70), ("H", 30)):
        base._car(db, name, soc, 0, state="deployed")
        db.val(f"DELETE FROM public.ottoq_visit_needs WHERE vehicle_id = '{_vid(name)}'")
    db.val(f"""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                            planned_duration_min, status)
               VALUES ('{w}', '{RUN}', '{T}'::timestamptz - interval '40 minutes', '{T}'::timestamptz + interval '1 hour', 30, 'active'),
                      ('{h}', '{RUN}', '{T}'::timestamptz - interval '60 minutes', '{T}'::timestamptz + interval '6 minutes', 30, 'returning')""")
    inb = {base.NAMES[r["vehicle_id"]]: r for r in db.json(
        f"""SELECT jsonb_agg(to_jsonb(i)) FROM public.ottoq_charge_line_inbound('{RUN}', '{DEPOT}', '{T}', 180, NULL) i""")}
    # W at 70%: (70 - 50) / 0.5 + 2 = 42 minutes, arriving at 50 - 0.5 x 2 = 49%; H driving home: 6 minutes, 27%
    assert (inb["W"]["eta_min"], inb["W"]["soc_at_arrival"], inb["W"]["source"]) == (42, 49, "forecast"), inb
    assert (inb["H"]["eta_min"], inb["H"]["soc_at_arrival"], inb["H"]["source"]) == (6, 27, "returning"), inb
    s = _state(db)
    assert [base.NAMES[c["id"]] for c in s["inbound"]] == ["H", "W"], s["inbound"]
    k = _sim(db, s)
    # both come home and are seated after they arrive; their minutes count from their arrival
    assert (k["cars"], k["inbound"], k["seated"]) == (8, 2, 8), k
    assert k["flow_sum"] > 397 and k["line_flow_sum"] == 397, k
    # the board sees them too
    b = db.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')")
    assert [(x["name"], x["eta_min"], x["source"]) for x in b["arriving"]] == [("H", 6, "returning"), ("W", 42, "forecast")]
    assert b["contention"]["arriving_60_min"] == 2 and b["check"]["return_model"]["reserve_soc"] == 50


def test_0620_the_door_keeps_the_state_it_judged_and_the_usage_says_how_it_went(db):
    _through_0620(db)
    _occupy(db, ["F1", "F2"])
    refused = _order(db, [("C", "l2"), ("A", "l2"), ("B", "l2")])
    assert refused["status"] == "refused" and refused["projection"]["reason"] == "worse_in_expected_future", refused
    snap = db.json(f"SELECT to_jsonb(s) FROM public.ottoq_charge_order_snapshots s WHERE order_id = {refused['order_id']}")
    assert snap["futures"] == 12 and float(snap["win_frac"]) == 0.8 and len(snap["state"]["cars"]) == 6, snap
    assert snap["agent_order"][_vid("C")] == {"rank": 1, "kind": "l2"} and len(snap["code_md5"]) == 32
    same = _order(db, [("B", "either")])
    assert same["projection"]["reason"] in ("same_as_kernel", "worse_in_expected_future", "no_better_in_expected_future")
    u = db.json(f"SELECT public.ottoq_agent_charge_order_usage('{RUN}', 5)")
    assert u["orders_refused"] == 2 and sum(u["refused_by_reason"].values()) == 2, u
    first = next(o for o in u["by_order"] if o["order_id"] == refused["order_id"])
    assert first["verdict"] == "worse_in_expected_future" and first["futures"] == 12 and first["need"] == 10, first
    rc, _, err = db.run("DELETE FROM public.ottoq_charge_order_snapshots")
    assert rc != 0 and "append-only" in err, err


def test_0620_the_board_times_charges_by_the_learned_clock_and_says_how_tight_the_line_is(db):
    _through_0620(db)
    b = db.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')")
    # six cars waiting, five chargers free and none freeing within 15 minutes: one car cannot plug in yet
    assert b["contention"] == {"waiting": 6, "free_now": 5, "freeing_15_min": 0, "arriving_60_min": 0,
                               "pressure": "congested"}, b["contention"]
    # two cars leave the line: four waiting, five free, nothing for an order to decide
    db.val(f"UPDATE public.vehicles SET current_state = 'deployed' WHERE id IN ('{_vid('C')}', '{_vid('D')}')")
    b = db.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')")
    assert (b["contention"]["waiting"], b["contention"]["pressure"]) == (4, "none"), b["contention"]
    db.val(f"UPDATE public.vehicles SET current_state = 'arrived_at_gate' WHERE id IN ('{_vid('C')}', '{_vid('D')}')")
    assert b["check"]["futures"] == 12 and float(b["check"]["win_frac"]) == 0.8
    i = next(c for c in b["cars"] if c["name"] == "I")
    assert (i["min_on_dcfc"], i["min_on_l2"]) == (41, 141), i              # no usable fit: 0614's minutes
    _spread_model(db, 0.2)
    db.val(f"""INSERT INTO public.ottoq_learned_estimates (depot_id, model, n_evidence, n_runs, usable, params, code_md5, note)
               SELECT depot_id, model, n_evidence, n_runs, usable,
                      jsonb_set(params, '{{cells,dcfc:a,factor}}', '2'), code_md5, 'test x2'
                 FROM public.ottoq_learned_estimates WHERE model = 'charge_time_v1' ORDER BY estimate_id DESC LIMIT 1""")
    b = db.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')")
    i = next(c for c in b["cars"] if c["name"] == "I")
    assert (i["min_on_dcfc"], i["min_on_l2"]) == (82, 141), i              # I at 40% is band a: the fast charger x2
    assert b["check"]["charge_time_factors"]["dcfc:a"] == 2


def test_0620_an_order_the_kernel_cannot_check_is_never_taken(db):
    _through_0620(db)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_charge_line_rollout(p_state jsonb, p_order jsonb, p_futures integer,
                p_seed text) RETURNS jsonb LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION 'no rollout today'; END $f$""")
    rec = _order(db, [("C", "dcfc")])
    assert rec["ok"] is True and rec["status"] == "refused" and rec["projection"]["reason"] == "rollout_failed", rec
    assert "no rollout today" in rec["projection"]["error"]
    assert db.val(f"SELECT count(*) FROM public.ottoq_charge_order_snapshots WHERE order_id = {rec['order_id']}") == "0"
    assert db.json(f"SELECT public.ottoq_agent_charge_order_live('{RUN}', 100)") == {}


def test_0620_refuses_a_door_it_was_not_written_against(db):
    _file(db, M0619)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_agent_charge_order_record(p_sim_run_id uuid, p_board_tick bigint,
                p_chain_id text, p_model text, p_order jsonb) RETURNS jsonb
              LANGUAGE sql AS $f$ SELECT '{}'::jsonb $f$""")
    rc, err = db.file(M0620)
    assert rc != 0 and "0620 P1" in err and "the door" in err, err


# ── 0621: the kernel grades its own check in hindsight ────────────────────────────────────────────────────────────────

M0621 = os.path.join(ROOT, "db", "migrations", "0621_the_kernel_grades_its_own_check_in_hindsight.sql")


def _through_0621(d):
    _through_0620(d)
    return _file(d, M0621)


def test_0621_applies_and_its_checks_run(db):
    err = _through_0621(db)
    assert "0621 V1: the schedule returns 0620's results on 40 cases" in err, err
    assert "0621 V2: a fault stops the charge" in err, err
    assert "0621 V3: 0 stored snapshots replay" in err, err
    assert "0621 V4: no running twin run has an order whose window has closed" in err, err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0621_%'") == "falsefalse"
    assert db.json("""SELECT jsonb_object_agg(table_name, class) FROM public.ottoq_run_scope_registry
                       WHERE table_name IN ('ottoq_charge_order_hindsight', 'ottoq_charge_order_attribution')""") == \
        {"ottoq_charge_order_hindsight": "evidence", "ottoq_charge_order_attribution": "evidence"}
    jobs = db.json("SELECT jsonb_object_agg(jobname, schedule) FROM cron.job WHERE jobname LIKE 'ottoq-arbiter-%'")
    assert jobs == {"ottoq-arbiter-hindsight-nightly": "*/10 11,12 * * *", "ottoq-arbiter-assess-nightly": "55 12 * * *"}


def _rand_case(rng, i):
    """A random line: waits, gaps, batteries, due times, plug limits, cars coming home, chargers busy, a random order."""
    cars = []
    for k in range(rng.randint(1, 9)):
        soc = rng.randint(5, 95)
        cars.append({"id": f"c{i}_{k}", "w": rng.choice([0, 3, 15, 40, 95, 130]), "g": max(100 - soc, 1),
                     "imm": rng.random() < 0.15, "soc": soc, "due": rng.choice([None, -10, 20, 60, 150]),
                     "dok": rng.random() > 0.1, "lok": rng.random() > 0.05,
                     "md": rng.randint(8, 70), "ml": rng.randint(20, 300), "sd": rng.choice([0, 0.2, 0.4]),
                     "sl": rng.choice([0, 0.3])})
    inbound = []
    for k in range(rng.randint(0, 4)):
        soc = rng.randint(10, 80)
        inbound.append({"id": f"i{i}_{k}", "eta": rng.randint(0, 170), "src": rng.choice(["forecast", "returning"]),
                        "esd": rng.choice([0, 0.1, 0.3]), "trip": rng.choice([0, 1.5, 4]), "soc": soc, "g": 100 - soc,
                        "imm": False, "w": 0, "md": rng.randint(10, 60), "ml": rng.randint(30, 280),
                        "sd": 0.25, "sl": 0.3})
    chargers = [{"id": f"s{i}_{k}", "k": rng.choice(["dcfc", "l2"]), "free": rng.choice([0, 0, 5, 30, 90]),
                 "sd": rng.choice([0, 0.2])} for k in range(rng.randint(1, 6))]
    state = {"ttl_min": rng.choice([0, 3.2, 10]), "pin_min": 90, "horizon_min": rng.choice([120, 480]),
             "cars": cars, "inbound": inbound, "chargers": chargers}
    pool = [c["id"] for c in cars] + [c["id"] for c in inbound]
    rng.shuffle(pool)
    order = {cid: {"rank": r, "kind": rng.choice(["dcfc", "l2", "either"])}
             for r, cid in enumerate(pool[:rng.randint(0, len(pool))], 1)}
    return state, (order or None)


def test_0621_the_schedule_is_0620s_simulator_on_random_lines(db):
    import random
    rng = random.Random(621)
    cases = [_rand_case(rng, i) for i in range(120)]
    _through_0620(db)
    db.val("CREATE TABLE public.t0621 (i int, sc int, state jsonb, ord jsonb, r jsonb)")
    rows = ", ".join(f"({i}, {sc}, $j${json.dumps(st)}$j$::jsonb, "
                     f"{'NULL' if o is None else '$j$' + json.dumps(o) + '$j$::jsonb'}, NULL)"
                     for i, (st, o) in enumerate(cases) for sc in (0, 1, 2))
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as fh:
        fh.write(f"INSERT INTO public.t0621 VALUES {rows};\n")
    try:
        _file(db, fh.name)
    finally:
        os.unlink(fh.name)
    db.val("UPDATE public.t0621 SET r = public.ottoq_charge_line_simulate(state, ord, sc, 'rand')")
    _file(db, M0621)
    bad = db.json("""SELECT COALESCE(jsonb_agg(jsonb_build_object('i', i, 'sc', sc)), '[]'::jsonb) FROM public.t0621
                      WHERE r IS DISTINCT FROM public.ottoq_charge_line_simulate(state, ord, sc, 'rand')
                         OR r IS DISTINCT FROM (public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true) - 'seats')""")
    assert bad == [], bad[:5]
    assert db.val("SELECT count(*) FROM public.t0621") == "360"
    # and the trace agrees with the totals it reports
    agree = db.json("""SELECT jsonb_build_object('n', count(*), 'bad', count(*) FILTER (WHERE
                         (x ->> 'seated')::int <> (SELECT count(*) FROM jsonb_array_elements(x -> 'seats') s WHERE s.value ->> 'r' IS NOT NULL)
                         OR (x ->> 'on_dcfc')::int <> (SELECT count(*) FROM jsonb_array_elements(x -> 'seats') s WHERE s.value ->> 'k' = 'dcfc')))
                         FROM (SELECT public.ottoq_charge_line_schedule(state, ord, sc, 'rand', true) AS x FROM public.t0621) q""")
    assert agree == {"n": 360, "bad": 0}, agree


THREE = {"ttl_min": 5, "pin_min": 90, "horizon_min": 480,
         "cars": [{"id": "a", "w": 0, "g": 70, "imm": False, "soc": 30, "due": None, "md": 40, "ml": 200},
                  {"id": "b", "w": 0, "g": 10, "imm": False, "soc": 90, "due": None, "md": 20, "ml": 30},
                  {"id": "c", "w": 0, "g": 40, "imm": False, "soc": 60, "due": 50, "md": 30, "ml": 120}],
         "inbound": [], "chargers": [{"id": "f", "k": "dcfc", "free": 0}, {"id": "l", "k": "l2", "free": 0}]}


def _sched(d, state, order=None, scenario=0):
    o = "NULL" if order is None else f"$j${json.dumps(order)}$j$::jsonb"
    return d.json(f"SELECT public.ottoq_charge_line_schedule($j${json.dumps(state)}$j$::jsonb, {o}, {scenario}, 's', true)")


def test_0621_moves_name_what_the_order_changed(db):
    _through_0621(db)
    order = {"c": {"rank": 1, "kind": "dcfc"}, "a": {"rank": 2, "kind": "l2"}}
    k, a = _sched(db, THREE), _sched(db, THREE, order)
    moves = db.json(f"""SELECT to_jsonb(public.ottoq_charge_order_moves($j${json.dumps(THREE)}$j$::jsonb,
                          $j${json.dumps(k)}$j$::jsonb, $j${json.dumps(a)}$j$::jsonb))""")
    # c, late on the L2 in the kernel's line (120 against due 50), made on time on the fast charger; a at 30% put on
    # the L2 where the kernel's line put it on the fast charger
    assert moves == ["due_rescue_fast", "kind_swap", "low_battery_on_l2"], moves
    same = db.json(f"""SELECT to_jsonb(public.ottoq_charge_order_moves($j${json.dumps(THREE)}$j$::jsonb,
                         $j${json.dumps(k)}$j$::jsonb, $j${json.dumps(k)}$j$::jsonb))""")
    assert same == []


def test_0621_realize_puts_each_part_in_place(db):
    _through_0621(db)
    st = {"ttl_min": 3, "pin_min": 90, "horizon_min": 480,
          "cars": [{"id": "a", "w": 0, "g": 50, "soc": 50, "md": 30, "ml": 60}],
          "inbound": [{"id": "h", "eta": 6, "src": "forecast", "esd": 0.1, "trip": 2, "soc": 27, "g": 73, "w": 0,
                       "imm": False, "md": 40, "ml": 200, "sd": 0.2, "sl": 0.3}],
          "chargers": [{"id": "f", "k": "dcfc", "free": 0}, {"id": "l", "k": "l2", "free": 25, "sd": 0.2}]}
    real = {"observed_min": 90,
            "cars": {"a": {"s0": 1, "k0": "l2", "m": 90, "cen": False, "end": "completed"}},
            "inbound": {"h": {"arrived": True, "eta": 9, "soc": 25, "g": 75, "md": 42, "ml": 231, "sd": 0.2, "sl": 0.3,
                              "due": 70, "imm": False, "s0": 9.5, "k0": "dcfc", "m": 50, "cen": True, "end": "running"}},
            "appeared": [{"id": "x", "src": "appeared", "how": "returned", "eta": 20, "esd": 0, "trip": 0, "w": 0,
                          "soc": 18, "g": 82, "imm": False, "due": None, "dok": True, "lok": True, "md": 45, "ml": 230,
                          "sd": 0.2, "sl": 0.3, "s0": 40, "k0": "dcfc", "m": 60, "cen": False, "end": "completed"}],
            "chargers": {"l": {"free": 20, "cen": False}, "f": {"dn": [[30, 150]]}},
            "back": [{"id": "z", "k": "l2", "free": 30, "sd": 0}], "faults": 1, "unmodeled_sessions": 0}

    def rz(parts):
        return db.json(f"""SELECT public.ottoq_charge_line_realize($j${json.dumps(st)}$j$::jsonb, $j${json.dumps(real)}$j$::jsonb,
                                                                  ARRAY{parts}::text[])""")
    assert rz([]) == st
    s = rz(["arrivals"])
    h = s["inbound"][0]
    assert (h["eta"], h["soc"], h["due"], h["src"], h["esd"], h["md"]) == (9, 25, 70, "arrived", 0, 42), h
    assert s["cars"] == st["cars"] and s["chargers"] == st["chargers"]
    s = rz(["charge_times"])
    assert (s["cars"][0]["ml"], s["cars"][0]["md"]) == (90, 45), s["cars"][0]     # 90 on the L2; the fast one x 30/60
    # h was still charging at the cut after 50 minutes on a fast charger: at least the check's 40
    assert (s["inbound"][0]["md"], s["inbound"][0]["ml"]) == (50, 250), s["inbound"][0]
    s = rz(["arrivals", "charge_times"])
    assert s["inbound"][0]["md"] == 50 and s["inbound"][0]["ml"] == 275, s["inbound"][0]   # 50 x 231 / 42
    s = rz(["appeared"])
    assert [c["id"] for c in s["inbound"]] == ["h", "x"] and "s0" not in s["inbound"][1] and s["inbound"][1]["md"] == 45
    assert rz(["appeared", "charge_times"])["inbound"][1]["md"] == 60
    s = rz(["running"])
    assert [c["free"] for c in s["chargers"]] == [0, 20]
    s = rz(["faults"])
    assert s["chargers"][0]["dn"] == [[30, 150]] and s["chargers"][-1] == {"id": "z", "k": "l2", "free": 30, "sd": 0}
    assert len(s["chargers"]) == 3


def _session(d, car, stall, start, end=None, status="completed", reason=None, soc_start=None, run=RUN):
    sid = str(uuid.uuid4())
    end_sql = "NULL" if end is None else f"'{T}'::timestamptz + interval '{end} minutes'"
    reason = reason if reason is not None else (status if status != "active" else None)
    d.val(f"""INSERT INTO public.ocpp_sessions (id, depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id,
                                                connector_id, status, started_at, ended_at, soc_start, stopped_reason, sim_run_id)
              VALUES ('{sid}', '{DEPOT}', '{_vid(stall)}', '{_vid(car)}', '{stall}', '{sid}', 1, 1, '{status}',
                      '{T}'::timestamptz + interval '{start} minutes', {end_sql},
                      {'NULL' if soc_start is None else soc_start}, {'NULL' if reason is None else repr(reason)}, '{run}')""")
    return sid


def _fault_event(d, session, at, repair):
    d.val(f"""INSERT INTO public.ottoq_events (actor_type, event_type, event_category, entity_type, entity_id, payload,
                                               payload_hash, sim_run_id, sim_clock_at)
              VALUES ('twin', 'charge.session_faulted', 'charging', 'ocpp_session', '{session}',
                      '{{"repair_minutes": {repair}, "auto_rerouted": true}}', 'h', '{RUN}',
                      '{T}'::timestamptz + interval '{at} minutes')""")


def _a_morning(d):
    """0621's miniature morning. At T: the six cars of the line; H driving home (due at minute 6); W at work, forecast
    home; Y charging on L3 since minute -30; L4 faulted at minute -60 for 90 minutes; Z in a bay. The order puts C on a
    fast charger. After it: I charges on F1 0.25-45.25; C on F2 0.25-60; P on L1 from 0.25, still charging at the cut;
    B on L2 from 0.25 until its charger faults at 30 (down 120); Y finishes at 20; A on L3 25-85; H home at 9 with 25%,
    due at 70, on F1 from 46; X dispatched after the order, home at 20 with 18%, on L4 from 31; Z out of the bay onto F2
    at 61. The run's clock reaches minute 100; the window is 90."""
    _file(d, M0619)
    _file(d, M0620)
    d.val(f"""INSERT INTO public.ottoq_learned_estimates (depot_id, model, n_evidence, n_runs, usable, params, code_md5, note)
              VALUES ('{DEPOT}', 'return_v1', 100, 5, true, '{{"threshold_soc": 50, "drain_pct_per_min": 0.5,
                      "drain_log_sd": 0.1, "trip_min": 2, "other_share": 0.1}}', 'test', 'test')""")
    _spread_model(d, 0.2)
    _file(d, M0621)
    for name, soc, state in (("W", 70, "deployed"), ("H", 30, "deployed"), ("Y", 60, "charging_l2"),
                             ("Z", 50, "in_detail_bay")):
        base._car(d, name, soc, 0, state=state)
        d.val(f"DELETE FROM public.ottoq_visit_needs WHERE vehicle_id = '{_vid(name)}'")
    d.val(f"""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                           planned_duration_min, status)
              VALUES ('{_vid('W')}', '{RUN}', '{T}'::timestamptz - interval '40 minutes', '{T}'::timestamptz + interval '1 hour', 30, 'active'),
                     ('{_vid('H')}', '{RUN}', '{T}'::timestamptz - interval '60 minutes', '{T}'::timestamptz + interval '6 minutes', 30, 'returning')""")
    base._stall(d, "L4", "l2", 19.2)
    d.val(f"UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted' WHERE charger_id = '{_vid('L4')}'")
    d.val(f"UPDATE public.stalls SET current_vehicle_id = '{_vid('Y')}' WHERE stall_code = 'L3'")
    old = _session(d, "Y", "L4", -80, -60, status="faulted", reason="fault.station_hardware")
    _fault_event(d, old, -60, 90)
    _session(d, "Y", "L3", -30, None, status="active")
    rec = _order(d, [("C", "dcfc")])
    assert rec["ok"] and rec["order_id"], rec
    # what happened after the order
    d.val(f"UPDATE public.ocpp_sessions SET status = 'completed', stopped_reason = 'completed', "
          f"ended_at = '{T}'::timestamptz + interval '20 minutes' WHERE vehicle_id = '{_vid('Y')}' AND status = 'active'")
    _session(d, "I", "F1", 0.25, 45.25, soc_start=40)
    _session(d, "C", "F2", 0.25, 60, soc_start=30)
    _session(d, "P", "L1", 0.25, None, status="active", soc_start=70)
    b = _session(d, "B", "L2", 0.25, 30, status="faulted", reason="fault.connector_cable", soc_start=60)
    _fault_event(d, b, 30, 120)
    _session(d, "A", "L3", 25, 85, soc_start=50)
    d.val(f"""UPDATE public.ottoq_vehicle_dispatches SET actual_return_at = '{T}'::timestamptz + interval '9 minutes',
                     soc_at_return_pct = 25, status = 'returned' WHERE vehicle_id = '{_vid('H')}'""")
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, visit_key, status, urgency, dispatch_due_at,
                                                    target_soc, atoms, arrived_at, created_at)
              VALUES ('{_vid('H')}', '{RUN}', '{DEPOT}', 'H2', 'open', 'standard', '{T}'::timestamptz + interval '70 minutes',
                      100, '[]', '{T}'::timestamptz + interval '9 minutes', '{T}'::timestamptz + interval '9 minutes')""")
    _session(d, "H", "F1", 46, 80, soc_start=25)
    base._car(d, "X2", 18, 0, state="deployed")
    d.val(f"DELETE FROM public.ottoq_visit_needs WHERE vehicle_id = '{_vid('X2')}'")
    d.val(f"""INSERT INTO public.ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at, scheduled_return_at,
                                                           planned_duration_min, status, actual_return_at, soc_at_return_pct)
              VALUES ('{_vid('X2')}', '{RUN}', '{T}'::timestamptz + interval '5 minutes', '{T}'::timestamptz + interval '20 minutes',
                      15, 'returned', '{T}'::timestamptz + interval '20 minutes', 18)""")
    _session(d, "X2", "L4", 31, 89, soc_start=18)
    _session(d, "Z", "F2", 61, 75, soc_start=50)
    d.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_current = '{T}'::timestamptz + interval '100 minutes' WHERE sim_run_id = '{RUN}'")
    return rec["order_id"]


def test_0621_what_happened_is_read_from_the_run(db):
    oid = _a_morning(db)
    snap = db.json(f"SELECT state FROM public.ottoq_charge_order_snapshots WHERE order_id = {oid}")
    assert sorted(base.NAMES[c["id"]] for c in snap["inbound"]) == ["H", "W"], snap["inbound"]
    assert {c["id"] for c in snap["chargers"]} == {_vid(c) for c in ("F1", "F2", "L1", "L2", "L3")}, snap["chargers"]
    r = db.json(f"SELECT public.ottoq_charge_order_realized({oid}, 90)")
    assert (r["observed_min"], r["faults"], r["unmodeled_sessions"]) == (90, 1, 0), r
    cars = {base.NAMES[k]: v for k, v in r["cars"].items()}
    assert cars["I"] == {"s0": 0.25, "k0": "dcfc", "m": 45, "cen": False, "end": "completed"}, cars["I"]
    assert cars["P"] == {"s0": 0.25, "k0": "l2", "m": 89.75, "cen": True, "end": "running"}, cars["P"]
    assert cars["B"] == {"s0": 0.25, "k0": "l2", "m": None, "cen": True, "end": "fault.connector_cable"}, cars["B"]
    assert (cars["A"]["s0"], cars["A"]["m"], cars["A"]["cen"]) == (25, 60, False), cars["A"]
    assert cars["D"] == {"s0": None}, cars["D"]
    inb = {base.NAMES[k]: v for k, v in r["inbound"].items()}
    h = inb["H"]
    assert (h["arrived"], h["eta"], h["soc"], h["due"], h["s0"], h["k0"], h["m"]) == (True, 9, 25, 70, 46, "dcfc", 34), h
    w = inb["W"]
    assert (w["arrived"], w["eta"], w["soc"]) == (False, 90, 49), w        # forecast at 42, not home by the cut
    app = {base.NAMES[c["id"]]: c for c in r["appeared"]}
    assert sorted(app) == ["X2", "Z"], app
    assert (app["X2"]["how"], app["X2"]["eta"], app["X2"]["soc"], app["X2"]["s0"], app["X2"]["m"]) == ("returned", 20, 18, 31, 58)
    assert (app["Z"]["how"], app["Z"]["eta"], app["Z"]["soc"], app["Z"]["k0"]) == ("at_depot", 61, 50, "dcfc")
    stalls = {_vid(c): c for c in ("F1", "F2", "L1", "L2", "L3", "L4")}
    ch = {stalls[k]: v for k, v in r["chargers"].items()}
    assert ch["L3"] == {"free": 20, "cen": False}, ch                       # Y's charge under way ended at 20
    assert ch["L2"] == {"dn": [[30, 150]]}, ch                             # B's charger faulted at 30 for 120
    assert [(stalls[c["id"]], c["free"]) for c in r["back"]] == [("L4", 30)], r["back"]


def test_0621_the_grade_and_its_shapley_split(db):
    oid = _a_morning(db)
    out = db.json(f"SELECT public.ottoq_charge_order_grade_pending('{RUN}', 5, true, 60000, 90)")
    assert (out["graded"], out["errors"]) == (1, 0), out
    h = db.json(f"SELECT to_jsonb(h) FROM public.ottoq_charge_order_hindsight h WHERE order_id = {oid}")
    o = db.json(f"SELECT to_jsonb(o) FROM public.ottoq_agent_charge_orders o WHERE order_id = {oid}")
    assert h["reason"] == o["projection"]["reason"] and h["taken"] == (o["status"] in ("accepted", "partial"))
    # the expected future is the check's own scenario 0
    for side in ("kernel", "agent"):
        for key in ("on_time", "late_sum", "flow_sum"):
            assert float(h["expected"][side][key]) == float(o["projection"][side][key]), (side, key)
    hc = h["hindsight"]["cmp"]
    want = ("no_decision" if not h["decision"] else
            {(True, 1): "right_take", (True, 0): "neutral_take", (True, -1): "wrong_take",
             (False, 1): "missed_win", (False, 0): "right_refusal", (False, -1): "right_refusal"}[(h["taken"], hc)])
    assert h["outcome"] in (want, "no_decision_mattered"), h
    f = h["forecast"]
    assert (f["arrivals"]["n"], f["arrivals"]["arrived"], f["arrivals"]["no_show"]) == (2, 1, 1), f["arrivals"]
    assert f["appeared"] == {"n": 2, "returned": 1} and f["faults"] == {"in_window": 1, "back": 1}, f
    assert f["running"]["n"] == 1 and float(f["running"]["sum_err"]) != 0, f["running"]
    assert set(f["charge_times"]) == {"dcfc", "l2"} and f["charge_times"]["dcfc"]["n"] == 3, f["charge_times"]
    assert h["fidelity"]["cars"] >= 7 and h["fidelity"]["both"] >= 1, h["fidelity"]
    if h["decision"]:
        a = db.json(f"SELECT to_jsonb(a) FROM public.ottoq_charge_order_attribution a WHERE order_id = {oid}")
        assert a is not None and len(a["subset_values"]) == 32, a
        # v(none) is the expected future, v(all) is hindsight, and the five values sum to the difference
        assert a["subset_values"][0][0] == h["expected"]["cmp"] and a["subset_values"][31][0] == hc, a["subset_values"]
        for i, key in enumerate(("cmp", "on_time", "late", "flow")):
            total = sum(float(v[key]) for v in a["shapley"].values())
            diff = float(a["subset_values"][31][i]) - float(a["subset_values"][0][i])
            assert abs(total - diff) < 1e-3, (key, total, diff)
    # graded once
    again = db.json(f"SELECT public.ottoq_charge_order_grade_pending('{RUN}', 5, true, 60000, 90)")
    assert (again["graded"], again["due"]) == (0, 0), again


def _hand_order(d, oid, state, order, status, projection, real, taken):
    d.val(f"""INSERT INTO public.ottoq_charge_order_snapshots (order_id, sim_run_id, depot_id, sim_clock, seed, futures,
                                                               win_frac, state, agent_order, code_md5)
              VALUES ({oid}, '{RUN}', '{DEPOT}', '{T}', 'hand', 12, 0.8, $j${json.dumps(state)}$j$::jsonb,
                      $j${json.dumps(order)}$j$::jsonb, 'hand')""")
    d.val(f"""INSERT INTO public.ottoq_agent_charge_orders (order_id, sim_run_id, depot_id, board_tick, recorded_tick, sim_clock,
                                                            chain_id, model, status, n_offered, n_accepted, cars, dropped, projection)
              VALUES ({oid}, '{RUN}', '{DEPOT}', 1, 1, '{T}', 'hand', 'hand', '{status}', 1, 1, '[]', '[]',
                      $j${json.dumps(projection)}$j$::jsonb)""")
    exp = db_cmp(d, state, order)
    hind = db_cmp(d, d.json(f"""SELECT public.ottoq_charge_line_realize($j${json.dumps(state)}$j$::jsonb,
                                  $j${json.dumps(real)}$j$::jsonb, ARRAY['arrivals','appeared','charge_times','running','faults'])"""), order)
    d.val(f"""INSERT INTO public.ottoq_charge_order_hindsight (order_id, sim_run_id, depot_id, sim_clock, window_min,
                observed_min, status, reason, taken, decision, futures, wins, need, p_win, expected, hindsight, outcome,
                moves, forecast, fidelity, realized, code_md5)
              VALUES ({oid}, '{RUN}', '{DEPOT}', '{T}', 90, 90, '{status}', '{projection['reason']}', {str(taken).lower()},
                      true, 12, {projection['wins']}, 10, {projection['wins'] / 12}, $j${json.dumps(exp)}$j$::jsonb,
                      $j${json.dumps(hind)}$j$::jsonb, 'right_take', '{{}}', '{{}}', '{{}}', $j${json.dumps(real)}$j$::jsonb, 'hand')""")
    return exp, hind


def db_cmp(d, state, order):
    return d.json(f"""SELECT public.ottoq_charge_line_compare(public.ottoq_charge_line_simulate(s, NULL, 0, 'hand'),
                                                              public.ottoq_charge_line_simulate(s, o, 0, 'hand'))
                        FROM (SELECT $j${json.dumps(state)}$j$::jsonb AS s, $j${json.dumps(order)}$j$::jsonb AS o) q""")


def test_0621_a_fault_the_check_could_not_see_takes_the_whole_blame(db):
    # a (50%, due 50) and b (90%): the kernel puts a on the L2 (45 minutes) and b on the fast charger; the agent puts a
    # on the fast charger (30) and b on the L2: as many on time, 10 fewer minutes in the depot. Then the L2 faults at
    # minute 5 until 100: under the kernel a moves to the fast charger at 10 and is ready at 36.7; under the agent b
    # waits for the fast charger until 30 and is ready at 36.7, 20 minutes more in the depot than the kernel's line.
    _through_0621(db)
    st = {"ttl_min": 3, "pin_min": 90, "horizon_min": 480,
          "cars": [{"id": "a", "w": 0, "g": 50, "imm": False, "soc": 50, "due": 50, "md": 30, "ml": 45},
                   {"id": "b", "w": 0, "g": 10, "imm": False, "soc": 90, "due": None, "md": 10, "ml": 15}],
          "inbound": [], "chargers": [{"id": "f", "k": "dcfc", "free": 0}, {"id": "l", "k": "l2", "free": 0}]}
    order = {"a": {"rank": 1, "kind": "dcfc"}}
    real = {"observed_min": 90, "cars": {}, "inbound": {}, "appeared": [], "chargers": {"l": {"dn": [[5, 100]]}},
            "back": [], "faults": 1, "unmodeled_sessions": 0}
    exp, hind = _hand_order(db, 9001, st, order, "accepted",
                            {"reason": "wins_most_futures", "wins": 12, "futures": 12, "need": 10}, real, True)
    assert (exp["cmp"], exp["by"], float(exp["d_flow"])) == (1, "flow", -10), exp
    assert (hind["cmp"], hind["by"], float(hind["d_flow"])) == (-1, "flow", 20), hind
    a = db.json("SELECT public.ottoq_charge_order_attribute(9001)")
    sh = a["shapley"]
    assert float(sh["faults"]["cmp"]) == -2 and float(sh["faults"]["flow"]) == 30, sh
    assert all(float(sh[p][k]) == 0 for p in ("arrivals", "appeared", "charge_times", "running")
               for k in ("cmp", "on_time", "late", "flow")), sh
    assert a["verdict_changed"] is True
    tr = db.json(f"SELECT public.ottoq_charge_order_track_record('{RUN}', '{DEPOT}', 7)")
    assert tr["check_wrong_by"] == {"part": "faults", "share": 1, "verdicts_changed": 1}, tr


def test_0621_the_door_grades_closed_orders_and_the_board_shows_the_record(db):
    oid = _a_morning(db)
    assert db.val("SELECT count(*) FROM public.ottoq_charge_order_hindsight") == "0"
    rec = _order(db, [("D", "either")])         # D is still waiting at minute 100: the door grades the first order
    assert rec["ok"], rec
    assert db.val(f"SELECT count(*) FROM public.ottoq_charge_order_hindsight WHERE order_id = {oid}") == "1"
    assert db.val("SELECT count(*) FROM public.ottoq_charge_order_attribution") == "0"     # the night's, not the door's
    b = db.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}'::timestamptz + interval '100 minutes')")
    tr = b["track_record"]
    assert tr["window_min"] == 90 and tr["this_run"]["graded"] == 1 and tr["depot"]["graded"] == 1, tr
    u = db.json(f"SELECT public.ottoq_agent_charge_order_usage('{RUN}', 5)")
    assert u["hindsight"]["graded"] == 1, u["hindsight"]
    first = next(x for x in u["by_order"] if x["order_id"] == oid)
    h = db.json(f"SELECT to_jsonb(h) FROM public.ottoq_charge_order_hindsight h WHERE order_id = {oid}")
    assert first["hindsight"] == h["outcome"] and first["moves"] == h["moves"], (first, h["outcome"])


def test_0621_the_self_assessment_names_what_to_build(db):
    _through_0621(db)
    st = {"ttl_min": 3, "pin_min": 90, "horizon_min": 480,
          "cars": [{"id": "a", "w": 0, "g": 50, "imm": False, "soc": 50, "due": 50, "md": 30, "ml": 45},
                   {"id": "b", "w": 0, "g": 10, "imm": False, "soc": 90, "due": None, "md": 10, "ml": 15}],
          "inbound": [], "chargers": [{"id": "f", "k": "dcfc", "free": 0}, {"id": "l", "k": "l2", "free": 0}]}
    real = {"observed_min": 90, "cars": {}, "inbound": {}, "appeared": [], "chargers": {"l": {"dn": [[5, 100]]}},
            "back": [], "faults": 1, "unmodeled_sessions": 0}
    for i in range(12):
        _hand_order(db, 9100 + i, st, {"a": {"rank": 1, "kind": "dcfc"}}, "accepted",
                    {"reason": "wins_most_futures", "wins": 11, "futures": 12, "need": 10}, real, True)
        db.val(f"SELECT public.ottoq_charge_order_attribute({9100 + i})")
    s = db.json(f"SELECT public.ottoq_arbiter_self_assessment('{DEPOT}', now() - interval '1 day')")
    assert (s["graded"], s["decisions"]) == (12, 12), s
    assert s["calibration"]["brier"] == round((11 / 12) ** 2, 4) and s["calibration"]["base_rate_won"] == 0, s["calibration"]
    sweep = {float(x["win_frac"]): x for x in s["bar"]["sweep"]}
    assert sweep[0.8]["taken"] == 12 and sweep[0.8]["lost"] == 12 and sweep[1.0]["taken"] == 0, sweep
    assert float(s["bar"]["current_win_frac"]) == 0.8
    areas = {a["area"]: a for a in s["improvement_areas"]}
    assert areas["forecast_faults"]["kind"] == "capability_gap", areas.keys()
    assert areas["bar_stricter"]["evidence"]["best"]["win_frac"] == 1.0, areas["bar_stricter"]
    assert areas["futures_uninformative"]["kind"] == "calibration"
    assert s["what_made_the_check_wrong"]["parts"]["faults"]["verdict_share"] == 1
    # nightly: never while a run is running; then grades and writes an assessment
    assert db.json("SELECT public.ottoq_arbiter_hindsight_nightly(5000)") == {"skipped": "a run is running"}
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    assert db.json("SELECT public.ottoq_arbiter_hindsight_nightly(5000)")["errors"] == 0
    aid = db.val(f"SELECT public.ottoq_arbiter_assess('{DEPOT}', 7)")
    row = db.json(f"SELECT to_jsonb(x) FROM public.ottoq_arbiter_assessments x WHERE assessment_id = {aid}")
    assert row["n_graded"] == 12 and any(a["area"] == "forecast_faults" for a in row["improvement_areas"]), row


def test_0621_the_ledgers_are_append_only(db):
    _through_0621(db)
    st = {"ttl_min": 3, "pin_min": 90, "horizon_min": 480,
          "cars": [{"id": "a", "w": 0, "g": 50, "imm": False, "soc": 50, "due": 50, "md": 30, "ml": 45}],
          "inbound": [], "chargers": [{"id": "f", "k": "dcfc", "free": 0}]}
    _hand_order(db, 9200, st, {"a": {"rank": 1, "kind": "dcfc"}}, "accepted",
                {"reason": "wins_most_futures", "wins": 12, "futures": 12, "need": 10},
                {"observed_min": 90, "cars": {}, "inbound": {}, "appeared": [], "chargers": {}, "back": []}, True)
    db.val("SELECT public.ottoq_charge_order_attribute(9200)")
    assert db.val(f"SELECT public.ottoq_arbiter_assess('{DEPOT}', 7)") != ""
    for t in ("ottoq_charge_order_hindsight", "ottoq_charge_order_attribution", "ottoq_arbiter_assessments"):
        rc, _, err = db.run(f"UPDATE public.{t} SET code_md5 = 'x'")
        assert rc != 0 and "append-only" in err, (t, err)
        rc, _, err = db.run(f"DELETE FROM public.{t}")
        assert rc != 0 and "append-only" in err, (t, err)


def test_0621_refuses_a_simulator_it_was_not_written_against(db):
    _through_0620(db)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_charge_line_simulate(p_state jsonb, p_order jsonb, p_scenario integer,
                p_seed text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$ SELECT '{}'::jsonb $f$""")
    rc, err = db.file(M0621)
    assert rc != 0 and "0621 P1" in err and "the simulator" in err, err
