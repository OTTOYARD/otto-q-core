"""bridge/proposer_bridge.py -- the pure half, tested without a database.

The frame is the production contract shape (ottoq_build_decision_frame: vehicles
with id/state/soc/inlet_type/inlet_max_kw/target_soc/vehicle_class_code; stalls
with id/type/status/connector_type/connector_max_kw/supported_inlet_types), the
class rows are the SELECT_VEHICLE_CLASSES shape, and every id is a uuid because
the emitter refuses anything else -- the door casts to uuid and a fixture that
passed 'v-1' would prove nothing about the SQL that actually runs.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from bridge import proposer_bridge as pb  # noqa: E402

RUN = "0a7d4569-888b-4633-a919-dbc4b8adca29"
DEPOT = "11111111-1111-1111-1111-111111111111"
V1 = "6e7d0b1c-0000-4000-8000-000000000001"
V2 = "6e7d0b1c-0000-4000-8000-000000000002"
V3 = "6e7d0b1c-0000-4000-8000-000000000003"
S1 = "5a11a000-0000-4000-8000-000000000001"
S2 = "5a11a000-0000-4000-8000-000000000002"
S3 = "5a11a000-0000-4000-8000-000000000003"

SITE = json.loads((HERE / "sites" / "nashville-flagship.json").read_text())

#: SELECT_VEHICLE_CLASSES rows as PostgREST would hand them back (numerics as
#: strings), so the projection's coercion is on the path too.
CLASS_ROWS = [
    {"vehicle_class_code": "waymo_jaguar_ipace_2024", "battery_capacity_kwh": "90",
     "max_charge_rate_kw": "100", "charge_kinds": ["dcfc", "l2"],
     "energy_curve": [{"above_soc_pct": 0, "accept_frac": 1.0},
                      {"above_soc_pct": 70, "accept_frac": 0.6},
                      {"above_soc_pct": 85, "accept_frac": 0.35}],
     "battery_chemistry": "NMC"},
    {"vehicle_class_code": "generic_av_l2", "battery_capacity_kwh": "100",
     "max_charge_rate_kw": "19", "charge_kinds": ["l2"],
     "energy_curve": [{"above_soc_pct": 0, "accept_frac": 1.0}],
     "battery_chemistry": "NMC"},
]


def _vehicle(vid, *, soc=30, state="arrived_at_gate", cls="waymo_jaguar_ipace_2024",
             inlet="CCS1", kw=100.0):
    return {"id": vid, "state": state, "soc": soc, "stall_id": None,
            "inlet_type": inlet, "inlet_max_kw": kw, "fleet_operator_id": None,
            "make": "Jaguar", "platform": "waymo", "svc_step": None,
            "target_soc": 90, "min_soc_threshold": 20, "vehicle_class_code": cls}


def _stall(sid, *, kind="dcfc", kw=150):
    return {"id": sid, "type": kind, "status": "available", "vehicle_id": None,
            "connector_type": "Multi", "connector_max_kw": kw,
            "supported_inlet_types": ["CCS1", "NACS"]}


def _frame(vehicles=None, stalls=None):
    return {
        "vehicles": vehicles if vehicles is not None else
                    [_vehicle(V1, soc=25), _vehicle(V2, soc=40),
                     _vehicle(V3, soc=30, cls="generic_av_l2", kw=19.0)],
        "stalls": stalls if stalls is not None else
                  [_stall(S1), _stall(S2), _stall(S3, kind="l2", kw=19)],
        "sessions": [], "energy": None, "bess": None,
    }


def _fire(**kw):
    return pb.fire(_frame(), CLASS_ROWS, site=SITE, sim_run_id=RUN, depot_id=DEPOT,
                   fired_at="2026-09-12T17:00:00+00:00", **kw)


# ---- fire() -------------------------------------------------------------------

def test_fire_produces_one_door_shaped_row_per_serviceable_vehicle():
    r = _fire()
    rows, rec = r["rows"], r["fire"]
    assert rec["status"] == "proposed"
    assert {row["entity_id"] for row in rows} == {V1, V2, V3}
    for row in rows:
        assert row["source"] == "forward_lex"
        assert row["action_context"] == "stall_assignment"
        assert row["entity_type"] == "vehicle"
        p = row["proposal"]
        assert p["verb"] == "assign_stall"
        assert p["resolved_action_context"] == "stall_assignment"
        assert p["rationale"]["optimizer"] == "forward_lex"
        if not p["abstain"]:
            assert p["stall_id"] in {S1, S2, S3}
            assert p["stall_type"] in {"dcfc", "l2"}
            assert p["requested_kw"] > 0
    assert rec["n_rows"] == 3
    assert rec["n_planned"] + rec["n_abstained"] == 3
    assert rec["n_vehicles"] == 3 and rec["n_in_serviceable_state"] == 3
    assert rec["frame_hash"].startswith("sha256:")
    assert rec["solver"]["optimizer"] == "forward_lex"
    assert rec["source"] == "forward_lex"


def test_the_l2_only_class_is_never_sent_to_a_dcfc_point():
    # The whole plan: every vehicle is due, and V3 (l2-only, 19 kW) is on S3.
    rows = _fire(start_within_min=10**6)["rows"]
    v3 = next(r for r in rows if r["entity_id"] == V3)
    assert v3["proposal"]["abstain"] is False
    assert v3["proposal"]["stall_type"] == "l2"
    assert v3["proposal"]["stall_id"] == S3
    # Under the default window the peak-minimising pass staggers V3 behind V1,
    # so its row is a not-due abstain -- and the stall it names is still S3.
    rows = _fire()["rows"]
    v3 = next(r for r in rows if r["entity_id"] == V3)
    if v3["proposal"]["abstain"]:
        assert v3["proposal"]["rationale"]["abstained_by"] == "bridge:not_due"
        assert v3["proposal"]["rationale"]["planned_stall_id"] == S3
    else:
        assert v3["proposal"]["stall_id"] == S3
    for r in rows:
        assert r["proposal"].get("stall_id") != S3 or r["entity_id"] == V3


def test_two_fires_on_one_frame_are_byte_identical():
    a, b = _fire(), _fire()
    assert a["rows"] == b["rows"]
    assert a["fire"] == b["fire"]


def test_frame_hash_ignores_key_order_and_whitespace():
    f1 = _frame()
    f2 = json.loads(json.dumps(f1, indent=3))
    f2["vehicles"][0] = dict(reversed(list(f2["vehicles"][0].items())))
    assert pb.content_hash(f1) == pb.content_hash(f2)
    f3 = _frame(); f3["vehicles"][0]["soc"] = 26
    assert pb.content_hash(f1) != pb.content_hash(f3)


def test_offline_vehicles_are_an_empty_fire_not_an_error():
    frame = _frame(vehicles=[_vehicle(V1, state="offline"),
                             _vehicle(V2, state="deployed")])
    r = pb.fire(frame, CLASS_ROWS, site=SITE, sim_run_id=RUN, depot_id=DEPOT)
    assert r["rows"] == []
    assert r["fire"]["status"] == "empty"
    assert r["fire"]["n_vehicles"] == 2
    assert r["fire"]["n_in_serviceable_state"] == 0
    assert r["fire"]["note"] == "no plannable vehicles in frame"


def test_a_frame_with_no_charge_capable_stall_is_recorded_not_raised():
    frame = _frame(stalls=[{"id": S1, "type": "staging", "status": "available",
                            "vehicle_id": None, "connector_type": None,
                            "connector_max_kw": None, "supported_inlet_types": None}])
    r = pb.fire(frame, CLASS_ROWS, site=SITE, sim_run_id=RUN, depot_id=DEPOT)
    assert r["rows"] == []
    assert r["fire"]["status"] == "empty"
    assert "no charge-capable stalls" in r["fire"]["error"]


def test_an_unknown_class_abstains_with_its_reason():
    frame = _frame(vehicles=[_vehicle(V1, cls="not_a_class")])
    r = pb.fire(frame, CLASS_ROWS, site=SITE, sim_run_id=RUN, depot_id=DEPOT)
    assert r["fire"]["status"] == "proposed"
    assert len(r["rows"]) == 1
    p = r["rows"][0]["proposal"]
    assert p["abstain"] is True
    assert "no class-table entry" in p["rationale"]["reason"]


def test_max_assets_defers_the_rest_with_a_row_each():
    r = _fire(max_assets=1)
    assert r["fire"]["n_planned"] == 1
    assert r["fire"]["n_deferred"] == 2
    deferred = [row for row in r["rows"] if row["proposal"]["abstain"]]
    assert len(deferred) == 2
    assert all("outside this tick's batch of 1" in d["proposal"]["rationale"]["reason"]
               for d in deferred)


def test_fire_refuses_a_bad_run_id_and_a_site_without_the_cooldown():
    with pytest.raises(pb.BridgeError, match="sim_run_id must be a uuid"):
        pb.fire(_frame(), CLASS_ROWS, site=SITE, sim_run_id="run-1", depot_id=DEPOT)
    with pytest.raises(pb.BridgeError, match="dcfc_cooldown_min"):
        pb.fire(_frame(), CLASS_ROWS, site={}, sim_run_id=RUN, depot_id=DEPOT)


# ---- the SQL emitter ------------------------------------------------------------

_DOOR = re.compile(r"SELECT public\.ottoq_submit_external_proposal\(")
_BATCH = re.compile(r"SELECT public\.ottoq_proposer_submit_batch\(")


def test_emit_sql_calls_the_door_once_per_row_and_never_inserts():
    r = _fire()
    sql = pb.emit_sql(r, sim_run_id=RUN, depot_id=DEPOT, ttl_seconds=60)
    assert len(_DOOR.findall(sql)) == 3
    assert len(_BATCH.findall(sql)) == 0
    assert "insert" not in sql.lower()
    assert "update" not in sql.lower()
    for line in sql.splitlines():
        if line.startswith("SELECT"):
            assert line.endswith(", 'forward_lex', 60);")
            assert f"'{RUN}'::uuid, '{DEPOT}'::uuid, 'stall_assignment', 'vehicle'" in line
    assert sql.count(pb.DOLLAR_TAG) == 2 * 3
    assert "-- fire:" in sql


def test_emit_sql_batch_is_one_call_carrying_rows_and_the_fire_record():
    r = _fire()
    sql = pb.emit_sql(r, sim_run_id=RUN, depot_id=DEPOT, ttl_seconds=45, via="batch")
    assert len(_BATCH.findall(sql)) == 1
    assert len(_DOOR.findall(sql)) == 0
    call = next(l for l in sql.splitlines() if l.startswith("SELECT"))
    assert call.endswith(", 45);")
    payloads = re.findall(re.escape(pb.DOLLAR_TAG) + r"(.*?)" + re.escape(pb.DOLLAR_TAG), call)
    assert len(payloads) == 2
    rows, rec = json.loads(payloads[0]), json.loads(payloads[1])
    assert len(rows) == 3 and {x["entity_id"] for x in rows} == {V1, V2, V3}
    assert rec["frame_hash"] == r["fire"]["frame_hash"]
    assert rec["status"] == "proposed"


def test_an_empty_fire_is_ledgered_on_the_batch_route_and_flagged_on_the_door_route():
    frame = _frame(vehicles=[_vehicle(V1, state="offline")])
    r = pb.fire(frame, CLASS_ROWS, site=SITE, sim_run_id=RUN, depot_id=DEPOT)
    door = pb.emit_sql(r, sim_run_id=RUN, depot_id=DEPOT)
    assert len(_DOOR.findall(door)) == 0
    assert "NOT ledgered on the door route" in door
    batch = pb.emit_sql(r, sim_run_id=RUN, depot_id=DEPOT, via="batch")
    assert len(_BATCH.findall(batch)) == 1
    assert "[]" in batch  # the empty rows payload


def test_emitter_refuses_a_non_uuid_entity_and_a_bad_source():
    row = {"action_context": "stall_assignment", "entity_type": "vehicle",
           "entity_id": "v-1", "source": "forward_lex", "proposal": {"abstain": True}}
    with pytest.raises(pb.BridgeError, match="entity_id must be a uuid"):
        pb.door_call_sql(row, sim_run_id=RUN, depot_id=DEPOT)
    row["entity_id"] = V1
    row["source"] = "forward lex; DROP"
    with pytest.raises(pb.BridgeError, match="source must match"):
        pb.door_call_sql(row, sim_run_id=RUN, depot_id=DEPOT)
    row["source"] = "forward_lex"
    with pytest.raises(pb.BridgeError, match="ttl_seconds"):
        pb.door_call_sql(row, sim_run_id=RUN, depot_id=DEPOT, ttl_seconds=0)


def test_emitter_refuses_a_payload_that_contains_the_dollar_tag():
    row = {"action_context": "stall_assignment", "entity_type": "vehicle",
           "entity_id": V1, "source": "forward_lex",
           "proposal": {"abstain": True, "rationale": {"reason": pb.DOLLAR_TAG}}}
    with pytest.raises(pb.BridgeError, match="dollar-quote tag"):
        pb.door_call_sql(row, sim_run_id=RUN, depot_id=DEPOT)


def test_emit_sql_rejects_an_unknown_route():
    with pytest.raises(pb.BridgeError, match="via must be"):
        pb.emit_sql(_fire(), sim_run_id=RUN, depot_id=DEPOT, via="insert")


# ---- the live half, without a database --------------------------------------------

def test_live_mode_names_the_missing_driver_instead_of_crashing(monkeypatch):
    def _no_driver():
        raise pb.BridgeError("live mode needs psycopg (pip install 'psycopg[binary]')")
    monkeypatch.setattr(pb, "_import_psycopg", _no_driver)
    with pytest.raises(pb.BridgeError, match="psycopg"):
        pb.run_live("postgresql://x", sim_run_id=RUN, depot_id=DEPOT, site=SITE)


def test_the_bridge_module_holds_no_insert_and_no_production_identifier():
    src = (HERE / "proposer_bridge.py").read_text()
    code = "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("#"))
    #: The one INSERT-shaped token allowed is inside the module docstring's prose.
    body = code.split('"""', 2)[2]
    assert "INSERT INTO" not in body.upper()
    assert "gxdrcyphqjzjsuhxuqtg" not in src
    assert "ycsisvozzgmisboumfqc" not in src


