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
    DEFAULT_DET_BUDGET_S,
    DEFAULT_SERVICEABLE_STATES,
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


# ---------------------------------------------------------------------------
# Rejection through the bridge (SOLVER_STATE.md 6.1a)
# ---------------------------------------------------------------------------

def _oversubscribed(n_vehicles=8, n_stalls=1):
    """More vehicles than the site can serve inside the horizon."""
    return _frame([_vehicle(f"v{i}", soc=15) for i in range(n_vehicles)],
                  [_stall(f"s{i}") for i in range(n_stalls)])


def test_an_oversubscribed_site_returns_a_plan_instead_of_nothing():
    frame = _oversubscribed()
    # Without rejection the model is infeasible and the whole call yields nothing.
    with pytest.raises(RuntimeError):
        propose(frame, CLASSES, site=SITE, horizon_min=120,
                default_ready_delta_min=60)

    r = propose(frame, CLASSES, site=SITE, horizon_min=120,
                default_ready_delta_min=60, allow_rejection=True)
    assert r["solver"]["rejected"], "rejection enabled but nothing was rejected"
    #: `planned` COUNTS DECLINED ROWS TOO. It is len(rows) from plan_to_proposals,
    #: and a declined asset gets a row there (deliberately -- that is how
    #: "asked and declined" stays distinguishable from "never asked"). So
    #: `assert r["planned"] > 0, "a partial plan should still serve someone"`
    #: was true even when the site served NOBODY, which is precisely the case
    #: the sentence was written to rule out. Count the served rows instead.
    served = [row for row in r["proposals"] if not row["proposal"]["abstain"]]
    declined = [row for row in r["proposals"] if row["proposal"]["abstain"]]
    assert served, (
        f"a partial plan should still serve someone: {len(r['proposals'])} rows "
        f"out and every one of them declined")
    assert declined, "the oversubscribed frame produced no declined row"
    assert len(served) + len(declined) == r["planned"] + r["abstained"], (
        "a vehicle went missing between the plan and the batch")


def test_no_vehicle_ever_vanishes_from_the_batch():
    """THE SILENT-DROP GUARD, and it is the reason this feature needed a test here
    rather than only in the solver battery.

    plan_to_proposals used to `continue` past any asset with no charge op. That
    was harmless while every asset was guaranteed a point, and became a silent
    drop the instant the solver could decline one: a vehicle the solver
    deliberately could not serve would have left NO ROW AT ALL, making it
    indistinguishable from a vehicle nobody asked about. Row count is what sees
    it -- every other assertion in this file passes with the drop in place.
    """
    frame = _oversubscribed()
    r = propose(frame, CLASSES, site=SITE, horizon_min=120,
                default_ready_delta_min=60, allow_rejection=True)
    assert len(r["proposals"]) == len(frame["vehicles"]), (
        f"{len(frame['vehicles'])} vehicles in, {len(r['proposals'])} rows out")
    assert {p["entity_id"] for p in r["proposals"]} == {v["id"] for v in frame["vehicles"]}


def test_a_declined_vehicle_says_so_and_says_why():
    frame = _oversubscribed()
    r = propose(frame, CLASSES, site=SITE, horizon_min=120,
                default_ready_delta_min=60, allow_rejection=True)
    declined = {p["entity_id"] for p in r["proposals"] if p["proposal"]["abstain"]}
    assert declined == set(r["solver"]["rejected"]), (
        f"abstained {sorted(declined)} but reported {sorted(r['solver']['rejected'])}")
    for p in r["proposals"]:
        if p["proposal"]["abstain"]:
            reason = p["proposal"]["rationale"]["reason"]
            assert "could not serve" in reason, f"unhelpful reason: {reason!r}"
        else:
            # a served vehicle still carries a real assignment, not an empty one
            assert p["proposal"]["stall_id"] and p["proposal"]["requested_kw"]


