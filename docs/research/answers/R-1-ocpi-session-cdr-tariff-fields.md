# R-1 — OCPI 2.2.1 / 2.3.0 Field Lists (Session, CDR, Tariff, Token, ChargingProfile)

## Answers

Source: https://github.com/ocpi/ocpi (modules are asciidoc at repo root).
- OCPI **2.2.1** → git tag `2.2.1`
- OCPI **2.3.0** → git tag `v2.3.0` (default branch `2.3.0/release/core`)
- Raw base: `https://raw.githubusercontent.com/ocpi/ocpi/<tag>/<file>.asciidoc`

Files used: `mod_sessions.asciidoc`, `mod_cdrs.asciidoc`, `mod_tariffs.asciidoc`,
`mod_tokens.asciidoc`, `mod_charging_profiles.asciidoc`, `types.asciidoc`.

Cardinality legend (`Card.` column verbatim): `1` = required · `?` = optional ·
`*` = 0..n · `+` = 1..n.

## Q1 — Session object (`mod_sessions.asciidoc` §Session Object)

**Identical in 2.2.1 and 2.3.0** (no field-table diff). Energy field is verbatim `kwh`
(type `number`, required). Token ref is verbatim `cdr_token` (type `CdrToken`, not a string).

| Field | Type | Card. | Unit / note |
|---|---|---|---|
| country_code | CiString(2) | 1 | ISO-3166 alpha-2 of owning CPO |
| party_id | CiString(3) | 1 | CPO id (ISO-15118) |
| id | CiString(36) | 1 | session id in CPO platform |
| start_date_time | DateTime | 1 | session → ACTIVE |
| end_date_time | DateTime | ? | session finished |
| **kwh** | number | 1 | kWh charged |
| **cdr_token** | CdrToken | 1 | token that started session |
| auth_method | AuthMethod | 1 | |
| authorization_reference | CiString(36) | ? | eMSP ref |
| location_id | CiString(36) | 1 | `Location.id` (string ref, NOT object) |
| evse_uid | CiString(36) | 1 | `EVSE.uid`, may be `#NA` |
| connector_id | CiString(36) | 1 | `Connector.id`, may be `#NA` |
| meter_id | string(255) | ? | kWh meter id |
| currency | string(3) | 1 | ISO 4217 |
| charging_periods | ChargingPeriod[] | * | |
| total_cost | Price | ? | price eMSP pays CPO |
| status | SessionStatus | 1 | |
| last_updated | DateTime | 1 | |

**CdrToken** (defined in `mod_cdrs.asciidoc`, reused here): `country_code` CiString(2) 1 ·
`party_id` CiString(3) 1 · `uid` CiString(36) 1 · `type` TokenType 1 · `contract_id` CiString(36) 1.

**ChargingPeriod**: `start_date_time` DateTime 1 · `dimensions` CdrDimension[] + · `tariff_id` CiString(36) ?.
**CdrDimension**: `type` CdrDimensionType 1 · `volume` number 1 (unit depends on `type`).

**SessionStatus** enum: `ACTIVE` · `COMPLETED` · `INVALID` · `PENDING` · `RESERVATION`.
**AuthMethod** enum: `AUTH_REQUEST` · `COMMAND` · `WHITELIST`.

## Q2 — CDR object (`mod_cdrs.asciidoc` §CDR Object)

**Field list identical in 2.2.1 and 2.3.0** (2.3.0 changes only descriptions/refs).
`session_id` is **optional** (`?`), not required.

