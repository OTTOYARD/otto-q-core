"""db/migrations/0631, EXECUTED: a fault owns the charge it cut, and an attribution is superseded with its grade.

WHY THIS EXISTS. The hindsight grader (0621) splits what happened after an order into five parts and replays every
subset of them to say which made the kernel's check wrong. A charge under way at the order that a charger fault ended
was split across two: the running clock got its early end, the faults got the charger's down time; replayed with one and
not the other, the world was one that did not happen, and the running block scored the fault as the clock's miss. 0631
gives the fault the whole of it, computes an attribution in one place, keeps a new attribution beside the first when its
grade is superseded, and points every reader at the standing attribution. Every claim in its header that a test can
execute is executed here, on the miniature depot of tests/test_agent_regrade_sql.py (0621's morning on the engine
through 0628, then 0630), with Y's charge on L3, under way at the order, cut by a connector fault at minute 30 and the
charger repaired at 90:
  - it applies after 0630, its checks run, its table and view are evidence, readable, append-only, it refuses before
    0630, and only the attribution names its ledger;
  - the cut charge was graded as the running clock's end; 0631 regrades it censored at the fault and cut there, and
    everything the grade judged stands as it was;
  - its attribution is computed again and kept beside the first: v(none) and v(all) as they were, every subset holding
    both or neither of running and faults as it was, the five values summing to the difference;
  - the replay: the running part alone keeps the charge to the clock's end, the faults part alone cuts it at the fault
    and keeps the charger down to the repair, and both together are the replay before 0631;
  - a grade after 0631 reads the fault's cut directly.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402  (0619-0622 and the morning's helpers)
import test_agent_regrade_sql as rg  # noqa: E402  (0630 and the morning on the engine through 0628)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0631 = os.path.join(ROOT, "db", "migrations", "0631_a_fault_owns_the_charge_it_cut.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_vid, _file = base._vid, arb._file
DEFECT = "fault_cut_read_as_running_end"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _apply(d):
    return _file(d, M0631)


def _cut_morning(d, attribute=True):
    """The morning; Y's charge on L3, under way at the order, cut by a connector fault at minute 30 and the charger
    repaired at 90; graded while the run ran (its clock at 100, the window closed at 90); then the run stopped at 100,
    after the window. Returns the order's id."""
    oid = rg._morning(d)
    sid = d.val(f"SELECT id FROM public.ocpp_sessions WHERE vehicle_id = '{_vid('Y')}' AND ended_at IS NULL")
    d.val(f"""UPDATE public.ocpp_sessions SET status = 'faulted', stopped_reason = 'fault.connector_cable',
                     ended_at = '{T}'::timestamptz + interval '30 minutes' WHERE id = '{sid}'""")
    arb._fault_event(d, sid, 30, 60)
    d.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_current = '{T}'::timestamptz + interval '100 minutes' "
          f"WHERE sim_run_id = '{RUN}'")
    rg._grade(d, attribute=attribute)
    rg._stop(d, 100)
    return oid


def _row(d, table, oid):
    return rg._row(d, table, oid)


def _drop(row, keys):
    return {k: v for k, v in row.items() if k not in keys}


# ── the migration ─────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0631_applies_after_0630_and_its_checks_run(db):
    rg.dc._through_0628(db)
    rg._idle(db)
    rc, err = db.file(M0631)
    assert rc != 0 and "0631 P1: 0630 is not applied" in err, err
    rg._apply(db)
    err = _apply(db)
    assert "0631: 0 standing grades read a charge a fault cut" in err and "0631 V2: 0 attributions" in err, err
    assert "0631: 0 grades superseded, 0 attributions with them" in err and "0631 V3: 0 regrades" in err, err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0631_a_fault_owns_the_charge_it_cut'") == "falsefalse"
    assert db.val("SELECT class FROM public.ottoq_run_scope_registry "
                  "WHERE table_name = 'ottoq_charge_order_reattributions'") == "evidence"
    cols = lambda rel: db.val(f"""SELECT string_agg(attname, ',' ORDER BY attnum) FROM pg_attribute
                                   WHERE attrelid = 'public.{rel}'::regclass AND attnum > 0 AND NOT attisdropped""")
    assert cols("ottoq_charge_order_attributions") == cols("ottoq_charge_order_attribution")
    assert cols("ottoq_charge_order_reattributions") == cols("ottoq_charge_order_attribution") + \
        ",reattributed_at,supersedes_code_md5,defect,detail"
    assert db.val("SELECT has_table_privilege('anon', 'public.ottoq_charge_order_attributions', 'SELECT')::text || "
                  "has_table_privilege('anon', 'public.ottoq_charge_order_reattributions', 'INSERT')::text") == "truefalse"
    assert db.val("SELECT strpos(pg_get_functiondef('public.ottoq_hindsight_code_md5()'::regprocedure), "
                  "'''public.ottoq_charge_order_attribute_compute(bigint)''') > 0") == "t"
    # only the attribution names its ledger, to write it; its readers read the standing attribution
    names = db.val(r"""SELECT COALESCE(string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text), '')
                         FROM pg_proc p
                        WHERE regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g')
                              ~ 'ottoq_charge_order_attribution(?![a-z_0-9])'""")
    assert names == "ottoq_charge_order_attribute(bigint)", names
    for fn in ("ottoq_charge_order_grade_pending(uuid,integer,boolean,integer,numeric)",
               "ottoq_charge_order_track_record(uuid,uuid,integer)",
               "ottoq_arbiter_self_assessment(uuid,timestamp with time zone)",
               "ottoq_charge_order_regrade(bigint,text,text)"):
        assert db.val(f"SELECT strpos(prosrc, 'ottoq_charge_order_attributions') > 0 FROM pg_proc "
                      f"WHERE oid = 'public.{fn}'::regprocedure") == "t", fn


