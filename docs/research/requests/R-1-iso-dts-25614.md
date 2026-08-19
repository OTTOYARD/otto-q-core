# R-1 — ISO/DTS 25614-1: deep-dive on scope, series roadmap, and overlap with OTTO-Q

Filed: 2026-08-19 · Updated: 2026-08-19 (identification resolved; questions sharpened) · Requester: Claude Code (build track) · Priority: high

## Identification (preliminary — Chase authorized a general web search; verify all of it)

- **ISO/DTS 25614-1 — Intelligent transport systems — Orchestration of vehicles for fixed locations — Part 1: Reservation service** (iso.org/standard/90889.html), owned by **ISO/TC 204** (Intelligent transport systems).
- Stage: DTS approval phase; search snippets indicate final text received / registered for formal approval ~2026-05-08, so publication as a TS is plausibly late 2026.
- Scope (from catalogue snippet, unverified verbatim): defines the data and operating functions required to orchestrate the use of spaces (spots, bays) for road vehicles to stop for loading/unloading goods and passengers — space definition and vehicle requirements, space-to-vehicle matching, scheduling, reservation, delays, rescheduling, cancellation, queueing-in-motion. All automation levels, crewed and uncrewed; curbsides, parking lots, indoor and outdoor facilities.

This is squarely adjacent to OTTO-Q's booking/assignment layer (stalls, `ottoq_stall_bookings`, supersede/reschedule, queueing). The preliminary read is: it standardizes the *reservation* commodity layer, not service events or settlement — which supports, not threatens, the §2.6 moat claim. The questions below are what the verdict still needs.

## Questions (precise, answerable)

1. **Verbatim scope.** The exact scope paragraph and abstract of ISO/DTS 25614-1 from the ISO catalogue (iso.org blocks our fetches; capture verbatim text).
2. **Series roadmap — the decision-relevant question.** What other parts of ISO 25614 exist or are planned (registered work items, WG programme of work)? Specifically: does any planned part cover *servicing operations* at fixed locations (charging, turnaround, maintenance), service-event records, or settlement — anything that would move the series toward our ServiceSession/SDR territory? Which TC 204 working group owns it, and who proposed the NWIP (country/organization)?
3. **Data model.** Does Part 1 define concrete message sets / data objects? If obtainable from public drafts or committee material: object names, field names, units, serialization. Nearest analogues to our objects (booking, ServiceLocation capability pairs, ServiceProfile).
4. **Relationship to adjacent specs.** Stated or evident relationship to: Open Mobility Foundation Curb Data Specification (CDS), ISO 4448 (kerbside/pathway operations), Alliance for Parking Data Standards (APDS), ISO 15118/OCPP/OCPI. Does 25614-1 reference any of them normatively?
5. **Regulatory / procurement pull.** Any regulation, municipal procurement framework, airport/port authority requirement, or OEM RFP language referencing 25614 or "smart loading zone" conformance? A voluntary TS only bites commercially where something benchmarks against it.
6. **IP posture.** Any patent declarations lodged with ISO for 25614 (RAND terms)? Relevant only if we later implement the spec.
7. **Participation path.** Which national mirror committee (e.g., US TAG to TC 204 via SAE/ANSI) would OTTO-Q join to see drafts and influence later parts, and roughly what does participation cost?

## Deliverable

`docs/research/answers/R-1-iso-dts-25614.md` with sources (ISO catalogue URL, TC 204 programme of work, any public drafts/committee press), verified-as-of date per H-file conventions.
