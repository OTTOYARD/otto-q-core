"""db/migrations/0626, EXECUTED: the check's self-review judges the charge clock within runs, finds what changed in its
world, splits the arrivals' misses into the bulk and the tails, grades the outflow, and ranks every place to improve by
how much of what made the check wrong it touches, open or already built, in words a person can act on.

WHY THIS EXISTS. 0626's header measured what the 2026-10-08 review got wrong: a run's level read as air temperature
(G360), two tails read as a narrow spread, rebuilt things named as open, counts of different things ranked as one,
and internal ids in its sentences. Every claim in that header a test can execute is executed here, on the scratch
PostgreSQL and the miniature depot of tests/test_agent_charge_order_sql.py, through 0619-0625 as
tests/test_agent_regime_sql.py applies them, with 0622's planted fleet:
  - it applies, its checks run, the audit and the words are readable as 0622's audit is, v3 is the service's alone, and
    it refuses a body it was not written against;
  - the words: a vehicle class by its maker, a ratio, a moment in the depot's own time;
  - the audit within runs: a run's level that moves with the day's temperature is not named, as 0622's audit named it;
    a temperature that moves charges within runs is named, with its slope within and between runs;
  - a change the scan names is an area of its own, with the record a person would write and the cut tried out of
    sample on the latest run since;
  - the arrivals' misses split into the bulk and the tails, with what to build for each;
  - the outflow's grade names a class whose own curve does worse than the one curve, and departures off their forecast;
  - ranked by impact, open before built: an old clock's calibration and the outflow are built when the orders predate them;
  - the nightly review writes v3, and writes a review with nothing graded when it names something.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import re
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622 and the planted fleet)
import test_agent_regime_sql as rg  # noqa: E402  (0625)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0626 = os.path.join(ROOT, "db", "migrations",
                     "0626_the_self_review_judges_the_clock_within_runs_and_ranks_what_to_build.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_file = arb._file

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

INTERNAL_ID = re.compile(r"\b[a-z0-9]+_[a-z0-9_]+\b|\bdcfc\b|\bl2\b|\b0[4-6]\d\d\b|charge_time")


def _apply(d):
    return _file(d, M0626)


def _through_0626(d):
    rg._through_0625(d, clear=True)
    return _apply(d)


def _review(d, since="now() - interval '7 days'", trial=False):
    return d.json(f"SELECT public.ottoq_arbiter_self_assessment_v3('{DEPOT}', {since}, {str(trial).lower()})")


def _areas(r):
    return {a["area"]: a for a in r["improvement_areas"]}


def _plain(a):
    """Every area speaks in words: a title, a finding and an action, none carrying an internal id."""
    words = " ".join(a.get(k) or "" for k in ("title", "finding", "action"))
    assert len(a["title"]) >= 10 and len(a["finding"]) >= 20 and len(a["action"]) >= 10, a
    assert not INTERNAL_ID.search(words), (INTERNAL_ID.search(words).group(0), words)


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0626_applies_and_its_checks_run(db):
    err = _through_0626(db)
    assert "0626 V1: the audit within runs keeps 0622's accuracy and shares on 0 kinds" in err, err
    assert "0626 V2: 0 graded, 0 areas (0 open, 0 built), in words" in err, err
    assert "0626 V3: nothing graded and nothing to name here: no review written" in err, err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0626_%'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0626_pre'") == "1"
    priv = db.json("""SELECT jsonb_build_object(
        'audit', has_function_privilege('anon', 'public.ottoq_charge_clock_audit_v2(uuid,timestamptz,jsonb)', 'EXECUTE'),
        'words', has_function_privilege('anon', 'public.ottoq_review_words(text,text)', 'EXECUTE'),
        'v3_anon', has_function_privilege('anon', 'public.ottoq_arbiter_self_assessment_v3(uuid,timestamptz,boolean)', 'EXECUTE'),
        'v3_auth', has_function_privilege('authenticated',
                     'public.ottoq_arbiter_self_assessment_v3(uuid,timestamptz,boolean)', 'EXECUTE'),
        'v3_service', has_function_privilege('service_role',
                        'public.ottoq_arbiter_self_assessment_v3(uuid,timestamptz,boolean)', 'EXECUTE'))""")
    assert priv == {"audit": True, "words": True, "v3_anon": False, "v3_auth": False, "v3_service": True}, priv


def test_0626_its_checks_hold_on_a_depot_with_something_to_say(db):
    # the miniature depot carries the twin depot's id, so V1-V3 read this world: a warm-weather fleet whose charges move
    # with the air, a week of graded orders with arrival tails, a Shapley split, and the old clock
    rg._through_0625(db, clear=True)
    _classes(db)
    arb._fleet(db, RUNS)
    _weather(db, per_degree=0.015)
    arb._fit(db)
    inb, real = _arrivals(300, 6, 6)
    for k in range(12):
        _graded(db, 9600 + k, inbound=inb[26 * k:26 * (k + 1)], real_inbound=real,
                appeared=[{"id": f"u{k}", "how": "returned", "eta": 40, "soc": 30}],
                forecast={"running": {"n": 10, "sum_err": -50, "sum_abs_err": 100}})
        _attribution(db, 9600 + k, {"arrivals": 1.0} if k < 6 else {"running": 1.0} if k < 9 else {"faults": 1.0})
    err = _apply(db)
    assert re.search(r"0626 V1: the audit within runs keeps 0622's accuracy and shares on 2 kinds", err), err
    m = re.search(r"0626 V2: 12 graded, (\d+) areas \((\d+) open, (\d+) built\), in words; ranked: (.*)", err)
    assert m and int(m.group(1)) >= 5, err
    assert "1. [open, 50%] A few cars come home far from their forecast" in m.group(4), m.group(4)
    assert "The charge clock does not see the air temperature" in m.group(4), m.group(4)
    assert re.search(r"0626 V3: review \d+ written, v3, \d+ areas, trials \{\}", err), err
    row = db.json("SELECT to_jsonb(x) FROM public.ottoq_arbiter_assessments x ORDER BY assessment_id DESC LIMIT 1")
    assert row["assessment"]["v"] == 3 and row["n_graded"] == 12, row["assessment"].keys()
    for a in row["improvement_areas"]:
        _plain(a)


def test_0626_refuses_a_body_it_was_not_written_against(db):
    rg._through_0625(db, clear=True)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_evidence_regime_scan(p_depot uuid, p_since timestamptz DEFAULT NULL,
                p_model jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE sql STABLE AS $f$ SELECT '{}'::jsonb $f$""")
    rc, err = db.file(M0626)
    assert rc != 0 and "0626 P1" in err and "the scan (0625)" in err, err


