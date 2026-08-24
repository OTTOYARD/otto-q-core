# R-3 — Battery degradation coefficients for a depot scheduling objective

**Answer to request:** `docs/research/requests/R-3-battery-degradation-coefficients.md`
**Answered by:** Hermes research subagent · **Date:** 2026-08-24
**Status:** COMPLETE (Q1–Q7 answered; explicit `NOT FOUND` where literature gives no defensible number)

---

## Scope & how to read this

The model to parameterise (from the request):

```
calendar = k_cal · exp(−Ea / (R · T_pack)) · f_soc(SoC_parked) · sqrt(t_hours)
cycle    = k_cyc · Ah_throughput · g_rate(C_rate) · h_temp(T_pack)
```

Every figure below carries units and a citable source, tagged **primary**
(peer-reviewed experiment/model), **review** (peer-reviewed survey), **standards**
(institutional report), **trade-press**, or **inference** (my synthesis across the above —
always flagged, never presented as a measured value). Chemistry split is NMC / LFP where the
literature distinguishes them.

The single most important finding for the scheduler is **Q5/Q7**: the *cold* charge (lithium
plating) and the *high-SoC park* (calendar fade) are the two levers a depot scheduler can
actually pull, and both have peer-reviewed effect sizes in the 44–130 % lifetime range (SoC
capping) and ~7–8 % cost range (depot charging optimisation).

---

## Answers

### Q1 — Calendar ageing activation energy `Ea` (kJ/mol) and reference temperature

**NMC (graphite/NMC):** `Ea ≈ 0.94 eV ≈ 90.7 kJ/mol`. The reference temperature the fitted
`k_cal` assumes is **25 °C (298.15 K)** — the Arrhenius fits are normalised to 25 °C.

- Source: Ecker et al. 2012, *J. Power Sources* **215**, 248–257, doi:10.1016/j.jpowsour.2012.05.012
  (**primary**; the canonical NMC lifetime-prediction model). Schmalstieg et al. 2014,
  *J. Power Sources* **257**, 325–334, doi:10.1016/j.jpowsour.2014.02.012 (**primary**) uses the
  same cell family and a consistent value.

**LFP (graphite/LFP):** `Ea ≈ 62 kJ/mol (≈ 0.64 eV)` — adopted from calendar-ageing data of a
different cell, not independently re-fitted.

- Source: Schimpe et al. 2018, *J. Electrochem. Soc.* **165**(2) A181–A193,
  doi:10.1149/2.0161802jes (**primary**; LFP degradation-mechanism model). ⚠ Caveat: this is an
  *adopted* value, and LFP calendar Ea is reported lower than NMC's elsewhere.

**Spread across chemistries / SoC (do not treat Ea as a single constant):**
30–90 kJ/mol (0.31–0.94 eV), average ≈ 60 kJ/mol (0.62 eV), and Ea rises with storage SoC.

- Source: Theiler et al. 2021, *Batteries* **7**(2):22, doi:10.3390/batteries7020022 (**review**).
  Corroborated at cell level by the 232-cell dataset in Lam, Chueh et al. 2025, *Joule* **9**(1),
  101796, doi:10.1016/j.joule.2024.11.013 (**primary**), where Ea clusters near ~1 eV for NMC-type
  cells and lower for LFP.

**Use in the model:** with `R = 8.314 J/(mol·K)`, take `Ea = 90.7 kJ/mol` (NMC) and
`Ea = 62 kJ/mol` (LFP) at `T_ref = 298.15 K`. If you fold the SoC-dependence of Ea into
`f_soc(SoC)` instead of the exponential, keep `Ea` constant at the 50 %-SoC value above.

### Q2 — `f_soc(SoC)`: storage-SoC dependence of calendar fade (normalised table)

The traceable fact is that calendar fade is **not monotonic in SoC** — it shows **plateaus**
(flat fade over 20–30 % SoC bands), a **step**, and a **steep rise at 100 % SoC** (NMC):

- The step (onset of faster fade) sits at **~60 % SoC for NMC/NCA** and **above ~70 % SoC for
  LFP** — it corresponds to the half-lithiated-graphite stage transition, not a smooth curve.
- NMC shows a **steep additional rise at 100 % SoC**; LFP's 100 % rise is milder.
- Minimum fade is at low-to-mid SoC. "For long-term storage, the graphite anode should be
  lithiated less than 50 %."

  Source: Keil et al. 2016, *J. Electrochem. Soc.* **163**(9) A1872, doi:10.1149/2.0411609jes
  (**primary**; calendar aging of NCA/NMC/LFP at 16 SoCs and 25/40/50 °C — the definitive
  SoC-dependence dataset).