def test_a_derated_inlet_is_a_per_vehicle_fact_not_a_per_platform_one():
    """Two vehicles of one platform, different inlet limits: each gets its own.

    `inlet_max_kw` is declared per vehicle in the frame contract because a
    derated or damaged inlet is a fact about one truck. The synthesized asset
    class was keyed on platform alone and filled with `setdefault`, so only the
    FIRST vehicle of each platform was ever consulted:

      full first    -> {'v-derated': 100, 'v-full': 100}   # derated over-asked
      derated first -> {'v-derated': 25,  'v-full': 25}    # healthy throttled

    Both are wrong, in opposite directions, and which one you get depends on
    frame row order — so the same site state produced two different plans.
    """
    full = _vehicle("v-full", inlet_max_kw=100.0)
    derated = _vehicle("v-derated", inlet_max_kw=25.0)
    stalls = [_stall("s-0"), _stall("s-1")]

    def kws(vehicles):
        r = propose(_frame(vehicles, stalls), CLASSES, site=SITE, horizon_min=480)
        return {p["entity_id"]: p["proposal"]["requested_kw"] for p in r["proposals"]}

    assert kws([full, derated]) == {"v-full": 100, "v-derated": 25}
    # ...and reordering the frame rows changes nothing.
    assert kws([derated, full]) == kws([full, derated])


def test_two_identical_units_still_share_one_synthesized_class():
    """The fix must not shatter the class table: units whose per-unit facts agree
    are one class, so the model keeps its symmetry and the scenario stays small."""
    frame = _frame([_vehicle("v-a", inlet_max_kw=100.0),
                    _vehicle("v-b", inlet_max_kw=100.0),
                    _vehicle("v-c", inlet_max_kw=40.0)],
                   [_stall("s-0"), _stall("s-1")])
    sc, _ = frame_to_scenario(frame, CLASSES, site=SITE, horizon_min=480)
    assert len(sc["asset_classes"]) == 2, sorted(sc["asset_classes"])
    by_aid = {a.aid: a.cls for a in sc["assets"]}
    assert by_aid["v-a"] == by_aid["v-b"] != by_aid["v-c"]


def test_every_default_serviceable_state_is_a_real_production_label():
    """The set named three states the `vehicle_state` type cannot hold.

    `awaiting_stall`, `in_queue` and `charge_scheduled` are not labels of the
    production enum — they were written from memory — so three sixths of the
    default predicate was dead code that could never match a frame row. The
    enum is committed at db/contracts/vehicle_state_enum.json (a snapshot, read
    by this test only; nothing reads it at runtime), so the check needs no
    database and the set cannot drift from the type unnoticed again.
    """
    import json
    enum = json.loads(
        (HERE.parent / "db" / "contracts" / "vehicle_state_enum.json").read_text())
    labels = set(enum["labels"])
    assert enum["type"] == "vehicle_state"
    bogus = sorted(DEFAULT_SERVICEABLE_STATES - labels)
    assert bogus == [], (
        f"states that the production enum cannot hold: {bogus}; "
        f"real labels are {sorted(labels)}")


def test_the_on_site_waiting_state_is_not_filtered_out():
    """`staged_awaiting_service` is the enum's on-site-waiting label and was
    missing from the set, so those vehicles were dropped before
    frame_to_scenario ever saw them — no proposal AND no abstention, which is
    the silent drop plan_to_proposals exists to prevent.

    On the flagship depot that state carried 3,386 transitions across 113 of 116
    vehicles in 24 hours; at the busiest sampled minute 16 vehicles held it
    against 19 the old set could see. Nearly half the serviceable population.
    """
    assert "staged_awaiting_service" in DEFAULT_SERVICEABLE_STATES
    frame = _frame(
        [_vehicle("v-gate", state="arrived_at_gate"),
         _vehicle("v-staged", state="staged_awaiting_service")],
        [_stall("s-0"), _stall("s-1")])
    r = propose(frame, CLASSES, site=SITE, horizon_min=480)
    assert {p["entity_id"] for p in r["proposals"]} == {"v-gate", "v-staged"}
    assert not any(p["proposal"]["abstain"] for p in r["proposals"])


def test_every_proposal_is_bounded_without_the_caller_asking():
    """propose() defaulted det_budget_s AND time_limit_s to None -- no budget of
    any kind -- and orchestrate() forwarded only **propose_kwargs with no caller
    supplying them, so nothing in the shipped call graph ever bounded a solve.

    An unbounded proposal is two problems: it can overrun the tick it was meant
    to occupy, and its cost becomes a property of how loaded the box was rather
    than of the instance, which is not reproducible under a run ID.
    """
    import inspect
    sig = inspect.signature(propose)
    assert sig.parameters["det_budget_s"].default == DEFAULT_DET_BUDGET_S
    assert DEFAULT_DET_BUDGET_S is not None and DEFAULT_DET_BUDGET_S > 0

    # ...and the default actually reaches the solver, which reports it back.
    r = propose(FRAME, CLASSES, site=SITE, horizon_min=480)
    assert r["solver"]["reproducible"] is True, (
        "a bounded solve on deterministic work must report reproducible; "
        "False means a wall clock stopped the search")


