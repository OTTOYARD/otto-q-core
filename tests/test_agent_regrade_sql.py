"""db/migrations/0630, EXECUTED: the grader reads a run's stop as the stop, and a grade found wrong is superseded.

WHY THIS EXISTS. The kernel grades every agent charge order its check judged (0621) against what happened in the 90
sim-minutes after it, and for each charger the check modelled busy it reads when the charge under way ended. The
operator's stop ends every open charge as `sim_reset` on the run's own clock, and the grader read those as charges that
ended there: 99 of 247 stored grades on live, each graded as if the chargers the stop interrupted had come free at the
cut. 0630 reads them as still under way, computes a grade in one place for the first grade and a regrade, keeps a new
grade beside a wrong first one (the grades are append-only evidence), and points every reader at the standing grade.
Every claim in its header that a test can execute is executed here, on the scratch PostgreSQL and the miniature depot
of tests/test_agent_charge_order_sql.py, through 0619-0628 as tests/test_agent_drain_class_sql.py applies them, with
0621's miniature morning (tests/test_agent_arbiter_sql.py) stopped at minute 50 with Y still charging on L3:
  - it applies, its checks run, its tables and view are evidence, readable, append-only, and it refuses a body it was not
    written against, a run running, and a grade it would supersede whose attribution was computed from it;
  - the stopped run's interrupted charge was graded as ending at the stop; 0630 keeps that grade and regrades it beside
    it, censored, by the grader as it is now, and the standing grade is the regrade;
  - a grade after 0630 reads the stop as the stop, and needs no regrade;
  - the computation is the grade: the stored grade and the computation agree field for field;
  - a grade the stop did not touch reads the same before and after (V2), the run's status aside;
  - the regrade refuses a bad defect code, an order with no grade, an unchanged grader, an attribution, a purged run;
  - only the grader names the ledger, to write it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622 and the morning's helpers)
import test_agent_drain_class_sql as dc  # noqa: E402  (0623-0628, in order)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0630 = os.path.join(ROOT, "db", "migrations", "0630_the_grader_reads_a_runs_stop_as_the_stop.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_vid, _file = base._vid, arb._file
DEFECT = "run_stop_read_as_charge_end"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _apply(d):
    return _file(d, M0630)


def _morning(d):
    """0621's miniature morning on the engine through 0628, without its migrations: the six cars of the line, H driving
    home, W at work, Y charging on L3 since minute -30, L4 faulted at -60 for 90, Z in a bay; the agent's order puts C
    on a fast charger. After it: I charges on F1 0.25-45.25 and P on L1 from 0.25. Returns the order's id."""
    dc._through_0628(d)
    d.val(f"""INSERT INTO public.ottoq_learned_estimates (depot_id, model, n_evidence, n_runs, usable, params, code_md5, note)
              VALUES ('{DEPOT}', 'return_v1', 100, 5, true, '{{"threshold_soc": 50, "drain_pct_per_min": 0.5,
                      "drain_log_sd": 0.1, "trip_min": 2, "other_share": 0.1}}', 'test', 'test')""")
    arb._spread_model(d, 0.2)
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
    old = arb._session(d, "Y", "L4", -80, -60, status="faulted", reason="fault.station_hardware")
    arb._fault_event(d, old, -60, 90)
    arb._session(d, "Y", "L3", -30, None, status="active")
    rec = base._order(d, [("C", "dcfc")])
    assert rec["ok"] and rec["order_id"], rec
    arb._session(d, "I", "F1", 0.25, 45.25, soc_start=40)
    arb._session(d, "P", "L1", 0.25, None, status="active", soc_start=70)
    return rec["order_id"]


def _stop(d, at_min):
    """The operator's stop at minute at_min: every charge still open ends as sim_reset on the run's own clock
    (ottoq_sim_release_depot), and the run is over."""
    d.val(f"""UPDATE public.ocpp_sessions SET status = 'cancelled', stopped_reason = 'sim_reset',
                     ended_at = '{T}'::timestamptz + interval '{at_min} minutes'
               WHERE ended_at IS NULL AND sim_run_id = '{RUN}'""")
    d.val(f"""UPDATE public.ottoq_sim_runs SET status = 'completed', ended_at = now(),
                     sim_clock_current = '{T}'::timestamptz + interval '{at_min} minutes' WHERE sim_run_id = '{RUN}'""")


