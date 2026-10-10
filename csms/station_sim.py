"""A simulated OCPP 2.0.1 charging station, for the twin's chargers.

It connects to a back end at ``ws://host:port/<station id>`` (subprotocol ``ocpp2.0.1``), boots, reports its
connectors, runs a transaction as ``TransactionEvent`` Started, Updated and Ended (the OCPP 1.6 names
``StartTransaction``, ``StopTransaction`` and in-transaction ``MeterValues`` do not exist in 2.0.1), and honours a
``SetChargingProfile``: it draws the lower of its own rating, the car's limit and the profile's limit for the
current period.

Time is the caller's: every method takes the moment it happens at, so a twin can drive it on its own sim clock and two
runs on the same inputs send the same messages.
"""
from __future__ import annotations

import datetime as dt
from dataclasses import dataclass
from typing import Any

from ocpp.routing import on
from ocpp.v201 import ChargePoint, call, call_result, datatypes, enums
from websockets.asyncio.client import connect

SUBPROTOCOL = "ocpp2.0.1"


def iso(t: dt.datetime) -> str:
    return t.astimezone(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _parse(ts: str) -> dt.datetime:
    return dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))


@dataclass
class Transaction:
    transaction_id: str
    evse_id: int
    started_at: dt.datetime
    vehicle_max_w: float
    seq_no: int = 0
    energy_wh: float = 0.0
    power_w: float = 0.0
    metered_to: dt.datetime | None = None


