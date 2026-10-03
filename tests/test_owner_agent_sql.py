"""db/migrations/0605 (and 0606), EXECUTED on a stub engine: an owner's agent sets what its own cars need.

WHY THIS EXISTS. 0605 changes three tick-path functions (the effective charge target, the departure test, the world
step), adds a trigger on every new visit and one on every run's end, and gives an outside agent its first way to change
what the engine plans. Compile-checking would see none of the behaviour that matters, so this drives it end to end:

  * the copied engine bodies are byte-identical to the live catalog (md5), and 0605 refuses anything else;
  * the owner door: scope, names ("Tesla 98" is refused with the fleet's names), the contract range, the services an
    owner may and may not request, previews bound to a plan hash, idempotency, undo, refusals recorded as evidence;
  * the engine side: the tick re-targets cars and puts orders on visits (and takes them off), a new visit carries
    standing orders from its first row, the departure test honours holds and orders still waiting for their tick;
  * the run's end lifts everything, puts every car back to its baseline target and refuses new commands;
  * inert without owner settings: the tick step, the visit trigger, the target and the departure test change nothing;
  * grants: nothing new is reachable by a client role except the one boolean the departure test needs.

tests/fixtures/agent_gateway_stub_engine.sql (0559's stub) and tests/fixtures/owner_agent_stub_engine.sql (this file's)
are loaded first. It SKIPS where no scratch PostgreSQL is reachable, like tests/test_agent_gateway_sql.py.
"""
import hashlib
import json
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB_0559 = os.path.join(ROOT, "tests", "fixtures", "agent_gateway_stub_engine.sql")
STUB_0605 = os.path.join(ROOT, "tests", "fixtures", "owner_agent_stub_engine.sql")
M0559 = os.path.join(ROOT, "db", "migrations", "0559_an_outside_agent_asks_through_one_door_and_a_person_decides.sql")
M0560 = os.path.join(ROOT, "db", "migrations", "0560_the_fleet_owner_cockpit_reads_its_own_agent_requests.sql")
M0605 = os.path.join(ROOT, "db", "migrations", "0605_an_owners_agent_sets_what_its_own_cars_need_and_the_runs_end_puts_it_back.sql")
M0606 = os.path.join(ROOT, "db", "migrations", "0606_the_fleet_owner_cockpit_reads_what_its_agent_set.sql")

TWIN = "11111111-1111-1111-1111-111111111111"
OTHER_DEPOT = "aaaaaaaa-0000-0000-0000-000000000002"
WAYMO, TESLA = "22222222-2222-2222-2222-222222222222", "33333333-3333-3333-3333-333333333333"
FIRST_RUN = "5e5e5e5e-0000-0000-0000-000000000001"
AV001, AV041, AV045, RT003, AV041_ELSEWHERE, W1 = (
    "ee000000-0000-0000-0000-0000000000b1", "ee000000-0000-0000-0000-0000000000b2", "ee000000-0000-0000-0000-0000000000b3",
    "ee000000-0000-0000-0000-0000000000b4", "ee000000-0000-0000-0000-0000000000b9", "ee000000-0000-0000-0000-0000000000a1")

#: md5(pg_get_functiondef()) read from the LIVE catalog (gxdrcyphqjzjsuhxuqtg) on 2026-10-03.
LIVE_MD5 = {
    "public.ottoq_sim_advance_tick_world": "5f1cf65bd306f57e338d1f729e63f86a",
    "public.ottoq_effective_target_soc_at": "e937cb1b8ede9f4ba37b17f0291c47ea",
    "public.ottoq_departure_clear": "1ebf41c502acf3d9eaf1f2aedf2ca1cc",
    "public.ottoq_effective_target_soc": "93158a2ab19cc8a15da3e043a3051507",
    "public.ottoq_default_target_soc": "a380d18a6a63d9a956ff3a3841a89b00",
    "public.ottoq_vehicle_fault_open": "b8149139faa6333a3f329d68f2d0c565",
    "public.ottoq_close_run_needs": "05ba4e6a825fe7d27a1009fa95b84475",
    "public.ottoq_tg_close_run_needs_on_terminal": "3fdcdb80d931c3f496e971681426f63e",
    "ottoq.ottoq_svc_to_stall_type": "06545b6b3bfd2082adc678b146285481",
    "ottoq.ottoq_atom_retirable_set": "ca6fefa490efbce29c2696a4e55b0382",
    "ottoq.ottoq_atom_retirable": "e4bc934bab8659f3804f56a8c0bf55c5",
    "ottoq.ottoq_bay_purpose_atoms": "0ddc48dd5c1177b1950a13041e5964c1",
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


def q(text):
    return "'" + text.replace("'", "''") + "'"


class Db:
    def __init__(self, name):
        self.name = name

    def run(self, sql, *, role=None, check=True):
        prefix = f"SET ROLE {role};\n" if role else ""
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1",
                            "-c", prefix + sql], capture_output=True, text=True)
        out = [l for l in p.stdout.splitlines() if l.strip()]
        if check and p.returncode != 0:
            raise AssertionError(f"SQL failed ({p.returncode}): {p.stderr}\n--- sql ---\n{sql}")
        return p.returncode, (out[-1] if out else ""), p.stderr

    def val(self, sql, **kw):
        return self.run(sql, **kw)[1]

    def json(self, sql, **kw):
        return json.loads(self.val(sql, **kw))

    def text(self, sql):
        """The whole of a one-value result, line breaks and all (val() keeps only its last line)."""
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                           capture_output=True, text=True)
        assert p.returncode == 0, p.stderr
        return p.stdout[:-1] if p.stdout.endswith("\n") else p.stdout

    def rows(self, sql):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-F", "|", "-v", "ON_ERROR_STOP=1",
                            "-c", sql], capture_output=True, text=True)
        assert p.returncode == 0, p.stderr
        return [l.split("|") for l in p.stdout.splitlines() if l.strip()]

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr

    def call(self, token_hash, tool, args=None, transport="rest"):
        a = json.dumps(args or {})
        return self.json(f"SELECT ottoq_agent_call('{token_hash}', '{tool}', {q(a)}::jsonb, '{transport}', '{{}}'::jsonb)")

    def issue(self, name, kind, caps, fleet=None):
        f = "NULL" if fleet is None else f"'{fleet}'"
        arr = "ARRAY[" + ",".join(f"'{c}'" for c in caps) + "]::text[]"
        res = self.json(f"SELECT ottoq_agent_issue_token('{name}', '{kind}', {arr}, {f}, '{TWIN}', NULL, 600, 20)")
        assert res["ok"], res
        return hashlib.sha256(res["token"].encode()).hexdigest()

    def tick(self, run, clock):
        return int(self.val(f"SELECT ottoq.ottoq_owner_orders_tick('{run}', '{clock}')"))

    def clear(self, vehicle, run, clock, readiness=True):
        return self.val(f"SELECT ottoq_departure_clear('{vehicle}', '{run}', '{clock}', {str(readiness).lower()})") == "t"


