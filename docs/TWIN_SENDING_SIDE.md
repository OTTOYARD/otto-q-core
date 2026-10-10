# The twin's sending side through the v2 door

**Status:** design, 2026-10-10 1:00 AM CT. Step 4 of the twin data contract review: *"The twin publishes and
receives only through the v2 door, as two synthetic operators."* The receiving half is built (0653-0655: the
operators read their directives through the door and answer each with an ack; the flag `twin_operator_door` waits on
its second pair). This is the sending half. Chase, 2026-10-09: route the twin's sending signals through the door
first, full separation later.

## What the twin sends today, and where it lands

Every one of these is a direct write from the twin's tick into OTTO-Q's own tables, in OTTO-Q's transaction. A real
operator could do none of them.

| Signal | Written today by | Lands in | Engine readers that decide something |
|---|---|---|---|
| Telemetry | `twin.ottoq_sim_emit_telemetry`, one packet per deployed car per tick (its only caller is `twin.ottoq_sim_advance_deployed_telemetry`), including rows for packets it drops | `ottoq_telemetry_packets` (+ the car's SoC on `vehicles`) | two recall policies (`ottoq_recall_naive_threshold_v1`, `ottoq_recall_interval_scheduled_v1`) and the measured burn (`ottoq_measured_burn_pct_per_min`) read `soc_pct`; the computed ETA reads `speed_kmh`; the shield's `ottoq_hw_vehicle_status` reads `soc_pct`. **No engine function reads a packet's position**, and the twin app reads only packet counts. |
| Faults | the same tick function, from `twin.ottoq_sim_maybe_incident` | `ottoq_vehicle_incidents`, the car to `tow_requested` | the visit deriver and the bays, through the car's state |
| Coming home | the same tick function's return block, which calls **OTTO-Q's own evaluator** (`ottoq_evaluate_return_need`) inside the twin's tick and marks the dispatch `returning` with an ETA | `ottoq_vehicle_dispatches`, `vehicles`, the recall ledger | the day plan, the futures, the gate intake |
| Leaving | `twin.ottoq_sim_dispatch_vehicle` (and the run-start prime) | `ottoq_vehicle_dispatches` (status `active`), the car to `deployed` | everything downstream of a car leaving |

## What the door already does with each (`ottoq.ottoq_v2_apply`)

| Event | Effect today |
|---|---|
| `vehicle.telemetry` | a packet (VSS signals, each with its own time; a position outside the geofence dropped and counted), and the car's SoC when fresh on the key's clock |
| `vehicle.fault.summary` | an open `exceptions` row (category, severity, services needed, whether it takes the car offline) |
| `depot.arrival.intent` | `ottoq_ingest_vehicle_signal`, which asks `ottoq_decide_return_on_signal` and may mark the dispatch `returning`, and the car `en_route_to_depot` |
| `vehicle.departed` | kept in the inbox only: *"the depot's release of what it held for the car is wired when the twin sends departures (step 4)"* |

## The order, and why

Each stage is its own flag, off by default, so each is measured by its own pair and flipped as a certified change.
The receiving half's flag (`twin_operator_door`) is separate and stays separate.

1. **Telemetry.** The tick builds a `vehicle.telemetry` event per deployed car (SoC, power, speed, battery and air
   temperature, odometer, DTCs) under its operator's key and per-car sequence, and the door writes the packet. A
   packet the twin's world drops is simply not sent (a real operator's lost packet never reaches the door either);
   `degraded` integrity has no field in the contract and is lost, which costs nothing because no engine reader uses
   it. Positions on the road are dropped by rule 5, which costs nothing either (no reader). Cost: one door call per
   deployed car per tick, to be measured. **Nothing here depends on a decision.**
2. **Faults.** An incident becomes a `vehicle.fault.summary`: collisions to `vehicle_damage` (minor, moderate, major
   to low, medium, high), an electrical breakdown to `vehicle_malfunction`, a tire to `tire_issue`, a stranded car to
   `vehicle_unresponsive`; `takes_vehicle_offline` from the tow. The car's physical state (towed) stays the world's
   own write until full separation, because the twin and OTTO-Q still share the `vehicles` row.
