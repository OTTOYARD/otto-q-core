"""db/migrations/0653, the twin as two operators (sim-a, sim-b), EXECUTED on a stub engine.

WHY THIS EXISTS. Step 4 of the twin data contract review: "The twin publishes and receives only through the v2 door,
as two synthetic operators. Acks stop happening inside OTTO-Q's transaction. An automated test proves sim-a never
sees sim-b." This is that test, and the promises around it:

  * sim-a speaks for Waymo Nashville and sim-b for Tesla Robotaxi TN and Zoox Southeast, each through its own twin key;
  * sim-a never sees sim-b: the outbox gives each only its own fleets' directives, an event or ack about the other's car
    reads as not found, an ack naming the other's directive is refused, and ottoq_assert_operator_isolation finds
    nothing to report after a mixed step while having judged something for both;
  * the world is shared and the operators are channels: one walk serves both in the walk's own order, so a stall two
    operators' cars were both sent to goes by that order, not by which operator spoke first;
  * every ack the twin sends is a CloudEvent that conforms to contract/schemas;
  * when the walk reports instead of writing (0654), the engine learns each outcome only from the ack: the command is
    confirmed or refused under the operator's own name, with a directive.ack event;
  * the run pin: only the step names the run a twin key is judged on.

Loads tests/fixtures/v2_door_stub_engine.sql, tests/fixtures/v2_door_seed.sql, 0649-0651, checks 0652 refuses, then
tests/fixtures/v2_twin_operators_stub.sql and 0653, and checks 0654 refuses (it patches the live tick path). SKIPS where
no scratch PostgreSQL is reachable.
"""
import json
import os
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
sys.path.insert(0, os.path.join(ROOT, "contract"))
import ottoq_contract as kit  # noqa: E402
from test_v2_door_sql import MIG, SEED, STUB, TWIN, WAYMO, TESLA, Db, _drop, _new_db, _server_up, q  # noqa: E402

ZOOX = "44444444-4444-4444-4444-444444444444"
OPS_STUB = os.path.join(ROOT, "tests", "fixtures", "v2_twin_operators_stub.sql")
MIG["0653"] = os.path.join(ROOT, "db", "migrations", "0653_the_twin_speaks_to_otto_q_as_two_operators.sql")
MIG["0654"] = os.path.join(ROOT, "db", "migrations",
                           "0654_the_walk_reports_to_the_twin_and_the_ticks_let_its_operators_answer_first.sql")
MIG["0655"] = os.path.join(ROOT, "db", "migrations",
                           "0655_the_finalizer_leaves_a_directive_its_operator_answered_as_it_was_answered.sql")
MIG["0657"] = os.path.join(ROOT, "db", "migrations", "0657_the_readiness_check_is_the_last_thing_a_visit_does.sql")
MIG["0659"] = os.path.join(ROOT, "db", "migrations",
                           "0659_the_twins_chargers_can_be_depot_grade_and_the_research_wing_measures_it.sql")
MIG["0690"] = os.path.join(ROOT, "db", "migrations", "0690_the_dispatch_ledger_counts_the_miles_the_car_drove.sql")
RUN = "cccccccc-0000-0000-0000-00000000000c"
CLOCK = "2026-10-09T15:00:00Z"

pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture(scope="module")
def db():
    d = _new_db()
    try:
        for path in (STUB, SEED, MIG["0649"], MIG["0650"], MIG["0651"]):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        rc, err = d.file(MIG["0652"])
        assert rc != 0, "0652 applied on the stub"
        for path in (OPS_STUB, MIG["0653"]):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        d.run("UPDATE stalls SET connector_max_kw = CASE WHEN stall_type = 'dcfc' THEN 150 WHEN stall_type = 'l2' THEN 19.2 END")
        # one more car for each side, so a step carries several cars per operator
        d.run(f"""INSERT INTO vehicles (id, fleet_operator_id, home_depot_id, current_depot_id, display_name, current_state, current_soc)
                  VALUES (md5('veh-t2')::uuid, '{TESLA}', '{TWIN}', '{TWIN}', 'Tesla-RT-006', 'arrived_at_gate', 40),
                         (md5('veh-z2')::uuid, '{ZOOX}', '{TWIN}', '{TWIN}', 'Zoox-AV-100', 'arrived_at_gate', 40)""")
        d.run("UPDATE vehicles SET current_state = 'arrived_at_gate' WHERE home_depot_id = '" + TWIN + "'")
        d.run(f"INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, run_by, started_at, sim_clock_current, tick_interval_seconds, time_scale) "
              f"VALUES ('{RUN}', '{TWIN}', 'running', 'operator_demo', now(), '{CLOCK}', 30, 60)")
        yield d
    finally:
        _drop(d)