def _new_db():
    name = f"ottoq_own_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c", f"CREATE DATABASE {name}"], check=True,
                   capture_output=True)
    return Db(name)


def _drop(db):
    subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c", f"DROP DATABASE IF EXISTS {db.name} WITH (FORCE)"],
                   capture_output=True)


SEED = f"""
INSERT INTO vehicles (id, fleet_operator_id, home_depot_id, current_depot_id, make, model, display_name, current_soc,
                      current_state, target_soc, av_api_vehicle_id) VALUES
 ('{AV041}', '{TESLA}', '{TWIN}', '{TWIN}', 'Tesla', 'Model Y', 'Tesla-AV-041', 72, 'charging_dcfc', 100, 'twin-sim-041'),
 ('{AV045}', '{TESLA}', '{TWIN}', '{TWIN}', 'Tesla', 'Model Y', 'Tesla-AV-045', 99, 'staged_for_departure', 100, 'twin-sim-045'),
 ('{RT003}', '{TESLA}', '{TWIN}', '{TWIN}', 'Tesla', 'Cybercab', 'Tesla-RT-003', 93, 'charging_l2', 100, NULL),
 ('{AV041_ELSEWHERE}', '{TESLA}', '{OTHER_DEPOT}', '{OTHER_DEPOT}', 'Tesla', 'Model Y', 'Tesla-AV-041', 50, 'deployed', 100, 'twin-sim-041');
UPDATE vehicles SET target_soc = 100 WHERE id = '{AV001}';
"""


def fresh_run(db, clock="2026-09-27 12:00:00+00"):
    """End whatever demo run is live (lifting its owner settings) and start a new one with the cars' visits."""
    db.run("UPDATE ottoq_sim_runs SET status = 'completed' WHERE status IN ('running', 'paused')")
    run = str(uuid.uuid4())
    db.run(f"""INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_current, sim_clock_end, run_by)
               VALUES ('{run}', '{TWIN}', 'running', clock_timestamp(), '{clock}', '{clock}'::timestamptz + interval '20 hours',
                       'operator_demo')""")
    db.run(f"""UPDATE vehicles SET current_state = CASE id WHEN '{AV041}' THEN 'charging_dcfc' WHEN '{AV045}' THEN 'staged_for_departure'
                                                         WHEN '{RT003}' THEN 'charging_l2' WHEN '{AV001}' THEN 'deployed' ELSE current_state END::vehicle_state,
                                 current_soc = CASE id WHEN '{AV041}' THEN 72 WHEN '{AV045}' THEN 99 WHEN '{RT003}' THEN 93 WHEN '{AV001}' THEN 35 ELSE current_soc END,
                                 target_soc = 100
                WHERE fleet_operator_id = '{TESLA}'""")
    db.run(f"""INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, target_soc) VALUES
      ('{AV041}', '{run}', '{TWIN}', '2026-09-27 11:30+00', 'av041:{run[:8]}', '[{{"svc":"charge","status":"in_progress","target_soc":100,"concurrency":"anchor"}},{{"svc":"readiness_check","concurrency":"gate"}}]', 100),
      ('{AV045}', '{run}', '{TWIN}', '2026-09-27 10:30+00', 'av045:{run[:8]}', '[{{"svc":"charge","status":"done","target_soc":100}},{{"svc":"exterior_wash","status":"pending","concurrency":"bay","requires_bay":"wash_bay"}},{{"svc":"readiness_check","status":"done"}}]', 100),
      ('{RT003}', '{run}', '{TWIN}', '2026-09-27 11:00+00', 'rt003:{run[:8]}', '[{{"svc":"charge","status":"in_progress","target_soc":100}},{{"svc":"readiness_check"}}]', 100)""")
    return run


@pytest.fixture(scope="module")
def db():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606):
            if path == M0606 and not os.path.exists(M0606):
                continue
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        d.run(SEED)
        yield d
    finally:
        _drop(d)


@pytest.fixture(scope="module")
def owner(db):
    return db.issue("chase-hermes", "personal", ["read", "note", "owner_settings"], TESLA)


# ───────────────────────────────────────────────────────────────────────────────────────── the premises ──

def test_the_copied_engine_bodies_are_byte_identical_to_the_live_catalog():
    d = _new_db()
    try:
        assert d.file(STUB_0559)[0] == 0 and d.file(STUB_0605)[0] == 0
        for fn, want in LIVE_MD5.items():
            schema, name = fn.split(".")
            got = d.val(f"SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace "
                        f"WHERE n.nspname = '{schema}' AND p.proname = '{name}'")
            assert got == want, f"{fn}: stub md5 {got} is not the live {want}"
    finally:
        _drop(d)


