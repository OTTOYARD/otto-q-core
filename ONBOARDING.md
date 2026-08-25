# ONBOARDING.md — `onboard()` in sizing mode

Scheduling asks: **given this depot, how do I serve this fleet?**
Onboarding asks: **given this fleet, what depot do I need?**

Same model, inverted. And the two directions share one object:

```
                 ┌──────────────┐
   FleetSpec ───▶│   sizer      │───▶ SiteProfile ───▶ conformance harness
                 └──────────────┘         ▲                    │
                                          └────────────────────┘
                              a sized depot is immediately runnable
```

A `SiteProfile` is the **input** to scheduling and the **output** of sizing. Hand the emitted
profile to `conformance.harness.run_all(site)` and the same invariants that police a real site
police the proposed one. There is no parallel model of a depot anywhere in this.

---

## The flat-load floor

The central quantity, and the one that keeps a sizing pitch honest.

> If a fleet needs **E** kWh delivered inside a **W**-hour window, then **E/W kW** is the
> smallest possible average draw. A perfect scheduler achieves it. **Nothing beats it.**

Which means:

- Selling "we shave your peak" **above** E/W is selling real scheduling work.
- Selling it **below** E/W is selling physics that does not exist. You need storage, a longer
  window, or a smaller fleet.

The sizer computes this rather than asserting it, and **always evaluates the floor** even when a
caller's sweep steps over it — a sweep that misses the floor silently recommends buying more
service than physics requires, which is the exact overbuy this module exists to prevent.

## Worked example — Site Alpha's own three tenants

18 robotaxis, 6 electric yard tractors, 24 AMRs (opportunity-charged, 2 cycles/day), 8-hour
overnight window, 100 kW base load.

| quantity | value |
|---|---|
| Energy needed per day | **2,101 kWh** |
| **Flat-load floor** | **363 kW** |
| Unmanaged peak (everything at once) | **2,896 kW** |
| Ratio | **7.99 : 1** |
| Service points needed | 2 DCFC-class · 1 tractor · 12 AMR pads |

The unmanaged peak is what a utility sizes for **absent demonstrated load management** — R-4
quotes EPRI directly: utilities may size on "the assumption that all vehicles are charging at the
same time." That is the connection you buy if you have no scheduler.

### What that is worth, at Nashville's real tariff

| service sized at | annual operating cost |
|---|---|
| 2,896 kW (unmanaged) | **$791,661** |
| 363 kW (flat-load floor) | **$120,794** |
| **difference** | **$670,867 / year** |

### The honesty caveat, which matters more than the number

**$670,867/yr is the size of the prize, not the size of our edge.** It is the gap between
*perfect flattening* and *no management at all*. A real depot running FIFO or a greedy heuristic
lands somewhere in between — probably much closer to the floor than to the unmanaged peak.

**Our edge is OTTO-Q versus a competent naive scheduler, and that gap is narrower.** Measuring it
is the A/B benchmark's job (`policies/`), not this module's. This number bounds the total
opportunity; it must never be quoted as the delta we deliver over an alternative.

## Site selection falls straight out

Same fleet, same physics, three metros:

| metro | tariff | recommended service | annual operating cost |
|---|---|---|---|
| Las Vegas | NV Energy LGS-2 | 363 kW | **$36,218** |
| Phoenix | APS E-35 | 363 kW | **$39,626** |
| Nashville | NES GSA-3 | 363 kW | **$120,794** |
| Atlanta | Georgia Power PLL-18 | 363 kW | **$148,837** |

*(Corrected 2026-08-25 with R-6's primary tariff reads. Two corrections worth naming: the APS
on-peak window is 11:00–21:00 weekdays — not the 16:00–19:00 this repo originally assumed — and
Phoenix barely moved anyway ($39,290 → $39,626) because an overnight fleet is off-peak under
either window. Atlanta, however, went from $62,273 to $148,837: Georgia Power's real PLL-18
prices energy in declining blocks keyed to hours-use of demand, and a low-load-factor depot pays
11–19 ¢/kWh — the earlier flat 5.5 ¢ placeholder understated it 2.4×. The placeholder was
labeled as one; this is the label doing its job.)*

The TOU metros are **3× cheaper for the identical fleet** — an overnight window falls entirely
inside their cheap off-peak bands, while Nashville bills one flat $21.40/kW against the monthly
max whenever it occurs, and Atlanta's declining blocks punish low hours-use outright. **An
overnight-charging depot should strongly prefer a time-of-use tariff and should fear
hours-use-block tariffs at low load factor** — both recommendations now come out of the model
rather than out of intuition.

## The trap the model exists to catch

Storage recharge **draws from the same meter and counts toward the same monthly peak.**

A design that shaves the service window down to some target and then recharges hard overnight has
**moved its peak, not removed it.** The sizer models the recharge explicitly, spread across the
whole non-window period (the cheapest shape, and therefore the fair one to cost — a worse
recharge schedule can only make the bill higher). If recharge sets a billed peak above the
service the candidate was sized for, the candidate is marked **infeasible with the reason
stated**, not quietly costed.

This is the most expensive mistake available in a battery-buffered design, and a sizing tool that
ignored recharge would recommend it confidently.

## What it computes exactly, and what it does not

**Exact:** energy required · the flat-load floor · charge-hours and therefore point counts (given
taper) · storage energy and power to hold the grid beneath the floor · the recharge that storage
then needs and what it adds to the billed peak · operating cost at the site's real tariff.

**Not attempted:** searching over layouts, sequencing individual assets, queueing. Those are the
scheduler's job, and the sizer defers to it — every candidate it emits is a `SiteProfile` the
scheduler can be run against for confirmation.

**Deliberately not costed: capital.** R-4 gives front-of-meter service-upgrade cost at
**$2.5–2.9M** for US medium/heavy-duty truck charging facilities and **$17,500 per DCFC station**
at small sites, with **6–24+ month** lead times — surfaced as a labelled range where a grid
upgrade is implied. No defensible per-kWh storage capex exists in merged research, so it is a
caller input and its absence is reported in `SizingResult.notes` rather than papered over.

## Unservable classes are reported, not rounded away

If a single asset's session is longer than the whole window, **no point count fixes it** — an
asset charges on one point at a time. That is a window problem (or a charger-rate problem), and
`unservable_classes()` names it rather than letting a rounded-up point count look like a solved
problem.

A related bug was found by this module's own tests and fixed: the point calculation could return
**9 points to serve 7 assets**. Arithmetically that is what the division says; physically it is
nonsense. `count` is now a hard ceiling.

## Using it

```python
from onboarding.sizer import FleetSpec, FleetClass, size, to_site_profile
from sites.site_profile import get

fleet = FleetSpec(
    fleet_id="acme_depot_1", service_window_h=8.0, base_load_kw=100.0,
    classes=(FleetClass("robotaxi_a", count=40, battery_kwh=90, max_charge_kw=150),),
)

result = size(fleet, get("site_alpha").tariff)
result.summary()                    # floor, unmanaged peak, points, frontier, notes

site = to_site_profile(fleet, result, tariff_doc, site_id="acme_1", name="Acme 1")
run_all(site)                       # the proposed depot, checked like a real one
```

`FleetClass` field names match `ottoq_vehicle_classes`, which CLAUDE.md 2.3 names as the asset
profile and which is already sector-agnostic. Nothing in this module says "vehicle".