# ---- CLI -----------------------------------------------------------------------------

def test_cli_offline_writes_sql_and_a_json_result(tmp_path, capsys):
    frame_p, classes_p = tmp_path / "frame.json", tmp_path / "classes.json"
    frame_p.write_text(json.dumps(_frame()))
    classes_p.write_text(json.dumps(CLASS_ROWS))
    out_sql, out_json = tmp_path / "out.sql", tmp_path / "out.json"
    rc = pb.main(["--run", RUN, "--depot", DEPOT,
                  "--site", str(HERE / "sites" / "nashville-flagship.json"),
                  "--frame", str(frame_p), "--classes", str(classes_p),
                  "--emit-sql", str(out_sql), "--json-out", str(out_json), "--ttl", "30"])
    assert rc == 0
    sql = out_sql.read_text()
    assert len(_DOOR.findall(sql)) == 3
    assert all(l.endswith(", 'forward_lex', 30);") for l in sql.splitlines() if l.startswith("SELECT"))
    result = json.loads(out_json.read_text())
    assert result["fire"]["status"] == "proposed" and len(result["rows"]) == 3
    err = capsys.readouterr().err
    assert '"status":"proposed"' in err


def test_cli_offline_needs_both_inputs(tmp_path):
    with pytest.raises(SystemExit):
        pb.main(["--run", RUN, "--depot", DEPOT,
                 "--site", str(HERE / "sites" / "nashville-flagship.json")])