def test_0605_refuses_without_0559_and_refuses_a_second_apply(db):
    d = _new_db()
    try:
        assert d.file(STUB_0559)[0] == 0 and d.file(STUB_0605)[0] == 0
        rc, err = d.file(M0605)
        assert rc != 0 and "0559" in err and "not applied" in err, err
    finally:
        _drop(d)
    rc, err = db.file(M0605)
    assert rc != 0 and "0605 P1: already applied" in err, err


def test_0605_refuses_an_engine_body_it_did_not_measure():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559):
            assert d.file(path)[0] == 0
        d.run("""CREATE OR REPLACE FUNCTION public.ottoq_departure_clear(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamptz,
                 p_need_readiness boolean DEFAULT true) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT true $$""")
        rc, err = d.file(M0605)
        assert rc != 0 and "0605 P1: not the body this file was written against" in err and "ottoq_departure_clear" in err, err
    finally:
        _drop(d)


def test_the_world_step_gains_exactly_one_line(db):
    src = db.text("SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_sim_advance_tick_world(uuid)'::regprocedure")
    assert src.count("ottoq.ottoq_owner_orders_tick(p_sim_run_id, v_new_sim_clock)") == 1
    old = db.text("SELECT definition FROM ottoq_schema_snapshots WHERE label = '0605_pre' AND object_name = 'ottoq_sim_advance_tick_world'")
    assert old and "ottoq_owner_orders_tick" not in old
    # the owner step comes before the visit atoms and before the charges advance
    new = db.text("SELECT pg_get_functiondef('public.ottoq_sim_advance_tick_world(uuid)'::regprocedure)")
    assert new.index("ottoq_owner_orders_tick") < new.index("ottoq_sim_advance_visit_atoms") < new.index("ottoq_sim_advance_charge_sessions")


def test_classified_for_one_recert_round(db):
    assert db.rows("SELECT forces_recert, forces_dial_restart FROM ottoq_cert_lineage WHERE name LIKE '0605%'") == [["t", "t"]]


def test_the_verification_probe_left_nothing_behind():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605):
            assert d.file(path)[0] == 0
        assert d.val("SELECT count(*) FROM ottoq_owner_commands") == "0"
        assert d.val("SELECT count(*) FROM ottoq_owner_settings") == "0"
        assert d.val("SELECT count(*) FROM ottoq_agent_principals") == "0"
    finally:
        _drop(d)


# ──────────────────────────────────────────────────────────────────────────────────────────────── grants ──

def test_nothing_new_is_reachable_by_a_client_role_but_the_departure_helper_and_the_board(db):
    fns = [r[0] for r in db.rows("""SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                                     WHERE n.nspname IN ('public','ottoq') AND (p.proname LIKE 'ottoq\\_owner\\_%'
                                       OR p.proname IN ('ottoq_tg_owner_orders_on_new_visit','ottoq_tg_lift_owner_settings_on_terminal'))""")]
    assert len(fns) >= 25
    for fn in fns:
        got = tuple(db.val(f"SELECT has_function_privilege('{r}', '{fn}', 'EXECUTE')") for r in ("anon", "authenticated", "service_role"))
        want = (("f", "t", "t") if "ottoq_owner_departure_blocked" in fn
                else ("t", "t", "t") if "ottoq_owner_board" in fn     # 0606: OrchestrAV's read, granted on purpose
                else ("f", "f", "f"))
        assert got == want, f"{fn}: {got}"
    for tbl in ("ottoq_owner_commands", "ottoq_owner_settings"):
        for role in ("anon", "authenticated", "service_role"):
            rc, _, err = db.run(f"SELECT count(*) FROM {tbl}", role=role, check=False)
            assert rc != 0 and "permission denied" in err, (tbl, role, err)
    # the replaced functions keep their grants; the gateway door stays service_role only
    assert db.val("SELECT has_function_privilege('anon', 'ottoq_agent_call(text,text,jsonb,text,jsonb)', 'EXECUTE')") == "f"
    assert db.val("SELECT has_function_privilege('anon', 'ottoq_departure_clear(uuid,uuid,timestamptz,boolean)', 'EXECUTE')") == "t"
    # and the departure test answers for exactly the roles it answered for before: anon was already stopped at the
    # effective target it calls first (live grants, measured), never at the owner helper
    for role in ("authenticated", "service_role"):
        rc, _, err = db.run(f"SELECT ottoq_departure_clear('{AV045}', '{FIRST_RUN}', now(), true)", role=role, check=False)
        assert rc == 0, (role, err)
    rc, _, err = db.run(f"SELECT ottoq_departure_clear('{AV045}', '{FIRST_RUN}', now(), true)", role="anon", check=False)
    assert rc != 0 and "ottoq_effective_target_soc_at" in err and "owner" not in err, err


def test_owner_settings_needs_a_fleet_at_issue_and_in_the_table(db):
    res = db.json(f"SELECT ottoq_agent_issue_token('no-fleet', 'personal', ARRAY['read','owner_settings'], NULL, '{TWIN}', NULL, 60, 5)")
    assert res["error"] == "owner_settings_needs_a_fleet"
    rc, _, err = db.run(f"""INSERT INTO ottoq_agent_principals (name, kind, capabilities, token_hash, token_prefix)
                            VALUES ('sneaky', 'personal', ARRAY['owner_settings'], repeat('a', 64), 'oqa_aaaaaaaa')""", check=False)
    assert rc != 0 and "ottoq_agent_principals_owner_scope_check" in err, err


# ─────────────────────────────────────────────────────────────────────────────────────────── the reads ──

def test_whoami_carries_the_owner_block(db, owner):
    fresh_run(db)
    who = db.call(owner, "whoami")["data"]
    o = who["owner"]
    assert o["charge_limit_pct"] == {"min": 80, "max": 100}
    assert o["cars"] == 4 and o["hold_max_hours"] == 24
    assert {s["service"] for s in o["requestable_services"]} == {
        "exterior_wash", "interior_deep_clean", "interior_tidy", "interior_inspection", "sensor_clean", "sensor_calibration",
        "software_update", "remote_diagnostics", "mechanical_pm", "cosmetic_repair", "item_retrieval"}
    assert "never how they move" in o["rules"]
    assert o["orchestrav"].startswith("https://ottoyard-orchestra-av.lovable.app/?source=agent&run=")
    assert "yours to set" in who["how_changes_happen"]


