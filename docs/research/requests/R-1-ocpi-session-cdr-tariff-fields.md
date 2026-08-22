# R-1 · OCPI 2.2.1 field lists for Session, CDR, Tariff, Token, ChargingProfile

**Filed:** 2026-08-22 by Claude Code (build track), during Run 4 / Phase C10.
**Blocking:** the field-by-field OCPI mapping in `ADAPTERS.md` and the lossless
round-trip test in `adapters/ocpi/`.

## Why this is being asked

H7 §3.1 names `github.com/ocpi/ocpi` as the field source and marks it **adopt**, and
H8 confirms the governance path and that conformance is validated by the EVRoaming
Test Tool against **2.2.1 or 2.3.0**. Neither merged file contains the field lists
themselves. C10 requires a mapping that is field-by-field and round-trips a synthetic
session **losslessly**, which cannot be verified against a spec I do not hold.

Per CLAUDE.md Part 1 Rule 3 the mapping is being built now against clearly labelled
`ASSUMPTION — pending R-1` markers, drawn from the object shapes already implied by
our own C3 tables. Every assumed field name is marked in `ADAPTERS.md` and in the
adapter source. When this request is answered, the assumptions get reconciled and the
markers removed; any field we guessed wrong is a mapping bug, not a rename.

## Questions — precise, answerable, field-level

Please answer for **OCPI 2.2.1** (and flag any field that differs in **2.3.0**, since
H8 says both are conformance-testable and we would rather target the one with the
longer runway).

1. **Session** — the complete field list: name, type, cardinality (required/optional),
   and units where applicable. Specifically: the exact spelling and type of the energy
   field (`kwh`?), the token reference (`cdr_token`?), the location/EVSE/connector
   references, `auth_method`, `status`, `currency`, `total_cost`, `last_updated`, and
   the shape of `charging_periods[]`.
2. **CDR** — same. Specifically whether `session_id` is required, the full set of
   `total_*` cost/energy/time fields and their units (kWh? hours? minutes?), the shape
   of `cdr_location`, and the exact shape and semantics of `signed_data`.
3. **Tariff** — same. Specifically the structure of `elements[]` →
   `price_components[]` (which `type` values exist — ENERGY, TIME, FLAT, PARKING_TIME?)
   and of `restrictions` (which fields: start_time, end_time, day_of_week, min_kwh,
   max_kwh, …?), plus `min_price`/`max_price` semantics.
4. **Token** — the field list, and specifically the values `type` may take and what
   `contract_id` is keyed on.
5. **ChargingProfile / SetChargingProfile** — the field list for the *forward
   schedule* object: `start_date_time`, `duration`, `charging_rate_unit` (allowed
   values), `min_charging_rate`, and the shape of `charging_profile_period[]`
   (`start_period` units — seconds from profile start? — and `limit` units).
6. **Units and enums, explicitly.** For every numeric field above, the unit. For every
   enumerated field, the complete allowed value set. These are what a lossless
   round-trip test asserts on, and they are where a plausible guess does the most
   damage.
7. **One design question, not a field question:** does OCPI define *any* object for a
   completed **non-energy** service event, or is CDR strictly energy-bearing? Our claim
   in CLAUDE.md 2.6 is that nothing standardises service events in any sector and that
   the SDR is a CDR analogue extended to non-energy operations. If OCPI has anything in
   this space — including in the Booking module (v1.1) or the Accessibility extension
   that H8 mentions — we need to know before repeating that claim in a spec we intend
   to publish.

## What a good answer looks like

The field tables verbatim (or near-verbatim) from the spec, with a version stamp and
the source URL, so the mapping can be checked line by line. Prose summaries will not
close this request — the failure mode being guarded against is a field name that is
*almost* right.