def test_the_batch_bound_defers_the_rest_and_every_vehicle_still_gets_a_row():
    """A deterministic budget bounds the SEARCH, not the MODEL.

    Measured on this codebase: a 44-vehicle / 16-stall frame costs ~95 s of wall
    time at the default budget, mostly construction and propagation, so no
    budget setting makes it fit the engine's 30-second tick. A caller that must
    occupy the one-tick seat sizes the frame: max_assets=8 on that same frame
    runs in ~7.6 s.

    The rule that survives is the module's own: NEVER SILENTLY DROPS ONE. A
    deferred vehicle gets an abstention row naming the batch, so "deferred to
    the next tick" stays distinguishable from "nobody asked".
    """
    vehicles = [_vehicle(f"v-{i}", soc=20 + (i * 7) % 50) for i in range(10)]
    frame = _frame(vehicles, [_stall(f"s-{i}") for i in range(4)])

    r = propose(frame, CLASSES, site=SITE, horizon_min=480, max_assets=3)

    assert r["planned"] == 3
    assert r["deferred"] == 7
    assert {p["entity_id"] for p in r["proposals"]} == {v["id"] for v in vehicles}
    deferred = [p for p in r["proposals"]
                if "outside this tick's batch"
                in p["proposal"]["rationale"].get("reason", "")]
    assert len(deferred) == 7
    assert all(p["proposal"]["abstain"] for p in deferred)


def test_the_batch_keeps_the_most_urgent_and_the_choice_is_not_frame_order():
    """Urgency is deadline first, then depth of need: earliest ready_by, then
    lowest SoC, then aid. Selecting by frame order would make the proposal a
    function of how the frame was assembled."""
    vehicles = [_vehicle("v-late", soc=80), _vehicle("v-urgent", soc=10),
                _vehicle("v-mid", soc=45)]
    ready = {"v-late": 600, "v-urgent": 30, "v-mid": 120}
    frame = _frame(vehicles, [_stall("s-0"), _stall("s-1")])

    def planned_of(rows):
        return {p["entity_id"] for p in rows["proposals"]
                if not p["proposal"]["abstain"]}

    a = propose(frame, CLASSES, site=SITE, horizon_min=720,
                ready_by_min=ready, max_assets=2)
    assert planned_of(a) == {"v-urgent", "v-mid"}

    # reversing the frame rows changes nothing
    b = propose(_frame(list(reversed(vehicles)), [_stall("s-0"), _stall("s-1")]),
                CLASSES, site=SITE, horizon_min=720,
                ready_by_min=ready, max_assets=2)
    assert planned_of(b) == planned_of(a)


def test_a_batch_bound_below_one_is_refused():
    with pytest.raises(ValueError, match="max_assets"):
        propose(FRAME, CLASSES, site=SITE, horizon_min=480, max_assets=0)


def test_rejection_stays_off_unless_asked():
    """Default OFF, asserted directly: the flag is what makes this feature safe to
    land at all, since an accidental default would let the proposer quietly decline
    vehicles the site could in fact have served."""
    frame = _frame([_vehicle("v0"), _vehicle("v1")], [_stall("s0"), _stall("s1")])
    r = propose(frame, CLASSES, site=SITE, horizon_min=480)
    assert r["solver"]["rejected"] == []
    assert all(not p["proposal"]["abstain"] for p in r["proposals"])

# ---------------------------------------------------------------------------
# Regime-aware propose (hour_of_day set) — the intent drives the proposer
# ---------------------------------------------------------------------------

def test_regime_path_runs_the_regimes_pass_order():
    rush = propose(FRAME, CLASSES, site=SITE, hour_of_day=7)
    s = rush["solver"]
    assert s["regime"] == "dispatch_rush"
    assert s["pass_modes"] == ["min_tardy", "min_flow", "min_peak"]
    assert s["complete"] is True
    assert s["total_tardy_min"] == 0
    assert s["site_peak_kw"] is not None and s["total_flow_min"] is not None


def test_grid_peak_regime_orders_energy_first_and_skips_flow():
    r = propose(FRAME, CLASSES, site=SITE, hour_of_day=14,
                signals=frozenset({"grid_peak_imminent"}))
    s = r["solver"]
    assert s["regime"] == "grid_peak"
    assert s["pass_modes"] == ["min_tardy", "min_peak"]
    assert s["total_flow_min"] is None