**Normalised table (approximate engineering values, normalised to 50 % SoC = 1.0):**

| SoC_parked | NMC `f_soc` | LFP `f_soc` |
|-----------:|------------:|------------:|
| 30 % | ≈ 1.0 | ≈ 1.0 |
| 50 % | **1.0 (ref)** | **1.0 (ref)** |
| 70 % | ≈ 1.5–2 | ≈ 1.0–1.5 |
| 80 % | ≈ 1.5–2 | ≈ 1.5 |
| 90 % | ≈ 2 | ≈ 1.5–2 |
| 100 % | ≈ 3–5 | ≈ 2 |

⚠ **Label: inference.** The *shape* (plateau → step → 100 % rise, and the step positions) is
primary literature (Keil 2016). The *numeric multipliers* are my read of Keil 2016 Fig. 2 and the
linear-in-OCV form used by Schmalstieg 2014 / Naumann 2018 — **no single source tabulates a clean
`30/50/70/80/90/100 %` normalised multiplier series**, so treat these as order-of-magnitude
placeholders and calibrate against your cell. A defensible engineering surrogate is
`f_soc ∝ OCV(SoC)` (Schmalstieg 2014), which reproduces the monotonic rise above the step but
misses the 100 %-SoC cliff — include the cliff explicitly for NMC.

Key scheduling consequence: **parking at 50 % instead of 90–100 % SoC cuts calendar fade by
roughly 2–5× for NMC** (the exact ratio is cell-specific — see Q7 for the peer-reviewed fleet
effect size).

### Q3 — Time exponent: is `sqrt(t)` correct for the first 1–3 years?

**Yes — `sqrt(t)` (exponent 0.5) is the accepted SEI-limited form**, and is the correct default
for the first ~1–3 years of calendar aging:

- SEI growth is diffusion-limited, so thickness (and hence lithium loss) grows **∝ √t**; this is
  the standard mechanistic assumption. Keil et al. 2016 (doi:10.1149/2.0411609jes, **primary**):
  "the overall trend exhibits a square-root-of-time behaviour … in good correlation with SEI
  growth, for which a linear increase with the square root of time is generally assumed."
  Corroborated by Edge et al. 2021, *Phys. Chem. Chem. Phys.* **23**, 8200 (**review**): "the SEI
  growth rate approximately correlates with the square root of time."

**However, the two most-cited *empirical* calendar models use exponent 0.75**, not 0.5:

- Ecker et al. 2012 (doi:10.1016/j.jpowsour.2012.05.012) and Schmalstieg et al. 2014
  (doi:10.1016/j.jpowsour.2014.02.012) both fit `capacity_fade ∝ t^0.75` over the first years —
  a better empirical fit because early fade combines SEI growth with other mechanisms.

**Longer times trend toward linear (`t^1.0`).** The standard reconciliation is a two-term form
`Q_cal = k1·t + k2·√t` (e.g. Redondo-Iglesias et al. 2018, *J. Energy Storage* **17**, 153,
doi:10.1016/j.est.2018.09.002, **primary**).

**Recommendation:** keep `sqrt(t_hours)` as specified — it is defensible and matches the SEI
physics — but be aware that (a) the most-cited empirical fits use 0.75, and (b) beyond ~3 years
you may need the additive linear term. For a 12-month depot horizon, `√t` is the right choice.

### Q4 — `g_rate(C_rate)`: relative cycle fade vs charge C-rate (normalised to 1C)

**Discharge side: the dependence is weak — `g_rate ≈ 1` across 0.1–2C.**

- Source: Preger et al. 2020, *J. Electrochem. Soc.* **167**(12) 120532,
  doi:10.1149/1945-7111/abae37 (**primary**; commercial NMC/NCA/LFP, multi-year cycling):
  "discharge rate dependence for NMC and LFP cells appears low."

**Charge side: the rate effect is dominated by lithium plating (low T, high SoC), not a smooth
monotonic multiplier — a clean charge-only normalised table is `NOT FOUND` in a single source.**

Two traceable pieces to use instead:

1. **Engineering-standard form** (rate enters as an *effective activation energy*):
   `Q_loss = B · exp(−(Ea + η·C_rate)/(R·T)) · Ah^z`. Wang et al. 2011, *J. Power Sources*
   **196**(8) 3942–3948, doi:10.1016/j.jpowsour.2010.11.134 (**primary**, graphite/LFP):
   `Ea = 31.7 kJ/mol`, `z ≈ 0.55`. This is the cleanest literature `g_rate` to drop into the model.