# ── the words ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def _classes(d):
    d.val("""INSERT INTO public.ottoq_vehicle_classes (vehicle_class_code, oem_name, manufacturer, model, status) VALUES
               ('alpha_av_2024', 'Alpha', 'Alpha Motors', 'A1 (fleet build)', 'active'),
               ('beta_av_2024', 'Beta', 'Beta', 'One', 'active'),
               ('beta_van_2025', 'Beta', 'Beta', 'Van (cargo)', 'active'),
               ('beta_old_2019', 'Beta', 'Beta', 'Old', 'retired'),
               ('generic_av_dcfc', 'Generic', 'Generic', 'AV-DCFC', 'active')""")


def test_0626_the_words_say_what_the_keys_mean(db):
    _through_0626(db)
    _classes(db)

    def w(what, key):
        return db.val(f"SELECT public.ottoq_review_words('{what}', '{key}')")
    assert w("class", "alpha_av_2024") == "Alpha"                  # one active class: its maker's name
    assert w("class", "beta_av_2024") == "Beta One"                # two active classes share a maker: maker and model
    assert w("class", "beta_van_2025") == "Beta Van"               # the model's parenthesis goes
    assert w("class", "generic_av_dcfc") == "AV-DCFC"              # a generic class: its model
    assert w("class", "zeta_x_2030") == "zeta x 2030"              # a class the catalog does not know: no underscores
    assert (w("kind", "dcfc"), w("kind", "l2"), w("covariate", "ambient_c"), w("part", "appeared")) == \
        ("fast chargers", "L2 chargers", "air temperature", "cars it never saw coming")
    assert w("move", "reorder_only") == "only reordered the line" and w("dwell", "bay") == "cars waiting on a bay service"
    assert [db.val(f"SELECT public.ottoq_review_change({r})") for r in ("0.32", "1.093", "1.004", "1", "NULL")] == \
        ["68% shorter", "9% longer", "no different", "no different", "by an unknown amount"]
    assert db.val("SELECT public.ottoq_review_change(1.5, 'fewer', 'more')") == "50% more"
    assert [db.val(f"SELECT public.ottoq_review_change({r}, 'shorter', 'longer', 1)") for r in ("1.0155", "0.9904", "1.0004")] == \
        ["1.6% longer", "1.0% shorter", "no different"]
    # the depot's own time, daylight saving and not (CLAUDE.md rule 7)
    assert db.val("SELECT public.ottoq_review_ct('2026-09-30 11:53:08+00')") == "Sep 30, 6:53 AM CT"
    assert db.val("SELECT public.ottoq_review_ct('2026-12-01 00:05:00+00')") == "Nov 30, 6:05 PM CT"
    assert db.val("SELECT public.ottoq_review_ct(NULL)") == "an unknown moment"