def test_my_fleet_reads_only_the_owners_cars_at_the_depot_in_plain_words(db, owner):
    fresh_run(db)
    out = db.call(owner, "my_fleet")
    assert out["ok"] and out["http_status"] == 200
    data = out["data"]
    names = sorted(c["name"] for c in data["cars"])
    assert names == ["Tesla-AV-001", "Tesla-AV-041", "Tesla-AV-045", "Tesla-RT-003"]
    assert AV041_ELSEWHERE not in {c["vehicle_id"] for c in data["cars"]}       # the same name, another depot
    assert data["summary"].startswith("You have 4 cars at OTTOYARD Nashville Flagship. On the demo run")
    assert "2 charging" in data["summary"] and "every car charges to 100%" in data["summary"]
    assert data["your_range"] == {"charge_limit_min_pct": 80, "charge_limit_max_pct": 100}


def test_a_token_without_a_fleet_has_no_my_fleet(db):
    depot = db.issue("depot-reader", "depot_ops", ["read"])
    out = db.call(depot, "my_fleet")
    assert out["http_status"] == 403 and out["error"]["code"] == "fleet_scope_required"


# ─────────────────────────────────────────────────────────────────────────────────── names and scope ──

@pytest.mark.parametrize("ref,want", [
    ("Tesla-AV-045", AV045), ("tesla av 045", AV045), ("AV-45", AV045), ("45", AV045), ("twin-sim-045", AV045),
    ("RT 3", RT003), ("Cybercab 3", RT003), ("Tesla RT-003", RT003), (AV041, AV041), ("Tesla 41", AV041),
])
def test_a_car_is_found_by_the_names_people_use(db, owner, ref, want):
    fresh_run(db)
    out = db.call(owner, "set_charge_limit", {"vehicles": [ref], "percent": 90, "mode": "preview"})
    assert out["http_status"] == 200, out
    assert [v["id"] for v in out["data"]["command"]["vehicles"]] == [want]


def test_tesla_98_is_refused_with_the_fleets_names_and_recorded(db, owner):
    fresh_run(db)
    out = db.call(owner, "request_service", {"vehicles": ["Tesla 98"], "service": "service bay"})
    assert not out["ok"] and out["http_status"] == 422 and out["error"]["code"] == "vehicle_not_found"
    assert "Tesla 98" in out["error"]["message"] and "Tesla-RT-003" in out["error"]["message"]
    assert out["data"]["command"]["outcome"] == "refused"
    rec = db.rows(f"SELECT outcome, refusal->>'code' FROM ottoq_owner_commands WHERE command_id = '{out['data']['command']['command_id']}'")
    assert rec == [["refused", "vehicle_not_found"]]
    ledger = db.rows(f"SELECT ok, http_status, error_code FROM ottoq_agent_call_ledger WHERE call_id = {out['call_id']}")
    assert ledger == [["f", "422", "vehicle_not_found"]]


def test_another_owners_car_reads_as_missing(db, owner):
    fresh_run(db)
    for ref in (W1, "Waymo-AV-001"):
        out = db.call(owner, "hold_vehicle", {"vehicles": [ref], "for_minutes": 30})
        assert out["error"]["code"] == "vehicle_not_found", ref


def test_an_ambiguous_name_is_refused_not_guessed(db, owner):
    fresh_run(db)
    db.run(f"""INSERT INTO vehicles (id, fleet_operator_id, home_depot_id, current_depot_id, make, model, display_name, current_soc,
                                     current_state, target_soc)
               VALUES ('ee000000-0000-0000-0000-0000000000c9', '{TESLA}', '{TWIN}', '{TWIN}', 'Tesla', 'Model Y', 'Tesla-AV-003',
                       60, 'deployed', 100)""")
    try:
        out = db.call(owner, "hold_vehicle", {"vehicles": ["3"], "for_minutes": 30})
        assert out["error"]["code"] == "vehicle_ambiguous"
        assert "Tesla-AV-003" in out["error"]["message"] and "Tesla-RT-003" in out["error"]["message"]
    finally:
        db.run("DELETE FROM vehicles WHERE id = 'ee000000-0000-0000-0000-0000000000c9'")


# ──────────────────────────────────────────────────────────────────────────────────────── charge limit ──

def test_the_charge_limit_lives_inside_the_owners_contract(db, owner):
    fresh_run(db)
    low = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 70})
    assert low["error"]["code"] == "below_contract_minimum" and "80% to 100%" in low["error"]["message"]
    high = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 101})
    assert high["error"]["code"] == "above_ceiling"
    bad = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 90.5})
    assert bad["http_status"] == 400 and bad["error"]["code"] == "invalid_arguments"
    assert db.val("SELECT count(*) FROM ottoq_owner_settings WHERE status = 'active'") == "0"


def test_preview_then_confirm_with_the_plan_hash(db, owner):
    run = fresh_run(db)
    prev = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 90, "mode": "preview"})
    assert prev["http_status"] == 200 and prev["data"]["outcome"] == "previewed"
    assert prev["data"]["summary"].startswith("Preview only, nothing has changed. If you confirm: All 4 Teslas charge to at most 90% instead of 100%.")
    assert db.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}'") == "0"
    confirm = prev["data"]["confirm"]
    assert confirm["args"]["mode"] == "apply" and confirm["args"]["expect_plan_hash"] == prev["data"]["command"]["plan_hash"]
    # a car's state of charge moving does not change the plan; a setting moving does
    db.run(f"UPDATE vehicles SET current_soc = 80 WHERE id = '{AV041}'")
    done = db.call(owner, "set_charge_limit", {**confirm["args"]})
    assert done["http_status"] == 201 and done["data"]["outcome"] == "applied", done
    assert done["data"]["summary"].startswith("Done. All 4 Teslas charge to at most 90% instead of 100%.")
    assert done["data"]["link"].endswith(f"&command={done['data']['command']['command_id']}")
    assert done["data"]["undo"] == {"tool": "undo_command", "args": {"command_id": done["data"]["command"]["command_id"]}}
    stale = db.call(owner, "set_charge_limit", {**confirm["args"]})
    assert stale["error"]["code"] == "plan_changed"