| Field | Type | Card. | Unit / note |
|---|---|---|---|
| country_code | CiString(2) | 1 | ISO-3166 alpha-2 of owning CPO |
| party_id | CiString(3) | 1 | CPO id (ISO-15118) |
| id | CiString(39) | 1 | unique per country_code/party_id |
| start_date_time | DateTime | 1 | |
| end_date_time | DateTime | 1 | |
| **session_id** | CiString(36) | **?** | omit only if no Sessions module / reservation-only |
| cdr_token | CdrToken | 1 | |
| auth_method | AuthMethod | 1 | last method used |
| authorization_reference | CiString(36) | ? | |
| cdr_location | CdrLocation | 1 | |
| meter_id | string(255) | ? | |
| currency | string(3) | 1 | ISO 4217 |
| tariffs | Tariff[] | * | |
| charging_periods | ChargingPeriod[] | + | |
| signed_data | SignedData | ? | |
| total_cost | Price | 1 | |
| total_fixed_cost | Price | ? | start tariff etc. |
| total_energy | number | 1 | **kWh** |
| total_energy_cost | Price | ? | |
| total_time | number | 1 | **hours** |
| total_time_cost | Price | ? | |
| total_parking_time | number | ? | **hours** |
| total_parking_cost | Price | ? | |
| total_reservation_cost | Price | ? | |
| remark | string(255) | ? | |
| invoice_reference_id | CiString(39) | ? | |
| credit | boolean | ? | Credit CDR flag |
| credit_reference_id | CiString(39) | ? | required for Credit CDR |
| home_charging_compensation | boolean | ? | |
| last_updated | DateTime | 1 | |

**cdr_location** (`CdrLocation` class): `id` CiString(36) 1 · `name` string(255) ? ·
`address` string(45) 1 · `city` string(45) 1 · `postal_code` string(10) ? ·
`state` string(20) ? · `country` string(3) 1 (ISO 3166-1 alpha-3) ·
`coordinates` GeoLocation 1 · `evse_uid` CiString(36) 1 · `evse_id` CiString(48) 1 ·
`connector_id` CiString(36) 1 · `connector_standard` ConnectorType 1 ·
`connector_format` ConnectorFormat 1 · `connector_power_type` PowerType 1.
(`evse_uid`/`evse_id`/`connector_id` may be `#NA` for reservation-never-started.)

**signed_data** (`SignedData` class): `encoding_method` CiString(36) 1 ·
`encoding_method_version` int ? · `public_key` string(512) ? (base64) ·
`signed_values` SignedValue[] + · `url` string(512) ?
(spec type cell links CiString but labels `string(512)` — a known spec typo).
**SignedValue**: `nature` CiString(32) 1 (values `Start`/`End`/`Intermediate`) ·
`plain_data` string(512) 1 · `signed_data` string(5000) 1 (base64 blob).
`encoding_method` names: OCMF, Alfen Eichrecht, EDL40 E-Mobility Extension, EDL40 Mennekes.

## Q3 — Tariff (`mod_tariffs.asciidoc` §Tariff Object + data types)

**Tariff object** (2.2.1; 2.3.0 delta flagged inline):

| Field | Type | Card. | Note |
|---|---|---|---|
| country_code | CiString(2) | 1 | |
| party_id | CiString(3) | 1 | |
| id | CiString(36) | 1 | |
| currency | string(3) | 1 | ISO 4217 |
| type | TariffType | ? | |
| tariff_alt_text | DisplayText[] | * | |
| tariff_alt_url | URL | ? | |
| min_price | **Price** (2.2.1) → **PriceLimit** (2.3.0) | ? | floor |
| max_price | **Price** (2.2.1) → **PriceLimit** (2.3.0) | ? | ceiling |
| preauthorize_amount | number | ? | **NEW in 2.3.0** |
| elements | TariffElement[] | + | |
| tax_included | TaxIncluded | 1 | **NEW in 2.3.0** |
| start_date_time | DateTime | ? | |
| end_date_time | DateTime | ? | |
| energy_mix | EnergyMix | ? | (locations module) |
| last_updated | DateTime | 1 | |

**TariffElement**: `price_components` PriceComponent[] + · `restrictions` TariffRestrictions ?.
**PriceComponent**: `type` TariffDimensionType 1 · `price` number 1 (per unit, excl. VAT in
2.2.1; incl/excl per `tax_included` in 2.3.0) · `vat` number ? (VAT %) · `step_size` int 1.

**TariffDimensionType** enum (both versions): `ENERGY` (kWh, step×1 Wh) · `FLAT` (no unit) ·
`PARKING_TIME` (hours, step×1 s) · `TIME` (hours, step×1 s).
→ There is **no** `PARKING` value; reservation is not a dimension (see `reservation` restriction).

**TariffRestrictions** class (all `?` unless noted; multiple restrictions = logical AND):

