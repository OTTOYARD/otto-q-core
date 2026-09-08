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

#: THE FINGERPRINT COVERS EVERYTHING EXCEPT ITSELF (finding L-55).
#:
#: It used to project onto four hardcoded top-level keys, which put the WHOLE
#: manifest outside the hash -- `version`, `kind` and `description` along with
#: it -- and left any future top-level key unauthenticated by default. The
#: loader then built `Intent.version` from `manifest["version"]`, so it
#: returned a verified-looking object carrying a field the verification never
#: covered, and a document could declare itself version 9 of a different kind
#: without disturbing its own hash.
#:
#: Only the two SELF-REFERENTIAL manifest fields stay out, and for the reason
#: the original comment gave: `fingerprint_md5` cannot hash itself, and
#: `generated_at` is the stamp's timestamp, so a re-stamp that lands the same
#: content is not a change to the world (0201 discipline). Everything else is
#: covered, and a key added later is covered by default rather than covered
#: only if someone remembers to extend a list.
UNHASHED_MANIFEST_KEYS = ("fingerprint_md5", "generated_at")


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

    @property
    def known_signals(self) -> frozenset[str]:
        """Every signal name any regime in THIS artifact matches on.

        The vocabulary is the artifact's, not a constant, so a pack that
        declares its own signals is checked against its own doctrine.
        """
        return frozenset(sig for r in self.regimes
                         for sig in r.match.get("signals", []))


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
    """The document, minus the two fields that cannot describe themselves."""
    out = {k: v for k, v in raw.items() if k != "manifest"}
    manifest = raw.get("manifest")
    if isinstance(manifest, dict):
        out["manifest"] = {k: v for k, v in manifest.items()
                           if k not in UNHASHED_MANIFEST_KEYS}
    return out


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


#: The canonical ORDER of the two named floors. Readiness (never strand an
#: asset) then service completion (never miss a must-by) — both structural,
#: from DECISION_BOUNDARY.md: "anything that can strand an asset" and
#: "obligation … the must-by is deterministic and non-negotiable."
#:
#: THIS IS AN ORDER, NOT THE DEFINITION (finding L-56). There were two
#: independent definitions of "floor": this Python tuple, which decided what
#: got PREPENDED, and the artifact's own declarative `kind == "floor"` field,
#: which decided what `ActiveIntent.floors` REPORTED. An objective the artifact
#: declares as a floor but that is not named here was silently dropped by every
#: regime that did not list it — precisely the failure resolve_intent's
#: docstring says the mechanism prevents. The artifact is now the definition
#: and this tuple only fixes the order of the two it names.
CANONICAL_FLOOR_ORDER = ("readiness", "service_completion")


def _floors_of(intent: "Intent") -> tuple[str, ...]:
    """Every objective the ARTIFACT declares a floor, canonical names first."""
    named = tuple(k for k in CANONICAL_FLOOR_ORDER
                  if k in intent.objectives
                  and intent.objectives[k].kind == "floor")
    rest = tuple(k for k, o in sorted(intent.objectives.items())
                 if o.kind == "floor" and k not in CANONICAL_FLOOR_ORDER)
    return named + rest


def _dedupe(seq: tuple[str, ...]) -> tuple[str, ...]:
    seen: set[str] = set()
    out: list[str] = []
    for x in seq:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return tuple(out)


def _build_active(intent: Intent, regime: Regime) -> ActiveIntent:
    """Build the ActiveIntent for a matched regime (floors prepended, deduped)."""
    canonical = _floors_of(intent)
    soft = tuple(k for k in regime.priority
                 if k in intent.objectives and k not in canonical)
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


def resolve_intent(intent: Intent, *, hour_of_day: int,
                   signals: frozenset[str] = frozenset()) -> ActiveIntent:
    """Pick the active regime and return its ordered objectives.

    SIGNALS OVERRIDE THE CLOCK, structurally — not by declaration-order luck.
    Regimes that REQUIRE a signal (grid_peak, demand_surge, weather_event) are
    evaluated before any pure-clock regime, so a grid_peak_imminent signal at
    07:00 resolves to grid_peak, never to dispatch_rush. Within the signal pass,
    declaration order is the precedence (the artifact declares weather_event
    first, so a grounding risk outranks a cost or throughput signal — safety
    first); within the clock pass, dispatch_rush precedes overnight precedes the
    steady_state default.

    FLOORS ARE STRUCTURAL, not regime-dependent: the canonical floors are
    prepended to whatever the regime lists. A regime that omits a floor must not
    be allowed to drop it — grid_peak and overnight list only their soft
    objectives, and without this prepend they would silently sacrifice
    readiness, the exact defect DECISION_BOUNDARY.md forbids.
    """
    #: AN UNKNOWN SIGNAL IS AN ERROR, NOT A NO-OP (finding L-38). `_matches`
    #: only ever tested `need.issubset(signals)`, so a misspelled name matched
    #: nothing, pass 1 found no signal regime, and the resolver fell through to
    #: the CLOCK pass and returned a regime as if no signal had been raised.
    #: `grid_peak_imminant` at 07:00 silently resolved to dispatch_rush --
    #: throughput first, on a tick that was about to hit a demand-charge
    #: ceiling. This is the same hazard signals.py guards on the other side of
    #: the seam, where a missing field is never quietly read as zero because it
    #: "would hide a real surge"; the same discipline applies here.
    unknown = frozenset(signals) - intent.known_signals
    if unknown:
        raise ValueError(
            f"unknown signal(s) {sorted(unknown)} — this intent artifact "
            f"declares {sorted(intent.known_signals)}. A signal name no regime "
            f"matches on cannot raise a regime, and silently resolving by the "
            f"clock instead would hide it")

    hod = hour_of_day % 24
    # Pass 1: signal-bearing regimes, in declaration order.
    for regime in intent.regimes:
        if regime.match.get("signals") and _matches(regime, hod, signals):
            return _build_active(intent, regime)
    # Pass 2: pure-clock regimes, in declaration order (steady_state last).
    for regime in intent.regimes:
        if not regime.match.get("signals") and _matches(regime, hod, signals):
            return _build_active(intent, regime)
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
