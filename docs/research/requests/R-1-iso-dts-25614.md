# R-1 — ISO/DTS 25614: identification, scope, and overlap assessment

Filed: 2026-08-19 · Requester: Claude Code (build track) · Priority: high — Chase has asked for a business-impact verdict; this request gates it.

## Context (why we need this)

Chase asked whether "ISO DTS 25614" causes any issues for OTTO-Q or the business model. The identifier appears nowhere in our repos or merged research (H8 covers OCPI / VDA 5050 / GMG only). The impact verdict hinges entirely on what this document actually standardizes — specifically whether it touches any of: depot/fleet charging orchestration, service-event data objects (our ServiceSession/SDR territory, brief §2.6), smart-charging profile publication, or return-to-base operations for autonomous assets.

## Questions (precise, answerable)

1. **Identification.** Exact document identifier and full title of ISO/DTS 25614. Which ISO technical committee and subcommittee owns it (e.g., TC 204, TC 22/SC 31, TC 69)? Current stage code on iso.org (DTS ballot open / approved / published as TS) and the stage date. Expected publication date if listed.
2. **Scope statement.** The verbatim scope paragraph from the ISO catalogue page (iso.org/standard/…), plus the abstract if published.
3. **Normative references.** The list of normative references — specifically whether ISO 15118 (any part), IEC 63110, ISO 17409, OCPP (via IEC 63110), or any OCPI/roaming document appears.
4. **Data objects defined.** Does it define message sets, data models, or record formats? If yes: object names, field names, units, and serialization (JSON/XML/ASN.1). We need to test overlap against: charging session records, charge detail records (CDR analogues), service/maintenance event records, charging schedules/profiles, tariff structures.
5. **Applicability.** Is it aimed at (a) vehicle↔charger, (b) charger↔backend, (c) operator↔operator, (d) fleet/depot management systems, or (e) something else entirely (note: 5-digit ISO numbers reuse ranges across unrelated TCs — confirm this is even transport/energy domain before deep-diving; if it is unrelated, e.g. materials or health informatics, say so in one line and stop).
6. **Regulatory pull.** Is ISO/DTS 25614 referenced by any regulation or procurement requirement (EU AFIR delegated acts, NEVI, national grid codes) or by OCA/EVRoaming roadmaps? A TS only bites commercially if something mandates or benchmarks against it.
7. **Conformance.** Does it define conformance/test requirements, and is there a certification program planned?
8. **Overlap verdict inputs.** For each data object it defines (Q4), one line: nearest OCPI/OCPP analogue, and whether it covers non-energy service events (cleaning, calibration, inspection, swap) or energy only. This is the single most decision-relevant fact: our §2.6 moat claim is "nothing standardizes service events in any sector."

## Deliverable

`docs/research/answers/R-1-iso-dts-25614.md` with sources (iso.org catalogue URL, TC page, any public drafts or committee press), verified-as-of date per H-file conventions.
