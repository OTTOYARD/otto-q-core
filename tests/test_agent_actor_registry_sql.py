"""db/migrations/0702, EXECUTED: the production guard knows every agent by name.

WHY THIS EXISTS. public.ottoq_is_agent_actor decides, for every guard that asks, whether a writer is an agent or a person,
and before 0702 it knew one name, 'ottoq_prime'. The OttoCommand chat seat (an LLM writing a depot dial as
'ottocommand'), the self-tuner ('cil') and the feed agents passed the rule-10 production guard, the agent_writable guard
and the agent envelope as if they were people. 0702 puts every agent in one registry the predicate reads. Every claim
it makes is about behaviour, so each is executed here on the live functions' own source: 0629's stub plus 0629 itself
reproduce the setter, the clamp, the predicate, the refusal and production_start byte for byte, and
tests/fixtures/agent_actor_registry_stub.sql adds the AI.001 evaluator and the FR1 procedure as live (the first test
proves all of it by md5):

  - in production the chat seat and the self-tuner are refused at run, depot and global scope; a person is not;
  - on a twin run they are held to the agent envelope (0.30, not the engine's 0.25) and refused a dial no agent owns;
  - a write that names nobody is the chat seat's (the setter's default), so it fails closed; FR1 names itself;
  - every answer for ottoq_prime, its prefixes and the engine's own names is what it was before 0702;
  - AI.001 judges a registry name and still judges a name its parameters add;
  - the registry is closed to the client roles, append-only, wildcard-free, and one row makes a new agent;
  - production_start reports a setting the chat seat left at the depot;
  - the file refuses a body it was not written against, refuses a second run, and its rollback restores the old answers.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_agent_production_arm_sql.py.
"""
import json
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB_0629 = os.path.join(ROOT, "tests", "fixtures", "agent_production_arm_stub.sql")
STUB_0702 = os.path.join(ROOT, "tests", "fixtures", "agent_actor_registry_stub.sql")
M0629 = os.path.join(ROOT, "db", "migrations", "0629_a_production_session_is_armed_and_no_agent_write_reaches_it.sql")
M0702 = os.path.join(ROOT, "db", "migrations", "0702_the_production_guard_knows_every_agent_by_name.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
GLOBAL = "00000000-0000-0000-0000-000000000000"
OLD_PROD = "e8a0ba01-0000-0000-0000-000000000629"
OLD_DEMO = "b2efcc07-0000-0000-0000-000000000629"

#: pg_get_functiondef md5 of each body as the live database held it on 2026-10-13 (read-only catalog reads)
LIVE_DEF_MD5 = {
    "public.ottoq_policy_set(text,uuid,text,numeric,text)": "bb217cfef110d775bba0adbc878ecb63",
    "public.ottoq_dial_clamp(text,numeric,text)": "b32246daf49a45430a2b59ea9f2bd3b3",
    "public.ottoq_production_start(uuid)": "c0ae7ec68b695cd76c22268852568bea",
    "public.ottoq_agentic_arm(uuid,text)": "02fad75c643e04667fed74777513ddbb",
    "public.ottoq_apply_ops_action(uuid,uuid,text,jsonb,text)": "3ca7589f04aa9c1b76e38030c6952ca4",
    "public.ottoq_is_agent_actor(text,text[])": "f349c63ad2c48b7756633024d6da263b",
    "public.ottoq_production_write_refusal(text,uuid,text)": "d9e972c68f66b15b7239b256d64d1cee",
    "public.ottoq_rule_eval_agent_dial_envelope(text,uuid,jsonb,jsonb)": "7af6e2b784ec1e358b39f162efe0f31e",
    "public.ottoq_fr1_cert_arm(uuid,bigint,uuid,integer,timestamp with time zone,boolean)": "2c7b9c06574bfff33de5bfe664deba56",
}
#: md5(prosrc) after 0702, the figures db/checks/0439 asserts on live
POST_SRC_MD5 = {
    "public.ottoq_is_agent_actor(text,text[])": "713b1ad12171ec2952a33219a566abac",
    "public.ottoq_production_write_refusal(text,uuid,text)": "2ec5bbb09de9bf1a882056acd45244db",
    "public.ottoq_rule_eval_agent_dial_envelope(text,uuid,jsonb,jsonb)": "0fa35238210c5363ce60f30fb708db00",
    "public.ottoq_fr1_cert_arm(uuid,bigint,uuid,integer,timestamp with time zone,boolean)": "6a4aae6f80becf24297f0427524d4ce5",
}
AGENTS = ["ottoq_prime", "ottoq_prime:promoter", "ottoq_prime:agent_gateway:someone", "ottocommand", "ottocommand:x",
          "cil", "cil:x", "nemotron-3-ultra", "auto_learning_loop"]
NOT_AGENTS = ["production_start", "auto:operator_demo", "auto:ab_harness", "auto:cert_harness", "scenario_loader",
              "proposer_bridge", "dial_window_cron:close", "sweep_window_cron:open", "research_wing_kernel_arm",
              "fr1_cert_arm", "orchestra_ui", "cockpit_operator", "chase", "0152_cert_quiesce", "migration:0401",
              "cil_heuristic", "ottocommander", "OTTOCOMMAND", "mpc", ""]


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
    name = f"ottoq_actors_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        rc, err = d.file(STUB_0629)
        assert rc == 0, f"0629's stub did not load: {err}"
        rc, err = d.file(M0629)
        assert rc == 0, f"0629 did not apply: {err}"
        rc, err = d.file(STUB_0702)
        assert rc == 0, f"0702's stub did not load: {err}"
        yield d
    finally:
        subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"],
                       capture_output=True)


