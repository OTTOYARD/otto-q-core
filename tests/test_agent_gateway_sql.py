"""db/migrations/0559 + 0560, EXECUTED against a stub engine -- the agent gateway's database half.

WHY THIS EXISTS. scripts/compile-check.py stops at 0559's first precondition in an empty database (by design) and
compiles only DO blocks and plpgsql bodies whose types exist, so the tables, the grants, the dispatcher, the scoping,
the routing and the guards would all reach the apply window unexecuted. 0364 made the same point and validated by
hand; this makes it a test.

WHAT IT RUNS AGAINST. tests/fixtures/agent_gateway_stub_engine.sql: the two engine doors an approval routes to
(ottoq_hw_recall_vehicle, ottoq_apply_ops_action) and the functions they and the gateway call (ottoq_policy_set,
ottoq_dial_clamp, ottoq_is_agent_actor, ottoq_policy_get, ottoq.ottoq_stall_free_between, ottoq_twin_run_context,
ottoq_vehicle_card, ottoq_check_run_scope_registry) are the LIVE bodies, and the first test below proves it by md5
against the live catalog. ottoq_depot_cards and ottoq_activity_feed are stubs with the live signature.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_compile_check.py, so CI without a database stays
green. It uses $PGHOST/$PGPORT/$PGUSER/$PGPASSWORD when PGHOST is set, else the local cluster on /var/tmp:55432.
"""
import hashlib
import json
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "agent_gateway_stub_engine.sql")
M0559 = os.path.join(ROOT, "db", "migrations", "0559_an_outside_agent_asks_through_one_door_and_a_person_decides.sql")
M0560 = os.path.join(ROOT, "db", "migrations", "0560_the_fleet_owner_cockpit_reads_its_own_agent_requests.sql")

TWIN = "11111111-1111-1111-1111-111111111111"
RUN = "5e5e5e5e-0000-0000-0000-000000000001"
WAYMO, TESLA, ZOOX = ("22222222-2222-2222-2222-222222222222", "33333333-3333-3333-3333-333333333333",
                      "44444444-4444-4444-4444-444444444444")
W1, W2, T1, Z1, W_OTHER_DEPOT = ("ee000000-0000-0000-0000-0000000000a1", "ee000000-0000-0000-0000-0000000000a2",
                                 "ee000000-0000-0000-0000-0000000000b1", "ee000000-0000-0000-0000-0000000000c1",
                                 "ee000000-0000-0000-0000-0000000000a9")
SUPERVISOR, MANAGER, TECH, OTHER_DEPOT_MANAGER = ("a0000000-0000-0000-0000-00000000000a",
                                                  "b0000000-0000-0000-0000-00000000000b",
                                                  "c0000000-0000-0000-0000-00000000000c",
                                                  "d0000000-0000-0000-0000-00000000000d")
TESLA_USER, WAYMO_USER = "e0000000-0000-0000-0000-00000000000e", "f0000000-0000-0000-0000-00000000000f"

