"""The intent artifact — load, verify, and resolve the commander's intent.

The intent is a versioned, content-fingerprinted JSON artifact (intent_v1.json)
that declares the full objective taxonomy, the regime-conditioned priority
orderings, and the numeraire decision. This module:

  * loads and VERIFIES the artifact (a tampered or truncated intent is refused,
    never silently used — same discipline as the 0201 calibration fingerprint),
  * resolves the ACTIVE regime from a declarative match (hour window + signals),
  * returns the ordered objective list the optimizer should act on.

The intent is doctrine, not code: it never mutates world state, never imports a
database or network client, and is a pure function of (artifact, clock, signals).
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path

ARTIFACT_PATH = Path(__file__).parent / "intent_v1.json"

#: The canonical content — what the fingerprint covers. `manifest` is excluded
#: on purpose: it carries the fingerprint itself and generated_at, so a re-stamp
#: that lands the same content is not a change to the world (0201 discipline).
CANONICAL_KEYS = ("numeraire", "objectives", "regimes", "tier3_constraints")


@dataclass(frozen=True)
class Objective:
    key: str
    tier: int
    label: str
    metric: str
    direction: str
    kind: str                      # "floor" | "objective"
    dollar_value: str              # "sourced" | "NOT_FOUND"
    dollar_value_detail: str
    solver_wiring: str
    provenance: dict


@dataclass(frozen=True)
class Regime:
    key: str
    label: str
    match: dict
    priority: tuple[str, ...]
    rationale: str


@dataclass(frozen=True)
class Intent:
    objectives: dict[str, Objective]
    regimes: tuple[Regime, ...]
    numeraire: dict
    tier3_constraints: dict
    fingerprint: str
    version: int


@dataclass(frozen=True)
class ActiveIntent:
    regime_key: str
    regime_label: str
    priority: tuple[str, ...]       # objective keys, in priority order
    floors: tuple[str, ...]         # priority subset with kind == "floor"
    objectives: tuple[str, ...]     # priority subset with kind == "objective"
    rationale: str


def fingerprint(content: dict) -> str:
    """md5 over the canonical content — the same discipline as
    `ottoq_calibration_fingerprint()` (0201): a re-stamp that lands the same
    numbers is not a change to the world."""
    blob = json.dumps(content, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.md5(blob).hexdigest()


def _canonical(raw: dict) -> dict:
    return {k: raw[k] for k in CANONICAL_KEYS}


def load_intent(path: str | Path = ARTIFACT_PATH) -> Intent:
    raw = json.loads(Path(path).read_text())
    manifest = raw["manifest"]

    # Verify the content hash before trusting it. A mismatch means tampered or
    # truncated — refuse, do not forecast/optimize on it.
    actual = fingerprint(_canonical(raw))
    if manifest["fingerprint_md5"] != actual:
        raise ValueError(
            f"intent fingerprint mismatch: manifest says "
            f"{manifest['fingerprint_md5']}, content hashes to {actual} — "
            f"refusing to optimize on an unverified intent")

    objectives = {
        key: Objective(
            key=key, tier=int(o["tier"]), label=o["label"], metric=o["metric"],
            direction=o["direction"], kind=o["kind"],
            dollar_value=o["dollar_value"],
            dollar_value_detail=o["dollar_value_detail"],
            solver_wiring=o["solver_wiring"], provenance=o["provenance"],
        )
        for key, o in raw["objectives"].items()
    }
    regimes = tuple(
        Regime(key=r["key"], label=r["label"], match=r.get("match", {}),
               priority=tuple(r["priority"]), rationale=r["rationale"])
        for r in raw["regimes"]
    )
    return Intent(
        objectives=objectives, regimes=regimes,
        numeraire=raw["numeraire"], tier3_constraints=raw["tier3_constraints"],
        fingerprint=manifest["fingerprint_md5"], version=int(manifest["version"]),
    )


def _matches(regime: Regime, hour_of_day: int, signals: frozenset[str]) -> bool:
    m = regime.match
    if not m:
        return True                      # steady_state: empty match = default
    hr = m.get("hour_range")
    if hr is not None:
        lo, hi = hr[0], hr[1]
        if lo <= hi:
            if not (lo <= hour_of_day < hi):
                return False
        else:                            # wrap across midnight (e.g. [20, 4])
            if not (hour_of_day >= lo or hour_of_day < hi):
                return False
    need = set(m.get("signals", []))
    if need and not need.issubset(signals):
        return False
    return True


#: The floors that must hold under EVERY regime, in canonical order. Readiness
#: (never strand an asset) then service completion (never miss a must-by) —
#: both structural, from DECISION_BOUNDARY.md: "anything that can strand an
#: asset" and "obligation … the must-by is deterministic and non-negotiable."
#: A regime's priority list orders the SOFT objectives; the floors are prepended
#: in resolve_intent so no regime can ever drop them.
CANONICAL_FLOORS = ("readiness", "service_completion")


def _dedupe(seq: tuple[str, ...]) -> tuple[str, ...]:
    seen: set[str] = set()
    out: list[str] = []
    for x in seq:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return tuple(out)


def resolve_intent(intent: Intent, *, hour_of_day: int,
                   signals: frozenset[str] = frozenset()) -> ActiveIntent:
    """Pick the active regime and return its ordered objectives.

    Regimes are evaluated in declaration order; the first match wins. Every
    artifact carries a `steady_state` regime with an empty match last, so the
    resolver is TOTAL — it never returns "no regime".

    FLOORS ARE STRUCTURAL, not regime-dependent: the canonical floors are
    prepended to whatever the regime lists. A regime that omits a floor must not
    be allowed to drop it — grid_peak and overnight list only their soft
    objectives, and without this prepend they would silently sacrifice
    readiness, the exact defect DECISION_BOUNDARY.md forbids.
    """
    for regime in intent.regimes:
        if _matches(regime, hour_of_day % 24, signals):
            canonical = tuple(k for k in CANONICAL_FLOORS if k in intent.objectives)
            soft = tuple(k for k in regime.priority
                         if k in intent.objectives and k not in CANONICAL_FLOORS)
            priority = _dedupe(canonical + soft)
            floors = tuple(k for k in priority
                           if intent.objectives[k].kind == "floor")
            objs = tuple(k for k in priority
                         if intent.objectives[k].kind == "objective")
            return ActiveIntent(
                regime_key=regime.key, regime_label=regime.label,
                priority=priority, floors=floors, objectives=objs,
                rationale=regime.rationale,
            )
    raise RuntimeError("intent has no matching regime — a steady_state default "
                       "is required and was absent")


def all_objective_keys(intent: Intent) -> tuple[str, ...]:
    """Every objective declared, in stable (sorted) order — for completeness
    checks: the union of every regime's priority must cover all objectives."""
    return tuple(sorted(intent.objectives))


def stamp(path: str | Path = ARTIFACT_PATH) -> str:
    """Compute and write the fingerprint into the manifest, then return it.

    The one deliberate write path (used at authoring time, not at runtime):
    regenerates the fingerprint after the content is edited. Runtime load never
    writes."""
    p = Path(path)
    raw = json.loads(p.read_text())
    fp = fingerprint(_canonical(raw))
    raw["manifest"]["fingerprint_md5"] = fp
    p.write_text(json.dumps(raw, indent=2, sort_keys=True) + "\n")
    return fp