def test_the_limit_is_read_at_the_one_target_and_applied_by_the_tick(db, owner):
    run = fresh_run(db)
    db.run("TRUNCATE stub_events")
    out = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 90})
    assert out["data"]["outcome"] == "applied"
    # read at the one answer (0539), for this run's cars only; the same name at another depot is untouched
    targets = dict(db.rows(f"SELECT id, ottoq_effective_target_soc_at(id, now()) FROM vehicles WHERE fleet_operator_id = '{TESLA}'"))
    assert targets[AV041] == "90" and targets[AV045] == "90" and targets[RT003] == "90" and targets[AV041_ELSEWHERE] == "100"
    # pinned to another run, or to none, the owner's limit does not apply (a pair arm, a stop)
    assert db.val(f"SELECT set_config('ottoq.sim_run_id', '{uuid.uuid4()}', false) IS NOT NULL AND ottoq_effective_target_soc_at('{AV041}', now()) = 100") == "t"
    assert db.val(f"SELECT set_config('ottoq.sim_run_id', 'none', false) IS NOT NULL AND ottoq_effective_target_soc_at('{AV041}', now()) = 100") == "t"
    assert db.val(f"SELECT set_config('ottoq.sim_run_id', '{run}', false) IS NOT NULL AND ottoq_effective_target_soc_at('{AV041}', now()) = 90") == "t"
    # the tick: the car's stamp (which the charge advance re-reads every tick), its visit and its open charge atom
    assert db.tick(run, "2026-09-27 12:05+00") == 4
    stamps = dict(db.rows(f"SELECT id, target_soc FROM vehicles WHERE fleet_operator_id = '{TESLA}'"))
    assert stamps[AV041] == "90" and stamps[AV041_ELSEWHERE] == "100"
    vis = db.rows(f"SELECT target_soc, atoms->0->>'target_soc' FROM ottoq_visit_needs WHERE vehicle_id = '{AV041}' AND sim_run_id = '{run}'")
    assert vis == [["90", "90"]]
    done_atom = db.val(f"SELECT atoms->0->>'target_soc' FROM ottoq_visit_needs WHERE vehicle_id = '{AV045}' AND sim_run_id = '{run}'")
    assert done_atom == "100"   # a finished charge is history; it is not rewritten
    assert db.rows("SELECT event_type, payload->>'retargeted' FROM stub_events") == [["ottoq.owner_settings_applied", "4"]]
    # idempotent: nothing pending, nothing changes, no event
    assert db.tick(run, "2026-09-27 12:06+00") == 0
    assert db.val("SELECT count(*) FROM stub_events") == "1"


def test_undo_restores_what_a_command_replaced(db, owner):
    run = fresh_run(db)
    first = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 90})["data"]["command"]["command_id"]
    second = db.call(owner, "set_charge_limit", {"vehicles": ["RT-3", "AV 41"], "percent": 85})["data"]["command"]["command_id"]
    undo = db.call(owner, "undo_command", {"command_id": second})
    assert undo["data"]["outcome"] == "applied" and "2 go back to 90%" in undo["data"]["summary"]
    limits = dict(db.rows(f"SELECT vehicle_id, charge_limit_pct FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND status = 'active'"))
    assert limits == {AV001: "90", AV041: "90", AV045: "90", RT003: "90"}
    assert db.call(owner, "undo_command", {"command_id": second})["error"]["code"] == "already_undone"
    db.call(owner, "undo_command", {"command_id": first})
    assert db.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND status = 'active'") == "0"
    assert db.call(owner, "undo_command", {"command_id": undo["data"]["command"]["command_id"]})["error"]["code"] == "cannot_undo_an_undo"
    db.tick(run, "2026-09-27 12:10+00")
    assert db.val(f"SELECT target_soc FROM vehicles WHERE id = '{AV041}'") == "100"


def test_the_same_key_is_the_same_command(db, owner):
    fresh_run(db)
    a = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 95, "idempotency_key": "limit-95"})
    b = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 95, "idempotency_key": "limit-95"})
    assert a["http_status"] == 201 and b["http_status"] == 200 and b["data"]["duplicate"] is True
    assert a["data"]["command"]["command_id"] == b["data"]["command"]["command_id"]


# ──────────────────────────────────────────────────────────────────────────────────────────── services ──

def test_a_service_bay_after_charging(db, owner):
    run = fresh_run(db)
    out = db.call(owner, "request_service", {"vehicles": ["AV-41"], "service": "service bay"})
    assert out["data"]["outcome"] == "applied"
    s = out["data"]["summary"]
    assert s.startswith("Done. Tesla-AV-041 gets mechanical PM on this visit (in the service bay, about 40 min)")
    assert "work in a bay comes after the charge" in s
    # until the tick has put it on the visit, the car may not leave (an order placed mid-tick cannot be outrun)
    db.run(f"UPDATE vehicles SET current_soc = 100 WHERE id = '{AV041}'")
    db.run(f"""UPDATE ottoq_visit_needs SET atoms = '[{{"svc":"charge","status":"done"}},{{"svc":"readiness_check","status":"done"}}]'
               WHERE vehicle_id = '{AV041}' AND sim_run_id = '{run}'""")
    assert not db.clear(AV041, run, "2026-09-27 12:00+00")
    assert db.tick(run, "2026-09-27 12:01+00") == 1
    atom = db.json(f"""SELECT a FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                       WHERE n.vehicle_id = '{AV041}' AND n.sim_run_id = '{run}' AND a->>'svc' = 'mechanical_pm'""")
    assert atom["requires_bay"] == "service_bay" and atom["concurrency"] == "bay" and atom["est_min"] == 40
    assert atom["must_do"] is True and atom["carryover_eligible"] is False and atom["owner_added"] is True
    # now the open atom holds it, as every open atom does (0543)
    assert not db.clear(AV041, run, "2026-09-27 12:02+00")
    db.run(f"""UPDATE ottoq_visit_needs SET atoms = (SELECT jsonb_agg(CASE WHEN a->>'svc' = 'mechanical_pm' THEN a || '{{"status":"done"}}' ELSE a END)
                                                      FROM jsonb_array_elements(atoms) a)
               WHERE vehicle_id = '{AV041}' AND sim_run_id = '{run}'""")
    assert db.clear(AV041, run, "2026-09-27 12:50+00")
    db.tick(run, "2026-09-27 12:51+00")
    assert db.val(f"SELECT status FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND kind = 'service'") == "fulfilled"


