"""db/migrations/0706, EXECUTED: the agent's charge order that stands is the one built from the newest board, not the last
to arrive; an outranked order never stands; and which order replaced which can be read.

WHY THIS EXISTS. 0614's ottoq_agent_charge_order_live took the taken order with the highest order_id: the last to ARRIVE.
Two agent passes can overlap, so an order built from an older board that finishes later stood over a fresher one (19 of
839 live orders arrived out of board order; 8 of them were taken, and stood on 74 run-ticks). 0706 ranks the taken orders
by LEAST(board_tick, recorded_tick), then order_id, and lets the first stand only while it is younger than the ttl.
Executed here on the miniature depot of tests/test_agent_charge_order_sql.py through 0618 (the live function is 0614's,
md5 c1c0eb65, as on the engine):
  - it refuses a live run with the dial on, applies, its checks run, it is classified FALSE/FALSE, it refuses twice;
  - an order from an older board that arrives later does not stand over the fresher one, through the door and in the
    line the cockpits and the decide path read;
  - an outranked order does not come back when the fresher one expires;
  - a board tick from the future ranks at the tick the order was recorded; a missing board ranks as its arrival;
  - ties on the board go to the later arrival, and where boards arrive in order nothing changes;
  - the succession view says which order stood, what outranked it, and what replaced it.
And, when db/migrations/0712_*.sql is in the tree (it is on the branch that applied it, not on main), the item's seed
check: the same order on two runs with the same random_seed at the same tick draws the same seed and the same verdict.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import glob
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0706 = os.path.join(ROOT, "db", "migrations",
                     "0706_the_order_built_from_the_newest_board_stands_and_an_outranked_order_never_does.sql")
NAME = "0706_the_order_built_from_the_newest_board_stands_and_an_outranked_order_never_does"
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
_vid, _dial, _line = base._vid, base._dial, base._line

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _stopped(d):
    d.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")


def _running(d):
    d.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")


def _apply(d):
    _stopped(d)
    err = arb._file(d, M0706)
    _running(d)
    return err


def _put(d, board, rec, cars, status="accepted", run=RUN):
    """An order row as the door writes one, straight into the ledger (the ledger takes INSERTs), so a test can set the
    board and recorded ticks the door would take from the pass and the run. Returns its order_id."""
    payload = json.dumps([{"vehicle_id": _vid(n), "rank": r, "kind": k} for r, (n, k) in enumerate(cars, 1)])
    b = "NULL" if board is None else board
    return int(d.val(f"""INSERT INTO public.ottoq_agent_charge_orders
                           (sim_run_id, depot_id, board_tick, recorded_tick, sim_clock, chain_id, model, status, n_offered,
                            n_accepted, cars, dropped)
                         VALUES ('{run}', '{DEPOT}', {b}, {rec}, '{T}', 'test', 'test', '{status}', {len(cars)}, {len(cars)},
                                 $j${payload}$j$::jsonb, '[]')
                         RETURNING order_id"""))


def _live(d, tick, run=RUN):
    """The order_id the live function answers at the tick, or None."""
    v = d.val(f"""SELECT max((e.value ->> 'order_id')::bigint)
                    FROM jsonb_each(public.ottoq_agent_charge_order_live('{run}', {tick})) e""")
    return int(v) if v else None


def _succession(d):
    return {r["order_id"]: (r["stood"], r["outranked_by"], r["superseded_by"]) for r in d.json(
        """SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.order_id), '[]')
             FROM public.ottoq_agent_charge_order_succession s""")}


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0706_applies_its_checks_run_and_it_refuses_a_live_run_and_a_second_apply(db):
    assert db.val("SELECT md5(pg_get_functiondef('public.ottoq_agent_charge_order_live(uuid,bigint)'::regprocedure))") \
        == "c1c0eb65fb40162c78966598526f51e3"            # 0614's function, as on the engine
    rc, err = db.file(M0706)                             # the fixture's run is running with the dial on
    assert rc != 0 and "0706 P1: a run with agent_charge_order on is live" in err, err
    _stopped(db)
    err = arb._file(db, M0706)
    assert "0706 V1 PASSED" in err and "0706 V3 PASSED: 0 taken orders" in err, err
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{NAME}'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0706_pre'") == "1"
    assert db.val("SELECT count(*) FROM public.ottoq_agent_charge_orders") == "0"      # the probes rolled back
    rc, err = db.file(M0706)
    assert rc != 0 and "0706 P1: already applied" in err, err


def test_0706_refuses_a_live_order_function_it_was_not_written_against(db):
    _stopped(db)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_agent_charge_order_live(p_sim_run_id uuid, p_tick bigint)
              RETURNS jsonb LANGUAGE sql STABLE AS $f$ SELECT '{}'::jsonb $f$""")
    rc, err = db.file(M0706)
    assert rc != 0 and "0706 P1: ottoq_agent_charge_order_live is not the definition 0614 left" in err, err