def test_default_path_keeps_the_two_pass_contract_without_a_regime():
    r = propose(FRAME, CLASSES, site=SITE)
    assert "regime" not in r["solver"]
    assert r["solver"]["pass1_status"] in ("OPTIMAL", "FEASIBLE")
    assert r["solver"]["pass2_status"] in ("OPTIMAL", "FEASIBLE")
    assert r["solver"]["total_tardy_min"] == 0


def _crowded(n_vehicles=14, n_stalls=5):
    """A frame big enough that the later lexicographic passes cannot be proved
    inside a small deterministic budget. Fourteen vehicles over five DCFC stalls
    is oversubscribed but feasible — the first pass proves out, the second and
    third run out of budget holding an incumbent."""
    return _frame(
        [_vehicle(f"v-{i}", soc=20 + (i * 7) % 50) for i in range(n_vehicles)],
        [_stall(f"s-{i}") for i in range(n_stalls)],
    )


def test_a_budget_truncated_pass_is_not_reported_complete():
    """FEASIBLE is an incumbent, not a proof, and `complete` must say so.

    CP-SAT returns FEASIBLE when it exhausts the deterministic budget holding a
    solution it never proved minimal. The chain records that incumbent in
    `optima` — correctly, since it is achieved and therefore a sound ceiling for
    the later passes — but the fire record used to read "there is a number here"
    as "this pass held its optimum". A truncated plan was published as a whole
    one, and its unproven T* could be cited as the site's readiness floor.

    The budget is DETERMINISTIC, not a wall clock, so the truncation is a
    property of the instance and reproduces on any machine.
    """
    r = propose(_crowded(), CLASSES, site=SITE, horizon_min=480,
                hour_of_day=7, det_budget_s=0.3)
    s = r["solver"]
    statuses = [p["status"] for p in s["passes"]]
    assert statuses[0] == "OPTIMAL" and "FEASIBLE" in statuses[1:], (
        f"this frame no longer truncates a later pass: {statuses}")
    assert not r["solver"].get("retained_previous"), (
        "a retained pass would prove the old code too; this must be the "
        "FEASIBLE case specifically")
    assert s["complete"] is False, (
        f"complete claimed on statuses {statuses} — a truncated plan reported "
        f"as a whole one")
    # ...and the trace names WHICH pass was unproven, so the record is usable.
    assert [p["proven"] for p in s["passes"]] == [st == "OPTIMAL" for st in statuses]


def test_the_truncation_is_reproducible_not_a_race():
    """The guard above is only meaningful if the same budget truncates the same
    passes every time — otherwise it is a flake waiting to land in CI."""
    a = propose(_crowded(), CLASSES, site=SITE, horizon_min=480,
                hour_of_day=7, det_budget_s=0.3)["solver"]
    b = propose(_crowded(), CLASSES, site=SITE, horizon_min=480,
                hour_of_day=7, det_budget_s=0.3)["solver"]
    assert [p["status"] for p in a["passes"]] == [p["status"] for p in b["passes"]]
    assert a["complete"] == b["complete"] is False


def test_complete_is_still_true_when_every_pass_proves_its_optimum():
    """The other half: the guard above must not simply nail `complete` to False."""
    r = propose(FRAME, CLASSES, site=SITE, hour_of_day=7)
    s = r["solver"]
    assert [p["status"] for p in s["passes"]] == ["OPTIMAL"] * len(s["pass_modes"])
    assert s["complete"] is True


def test_regime_path_is_deterministic():
    a = propose(FRAME, CLASSES, site=SITE, hour_of_day=7)
    b = propose(FRAME, CLASSES, site=SITE, hour_of_day=7)
    assert a["proposals"] == b["proposals"]
    assert a["solver"]["passes"] == b["solver"]["passes"]


def test_regime_path_composes_with_rejection():
    frame = _oversubscribed()
    r = propose(frame, CLASSES, site=SITE, horizon_min=120,
                default_ready_delta_min=60, allow_rejection=True, hour_of_day=7)
    s = r["solver"]
    assert s["regime"] == "dispatch_rush"
    assert s["rejected"], "rejection enabled but nothing was rejected"
    assert s["complete"] is True
    # the peak is read from site_peak_kw, never the rejection-inflated objective
    assert s["site_peak_kw"] is not None and s["site_peak_kw"] < 100_000
    # every declined vehicle still gets a row
    assert {p["entity_id"] for p in r["proposals"]} == {
        v["id"] for v in frame["vehicles"]}
