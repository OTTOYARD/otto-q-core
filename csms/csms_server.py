"""OTTO-Q's charger back end (a CSMS) speaking OCPP 2.0.1 over WebSocket.

Step 5 of the twin data contract review: the twin's chargers speak real OCPP 2.0.1 to a real back end instead of
being rows in a table. This module is that back end. It accepts any number of charging stations at
``ws://host:port/<station id>`` (subprotocol ``ocpp2.0.1``), answers what a station sends (BootNotification,
Heartbeat, StatusNotification, Authorize, TransactionEvent, MeterValues), and pushes a charge plan to a station as a
``SetChargingProfile`` built from OTTO-Q's ``directive.charge.plan`` (contract/README.md, rule 7).

Every message both ways is kept in ``CSMS.log`` in the shape of ``public.ottoq_ocpp_messages`` (direction, message
type, payload), so a bridge can write it there. Messages are validated against the OCPP 2.0.1 JSON schemas by the
``ocpp`` library (mobilityhouse/ocpp, MIT) in both directions; a malformed one is refused, not stored.

OTTO-Q never commands a vehicle (contract rule 7): charging is controlled only here, at the charger, and power reaches
a site only as a forward schedule.
"""
from __future__ import annotations

import asyncio
import datetime as dt
import logging
from collections import deque
from dataclasses import dataclass, field
from typing import Any

from ocpp.routing import on
from ocpp.v201 import ChargePoint, call, call_result, datatypes, enums
from websockets.asyncio.server import ServerConnection, serve

SUBPROTOCOL = "ocpp2.0.1"
HEARTBEAT_INTERVAL_S = 30
log = logging.getLogger("ottoq.csms")


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def charge_plan_to_profile(plan: dict[str, Any], *, profile_id: int, transaction_id: str | None,
                           stack_level: int = 0) -> datatypes.ChargingProfileType:
    """Map a contract ``directive.charge.plan`` onto an OCPP 2.0.1 ``ChargingProfile``, one to one (rule 7).

    ``charging_schedule.start_schedule`` -> ``startSchedule``, ``charging_rate_unit`` -> ``chargingRateUnit``,
    ``periods[].start_period_s`` -> ``chargingSchedulePeriod[].startPeriod``, ``limit`` -> ``limit``,
    ``number_phases`` -> ``numberPhases``; purpose ``TxProfile``, kind ``Absolute``.
    """
    sched = plan["charging_schedule"]
    periods = [
        datatypes.ChargingSchedulePeriodType(
            start_period=int(p["start_period_s"]),
            limit=float(p["limit"]),
            number_phases=int(p["number_phases"]) if p.get("number_phases") is not None else None,
        )
        for p in sched["periods"]
    ]
    if not periods or periods[0].start_period != 0:
        raise ValueError("a charging schedule starts with a period at 0 s")
    if any(b.start_period <= a.start_period for a, b in zip(periods, periods[1:])):
        raise ValueError("schedule periods must start in increasing order")
    return datatypes.ChargingProfileType(
        id=profile_id,
        stack_level=stack_level,
        charging_profile_purpose=enums.ChargingProfilePurposeEnumType.tx_profile,
        charging_profile_kind=enums.ChargingProfileKindEnumType.absolute,
        transaction_id=transaction_id,
        charging_schedule=[
            datatypes.ChargingScheduleType(
                id=profile_id,
                start_schedule=sched["start_schedule"],
                charging_rate_unit=enums.ChargingRateUnitEnumType(sched["charging_rate_unit"]),
                charging_schedule_period=periods,
            )
        ],
    )


@dataclass
class StationState:
    """What the back end knows about one station, from the station's own messages."""
    station_id: str
    boot: dict[str, Any] | None = None
    connectors: dict[tuple[int, int], str] = field(default_factory=dict)   # (evse, connector) -> status
    transactions: dict[str, dict[str, Any]] = field(default_factory=dict)  # transaction id -> latest state
    last_seq_no: dict[str, int] = field(default_factory=dict)              # transaction id -> last seqNo seen


