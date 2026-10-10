"""The bridge: the twin's charger rows said by one OCPP 2.0.1 station per charger to the back end, over a real WebSocket.

No database: the rows are written here in the shapes the twin's log holds (read 2026-10-10 from
``public.ottoq_ocpp_messages`` at the twin depot, and 0694's helpers for the 2.0.1 transaction). The SQL test
``tests/test_twin_ocpp201_sql.py`` sends rows built by 0694's own helpers through the same bridge.
"""
import asyncio
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bridge import ChargerBridge, StationFacts, TwinFrame, replay, summarize  # noqa: E402
from csms_server import CSMS  # noqa: E402

TX = "TXN-20260902104500-4ad4c580"
AT = "2026-09-02T11:00:00+00:00"
CUSTOM = {"vendorId": "com.ottoyard.twin", "target_soc_pct": 100, "ambient_temp_c": 10.2}


def sample(measurand, value, unit):
    return {"value": value, "measurand": measurand, "unitOfMeasure": {"unit": unit}}


def tx_event(event, trigger, seq, samples, **extra):
    p = {"eventType": event, "timestamp": AT, "triggerReason": trigger, "seqNo": seq,
         "transactionInfo": {"transactionId": TX, "chargingState": "Idle" if event == "Ended" else "Charging"},
         "evse": {"id": 1, "connectorId": 1}, "meterValue": [{"timestamp": AT, "sampledValue": samples}]}
    p.update(extra)
    return p


def row(seq, station, action, payload, direction="cs_to_csms"):
    return {"message_seq": seq, "ocpp_identifier": station, "direction": direction, "message_type": action,
            "payload": payload}


# one charge on the L2, told as the twin tells it since 0694
CHARGE = [
    row(1, "NASH-L2-08", "StatusNotification", {"evseId": 1, "timestamp": AT, "connectorId": 1, "connectorStatus": "Occupied"}),
    row(2, "NASH-L2-08", "Authorize", {"idToken": {"type": "ISO14443", "idToken": "TWIN-a24e3f67"}}),
    row(3, "NASH-L2-08", "TransactionEvent", tx_event("Started", "CablePluggedIn", 0,
        [sample("Energy.Active.Import.Register", 0, "kWh"), sample("SoC", 80, "Percent")],
        idToken={"idToken": "TWIN-a24e3f67", "type": "ISO14443"}, customData=CUSTOM)),
    row(5, "NASH-L2-08", "TransactionEvent", tx_event("Updated", "MeterValuePeriodic", 1,
        [sample("Power.Active.Import", 19.2, "kW"), sample("SoC", 86.5, "Percent"),
         sample("Energy.Active.Import.Register", 4.8, "kWh")], customData={"vendorId": "com.ottoyard.twin", "battery_temp_c": 27.1})),
    row(7, "NASH-L2-08", "TransactionEvent", tx_event("Ended", "ChargingStateChanged", 2,
        [sample("Energy.Active.Import.Register", 13.1, "kWh"), sample("SoC", 100, "Percent")],
        customData={"vendorId": "com.ottoyard.twin", "twin_reason": "completed"})
        | {"transactionInfo": {"transactionId": TX, "chargingState": "Idle", "stoppedReason": "SOCLimitReached",
                               "timeSpentCharging": 2460}}),
    row(8, "NASH-L2-08", "StatusNotification", {"evseId": 1, "timestamp": AT, "connectorId": 1, "connectorStatus": "Available"}),
]
FACTS = {"NASH-L2-08": StationFacts("NASH-L2-08", "ChargePoint", "CT4000 Family", None, "5.105.1"),
         "NASH-DCFC-04": StationFacts("NASH-DCFC-04", "ABB", "Terra HP 350", None, "1.4.2")}


async def _deliver(rows):
    csms = CSMS()
    url = f"ws://127.0.0.1:{await csms.start('127.0.0.1', 0)}"
    bridge = ChargerBridge(url, facts=FACTS)
    try:
        deliveries = await bridge.deliver(TwinFrame.from_row(r) for r in rows)
        for _ in range(100):
            await asyncio.sleep(0)
        return csms, bridge, deliveries
    finally:
        await bridge.close()
        await csms.stop()