#: md5(pg_get_functiondef()) read from the LIVE catalog (gxdrcyphqjzjsuhxuqtg) on 2026-09-28. The stub's copies must
#: match, or the routing this file tests is not the routing production runs.
LIVE_MD5 = {
    "public.ottoq_hw_recall_vehicle": "1460f1126e0e1faacf4cb3e68376da79",
    "public.ottoq_apply_ops_action": "3ca7589f04aa9c1b76e38030c6952ca4",
    "public.ottoq_policy_set": "cabe39cc8e194ddf8e81f84b91181884",
    "public.ottoq_dial_clamp": "b32246daf49a45430a2b59ea9f2bd3b3",
    "public.ottoq_is_agent_actor": "f349c63ad2c48b7756633024d6da263b",
    "public.ottoq_policy_get": "60514764c4250d201c1ad0079f189584",
    "ottoq.ottoq_stall_free_between": "f5c4526d8243fe0ff3c192b65e9ef962",
    "public.ottoq_twin_run_context": "44b3bf3fc4a335c1b0226ae87cf62ae8",
    "public.ottoq_vehicle_card": "bbb2937f6fb4b9a7ab8383bb749f58a7",
    "public.ottoq_check_run_scope_registry": "4d0011f6bfd5d7448273ccd7c6bcc5dc",
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

    def run(self, sql, *, uid=None, role=None, check=True):
        """Run SQL in one session. Returns (returncode, last stdout line, stderr)."""
        prefix = ""
        if uid is not None:
            prefix += f"SELECT set_config('request.jwt.claim.sub', '{uid}', false);\n"
        if role is not None:
            prefix += f"SET ROLE {role};\n"
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

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr

    def call(self, token_hash, tool, args=None, meta=None):
        a = json.dumps(args or {}).replace("'", "''")
        m = json.dumps(meta or {}).replace("'", "''")
        return self.json(f"SELECT ottoq_agent_call('{token_hash}', '{tool}', '{a}'::jsonb, 'rest', '{m}'::jsonb)")

    def decide(self, uid, request_id, decision, note=None):
        n = "NULL" if note is None else "'" + note.replace("'", "''") + "'"
        return self.json(f"SELECT ottoq_agent_request_decide('{request_id}', '{decision}', {n})", uid=uid)

    def issue(self, name, kind, caps, fleet=None, rate=60, pending=20):
        f = "NULL" if fleet is None else f"'{fleet}'"
        arr = "ARRAY[" + ",".join(f"'{c}'" for c in caps) + "]::text[]"
        res = self.json(f"SELECT ottoq_agent_issue_token('{name}', '{kind}', {arr}, {f}, '{TWIN}', NULL, {rate}, {pending})")
        assert res["ok"], res
        return hashlib.sha256(res["token"].encode()).hexdigest(), res


@pytest.fixture(scope="module")
def db():
    name = f"ottoq_agw_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub engine did not load: {err}"
        rc, err = d.file(M0559)
        assert rc == 0, f"0559 did not apply: {err}"
        rc, err = d.file(M0560)
        assert rc == 0, f"0560 did not apply: {err}"
        yield d
    finally:
        subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


@pytest.fixture(scope="module")
def agents(db):
    hermes, _ = db.issue("hermes", "personal", ["read", "note", "request_recall", "request_ops_action", "request_adjustment"])
    waymo, _ = db.issue("waymo-agent", "fleet_operator", ["read", "note", "request_recall", "request_adjustment"], WAYMO)
    tesla, _ = db.issue("tesla-agent", "fleet_operator", ["read", "note", "request_recall"], TESLA)
    return {"hermes": hermes, "waymo": waymo, "tesla": tesla}


def test_the_copied_doors_are_byte_identical_to_the_live_catalog(db):
    for fn, want in LIVE_MD5.items():
        schema, name = fn.split(".")
        got = db.val(f"SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace "
                     f"WHERE n.nspname = '{schema}' AND p.proname = '{name}'")
        assert got == want, f"{fn}: stub md5 {got} is not the live {want}"


def test_a_second_apply_refuses_before_touching_anything(db):
    rc, err = db.file(M0559)
    assert rc != 0 and "0559 P2" in err, err
    rc, err = db.file(M0560)
    assert rc != 0 and "0560 P1" in err, err


def test_the_verification_probe_left_nothing_behind(db):
    # 0559 V7 issues a token, reads, writes a note, revokes, and rolls it all back. A fresh apply holds no rows.
    fresh = f"ottoq_agw_fresh_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {fresh}"], check=True, capture_output=True)
    try:
        f = Db(fresh)
        assert f.file(STUB)[0] == 0 and f.file(M0559)[0] == 0
        assert f.val("SELECT count(*) FROM ottoq_agent_principals") == "0"
        assert f.val("SELECT count(*) FROM ottoq_agent_requests") == "0"
        assert f.val("SELECT count(*) FROM ottoq_agent_call_ledger") == "0"
        # 0559 alone does not open the operator read to anon; 0560 is the separate decision
        assert f.val("SELECT has_function_privilege('anon', 'ottoq_agent_requests_for_operator(uuid,uuid,integer)', 'EXECUTE')") == "f"
    finally:
        subprocess.run(admin + ["-c", f"DROP DATABASE IF EXISTS {fresh} WITH (FORCE)"], capture_output=True)