# ── through the door: two passes overlap, and the older board arrives last ───────────────────────────────────────────

def _record(d, board, cars, chain):
    payload = json.dumps({"cars": [{"vehicle_id": _vid(n), "kind": k} for n, k in cars], "why": chain})
    return d.json(f"SELECT public.ottoq_agent_charge_order_record('{RUN}', {board}, '{chain}', 'm', $j${payload}$j$::jsonb)")


def test_0706_through_the_door_the_fresher_board_stands_over_the_later_arrival(db):
    # the kernel's own order, sent twice: 0618's check takes it ("no_worse"). The pass that read the board of tick 99
    # records first; one that read the older board of tick 90 records after it, at the same tick.
    kernel = [("B", "either"), ("A", "either"), ("D", "either"), ("C", "either")]
    fresh, stale = _record(db, 99, kernel, "fresh"), _record(db, 90, kernel, "stale")
    assert fresh["status"] == stale["status"] == "accepted", (fresh, stale)
    assert _live(db, 100) == stale["order_id"]           # 0614: the last to arrive stands
    err = _apply(db)
    assert "0706 V3 PASSED: 2 taken orders on the engine, 1 stood, 1 outranked" in err, err
    assert _live(db, 100) == fresh["order_id"]           # 0706: the newest board stands
    assert _succession(db) == {fresh["order_id"]: (True, None, None), stale["order_id"]: (False, fresh["order_id"], None)}
    # the next pass, from the board of tick 100, replaces it
    nxt = _record(db, 100, kernel, "next")
    assert _live(db, 100) == nxt["order_id"]
    assert _succession(db)[fresh["order_id"]] == (True, None, nxt["order_id"])


# ── the line the cockpits and the decide path read ───────────────────────────────────────────────────────────────────

def test_0706_the_line_follows_the_order_from_the_newest_board(db):
    _put(db, 99, 100, [("C", "either"), ("D", "either"), ("A", "either"), ("B", "either")])
    _put(db, 90, 100, [("B", "either"), ("A", "either"), ("D", "either"), ("C", "either")])
    # immediate dispatch, then P past the 90-minute pin, then the order that stands
    assert _line(db) == ["I", "P", "B", "A", "D", "C"]  # 0614: the later arrival, from the older board
    _apply(db)
    assert _line(db) == ["I", "P", "C", "D", "A", "B"]  # 0706: the newest board


# ── what stands, tick by tick ─────────────────────────────────────────────────────────────────────────────────────────

def test_0706_an_outranked_order_does_not_come_back_when_the_fresher_one_expires(db):
    _apply(db)
    _dial(db, "agent_charge_order_ttl_ticks", 5)
    a = _put(db, 20, 22, [("C", "dcfc")])
    b = _put(db, 10, 23, [("D", "l2")])                  # an older board, arriving later
    assert [_live(db, t) for t in (21, 22, 23, 27, 28)] == [None, a, a, a, None]
    # 0614 would have stood b from tick 23 to 28: at 28 a has expired and b, which it outranked, must not come back
    c = _put(db, 25, 30, [("A", "dcfc")])                 # the next fresher board stands again
    assert [_live(db, t) for t in (29, 30, 35, 36)] == [None, c, c, None]
    assert _succession(db) == {a: (True, None, c), b: (False, a, None), c: (True, None, None)}


def test_0706_a_refused_order_never_stands_however_fresh_its_board(db):
    _apply(db)
    a = _put(db, 20, 22, [("C", "dcfc")])
    _put(db, 30, 23, [("D", "l2")], status="refused")
    _put(db, 31, 23, [("D", "l2")], status="rejected")
    assert _live(db, 23) == a
    assert set(_succession(db)) == {a}


def test_0706_a_board_from_the_future_ranks_at_the_tick_its_order_was_recorded(db):
    _apply(db)
    d = _put(db, 1_000_000, 24, [("C", "dcfc")])
    e = _put(db, 30, 31, [("D", "l2")])
    # D's claimed board is clamped to 24, so E (from the board of 30) replaces it; ranking the raw board_tick would
    # have stood D over every later order of the run
    assert _live(db, 24) == d and _live(db, 31) == e
    assert _succession(db)[d] == (True, None, e)


def test_0706_a_missing_board_ranks_as_its_arrival(db):
    _apply(db)
    a = _put(db, 20, 22, [("C", "dcfc")])
    n = _put(db, None, 23, [("D", "l2")])                 # no board given: as fresh as its arrival (0614's rule)
    assert _live(db, 23) == n
    b = _put(db, 21, 24, [("A", "dcfc")])                 # a board older than n's arrival: outranked by n
    assert _live(db, 24) == n
    assert _succession(db) == {a: (True, None, n), n: (True, None, None), b: (False, n, None)}


