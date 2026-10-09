"""db/migrations/0632, EXECUTED: the charge clock reads the air.

WHY THIS EXISTS. 0632 gives the charge clock (0622) a level for the depot's air at each charge's start. The fit learns it
per kind, in whichever shape predicts each run best from the others (no level, a slope, or a slope that bends once),
keeps it only from six runs and when it beats no level by 1% out of sample, and fits the run, the car and the charge in
progress on what it leaves. The clock reads it through the run's evidence, which carries the depot's air. Every claim in
its header that a test can execute is executed here, on the scratch PostgreSQL and the miniature depot of
tests/test_agent_charge_order_sql.py, through 0619-0631 as tests/test_agent_fault_cut_sql.py applies them, with 0622's
planted fleet given an air per run (12 to 29.5 °C, warming 0.4 °C a charge within it) and charges that slow above a bend
(fast charges 3% a degree above 22 °C, L2 2% a degree above 18 °C):
  - it applies, its checks run, the evidence ends with its air, the fit's code md5 covers the level and its solve, every
    reader may call the level, and it refuses a body it was not written against, a run running, and an engine before 0630;
  - the fit finds the L2 bend where it was planted, and the slope above it; fast charges get a level that rises with
    the air;
  - in a world the air does not move, no level is kept;
  - without the air ({"air": false}) the fit is 0625's, key for key;
  - the clock reads the air through the run's evidence from the run's first minute (n 0, air_c), and adds the level;
  - past the air the fit saw, the clock holds the edge and widens its spread by the steepest slope;
  - the run's offset is what the air leaves: on the hottest run, near nothing with the level, large without it;
  - the trial scores the air out of sample: on the two hottest runs, the clock with the level beats the one without;
  - the self-review: orders timed by a clock without the air, graded, are history once the clock reads it, and the air
    area says what the clock reads.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import math
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622, the planted fleet and the morning's helpers)
import test_agent_regrade_sql as rg  # noqa: E402  (0630, and the engine through 0628)
import test_agent_fault_cut_sql as fc  # noqa: E402  (0631)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0632 = os.path.join(ROOT, "db", "migrations", "0632_the_charge_clock_reads_the_air.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_vid, _file = base._vid, arb._file

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

RUNS = 8
WARM = [12 + 2.5 * r for r in range(RUNS)]          # each run's air: 12 to 29.5 °C
FLAT = [22, 14, 26, 12, 24, 18, 20, 16]             # an air that says nothing of the fleet's run effects (0622's RUN_EFF)


def _apply(d):
    return _file(d, M0632)


def _through_0631(d):
    rg.dc._through_0628(d)
    rg._idle(d)
    rg._apply(d)
    fc._apply(d)


def _run(r):
    return f"md5('cc-run-{r}')::uuid"


def _plant(d, airs=WARM, effect=True):
    """0622's planted fleet, each run at its air (the ledger's depot_air_c: the run's air plus 0.4 °C for each of its
    charges, two hours apart), its runs recorded in ottoq_sim_runs, and the twin's reading of the depot's air answered
    from them. With `effect`, a fast charge runs exp(0.03 (air - 22)+) longer and an L2 charge exp(0.02 (air - 18)+)."""
    arb._fleet(d, len(airs))
    vals = ", ".join(f"({_run(r)}, {a})" for r, a in enumerate(airs))
    d.val(f"CREATE TABLE public._air (run uuid PRIMARY KEY, air numeric); INSERT INTO public._air VALUES {vals}")
    d.val("""UPDATE public.ottoq_charge_duration_ledger l
                SET depot_air_c = round(a.air + 0.4 * extract(epoch FROM (l.started_at - date_trunc('day', l.started_at))) / 7200, 2)
               FROM public._air a WHERE a.run = l.sim_run_id""")
    if effect:
        d.val("""UPDATE public.ottoq_charge_duration_ledger
                    SET duration_min = round(duration_min * exp(CASE WHEN charger_type = 'dcfc'
                                                                     THEN 0.03 * GREATEST(depot_air_c - 22, 0)
                                                                     ELSE 0.02 * GREATEST(depot_air_c - 18, 0) END)::numeric, 3)""")
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at, ended_at, sim_clock_start,
                                                sim_clock_current)
              SELECT md5('cc-run-' || r.r)::uuid, '{DEPOT}', 'completed',
                     now() - make_interval(days => {len(airs)} - r.r) - interval '1 hour',
                     now() - make_interval(days => {len(airs)} - r.r) + interval '1 hour',
                     '{T}'::timestamptz + make_interval(days => r.r), '{T}'::timestamptz + make_interval(days => r.r, hours => 12)
                FROM generate_series(0, {len(airs)} - 1) r(r)
              ON CONFLICT (sim_run_id) DO NOTHING""")
    d.val("""CREATE OR REPLACE FUNCTION twin.ottoq_sim_site_ambient_c(p_sim_run_id uuid, p_clock timestamptz) RETURNS numeric
              LANGUAGE sql STABLE AS $f$ SELECT air FROM public._air WHERE run = p_sim_run_id $f$""")


