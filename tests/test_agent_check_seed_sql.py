"""db/migrations/0712, EXECUTED: the check's futures are drawn from the world, not from the run's minted id.

WHY THIS EXISTS. The kernel's check on an agent's charge order (0620) seeded its sampled futures with
`sim_run_id : tick : chain_id`, two random UUIDs, so the same world at the same tick drew different futures on every run and
every pass, and both taken orders the study replayed flipped to refused on a change of run id alone (DC-7). 0712 seeds
with `world : random_seed : tick`. Executed here on the miniature depot of tests/test_agent_charge_order_sql.py, through
0619-0639 as tests/test_agent_holds_sql.py applies them (the chain reproduces the live record function, md5 66576edf):
  - before 0712 the same order at the same tick on the same world gets a different seed from a different chain id
    (the defect, reproduced);
  - after it, the seed is world:random_seed:tick, names neither id, and the same order at the same tick from two passes
    meets the same futures and gets the same verdict;
  - a run with no random_seed (a production session) falls back to its own id.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402
import test_agent_arbiter_sql as arb  # noqa: E402
import test_agent_holds_sql as holds  # noqa: E402
from test_agent_outflow_sql import db  # noqa: E402,F401  (the fixture: a fresh miniature depot through 0618)

ROOT = base.ROOT
M0712 = os.path.join(ROOT, "db", "migrations",
                     "0712_the_checks_futures_are_drawn_from_the_world_not_from_the_runs_minted_id.sql")
RUN = base.RUN
_vid = base._vid

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

ORDER = [("C", "either"), ("A", "either"), ("B", "either")]


def _record(d, chain, run=RUN):
    payload = json.dumps({"cars": [{"vehicle_id": _vid(n), "kind": k, "why": n} for n, k in ORDER], "why": "seed test"})
    return d.json(f"SELECT public.ottoq_agent_charge_order_record('{run}', 99, '{chain}', 'm', $j${payload}$j$::jsonb)")


def _snap(d, order_id):
    return d.json(f"SELECT to_jsonb(s) - 'state' FROM public.ottoq_charge_order_snapshots s WHERE order_id = {order_id}")


def _armed(d):
    base._dial(d, "agent_charge_order", 1)
    d.val(f"UPDATE public.ottoq_sim_runs SET random_seed = 424242, status = 'running' WHERE sim_run_id = '{RUN}'")


def test_0712_the_live_definition_is_the_one_the_chain_builds(db):
    holds._through_0639(db)
    assert db.val("SELECT md5(pg_get_functiondef('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)'"
                  "::regprocedure))") == "66576edf15e404aab2c948e52e36e7cb"


def test_0712_before_it_a_minted_chain_id_changes_the_futures_and_after_it_does_not(db):
    holds._through_0639(db)
    _armed(db)
    a, b = _record(db, "chain-a"), _record(db, "chain-b")
    assert a["ok"] and b["ok"], (a, b)
    sa, sb = _snap(db, a["order_id"]), _snap(db, b["order_id"])
    assert sa["seed"] != sb["seed"] and "chain-a" in sa["seed"] and RUN in sa["seed"]     # the defect

    err = arb._file(db, M0712)
    assert "0712 V1-V2 PASSED" in err, err
    c, e = _record(db, "chain-c"), _record(db, "chain-e")
    sc, se = _snap(db, c["order_id"]), _snap(db, e["order_id"])
    assert sc["seed"] == se["seed"] == "world:424242:100", (sc["seed"], se["seed"])
    assert RUN not in sc["seed"] and "chain" not in sc["seed"]
    assert c["projection"] == e["projection"] and c["status"] == e["status"], (c, e)


def test_0712_a_run_with_no_random_seed_falls_back_to_its_own_id(db):
    """A production session has no replica, and may have no random_seed: it keeps drawing from its own id."""
    holds._through_0639(db)
    _armed(db)
    arb._file(db, M0712)
    db.val(f"UPDATE public.ottoq_sim_runs SET random_seed = NULL WHERE sim_run_id = '{RUN}'")
    seedless = _snap(db, _record(db, "z")["order_id"])
    assert seedless["seed"] == f"world:{RUN}:100", seedless["seed"]