def test_0706_ties_go_to_the_later_arrival_and_boards_in_order_change_nothing(db):
    _apply(db)
    a = _put(db, 20, 22, [("C", "dcfc")])
    b = _put(db, 20, 23, [("D", "l2")])                   # the same board, arriving later
    assert _live(db, 23) == b and _succession(db)[a] == (True, None, b)
    c = _put(db, 23, 25, [("A", "dcfc")])
    d2 = _put(db, 24, 26, [("B", "l2")])
    # boards arriving in order: the newest board is the latest arrival, 0614's answer at every tick
    assert [_live(db, t) for t in (22, 23, 24, 25, 26, 40, 41, 42)] == [a, b, b, c, d2, d2, d2, None]


def test_0706_the_runs_are_separate(db):
    _apply(db)
    other = "a0000000-0000-0000-0000-0000000007a6"
    a = _put(db, 50, 60, [("C", "dcfc")], run=other)
    b = _put(db, 20, 22, [("D", "l2")])
    assert _live(db, 60, run=other) == a and _live(db, 22) == b
    assert _succession(db) == {a: (True, None, None), b: (True, None, None)}


def test_0706_the_view_reads_with_the_readers_rights(db):
    _apply(db)
    assert db.val("""SELECT array_to_string(reloptions, ',') FROM pg_class
                      WHERE oid = 'public.ottoq_agent_charge_order_succession'::regclass""") == "security_invoker=true"
    assert db.val("SELECT has_table_privilege('anon', 'public.ottoq_agent_charge_order_succession', 'SELECT')") == "f"
    assert db.val("SELECT has_table_privilege('authenticated', 'public.ottoq_agent_charge_order_succession', 'SELECT')") == "t"


# ── the item's seed check, against 0712 when it is in the tree ───────────────────────────────────────────────────────

M0712 = sorted(glob.glob(os.path.join(ROOT, "db", "migrations", "0712_*.sql")))


@pytest.mark.skipif(not M0712, reason="0712 (the check's seed) is not in this tree; it is on the branch that applied it")
def test_0712_the_same_order_on_two_runs_with_one_random_seed_at_one_tick_draws_one_seed(db):
    """The item's V for the seed half, which 0712 built: two runs, the same random_seed and tick, the same world and the
    same order: the same seed string and the same verdict; a different random_seed draws a different seed."""
    import test_agent_holds_sql as holds  # noqa: E402  (0619-0639, which build the door 0712 patches)
    holds._through_0639(db)
    arb._file(db, M0712[0])
    two = "a0000000-0000-0000-0000-000000000712"
    db.val(f"UPDATE public.ottoq_sim_runs SET random_seed = 424242, status = 'running' WHERE sim_run_id = '{RUN}'")
    db.val(f"""INSERT INTO public.ottoq_sim_runs
               SELECT (jsonb_populate_record(NULL::public.ottoq_sim_runs,
                                             to_jsonb(r) || jsonb_build_object('sim_run_id', '{two}', 'sim_run_seq', 99999))).*
                 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '{RUN}'""")
    db.val(f"""INSERT INTO public.ottoq_policy_params
               SELECT scope_type, '{two}', param_key, param_value, updated_by, updated_at
                 FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = '{RUN}'""")
    db.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, visit_key, status, urgency,
                                                     dispatch_due_at, target_soc, atoms, created_at)
               SELECT vehicle_id, '{two}', depot_id, visit_key, status, urgency, dispatch_due_at, target_soc, atoms, created_at
                 FROM public.ottoq_visit_needs WHERE sim_run_id = '{RUN}'""")
    order = json.dumps({"cars": [{"vehicle_id": _vid(n), "kind": k} for n, k in
                                 [("C", "either"), ("A", "either"), ("B", "either")]], "why": "two runs"})
    rec = {r: db.json(f"SELECT public.ottoq_agent_charge_order_record('{r}', 99, 'chain-{r[-4:]}', 'm', $j${order}$j$::jsonb)")
           for r in (RUN, two)}
    snaps = {r: db.json(f"SELECT jsonb_build_object('seed', seed, 'state', md5(state::text)) "
                        f"FROM public.ottoq_charge_order_snapshots WHERE order_id = {rec[r]['order_id']}") for r in rec}
    assert snaps[RUN]["state"] == snaps[two]["state"], snaps                    # the same world
    assert snaps[RUN]["seed"] == snaps[two]["seed"] == "world:424242:100", snaps
    assert RUN not in snaps[RUN]["seed"] and two not in snaps[two]["seed"]
    assert rec[RUN]["projection"] == rec[two]["projection"] and rec[RUN]["status"] == rec[two]["status"], rec
    db.val(f"UPDATE public.ottoq_sim_runs SET random_seed = 7 WHERE sim_run_id = '{two}'")
    third = db.json(f"SELECT public.ottoq_agent_charge_order_record('{two}', 99, 'c', 'm', $j${order}$j$::jsonb)")
    assert db.val(f"SELECT seed FROM public.ottoq_charge_order_snapshots WHERE order_id = {third['order_id']}") \
        == "world:7:100"