# ---- the plan is a schedule; the door takes this tick's assignments ------------------

def _row(vid, sid, start, end=None):
    return {"action_context": "stall_assignment", "entity_type": "vehicle", "entity_id": vid,
            "source": "forward_lex",
            "proposal": {"verb": "assign_stall", "abstain": False, "stall_id": sid, "stall_type": "l2",
                         "vehicle_id": vid, "requested_kw": 19,
                         "rationale": {"optimizer": "forward_lex", "planned_start_min": start,
                                       "planned_end_min": end or start + 100, "ready_by_source": "default"},
                         "resolved_action_context": "stall_assignment"}}


def test_a_charge_planned_beyond_the_window_abstains_with_its_planned_start():
    rows, not_due = pb.only_due_now([_row(V1, S3, 0), _row(V2, S3, 174)], start_within_min=30)
    assert not_due == [V2]
    assert rows[0]["proposal"]["abstain"] is False and rows[0]["proposal"]["stall_id"] == S3
    p = rows[1]["proposal"]
    assert p["abstain"] is True and "stall_id" not in p
    assert p["rationale"]["planned_start_min"] == 174 and p["rationale"]["planned_stall_id"] == S3
    assert p["rationale"]["abstained_by"] == "bridge:not_due"
    assert "+174 min" in p["rationale"]["reason"]