def _model(d):
    return d.json(f"SELECT public.ottoq_charge_clock_model('{DEPOT}')")


def _car(cls="alpha_av_2024", model="A1", k=0):
    return arb._fleet_car(cls, model, k)


def _ev(d, m, r, at="start"):
    col = "sim_clock_start" if at == "start" else "sim_clock_current"
    return d.json(f"""SELECT public.ottoq_charge_clock_run_evidence($j${json.dumps(m)}$j$::jsonb, {_run(r)},
                                                                  (SELECT {col} FROM public.ottoq_sim_runs
                                                                    WHERE sim_run_id = {_run(r)}))""")


def _level(d, lv, air):
    return float(d.val(f"SELECT public.ottoq_charge_clock_air($j${json.dumps(lv)}$j$::jsonb, {air})"))


# ── the migration ─────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0632_applies_and_its_checks_run(db):
    _through_0631(db)
    _plant(db)
    fid, _ = arb._fit(db)
    err = _apply(db)
    assert "0632 V1: the level, the solve and the clock with a planted level read as meant" in err, err
    assert f"0632 V2: on fit {fid} (no level for the air)" in err and "read exactly as before, with and without the air" in err, err
    assert "0632 V3: without the air, 0625's fit key for key" in err and "0632 V4: fit" in err, err
    assert "0632 V5:" in err and "0632 V6:" in err, err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0632_the_charge_clock_reads_the_air'") == "falsefalse"
    # the evidence ends with its air; the fit's code md5 covers the level and its solve; every reader may read the level
    assert db.val("""SELECT attname FROM pg_attribute WHERE attrelid = 'public.ottoq_charge_clock_evidence'::regclass
                      AND attnum > 0 AND NOT attisdropped ORDER BY attnum DESC LIMIT 1""") == "air"
    assert db.val("SELECT (strpos(d, 'public.ottoq_charge_clock_air(jsonb,numeric)') > 0 AND strpos(d, 'public.ottoq_solve_sym3(') > 0)"
                  "::text FROM (SELECT pg_get_functiondef('public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,"
                  "interval,numeric,text)'::regprocedure) AS d) x") == "true"
    assert db.val("SELECT has_function_privilege('anon', 'public.ottoq_charge_clock_air(jsonb,numeric)', 'EXECUTE')::text "
                  "|| has_function_privilege('anon', 'public.ottoq_depot_air_c(uuid,timestamp with time zone)', "
                  "'EXECUTE')::text") == "truetrue"
    # the refit reads the air, on both kinds
    m = _model(db)
    assert int(m["estimate_id"]) > fid and m["params"]["air"]["l2"]["usable"] and m["params"]["air"]["dcfc"]["usable"], m["params"]["air"]
    assert "after_air" in m["params"]["diagnostics"]["rms_ladder"]