# ── the audit within runs ─────────────────────────────────────────────────────────────────────────────────────────────

RUNS = 8
SINCE = "now() - interval '10 days'"


def _weather(d, per_degree=0.0, base=18.0, run_c_per_eff=60.0):
    """The planted fleet's charges get an air temperature: each run's own day (base plus run_c_per_eff times the run's
    planted effect, so a warmer run is also a slower one on fast chargers) and each charge its own hour (a hash, within
    +-4 degrees, independent of the car, the band and the run). With per_degree, a fast charge also runs exp(per_degree
    times its temperature less base) longer: a variable the clock has no level for."""
    run_vals = ", ".join(f"({rg._run(r)}, {arb.RUN_EFF[r % len(arb.RUN_EFF)]})" for r in range(RUNS))
    d.val(f"""UPDATE public.ottoq_charge_duration_ledger l
                 SET ambient_temp_c = round(({base} + {run_c_per_eff} * r.eff
                                             + ((('x' || substr(md5(l.session_id::text || 'air'), 1, 8))::bit(32)::int % 400)
                                                / 100.0))::numeric, 2)
                FROM (VALUES {run_vals}) r(run, eff) WHERE l.sim_run_id = r.run""")
    if per_degree:
        d.val(f"""UPDATE public.ottoq_charge_duration_ledger
                     SET duration_min = round(duration_min * exp({per_degree} * (ambient_temp_c - {base}))::numeric, 3)
                   WHERE charger_type = 'dcfc'""")


def test_0626_a_runs_level_that_moves_with_the_day_is_not_taken_for_air_temperature(db):
    _through_0626(db)
    arb._fleet(db, RUNS)
    _weather(db)
    arb._fit(db)
    old = db.json(f"SELECT public.ottoq_charge_clock_audit('{DEPOT}', {SINCE}, NULL)")
    new = db.json(f"SELECT public.ottoq_charge_clock_audit_v2('{DEPOT}', {SINCE}, NULL)")
    o = {c["covariate"]: c for c in old["by_kind"]["dcfc"]["covariates"]}
    n = {c["covariate"]: c for c in new["by_kind"]["dcfc"]["covariates"]}
    # 0622's audit reads the run's level twice: as the run, and as the day's air temperature
    assert float(o["run"]["adj_eta2"]) >= 0.3 and float(o["ambient_c"]["adj_eta2"]) >= 0.05, o
    # the same shares across runs, and within runs the air explains nothing
    assert set(n) == set(o) and {"class", "model", "vehicle", "band", "ambient_c", "run"} <= set(o), (set(o), set(n))
    for cov in set(o) - {"run"}:
        assert (n[cov]["groups"], n[cov]["eta2"], n[cov]["adj_eta2"]) == (o[cov]["groups"], o[cov]["eta2"], o[cov]["adj_eta2"]), cov
    assert float(n["ambient_c"]["adj_eta2_within"]) < 0.02, n["ambient_c"]
    assert n["run"]["modelled"] is True and n["run"]["judged"] == "across_runs" and n["run"]["adj_eta2_within"] is None
    air = new["by_kind"]["dcfc"]["air_temperature"]
    assert air["between"]["runs"] == RUNS and float(air["between"]["r2"]) >= 0.9, air       # the day predicts the run...
    assert abs(float(air["within"]["t"])) < 2, air                                           # ...and nothing within it
    # 0622's review named the air temperature; this one does not, nor the run
    v2 = {a["area"] for a in db.json(f"SELECT public.ottoq_arbiter_self_assessment_v2('{DEPOT}', {SINCE})")["improvement_areas"]}
    assert "charge_clock_misses_ambient_c_dcfc" in v2 and "charge_clock_misses_run_dcfc" in v2, v2
    r = _review(db, SINCE)
    assert not any(a.startswith(("charge_clock_misses", "charge_clock_stale")) for a in _areas(r)), list(_areas(r))
    for a in r["improvement_areas"]:
        _plain(a)


