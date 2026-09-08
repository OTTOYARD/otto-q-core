"""The forward orchestrator as a PRODUCTION PROPOSER — propose/dispose, never write.

THE TWO LAWS, restated where they bind (CLAUDE.md 2.5, "agents propose, solver
disposes"):

  1. This module NEVER writes anything. propose() returns rows; whoever calls it
     (an edge function, a founder-gated integration) inserts them into
     ottoq_external_proposals, where the deferral pattern gives an in-flight
     proposal its one-tick right-of-first-refusal before the local decide path
     pre-empts. The DISPOSER remains the production decide path -- exactly the
     seat cuOpt occupies today, and deliberately no more.
  2. No proposal is ever a command. Every row is advisory and carries abstain
     semantics. EXPIRY IS THE CALLER'S, and saying otherwise here was wrong: no
     row this module builds carries expires_at or a TTL -- grep the file, the
     only match used to be the law itself. proposer/README.md has it right
     ("inserts the rows with sim_run_id/depot_id/expires_at"), because the
     expiry belongs to the insert, where the sim run and depot are known and
     the deferral pattern's one-tick window is measured. A law a module states
     about its own output must be enforceable by that module; this one is an
     obligation on its caller, and it is now stated as one.

THE CONTRACT SHAPES ARE THE PRODUCTION ONES, verbatim. The input is the decision
frame as ottoq_build_decision_frame emits it (keys: vehicles, stalls, sessions,
energy, bess; vehicle rows carry id/soc/state/stall_id/inlet_type/target_soc/
inlet_max_kw; stall rows carry id/type/status/connector_type/connector_max_kw).
The output rows match ottoq_external_proposals and its observed proposal jsonb
(verb=assign_stall, stall_id, stall_type, vehicle_id, requested_kw, rationale,
resolved_action_context) so the existing gate router needs nothing new to
receive them.

WHAT THE FRAME DOES NOT CARRY, declared rather than guessed -- this is the
separation discipline applied to production data:

  - battery_kwh and the energy curve: a frame has soc (%) but not capacity, so
    energy is uncomputable from the frame alone. The caller supplies a
    class_table (platform -> battery_kwh / max_charge_kw / energy_curve /
    charge_kinds); in production that join is ottoq_vehicle_classes, which
    CLAUDE.md 2.3 names as the asset profile. There is NO default -- a made-up
    battery size would be a silently wrong plan for every vehicle.
  - required-ready-times: the frame does not say when each vehicle must be
    ready; production would join visit needs / dispatch schedules. The caller
    passes ready_by_min per vehicle or one default delta, and every proposal's
    rationale records which was used, so a schedule built on a default is
    labeled as one.

The solver underneath is policies/forward.py's generalized lexicographic chain
on the kernel model. By default it runs the cheap two-pass solve (minimize
tardiness, then hold it and minimize the site's instantaneous peak) -- the hot-
path default, because the third lever (min_flow / dwell) does not prove OPTIMAL
and costs ~10-20x the two-pass solve. Pass hour_of_day to resolve the active
regime from the commander's intent (intent/) and run that regime's ordered pass
sequence instead, so the schedule follows doctrine. The kernel stays sector-
blind; this module is the adapter between one database's vocabulary and the
kernel's declared-data world, which is exactly where CLAUDE.md says adapters
live.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Callable

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "solvers" / "cpsat"))
sys.path.insert(0, str(HERE.parent / "policies"))

from model import build_and_solve, materialize  # noqa: E402
from forward import lexicographic_solve_traced     # noqa: E402
from intent.solve import pass_sequence             # noqa: E402
from regime import resolve_active                  # noqa: E402

#: Vehicle states that mean "on site and awaiting or receiving service". Being a
#: DEFAULT and not a constant baked into the solve is the point: the kernel model
#: never sees state names at all, and a caller with better knowledge passes its
#: own predicate.
#:
#: EVERY MEMBER IS A LABEL OF THE PRODUCTION `vehicle_state` ENUM. It was not.
#: The first version was written from memory and named three states the type
#: cannot hold -- `awaiting_stall`, `in_queue`, `charge_scheduled` -- while
#: omitting `staged_awaiting_service`, which is the enum's actual "on site,
#: waiting" label and one of the busiest states the depot has (3,386 transitions
#: across 113 of 116 flagship vehicles in 24h; 16 vehicles held it at the
#: busiest sampled minute against 19 the old set could see). Those 16 were
#: filtered out before frame_to_scenario, so they got neither a proposal nor an
#: abstention -- exactly the silent drop plan_to_proposals forbids.
#:
#: The full vocabulary is committed at db/contracts/vehicle_state_enum.json and
#: tests/-- test_forward_proposer asserts every member below is one of its labels,
#: so this set cannot drift from the type again without CI saying so.
#:
#: Deliberately EXCLUDED, though they are real labels: `charge_complete_holding`,
#: `service_complete_holding` and `staged_for_departure`. Those are post-service
#: states -- the vehicle is done and staged out. This proposer proposes charge
#: assignments; a caller that wants to schedule non-charge service on a holding
#: vehicle passes its own predicate.
#: R-11, THE CHEMISTRY DAILY-SoC CAP, AS A TRANSLATION AND NOT A DECISION.
#:
#: The kernel already enforces this rule: model.py::_clamp_target caps a target
#: at the asset class's `max_daily_soc_pct` and defaults to 100 when the class
#: declares none. What was missing is the bridge between the two vocabularies.
#: The production class table (`ottoq_vehicle_classes`) has NO max_daily_soc_pct
#: column -- it declares `battery_chemistry` (NMC, NCA, or null) -- and
#: frame_to_scenario never copied either field. So _clamp_target read a class
#: dict that could not contain a cap, fell through to 100, and the rule was a
#: NO-OP ON EVERY LIVE FRAME while T13 passed by calling _clamp_target directly
#: with a hand-built dict. A green guard over a dead path (finding L-51).
#:
#: The mapping is DATA WITH A CITATION, not a scheduling opinion, which is why
#: it may live in the bridge: adapters translate, never decide. NMC degrades
#: sharply above ~80% SoC (Wikner & Thiringer 2018, doi:10.3390/app8101825;
#: Keil et al. 2016, doi:10.1149/2.0411609jes) -- the same sources R-11 and the
#: kernel docstring already cite, and 80 is the value the canonical scenarios
#: and T13 already use. NCA shares the high-SoC degradation mechanism and is
#: capped with it. A chemistry not named here gets NO cap rather than a guessed
#: one: an unknown chemistry is not evidence for a number.
#:
#: An explicit `max_daily_soc_pct` on the class always wins, so a pack can state
#: a cap the chemistry table does not know about, and this stays advisory data.
CHEMISTRY_DAILY_SOC_CAP_PCT = {
    "NMC": 80,
    "NCA": 80,
}


#: THE PROPOSER IS ALWAYS BOUNDED. propose() used to default det_budget_s and
#: time_limit_s to None -- no budget of any kind -- and orchestrate() passed
#: neither, so nothing in the shipped call graph ever bounded a solve. An
#: unbounded proposal is two problems at once: it can miss the tick it was
#: meant to occupy, and its cost is a property of the box rather than of the
#: instance, so it is not reproducible under a run ID.
#:
#: The budget is DETERMINISTIC WORK, not wall-clock seconds, so the same frame
#: costs the same budget on any machine. Measured on this codebase's own
#: two-pass hot path (both passes get the budget, and pass 2 spends all of it):
#:
#:     10 vehicles / 4 stalls   det_budget 2.0  ->   4.4 s wall
#:     20 vehicles / 8 stalls   det_budget 2.0  ->  12.6 s wall
#:     44 vehicles / 16 stalls  det_budget 2.0  ->  94.8 s wall
#:
#: 2.0 is an engineering default, not a sourced number: it keeps a tick-sized
#: frame inside a 30-second tick (the interval every run in the engine uses)
#: with room for model construction. It is NOT enough to make a 44-vehicle
#: frame fit that tick -- see max_assets on propose() and the note in
#: proposer/README.md. Callers with a different tick pass their own.
DEFAULT_DET_BUDGET_S = 2.0

DEFAULT_SERVICEABLE_STATES = frozenset({
    "arrived_at_gate", "staged_awaiting_service", "charging_dcfc", "charging_l2",
})

#: Stall types that can never charge anything, regardless of connector fields.
NON_CHARGING_TYPES = frozenset({"staging"})

#: THE PRODUCTION JOIN KEY (finding L-41). `ottoq_vehicle_classes` is keyed by
#: vehicle_class_code; this bridge keyed its class table on the frame's
#: `platform`, which that table does not have a column for, so the join the
#: README described could not be made. Migration 0209 puts the key in the frame
#: and proposer/class_table.py writes the column projection; this is the field
#: the two now meet on. 220 of the flagship depot's 221 autonomous vehicles
#: carry it; the one that does not gets an abstention naming the field, which
#: is the honest answer and not a guessed battery.
DEFAULT_CLASS_KEY = "vehicle_class_code"

#: INLET COMPATIBILITY, EXPRESSED IN THE ONLY VOCABULARY THE KERNEL HAS
#: (finding L-42).
#:
#: The kernel's capability model is one string: a service point declares a
#: `kind`, an asset class declares the `charge_kinds` it can use, and the model
#: chooses among points whose kind the class names (model.py:437). The kernel
#: knows nothing about connectors and must not -- an inlet is a sector fact and
#: the kernel never learns what sector it is in. So the BRIDGE folds the
#: connector INTO the capability label: a point is `dcfc@CCS1`, or
#: `dcfc@CCS1+NACS` for a multi-standard one, and a vehicle may use exactly
#: those labels whose inlet set contains its own inlet.
#:
#: What this closes: `charge_kinds` alone decided which stall types a vehicle
#: could be sent to, and frame_to_scenario read NEITHER the vehicle's
#: `inlet_type` NOR the stall's `connector_type` -- both of which the frame
#: already carries. A PAD-inlet AMR was proposable onto a CCS1 DCFC stall, and
#: the consumer (ottoq_l2_external_proposal) validates occupancy, reservation,
#: station_state and heartbeat but not the plug, so nothing downstream would
#: have caught it either.
#:
#: THE RULE IS NOT INVENTED HERE. The engine already owns it, in the L1 rule
#: that guards the live decide path (db/baseline/functions_public.sql:6632):
#:
#:     a `Multi` stall passes iff the vehicle's inlet is in the stall's
#:     supported_inlet_types; otherwise the connector_type must equal the
#:     inlet_type exactly.
#:
#: This is a faithful translation of that rule into the kernel's declared-data
#: vocabulary, not a second opinion about plugs. Measured on the flagship depot
#: 2026-09-08: all 84 charging stalls are `Multi` with supported {CCS1, NACS},
#: and the 220 autonomous vehicles carry CCS1 (158) or NACS (62) -- so a bridge
#: that compared connector_type to inlet_type literally would have abstained on
#: every vehicle at the site, and one that ignored both proposed every vehicle
#: onto every plug. Neither is the rule the engine actually runs.
CAPABILITY_SEP = "@"
INLET_SEP = "+"

#: The connector_type value that means "this point declares its supported inlets
#: separately", per the L1 rule above. Compared after normalization.
MULTI_STANDARD_CONNECTOR = "MULTI"


def _connector(value: Any) -> str | None:
    """A connector/inlet label normalized for comparison, or None if unstated.

    Case and surrounding space are formatting, not facts: a stall recorded as
    'ccs1 ' and a vehicle recorded as 'CCS1' are the same plug, and treating
    them as different would abstain on every vehicle at that site while the
    reason said "no capable point", which is true and useless.
    """
    if value is None:
        return None
    text = str(value).strip().upper()
    return text or None


def _accepted_inlets(stall: dict) -> frozenset[str]:
    """Which inlets this stall accepts -- the L1 rule, read off the frame row.

    Empty means the point can serve nobody: an unstated connector, a
    NonCharging bay, or a multi-standard stall that declares no supported list.
    Empty is not a wildcard. Guessing a plug is how an AMR ends up at a 350 kW
    DC connector it cannot physically take.
    """
    conn = _connector(stall.get("connector_type"))
    if conn is None:
        return frozenset()
    if conn == MULTI_STANDARD_CONNECTOR:
        supported = stall.get("supported_inlet_types") or ()
        return frozenset(filter(None, (_connector(i) for i in supported)))
    return frozenset({conn})


def _capability(kind: str, inlets) -> str:
    """The kernel-side capability label for (stall type, accepted inlets)."""
    return f"{kind}{CAPABILITY_SEP}{INLET_SEP.join(sorted(inlets))}"


def _capability_kind(cap: str) -> str:
    return cap.split(CAPABILITY_SEP, 1)[0]


def _capability_inlets(cap: str) -> frozenset[str]:
    return frozenset(cap.split(CAPABILITY_SEP, 1)[1].split(INLET_SEP))


class FrameError(ValueError):
    """A frame or class table this bridge refuses to guess around."""


class ChainError(RuntimeError):
    """The shipped plan does not honour a ceiling the chain says it holds.

    Distinct from FrameError on purpose: FrameError means the caller handed
    this bridge something it will not guess around, ChainError means the
    lexicographic chain itself is broken. A caller may sensibly catch the
    first and log an abstention; catching the second and shipping the plan
    anyway is exactly what finding L-22 says must stop being possible.
    """


#: The reproducibility keys the MODEL says a run needs and the fire record
#: dropped (finding L-43). model.py records ortools_version in every plan's
#: `repro` block and states in its own comment why: measured across 9.11 and
#: 9.15, every objective value is identical but all four committed plans differ
#: -- the two versions break ties among equally-optimal schedules differently,
#: so WHICH asset goes to WHICH point at WHICH minute moves. The schedule ships;
#: the objective is just a number about it. A fire record without the version
#: therefore cannot reproduce the plan it describes, which is the whole job of a
#: fire record. det_budget_s and wall_limit_s travel with it for the same
#: reason: they are what truncated the search, when anything did.
_REPRO_KEYS = ("ortools_version", "det_budget_s", "wall_limit_s")


def _repro_identity(*plans: dict) -> dict:
    """The reproducibility identity of the plan that ships.

    Plans are consulted in order and the FIRST that carries a repro block wins:
    the final plan normally, falling back to an earlier pass when the final one
    is a retained plan whose repro block is the earlier pass's anyway.
    """
    for plan in plans:
        repro = plan.get("repro") or {}
        if repro:
            return {k: repro.get(k) for k in _REPRO_KEYS}
    return {k: None for k in _REPRO_KEYS}


def _measure_plan(plan: dict) -> dict:
    """The three published KPIs, MEASURED OFF THE PLAN THAT SHIPS (finding L-22).

    The fire record used to publish `optima['min_tardy']`, `optima['min_peak']`
    and `optima['min_flow']` -- the values the 1st, 2nd and 3rd passes REACHED
    -- as though they described `final_plan`, which is produced by a later pass
    than most of them. Nothing re-derived them from the artifact. So the entire
    correctness of a published number rested on the ceiling threading in
    policies/forward.py being right, and a threading bug would have shipped a
    number the plan does not have, under a run ID, silently. Doctrine 5 says no
    number ships without a run ID; it means no number ships without the artifact
    it describes, either.

    Each figure is computed with the SAME definition the model optimizes, so
    measured and optimum are comparable and _check_optima can assert on them:

      total_tardy_min  sum(tardy_min) over served assets  == the model's
                       sum(all_tardy) (a rejected asset carries None here and
                       contributes zero there).
      total_flow_min   sum(finish) over served assets     == sum(all_finish).
      site_peak_kw     the max of the charge-segment kW step function == the
                       AddCumulative(power_intervals, power_demands) the
                       min_peak pass minimizes: power_intervals ARE the charge
                       segments and power_demands ARE their kW (model.py:461).
                       Measured rather than read from plan['site_peak_kw']
                       because that field exists only when a min_peak pass
                       produced the final plan -- a flow-last regime ships a
                       plan that does not carry it at all.
    """
    assets = plan.get("assets", [])
    events: list[tuple[int, int, int]] = []
    for a in assets:
        for op in a.get("ops", []):
            if op.get("op") != "charge":
                continue
            for seg in op.get("segments", []):
                #: Half-open [start, end): a segment ending at minute t and one
                #: starting at t do not overlap, so ends are applied first at a
                #: shared coordinate (-1 sorts before +1).
                events.append((seg["start"], 1, seg["kw"]))
                events.append((seg["end"], -1, seg["kw"]))
    peak = running = 0
    for _t, sign, kw in sorted(events, key=lambda e: (e[0], e[1])):
        running += sign * kw
        peak = max(peak, running)
    return {
        "total_tardy_min": sum(a["tardy_min"] for a in assets
                               if a.get("tardy_min") is not None),
        "total_flow_min": sum(a["finish"] for a in assets
                              if a.get("finish") is not None),
        "site_peak_kw": peak,
    }


#: Which measured figure answers to which pass's optimum.
_OPTIMUM_OF = {"min_tardy": "total_tardy_min", "min_peak": "site_peak_kw",
               "min_flow": "total_flow_min"}


def _check_optima(measured: dict, optima: dict) -> None:
    """Every pass's ceiling must be honoured by the plan that ships.

    A later pass holds each earlier optimum as a hard `<=`, and the last pass's
    own optimum is achieved by its own plan, so `measured <= optimum` is true
    of a correct chain for EVERY pass -- including a budget-truncated one,
    whose recorded value is an incumbent a real solution achieved. A violation
    is therefore not a tolerance question and not a caller's problem: it means
    a ceiling was dropped between passes, and the number about to be published
    is not a number this plan has. It raises.

    optima[mode] is None for a RETAINED pass (policies/forward.py returns early
    and says so); there is no claim to check, so there is nothing to violate.
    """
    for mode, value in optima.items():
        if value is None:
            continue
        key = _OPTIMUM_OF.get(mode)
        if key is None or measured.get(key) is None:
            continue
        if measured[key] > value:
            raise ChainError(
                f"the shipped plan does not honour the {mode} ceiling: measured "
                f"{key}={measured[key]} against an optimum of {value}. A later "
                f"pass dropped an earlier pass's constraint; the fire record "
                f"would have published {value} for a plan that has "
                f"{measured[key]}.")


#: ONE DEFAULT FOR target_soc, IN ONE PLACE (finding L-24).
#:
#: There were two. The serviceable predicate read `float(v.get("target_soc") or
#: 100)` and the scenario row two dozen lines later read `int(v.get("target_soc")
#: or 90)`, so a vehicle whose frame row carried no target was admitted against
#: a target of 100 and then planned against a target of 90. At soc 95 that meant
#: admitted as needing charge, then handed to the kernel already past its target
#: -- an asset with no charge segments, occupying the model and the plan and
#: proposable to nothing. 90 is the number the kernel itself defaults to
#: (model.py::materialize twice, harness_alpha, onboarding/sizer), so 90 is the
#: one that survives; the 100 was the outlier and is gone.
DEFAULT_TARGET_SOC_PCT = 90


def _pct(value: Any) -> float | None:
    """A percentage field off a frame row as a float, or None if absent.

    NULL AND GARBAGE BOTH BECOME None, DELIBERATELY. `float(None)` raises
    TypeError, and one such raise inside the vehicle loop took the whole batch
    down -- every other vehicle in the frame lost its proposal because one row
    had a null the frame contract permits. A value this function cannot read is
    a value the caller must be TOLD about, which is what the abstention rows in
    frame_to_scenario do; it is not grounds for killing the batch.
    """
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _resolved_target_soc(vehicle: dict) -> float:
    """The vehicle's target SoC, resolved through the single default."""
    target = _pct(vehicle.get("target_soc"))
    return DEFAULT_TARGET_SOC_PCT if target is None else target