2. **Combined charge+discharge anchor** (single number, both rates together): cells cycled
   1C/1C reached 20 % SOH loss in 172 cycles vs **81 cycles at 2C/2C** (~2× faster fade).
   Source: *Energies* **18**(2):342 (2025), doi:10.3390/en18020342 (**review**), citing Lecompte et
   al. ⚠ Conflates charge and discharge rate.

**Recommendation:** model `g_rate ≈ 1` for discharge; for charge, do **not** use a smooth
multiplier — instead gate the cold-fast-charge regime (Q5) with a step penalty for plating, which
is the physically correct and scheduler-actionable behaviour. If you need a continuous charge-side
factor, use the Wang 2011 `exp(−η·C_rate/(R·T))` form (charge-side η not independently tabulated —
`NOT FOUND`).

### Q5 — `h_temp(T)`: relative cycle fade vs pack temperature (cold end = the lever)

Cycle fade vs temperature is **U-shaped**, with the minimum near **25 °C** and faster fade both
colder (lithium plating) and hotter (SEI/electrolyte decomposition).

- Source: Waldmann et al. 2014, *J. Power Sources* **262**, 129–135, doi:10.1016/j.jpowsour.2014.03.112
  (**primary**; 18650 NMC/LMO cycled at 1C from −20 to 70 °C — the canonical temperature-dependence
  study, and the origin of the "plating ↔ SEI ↔ breakdown" mechanism map). Exact normalised
  multipliers are not tabulated cleanly across −10→50 °C in a single citable table — `NOT FOUND`
  as such; use the anchors below.

**Cold end (the lever your scheduler can actually pull):**

- **Up to ~35 % degradation** observed at −10 and −20 °C, where lithium loss converts to plating
  (dendrites raise resistance and cut capacity). Source: Yarimca et al. 2024, *Batteries*
  **10**(11):374, doi:10.3390/batteries10110374 (**review**).
- **NMC 21700 fast-charged at −20/−10/0 °C loses lifespan dramatically even at *nominal* charge
  current.** Source: Lecompte et al., cited in *Energies* **18**(2):342 (2025) (**primary**).
- **LFP shows a "tipping point" at 5–10 °C**: below it, cold/plating dominates; above it, hot-ageing
  dominates. Source: Preger et al. 2020 (doi:10.1149/1945-7111/abae37, **primary**).
- Plating threshold in practice: charging at **≥ ~0.5C below ~0–10 °C** risks plating; **below 0 °C
  even moderate rates** do. Sources: Tesla Motors Club operational guidance (**trade-press**);
  Lecompte et al. (**primary**).

**Hot end:** in the 15–35 °C band, LFP cycle fade ranked **35 °C > 50 °C > 25 °C** and fade
*increased* with temperature for LFP but *decreased* for NMC (different dominant mechanisms).
Source: Preger et al. 2020 (**primary**).

**Scheduler translation (inference):** `h_temp` should not be a symmetric U — make the **cold
branch conditional on charge rate/SoC** (plating only bites when you *charge* cold), while the hot
branch is a smooth Arrhenius-like increase in `exp(−Ea_cyc/(R·T))`. Recommended functional form:
`h_temp = exp(−Ea_cyc/R · (1/T − 1/298.15))` for T ≥ ~10 °C (with `Ea_cyc ≈ 31.7 kJ/mol`, Wang
2011, primary), plus a **step penalty for charging below ~10 °C** that scales with C-rate. This
models cold charging as "sharply bad when you fast-charge cold", not merely "less bad than hot".

### Q6 — `k_cal` / `k_cyc` magnitudes — a defensible 12-month anchor point

Portable SI constants for `k_cal` and `k_cyc` are **cell-specific and not cleanly tabulated** as
single transferable numbers — `NOT FOUND` as such. The anchor point (which the request says is
sufficient) is instead given as % capacity fade, built from primary sources:

**Anchor scenario:** 1 full-equivalent cycle/day (= 365 EFC/yr), 25 °C pack, 1C charge, parked at
90 % SoC, 12 months.

| Component | NMC | LFP | Source (label) |
|---|---|---|---|
| Calendar @25 °C | ~2–3 %/yr (at 90 % SoC, above the 60 % step) | ~1–2 %/yr (LFP: ≈0.2 pp/month at 25 °C mid-SoC → ~2.4 pp/yr; slightly higher at 90 %) | Keil 2016, doi:10.1149/2.0411609jes (**primary**); Ecker/Schmalstieg models (**primary**) |
| Cycle @1 EFC/day | 365 EFC out of 200–2500 EFC to 80 % → ~3–20 %/yr | 365 EFC out of 2500–9000 EFC to 80 % → ~0.8–3 %/yr | Preger 2020, doi:10.1149/1945-7111/abae37 (**primary**) |
| **12-month total (all-in)** | **~5–8 % capacity fade** | **~2–4 % capacity fade** | **inference** (sum of above) |