def frames_received(csms, station, action):
    """The payloads the back end received for one station and action, as it logged the raw frames."""
    out = []
    for r in csms.log:
        msg = json.loads(r["frame"])
        if r["station_id"] == station and r["direction"] == "cs_to_csms" and msg[0] == 2 and msg[2] == action:
            out.append(msg[3])
    return out


def test_a_twin_charge_is_said_by_its_charger_and_the_back_end_receives_it_unaltered():
    csms, bridge, deliveries = asyncio.run(_deliver(CHARGE))
    assert [d.outcome for d in deliveries] == ["accepted"] * len(CHARGE)
    # the charger boots once, as itself
    boot = frames_received(csms, "NASH-L2-08", "BootNotification")
    assert boot == [{"chargingStation": {"model": "CT4000 Family", "vendorName": "ChargePoint", "firmwareVersion": "5.105.1"},
                     "reason": "PowerUp"}]
    # every row arrives exactly as the twin wrote it: customData keys are not renamed on the way
    assert frames_received(csms, "NASH-L2-08", "TransactionEvent") == [r["payload"] for r in CHARGE if r["message_type"] == "TransactionEvent"]
    tx = csms.stations["NASH-L2-08"].transactions[TX]
    assert (tx["first_event_type"], tx["event_type"], tx["seq_nos"]) == ("Started", "Ended", [0, 1, 2])
    assert tx["stopped_reason"] == "SOCLimitReached" and tx["energy_wh"] == 13.1
    s = summarize(deliveries, csms)
    assert s["outcomes"] == {"accepted": 6}
    assert (s["transactions"], s["transactions_ended"], s["transactions_seq_in_order"], s["transactions_seq_from_zero"],
            s["transactions_opened_by_started"]) == (1, 1, 1, 1, 1)


def test_what_is_not_2_0_1_is_refused_by_the_station_and_never_reaches_the_back_end():
    legacy = [  # the twin's log before 0694, read 2026-10-10
        row(11, "NASH-L2-08", "Authorize", {"idToken": {"type": "ISO14443", "idToken": "TWIN-a24e3f67"}, "timestamp": AT}),
        row(12, "NASH-L2-08", "StartTransaction", {"idTag": "TWIN-a24e3f67", "timestamp": AT, "meterStart": 0, "connectorId": 1}),
        row(13, "NASH-DCFC-04", "MeterValues", {"timestamp": AT, "connectorId": 1, "transactionId": TX, "sampledValue": [
            {"unit": "Celsius", "value": 27.1, "location": "battery", "measurand": "Temperature"}]}),
        row(14, "NASH-DCFC-04", "StatusNotification", {"evseId": 1, "timestamp": AT, "connectorId": 1, "connectorStatus": "Available"}),
    ]
    csms, bridge, deliveries = asyncio.run(_deliver(legacy))
    assert [(d.action, d.outcome) for d in deliveries] == [
        ("Authorize", "not_2_0_1"), ("StartTransaction", "not_2_0_1"), ("MeterValues", "not_2_0_1"),
        ("StatusNotification", "accepted")]
    received = {json.loads(r["frame"])[2] for r in csms.log if r["direction"] == "cs_to_csms" and json.loads(r["frame"])[0] == 2}
    assert received == {"BootNotification", "StatusNotification"}  # the boots, and the one 2.0.1 row
    assert all(d.error for d in deliveries if d.outcome != "accepted")


def test_a_valid_request_the_back_end_does_not_handle_is_its_error_and_a_back_end_frame_is_not_sent():
    rows = [row(21, "NASH-DCFC-04", "FirmwareStatusNotification", {"status": "Idle"}),
            row(22, "NASH-DCFC-04", "SetChargingProfile", {"evseId": 1}, direction="csms_to_cs")]
    csms, bridge, deliveries = asyncio.run(_deliver(rows))
    assert [(d.action, d.outcome) for d in deliveries] == [
        ("FirmwareStatusNotification", "csms_error"), ("SetChargingProfile", "not_a_station_frame")]
    assert "CALLERROR" in deliveries[0].error


def test_replay_runs_its_own_back_end_and_reports_by_action():
    s = asyncio.run(replay(CHARGE, FACTS))
    assert s["frames"] == 6 and s["outcomes"] == {"accepted": 6} and s["stations"] == 1 and s["boots"] == {"Accepted": 1}
    assert s["by_action"] == {"Authorize:accepted": 1, "StatusNotification:accepted": 2, "TransactionEvent:accepted": 3}