def test_every_role_reaches_exactly_its_doors(db):
    expect = {
        # function: (anon, authenticated, service_role)
        "ottoq_agent_call(text,text,jsonb,text,jsonb)": ("f", "f", "t"),
        "ottoq_agent_issue_token(text,text,text[],uuid,uuid,text,integer,integer)": ("f", "f", "t"),
        "ottoq_agent_revoke(text,text,boolean)": ("f", "f", "t"),
        "ottoq_agent_inbox(uuid,boolean,integer)": ("f", "t", "t"),
        "ottoq_agent_request_decide(uuid,text,text)": ("f", "t", "t"),
        "ottoq_agent_requests_for_operator(uuid,uuid,integer)": ("t", "t", "t"),  # anon by 0560
        "ottoq_agent_submit_request(ottoq_agent_principals,text,jsonb)": ("f", "f", "f"),
        "ottoq_agent_read_fleet(ottoq_agent_principals,jsonb)": ("f", "f", "f"),
        "ottoq_agent_resolve(text)": ("f", "f", "f"),
    }
    for fn, want in expect.items():
        got = tuple(db.val(f"SELECT has_function_privilege('{r}', '{fn}', 'EXECUTE')")
                    for r in ("anon", "authenticated", "service_role"))
        assert got == want, f"{fn}: {got} != {want}"
    for tbl in ("ottoq_agent_principals", "ottoq_agent_requests", "ottoq_agent_call_ledger"):
        for role in ("anon", "authenticated", "service_role"):
            rc, _, err = db.run(f"SELECT count(*) FROM {tbl}", role=role, check=False)
            assert rc != 0 and "permission denied" in err, f"{role} could read {tbl}"


def test_the_token_hash_is_plain_sha256_hex_so_the_edge_function_can_compute_it(db):
    token = "oqa_" + "ab" * 32
    sql_hash = db.val(f"SELECT encode(sha256(convert_to('{token}', 'UTF8')), 'hex')")
    assert sql_hash == hashlib.sha256(token.encode()).hexdigest()


def test_a_fleet_scoped_agent_sees_only_its_fleet(db, agents):
    w = agents["waymo"]
    fleet = db.call(w, "fleet_summary")
    assert fleet["ok"] and fleet["data"]["scope"] == "your fleet only"
    assert sorted(v["display_name"] for v in fleet["data"]["vehicles"]) == ["Waymo-AV-001", "Waymo-AV-002"]
    # a Tesla car and a Waymo car at another depot read exactly like a car that does not exist
    for vid in (T1, W_OTHER_DEPOT, str(uuid.uuid4())):
        r = db.call(w, "vehicle_card", {"vehicle_id": vid})
        assert r["http_status"] == 404 and r["error"]["code"] == "vehicle_not_found", r
    own = db.call(w, "vehicle_card", {"vehicle_id": W2})
    assert own["ok"] and own["data"]["card"]["operator"]["name"] == "Waymo Nashville"
    decisions = db.call(w, "recent_decisions")
    assert {d["vehicle"] for d in decisions["data"]["decisions"]} == {"Waymo-AV-001", "Waymo-AV-002"}
    everyone = db.call(agents["hermes"], "recent_decisions")
    assert {d["vehicle"] for d in everyone["data"]["decisions"]} == {"Waymo-AV-001", "Waymo-AV-002", "Tesla-AV-001", "Zoox-AV-001"}


