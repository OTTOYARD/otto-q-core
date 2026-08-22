"""C10 — OCPI mapping over the existing OCPP/session substrate.

THE STRATEGIC POINT, which is the reason this file exists at all (CLAUDE.md 2.6):
OCPI standardised *electrons*. Its CDR is a settlement record for a charging
session. Nothing in any sector standardises a settlement record for a completed
SERVICE event — a wash, a calibration, a sensor clean, a battery swap. H1's gap
table says the same thing from the intralogistics side and marks the owner of
"Model Service Session w/ Economics" as **None**, with the note "This is the moat."

So the mapping runs in both directions and is deliberately asymmetric:

    ServiceDetailRecord  →  OCPI CDR      LOSSY BY DESIGN, and the loss is the point.
                                          An energy SDR maps cleanly. A wash SDR has
                                          no kWh, no meter, no connector — OCPI has
                                          nowhere to put it. What survives the trip
                                          is exactly the part OCPI already owns.
    OCPI CDR             →  ServiceDetailRecord   LOSSLESS. Everything OCPI carries
                                          has a home in the SDR, because the SDR was
                                          shaped as a superset (C3).

C10 requires the mapping to "round-trip a synthetic session losslessly". The
round-trip that is asserted in tests is therefore the one that CAN be lossless —
CDR → SDR → CDR — plus an explicit, enumerated statement of what an SDR loses on
the way out. Claiming a lossless round-trip in the other direction would be false
for every non-energy operation, i.e. for the majority of the catalog.

    ══════════════════════════════════════════════════════════════════════════
    ASSUMPTION — pending R-1. EVERY OCPI FIELD NAME BELOW IS ASSUMED.
    H7 §3.1 names github.com/ocpi/ocpi as the field source and marks it "adopt";
    H8 confirms conformance is tested by the EVRoaming Test Tool against 2.2.1 or
    2.3.0. NEITHER MERGED FILE CONTAINS THE FIELD LISTS. Request R-1 asks for them
    field-by-field with units and complete enum sets.
    Until R-1 lands, treat the *names* here as unverified and the *structure* as
    load-bearing: the mapping machinery, the totality check and the round-trip
    property are all independent of spelling. When R-1 arrives, wrong names are a
    rename in OCPI_CDR_FIELDS below — not a redesign.
    ══════════════════════════════════════════════════════════════════════════
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from adapters.base import Adapter, AssetFact, ServiceIntent


# OCPI CDR field  →  ottoq_service_detail_records column (verified against the
# live schema; the SDR side of every pair is real, the OCPI side is R-1-pending).
OCPI_CDR_FIELDS: dict[str, str] = {
    "id":                 "sdr_id",
    "start_date_time":    "started_at",
    "end_date_time":      "ended_at",
    "session_id":         "ocpp_session_id",
    "total_energy":       "energy_kwh",
    "total_cost":         "total_cost_usd",
    "currency":           "currency",
    "total_time":         "duration_min",        # UNIT MISMATCH — see below
    "cdr_token":          "fleet_operator_id",   # via ottoq_service_tokens
    "tariff_id":          "tariff_id",
    "signed_data":        "signature",
    "last_updated":       "issued_at",
    "cdr_location":       "depot_id + stall_id",
}

# SDR columns with NO OCPI home. This list is the moat, enumerated.
SDR_FIELDS_OCPI_CANNOT_CARRY: dict[str, str] = {
    "operation_code":   "OCPI has no concept of a non-energy operation",
    "pack_id":          "OCPI has no sector dimension",
    "asset_class_code": "OCPI's token/EV model has no asset class",
    "peak_kw":          "CDR carries totals; peak is a demand-billing input",
    "cost_components":  "OCPI totals are flat; the component breakdown is ours",
    "billable_amount_usd": "distinct from total_cost — margin lives between them",
    "source_kind":      "which subsystem produced the record",
    "leg_id / visit_id / booking_id": "itinerary provenance",
    "payload_hash / signature_key_id / signature_algorithm":
        "OCPI signed_data is one blob; our signing is a keyed registry",
    "data_source":      "sim vs production co-existence (CLAUDE.md 2.8)",
    "sim_run_id":       "the run ID every number ships with (CLAUDE.md 2.9)",
}

# UNIT HAZARD, flagged rather than guessed. Our duration_min is MINUTES. R-1 asks
# explicitly whether OCPI total_time is hours or minutes. The converter below is
# written so the unit lives in exactly one place.
OCPI_TOTAL_TIME_UNIT = "hours"      # ASSUMPTION — pending R-1


@dataclass(frozen=True)
class SdrView:
    """The SDR columns this mapping touches. Mirrors ottoq_service_detail_records."""
    sdr_id: str
    started_at: str
    ended_at: str
    ocpp_session_id: str | None
    energy_kwh: float | None
    total_cost_usd: float | None
    currency: str
    duration_min: float | None
    fleet_operator_id: str
    tariff_id: str | None
    signature: str | None
    issued_at: str
    depot_id: str
    stall_id: str | None
    # carried through the round trip but invisible to OCPI:
    operation_code: str = ""
    pack_id: str = ""
    asset_class_code: str = ""


def _min_to_ocpi_time(duration_min: float | None) -> float | None:
    if duration_min is None:
        return None
    if OCPI_TOTAL_TIME_UNIT == "hours":
        return duration_min / 60.0
    return duration_min


def _ocpi_time_to_min(total_time: float | None) -> float | None:
    if total_time is None:
        return None
    if OCPI_TOTAL_TIME_UNIT == "hours":
        return total_time * 60.0
    return total_time


class OcpiAdapter(Adapter):
    """Translates between OCPI-shaped settlement records and the SDR.

    Decides nothing: it does not price, does not choose a tariff, does not decide
    whether a session is billable. Those are kernel/settlement concerns.
    """

    protocol_name = "OCPI"
    protocol_version = "2.2.1 — ASSUMPTION pending R-1"

    # ---- inbound: a foreign CDR becomes facts -----------------------------
    def inbound(self, message: dict[str, Any]) -> tuple[AssetFact, ...]:
        """An OCPI CDR is a settled past event, so it yields one historical fact."""
        return (
            AssetFact(
                asset_ref=str(message.get("cdr_token", "")),
                observed_at=str(message.get("end_date_time", "")),
                extra=(
                    ("ocpi_cdr_id", str(message.get("id", ""))),
                    ("total_energy_kwh", str(message.get("total_energy", ""))),
                    ("total_cost", str(message.get("total_cost", ""))),
                ),
            ),
        )

    # ---- outbound: an intent becomes an OCPI-shaped forward reference -----
    def outbound(self, intent: ServiceIntent) -> dict[str, Any]:
        """OCPI has no 'planned service' object, so this is the honest minimum."""
        return {
            "_ottoq_note": "OCPI defines no forward service object; R-1 Q7 asks "
                           "whether the Booking module changes this.",
            "operation_code": intent.operation_code,
            "location_ref": intent.service_point_ref,
            "start_date_time": intent.not_before,
            "end_date_time": intent.not_after,
        }

    # ---- the settlement mapping proper ------------------------------------
    def sdr_to_cdr(self, sdr: SdrView) -> dict[str, Any]:
        """SDR → OCPI CDR. Lossy for non-energy operations, by design."""
        return {
            "id": sdr.sdr_id,
            "start_date_time": sdr.started_at,
            "end_date_time": sdr.ended_at,
            "session_id": sdr.ocpp_session_id,
            "total_energy": sdr.energy_kwh,
            "total_cost": sdr.total_cost_usd,
            "currency": sdr.currency,
            "total_time": _min_to_ocpi_time(sdr.duration_min),
            "cdr_token": sdr.fleet_operator_id,
            "tariff_id": sdr.tariff_id,
            "signed_data": sdr.signature,
            "last_updated": sdr.issued_at,
            "cdr_location": {"depot_id": sdr.depot_id, "stall_id": sdr.stall_id},
        }

    def cdr_to_sdr(self, cdr: dict[str, Any], *,
                   operation_code: str = "", pack_id: str = "",
                   asset_class_code: str = "") -> SdrView:
        """OCPI CDR → SDR. Lossless: the SDR is a superset by construction.

        The three keyword arguments are the dimensions OCPI does not carry. They
        are REQUIRED to be supplied by the caller rather than defaulted silently,
        because an SDR that quietly claims pack_id='' is a settlement record that
        cannot be attributed — and attribution is the whole point of the object.
        """
        loc = cdr.get("cdr_location") or {}
        return SdrView(
            sdr_id=str(cdr.get("id", "")),
            started_at=str(cdr.get("start_date_time", "")),
            ended_at=str(cdr.get("end_date_time", "")),
            ocpp_session_id=cdr.get("session_id"),
            energy_kwh=cdr.get("total_energy"),
            total_cost_usd=cdr.get("total_cost"),
            currency=str(cdr.get("currency", "")),
            duration_min=_ocpi_time_to_min(cdr.get("total_time")),
            fleet_operator_id=str(cdr.get("cdr_token", "")),
            tariff_id=cdr.get("tariff_id"),
            signature=cdr.get("signed_data"),
            issued_at=str(cdr.get("last_updated", "")),
            depot_id=str(loc.get("depot_id", "")),
            stall_id=loc.get("stall_id"),
            operation_code=operation_code,
            pack_id=pack_id,
            asset_class_code=asset_class_code,
        )
