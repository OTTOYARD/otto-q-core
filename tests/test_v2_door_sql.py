"""db/migrations/0649-0652, the v2 operator door (contract/README.md), EXECUTED on a stub engine.

WHY THIS EXISTS. The door decides who may speak for which car, takes each event once and in order, and renders what
OTTO-Q asks of a car as a signed contract directive. Each of those is a tenancy or a safety promise, and none of them
is visible to a compile check:

  * a key speaks only for its own fleets' cars at its own depot; another fleet's car reads as not found, and so does a
    car of the same fleet at another depot;
  * an event is taken once (source + id), applied in sequence order per car, late ones stored and never applied over
    newer state, every row timed by the event; a twin key is judged on its run's clock;
  * an ack moves a directive only for the car it names, maps the contract's closed reasons onto the engine's, and
    leaves one signed event; an owner's charge target never comes in through an intent (CLAUDE.md rule 9);
  * a directive renders with its id, version, the one it replaced, an expiry two ticks out and an ack deadline one
    tick out, at the owner's target, never at zero watts, for the key's own fleet only, and it conforms to the
    contract's schemas once signed (contract/ottoq_contract.py checks it);
  * 0652 patches the live walk at md5-guarded anchors, so on a stub it must refuse, and it does; it is executed against
    the live walk inside its own V1 at apply time.

Loads tests/fixtures/v2_door_stub_engine.sql, tests/fixtures/v2_door_seed.sql, then 0649, 0650 and 0651. SKIPS where no
scratch PostgreSQL is reachable, like every *_sql suite.
"""
import hashlib
import json
from datetime import datetime, timezone
import os
import shutil
import subprocess
import sys
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "contract"))
import ottoq_contract as kit  # noqa: E402

STUB = os.path.join(ROOT, "tests", "fixtures", "v2_door_stub_engine.sql")
SEED = os.path.join(ROOT, "tests", "fixtures", "v2_door_seed.sql")
MIG = {n: os.path.join(ROOT, "db", "migrations", f) for n, f in {
    "0649": "0649_source_keys_are_issued_by_the_platform_and_bind_a_depot_and_a_data_source.sql",
    "0650": "0650_the_v2_door_takes_cloudevents_keeps_their_time_drops_duplicates_and_orders_them.sql",
    "0651": "0651_a_directive_leaves_with_an_id_a_version_an_expiry_and_the_depots_signing_key.sql",
    "0652": "0652_the_twin_applies_the_directives_it_is_handed_and_answers_each_with_an_ack.sql",
}.items()}
TWIN = "11111111-1111-1111-1111-111111111111"
WAYMO, TESLA = "22222222-2222-2222-2222-222222222222", "33333333-3333-3333-3333-333333333333"
RUN = "aaaaaaaa-0000-0000-0000-000000000001"
# md5(pg_get_functiondef()) of the live public.ottoq_check_run_scope_registry, read 2026-10-10 ~00:35 UTC
LIVE_REGISTRY_CHECK_MD5 = "4d0011f6bfd5d7448273ccd7c6bcc5dc"


def _conn_args():
    if os.environ.get("PGHOST"):
        return ["-h", os.environ["PGHOST"], "-p", os.environ.get("PGPORT", "5432"), "-U", os.environ.get("PGUSER", "postgres")]
    return ["-h", "/var/tmp", "-p", "55432", "-U", "postgres"]


def _server_up():
    if not shutil.which("psql"):
        return False
    return subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-Atc", "select 1"], capture_output=True).returncode == 0


pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def q(s):
    return "'" + s.replace("'", "''") + "'"


class Db:
    def __init__(self, name):
        self.name = name

    def run(self, sql, check=True):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                           capture_output=True, text=True)
        if check and p.returncode != 0:
            raise AssertionError(f"SQL failed: {p.stderr}\n--- sql ---\n{sql}")
        out = [l for l in p.stdout.splitlines() if l.strip()]
        return p.returncode, (out[-1] if out else ""), p.stderr

    def val(self, sql):
        return self.run(sql)[1]

    def json(self, sql):
        return json.loads(self.val(sql))

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr


def _new_db():
    name = f"ottoq_v2door_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    return Db(name)


def _drop(d):
    subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c", f"DROP DATABASE IF EXISTS {d.name} WITH (FORCE)"],
                   capture_output=True)


@pytest.fixture(scope="module")
def db():
    d = _new_db()
    try:
        for path in (STUB, SEED, MIG["0649"], MIG["0650"], MIG["0651"]):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        d.run(f"INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, run_by, sim_clock_current, tick_interval_seconds, time_scale) "
              f"VALUES ('{RUN}', '{TWIN}', 'running', 'demo', '2026-10-09T14:00:00Z', 30, 60)")
        d.run("UPDATE stalls SET connector_max_kw = CASE WHEN stall_type = 'dcfc' THEN 150 WHEN stall_type = 'l2' THEN 19.2 END")
        yield d
    finally:
        _drop(d)


def issue(db, name, data_source, streams, fleets):
    k = db.json(f"SELECT ottoq_issue_source_key('{TWIN}', 'fleet_api', {q(name)}, {q(data_source)}, "
                f"ARRAY[{','.join(q(s) for s in streams)}]::text[])")
    if fleets:
        db.run(f"SELECT ottoq_scope_source_key('{k['id']}', ARRAY[{','.join(q(f) for f in fleets)}]::uuid[])")
    return hashlib.sha256(k["key"].encode()).hexdigest()


def ev(op, car, typ, seq, data, eid=None, time="2026-10-09T13:59:30Z"):
    return {"specversion": "1.0", "id": eid or f"{op}-{car}-{seq}", "source": f"urn:ottoq:src:{op}:{car}", "subject": car,
            "type": f"com.ottoyard.{typ}", "time": time, "sequence": f"{seq:020d}", "datacontenttype": "application/json",
            "dataschema": f"https://ottoyard.com/schemas/ottoq/contract/0.1/{typ}.json", "data": data}


def now_utc():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def soc(value, ts="2026-10-09T13:59:30Z"):
    return {"signals": {"Vehicle.Powertrain.TractionBattery.StateOfCharge.Current": {"value": value, "ts": ts}}}


def take(db, h, events, dry=False):
    return db.json(f"SELECT ottoq_v2_take_events({q(h)}, {q(json.dumps(events))}::jsonb, {str(dry).lower()})")


# ─────────────────────────────────────────────────────────────────────────────────────── the premises ──

def test_the_copied_registry_check_is_the_live_body(db):
    assert db.val("SELECT md5(pg_get_functiondef('public.ottoq_check_run_scope_registry()'::regprocedure))") == LIVE_REGISTRY_CHECK_MD5


def test_a_second_apply_refuses_before_touching_anything(db):
    for n in ("0650", "0651"):
        rc, err = db.file(MIG[n])
        assert rc != 0 and f"{n} P1" in err, err


def test_0652_refuses_a_walk_it_was_not_written_against(db):
    rc, err = db.file(MIG["0652"])
    assert rc != 0, "0652 applied to a database without the live walk"
    assert "0652 P1" in err or "does not exist" in err, err


def test_the_registry_stays_clean_and_the_new_tables_are_engine_class(db):
    assert db.val("SELECT count(*) FROM ottoq_check_run_scope_registry() WHERE severity = 'block'") == "0"
    assert db.val("SELECT string_agg(table_name || ':' || class, ',' ORDER BY table_name) FROM ottoq_run_scope_registry "
                  "WHERE table_name LIKE 'ottoq_v2_%'") == "ottoq_v2_cursors:engine,ottoq_v2_inbox:engine"


def test_only_the_platform_reaches_the_door(db):
    for f in ("ottoq_v2_take_events(text,jsonb,boolean)", "ottoq_v2_read_directives(text,bigint,integer,boolean)",
              "ottoq_scope_source_key(uuid,uuid[])", "ottoq_v2_signing_key_current()"):
        assert db.val(f"SELECT has_function_privilege('anon', 'public.{f}', 'EXECUTE')") == "f", f
        assert db.val(f"SELECT has_function_privilege('authenticated', 'public.{f}', 'EXECUTE')") == "f", f
        assert db.val(f"SELECT has_function_privilege('service_role', 'public.{f}', 'EXECUTE')") == "t", f
    for t in ("ottoq_v2_inbox", "ottoq_v2_cursors", "ottoq_v2_signing_keys"):
        assert db.val(f"SELECT has_table_privilege('anon', 'public.{t}', 'SELECT')") == "f", t


