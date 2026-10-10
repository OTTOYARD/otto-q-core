"""db/migrations/0694: what the twin's chargers write is OCPP 2.0.1, checked against the 2.0.1 JSON schemas.

WHY THIS EXISTS. FINDINGS G412: the twin's charger log said 2.0.1 and spoke 1.6 (StartTransaction, MeterValues,
StopTransaction; a Temperature measurand and an Authorize timestamp 2.0.1 does not admit). 0694 builds every
TransactionEvent through helpers it creates; this test loads those helpers from the migration file itself, builds each
message the twin's start, advance and stop write (Started; Updated, and the reading before a fault; Ended for every
reason a charge stops for in the engine's history; Authorize; StatusNotification) and validates each against the
OCPP 2.0.1 schemas the pinned `ocpp` library ships (requirements.txt). Two controls in the old shape must be refused, so
a validator that passes everything cannot pass this test. It also checks the charge clock's reader takes a reading's
charge from either shape, and that a session's seqNo counts its own events.

That the patched start, advance and stop call these helpers, and that one charge on the live functions comes out as one
2.0.1 transaction, is proved in 0694's own V1. SKIPS where no scratch PostgreSQL is reachable.
"""
import asyncio
import json
import os
import re
import sys
import tempfile

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
from test_v2_door_sql import _drop, _new_db, _server_up  # noqa: E402

MIG_0694 = os.path.join(ROOT, "db", "migrations", "0694_the_twins_chargers_speak_ocpp_2_0_1.sql")
# every stopped_reason a twin charge has ended with (ocpp_sessions, read 2026-10-10)
REASONS = ["completed", "sim_reset", "fault.session_aborted_other", "fault.connector_cable", "fault.communication_dropout",
           "fault.station_hardware", "fault.thermal_emergency", "fault.ground_fault_safety", "vehicle_departed_orphan_sweep",
           "fault.operator_injected"]
TX = "TXN-20260901130500-abcdef12"

pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _helpers_sql():
    src = open(MIG_0694, encoding="utf-8").read()
    fns = re.findall(r'^(CREATE FUNCTION (?:twin\.ottoq_ocpp201_|ottoq\.ottoq_ocpp_meter_soc).*?\$fn\$.*?\$fn\$;)', src, re.S | re.M)
    assert len(fns) == 6, f"expected the six helpers of 0694, found {len(fns)}"
    return "\n".join(fns)


@pytest.fixture(scope="module")
def db():
    d = _new_db()
    try:
        d.run("CREATE SCHEMA twin; CREATE SCHEMA ottoq; "
              "CREATE TABLE public.ottoq_ocpp_messages (message_seq bigserial, ocpp_session_id uuid, message_type text, "
              "payload jsonb)")
        with tempfile.NamedTemporaryFile("w", suffix=".sql", encoding="utf-8", delete=False) as f:
            f.write(_helpers_sql())
        try:
            rc, err = d.file(f.name)
        finally:
            os.remove(f.name)
        assert rc == 0, f"0694's helpers did not load: {err}"
        d.run("SET TimeZone = 'UTC'")
        yield d
    finally:
        _drop(d)


def tx_event(db, event, trigger, seq, samples, custom=None, id_token=None, stopped=None, spent=None, at="2026-09-01 13:05:00+00"):
    smp = ", ".join(f"twin.ottoq_ocpp201_sample('{m}', {v}, '{u}')" for m, v, u in samples)
    sql = (f"SET TimeZone = 'UTC'; SELECT twin.ottoq_ocpp201_tx_event('{event}', {trigger}, {seq}, '{TX}', '{at}', "
           f"'{'Idle' if event == 'Ended' else 'Charging'}', twin.ottoq_ocpp201_samples(ARRAY[{smp}]::jsonb[]), "
           f"{custom or 'NULL'}, {repr(id_token) if id_token else 'NULL'}, {stopped or 'NULL'}, {spent or 'NULL'})")
    return db.json(sql)


async def _validate(action, payload):
    from ocpp.messages import Call, validate_payload
    await validate_payload(Call(unique_id="1", action=action, payload=payload), ocpp_version="2.0.1")


def valid(action, payload):
    asyncio.run(_validate(action, payload))


def refused(action, payload):
    try:
        valid(action, payload)
    except Exception:  # the library raises its FormatViolationError / TypeConstraintViolationError
        return True
    return False


