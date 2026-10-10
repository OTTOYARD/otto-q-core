# OTTO-Q's charger back end (OCPP 2.0.1)

**Status:** prototype, 2026-10-10. Step 5 of the twin data contract review: *"Real OCPP. An open-source charger back
end and simulated charge points speaking OCPP 2.0.1 (TransactionEvent, SetChargingProfile). Retires the 1.6 message
names."* Chase, 2026-10-09: host it on AWS.

| File | What it is |
|---|---|
| `csms_server.py` | the back end (a CSMS): takes stations at `ws://host:port/<station id>`, subprotocol `ocpp2.0.1`; answers BootNotification, Heartbeat, StatusNotification, Authorize, MeterValues and TransactionEvent; sends OTTO-Q's charge plan to a station as `SetChargingProfile`; keeps every frame both ways |
| `station_sim.py` | a simulated charging station: boots, reports its connector, runs a transaction as TransactionEvent Started, Updated and Ended, and draws the lower of its rating, the car's limit and the profile's limit for the period in force |
| `test_csms.py` | the battery: a back end and two stations over a real WebSocket on 127.0.0.1; runs in CI's pytest step |

Both sides use [`ocpp`](https://github.com/mobilityhouse/ocpp) 2.1.0 (MIT, released 2025-07-16), which validates
every frame against the OCPP 2.0.1 JSON schemas in both directions, and [`websockets`](https://pypi.org/project/websockets/)
15.0.1 (BSD-3-Clause, released 2025-03-05). Both are pinned in `requirements.txt`.

## Why: the twin's charger log speaks OCPP 1.6 under a 2.0.1 label

`public.ottoq_ocpp_messages` is written by `twin.ottoq_sim_emit_ocpp`, called from the twin's start, advance and
stop charge-session steps. Read 2026-10-10: every row says `ocpp_version = '2.0.1'`, and the types are
`MeterValues` (1,216,127), `StatusNotification` (70,111), `Authorize` (37,420), **`StartTransaction` (37,420)** and
**`StopTransaction` (32,691)**. The last two are OCPP 1.6 messages; 2.0.1 has no such actions. A charging session in
2.0.1 is one transaction told as `TransactionEvent` with `eventType` Started, Updated and Ended, a `seqNo` that counts
up from 0, and the meter values inside it. A charge-point operator reading that log would see a 1.6 back end.

## The mapping a charge plan takes (contract rule 7)

`directive.charge.plan.charging_schedule` becomes a `ChargingProfile` with purpose `TxProfile` and kind `Absolute`:
`start_schedule` to `startSchedule`, `charging_rate_unit` to `chargingRateUnit`, `periods[].start_period_s` to
`chargingSchedulePeriod[].startPeriod`, `limit` to `limit`, `number_phases` to `numberPhases`
(`charge_plan_to_profile`). The test sends the contract's own example plan (150 kW for 1,500 s, then 50 kW) to a
350 kW station charging a car that takes 250 kW, and the station draws 150 kW, then 50 kW. Charging is controlled only
at the charger; OTTO-Q never commands a car.

## What comes next, in order

1. **Retire the 1.6 names in the twin's log.** Change `twin.ottoq_sim_emit_ocpp`'s three callers to write what a
   2.0.1 station sends: `TransactionEvent` Started (with the `idToken`), Updated (with the meter values; it replaces
   the in-transaction `MeterValues`) and Ended (with `stoppedReason`), each with its `seqNo`, plus the
   `StatusNotification` shape 2.0.1 uses (`connectorStatus`, `evseId`, `connectorId`). A migration with a measured
   pair: it changes rows the twin writes, and readers of `message_type` must be found and moved with it.
2. **The bridge.** A small process beside the back end that drives one simulated station per twin charger (45 at the
   twin depot: 35 L2 of 19.2 kW, 10 DCFC of 350 kW) from the twin's charge sessions, and writes the back end's log
   into `ottoq_ocpp_messages` and OTTO-Q's charge plans out as `SetChargingProfile`. Then the twin's chargers are
   real WebSocket clients and the log is what a real back end recorded, which is the swap test for chargers.
3. **Host it on AWS** beside the intelligence service on `ottoq-intel-2`, deployed the way that service is
   (`ottoq-intelligence/.github/workflows/aws-deploy-ssm.yml`: over SSM, no SSH, no inbound rule). With the simulated
   stations on the same box the back end listens on localhost only. A real charger needs an inbound `wss://` port with
   TLS, and OCPP 2.0.1's security profile 2 or 3 (basic auth over TLS, or client certificates), which pairs with the
   contract's mTLS plan.