def test_stall_availability_is_three_gates_on_the_sim_clock(db, agents):
    r = db.call(agents["hermes"], "stall_availability")
    assert r["ok"] and r["data"]["live"]
    assert r["data"]["window_sim"]["from"].startswith("2026-09-27T12:00:00")
    offerable = sorted(s["stall_code"] for s in r["data"]["offerable_stalls"])
    # DCFC-02: charger Faulted. DCFC-03: occupied. L2-01: booked in the SIM window. STG-01: reserved_by set (the gate
    # ottoq_stall_free_between does not read). L2-02 is booked only in the REAL-clock window, so it IS offerable --
    # a calendar read against now() would have refused it and offered L2-01 instead.
    assert offerable == ["DCFC-01", "L2-02", "STG-02"], offerable
    by = {t["stall_type"]: t for t in r["data"]["by_type"]}
    assert by["dcfc"] == {"stall_type": "dcfc", "total": 3, "pointer_free": 2, "calendar_and_charger_free": 2,
                          "charger_faulted": 1, "offerable": 1}
    assert by["l2"]["calendar_and_charger_free"] == 1 and by["staging"]["pointer_free"] == 1
    bad = db.call(agents["hermes"], "stall_availability", {"stall_type": "garage"})
    assert bad["http_status"] == 400


def test_submissions_are_refused_with_the_reason(db, agents):
    h, w = agents["hermes"], agents["waymo"]
    cases = [
        (w, "submit_request", {"kind": "ops_action", "title": "x", "action": "enable_energy_reserve"}, 403, "capability_missing"),
        (h, "submit_request", {"kind": "ops_action", "title": "x", "action": "raise_deploy_surge"}, 422, "not_agent_writable"),
        (h, "submit_request", {"kind": "ops_action", "title": "x", "action": "extend_forecast_horizon"}, 422, "not_agent_writable"),
        (h, "submit_request", {"kind": "ops_action", "title": "x", "action": "launch"}, 400, "unknown_ops_action"),
        (w, "submit_request", {"kind": "recall_vehicle", "title": "x", "vehicle_id": T1}, 404, "vehicle_not_found"),
        (h, "submit_request", {"kind": "recall_vehicle", "title": "x"}, 400, "invalid_arguments"),
        (h, "submit_request", {"kind": "teleport", "title": "x"}, 400, "invalid_kind"),
        (h, "submit_request", {"kind": "adjustment", "title": "x", "adjustment": "Bad Name"}, 400, "invalid_arguments"),
        (h, "send_note", {"title": ""}, 400, "invalid_arguments"),
        (h, "send_note", {"title": "x", "ttl_minutes": 1}, 400, "invalid_arguments"),
        (h, "drop_tables", {}, 404, "unknown_tool"),
        ("0" * 64, "whoami", {}, 401, "unauthenticated"),
    ]
    for tok, tool, args, status, code in cases:
        r = db.call(tok, tool, args)
        assert (r["http_status"], r["error"]["code"]) == (status, code), (tool, args, r)


def test_arguments_the_gateway_refused_are_still_authenticated_and_ledgered_here(db, agents):
    """The edge function checks arguments against each tool's published schema, and asks the database BEFORE it answers
    a refusal (meta.gateway_refusal): an unknown token gets its 401 rather than a lesson in the schema, a missing
    capability outranks the argument problem, and a known token's malformed call leaves a ledger row under its tool."""
    flag = {"gateway_refusal": "invalid_arguments", "path": "/v1/vehicles/not-a-uuid", "http_method": "GET"}
    r = db.call(agents["waymo"], "vehicle_card", {}, flag)
    assert (r["http_status"], r["error"]["code"]) == (400, "invalid_arguments"), r
    row = db.json(f"SELECT to_jsonb(l) FROM ottoq_agent_call_ledger l WHERE l.call_id = {r['call_id']}")
    assert (row["tool"], row["http_status"], row["error_code"], row["path"], row["ok"]) == \
        ("vehicle_card", 400, "invalid_arguments", "/v1/vehicles/not-a-uuid", False)
    assert db.call("f" * 64, "vehicle_card", {}, flag)["http_status"] == 401
    note_only, _ = db.issue("note-only-refusal", "personal", ["note"])
    r = db.call(note_only, "vehicle_card", {}, flag)
    assert (r["http_status"], r["error"]["code"]) == (403, "capability_missing"), r
    r = db.call(agents["waymo"], "drop_tables", {}, flag)
    assert (r["http_status"], r["error"]["code"]) == (404, "unknown_tool"), r
    # an unflagged call with the same (empty) arguments is the tool's own refusal, not the gateway's
    r = db.call(agents["waymo"], "vehicle_card", {})
    assert (r["http_status"], r["error"]["message"]) == (400, "vehicle_id is required."), r