def test_the_old_shapes_are_refused_so_the_validator_is_not_a_rubber_stamp():
    # the reading the twin wrote before 0694, as a 2.0.1 TransactionEvent: Temperature is no 2.0.1 measurand, and a
    # sampled value has no unit or location of that form
    assert refused("TransactionEvent", {
        "eventType": "Updated", "timestamp": "2026-09-01T13:15:00+00:00", "triggerReason": "MeterValuePeriodic", "seqNo": 1,
        "transactionInfo": {"transactionId": TX}, "meterValue": [{"timestamp": "2026-09-01T13:15:00+00:00", "sampledValue": [
            {"value": 31.4, "measurand": "Temperature", "unit": "Celsius", "location": "battery"}]}]})
    # Authorize admits idToken, certificate and hash data only
    assert refused("Authorize", {"idToken": {"idToken": "TWIN-abcdef12", "type": "ISO14443"},
                                 "timestamp": "2026-09-01T13:05:00+00:00"})


def test_a_charge_opens_as_a_2_0_1_transaction_started(db):
    p = tx_event(db, "Started", "'CablePluggedIn'", 0,
                 [("Energy.Active.Import.Register", 0, "kWh"), ("SoC", 50, "Percent")],
                 custom="jsonb_build_object('target_soc_pct', 100, 'ambient_temp_c', 22.5)", id_token="TWIN-abcdef12")
    valid("TransactionEvent", p)
    assert p["eventType"] == "Started" and p["seqNo"] == 0 and p["idToken"]["idToken"] == "TWIN-abcdef12"
    assert p["customData"] == {"vendorId": "com.ottoyard.twin", "target_soc_pct": 100, "ambient_temp_c": 22.5}


def test_each_tick_and_the_reading_before_a_fault_are_2_0_1_updated_events(db):
    p = tx_event(db, "Updated", "'MeterValuePeriodic'", 1,
                 [("Power.Active.Import", 11.0412, "kW"), ("SoC", 52.37, "Percent"),
                  ("Energy.Active.Import.Interval", 1.8402, "kWh"), ("Energy.Active.Import.Register", 1.8402, "kWh")],
                 custom="jsonb_build_object('battery_temp_c', 31.4)")
    valid("TransactionEvent", p)
    assert [s["measurand"] for s in p["meterValue"][0]["sampledValue"]] == [
        "Power.Active.Import", "SoC", "Energy.Active.Import.Interval", "Energy.Active.Import.Register"]
    f = tx_event(db, "Updated", "'MeterValuePeriodic'", 2, [("Power.Active.Import", 10.9, "kW"), ("SoC", "NULL", "Percent")],
                 custom="jsonb_build_object('battery_temp_c', 32.0, 'fault_imminent', true)")
    valid("TransactionEvent", f)
    # a sample with no value is left out, never sent as a null (2.0.1 requires value)
    assert [s["measurand"] for s in f["meterValue"][0]["sampledValue"]] == ["Power.Active.Import"]
    assert f["customData"]["fault_imminent"] is True


@pytest.mark.parametrize("reason", REASONS)
def test_every_reason_a_charge_has_ended_for_is_a_2_0_1_ended_event(db, reason):
    p = tx_event(db, "Ended", f"(twin.ottoq_ocpp201_ended_reasons('{reason}')).trigger_reason", 3,
                 [("Energy.Active.Import.Register", 5.52, "kWh"), ("SoC", 56, "Percent")],
                 custom=f"jsonb_build_object('twin_reason', '{reason}', 'duration_seconds', 1800.0)",
                 stopped=f"(twin.ottoq_ocpp201_ended_reasons('{reason}')).stopped_reason", spent=1800)
    valid("TransactionEvent", p)
    assert p["customData"]["twin_reason"] == reason and p["transactionInfo"]["timeSpentCharging"] == 1800
    if reason == "completed":
        assert (p["triggerReason"], p["transactionInfo"]["stoppedReason"]) == ("ChargingStateChanged", "SOCLimitReached")
    if reason == "fault.ground_fault_safety":
        assert p["transactionInfo"]["stoppedReason"] == "GroundFault"


def test_authorize_and_status_notification_are_2_0_1():
    valid("Authorize", {"idToken": {"idToken": "TWIN-abcdef12", "type": "ISO14443"}})
    valid("StatusNotification", {"connectorId": 1, "connectorStatus": "Occupied", "evseId": 1,
                                 "timestamp": "2026-09-01T13:05:00+00:00"})