class SimStation(ChargePoint):
    """One simulated station. ``max_w`` is its rating per EVSE."""

    def __init__(self, station_id: str, connection, *, model: str, vendor: str, max_w: float):
        super().__init__(station_id, connection)
        self.model, self.vendor, self.max_w = model, vendor, max_w
        self.profiles: dict[int, dict[str, Any]] = {}   # evse id -> the TxProfile in force
        self.tx: dict[int, Transaction] = {}             # evse id -> the transaction on it

    # ── what the back end asks ──
    @on(enums.Action.set_charging_profile)
    async def on_set_charging_profile(self, evse_id, charging_profile, **kwargs):
        if charging_profile.get("charging_profile_purpose") != enums.ChargingProfilePurposeEnumType.tx_profile:
            return call_result.SetChargingProfile(status=enums.ChargingProfileStatusEnumType.rejected)
        tx = self.tx.get(evse_id)
        if tx is None or charging_profile.get("transaction_id") not in (None, tx.transaction_id):
            return call_result.SetChargingProfile(status=enums.ChargingProfileStatusEnumType.rejected)
        self.profiles[evse_id] = charging_profile
        return call_result.SetChargingProfile(status=enums.ChargingProfileStatusEnumType.accepted)

    # ── what the station says ──
    async def boot(self, at: dt.datetime) -> str:
        res = await self.call(call.BootNotification(
            charging_station=datatypes.ChargingStationType(model=self.model, vendor_name=self.vendor),
            reason=enums.BootReasonEnumType.power_up))
        return res.status

    async def heartbeat(self) -> str:
        return (await self.call(call.Heartbeat())).current_time

    async def status(self, at: dt.datetime, evse_id: int, status: str) -> None:
        await self.call(call.StatusNotification(timestamp=iso(at), connector_status=enums.ConnectorStatusEnumType(status),
                                                evse_id=evse_id, connector_id=1))

    def limit_w(self, evse_id: int, at: dt.datetime) -> float:
        """The profile's limit for the period in force at ``at`` (W), or the rating with no profile."""
        prof = self.profiles.get(evse_id)
        if not prof:
            return self.max_w
        sched = prof["charging_schedule"][0]
        elapsed = (at - _parse(sched["start_schedule"])).total_seconds()
        if elapsed < 0:
            return self.max_w
        limit = self.max_w
        for p in sched["charging_schedule_period"]:
            if p["start_period"] <= elapsed:
                limit = p["limit"] if sched["charging_rate_unit"] == "W" else p["limit"] * 230.0 * p.get("number_phases", 3)
        return limit

    async def start_transaction(self, at: dt.datetime, evse_id: int, transaction_id: str, id_token: str,
                                vehicle_max_w: float) -> None:
        await self.status(at, evse_id, "Occupied")
        await self.call(call.Authorize(id_token=datatypes.IdTokenType(id_token=id_token, type=enums.IdTokenEnumType.central)))
        tx = Transaction(transaction_id, evse_id, at, vehicle_max_w, metered_to=at)
        self.tx[evse_id] = tx
        await self._event(tx, at, enums.TransactionEventEnumType.started, enums.TriggerReasonEnumType.cable_plugged_in,
                          id_token=id_token)

    async def meter(self, at: dt.datetime, evse_id: int) -> float:
        """Advance the meter to ``at`` at the power in force since the last reading; send an Updated event."""
        tx = self.tx[evse_id]
        tx.power_w = min(self.max_w, tx.vehicle_max_w, self.limit_w(evse_id, tx.metered_to))
        tx.energy_wh += tx.power_w * (at - tx.metered_to).total_seconds() / 3600.0
        tx.metered_to = at
        await self._event(tx, at, enums.TransactionEventEnumType.updated, enums.TriggerReasonEnumType.meter_value_periodic)
        return tx.power_w

    async def stop_transaction(self, at: dt.datetime, evse_id: int, reason: str = "EVDisconnected") -> float:
        tx = self.tx.pop(evse_id)
        # the Ended event carries the register at the moment the car left, not at the last periodic reading
        tx.power_w = min(self.max_w, tx.vehicle_max_w, self.limit_w(evse_id, tx.metered_to))
        tx.energy_wh += tx.power_w * (at - tx.metered_to).total_seconds() / 3600.0
        tx.metered_to = at
        await self._event(tx, at, enums.TransactionEventEnumType.ended, enums.TriggerReasonEnumType.ev_communication_lost
                          if reason == "EVDisconnected" else enums.TriggerReasonEnumType.stop_authorized,
                          stopped_reason=reason)
        self.profiles.pop(evse_id, None)
        await self.status(at, evse_id, "Available")
        return tx.energy_wh

    async def _event(self, tx: Transaction, at: dt.datetime, event_type, trigger, *, id_token: str | None = None,
                     stopped_reason: str | None = None) -> None:
        info = datatypes.TransactionType(
            transaction_id=tx.transaction_id,
            charging_state=enums.ChargingStateEnumType.charging if event_type != enums.TransactionEventEnumType.ended
            else enums.ChargingStateEnumType.idle,
            stopped_reason=enums.ReasonEnumType(stopped_reason) if stopped_reason else None)
        meter = [datatypes.MeterValueType(timestamp=iso(at), sampled_value=[
            datatypes.SampledValueType(value=round(tx.energy_wh, 1), measurand=enums.MeasurandEnumType.energy_active_import_register),
            datatypes.SampledValueType(value=round(tx.power_w, 1), measurand=enums.MeasurandEnumType.power_active_import),
        ])]
        await self.call(call.TransactionEvent(
            event_type=event_type, timestamp=iso(at), trigger_reason=trigger, seq_no=tx.seq_no, transaction_info=info,
            meter_value=meter, evse=datatypes.EVSEType(id=tx.evse_id, connector_id=1),
            id_token=datatypes.IdTokenType(id_token=id_token, type=enums.IdTokenEnumType.central) if id_token else None))
        tx.seq_no += 1


async def open_station(url: str, station_id: str, **kw) -> tuple[SimStation, Any]:
    """Connect a station to a back end and start its receive loop; returns (station, the loop's task)."""
    import asyncio
    ws = await connect(f"{url.rstrip('/')}/{station_id}", subprotocols=[SUBPROTOCOL])
    st = SimStation(station_id, ws, **kw)
    task = asyncio.create_task(st.start())
    return st, task
