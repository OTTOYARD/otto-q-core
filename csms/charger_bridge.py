"""The bridge: the twin's chargers as real OCPP 2.0.1 stations on a WebSocket to OTTO-Q's charger back end.

Step 5 of the twin data contract review, its second part (csms/README.md, "What comes next"). Since 0694 the twin's
charge steps write what a 2.0.1 station sends into ``public.ottoq_ocpp_messages``: ``Authorize`` with the token only,
``StatusNotification``, and each charge as one transaction told by ``TransactionEvent`` Started, Updated and Ended.
The bridge takes those rows in ``message_seq`` order and has each charger say them, as itself, to a real back end
(``csms_server.CSMS``) over a real WebSocket: one station per charger, connected at ``/<ocpp_identifier>`` with the
``ocpp2.0.1`` subprotocol, booted once with the charger's own vendor, model, serial number and firmware.

A row is sent exactly as the twin wrote it. The ``ocpp`` library's own ``call()`` rebuilds a payload from snake_case
and would rename the twin's ``customData`` keys on the way out, so the bridge sends the frame itself, validated against
the 2.0.1 schemas before it leaves and the answer validated when it comes back, as ``call()`` does. What the back end
received is therefore byte for byte what the twin wrote, which is the point: the log is something a real back end
accepted, frame by frame, or the frame that it did not accept is named.

Every row ends in one of three outcomes, never silently:

- ``accepted``: the back end answered with a result that is valid 2.0.1;
- ``not_2_0_1``: the row is not a valid 2.0.1 request (a 1.6 name such as ``StartTransaction``, or a malformed
  payload), so the station refused to send it and the back end never saw it;
- ``csms_error``: the back end answered with a CALLERROR (an action it does not implement, a payload it rejects), or
  with a result that is not valid 2.0.1.

Rows the back end would send to a station (``csms_to_cs``) are not the station's to say and are counted, not sent.

Time is the twin's: nothing here reads a clock to decide what to say, so the same rows produce the same frames.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import sys
from collections import Counter
from dataclasses import dataclass, field
from typing import Any, Iterable

from ocpp.exceptions import OCPPError
from ocpp.messages import Call, MessageType, validate_payload
from ocpp.v201 import ChargePoint, call, datatypes, enums
from websockets.asyncio.client import connect

SUBPROTOCOL = "ocpp2.0.1"
OUTCOMES = ("accepted", "not_2_0_1", "csms_error")


class NotTwoZeroOne(Exception):
    """The row is not a valid OCPP 2.0.1 request; the station refused to send it."""


class CsmsError(Exception):
    """The back end answered with a CALLERROR, or with a result that is not valid 2.0.1."""


@dataclass(frozen=True)
class StationFacts:
    """A charger as ``public.ottoq_ocpp_chargers`` knows it: what it says in its BootNotification."""
    ocpp_identifier: str
    vendor: str = "OTTOYARD twin"
    model: str = "sim"
    serial_number: str | None = None
    firmware_version: str | None = None


@dataclass(frozen=True)
class TwinFrame:
    """One row of ``public.ottoq_ocpp_messages`` with its charger's identifier."""
    seq: int
    station_id: str
    direction: str
    action: str
    payload: dict[str, Any]

    @classmethod
    def from_row(cls, row: dict[str, Any]) -> "TwinFrame":
        payload = row["payload"]
        return cls(seq=int(row["message_seq"]), station_id=row["ocpp_identifier"], direction=row.get("direction", "cs_to_csms"),
                   action=row["message_type"], payload=json.loads(payload) if isinstance(payload, str) else payload)


@dataclass
class Delivery:
    seq: int
    station_id: str
    action: str
    outcome: str
    response: dict[str, Any] | None = None
    error: str | None = None


class TwinStation(ChargePoint):
    """A twin charger on the wire. It says only what the twin wrote, and boots once as the charger it is."""

    async def send_raw(self, action: str, payload: dict[str, Any]) -> dict[str, Any]:
        """Send ``payload`` as a CALL of ``action`` exactly as given; return the CALLRESULT payload.

        Mirrors ``ChargePoint.call`` (ocpp 2.1.0) without its snake_case round trip: the request is validated against
        the 2.0.1 schema before it is sent, the answer after it arrives, and a CALLERROR is raised as its exception.
        """
        msg = Call(unique_id=str(self._unique_id_generator()), action=action, payload=payload)
        try:  # the library raises an OCPPError for a payload the schema refuses and for an action it has none for
            await validate_payload(msg, self._ocpp_version)
        except OCPPError as e:
            raise NotTwoZeroOne(f"{type(e).__name__}: {e}") from e
        async with self._call_lock:
            await self._send(msg.to_json())
            response = await self._get_specific_response(msg.unique_id, self._response_timeout)
        if response.message_type_id == MessageType.CallError:
            raise CsmsError(f"CALLERROR {response.error_code}: {response.error_description}")
        response.action = action
        try:
            await validate_payload(response, self._ocpp_version)
        except OCPPError as e:
            raise CsmsError(f"an answer that is not valid 2.0.1: {type(e).__name__}: {e}") from e
        return response.payload

    async def boot(self, facts: StationFacts) -> str:
        res = await self.call(call.BootNotification(
            charging_station=datatypes.ChargingStationType(
                model=facts.model, vendor_name=facts.vendor, serial_number=facts.serial_number,
                firmware_version=facts.firmware_version),
            reason=enums.BootReasonEnumType.power_up))
        return res.status


