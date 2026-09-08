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

import forward_proposer  # noqa: E402
from forward_proposer import (  # noqa: E402
    CHEMISTRY_DAILY_SOC_CAP_PCT,
    DEFAULT_DET_BUDGET_S,
    DEFAULT_SERVICEABLE_STATES,
    DEFAULT_TARGET_SOC_PCT,
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
    #: vehicle_class_code mirrors platform here so the class tables below stay
    #: readable; production keys the two apart (L-41), and the bridge joins on
    #: whichever field `class_key` names.
    base = {"id": vid, "soc": soc, "make": platform.title(), "state": state,
            "platform": platform, "vehicle_class_code": platform,
            "stall_id": None, "svc_step": "await",
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
    reason = out["proposals"][0]["proposal"]["rationale"]["reason"]
    #: The reason now names the INLET as well as the kinds (L-42), and says what
    #: the site does offer -- "no capable point" was true and undiagnosable.
    assert "charge_kinds ['dcfc']" in reason and "inlet CCS1" in reason


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


def test_a_wall_clock_solve_reports_itself_unreproducible():
    """The OTHER honesty flag. `complete` is pinned above; `reproducible` was not,
    and it could be hard-coded True with the entire suite green — verified
    2026-09-08 by nailing it and watching 167 tests pass.

    The flag is `status == OPTIMAL or time_limit_s is None`: a proof is
    limit-independent, so it holds whatever the limits were; otherwise the
    search was truncated and only a DETERMINISTIC budget truncates it in the
    same place on every machine. Reporting True for a clock-bounded, unproven
    plan would launder an irreproducible schedule into a run ID, which is the
    one thing the flag exists to prevent.

    THE TEST ITSELF MUST BE DETERMINISTIC, which the first draft was not: it
    used a 0.25 s wall clock to force the flag, and on a loaded box the first
    pass sometimes found no solution at all and raised INFEASIBLE — flaky, one
    failure in three. Here the DETERMINISTIC budget does the truncating (this
    frame reliably leaves a later pass at FEASIBLE) and the wall clock is only
    PRESENT, generous enough never to bite. Present-and-unproven is exactly the
    condition the flag is about.
    """
    frame = _crowded()

    det = propose(frame, CLASSES, site=SITE, horizon_min=480,
                  hour_of_day=7, det_budget_s=0.3)
    assert det["solver"]["reproducible"] is True, (
        "a deterministic-budget solve is reproducible by construction")

    wall = propose(frame, CLASSES, site=SITE, horizon_min=480,
                   hour_of_day=7, det_budget_s=0.3, time_limit_s=120)
    assert not all(p["status"] == "OPTIMAL" for p in wall["solver"]["passes"]), (
        "this frame no longer leaves a pass unproven; the flag would be True "
        "for the legitimate reason and the test would prove nothing")
    assert wall["solver"]["reproducible"] is False, (
        "a wall clock was in play on an unproven plan, so the result is not a "
        "function of (scenario, seed, config) alone and must not claim to be")


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


def test_the_chemistry_cap_reaches_the_production_path(): 
    """R-11 through the BRIDGE, which is where it was dead.

    `_clamp_target` has always capped a target at the class's
    `max_daily_soc_pct`. T13 proves that by calling it directly with a
    hand-built dict — and the production class table has no such column, while
    `frame_to_scenario` copied neither it nor `battery_chemistry`. So every live
    frame reached `_clamp_target` with a class that could not carry a cap, fell
    through to the default 100, and the rule did nothing. T13 stayed green the
    whole time: a guard over a dead path (L-51).

    This asserts the property end-to-end — a frame goes in, and the asset the
    solver is handed carries the capped target.
    """
    classes = {"nmc_ride": {"battery_kwh": 90, "max_charge_kw": 100,
                            "charge_kinds": ["dcfc"], "battery_chemistry": "NMC"}}
    frame = _frame([_vehicle("v-nmc", platform="nmc_ride", soc=30, target_soc=95)],
                   [_stall("s-0")])
    sc, _ = frame_to_scenario(frame, classes, site=SITE, horizon_min=480)

    cname = next(iter(sc["asset_classes"]))
    assert sc["asset_classes"][cname]["max_daily_soc_pct"] == 80, (
        "the bridge did not carry the chemistry cap into the scenario")
    assert sc["assets"][0].target_soc == 80, (
        f"asset asked for {sc['assets'][0].target_soc}% on an NMC pack; R-11 "
        f"caps routine daily cycling at 80%")


def test_an_explicit_cap_beats_the_chemistry_default():
    """A pack that states its own cap is not overruled by the chemistry table."""
    classes = {"odd": {"battery_kwh": 90, "max_charge_kw": 100,
                       "charge_kinds": ["dcfc"], "battery_chemistry": "NMC",
                       "max_daily_soc_pct": 70}}
    sc, _ = frame_to_scenario(
        _frame([_vehicle("v-1", platform="odd", soc=30, target_soc=95)],
               [_stall("s-0")]), classes, site=SITE, horizon_min=480)
    assert sc["assets"][0].target_soc == 70


def test_an_unknown_chemistry_is_not_given_a_guessed_cap():
    """LFP tolerates high SoC and is not in the table; a chemistry we have no
    evidence for must get NO cap rather than an invented one. Silence is the
    honest answer, and it keeps legacy behaviour byte-for-byte."""
    assert "LFP" not in CHEMISTRY_DAILY_SOC_CAP_PCT
    classes = {"lfp": {"battery_kwh": 90, "max_charge_kw": 100,
                       "charge_kinds": ["dcfc"], "battery_chemistry": "LFP"}}
    sc, _ = frame_to_scenario(
        _frame([_vehicle("v-1", platform="lfp", soc=30, target_soc=95)],
               [_stall("s-0")]), classes, site=SITE, horizon_min=480)
    assert "max_daily_soc_pct" not in sc["asset_classes"][next(iter(sc["asset_classes"]))]
    assert sc["assets"][0].target_soc == 95


def test_a_class_with_no_chemistry_at_all_is_unchanged():
    """Two of the nine live classes declare no chemistry. They must behave
    exactly as they did before this fix existed."""
    classes = {"plain": {"battery_kwh": 90, "max_charge_kw": 100,
                         "charge_kinds": ["dcfc"]}}
    sc, _ = frame_to_scenario(
        _frame([_vehicle("v-1", platform="plain", soc=30, target_soc=95)],
               [_stall("s-0")]), classes, site=SITE, horizon_min=480)
    assert sc["assets"][0].target_soc == 95


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
    #: The regime skipped min_flow, so the CHAIN HELD no flow optimum -- that
    #: is what optima_reached says. total_flow_min is now measured off the
    #: shipped plan (L-22), and a plan that was never flow-optimized still has
    #: a flow time; reporting it as None said "no number" when the truth was
    #: "a number nobody minimized".
    assert "min_flow" not in s["optima_reached"]
    assert s["total_flow_min"] > 0


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


# ---------------------------------------------------------------------------
# L-24: one null in one row must not cost the batch, and one default for
# target_soc must serve both the admission test and the plan.
# ---------------------------------------------------------------------------

def _mixed(bad):
    """`bad` beside two ordinarily plannable vehicles and two stalls."""
    return _frame([_vehicle("v-ok1", soc=20), bad, _vehicle("v-ok2", soc=35)],
                  [_stall("s-1"), _stall("s-2")])


def _reason(rows, vid):
    row = next(r for r in rows if r["entity_id"] == vid)
    return row["proposal"].get("rationale", {}).get("reason", "")


def test_a_null_soc_abstains_instead_of_killing_the_batch():
    r = propose(_mixed(_vehicle("v-null", soc=None)), CLASSES, site=SITE)
    ids = {p["entity_id"] for p in r["proposals"]}
    assert ids == {"v-ok1", "v-null", "v-ok2"}, "a row per vehicle, always"
    assert "no readable soc" in _reason(r["proposals"], "v-null")
    planned = {p["entity_id"] for p in r["proposals"]
               if not p["proposal"].get("abstain")}
    assert planned == {"v-ok1", "v-ok2"}, "the rest of the batch survives it"


def test_a_missing_soc_key_is_the_same_abstention():
    bad = _vehicle("v-nosoc")
    del bad["soc"]
    r = propose(_mixed(bad), CLASSES, site=SITE)
    assert "no readable soc" in _reason(r["proposals"], "v-nosoc")
    assert len(r["proposals"]) == 3


def test_an_unreadable_soc_is_an_abstention_not_a_raise():
    r = propose(_mixed(_vehicle("v-junk", soc="n/a")), CLASSES, site=SITE)
    assert "no readable soc" in _reason(r["proposals"], "v-junk")


def test_one_default_for_target_soc_serves_both_admission_and_plan():
    #: The two defaults were 100 (admission) and 90 (the plan). At soc 95 that
    #: pair admitted a vehicle and then planned it past its own target. Under
    #: one default of 90 it is simply not a candidate -- and the vehicle that
    #: IS a candidate is planned against the same 90 that admitted it.
    sc, abst = frame_to_scenario(
        _frame([_vehicle("v-high", soc=95, target_soc=None),
                _vehicle("v-low", soc=30, target_soc=None)],
               [_stall("s-1")]),
        CLASSES, site=SITE)
    explicit = sc["assets_spec"]["explicit"]
    assert [a["aid"] for a in explicit] == ["v-low"], "95 is past a target of 90"
    assert explicit[0]["target_soc"] == DEFAULT_TARGET_SOC_PCT == 90
    assert abst == []


def test_a_target_that_rounds_onto_the_soc_abstains_rather_than_planning_a_no_op():
    #: 89.6 < 90.0 as floats, so the admission test lets it through; both round
    #: to 90, so the kernel would build no charge segment for it at all. The
    #: guard compares the integers the kernel actually receives.
    r = propose(_mixed(_vehicle("v-edge", soc=89.6, target_soc=90)),
                CLASSES, site=SITE)
    assert "at or below soc 90" in _reason(r["proposals"], "v-edge")
    assert len(r["proposals"]) == 3


def test_a_custom_predicate_cannot_smuggle_an_impossible_asset_past_the_bridge():
    sc, abst = frame_to_scenario(
        _frame([_vehicle("v-full", soc=95, target_soc=90)], [_stall("s-1")]),
        CLASSES, site=SITE, serviceable=lambda v: True)
    assert sc["assets_spec"]["explicit"] == []
    assert len(abst) == 1 and "at or below soc 95" in (
        abst[0]["proposal"]["rationale"]["reason"])


# ---------------------------------------------------------------------------
# L-25: the advisory row must carry the taper it plans.
# ---------------------------------------------------------------------------

def _charging_rows(result):
    return [p for p in result["proposals"] if not p["proposal"].get("abstain")]


def test_the_advisory_row_carries_the_taper_it_plans():
    #: waymo's curve breaks at 70%, so 30 -> 90 is two segments at two kW.
    r = propose(_frame([_vehicle("v-1", soc=30, target_soc=90)], [_stall("s-1")]),
                CLASSES, site=SITE)
    row = _charging_rows(r)[0]["proposal"]
    segs = row["rationale"]["segments"]
    assert len(segs) >= 2, f"this frame no longer tapers: {segs}"
    assert {s["kw"] for s in segs} != {segs[0]["kw"]}, "the taper is flat"
    #: The energy is the integral of the step function, not the rectangle the
    #: row used to invite. The rectangle is strictly larger here, which is the
    #: settlement error L-25 describes, in kWh.
    span_h = (row["rationale"]["planned_end_min"]
              - row["rationale"]["planned_start_min"]) / 60.0
    assert row["rationale"]["planned_kwh"] < row["requested_kw"] * span_h
    assert row["rationale"]["planned_kwh"] == pytest.approx(
        sum(s["kw"] * (s["end"] - s["start"]) for s in segs) / 60.0, abs=1e-3)


def test_requested_kw_is_the_peak_segment_not_the_first():
    #: A curve that ACCELERATES: the first segment is the weakest. First-segment
    #: kW would under-report what the connector must deliver by 2x.
    classes = {"rising": {"battery_kwh": 90, "max_charge_kw": 100,
                          "charge_kinds": ["dcfc"],
                          "energy_curve": [{"above_soc_pct": 0, "accept_frac": 0.5},
                                           {"above_soc_pct": 50, "accept_frac": 1.0}]}}
    r = propose(_frame([_vehicle("v-1", platform="rising", soc=30, target_soc=90)],
                       [_stall("s-1")]),
                classes, site=SITE)
    row = _charging_rows(r)[0]["proposal"]
    segs = row["rationale"]["segments"]
    assert segs[0]["kw"] < max(s["kw"] for s in segs), "not a rising curve"
    assert row["requested_kw"] == max(s["kw"] for s in segs)


# ---------------------------------------------------------------------------
# L-23: the hot path must report completeness the way the regime path does.
# ---------------------------------------------------------------------------

def test_the_default_path_reports_completeness_and_retention():
    s = propose(FRAME, CLASSES, site=SITE)["solver"]
    assert s["complete"] is True
    assert s["retained_previous"] is False
    assert s["reproducible"] is True


def test_a_truncated_default_path_is_not_reported_complete():
    #: The same instance the regime-path guard uses, on the branch production
    #: actually runs. Before L-23 this record had no `complete` at all, so a
    #: caller reading solver.get("complete") got None on EVERY hot-path
    #: invocation and could not tell a truncated plan from a whole one.
    s = propose(_crowded(), CLASSES, site=SITE, horizon_min=480,
                det_budget_s=0.3)["solver"]
    assert "FEASIBLE" in (s["pass1_status"], s["pass2_status"]), (
        f"this frame no longer truncates: {s['pass1_status']}/{s['pass2_status']}")
    assert s["complete"] is False


# ---------------------------------------------------------------------------
# L-22: the published numbers describe the plan that ships.
# ---------------------------------------------------------------------------

def _peak_from_rows(result):
    """The site's instantaneous peak, rebuilt from the ADVISORY ROWS alone."""
    events = []
    for p in _charging_rows(result):
        for seg in p["proposal"]["rationale"]["segments"]:
            events += [(seg["start"], 1, seg["kw"]), (seg["end"], -1, seg["kw"])]
    peak = running = 0
    for _t, sign, kw in sorted(events, key=lambda e: (e[0], e[1])):
        running += sign * kw
        peak = max(peak, running)
    return peak


@pytest.mark.parametrize("kwargs", [{}, {"hour_of_day": 7}])
def test_the_published_peak_is_a_property_of_the_shipped_plan(kwargs):
    r = propose(FRAME, CLASSES, site=SITE, **kwargs)
    assert r["solver"]["site_peak_kw"] == _peak_from_rows(r) > 0
    assert r["solver"]["total_tardy_min"] == sum(
        p["proposal"]["rationale"]["tardy_min"] for p in _charging_rows(r))


def test_the_optima_each_pass_reached_are_kept_alongside_the_measurement():
    s = propose(FRAME, CLASSES, site=SITE, hour_of_day=7)["solver"]
    assert set(s["optima_reached"]) == set(s["pass_modes"])
    #: A correct chain measures at or below every ceiling it held.
    assert s["total_tardy_min"] <= s["optima_reached"]["min_tardy"]
    assert s["site_peak_kw"] <= s["optima_reached"]["min_peak"]
    assert s["total_flow_min"] <= s["optima_reached"]["min_flow"]


def test_a_dropped_ceiling_raises_instead_of_publishing_a_number_the_plan_lacks(
        monkeypatch):
    """The failure L-22 says must not be able to ship silently.

    A chain that reports an optimum its final plan does not honour is a chain
    bug -- the number would be published under a run ID against an artifact
    that does not have it. Simulated here by returning a real plan with a
    fabricated optimum, which is exactly the shape a dropped ceiling takes.
    """
    real = forward_proposer.lexicographic_solve_traced

    def _liar(sc, modes, *, budget=None):
        plan, optima, passes = real(sc, modes, budget=budget)
        return plan, {**optima, "min_peak": 1}, passes

    monkeypatch.setattr(forward_proposer, "lexicographic_solve_traced", _liar)
    with pytest.raises(forward_proposer.ChainError, match="min_peak ceiling"):
        propose(FRAME, CLASSES, site=SITE, hour_of_day=7)


# ---------------------------------------------------------------------------
# L-42: charge_kinds is required, and a plug that does not fit is not a
# scheduling preference.
# ---------------------------------------------------------------------------

def test_a_class_without_charge_kinds_is_refused_not_defaulted():
    #: battery_kwh raises; charge_kinds used to default to BOTH charging types,
    #: and it is the field that decides which stall types a vehicle may reach.
    classes = {"waymo": {k: v for k, v in CLASSES["waymo"].items()
                         if k != "charge_kinds"}}
    with pytest.raises(FrameError, match="charge_kinds"):
        frame_to_scenario(_frame([_vehicle("v-1")], [_stall("s-1")]),
                          classes, site=SITE)


def test_a_pad_inlet_asset_is_never_proposed_onto_a_ccs_charger():
    """The physically impossible assignment, refused at the bridge.

    An AMR with a PAD inlet and a site of CCS1 DCFC stalls: the kinds match
    (`dcfc` is in the class's charge_kinds), so before L-42 the vehicle was
    proposed a stall whose connector it cannot physically accept. Nothing
    downstream checks -- ottoq_l2_external_proposal validates occupancy,
    reservation, station_state and heartbeat, but not the plug.
    """
    classes = {"amr": {"battery_kwh": 20, "max_charge_kw": 15,
                       "charge_kinds": ["dcfc", "l2"]}}
    r = propose(_frame([_vehicle("v-amr", platform="amr", soc=30,
                                 inlet_type="PAD", inlet_max_kw=15.0)],
                       [_stall("s-1"), _stall("s-2", kind="l2", kw=11)]),
                classes, site=SITE)
    assert r["planned"] == 0 and r["abstained"] == 1
    reason = r["proposals"][0]["proposal"]["rationale"]["reason"]
    assert "inlet PAD" in reason and "CCS1" in reason


def test_a_pad_asset_is_planned_onto_the_pad_and_not_onto_the_ccs_stall():
    """The other half: matching is a MATCH, not a blanket refusal.

    Two L2 points side by side, one PAD and one CCS1. The kinds are identical,
    so only the connector distinguishes them -- and the PAD asset must land on
    the PAD point. This is the assertion the composite capability label exists
    to make possible; the kernel itself has no notion of a connector.
    """
    classes = {"amr": {"battery_kwh": 20, "max_charge_kw": 15,
                       "charge_kinds": ["l2"]}}
    pad = _stall("s-pad", kind="l2", kw=15)
    pad["connector_type"] = "PAD"
    r = propose(_frame([_vehicle("v-amr", platform="amr", soc=30,
                                 inlet_type="pad", inlet_max_kw=15.0)],
                       [pad, _stall("s-ccs", kind="l2", kw=11)]),
                classes, site=SITE)
    assert r["planned"] == 1 and r["abstained"] == 0
    assert _charging_rows(r)[0]["proposal"]["stall_id"] == "s-pad"


def test_inlet_matching_is_case_and_space_insensitive():
    frame = _frame([_vehicle("v-1", inlet_type=" ccs1 ")],
                   [_stall("s-1")])   # the stall says "CCS1"
    r = propose(frame, CLASSES, site=SITE)
    assert r["planned"] == 1 and r["abstained"] == 0


def test_a_vehicle_with_no_inlet_type_abstains_rather_than_guessing():
    bad = _vehicle("v-1")
    bad["inlet_type"] = None
    r = propose(_frame([bad, _vehicle("v-2")], [_stall("s-1")]),
                CLASSES, site=SITE)
    assert "no inlet_type" in _reason(r["proposals"], "v-1")
    assert r["planned"] == 1


def test_a_stall_with_no_connector_type_is_not_a_capability():
    st = _stall("s-1")
    st["connector_type"] = None
    with pytest.raises(FrameError, match="declare an accepted inlet"):
        frame_to_scenario(_frame([_vehicle("v-1")], [st]), CLASSES, site=SITE)


def test_the_proposal_row_reports_the_databases_stall_type_not_the_label():
    r = propose(_frame([_vehicle("v-1", soc=30)], [_stall("s-1")]),
                CLASSES, site=SITE)
    row = _charging_rows(r)[0]["proposal"]
    assert row["stall_type"] == "dcfc", (
        "the gate router receives the database's vocabulary, never dcfc@CCS1")


def test_the_dcfc_cooldown_survives_the_capability_label():
    """The kernel's `kind == "dcfc"` fallback cannot see a composite label.

    So the bridge DECLARES the gap. Without this the 18-minute min-gap on a
    DCFC point vanishes from every production frame, silently.
    """
    sc, _ = frame_to_scenario(_frame([_vehicle("v-1")], [_stall("s-1")]),
                              CLASSES, site=SITE)
    assert sc["service_points"][0]["min_gap_min"] == SITE["dcfc_cooldown_min"]
    #: ...and an L2 point still has none.
    sc2, _ = frame_to_scenario(
        _frame([_vehicle("v-1")], [_stall("s-2", kind="l2", kw=11)]),
        CLASSES, site=SITE)
    assert sc2["service_points"][0]["min_gap_min"] == 0


# ---------------------------------------------------------------------------
# L-52: the production entry point takes the doctrine as a parameter.
# ---------------------------------------------------------------------------

def test_propose_resolves_the_regime_from_the_intent_it_is_given():
    """The kernel default was the only doctrine reachable from here (L-52).

    A pack whose priorities genuinely differ could not express that through the
    production proposer at all -- and the default artifact is robotaxi-flavoured
    in places a pack then reads unconditionally.
    """
    import dataclasses
    from intent.intent import load_intent

    base = load_intent()
    pack = dataclasses.replace(
        base,
        regimes=tuple(dataclasses.replace(r, priority=tuple(reversed(r.priority)))
                      for r in base.regimes))

    default = propose(FRAME, CLASSES, site=SITE, hour_of_day=7)["solver"]
    packed = propose(FRAME, CLASSES, site=SITE, hour_of_day=7,
                     intent=pack)["solver"]
    assert default["pass_modes"] != packed["pass_modes"], (
        "the intent override did not reach the regime resolver")
    #: The readiness floor is structural and survives any doctrine.
    assert packed["pass_modes"][0] == "min_tardy"


# ---------------------------------------------------------------------------
# L-42, production half: the engine's own Multi rule, mirrored.
# ---------------------------------------------------------------------------

def _multi(sid, kind="dcfc", kw=350, supported=("CCS1", "NACS")):
    """A stall in the shape the flagship depot actually holds: every charging
    stall is connector_type 'Multi' with a supported_inlet_types list."""
    st = _stall(sid, kind=kind, kw=kw)
    st["connector_type"] = "Multi"
    st["supported_inlet_types"] = list(supported)
    return st


def test_a_multi_stall_serves_every_inlet_it_declares():
    frame = _frame([_vehicle("v-ccs", soc=30, inlet_type="CCS1"),
                    _vehicle("v-nacs", platform="tesla", soc=30,
                             inlet_type="NACS")],
                   [_multi("s-1"), _multi("s-2")])
    classes = {**CLASSES, "tesla": {"battery_kwh": 75, "max_charge_kw": 250,
                                    "charge_kinds": ["dcfc"]}}
    r = propose(frame, classes, site=SITE)
    assert r["planned"] == 2 and r["abstained"] == 0


def test_a_multi_stall_refuses_an_inlet_it_does_not_declare():
    #: The exact discrimination the L1 rule makes: Multi is not a wildcard, it
    #: is a declared list. A CHAdeMO vehicle at a CCS1+NACS stall is refused.
    frame = _frame([_vehicle("v-cha", soc=30, inlet_type="CHAdeMO")],
                   [_multi("s-1")])
    r = propose(frame, CLASSES, site=SITE)
    assert r["planned"] == 0 and r["abstained"] == 1
    reason = r["proposals"][0]["proposal"]["rationale"]["reason"]
    assert "inlet CHADEMO" in reason and "CCS1" in reason and "NACS" in reason


def test_a_multi_stall_with_no_supported_list_serves_nobody():
    #: Empty is not a wildcard. The L1 rule reads
    #: COALESCE(supported_inlet_types, ARRAY[]::text[]) and an empty array
    #: matches no inlet; a bridge that treated it as "anything" would put every
    #: vehicle on a plug the engine itself would then refuse.
    with pytest.raises(FrameError, match="declare an accepted inlet"):
        frame_to_scenario(_frame([_vehicle("v-1")], [_multi("s-1", supported=())]),
                          CLASSES, site=SITE)


def test_a_mixed_site_routes_each_inlet_to_the_plug_that_fits():
    """One NACS-only DCFC beside one CCS1-only DCFC, and two vehicles."""
    ccs, nacs = _stall("s-ccs"), _stall("s-nacs")
    nacs["connector_type"] = "NACS"
    classes = {**CLASSES, "tesla": {"battery_kwh": 75, "max_charge_kw": 250,
                                    "charge_kinds": ["dcfc"]}}
    r = propose(_frame([_vehicle("v-ccs", soc=30, inlet_type="CCS1"),
                        _vehicle("v-nacs", platform="tesla", soc=30,
                                 inlet_type="NACS")],
                       [ccs, nacs]), classes, site=SITE)
    assert r["planned"] == 2
    where = {p["entity_id"]: p["proposal"]["stall_id"]
             for p in _charging_rows(r)}
    assert where == {"v-ccs": "s-ccs", "v-nacs": "s-nacs"}


def test_the_capability_label_is_order_independent():
    """Same site, supported list written both ways: identical scenario."""
    a, _ = frame_to_scenario(
        _frame([_vehicle("v-1")], [_multi("s-1", supported=("CCS1", "NACS"))]),
        CLASSES, site=SITE)
    b, _ = frame_to_scenario(
        _frame([_vehicle("v-1")], [_multi("s-1", supported=("NACS", "CCS1"))]),
        CLASSES, site=SITE)
    assert a["service_points"] == b["service_points"]
    assert a["asset_classes"] == b["asset_classes"]
