"""db/migrations/0829, EXECUTED: a car whose cabin clean is done at a charging post is in no bay's line (G544).

WHY THIS EXISTS. 0781 has a car whose turn in the bays is far off yield its place in the charge line, and reads that
turn from public.ottoq_bay_line, which puts the interior deep clean (requires_bay 'detail') in the wash bays' line. 0817
moved that clean to the charging posts. On run 7a08f52a (2026-11-13) 11 of the 15 cars yielding in a charge line of 31
were held only for a clean their charging post does. Executed here on 0781's own harness (the miniature depot through
0642, the live decide tick, 0781 applied, so public.ottoq_bay_line is the live definition, md5 pinned by 0829's P1), with
0817's one test, public.ottoq_wash_bay_exterior_only, loaded as 0817 defines it:
  - 0829 applies, classifies FALSE/FALSE, keeps the function's attributes, and refuses a run running, a body it was
    not written against, a database without 0817 and a second apply;
  - with the wash bay not exterior only (any of the three dials off) the line is row for row what it was;
  - with it exterior only, a car that owes only a deep clean is in no line, a car that owes a deep clean and a wash is in
    the wash line for its wash alone, and the service line is untouched;
  - the car held only for a post's clean no longer yields (exit_key 0, no turn in the bays), and a car that owes
    service-bay work yields as before;
  - the pre-image restores the function.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import tempfile

import pytest

import test_agent_charge_order_sql as base  # noqa: E402
import test_charge_order_exit_first_sql as x  # noqa: E402  (0781's harness, shared on purpose)
from test_charge_order_exit_first_sql import db, template  # noqa: F401,E402

ROOT = base.ROOT
M0829 = os.path.join(ROOT, "db", "migrations", "0829_a_car_whose_cabin_clean_is_done_at_a_post_is_in_no_bays_line.sql")
L0829 = "0829_a_car_whose_cabin_clean_is_done_at_a_post_is_in_no_bays_line"
L0817 = "0817_the_wash_bay_is_exterior_only_and_cabin_work_is_done_at_a_fast_charger_post"
LINE = "public.ottoq_bay_line(uuid,uuid,timestamp with time zone)"
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

# 0817's one test, as 0817 defines it (db/migrations/0817, "the one test"), and its lineage row
EXTERIOR_ONLY = f"""
CREATE FUNCTION public.ottoq_wash_bay_exterior_only(p_sim_run_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT COALESCE(public.ottoq_policy_get(p_sim_run_id, 'wash_bay_exterior_only', 0), 0) >= 1
     AND COALESCE(public.ottoq_policy_get(p_sim_run_id, 'cabin_robot_deep_clean', 0), 0) >= 1
     AND COALESCE(public.ottoq_policy_get(p_sim_run_id, 'stall_cabin_robot', 0), 0) >= 1;
$function$;
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('{L0817}', false, false, 'stand-in for the test', now());
"""


def _clean(est, **kw):
    return dict({"svc": "interior_deep_clean", "est_min": est, "status": "pending", "must_do": True,
                 "concurrency": "bay", "requires_bay": "detail"}, **kw)


def _ready(d, apply=True, exterior=True):
    """0781's miniature depot with its bays, plus: B owes only a deep clean (40 min), I a deep clean and a wash,
    and C its calibration and wash as before."""
    x._apply(d)
    x._bays(d)
    x._work(d, "B", [_clean(40)], arrived_min=35)
    x._work(d, "I", [_clean(30), x._wash(8)], arrived_min=5)
    rc, err = d.run(EXTERIOR_ONLY)[0], d.run("SELECT 1")[2]
    assert rc == 0, err
    if apply:
        rc, err = d.file(M0829)
        assert rc == 0, f"0829 did not apply: {err}"
    if exterior:
        for k in ("wash_bay_exterior_only", "cabin_robot_deep_clean", "stall_cabin_robot"):
            x._dial(d, k, 1)
    return err if apply else None


def _lanes(d):
    return {k: (float(r["open"]), float(r["eta"])) for k, r in x._line_rows(d).items()}


def test_0824_applies_keeps_the_functions_attributes_and_refuses_twice(db):
    x._apply(db)
    before = db.val(f"SELECT coalesce(proacl::text, chr(45)) || prosecdef::text || provolatile::text || proconfig::text FROM pg_proc WHERE oid = '{LINE}'::regprocedure")
    x._bays(db)
    assert db.run(EXTERIOR_ONLY)[0] == 0
    rc, err = db.file(M0829)
    assert rc == 0, err
    assert "0829 V2 PASSED" in err
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM ottoq_cert_lineage WHERE name = '{L0829}'") == "falsefalse"
    assert db.val(f"SELECT coalesce(proacl::text, chr(45)) || prosecdef::text || provolatile::text || proconfig::text FROM pg_proc WHERE oid = '{LINE}'::regprocedure") == before
    assert db.val("SELECT count(*) FROM ottoq_schema_snapshots WHERE label = '0829_pre'") == "1"
    rc, err = db.file(M0829)
    assert rc != 0 and "0829 P2: already applied" in err


def test_0824_applies_with_windows_line_endings_to_the_same_body(db):
    x._apply(db)
    assert db.run(EXTERIOR_ONLY)[0] == 0
    with open(M0829, newline="") as f:
        sql = f.read()
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, newline="") as t:
        t.write(sql.replace("\n", "\r\n"))
    try:
        rc, err = db.file(t.name)          # V3 holds the body to the md5 the tests ran
        assert rc == 0, err
    finally:
        os.unlink(t.name)


def test_0824_refuses_a_run_running_a_changed_body_and_a_database_without_0817(db):
    x._apply(db)
    rc, err = db.file(M0829)                                   # no 0817 here yet
    assert rc != 0 and "0829 P1: 0781 or 0817 is not applied" in err
    assert db.run(EXTERIOR_ONLY)[0] == 0
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0829)
    assert rc != 0 and "0829 P0: a run is running" in err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    db.val(f"COMMENT ON FUNCTION {LINE} IS 'x'")               # a comment does not change the definition
    db.val(f"ALTER FUNCTION {LINE} COST 101")                  # this does
    rc, err = db.file(M0829)
    assert rc != 0 and "0829 P1: public.ottoq_bay_line is not the definition" in err


def test_with_the_wash_bay_not_exterior_only_the_line_is_what_it_was(db):
    _ready(db, apply=False, exterior=False)
    before = _lanes(db)
    assert ("B", "wash_bay") in before and ("I", "wash_bay") in before      # 0781 puts the deep clean in the wash line
    assert before[("I", "wash_bay")][0] == 38.0                             # the clean and the wash together
    rc, err = db.file(M0829)
    assert rc == 0, err
    assert _lanes(db) == before
    # two of the three dials on is still not exterior only (0817's one test): unchanged
    x._dial(db, "wash_bay_exterior_only", 1)
    x._dial(db, "cabin_robot_deep_clean", 1)
    assert _lanes(db) == before


def test_exterior_only_a_cabin_clean_is_in_no_line_and_a_wash_still_is(db):
    _ready(db, apply=False, exterior=False)
    before = _lanes(db)
    rc, err = db.file(M0829)
    assert rc == 0, err
    for k in ("wash_bay_exterior_only", "cabin_robot_deep_clean", "stall_cabin_robot"):
        x._dial(db, k, 1)
    after = _lanes(db)
    assert ("B", "wash_bay") not in after and not any(c == "B" for c, _ in after)   # only a deep clean: no line at all
    assert after[("I", "wash_bay")][0] == 8.0                                       # the wash alone
    assert after[("C", "wash_bay")][0] == before[("C", "wash_bay")][0] == 10.0
    # the wash line is C then I by arrival, with nothing ahead of C: B's 40 minutes are gone from it
    assert after[("C", "wash_bay")][1] == 0.0 and after[("I", "wash_bay")][1] == 10.0
    # the service line is untouched, row for row
    assert {k: v for k, v in after.items() if k[1] == "service_bay"} == {k: v for k, v in before.items() if k[1] == "service_bay"}


def test_a_car_held_only_for_a_posts_clean_no_longer_yields(db):
    _ready(db, apply=False, exterior=True)
    x._exit_on(db)
    x._work(db, "B", [_clean(240)], arrived_min=35)
    before = x._keys(db)
    assert before["B"]["x"] in (0, 1)
    # B's turn in the "wash line" under 0781: behind C's wash and I's clean and wash, on one bay
    line_before = _lanes(db)
    assert ("B", "wash_bay") in line_before
    rc, err = db.file(M0829)
    assert rc == 0, err
    after = x._keys(db)
    assert after["B"]["eta"] is None and after["B"]["x"] == 0           # in no bay's line: nothing to yield for
    # a car that owes service-bay work keeps its turn and its key
    for c in ("A", "P", "D"):
        assert after[c]["eta"] == before[c]["eta"] and after[c]["x"] == before[c]["x"], c
    # I's turn is now its wash's, never later than it was
    assert float(after["I"]["eta"]) <= float(before["I"]["eta"])


def test_the_held_car_yielded_before_and_holds_its_place_after(db):
    """The defect itself, staged: with a long wash line of cabin work, a car owing only a deep clean yields under 0781
    and does not under 0829."""
    _ready(db, apply=False, exterior=True)
    x._exit_on(db)
    x._work(db, "C", [_clean(300)], arrived_min=200)      # a long clean ahead of B in the 'wash line'
    x._work(db, "B", [_clean(40)], arrived_min=35)
    k = x._keys(db)
    assert k["B"]["x"] == 1 and float(k["B"]["eta"]) >= 300              # held for a wash bay it will never enter
    pos_before = x._kernel(db).index("B")
    rc, err = db.file(M0829)
    assert rc == 0, err
    k2 = x._keys(db)
    assert k2["B"]["x"] == 0 and k2["B"]["eta"] is None and k2["C"]["x"] == 0
    assert x._kernel(db).index("B") <= pos_before


def test_the_pre_image_restores_the_function(db):
    _ready(db, apply=False, exterior=True)
    md5_before = x._md5(db, LINE)
    rc, err = db.file(M0829)
    assert rc == 0, err
    assert x._md5(db, LINE) != md5_before
    db.val("""DO $$ DECLARE d text; BEGIN SELECT definition INTO d FROM ottoq_schema_snapshots WHERE label = '0829_pre'; EXECUTE d; END $$""")
    assert x._md5(db, LINE) == md5_before