def _apply(d):
    rc, err = d.file(M0702)
    assert rc == 0, f"0702 did not apply: {err}"
    return err


def _set(d, scope, scope_id, key, value, by=None):
    by_arg = "" if by is None else f", '{by}'"
    return d.json(f"SELECT public.ottoq_policy_set('{scope}', '{scope_id}', '{key}', {value}{by_arg})")


def _set_rolled_back(d, scope, scope_id, key, value, by):
    """The setter's verdict, with whatever it wrote rolled back."""
    rc, out, err = d.run(f"BEGIN; SELECT public.ottoq_policy_set('{scope}', '{scope_id}', '{key}', {value}, '{by}'); ROLLBACK;")
    assert rc == 0, err
    return json.loads(out[-1])


def _run(d, run_by, status="running"):
    rid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0702-{run_by}-{status}"))
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, started_at, run_by, policy)
              VALUES ('{rid}', '{DEPOT}', '{status}', 1, now(), '{run_by}', 'otto_q')""")
    return rid


def _row(d, scope, scope_id, key):
    return d.val(f"""SELECT COALESCE((SELECT param_value::text || '|' || updated_by FROM public.ottoq_policy_params
                                       WHERE scope_type = '{scope}' AND scope_id = '{scope_id}' AND param_key = '{key}'),
                                      'none')""")


def _agents(d, names):
    arr = "ARRAY[" + ",".join("'" + n.replace("'", "''") + "'" for n in names) + "]::text[]"
    return d.json(f"SELECT jsonb_object_agg(n, public.ottoq_is_agent_actor(n)) FROM unnest({arr}) n")


def _ai001(d, by, key="energy_demand_factor_peak", requested=0.15, params='{"agent_actors": ["ottoq_prime"]}'):
    return d.json(f"""SELECT to_jsonb(public.ottoq_rule_eval_agent_dial_envelope('policy_param', NULL,
                        jsonb_build_object('param_key', '{key}', 'requested', {requested}, 'by', '{by}'), '{params}'))""")


# ── the fixture is the live database's source ──

def test_the_fixture_carries_the_live_bodies(db):
    for sig, want in LIVE_DEF_MD5.items():
        assert db.val(f"SELECT md5(pg_get_functiondef('{sig}'::regprocedure))") == want, sig


def test_0702_applies_and_its_own_checks_pass(db):
    err = _apply(db)
    for tag in ("0702 P2: before:", "0702 V1 PASSED", "0702 V2 PASSED", "0702 V4 PASSED"):
        assert tag in err, err
    for sig, want in POST_SRC_MD5.items():
        assert db.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = '{sig}'::regprocedure") == want, sig
    assert db.val("""SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage
                      WHERE name = '0702_the_production_guard_knows_every_agent_by_name'""") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0702_pre'") == "4"
    # the probes left nothing behind
    assert db.val("SELECT count(*) FROM public.ottoq_policy_params WHERE updated_by LIKE '0702%'") == "0"
    assert db.val(f"SELECT status FROM public.ottoq_sim_runs WHERE sim_run_id = '{OLD_PROD}'") == "completed"


# ── the defect, then the fix ──

def test_before_0702_the_chat_seat_and_the_self_tuner_write_as_people(db):
    prod = _run(db, "production_live")
    r = _set_rolled_back(db, "depot", DEPOT, "energy_demand_factor_peak", 0.15, "ottocommand")
    assert r["ok"] is True and r["applied"] == 0.25, r          # the engine floor, not the agent's, and it reached production
    assert _set_rolled_back(db, "run", prod, "deploy_peak_fraction", 0.5, "cil")["ok"] is True
    assert db.val(f"SELECT public.ottoq_production_write_refusal('run', '{prod}', 'ottocommand') IS NULL") == "t"


def test_in_production_the_chat_seat_and_the_self_tuner_are_refused_and_a_person_is_not(db):
    _apply(db)
    prod = _run(db, "production_live")
    before = _row(db, "depot", DEPOT, "energy_demand_factor_peak")

    # the chat seat's own tool write: depot scope, while a production session is live there
    r = _set(db, "depot", DEPOT, "energy_demand_factor_peak", 0.15, "ottocommand")
    assert r["ok"] is False and r["error"] == "production_never_self_tunes", r
    assert r["reason"] == "depot_hosts_a_live_production_session"
    assert _set(db, "global", GLOBAL, "energy_demand_factor_peak", 0.5, "ottocommand")["reason"] == "a_production_session_is_live"
    for by in ("ottocommand", "ottocommand:anything", "cil", "nemotron-3-ultra", "auto_learning_loop"):
        r = _set(db, "run", prod, "energy_demand_factor_peak", 0.5, by)
        assert r["error"] == "production_never_self_tunes" and r["reason"] == "production_run", (by, r)
    r = _set(db, "depot", DEPOT, "deploy_peak_fraction", 0.5, "cil")
    assert r["reason"] == "depot_hosts_a_live_production_session", r
    assert _row(db, "depot", DEPOT, "energy_demand_factor_peak") == before          # nothing was written

    # the agent is refused as 0629 built it; a person writes at every scope
    assert _set(db, "run", prod, "energy_demand_factor_peak", 0.5, "ottoq_prime")["reason"] == "production_run"
    assert _set(db, "run", prod, "energy_demand_factor_peak", 0.5, "chase")["ok"] is True
    assert _set(db, "depot", DEPOT, "energy_demand_factor_peak", 0.5, "chase")["ok"] is True
    assert _row(db, "depot", DEPOT, "energy_demand_factor_peak") == "0.5|chase"


def test_on_a_twin_run_the_chat_seat_is_held_to_the_agent_envelope(db):
    _apply(db)
    demo = _run(db, "operator_demo")
    r = _set(db, "run", demo, "energy_demand_factor_peak", 0.15, "ottocommand")
    assert r["ok"] is True and r["applied"] == 0.3 and r["clamped"] is True, r      # the agent floor, not 0.25
    r = _set(db, "run", demo, "energy_demand_factor_peak", 0.95, "ottocommand")
    assert r["applied"] == 0.9, r                                                     # the agent ceiling, not 0.95
    for by in ("ottocommand", "cil"):
        r = _set(db, "run", demo, "deploy_peak_fraction", 0.5, by)
        assert r["ok"] is False and r["error"] == "not_agent_writable", (by, r)
    assert _row(db, "run", demo, "deploy_peak_fraction") == "none"
    # a person and the engine keep the engine's range and every dial
    assert _set(db, "run", demo, "energy_demand_factor_peak", 0.15, "chase")["applied"] == 0.25
    assert _set(db, "run", demo, "deploy_peak_fraction", 0.5, "scenario_loader")["ok"] is True


def test_a_write_that_names_nobody_is_the_chat_seats(db):
    _apply(db)
    prod, demo = _run(db, "production_live"), _run(db, "operator_demo")
    # the setter's default p_by is 'ottocommand': fail-closed in production, held to the agent's dials on the twin
    r = _set(db, "run", prod, "energy_demand_factor_peak", 0.5)
    assert r["error"] == "production_never_self_tunes" and r["by"] == "ottocommand", r
    assert _set(db, "run", demo, "energy_mpc_follow", 1)["error"] == "not_agent_writable"
    # FR1, the one engine caller that named nobody, names itself now
    fr1 = db.json("""SELECT to_json(pg_get_functiondef('public.ottoq_fr1_cert_arm(uuid,bigint,uuid,integer,timestamp with time zone,boolean)'::regprocedure))""")
    assert "PERFORM ottoq_policy_set('run', p_run, 'energy_mpc_follow', 1, 'fr1_cert_arm');" in fr1
    assert _set(db, "run", demo, "energy_mpc_follow", 1, "fr1_cert_arm")["ok"] is True


# ── nothing else moved ──

def test_every_other_answer_is_the_one_before_0702(db):
    prod, demo = _run(db, "production_live"), _run(db, "operator_demo")
    probes = [("run", prod, "energy_reserve_shave", 1), ("run", prod, "energy_demand_factor_peak", 0.5),
              ("run", demo, "energy_demand_factor_peak", 0.15), ("run", demo, "deploy_peak_fraction", 0.5),
              ("run", demo, "forecast_horizon_min", 45), ("depot", DEPOT, "energy_demand_factor_peak", 0.5),
              ("global", GLOBAL, "energy_demand_factor_expensive", 0.5)]
    names = ["ottoq_prime", "ottoq_prime:promoter", "ottoq_prime:agent_gateway:x"] + NOT_AGENTS

    arr = "ARRAY[" + ",".join("'" + n + "'" for n in names) + "]::text[]"
    vals = ",".join(f"('{s}', '{i}'::uuid, '{k}', {v})" for s, i, k, v in probes)

    def snapshot():
        # one statement, rolled back: a verdict of the setter does not depend on the rows written before it
        rc, out_, err = db.run(f"""BEGIN;
            SELECT jsonb_object_agg(n || '|' || p.s || '|' || p.i || '|' || p.k,
                                    public.ottoq_policy_set(p.s, p.i, p.k, p.v, n))
              FROM unnest({arr}) n CROSS JOIN (VALUES {vals}) AS p(s, i, k, v);
            ROLLBACK;""")
        assert rc == 0, err
        out = {"setter": json.loads(out_[-1])}
        out["ai001"] = db.json(f"""SELECT jsonb_object_agg(n, to_jsonb(public.ottoq_rule_eval_agent_dial_envelope(
                                     'policy_param', NULL, jsonb_build_object('param_key', 'energy_demand_factor_peak',
                                     'requested', 0.15, 'by', n), '{{"agent_actors": ["ottoq_prime"]}}')))
                                     FROM unnest({arr}) n""")
        out["predicate"] = _agents(db, names)
        out["listed"] = db.json("""SELECT jsonb_build_array(public.ottoq_is_agent_actor('ottocommand', ARRAY['ottoq_prime']),
                                          public.ottoq_is_agent_actor('ottoq_prime:promoter', ARRAY['ottoq_prime']),
                                          public.ottoq_is_agent_actor('ottoq_prime', '{}'::text[]),
                                          public.ottoq_is_agent_actor(NULL))""")
        return out

    before = snapshot()
    _apply(db)
    after = snapshot()
    assert len(before["setter"]) == len(names) * len(probes)
    moved = [(part, k) for part in ("setter", "ai001", "predicate")
             for k in before[part] if before[part][k] != after[part][k]]
    assert moved == [], moved
    assert after["listed"] == before["listed"]
    assert after["listed"] == [False, True, False, False]
    assert all(after["predicate"][n] for n in ["ottoq_prime", "ottoq_prime:promoter", "ottoq_prime:agent_gateway:x"])
    assert not any(after["predicate"][n] for n in NOT_AGENTS)


def test_0629s_production_arm_and_start_are_unchanged(db):
    _apply(db)
    out = db.json(f"SELECT public.ottoq_production_start('{DEPOT}')")
    assert out["ok"] is True and out["arming"]["verdict"] == "armed"
    prod = out["sim_run_id"]
    assert db.val(f"""SELECT count(*) FROM public.ottoq_policy_params WHERE scope_id = '{prod}'
                        AND updated_by = 'production_start'""") == "12"
    # the inherited setting a person must see: the promotion still in force, nothing else at the twin depot
    inherited = out["agent_written_settings_in_force"]
    assert [(i["scope_type"], i["param_key"], i["updated_by"]) for i in inherited] == \
        [("depot", "energy_reserve_shave", "ottoq_prime:promoter")]


def test_production_start_reports_a_setting_the_chat_seat_left(db):
    _apply(db)
    db.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
               VALUES ('depot', '{DEPOT}', 'energy_demand_factor_expensive', 0.3, 'ottocommand')""")
    out = db.json(f"SELECT public.ottoq_production_start('{DEPOT}')")
    got = sorted((i["param_key"], i["updated_by"]) for i in out["agent_written_settings_in_force"])
    assert got == [("energy_demand_factor_expensive", "ottocommand"), ("energy_reserve_shave", "ottoq_prime:promoter")]