# ───────────────────────────────────────────────────────────────────────────────────────────── tenancy ──

def test_a_key_speaks_only_for_its_own_fleets_cars_at_its_own_depot(db):
    h = issue(db, "ten-a", "production", ["telemetry"], [WAYMO])
    r = take(db, h, [ev("ten-a", "Waymo-001", "vehicle.telemetry", 1, soc(40)),
                     ev("ten-a", "Tesla-AV-041", "vehicle.telemetry", 1, soc(40)),
                     ev("ten-a", "Waymo-900", "vehicle.telemetry", 1, soc(40)),
                     ev("ten-b", "Waymo-001", "vehicle.telemetry", 2, soc(40))])
    got = [(x["disposition"], x.get("reason")) for x in r["results"]]
    assert got == [("applied", None), ("refused", "vehicle_not_found"), ("refused", "vehicle_not_found"),
                   ("refused", "source_is_not_this_key")], got


def test_a_key_with_no_fleet_or_without_the_stream_is_refused(db):
    h = issue(db, "nofleet", "production", ["telemetry"], [])
    assert take(db, h, [ev("nofleet", "Waymo-001", "vehicle.telemetry", 1, soc(40))])["results"][0]["reason"] == "key_speaks_for_no_fleet"
    h2 = issue(db, "nostream", "production", ["telemetry"], [WAYMO])
    f = ev("nostream", "Waymo-001", "vehicle.fault.summary", 1, {"severity": "low", "category": "other"})
    assert take(db, h2, [f])["results"][0]["reason"] == "stream_not_allowed"
    assert take(db, hashlib.sha256(b"no such key").hexdigest(), [f])["reason"] == "unknown_or_revoked_key"


# ──────────────────────────────────────────────────────────────────────────────────── once, and in order ──

def test_once_in_order_late_never_overwrites_and_rows_carry_the_event_time(db):
    h = issue(db, "ord", "production", ["telemetry"], [WAYMO])
    car, fresh = "Waymo-002", now_utc()   # a production key's clock is the wall clock: a reading must be fresh by it
    r1 = take(db, h, [ev("ord", car, "vehicle.telemetry", 1, soc(41, fresh), time="2026-10-09T10:00:00Z")])
    r_dup = take(db, h, [ev("ord", car, "vehicle.telemetry", 1, soc(41, fresh))])
    r3 = take(db, h, [ev("ord", car, "vehicle.telemetry", 3, soc(63, fresh))])
    r2 = take(db, h, [ev("ord", car, "vehicle.telemetry", 2, soc(12, fresh))])
    assert [r1["results"][0]["disposition"], r_dup["results"][0]["disposition"], r3["results"][0]["disposition"],
            r2["results"][0]["disposition"]] == ["applied", "duplicate", "applied", "late"]
    assert r3["results"][0]["detail"]["gap_before"] == 1
    assert db.val(f"SELECT current_soc FROM vehicles WHERE display_name = '{car}'") == "63"
    assert db.val(f"SELECT packet_at FROM ottoq_telemetry_packets WHERE packet_id = '{r1['results'][0]['detail']['packet_id']}'") \
        == "2026-10-09 10:00:00+00"
    assert db.val("SELECT count(*) FROM ottoq_v2_inbox WHERE source_name = 'ord'") == "3"   # 1, 3 and late 2


def test_a_stale_charge_is_kept_as_a_packet_and_not_put_on_the_car(db):
    h = issue(db, "stale", "production", ["telemetry"], [WAYMO])
    before = db.val("SELECT current_soc FROM vehicles WHERE display_name = 'Waymo-003'")
    r = take(db, h, [ev("stale", "Waymo-003", "vehicle.telemetry", 1, soc(99, ts="2020-01-01T00:00:00Z"))])
    assert r["results"][0]["detail"]["soc"] == "stale"
    assert db.val("SELECT current_soc FROM vehicles WHERE display_name = 'Waymo-003'") == before