def test_0632_refuses_an_engine_before_0630_a_body_it_was_not_written_against_and_a_run_running(db):
    rg.dc._through_0628(db)
    rg._idle(db)
    rc, err = db.file(M0632)
    assert rc != 0 and "0632 P1: public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean) is not " \
                       "the body measured" in err, err
    rg._apply(db)
    fc._apply(db)
    db.val(r"""DO $x$ BEGIN
                    EXECUTE regexp_replace(pg_get_functiondef('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)'::regprocedure),
                                           '\$function\$\n', E'$function$\n-- a later change\n');
                  END $x$""")
    rc, err = db.file(M0632)
    assert rc != 0 and "0632 P1: public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb) " \
                       "is not the body measured" in err, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0632)
    assert rc != 0 and "0632 P0: a run is running" in err, err


# ── the fit ───────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0632_the_fit_finds_the_bend_it_was_given(db):
    _through_0631(db)
    _plant(db)
    _apply(db)
    air = _model(db)["params"]["air"]
    l2, dc = air["l2"], air["dcfc"]
    # L2: a bend where it was planted, flat below it, and the planted slope above it, preferred out of sample
    assert l2["shape"] == "hinge" and abs(float(l2["knee"]) - 18) <= 1, l2
    assert abs(float(l2["b1"])) < 0.006 and 0.012 < float(l2["b1"]) + float(l2["b2"]) < 0.028, l2
    assert float(l2["cv"]["hinge"]) < float(l2["cv"]["linear"]) < float(l2["cv"]["none"]), l2
    assert l2["runs"] == RUNS and float(l2["gain"]) > 0.5 and float(l2["lo"]) < 13 and float(l2["hi"]) > 30, l2
    # fast charges: a level that rises with the air past the planted bend, kept
    assert dc["usable"] and dc["shape"] in ("hinge", "linear"), dc
    assert _level(db, dc, 30) - _level(db, dc, 22) > 0.12, dc
    # the level is centred: over its own evidence it averages zero
    mean = float(db.val("""SELECT sum(public.ottoq_charge_clock_air(m.j #> '{params,air,l2}', l.depot_air_c)
                                      * power(0.5, extract(epoch FROM (f.evidence_through - l.recorded_at)) / 86400.0 / 3))
                                  / sum(power(0.5, extract(epoch FROM (f.evidence_through - l.recorded_at)) / 86400.0 / 3))
                             FROM (SELECT public.ottoq_charge_clock_model('11111111-1111-1111-1111-111111111111') AS j) m
                             JOIN public.ottoq_charge_clock_fits f ON f.fit_id = (m.j ->> 'estimate_id')::bigint
                             JOIN public.ottoq_charge_duration_ledger l ON l.charger_type = 'l2'
                              AND l.recorded_at > f.evidence_from AND l.recorded_at <= f.evidence_through"""))
    assert abs(mean) < 0.002, mean


def test_0632_a_world_the_air_does_not_move_gets_no_level(db):
    _through_0631(db)
    _plant(db, airs=FLAT, effect=False)
    _apply(db)
    air = _model(db)["params"]["air"]
    for kind in ("l2", "dcfc"):
        assert not air[kind]["usable"], air[kind]
    # and the clock reads the same with the air as without it
    m = _model(db)
    who = arb._who(db, _car())
    ev = _ev(db, m, 2, at="end")
    assert ev["l2"]["n"] > 0 and "air_c" not in json.dumps(ev), ev
    assert arb._clock(db, m, "l2", who, 40, run=ev["l2"]) == arb._clock(db, m, "l2", who, 40, run=ev["l2"] | {"air_c": 30})