| Field | Type | Card. | Unit / note |
|---|---|---|---|
| start_time | string(5) | ? | "HH:MM" 24h local |
| end_time | string(5) | ? | "HH:MM" |
| start_date | string(10) | ? | "YYYY-MM-DD" |
| end_date | string(10) | ? | "YYYY-MM-DD" |
| min_kwh | number | ? | kWh (inclusive) |
| max_kwh | number | ? | kWh (exclusive) |
| min_current | number | ? | A |
| max_current | number | ? | A |
| min_power | number | ? | kW |
| max_power | number | ? | kW |
| min_duration | int | ? | seconds |
| max_duration | int | ? | seconds |
| day_of_week | DayOfWeek[] | * | |
| reservation | ReservationRestrictionType | ? | |

**DayOfWeek**: `MONDAY` `TUESDAY` `WEDNESDAY` `THURSDAY` `FRIDAY` `SATURDAY` `SUNDAY`.
**ReservationRestrictionType**: `RESERVATION` · `RESERVATION_EXPIRES`.
**TariffType**: `AD_HOC_PAYMENT` · `PROFILE_CHEAP` · `PROFILE_FAST` · `PROFILE_GREEN` · `REGULAR`.

**min_price / max_price semantics** (2.2.1): floor/ceiling on the whole session cost, applied
independently to excl-VAT and incl-VAT totals (see spec NOTE). In 2.3.0 the `PriceLimit` class
carries `before_taxes` (number, 1) and `after_taxes` (number, ?), same floor/ceiling semantics.

## Q4 — Token (`mod_tokens.asciidoc` §Token Object)

| Field | Type | Card. | Note |
|---|---|---|---|
| country_code | CiString(2) | 1 | MSP/eMSP that owns token |
| party_id | CiString(3) | 1 | eMSP id (ISO-15118) |
| uid | CiString(36) | 1 | token identifier (RFID hidden ID etc.) |
| type | TokenType | 1 | |
| contract_id | CiString(36) | 1 | EV-driver contract token id in eMSP platform |
| visual_number | string(64) | ? | printed number |
| issuer | string(64) | 1 | issuing company |
| group_id | CiString(36) | ? | groups tokens (OCPP parentId ≤20) |
| valid | boolean | 1 | |
| whitelist | WhitelistType | 1 | |
| language | string(2) | ? | ISO 639-1 |
| default_profile_type | ProfileType | ? | |
| energy_contract | EnergyContract | ? | |
| last_updated | DateTime | 1 | |

`uid` + `type` is the unique key within the eMSP system. **`contract_id`** is keyed on the EV
driver's contract token within the eMSP's platform (recommended eMA ID, "eMI3 standard v1.0").

**TokenType** (2.2.1, `_enum_`): `AD_HOC_USER` · `APP_USER` · `OTHER` · `RFID`.
**TokenType** (2.3.0, `_OpenEnum_`): adds **`EMAID`** (ISO 15118) → `AD_HOC_USER` · `APP_USER` ·
`EMAID` · `OTHER` · `RFID`.

**AllowedType**: `ALLOWED` · `BLOCKED` · `EXPIRED` · `NO_CREDIT` · `NOT_ALLOWED`.
**WhitelistType**: `ALWAYS` · `ALLOWED` · `ALLOWED_OFFLINE` · `NEVER`.
**EnergyContract**: `supplier_name` string(64) 1 · `contract_id` string(64) ?.

## Q5 — ChargingProfile / SetChargingProfile (`mod_charging_profiles.asciidoc`)

**Identical in 2.2.1 and 2.3.0** (only prose/wording diffs). The forward schedule object is the
`ChargingProfile` class. Note the period class is spelled **`ChargingprofilePeriod`** (lowercase
"p") — a real trap for field-level mapping.

**ChargingProfile** class:

| Field | Type | Card. | Unit / note |
|---|---|---|---|
| start_date_time | DateTime | ? | absolute start; if absent, relative to start of charging |
| duration | int | ? | seconds; if empty, last period runs indefinitely |
| charging_rate_unit | ChargingRateUnit | 1 | |
| min_charging_rate | number | ? | unit = `chargingRateUnit`; ≤1 decimal digit |
| charging_profile_period | ChargingProfilePeriod[] | * | |

**ChargingprofilePeriod** class:

| Field | Type | Card. | Unit / note |
|---|---|---|---|
| start_period | int | 1 | **seconds from start of profile**; also defines end of previous period |
| limit | number | 1 | rate limit in `chargingRateUnit` (A or W); ≤1 decimal digit |

