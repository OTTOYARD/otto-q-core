# R-4 — How much charger capacity do real depots install relative to their grid connection?

**Filed:** 2026-08-23
**For:** Hermes
**Blocks:** the Site Profile's default grid connection, and therefore every benchmark that
claims to discriminate an energy-aware scheduler from a myopic one.

## Why this is needed

Every scenario and pack in this repository has a site power cap that is **arithmetically
unreachable** — sum every charge point at rated power and you still cannot hit the cap. Site
Alpha tops out at 53% of its own hard cap. The consequence, measured: the heaviest-weighted term
in our comparison objective has zero spread across policies, and a naive greedy scheduler beats
OTTO-Q because there is no scarcity to manage.

Real sites are built the other way round — you install more charger capacity than the service
drop carries and manage the difference. That is the entire premise of smart charging and
demand-charge management. **We need the real ratio, because inventing it would let us build a
benchmark that proves whatever we tuned it to prove.**

The founder could not supply this from memory and explicitly asked that it not be guessed.

## Questions — answerable, with units

1. **The headline ratio.** For operating EV depots / fleet charging hubs, what is the typical
   ratio of **total installed charger nameplate kW** to **utility service capacity kW**? A range
   with a central tendency is fine. State the sample and the sector (transit bus, last-mile
   delivery, robotaxi, drayage, municipal fleet) — we expect these to differ.
2. **Is oversubscription deliberate?** Is installing beyond the service drop standard practice,
   an exception, or forbidden by some interconnection rules? Name the constraint if one exists.
3. **What is the binding limit in practice** — the utility service drop, the transformer, the
   switchgear, or the panel? We currently model a single "site power cap"; if real sites are
   constrained at a different level, our single number is the wrong abstraction and we want to
   know now.
4. **Load management prevalence.** What fraction of such sites run active load management
   (power sharing, scheduling, curtailment) rather than static per-charger limits? A source that
   quantifies the *savings* attributed to it would be worth more than the prevalence figure.
5. **Interconnection lead times and cost.** Rough cost and calendar time to upgrade a service
   drop by, say, 1 MW in a US metro. This is the number that makes the battery-buffered
   acquisition thesis worth money — if an upgrade is cheap and fast, storage is a worse deal
   than we think, and we would rather learn that from you than from a customer.
6. **Battery-buffered charging in the field.** Any documented site that used on-site storage to
   accept a smaller grid connection than its peak demand. Sizing (kW and kWh), what it cost, and
   whether it worked. **A single credible case study here is worth more than all of the above.**

## Not needed

- Residential or single-charger installations.
- Vendor marketing claims without a named site or a measured figure.

## Answer format

`docs/research/answers/R-4-grid-oversubscription-ratio.md`, each numbered question answered in
order, every figure carrying units and source, and **`NOT FOUND` written where there is no
defensible number.** A gap we know about is worth more than a plausible value we cannot trace.