@dataclass
class ChargerBridge:
    """Holds one connected, booted station per charger and delivers the twin's rows through them, in order."""
    csms_url: str
    facts: dict[str, StationFacts] = field(default_factory=dict)
    stations: dict[str, TwinStation] = field(default_factory=dict)
    boots: dict[str, str] = field(default_factory=dict)
    _loops: list[asyncio.Task] = field(default_factory=list)

    async def _station(self, station_id: str) -> TwinStation:
        st = self.stations.get(station_id)
        if st is None:
            ws = await connect(f"{self.csms_url.rstrip('/')}/{station_id}", subprotocols=[SUBPROTOCOL])
            st = TwinStation(station_id, ws)
            self._loops.append(asyncio.create_task(st.start()))
            self.stations[station_id] = st
            self.boots[station_id] = await st.boot(self.facts.get(station_id, StationFacts(station_id)))
        return st

    async def deliver(self, frames: Iterable[TwinFrame]) -> list[Delivery]:
        out: list[Delivery] = []
        for f in sorted(frames, key=lambda x: x.seq):
            if f.direction != "cs_to_csms":
                out.append(Delivery(f.seq, f.station_id, f.action, "not_a_station_frame"))
                continue
            st = await self._station(f.station_id)
            try:
                resp = await st.send_raw(f.action, f.payload)
                out.append(Delivery(f.seq, f.station_id, f.action, "accepted", response=resp))
            except NotTwoZeroOne as e:
                out.append(Delivery(f.seq, f.station_id, f.action, "not_2_0_1", error=str(e)))
            except CsmsError as e:
                out.append(Delivery(f.seq, f.station_id, f.action, "csms_error", error=str(e)))
        return out

    async def close(self) -> None:
        for st in self.stations.values():
            await st._connection.close()
        for t in self._loops:
            t.cancel()
        await asyncio.gather(*self._loops, return_exceptions=True)


def summarize(deliveries: list[Delivery], csms: Any | None = None) -> dict[str, Any]:
    """What a replay found: outcomes by action, and every transaction as the back end saw it."""
    by = Counter((d.action, d.outcome) for d in deliveries)
    s: dict[str, Any] = {
        "frames": len(deliveries),
        "outcomes": dict(Counter(d.outcome for d in deliveries)),
        "by_action": {f"{a}:{o}": n for (a, o), n in sorted(by.items())},
        "first_refusals": [{"seq": d.seq, "station": d.station_id, "action": d.action, "outcome": d.outcome,
                            "error": (d.error or "")[:300]} for d in deliveries if d.outcome != "accepted"][:10],
    }
    if csms is not None:
        txs = [(sid, tx_id, tx) for sid, st in csms.stations.items() for tx_id, tx in st.transactions.items()]
        s["transactions"] = len(txs)
        s["transactions_ended"] = sum(1 for _, _, tx in txs if tx.get("event_type") == "Ended")
        s["transactions_seq_in_order"] = sum(1 for _, _, tx in txs if tx.get("seq_nos") == sorted(set(tx.get("seq_nos", []))))
        s["transactions_seq_from_zero"] = sum(1 for _, _, tx in txs if (tx.get("seq_nos") or [None])[0] == 0)
        s["transactions_opened_by_started"] = sum(1 for _, _, tx in txs if tx.get("first_event_type") == "Started")
    return s


async def replay(rows: list[dict[str, Any]], facts: dict[str, StationFacts] | None = None,
                 csms_url: str | None = None) -> dict[str, Any]:
    """Deliver ``rows`` through a back end: the one at ``csms_url``, or a fresh one in this process on 127.0.0.1."""
    csms = None
    if csms_url is None:
        from csms_server import CSMS
        csms = CSMS()
        csms_url = f"ws://127.0.0.1:{await csms.start('127.0.0.1', 0)}"
    bridge = ChargerBridge(csms_url, facts=facts or {})
    try:
        deliveries = await bridge.deliver(TwinFrame.from_row(r) for r in rows)
        for _ in range(100):  # the back end records a frame as it routes it; let the last answers settle
            await asyncio.sleep(0)
        return summarize(deliveries, csms) | {"stations": len(bridge.stations),
                                              "boots": dict(Counter(bridge.boots.values()))}
    finally:
        await bridge.close()
        if csms is not None:
            await csms.stop()


def main(argv: list[str] | None = None) -> int:  # pragma: no cover - the command line
    ap = argparse.ArgumentParser(description="Replay the twin's charger rows through OTTO-Q's OCPP 2.0.1 back end.")
    ap.add_argument("rows", help="JSON Lines: message_seq, ocpp_identifier, direction, message_type, payload per line")
    ap.add_argument("--csms", help="ws://host:port of a running back end; default: one in this process on 127.0.0.1")
    ap.add_argument("--chargers", help="JSON Lines of ottoq_ocpp_chargers rows (ocpp_identifier, vendor, model, ...)")
    a = ap.parse_args(argv)
    rows = [json.loads(line) for line in open(a.rows, encoding="utf-8") if line.strip()]
    facts = {}
    if a.chargers:
        for line in open(a.chargers, encoding="utf-8"):
            if line.strip():
                c = json.loads(line)
                facts[c["ocpp_identifier"]] = StationFacts(c["ocpp_identifier"], c.get("vendor") or "OTTOYARD twin",
                                                           c.get("model") or "sim", c.get("serial_number"),
                                                           c.get("firmware_version"))
    print(json.dumps(asyncio.run(replay(rows, facts, a.csms)), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
