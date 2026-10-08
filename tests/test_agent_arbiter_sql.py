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