# ── the shield ──

def test_ai001_judges_the_registry_and_still_its_own_parameters(db):
    assert _ai001(db, "ottocommand")["reason"] == "actor ottocommand is not an agent"
    _apply(db)
    r = _ai001(db, "ottocommand")
    assert r["passed"] is False and r["severity_override"] == "critical" and r["suggested_action"] == "clamp_to_agent_envelope"
    r = _ai001(db, "cil", key="deploy_peak_fraction", requested=0.5)
    assert r["passed"] is False and r["suggested_action"] == "set_agent_writable_or_block_the_actor"
    assert _ai001(db, "ottocommand", requested=0.5)["passed"] is True        # inside the envelope
    assert _ai001(db, "chase")["reason"] == "actor chase is not an agent"
    # 0353's data path: a name the rule's parameters add is judged without a registry row
    r = _ai001(db, "extra_agent", params='{"agent_actors": ["ottoq_prime", "extra_agent"]}')
    assert r["passed"] is False and r["payload"]["judged"] is True


# ── the registry ──

def test_the_registry_is_closed_append_only_and_wildcard_free(db):
    _apply(db)
    assert db.val("""SELECT string_agg(actor || '=' || kind, ',' ORDER BY actor COLLATE "C") FROM public.ottoq_agent_actors""") == \
        ("auto_learning_loop=self_tuner,cil=self_tuner,nemotron-3-ultra=feed_agent,ottocommand=chat_tool,"
         "ottoq_prime=llm_agent,ottoq_prime:agent_gateway=llm_agent,ottoq_prime:promoter=self_tuner")
    for role in ("anon", "authenticated"):
        rc, _, err = db.run(f"BEGIN; SET LOCAL ROLE {role}; SELECT count(*) FROM public.ottoq_agent_actors; ROLLBACK;")
        assert rc != 0 and "permission denied" in err, (role, err)
        # and yet the predicate answers for them
        rc, out, err = db.run(f"BEGIN; SET LOCAL ROLE {role}; SELECT public.ottoq_is_agent_actor('ottocommand'); ROLLBACK;")
        assert rc == 0 and out[-1] == "t", (role, err)
    rc, out, err = db.run("BEGIN; SET LOCAL ROLE service_role; SELECT count(*) FROM public.ottoq_agent_actors; ROLLBACK;")
    assert rc == 0 and out[-1] == "7", err
    rc, _, err = db.run("""BEGIN; SET LOCAL ROLE service_role; INSERT INTO public.ottoq_agent_actors (actor, kind, note, added_in)
                           VALUES ('rogue', 'llm_agent', 'a service-key caller adding an agent', 'test'); ROLLBACK;""")
    assert rc != 0 and "permission denied" in err
    for stmt in ("DELETE FROM public.ottoq_agent_actors WHERE actor = 'cil'",
                 "UPDATE public.ottoq_agent_actors SET kind = 'llm_agent' WHERE actor = 'cil'",
                 "TRUNCATE public.ottoq_agent_actors"):
        rc, _, err = db.run(stmt)
        assert rc != 0 and "append-only" in err, (stmt, err)
    for bad in ("%", "Upper", "ends:", "has space", "x\\\\y"):
        rc, _, err = db.run(f"""INSERT INTO public.ottoq_agent_actors (actor, kind, note, added_in)
                                VALUES ('{bad}', 'llm_agent', 'a pattern no guard should ever read', 'test')""")
        assert rc != 0 and "ottoq_agent_actors_actor_shape" in err, (bad, err)
    assert db.val("SELECT count(*) FROM public.ottoq_agent_actors") == "7"
    # the override exists, for a migration that says why
    rc, out, err = db.run("""BEGIN; SET LOCAL ottoq.agent_actors_unlock = 'on';
                             DELETE FROM public.ottoq_agent_actors WHERE actor = 'auto_learning_loop';
                             SELECT count(*) FROM public.ottoq_agent_actors; ROLLBACK;""")
    assert rc == 0 and out[-1] == "6", err