def test_0626_a_temperature_that_moves_charges_within_runs_is_named_with_both_slopes(db):
    _through_0626(db)
    arb._fleet(db, RUNS)
    _weather(db, per_degree=0.015)
    arb._fit(db)
    r = _review(db, SINCE)
    areas = _areas(r)
    a = areas["charge_clock_misses_air_temperature"]
    _plain(a)
    assert (a["kind"], a["part"], a["status"], a["tier"], a["thin"]) == ("capability_gap", "charge_times", "open", 2, False), a
    k = {x["kind"]: x for x in a["evidence"]["by_kind"]}
    assert list(k) == ["dcfc"], k                                    # L2 charges do not move with the air: not named
    w, b = k["dcfc"]["within"], k["dcfc"]["between"]
    assert abs(float(w["per_degree"]) - 0.015) < 0.004 and float(w["t"]) >= 3, w
    # between runs the slope carries the run's own level too (the warmer runs were planted slower): 0.015 + 1/60
    assert abs(float(b["per_degree"]) - (0.015 + 1 / 60)) < 0.006 and float(b["r2"]) >= 0.9 and b["runs"] == RUNS, b
    assert a["finding"].startswith("Charges on fast chargers ran ") and "for each degree warmer between runs (8 runs" in a["finding"]
    assert "within them (t " in a["finding"] and a["action"].startswith("Give the clock a level for the air temperature")
    # with nothing graded, nothing has an impact, and the clock's areas rank by tier then weight
    assert a["impact"] is None and r["graded"] == 0 and a["rank"] == 1, (a["rank"], [x["area"] for x in r["improvement_areas"]])


# ── a change in the clock's world ─────────────────────────────────────────────────────────────────────────────────────

