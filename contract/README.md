# OTTO-Q depot contract 0.1

How a fleet operator and an OTTO-Q depot talk: what an operator sends about its own cars,
what the depot sends back, and the rules both sides keep.

**Status:** written 2026-10-09 as step 2 of the twin data contract review. Step 3 built the door
that serves it, `ottoq-depot-v2` (database half: migrations 0650 to 0652), beside the current
`ottoq-ingest`, which stays until nothing uses it. Step 4 makes the twin a client of that door as two synthetic operators,
`sim-a` and `sim-b`, so the twin talks to OTTO-Q the way a real operator would.

| Link | What it speaks | State |
|---|---|---|
| operator to and from OTTO-Q | this contract: CloudEvents 1.0.2 envelope, JSON Schema 2020-12 payloads, COVESA VSS 6.0 signal names | 0.1, documents only |
| OTTO-Q to a charger | OCPP 2.0.1 | the twin's chargers are modeled as 2.0.1; real `TransactionEvent` and `SetChargingProfile` in step 5 |
| OTTO-Q to the utility | OpenADR 3 | later |
| who is talking | interim: platform-issued source keys (migration 0649). Target: mutual TLS with OAuth client credentials and certificate-bound tokens (RFC 8705) | interim live on `ottoq-ingest` |

This contract replaces, for operator traffic, the twin's internal channel
(`ottoyarddepot-sim/src/lib/ottoq/contracts.ts`, channel version 1.1.0) and answers the open
question in `ottoyarddepot-sim/docs/OTTOQ-TWIN-BOUNDARY.md` about a closed refusal
vocabulary: the ack reasons below are closed.

## Files

| File | What it is |
|---|---|
| `schemas/envelope.json` | the CloudEvents envelope as this contract narrows it; validates a whole event, `data` included |
| `schemas/<type>.json` | one schema per event type (ten), plus `defs.json` for shared pieces |
| `asyncapi.yaml` | AsyncAPI 3.1.0 index of the two channels and ten messages |
| `vss_mapping.json` | every vehicle field OTTO-Q holds today, named in VSS, with its unit conversion, and the fields deliberately not carried |
| `examples/valid/` | one conforming event per type (10) |
| `examples/invalid/` | 18 events that break one rule each; `expect.json` names the rule |
| `examples/example-jwks.json` | the public half of the published RFC 8037 test key that signs the examples |
| `ottoq_contract.py` | the kit: validate an event, canonicalize, sign, verify |
| `test_ottoq_contract.py` | the battery; runs in CI's pytest step with no database and no network |

```
python3 contract/ottoq_contract.py check EVENT.json... --jwks contract/examples/example-jwks.json
python3 contract/ottoq_contract.py sign-examples --check
python3 -m pytest -q contract/
```

## The envelope

Every event is a CloudEvents 1.0.2 event in structured JSON mode. This contract narrows
CloudEvents; it never widens it.

- **Required:** `specversion` = `"1.0"`, `id`, `source`, `type`, `time`, `datacontenttype` =
  `"application/json"`, `dataschema`, `data`. CloudEvents makes `time` and `dataschema`
  optional; this contract requires both.
- **`dataschema` is pinned per type** to `https://ottoyard.com/schemas/ottoq/contract/0.1/<type>.json`.
- **No other attributes.** There is no tenant, depot, fleet or data-source attribute, and an
  unknown attribute is refused, not ignored (rule 1). CloudEvents 1.0.2's optional
  `sequencetype` is not used; the contract itself defines what `sequence` means.
