"""The forward orchestrator as a PRODUCTION PROPOSER — propose/dispose, never write.

THE TWO LAWS, restated where they bind (CLAUDE.md 2.5, "agents propose, solver
disposes"):

  1. This module NEVER writes anything. propose() returns rows; whoever calls it
     (an edge function, a founder-gated integration) inserts them into
     ottoq_external_proposals, where the deferral pattern gives an in-flight
     proposal its one-tick right-of-first-refusal before the local decide path
     pre-empts. The DISPOSER remains the production decide path -- exactly the
     seat cuOpt occupies today, and deliberately no more.
  2. No proposal is ever a command. Every row is advisory, carries abstain
     semantics, and expires.

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

The solver underneath is policies/forward.py's lexicographic pair of solves on
the generalized kernel model: minimize tardiness, then hold it and minimize the
site's instantaneous peak. The kernel stays sector-blind; this module is the
adapter between one database's vocabulary and the kernel's declared-data world,
which is exactly where CLAUDE.md says adapters live.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Callable

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "solvers" / "cpsat"))

from model import build_and_solve, materialize  # noqa: E402

#: Vehicle states that mean "on site and awaiting service". The default is the
#: conservative reading of the twin vocabulary; a caller with better knowledge
#: passes its own predicate. Being a DEFAULT and not a constant baked into the
#: solve is the point: the kernel model never sees state names at all.
DEFAULT_SERVICEABLE_STATES = frozenset({
    "arrived_at_gate", "awaiting_stall", "in_queue", "charging_dcfc",
    "charging_l2", "charge_scheduled",
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
        cname = f"{platform}"
        classes.setdefault(cname, {
            "battery_kwh": float(cls["battery_kwh"]),
            "max_charge_kw": float(min(cls["max_charge_kw"],
                                       v.get("inlet_max_kw") or cls["max_charge_kw"])),
            "inlet": v.get("inlet_type", "CCS"),
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
            det_budget_s: float | None = None,
            time_limit_s: float | None = None,
            allow_rejection: bool = False) -> dict:
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
    """
    scenario, abstentions = frame_to_scenario(
        frame, class_table, site=site, horizon_min=horizon_min,
        ready_by_min=ready_by_min,
        default_ready_delta_min=default_ready_delta_min)

    if not scenario["assets_spec"]["explicit"]:
        return {"proposals": abstentions, "abstained": len(abstentions),
                "planned": 0, "solver": None,
                "note": "no plannable vehicles in frame"}

    budget = {"time_limit_s": time_limit_s, "allow_rejection": allow_rejection}
    if det_budget_s is not None:
        budget["det_budget_s"] = det_budget_s
    pass1 = build_and_solve(scenario, objective_mode="min_tardy", **budget)
    #: T* IS THE BEST SERVICE LEVEL OVER THE VEHICLES THAT CAN BE SERVED. A
    #: rejected one carries tardy_min None -- it has no deadline to miss, because
    #: nothing is being done for it -- and summing it raw is a TypeError, which is
    #: how this was found. It matches the model: the lexicographic passes read
    #: CHARGED tardiness, from which rejected assets are already excluded, so
    #: pass 2's `sum(tardy) <= T*` budget and this figure count the same set.
    #: Pass 2 cannot quietly reject MORE to buy a lower peak: the rejection price
    #: (100,000) is two orders of magnitude above any peak this site can reach.
    t_star = sum(a["tardy_min"] for a in pass1["assets"] if a["tardy_min"] is not None)
    pass2 = build_and_solve(scenario, objective_mode="min_peak",
                            max_tardy_total=t_star, previous_plan=pass1,
                            **budget)

    ready_by_used = {a["aid"]: ("explicit" if a["aid"] in (ready_by_min or {})
                                else "default")
                     for a in scenario["assets_spec"]["explicit"]}
    rows = plan_to_proposals(pass2, scenario, ready_by_used=ready_by_used)
    return {
        "proposals": rows + abstentions,
        "planned": len(rows),
        "abstained": len(abstentions),
        "solver": {
            "optimizer": "forward_lex",
            "pass1_status": pass1["solver_status"],
            "pass2_status": pass2["solver_status"],
            "total_tardy_min": t_star,
            #: FALSE means a wall-clock limit may have decided this plan, so it
            #: is not a function of (scenario, seed, config) alone. A fire
            #: record carrying FALSE must not be cited as a reproducible number.
            "reproducible": bool(pass1.get("repro", {}).get("reproducible")
                                 and pass2.get("repro", {}).get("reproducible")),
            #: WHO THE SOLVER COULD NOT SERVE, named. Without rejection enabled an
            #: over-subscribed site returns INFEASIBLE and this whole call yields
            #: nothing; with it, the fire record can say "invoked, planned N,
            #: could not serve M, and here is M" -- the same quantifiability
            #: cuopt_invocation_log gives the other proposer.
            "rejected": list(pass2.get("rejected", [])),
            "deterministic_time": round(
                pass1.get("repro", {}).get("deterministic_time", 0.0)
                + pass2.get("repro", {}).get("deterministic_time", 0.0), 6),
        },
    }
