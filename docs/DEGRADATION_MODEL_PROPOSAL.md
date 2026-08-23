# Battery degradation model — proposal

**Asked for:** propose a degradation model from ACN-Data.

**The honest headline first: ACN-Data cannot produce a degradation model, and it is also the
wrong duty cycle for our reference sector.** What follows is a proposal that uses the real data
we actually have for the parts it can support, and marks the rest as an assumption with a
research request filed. Nothing here is built yet.

---

## 1. What ACN-Data actually is, measured from our own ingest

`ottoq_calibration_distributions`, dataset `acn_data` — 4,000 real sessions, Caltech + JPL,
2018-04-25 to 2018-07-03:

| variable | n | mean | median | max |
|---|---|---|---|---|
| `energy_delivered_kwh` | 4,000 | **9.02** | 7.50 | 47.81 |
| `charge_duration_minutes` | 3,985 | 206.2 | 151.8 | 1409.4 |
| `dwell_time_minutes` | 3,948 | 346.7 | 308.1 | 1424.3 |

**Two conclusions follow, and both matter.**

**(a) It contains no battery health data whatsoever.** Sessions in, energy out, dwell times. There
is no capacity measurement, no state-of-health, no cycle count, no pack temperature. A
degradation model cannot be *fitted* to it, only *driven* by it. Any claim that our degradation
model is "calibrated from ACN-Data" would be false.

**(b) It is workplace Level-2 charging, not a robotaxi depot.** 9.02 kWh delivered over 346
minutes of dwell is roughly **2.6 kW average** — commuters plugging in at the office. Our
robotaxi reference is 90–110 kWh packs on 150 kW DC fast chargers, arriving at 10–45% SoC and
taking 50–80 kWh per visit. **ACN's energy distribution is about 6–8× too small for our duty
cycle.** It is legitimate for dwell-time *shape* and arrival *patterns*; it is not legitimate as
the energy or C-rate distribution for a robotaxi depot, and using it that way would quietly
understate every stress term in the model.

## 2. What we *do* have that a degradation model genuinely needs

The single strongest environmental driver of battery ageing is temperature, and we have real,
local, thirty-year data for it already ingested:

| dataset | variable | what it gives us |
|---|---|---|
| `noaa_normals_1991_2020` (Nashville BNA, n=10,958) | `ambient_temp_c` per month | Jan mean **4.2 °C**, Jul mean **27.1 °C**, observed range **−27.2 … +41.7 °C**, plus per-month diurnal amplitude and AR(1) day-to-day persistence (φ = 0.72) |
| `nrel_fleet` (n≈15,000) | `daily_energy_kwh` | mean 57.8, median 49.8 — real commercial-fleet cycle depth |
| our own scenario data | pack kWh, charger kW, energy curve | C-rate and SoC band are already modelled: 150 kW into a 90 kWh pack is **1.67C**, with taper above 70% and 85% |

## 3. The proposed model

Standard two-term decomposition. **The functional form is physics; the coefficients are not ours
yet.**

```
capacity_fade  =  calendar_term  +  cycle_term
```

**Calendar term** — proceeds with *time*, worse when the pack sits hot and full:

```
calendar  =  k_cal · exp(−Ea / (R · T_pack)) · f_soc(SoC_parked) · sqrt(t_hours)
```

**Cycle term** — proceeds with *energy throughput*, worse at high charge rate and at temperature
extremes in *both* directions (cold charging drives lithium plating; hot charging accelerates
SEI growth):

```
cycle  =  k_cyc · Ah_throughput · g_rate(C_rate) · h_temp(T_pack)
```

### Why this shape is the right one for us specifically

Every input on the right-hand side is something **the scheduler controls**, and something a
throughput-maximising policy ignores:

| lever | what the scheduler decides | greedy's behaviour |
|---|---|---|
| `SoC_parked` and dwell at high SoC | charge to 80% now and top up later, vs charge to 100% and sit | charges to target as fast as possible, then parks full |
| `C_rate` | DCFC at 1.67C vs L2 at 0.12C, when the deadline permits either | always picks the fastest point available |
| `T_pack` at charge time | charge the cold pack after a warm-up, or the hot pack after dusk | ignores temperature entirely |
| `Ah_throughput` | avoid unnecessary partial cycles | no concept of it |

**This is the concrete, measurable form of the founder's thesis** — that the edge is strategic
positioning across depot variables rather than raw throughput. It stops being an assertion the
moment these four terms are in the objective.

### The part we do not have, stated plainly

`k_cal`, `Ea`, `k_cyc`, and the shapes of `f_soc`, `g_rate`, `h_temp` are **not derivable from any
dataset we hold.** They come from battery ageing literature and are chemistry-specific (NMC vs
LFP behave differently, and our `ottoq_vehicle_classes` mixes chemistries). Filed as
**`docs/research/requests/R-3-battery-degradation-coefficients.md`** for Hermes.

Until R-3 returns, any absolute fade number this model emits is `ASSUMPTION — pending R-3` and
must not appear in a customer-facing claim.

## 4. Why it is still worth building before R-3 lands

**For A/B comparison we need the model to be right in its *ordering*, not in its *absolute
level*.** Two policies that deliver the same kWh into the same fleet on the same day, but at
different charge rates, in different SoC bands, at different pack temperatures, will rank
correctly under any monotone choice of the coefficients — because the exposure differences are
real and the functional form is monotone in each of them.

So the defensible claim shape available to us pre-R-3 is:

> "Under identical demand, policy A subjects the fleet to *X%* less degradation-weighted
> exposure than policy B" — with the exposure decomposition shown.

and the claim shape that is **not** available pre-R-3 is:

> "OTTO-Q extends pack life by *N* months."

That distinction is the whole reason to file R-3 rather than pick plausible-looking constants.

## 5. What I would build, in order

1. **Exposure accounting first** — per charge session, log `(kWh, mean C-rate, SoC band entered,
   SoC band left, pack temperature proxy, hours parked above 80%)`. This is pure measurement,
   needs no coefficients, and is independently useful: it is the `ServiceDetailRecord`'s energy
   payload getting richer, which CLAUDE.md 2.6 already wants.
2. **A pack-temperature proxy** — ambient from the NOAA card, plus a rise term during fast
   charge and a decay term at rest. Crude but directionally right, and honest about being a proxy.
3. **The two-term model behind a config-swappable interface**, so R-3's coefficients drop in
   without touching call sites — the same pattern C9 used for the Recall Decision.
4. **Degradation as a term in the comparison objective**, reported next to tardiness and energy
   cost rather than folded into a single score, so the trade is visible rather than assumed.

Steps 1–2 are worth doing regardless of R-3, because they are measurement rather than modelling.
Steps 3–4 should wait for the founder's decision on the wider benchmark questions.
