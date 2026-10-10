"""The charger back end and a simulated station, speaking OCPP 2.0.1 over a real WebSocket on localhost.

Runs in CI's pytest step: no database, no network beyond 127.0.0.1. Every frame is checked against the OCPP 2.0.1 JSON
schemas by the ``ocpp`` library on both sides, so a message that is not valid 2.0.1 fails the test where it is sent.
"""
import asyncio
import datetime as dt
import json
import os
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from csms_server import CSMS, charge_plan_to_profile  # noqa: E402
from station_sim import open_station  # noqa: E402

ROOT = os.path.dirname(HERE)
PLAN = json.load(open(os.path.join(ROOT, "contract", "examples", "valid", "directive.charge.plan.json")))["data"]
T0 = dt.datetime(2026, 10, 9, 14, 27, tzinfo=dt.timezone.utc)  # the plan's start_schedule
OCPP16_ONLY = {"StartTransaction", "StopTransaction", "RemoteStartTransaction", "RemoteStopTransaction"}


def test_a_charge_plan_maps_onto_a_tx_profile_one_to_one():
    prof = charge_plan_to_profile(PLAN, profile_id=7, transaction_id="tx-1")
    assert prof.charging_profile_purpose == "TxProfile" and prof.charging_profile_kind == "Absolute"
    assert prof.transaction_id == "tx-1" and prof.stack_level == 0
    sched = prof.charging_schedule[0]
    assert sched.start_schedule == PLAN["charging_schedule"]["start_schedule"]
    assert sched.charging_rate_unit == "W"
    assert [(p.start_period, p.limit) for p in sched.charging_schedule_period] == [(0, 150000.0), (1500, 50000.0)]


def test_a_schedule_that_does_not_start_at_zero_or_goes_backwards_is_refused():
    bad = json.loads(json.dumps(PLAN))
    bad["charging_schedule"]["periods"][0]["start_period_s"] = 60
    with pytest.raises(ValueError):
        charge_plan_to_profile(bad, profile_id=1, transaction_id=None)
    bad = json.loads(json.dumps(PLAN))
    bad["charging_schedule"]["periods"][1]["start_period_s"] = 0
    with pytest.raises(ValueError):
        charge_plan_to_profile(bad, profile_id=1, transaction_id=None)


async def _session():
    csms = CSMS()
    port = await csms.start("127.0.0.1", 0)
    url = f"ws://127.0.0.1:{port}"
    dc, dc_loop = await open_station(url, "NASH-DC-04", model="sim-dcfc", vendor="OTTOYARD twin", max_w=350000)
    l2, l2_loop = await open_station(url, "NASH-L2-11", model="sim-l2", vendor="OTTOYARD twin", max_w=19200)
    try:
        assert await dc.boot(T0) == "Accepted" and await l2.boot(T0) == "Accepted"
        await dc.heartbeat()
        await dc.status(T0, 1, "Available")
        await l2.status(T0, 1, "Available")
        # a car that takes up to 250 kW plugs into the fast charger
        await dc.start_transaction(T0, 1, "tx-dc-1", "SIMA-0001", vehicle_max_w=250000)
        for _ in range(50):  # the back end holds the station before it is asked to do anything
            if "NASH-DC-04" in csms.handlers:
                break
            await asyncio.sleep(0.01)
        status = await csms.set_charging_profile("NASH-DC-04", 1, PLAN, "tx-dc-1")
        powers = []
        for minutes in (10, 20, 25, 35, 45):
            powers.append(await dc.meter(T0 + dt.timedelta(minutes=minutes), 1))
        energy = await dc.stop_transaction(T0 + dt.timedelta(minutes=50), 1)
        # the L2 next to it, with no profile, draws its own rating
        await l2.start_transaction(T0, 1, "tx-l2-1", "SIMB-0002", vehicle_max_w=11000)
        l2_power = await l2.meter(T0 + dt.timedelta(minutes=30), 1)
        await l2.stop_transaction(T0 + dt.timedelta(minutes=31), 1)
        return csms, status, powers, energy, l2_power
    finally:
        for task in (dc_loop, l2_loop):
            task.cancel()
        await csms.stop()


def test_a_station_charges_under_the_plan_otto_q_sent_it_in_ocpp_2_0_1():
    csms, status, powers, energy, l2_power = asyncio.run(_session())
    assert status == "Accepted"
    # the profile caps the 350 kW station at 150 kW for 1,500 s, then 50 kW; the car would take 250 kW
    # (each meter reading reports the power since the previous one: 0-10, 10-20, 20-25, 25-35, 35-45 minutes)
    assert powers == [150000, 150000, 150000, 50000, 50000]
    assert round(energy) == round(150000 * 25 / 60 + 50000 * 20 / 60 + 50000 * 5 / 60)
    assert l2_power == 11000  # the L2's 19.2 kW is above what the car takes
    sent = csms.message_types()
    actions = {a for _, a in sent}
    assert {"BootNotification", "Heartbeat", "StatusNotification", "Authorize", "TransactionEvent",
            "SetChargingProfile"} <= actions
    assert not (actions & OCPP16_ONLY), "an OCPP 1.6-only message name"
    assert ("csms_to_cs", "SetChargingProfile") in sent
    # each transaction's events are Started, Updated..., Ended with seqNo 0, 1, 2, ...
    st = csms.stations["NASH-DC-04"]
    assert st.transactions["tx-dc-1"]["event_type"] == "Ended" and st.last_seq_no["tx-dc-1"] == 6
    assert st.transactions["tx-dc-1"]["events"] == 7
    assert csms.stations["NASH-L2-11"].transactions["tx-l2-1"]["event_type"] == "Ended"