def test_0632_without_the_air_the_fit_is_0625s(db):
    _through_0631(db)
    _plant(db)
    through = db.val("SELECT now()::text")
    before = db.json(f"SELECT public.ottoq_charge_time_v2_params('{DEPOT}', '{through}', interval '21 days', 3)")
    _apply(db)
    off = db.json(f"""SELECT public.ottoq_charge_time_v2_params_cut('{DEPOT}', '{through}', interval '21 days', 3,
                                                                    '{{"air": false}}')""")
    assert off == before
    on = db.json(f"SELECT public.ottoq_charge_time_v2_params('{DEPOT}', '{through}', interval '21 days', 3)")
    assert "air" in on and "air" not in before
    # the levels above the air are 0625's; the run, the car and the charge in progress are fitted on what it leaves
    for k in ("cells", "class_cells", "model_cells"):
        assert on[k] == before[k], k
    assert float(on["run"]["l2"]["k"]) > float(before["run"]["l2"]["k"]), (on["run"], before["run"])
    # a cut set says the air with a boolean, nothing else
    rc, out, err = db.run(f"""SELECT public.ottoq_charge_time_v2_params_cut('{DEPOT}', now(), interval '21 days', 3,
                                                                           '{{"air": "no"}}')""")
    assert rc != 0 and 'or {"air": boolean} (0632)' in err, err


# ── the clock ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0632_the_clock_reads_the_air_through_the_run_evidence_from_its_first_minute(db):
    _through_0631(db)
    _plant(db)
    _apply(db)
    m = _model(db)
    ev = _ev(db, m, 7)                      # the hottest run, at its first minute: no charge of either kind yet
    for kind in ("l2", "dcfc"):
        assert ev[kind] == {"n": 0, "s": 0, "off": 0, "veh": {}, "air_c": 29.5}, ev
    who = arb._who(db, _car())
    plain = arb._clock(db, m, "l2", who, 40)
    warm = arb._clock(db, m, "l2", who, 40, run=ev["l2"])
    level = _level(db, m["params"]["air"]["l2"], 29.5)
    assert warm["lvl"] == plain["lvl"] + "+air" and abs(float(warm["air"]) - level) < 1e-4, (plain, warm)
    assert abs(float(warm["f"]) - float(plain["f"]) - level) <= 2e-4 and warm["sd"] == plain["sd"], (plain, warm)
    # the level is centred where the clock's evidence sat (the recent runs, warm ones, weigh most): a run hotter than
    # that runs longer than the clock without the air says, a cold one shorter
    cold = arb._clock(db, m, "l2", who, 40, run=_ev(db, m, 0)["l2"])
    assert float(cold["m"]) < float(plain["m"]) < float(warm["m"]), (cold, plain, warm)
    assert abs(float(cold["air"]) - _level(db, m["params"]["air"]["l2"], 12)) < 1e-4, cold
    # the remaining clock reads it too, on both its parts
    rem = db.json(f"""SELECT public.ottoq_charge_clock_remaining($j${json.dumps(m)}$j$::jsonb, 'l2',
                        $j${json.dumps(who)}$j$::jsonb, 75, 40, 60, 100, 19.2, 250, 40, $j${json.dumps(ev['l2'])}$j$::jsonb)""")
    assert "+air" in rem["lvl"], rem


def test_0632_past_the_air_it_saw_the_clock_holds_the_edge_and_widens(db):
    _through_0631(db)
    _plant(db)
    _apply(db)
    m = _model(db)
    lv = m["params"]["air"]["l2"]
    who = arb._who(db, _car())
    hi = arb._clock(db, m, "l2", who, 40, run={"air_c": float(lv["hi"])})
    far = arb._clock(db, m, "l2", who, 40, run={"air_c": float(lv["hi"]) + 10})
    assert far["f"] == hi["f"] and far["m"] == hi["m"], (hi, far)
    assert abs(float(far["sd"]) - math.sqrt(float(hi["sd"]) ** 2 + (float(lv["g"]) * 10) ** 2)) < 2e-4, (hi, far, lv)
    cold = arb._clock(db, m, "l2", who, 40, run={"air_c": float(lv["lo"]) - 20})
    lo = arb._clock(db, m, "l2", who, 40, run={"air_c": float(lv["lo"])})
    assert cold["f"] == lo["f"] and float(cold["sd"]) > float(lo["sd"]), (lo, cold)