def _default_serviceable(vehicle: dict) -> bool:
    """On site, in a serviceable state, and not already at its target.

    NULL-TOLERANT ON PURPOSE, and both halves matter. Reading soc as a number
    here is what raised on a null row; deciding a null-soc vehicle is
    unserviceable here would drop it silently, which is the same bug wearing
    the other mask. So an unreadable soc PASSES this predicate and reaches
    frame_to_scenario's guard, which turns it into an ABSTAIN row -- the
    disposer learns the proposer saw the vehicle and declined it.
    """
    if vehicle.get("state") not in DEFAULT_SERVICEABLE_STATES:
        return False
    soc = _pct(vehicle.get("soc"))
    if soc is None:
        return True
    return soc < _resolved_target_soc(vehicle)


def frame_to_scenario(frame: dict, class_table: dict, *,
                      site: dict, horizon_min: int = 720,
                      ready_by_min: dict[str, int] | None = None,
                      default_ready_delta_min: int = 240,
                      serviceable: Callable[[dict], bool] | None = None,
                      class_key: str = DEFAULT_CLASS_KEY,
                      ) -> tuple[dict, list[dict]]:
    """Translate a production decision frame into a kernel scenario.

    Returns (scenario, abstentions). Vehicles that cannot be planned -- no class
    entry, no readable soc, no plug that fits any point on site -- become
    ABSTAIN proposals rather than being silently dropped: the disposer should
    know the proposer saw them and declined, which is cuOpt's abstention
    pattern.

    `class_key` names the FRAME FIELD that keys `class_table`. It defaults to
    the production join key (see DEFAULT_CLASS_KEY); a caller holding a table
    keyed some other way -- a pack file keyed by platform, a fixture -- names
    its own field rather than reshaping the table.
    """
    ready_by_min = ready_by_min or {}
    if serviceable is None:
        serviceable = _default_serviceable

    points, kinds_on_site = [], set()
    #: kind -> the inlets the site actually accepts for it, kept only so an
    #: abstention can say what IS on site rather than only what is not.
    connectors_by_kind: dict[str, set[str]] = {}
    for st in frame.get("stalls", []):
        kind = st.get("type")
        kw = float(st.get("connector_max_kw") or 0)
        if kind in NON_CHARGING_TYPES or kw <= 0:
            continue
        inlets = _accepted_inlets(st)
        if not inlets:
            #: A stall that does not say which plugs it has cannot be matched to
            #: an inlet, and GUESSING one is the defect this finding is about.
            #: It drops out of the capability set; the consequence surfaces on
            #: the vehicle side, where an abstention names the inlet that found
            #: nothing and the plugs the site does offer.
            continue
        cap = _capability(kind, inlets)
        #: THE COOLDOWN MUST BE DECLARED, NOT INFERRED FROM THE LABEL. The
        #: kernel falls back to `site["dcfc_cooldown_min"] if kind == "dcfc"`
        #: for a point that declares no min_gap_min (model.py:497) -- a string
        #: literal that a composite capability label silently stops matching.
        #: Measured on the crowded fixture: composing the label without this
        #: line dropped the 18-minute DCFC min-gap from every point, which
        #: CLAUDE.md 2.5 names a modelling requirement that bites, and the
        #: whole suite stayed green but for two status assertions. Declaring
        #: the gap here is the kernel's own declared-data path and is what the
        #: label was always standing in for.
        if kind == "dcfc" and "dcfc_cooldown_min" not in site:
            raise FrameError("site declares no dcfc_cooldown_min; the DCFC "
                             "minimum gap on a service point cannot be guessed")
        gap = int(site["dcfc_cooldown_min"]) if kind == "dcfc" else 0
        points.append({"id": st["id"], "kind": cap, "kw": int(kw),
                       "min_gap_min": gap,
                       #: The ORIGINAL stall type, carried for the proposal
                       #: row's `stall_type`: the gate router's contract is the
                       #: database's vocabulary, not the kernel's label.
                       "stall_type": kind})
        kinds_on_site.add(cap)
        connectors_by_kind.setdefault(kind, set()).update(inlets)
    if not points:
        raise FrameError("frame has no charge-capable stalls that declare an "
                         "accepted inlet; nothing to propose on")

    classes: dict[str, dict] = {}
    explicit: list[dict] = []
    abstentions: list[dict] = []
    for v in frame.get("vehicles", []):
        if not serviceable(v):
            continue
        #: THE TWO GUARDS THAT KEEP ONE BAD ROW FROM COSTING THE BATCH, and that
        #: keep an unplannable vehicle from being planned anyway. Both abstain
        #: rather than raise and rather than drop: the frame contract permits a
        #: null soc, so a null soc is an input this bridge must answer for, not
        #: an exception it may throw across every other vehicle in the frame.
        soc_pct = _pct(v.get("soc"))
        if soc_pct is None:
            abstentions.append(_abstain(v, "frame carries no readable soc for "
                                           "this vehicle; nothing to plan "
                                           "toward"))
            continue
        #: Compared as the INTEGERS THE KERNEL WILL ACTUALLY SEE, not as the
        #: floats they came in as: soc 89.6 and target 90.0 both round to 90,
        #: and it is the rounded pair that decides whether model.py builds any
        #: charge segment at all. Guarding the raw floats would let exactly that
        #: pair through as an asset with nothing to do.
        soc_i = int(round(soc_pct))
        target_i = int(round(_resolved_target_soc(v)))
        if target_i <= soc_i:
            abstentions.append(_abstain(v, f"target_soc {target_i} is at or "
                                           f"below soc {soc_i}; no charge to "
                                           f"schedule"))
            continue
        ckey = v.get(class_key)
        cls = class_table.get(ckey)
        if cls is None:
            abstentions.append(_abstain(v, f"no class-table entry for "
                                           f"{class_key} {ckey!r}; battery "
                                           f"unknown"))
            continue
        #: REQUIRED, exactly like battery_kwh (finding L-42). charge_kinds alone
        #: decides which stall types a vehicle may be sent to, and it used to
        #: default to ("dcfc", "l2") -- so a class table that omitted it, which
        #: every production-derived one does since ottoq_vehicle_classes has no
        #: such column, silently granted every vehicle both charging types. The
        #: module's own rule for battery_kwh applies unchanged: a made-up
        #: capability is a silently wrong plan, and silence is not a default.
        if "charge_kinds" not in cls:
            raise FrameError(
                f"class {ckey!r} declares no charge_kinds; the field decides "
                f"which stall types this vehicle may be sent to and there is no "
                f"safe default for it (see battery_kwh)")
        ck = tuple(cls["charge_kinds"])
        inlet = _connector(v.get("inlet_type"))
        if inlet is None:
            abstentions.append(_abstain(v, "frame declares no inlet_type; the "
                                           "plug that fits cannot be guessed"))
            continue
        #: Sorted so the class's charge_kinds -- and therefore the scenario and
        #: the plan -- do not depend on set iteration order.
        caps = tuple(c for c in sorted(kinds_on_site)
                     if _capability_kind(c) in ck and inlet in _capability_inlets(c))
        if not caps:
            offered = sorted({i for k in ck
                              for i in connectors_by_kind.get(k, ())})
            abstentions.append(_abstain(
                v, f"no point on site accepts inlet {inlet} for charge_kinds "
                   f"{list(ck)}; the site accepts "
                   f"{offered or 'no inlet of those kinds'}"))
            continue
        #: THE SYNTHESIZED CLASS IS KEYED ON THE PER-UNIT FACTS, NOT THE PLATFORM.
        #: `inlet_max_kw` and `inlet_type` are declared per vehicle in the frame
        #: contract precisely because they vary per unit: a derated or damaged
        #: inlet is a fact about one truck, not about its make. Keying on
        #: `platform` alone and populating with `setdefault` meant only the FIRST
        #: vehicle of each platform was consulted and every later one inherited
        #: its limit -- so a derated unit was proposed 100 kW it cannot take, a
        #: healthy unit beside it was held to 25 kW it did not need, and swapping
        #: the two frame rows swapped the answers. Same frame, different plan,
        #: from row order alone. A derated unit now materializes its own class.
        eff_kw = float(min(cls["max_charge_kw"],
                           v.get("inlet_max_kw") or cls["max_charge_kw"]))
        cname = f"{ckey}|{int(eff_kw)}|{inlet}"
        #: The chemistry cap, resolved once per synthesized class. Explicit
        #: beats derived; derived beats nothing; nothing means no cap, exactly
        #: as before for any class that declares neither field.
        cap = cls.get("max_daily_soc_pct")
        if cap is None:
            cap = CHEMISTRY_DAILY_SOC_CAP_PCT.get(cls.get("battery_chemistry"))
        classes.setdefault(cname, {
            "battery_kwh": float(cls["battery_kwh"]),
            "max_charge_kw": eff_kw,
            "inlet": inlet,
            #: The COMPOSITE capabilities this vehicle's plug can actually
            #: reach, not the bare kinds: this is what binds the plug to the
            #: point inside the kernel's own model.
            "charge_kinds": list(caps),
            "energy_curve": cls.get("energy_curve",
                                    [{"above_soc_pct": 0, "accept_frac": 1.0}]),
            **({"max_daily_soc_pct": int(cap)} if cap is not None else {}),
        })
        rb = int(ready_by_min.get(v["id"], default_ready_delta_min))
        explicit.append({
            "aid": v["id"], "cls": cname, "arrival_min": 0,
            "soc": soc_i,
            "target_soc": target_i,
            "ready_by_min": rb,
        })

    scenario = {
        "name": "production_frame", "seed": 0, "horizon_min": horizon_min,
        "site": site,
        "objective_weights": {"tardiness_per_min": 10, "onpeak_kw_min": 0,
                              "peak_excess_per_kw": 0, "per_move": 0},
        "asset_classes": classes,
        "service_points": points,
        "parallel_ops_menu": {},
        "assets_spec": {"explicit": explicit},
    }
    return materialize(scenario), abstentions