- **From an operator:** `source` is `urn:ottoq:src:<operator>:<vehicle_ref>`, `subject` is the
  `vehicle_ref`, and `sequence` is a 20-digit zero-padded counter for that source. No `ottoqsig`.
  Every operator event concerns one car, so naming the car in `source` gives a per-car order.
  That is the advice the sequence extension gives today for ordering by a second dimension
  (on CloudEvents' `main` branch; the `v1.0.2` text predates it).
- **From OTTO-Q:** `source` is `urn:ottoq:depot:<depot uuid>`, `subject` is the car's
  `vehicle_ref` where the event concerns one car, and `ottoqsig` is required (Signatures, below).
- **Transport:** HTTPS `POST` of one event (`Content-Type: application/cloudevents+json`) or of
  a batch (`application/cloudevents-batch+json`, a JSON array). The HTTP binding says batched
  mode must not be used unless solicited and that the receiver should choose the maximum size;
  this contract solicits it, at most **500 events and 1 MiB** per batch. Binary mode is not
  accepted in 0.1: every event is one JSON document the schemas judge whole and the signature
  covers whole.
- **The door** (`ottoq-depot-v2`): `POST /events` takes one event or a batch; `?dry_run=true`
  does everything and keeps nothing. Each event comes back `applied`, `late`, `duplicate` or
  `refused` with its reason. `GET /directives?after=<cursor>&limit=<1-500>` returns the key's own
  directives, oldest first, signed, as a batch, with the next cursor in the `OTTOQ-Next-After`
  header (`?peek=true` leaves them unmarked as delivered). `GET /jwks` returns the keys they verify
  under. The key goes in the `X-OTTO-Q-API-Key` header.
- **Timestamps** are RFC 3339 with an explicit `Z` or offset. `format` is an annotation only;
  every rule on a string is a `pattern`, so any 2020-12 validator enforces the same contract.

## The events

| Type (`com.ottoyard.` + ) | From | What | Ack | Source-key stream |
|---|---|---|---|---|
| `vehicle.telemetry` | operator | VSS signals, each with the time it was observed | no | `telemetry` |
| `depot.arrival.intent` | operator | a car is coming home: ETA and its spread, predicted charge, services needed, ready-by | no | `arrival` |
| `vehicle.fault.summary` | operator | the operator's own reading of a fault: severity, category, whether it takes the car offline | no | `incident` |
| `vehicle.departed` | operator | the car has left the depot | no | `arrival` |
| `directive.ack` | operator | the answer to one version of one directive | — | none: it answers a directive the key's own operator was sent |
| `directive.stall.assignment` | OTTO-Q | where the car should go, for what, and for how long | required | — |
| `directive.charge.plan` | OTTO-Q | the charge it will get at its charger, as an OCPP 2.0.1 charging schedule | required | — |
| `directive.service.schedule` | OTTO-Q | every service on this visit, where and when; overlapping windows run together | required | — |
| `readiness.forecast` | OTTO-Q | when the car should be ready for work (p50, p90) and what is still open | none | — |
| `capacity.offer` | OTTO-Q | what the depot holds for this operator in a window, in coarse counts | none | — |

The streams are the ones a source key carries (`ottow_api_keys.streams`, migration 0649):
`energy`, `telemetry`, `ocpp`, `arrival`, `incident`. An ack needs no stream, and reading
directives needs none: both need the key to speak for the car's fleet
(`ottow_api_keys.fleet_operator_ids`, set by `ottoq_scope_source_key`, migration 0650).

## The rules

**1. The credential decides who is talking.** The depot, the operator, the data source
(`production`, `twin`, `replay` or `shadow`) and the streams come from the credential, never
from the event. The operator segment of `source` must be the credential's own source name, or
the event is refused. A `vehicle_ref` (the car's `display_name`) resolves only among the cars of
the fleets the key speaks for, at the key's depot; anything else reads as not found, so a key can
neither touch another tenant's car nor learn that it exists. A key that speaks for no fleet sends
no car's events.

**2. Event time is kept, and an old signal reads as unknown.** `time` and every signal's `ts`
are stored as sent, beside the time the door took the event. A signal older than its time to
live reads as unknown, never as its last value. "Now" is the clock of the credential's data
source: the wall clock for `production` and `shadow`, the running run's sim clock for `twin` and
`replay` (a twin or replay key with no running run at its depot is refused). Mixing the two clocks
is the bug class `db/checks/0326` §1 measured on the stall calendar. The production defaults
below are chosen for depot decisions, not measured; an operator agreement may tighten them.
Twin values are set in step 4 against the run's tick length, because one twin tick can move
the sim clock by 30 minutes and a real-world threshold against that cadence fails by
construction (the HW.002 finding, G150).

| Signal (VSS path) | Unit | TTL (production) |
|---|---|---|
| `Vehicle.Powertrain.TractionBattery.StateOfCharge.Current`, `.Displayed` | percent | 120 s |
| `Vehicle.Powertrain.TractionBattery.CurrentPower` (positive into the battery) | W | 60 s |
| `Vehicle.Powertrain.TractionBattery.Charging.IsCharging` | boolean | 60 s |
| `Vehicle.Powertrain.TractionBattery.Charging.TimeToComplete` | s | 120 s |
| `Vehicle.Speed` | km/h | 60 s |
| `Vehicle.CurrentLocation.Latitude`, `.Longitude` (sent together) | degrees | 60 s |
| `Vehicle.Powertrain.TractionBattery.Temperature.Average` | Celsius | 300 s |
| `Vehicle.Powertrain.TractionBattery.Range`, `Vehicle.Powertrain.Range` | m | 300 s |
| `Vehicle.Diagnostics.DTCList` (OBD-II codes only) | — | 300 s |
| `Vehicle.Exterior.AirTemperature` | Celsius | 900 s |
| `Vehicle.TraveledDistance` | m | 3,600 s |
| `Vehicle.Chassis.Axle.Row{1,2}.Wheel.{Left,Right}.Tire.Pressure` | kPa | 3,600 s |
| `Vehicle.Powertrain.TractionBattery.Charging.ChargeLimit` (read only) | percent | 86,400 s |
| `Vehicle.Powertrain.TractionBattery.StateOfHealth`, `.NetCapacity` | percent, kWh | 604,800 s |

**3. Directives are versioned, expiring requests.** Each carries `directive_id`, `version`,
`supersedes`, `issued_at`, `valid_from`, `expires_at`, `ack_deadline` and `vehicle_ref`. The
operator acts on the highest version it holds, not before `valid_from`, never after
`expires_at`. A new version of the same `directive_id` amends it; `supersedes` names a different
directive this one replaces. A directive is a request: the operator may refuse it, and no ack by
`ack_deadline` means not done, so OTTO-Q re-plans instead of assuming.

**4. A tenant sees only its own cars.** Everything OTTO-Q sends an operator concerns that
operator's own cars and holds. Nothing names another tenant's car, charge, ETA or count. So
`capacity.offer` has no vehicle field at all and gives the wait for a charger as a band, not a
place in line: a place in line is an exact count of the cars ahead, and some are another
tenant's.

**5. Precise location only inside the depot.** A latitude and longitude outside the depot's
geofence are dropped by the door (the rest of the event stands) and the drop is counted. OTTO-Q
is the pit lane, not the race: where a car is on the road is the operator's business, and its
ETA comes from the arrival intent. The twin depot's geofence is its stalls' convex hull
buffered by 50 m (set by migration 0650; it was empty before).

**6. Each event once, in order per car.** CloudEvents makes `source` + `id` unique; the door
refuses a second event with the same pair as a duplicate. An event is applied only if its
`sequence` is above the last one applied for its source. A lower one is stored as late and
never overwrites newer state. A gap is recorded and never waited for, so one lost event cannot
hold a car's telemetry hostage. A refused event is not stored: correct it and send it again with
a sequence above the last one applied, or it will read as late.

**7. OTTO-Q never actuates a vehicle.** Directives are requests to the operator, never commands
to a car. `ChargeLimit` is a VSS actuator, so OTTO-Q only reads it. Charging is controlled only
at the charger, by OTTO-Q's charger back end over OCPP 2.0.1: `charge.plan`'s
`charging_schedule` maps one to one onto a `ChargingProfile` with purpose `TxProfile` and kind
`Absolute` (`start_schedule` to `startSchedule`, `charging_rate_unit` to `chargingRateUnit`,
`periods[].start_period_s` to `chargingSchedulePeriod[].startPeriod`, `limit` to `limit`,
`number_phases` to `numberPhases`). Power reaches a site only as a forward schedule, never as a
real-time setpoint (`ADAPTERS.md`, law 2).

**8. Vehicle first.** A car's charge target is its owner's: 100% unless the owner set less
(CLAUDE.md rule 9). Only the owner's credential may send `charge_target_pct`, and OTTO-Q never
lowers it. Every service the depot finds a car to need is done before the depot calls the car
ready; `readiness.forecast` lists what is still open. When a car is not ready it is
re-orchestrated, not released. Leaving is the operator's own act, reported as `vehicle.departed`,
and OTTO-Q records what was still open if it left early.

**9. Refusals come from a closed list.** OTTO-Q re-plans differently for each reason, so an
open text field would be a refusal it cannot act on.

| `reason` | Meaning | What OTTO-Q does |
|---|---|---|
| `occupied` | the stall was physically taken | records a space conflict and assigns another stall |
| `vehicle_unresponsive` | the car cannot move | treats it as an immobile asset: keeps the stall and schedules recovery |
| `unsafe` | carrying it out now would be unsafe | blocks the stall or path, re-plans, and flags it for a person |
| `charger_fault` | the charger failed at or during plug-in | marks the charger suspect and re-queues the car to finish its charge |
| `vehicle_not_at_depot` | the car is not at the depot | re-forecasts the arrival from the next intent |
| `owner_override` | the owner instructed otherwise | honors it as the owner's requirement |
| `expired` | it could not be done before `expires_at` | re-issues it if it is still needed |
| `superseded` | a newer directive replaced it | nothing: the newer one stands |
| `other` | none of the above; `detail` is required | counts it and puts it before a person; frequent use means the list grows |

`accepted` carries no reason; `rejected` (the operator chose not to) and `unable` (it could not)
always carry one.

## Signatures

Everything OTTO-Q sends carries `ottoqsig`, a detached JWS in compact form (RFC 7515 Appendix
F): `BASE64URL(header) + ".." + BASE64URL(signature)`.

- **Header:** exactly `{"alg":"Ed25519","kid":"<key id>"}`. RFC 9864 (October 2025) registered
  `Ed25519` as a fully specified algorithm and deprecated the polymorphic `EdDSA`, so `EdDSA` is
  refused.
- **What is signed:** the RFC 8785 canonical form of the **whole event without `ottoqsig`**, so
  the signature binds `id`, `source`, `type`, `subject`, `time` and `data` together. A signature
  over `data` alone would let a directive be replayed under another event's identity.
- **Signing input:** `BASE64URL(header) + "." + BASE64URL(JCS(event minus ottoqsig))`, signed with
  Ed25519 (RFC 8032), which is deterministic: the same event and key always give the same bytes.
- **Keys:** each depot signs with its own key, named by `kid` and published as a JWK Set
  (RFC 7517) of `OKP`/`Ed25519` public keys. Where the set is published, and how keys rotate
  with overlap, is decided in step 3. No real key is ever in this repository.
- **The examples** are signed with the published test key of RFC 8037 Appendix A.1
  (`kid` `rfc8037-a1-test-key`), so anyone can check a verifier against them. Checked two ways
  on 2026-10-09: by this kit, and independently by Node 22's `JSON.stringify` and `crypto.verify`
  (9 of 9 signed examples verified).

Operator events are not signed: the credential that sends them is the proof (rule 1).

## Versioning

The contract version is in every schema's `$id` and every `dataschema` (`.../contract/0.1/...`).
On an operator's events, adding an optional field or a reason is backward compatible: old
senders simply do not send it. On OTTO-Q's events it is not, because every schema refuses
unknown fields, so OTTO-Q sends each operator the version its credential speaks, and a new
field ships under a new version URL. A removed or renamed field is always a new version.

## Decisions made while writing, and what is left

- **`EdDSA` became `Ed25519`** (RFC 9864, above).
- **The signature covers the whole event,** not only `data`.
- **The twin's fault codes are not OBD-II.** Measured on the twin depot's cars over 30 days:
  834,782 packets carry 710 codes in 15 distinct values, every one the twin's own form
  (`AV-P0003`, `AV-PL010`, `AV-H0050` ...), none in the SAE J2012 form VSS defines `DTCList`
  for. They travel as `vehicle.fault.summary` `fault_codes`, stored and never interpreted.
- **The tire array has no wheel order in the twin.** `twin.ottoq_sim_emit_telemetry` draws the
  four pressures independently, so index 1 to 4 = front-left, front-right, rear-left, rear-right
  is a naming choice, not a fact (`vss_mapping.json`).
- **Twin power has the opposite sign of VSS:** `instant_power_kw` is positive while driving
  (810,342 of 835,238 driving packets, 30 days), so `CurrentPower` = -1000 x `instant_power_kw`.
- **Settled while building the door (step 3):** a key names the fleets it speaks for; an ack
  needs no stream; directives are read from `GET /directives` (a push to a registered webhook
  would be the same events on another transport); the JWK Set is `GET /jwks`; the twin depot has
  a geofence; `ready_by` on a charge plan is sent only where the depot knows the car's due time;
  `stall_type` carries every type the engine has. A command renders as a directive with
  `directive_id` = its command id, version 1 (the engine issues a new command, not a new
  version, when it changes its mind), an ack deadline one tick after issue and an expiry two
  ticks after (the hold window the engine already gives a stall), at the owner's target
  (`ottoq_effective_target_soc_at`), and never at zero watts.
- **The engine's refusal codes and the contract's reasons are both closed lists.** The door maps
  one onto the other (`occupied` to `target_occupied`, `charger_fault` to `resource_faulted`, and so
  on) and keeps the contract's reason verbatim beside the engine's code, so nothing is lost.
- **Left for step 4:** the twin's TTLs against its tick length, and `sim-a`/`sim-b` as clients,
  with a test that `sim-a` never sees `sim-b`.
- **Left for step 5:** the OCPP 2.0.1 messages behind `charge.plan`.
- **When a real operator onboards:** mutual TLS and OAuth client credentials (RFC 8705) in place
  of source keys.
- **AsyncAPI tooling:** AsyncAPI 3.1.0 requires tools to support only its own Schema Object and
  JSON Schema Draft 07. These payloads are 2020-12, declared as a custom `schemaFormat`, which
  AsyncAPI allows and leaves optional to support. So an AsyncAPI tool will read
  `asyncapi.yaml` but may not validate payloads; `ottoq_contract.py` does. `asyncapi.yaml`
  itself validates against AsyncAPI's own 3.1.0 JSON Schema with 0 errors (checked 2026-10-09 CT
  against `asyncapi/spec-json-schemas` at `21e5be6`, `schemas/3.1.0-without-$id.json`; a copy
  with two deliberate mistakes drew 2 errors). CI checks its structure, not that schema.

## Sources

Every external fact above, with its version and where it was read. All retrieved on 2026-10-09
between 6:45 and 7:05 PM CT (23:45 to 00:05 UTC).

| Fact | Version | Source |
|---|---|---|
| Required attributes; `source` + `id` unique; `time` is RFC 3339; attribute names | CloudEvents 1.0.2 (tag `v1.0.2`, `fc1f6f3`) | https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md |
| `application/cloudevents+json`; batch format `application/cloudevents-batch+json` (§4.2) | CloudEvents JSON format 1.0.2 | https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/formats/json-format.md |
| Structured, binary and batched modes; batched only when solicited, receiver chooses the size (§3) | CloudEvents HTTP binding 1.0.2 | https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/bindings/http-protocol-binding.md |
| `sequence` is a non-empty lexicographically orderable string; optional `sequencetype` | sequence extension at tag `v1.0.2` | https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/extensions/sequence.md |
| zero-pad for string order; put a second ordering dimension in `source`; `sequencetype` removed | sequence extension on `main` at `2ed3806` (no CloudEvents tag after `v1.0.2` exists) | https://github.com/cloudevents/spec/blob/2ed3806b4ad8fda35813263cfefb2d73098b7655/cloudevents/extensions/sequence.md |
| Schema formats every implementation must support; custom `schemaFormat` allowed, support optional; operation `security` | AsyncAPI 3.1.0 (tag `v3.1.0`, `b3fac5b`) | https://github.com/asyncapi/spec/blob/v3.1.0/spec/asyncapi.md |
| AsyncAPI 3.1.0 JSON Schema used to validate `asyncapi.yaml` | `asyncapi/spec-json-schemas` `master` at `21e5be6` | https://github.com/asyncapi/spec-json-schemas/blob/21e5be6d86a6c337808b6b07fc5fc342ef6d9d49/schemas/3.1.0-without-%24id.json |
| Every VSS path, type, datatype and unit used; `CurrentPower` positive into the battery; `DTCList` is OBD II (SAE-J2012DA_201812) codes | COVESA VSS 6.0 (tag `v6.0`, `20c609b`, 2026-01-15); same in 6.1 (`2817646`, 2026-09-17) | https://github.com/COVESA/vehicle_signal_specification/tree/v6.0/spec |
| `ChargingProfileType` and `ChargingScheduleType` field names, purposes and kinds | OCPP 2.0.1 JSON schema, file comment "OCPP 2.0.1 FINAL", as redistributed by `mobilityhouse/ocpp` (`master` at `b39291d`) | https://github.com/mobilityhouse/ocpp/blob/b39291d6ae769649062ec73fcb5e471b8eaed51c/ocpp/v201/schemas/SetChargingProfileRequest.json |
| Detached content (Appendix F) | RFC 7515, May 2015 | https://www.rfc-editor.org/rfc/rfc7515#appendix-F |
| JWK Set | RFC 7517, May 2015 | https://www.rfc-editor.org/rfc/rfc7517 |
| Canonical JSON: ECMAScript numbers, UTF-16 key order; samples in §3.2.2, §3.2.3, Appendix B | RFC 8785, June 2020 | https://www.rfc-editor.org/rfc/rfc8785 |
| Ed25519 test key (A.1) and signing vector (A.4) | RFC 8037, January 2017 | https://www.rfc-editor.org/rfc/rfc8037#appendix-A |
| `Ed25519` registered; polymorphic `EdDSA` deprecated (§4.1) | RFC 9864, October 2025 | https://www.rfc-editor.org/rfc/rfc9864#section-4.1 |
| Mutual-TLS client authentication and certificate-bound access tokens | RFC 8705, February 2020 | https://www.rfc-editor.org/rfc/rfc8705 |
| Timestamps | RFC 3339, July 2002 | https://www.rfc-editor.org/rfc/rfc3339 |
| JSON Schema dialect of every schema here | JSON Schema 2020-12 | https://json-schema.org/draft/2020-12/schema |

Facts measured in OTTO-Q's own database (project `gxdrcyphqjzjsuhxuqtg`, twin depot
`11111111-1111-1111-1111-111111111111`, 2026-10-09): the power sign, the fault-code census and
the empty geofence above; the tire draw from the live body of `twin.ottoq_sim_emit_telemetry`.