**ChargingRateUnit** enum: `W` (Watts, total allowed power) · `A` (Amperes, per phase).

**SetChargingProfile** object: `charging_profile` ChargingProfile 1 · `response_url` URL 1.
(Also `ActiveChargingProfile`: `start_date_time` DateTime 1 · `charging_profile` ChargingProfile 1.
`ChargingProfileResponseType`: `ACCEPTED`·`NOT_SUPPORTED`·`REJECTED`·`TOO_OFTEN`·`UNKNOWN_SESSION`.
`ChargingProfileResultType`: `ACCEPTED`·`REJECTED`·`UNKNOWN`.)

## Q6 — Units & enums (complete, for lossless round-trip assertions)

**Numeric field units:**
- Session.`kwh`, CDR.`total_energy`, TariffRestrictions `min_kwh`/`max_kwh`, CdrDimension ENERGY/ENERGY_IMPORT/ENERGY_EXPORT volume → **kWh**.
- CDR.`total_time`, `total_parking_time`; CdrDimension TIME/PARKING_TIME/RESERVATION_TIME volume → **hours**.
- CdrDimension CURRENT/MAX_CURRENT/MIN_CURRENT → **A** (ampere).
- CdrDimension MAX_POWER/MIN_POWER/POWER → **kW**.
- CdrDimension STATE_OF_CHARGE → **percentage 0–100**.
- ChargingProfile.`duration`, ChargingprofilePeriod.`start_period` → **seconds**.
- ChargingprofilePeriod.`limit`, `min_charging_rate` → unit set by `charging_rate_unit` (W or A).
- PriceComponent.`step_size` → int, multiplier depends on `type` (ENERGY ×1 Wh; TIME/PARKING_TIME ×1 s; FLAT none).
- PriceComponent.`vat` → number, percent.
- TariffRestrictions `min_current`/`max_current` → A; `min_power`/`max_power` → kW; `min_duration`/`max_duration` → **seconds**.
- `number` type = JSON number, 4 decimals by default.

**Enums (complete value sets):**
- SessionStatus: `ACTIVE COMPLETED INVALID PENDING RESERVATION`
- AuthMethod: `AUTH_REQUEST COMMAND WHITELIST`
- CdrDimensionType: `CURRENT ENERGY ENERGY_EXPORT ENERGY_IMPORT MAX_CURRENT MIN_CURRENT MAX_POWER MIN_POWER PARKING_TIME POWER RESERVATION_TIME STATE_OF_CHARGE TIME` (values marked Session-Only: CURRENT, ENERGY_EXPORT, ENERGY_IMPORT, POWER, STATE_OF_CHARGE)
- TariffDimensionType: `ENERGY FLAT PARKING_TIME TIME`
- DayOfWeek: `MONDAY TUESDAY WEDNESDAY THURSDAY FRIDAY SATURDAY SUNDAY`
- ReservationRestrictionType: `RESERVATION RESERVATION_EXPIRES`
- TariffType: `AD_HOC_PAYMENT PROFILE_CHEAP PROFILE_FAST PROFILE_GREEN REGULAR`
- TokenType 2.2.1: `AD_HOC_USER APP_USER OTHER RFID`
- TokenType 2.3.0 (OpenEnum): `AD_HOC_USER APP_USER EMAID OTHER RFID`
- AllowedType: `ALLOWED BLOCKED EXPIRED NO_CREDIT NOT_ALLOWED`
- WhitelistType: `ALWAYS ALLOWED ALLOWED_OFFLINE NEVER`
- ProfileType: `CHEAP FAST GREEN REGULAR`
- ChargingRateUnit: `W A`
- ChargingProfileResponseType: `ACCEPTED NOT_SUPPORTED REJECTED TOO_OFTEN UNKNOWN_SESSION`
- ChargingProfileResultType: `ACCEPTED REJECTED UNKNOWN`
- Role: 2.2.1 `CPO EMSP HUB NAP NSP OTHER SCSP`; 2.3.0 removes `HUB`.
- TaxIncluded (2.3.0): `YES NO N/A`

## Q7 — Design question: is there any OCPI object for a completed non-energy service event?