def test_every_return_reaches_new_visits_from_their_first_row_and_cancel_takes_only_the_owners(db, owner):
    run = fresh_run(db)
    out = db.call(owner, "request_service", {"vehicles": "all", "service": "external cleaning", "when": "every_return"})
    assert out["data"]["outcome"] == "applied"
    assert "on every visit from now on, this one included" in out["data"]["summary"]
    # a car that comes back opens a visit: the trigger puts the wash on it before any planner reads it
    svcs = db.json(f"""INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms)
                       VALUES ('{AV001}', '{run}', '{TWIN}', '2026-09-27 12:20+00', 'av001:{run[:8]}', '[{{"svc":"charge"}}]')
                       RETURNING jsonb_path_query_array(atoms, '$[*].svc')""")
    assert svcs == ["charge", "exterior_wash"]
    db.tick(run, "2026-09-27 12:21+00")
    washes = dict(db.rows(f"""SELECT n.vehicle_id, count(*) FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                              WHERE n.sim_run_id = '{run}' AND a->>'svc' = 'exterior_wash' GROUP BY 1"""))
    assert washes == {AV001: "1", AV041: "1", AV045: "1", RT003: "1"}       # AV-045's own wash is tagged, not doubled
    assert db.val(f"""SELECT a ? 'owner_added' FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                      WHERE n.vehicle_id = '{AV045}' AND n.sim_run_id = '{run}' AND a->>'svc' = 'exterior_wash'""") == "f"
    cancel = db.call(owner, "cancel_service", {"vehicles": "all", "service": "exterior_wash"})
    assert "3 have it taken off their plans" in cancel["data"]["summary"]
    assert "1 keeps it on this visit because OTTO-Q found it needed" in cancel["data"]["summary"]
    db.tick(run, "2026-09-27 12:22+00")
    left = db.rows(f"""SELECT n.vehicle_id, a::text FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                       WHERE n.sim_run_id = '{run}' AND a->>'svc' = 'exterior_wash'""")
    assert [r[0] for r in left] == [AV045] and "owner_setting_ids" not in left[0][1]


def test_a_started_owner_service_finishes_when_cancelled(db, owner):
    run = fresh_run(db)
    db.call(owner, "request_service", {"vehicles": ["RT-3"], "service": "software update"})
    db.tick(run, "2026-09-27 12:01+00")
    db.run(f"""UPDATE ottoq_visit_needs SET atoms = (SELECT jsonb_agg(CASE WHEN a->>'svc' = 'software_update' THEN a || '{{"status":"in_progress"}}' ELSE a END)
                                                      FROM jsonb_array_elements(atoms) a)
               WHERE vehicle_id = '{RT003}' AND sim_run_id = '{run}'""")
    out = db.call(owner, "cancel_service", {"vehicles": ["RT-3"]})
    assert "is under way and finishes" in out["data"]["summary"]
    db.tick(run, "2026-09-27 12:02+00")
    assert db.val(f"""SELECT a->>'status' FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                      WHERE n.vehicle_id = '{RT003}' AND n.sim_run_id = '{run}' AND a->>'svc' = 'software_update'""") == "in_progress"


def test_next_return_waits_for_the_car_to_leave(db, owner):
    run = fresh_run(db)
    db.call(owner, "request_service", {"vehicles": ["45"], "service": "interior deep clean", "when": "next_return"})
    db.tick(run, "2026-09-27 12:01+00")
    assert db.val(f"""SELECT count(*) FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                      WHERE n.vehicle_id = '{AV045}' AND n.sim_run_id = '{run}' AND a->>'svc' = 'interior_deep_clean'""") == "0"
    # a re-derive while it never left is not a return
    db.run(f"""INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms)
               VALUES ('{AV045}', '{run}', '{TWIN}', '2026-09-27 12:30+00', 'av045b:{run[:8]}', '[{{"svc":"charge"}}]')""")
    assert db.val(f"""SELECT count(*) FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                      WHERE n.visit_key = 'av045b:{run[:8]}' AND a->>'svc' = 'interior_deep_clean'""") == "0"
    db.run(f"INSERT INTO ottoq_vehicle_dispatches (vehicle_id, sim_run_id, dispatched_at) VALUES ('{AV045}', '{run}', '2026-09-27 13:00+00')")
    db.run(f"""INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms)
               VALUES ('{AV045}', '{run}', '{TWIN}', '2026-09-27 15:00+00', 'av045c:{run[:8]}', '[{{"svc":"charge"}}]')""")
    atom = db.json(f"""SELECT a FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                       WHERE n.visit_key = 'av045c:{run[:8]}' AND a->>'svc' = 'interior_deep_clean'""")
    assert atom["requires_bay"] == "detail" and atom["stall_type_required"] == "wash_bay"