3. **Leaving.** OTTO-Q decides a car is ready; the operator takes it. Today one write does both. The door's
   `vehicle.departed` gets its effect (release the stall, the bookings and the holds OTTO-Q kept for the car, and
   record what was still open if it left early, contract rule 8), and the twin's dispatcher sends it.
4. **Coming home**, which needs the contract to grow first (next section).

## Two couplings found while preparing stage 1 (read 2026-10-10, about 1:00 AM CT)

- **The twin's world reads OTTO-Q's packets as its own truth.** `twin.ottoq_sim_advance_wear_counters` takes each
  car's speed from its latest row in `ottoq_telemetry_packets` and the tick's worst DTC severity from the packets'
  `dtc_codes`, and turns them into soil, preventive-maintenance and calibration wear. So the packets are both what
  OTTO-Q was told and what the world did. Once the door writes them, a lost packet changes the world (today a dropped
  packet row reads as speed 0; through the door there is no row and the previous speed stands), and anything the door
  does not carry vanishes from the world. **Prerequisite for stage 1:** the deployed tick keeps its own drive log
  (`twin.*`, run-scoped: speed, DTC, per car per tick) and the wear counters read that, not the packets.
- **The twin's DTCs are not OBD-II codes.** They come from `ottoq_dtc_catalog` as proprietary codes (`AV-H0001`,
  `AV-SN003`, ...). The contract carries only OBD-II codes in `Vehicle.Diagnostics.DTCList` and puts an operator's own
  codes in `vehicle.fault.summary.fault_codes`. The database half of the door does not re-check the schema (the HTTP
  half does), so sending them as telemetry would work only because the twin skips the HTTP check, which is exactly the
  privilege the swap test forbids. **So DTCs move with faults, not with telemetry:** stage 1 sends no DTC list, and
  stage 2 sends each new DTC as a fault summary (category from the catalog's: perception and sensor to
  `sensor_anomaly`, hardware and powertrain to `vehicle_malfunction`, the rest `other`; `takes_vehicle_offline`
  false). That gives OTTO-Q an exception per DTC, which it does not get today: a change to measure, not a plumbing step.

Stages 1 and 2 therefore ship together, after the drive log, and their pair reads the depot's service demand as well
as its fleet hours.

## The one gap: OTTO-Q cannot recall a car through the door

The Recall Decision (CLAUDE.md 2.7) is *"the single interface to every work-side system"*. Contract 0.1 has no
directive for it: only the operator can say a car is coming home (`depot.arrival.intent`). The twin works today
because OTTO-Q's evaluator runs inside the twin's own tick, which no real operator would allow. Routing returns
through the door with 0.1 leaves two bad choices: the twin's operator decides returns on a policy of its own (and
OTTO-Q's recall stops shaping the twin's arrivals), or two deciders run at once (the twin's block and the door's
`ottoq_decide_return_on_signal`).

**Recommended: contract 0.2 adds `directive.recall`** (OTTO-Q to operator): `recall_by`, the services the visit is
for, `target_ready_time`, and the versioning, expiry and ack rules every directive already has. The operator answers
with an ack (`accepted`; `rejected` or `unable` from the closed list, plus one new reason, `mission_in_progress`,
which 2.7 calls a first-class event that triggers a re-solve) and, when it turns the car home, a
`depot.arrival.intent` with its own ETA. OTTO-Q's evaluator then runs on the telemetry the door took, not inside the
twin's tick, and the twin's operators honour recalls as a real operator would. That is the full separation; stages 1-3
do not wait for it.

## What changes in the numbers

Nothing until a flag is set. Each stage's pair reads the depot's day (fleet hours, turnaround, waits) with the flag at
0 and at 1 on the same seed; the flip forces a recertification, because packets, exceptions and dispatches are then
written by a different path. At the end of stage 4 and the recall directive, the twin's tick writes only `twin.*`
tables and the door's inputs, which is the swap test made literal: the same OTTO-Q, fed by a real operator through the
same door, sees the same kind of world.