def key_hash(db, name):
    return db.val(f"SELECT k.key_hash FROM twin.ottoq_twin_operators o JOIN ottow_api_keys k ON k.id = o.key_id WHERE o.source_name = {q(name)}")


def car(db, ref):
    return db.val(f"SELECT id FROM vehicles WHERE display_name = {q(ref)} AND home_depot_id = '{TWIN}'")


def stall(db, n):
    return db.val(f"SELECT md5('stall{n}')::uuid")


def cmd(db, ref, stall_n, issued=CLOCK, ctype="proceed_to_stall"):
    return db.val(f"INSERT INTO ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at) "
                  f"VALUES ('{RUN}', '{TWIN}', '{car(db, ref)}', {q(ctype)}, jsonb_build_object('stall_id', '{stall(db, stall_n)}'::uuid), "
                  f"{q(issued)}) RETURNING command_id")


def step(db):
    return db.json(f"SELECT twin.ottoq_twin_operator_step('{RUN}')")


def ack_ev(op, ref, seq, directive_id, eid):
    return {"specversion": "1.0", "id": eid, "source": f"urn:ottoq:src:{op}:{ref}", "subject": ref,
            "type": "com.ottoyard.directive.ack", "time": CLOCK, "sequence": f"{seq:020d}", "datacontenttype": "application/json",
            "dataschema": "https://ottoyard.com/schemas/ottoq/contract/0.1/directive.ack.json",
            "data": {"directive_id": directive_id, "directive_version": 1, "disposition": "accepted", "observed_at": CLOCK}}


# ─────────────────────────────────────────────────────────────────────────────────────── the operators ──

def test_0653_applied_and_its_own_probe_passed(db):
    assert db.val("SELECT count(*) FROM ottoq_cert_lineage WHERE name = '0653_the_twin_speaks_to_otto_q_as_two_operators' "
                  "AND NOT forces_recert") == "1"


def test_sim_a_and_sim_b_are_twin_keys_scoped_to_their_own_fleets(db):
    rows = db.val("SELECT string_agg(o.source_name || '=' || k.data_source || ':' || array_to_string(k.fleet_operator_ids, '+'), ' ' "
                  "ORDER BY o.source_name) FROM twin.ottoq_twin_operators o JOIN ottow_api_keys k ON k.id = o.key_id WHERE k.is_active")
    assert rows == f"sim-a=twin:{WAYMO} sim-b=twin:{TESLA}+{ZOOX}"


def test_a_second_apply_refuses_before_touching_anything(db):
    rc, err = db.file(MIG["0653"])
    assert rc != 0 and "0653 P1" in err, err


def test_0654_refuses_tick_paths_it_was_not_written_against(db):
    # 0654 patches the live walk and four tick drivers at md5-guarded anchors; on the stub it must refuse and change
    # nothing. Its report mode is what stub_walk_mode.reports stands in for; it runs against the live walk in 0654's V1.
    rc, err = db.file(MIG["0654"])
    assert rc != 0, "0654 applied on the stub"
    assert db.val("SELECT count(*) FROM ottoq_cert_lineage WHERE name LIKE '0654%'") == "0"