def test_the_window_is_inclusive_and_proposer_abstentions_pass_through():
    ab = {"action_context": "stall_assignment", "entity_type": "vehicle", "entity_id": V3,
          "source": "forward_lex", "proposal": {"verb": "assign_stall", "abstain": True,
          "vehicle_id": V3, "rationale": {"reason": "x", "optimizer": "forward_lex"},
          "resolved_action_context": "stall_assignment"}}
    rows, not_due = pb.only_due_now([_row(V1, S1, 30), ab], start_within_min=30)
    assert not_due == [] and rows[0]["proposal"]["abstain"] is False and rows[1] is ab


def test_a_batch_never_names_one_stall_twice_for_immediate_starts():
    #: Six vehicles, few stalls, a tight window: whatever the solver sequences
    #: onto one point, only the first occupant is submitted as an assignment.
    vehicles = [_vehicle(f"6e7d0b1c-0000-4000-8000-0000000000{i:02x}", soc=20 + i) for i in range(6)]
    frame = _frame(vehicles=vehicles, stalls=[_stall(S1, kind="l2", kw=19), _stall(S2, kind="l2", kw=19)])
    r = pb.fire(frame, CLASS_ROWS, site=SITE, sim_run_id=RUN, depot_id=DEPOT, start_within_min=30)
    live = [x["proposal"]["stall_id"] for x in r["rows"] if not x["proposal"]["abstain"]]
    assert len(live) == len(set(live))
    assert r["fire"]["n_not_due"] == len(r["rows"]) - len(live)
    assert r["fire"]["n_planned"] == len(live)
    assert r["fire"]["start_within_min"] == 30 and r["fire"]["default_ready_delta_min"] == 240