def test_the_same_idempotency_key_replays_instead_of_asking_twice(db, agents):
    first = db.call(agents["tesla"], "send_note", {"title": "idempotent", "idempotency_key": "k-1"})
    again = db.call(agents["tesla"], "send_note", {"title": "idempotent, retried", "idempotency_key": "k-1"})
    assert first["http_status"] == 201 and again["http_status"] == 200 and again["data"]["duplicate"]
    assert first["data"]["request"]["request_id"] == again["data"]["request"]["request_id"]


def test_only_the_right_person_decides(db, agents):
    note = db.call(agents["hermes"], "send_note", {"title": "who decides"})["data"]["request"]["request_id"]
    assert db.json(f"SELECT ottoq_agent_request_decide('{note}', 'approved')")["error"] == "sign_in_required"
    assert db.decide(TECH, note, "approved")["error"] == "role_insufficient"
    assert db.decide(OTHER_DEPOT_MANAGER, note, "approved")["error"] == "not_authorized"
    assert db.decide(SUPERVISOR, note, "maybe")["error"] == "invalid_decision"
    db.run(f"UPDATE fleet_operators SET auth_user_id = '{TESLA_USER}' WHERE id = '{TESLA}'")
    db.run(f"UPDATE fleet_operators SET auth_user_id = '{WAYMO_USER}' WHERE id = '{WAYMO}'")
    waymo_req = db.call(agents["waymo"], "submit_request",
                        {"kind": "adjustment", "title": "hold Waymo-AV-001", "vehicle_id": W1,
                         "adjustment": "hold_until", "value": "06:00"})["data"]["request"]["request_id"]
    assert db.decide(TESLA_USER, waymo_req, "approved")["error"] == "not_your_fleet"
    ops = db.call(agents["hermes"], "submit_request",
                  {"kind": "ops_action", "title": "reserve on (operator must not decide)", "action": "enable_energy_reserve"})
    ops_id = ops["data"]["request"]["request_id"]
    assert db.decide(WAYMO_USER, ops_id, "approved")["error"] == "not_your_fleet"   # depot-wide: no fleet
    declined = db.decide(WAYMO_USER, waymo_req, "declined", "we need it on the road")
    assert declined["ok"] and declined["status"] == "declined"
    assert db.decide(SUPERVISOR, waymo_req, "approved")["error"] == "already_declined"
    assert db.decide(SUPERVISOR, note, "approved")["status"] == "acknowledged"
    assert db.decide(SUPERVISOR, ops_id, "declined")["status"] == "declined"