def test_0655_refuses_a_finalizer_it_was_not_written_against(db):
    # 0655 patches the live run finalizer at an md5-guarded anchor and is written after 0654; on the stub it must refuse
    # at its premises and change nothing. That the finalizer keeps an operator's answer is proved on the live finalizer
    # in 0655's own V1.
    rc, err = db.file(MIG["0655"])
    assert rc != 0 and "0655 P1" in err, err
    assert db.val("SELECT count(*) FROM ottoq_cert_lineage WHERE name LIKE '0655%'") == "0"


def test_0657_refuses_a_visit_advancer_it_was_not_written_against(db):
    # 0657 patches the live visit-atom advancer at an md5-guarded anchor so a readiness check closes only after the
    # visit's other work (FINDINGS G398); on the stub it must refuse at its premises and change nothing. That the check
    # waits for a pending charge and closes in the pass the last work ends is proved on the live advancer in 0657's V1.
    rc, err = db.file(MIG["0657"])
    assert rc != 0 and "0657 P1" in err, err
    assert db.val("SELECT count(*) FROM ottoq_cert_lineage WHERE name LIKE '0657%'") == "0"


def test_0659_refuses_out_of_order_and_changes_nothing(db):
    # 0659 adds the depot-grade charger dial and patches the live fault card at md5-guarded anchors; it is written after
    # 0658, so on the stub it must refuse at its premises and leave no dial, plan or lineage row. That the card is byte
    # for byte the same with the dial unset, and scaled at 1, is proved on the live fault card in 0659's own V1.
    rc, err = db.file(MIG["0659"])
    assert rc != 0 and "0659 P1" in err, err
    assert db.val("SELECT count(*) FROM ottoq_cert_lineage WHERE name LIKE '0659%'") == "0"


def test_0690_refuses_out_of_order_and_changes_nothing(db):
    # 0690 patches the live deployed-telemetry step at md5-guarded anchors so a dispatch accrues each tick's miles
    # (FINDINGS G406); it is written after 0659, so on the stub it must refuse at its premises and leave no lineage row.
    # That each tick adds exactly its packet's speed x its minutes, and the close keeps the total, is proved on the live
    # step in 0690's own V1.
    rc, err = db.file(MIG["0690"])
    assert rc != 0 and "0690 P1" in err, err
    assert db.val("SELECT count(*) FROM ottoq_cert_lineage WHERE name LIKE '0690%'") == "0"


def test_only_the_platform_reaches_the_operators(db):
    for f in ("twin.ottoq_twin_operator_step(uuid)", "public.ottoq_assert_operator_isolation(uuid)",
              "public.ottoq_api_twin_apply_directives(uuid,timestamptz,jsonb)"):
        assert db.val(f"SELECT has_function_privilege('anon', {q(f)}, 'EXECUTE')") == "f", f
        assert db.val(f"SELECT has_function_privilege('service_role', {q(f)}, 'EXECUTE')") == "t", f
    assert db.val("SELECT count(*) FROM ottoq_check_run_scope_registry() WHERE severity = 'block'") == "0"
    assert db.val("SELECT string_agg(table_name, ',' ORDER BY table_name) FROM ottoq_run_scope_registry "
                  "WHERE table_schema = 'twin' AND class = 'engine'") == \
        "ottoq_twin_operator_log,ottoq_twin_operator_sequences,ottoq_twin_operator_state"


# ───────────────────────────────────────────────────────────────────────── sim-a never sees sim-b ──

def test_the_outbox_gives_each_operator_only_its_own_fleets_directives(db):
    ids = {ref: cmd(db, ref, n) for ref, n in (("Waymo-001", 60), ("Tesla-AV-041", 61), ("Zoox-001", 62), ("Waymo-002", 63))}
    seen = {}
    for op in ("sim-a", "sim-b"):   # no pin: the depot's one running run
        r = db.json(f"SELECT ottoq_v2_read_directives({q(key_hash(db, op))}, 0, 500, false)")
        assert r["sim_run_id"] == RUN, r
        seen[op] = {e["data"]["directive_id"] for e in r["events"]}
    assert seen["sim-a"] == {ids["Waymo-001"], ids["Waymo-002"]}
    assert seen["sim-b"] == {ids["Tesla-AV-041"], ids["Zoox-001"]}
    db.run(f"UPDATE ottoq_vehicle_commands SET status = 'expired' WHERE command_id IN ({','.join(q(i) for i in ids.values())})")