def _abstain(vehicle: dict, reason: str) -> dict:
    return {
        "action_context": "stall_assignment",
        "entity_type": "vehicle",
        "entity_id": vehicle["id"],
        "source": "forward_lex",
        "proposal": {
            "verb": "assign_stall", "abstain": True,
            "vehicle_id": vehicle["id"], "rationale": {"reason": reason,
                                                       "optimizer": "forward_lex"},
            "resolved_action_context": "stall_assignment",
        },
    }


def plan_to_proposals(plan: dict, scenario: dict, *,
                      ready_by_used: dict[str, str]) -> list[dict]:
    """One advisory row per asset: a planned charge, or an explicit abstention.

    NEVER SILENTLY DROPS ONE. The `continue` this replaced skipped any asset with
    no charge op, which was harmless while every asset was guaranteed a point --
    and became a silent-drop the moment the solver could reject one
    (allow_rejection, SOLVER_STATE.md 6.1a). A vehicle the solver deliberately
    could not serve would have left no row at all, making it indistinguishable
    from a vehicle nobody asked about. That distinction is the entire reason
    cuopt_invocation_log exists on the other proposer, and it survives here.
    """
    #: The DATABASE's stall type, not the kernel's composite capability label:
    #: the gate router receives `dcfc`, never `dcfc@CCS1`.
    kinds = {p["id"]: p.get("stall_type", p["kind"])
             for p in scenario["service_points"]}
    out = []
    for a in plan["assets"]:
        charge = next((o for o in a["ops"] if o["op"] == "charge"), None)
        if charge is None:
            #: served is False -> the solver looked and could not place it.
            #: served absent -> rejection was off, so no charge op means something
            #: unexpected; say that rather than inventing a reason.
            reason = ("the site could not serve this vehicle within its capacity"
                      if a.get("served") is False else
                      "no charge operation in the returned plan")
            #: _abstain reads only the id, and the plan carries it -- reaching
            #: back into assets_spec for the original row would key on `aid`
            #: there, not `id`, and buy nothing.
            out.append(_abstain({"id": a["aid"]}, reason))
            continue
        #: THE TAPER SURVIVES THE ROW (finding L-25). `requested_kw` was the
        #: FIRST segment's kW while planned_start/planned_end spanned ALL of
        #: them, so the row invited kW x duration -- and the model produces
        #: multi-segment charge ops precisely because acceptance falls above
        #: ~70% SoC (CLAUDE.md 2.5 names the piecewise curve a modelling
        #: requirement that bites). On a 30->90 plan that arithmetic overstates
        #: the energy by the whole tapered tail, and CLAUDE.md 2.6 sends this
        #: substrate into the SDR, so the overstatement would have settled.
        #:
        #: requested_kw stays SINGLE-VALUED for the gate router's existing
        #: contract, but it is now the PEAK segment rather than the first: the
        #: number a connector must be able to deliver. Those coincide on a
        #: monotone taper and differ the moment a curve is not monotone, and
        #: the peak is the one that is safe to size against.
        segments = charge["segments"]
        planned_kwh = round(
            sum(sg["kw"] * (sg["end"] - sg["start"]) for sg in segments) / 60.0, 3)
        out.append({
            "action_context": "stall_assignment",
            "entity_type": "vehicle",
            "entity_id": a["aid"],
            "source": "forward_lex",
            "proposal": {
                "verb": "assign_stall", "abstain": False,
                "stall_id": charge["point"],
                "stall_type": kinds[charge["point"]],
                "vehicle_id": a["aid"],
                "requested_kw": max(sg["kw"] for sg in segments),
                "rationale": {
                    "optimizer": "forward_lex",
                    "planned_start_min": charge["start"],
                    "planned_end_min": charge["end"],
                    "planned_kwh": planned_kwh,
                    "segments": segments,
                    "tardy_min": a["tardy_min"],
                    "ready_by_source": ready_by_used.get(a["aid"], "default"),
                },
                "resolved_action_context": "stall_assignment",
            },
        })
    return out