def test_0631_a_cut_charge_is_the_faults_and_its_grade_and_attribution_are_superseded(db):
    oid = _cut_morning(db)
    rg._apply(db)
    l3 = _vid("L3")
    fc = rg._forecast_free(db, oid, l3)
    first = _row(db, "ottoq_charge_order_hindsight", oid)
    first_attr = _row(db, "ottoq_charge_order_attribution", oid)
    # the defect: the cut charge read as the running clock's end, and scored as its miss
    assert first["realized"]["chargers"][l3] == {"free": 30, "cen": False, "dn": [[30, 90]]}, first["realized"]["chargers"]
    run = first["forecast"]["running"]
    assert (float(run["n"]), float(run["sum_err"])) == (1, 30 - fc) and fc > 30, (run, fc)
    assert first_attr is not None and first["decision"] is True
    code_before = first["code_md5"]
    err = _apply(db)
    assert "0631: 1 standing grades read a charge a fault cut as the running clock's end (1 charger records; 1 " \
           "decisions; 1 attributed; 0 by 0621's grader), of 1 graded" in err, err
    assert "0631: 1 grades superseded, 1 attributions with them" in err and "0631 V3: 1 regrades" in err, err
    assert "0631 V4: 1 reattributions" in err, err
    # the first grade and the first attribution stay as they were
    assert _row(db, "ottoq_charge_order_hindsight", oid) == first
    assert _row(db, "ottoq_charge_order_attribution", oid) == first_attr
    # the standing grade: the cut charger censored at the fault and cut there, the running block without it, and
    # everything the grade judged as it was
    g = _row(db, "ottoq_charge_order_grades", oid)
    code_now = db.val("SELECT public.ottoq_hindsight_code_md5()")
    assert g["code_md5"] == code_now != code_before
    assert g["realized"]["chargers"][l3] == {"free": max(30.0, fc), "cen": True, "cut": 30, "dn": [[30, 90]]}, \
        g["realized"]["chargers"]
    assert float(g["forecast"]["running"]["n"]) == 0, g["forecast"]["running"]
    keep = ("expected", "hindsight", "outcome", "moves", "fidelity", "graded_at", "decision", "taken", "p_win")
    assert {k: g[k] for k in keep} == {k: first[k] for k in keep}
    assert {k: v for k, v in g["forecast"].items() if k != "running"} == \
        {k: v for k, v in first["forecast"].items() if k != "running"}
    regrade = db.json(f"SELECT to_jsonb(r) FROM public.ottoq_charge_order_regrades r WHERE order_id = {oid}")
    assert (regrade["defect"], regrade["supersedes_code_md5"], regrade["detail"]["chargers"]) == (DEFECT, code_before, [l3])
    # the standing attribution: computed again, kept beside the first, the same game with its halves made whole
    a = _row(db, "ottoq_charge_order_attributions", oid)
    ra = db.json(f"SELECT to_jsonb(r) FROM public.ottoq_charge_order_reattributions r WHERE order_id = {oid}")
    assert a == _drop(ra, ("reattributed_at", "supersedes_code_md5", "defect", "detail"))
    assert (ra["defect"], ra["supersedes_code_md5"], ra["computed_at"]) == (DEFECT, first_attr["code_md5"],
                                                                          first_attr["computed_at"])
    assert a["code_md5"] == code_now and a["verdict_changed"] == first_attr["verdict_changed"]
    assert ra["detail"]["verdict_changed"] == {"was": first_attr["verdict_changed"], "now": a["verdict_changed"]}
    assert ra["detail"]["shapley_was"] == first_attr["shapley"]
    sv, sv0 = a["subset_values"], first_attr["subset_values"]
    assert sv[0] == sv0[0] and sv[31] == sv0[31]
    assert all(sv[m] == sv0[m] for m in range(32) if ((m >> 3) & 1) == ((m >> 4) & 1))
    for i, key in enumerate(("cmp", "on_time", "late", "flow")):
        total = sum(float(v[key]) for v in a["shapley"].values())
        assert abs(total - (float(sv[31][i]) - float(sv[0][i]))) < 2e-3, (key, total)
    assert db.json(f"SELECT public.ottoq_charge_order_attribute({oid})") == a
    tr = db.json(f"SELECT public.ottoq_charge_order_track_record('{RUN}', '{DEPOT}', 7)")
    assert tr["this_run"]["graded"] == 1, tr


