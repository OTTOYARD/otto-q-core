"""db/migrations/0625, EXECUTED: a learned model knows when its world changed, and finds the change itself.

WHY THIS EXISTS. 0625 gives the charge clock (0622) a record of the changes in its world, honoured per kind of charger by
every fit; a scan that finds such a change in the clock's own evidence and lists the migrations applied while it
happened; and a trial that measures a cut out of sample. Every claim in its header that a test can execute is executed
here, on the scratch PostgreSQL and the miniature depot of tests/test_agent_charge_order_sql.py, through 0619-0624 as
tests/test_agent_dwell_class_sql.py applies them, with 0622's planted fleet:
  - it applies, its checks run, the record is append-only and read-only to the browser, the fit and the trial are the
    service's alone, and it refuses a body it was not written against;
  - the record's reader: the latest change per scope inside the window, a depot's own and every depot's, never another
    depot's, and nothing for a model the record does not know;
  - with nothing recorded inside the window the params are 0622's key for key;
  - a change recorded on fast chargers fits them on the charges after it alone, every L2 key as it was, and the class
    the change moved is timed at its new level; a cut on every kind cuts both; a kind the clock does not know is refused;
  - a change too recent to carry the fast chargers by itself waits, says so, and leaves the fit 0622's;
  - the fit honours the record, and its code md5 covers the cut and the record's reader;
  - the scan names a planted change on the kind and the class it moved, bounds when, lists the migrations applied in
    that time and marks the one that redefined a charging function; names nothing on L2 and nothing once the change is
    recorded; and groups the charges recorded outside any run by day;
  - the trial: on the runs after a change, the cut beats the uncut clock on fast chargers and leaves L2 exactly as it was.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622 and the planted fleet)
import test_agent_dwell_class_sql as dw  # noqa: E402  (0623-0624)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0625 = os.path.join(ROOT, "db", "migrations", "0625_a_learned_model_knows_when_its_world_changed.sql")
DEPOT = base.DEPOT
_file = arb._file

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

RUNS = 8          # the planted fleet's runs, a day apart, the last a day ago
CHANGE = 4        # the first run after the planted change (0-based)
SHIFT = 0.5       # how much longer alpha's fast charges ran before it, in log


def _apply(d):
    return _file(d, M0625)


def _clear_record(d):
    """The miniature depot carries the twin depot's id, so 0625's record of 0573 is its own too, and inside a 21-day
    window until 2026-10-21. A test that plants its own world starts from an empty record, so that what it asserts does
    not depend on the day it runs (the record's override is a session's deliberate act; this is a scratch database)."""
    d.val("BEGIN; SET LOCAL ottoq.evidence_regimes_unlock = 'on'; DELETE FROM public.ottoq_evidence_regimes; COMMIT;")


def _through_0625(d, clear=True):
    dw._through_0624(d)
    err = _apply(d)
    if clear:
        _clear_record(d)
    return err


def _run(r):
    """The planted fleet's run r (arb._fleet keys each run as md5('cc-run-' || r))."""
    return f"md5('cc-run-{r}')::uuid"


def _fleet_with_a_change(d, runs=RUNS, change=CHANGE, shift=SHIFT):
    """0622's planted fleet, with class alpha's fast charges running exp(shift) longer in the runs before `change`: a
    world that changed between run change-1 and run change. Returns the moment half a day after run change-1's last
    record, which is when the record says it changed."""
    arb._fleet(d, runs)
    d.val(f"""UPDATE public.ottoq_charge_duration_ledger l SET duration_min = round(l.duration_min * exp({shift})::numeric, 3)
               FROM public.vehicles v
              WHERE v.id = l.vehicle_id AND v.vehicle_class_code = 'alpha_av_2024' AND l.charger_type = 'dcfc'
                AND l.sim_run_id IN ({", ".join(_run(r) for r in range(change))})""")
    return _ts(d, f"""SELECT max(recorded_at) + interval '12 hours' FROM public.ottoq_charge_duration_ledger
                       WHERE sim_run_id = {_run(change - 1)}""")