def test_an_approval_goes_through_the_engines_own_door_and_records_its_reply(db, agents):
    h, w = agents["hermes"], agents["waymo"]
    adj = db.call(h, "submit_request", {"kind": "adjustment", "title": "cap at 90", "vehicle_id": W1,
                                        "adjustment": "charge_target", "value": 90})["data"]["request"]["request_id"]
    ops = db.call(h, "submit_request", {"kind": "ops_action", "title": "reserve on",
                                        "action": "enable_energy_reserve"})["data"]["request"]["request_id"]
    rec = db.call(h, "submit_request", {"kind": "recall_vehicle", "title": "bring W1 home",
                                        "vehicle_id": W1})["data"]["request"]["request_id"]
    rec_busy = db.call(w, "submit_request", {"kind": "recall_vehicle", "title": "bring W2 home",
                                             "vehicle_id": W2})["data"]["request"]["request_id"]
    commands_before = db.val("SELECT count(*) FROM ottoq_vehicle_commands")
    params_before = db.val("SELECT count(*) FROM ottoq_policy_params")

    r = db.decide(SUPERVISOR, adj, "approved")
    assert r["status"] == "approved_no_engine_door" and r["engine_door"] is None
    assert db.val("SELECT count(*) FROM ottoq_vehicle_commands") == commands_before
    assert db.val("SELECT count(*) FROM ottoq_policy_params") == params_before

    r = db.decide(MANAGER, ops, "approved", "go")
    assert r["status"] == "applied" and r["engine_door"] == "ottoq_apply_ops_action"
    assert r["engine_reply"]["status"] in ("applied", "no_change")
    # the approval kept the AGENT envelope: the setter recorded an agent actor, not a person
    assert db.val(f"SELECT updated_by FROM ottoq_policy_params WHERE scope_type = 'run' AND scope_id = '{RUN}' "
                  "AND param_key = 'energy_reserve_shave'") == "ottoq_prime:agent_gateway:hermes"

    r = db.decide(SUPERVISOR, rec, "approved")
    assert r["status"] == "applied" and r["engine_reply"]["ok"] is True and r["engine_reply"]["note"] == "queued"
    cmd = db.json(f"SELECT to_jsonb(c) FROM ottoq_vehicle_commands c WHERE c.command_id = '{r['engine_reply']['command_id']}'")
    assert cmd["command_type"] == "begin_charge" and cmd["issued_by"] == "cockpit_recall" and cmd["sim_run_id"] == RUN
    assert cmd["payload"]["actor"].startswith("agent:hermes approved_by:crew:")
    assert rec in cmd["payload"]["reason"]

    r = db.decide(SUPERVISOR, rec_busy, "approved")          # W2 is charging: the door refuses, and says why
    assert r["status"] == "refused_by_engine" and r["engine_reply"]["error"] == "already_returning_or_home"

    mine = db.call(h, "list_requests", {"request_id": rec})
    assert mine["data"]["requests"][0]["status"] == "applied"
    assert mine["data"]["requests"][0]["decided_by"] == {"kind": "crew"}   # the agent sees crew, not a name


def test_closed_requests_are_frozen_and_the_ledgers_refuse_edits(db, agents):
    rid = db.call(agents["tesla"], "send_note", {"title": "to be dismissed"})["data"]["request"]["request_id"]
    assert db.decide(MANAGER, rid, "declined")["ok"]
    for sql in (f"UPDATE ottoq_agent_requests SET decision_note = 'rewritten' WHERE request_id = '{rid}'",
                f"DELETE FROM ottoq_agent_requests WHERE request_id = '{rid}'",
                "DELETE FROM ottoq_agent_call_ledger WHERE call_id = (SELECT max(call_id) FROM ottoq_agent_call_ledger)",
                "UPDATE ottoq_agent_call_ledger SET ok = true WHERE call_id = (SELECT max(call_id) FROM ottoq_agent_call_ledger)",
                "TRUNCATE ottoq_agent_call_ledger",
                "TRUNCATE ottoq_agent_requests CASCADE",
                "UPDATE ottoq_agent_principals SET capabilities = ARRAY['read','note','request_recall','request_adjustment'] WHERE name = 'tesla-agent'",
                "DELETE FROM ottoq_agent_principals WHERE name = 'tesla-agent'"):
        rc, _, err = db.run(sql, check=False)
        assert rc != 0 and ("refused" in err or "immutable" in err or "cannot change" in err or "fixed at issue" in err), (sql, err)
    open_rid = db.call(agents["tesla"], "send_note", {"title": "what I asked"})["data"]["request"]["request_id"]
    rc, _, err = db.run(f"UPDATE ottoq_agent_requests SET title = 'what I did not ask' WHERE request_id = '{open_rid}'", check=False)
    assert rc != 0 and "immutable" in err