def test_one_row_makes_a_new_agent_everywhere(db):
    _apply(db)
    prod, demo = _run(db, "production_live"), _run(db, "operator_demo")
    assert _set(db, "run", demo, "deploy_peak_fraction", 0.5, "new_tuner")["ok"] is True
    db.val("""INSERT INTO public.ottoq_agent_actors (actor, kind, note, added_in)
              VALUES ('new_tuner', 'self_tuner', 'a tuner registered by a later migration', 'test')""")
    assert _set(db, "run", demo, "deploy_peak_fraction", 0.5, "new_tuner:v2")["error"] == "not_agent_writable"
    assert _set(db, "run", prod, "energy_demand_factor_peak", 0.5, "new_tuner")["error"] == "production_never_self_tunes"
    assert _ai001(db, "new_tuner")["payload"]["judged"] is True


def test_the_floor_holds_if_the_registry_is_emptied(db):
    _apply(db)
    db.val("SET ottoq.agent_actors_unlock = 'on'; DELETE FROM public.ottoq_agent_actors;")
    assert _agents(db, ["ottoq_prime", "ottoq_prime:promoter", "ottocommand"]) == \
        {"ottoq_prime": True, "ottoq_prime:promoter": True, "ottocommand": False}


def test_the_predicate_is_stable_security_definer_and_not_publics(db):
    _apply(db)
    row = db.val("""SELECT provolatile::text || '|' || prosecdef::text || '|' || array_to_string(proconfig, ';') || '|' ||
                           has_function_privilege('anon', oid, 'EXECUTE') || '|' ||
                           has_function_privilege('authenticated', oid, 'EXECUTE') || '|' ||
                           has_function_privilege('service_role', oid, 'EXECUTE') || '|' ||
                           (proacl::text ~ '(^|[{,])=X/')
                      FROM pg_proc WHERE oid = 'public.ottoq_is_agent_actor(text,text[])'::regprocedure""")
    assert row == "s|true|search_path=public, pg_temp|true|true|true|false"


