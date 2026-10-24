"""db/migrations/0783, EXECUTED: the agent's board says where the depot's wall is (G503).

WHY THIS EXISTS. On run 78c0624c the agent named the chargers as the depot's constraint 266 times while the two service
bays were the wall, because nothing on its board compared a resource's queued work with its capacity. 0783 adds
public.ottoq_depot_constraint and puts it on the board as 'constraint', behind a dial. Executed here on the miniature
depot carried through 0642 and 0781 (tests/test_charge_order_exit_first_sql.py), with 0780's helper, the live board
(tests/fixtures/constraint_board_live.sql, md5 asserted) and stand-ins for what the board reads that the miniature depot
lacks (tests/fixtures/constraint_board_stub.sql):
  - 0783 applies on the live board, its checks run, it is classified FALSE/FALSE, and it refuses a world without 0781,
    a board it was not written against and a second apply;
  - the read model, by hand: each resource's units, busy and idle, its queue and the minutes it owes, the work under
    way, the hours to clear it, the units idle with a car ready, the cars whose exit each resource decides, the minutes
    of charge owed to cars a bay holds, and the wall with its lesson;
  - the board carries it only with grounding and the dial both on, and is otherwise unchanged;
  - the pre-image restores the board.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)
import test_charge_order_exit_first_sql as xf  # noqa: E402  (the miniature depot through 0642, 0781 and its bays)
import test_bay_open_shop_sql as osh  # noqa: E402  (0780's helper as 0780 writes it)

ROOT = base.ROOT
M0783 = os.path.join(ROOT, "db", "migrations", "0783_the_agents_board_says_where_the_depots_wall_is.sql")
BOARD_LIVE = os.path.join(ROOT, "tests", "fixtures", "constraint_board_live.sql")
BOARD_STUB = os.path.join(ROOT, "tests", "fixtures", "constraint_board_stub.sql")
NAME = "0783_the_agents_board_says_where_the_depots_wall_is"
BOARD = "public.ottoq_agent_board(uuid)"
LIVE_BOARD = "cc155a31209fd8e89260028d24a9715f"
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_dial, _vid = base._dial, base._vid

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_x783_tpl_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    xf._admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, xf.arb.ARB_STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        base._world(d)
        base._through_0618(d)
        xf.fl._through_0642(d)
        for path in (xf.DECIDE, BOARD_STUB, BOARD_LIVE):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        rc, out, err = d.run(osh._helper_sql())
        assert rc == 0, f"0780's helper did not load: {err}"
        xf._apply(d)                                                     # 0781, its run completed
        xf._admin(f"ALTER DATABASE {name} WITH IS_TEMPLATE true")
        yield name
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"ALTER DATABASE {name} WITH IS_TEMPLATE false"], capture_output=True)
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


@pytest.fixture()
def db(template):
    name = f"ottoq_x783_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    xf._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    d = base.Db(name)
    try:
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _apply(d):
    rc, err = d.file(M0783)
    assert rc == 0, f"0783 did not apply: {err}"
    return err


def _constraint(d):
    return d.json(f"SELECT public.ottoq_depot_constraint('{RUN}', '{DEPOT}', '{T}')")


def _board(d):
    return d.json(f"SELECT public.ottoq_agent_board('{RUN}')")


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0783_applies_on_the_live_board_and_refuses_twice(db):
    assert xf._md5(db, BOARD) == LIVE_BOARD
    err = _apply(db)
    assert "0783 V1: the board less its insertion is its pre-image" in err, err
    assert "0783 V2: at the default the board of run a0000000 reads as before" in err, err
    assert "0783 V3: with the dial the board of run a0000000 names the wall: posts" in err, err
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{NAME}'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0783_pre'") == "1"
    assert db.json("""SELECT jsonb_build_array(default_value, min_value, max_value, agent_writable)
                        FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_constraint_board'""") == [0, 0, 1, False]
    assert db.val("SELECT count(*) FROM public.ottoq_policy_params WHERE param_key = 'agent_constraint_board'") == "0"
    rc, err = db.file(M0783)
    assert rc != 0 and "0783 P1: already applied" in err, err


def test_0783_refuses_a_world_without_0781_and_a_board_it_was_not_written_against(db):
    db.val("ALTER FUNCTION public.ottoq_bay_line(uuid, uuid, timestamptz) RENAME TO ottoq_bay_line_away")
    rc, err = db.file(M0783)
    assert rc != 0 and "0783 P1: 0781 is not applied" in err, err
    db.val("ALTER FUNCTION public.ottoq_bay_line_away(uuid, uuid, timestamptz) RENAME TO ottoq_bay_line")
    src = db.json(f"SELECT to_json(pg_get_functiondef('{BOARD}'::regprocedure))")
    rc, out, err = db.run(src.replace("--: 0709: this run's cars", "--: 0709 (edited): this run's cars", 1))
    assert rc == 0, err
    rc, err = db.file(M0783)
    assert rc != 0 and "0783 P1: the agent's board is not the body this file patches" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0783_pre'") == "0"


