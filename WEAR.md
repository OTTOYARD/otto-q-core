# WEAR.md — the derived degradation layer

Exposure capture already worked. A 20-tick run produces 61 OCPP sessions and 187
ServiceDetailRecords carrying `soc_start`, `soc_end`, `energy_delivered_kwh`,
`peak_power_kw` and `ambient_temp_c`. **The gap was never capture — it was the derived layer**
that turns those columns into a number a scheduler can optimise. This is that layer.

**Nothing here is calibrated on simulation output.** The coefficients are literature (research
answer R-3); the exposure is whatever SDRs it is handed. Point it at a real depot's SDRs and it
works identically — which is the requirement: the intelligence layer must never learn the
simulator's habits.

---

## The two levers

R-3's headline finding for us, and the reason this module is small rather than general:

> The **cold charge** (lithium plating) and the **high-SoC park** (calendar fade) are the two
> things a *depot scheduler* can actually pull.

Discharge rate barely matters and we don't control it. Ambient temperature we don't control
either. What we control is **when** a vehicle charges (therefore how cold it is) and **what SoC
it sits at** between shifts. Both have peer-reviewed effect sizes. So this module optimises
exactly two things and says so, rather than presenting a general-purpose battery model we can't
support.

| lever | what it's worth | how it's modelled |
|---|---|---|
| Park at 50% instead of 100% | **4.0× less calendar fade** (NMC), 2.0× (LFP) | `soc_park_saving()` |
| Avoid cold fast-charge | up to **35% capacity loss** observed at −10/−20 °C | `plating_risk()` — a regime |

## Provenance is a first-class field

Every coefficient carries its source and how well supported it is. **A number whose source
cannot be checked is a number that will eventually be quoted as fact**, so this is the same
discipline as the pack mechanism registry.

| tag | meaning |
|---|---|
| `primary` | peer-reviewed experiment or model |
| `review` | peer-reviewed survey |
| `inference` | R-3's own synthesis across sources, explicitly flagged there |
| `not_found` | no defensible value exists — **the model refuses rather than guessing** |

`provenance_report()` prints the whole ledger, including `refuses_to_compute`.

### What the model refuses to compute

Two things, both because R-3 records them as NOT FOUND:

- **A smooth charge-side rate multiplier.** R-3 Q4: no clean charge-only normalised table exists
  in any single source, and the physically correct, scheduler-actionable behaviour is to **gate**
  the cold-fast-charge regime, not curve-fit it. So `plating_risk()` returns `severe` / `elevated`
  / `none` — a regime, not a coefficient. Inventing a smooth curve here would be inventing the
  exact number R-3 says does not exist.
- **A normalised `h_temp` table across −10→50 °C.** The U-shape with its ~25 °C minimum is primary
  (Waldmann 2014); the multiplier table is not.

Requesting either raises `NotFoundError`.

### What rests on inference, and is labelled everywhere it surfaces

The `f_soc` multipliers. R-3 Q2 is explicit: the **shape** (plateau → step at ~60% SoC for NMC,
~70% for LFP → steep rise at 100%) is primary literature (Keil 2016), but the **numeric
multipliers** are R-3's own read — *"no single source tabulates a clean normalised multiplier
series … treat these as order-of-magnitude placeholders and calibrate against your cell."*

So every `WearAssessment` computed with a parked period carries an `inference_flags` entry, and
`as_row()` exposes `rests_on_inference`. **The weakest number in the model must not look like the
strongest.**

## Coefficients

| item | value | provenance | source |
|---|---|---|---|
| NMC activation energy | 90,700 J/mol | primary | Ecker 2012, doi:10.1016/j.jpowsour.2012.05.012 |
| LFP activation energy | 62,000 J/mol | primary | Schimpe 2018, doi:10.1149/2.0161802jes |
| `f_soc` multipliers | table | **inference** | shape: Keil 2016, doi:10.1149/2.0411609jes |
| time exponent | 0.5 (√t) | primary | Keil 2016 |
| discharge `g_rate` | 1.0 | primary | Preger 2020, doi:10.1149/1945-7111/abae37 |
| charge `g_rate` (smooth) | — | **not_found** | R-3 Q4 |
| `h_temp` table | — | **not_found** | R-3 Q5 |
| cold-charge capacity loss | 0.35 | review | Yarimca 2024, doi:10.3390/batteries10110374 |

### One caveat worth stating

NMC's Ea of 90.7 kJ/mol sits at the **top** of R-3's reported spread (30–90 kJ/mol across
chemistries, average ≈60). It's the canonical Ecker/Schmalstieg value for the graphite/NMC cell
family, so it is the right default — but it makes the model temperature-sensitive: it implies
**5.77× the calendar fade at 40 °C versus 25 °C**, steeper than the common "2× per 10 °C" rule of
thumb. Calibrate against the actual cell before quoting an absolute figure.

### Time exponent

R-3 Q3 confirms √t is the SEI-limited form and the right default for a 12-month horizon — while
noting the two most-cited *empirical* fits (Ecker 2012, Schmalstieg 2014) use **0.75**, and that
beyond ~3 years an additive linear term is needed. Hence `time_exponent` is a parameter, not a
hard-coded 0.5.

## Using it

```python
from wear.degradation import ExposureRecord, assess, provenance_report, soc_park_saving, NMC

records = [ExposureRecord(asset_id="v1", chemistry="NMC", battery_kwh=90,
                          soc_start_pct=22, soc_end_pct=88, energy_delivered_kwh=59.4,
                          peak_power_kw=100, ambient_temp_c=4.0, duration_h=0.8)]

for a in assess(records, parked_hours=10, parked_soc_pct=88):
    print(a.as_row())          # cycles, calendar fade, plating events, rests_on_inference

soc_park_saving(NMC, from_soc_pct=100, to_soc_pct=50)   # 4.0
provenance_report()                                      # the whole ledger
```

`ExposureRecord`'s fields map one-to-one onto what an SDR already carries, so wiring this to
production data is a query, not a migration.