def test_the_fire_record_counts_busy_stalls_on_every_path():
    """L-58: 'planned on N of M' is a ledger fact. The count is on the proposed
    path and on the empty path alike, and a held stall is never in a row."""
    occ = _stall(S1); occ.update(status="occupied", vehicle_id=V2)
    held = _stall(S2); held.update(vehicle_id=V3)          # status 'available', held
    r = pb.fire(_frame(stalls=[occ, held, _stall(S3, kind="l2", kw=19)]),
                CLASS_ROWS, site=SITE, sim_run_id=RUN, depot_id=DEPOT)
    assert r["fire"]["n_stalls"] == 3 and r["fire"]["n_stalls_busy"] == 2
    for row in r["rows"]:
        assert row["proposal"].get("stall_id") not in {S1, S2}

    all_busy = pb.fire(_frame(stalls=[occ, held]), CLASS_ROWS, site=SITE,
                       sim_run_id=RUN, depot_id=DEPOT)
    assert all_busy["fire"]["status"] == "empty"
    assert all_busy["fire"]["n_stalls_busy"] == 2
    assert "occupied or held" in all_busy["fire"]["error"]


def test_the_fire_record_names_the_states_it_planned_for():
    """L-60: a fire narrowed to the held arrivals says so on the record, counts
    the frame by that set, and plans for nothing outside it."""
    frame = _frame(vehicles=[_vehicle(V1, soc=25, state="arrived_at_gate"),
                             _vehicle(V2, soc=40, state="staged_awaiting_service")])
    r = pb.fire(frame, CLASS_ROWS, site=SITE, sim_run_id=RUN, depot_id=DEPOT,
                serviceable_states=frozenset({"arrived_at_gate"}))
    assert r["fire"]["serviceable_states"] == ["arrived_at_gate"]
    assert r["fire"]["n_in_serviceable_state"] == 1
    assert {row["entity_id"] for row in r["rows"]} == {V1}
    full = pb.fire(frame, CLASS_ROWS, site=SITE, sim_run_id=RUN, depot_id=DEPOT)
    assert full["fire"]["serviceable_states"] == sorted(pb.DEFAULT_SERVICEABLE_STATES)
    assert full["fire"]["n_in_serviceable_state"] == 2
    assert pb._parse_states("arrived_at_gate, charging_l2") == frozenset(
        {"arrived_at_gate", "charging_l2"})
    assert pb._parse_states(None) is None


