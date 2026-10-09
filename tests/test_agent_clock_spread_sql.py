"""db/migrations/0636, EXECUTED: the charge clock's spread is what its own charges show, by kind and length of charge.

WHY THIS EXISTS. The charge clock gives every charge a spread and the check's futures draw each charge's minutes from it.
On the twin depot's fast chargers the spread was far too sure (a charge inside the 80% band about two times in three once
the clock knows the run, at every length), and the self-review ranked it third (G362). 0636 has every fit measure, on
its own charges, how wide each kind and length of charge runs against the spread the clock gives it, writes that as the
fit's `spread`, and the clock scales its spread by the length's factor; the minutes never move. Every claim in its header
that a test can execute is executed here, on the scratch PostgreSQL and the miniature depot of
tests/test_agent_charge_order_sql.py, through 0619-0635 as tests/test_agent_charger_faults_sql.py applies them:
  - it applies, its checks run, and it refuses an engine before 0635, a body it was not written against and a run
    running;
  - the spread's fit, by arithmetic, on charges planted with a known spread within each run: each length's factor is its
    own 80% band in spreads shrunk toward the kind's by n / (n + 30), a thin length takes the kind's, a thin kind gets
    none, the factor is held within 0.5-4, the regime cut and the window are honoured, and it says what share fell
    inside the band before and after;
  - the clock scales its spread by the length's factor and never moves its minutes; without a spread it is 0632's, key
    for key;
  - every fit carries it unless a person turns the dial to 0 at the depot, and then the fit is 0632's, key for key; the
    fit's md5 covers it;
  - the audit's band on a fleet moves to what the charges show, and out of sample too;
  - the self-review marks the band built while the audit reads only the fit's own charges.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import math
import os
import re
import sys
from statistics import NormalDist

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622: the fleet and the fit)
import test_agent_charger_faults_sql as fz  # noqa: E402  (0635 and the chain through it)
import test_agent_self_review_sql as sr  # noqa: E402  (the review's words)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0636 = os.path.join(ROOT, "db", "migrations", "0636_the_charge_clocks_spread_is_what_its_charges_show.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
SD = "55555555-5555-5555-5555-555555555555"                      # a depot whose only charges are the planted ones
SD2 = "66666666-6666-6666-6666-666666666666"                     # and another
_file = arb._file

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

# a minimal clock: one pooled cell a kind, no levels: every charge's forecast is 0614's estimate with spread 0.05 / 0.1
MODEL_PARAMS = {"cells": {"dcfc:*": {"usable": True, "factor": 1, "log_sd": 0.05},
                          "l2:*": {"usable": True, "factor": 1, "log_sd": 0.1}},
                "class_cells": {}}
Q = [NormalDist().inv_cdf((i - 0.5) / 20) for i in range(1, 21)]  # twenty residuals, symmetric about 0


def _apply(d):
    return _file(d, M0636)


def _through_0635(d):
    fz._through_0634(d)
    err = fz._apply(d)
    assert "0635 V5" in err, err


def _pct(xs, p):
    """percentile_cont, as PostgreSQL computes it."""
    s = sorted(xs)
    pos = p * (len(s) - 1)
    lo = math.floor(pos)
    return s[lo] + (pos - lo) * (s[min(lo + 1, len(s) - 1)] - s[lo])


def _band(zs):
    return (_pct(zs, 0.9) - _pct(zs, 0.1)) / 2.5631


def _car(d, vid, depot=SD):
    d.val(f"""INSERT INTO public.vehicles (id, fleet_operator_id, home_depot_id, category, display_name, current_soc,
                                           battery_capacity_kwh, inlet_type, inlet_max_kw, current_state)
              VALUES ('{vid}', '{base.OPERATOR}', '{depot}', 'autonomous', 'spread-car', 80, 75, 'NACS', 250, 'deployed')
              ON CONFLICT (id) DO NOTHING""")


def _plant(d, tag, runs, kind, soc, scale, sd=0.05, depot=SD, recorded="now() - interval '1 day'", tick=0.5):
    """Twenty completed charges of `kind` from `soc` in each of `runs` runs (one car), each ran exp(sd * scale * q) times
    0614's estimate, q the twenty normal quantiles: within each run their log residuals are sd * scale * q, mean 0."""
    vid = base._vid(f"spread-{depot}")
    _car(d, vid, depot)
    kw = 150 if kind == "dcfc" else 19.2
    qs = "ARRAY[" + ", ".join(repr(q) for q in Q) + "]::float8[]"
    d.val(f"""INSERT INTO public.ottoq_charge_duration_ledger (session_id, recorded_at, source_kind, sim_run_id, depot_id,
                                                                charger_type, charger_kw, vehicle_id, vehicle_kw, battery_kwh,
                                                                soc_start, soc_end, duration_min, stopped_reason, tick_minutes)
              SELECT md5('{tag}:' || r || ':' || g)::uuid, {recorded}, 'live', md5('{tag}-run-' || r)::uuid, '{depot}',
                     '{kind}', {kw}, '{vid}', 250, 75, {soc}, 100,
                     round((public.ottoq_charge_minutes_estimate(75, {soc}, 100, {kw}, 250)
                            * exp({sd} * {scale} * ({qs})[g]))::numeric, 9), 'completed', {tick}
                FROM generate_series(1, {runs}) r CROSS JOIN generate_series(1, 20) g""")