def test_an_ack_about_the_other_operators_car_or_directive_is_refused(db):
    b_cmd = cmd(db, "Tesla-AV-041", 70)
    a_hash = key_hash(db, "sim-a")
    r = db.json(f"SELECT ottoq_v2_take_events({q(a_hash)}, {q(json.dumps([ack_ev('sim-a', 'Tesla-AV-041', 1, b_cmd, 'x-1'), ack_ev('sim-a', 'Waymo-001', 1, b_cmd, 'x-2')]))}::jsonb, false)")
    assert [(x["disposition"], x.get("reason")) for x in r["results"]] == [("refused", "vehicle_not_found"), ("refused", "directive_not_found")]
    assert db.val(f"SELECT status FROM ottoq_vehicle_commands WHERE command_id = '{b_cmd}'") == "issued"
    db.run(f"UPDATE ottoq_vehicle_commands SET status = 'expired' WHERE command_id = '{b_cmd}'")


# ──────────────────────────────────────────────────────────────── the step, with the walk reporting ──

def test_the_step_serves_both_operators_in_one_walk_and_the_engine_learns_only_from_acks(db):
    db.run("UPDATE stub_walk_mode SET reports = true")
    try:
        # a Tesla car and a Waymo car sent to the SAME stall: the earlier one gets it, whichever operator speaks first
        t_first = cmd(db, "Tesla-RT-006", 80, issued="2026-10-09T14:59:00Z")
        w_second = cmd(db, "Waymo-003", 80, issued=CLOCK)
        a_own = cmd(db, "Waymo-002", 81)
        z_own = cmd(db, "Zoox-AV-100", 82)
        s = step(db)
        # 9 read: these 4, and 5 the tests above sent and then closed, which are answered already and get no ack
        assert s["ok"] and s["directives"] == 9, s
        assert s["operators"]["sim-a"]["acks"] == 2 and s["operators"]["sim-b"]["acks"] == 2, s
        assert s["operators"]["sim-a"]["already_answered"] == 2 and s["operators"]["sim-b"]["already_answered"] == 3, s
        assert s["operators"]["sim-a"]["not_applied"] == 0 and s["operators"]["sim-b"]["not_applied"] == 0, s
        rows = {i: db.val(f"SELECT status || '|' || COALESCE(reason_code, '-') || '|' || confirmed_by || '|' || COALESCE(payload->'ack'->>'reason', '-') "
                          f"FROM ottoq_vehicle_commands WHERE command_id = '{i}'") for i in (t_first, w_second, a_own, z_own)}
        assert rows[t_first] == "confirmed|-|operator:sim-b|-", rows
        assert rows[w_second] == "refused|target_occupied|operator:sim-a|occupied", rows
        assert rows[a_own] == "confirmed|-|operator:sim-a|-" and rows[z_own] == "confirmed|-|operator:sim-b|-", rows
        # the world moved the cars; the engine's rows moved only by the acks, each with its own event
        assert db.val(f"SELECT current_vehicle_id FROM stalls WHERE id = '{stall(db, 80)}'") == car(db, "Tesla-RT-006")
        assert db.val(f"SELECT count(*) FROM ottoq_events WHERE event_type = 'directive.ack' AND sim_run_id = '{RUN}' "
                      f"AND actor_type = 'oem_dispatch_webhook' AND data_source = 'twin'") == "4"
        assert db.val(f"SELECT string_agg(source_name || ':' || outcome, ',' ORDER BY source_name, outcome) FROM twin.ottoq_twin_operator_log "
                      f"WHERE sim_run_id = '{RUN}' AND command_id IN ('{t_first}', '{w_second}', '{a_own}', '{z_own}')") == \
            "sim-a:executed,sim-a:refused,sim-b:executed,sim-b:executed"
        # a second step reads nothing new and answers nothing twice
        s2 = step(db)
        assert s2["directives"] == 0 and s2["operators"]["sim-a"]["acks"] == 0 and s2["operators"]["sim-b"]["acks"] == 0, s2
    finally:
        db.run("UPDATE stub_walk_mode SET reports = false")


