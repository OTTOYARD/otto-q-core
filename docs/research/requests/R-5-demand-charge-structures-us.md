# R-5 — Demand-charge structures beyond Nashville

**Filed:** 2026-08-23
**For:** Hermes
**Blocks:** nothing immediately — the Site Profile can ship Nashville-only. This request stops it
from being *permanently* Nashville-shaped.

## Why this is needed

`ottoq_depot_tariffs` already holds the real NES GSA-3 schedule (sourced from the NES
commercial-rate PDF): $21.40/kW on the first 1,000 kW, `NCP_30min` demand basis, and a billing
floor of 30% of the prior-12-month peak. We have modelled the economics against it and the
numbers are large — roughly $261,000/year per megawatt of peak avoided, and $622,704 of exposure
from a single 30-minute excursion under the ratchet.

The Site Profile is being built as a general object. If the only tariff shape we ever encode is
Nashville's, we will hard-code one utility's structure into a supposedly portable abstraction —
the exact mistake we just spent a day undoing with the site power cap.

## Questions

1. **How much do these structures vary?** Across the major US markets where autonomous fleets
   are actually depoted — at minimum the Bay Area, LA, Phoenix, Austin, Las Vegas, Miami,
   Atlanta and Nashville — what are the commercial demand charges ($/kW/month) for a
   1–5 MW customer, and how do they differ *in shape*, not just in level?
2. **Which demand bases occur?** We model `NCP_30min` (non-coincident peak, highest
   30-consecutive-minute average). Which other bases are in use — 15-minute, coincident peak,
   on-peak-only — and roughly how common is each? **The interval length matters enormously to a
   scheduler**, so please be precise about it.
3. **Ratchets.** How common is a billing floor tied to a prior-period peak, and what are typical
   percentages and look-back windows? Ours is 30% over 12 months.
4. **EV-specific schedules.** NES offers `EVC` — no demand charge at all, 21.773 ¢/kWh flat.
   How widespread are demand-charge-free EV tariffs, are they typically time-limited or
   introductory, and do any impose a load-factor or capacity condition?
5. **The fields a portable tariff object needs.** Given 1–4, what is the minimum set of fields
   that would represent the great majority of US commercial tariffs faithfully? We would rather
   design the object around your answer than around the one tariff we happen to hold.

## Not needed

- Residential rates, wholesale market prices, or anything outside the US for now.
- Exhaustive coverage. Five or six well-sourced utilities that differ in *shape* beat twenty
  that are all the same shape.

## Answer format

`docs/research/answers/R-5-demand-charge-structures-us.md`, each question answered in order,
every figure carrying units and a source URL, and **`NOT FOUND`** where no defensible figure
exists. Where a utility's own tariff PDF and a third-party database disagree, say so and treat
the utility PDF as authoritative — that is how the NES row was handled.
