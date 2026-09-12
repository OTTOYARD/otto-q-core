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
    rows = _fire()["rows"]
    v3 = next(r for r in rows if r["entity_id"] == V3)
    assert v3["proposal"]["abstain"] is False
    assert v3["proposal"]["stall_type"] == "l2"
    assert v3["proposal"]["stall_id"] == S3


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