def test_a_lapsed_request_reads_expired_and_is_recorded_expired(db, agents):
    rid = db.call(agents["tesla"], "send_note", {"title": "will lapse", "ttl_minutes": 5})["data"]["request"]["request_id"]
    db.run("SET ottoq.agent_ledger_unlock = 'on'; UPDATE ottoq_agent_requests SET created_at = now() - interval '2 hours', "
           f"expires_at = now() - interval '1 hour' WHERE request_id = '{rid}'")
    listed = db.call(agents["tesla"], "list_requests", {"request_id": rid})["data"]["requests"][0]
    assert listed["status"] == "expired" and listed["recorded_status"] == "pending" and listed["lapsed"]
    assert db.decide(SUPERVISOR, rid, "approved")["error"] == "expired"
    assert db.val(f"SELECT status FROM ottoq_agent_requests WHERE request_id = '{rid}'") == "expired"


def test_the_rate_limit_and_revocation_close_the_door(db):
    tok, _ = db.issue("ratey", "personal", ["read", "note"], rate=3, pending=2)
    assert [db.call(tok, "whoami")["http_status"] for _ in range(4)] == [200, 200, 200, 429]
    tok2, _ = db.issue("revoke-me", "personal", ["read", "note"], pending=3)
    open_note = db.call(tok2, "send_note", {"title": "open when revoked"})["data"]["request"]["request_id"]
    rev = db.json("SELECT ottoq_agent_revoke('revoke-me', 'rotated in a test')")
    assert rev["ok"] and rev["open_requests_expired"] == 1
    assert db.call(tok2, "whoami")["http_status"] == 401
    assert db.val(f"SELECT status FROM ottoq_agent_requests WHERE request_id = '{open_note}'") == "expired"
    rc, _, err = db.run("UPDATE ottoq_agent_principals SET status = 'active', revoked_at = NULL, revoked_reason = NULL "
                        "WHERE name = 'revoke-me'", check=False)
    assert rc != 0 and "cannot be undone" in err
    assert db.json("SELECT ottoq_agent_issue_token('revoke-me', 'personal')")["error"] == "name_taken"


def test_the_pending_cap_protects_the_inbox(db):
    tok, _ = db.issue("chatty", "personal", ["read", "note"], pending=2)
    assert db.call(tok, "send_note", {"title": "one"})["http_status"] == 201
    assert db.call(tok, "send_note", {"title": "two"})["http_status"] == 201
    third = db.call(tok, "send_note", {"title": "three"})
    assert third["http_status"] == 429 and third["error"]["code"] == "too_many_pending"


def test_with_no_live_run_nothing_is_pretended(db, agents):
    h = agents["hermes"]
    pending_ops = db.call(h, "submit_request", {"kind": "ops_action", "title": "reserve (run will end)",
                                                "action": "enable_energy_reserve"})["data"]["request"]["request_id"]
    db.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    try:
        assert db.call(h, "depot_status")["data"]["live"] is False
        assert db.call(h, "stall_availability")["data"]["live"] is False
        assert db.call(h, "recent_decisions")["data"]["live"] is False
        refused = db.call(h, "submit_request", {"kind": "ops_action", "title": "x", "action": "enable_energy_reserve"})
        assert refused["http_status"] == 422 and refused["error"]["code"] == "no_live_run"
        r = db.decide(MANAGER, pending_ops, "approved")
        assert r["status"] == "approved_not_applied" and r["engine_door"] is None
        assert r["engine_reply"]["called"] is False
    finally:
        db.run(f"UPDATE ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")


