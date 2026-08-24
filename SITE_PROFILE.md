# SITE_PROFILE.md — the declarative object for THE PLACE

A pack describes the **assets** and the **work**. Nothing described the **site**, so the site's
properties leaked into code as constants. This closes that gap.

```
pack (assets + work)  +  SiteProfile (the place)  =  a complete runnable description
```

`SiteProfile` is **KERNEL**. Nothing in it names a sector. A mine, a vertiport, a yard and a
robotaxi depot each have a grid connection, a tariff, maybe storage, a layout with travel times,
an environment and maybe robotics. The declared values differ; the object does not.

---

## Why it had to exist

Four separately-proven problems trace to this one missing object:

| Problem (all previously proven) | Cause |
|---|---|
| Every committed scenario's power cap is arithmetically unreachable | the cap was a literal, unrelated to the chargers actually installed |
| The tariff never reaches the objective | there was one tariff, and it was Nashville's |
| There is no battery-buffered scenario | storage had nowhere to be declared |
| The ratchet is unmodelled | ratchets had nowhere to be declared |

The literal in question was `SITE_POWER_CAP_KW = 3000.0` in `conformance/harness.py` — a
C8-shaped, Nashville-shaped assumption wearing the costume of a kernel constant.

## The power model is two-level, and that is the point

Research answer **R-4** measured why a single scalar is the wrong abstraction:

> "Panel capacity and utility service capacity are distinct constraints. Available breaker slots
> do not guarantee that the utility service entrance, utility transformer, or distribution feeder
> has sufficient capacity."

So the binding limit is the **utility service entrance / service transformer** — utility-side —
with dedicated switchgear as a second downstream limit for DCFC above 100 kW. The profile
declares each level it knows about; `power_cap_kw()` returns the smallest after margin, and
`binding_level()` names which physical thing an operator would actually have to upgrade.

Crucially, the **sum of installed charger nameplate is a separate, larger quantity**. Their ratio
is the **oversubscription ratio**, which R-4 measures at **~2:1 to ~3.4:1** in normal practice
(band ~1.4:1 to ~7:1, the extreme being battery-buffered). Deliberate oversubscription is
standard for multi-charger depots — *but only when paired with certified load management*, which
is what this kernel is.

### What that immediately exposed

Site Alpha, our reference benchmark site, carries **1,612 kW** of installed chargers
(10×150 kW DCFC + 8×11 kW L2 + 6×4 kW AMR pad) against a **3,000 kW** cap.

> **Oversubscription ratio: 0.54:1.** Every charger on the site running flat out simultaneously
> draws barely half the cap. **No schedule can violate it.**

R-4's observed band starts at 1.4:1; Site Alpha is on the wrong side of 1.0. This is the finding
in `docs/BENCHMARK_CREDIBILITY.md` — that "zero power-cap violations" measured arithmetic rather
than scheduling — now expressed as **data the object computes**, not prose a reader must find.
`is_binding()` returns `False`, and the conformance result carries `power_cap_binds=False` so the
verdict ships with its own caveat.

`sites/profiles/site_alpha.json` preserves the defect deliberately, with a regression test that
locks it in. `site_alpha_binding.json` is the same site at R-4's central ratio (2.50:1, 7,512 kW
of chargers on a 3,000 kW service) — **that** is the profile a credible throughput benchmark
should run on.

## The tariff object is a list, not a rate

Research answer **R-5** surveyed ten schedules across nine metros. What it found:

- Demand-charge **level** spans ~$4.7/kW/mo (SRP) to ~$45/kW/mo (SCE TOU-8) — a 10× spread — and
  the **shape** varies at least as much as the level.
- The demand **interval** is a hard regional split: **15-minute** in the West/Southwest/Texas,
  **30-minute** in the Southeast (FPL, Georgia Power, NES).
- A tariff has a **list** of priced demand components. SCE has two to three, LADWP three, APS
  two, Georgia Power none plus a demand floor.

R-5's warning, quoted exactly: *"A scheduler hard-coding `NCP_30min` (Nashville's shape) will
silently mis-model every California, Arizona, Texas and Nevada depot."*

So `demand` is a list; `interval_min` is required and **has no default** (R-5 named it the field
most likely to be wrong if omitted — loading refuses a component without it); seasons and TOU
windows are declared per component; and demand is priced through a **tier ladder** so NES's
"$21.40/kW first 1,000 kW, $21.78 above" is one billed quantity in two tiers rather than two
components double-counting the peak.

Demand is computed at each component's **own interval** by averaging the load curve within it —
which is how a demand meter actually reads. Taking an instantaneous maximum instead would erase
the 15-vs-30 distinction entirely.

### The ratchet, and why it changes the scheduling problem

Same site, same peaky curve, same flattened curve, same history — two tariffs:

