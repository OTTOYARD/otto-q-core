"""db/migrations/0638, EXECUTED: the self-review remembers what it found until its evidence lets it go, and its window
never cuts a run in two.

WHY THIS EXISTS. Each morning the check's self-review forgot what it said the morning before: an area left the list the
moment the evidence that named it aged out of the 7-day window, with nothing changed in the code or the world (G369), or
because the review could no longer test it (G375), and the window was cut on the calendar, so an area could turn on part
of one run. Every claim in 0638's header that a test can execute is executed here, on the scratch PostgreSQL and the
miniature depot of tests/test_agent_charge_order_sql.py, through 0619-0637 as tests/test_agent_return_usable_sql.py
applies them:
  - it applies, its checks run, and it refuses an engine before 0637 and a second apply;
  - the carry: an area named again keeps when the chain first named it; one whose evidence aged out is kept as
    left_window with the wider window's numbers; one its evidence no longer names as not_named_since, as last named;
    one built since as built; one last named longer ago than a window lapses; one built before goes; ranked named and
    open, unseen, built; a note is never stacked on a note;
  - the window: moved back to keep a run whole, by its charges or its graded orders; not for a run that began more than
    a day before the cut; not for a run on either side of it;
  - the nightly review: written with nothing graded when it still carries an area, carried again the next morning
    without a second note, and not written when there is nothing to name or carry.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import re
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402
import test_agent_return_usable_sql as ru  # noqa: E402  (0637 and the chain through it)
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0638 = os.path.join(ROOT, "db", "migrations", "0638_the_self_review_remembers_what_it_found.sql")
DEPOT = base.DEPOT
WD = "88888888-8888-8888-8888-888888888888"      # a depot of its own for the window's planted evidence
EMPTY = "99999999-9999-9999-9999-999999999999"   # a depot with no evidence at all
_file = arb._file

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

T = "2026-10-09 12:55:00+00"


def _apply(d):
    return _file(d, M0638)


def _through_0637(d):
    ru._through_0636(d)
    err = ru._apply(d)
    assert "0637 V3" in err, err


def _through_0638(d):
    _through_0637(d)
    return _apply(d)


def _area(code, status="open", finding=None, **kw):
    a = {"area": code, "status": status, "title": f"Area {code}", "finding": finding or f"{code} was found."}
    a.update(kw)
    return a


def _carry(d, live, prev, wide=None, since="7 days", prev_since="8 days", prev_at="1 day", lapse="7 days", at=T):
    w = "NULL" if wide is None else f"$j${json.dumps(wide)}$j$::jsonb"
    p = "NULL" if prev is None else f"$j${json.dumps(prev)}$j$::jsonb"
    return d.json(f"""SELECT public.ottoq_review_carry($j${json.dumps(live)}$j$::jsonb, '{at}'::timestamptz - interval '{since}',
                                                      '{at}'::timestamptz, {p}, '{at}'::timestamptz - interval '{prev_since}',
                                                      '{at}'::timestamptz - interval '{prev_at}', {w}, interval '{lapse}')""")


def _by(v):
    return {a["area"]: a for a in v["areas"]}


def _order(v):
    return [f"{a['area']}:{a['status']}" for a in sorted(v["areas"], key=lambda a: a["rank"])]


def _ts(d, expr):
    return d.val(f"SELECT ({expr})::timestamptz")


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0638_applies_and_its_checks_run(db):
    err = _through_0638(db)
    assert ("0638 V1: the carry by meaning: 3 named now (1 named before), 2 kept unseen (1 whose evidence aged out, 1 its "
            "evidence no longer names), 1 built since, 1 lapsed, 1 built before and gone; ranked named, unseen, built") in err, err
    assert re.search(r"0638 V2: the twin depot's review window starts \d+\.\d min before the 7-day cut "
                     r"\((no run straddles it|a run kept whole)\)", err), err
    assert "0638 V3" not in err, err                                  # the review is run after the apply, not in it
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0638_the_self_review_remembers_what_it_found'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0638_pre'") == "1"
    # the review is the service's alone; the carry and the window are anyone's to read
    assert db.val("SELECT has_function_privilege('anon', 'public.ottoq_arbiter_review(uuid,integer,boolean)', 'EXECUTE')") == "f"
    assert db.val("SELECT has_function_privilege('authenticated', 'public.ottoq_arbiter_review(uuid,integer,boolean)', "
                  "'EXECUTE')") == "f"
    assert db.val("SELECT has_function_privilege('service_role', 'public.ottoq_arbiter_review(uuid,integer,boolean)', "
                  "'EXECUTE')") == "t"
    assert db.val("SELECT has_function_privilege('anon', 'public.ottoq_review_window_start(uuid,timestamptz,integer)', "
                  "'EXECUTE')") == "t"


def test_0638_refuses_an_engine_before_0637_and_a_second_apply(db):
    ru._through_0636(db)
    rc, err = db.file(M0638)
    assert rc != 0 and "0638 P1: 0637 is not applied" in err, err
    ru._apply(db)
    _apply(db)
    rc, err = db.file(M0638)
    assert rc != 0 and "0638 P1: ottoq_arbiter_assess is not the body 0628 left" in err, err


# ── the carry ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_an_area_named_again_keeps_when_it_was_first_named_and_reads_as_now(db):
    _through_0638(db)
    prev = [_area("a", first_seen_at="2026-10-05 12:55:00+00", last_seen_at="2026-10-08 12:55:00+00",
                  seen_since="2026-10-01 12:55:00+00")]
    v = _carry(db, [_area("a", finding="a now.", rank=1)], prev)
    a = _by(v)["a"]
    assert a["seen"] is True and a["status"] == "open" and a["finding"] == "a now."
    assert a["first_seen_at"].startswith("2026-10-05T12:55:00")
    assert a["last_seen_at"].startswith("2026-10-09T12:55:00")
    assert a["seen_since"].startswith("2026-10-02T12:55:00")
    assert "unseen_reason" not in a and "seen_finding" not in a
    # an area the chain never named is first named now
    v = _carry(db, [_area("n", rank=1)], prev)
    assert _by(v)["n"]["first_seen_at"].startswith("2026-10-09T12:55:00")
    assert v["named"] == 1 and v["unseen"] == 1 and v["not_named_since"] == 1


def test_an_area_whose_evidence_aged_out_is_kept_with_the_wider_windows_numbers(db):
    _through_0638(db)
    v = _carry(db, [], [_area("b", rank=1)], wide=[_area("b", finding="b read over the wider window.", weight=40)])
    b = _by(v)["b"]
    assert b["status"] == "unseen" and b["seen"] is False and b["unseen_reason"] == "left_window"
    assert b["seen_finding"] == "b read over the wider window." and b["weight"] == 40
    assert b["finding"].startswith("b read over the wider window. This review's evidence does not name it: what named it "
                                   "is older than its window, and read with that it still is. Last named ")
    assert b["finding"].endswith(" unless named again.") and " CT; kept until " in b["finding"]
    # the defaults for a review written before 0638: last named when it was written, over its window
    assert b["last_seen_at"].startswith("2026-10-08T12:55:00") and b["first_seen_at"].startswith("2026-10-08T12:55:00")
    assert b["seen_since"].startswith("2026-10-01T12:55:00")
    assert v["left_window"] == 1 and v["unseen"] == 1


def test_an_area_its_evidence_no_longer_names_is_kept_as_last_named_and_its_note_never_stacks(db):
    _through_0638(db)
    v1 = _carry(db, [], [_area("c", finding="c was found.", rank=1)], wide=[])
    c1 = _by(v1)["c"]
    assert c1["unseen_reason"] == "not_named_since" and c1["seen_finding"] == "c was found."
    assert c1["finding"].startswith("c was found. This review's evidence does not name it, nor read with what named it: "
                                    "answered, or no longer something the review can test. Last named ")
    # the next morning: carried again from the carried copy, one note, the same last-named moment
    v2 = _carry(db, [], [c1], wide=None, at="2026-10-10 12:55:00+00", prev_at="0 days")
    c2 = _by(v2)["c"]
    assert c2["seen_finding"] == "c was found." and c2["finding"].count("This review's evidence does not name it") == 1
    assert c2["last_seen_at"] == c1["last_seen_at"] and c2["first_seen_at"] == c1["first_seen_at"]
    # and named again later: seen, its first naming kept
    v3 = _carry(db, [_area("c", finding="c again.", rank=1)], [c2], at="2026-10-11 12:55:00+00", prev_at="0 days")
    c3 = _by(v3)["c"]
    assert c3["seen"] is True and c3["status"] == "open" and c3["finding"] == "c again."
    assert c3["first_seen_at"] == c1["first_seen_at"] and "seen_finding" not in c3


def test_built_since_lapsed_and_built_before_and_the_ranking(db):
    _through_0638(db)
    prev = [_area("f", rank=1), _area("d", last_seen_at="2026-10-01 12:00:00+00", rank=2), _area("e", "built", rank=3),
            _area("u", rank=4)]
    live = [_area("g", rank=1), _area("h", "built", rank=2)]
    v = _carry(db, live, prev, wide=[_area("f", "built", finding="f is built.")])
    assert _order(v) == ["g:open", "u:unseen", "h:built", "f:built"]
    assert _by(v)["f"]["unseen_reason"] == "left_window" and _by(v)["f"]["finding"].startswith(
        "f is built. This review's evidence does not name it; read with the evidence that named it, it has been built since.")
    assert [x["area"] for x in v["lapsed"]] == ["d"]
    assert "e" not in _by(v)
    assert (v["named"], v["unseen"], v["left_window"], v["not_named_since"], v["built_since"]) == (2, 1, 1, 1, 1)
    # an area last named exactly one window ago lapses; a minute later than that it is kept
    v = _carry(db, [], [_area("x", last_seen_at="2026-10-02 12:55:00+00"), _area("y", last_seen_at="2026-10-02 12:56:00+00")])
    assert [x["area"] for x in v["lapsed"]] == ["x"] and list(_by(v)) == ["y"]
    # nothing before: what is named, as named
    v = _carry(db, live, None)
    assert _order(v) == ["g:open", "h:built"] and v["lapsed"] == [] and v["unseen"] == 0


# ── the window ────────────────────────────────────────────────────────────────────────────────────────────────────────

def _charges_at(d, run, times):
    for i, t in enumerate(times):
        d.val(f"""INSERT INTO public.ottoq_charge_duration_ledger (session_id, recorded_at, source_kind, sim_run_id, depot_id,
                                                                    charger_type, charger_kw, vehicle_id, vehicle_kw,
                                                                    battery_kwh, soc_start, soc_end, duration_min,
                                                                    stopped_reason, tick_minutes)
                  VALUES (md5('{run}:{i}')::uuid, '{t}', 'live', md5('{run}')::uuid, '{WD}', 'dcfc', 150,
                          md5('car')::uuid, 250, 75, 40, 100, 30, 'completed', 0.5)""")


def _graded_at(d, run, times):
    for i, t in enumerate(times):
        d.val(f"""INSERT INTO public.ottoq_charge_order_hindsight (order_id, sim_run_id, depot_id, sim_clock, window_min,
                    observed_min, status, reason, taken, decision, futures, wins, need, p_win, expected, hindsight,
                    outcome, moves, forecast, fidelity, realized, code_md5, graded_at)
                  VALUES ((SELECT COALESCE(max(order_id), 900000) + 1 FROM public.ottoq_charge_order_hindsight),
                          md5('{run}')::uuid, '{WD}', '{t}', 90, 90, 'refused', 'hand', false, true, 12, 3, 7, 0.25,
                          '{{}}', '{{}}', 'right_refusal', '{{}}', '{{}}', '{{}}', '{{}}', 'hand', '{t}')""")


def _start(d, at=T, days=7):
    return d.val(f"SELECT public.ottoq_review_window_start('{WD}', '{at}', {days})")


def test_the_window_keeps_a_run_whole_by_its_charges_or_its_graded_orders(db):
    _through_0638(db)
    cut = _ts(db, f"'{T}'::timestamptz - interval '7 days'")
    assert _start(db) == cut                                                   # nothing planted: the cut
    _charges_at(db, "after", ["2026-10-02 14:00:00+00", "2026-10-02 15:00:00+00"])
    _charges_at(db, "before", ["2026-10-01 20:00:00+00", "2026-10-02 12:00:00+00"])
    assert _start(db) == cut                                                   # a run on either side of it: the cut
    _charges_at(db, "split", ["2026-10-02 11:30:00+00", "2026-10-02 12:40:00+00", "2026-10-02 13:30:00+00"])
    assert _start(db) == _ts(db, "'2026-10-02 11:30:00+00'")                   # kept whole: its first charge
    _graded_at(db, "graded", ["2026-10-02 10:15:00+00", "2026-10-02 13:15:00+00"])
    assert _start(db) == _ts(db, "'2026-10-02 10:15:00+00'")                   # a graded order earlier still
    # a run whose evidence began more than a day before the cut is cut as before
    _charges_at(db, "long", ["2026-10-01 09:00:00+00", "2026-10-02 18:00:00+00"])
    assert _start(db) == _ts(db, "'2026-10-02 10:15:00+00'")
    # and the window is never later than the cut
    assert _start(db, at="2026-10-09 13:30:00+00") <= _ts(db, "'2026-10-02 13:30:00+00'")


# ── the nightly review ───────────────────────────────────────────────────────────────────────────────────────────────

def _plant_review(d, areas, ago="1 day", since_ago="8 days", depot=DEPOT):
    return int(d.val(f"""INSERT INTO public.ottoq_arbiter_assessments (depot_id, assessed_at, since, n_graded, n_decisions,
                                                                     assessment, improvement_areas, code_md5)
                         VALUES ('{depot}', now() - interval '{ago}', now() - interval '{since_ago}', 0, 0, '{{}}',
                                 $j${json.dumps(areas)}$j$::jsonb, 'hand')
                         RETURNING assessment_id"""))


def _latest(d):
    return d.json(f"""SELECT to_jsonb(a) FROM public.ottoq_arbiter_assessments a WHERE a.depot_id = '{DEPOT}'
                       ORDER BY a.assessment_id DESC LIMIT 1""")


def test_the_nightly_review_carries_what_it_cannot_see_and_writes_nothing_when_nothing_is_left(db):
    _through_0638(db)
    named_now = {a["area"] for a in db.json(f"SELECT public.ottoq_arbiter_review('{DEPOT}', 7, false)")["improvement_areas"]}
    prev = _plant_review(db, [_area("not_on_this_depot", finding="Something this depot never shows.", rank=1),
                              _area("long_gone", last_seen_at="2026-01-01 00:00:00+00", rank=2),
                              _area("history", "built", rank=3)])
    rid = db.val(f"SELECT public.ottoq_arbiter_assess('{DEPOT}', 7)")
    assert rid != "" and int(rid) > prev
    r = _latest(db)
    by = {a["area"]: a for a in r["improvement_areas"]}
    kept = by["not_on_this_depot"]
    assert kept["status"] == "unseen" and kept["unseen_reason"] == "not_named_since"
    assert kept["seen_finding"] == "Something this depot never shows."
    assert "long_gone" not in by and "history" not in by
    assert set(by) - {"not_on_this_depot"} == named_now
    m = r["assessment"]["memory"]
    assert m["previous"] == prev and [x["area"] for x in m["lapsed"]] == ["long_gone"]
    assert m["unseen"] == 1 and r["assessment"]["areas_unseen"] == 1
    w = r["assessment"]["window"]
    assert w["days"] == 7
    assert db.val(f"SELECT since = '{w['since']}'::timestamptz FROM public.ottoq_arbiter_assessments "
                  f"WHERE assessment_id = {rid}") == "t"
    # the next morning reads this one: carried again, one note, last named when the planted review was written
    db.val(f"SELECT public.ottoq_arbiter_assess('{DEPOT}', 7)")
    again = {a["area"]: a for a in _latest(db)["improvement_areas"]}["not_on_this_depot"]
    assert again["finding"].count("This review's evidence does not name it") == 1
    assert again["last_seen_at"] == kept["last_seen_at"]


def test_the_nightly_review_is_not_written_with_nothing_to_name_or_carry(db):
    _through_0638(db)
    assert db.json(f"SELECT public.ottoq_arbiter_review('{EMPTY}', 7, false)")["improvement_areas"] == []
    n = int(db.val("SELECT count(*) FROM public.ottoq_arbiter_assessments"))
    assert db.val(f"SELECT public.ottoq_arbiter_assess('{EMPTY}', 7)") == ""      # NULL: nothing written
    _plant_review(db, [_area("lapsing", last_seen_at="2026-01-01 00:00:00+00", rank=1)], depot=EMPTY)
    assert db.val(f"SELECT public.ottoq_arbiter_assess('{EMPTY}', 7)") == ""
    assert int(db.val("SELECT count(*) FROM public.ottoq_arbiter_assessments")) == n + 1
    # with one still to carry, it is written, though nothing is graded and nothing named
    _plant_review(db, [_area("still_open", rank=1)], depot=EMPTY)
    rid = db.val(f"SELECT public.ottoq_arbiter_assess('{EMPTY}', 7)")
    assert rid != ""
    r = db.json(f"SELECT to_jsonb(a) FROM public.ottoq_arbiter_assessments a WHERE a.assessment_id = {rid}")
    assert r["n_graded"] == 0 and [(a["area"], a["status"]) for a in r["improvement_areas"]] == [("still_open", "unseen")]
