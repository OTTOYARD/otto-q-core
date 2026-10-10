"""The live bridge's loop (relay.py) against a fake relay and a real back end on 127.0.0.1: no database, no network."""
import asyncio
import json
import os
import sys
import tempfile

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from csms_server import CSMS  # noqa: E402
from csms_relay import Relay, RelayError, StateFile  # noqa: E402

KEY = "ottow_" + "ef" * 32
AT = "2026-10-10T13:00:00+00:00"
TX = "TXN-20261010130000-0000beef"


def row(seq, action, payload, station="NASH-L2-08"):
    return {"message_seq": seq, "ocpp_identifier": station, "direction": "cs_to_csms", "message_type": action, "payload": payload}


STARTED = {"eventType": "Started", "timestamp": AT, "triggerReason": "CablePluggedIn", "seqNo": 0,
           "transactionInfo": {"transactionId": TX, "chargingState": "Charging"}, "evse": {"id": 1, "connectorId": 1},
           "idToken": {"idToken": "TWIN-0000beef", "type": "ISO14443"},
           "meterValue": [{"timestamp": AT, "sampledValue": [{"value": 0, "measurand": "Energy.Active.Import.Register",
                                                              "unitOfMeasure": {"unit": "kWh"}}]}]}
BATCH = [row(11, "StatusNotification", {"evseId": 1, "timestamp": AT, "connectorId": 1, "connectorStatus": "Occupied"}),
         row(12, "Authorize", {"idToken": {"type": "ISO14443", "idToken": "TWIN-0000beef"}}),
         row(14, "TransactionEvent", STARTED),
         row(15, "StartTransaction", {"idTag": "TWIN-0000beef", "timestamp": AT, "meterStart": 0, "connectorId": 1})]
CHARGERS = [{"ocpp_identifier": "NASH-L2-08", "vendor": "ChargePoint", "model": "CT4000 Family", "firmware_version": "5.105.1"}]


class FakeRelay:
    """The relay's two routes over a list of rows; fails the next report when told to."""

    def __init__(self, rows):
        self.rows, self.reports, self.calls, self.fail_next_report = rows, [], [], False

    def __call__(self, method, url, key, body=None):
        assert key == KEY
        path = url.split("ottoq-csms-relay", 1)[1]
        self.calls.append((method, path))
        if method == "GET":
            q = dict(p.split("=") for p in path.split("?", 1)[1].split("&"))
            after, limit = int(q["after"]), int(q["limit"])
            head = max(r["message_seq"] for r in self.rows) if self.rows else 0
            if after < 0:
                return {"ok": True, "rows": [], "next_after": 10, "more": False, "chargers": CHARGERS}
            page = [r for r in self.rows if r["message_seq"] > after][:limit]
            out = {"ok": True, "rows": page, "next_after": page[-1]["message_seq"] if page else after, "more": len(page) == limit}
            if q.get("chargers") == "true":
                out["chargers"] = CHARGERS
            return out
        if self.fail_next_report:
            self.fail_next_report = False
            raise RelayError(503, {"ok": False})
        self.reports.append(body)
        return {"ok": True, "report_id": len(self.reports)}


async def _run(scenario):
    csms = CSMS()
    url = f"ws://127.0.0.1:{await csms.start('127.0.0.1', 0)}"
    with tempfile.TemporaryDirectory() as d:
        state = StateFile(os.path.join(d, "relay.json"))
        try:
            return await scenario(csms, url, state)
        finally:
            await csms.stop()


def received(csms, action):
    return [json.loads(r["frame"]) for r in csms.log if r["direction"] == "cs_to_csms" and json.loads(r["frame"])[2] == action]


def test_the_first_round_starts_at_the_head_and_the_next_delivers_and_reports():
    async def scenario(csms, url, state):
        fake = FakeRelay(BATCH)
        relay = Relay("https://x/functions/v1/ottoq-csms-relay", KEY, url, state, request=fake)
        first = await relay.round()
        assert first == {"frames": 0, "more": False, "report_id": None} and state.load()["cursor"] == 10
        second = await relay.round()
        await relay.bridge.close()
        return fake, second, state.load(), csms
    fake, second, st, csms = asyncio.run(_run(scenario))
    assert second == {"frames": 4, "more": False, "report_id": 1}
    rep = fake.reports[0]
    assert (rep["from_seq"], rep["to_seq"], rep["frames"]) == (11, 15, 4)
    assert rep["outcomes"] == {"accepted": 3, "not_2_0_1": 1, "csms_error": 0, "not_a_station_frame": 0}
    assert rep["transactions"] == {"transactions": 1, "started": 1, "ended": 0, "seq_in_order": 1}
    assert rep["first_refusals"][0]["action"] == "StartTransaction" and rep["bridge"]["ocpp"]
    assert st == {"cursor": 15, "pending_report": None, "last_report_id": 1}
    # the charger booted once, as itself, and said the three 2.0.1 rows
    boot = received(csms, "BootNotification")
    assert len(boot) == 1 and boot[0][3]["chargingStation"]["vendorName"] == "ChargePoint"
    assert len(received(csms, "TransactionEvent")) == 1 and received(csms, "StartTransaction") == []


def test_a_report_the_relay_did_not_keep_is_sent_again_and_its_frames_are_not():
    async def scenario(csms, url, state):
        fake = FakeRelay(BATCH)
        relay = Relay("https://x/functions/v1/ottoq-csms-relay", KEY, url, state, request=fake)
        await relay.round()
        fake.fail_next_report = True
        with pytest.raises(RelayError):
            await relay.round()
        mid = state.load()
        third = await relay.round()
        await relay.bridge.close()
        return fake, mid, third, state.load(), csms
    fake, mid, third, st, csms = asyncio.run(_run(scenario))
    assert mid["cursor"] == 15 and mid["pending_report"]["frames"] == 4   # the frames are said; the report waits
    assert third == {"frames": 0, "more": False, "report_id": None} and len(fake.reports) == 1
    assert st["pending_report"] is None and st["last_report_id"] == 1
    assert len(received(csms, "TransactionEvent")) == 1   # said once
