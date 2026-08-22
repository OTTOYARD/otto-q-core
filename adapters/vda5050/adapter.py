"""C10 — VDA 5050 adapter draft. Source: docs/research/H1-intralogistics.md (merged).

WHERE OTTO-Q SITS. Beside a VDA 5050 master controller, not instead of it.
H1 is unambiguous that VDA 5050 is "comprehensive, operational and
command-capable" for dispatching orders and managing traffic, and that it
"explicitly excludes service-side functions: energy strategy, battery health
economics, service events, and cross-fleet settlement." That exclusion is the
seam this adapter sits in.

    master controller  →  keeps work-side dispatch entirely. Nodes, edges,
                          corridors, traffic, deadlocks. OTTO-Q never writes here.
    OTTO-Q             →  takes asset state, decides recall and service
                          scheduling, returns ready-for-work.

THE HANDOFF SEQUENCE, and who owns each step:

    1. master → robot        /order  (work)                        [master]
    2. robot  → master       /state  (telemetry, continuous)       [robot]
    3. master → OTTO-Q       /state forwarded, or tapped           [integration]
    4. OTTO-Q                RecallDecision.decide(...)            [KERNEL — recall/]
    5. OTTO-Q → master       ServiceIntent                          [kernel decision]
    6. this adapter          ServiceIntent → /order (service)      [TRANSLATION ONLY]
    7. master → robot        /order (service), master sequences it [master]
    8. robot  → master       /state, actionState COMPLETED          [robot]
    9. this adapter          /state → AssetFact(ready)              [TRANSLATION ONLY]
   10. OTTO-Q → master       ready-for-work                         [kernel]

Steps 6 and 9 are the only ones this file performs. Step 4 is the kernel's, and
Law 1 is what keeps it there: the master controller decides WHERE the robot
drives, OTTO-Q decides WHEN it stops working and WHAT it needs, and this adapter
decides nothing at all.

VERSION DISCREPANCY IN THE SOURCE — flagged, not papered over. H1's prose states
VDA 5050 "Version 3.0.0 (March 2026)", while every JSON example it captures
carries `"version": "1.3.2"`. Both cannot describe the same capture. The adapter
therefore treats the wire `version` string as PROVISIONAL: it is read, echoed and
never parsed for behaviour. Resolving it is R-2.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from adapters.base import Adapter, AssetFact, ServiceIntent


# Every /state field H1 captures, and what this adapter does with it. C10 requires
# that the draft "names every consumed/emitted field or marks it provisional".
CONSUMED_STATE_FIELDS: dict[str, str] = {
    "headerId":            "consumed — de-duplication and ordering within a topic",
    "timestamp":           "consumed — becomes AssetFact.observed_at, verbatim, unconverted",
    "version":             "PROVISIONAL — echoed, never parsed (see version discrepancy above)",
    "manufacturer":        "consumed — composes the asset_ref namespace",
    "serialNumber":        "consumed — composes the asset_ref namespace",
    "orderId":             "consumed — correlates a service order we emitted",
    "orderUpdateId":       "consumed — correlates a service order we emitted",
    "lastNodeId":          "consumed — becomes AssetFact.position_ref, verbatim",
    "lastNodeSequenceId":  "carried in extra — needed to disambiguate revisited nodes",
    "driving":             "consumed — contributes to blocked",
    "paused":              "consumed — contributes to blocked",
    "powerSupply.batteryCharge": "consumed — becomes AssetFact.soc_pct (percent)",
    "powerSupply.voltage": "carried in extra — battery-health economics, an H1 gap-table row",
    "powerSupply.current": "carried in extra — sign distinguishes charge from discharge",
    "safetyState.activeEmergencyStop": "consumed — NONE|MANUAL|REMOTE; non-NONE ⇒ faulted",
    "safetyState.fieldViolation":      "consumed — contributes to faulted",
    "nodeStates":          "consumed — actionStates drive service-completion detection",
    "edgeStates":          "carried in extra — traffic state belongs to the master, not to us",
}

# Every /order field this adapter emits.
EMITTED_ORDER_FIELDS: dict[str, str] = {
    "headerId":        "emitted — per-topic counter supplied by the caller",
    "timestamp":       "emitted — ISO8601, from the kernel decision, not wall clock",
    "version":         "PROVISIONAL — echoed from the robot's own /state",
    "manufacturer":    "emitted — split back out of asset_ref",
    "serialNumber":    "emitted — split back out of asset_ref",
    "orderId":         "emitted — deterministic from the intent, never random",
    "orderUpdateId":   "emitted — 0; this adapter never revises an order it sent",
    "nodes":           "emitted — exactly one node: the service point",
    "nodes[].nodeId":  "emitted — ServiceIntent.service_point_ref, verbatim",
    "nodes[].sequenceId": "emitted — 0",
    "nodes[].released":   "emitted — true; a service node is never horizon",
    "nodes[].nodePosition": "NOT EMITTED — the master owns geometry; H1 notes it is "
                            "optional and unused by line-guided robots",
    "nodes[].actions[].actionId":     "emitted — deterministic from the intent",
    "nodes[].actions[].actionType":   "emitted — mapped from operation_code",
    "nodes[].actions[].blockingType": "emitted — HARD for service actions (see below)",
    "nodes[].actions[].actionParameters": "emitted — operation code, window, reason",
    "edges":           "NOT EMITTED — edges are traffic; traffic is the master's",
    "edges[].corridor": "NOT EMITTED — same reason",
}

# operation_code (ottoq_operation_catalog) → VDA 5050 actionType.
# PROVISIONAL: H1 captures the /order schema and `loadUnload` /
# `driveThroughSpeedGate` as examples, but does not enumerate the predefined
# actionType vocabulary. Whether a conforming robot exposes a charging action —
# and under what name — is R-2. Until then these are OTTO-Q-namespaced custom
# actions, which is the safe direction: a custom action a robot does not know is
# rejected loudly, whereas a guessed standard name could collide with a real one.
OPERATION_TO_ACTION_TYPE: dict[str, str] = {
    "charge_dcfc":       "ottoq.startCharging",     # PROVISIONAL — pending R-2
    "charge_l2":         "ottoq.startCharging",     # PROVISIONAL — pending R-2
    "battery_swap":      "ottoq.batterySwap",       # PROVISIONAL — pending R-2
    "opportunity_charge": "ottoq.startCharging",    # PROVISIONAL — pending R-2
    "inspection":        "ottoq.presentForInspection",  # PROVISIONAL — pending R-2
    "park":              "ottoq.park",              # PROVISIONAL — pending R-2
}

# H1 captures blockingType values NONE, SOFT, SINGLE, HARD, and that HARD
# "prevents other actions". A service action occupies the asset exclusively —
# a robot cannot be charging and hauling — so HARD is the only correct choice.
SERVICE_BLOCKING_TYPE = "HARD"


@dataclass(frozen=True)
class Vda5050Identity:
    """VDA 5050 identifies an asset by (manufacturer, serialNumber), not one id."""
    manufacturer: str
    serial_number: str

    @property
    def asset_ref(self) -> str:
        return f"{self.manufacturer}/{self.serial_number}"

    @staticmethod
    def from_asset_ref(asset_ref: str) -> "Vda5050Identity":
        manufacturer, _, serial = asset_ref.partition("/")
        if not serial:
            raise ValueError(
                f"asset_ref {asset_ref!r} is not manufacturer/serialNumber. VDA 5050 "
                f"has no single-field identity; inventing one loses the namespace."
            )
        return Vda5050Identity(manufacturer, serial)


class Vda5050Adapter(Adapter):
    """Translates VDA 5050 /state → AssetFact and ServiceIntent → /order.

    Holds no site state and no scheduler handle, by construction (Law 1).
    """

    protocol_name = "VDA 5050"
    protocol_version = "PROVISIONAL — see module docstring; R-2"

    # ---- inbound: /state → facts ------------------------------------------
    def inbound(self, message: dict[str, Any]) -> tuple[AssetFact, ...]:
        """One /state message describes exactly one robot, so at most one fact."""
        ident = Vda5050Identity(
            manufacturer=str(message.get("manufacturer", "")),
            serial_number=str(message.get("serialNumber", "")),
        )
        power = message.get("powerSupply") or {}
        safety = message.get("safetyState") or {}

        estop = safety.get("activeEmergencyStop", "NONE")
        faulted = (estop != "NONE") or bool(safety.get("fieldViolation", False))

        # "Blocked" means not making progress, which is NOT the same as faulted:
        # a paused healthy robot is blocked; an e-stopped one is both.
        blocked = bool(message.get("paused", False)) or not bool(message.get("driving", False))

        soc = power.get("batteryCharge")

        extra: list[tuple[str, str]] = []
        for wire_key, fact_key in (
            ("lastNodeSequenceId", "last_node_sequence_id"),
            ("orderId", "order_id"),
            ("orderUpdateId", "order_update_id"),
            ("headerId", "header_id"),
            ("version", "protocol_version_reported"),
        ):
            if wire_key in message:
                extra.append((fact_key, str(message[wire_key])))
        for wire_key, fact_key in (("voltage", "battery_voltage_v"), ("current", "battery_current_a")):
            if wire_key in power:
                extra.append((fact_key, str(power[wire_key])))
        # Completed service actions, so the kernel can see ready-for-work (step 9).
        for node in message.get("nodeStates", []) or []:
            for action in node.get("actionStates", []) or []:
                if str(action.get("actionType", "")).startswith("ottoq.") or "actionId" in action:
                    extra.append((f"action:{action.get('actionId')}", str(action.get("actionState"))))

        return (
            AssetFact(
                asset_ref=ident.asset_ref,
                observed_at=str(message.get("timestamp", "")),
                soc_pct=float(soc) if soc is not None else None,
                faulted=faulted,
                blocked=blocked,
                position_ref=message.get("lastNodeId"),
                extra=tuple(extra),
            ),
        )

    # ---- outbound: intent → /order ----------------------------------------
    def outbound(self, intent: ServiceIntent) -> dict[str, Any]:
        """Phrase an already-made kernel decision as a single-node VDA 5050 order."""
        ident = Vda5050Identity.from_asset_ref(intent.asset_ref)
        action_type = OPERATION_TO_ACTION_TYPE.get(
            intent.operation_code, f"ottoq.{intent.operation_code}"
        )
        # Deterministic ids: a re-sent order must be recognisably the same order.
        # Random ids here would make the master's de-duplication impossible and
        # would put a nondeterminism in the adapter — the exact class of defect
        # migrations 0052/0055/0058 spent three rounds removing from the engine.
        order_id = f"ottoq:{intent.asset_ref}:{intent.operation_code}:{intent.not_before}"
        action_id = f"{order_id}#a0"

        return {
            "headerId": 0,
            "timestamp": intent.not_before,
            "version": "PROVISIONAL",
            "manufacturer": ident.manufacturer,
            "serialNumber": ident.serial_number,
            "orderId": order_id,
            "orderUpdateId": 0,
            "nodes": [
                {
                    "nodeId": intent.service_point_ref,
                    "sequenceId": 0,
                    "released": True,
                    "actions": [
                        {
                            "actionId": action_id,
                            "actionType": action_type,
                            "blockingType": SERVICE_BLOCKING_TYPE,
                            "actionParameters": [
                                {"key": "ottoq.operationCode", "value": intent.operation_code},
                                {"key": "ottoq.notBefore", "value": intent.not_before},
                                {"key": "ottoq.notAfter", "value": intent.not_after},
                                {"key": "ottoq.reason", "value": intent.reason},
                            ],
                        }
                    ],
                }
            ],
            "edges": [],
        }
