"""The ottoq_vehicle_classes -> class_table projection (finding L-41).

The rows below are the LIVE SHAPE, read from the flagship database 2026-09-08
after migration 0209: the exact column names, the Decimal-or-string numerics a
client returns, and the charge_kinds text[] the migration backfilled. Their
CONTENT is the real content -- these are nine rows of a lookup table, not
telemetry -- which is what makes the round-trip below a claim about production
rather than about a fixture.
"""

from __future__ import annotations

import sys
from decimal import Decimal
from pathlib import Path

import pytest

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

from class_table import (  # noqa: E402
    OPTIONAL,
    REQUIRED,
    SELECT_VEHICLE_CLASSES,
    ClassTableError,
    class_table_from_rows,
)
from forward_proposer import DEFAULT_CLASS_KEY, frame_to_scenario, propose  # noqa: E402

#: Three of the nine live classes: the two that carry vehicles at the flagship
#: depot, and the one class with fast_charge_compatible = false.
LIVE_ROWS = [
    {"vehicle_class_code": "waymo_jaguar_ipace_2024",
     "battery_capacity_kwh": Decimal("90"), "max_charge_rate_kw": Decimal("100"),
     "charge_kinds": ["dcfc", "l2"], "battery_chemistry": "NMC",
     "energy_curve": [{"above_soc_pct": 0, "accept_frac": 1.0},
                      {"above_soc_pct": 70, "accept_frac": 0.6}]},
    {"vehicle_class_code": "tesla_model_y_robotaxi_2024",
     "battery_capacity_kwh": "75", "max_charge_rate_kw": "250",
     "charge_kinds": ["dcfc", "l2"], "battery_chemistry": "NCA",
     "energy_curve": None},
    {"vehicle_class_code": "generic_av_l2",
     "battery_capacity_kwh": Decimal("100"), "max_charge_rate_kw": Decimal("19"),
     "charge_kinds": ["l2"], "battery_chemistry": "NMC", "energy_curve": None},
]

SITE = {"power_cap_kw_hard": 600, "power_soft_target_kw": 450,
        "dcfc_cooldown_min": 18, "move_duration_min": 4, "path_capacity": 2,
        "cold_start_below_c": 5, "cold_start_penalty_min": 12,
        "onpeak_window_min": [240, 420]}


def test_the_projection_renames_every_column_the_kernel_needs():
    table = class_table_from_rows(LIVE_ROWS)
    assert set(table) == {r["vehicle_class_code"] for r in LIVE_ROWS}
    waymo = table["waymo_jaguar_ipace_2024"]
    assert waymo["battery_kwh"] == 90.0 and isinstance(waymo["battery_kwh"], float)
    assert waymo["max_charge_kw"] == 100.0
    assert waymo["charge_kinds"] == ["dcfc", "l2"]
    assert waymo["battery_chemistry"] == "NMC"
    assert len(waymo["energy_curve"]) == 2
    #: None of the RENAMED database column names survive into the kernel dict
    #: -- passing a row verbatim is what raised KeyError before this module.
    #: (charge_kinds is deliberately not renamed; it is in REQUIRED because it
    #: is required, not because it moves.)
    renamed = {c for c, f in REQUIRED.items() if c != f}
    assert renamed and not (set(waymo) & renamed), sorted(set(waymo) & renamed)


def test_string_and_decimal_numerics_both_land_as_floats():
    tesla = class_table_from_rows(LIVE_ROWS)["tesla_model_y_robotaxi_2024"]
    assert tesla["battery_kwh"] == 75.0 and tesla["max_charge_kw"] == 250.0


def test_a_null_optional_column_is_omitted_not_nulled():
    tesla = class_table_from_rows(LIVE_ROWS)["tesla_model_y_robotaxi_2024"]
    assert "energy_curve" not in tesla, (
        "a null curve must be ABSENT so the kernel's own flat default applies; "
        "a None would be read as a curve and crash the segmenter")


@pytest.mark.parametrize("column", sorted(REQUIRED))
def test_a_missing_required_column_raises_and_names_the_class(column):
    row = {**LIVE_ROWS[0], column: None}
    with pytest.raises(ClassTableError, match="waymo_jaguar_ipace_2024"):
        class_table_from_rows([row])


def test_the_postgres_array_literal_is_refused_rather_than_iterated():
    #: '{dcfc,l2}' iterates as characters, so the class would come out capable
    #: of 'd', '{', ',' -- and match no point, silently, on every vehicle.
    row = {**LIVE_ROWS[0], "charge_kinds": "{dcfc,l2}"}
    with pytest.raises(ClassTableError, match="postgres literal"):
        class_table_from_rows([row])


def test_an_empty_charge_kinds_is_refused():
    with pytest.raises(ClassTableError, match="empty charge_kinds"):
        class_table_from_rows([{**LIVE_ROWS[0], "charge_kinds": []}])