| tariff | ratchet | billed demand after flattening | saving from flattening |
|---|---|---|---|
| NES GSA-3 (Nashville) | 30% / 12 mo | **1,400 kW** (the real peak) | **48%** |
| Georgia Power PLL-18 (Atlanta) | 95% / 12 mo | **2,660 kW** (the floor) | **5%** |

Under a 95% floor, flattening *this* month recovers almost nothing: the money was lost when the
peak was first set, and the floor survives a year. **That asymmetry is the argument for a forward
view**, and it now falls out of the object rather than being asserted in a deck. R-5's note that
Nashville's 30% is "unusually lenient" means calibrating only against NES understates ratchet
severity by roughly 3×.

## What is declared

```
SiteProfile {
  site_id, name, timezone, notes
  grid: { service_capacity_kw*, transformer_kw, switchgear_kw,
          voltage_class, safety_margin_pct,
          upgrade_lead_time_months, upgrade_cost_usd }
  installed_charger_kw           // separate from grid — their ratio is the finding
  tariff: PortableTariff         // demand[], energy[], ratchet, TOU windows, EV carve-out
  storage: { power_kw, energy_kwh, units, round_trip_efficiency,
             soc_min_pct, soc_max_pct, recharge_counts_toward_peak }
  layout: { move_duration_min, path_capacity, dcfc_cooldown_min }
  environment: { cold_start_below_c, cold_start_penalty_min, ambient_profile }
  robotics: { arms, mate_min, demate_min, tether_release_supported }
}
```
`*` required.

### Storage is sized by energy, not power

`nashville_nes_gsa3_bess` encodes the founder's site-acquisition thesis: a 3 MW service plus
three Tesla Megapack 2 XL (real specs from `ottoq_bess_units` — 3,000 kWh / 1,500 kW each, LFP,
96% RTE, SoC 10–95%).

- Firm capacity during a wave: 3,000 + 4,500 = **7,500 kW**
- Usable energy: **7,650 kWh** → duration **1.70 h**

That duration is the correction recorded in `docs/BESS_SITE_ACQUISITION_THESIS.md`: **beyond
~1.7 h it is energy, not power, that sets the pack count**, so a 4-hour wave needs ~4.7 packs,
not 3. And `recharge_counts_toward_peak` is stated rather than assumed, because the recharge is
itself a scheduling problem. Field precedent for the pattern is Zenobē / National Express Yardley
Wood — 667 kWh BESS serving 19 e-buses on a restricted grid connection (R-4).

## Committed profiles

| profile | what it is for |
|---|---|
| `site_alpha` | C8 reference **as built** — preserves the non-binding-cap defect, regression-locked |
| `site_alpha_binding` | same site at R-4's central 2.5:1 ratio — the cap actually binds |
| `nashville_nes_gsa3_bess` | the site-acquisition thesis: 3 MW service + 3 Megapacks |
| `phoenix_aps_e35` | **portability test 1** — 15-minute interval, demand split by time of use |
| `atlanta_georgia_power` | **portability test 2** — 30-minute interval, 95% ratchet |

The last two exist to prove the object is not Nashville-shaped. If a future change makes either
unexpressible, the tariff object has regressed to a single-utility model.

## Known limitations, stated rather than approximated away

- **Georgia Power's energy structure is not modelled.** PLL-18 prices energy in declining blocks
  whose rate depends on hours-use of demand, so it has no clean $/kWh. The object carries a flat
  energy list and cannot express it; the profile's energy rate is a **placeholder, not a sourced
  rate**, and says so. The demand side — what a scheduler optimises against — is faithful.
  Extending the object needs the block table, which R-5 does not carry.
- **APS on-peak clock hours are an assumption.** R-5 supplies APS's $/kW and its 15-minute
  interval but not the window hours; 16:00–19:00 is labelled `ASSUMPTION — pending R-6` in the
  profile rather than presented as sourced.
- **Coincident-peak demand refuses to guess.** A CP component raises unless the system-peak
  intervals are supplied, because CP cannot be inferred from site load. R-5 notes CP is rare
  below transmission level.
- **NES energy excludes the TVA fuel cost adjustment** (~2.8–4 ¢/kWh), a monthly pass-through, so
  energy cost is understated by design.

## Using it

```python
from sites.site_profile import get
from conformance.harness import run_all

site = get("site_alpha_binding")
results = run_all(site)          # every pack conformance-checked against THIS place

site.headroom_report()           # ratio, binding level, storage duration, is_binding
site.tariff.bill(load_curve, month=7, historical_peak_kw=2800)
```

`conformance.harness.verify()` takes the site and reads the cap from it. `SITE_POWER_CAP_KW`
still resolves for existing callers but is now **derived** from the default profile rather than
declared — nothing needs to know that number any more.