def _runs_table(d, runs=RUNS):
    """The planted fleet's runs as the run table keeps them: completed, at the depot, started a minute before their
    first charge."""
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at, run_by, policy)
              SELECT l.sim_run_id, '{DEPOT}', 'completed', min(l.recorded_at) - interval '1 minute', 'operator_demo', 'otto_q'
                FROM public.ottoq_charge_duration_ledger l
               WHERE l.sim_run_id IN ({", ".join(rg._run(r) for r in range(runs))}) GROUP BY l.sim_run_id""")


def _migrations(d, at):
    """What was applied while the world changed, as the database keeps it: one migration that redefines how the twin
    charges, at the moment the change took effect, and one that does not."""
    d.val(f"""CREATE SCHEMA supabase_migrations;
              CREATE TABLE supabase_migrations.schema_migrations (version text PRIMARY KEY, statements text[], name text);
              INSERT INTO supabase_migrations.schema_migrations VALUES
                (to_char(('{at}'::timestamptz) AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS'),
                 ARRAY['CREATE OR REPLACE FUNCTION public.ottoq_sim_compute_charge_rate(p numeric) RETURNS numeric'],
                 'the_charge_curves_change'),
                (to_char(('{at}'::timestamptz + interval '1 minute') AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS'),
                 ARRAY['CREATE OR REPLACE FUNCTION public.ottoq_value_summary() RETURNS jsonb'], 'the_value_tab')""")
    return d.val(f"SET TIME ZONE 'UTC'; SELECT to_jsonb(date_trunc('second', '{at}'::timestamptz)) #>> '{{}}'")


def test_0626_a_change_the_scan_names_is_an_area_with_its_record_and_its_trial(db):
    _through_0626(db)
    _classes(db)
    boundary = rg._fleet_with_a_change(db, runs=RUNS, change=RUNS - 3, shift=1.0)
    arb._fit(db)                                                  # the clock, fitted across the change
    _runs_table(db)
    at = _migrations(db, boundary)
    r = _review(db, SINCE, trial=True)
    a = _areas(r)["charge_clock_world_changed_dcfc"]
    _plain(a)
    assert (a["kind"], a["part"], a["status"], a["tier"], a["rank"]) == ("world_changed", "charge_times", "open", 1, 1), a
    assert "l2" not in {x["area"].rsplit("_", 1)[-1] for x in r["improvement_areas"] if x["kind"] == "world_changed"}
    assert re.search(r"changed: Alpha \d+% shorter", a["finding"]), a["finding"]
    assert "2 changes to the engine were applied in that window, 1 of them to how charging works." in a["finding"], a["finding"]
    ct = db.val(f"SELECT public.ottoq_review_ct('{at}')")
    assert f"Fitted only on what came after {ct}, the clock's mean miss on the latest run's 36 charges on fast chargers " \
           "would go from " in a["finding"], a["finding"]
    assert a["action"] == f"If a change in the engine explains it, record it for fast chargers from {ct}: the clock learns " \
                          "from it that night.", a["action"]
    rec = a["evidence"]["record"]
    assert rec == {"model": "charge_time_v2", "scope": "dcfc", "depot_id": DEPOT, "starts_at": at,
                   "source": "migration " + db.val(f"SELECT to_char(('{at}'::timestamptz) AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS')")
                             + " the_charge_curves_change"}, rec
    t = a["evidence"]["trial"]
    assert t["runs"] == [db.val(f"SELECT {rg._run(RUNS - 1)}::text")] and t["regimes_b"]["dcfc"]["applied"] is True, t
    assert float(t["by_kind"]["dcfc"]["mae_b"]) < 0.75 * float(t["by_kind"]["dcfc"]["mae_a"]), t["by_kind"]
    assert r["world_trials"]["dcfc"] == t
    # without the trial the area stands on the scan alone
    a0 = _areas(_review(db, SINCE))["charge_clock_world_changed_dcfc"]
    assert a0["evidence"]["trial"] is None and "Fitted only on" not in a0["finding"], a0
    # the nightly review writes it, with nothing graded, trial and all
    aid = db.val(f"SELECT public.ottoq_arbiter_assess('{DEPOT}', 10)")
    row = db.json(f"SELECT to_jsonb(x) FROM public.ottoq_arbiter_assessments x WHERE assessment_id = {aid}")
    assert row["n_graded"] == 0 and row["assessment"]["v"] == 3 and row["assessment"]["world_trials"]["dcfc"] == t, row
    assert row["improvement_areas"][0]["area"] == "charge_clock_world_changed_dcfc", row["improvement_areas"][0]
    # once a person records it and the clock is refitted, the scan finds nothing more and the area is gone
    rg._record(db, "dcfc", at)
    arb._fit(db)
    assert "charge_clock_world_changed_dcfc" not in _areas(_review(db, SINCE))


# ── graded orders by hand ─────────────────────────────────────────────────────────────────────────────────────────────

PARTS = ("arrivals", "appeared", "charge_times", "running", "faults")


def _graded(d, oid, *, cars=(), inbound=(), real_cars=None, real_inbound=None, appeared=(), forecast=None, moves=(),
            taken=True, p_win=1.0, wins=12, hind_cmp=1, hind=None, observed=90, models=None, outflow=None, at_min=0):
    """A graded order: its snapshot (the check's state, with `models` and `outflow` where given) and its hindsight row
    (what came of it, the forecast errors, the moves)."""
    st = {"ttl_min": 3, "pin_min": 90, "horizon_min": 480, "cars": list(cars), "inbound": list(inbound), "chargers": []}
    if models is not None:
        st["models"] = models
    if outflow is not None:
        st["outflow"] = outflow
    rz = {"observed_min": observed, "cars": real_cars or {}, "inbound": real_inbound or {}, "appeared": list(appeared),
          "chargers": {}, "back": []}
    at = f"'{T}'::timestamptz + interval '{at_min} minutes'"
    d.val(f"""INSERT INTO public.ottoq_charge_order_snapshots (order_id, sim_run_id, depot_id, sim_clock, seed, futures,
                                                               win_frac, state, agent_order, code_md5)
              VALUES ({oid}, '{RUN}', '{DEPOT}', {at}, 'hand', 12, 0.8, $j${json.dumps(st)}$j$::jsonb, '{{}}', 'hand')""")
    mv = "ARRAY[" + ", ".join(f"'{m}'" for m in moves) + "]::text[]" if moves else "'{}'::text[]"
    d.val(f"""INSERT INTO public.ottoq_charge_order_hindsight (order_id, sim_run_id, depot_id, sim_clock, window_min,
                observed_min, status, reason, taken, decision, futures, wins, need, p_win, expected, hindsight, outcome,
                moves, forecast, fidelity, realized, code_md5)
              VALUES ({oid}, '{RUN}', '{DEPOT}', {at}, 90, {observed}, '{'accepted' if taken else 'refused'}',
                      'wins_most_futures', {str(taken).lower()}, true, 12, {wins}, 10, {p_win}, '{{"cmp": 1}}',
                      $j${json.dumps(hind or {"cmp": hind_cmp})}$j$::jsonb, 'right_take', {mv},
                      $j${json.dumps(forecast or {})}$j$::jsonb, '{{}}',
                      $j${json.dumps(rz)}$j$::jsonb, 'hand')""")


def _attribution(d, oid, cmp):
    """The order's Shapley split: `cmp` gives each part's share of the verdict, the rest 0."""
    sh = {p: {"cmp": cmp.get(p, 0), "on_time": 0, "late": 0, "flow": 0} for p in PARTS}
    d.val(f"""INSERT INTO public.ottoq_charge_order_attribution (order_id, sim_run_id, depot_id, parts, subset_values,
                                                                 shapley, verdict_changed, code_md5)
              VALUES ({oid}, '{RUN}', '{DEPOT}', ARRAY['arrivals','appeared','charge_times','running','faults'], '[]',
                      $j${json.dumps(sh)}$j$::jsonb, true, 'hand')""")


def _arrivals(n_bulk, early, late, bulk_sd=1.0, horizon=40, short=10, trip=2, esd=0.1, start=0):
    """Inbound cars forecast home and when each came: the bulk at the normal quantiles times bulk_sd (in spreads), the
    early ones 6 spreads early, the late ones 8 spreads late on short trips. Returns (state entries, realized)."""
    from statistics import NormalDist
    nd = NormalDist()
    zs = [(nd.inv_cdf((i + 0.5) / n_bulk) * bulk_sd, horizon) for i in range(n_bulk)]
    zs += [(-6.0, horizon)] * early + [(8.0, short)] * late
    inb, real = [], {}
    for i, (z, hz) in enumerate(zs):
        cid = f"car-{start + i}"
        fc = trip + hz
        inb.append({"id": cid, "src": "forecast", "eta": fc, "trip": trip, "esd": esd})
        real[cid] = {"arrived": True, "eta": round(trip + hz * pow(2.718281828459045, z * esd), 4)}
    return inb, real


# ── the arrivals: the bulk and the tails ──────────────────────────────────────────────────────────────────────────────

def test_0626_the_arrivals_misses_are_split_into_the_bulk_and_the_tails(db):
    _through_0626(db)
    inb, real = _arrivals(300, 6, 6)
    for k in range(12):                                          # twelve orders, 26 of the cars in each
        _graded(db, 9600 + k, inbound=inb[26 * k:26 * (k + 1)], real_inbound=real)
    r = _review(db)
    t = r["arrival_tails"]
    assert (t["n"], t["early"]["n"], t["late"]["n"]) == (312, 6, 6), t
    assert abs(float(t["bulk"]["sd_z"]) - 1) < 0.05 and abs(float(t["bulk"]["mean_z"])) < 0.01, t["bulk"]
    assert float(t["late"]["mean_minutes_to_reserve"]) == 10 and float(t["bulk"]["mean_minutes_to_reserve"]) == 40, t
    a = _areas(r)["arrival_spread"]
    _plain(a)
    assert (a["kind"], a["part"], a["status"], a["tier"]) == ("capability_gap", "arrivals", "open", 2), a
    assert a["title"] == "A few cars come home far from their forecast", a["title"]
    early_min = round(40 * (pow(2.718281828459045, -0.6) - 1), 1)
    assert f"6 cars (1.9%) came home a mean {abs(early_min)} minutes early, before their battery reached the reserve" \
        in a["finding"], a["finding"]
    assert "The late ones were on short trips, a mean 10.0 minutes from the reserve against 40.0 for the rest" in a["finding"]
    assert a["action"] == ("Sample an early call home in the futures, at the rate the depot's own returns show; add a "
                           "delay in minutes to each return, not only a share of the trip."), a["action"]


def test_0626_a_bulk_wider_than_the_futures_sample_is_said_so(db):
    _through_0626(db)
    inb, real = _arrivals(100, 0, 0, bulk_sd=2.0)
    for k in range(4):
        _graded(db, 9700 + k, inbound=inb[25 * k:25 * (k + 1)], real_inbound=real)
    a = _areas(_review(db))["arrival_spread"]
    _plain(a)
    assert (a["kind"], a["title"]) == ("calibration", "Cars come home with more spread than its futures sample"), a
    assert a["action"] == "Widen the futures' return spread to what arrivals show.", a["action"]


# ── ranked by impact, open before built ───────────────────────────────────────────────────────────────────────────────

def test_0626_ranks_by_impact_and_marks_built_what_was_rebuilt_after_the_orders(db):
    _through_0626(db)
    arb._fleet(db, 6)
    arb._fit(db)                                                  # the depot's clock is now charge_time_v2
    _classes(db)
    inb, real = _arrivals(120, 0, 0)                              # arrivals the futures sample well
    # twelve orders timed by the clock before it (no model named: 0619's), none carrying an outflow; fast charges ran a
    # third shorter than forecast; charges under way ended 5 minutes early; cars came home unseen, having left after
    for k in range(12):
        cars = [{"id": f"f{k}-{j}", "md": 30, "sd": 0.1, "ml": 120, "sl": 0.1} for j in range(3)]
        rc = {c["id"]: {"k0": "dcfc", "s0": 1, "m": 20, "cen": False} for c in cars}
        _graded(db, 9800 + k, cars=cars, real_cars=rc, inbound=inb[10 * k:10 * (k + 1)], real_inbound=real,
                appeared=[{"id": f"u{k}", "how": "returned", "eta": 40, "soc": 30}],
                forecast={"running": {"n": 10, "sum_err": -50, "sum_abs_err": 100}})
        _attribution(db, 9800 + k, {"arrivals": 1.0} if k < 5 else {"appeared": 1.0} if k < 8 else
                     {"running": 1.0} if k < 10 else {"charge_times": 1.0} if k < 11 else {"faults": 1.0})
    r = _review(db)
    assert r["clocks"]["rebuilt_since"] == "model" and r["clocks"]["now"]["model"] == "charge_time_v2", r["clocks"]
    order = [(a["area"], a["status"], a["thin"], a["impact"]) for a in r["improvement_areas"]]
    assert [a["rank"] for a in r["improvement_areas"]] == list(range(1, len(order) + 1))
    for a in r["improvement_areas"]:
        _plain(a)
    strong = [o for o in order if o[1] == "open" and not o[2]]
    # the largest part first; the clock's own audit of this fleet (its band levels sit 2.5% off within runs, a level a
    # weighted median leaves between the planted runs' steps) ranks with how long charges took, ahead of the faults
    # alone; the hour of day, which always meets the same band here, is not named for it
    assert strong[0] == ("forecast_arrivals", "open", False, 0.417) and strong[-1] == ("forecast_faults", "open", False, 0.083), order
    assert {o[0] for o in strong[1:-1]} <= {"charge_clock_stale_band"} and all(o[3] == 0.083 for o in strong[1:-1]), order
    assert not any(o[0].startswith("charge_clock_misses") for o in order), order
    built = [o for o in order if o[1] == "built"]
    assert built == [("forecast_appeared", "built", False, 0.25), ("forecast_running", "built", False, 0.167),
                     ("charge_clock_dcfc", "built", False, 0.083)], order
    assert order.index(built[0]) > max(order.index(o) for o in order if o[1] == "open"), order
    areas = _areas(r)
    assert "these orders were timed by an earlier charge clock" in areas["charge_clock_dcfc"]["finding"].lower()
    assert areas["charge_clock_dcfc"]["title"] == "Charges on fast chargers ran 33% shorter than it forecast"
    assert areas["forecast_running"]["title"] == "Charges under way ended sooner than it expected"
    assert "They ended a mean 5.00 minutes sooner than it expected, missing by a mean 10.00 minutes over 120 charges." \
        in areas["forecast_running"]["finding"], areas["forecast_running"]["finding"]
    ap = areas["forecast_appeared"]
    assert "1.00 cars a window came home unseen" in ap["finding"] and "none of the 12 orders graded here carried it" in ap["finding"], ap
    assert ap["action"].startswith("Grade the next armed run's orders"), ap
    assert areas["forecast_faults"]["action"].startswith("Sample charger faults in the futures"), areas["forecast_faults"]
    assert (r["areas_open"], r["areas_built"]) == (len(order) - 3, 3)


# ── the outflow's grade ───────────────────────────────────────────────────────────────────────────────────────────────

def test_0626_the_outflow_grade_names_what_its_forecast_missed(db):
    _through_0626(db)
    flow = {"cars": 10, "modelled": 5, "real": 3, "hits": 2, "unseen": 1, "unseen_returned": 1,
            "dwell": {"seen": 10, "left": 8, "p_left": 6, "brier": 1.0, "pit_n": 8, "pit50": 6, "pit80": 7, "pit_sum": 3},
            "dwell_pooled": {"seen": 10, "left": 8, "p_left": 6.5, "brier": 1.1},
            "dwell_by": {"bay": {"seen": 3, "left": 2, "p_left": 1, "brier": 0.9, "brier_pooled": 0.6},
                         "clear": {"seen": 7, "left": 6, "p_left": 5, "brier": 0.1, "brier_pooled": 0.5}}}
    for k in range(12):
        _graded(db, 9900 + k, outflow={"v": 2}, forecast={"outflow": flow},
                models={"charge_time": 1, "charge_time_model": "charge_time_v2", "return": 2})
        _attribution(db, 9900 + k, {"appeared": 1.0})
    r = _review(db)
    areas = _areas(r)
    assert r["outflow_grade"]["orders"] == 12 and r["outflow_grade"]["dwell"]["seen"] == 120, r["outflow_grade"]
    assert set(a for a in areas if a.startswith("outflow")) == \
        {"outflow_departures", "outflow_dwell_class_bay", "outflow_returns", "outflow_dwell_shape"}, list(areas)
    assert "forecast_appeared" not in areas and "outflow_dwell_base_rate" not in areas      # it beats the base rate
    for name in ("outflow_departures", "outflow_dwell_class_bay", "outflow_returns", "outflow_dwell_shape"):
        a = areas[name]
        _plain(a)
        assert (a["part"], a["impact"], a["status"], a["tier"]) == ("appeared", 1, "open", 2), a
    assert areas["outflow_departures"]["title"] == "More charged cars left than it expected"
    assert "it expected 72 to leave inside their windows and 96 did (1.33 of expected)" in areas["outflow_departures"]["finding"]
    bay = areas["outflow_dwell_class_bay"]
    assert bay["title"] == "Its departure curve for cars waiting on a bay service does worse than one curve for all", bay
    assert "scored a Brier of 0.3000 on their own curve and 0.2000 on the curve for all cars" in bay["finding"], bay
    assert bay["action"].startswith("Time a bay car's departure from the bays' own queue"), bay
    assert areas["outflow_returns"]["title"] == "It brings cars back sooner than they come"
    assert areas["outflow_dwell_shape"]["title"] == "Cars leave sooner after a charge than its curves say"


# ── the bar and the agent's moves, in words ───────────────────────────────────────────────────────────────────────────

def test_0626_the_bar_and_the_agents_moves_are_said_plainly_and_thin_evidence_says_so(db):
    _through_0626(db)
    # twelve decisions the check took at 11 of 12 futures, each lost in hindsight; the agent's orders that only
    # reordered the line lost every time
    for k in range(12):
        _graded(db, 9950 + k, moves=["reorder_only"], p_win=11 / 12, wins=11,
                hind={"cmp": -1, "d_on_time": -1, "d_late": 5, "d_flow": 10})
    r = _review(db)
    areas = _areas(r)
    bar = areas["bar_stricter"]
    _plain(bar)
    assert bar["title"] == "Taking none of these orders would have done better", bar
    assert bar["finding"].startswith("In hindsight, taking none of these orders would have done better than the bar it ran "
                                     "under (0.80 of the futures), which took 12 (0 won, 12 lost)"), bar["finding"]
    assert bar["thin"] is False and bar["action"].startswith("Test a bar of 1.0 in a paired twin run"), bar
    mv = areas["agent_move_loses_reorder_only"]
    _plain(mv)
    assert mv["title"] == "The agent's orders that only reordered the line keep losing", mv
    assert "lost to the kernel's own order in hindsight 12 times of 12 (won 0); the check took 12." in mv["finding"], mv
    fu = areas["futures_uninformative"]
    _plain(fu)
    assert fu["thin"] is True and "within each other's noise" in fu["finding"], fu
    # thin areas rank after every strong open one
    ranks = {a["area"]: a["rank"] for a in r["improvement_areas"]}
    assert ranks["futures_uninformative"] > max(ranks[a] for a in ranks if not areas[a]["thin"]), ranks
