# OTTO-Q's charger back end (OCPP 2.0.1)

**Status:** prototype, 2026-10-10. Step 5 of the twin data contract review: *"Real OCPP. An open-source charger back
end and simulated charge points speaking OCPP 2.0.1 (TransactionEvent, SetChargingProfile). Retires the 1.6 message
names."* Chase, 2026-10-09: host it on AWS.

| File | What it is |
|---|---|
| `csms_server.py` | the back end (a CSMS): takes stations at `ws://host:port/<station id>`, subprotocol `ocpp2.0.1`; answers BootNotification, Heartbeat, StatusNotification, Authorize, MeterValues and TransactionEvent; sends OTTO-Q's charge plan to a station as `SetChargingProfile`; keeps every frame both ways |
| `station_sim.py` | a simulated charging station: boots, reports its connector, runs a transaction as TransactionEvent Started, Updated and Ended, and draws the lower of its rating, the car's limit and the profile's limit for the period in force |
| `test_csms.py` | the battery: a back end and two stations over a real WebSocket on 127.0.0.1; runs in CI's pytest step |
| `bridge.py` | the bridge: the twin's charger rows (`ottoq_ocpp_messages`, in `message_seq` order) said by one station per charger, as that charger, to the back end; every row ends `accepted`, `not_2_0_1` (refused by the station, never sent) or `csms_error` (a CALLERROR or an answer that is not 2.0.1) |
| `test_bridge.py` | the bridge's battery, in CI's pytest step; `tests/test_twin_ocpp201_sql.py` also sends a charge built by 0694's own SQL helpers through it |

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

1. **Retire the 1.6 names in the twin's log (G412). Written as pending migration 0694.** The twin's start, advance and
   stop write what a 2.0.1 station sends: `Authorize` with the token only, and `TransactionEvent` Started (with the
   `idToken`), Updated (the meter values; it replaces the in-transaction `MeterValues`) and Ended (with `stoppedReason`),
   each with its `seqNo`; the `StatusNotification` was already 2.0.1's shape. The battery temperature, which 2.0.1 has no
   measurand for, and the twin's own facts ride in `customData`. The one engine reader of the log,
   `public.ottoq_charge_time_v2_params_cut`, takes a reading's charge from either shape, so the charge clock fits the
   same (0694's V1 compares a fit before and after) and needs no evidence regime or recertification. Every shape is
   validated against the 2.0.1 schemas in CI (`tests/test_twin_ocpp201_sql.py`).
2. **The bridge. First part built (`bridge.py`, 2026-10-10).** One station per twin charger (45 at the twin depot: 35
   ChargePoint CT4000 of 19.2 kW, 10 ABB Terra HP 350), each booted once with its own vendor, model and firmware from
   `ottoq_ocpp_chargers`, says the twin's rows to the back end over a real WebSocket. A row goes out exactly as the twin
   wrote it: the library's own `call()` rebuilds a payload from snake_case and would rename the twin's `customData`
   keys, so the bridge sends the frame itself, validated against the 2.0.1 schemas before it leaves and the answer when
   it returns. Tested against the shapes the live log holds: a charge as 0694 writes it is accepted frame for frame and
   arrives unaltered (Started, Updated, Ended with seqNo 0, 1, 2); the log as it is today is refused for every row but
   its `StatusNotification`s (the `Authorize` carries a timestamp 2.0.1 does not admit, and `StartTransaction`,
   `StopTransaction` and the 1.6-shaped `MeterValues` are not 2.0.1). Run 17a490fc's 10,537 charger rows, read
   2026-10-10, are 1,034 `StatusNotification`, 534 `Authorize`, 534 `StartTransaction`, 500 `StopTransaction` and 7,935
   `MeterValues`; the replay that measures them through the bridge runs after 0694, on the first run that writes 2.0.1
   rows, beside a replay of rows from before it.

   **Still to build, and how (the live bridge).** The twin's rows come out of the database and the back end's log goes
   back in, with no inbound port on the box and no database key on it. In: the back end's frames go to OTTO-Q through
   `ottoq-ingest` under a platform-issued source key carrying the `ocpp` stream, which already takes the tenant and the
   data source from the credential (0649, and Security 4 of this review). Out: a relay edge function returns the twin's
   charger rows after a cursor to a key scoped to the twin depot. The key is generated on the box and kept in its
   parameter store; only its hash leaves it. Then a dial switches the twin from writing its charger log itself to
   writing an outbox the bridge drains, and the log of record is what the back end received. OTTO-Q's charge plans go
   out as `SetChargingProfile` through the same relay; the twin's charge physics reading a station's accepted limit is
   the step after.
3. **Host it on AWS** beside the intelligence service on `ottoq-intel-2`, deployed the way that service is
   (`ottoq-intelligence/.github/workflows/aws-deploy-ssm.yml`: over SSM, no SSH, no inbound rule). With the simulated
   stations on the same box the back end listens on localhost only. A real charger needs an inbound `wss://` port with
   TLS, and OCPP 2.0.1's security profile 2 or 3 (basic auth over TLS, or client certificates), which pairs with the
   contract's mTLS plan.