def test_0632_the_runs_offset_is_what_the_air_leaves(db):
    _through_0631(db)
    _plant(db)
    pre_fid, pre = arb._fit(db)             # the clock before 0632: no level for the air
    _apply(db)
    m = _model(db)
    with_air = _ev(db, m, 7, at="end")
    without = _ev(db, pre, 7, at="end")
    for kind in ("dcfc", "l2"):
        assert without[kind]["n"] > 0 and float(without[kind]["off"]) > 0.08, without
        assert abs(float(with_air[kind]["off"])) < 0.05 and with_air[kind]["air_c"] == 29.5, with_air


def test_0632_the_trial_scores_the_air_out_of_sample(db):
    _through_0631(db)
    _plant(db)
    _apply(db)
    through = db.val(f"SELECT min(started_at)::text FROM public.ottoq_sim_runs WHERE sim_run_id IN ({_run(6)}, {_run(7)})")
    t = db.json(f"""SELECT public.ottoq_charge_clock_trial('{DEPOT}', ARRAY[{_run(6)}, {_run(7)}], '{through}',
                                                            '{{"air": false}}', '{{}}')""")
    assert t["air_a"] is None and t["air_b"]["l2"]["usable"], t
    for kind in ("l2", "dcfc"):
        k = t["by_kind"][kind]
        assert float(k["mae_b"]) < float(k["mae_a"]) and abs(float(k["bias_b"])) < abs(float(k["bias_a"])), (kind, k)


# ── the self-review ───────────────────────────────────────────────────────────────────────────────────────────────────

def test_0632_the_review_marks_orders_timed_without_the_air_as_history(db):
    """0621's miniature morning, its order timed by a v2 clock with no level for the air and graded; then 0630, 0631 and
    0632, whose refit reads the air: the order is history (rebuilt 'air'), and the air area says what the clock reads."""
    rg.dc._through_0628(db)
    _plant(db)
    fid, _ = arb._fit(db)
    db.val(f"""INSERT INTO public.ottoq_learned_estimates (depot_id, model, n_evidence, n_runs, usable, params, code_md5, note)
               VALUES ('{DEPOT}', 'return_v1', 100, 5, true, '{{"threshold_soc": 50, "drain_pct_per_min": 0.5,
                       "drain_log_sd": 0.1, "trip_min": 2, "other_share": 0.1}}', 'test', 'test')""")
    for name, soc, state in (("W", 70, "deployed"), ("H", 30, "deployed"), ("Y", 60, "charging_l2")):
        base._car(db, name, soc, 0, state=state)
        db.val(f"DELETE FROM public.ottoq_visit_needs WHERE vehicle_id = '{_vid(name)}'")
    db.val(f"UPDATE public.stalls SET current_vehicle_id = '{_vid('Y')}' WHERE stall_code = 'L3'")
    arb._session(db, "Y", "L3", -30, None, status="active")
    rec = base._order(db, [("C", "dcfc")])
    assert rec["ok"] and rec["order_id"], rec
    models = db.json(f"SELECT state -> 'models' FROM public.ottoq_charge_order_snapshots WHERE order_id = {rec['order_id']}")
    assert models["charge_time_model"] == "charge_time_v2" and int(models["charge_time"]) == fid, models
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_current = '{T}'::timestamptz + interval '100 minutes' "
           f"WHERE sim_run_id = '{RUN}'")
    rg._grade(db)
    rg._stop(db, 100)
    rg._apply(db)
    fc._apply(db)
    err = _apply(db)
    assert "0632 V6:" in err and "its air area built: The charge clock reads the air" in err, err
    v = db.json(f"SELECT public.ottoq_arbiter_self_assessment_v3('{DEPOT}', now() - interval '7 days', false)")
    assert v["clocks"]["rebuilt_since"] == "air", v["clocks"]
    area = next(a for a in v["improvement_areas"] if a["area"] == "charge_clock_misses_air_temperature")
    assert area["status"] == "built" and area["title"] == "The charge clock reads the air", area
    assert "L2 chargers run" in area["finding"] and "above 18 °C" in area["finding"], area["finding"]
    assert "timed by a charge clock that did not read the air" in area["finding"], area["finding"]
    assert area["action"] == "Nothing until orders timed by the clock that reads the air are graded.", area