def propose(frame: dict, class_table: dict, *, site: dict,
            horizon_min: int = 720,
            ready_by_min: dict[str, int] | None = None,
            default_ready_delta_min: int = 240,
            det_budget_s: float | None = DEFAULT_DET_BUDGET_S,
            time_limit_s: float | None = None,
            allow_rejection: bool = False,
            max_assets: int | None = None,
            hour_of_day: int | None = None,
            signals: frozenset = frozenset(),
            intent=None,
            class_key: str = DEFAULT_CLASS_KEY) -> dict:
    """Frame in, advisory rows out. Writes nothing, ever.

    The result carries the rows AND the solve's own accounting (T*, peak,
    statuses) so the caller can log an honest fire record next to the insert --
    the same discipline as cuopt_invocation_log: every invocation quantifiable,
    "never invoked" distinguishable from "invoked and abstained".

    allow_rejection lets the solver return a plan for a site it cannot fully
    serve, instead of INFEASIBLE and no plan at all. Every vehicle it declines
    still gets a row, with abstain=True and a reason -- a decline that produced
    no row would be indistinguishable from a vehicle nobody asked about.

    The budget is DETERMINISTIC work by default, not wall-clock time: a
    proposal truncated by the clock is a function of how loaded the box was,
    and rows like that must never be logged under a run ID as if they were
    reproducible. A caller that genuinely needs a wall-clock ceiling -- the
    live decide path has one tick of right-of-first-refusal before the local
    path pre-empts it -- may still pass time_limit_s; solver["reproducible"]
    then reports whether the clock was what stopped the search, so
    "truncated by the clock" stays distinguishable in the fire record.

    Pass hour_of_day (0-23) to run the REGIME-AWARE path: the active regime
    is resolved from the commander's intent and its ordered pass sequence is
    run through the generalized lexicographic chain, with `signals` marking
    conditions the regime matches on (e.g. grid_peak_imminent). The fire
    record then names the regime, the pass order, and the per-pass trace,
    and reports optima read from served assets only (so rejection composes).
    Left unset, the solver record keeps the two-pass pass1_status/pass2_status
    contract exactly as before.

    `intent` supplies the doctrine to resolve that regime FROM. Left None it is
    the kernel default artifact -- which is one process-global object, and was
    the only reachable one from this entry point, so no pack or tenant could
    bring its own priority orderings (finding L-52). policies/regime.py's
    intent_for_pack(pack_id) resolves a pack's artifact, and any Intent loaded
    by intent.load_intent is accepted here.
    """
    scenario, abstentions = frame_to_scenario(
        frame, class_table, site=site, horizon_min=horizon_min,
        ready_by_min=ready_by_min,
        default_ready_delta_min=default_ready_delta_min,
        class_key=class_key)

    if not scenario["assets_spec"]["explicit"]:
        return {"proposals": abstentions, "abstained": len(abstentions),
                "planned": 0, "solver": None,
                "note": "no plannable vehicles in frame"}

    #: THE BATCH BOUND, and why it is the caller's number and not a default.
    #:
    #: A deterministic budget bounds the SEARCH; it does not bound the MODEL.
    #: A 44-vehicle frame costs ~95 s of wall time at det_budget 2.0 mostly in
    #: construction and propagation, so no budget setting makes it fit a
    #: 30-second tick. A caller that must occupy the one-tick seat sizes the
    #: frame instead: solve the most urgent max_assets, and ABSTAIN on the rest
    #: with a reason that names the batch.
    #:
    #: Urgency is deadline first, then depth of need -- earliest ready_by_min,
    #: then lowest SoC, then aid for a stable tie-break. That is a selection of
    #: WHO TO ASK ABOUT, not a scheduling decision: the solver still decides
    #: placement and time for the batch it is given, and the deferred vehicles
    #: get rows, so "deferred to the next tick" stays distinguishable from
    #: "nobody asked". Left unset there is no batching and the whole frame is
    #: solved, which is right for offline planning.
    deferred: list[dict] = []
    if max_assets is not None:
        if max_assets < 1:
            raise ValueError(f"max_assets must be >= 1, got {max_assets}")
        explicit = scenario["assets_spec"]["explicit"]
        if len(explicit) > max_assets:
            ranked = sorted(explicit,
                            key=lambda a: (a["ready_by_min"], a["soc"], a["aid"]))
            keep, drop = ranked[:max_assets], ranked[max_assets:]
            for a in drop:
                deferred.append(_abstain(
                    {"id": a["aid"]},
                    f"outside this tick's batch of {max_assets} most urgent "
                    f"(ready_by {a['ready_by_min']} min, soc {a['soc']}%); "
                    f"re-offered next tick"))
            kept = {a["aid"] for a in keep}
            scenario["assets_spec"]["explicit"] = [
                a for a in explicit if a["aid"] in kept]
            scenario["assets"] = [a for a in scenario["assets"]
                                  if a.aid in kept]

    budget = {"time_limit_s": time_limit_s, "allow_rejection": allow_rejection}
    if det_budget_s is not None:
        budget["det_budget_s"] = det_budget_s

    ready_by_used = {a["aid"]: ("explicit" if a["aid"] in (ready_by_min or {})
                                else "default")
                     for a in scenario["assets_spec"]["explicit"]}

    if hour_of_day is None:
        #: THE CHEAP HOT-PATH DEFAULT, unchanged: the two-pass forward solve.
        #: The regime-aware chain is opt-in (hour_of_day set) because the third
        #: lever (min_flow) does not prove OPTIMAL and costs ~10-20x the two-pass
        #: solve -- fine for offline planning, too slow for the live tick. This
        #: branch is byte-for-byte what propose() did before the intent layer.
        pass1 = build_and_solve(scenario, objective_mode="min_tardy", **budget)
        #: T* IS THE BEST SERVICE LEVEL OVER THE VEHICLES THAT CAN BE SERVED. A
        #: rejected one carries tardy_min None -- it has no deadline to miss,
        #: because nothing is being done for it -- and summing it raw is a
        #: TypeError, which is how this was found. It matches the model: the
        #: lexicographic passes read CHARGED tardiness, from which rejected
        #: assets are already excluded, so pass 2's `sum(tardy) <= T*` budget and
        #: this figure count the same set. Pass 2 cannot quietly reject MORE to
        #: buy a lower peak: the rejection price (100,000) is two orders of
        #: magnitude above any peak this site can reach.
        t_star = sum(a["tardy_min"] for a in pass1["assets"]
                     if a["tardy_min"] is not None)
        pass2 = build_and_solve(scenario, objective_mode="min_peak",
                                max_tardy_total=t_star, previous_plan=pass1,
                                **budget)
        final_plan = pass2
        #: A RETAINED PASS 2 IS PASS 1'S SCHEDULE WEARING PASS 2'S NAME. When
        #: pass 2 cannot solve within the budget, model.py returns pass 1's plan
        #: with retained_previous=True and pass 1's repro dict attached -- so
        #: `reproducible` read true, `pass2_status` read whatever pass 1 proved,
        #: and nothing on the record said the peak pass never landed. The
        #: regime branch has surfaced this since it was written; the hot path,
        #: which is the branch production actually runs, did not (finding L-23).
        retained = bool(pass2.get("retained_previous"))
        optima = {"min_tardy": t_star,
                  "min_peak": (None if retained
                               else pass2.get("site_peak_kw"))}
        measured = _measure_plan(final_plan)
        _check_optima(measured, optima)
        solver_record = {
            "optimizer": "forward_lex",
            "pass1_status": pass1["solver_status"],
            "pass2_status": pass2["solver_status"],
            #: MEASURED OFF final_plan, not re-reported from the passes -- see
            #: _measure_plan. `optima_reached` keeps what each pass reached, so
            #: nothing is lost and the two can be compared by an auditor.
            "total_tardy_min": measured["total_tardy_min"],
            "site_peak_kw": measured["site_peak_kw"],
            "total_flow_min": measured["total_flow_min"],
            "optima_reached": optima,
            "retained_previous": retained,
            #: complete has ONE meaning across both branches: every pass this
            #: path was asked to run RAN and PROVED its optimum. FEASIBLE is an
            #: incumbent, not a proof, and a retained pass did not run at all.
            "complete": (not retained
                         and pass1["solver_status"] == "OPTIMAL"
                         and pass2["solver_status"] == "OPTIMAL"),
            #: FALSE means a wall-clock limit may have decided this plan, so it
            #: is not a function of (scenario, seed, config) alone. A fire
            #: record carrying FALSE must not be cited as a reproducible number.
            #: A retained plan is not this pass's plan, so it cannot be cited
            #: as this pass's reproducible result either -- the same gate the
            #: regime branch applies.
            "reproducible": bool(not retained
                                 and pass1.get("repro", {}).get("reproducible")
                                 and pass2.get("repro", {}).get("reproducible")),
            "rejected": list(pass2.get("rejected", [])),
            "deterministic_time": round(
                pass1.get("repro", {}).get("deterministic_time", 0.0)
                + pass2.get("repro", {}).get("deterministic_time", 0.0), 6),
            **_repro_identity(pass2, pass1),
        }
    else:
        #: THE REGIME-AWARE PATH: the commander's intent resolves the active
        #: regime and its pass order, then the generalized lexicographic chain
        #: runs it. Every earlier pass's optimum is held by the later passes, and
        #: the fire record names the regime and the per-pass trace so an auditor
        #: can see WHY this order was chosen. rejection composes: the optima are
        #: read from served assets only (T*/F*) and site_peak_kw (P*).
        #: `intent` is the PACK's doctrine when the caller has one (finding
        #: L-52). None keeps the kernel default, which is what every existing
        #: caller gets, unchanged.
        active = resolve_active(hour_of_day, signals, intent=intent)
        modes = pass_sequence(active)
        final_plan, optima, passes = lexicographic_solve_traced(
            scenario, modes, budget=budget)
        measured = _measure_plan(final_plan)
        _check_optima(measured, optima)
        solver_record = {
            "optimizer": "forward_lex",
            "regime": active.regime_key,
            "regime_label": active.regime_label,
            "pass_modes": list(modes),
            "passes": passes,
            #: MEASURED OFF final_plan (finding L-22). These three were the
            #: per-pass optima, which describe the plan each pass returned and
            #: not the one that ships. A consequence worth stating: a figure is
            #: now reported whether or not a pass optimized it -- a regime that
            #: skips min_flow still has a flow time, and this is it. What the
            #: chain actually held is `optima_reached`, where a skipped mode is
            #: absent and a retained one is None.
            "total_tardy_min": measured["total_tardy_min"],
            "site_peak_kw": measured["site_peak_kw"],
            "total_flow_min": measured["total_flow_min"],
            "optima_reached": dict(optima),
            "retained_previous": bool(final_plan.get("retained_previous")),
            #: complete == every pass in the regime RAN and PROVED its optimum.
            #: Three ways it can be False, and all three used to be invisible:
            #: a retained pass (INFEASIBLE/UNKNOWN) sets optima[mode]=None and
            #: returns early, so `passes` is short; and a budget-truncated pass
            #: returns FEASIBLE — an incumbent, not a proof. That last case was
            #: reported complete:true, which published a truncated plan as a
            #: whole one and let a non-optimal T* be cited as the readiness
            #: floor. Optimality is claimed from the status, never from the
            #: presence of a number.
            "complete": (
                len(passes) == len(modes)
                and all(p.get("proven") for p in passes)
                and all(optima.get(m) is not None for m in modes)
            ),
            "reproducible": bool(
                not final_plan.get("retained_previous")
                and all(p.get("reproducible") for p in passes)),
            "rejected": list(final_plan.get("rejected", [])),
            "deterministic_time": round(
                sum(p.get("deterministic_time", 0.0) for p in passes), 6),
            **_repro_identity(final_plan),
        }

    rows = plan_to_proposals(final_plan, scenario, ready_by_used=ready_by_used)
    #: EVERY VEHICLE THE FRAME OFFERED STILL HAS EXACTLY ONE ROW: planned,
    #: abstained at translation (unknown platform, no capable point), or
    #: deferred out of this tick's batch.
    return {
        "proposals": rows + abstentions + deferred,
        "planned": len(rows),
        "abstained": len(abstentions) + len(deferred),
        "deferred": len(deferred),
        "solver": solver_record,
    }