# ── the migration's own guards ──

def test_0702_refuses_a_body_it_was_not_written_against(db):
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_is_agent_actor(p_by text, p_actors text[] DEFAULT NULL::text[])
              RETURNS boolean LANGUAGE sql IMMUTABLE AS $f$ SELECT false $f$""")
    rc, err = db.file(M0702)
    assert rc != 0 and "0702 P1" in err
    assert db.val("SELECT to_regclass('public.ottoq_agent_actors') IS NULL") == "t"


def test_0702_refuses_a_new_caller_that_names_nobody(db):
    db.val("""CREATE FUNCTION public.ottoq_some_new_harness(p_run uuid) RETURNS void LANGUAGE plpgsql AS $f$
              BEGIN PERFORM public.ottoq_policy_set('run', p_run, 'energy_mpc_follow', 1); END $f$""")
    rc, err = db.file(M0702)
    assert rc != 0 and "unnamed call sites are not FR1" in err


def test_0702_applies_once(db):
    _apply(db)
    rc, err = db.file(M0702)
    assert rc != 0 and "0702 P1: already applied" in err


def test_the_rollback_in_the_header_restores_the_old_answers(db):
    _apply(db)
    assert _agents(db, ["ottocommand", "cil"]) == {"ottocommand": True, "cil": True}
    defs = db.json("""SELECT jsonb_agg(definition ORDER BY object_name) FROM public.ottoq_schema_snapshots
                       WHERE label = '0702_pre'""")
    for d in defs:
        rc, _, err = db.run(d)
        assert rc == 0, err
    db.val("GRANT EXECUTE ON FUNCTION public.ottoq_is_agent_actor(text, text[]) TO PUBLIC")
    assert _agents(db, ["ottocommand", "cil", "ottoq_prime:promoter"]) == \
        {"ottocommand": False, "cil": False, "ottoq_prime:promoter": True}
    for sig, want in LIVE_DEF_MD5.items():
        if sig in POST_SRC_MD5:
            assert db.val(f"SELECT md5(pg_get_functiondef('{sig}'::regprocedure))") == want, sig