# ── the read model, by hand ───────────────────────────────────────────────────────────────────────────────────────────

def test_the_read_model_names_the_service_bays_the_wall_by_hand(db):
    _apply(db)
    xf._bays(db)
    c = _constraint(db)
    res = {r["resource"]: r for r in c["resources"]}
    assert [r["resource"] for r in c["resources"]] == ["wash_bay", "service_bay", "posts"]
    svc, wash, posts = res["service_bay"], res["wash_bay"], res["posts"]
    # the service bays: SVC3 in maintenance, Q in SVC1 with 25 minutes left; D, P, A, C and I queued for 200 + 40 + 40 +
    # 60 + 40 minutes; every one of them still owes a charge, so none is ready for the idle bay
    assert {k: svc[k] for k in ("units_up", "busy_now", "idle_now", "idle_with_car_ready", "queued_cars", "queued_min",
                                "in_progress_min")} == {"units_up": 2, "busy_now": 1, "idle_now": 1,
                                                        "idle_with_car_ready": 0, "queued_cars": 5, "queued_min": 380,
                                                        "in_progress_min": 25}
    assert float(svc["hours_to_clear"]) == round((380 + 25) / 2 / 60, 2)
    # the wash bay: C's 10 minutes
    assert {k: wash[k] for k in ("units_up", "busy_now", "idle_now", "queued_cars", "queued_min")} == {
        "units_up": 1, "busy_now": 0, "idle_now": 1, "queued_cars": 1, "queued_min": 10}
    # the posts: five up and free, the kernel's six cars and their minutes
    k = xf._keys(db)
    total = sum(float(r["m"]) for r in k.values())
    assert {kk: posts[kk] for kk in ("units_up", "units_down", "busy_now", "idle_now", "idle_with_car_ready",
                                     "queued_cars", "in_progress_min")} == {
        "units_up": 5, "units_down": 0, "busy_now": 0, "idle_now": 5, "idle_with_car_ready": 5, "queued_cars": 6,
        "in_progress_min": 0}
    assert posts["queued_min"] == round(total)
    assert float(posts["hours_to_clear"]) == round(total / 5 / 60, 2)
    # every car owing service work waits longest on the service bays; B owes no bay work
    assert c["exit_decided_by"] == {"service_bay": 5, "posts": 1}
    assert posts["queued_min_bays_decide"] == round(total - float(k["B"]["m"]))
    assert c["wall"] == "service_bay"
    assert c["lesson"] == (f"The service bays are the wall: {float(svc['hours_to_clear']):.2f} hours of work queued for 2 "
                           f"of them, 5 cars waiting. {posts['queued_min_bays_decide']} of the {posts['queued_min']} "
                           "minutes of charge the line owes are for cars whose exit a bay decides.")


def test_a_car_that_owes_no_charge_is_ready_for_an_idle_bay_and_a_faulted_post_is_down(db):
    _apply(db)
    xf._bays(db)
    db.val(f"UPDATE public.vehicles SET current_soc = 100 WHERE id = '{_vid('A')}'")
    db.val(f"UPDATE public.ottoq_ocpp_chargers SET station_state = 'Faulted' WHERE charger_id = '{_vid('L3')}'")
    c = _constraint(db)
    res = {r["resource"]: r for r in c["resources"]}
    assert res["service_bay"]["idle_with_car_ready"] == 1                # A is full and waits for the idle bay
    assert res["posts"]["units_up"] == 4 and res["posts"]["units_down"] == 1 and res["posts"]["idle_now"] == 4
    assert res["posts"]["queued_cars"] == 5                              # A owes no charge: not in the kernel's line


def test_with_the_line_short_and_no_bays_the_posts_are_the_wall(db):
    _apply(db)
    c = _constraint(db)                                                  # the miniature depot has no bays
    assert c["wall"] == "posts" and c["exit_decided_by"] == {"posts": 6}
    assert c["lesson"].startswith("The charging posts are the wall:") and "bay decides" not in c["lesson"]


# ── the board ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_board_carries_it_only_with_grounding_and_the_dial(db):
    xf._bays(db)
    before = _board(db)
    _apply(db)
    assert _board(db) == before and "constraint" not in before
    _dial(db, "agent_constraint_board", 1)
    assert _board(db) == before                                           # grounding off: unchanged
    _dial(db, "agent_board_grounding_enabled", 1)
    b = _board(db)
    assert b["constraint"] == _constraint(db) and b["grounding"] == {"stand_in": "grounding"}
    assert {k: v for k, v in b.items() if k not in ("constraint", "grounding", "scouts")} == before
    _dial(db, "agent_constraint_board", 0)
    assert "constraint" not in _board(db)


def test_the_pre_image_restores_the_board(db):
    _apply(db)
    rc, out, err = db.run(db.json("SELECT to_json(definition) FROM public.ottoq_schema_snapshots WHERE label = '0783_pre'"))
    assert rc == 0, err
    assert xf._md5(db, BOARD) == LIVE_BOARD