def _spread_fit(d, params=None, through="now()", depot=SD):
    p = json.dumps(params if params is not None else MODEL_PARAMS)
    out = d.val(f"SELECT public.ottoq_charge_clock_spread_fit('{depot}', $p${p}$p$::jsonb, {through}, interval '21 days')")
    return json.loads(out) if out else None


def _clock(d, params, kind, soc, run="NULL"):
    kw = 150 if kind == "dcfc" else 19.2
    return d.json(f"""SELECT public.ottoq_charge_clock($m${json.dumps({"params": params})}$m$::jsonb, '{kind}', '{{}}'::jsonb,
                                                     75, {soc}, 100, {kw}, 250, {run})""")


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0636_applies_and_its_checks_run(db):
    _through_0635(db)
    err = _apply(db)
    assert ("0636 V1: a fast charge of 28.0 minutes takes the 15-30 factor (spread 0.0500 -> 0.0600), one of 48.0 the "
            "45-and-over (0.0700); an L2 charge the block does not name keeps 0.1000; the fit, its md5, the self-review and "
            "the dial as meant") in err, err
    assert re.search(r"0636 V2: on the clock as it stood \(fit \S+, no spread\), \d+ charges read exactly as before", err), err
    assert re.search(r"0636 V3: fit \d+ in [\d.]+ s, usable \w+\. The spread: ", err), err
    assert re.search(r"0636 V4: out of sample, ", err), err
    assert re.search(r"0636 V5: the self-review in \d+ ms; its band areas: ", err), err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0636_the_charge_clocks_spread_is_what_its_charges_show'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0636_pre'") == "4"
    assert db.val("""SELECT default_value::text || '/' || min_value || '/' || max_value || '/' || agent_writable
                       FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_clock_spread_by_length'""") == "1/0/1/false"
    # the fit's md5 covers the spread's fit: a change there changes it
    assert db.val("""SELECT strpos(pg_get_functiondef('public.ottoq_fit_charge_time_v2(uuid,timestamptz,interval,numeric,text)'::regprocedure),
                                   'ottoq_charge_clock_spread_fit(uuid,jsonb,timestamp with time zone,interval)') > 0""") == "t"


