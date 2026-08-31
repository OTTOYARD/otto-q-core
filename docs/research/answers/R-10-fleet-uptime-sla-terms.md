# R-10 (answer) — What autonomous-fleet operators actually contract for

**Answered:** 2026-08-31 · delivered by Chase into the build track
**Request:** `docs/research/requests/R-10-fleet-uptime-sla-terms.md`
**Evidence-quality labels are the researcher's own and are preserved verbatim.**

## The headline finding

**No third-party AV depot or fleet-services contract is public in any of the three segments.**
Not Waymo–Moove, not Waymo–Uber, not any yard-automation deal, not any AMR RaaS agreement.
TechCrunch asked directly and Waymo would not disclose the financial arrangement with Moove.

So for Q2, Q3 and Q4 most cells are genuinely **not public**, and the numbers that do exist come
from adjacent regulated regimes that AV depots will *inherit rather than invent*. That is the
useful part: those regimes are already drafted, already enforced, and already disagree with each
other about what they count.

## Q1 — Availability and its denominator

**Robotaxi — no published availability metric. Not one.** Waymo, Zoox and May Mobility publish
no uptime or fleet-readiness figure, and the CPUC does not ask for one. What CPUC quarterly
reporting actually requires (D.18-05-043; D.20-11-046 as modified by D.21-05-017; D.24-11-002)
is per-vehicle operational data: VMT, deadhead miles to pickup, occupancy, WAV requests, and the
time each vehicle waits between ending one passenger trip and starting the next — reported as
both a daily average and a monthly total in hours, per vehicle. D.24-11-002 added incident-level
and fleet-level stoppage-event reporting for operators exceeding 300 quarterly trips. Waymo has
claimed confidentiality over portions of every deployment report, and those fields are redacted
in the public postings. (CPUC page last updated 2026-08-18.) **Well-evidenced.**

**EV charging infrastructure — the only precise formula in public law.** 23 CFR 680.116(b)
requires each charging port to average **greater than 97% annual uptime**, calculated monthly
over the trailing twelve months:

```
mu = ((525600 - (T_outage - T_excluded)) / 525600) * 100
```

Denominator is **minutes in a year, per port**. A port counts as "up" when hardware and software
are both online *and* it actually dispenses electricity at the minimum required power level.
`T_excluded` is where the negotiation lives: utility service interruptions, failures caused by
the vehicle, scheduled maintenance, vandalism, natural disasters — plus all hours outside the
station's stated hours of operation. Effective 2023-02-28; eCFR current as of 2026-08-27.
**Well-evidenced.**

**Transit — the vehicle-side denominator.** FTA Circular 5010.1E defines spare ratio as spare
vehicles available for fixed-route service divided by fixed-route vehicles required for annual
maximum service, capped at 20% for recipients operating 50 or more fixed-route revenue vehicles;
no set ratio for rail or for smaller operators. APTA published a study in March 2025 on why
agencies increasingly cannot hit it — all-day service patterns, maintenance staffing shortages,
parts delays, aging fleets. **Well-evidenced.**

**AMR / intralogistics.** The contractual availability formula is usually **VDI 3423**
(*Technical availability of machines and production lines*, 2011-08), which defines availability
and efficiency terms for individual machines and whole production systems, including how
downtimes and consequential failure times are allocated. It is paywalled; the researcher declined
to reconstruct the formula text from memory. Its denominator is **planned utilisation time**, not
calendar time — the structurally important difference from NEVI.
**Standard confirmed; contents not verified.**

Widely repeated "95–99% RaaS uptime SLA" figures exist only in SEO/aggregator content with no
named contract behind them. **Treat as unsourced. Do not use.**

## Q2 — Readiness deadline and state

**Robotaxi: not public.** No SoC threshold, no cleanliness interval, no calibration validity
window appears in any filing, permit or contract found.

The closest primary-adjacent description is Zoox's Las Vegas operation, where trade reporting
describes a "mission readiness" team that starts up and shuts down vehicles, cleans sensors and
interiors, swaps components and charges batteries, in a depot being expanded by 190,000 sq ft.
That names the task list but no times or thresholds. **Secondary source, thin.**

**Yard / drayage: this one IS specified, by a standards body.** CVSA's Enhanced CMV Inspection
Program (board-approved 2022-09-22) establishes a **no-defect, point-of-origin inspection before
dispatch**, conducted by CVSA-trained and -certified carrier personnel, plus in-transit
inspections at a dictated interval; any vehicle or trailer failing at dispatch must be repaired
before it goes out. Reported duration is a **30–40 minute** pre-trip inspection, which then lets
the ADS-equipped vehicle bypass fixed inspection sites, backed by a 40-hour CVSA training course
and exam. That is a real "ready" definition for driverless trucking: defect-free,
certified-inspector-signed, ~35 minutes of labour per dispatch. **Well-evidenced.**

**Depot charging readiness** is described consistently across vendor sources as a "departure
readiness rate" — percentage of vehicles hitting required SoC before the dispatch window — but
every source found is a vendor blog, not a contract. **Thin.** VDV 261 is the real standard
governing e-bus / charge-point data exchange that would make such a term measurable.

## Q3 — The NULL fields, directly

