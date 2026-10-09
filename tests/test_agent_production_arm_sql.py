"""db/migrations/0629, EXECUTED: a production session is armed, and no write under an agent's name reaches it.

WHY THIS EXISTS. 0629 turns the agent on where real vehicles will be (Chase, 2026-10-08 CT: "Agent should always be on when
runs are activated, and definitely when actual vehicle data is integrated") and holds CLAUDE.md rule 10 at the one door
every setting passes through. Both halves are claims about behaviour, so both are executed here against the live
functions' own source (tests/fixtures/agent_production_arm_stub.sql carries the five bodies 0629 patches, byte for byte,
and the first test proves it by md5):

  - ottoq_production_start arms the session (the arm's ten keys, the charge order, and the three tick-counted dials set
    for a 120-second tick), reports the setting it inherits under an agent's name, and its event says so;
  - on a production run the agent's dial write, an outside agent's person-approved write and the agent's ops action are
    refused with production_never_self_tunes and write nothing; a person's write is taken;
  - an agent's write to a twin run is taken exactly as before;
  - depot and global scope are refused for an agent only while a production session is live;
  - an operator's run and a sweep arm are armed exactly as before 0629, and a certification arm is still refused;
  - the arming report requires the two hold keys at 0 in production and at 1 elsewhere;
  - the migration refuses a body it was not written against.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_agent_charge_order_sql.py.
"""
import json
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "agent_production_arm_stub.sql")
M0629 = os.path.join(ROOT, "db", "migrations", "0629_a_production_session_is_armed_and_no_agent_write_reaches_it.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
GLOBAL = "00000000-0000-0000-0000-000000000000"
OLD_PROD = "e8a0ba01-0000-0000-0000-000000000629"
ARMED_KEYS = ["agent_asset_depth_enabled", "agent_board_grounding_enabled", "agent_review_enabled",
              "agent_solver_chain_enabled", "cuopt_first_refusal_max_defers", "cuopt_propose_enabled",
              "orchestrator_agent_enabled", "prearrival_charge_yields_to_solver", "proposer_frame_facts",
              "proposer_hold_enabled"]
LIVE_MD5 = {
    "public.ottoq_policy_set(text,uuid,text,numeric,text)": "70238f3381c885e47b7a6f8128f65121",
    "public.ottoq_production_start(uuid)": "c0554484f74511c58145c561076434d3",
    "public.ottoq_agentic_arm(uuid,text)": "9509e976b925e380a4ebd68115a75f1e",
    "public.ottoq_agentic_arming(uuid)": "fe54eb23d05d9b626b44e28743712c14",
    "public.ottoq_agent_board(uuid)": "144242b72a24b58bf792af1527a238ce",
    "public.ottoq_is_agent_actor(text,text[])": "c28f0d8abf4b72459dcd4ef8c75aaa33",
    "public.ottoq_dial_clamp(text,numeric,text)": "f44f34e288741294d2cd3764d106454d",
    "public.ottoq_policy_get(uuid,text,numeric)": "72b658f3a9c5a7ec0fae15aecc907f38",
    "public.ottoq_apply_ops_action(uuid,uuid,text,jsonb,text)": "a3caae9750fd3b91e21c692cf94db779",
}


def _conn_args():
    if os.environ.get("PGHOST"):
        return ["-h", os.environ["PGHOST"], "-p", os.environ.get("PGPORT", "5432"),
                "-U", os.environ.get("PGUSER", "postgres")]
    return ["-h", "/var/tmp", "-p", "55432", "-U", "postgres"]


def _server_up():
    if not shutil.which("psql"):
        return False
    p = subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-Atc", "select 1"], capture_output=True, text=True)
    return p.returncode == 0


pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


class Db:
    def __init__(self, name):
        self.name = name

    def run(self, sql):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                           capture_output=True, text=True)
        return p.returncode, [l for l in p.stdout.splitlines() if l.strip()], p.stderr

    def val(self, sql):
        rc, out, err = self.run(sql)
        if rc != 0:
            raise AssertionError(f"SQL failed: {err}\n--- sql ---\n{sql}")
        return out[-1] if out else ""

    def json(self, sql):
        return json.loads(self.val(sql))

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr


@pytest.fixture()
def db():
    name = f"ottoq_prod_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        yield d
    finally:
        subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"],
                       capture_output=True)


def _apply(d):
    rc, err = d.file(M0629)
    assert rc == 0, f"0629 did not apply: {err}"
    return err


def _set(d, scope, scope_id, key, value, by):
    return d.json(f"SELECT public.ottoq_policy_set('{scope}', '{scope_id}', '{key}', {value}, '{by}')")


def _dials(d, rid):
    return d.json(f"""SELECT COALESCE(jsonb_object_agg(param_key, param_value), '{{}}') FROM public.ottoq_policy_params
                       WHERE scope_type = 'run' AND scope_id = '{rid}'""")


def _run(d, run_by, status="running"):
    rid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0629-{run_by}-{status}"))
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, started_at, run_by, policy)
              VALUES ('{rid}', '{DEPOT}', '{status}', 1, now(), '{run_by}', 'otto_q')""")
    return rid


def _start(d):
    out = d.json(f"SELECT public.ottoq_production_start('{DEPOT}')")
    assert out["ok"] is True, out
    return out


# ── the fixture is the live database's source ──

def test_the_fixture_carries_the_live_bodies(db):
    for sig, want in LIVE_MD5.items():
        assert db.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = '{sig}'::regprocedure") == want, sig


# ── a production session is armed ──

def test_production_start_arms_the_session_for_a_120_second_tick(db):
    _apply(db)
    out = _start(db)
    prod = out["sim_run_id"]
    dials = _dials(db, prod)
    assert sorted(dials) == sorted(ARMED_KEYS + ["agent_charge_order", "agent_charge_order_ttl_ticks"])
    assert dials["orchestrator_agent_enabled"] == 1 and dials["cuopt_propose_enabled"] == 1
    assert dials["agent_solver_chain_enabled"] == 1 and dials["agent_review_enabled"] == 1
    assert dials["agent_charge_order"] == 1
    # the three dials that count ticks, set for a 120-second tick
    assert dials["cuopt_first_refusal_max_defers"] == 0
    assert dials["proposer_hold_enabled"] == 0
    assert dials["agent_charge_order_ttl_ticks"] == 3
    # every dial was written by the start, not by an agent
    assert db.val(f"""SELECT count(*) FROM public.ottoq_policy_params WHERE scope_id = '{prod}'
                        AND updated_by <> 'production_start'""") == "0"

    assert out["agents"].startswith("armed (0629)")
    assert out["arming"]["verdict"] == "armed"
    assert out["arming"]["satisfied"] == out["arming"]["required"] == 7
    holds = {k["param_key"]: k for k in out["arming"]["keys"]}
    assert holds["proposer_hold_enabled"]["required"] == 0 and holds["proposer_hold_enabled"]["satisfied"] is True
    assert holds["cuopt_first_refusal_max_defers"]["required"] == 0
    # the inherited setting under an agent's name is reported; a person's global dial is not
    inherited = out["agent_written_settings_in_force"]
    assert [(i["scope_type"], i["param_key"], i["updated_by"]) for i in inherited] == \
        [("depot", "energy_reserve_shave", "ottoq_prime:promoter")]
    ev = db.json("SELECT payload FROM public.event_stub WHERE event_type = 'production.session_started'")
    assert ev["agents"] == "armed (0629)" and len(ev["agent_written_settings_in_force"]) == 1


def test_a_production_session_never_starts_half_armed(db):
    _apply(db)
    # a catalog that would clamp the ttl (floor above 3) makes the arm raise, and the start leaves nothing behind
    db.val("UPDATE public.ottoq_policy_param_catalog SET min_value = 5 WHERE param_key = 'agent_charge_order_ttl_ticks'")
    rc, _, err = db.run(f"SELECT public.ottoq_production_start('{DEPOT}')")
    assert rc != 0 and "agent_charge_order_ttl_ticks was not set as asked" in err
    assert db.val("SELECT count(*) FROM public.ottoq_sim_runs WHERE run_by = 'production_live' AND status = 'running'") == "0"


# ── no write under an agent's name reaches it ──

def test_an_agent_cannot_change_a_production_sessions_settings(db):
    _apply(db)
    prod = _start(db)["sim_run_id"]
    before = _dials(db, prod)

    for by in ("ottoq_prime", "ottoq_prime:agent_gateway:outside", "ottoq_prime:promoter"):
        r = _set(db, "run", prod, "energy_demand_factor_peak", 0.6, by)
        assert r["ok"] is False and r["error"] == "production_never_self_tunes" and r["reason"] == "production_run", r
    ops = db.json(f"""SELECT public.ottoq_apply_ops_action('{prod}', '{DEPOT}', 'extend_forecast_horizon', '{{}}', 'ottoq_prime')""")
    assert ops["status"] == "refused" and ops["reason"] == "production_never_self_tunes", ops
    assert _dials(db, prod) == before      # nothing was written

    # while the session is live, an agent's depot or global write would reach it too
    r = _set(db, "depot", DEPOT, "energy_demand_factor_peak", 0.6, "ottoq_prime")
    assert r["error"] == "production_never_self_tunes" and r["reason"] == "depot_hosts_a_live_production_session"
    r = _set(db, "global", GLOBAL, "energy_demand_factor_peak", 0.6, "ottoq_prime")
    assert r["error"] == "production_never_self_tunes" and r["reason"] == "a_production_session_is_live"

    # a person's write is taken, at every scope
    assert _set(db, "run", prod, "energy_demand_factor_peak", 0.6, "chase")["ok"] is True
    assert _set(db, "depot", DEPOT, "energy_demand_factor_peak", 0.6, "chase")["ok"] is True
    assert _dials(db, prod)["energy_demand_factor_peak"] == 0.6


def test_once_the_session_is_over_only_its_own_settings_stay_closed(db):
    _apply(db)
    prod = _start(db)["sim_run_id"]
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{prod}'")
    assert _set(db, "run", prod, "energy_demand_factor_peak", 0.6, "ottoq_prime")["reason"] == "production_run"
    assert _set(db, "depot", DEPOT, "energy_demand_factor_peak", 0.6, "ottoq_prime")["ok"] is True
    assert _set(db, "global", GLOBAL, "energy_demand_factor_peak", 0.6, "ottoq_prime")["ok"] is True


def test_an_agent_on_a_twin_run_is_unchanged(db):
    _apply(db)
    demo = _run(db, "operator_demo")
    r = _set(db, "run", demo, "energy_demand_factor_peak", 0.6, "ottoq_prime")
    assert r["ok"] is True and r["applied"] == 0.6
    ops = db.json(f"""SELECT public.ottoq_apply_ops_action('{demo}', '{DEPOT}', 'enable_energy_reserve', '{{}}', 'ottoq_prime')""")
    # the depot-scope promotion already holds the reserve on, so the move is not a move
    assert ops["status"] == "no_change"
    # the 0432 guard still answers first for a dial that is not an agent's
    assert _set(db, "run", demo, "forecast_horizon_min", 45, "ottoq_prime")["error"] == "not_agent_writable"


# ── every other run is armed as before ──

def test_twin_runs_are_armed_as_before_and_a_certification_arm_is_still_refused(db):
    _apply(db)
    demo, sweep, cert = _run(db, "operator_demo"), _run(db, "ab_harness"), _run(db, "cert_harness")

    out = db.json(f"SELECT public.ottoq_agentic_arm('{demo}', 'auto:operator_demo')")
    dials = _dials(db, demo)
    assert sorted(dials) == sorted(ARMED_KEYS + ["agent_charge_order"])
    assert dials["cuopt_first_refusal_max_defers"] == 6 and dials["proposer_hold_enabled"] == 1
    assert len(out["receipts"]) == len(ARMED_KEYS) + 1
    assert out["arming"]["verdict"] == "armed"
    hold = {k["param_key"]: k for k in out["arming"]["keys"]}["proposer_hold_enabled"]
    assert hold["required"] == 1 and hold["satisfied"] is True

    db.json(f"SELECT public.ottoq_agentic_arm('{sweep}', 'auto:ab_harness')")
    assert sorted(_dials(db, sweep)) == sorted(ARMED_KEYS)

    rc, _, err = db.run(f"SELECT public.ottoq_agentic_arm('{cert}', 'auto:cert_harness')")
    assert rc != 0 and "certification arm" in err
    assert _dials(db, cert) == {}


def test_the_arming_report_holds_production_to_zero_holds(db):
    _apply(db)
    prod = _start(db)["sim_run_id"]
    # a hold turned on in production is not the armed production configuration
    assert _set(db, "run", prod, "proposer_hold_enabled", 1, "chase")["ok"] is True
    rep = db.json(f"SELECT public.ottoq_agentic_arming('{prod}')")
    assert rep["verdict"] == "partial" and rep["missing"] == ["proposer_hold_enabled"]
    # and a twin run without its holds is not armed either: the twin's requirement is unchanged
    demo = _run(db, "operator_demo")
    db.json(f"SELECT public.ottoq_agentic_arm('{demo}', 'auto:operator_demo')")
    assert _set(db, "run", demo, "proposer_hold_enabled", 0, "chase")["ok"] is True
    rep = db.json(f"SELECT public.ottoq_agentic_arming('{demo}')")
    assert rep["verdict"] == "partial" and rep["missing"] == ["proposer_hold_enabled"]


# ── the board, the words, the migration's own guards ──

def test_the_board_says_production_only_on_a_production_run(db):
    _apply(db)
    src = db.json("SELECT to_json(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_agent_board(uuid)'::regprocedure")
    block = src[src.index("IF EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id AND r.run_by = 'production_live') THEN"):]
    assert "'production', jsonb_build_object(" in block and "'dials', 'read_only'" in block
    assert src.rstrip().endswith("RETURN v_board;\nEND;")
    pre = db.val("""SELECT definition FROM public.ottoq_schema_snapshots
                     WHERE label = '0629_pre' AND object_name = 'ottoq_agent_board'""")
    assert pre.count("'production'") == 0


def test_the_catalog_says_what_production_is_armed_with(db):
    _apply(db)
    words = dict(db.json("""SELECT jsonb_agg(jsonb_build_array(param_key, description)) FROM public.ottoq_policy_param_catalog
                            WHERE description LIKE '%0629%'"""))
    assert sorted(words) == ["agent_charge_order", "agent_charge_order_ttl_ticks", "agent_review_enabled",
                             "cuopt_first_refusal_max_defers", "orchestrator_agent_enabled", "proposer_hold_enabled"]
    assert "production runs keep 0" not in words["agent_review_enabled"]
    assert db.val("""SELECT count(*) FROM public.ottoq_schema_snapshots
                      WHERE label = '0629_pre' AND object_kind = 'catalog_description'""") == "6"


def test_0629_refuses_a_body_it_was_not_written_against(db):
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_production_start(p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid)
              RETURNS jsonb LANGUAGE sql AS $f$ SELECT '{}'::jsonb $f$""")
    rc, err = db.file(M0629)
    assert rc != 0 and "0629 P1" in err
    assert db.val("SELECT count(*) FROM pg_proc WHERE proname = 'ottoq_production_write_refusal'") == "0"


def test_0629_applies_once(db):
    _apply(db)
    rc, err = db.file(M0629)
    assert rc != 0 and "0629 P1" in err