def test_0636_refuses_an_engine_before_0635_a_body_it_was_not_written_against_and_a_run_running(db):
    fz._through_0634(db)
    rc, err = db.file(M0636)
    assert rc != 0 and "0636 P1: public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean) is not " \
                       "the body measured" in err, err
    fz._apply(db)
    db.val(r"""DO $x$ BEGIN
                    EXECUTE regexp_replace(pg_get_functiondef('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)'::regprocedure),
                                           '\$function\$\n', E'$function$\n  -- a later change\n');
                  END $x$""")
    rc, err = db.file(M0636)
    assert rc != 0 and "0636 P1: public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb) " \
                       "is not the body measured" in err, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0636)
    assert rc != 0 and "0636 P0: a run is running" in err, err
    assert db.val("SELECT to_regprocedure('public.ottoq_charge_clock_spread_fit(uuid,jsonb,timestamptz,interval)') IS NULL") == "t"


# ── the spread's fit, by arithmetic ───────────────────────────────────────────────────────────────────────────────────

def test_0636_each_lengths_factor_is_its_own_band_shrunk_toward_the_kinds(db):
    _through_0635(db)
    _apply(db)
    # fast: four runs, each twenty charges from 70% (28 minutes: 15-30) at 1.5 spreads and twenty from 20% (48: 45 and
    # over) at 2.5 spreads; L2: twenty from 70% (70 minutes: 60-120) at the spread the clock gives
    _plant(db, "a", 4, "dcfc", 70, 1.5)
    _plant(db, "b", 4, "dcfc", 20, 2.5)
    _plant(db, "c", 4, "l2", 70, 1.0, sd=0.1)
    s = _spread_fit(db)
    # each planted set has runs of its own, twenty charges a run with mean 0: z is the planted residual times
    # sqrt(20 / 19) over the clock's spread
    zf2 = [1.5 * q * math.sqrt(20 / 19) for q in Q] * 4
    zf4 = [2.5 * q * math.sqrt(20 / 19) for q in Q] * 4
    zl = [q * math.sqrt(20 / 19) for q in Q] * 4
    sk = _band(zf2 + zf4)
    want = [sk, (80 * _band(zf2) + 30 * sk) / 110, sk, (80 * _band(zf4) + 30 * sk) / 110]
    f = s["dcfc"]
    assert f["edges"] == [15, 30, 45] and f["n_by_length"] == [0, 80, 0, 80] and (f["n"], f["units"]) == (160, 8), f
    assert all(abs(a - b) < 2e-4 for a, b in zip(f["s"], want)), (f["s"], want)
    assert abs(f["s_kind"] - sk) < 2e-4 and f["s_raw"][0] is None and abs(f["s_raw"][1] - _band(zf2)) < 2e-4, f
    before = sum(abs(z) <= 1.2816 for z in zf2 + zf4) / 160
    after = (sum(abs(z) <= 1.2816 * want[1] for z in zf2) + sum(abs(z) <= 1.2816 * want[3] for z in zf4)) / 160
    assert (f["in_band_before"], f["in_band_after"]) == (round(before, 3), round(after, 3)), f
    lk = s["l2"]
    assert lk["edges"] == [60, 120, 240] and lk["n_by_length"] == [0, 80, 0, 0], lk
    assert all(abs(x - _band(zl)) < 2e-4 for x in lk["s"]), (lk["s"], _band(zl))
    assert s["v"] == 1 and "80% band" in s["rule"]


def test_0636_a_thin_kind_gets_none_and_the_factor_is_held_within_bounds(db):
    _through_0635(db)
    _apply(db)
    # three runs of twenty is enough charges (60) and runs (3); two runs, or fewer than five charges a run, is not
    _plant(db, "w", 2, "l2", 70, 1.0, sd=0.1)
    assert _spread_fit(db) is None
    _plant(db, "x", 3, "dcfc", 70, 9.0)                         # nine spreads wide: held at 4
    s = _spread_fit(db)
    assert set(s) == {"dcfc", "v", "rule"} and s["dcfc"]["s"] == [4, 4, 4, 4], s
    # a kind whose charges run a tenth as wide as the clock says is held at 0.5
    _plant(db, "y", 3, "l2", 70, 0.1, sd=0.1, depot=SD2)
    assert _spread_fit(db, depot=SD2)["l2"]["s"] == [0.5, 0.5, 0.5, 0.5]