@pytest.mark.parametrize("service,code", [
    ("fault_repair", "service_not_requestable"), ("charge", "service_not_requestable"),
    ("readiness_check", "service_not_requestable"), ("perimeter_walkaround", "service_not_requestable"),
    ("teleport", "unknown_service"),
])
def test_services_an_owner_may_not_request(db, owner, service, code):
    fresh_run(db)
    out = db.call(owner, "request_service", {"vehicles": "all", "service": service})
    assert out["error"]["code"] == code, out


def test_a_service_the_contract_blocks_is_refused(db, owner):
    fresh_run(db)
    db.run(f"UPDATE ottoq_fleet_operator_slas SET blocked_services = ARRAY['software_update'] WHERE fleet_operator_id = '{TESLA}'")
    try:
        out = db.call(owner, "request_service", {"vehicles": "all", "service": "software_update"})
        assert out["error"]["code"] == "service_blocked_by_contract"
    finally:
        db.run(f"UPDATE ottoq_fleet_operator_slas SET blocked_services = '{{}}' WHERE fleet_operator_id = '{TESLA}'")


# ─────────────────────────────────────────────────────────────────────────────────────────────── holds ──

def test_a_hold_only_delays_and_ends_on_time(db, owner):
    run = fresh_run(db)
    db.run(f"""UPDATE ottoq_visit_needs SET atoms = '[{{"svc":"charge","status":"done"}},{{"svc":"readiness_check","status":"done"}}]'
               WHERE vehicle_id = '{AV045}' AND sim_run_id = '{run}'""")
    assert db.clear(AV045, run, "2026-09-27 12:00+00")
    out = db.call(owner, "hold_vehicle", {"vehicles": ["45"], "until": "8:30 AM"})     # 13:30 UTC, CDT
    assert out["data"]["outcome"] == "applied"
    assert "will not leave before 8:30 AM sim time; once it is ready it waits in staging" in out["data"]["summary"]
    assert not db.clear(AV045, run, "2026-09-27 13:29+00")
    assert db.clear(AV045, run, "2026-09-27 13:30+00")
    db.tick(run, "2026-09-27 13:31+00")
    assert db.val(f"SELECT status FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND kind = 'hold'") == "fulfilled"
    assert db.call(owner, "hold_vehicle", {"vehicles": ["45"], "for_minutes": 2000})["http_status"] == 400
    assert db.call(owner, "hold_vehicle", {"vehicles": ["45"], "until": "2026-09-28T23:00:00Z"})["error"]["code"] == "hold_too_long"
    assert db.call(owner, "hold_vehicle", {"vehicles": ["45"], "until": "2026-09-27T11:00:00Z"})["error"]["code"] == "hold_in_the_past"


def test_release_lets_a_held_car_go(db, owner):
    run = fresh_run(db)
    db.run(f"""UPDATE ottoq_visit_needs SET atoms = '[{{"svc":"charge","status":"done"}},{{"svc":"readiness_check","status":"done"}}]'
               WHERE vehicle_id = '{AV045}' AND sim_run_id = '{run}'""")
    db.call(owner, "hold_vehicle", {"vehicles": ["45"], "for_minutes": 120})
    assert not db.clear(AV045, run, "2026-09-27 12:30+00")
    out = db.call(owner, "release_hold", {"vehicles": ["Tesla-AV-045"]})
    assert out["data"]["summary"].startswith("Done. Tesla-AV-045 may leave as soon as it is ready.")
    assert db.clear(AV045, run, "2026-09-27 12:30+00")


# ───────────────────────────────────────────────────────────────────────────────────── the run's end ──

def test_the_runs_end_puts_everything_back(db, owner):
    run = fresh_run(db)
    db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 90})
    db.call(owner, "hold_vehicle", {"vehicles": ["45"], "for_minutes": 120})
    db.call(owner, "request_service", {"vehicles": "all", "service": "wash", "when": "every_return"})
    db.tick(run, "2026-09-27 12:01+00")
    assert db.val(f"SELECT target_soc FROM vehicles WHERE id = '{AV041}'") == "90"
    db.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    assert db.rows(f"SELECT DISTINCT status FROM ottoq_owner_settings WHERE sim_run_id = '{run}'") == [["lifted"]]
    stamps = {r[0] for r in db.rows(f"SELECT target_soc FROM vehicles WHERE fleet_operator_id = '{TESLA}'")}
    assert stamps == {"100"}
    assert db.val(f"SELECT bool_and(lifted_at IS NOT NULL) FROM ottoq_owner_commands WHERE sim_run_id = '{run}' AND outcome = 'applied'") == "t"
    after = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 90})
    assert after["error"]["code"] == "no_live_demo"
    assert db.call(owner, "my_settings")["data"]["summary"] == "No run is live, so nothing is in force: every car is at baseline."
    # the next run starts at baseline
    nxt = fresh_run(db)
    assert db.val(f"SELECT ottoq_effective_target_soc_at('{AV041}', now())") == "100"
    assert db.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{nxt}'") == "0"


def test_only_a_demo_run_takes_owner_settings(db, owner):
    db.run("UPDATE ottoq_sim_runs SET status = 'completed' WHERE status IN ('running', 'paused')")
    run = str(uuid.uuid4())
    db.run(f"""INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_current, run_by)
               VALUES ('{run}', '{TWIN}', 'running', clock_timestamp(), '2026-09-27 12:00+00', 'cert_harness')""")
    out = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 90})
    assert out["error"]["code"] == "no_live_demo" and "not a demo run" in out["error"]["message"]
    db.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")


# ───────────────────────────────────────────────────────────────────────────── inert without owners ──