class StationHandler(ChargePoint):
    """One connected station, as the back end sees it."""

    def __init__(self, station_id: str, connection: ServerConnection, csms: "CSMS"):
        super().__init__(station_id, connection)
        self.csms = csms
        self.state = csms.stations.setdefault(station_id, StationState(station_id))

    async def route_message(self, raw_msg):  # keep every inbound frame, as the bridge will store it
        self.csms._record(self.id, "cs_to_csms", raw_msg)
        return await super().route_message(raw_msg)

    async def _send(self, message):  # and every outbound one
        self.csms._record(self.id, "csms_to_cs", message)
        await super()._send(message)

    @on(enums.Action.boot_notification)
    async def on_boot_notification(self, charging_station, reason, **kwargs):
        self.state.boot = {"charging_station": charging_station, "reason": reason}
        return call_result.BootNotification(current_time=_now_iso(), interval=HEARTBEAT_INTERVAL_S,
                                            status=enums.RegistrationStatusEnumType.accepted)

    @on(enums.Action.heartbeat)
    async def on_heartbeat(self, **kwargs):
        return call_result.Heartbeat(current_time=_now_iso())

    @on(enums.Action.status_notification)
    async def on_status_notification(self, timestamp, connector_status, evse_id, connector_id, **kwargs):
        self.state.connectors[(evse_id, connector_id)] = connector_status
        return call_result.StatusNotification()

    @on(enums.Action.authorize)
    async def on_authorize(self, id_token, **kwargs):
        return call_result.Authorize(
            id_token_info=datatypes.IdTokenInfoType(status=enums.AuthorizationStatusEnumType.accepted))

    @on(enums.Action.meter_values)
    async def on_meter_values(self, evse_id, meter_value, **kwargs):
        return call_result.MeterValues()

    @on(enums.Action.transaction_event)
    async def on_transaction_event(self, event_type, timestamp, trigger_reason, seq_no, transaction_info, **kwargs):
        tx_id = transaction_info["transaction_id"]
        last = self.state.last_seq_no.get(tx_id)
        if last is not None and seq_no <= last:
            log.warning("station %s transaction %s: seqNo %s after %s", self.id, tx_id, seq_no, last)
        self.state.last_seq_no[tx_id] = seq_no
        if tx_id not in self.state.transactions and len(self.state.transactions) >= self.csms.keep_transactions:
            self.state.transactions.pop(next(iter(self.state.transactions)))   # the oldest goes
            self.state.last_seq_no = {k: v for k, v in self.state.last_seq_no.items() if k in self.state.transactions}
        tx = self.state.transactions.setdefault(tx_id, {"events": 0, "seq_nos": [], "first_event_type": event_type})
        tx.update(event_type=event_type, trigger_reason=trigger_reason, timestamp=timestamp,
                  charging_state=transaction_info.get("charging_state"),
                  stopped_reason=transaction_info.get("stopped_reason"))
        tx["events"] += 1
        tx["seq_nos"].append(seq_no)
        for mv in kwargs.get("meter_value") or []:
            for sv in mv.get("sampled_value", []):
                if sv.get("measurand", "Energy.Active.Import.Register") == "Energy.Active.Import.Register":
                    tx["energy_wh"] = sv["value"]
                elif sv.get("measurand") == "Power.Active.Import":
                    tx["power_w"] = sv["value"]
        if event_type == enums.TransactionEventEnumType.started:
            return call_result.TransactionEvent(
                id_token_info=datatypes.IdTokenInfoType(status=enums.AuthorizationStatusEnumType.accepted))
        return call_result.TransactionEvent()


class CSMS:
    """The back end: the stations it holds, and everything it was told and said."""

    def __init__(self, log_frames: int | None = None, keep_transactions: int = 5000):
        # a long-running back end keeps the last log_frames frames and keep_transactions transactions per station; the
        # bridge reports every frame's outcome upstream, so nothing is lost by forgetting here (None keeps all, for tests)
        self.stations: dict[str, StationState] = {}
        self.handlers: dict[str, StationHandler] = {}
        self.log: deque[dict[str, Any]] = deque(maxlen=log_frames)
        self.keep_transactions = keep_transactions
        self._next_profile_id = 1
        self._server = None

    def _record(self, station_id: str, direction: str, raw: Any) -> None:
        self.log.append({"station_id": station_id, "direction": direction, "frame": raw if isinstance(raw, str) else str(raw),
                         "at": _now_iso()})

    async def _on_connect(self, connection: ServerConnection) -> None:
        station_id = (connection.request.path or "/").strip("/")
        if not station_id or connection.subprotocol != SUBPROTOCOL:
            await connection.close(code=1002, reason="a station connects at /<station id> speaking ocpp2.0.1")
            return
        handler = StationHandler(station_id, connection, self)
        self.handlers[station_id] = handler
        try:
            await handler.start()
        except Exception:  # the station hung up; what it said is kept
            pass
        finally:
            if self.handlers.get(station_id) is handler:
                del self.handlers[station_id]

    async def start(self, host: str = "127.0.0.1", port: int = 0) -> int:
        self._server = await serve(self._on_connect, host, port, subprotocols=[SUBPROTOCOL])
        return self._server.sockets[0].getsockname()[1]

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()

    async def set_charging_profile(self, station_id: str, evse_id: int, plan: dict[str, Any],
                                   transaction_id: str | None) -> str:
        """Send OTTO-Q's charge plan to a station as a SetChargingProfile; return the station's status."""
        profile = charge_plan_to_profile(plan, profile_id=self._next_profile_id, transaction_id=transaction_id)
        self._next_profile_id += 1
        result = await self.handlers[station_id].call(call.SetChargingProfile(evse_id=evse_id, charging_profile=profile))
        return result.status

    def message_types(self) -> list[tuple[str, str]]:
        """(direction, action) for every CALL frame in the log, the shape ottoq_ocpp_messages keeps."""
        import json
        out = []
        for row in self.log:
            msg = json.loads(row["frame"])
            if msg[0] == 2:  # CALL
                out.append((row["direction"], msg[2]))
        return out


async def main(host: str = "0.0.0.0", port: int = 9000) -> None:  # pragma: no cover - the service entry point
    logging.basicConfig(level=logging.INFO)
    csms = CSMS()
    bound = await csms.start(host, port)
    log.info("OTTO-Q CSMS listening on ws://%s:%s/<station id> (%s)", host, bound, SUBPROTOCOL)
    await asyncio.Future()


if __name__ == "__main__":  # pragma: no cover
    asyncio.run(main())