def _idle(d):
    """The world's run, over (0630 applies only between runs)."""
    d.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed', ended_at = now() WHERE sim_run_id = '{RUN}'")


def _grade(d, attribute=False):
    out = d.json(f"SELECT public.ottoq_charge_order_grade_pending('{RUN}', 5, {str(attribute).lower()}, 60000, 90)")
    assert out["errors"] == 0, out
    return out


def _row(d, table, oid):
    return d.json(f"SELECT to_jsonb(x) FROM public.{table} x WHERE order_id = {oid}")


def _l3(d):
    return _vid("L3")


def _forecast_free(d, oid, charger):
    return float(d.val(f"""SELECT x.value ->> 'free' FROM public.ottoq_charge_order_snapshots s,
                                  jsonb_array_elements(s.state -> 'chargers') x
                            WHERE s.order_id = {oid} AND x.value ->> 'id' = '{charger}'"""))


# ── the migration ─────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0630_applies_and_its_checks_run(db):
    dc._through_0628(db)
    _idle(db)
    err = _apply(db)
    assert "0630: 0 stored grades read a charge the run's stop ended (0 charger records; 0 decisions), of 0 graded" in err, err
    assert "0630 V2: 0 grades this does not touch" in err and "0630: 0 grades superseded" in err, err
    assert "0630 V3: 0 regrades" in err and "0630 V6: nothing graded at the twin depot in 7 days" in err, err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0630_the_grader_reads_a_runs_stop_as_the_stop'") == "falsefalse"
    assert db.val("SELECT class FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_charge_order_regrades'") == \
        "evidence"
    # the view keeps the ledger's columns in its order, and the regrades add four of their own
    cols = lambda rel: db.val(f"""SELECT string_agg(attname, ',' ORDER BY attnum) FROM pg_attribute
                                   WHERE attrelid = 'public.{rel}'::regclass AND attnum > 0 AND NOT attisdropped""")
    assert cols("ottoq_charge_order_grades") == cols("ottoq_charge_order_hindsight")
    assert cols("ottoq_charge_order_regrades") == cols("ottoq_charge_order_hindsight") + \
        ",regraded_at,supersedes_code_md5,defect,detail"
    # readable as the ledger is, and append-only as it is
    assert db.val("SELECT relrowsecurity::text FROM pg_class WHERE oid = 'public.ottoq_charge_order_regrades'::regclass") \
        == "true"
    assert db.val("SELECT has_table_privilege('anon', 'public.ottoq_charge_order_grades', 'SELECT')::text || "
                  "has_table_privilege('anon', 'public.ottoq_charge_order_regrades', 'INSERT')::text") == "truefalse"
    assert db.val("SELECT has_function_privilege('anon', 'public.ottoq_charge_order_regrade(bigint,text,text)', "
                  "'EXECUTE')::text") == "false"
    # the code md5 covers the computation
    assert db.val("SELECT strpos(pg_get_functiondef('public.ottoq_hindsight_code_md5()'::regprocedure), "
                  "'''public.ottoq_charge_order_grade_compute(bigint,numeric)''') > 0") == "t"