def test_0636_the_fit_reads_its_window_and_its_regime_cut_and_fine_ticks_only(db):
    _through_0635(db)
    _apply(db)
    _plant(db, "in", 4, "dcfc", 70, 1.5)
    base_n = _spread_fit(db)["dcfc"]["n"]
    # charges recorded after the moment fitted through, older than the window, at five-minute ticks, or before the kind's
    # regime cut where the fit applied one: none of them is read
    _plant(db, "late", 4, "dcfc", 70, 9.0, recorded="now() + interval '1 hour'")
    _plant(db, "old", 4, "dcfc", 70, 9.0, recorded="now() - interval '30 days'")
    _plant(db, "coarse", 4, "dcfc", 70, 9.0, tick=5)
    s = _spread_fit(db)
    assert s["dcfc"]["n"] == base_n == 80, s
    _plant(db, "pre", 4, "dcfc", 70, 9.0, recorded="now() - interval '5 days'")
    assert _spread_fit(db)["dcfc"]["n"] == 160
    cut = dict(MODEL_PARAMS, regimes={"dcfc": {"applied": True, "starts_at": db.val("SELECT (now() - interval '3 days')::text")}})
    assert _spread_fit(db, cut)["dcfc"]["n"] == 80
    unapplied = dict(MODEL_PARAMS, regimes={"dcfc": {"applied": False, "starts_at": db.val("SELECT (now() - interval '3 days')::text")}})
    assert _spread_fit(db, unapplied)["dcfc"]["n"] == 160
    # a fit's own spread is never read back into the spread it measures
    with_spread = dict(MODEL_PARAMS, spread={"dcfc": {"edges": [15, 30, 45], "s": [3, 3, 3, 3]}})
    assert _spread_fit(db, with_spread) == _spread_fit(db)


# ── the clock ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0636_the_clock_scales_its_spread_by_the_lengths_factor_and_never_moves_its_minutes(db):
    _through_0635(db)
    _apply(db)
    sp = {"dcfc": {"edges": [15, 30, 45], "s": [1.1, 1.2, 1.3, 1.4]}, "l2": {"edges": [60, 120, 240], "s": [0.9, 1.0, 0.8, 0.7]}}
    with_sp = dict(MODEL_PARAMS, spread=sp)
    for kind, soc, want in (("dcfc", 95, 1.1), ("dcfc", 85, 1.2), ("dcfc", 70, 1.2), ("dcfc", 60, 1.3), ("dcfc", 30, 1.4),
                            ("l2", 90, 0.9), ("l2", 70, 1.0), ("l2", 30, 0.8), ("l2", 5, 0.8)):
        a, b = _clock(db, MODEL_PARAMS, kind, soc), _clock(db, with_sp, kind, soc)
        assert b["m"] == a["m"] and b["f"] == a["f"] and b["lvl"] == a["lvl"], (kind, soc, a, b)
        assert abs(b["sd"] - round(a["sd"] * want, 4)) < 1e-9 and b["sf"] == want and "sf" not in a, (kind, soc, a, b)
    # an edge is the bin above it: 15.0 minutes is 15-30
    assert _clock(db, with_sp, "dcfc", 85)["m"] == 15 and _clock(db, with_sp, "dcfc", 85)["sf"] == 1.2
    # nothing owed, an unknown battery, a block without factors: no factor, the spread as it was
    assert "sf" not in _clock(db, with_sp, "dcfc", 100)
    bad = dict(MODEL_PARAMS, spread={"dcfc": {"edges": [15]}})
    assert "sf" not in _clock(db, bad, "dcfc", 70)


