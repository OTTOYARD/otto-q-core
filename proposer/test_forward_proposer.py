"""Tests for the production proposer bridge.

The synthetic frame below is in the twin's ACTUAL emitted shape (keys and field
names read from a live decision snapshot, 2026-08-24) -- but its CONTENT is
invented here. That is the separation discipline: the bridge is tested against
the production contract's shape without ever reading production data.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from forward_proposer import (  # noqa: E402
    FrameError,
    frame_to_scenario,
    propose,
)

SITE = {"power_cap_kw_hard": 600, "power_soft_target_kw": 450,
        "dcfc_cooldown_min": 18, "move_duration_min": 4, "path_capacity": 2,
        "cold_start_below_c": 5, "cold_start_penalty_min": 12,
        "onpeak_window_min": [240, 420]}

CLASSES = {
    "waymo": {"battery_kwh": 90, "max_charge_kw": 100,
              "charge_kinds": ["dcfc", "l2"],
              "energy_curve": [{"above_soc_pct": 0, "accept_frac": 1.0},
                               {"above_soc_pct": 70, "accept_frac": 0.6}]},
    "zoox": {"battery_kwh": 110, "max_charge_kw": 150,
             "charge_kinds": ["dcfc"]},
}


def _vehicle(vid, platform="waymo", soc=30, state="arrived_at_gate", **kw):
    base = {"id": vid, "soc": soc, "make": platform.title(), "state": state,
            "platform": platform, "stall_id": None, "svc_step": "await",
            "inlet_type": "CCS1", "target_soc": 90, "inlet_max_kw": 100.0,
            "fleet_operator_id": "op-1", "min_soc_threshold": 20}
    base.update(kw)
    return base


def _stall(sid, kind="dcfc", kw=150, status="available"):
    return {"id": sid, "type": kind, "status": status,
            "vehicle_id": None, "connector_type": "CCS1",
            "connector_max_kw": kw}


def _frame(vehicles, stalls):
    return {"vehicles": vehicles, "stalls": stalls, "sessions": [],
            "energy": {}, "bess": []}


FRAME = _frame(
    [_vehicle("v-1", soc=25), _vehicle("v-2", soc=40),
     _vehicle("v-3", platform="zoox", soc=30, inlet_max_kw=150.0),
     _vehicle("v-4", soc=92, state="staged_for_departure"),   # not serviceable
     _vehicle("v-5", platform="cybertruck", soc=20)],          # unknown platform
    [_stall("s-1"), _stall("s-2"), _stall("s-3", kind="l2", kw=11),
     _stall("s-4", kind="staging", kw=0)])


@pytest.fixture(scope="module")
def result():
    return propose(FRAME, CLASSES, site=SITE)


# ---- the two laws ----------------------------------------------------------------

def test_propose_returns_rows_and_writes_nothing(result):
    """The bridge's entire output is its return value. There is nothing to
    assert about side effects because the module has no channel for any: the
    separation guard (tests/test_separation.py) proves it cannot import a
    database client, and this test proves the rows are advisory shapes."""
    assert isinstance(result["proposals"], list)
    for row in result["proposals"]:
        assert row["proposal"]["verb"] == "assign_stall"


def test_every_row_matches_the_production_proposal_shape(result):
    """Key-for-key against the observed ottoq_external_proposals contract."""
    for row in result["proposals"]:
        assert set(row) == {"action_context", "entity_type", "entity_id",
                            "source", "proposal"}
        assert row["action_context"] == "stall_assignment"
        assert row["entity_type"] == "vehicle"
        assert row["source"] == "forward_lex"
        p = row["proposal"]
        assert p["resolved_action_context"] == "stall_assignment"
        assert "abstain" in p and "rationale" in p
        if not p["abstain"]:
            assert {"stall_id", "stall_type", "vehicle_id",
                    "requested_kw"} <= set(p)


# ---- planning correctness --------------------------------------------------------

def test_plannable_vehicles_get_assignments_and_the_rest_abstain(result):
    planned = {r["entity_id"] for r in result["proposals"]
               if not r["proposal"]["abstain"]}
    abstained = {r["entity_id"] for r in result["proposals"]
                 if r["proposal"]["abstain"]}
    assert planned == {"v-1", "v-2", "v-3"}
    assert abstained == {"v-5"}          # unknown platform: abstain, not guess
    assert "v-4" not in planned | abstained   # not serviceable: not ours to plan
    assert result["planned"] == 3 and result["abstained"] == 1


def test_capability_binds_in_proposals(result):
    """zoox declares dcfc-only; it must never be proposed an l2 stall."""
    for row in result["proposals"]:
        p = row["proposal"]
        if p.get("vehicle_id") == "v-3" and not p["abstain"]:
            assert p["stall_type"] == "dcfc"


def test_an_unknown_platform_is_an_abstention_with_its_reason(result):
    row = next(r for r in result["proposals"] if r["entity_id"] == "v-5")
    assert row["proposal"]["abstain"] is True
    assert "class-table entry" in row["proposal"]["rationale"]["reason"]


def test_ready_by_provenance_is_recorded(result):
    """A schedule built on a default deadline is labeled as one -- the frame
    does not carry required-ready-times, and pretending otherwise would be a
    silently invented constraint."""
    for row in result["proposals"]:
        if not row["proposal"]["abstain"]:
            assert row["proposal"]["rationale"]["ready_by_source"] == "default"
    explicit = propose(FRAME, CLASSES, site=SITE,
                       ready_by_min={"v-1": 120})
    r1 = next(r for r in explicit["proposals"]
              if r["proposal"].get("vehicle_id") == "v-1")
    assert r1["proposal"]["rationale"]["ready_by_source"] == "explicit"


def test_solver_accounting_travels_with_the_rows(result):
    """cuopt_invocation_log discipline: every invocation quantifiable."""
    s = result["solver"]
    assert s["optimizer"] == "forward_lex"
    assert s["pass1_status"] in ("OPTIMAL", "FEASIBLE")
    assert s["pass2_status"] in ("OPTIMAL", "FEASIBLE")
    assert s["total_tardy_min"] == 0


def test_determinism(result):
    again = propose(FRAME, CLASSES, site=SITE)
    assert again["proposals"] == result["proposals"]


# ---- refusals --------------------------------------------------------------------

def test_a_frame_with_no_chargeable_stalls_is_refused():
    with pytest.raises(FrameError):
        frame_to_scenario(_frame([_vehicle("v-1")],
                                 [_stall("s-4", kind="staging", kw=0)]),
                          CLASSES, site=SITE)


def test_no_capable_point_on_site_is_an_abstention():
    frame = _frame([_vehicle("v-3", platform="zoox", soc=30)],
                   [_stall("s-3", kind="l2", kw=11)])   # zoox is dcfc-only
    out = propose(frame, CLASSES, site=SITE)
    assert out["planned"] == 0 and out["abstained"] == 1
    assert "no capable point" in out["proposals"][0]["proposal"]["rationale"]["reason"]


def test_an_empty_serviceable_set_is_a_quiet_no_op():
    frame = _frame([_vehicle("v-4", soc=95, state="staged_for_departure")],
                   [_stall("s-1")])
    out = propose(frame, CLASSES, site=SITE)
    assert out["planned"] == 0 and out["solver"] is None
