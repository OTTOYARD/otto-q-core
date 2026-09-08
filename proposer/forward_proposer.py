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


class FrameError(ValueError):
    """A frame or class table this bridge refuses to guess around."""


def frame_to_scenario(frame: dict, class_table: dict, *,
                      site: dict, horizon_min: int = 720,
                      ready_by_min: dict[str, int] | None = None,
                      default_ready_delta_min: int = 240,
                      serviceable: Callable[[dict], bool] | None = None,
                      ) -> tuple[dict, list[dict]]:
    """Translate a production decision frame into a kernel scenario.

    Returns (scenario, abstentions). Vehicles that cannot be planned -- unknown
    platform, or no capable charge point on site -- become ABSTAIN proposals
    rather than being silently dropped: the disposer should know the proposer
    saw them and declined, which is cuOpt's abstention pattern.
    """
    ready_by_min = ready_by_min or {}
    if serviceable is None:
        serviceable = lambda v: (v.get("state") in DEFAULT_SERVICEABLE_STATES
                                 and float(v.get("soc", 100)) <
                                 float(v.get("target_soc") or 100))

    points, kinds_on_site = [], set()
    for st in frame.get("stalls", []):
        kind = st.get("type")
        kw = float(st.get("connector_max_kw") or 0)
        if kind in NON_CHARGING_TYPES or kw <= 0:
            continue
        points.append({"id": st["id"], "kind": kind, "kw": int(kw)})
        kinds_on_site.add(kind)
    if not points:
        raise FrameError("frame has no charge-capable stalls; nothing to propose on")

    classes: dict[str, dict] = {}
    explicit: list[dict] = []
    abstentions: list[dict] = []
    for v in frame.get("vehicles", []):
        if not serviceable(v):
            continue
        platform = v.get("platform")
        cls = class_table.get(platform)
        if cls is None:
            abstentions.append(_abstain(v, f"no class-table entry for platform "
                                           f"{platform!r}; battery unknown"))
            continue
        ck = tuple(cls.get("charge_kinds", ("dcfc", "l2")))
        if not any(k in kinds_on_site for k in ck):
            abstentions.append(_abstain(v, f"no capable point on site for "
                                           f"charge_kinds {list(ck)}"))
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
        inlet = v.get("inlet_type", "CCS")
        cname = f"{platform}|{int(eff_kw)}|{inlet}"
        classes.setdefault(cname, {
            "battery_kwh": float(cls["battery_kwh"]),
            "max_charge_kw": eff_kw,
            "inlet": inlet,
            "charge_kinds": list(ck),
            "energy_curve": cls.get("energy_curve",
                                    [{"above_soc_pct": 0, "accept_frac": 1.0}]),
        })
        rb = int(ready_by_min.get(v["id"], default_ready_delta_min))
        explicit.append({
            "aid": v["id"], "cls": cname, "arrival_min": 0,
            "soc": int(round(float(v["soc"]))),
            "target_soc": int(v.get("target_soc") or 90),
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
    kinds = {p["id"]: p["kind"] for p in scenario["service_points"]}
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
                "requested_kw": charge["segments"][0]["kw"],
                "rationale": {
                    "optimizer": "forward_lex",
                    "planned_start_min": charge["start"],
                    "planned_end_min": charge["end"],
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
            signals: frozenset = frozenset()) -> dict:
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
    """
    scenario, abstentions = frame_to_scenario(
        frame, class_table, site=site, horizon_min=horizon_min,
        ready_by_min=ready_by_min,
        default_ready_delta_min=default_ready_delta_min)

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
        solver_record = {
            "optimizer": "forward_lex",
            "pass1_status": pass1["solver_status"],
            "pass2_status": pass2["solver_status"],
            "total_tardy_min": t_star,
            #: FALSE means a wall-clock limit may have decided this plan, so it
            #: is not a function of (scenario, seed, config) alone. A fire
            #: record carrying FALSE must not be cited as a reproducible number.
            "reproducible": bool(pass1.get("repro", {}).get("reproducible")
                                 and pass2.get("repro", {}).get("reproducible")),
            "rejected": list(pass2.get("rejected", [])),
            "deterministic_time": round(
                pass1.get("repro", {}).get("deterministic_time", 0.0)
                + pass2.get("repro", {}).get("deterministic_time", 0.0), 6),
        }
    else:
        #: THE REGIME-AWARE PATH: the commander's intent resolves the active
        #: regime and its pass order, then the generalized lexicographic chain
        #: runs it. Every earlier pass's optimum is held by the later passes, and
        #: the fire record names the regime and the per-pass trace so an auditor
        #: can see WHY this order was chosen. rejection composes: the optima are
        #: read from served assets only (T*/F*) and site_peak_kw (P*).
        active = resolve_active(hour_of_day, signals)
        modes = pass_sequence(active)
        final_plan, optima, passes = lexicographic_solve_traced(
            scenario, modes, budget=budget)
        solver_record = {
            "optimizer": "forward_lex",
            "regime": active.regime_key,
            "regime_label": active.regime_label,
            "pass_modes": list(modes),
            "passes": passes,
            "total_tardy_min": optima.get("min_tardy"),
            "site_peak_kw": optima.get("min_peak"),
            "total_flow_min": optima.get("min_flow"),
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