def test_a_dry_run_answers_and_keeps_nothing(db):
    h = issue(db, "dry", "production", ["telemetry"], [WAYMO])
    n = db.val("SELECT count(*) FROM ottoq_v2_inbox")
    r = take(db, h, [ev("dry", "Waymo-001", "vehicle.telemetry", 1, soc(50))], dry=True)
    assert r["dry_run"] is True and r["results"][0]["disposition"] == "applied"
    assert db.val("SELECT count(*) FROM ottoq_v2_inbox") == n


def test_a_twin_key_is_judged_on_its_runs_clock(db):
    h = issue(db, "sim-a", "twin", ["telemetry", "arrival", "incident"], [WAYMO])
    r = take(db, h, [ev("sim-a", "Waymo-001", "vehicle.telemetry", 1, soc(77))])
    assert r["sim_run_id"] == RUN and r["clock"].startswith("2026-10-09T14:00:00")
    assert r["results"][0]["detail"]["soc"] == "applied_no_ttl_for_twin"
    pkt = r["results"][0]["detail"]["packet_id"]
    assert db.val(f"SELECT sim_run_id || '|' || sim_clock_at FROM ottoq_telemetry_packets WHERE packet_id = '{pkt}'") \
        == f"{RUN}|2026-10-09 13:59:30+00"


def test_an_intent_signals_a_return_on_the_runs_clock_and_never_sets_a_target(db):
    h = issue(db, "sim-i", "twin", ["arrival"], [WAYMO])
    db.run("UPDATE vehicles SET current_state = 'deployed' WHERE display_name = 'Waymo-003'")
    r = take(db, h, [ev("sim-i", "Waymo-003", "depot.arrival.intent", 1,
                        {"intent_version": 1, "eta": "2026-10-09T14:25:00Z", "predicted_soc_pct": 31, "charge_target_pct": 80})])
    d = r["results"][0]["detail"]
    assert d["eta_min"] == 25.0 and d["marked_en_route"] is True
    assert any("charge_target_pct" in x for x in d["not_applied"])
    assert db.val("SELECT eta_min || '|' || source FROM stub_signals ORDER BY n DESC LIMIT 1") == "25.0|v2:sim-i"


def test_a_fault_summary_writes_a_titled_exception(db):
    h = issue(db, "flt", "production", ["incident"], [WAYMO])
    r = take(db, h, [ev("flt", "Waymo-001", "vehicle.fault.summary", 1,
                        {"severity": "high", "category": "tire_issue", "fault_codes": ["AV-W0010"], "takes_vehicle_offline": True})])
    exc = r["results"][0]["detail"]["exception_id"]
    assert db.val(f"SELECT title || '|' || exception_type || '|' || (metadata->>'takes_vehicle_offline') FROM exceptions WHERE id = '{exc}'") \
        == "Operator fault: tire issue|tire_issue|true"


# ─────────────────────────────────────────────────────────────────────────────────────────────── acks ──

