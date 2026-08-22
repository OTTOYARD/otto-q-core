"""C10 — mining adapter STUB. Interface contract only; refuses to run.

Grounded in docs/research/H2-mining.md (merged). Per CLAUDE.md C10.4 this is a
contract, not an implementation: mining is a PAPER conformance pack (2.2), and
its job in C11 is to be run against the kernel unchanged and to reveal whether
the kernel bends or breaks. Implementing it now would prejudge that verdict.

Follows the C5 `WaymoStagingPolicy` precedent: compiles, declares the contract,
raises on use.

WHAT A REAL MINING ADAPTER WOULD TRANSLATE
  inbound   fleet-management telemetry (Cat MineStar / Komatsu DISPATCH class
            systems) → AssetFact. Payload state, component hours, fuel OR SoC,
            tyre health (TPMS), oil analysis (KOWA) results.
  outbound  ServiceIntent → whatever the FMS accepts as a service task.

H2's OPEN QUESTIONS record that the MineStar integration endpoints, message
formats and auth methods are NOT known. That is why there is no draft here and
why this file names no field: a guessed field list would read as knowledge.

THE THREE CONSTRAINTS H2 CALLS LIKELIEST KERNEL-BREAKERS — and the honest read
on each, written BEFORE C11 runs so the verdict cannot be retrofitted:

  C4 Dynamic_Charging_Path_Dependency — a trolley-assisted truck MUST follow a
     fixed physical line. Our ServicePoint model is a set of capability pairs
     with no infrastructure network behind it. PROBABLY DECLARATIVE: a trolley
     segment can be modelled as a service point whose capability is "transit"
     and whose occupancy is exclusive. Unconfirmed.

  C5 Maintenance_Scheduling_From_Threshold_Ranges — recall triggered when ANY of
     component hours, oil analysis, or TPMS crosses a threshold. Our
     RecallDecision (2.7 / recall/) already takes a multi-signal AssetState and
     the naive implementation is literally a first-hit-wins rung ladder. LIKELY
     ALREADY SUPPORTED — this one looks easier than H2 expects.

  C6 Operator-Override_Overrules_System — a human can overrule a scheduled
     service and keep the truck hauling. H2 calls this "anathema to a
     solver-based kernel."
     THIS IS THE ONE TO WATCH, and the honest position is that we may already
     have it: CLAUDE.md 2.7 makes work-side refusal "a first-class event
     triggering re-solve, never an error", and C9 implements refuse() against
     exactly that contract. If a human override is just a refusal with a
     different actor, the kernel already bends. If it must also invalidate a
     constraint the solver treated as hard, it does not, and that is a genuine
     platform-thesis finding to escalate per CLAUDE.md 2.2 — not something to
     quietly absorb.
"""

from __future__ import annotations

from typing import Any

from adapters.base import Adapter, AssetFact, ServiceIntent

PACK_ID = "mining"
STATUS = "PAPER — contract only, per CLAUDE.md 2.2 and C10.4"

# Named so C11 can assert the pack declares them, without implying we can enforce them.
DECLARED_CONSTRAINTS: tuple[str, ...] = (
    "C1_Asset_Must_Have_Clearance",
    "C2_Resource_Sharing_Exclusive_Use",
    "C3_Energy_Resupply_Window",
    "C4_Dynamic_Charging_Path_Dependency",
    "C5_Maintenance_Scheduling_From_Threshold_Ranges",
    "C6_Operator_Override_Overrules_System",
)


class MiningAdapterNotImplemented(NotImplementedError):
    """Raised on any use. Mining is a paper pack until C11 says otherwise."""


class MiningAdapter(Adapter):
    protocol_name = "mining-fms (unspecified — see H2 OPEN QUESTIONS)"
    protocol_version = "none — no wire format is known"

    def inbound(self, message: Any) -> tuple[AssetFact, ...]:
        raise MiningAdapterNotImplemented(
            "Mining is a paper conformance pack. H2's OPEN QUESTIONS record that "
            "the MineStar/DISPATCH endpoints, schemas and auth are unknown; writing "
            "a mapping now would be invention dressed as integration."
        )

    def outbound(self, intent: ServiceIntent) -> Any:
        raise MiningAdapterNotImplemented(
            "Mining is a paper conformance pack. See inbound()."
        )