def test_0631_the_replay_gives_the_fault_the_whole_of_it(db):
    oid = _cut_morning(db)
    rg._apply(db)
    _apply(db)
    l3 = _vid("L3")
    fc = rg._forecast_free(db, oid, l3)

    def charger(parts):
        st = db.json(f"""SELECT public.ottoq_charge_line_realize(s.state, g.realized, ARRAY{parts}::text[])
                           FROM public.ottoq_charge_order_snapshots s JOIN public.ottoq_charge_order_grades g USING (order_id)
                          WHERE s.order_id = {oid}""")
        return next(c for c in st["chargers"] if c["id"] == l3)

    assert float(charger(["running"])["free"]) == max(30.0, fc) and "dn" not in charger(["running"])
    assert (float(charger(["faults"])["free"]), charger(["faults"])["dn"]) == (30, [[30, 90]])
    both = charger(["running", "faults"])
    assert (float(both["free"]), both["dn"]) == (30, [[30, 90]])
    # with both, the replay is the one before 0631: the first grade's record replayed by the same parts
    old = db.json(f"""SELECT public.ottoq_charge_line_realize(s.state, h.realized, ARRAY['running','faults']::text[])
                        FROM public.ottoq_charge_order_snapshots s JOIN public.ottoq_charge_order_hindsight h USING (order_id)
                       WHERE s.order_id = {oid}""")
    assert next(c for c in old["chargers"] if c["id"] == l3) == both
    # a record without cut replays as before: the faults part alone leaves the clock's end
    assert float(db.json(f"""SELECT x FROM public.ottoq_charge_order_snapshots s
                                JOIN public.ottoq_charge_order_hindsight h USING (order_id),
                                     jsonb_array_elements(public.ottoq_charge_line_realize(s.state, h.realized,
                                                          ARRAY['faults']::text[]) -> 'chargers') x
                               WHERE s.order_id = {oid} AND x ->> 'id' = '{l3}'""")["free"]) == fc


def test_0631_a_grade_after_it_reads_the_cut_directly(db):
    oid = rg._morning(db)
    sid = db.val(f"SELECT id FROM public.ocpp_sessions WHERE vehicle_id = '{_vid('Y')}' AND ended_at IS NULL")
    db.val(f"""UPDATE public.ocpp_sessions SET status = 'faulted', stopped_reason = 'fault.connector_cable',
                      ended_at = '{T}'::timestamptz + interval '30 minutes' WHERE id = '{sid}'""")
    arb._fault_event(db, sid, 30, 60)
    rg._stop(db, 100)
    rg._apply(db)
    err = _apply(db)
    assert "0631: 0 standing grades read a charge a fault cut" in err, err
    rg._grade(db, attribute=True)
    l3 = _vid("L3")
    h = _row(db, "ottoq_charge_order_hindsight", oid)
    assert h["realized"]["chargers"][l3] == {"free": max(30.0, rg._forecast_free(db, oid, l3)), "cen": True, "cut": 30,
                                             "dn": [[30, 90]]}, h["realized"]["chargers"]
    assert float(h["forecast"]["running"]["n"]) == 0
    assert db.val("SELECT count(*) FROM public.ottoq_charge_order_regrades") == "0"
    # the attribution kept the first time is the computation, field for field
    a = _row(db, "ottoq_charge_order_attribution", oid)
    c = db.json(f"SELECT to_jsonb(public.ottoq_charge_order_attribute_compute({oid}))")
    assert _drop(c, ("computed_at",)) == _drop(a, ("computed_at",))
    assert _row(db, "ottoq_charge_order_attributions", oid) == a


def test_0631_the_reattributions_are_append_only(db):
    oid = _cut_morning(db)
    rg._apply(db)
    _apply(db)
    for sql in (f"UPDATE public.ottoq_charge_order_reattributions SET defect = 'other_code' WHERE order_id = {oid}",
                f"DELETE FROM public.ottoq_charge_order_reattributions WHERE order_id = {oid}"):
        rc, _, err = db.run(sql)
        assert rc != 0 and "append-only" in err, (sql, err)


def test_0631_refuses_a_body_it_was_not_written_against(db):
    rg.dc._through_0628(db)
    rg._idle(db)
    rg._apply(db)
    db.val(r"""DO $x$ BEGIN
                 EXECUTE regexp_replace(pg_get_functiondef('public.ottoq_charge_line_realize(jsonb,jsonb,text[])'::regprocedure),
                                        '\$function\$\n', E'$function$\n-- a later change\n');
               END $x$""")
    rc, err = db.file(M0631)
    assert rc != 0 and "0631 P1: public.ottoq_charge_line_realize(jsonb,jsonb,text[]) is not the body measured" in err, err