def test_0630_a_stopped_runs_interrupted_charge_is_censored_and_its_first_grade_superseded(db):
    oid = _morning(db)
    _stop(db, 50)
    _grade(db)
    l3 = _l3(db)
    first = _row(db, "ottoq_charge_order_hindsight", oid)
    # the defect, as 0621-0629 graded it: Y's charge on L3, still under way when the run stopped at 50, read as ended
    assert first["observed_min"] == 50 and first["realized"]["chargers"][l3] == {"free": 50, "cen": False}, first
    fc = _forecast_free(db, oid, l3)
    run = first["forecast"]["running"]
    assert (float(run["n"]), float(run["sum_err"])) == (1, 50 - fc) and fc > 50, (run, fc)
    code_before = db.val("SELECT public.ottoq_hindsight_code_md5()")
    assert first["code_md5"] == code_before
    err = _apply(db)
    assert "0630: 1 stored grades read a charge the run's stop ended (1 charger records; 1 decisions), of 1 graded" in err
    assert "0630: 1 grades superseded" in err and "0630 V3: 1 regrades" in err, err
    assert "before 1 uncensored" in err and "after 0 uncensored" in err, err
    # the first grade stays as it was
    assert _row(db, "ottoq_charge_order_hindsight", oid) == first
    # the regrade: by the grader now, superseding the first's code, in the first's windows, naming the defect
    rg = _row(db, "ottoq_charge_order_regrades", oid)
    code_now = db.val("SELECT public.ottoq_hindsight_code_md5()")
    assert code_now != code_before and rg["code_md5"] == code_now and rg["supersedes_code_md5"] == code_before
    assert rg["graded_at"] == first["graded_at"] and rg["defect"] == DEFECT, rg
    free = max(50.0, fc)
    assert rg["realized"]["chargers"][l3] == {"free": free, "cen": True}, rg["realized"]["chargers"]
    assert {k: v for k, v in rg["realized"].items() if k != "chargers"} == \
        {k: v for k, v in first["realized"].items() if k != "chargers"}
    assert float(rg["forecast"]["running"]["n"]) == 0, rg["forecast"]["running"]
    d = rg["detail"]
    assert d["chargers"] == [l3] and {"realized", "forecast"} <= set(d["changed"]), d
    assert d["outcome"] == {"was": first["outcome"], "now": rg["outcome"]} and d["note"].startswith("0630"), d
    # the standing grade is the regrade, in the ledger's columns; the grade returns it
    standing = _row(db, "ottoq_charge_order_grades", oid)
    assert standing == {k: v for k, v in rg.items() if k not in ("regraded_at", "supersedes_code_md5", "defect", "detail")}
    assert db.json(f"SELECT public.ottoq_charge_order_grade({oid}, 90)") == standing
    # the readers read it: the track record and the usage count the standing grade, once
    tr = db.json(f"SELECT public.ottoq_charge_order_track_record('{RUN}', '{DEPOT}', 7)")
    assert tr["this_run"]["graded"] == 1 and tr["depot"]["graded"] == 1, tr
    u = db.json(f"SELECT public.ottoq_agent_charge_order_usage('{RUN}', 5)")
    assert u["hindsight"]["graded"] == 1, u["hindsight"]
    assert next(x for x in u["by_order"] if x["order_id"] == oid)["hindsight"] == rg["outcome"]


def test_0630_a_grade_after_it_reads_the_stop_as_the_stop(db):
    oid = _morning(db)
    _stop(db, 50)
    err = _apply(db)
    assert "0630: 0 stored grades read a charge the run's stop ended" in err, err
    _grade(db)
    l3 = _l3(db)
    h = _row(db, "ottoq_charge_order_hindsight", oid)
    assert h["realized"]["chargers"][l3] == {"free": max(50.0, _forecast_free(db, oid, l3)), "cen": True}, h["realized"]
    assert float(h["forecast"]["running"]["n"]) == 0 and h["code_md5"] == db.val("SELECT public.ottoq_hindsight_code_md5()")
    assert db.val("SELECT count(*) FROM public.ottoq_charge_order_regrades") == "0"
    assert _row(db, "ottoq_charge_order_grades", oid) == h
    # the computation is the grade: what is computed now is what was kept, but for its code and when
    c = db.json(f"SELECT to_jsonb(public.ottoq_charge_order_grade_compute({oid}, 90))")
    drop = ("code_md5", "graded_at")
    assert {k: v for k, v in c.items() if k not in drop} == {k: v for k, v in h.items() if k not in drop}
    assert c["code_md5"] == h["code_md5"]
    # a regrade under the same grader would repeat it
    out = db.run(f"SELECT public.ottoq_charge_order_regrade({oid}, '{DEFECT}')")
    assert out[0] != 0 and "the grader has not changed since order" in out[2], out


def test_0630_a_grade_the_stop_did_not_touch_reads_the_same(db):
    """V2: graded while the run ran, its window closed at 90 before the stop at 100; the stop ended charges after the
    cut, which the realizer already read as under way. Computed again after 0630 it is the same grade, but for the run's
    status (the grade records the run as it stood when graded)."""
    oid = _morning(db)
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_current = '{T}'::timestamptz + interval '100 minutes' "
           f"WHERE sim_run_id = '{RUN}'")
    _grade(db)
    first = _row(db, "ottoq_charge_order_hindsight", oid)
    assert first["observed_min"] == 90 and first["realized"]["run_status"] == "running", first["realized"]
    _stop(db, 100)
    err = _apply(db)
    assert "0630: 0 stored grades read a charge the run's stop ended" in err, err
    assert "0630 V2: 1 grades this does not touch computed again field for field" in err, err
    assert _row(db, "ottoq_charge_order_grades", oid) == first


