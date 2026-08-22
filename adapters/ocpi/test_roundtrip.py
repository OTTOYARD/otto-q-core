"""C10 done-when: "OCPI mapping round-trips a synthetic session losslessly."

The lossless direction is CDR → SDR → CDR, and that is what is asserted here.
The other direction is lossy for every non-energy operation, and that loss is
enumerated and asserted too — a mapping that quietly dropped `operation_code`
would otherwise look like a pass.
"""

from __future__ import annotations

import pytest

from adapters.base import assert_translation_only
from adapters.ocpi.adapter import (
    OCPI_CDR_FIELDS,
    SDR_FIELDS_OCPI_CANNOT_CARRY,
    OcpiAdapter,
    SdrView,
)


SYNTHETIC_CDR = {
    "id": "5d0b9b4c-8f2a-4d1e-9c33-2b7a51e6f001",
    "start_date_time": "2026-08-22T22:04:00Z",
    "end_date_time": "2026-08-22T22:41:00Z",
    "session_id": "9a1c77e2-4f10-4a55-bb90-1e2d3c4b5a60",
    "total_energy": 38.4,
    "total_cost": 9.12,
    "currency": "USD",
    "total_time": 0.6166666666666667,          # 37 minutes, in the assumed unit
    "cdr_token": "0f3c1b7a-2e44-4c9d-8f01-77aa22bb33cc",
    "tariff_id": "c1d2e3f4-a5b6-47c8-9d0e-1f2a3b4c5d6e",
    "signed_data": "sig:v1:9f8e7d6c",
    "last_updated": "2026-08-22T22:41:05Z",
    "cdr_location": {"depot_id": "22222222-2222-2222-2222-222222222222",
                     "stall_id": "fa4f4d72-1111-2222-3333-444455556666"},
}


def test_adapter_obeys_the_laws():
    assert_translation_only(OcpiAdapter)


def test_cdr_survives_a_full_round_trip_unchanged():
    a = OcpiAdapter()
    sdr = a.cdr_to_sdr(SYNTHETIC_CDR, operation_code="charge_dcfc",
                       pack_id="robotaxi", asset_class_code="av_sedan")
    back = a.sdr_to_cdr(sdr)
    assert back == SYNTHETIC_CDR, {
        k: (SYNTHETIC_CDR.get(k), back.get(k))
        for k in set(SYNTHETIC_CDR) | set(back)
        if SYNTHETIC_CDR.get(k) != back.get(k)
    }


def test_the_round_trip_covers_every_mapped_field():
    # A round trip that silently skipped a field would still pass equality if the
    # field were absent from the fixture. Assert the fixture exercises all of them.
    mapped = set(OCPI_CDR_FIELDS) - {"cdr_location"}   # nested, checked separately
    missing = mapped - set(SYNTHETIC_CDR)
    assert not missing, f"fixture does not exercise mapped fields: {sorted(missing)}"
    assert "cdr_location" in SYNTHETIC_CDR


def test_minutes_to_hours_conversion_is_exact_enough_to_round_trip():
    a = OcpiAdapter()
    sdr = a.cdr_to_sdr(SYNTHETIC_CDR, operation_code="x", pack_id="p", asset_class_code="c")
    assert sdr.duration_min == pytest.approx(37.0)
    assert a.sdr_to_cdr(sdr)["total_time"] == pytest.approx(SYNTHETIC_CDR["total_time"])


def test_a_non_energy_sdr_loses_exactly_what_we_say_it_loses():
    """The moat, asserted. A wash has no kWh and OCPI has nowhere to put the rest."""
    wash = SdrView(
        sdr_id="w-1", started_at="2026-08-22T23:00:00Z", ended_at="2026-08-22T23:11:00Z",
        ocpp_session_id=None, energy_kwh=None, total_cost_usd=4.50, currency="USD",
        duration_min=11.0, fleet_operator_id="op-a", tariff_id="t-wash",
        signature="sig:v1:aabb", issued_at="2026-08-22T23:11:02Z",
        depot_id="22222222-2222-2222-2222-222222222222", stall_id="wash-1",
        operation_code="exterior_wash", pack_id="robotaxi", asset_class_code="av_sedan",
    )
    cdr = OcpiAdapter().sdr_to_cdr(wash)

    # What OCPI keeps.
    assert cdr["total_cost"] == 4.50
    assert cdr["total_energy"] is None          # a wash moves no electrons

    # What OCPI cannot express — the enumerated loss.
    for lost in ("operation_code", "pack_id", "asset_class_code"):
        assert lost not in cdr, f"{lost} unexpectedly survived into an OCPI CDR"
        assert lost in " ".join(SDR_FIELDS_OCPI_CANNOT_CARRY), f"{lost} not documented as lost"

    # And the loss is total: from the CDR alone you cannot tell a wash from a charge
    # that delivered no energy. That indistinguishability IS the gap CLAUDE.md 2.6
    # and H1's gap table both describe.
    faulted_charge = OcpiAdapter().sdr_to_cdr(
        SdrView(**{**wash.__dict__, "operation_code": "charge_dcfc"})
    )
    assert faulted_charge == cdr


def test_attribution_dimensions_must_be_supplied_not_defaulted():
    # cdr_to_sdr accepts them as keywords precisely so a caller must think. If they
    # are omitted the record is unattributable, and this test documents that the
    # empty result is visible rather than plausible-looking.
    sdr = OcpiAdapter().cdr_to_sdr(SYNTHETIC_CDR)
    assert sdr.pack_id == "" and sdr.operation_code == ""