Cross-check against real fleet data: **2.3 %/yr average** capacity loss across 22,700 light-duty
EVs (2020 study and 2025/2026 update; best models ~1.8 %/yr), with fast-charging behaviour a key
driver. Source: Geotab 2026 telematics study (**trade-press**; real-world, mixed duty cycle, so a
lower bound for a hard-worked depot pack).

**How to back out `k_cal` / `k_cyc` from the anchor (recipe):**

```
k_cal = (calendar_fade_fraction) / [ exp(−Ea/R·(1/T − 1/298.15)) · f_soc(SoC) · sqrt(t_hours) ]
k_cyc = (cycle_fade_fraction) / [ Ah_throughput_EFC · g_rate(1C) · h_temp(25 °C) ]
```

evaluated at the anchor: `Ea` from Q1, `f_soc(90 %)` from Q2, `sqrt(8760 h) ≈ 93.6 h^0.5`,
`g_rate(1C) = 1`, `h_temp(25 °C) = 1`. This yields chemistry-consistent `k` values in your model's
own units without inventing a number — every input is traceable above. (Working the arithmetic is
deferred to the caller; the inputs are the deliverable here.)

### Q7 — Published depot/fleet-scale study on degradation vs charging strategy (with effect size)

**Yes — three citable findings, in increasing order of depot relevance:**

1. **Depot-scale, peer-reviewed, with a cost effect size.** "Joint optimization of vehicle
   scheduling and charging strategies for electric buses to reduce battery degradation",
   *J. Renewable Sustainable Energy* **16**(4), 044704 (2024) — also *IEEE Trans. Intelligent
   Transportation Systems* **25**(6), 6212–6225 (2024). **Effect: adjusting scheduling + charging
   strategy cuts battery-degradation cost by 7.45 % and total cost by 6 %** (despite slightly
   higher charging cost). (**primary**)

2. **SoC-limited charging, peer-reviewed, with a *lifetime* effect size — the single most useful
   number for your objective.** Wikner & Thiringer 2018, "Extending battery lifetime by avoiding
   high SOC", *Appl. Sci.* **8**(10):1825, doi:10.3390/app8101825. **Effect: capping charge at
   50 % SoC (vs full) increased EV battery lifetime expectancy by 44–130 %.** Directly confirms
   the Q2 calendar-fade lever at vehicle level. (**primary**)

3. **Strategy review (nine best practices) backing deferred charging + SoC management.**
   Woody et al. 2020, "Strategies to limit degradation and maximize Li-ion battery service
   lifetime", *J. Energy Storage* **28**, 101231, doi:10.1016/j.est.2020.101231. Quantifies how
   deferred charging, SoC windows, and temperature management map to service-life gains.
   (**primary**, review)

**Trade-press corroboration (use for narrative, not as the citation of record):**

- Zenobe (bus fleet operator): charging-strategy modelling "can delay replacement of the first
  battery in a fleet of 50 double-deck buses by up to three years" (**trade-press**).
- Geotab 2026 (22,700 EVs): charging behaviour is an emerging key degradation driver; fleet
  average 2.3 %/yr (**trade-press**, telematics).

**Bottom line for the objective:** the peer-reviewed effect sizes to anchor a policy-comparison
term are **44–130 % lifetime gain from SoC-capped charging** (Wikner & Thiringer 2018) and
**~7.45 % degradation-cost saving from coordinated depot scheduling** (JRSE/IEEE 2024). Cold-charge
pre-conditioning (Q5) is the third lever; its quantitative fleet-scale effect is **`NOT FOUND`** as
a published depot study — the supporting evidence is cell-level (Waldmann 2014; Lecompte et al.).

---

## Open items

1. **`f_soc` exact normalised multipliers** — no single source tabulates 30/50/70/80/90/100 %;
   calibrate against the specific cell (the *shape* is solid, the *numbers* are inference).
2. **Charge-only `g_rate(C_rate)` table** — `NOT FOUND`; use Wang 2011 form + plating gate.
3. **`h_temp` cold-branch magnitude** — qualitative/anchored, not a clean −10→50 °C multiplier
   table; cell- and rate-specific.
4. **`k_cal`/`k_cyc` as portable SI constants** — `NOT FOUND`; anchor point + recipe provided.
5. **Fleet-scale effect of thermal pre-conditioning** on degradation — no published depot study
   found; cell-level only.