def test_the_charge_clock_reads_a_readings_charge_from_either_shape_and_only_from_a_reading(db):
    mv16 = '{"sampledValue":[{"value":11,"measurand":"Power.Active.Import"},{"value":52.37,"measurand":"SoC"}]}'
    other = '{"sampledValue":[{"value":11,"measurand":"Power.Active.Import"},{"value":52.37,"measurand":"Voltage"}]}'
    upd = json.dumps(tx_event(db, "Updated", "'MeterValuePeriodic'", 1, [("Power.Active.Import", 11, "kW"), ("SoC", 52.37, "Percent")]))
    sta = json.dumps(tx_event(db, "Started", "'CablePluggedIn'", 0, [("SoC", 50, "Percent")], id_token="TWIN-abcdef12"))
    got = db.json("SELECT json_build_array("
                  f"ottoq.ottoq_ocpp_meter_soc('MeterValues', '{mv16}'), ottoq.ottoq_ocpp_meter_soc('MeterValues', '{other}'), "
                  f"ottoq.ottoq_ocpp_meter_soc('TransactionEvent', '{upd}'), ottoq.ottoq_ocpp_meter_soc('TransactionEvent', '{sta}'), "
                  "ottoq.ottoq_ocpp_meter_soc('TransactionEvent', '{\"eventType\":\"Updated\",\"meterValue\":[{\"sampledValue\":{\"value\":1}}]}'))")
    # the 1.6 row exactly as the old test read it; the 2.0.1 Updated by measurand; never Started; a malformed row is no
    # reading and no error
    assert got == [52.37, None, 52.37, None, None]


def test_a_sessions_seq_no_counts_its_own_events(db):
    sid = "aaaaaaaa-0000-0000-0000-00000000000a"
    other = "bbbbbbbb-0000-0000-0000-00000000000b"
    assert db.val(f"SELECT twin.ottoq_ocpp201_next_seq('{sid}')") == "0"
    db.run(f"INSERT INTO ottoq_ocpp_messages (ocpp_session_id, message_type, payload) VALUES "
           f"('{sid}', 'StatusNotification', '{{}}'), ('{sid}', 'TransactionEvent', '{{}}'), "
           f"('{sid}', 'TransactionEvent', '{{}}'), ('{other}', 'TransactionEvent', '{{}}')")
    assert db.val(f"SELECT twin.ottoq_ocpp201_next_seq('{sid}')") == "2"


def test_a_charge_the_helpers_build_is_accepted_by_a_real_back_end_over_a_websocket(db):
    # csms/bridge.py: the twin's rows said by their charger, as a 2.0.1 station, to OTTO-Q's back end on 127.0.0.1
    sys.path.insert(0, os.path.join(ROOT, "csms"))
    from bridge import replay
    started = tx_event(db, "Started", "'CablePluggedIn'", 0, [("Energy.Active.Import.Register", 0, "kWh"), ("SoC", 50, "Percent")],
                       custom="jsonb_build_object('target_soc_pct', 100, 'ambient_temp_c', 22.5)", id_token="TWIN-abcdef12")
    updated = tx_event(db, "Updated", "'MeterValuePeriodic'", 1,
                       [("Power.Active.Import", 11.0412, "kW"), ("SoC", 52.37, "Percent"),
                        ("Energy.Active.Import.Interval", 1.8402, "kWh"), ("Energy.Active.Import.Register", 1.8402, "kWh")],
                       custom="jsonb_build_object('battery_temp_c', 31.4)")
    ended = tx_event(db, "Ended", "(twin.ottoq_ocpp201_ended_reasons('fault.connector_cable')).trigger_reason", 2,
                     [("Energy.Active.Import.Register", 5.52, "kWh"), ("SoC", 56, "Percent")],
                     custom="jsonb_build_object('twin_reason', 'fault.connector_cable', 'duration_seconds', 1800.0)",
                     stopped="(twin.ottoq_ocpp201_ended_reasons('fault.connector_cable')).stopped_reason", spent=1800)
    rows = [{"message_seq": i, "ocpp_identifier": "NASH-L2-08", "direction": "cs_to_csms", "message_type": "TransactionEvent",
             "payload": p} for i, p in enumerate([started, updated, ended], 1)]
    s = asyncio.run(replay(rows))
    assert s["outcomes"] == {"accepted": 3}, s
    assert (s["transactions"], s["transactions_ended"], s["transactions_seq_in_order"], s["transactions_seq_from_zero"],
            s["transactions_opened_by_started"]) == (1, 1, 1, 1, 1)