def test_the_inbox_and_the_operator_feed_show_what_each_reader_may_see(db, agents):
    crew = db.json("SELECT ottoq_agent_inbox()", uid=SUPERVISOR)
    assert crew["ok"] and crew["viewer"]["can_decide"] is True and crew["counts"]["total"] > 0
    assert any(i["decided_by"] and "label" in i["decided_by"] for i in crew["items"])
    tech = db.json("SELECT ottoq_agent_inbox()", uid=TECH)
    assert tech["ok"] and tech["viewer"]["can_decide"] is False
    assert db.json("SELECT ottoq_agent_inbox()", uid=OTHER_DEPOT_MANAGER)["error"] == "not_depot_staff"
    assert db.json("SELECT ottoq_agent_inbox()")["error"] == "sign_in_required"
    feed = db.json(f"SELECT ottoq_agent_requests_for_operator('{WAYMO}')", role="anon")
    assert feed["ok"] and feed["can_decide"] is False and feed["items"]
    assert all(i["fleet_operator"]["id"] == WAYMO for i in feed["items"])
    assert all(i["decided_by"] is None or set(i["decided_by"]) == {"kind"} for i in feed["items"])
    bound = db.json(f"SELECT ottoq_agent_requests_for_operator('{WAYMO}')", uid=WAYMO_USER)
    assert bound["can_decide"] is True
    assert db.json("SELECT ottoq_agent_requests_for_operator(NULL)", role="anon")["error"] == "fleet_operator_required"


def test_every_call_is_ledgered_including_the_refusals(db, agents):
    before = int(db.val("SELECT count(*) FROM ottoq_agent_call_ledger"))
    db.call(agents["hermes"], "whoami")
    db.call(agents["hermes"], "vehicle_card", {"vehicle_id": str(uuid.uuid4())})
    db.call("f" * 64, "whoami")
    rows = db.json(f"SELECT jsonb_agg(jsonb_build_object('tool', tool, 'ok', ok, 'status', http_status, 'who', principal_name) "
                   f"ORDER BY call_id) FROM ottoq_agent_call_ledger WHERE call_id > (SELECT max(call_id) - 3 FROM ottoq_agent_call_ledger)")
    assert int(db.val("SELECT count(*) FROM ottoq_agent_call_ledger")) == before + 3
    assert rows == [{"tool": "whoami", "ok": True, "status": 200, "who": "hermes"},
                    {"tool": "vehicle_card", "ok": False, "status": 404, "who": "hermes"},
                    {"tool": "whoami", "ok": False, "status": 401, "who": None}]


def test_the_registry_guard_stays_clean_and_the_requests_outlive_their_run(db, agents):
    assert db.val("SELECT count(*) FROM ottoq_check_run_scope_registry() WHERE severity = 'block' "
                  "OR table_name LIKE 'ottoq_agent%'") == "0"
    assert db.val("SELECT class FROM ottoq_run_scope_registry WHERE table_name = 'ottoq_agent_requests'") == "evidence"
    assert db.val("SELECT count(*) FROM pg_constraint WHERE contype = 'f' AND confrelid = 'ottoq_sim_runs'::regclass "
                  "AND conrelid::regclass::text LIKE 'ottoq_agent%'") == "0"


def test_both_files_classify_themselves_for_the_recert_floor_and_the_dial_floor(db):
    """ottoq_cert_recert_floor() reads COALESCE(forces_recert, TRUE) and 0523's ottoq_dial_pair_floor() reads
    COALESCE(forces_dial_restart, TRUE), each joined to the ledger with any NNNN_ prefix stripped from both sides.
    A missing row, or a NULL in either column, restarts every canon streak or every dial experiment's pair count for a
    change that can move neither -- the class tests/test_migration_hygiene.py records five times. So both columns are
    asserted FALSE here, by the name each file writes, which must be its own stem."""
    for path in (M0559, M0560):
        stem = os.path.splitext(os.path.basename(path))[0]
        row = db.json(f"SELECT jsonb_build_object('recert', forces_recert, 'dial', forces_dial_restart) "
                      f"FROM ottoq_cert_lineage WHERE name = '{stem}'")
        assert row == {"recert": False, "dial": False}, (stem, row)