def test_without_owner_settings_nothing_on_the_tick_path_changes(db):
    run = fresh_run(db)
    db.run("TRUNCATE stub_events, stub_itinerary_calls")
    before = db.rows(f"SELECT id, target_soc, current_state FROM vehicles ORDER BY id")
    visits = db.rows(f"SELECT visit_id, atoms::text FROM ottoq_visit_needs WHERE sim_run_id = '{run}' ORDER BY visit_id")
    assert db.tick(run, "2026-09-27 12:05+00") == 0
    assert db.rows(f"SELECT id, target_soc, current_state FROM vehicles ORDER BY id") == before
    assert db.rows(f"SELECT visit_id, atoms::text FROM ottoq_visit_needs WHERE sim_run_id = '{run}' ORDER BY visit_id") == visits
    assert db.val("SELECT count(*) FROM stub_events") == "0" and db.val("SELECT count(*) FROM stub_itinerary_calls") == "0"
    # a new visit is inserted exactly as written
    atoms = '[{"svc":"charge","target_soc":100},{"svc":"readiness_check"}]'
    got = db.val(f"""INSERT INTO ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms)
                     VALUES ('{AV001}', '{run}', '{TWIN}', '2026-09-27 12:10+00', 'inert:{run[:8]}', '{atoms}') RETURNING atoms::text""")
    assert json.loads(got) == json.loads(atoms)
    # and the effective target and departure test read as the pre-0605 functions did
    old_target = db.text("SELECT definition FROM ottoq_schema_snapshots WHERE label = '0605_pre' AND object_name = 'ottoq_effective_target_soc_at'")
    assert "ottoq_owner" not in old_target
    for v in (AV001, AV041, AV045, RT003):
        assert db.val(f"SELECT ottoq_effective_target_soc_at('{v}', now())") == "100"


# ─────────────────────────────────────────────────────────────────────────────────── the evidence ──

def test_the_evidence_cannot_be_edited_and_records_who_asked(db, owner):
    fresh_run(db)
    out = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 95, "note": "range test"})
    cid = out["data"]["command"]["command_id"]
    rc, _, err = db.run(f"UPDATE ottoq_owner_commands SET summary = 'edited' WHERE command_id = '{cid}'", check=False)
    assert rc != 0 and "immutable" in err
    rc, _, err = db.run(f"DELETE FROM ottoq_owner_commands WHERE command_id = '{cid}'", check=False)
    assert rc != 0 and "DELETE refused" in err
    rc, _, err = db.run("TRUNCATE ottoq_owner_commands CASCADE", check=False)
    assert rc != 0
    rec = db.rows(f"SELECT principal_name, tool, mode, outcome, args->>'note' FROM ottoq_owner_commands WHERE command_id = '{cid}'")
    assert rec == [["chase-hermes", "set_charge_limit", "apply", "applied", "range test"]]


def test_my_commands_and_my_settings_read_back(db, owner):
    fresh_run(db)
    db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 90})
    db.call(owner, "request_service", {"vehicles": "all", "service": "wash", "when": "every_return"})
    s = db.call(owner, "my_settings")["data"]
    assert s["summary"].startswith("In force on this run: 4 cars charge to at most 90%; 4 cars have exterior wash on every return.")
    cmds = db.call(owner, "my_commands", {"limit": 2})["data"]["commands"]
    assert [c["command"]["tool"] for c in cmds] == ["request_service", "set_charge_limit"]
    car = db.call(owner, "my_vehicle", {"vehicle": "45"})["data"]
    assert car["summary"].startswith("Tesla-AV-045 (Model Y) is staged to leave, at 99%, charging to 90% (your limit; full is 100%).")


def test_the_ask_transport_is_ledgered(db, owner):
    fresh_run(db)
    out = db.call(owner, "my_fleet", transport="ask")
    assert db.val(f"SELECT transport FROM ottoq_agent_call_ledger WHERE call_id = {out['call_id']}") == "ask"


# ───────────────────────────────────────────────────────────────────────────── 0606: OrchestrAV's read ──

def test_the_cockpit_reads_what_the_agent_set_as_anon(db, owner):
    run = fresh_run(db)
    applied = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 90})["data"]["command"]["command_id"]
    db.call(owner, "request_service", {"vehicles": ["45"], "service": "wash", "when": "every_return"})
    db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 90, "mode": "preview"})          # not shown
    db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 60})                             # refused: shown
    rc, out, err = db.run(f"SELECT ottoq_owner_board('{TESLA}', '{TWIN}', '{applied}')", role="anon")
    assert rc == 0, err
    b = json.loads(out)
    assert b["ok"] and b["run"]["sim_run_id"] == run and b["run"]["demo"] is True and b["full_pct"] == 100
    assert b["counts"] == {"charge_limits": 4, "holds": 0, "orders": 1}
    assert b["by_vehicle"][AV045]["charge_limit_pct"] == 90
    assert b["by_vehicle"][AV045]["orders"] == [{"service": "exterior_wash", "name": "Exterior wash", "when": "every_return"}]
    assert [c["outcome"] for c in b["commands"]][:3] == ["refused", "applied", "applied"]
    assert all(c["outcome"] != "previewed" for c in b["commands"])
    hl = b["highlight"]
    assert hl["command_id"] == applied and hl["summary"].startswith("Done. All 4 Teslas charge to at most 90%")
    assert len(hl["effects"]) == 4 and "idempotency_key" not in hl["args"]
    for c in b["commands"]:
        assert "principal_id" not in c and "idempotency_key" not in c


def test_the_cockpit_read_is_scoped_to_one_operator(db, owner):
    fresh_run(db)
    cid = db.call(owner, "set_charge_limit", {"vehicles": "all", "percent": 95})["data"]["command"]["command_id"]
    waymo = json.loads(db.run(f"SELECT ottoq_owner_board('{WAYMO}', '{TWIN}', '{cid}')", role="anon")[1])
    assert waymo["ok"] and waymo["in_force"] == [] and waymo["commands"] == [] and "highlight" not in waymo or waymo["highlight"] is None
    assert json.loads(db.run("SELECT ottoq_owner_board(NULL)", role="anon")[1])["error"] == "fleet_operator_required"
    rc, _, err = db.run("SELECT count(*) FROM ottoq_owner_commands", role="anon", check=False)
    assert rc != 0 and "permission denied" in err