| Field asked for | Verdict |
|---|---|
| `max_visit_duration_minutes` | **Not public** for any AV segment. Nearest enforced hold-time-with-a-price regime in adjacent logistics is FMC detention/demurrage, 46 CFR Part 541, effective 2024-05-28 |
| `max_queue_depth` | **Not public** |
| `max_overnight_stage_count` | **Not public as a contract term.** Exists as a land-use condition: San Francisco has required Conditional Use Authorization for "Fleet Charging" since 2022, prohibits it as an accessory use to any other principal use, and amended the controls again in May 2024 for PDR districts |
| `max_concurrent_vehicles_at_depot` | Same — zoning, not contract. Supervisors denied Waymo a permit for the Toland Street lot on 23 May |
| `return_reserve_soc_pct` | **Not public** |
| `maintenance_window_start` / `_end` | **Not public** contractually; set by CUP conditions where they exist |
| `required_services_before_deploy` | **Not public** for robotaxi. Specified for trucking by the CVSA no-defect dispatch inspection above |

**Consequence for us: these columns stay NULL.** They are not to be filled with plausible
numbers. A NULL that means "nobody has published this" is honest; a 30 that means "we guessed"
would silently become a target and then a claim.

## Q4 — Penalties

No AV depot penalty schedule is public. The shape of contracted-fleet-service penalties in the
closest analogous market — public agency to third-party operator — is documented, and it is
**tiered around a percentage threshold with a per-occurrence charge below it**, not a flat
monthly credit.

The NYC Comptroller's audit of NYCT paratransit vendor contracts (report ME09-078A; numbering
places it in the FY2009 series — old, but the structure persists) describes it precisely:
vendors hitting **95%** on-time performance for the month — **92%** in the more recent contracts
— earn **ten cents per completed trip**, while a vendor missing that threshold pays NYCT
**$10.00 for each pickup more than 15 minutes past the scheduled window**. Liquidated damages
also attach to other measures including cleanliness. The audit's own finding is worth carrying:
liquidated damages were assessed far more often than incentives were paid.

A later MTA broker award used a cleaner incentive-only structure: brokers receive 1% of trip
value for trips exceeding a 94% on-time performance threshold. Publication date unconfirmed.
**Structure well-evidenced; specific figures are transit paratransit, not AV depot.**

On the charging side the enforcement mechanism is not a credit at all — it is **federal funding
eligibility** tied to the 97% floor.

## Q5 — The one number

Honest answer: **for AV depots nobody has published it**, so it cannot be named from a primary
source. What can be said is that the three regimes that will actually bind us count three
different things, and they do not reconcile:

- **NEVI counts port-minutes** — asset-side, calendar denominator, generous exclusions.
- **FTA counts vehicles-required-at-maximum-service** — fleet-side, peak-demand denominator, no exclusions.
- **VDI 3423 counts planned utilisation time** — schedule-side.

Every operational account found — transit, e-bus depots, paratransit — converges on the same
daily question in different words: **what fraction of the vehicles the schedule demanded were
actually out the gate, fit to work, at the clock time the schedule demanded them?** That is
*pull-out performance* in transit, *departure readiness rate* in e-bus depots, and has no
published name at all in robotaxi.

> **The denominator is the negotiation, not the target percentage.** A 97%-style commitment
> measured over calendar minutes per charging port is a completely different obligation from 97%
> of peak-hour vehicle requirement, and NEVI's `T_excluded` list shows exactly how much risk a
> well-drafted denominator moves off the operator.

Researcher's recommendation, adopted: **instrument fleet-ready-at-named-clock-time with a
defensible exclusion ledger** — the number that translates into every one of these regimes, and
the one we will be asked to warrant when a customer finally writes the SLA that does not exist
yet.

**Thinnest areas, as stated:** everything in Q3, the "one number" for robotaxi specifically, and
any RaaS uptime figure. **Strongest:** the NEVI formula, FTA spare ratio, CPUC reporting fields,
and the CVSA dispatch inspection.

## What this changes in the build

1. **We are missing a KPI, and it is the one everybody actually manages to.** The five canonical
   KPIs measure throughput, cost and latency. None of them answers "what fraction of the assets
   the schedule demanded were ready at the demanded clock time." That is a sixth KPI —
   commitment-shaped, not calendar-shaped — and on this evidence it outranks the other five for
   a customer.
2. **Availability is meaningless without a recorded exclusion set.** NEVI's `T_excluded` is not a
   footnote, it is the contract. Any readiness number we publish needs a per-interval ledger of
   what was excluded and why, or it cannot be defended in a negotiation. We have no such ledger
   today.
3. **The denominator must be an explicit, stored parameter**, not a convention buried in a view.
   The same fleet yields three different "availability" numbers under NEVI / FTA / VDI 3423
   denominators, and a customer will name which one they mean.
4. **`ottoq_fleet_operator_slas` NULLs stay NULL** pending a real customer term sheet. Filling
   them from this document would be inventing contract terms, which is the failure mode this
   request existed to avoid.
5. **CVSA gives the yard-logistics pack a real, sourced readiness definition** — defect-free,
   certified-inspector-signed, ~30–40 min pre-dispatch — which is the first non-invented
   `required_services_before_deploy` value we have for any pack.

Items 1–3 are build work and are **not** started on the strength of this file alone; they are
proposed to Chase first, because a new KPI changes what the CI gate asserts.