def test_0630_the_regrade_refuses(db):
    oid = _morning(db)
    _stop(db, 50)
    _grade(db)
    _apply(db)
    for call, why in (
            (f"ottoq_charge_order_regrade({oid}, 'Bad Code')", "name the defect as a short code"),
            (f"ottoq_charge_order_regrade(424242, '{DEFECT}')", "has no grade to supersede"),
            (f"ottoq_charge_order_regrade({oid}, '{DEFECT}')", "the grader has not changed since order")):
        rc, _, err = db.run(f"SELECT public.{call}")
        assert rc != 0 and why in err, (call, err)
    # an attribution computed from the standing grade: supersede both or neither
    db.val(f"SELECT public.ottoq_charge_order_attribute({oid})")
    rc, _, err = db.run(f"SELECT public.ottoq_charge_order_regrade({oid}, '{DEFECT}')")
    assert rc != 0 and "has an attribution computed from the grade" in err, err
    # a purged run: what happened can no longer be read
    db.val(f"UPDATE public.ottoq_sim_runs SET purged_at = now() WHERE sim_run_id = '{RUN}'")
    rc, _, err = db.run(f"SELECT public.ottoq_charge_order_regrade({oid}, '{DEFECT}')")
    assert rc != 0 and "was purged" in err, err


def test_0630_the_regrades_are_append_only(db):
    oid = _morning(db)
    _stop(db, 50)
    _grade(db)
    _apply(db)
    for sql in (f"UPDATE public.ottoq_charge_order_regrades SET defect = 'other_code' WHERE order_id = {oid}",
                f"DELETE FROM public.ottoq_charge_order_regrades WHERE order_id = {oid}"):
        rc, _, err = db.run(sql)
        assert rc != 0 and "append-only" in err, (sql, err)
    assert db.val("SELECT count(*) FROM public.ottoq_charge_order_regrades") == "1"


def test_0630_only_the_grader_names_the_ledger(db):
    dc._through_0628(db)
    _idle(db)
    _apply(db)
    names = db.val(r"""SELECT COALESCE(string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text), '')
                         FROM pg_proc p
                        WHERE regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g')
                              ~ 'ottoq_charge_order_hindsight(?![a-z_0-9])'""")
    assert names == "ottoq_charge_order_grade(bigint,numeric)", names
    # and every reader reads the standing grade
    for fn in ("ottoq_agent_charge_order_usage(uuid,integer)", "ottoq_charge_order_attribute(bigint)",
               "ottoq_charge_order_grade_pending(uuid,integer,boolean,integer,numeric)",
               "ottoq_charge_order_track_record(uuid,uuid,integer)",
               "ottoq_arbiter_self_assessment(uuid,timestamp with time zone)",
               "ottoq_charge_clock_calibration(uuid,timestamp with time zone)",
               "ottoq_arbiter_self_assessment_v2(uuid,timestamp with time zone)",
               "ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)"):
        assert db.val(f"SELECT strpos(prosrc, 'ottoq_charge_order_grades') > 0 FROM pg_proc "
                      f"WHERE oid = 'public.{fn}'::regprocedure") == "t", fn


def test_0630_refuses_while_a_run_is_running(db):
    _morning(db)
    rc, err = db.file(M0630)
    assert rc != 0 and "0630 P0: a run is running" in err, err


def test_0630_refuses_a_body_it_was_not_written_against(db):
    dc._through_0628(db)
    _idle(db)
    db.val(r"""DO $x$ BEGIN
                    EXECUTE regexp_replace(pg_get_functiondef('public.ottoq_charge_order_realized(bigint,numeric)'::regprocedure),
                                           '\$function\$\n', E'$function$\n-- a later change\n');
                  END $x$""")
    rc, err = db.file(M0630)
    assert rc != 0 and "0630 P1: public.ottoq_charge_order_realized(bigint,numeric) is not the body measured" in err, err


def test_0630_refuses_a_grade_whose_attribution_stands_on_it(db):
    oid = _morning(db)
    _stop(db, 50)
    _grade(db, attribute=True)
    assert db.val(f"SELECT count(*) FROM public.ottoq_charge_order_attribution WHERE order_id = {oid}") == "1"
    rc, err = db.file(M0630)
    assert rc != 0 and f"0630 P1: orders {oid} read a charge the stop ended and have an attribution" in err, err