def test_0636_without_a_spread_the_clock_is_0632s_key_for_key(db):
    _through_0635(db)
    m = db.json(f"SELECT public.ottoq_charge_clock_model('{DEPOT}')")   # 0632's fit of the chain's fleet: no spread
    calls = [(k, s0, r) for k in ("dcfc", "l2") for s0 in (10, 40, 70, 90) for r in ("NULL", """'{"air_c": 31}'::jsonb""")]
    mj = json.dumps(m)

    def read():
        return [db.val(f"""SELECT public.ottoq_charge_clock($m${mj}$m$::jsonb, '{k}',
                                   public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model),
                                   75, {s0}, 100, {150 if k == 'dcfc' else 19.2}, 250, {r})::text
                             FROM public.vehicles v WHERE v.vehicle_class_code IS NOT NULL ORDER BY v.id LIMIT 1""")
                for k, s0, r in calls]
    before = read()
    _apply(db)
    assert read() == before and "spread" not in m["params"]


# ── the fit carries it, behind the dial ───────────────────────────────────────────────────────────────────────────────

def test_0636_every_fit_carries_the_spread_unless_a_person_turns_it_off(db):
    _through_0635(db)
    _apply(db)
    through = db.val("SELECT now()::text")
    on = db.json(f"SELECT public.ottoq_charge_time_v2_params('{DEPOT}', '{through}', interval '21 days', 3)")
    assert set(on["spread"]) >= {"dcfc", "l2", "v", "rule"}, on.get("spread")
    db.val(f"""INSERT INTO public.ottoq_policy_params VALUES ('depot', '{DEPOT}', 'charge_clock_spread_by_length', 0,
                                                              'test', now())""")
    off = db.json(f"SELECT public.ottoq_charge_time_v2_params('{DEPOT}', '{through}', interval '21 days', 3)")
    assert "spread" not in off and off == {k: v for k, v in on.items() if k != "spread"}
    # the cut the fit itself reads, and nothing else: the 0632 params, key for key
    cut = db.json(f"""SELECT public.ottoq_charge_time_v2_params_cut('{DEPOT}', '{through}', interval '21 days', 3,
                             public.ottoq_evidence_regime_cuts('charge_time_v2', '{DEPOT}',
                                                               '{through}'::timestamptz - interval '21 days', '{through}'))""")
    assert off == cut
    # and a fit written with the dial on reads back with it
    db.val(f"DELETE FROM public.ottoq_policy_params WHERE param_key = 'charge_clock_spread_by_length'")
    fid, m = arb._fit(db)
    assert m["estimate_id"] == fid and "spread" in m["params"] and "dcfc" in m["params"]["spread"]


# ── the audit and the review ──────────────────────────────────────────────────────────────────────────────────────────

def _audit_band(d, model, kind="dcfc"):
    a = d.json(f"""SELECT public.ottoq_charge_clock_audit_v2('{DEPOT}', now() - interval '21 days',
                                                             $m${json.dumps(model)}$m$::jsonb)""")
    return a["by_kind"][kind]["clock"]["in_80pct_band_within_run"]


def test_0636_the_audits_band_moves_to_what_the_charges_show(db):
    _through_0635(db)
    _apply(db)                                                    # V3 refits the chain's fleet (8 runs) with the spread
    m = db.json(f"SELECT public.ottoq_charge_clock_model('{DEPOT}')")
    sp = m["params"]["spread"]
    plain = dict(m, params={k: v for k, v in m["params"].items() if k != "spread"})
    # the fleet's fast charges run narrower within a run than the clock's narrowed spread says: the audit read about
    # 99% inside the 80% band; with the spread each length shows, what the fit measured
    for kind in ("dcfc", "l2"):
        b0, b1 = _audit_band(db, plain, kind), _audit_band(db, m, kind)
        assert abs(b1 - 0.8) < abs(b0 - 0.8), (kind, b0, b1, sp[kind])
        assert abs(b0 - sp[kind]["in_band_before"]) < 0.05 and abs(b1 - sp[kind]["in_band_after"]) < 0.05, (kind, b0, b1, sp[kind])