def test_acks_move_only_the_named_cars_directive_and_map_the_closed_reasons(db):
    h = issue(db, "ack", "twin", ["telemetry"], [WAYMO])
    ids = {}
    for name, car in (("acc", "veh1"), ("flt", "veh1"), ("exp", "veh1"), ("other_car", "veh3")):
        ids[name] = db.val(f"INSERT INTO ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at) "
                           f"VALUES ('{RUN}', '{TWIN}', md5('{car}')::uuid, 'begin_charge', '{{}}', '2026-10-09T13:59:00Z') RETURNING command_id")
    def ack(seq, cid, disp, reason=None, detail=None, car="Waymo-001"):
        data = {"directive_id": cid, "directive_version": 1, "disposition": disp, "observed_at": "2026-10-09T14:00:00Z"}
        if reason:
            data["reason"] = reason
        if detail:
            data["detail"] = detail
        return ev("ack", car, "directive.ack", seq, data)
    r = take(db, h, [ack(1, ids["acc"], "accepted"), ack(2, ids["flt"], "unable", "charger_fault", "would not latch"),
                     ack(3, ids["exp"], "unable", "expired"), ack(4, ids["other_car"], "accepted"),
                     ack(5, ids["acc"], "rejected", "other")])
    got = [(x["disposition"], x.get("reason") or x.get("detail", {}).get("status")) for x in r["results"]]
    assert got == [("applied", "confirmed"), ("applied", "refused"), ("applied", "expired"),
                   ("refused", "directive_not_found"), ("refused", "ack_disposition_or_reason")], got
    row = db.val(f"SELECT status || '|' || reason_code || '|' || (payload->'ack'->>'reason') || '|' || confirmed_by "
                 f"FROM ottoq_vehicle_commands WHERE command_id = '{ids['flt']}'")
    assert row == "refused|resource_faulted|charger_fault|operator:ack"
    assert db.val(f"SELECT status FROM ottoq_vehicle_commands WHERE command_id = '{ids['other_car']}'") == "issued"
    assert db.val("SELECT count(*) FROM stub_events WHERE event_type = 'directive.ack' AND actor_type = 'oem_dispatch_webhook' "
                  "AND actor_id = 'ack' AND data_source = 'twin'") == "3"


# ──────────────────────────────────────────────────────────────────────────────────────── directives out ──

def test_directives_render_for_the_keys_own_fleet_and_conform_to_the_contract_once_signed(db):
    db.run(f"""
      INSERT INTO ottoq_ocpp_chargers VALUES (md5('chg1')::uuid, '{TWIN}', 'NASH-DCFC-01', 'Available');
      UPDATE stalls SET ocpp_charger_id = md5('chg1')::uuid WHERE stall_code = 'NASH-STALL-001';
      INSERT INTO ottoq_stall_bookings (booking_id, sim_run_id, stall_id, vehicle_id, purpose, during, state)
      VALUES (md5('bk1')::uuid, '{RUN}', md5('stall150')::uuid, md5('veh2')::uuid, 'wash',
              tstzrange('2026-10-09T14:05:00Z', '2026-10-09T14:20:00Z'), 'held');
      INSERT INTO ottoq_vehicle_commands (command_id, sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, status, confirmed_by)
      VALUES
       (md5('o1')::uuid, '{RUN}', '{TWIN}', md5('veh1')::uuid, 'begin_charge', jsonb_build_object('stall_id', md5('stall1')::uuid, 'requested_kw', '150'), '2026-10-09T13:30:00Z', 'issued', NULL),
       (md5('o2')::uuid, '{RUN}', '{TWIN}', md5('veh1')::uuid, 'proceed_to_stall', jsonb_build_object('stall_id', md5('stall60')::uuid), '2026-10-09T13:31:00Z', 'issued', NULL),
       (md5('o3')::uuid, '{RUN}', '{TWIN}', md5('veh2')::uuid, 'enter_wash', jsonb_build_object('stall_id', md5('stall150')::uuid, 'booking_id', md5('bk1')::uuid), '2026-10-09T13:32:00Z', 'issued', NULL),
       (md5('o4')::uuid, '{RUN}', '{TWIN}', md5('veh2')::uuid, 'dispatch', '{{"soc":89}}', '2026-10-09T13:33:00Z', 'issued', NULL),
       (md5('o5')::uuid, '{RUN}', '{TWIN}', md5('veh5')::uuid, 'begin_charge', jsonb_build_object('stall_id', md5('stall20')::uuid, 'requested_kw', '19.2'), '2026-10-09T13:34:00Z', 'refused', 'otto_q_preflight'),
       (md5('o6')::uuid, '{RUN}', '{TWIN}', md5('veh3')::uuid, 'begin_charge', jsonb_build_object('stall_id', md5('stall21')::uuid, 'requested_kw', '19.2'), '2026-10-09T13:35:00Z', 'issued', NULL),
       (md5('o7')::uuid, '{RUN}', '{TWIN}', md5('veh5')::uuid, 'begin_charge', jsonb_build_object('stall_id', md5('stall22')::uuid, 'requested_kw', '0'), '2026-10-09T13:36:00Z', 'issued', NULL)
    """)
    h = issue(db, "out-a", "twin", ["telemetry"], [WAYMO])
    after = int(db.val(f"SELECT command_seq - 1 FROM ottoq_vehicle_commands WHERE command_id = md5('o1')::uuid"))
    r = db.json(f"SELECT ottoq_v2_read_directives({q(h)}, {after}, 100, true)")
    by_id = {e["data"]["directive_id"]: e for e in r["events"]}
    o = {k: db.val(f"SELECT md5('{k}')::uuid") for k in ("o1", "o2", "o3", "o4", "o5", "o6", "o7")}
    # the dispatch, the pre-flight refusal, another fleet's car and a zero-watt plan never leave
    assert set(by_id) == {o["o1"], o["o2"], o["o3"]}, sorted(by_id)
    assert {e["subject"] for e in r["events"]} <= {"Waymo-001", "Waymo-002", "Waymo-003"}
    plan = by_id[o["o1"]]["data"]
    assert plan["target_soc_pct"] == 100 and plan["charging_schedule"]["periods"][0]["limit"] == 150000
    assert plan["evse_id"] == "NASH-DCFC-01"
    assert (plan["issued_at"], plan["ack_deadline"], plan["expires_at"]) == (
        "2026-10-09T13:30:00.000000Z", "2026-10-09T14:00:00.000000Z", "2026-10-09T14:30:00.000000Z")
    assert by_id[o["o2"]]["data"]["supersedes"] == {"directive_id": o["o1"], "version": 1}
    wash = by_id[o["o3"]]["data"]
    assert wash["purpose"] == "service" and wash["window"] == {"start": "2026-10-09T14:05:00.000000Z", "end": "2026-10-09T14:20:00.000000Z"}
    # every one conforms to the contract once signed, and the signature verifies
    v, key, keys = kit.envelope_validator(), kit.example_key(), kit.public_keys(kit.example_jwks())
    for e in r["events"]:
        e["ottoqsig"] = kit.sign(e, key, kit.EXAMPLE_KID)
        assert kit.problems(e, v) == [], (e["type"], kit.problems(e, v))
        assert kit.verify(e, keys) == kit.EXAMPLE_KID
    # first read marks them; a peek would not have
    assert db.val(f"SELECT count(*) FROM ottoq_vehicle_commands WHERE delivered_to = 'v2:out-a'") == "3"
    assert db.val(f"SELECT count(*) FROM ottoq_vehicle_commands WHERE command_id IN ('{o['o4']}', '{o['o6']}') AND delivered_at IS NOT NULL") == "0"
    assert r["next_after"] == int(db.val(f"SELECT max(command_seq) FROM ottoq_vehicle_commands WHERE vehicle_id IN "
                                         f"(SELECT id FROM vehicles WHERE fleet_operator_id = '{WAYMO}')"))