def test_every_ack_the_twin_sent_conforms_to_the_contract(db):
    events = db.json(f"SELECT COALESCE(jsonb_agg(event ORDER BY inbox_id), '[]') FROM ottoq_v2_inbox WHERE sim_run_id = '{RUN}' "
                     f"AND source_name IN ('sim-a', 'sim-b') AND ce_type = 'com.ottoyard.directive.ack'")
    assert len(events) >= 4
    v = kit.envelope_validator()
    for e in events:
        assert kit.problems(e, v) == [], (e["id"], kit.problems(e, v))
    # per car, the operator numbered its events in order
    seqs = {}
    for e in events:
        seqs.setdefault(e["source"], []).append(int(e["sequence"]))
    assert all(s == sorted(s) and len(set(s)) == len(s) for s in seqs.values()), seqs


def test_the_isolation_check_finds_nothing_and_judged_both_operators(db):
    rows = db.json(f"SELECT jsonb_agg(to_jsonb(i)) FROM ottoq_assert_operator_isolation('{RUN}') i")
    assert sum(r["violations"] for r in rows) == 0, rows
    for op in ("sim-a", "sim-b"):
        judged = {r["check_name"]: r["rows_seen"] for r in rows if r["source_name"] == op}
        for check in ("directive_delivered", "event_taken", "directive_answered", "command_confirmed_by_operator", "ack_event_recorded"):
            assert judged[check] > 0, (op, check, judged)


def test_the_isolation_check_reports_a_crossed_delivery(db):
    # sanity: the check is not blind. Pretend sim-a had been handed a Tesla directive.
    x = cmd(db, "Tesla-AV-041", 90)
    db.run(f"UPDATE ottoq_vehicle_commands SET delivered_to = 'v2:sim-a', status = 'expired' WHERE command_id = '{x}'")
    rows = db.json(f"SELECT jsonb_agg(to_jsonb(i)) FROM ottoq_assert_operator_isolation('{RUN}') i WHERE violations > 0")
    assert rows and rows[0]["check_name"] == "directive_delivered" and rows[0]["source_name"] == "sim-a" and x in rows[0]["sample"]
    db.run(f"UPDATE ottoq_vehicle_commands SET delivered_to = NULL WHERE command_id = '{x}'")


def test_the_handshake_counts_an_operators_ack_as_external(db):
    row = db.json("SELECT to_jsonb(h) FROM ottoq_command_handshake h WHERE data_source = 'twin'")
    confirmed_by_ops = int(db.val("SELECT count(*) FROM ottoq_vehicle_commands WHERE confirmed_by LIKE 'operator:sim-%'"))
    assert confirmed_by_ops > 0 and row["acked_by_asset"] >= confirmed_by_ops, row


# ───────────────────────────────────────────────────────────────────────────────────────────── the pin ──

def test_only_the_step_names_the_run_a_twin_key_is_judged_on(db):
    other = "dddddddd-0000-0000-0000-00000000000d"
    db.run(f"INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, run_by, started_at, sim_clock_current, tick_interval_seconds, time_scale) "
           f"VALUES ('{other}', '{TWIN}', 'running', 'operator_demo', now() + interval '1 minute', '2026-10-09T18:00:00Z', 30, 60)")
    try:
        h = key_hash(db, "sim-a")
        e = [ack_ev("sim-a", "Waymo-001", 999, "00000000-0000-0000-0000-000000000000", "pin-1")]
        unpinned = db.json(f"SELECT ottoq_v2_take_events({q(h)}, {q(json.dumps(e))}::jsonb, true)")
        pinned = db.json(f"SELECT set_config('ottoq.v2_twin_run', '{RUN}', false); "
                         f"SELECT ottoq_v2_take_events({q(h)}, {q(json.dumps(e))}::jsonb, true)")
        assert unpinned["sim_run_id"] == other and pinned["sim_run_id"] == RUN
    finally:
        db.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{other}'")