def _record(d, scope, starts_at, depot=DEPOT, model="charge_time_v2"):
    dep = "NULL" if depot is None else f"'{depot}'"
    d.val(f"""INSERT INTO public.ottoq_evidence_regimes (model, scope, depot_id, starts_at, reason, source)
              VALUES ('{model}', '{scope}', {dep}, '{starts_at}', 'a change planted by the test, on purpose', 'test')""")


def _params(d, through, cuts=None):
    if cuts is None:
        return d.json(f"SELECT public.ottoq_charge_time_v2_params('{DEPOT}', '{through}', interval '21 days', 3)")
    return d.json(f"""SELECT public.ottoq_charge_time_v2_params_cut('{DEPOT}', '{through}', interval '21 days', 3,
                                                                    $j${json.dumps(cuts)}$j$::jsonb)""")


def _ts(d, sql):
    """A moment as the record's reader and the scan write it: jsonb's ISO text, in UTC."""
    return d.val(f"SET TIME ZONE 'UTC'; SELECT to_jsonb(({sql})::timestamptz) #>> '{{}}'")


def _now(d):
    return _ts(d, "SELECT now()")


def _l2(p):
    """Every part of a params that is about L2."""
    out = {k: {x: v for x, v in p[k].items() if x.startswith("l2")}
           for k in ("cells", "class_cells", "model_cells", "vehicle_cells")}
    out.update({k: p[k].get("l2") for k in ("icc", "run", "session", "population")})
    out["within_sd"] = {x: v for x, v in p["diagnostics"]["within_sd"].items() if x.startswith("l2")}
    out["rms_ladder"] = {x: v.get("l2") for x, v in p["diagnostics"]["rms_ladder"].items()}
    out["rest"] = {k: v for k, v in p.items() if k not in ("cells", "class_cells", "model_cells", "vehicle_cells", "icc",
                                                           "run", "session", "population", "diagnostics", "regimes")}
    return out


def _alpha_f(d, params):
    """The clock's log factor on a fast charger, from 50%, for each alpha car, and its planted post-change value."""
    m = {"params": params}
    out = []
    for cls, make, model, ce, me in arb.FLEET:
        if cls != "alpha_av_2024":
            continue
        for k, ve in enumerate(arb.CAR_EFF):
            c = arb._clock(d, m, "dcfc", arb._who(d, arb._fleet_car(cls, model, k)), 50)
            out.append((float(c["f"]), ce + me + ve))
    return out


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0625_applies_and_its_checks_run(db):
    err = _through_0625(db, clear=False)
    assert "0625 V0: the twin depot has 0 fast charges to scan" in err, err
    assert "0625 V1(a): through 2026-09-30 11:53:00 over 2 days, 0622's params key for key; run d9d49732 is not here" \
        in err, err
    assert "0625 V2: run d9d49732 is not here" in err, err
    assert "0625 V3: the fit at apply" in err and "is not usable here" in err, err
    seed = db.json("""SET TIME ZONE 'UTC'; SELECT jsonb_build_object('model', model, 'scope', scope, 'depot', depot_id, 'at', starts_at,
                                                'source', source)
                        FROM public.ottoq_evidence_regimes""")
    assert seed == {"model": "charge_time_v2", "scope": "dcfc", "depot": "11111111-1111-1111-1111-111111111111",
                    "at": "2026-09-30T11:53:08+00:00",
                    "source": "migration 0573 (20260930115308); found by ottoq_evidence_regime_scan (0625 V0); "
                              "recorded by 0625"}, seed
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0625_%'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0625_pre'") == "2"
    priv = db.json("""SELECT jsonb_build_object(
        'read', has_table_privilege('anon', 'public.ottoq_evidence_regimes', 'SELECT'),
        'write', has_table_privilege('anon', 'public.ottoq_evidence_regimes', 'INSERT')
                 OR has_table_privilege('authenticated', 'public.ottoq_evidence_regimes', 'INSERT'),
        'rls', (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.ottoq_evidence_regimes'::regclass),
        'cuts', has_function_privilege('anon', 'public.ottoq_evidence_regime_cuts(text,uuid,timestamptz,timestamptz)', 'EXECUTE'),
        'scan', has_function_privilege('anon', 'public.ottoq_evidence_regime_scan(uuid,timestamptz,jsonb)', 'EXECUTE'),
        'cut_fit', has_function_privilege('anon',
                     'public.ottoq_charge_time_v2_params_cut(uuid,timestamptz,interval,numeric,jsonb)', 'EXECUTE'),
        'params', has_function_privilege('authenticated',
                     'public.ottoq_charge_time_v2_params(uuid,timestamptz,interval,numeric)', 'EXECUTE'),
        'trial', has_function_privilege('authenticated',
                     'public.ottoq_charge_clock_trial(uuid,uuid[],timestamptz,jsonb,jsonb,boolean)', 'EXECUTE'),
        'trial_service', has_function_privilege('service_role',
                     'public.ottoq_charge_clock_trial(uuid,uuid[],timestamptz,jsonb,jsonb,boolean)', 'EXECUTE'))""")
    assert priv == {"read": True, "write": False, "rls": True, "cuts": True, "scan": True, "cut_fit": False,
                    "params": False, "trial": False, "trial_service": True}, priv