**No.** OCPI 2.2.1 and 2.3.0 define **no** object for a completed non-energy service event. The
CDR is the only "completed transaction" record, and it is **strictly energy-bearing**:
`total_energy` (number, kWh) is required (Card. `1`), and Session.`kwh` is required (Card. `1`).

Caveats that matter for the CLAUDE.md 2.6 claim:
- The **Session** object's own prose says energy transfer is *not* required for a Session — a
  Session can be started purely for parking/start-tariff/reservation cost (see §Session Object:
  "That doesn't mean it is required that energy has been transferred"). But its `kwh` field is
  still Card. `1`, and only the CDR bills the outcome, with `total_energy` Card. `1`.
- A CDR *can* carry zero-energy costs via `total_time`/`total_parking_time`/`total_fixed_cost`/
  `total_reservation_cost`, and reservation/parking are first-class cost dimensions
  (`PARKING_TIME`, `RESERVATION_TIME` in CdrDimensionType; `RESERVATION`/`RESERVATION_EXPIRES`
  tariff restrictions). But there is no record type whose subject is a non-energy operation —
  the CDR is always a charging-session CDR.
- The **Commands** module (`StartSession`, `StopSession`, `ReserveNow`, `CancelReservation`,
  `UnlockConnector`) are *operations*, not completed-event records. A reservation is represented
  only as `Session.status = RESERVATION` and via `RESERVATION_TIME`/reservation tariffs — there
  is no standalone reservation record in the released spec.
- **Booking module**: `mod_bookings.asciidoc` exists **only** in tag `v2.3.0-bookings` (branches
  `2.3.0/release/bookings`, `develop-2.3.0-booking`) — it is **not** in the released 2.2.1 or
  2.3.0 (`v2.3.0` tag has no `mod_bookings.asciidoc`). It defines a `Booking` object with
  `reservation_status` (ReservationStatus enum) — a reservation *lifecycle* record, still not a
  generic completed non-energy "service event" record. (Request's "Booking module v1.1" is
  wrong — there is no v1.1 booking module; it's a 2.3.0-draft extension.)
- **Accessibility extension**: **NOT FOUND** — no accessibility file/module exists in the
  `ocpi/ocpi` repo at any tag or branch examined. H8's "Accessibility extension" is not in the
  spec repo.

→ CLAUDE.md 2.6's claim is corroborated for OCPI: nothing standardises a completed non-energy
service event, and the closest OCPI gets is reservation *lifecycle* (draft Booking module) plus
parking/reservation *cost dimensions* on an otherwise energy-bearing CDR.

## 2.3.0 → 2.2.1 delta (consolidated)

Fields that actually differ between the two conformance targets:
1. **Price class** (`types.asciidoc`): 2.2.1 `excl_vat` (number, 1) + `incl_vat` (number, ?) →
   2.3.0 `before_taxes` (number, 1) + `taxes` (TaxAmount[], *). New **TaxAmount** class:
   `name` string 1 · `account_number` string ? · `percentage` number ? · `amount` number 1.
   This changes every Price-typed field (Session.total_cost; CDR total_cost/total_fixed_cost/
   total_energy_cost/total_time_cost/total_parking_cost/total_reservation_cost).
2. **Tariff**: `min_price`/`max_price` type `Price` → **`PriceLimit`** {`before_taxes` number 1,
   `after_taxes` number ?}; **new** field `preauthorize_amount` (number ?); **new** field
   `tax_included` (TaxIncluded, 1); **new** enum `TaxIncluded` {YES, NO, N/A}.
3. **TokenType**: `_enum_` → `_OpenEnum_`; **new** value `EMAID`.
4. **Role** enum: `HUB` removed in 2.3.0.
5. **New Payments module** (`mod_payments.asciidoc`) in 2.3.0 (financial transactions; not a
   service-event record).

No field-list changes (only description/reference wording) in: Session object, CDR object,
ChargingProfile/ChargingprofilePeriod, TariffElement, PriceComponent, TariffRestrictions,
DayOfWeek, TariffDimensionType, ReservationRestrictionType, TariffType, AllowedType, WhitelistType,
ChargingRateUnit.

## Open items

None — all 7 questions answered from the `ocpi/ocpi` repo (tags `2.2.1` and `v2.3.0`). Only the
"Accessibility extension" (H8) could not be located because it does not exist in that repo.