def test_0636_out_of_sample_the_band_holds(db):
    _through_0635(db)
    _apply(db)
    # the last of the chain's eight runs, out of sample: its params fitted through its first charge
    run, t0 = db.val("""SELECT sim_run_id || ' ' || min(recorded_at) FROM public.ottoq_charge_duration_ledger
                         WHERE charger_type = 'dcfc' GROUP BY sim_run_id ORDER BY max(recorded_at) DESC LIMIT 1""").split(" ", 1)
    p = db.json(f"SELECT public.ottoq_charge_time_v2_params('{DEPOT}', '{t0}'::timestamptz - interval '1 second', interval '21 days', 3)")
    assert "dcfc" in p["spread"], p.get("spread")
    zs = db.json(f"""SELECT jsonb_agg(jsonb_build_array(y.w, y.sd0, y.sd1)) FROM (
                       SELECT x.lr - x.f - avg(x.lr - x.f) OVER () AS w, x.sd0, x.sd1 FROM (
                         SELECT ln((l.duration_min / public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end,
                                                                                         l.charger_kw, l.vehicle_kw))::numeric) AS lr,
                                (c0.c ->> 'f')::numeric AS f, (c0.c ->> 'sd')::numeric AS sd0, (c1.c ->> 'sd')::numeric AS sd1
                           FROM public.ottoq_charge_duration_ledger l JOIN public.vehicles v ON v.id = l.vehicle_id
                          CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(jsonb_build_object('params', $p${json.dumps(p)}$p$::jsonb - 'spread'),
                                     'dcfc', public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model), l.battery_kwh,
                                     l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw, jsonb_build_object('air_c', l.depot_air_c)) AS c) c0
                          CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(jsonb_build_object('params', $p${json.dumps(p)}$p$::jsonb),
                                     'dcfc', public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model), l.battery_kwh,
                                     l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw, jsonb_build_object('air_c', l.depot_air_c)) AS c) c1
                          WHERE l.sim_run_id = '{run}' AND l.charger_type = 'dcfc') x) y""")
    before = sum(abs(w / s0) <= 1.2816 for w, s0, _ in zs) / len(zs)
    after = sum(abs(w / s1) <= 1.2816 for w, _, s1 in zs) / len(zs)
    assert len(zs) == 36 and abs(after - 0.8) < abs(before - 0.8), (before, after)


def test_0636_the_review_marks_the_band_built_while_the_audit_reads_the_fits_own_charges(db):
    _through_0635(db)
    _apply(db)                                                    # V3's fit carries the spread
    v = db.json(f"SELECT public.ottoq_arbiter_self_assessment_v3('{DEPOT}', now() - interval '7 days', false)")
    bands = {a["area"]: a for a in v["improvement_areas"] if a["area"].startswith("charge_clock_band_")}
    assert set(bands) == {"charge_clock_band_dcfc", "charge_clock_band_l2"}, bands.keys()
    a = bands["charge_clock_band_dcfc"]
    sr._plain(a)
    m = db.json(f"SELECT public.ottoq_charge_clock_model('{DEPOT}')")["params"]["spread"]["dcfc"]
    assert (a["status"], a["kind"], a["part"]) == ("built", "calibration", "charge_times"), a
    assert a["title"] == "The charge clock's spread on fast chargers is what its charges show", a["title"]
    assert a["finding"] == (f"{round(100 * m['in_band_before'])}% of the {m['n']} charges on fast chargers it was fitted "
                            f"on fell inside its 80% band once it knows the run, and {round(100 * m['in_band_after'])}% "
                            "with the spread each length of charge shows. These are the charges it learned from, so this "
                            "is history until 30 charges come after the fit."), a["finding"]
    assert a["action"] == "Grade the band on the charges that come after the fit: the audit reads them once there are 30."
    # a fit without the spread says nothing built about the band
    db.val(f"""INSERT INTO public.ottoq_policy_params VALUES ('depot', '{DEPOT}', 'charge_clock_spread_by_length', 0,
                                                              'test', now())""")
    arb._fit(db)
    v = db.json(f"SELECT public.ottoq_arbiter_self_assessment_v3('{DEPOT}', now() - interval '7 days', false)")
    assert not [x for x in v["improvement_areas"] if x["area"].startswith("charge_clock_band_") and x["status"] == "built"]