def test_an_infeasible_frame_is_an_empty_fire_not_a_traceback():
    """L-62: thirteen vehicles, one stall, a 720-minute horizon -- the kernel
    raises when it can retain no plan. The bridge records that as an empty fire
    with the solver's words in `error`, and the loop keeps running."""
    many = [_vehicle(f"6e7d0b1c-0000-4000-8000-0000000000{i:02d}", soc=20) for i in range(10, 30)]
    r = pb.fire(_frame(vehicles=many, stalls=[_stall(S1, kind="l2", kw=7)]),
                CLASS_ROWS, site=SITE, sim_run_id=RUN, depot_id=DEPOT,
                default_ready_delta_min=30)
    assert r["fire"]["status"] == "empty" and r["rows"] == []
    assert "declined the frame" in r["fire"]["error"]
    # and the same frame WITH rejection allowed plans what fits and abstains on the rest
    ok = pb.fire(_frame(vehicles=many, stalls=[_stall(S1, kind="l2", kw=7)]),
                 CLASS_ROWS, site=SITE, sim_run_id=RUN, depot_id=DEPOT,
                 default_ready_delta_min=30, allow_rejection=True)
    assert ok["fire"]["status"] == "proposed"
    assert len(ok["rows"]) == len(many)


# ---------------------------------------------------------------------------
# The live loop's two guards, tested with a cursor-shaped fake so CI stays
# database-free (verify.yml: "no secrets, no database").
# ---------------------------------------------------------------------------


class FakeCur:
    """Enough of a psycopg cursor for the two read-only guards."""

    def __init__(self, one=None, many=None):
        self._one, self._many, self.sql = one, many or [], []

    def execute(self, sql, params=None):
        self.sql.append(" ".join(sql.split()))
        self.params = params

    def fetchone(self):
        return self._one

    def fetchall(self):
        return self._many

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def test_a_clear_process_list_is_not_a_refusal():
    cur = FakeCur(one=(0,))
    assert pb._cert_in_flight(cur) is None
    assert "pg_stat_activity" in cur.sql[0]
    # self-exclusion matters: the guard's own query matches its own ILIKE
    assert "pid <> pg_backend_pid()" in cur.sql[0]


