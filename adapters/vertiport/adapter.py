"""C10 — vertiport adapter STUB. Interface contract only; refuses to run.

Grounded in docs/research/H3-vertiport-drone.md (merged). Paper pack, same
standing as mining: the contract exists so C11 can load it; the implementation
does not, so C11's verdict is not prejudged.

H3 carries a NEUTRALITY FLAG worth repeating here, because it is commercially
load-bearing rather than technical: there is **no neutral multi-operator
orchestration ecosystem** for vertiports, and drone-in-a-box is vendor-captive.
H3's own open question — "How do vertiport operators plan to handle
inter-operator arbitration for pad scheduling?" — is the same unowned function
H1's gap table calls `Arbitrate Multi-Party Bay Access`, owner **None**. Two
independent sectors describing the same hole is the strongest evidence in the
research set that the kernel is aimed at something real.

WHAT A REAL VERTIPORT ADAPTER WOULD TRANSLATE
  inbound   vertiport management system → AssetFact. SoC, battery temperature,
            pad occupancy, tug availability.
  outbound  ServiceIntent → a pad/charge/turnaround task.

H3 records that Eve's UATM API-accessibility at third-party vertiports with
non-Eve vehicles is UNCONFIRMED, so no wire format is drafted.

THE THREE HARDEST CONSTRAINTS FROM H3, and the honest read on each:

  Battery Cooling — a 20-minute cooldown before fast charge if SoC > 90% on
     landing. Physical state gates scheduling. LIKELY DECLARATIVE, and notably
     we already have the shape: CLAUDE.md 2.5 lists "DCFC cooldown as a
     minimum-gap constraint on the SERVICE POINT (18 min in the throughput
     model)". Vertiport cooldown is the same constraint attached to the ASSET
     rather than the point. Whether the kernel can express an asset-side minimum
     gap is a real question for C11, not a rename.

  Tug-As-Resource — only N tugs; repositioning queues behind them. CLAUDE.md 2.3
     already requires "inter-point moves as scheduled operations" that "consume
     path resources". A tug is that, made explicit. PROBABLY SUPPORTED.

  Charger Compatibility — CCS vs proprietary; a handshake, so duration is not
     determined by power alone. Our capability model is (asset_class, operation)
     pairs, which expresses compatibility but NOT a non-numeric duration
     dependency. FLAGGED: this is the one that looks least like our model.
"""

from __future__ import annotations

from typing import Any

from adapters.base import Adapter, AssetFact, ServiceIntent

PACK_ID = "vertiport"
STATUS = "PAPER — contract only, per CLAUDE.md 2.2 and C10.4"

DECLARED_CONSTRAINTS: tuple[str, ...] = (
    "Pad_Separation",
    "Tug_As_Resource",
    "Battery_Cooling",
    "Charger_Compatibility",
    "Vertipad_Exclusive_Use",
)


class VertiportAdapterNotImplemented(NotImplementedError):
    """Raised on any use. Vertiport is a paper pack until C11 says otherwise."""


class VertiportAdapter(Adapter):
    protocol_name = "vertiport-vms (unspecified — see H3 OPEN QUESTIONS)"
    protocol_version = "none — no wire format is known"

    def inbound(self, message: Any) -> tuple[AssetFact, ...]:
        raise VertiportAdapterNotImplemented(
            "Vertiport is a paper conformance pack. H3 records that UATM "
            "API-accessibility for third-party vehicles is unconfirmed; there is "
            "no wire format to map."
        )

    def outbound(self, intent: ServiceIntent) -> Any:
        raise VertiportAdapterNotImplemented(
            "Vertiport is a paper conformance pack. See inbound()."
        )