def test_0625_refuses_a_clock_it_was_not_written_against(db):
    dw._through_0624(db)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_charge_clock_model(p_depot uuid) RETURNS jsonb
              LANGUAGE sql STABLE AS $f$ SELECT NULL::jsonb $f$""")
    rc, err = db.file(M0625)
    assert rc != 0 and "0625 P1" in err and "the depot's clock" in err, err


def test_0625_the_record_is_append_only(db):
    _through_0625(db, clear=False)
    rc, out, err = db.run("UPDATE public.ottoq_evidence_regimes SET reason = reason || ' again'")
    assert rc != 0 and "append-only" in err and "UPDATE refused" in err, err
    rc, out, err = db.run("DELETE FROM public.ottoq_evidence_regimes")
    assert rc != 0 and "append-only" in err and "DELETE refused" in err, err
    # the override exists, and is a session's deliberate act
    assert db.val("""BEGIN; SET LOCAL ottoq.evidence_regimes_unlock = 'on';
                     UPDATE public.ottoq_evidence_regimes SET source = source || '.'; ROLLBACK;
                     SELECT count(*) FROM public.ottoq_evidence_regimes WHERE source LIKE '%.'""") == "0"
    # a model the record does not know, a kind the clock does not know, and a reason that says nothing are refused
    for bad in ("('return_v1', 'dcfc', now(), 'a change planted by the test, on purpose', 'test')",
                "('charge_time_v2', 'dcfx', now(), 'a change planted by the test, on purpose', 'test')",
                "('charge_time_v2', 'dcfc', now(), 'changed', 'test')"):
        rc, out, err = db.run(f"""INSERT INTO public.ottoq_evidence_regimes (model, scope, starts_at, reason, source)
                                  VALUES {bad}""")
        assert rc != 0 and "violates check constraint" in err, (bad, err)


# ── the record's reader ───────────────────────────────────────────────────────────────────────────────────────────────

def test_0625_the_cuts_are_the_latest_change_per_scope_inside_the_window(db):
    _through_0625(db, clear=False)
    other = "22222222-2222-2222-2222-222222222222"
    _record(db, "dcfc", "2026-08-02T00:00:00+00:00")
    _record(db, "dcfc", "2026-08-05T00:00:00+00:00")
    _record(db, "dcfc", "2026-08-09T00:00:00+00:00")        # after the window
    _record(db, "l2", "2026-08-04T00:00:00+00:00", depot=other)
    _record(db, "*", "2026-08-03T00:00:00+00:00", depot=None)
    _record(db, "l2", "2026-08-01T00:00:00+00:00")           # at the window's start: not inside it

    def cuts(depot, frm="2026-08-01T00:00:00+00:00", thr="2026-08-08T00:00:00+00:00", model="charge_time_v2"):
        return db.json(f"SELECT public.ottoq_evidence_regime_cuts('{model}', '{depot}', '{frm}', '{thr}')")
    assert cuts(DEPOT) == {"dcfc": "2026-08-05T00:00:00+00:00", "*": "2026-08-03T00:00:00+00:00"}
    assert cuts(other) == {"l2": "2026-08-04T00:00:00+00:00", "*": "2026-08-03T00:00:00+00:00"}
    # the window is (from, through]: a change at through is inside it, one at from is not
    assert cuts(DEPOT, thr="2026-08-09T00:00:00+00:00")["dcfc"] == "2026-08-09T00:00:00+00:00"
    assert cuts(DEPOT, frm="2026-08-05T00:00:00+00:00") == {}
    assert cuts(DEPOT, model="return_v1") == {}
    # 0625's record of 0573 is the twin depot's (whose id the miniature depot carries), and no other depot's
    assert cuts(DEPOT, frm="2026-09-29T00:00:00+00:00", thr="2026-10-01T00:00:00+00:00") == \
        {"dcfc": "2026-09-30T11:53:08+00:00"}
    assert cuts(other, frm="2026-09-29T00:00:00+00:00", thr="2026-10-01T00:00:00+00:00") == {}


# ── the fit honours it ────────────────────────────────────────────────────────────────────────────────────────────────

def test_0625_with_nothing_recorded_inside_the_window_the_params_are_0622s(db):
    dw._through_0624(db)
    arb._fleet(db, RUNS)
    t = _now(db)
    before = _params(db, t)                                   # 0622's own function
    _apply(db)
    _clear_record(db)
    assert _params(db, t) == before                           # the record read, nothing inside the window
    assert _params(db, t, {}) == before                       # no cuts
    assert "regimes" not in before
    # a change older than the window, or after its end, is not a cut
    _record(db, "dcfc", "2026-01-01T00:00:00+00:00")
    _record(db, "*", "2099-01-01T00:00:00+00:00")
    assert _params(db, t) == before
    assert _params(db, t, {"dcfc": "2026-01-01T00:00:00+00:00", "l2": "2099-01-01T00:00:00+00:00"}) == before


def test_0625_a_change_on_fast_chargers_fits_them_on_what_came_after_and_leaves_l2_alone(db):
    _through_0625(db)
    boundary = _fleet_with_a_change(db)
    t = _now(db)
    uncut = _params(db, t)
    _record(db, "dcfc", boundary)
    cut = _params(db, t)
    assert cut == _params(db, t, {"dcfc": boundary})          # the record read is the explicit cut
    after = 3 * 12 * (RUNS - CHANGE)                          # three fast charges a car, twelve cars, four runs
    reg = cut["regimes"]
    assert list(reg) == ["dcfc"] and reg["dcfc"]["applied"] is True, reg
    assert reg["dcfc"]["n_after"] == after == cut["cells"]["dcfc:*"]["n"], (reg, cut["cells"]["dcfc:*"])
    assert reg["dcfc"]["starts_at"] == boundary
    assert uncut["cells"]["dcfc:*"]["n"] == 3 * 12 * RUNS
    # every L2 key is what it was; the fast chargers' runs are the four after the change
    assert _l2(cut) == _l2(uncut)
    assert cut["run"]["dcfc"]["runs"] == RUNS - CHANGE and uncut["run"]["dcfc"]["runs"] == RUNS
    # the class the change moved is timed at its new level: closer than the uncut clock, and within 0.1
    for (fc, target), (fu, _) in zip(_alpha_f(db, cut), _alpha_f(db, uncut)):
        assert abs(fc - target) < 0.1 and abs(fc - target) < abs(fu - target), (fc, fu, target)


def test_0625_a_cut_on_every_kind_cuts_both_and_an_unknown_kind_is_refused(db):
    _through_0625(db)
    boundary = _fleet_with_a_change(db)
    t = _now(db)
    p = _params(db, t, {"*": boundary})
    assert sorted(p["regimes"]) == ["dcfc", "l2"] and all(r["applied"] for r in p["regimes"].values()), p["regimes"]
    assert p["cells"]["l2:*"]["n"] == 2 * 12 * (RUNS - CHANGE) and p["cells"]["dcfc:*"]["n"] == 3 * 12 * (RUNS - CHANGE)
    # a kind's own change later than every kind's wins for it
    later = _ts(db, f"SELECT '{boundary}'::timestamptz + interval '1 day'")
    p = _params(db, t, {"*": boundary, "dcfc": later})
    assert p["regimes"]["dcfc"]["starts_at"] == later and p["regimes"]["l2"]["starts_at"] == boundary, p["regimes"]
    assert p["cells"]["dcfc:*"]["n"] == 3 * 12 * (RUNS - CHANGE - 1)
    rc, out, err = db.run(f"""SELECT public.ottoq_charge_time_v2_params_cut('{DEPOT}', now(), interval '21 days', 3,
                                                                           '{{"dcfx": "{boundary}"}}'::jsonb)""")
    assert rc != 0 and "a cut is {kind: timestamptz}" in err, err


def test_0625_a_change_too_recent_to_carry_the_kind_waits_and_says_so(db):
    _through_0625(db)
    _fleet_with_a_change(db)
    t = _now(db)
    uncut = _params(db, t)
    # after the last run's second fast charge: twelve fast charges after it, short of the 30 a pooled cell needs
    late = _ts(db, f"""SELECT min(recorded_at) + interval '90 seconds' FROM public.ottoq_charge_duration_ledger
                        WHERE sim_run_id = {_run(RUNS - 1)}""")
    _record(db, "dcfc", late)
    p = _params(db, t)
    assert p["regimes"]["dcfc"]["applied"] is False and p["regimes"]["dcfc"]["n_after"] == 12, p["regimes"]
    assert {k: v for k, v in p.items() if k != "regimes"} == uncut
    # with nothing after it at all, the same
    _record(db, "dcfc", t)
    p = _params(db, t)
    assert p["regimes"]["dcfc"] == {"applied": False, "n_after": 0, "n_eff_after": 0, "starts_at": t}, p["regimes"]
    assert {k: v for k, v in p.items() if k != "regimes"} == uncut


def test_0625_the_fit_honours_the_record_and_its_md5_covers_the_cut(db):
    _through_0625(db)
    boundary = _fleet_with_a_change(db)
    _record(db, "dcfc", boundary)
    fid, m = arb._fit(db)
    assert m["estimate_id"] == fid and m["usable"] is True and m["params"]["regimes"]["dcfc"]["applied"] is True, m
    assert db.val(f"""SELECT f.code_md5 = md5(
                          pg_get_functiondef('public.ottoq_charge_time_v2_params(uuid,timestamp with time zone,interval,numeric)'::regprocedure)
                          || pg_get_functiondef('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)'::regprocedure)
                          || pg_get_functiondef('public.ottoq_charge_clock_who(uuid,text,text,text)'::regprocedure)
                          || pg_get_functiondef('public.ottoq_charge_minutes_estimate(numeric,numeric,numeric,numeric,numeric)'::regprocedure)
                          || pg_get_functiondef('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)'::regprocedure)
                          || pg_get_functiondef('public.ottoq_evidence_regime_cuts(text,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure))
                        FROM public.ottoq_charge_clock_fits f WHERE f.fit_id = {fid}""") == "t"


# ── the scan ──────────────────────────────────────────────────────────────────────────────────────────────────────────

def _scan(d, since="now() - interval '21 days'"):
    return d.json(f"SELECT public.ottoq_evidence_regime_scan('{DEPOT}', {since}, NULL)")


def test_0625_the_scan_names_the_change_bounds_when_and_lists_what_was_applied_then(db):
    _through_0625(db)
    boundary = _fleet_with_a_change(db)
    arb._fit(db)                                               # the clock it scans against, fitted across the change
    last_before = _ts(db, f"""SELECT max(recorded_at) FROM public.ottoq_charge_duration_ledger
                                         WHERE sim_run_id = {_run(CHANGE - 1)} AND charger_type = 'dcfc'""")
    first_after = _ts(db, f"""SELECT min(recorded_at) FROM public.ottoq_charge_duration_ledger
                                         WHERE sim_run_id = {_run(CHANGE)} AND charger_type = 'dcfc'""")
    # what was applied while it happened, as the database keeps it: one migration that redefines how the twin charges,
    # one that does not, and one from another day
    db.val(f"""CREATE SCHEMA supabase_migrations;
               CREATE TABLE supabase_migrations.schema_migrations (version text PRIMARY KEY, statements text[], name text);
               INSERT INTO supabase_migrations.schema_migrations VALUES
                 (to_char(('{boundary}'::timestamptz) AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS'),
                  ARRAY['CREATE OR REPLACE FUNCTION public.ottoq_sim_compute_charge_rate(p numeric) RETURNS numeric'],
                  'the_charge_curves_change'),
                 (to_char(('{boundary}'::timestamptz + interval '1 minute') AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS'),
                  ARRAY['CREATE OR REPLACE FUNCTION public.ottoq_value_summary() RETURNS jsonb'], 'the_value_tab'),
                 (to_char(('{boundary}'::timestamptz - interval '3 days') AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS'),
                  ARRAY['CREATE OR REPLACE FUNCTION public.ottoq_sim_stop_charge_session() RETURNS void'],
                  'an_older_charging_change')""")
    s = _scan(db)
    d, l = s["by_kind"]["dcfc"], s["by_kind"]["l2"]
    assert d["named"] is True and l["named"] is False, (d, l)
    assert d["runs"] == RUNS and d["charges"] == 3 * 12 * RUNS and d["recorded"] is None, d
    sp = d["split"]
    assert sp["between"] == [last_before, first_after] and sp["window"] == [last_before, first_after], sp
    assert sp["last_run_before"] == db.val(f"SELECT {_run(CHANGE - 1)}::text")
    assert sp["first_run_after"] == db.val(f"SELECT {_run(CHANGE)}::text")
    cls = sp["classes"]
    assert set(cls) == {"alpha_av_2024", "beta_av_2024"} and sp["df"] == 2, cls
    # alpha moved by the planted shift (less the planted runs' own drift, which moves beta too), beta did not
    drift = sum(arb.RUN_EFF[r % 6] for r in range(CHANGE, RUNS)) / (RUNS - CHANGE) \
        - sum(arb.RUN_EFF[r % 6] for r in range(CHANGE)) / CHANGE
    assert abs(float(cls["alpha_av_2024"]["shift"]) - (drift - SHIFT)) < 0.06, (cls, drift)
    assert abs(float(cls["beta_av_2024"]["shift"]) - drift) < 0.06 and abs(float(cls["beta_av_2024"]["t"])) < 3, cls
    assert float(cls["alpha_av_2024"]["t"]) < -5 and cls["alpha_av_2024"]["runs_before"] == CHANGE, cls
    assert float(sp["q"]) >= 10 * sp["df"] and float(sp["max_shift"]) >= 0.15, sp
    assert sp["migrations"] == [
        {"version": db.val(f"SELECT to_char(('{boundary}'::timestamptz) AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS')"),
         "name": "the_charge_curves_change", "charging": True},
        {"version": db.val(f"""SELECT to_char(('{boundary}'::timestamptz + interval '1 minute') AT TIME ZONE 'UTC',
                                              'YYYYMMDDHH24MISS')"""),
         "name": "the_value_tab", "charging": False}], sp["migrations"]
    assert s["rule"] == {"min_charges_per_run": 3, "min_runs_each_side": 3, "sd_floor": 0.02, "q_per_df": 10,
                         "min_shift": 0.15}, s["rule"]
    # once the change is recorded the scan looks after it, and finds nothing more there
    _record(db, "dcfc", boundary)
    s = _scan(db)
    d = s["by_kind"]["dcfc"]
    assert d["recorded"] == boundary and d["since"] == boundary and d["named"] is False, d
    assert d["runs"] == RUNS - CHANGE and d["charges"] == 3 * 12 * (RUNS - CHANGE), d


def test_0625_the_scan_finds_nothing_in_a_world_that_did_not_change(db):
    _through_0625(db)
    arb._fleet(db, RUNS)
    arb._fit(db)
    s = _scan(db)
    assert s["by_kind"]["dcfc"]["named"] is False and s["by_kind"]["l2"]["named"] is False, s["by_kind"]
    assert float(s["by_kind"]["dcfc"]["split"]["max_shift"]) < 0.15
    assert "migrations" not in s["by_kind"]["dcfc"]["split"]   # where the database keeps none, none are listed


def test_0625_the_scan_groups_charges_outside_any_run_by_day(db):
    _through_0625(db)
    _fleet_with_a_change(db)
    arb._fit(db)
    day = db.val(f"""SELECT 'day ' || to_char(min(recorded_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD')
                       FROM public.ottoq_charge_duration_ledger WHERE sim_run_id = {_run(CHANGE)}""")
    db.val("UPDATE public.ottoq_charge_duration_ledger SET sim_run_id = NULL")
    d = _scan(db)["by_kind"]["dcfc"]
    assert d["named"] is True and d["runs"] == RUNS, d
    assert d["split"]["first_run_after"] == day, (d["split"], day)


# ── the trial ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0625_the_trial_scores_a_cut_out_of_sample(db):
    # a change two runs before the last, as large as the Zoox's at 0573: the uncut clock still weighs the five runs
    # before it more than the two after, and the run it is scored on is the last, which neither fit saw
    _through_0625(db)
    boundary = _fleet_with_a_change(db, change=RUNS - 3, shift=1.0)
    through = _ts(db, f"""SELECT min(recorded_at) - interval '1 minute' FROM public.ottoq_charge_duration_ledger
                           WHERE sim_run_id = {_run(RUNS - 1)}""")
    runs = f"ARRAY[{_run(RUNS - 1)}]"
    t = db.json(f"""SELECT public.ottoq_charge_clock_trial('{DEPOT}', {runs}, '{through}', '{{}}'::jsonb,
                                                           '{{"dcfc": "{boundary}"}}'::jsonb, true)""")
    k = t["by_kind"]
    assert k["dcfc"]["charges"] == 3 * 12 and k["l2"]["charges"] == 2 * 12, k
    assert float(k["dcfc"]["mae_b"]) < 0.75 * float(k["dcfc"]["mae_a"]), k
    assert (k["l2"]["mae_a"], k["l2"]["bias_a"]) == (k["l2"]["mae_b"], k["l2"]["bias_b"]), k
    assert t["regimes_a"] is None and t["regimes_b"]["dcfc"]["applied"] is True, t["regimes_b"]
    assert t["regimes_b"]["dcfc"]["n_after"] == 3 * 12 * 2, t["regimes_b"]
    assert t["params_a"] == _params(db, through, {}) and t["params_b"] == _params(db, through, {"dcfc": boundary})
    assert "params_a" not in db.json(f"""SELECT public.ottoq_charge_clock_trial('{DEPOT}', {runs}, '{through}', '{{}}'::jsonb,
                                                                               '{{}}'::jsonb)""")
    rc, out, err = db.run(f"SELECT public.ottoq_charge_clock_trial('{DEPOT}', ARRAY[]::uuid[], NULL, NULL, NULL)")
    assert rc != 0 and "a depot, and a time or runs that started, are required" in err, err