def test_a_certification_in_flight_is_named_not_guessed():
    reason = pb._cert_in_flight(FakeCur(one=(2,)))
    assert reason is not None
    assert "ottoq_determinism_pair" in reason and "2" in reason


def test_auto_resolves_the_depots_one_running_run():
    cur = FakeCur(many=[(RUN, "proposer_demo", "running")])
    assert pb._resolve_run(cur, DEPOT) == RUN


def test_auto_refuses_a_paused_run_and_says_why():
    cur = FakeCur(many=[(RUN, "proposer_demo", "paused")])
    with pytest.raises(pb.BridgeError) as exc:
        pb._resolve_run(cur, DEPOT)
    assert "paused" in str(exc.value) and RUN in str(exc.value)


def test_auto_refuses_two_running_runs_rather_than_picking_one():
    other = "0a7d4569-888b-4633-a919-dbc4b8adca30"
    cur = FakeCur(many=[(RUN, "proposer_demo", "running"),
                        (other, "ab_harness", "running")])
    with pytest.raises(pb.BridgeError) as exc:
        pb._resolve_run(cur, DEPOT)
    assert RUN in str(exc.value) and other in str(exc.value)


def test_auto_never_submits_into_a_certification_arm():
    cur = FakeCur(many=[(RUN, pb.CERT_RUN_BY, "running")])
    with pytest.raises(pb.BridgeError) as exc:
        pb._resolve_run(cur, DEPOT)
    assert "certification arm" in str(exc.value)


def test_auto_on_an_idle_depot_is_a_named_refusal():
    with pytest.raises(pb.BridgeError) as exc:
        pb._resolve_run(FakeCur(many=[]), DEPOT)
    assert "no running or paused run" in str(exc.value)


def test_the_guard_query_watches_the_ab_rig_too():
    assert any("ab_pair" in c for c in pb.CERT_CALLS)
    assert any("determinism_pair" in c for c in pb.CERT_CALLS)


def test_an_idle_depot_is_a_distinct_exception_so_a_scheduler_can_pass_it():
    with pytest.raises(pb.BridgeIdle):
        pb._resolve_run(FakeCur(many=[]), DEPOT)
    with pytest.raises(pb.BridgeIdle):
        pb._resolve_run(FakeCur(many=[(RUN, "proposer_demo", "paused")]), DEPOT)
    # ambiguity and a certification arm are NOT idleness -- a human must decide
    two = [(RUN, "proposer_demo", "running"),
           ("0a7d4569-888b-4633-a919-dbc4b8adca30", "ab_harness", "running")]
    with pytest.raises(pb.BridgeError) as amb:
        pb._resolve_run(FakeCur(many=two), DEPOT)
    assert not isinstance(amb.value, pb.BridgeIdle)
    with pytest.raises(pb.BridgeError) as cert:
        pb._resolve_run(FakeCur(many=[(RUN, pb.CERT_RUN_BY, "running")]), DEPOT)
    assert not isinstance(cert.value, pb.BridgeIdle)


def test_idle_ok_exits_zero_only_for_idleness(monkeypatch, tmp_path, capsys):
    site = tmp_path / "site.json"
    site.write_text(json.dumps(SITE))

    def idle(*a, **k):
        raise pb.BridgeIdle("depot has no running or paused run to propose into")

    monkeypatch.setattr(pb, "run_live", idle)
    argv = ["--run", "auto", "--depot", DEPOT, "--site", str(site),
            "--dsn", "postgresql://x", "--idle-ok"]
    assert pb.main(argv) == 0
    assert "idle" in capsys.readouterr().out

    def ambiguous(*a, **k):
        raise pb.BridgeError("depot has 2 running runs")

    monkeypatch.setattr(pb, "run_live", ambiguous)
    assert pb.main(argv) == 2