def test_the_signing_key_store_keeps_one_active_key_and_publishes_only_its_public_half(db):
    x, d = "C" * 43, "D" * 43
    s1 = db.json(f"SELECT ottoq_v2_signing_key_store('depot-k1', '{{\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"x\":\"{x}\"}}', "
                 f"'{{\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"x\":\"{x}\",\"d\":\"{d}\"}}')")
    s2 = db.json(f"SELECT ottoq_v2_signing_key_store('depot-k2', '{{\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"x\":\"{x}\"}}', "
                 f"'{{\"kty\":\"OKP\",\"crv\":\"Ed25519\",\"x\":\"{x}\",\"d\":\"{d}\"}}')")
    assert s1 == {"stored": True, "kid": "depot-k1"} and s2 == {"stored": False, "kid": "depot-k1"}
    assert db.json("SELECT ottoq_v2_signing_key_current()")["private_jwk"]["d"] == d
    jw = db.json("SELECT ottoq_v2_jwks()")
    assert [k["kid"] for k in jw["keys"]] == ["depot-k1"] and "d" not in jw["keys"][0]
    rc, _, err = db.run(f"SELECT ottoq_v2_signing_key_store('bad', '{{\"kty\":\"RSA\"}}', '{{}}')", check=False)
    assert rc == 0, err   # an active key exists: a later call names it and stores nothing, whatever it carries
