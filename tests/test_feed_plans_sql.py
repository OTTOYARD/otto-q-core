"""db/migrations/0716, EXECUTED: the feed agents propose the twin's world; a person promotes it.

WHY THIS EXISTS. Every operator Start fires seven Nemotron feed agents, and one rewrote the twin's charger fault plan three
times as ACTIVE versions, each fitted to the fault rate the twin had drawn from the plan before (G431; rule 10). Executed
here on a stub carrying ottoq_feed_plans as live has it:
  - an agent's new version, asking to be active, lands as a draft, and the active plan stays active;
  - the edge function's old "retire the active one" update is refused, and so is any edit of an active plan;
  - a person promotes a draft: it becomes active, the old one superseded, the promotion recorded;
  - a superseded version (the sourced v1) can be promoted back in one call;
  - an agent cannot promote, nor can an agent author promote its own version; the record is append-only.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "feed_plans_stub.sql")
M0716 = os.path.join(ROOT, "db", "migrations", "0716_the_feed_agents_propose_the_twins_world_and_a_person_promotes_it.sql")
V1 = "ef4eac4a-d017-42ce-9b98-99112df8dcd7"
V4 = "0dd38d00-710e-4825-aa71-cc61561ab7fd"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture()
def db():
    name = f"ottoq_feed_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        rc, err = d.file(M0716)
        assert rc == 0 and "0716 V1-V3 PASSED" in err, err
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _status(d, plan_id):
    return d.val(f"SELECT status FROM ottoq_feed_plans WHERE plan_id = '{plan_id}'")


def _agent_writes_v5(d):
    """What edge-functions/ottoq-feed-agents (v1) did: insert v5 active, then retire v4."""
    pid = d.val("""INSERT INTO ottoq_feed_plans (var_key, version, status, method, plan, provenance, authored_by, rationale)
                   VALUES ('charger_fault_repair', 5, 'active', 'quantile_grid', '{"base_session_fault_p": 0.06}', '{}',
                           'nemotron-3-ultra', 'fitted again') RETURNING plan_id""")
    rc, _, err = d.run(f"UPDATE ottoq_feed_plans SET status = 'superseded' WHERE plan_id = '{V4}'")
    return pid, rc, err


def test_0716_an_agents_version_is_a_draft_and_the_active_plan_cannot_be_retired_by_it(db):
    pid, rc, err = _agent_writes_v5(db)
    assert _status(db, pid) == "draft"
    assert rc != 0 and "changes only by ottoq_feed_plan_promote" in err, err
    assert _status(db, V4) == "active"
    rc, _, err = db.run(f"""UPDATE ottoq_feed_plans SET plan = '{{"base_session_fault_p": 0.2}}' WHERE plan_id = '{V4}'""")
    assert rc != 0, "an active plan was edited in place"
    rc, _, err = db.run(f"UPDATE ottoq_feed_plans SET status = 'active' WHERE plan_id = '{pid}'")
    assert rc != 0, "a draft was made active without a promotion"


def test_0716_a_person_promotes_a_draft_and_a_revert_is_one_call(db):
    pid, _, _ = _agent_writes_v5(db)
    r = db.json(f"SELECT public.ottoq_feed_plan_promote('{pid}', 'chase', 'reviewed against the corpus; ship it')")
    assert r["ok"] and r["version"] == 5 and r["replaced_version"] == 4, r
    assert _status(db, pid) == "active" and _status(db, V4) == "superseded"
    r = db.json(f"SELECT public.ottoq_feed_plan_promote('{V1}', 'chase', 'back to the sourced 0.05 dossier value')")
    assert r["version"] == 1 and r["replaced_version"] == 5, r
    assert db.val("SELECT count(*) FROM ottoq_feed_plans WHERE var_key = 'charger_fault_repair' AND status = 'active'") == "1"
    assert db.val("SELECT string_agg(version::text || ':' || promoted_by, ',' ORDER BY promotion_id) "
                  "FROM ottoq_feed_plan_promotions") == "5:chase,1:chase"


def test_0716_an_agent_cannot_promote_and_the_record_is_append_only(db):
    pid, _, _ = _agent_writes_v5(db)
    for who in ("nemotron-3-ultra", "ottoq_prime", "ottoq_prime:promoter", "ottocommand", "feed_agent"):
        rc, _, err = db.run(f"SELECT public.ottoq_feed_plan_promote('{pid}', '{who}', 'a reason long enough')")
        assert rc != 0 and "is an agent" in err, (who, err)
    rc, _, err = db.run(f"SELECT public.ottoq_feed_plan_promote('{pid}', 'x', 'short')")
    assert rc != 0
    db.json(f"SELECT public.ottoq_feed_plan_promote('{pid}', 'chase', 'reviewed against the corpus; ship it')")
    rc, _, err = db.run("DELETE FROM ottoq_feed_plan_promotions")
    assert rc != 0 and "append-only" in err, err