def test_a_duplicate_class_code_is_refused():
    with pytest.raises(ClassTableError, match="duplicate"):
        class_table_from_rows([LIVE_ROWS[0], LIVE_ROWS[0]])


def test_a_row_with_no_class_code_is_refused():
    with pytest.raises(ClassTableError, match="cannot be joined"):
        class_table_from_rows([{**LIVE_ROWS[0], "vehicle_class_code": None}])


def test_the_committed_select_names_every_column_the_projection_reads():
    for column in list(REQUIRED) + list(OPTIONAL) + ["vehicle_class_code"]:
        assert column in SELECT_VEHICLE_CLASSES, (
            f"{column} is projected but the committed SELECT does not fetch it")


# ---------------------------------------------------------------------------
# The join itself: a production-shaped frame, joined on the production key.
# ---------------------------------------------------------------------------

def _prod_frame():
    """The frame as ottoq_build_decision_frame emits it AFTER migration 0209 --
    vehicle_class_code on vehicles, supported_inlet_types on stalls, and the
    flagship depot's real connector shape (every charging stall is 'Multi')."""
    return {
        "vehicles": [
            {"id": "veh-w", "state": "arrived_at_gate", "soc": 31.5,
             "stall_id": None, "inlet_type": "CCS1", "inlet_max_kw": 100.0,
             "fleet_operator_id": "op-1", "make": "Jaguar", "platform": "waymo",
             "svc_step": None, "target_soc": 90, "min_soc_threshold": 20,
             "vehicle_class_code": "waymo_jaguar_ipace_2024"},
            {"id": "veh-t", "state": "arrived_at_gate", "soc": 22.0,
             "stall_id": None, "inlet_type": "NACS", "inlet_max_kw": 250.0,
             "fleet_operator_id": "op-2", "make": "Tesla", "platform": "tesla",
             "svc_step": None, "target_soc": 90, "min_soc_threshold": 20,
             "vehicle_class_code": "tesla_model_y_robotaxi_2024"},
            #: the one flagship vehicle that carries no class code
            {"id": "veh-x", "state": "arrived_at_gate", "soc": 40.0,
             "stall_id": None, "inlet_type": None, "inlet_max_kw": None,
             "fleet_operator_id": None, "make": None, "platform": "not_applicable",
             "svc_step": None, "target_soc": 90, "min_soc_threshold": 20,
             "vehicle_class_code": None},
        ],
        "stalls": [
            {"id": "st-1", "type": "dcfc", "status": "available",
             "vehicle_id": None, "connector_type": "Multi",
             "connector_max_kw": 350.0, "supported_inlet_types": ["CCS1", "CCS1", "NACS"]},
            {"id": "st-2", "type": "l2", "status": "available",
             "vehicle_id": None, "connector_type": "Multi",
             "connector_max_kw": 19.2, "supported_inlet_types": ["CCS1", "CCS1", "NACS"]},
            {"id": "st-3", "type": "staging", "status": "available",
             "vehicle_id": None, "connector_type": "NonCharging",
             "connector_max_kw": 0, "supported_inlet_types": []},
        ],
        "sessions": [], "energy": {}, "bess": [],
    }


def test_the_production_frame_joins_to_the_production_class_table():
    """L-41 end to end: real column names, real join key, real connector shape.

    Before this, the bridge indexed by `platform` against a table keyed by
    vehicle_class_code, using kernel field names the table does not have. Every
    live vehicle would have abstained for want of a class, or raised KeyError.
    """
    table = class_table_from_rows(LIVE_ROWS)
    r = propose(_prod_frame(), table, site=SITE)
    assert r["planned"] == 2, [p["proposal"] for p in r["proposals"]]
    assert r["abstained"] == 1
    unplanned = next(p for p in r["proposals"] if p["proposal"].get("abstain"))
    assert unplanned["entity_id"] == "veh-x"
    assert DEFAULT_CLASS_KEY in unplanned["proposal"]["rationale"]["reason"]


def test_the_multi_stalls_duplicate_ccs1_does_not_split_the_capability():
    """The live rows literally read {CCS1,CCS1,NACS}. It is a set, not a list."""
    sc, _ = frame_to_scenario(_prod_frame(), class_table_from_rows(LIVE_ROWS),
                              site=SITE)
    assert {p["kind"] for p in sc["service_points"]} == {
        "dcfc@CCS1+NACS", "l2@CCS1+NACS"}


def test_a_caller_may_still_join_on_platform():
    """`class_key` is the seam; the production key is only its default."""
    table = {"waymo": class_table_from_rows(LIVE_ROWS)["waymo_jaguar_ipace_2024"]}
    r = propose(_prod_frame(), table, site=SITE, class_key="platform")
    assert r["planned"] == 1
    assert {p["entity_id"] for p in r["proposals"]
            if not p["proposal"].get("abstain")} == {"veh-w"}
