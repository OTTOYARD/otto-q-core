# R-7 — eVTOL and drone turnaround parameters for the multimodal scenario

**Filed:** 2026-08-24 · **Answered:** 2026-08-25 · **Status:** final (sources verified 2026-08-25)

Scope: replace the engineering placeholders in `solvers/cpsat/scenario_vertiport.json` with
sourced figures. Where no defensible primary number exists, `NOT FOUND` is written rather than a
plausible guess — the placeholders stay labeled rather than quietly promoted. Labels: **(a)**
primary/official (OEM spec sheet, FAA/EASA doc, operator filing), **(b)** standards body,
**(c)** trade press/analyst, **(d)** inference.

The single most important structural fact: **eVTOL "turnaround" is dominated by energy transfer
(charge), not by aircraft handling.** Aircraft handling is seconds-to-minutes (they hover/air-taxi
under their own power — no tug required, see H-B §5). Charging is 10–55 minutes depending on OEM.
So the schedule is a *charger/kW allocation problem*, not a ground-crew problem.

---

## Q1 — eVTOL charge / turnaround per named aircraft

| Aircraft | Usable battery (kWh) | Charge power on pad | Turnaround / charge time | Swap? | Standard |
|---|---|---|---|---|---|
| **Joby S4** | **~125 kWh** (Aviation Week est.) / **~150 kWh** (derived at NASA-NTRS 200 Wh/kg pack bound) | **150–1000 VDC, up to 300 A/channel** (GEACS charger) → ~300 kW/channel (d) | "a matter of minutes" per GEACS (4 isolated packs, 2 ports) | No (charge) | Joby GEACS (proprietary charger, CCS-influenced) |
| **Archer Midnight** | **~75 kWh** (6× 800 V packs, ~260 Wh/kg) | 800 V architecture | **~10 min** for a ~20-mile hop; "as little as 12 min between sorties" | No (charge) | CCS-type (800 V) |
| **Beta ALIA** | **~220 kWh** total (multiple 45-kWh packs, 832 V max) | 400+ kW peak / 115 kW continuous | **~50 min full charge** | No (charge) | Proprietary (Beta Charge Cube, CCS) |
| **Lilium Jet** | **~300 kWh** (10 packs) | **350 kW** | **~55 min full charge** | No (charge) | Proprietary |
| **Volocopter VoloCity** | (not published as total kWh — 9 swappable packs) | — | **swap ~5 min**, or fast-charge ~40 min | **Yes (swap)** | VoloPort swap + charge |

**Charge vs swap — who plans swap:** Only Volocopter (VoloCity) plans battery swap as the primary
turnaround method (5 min swap, confirmed by Volocopter's own site and AAM trade listings). Joby,
Archer, Beta, and Lilium all charge in place. So for the multimodal scenario, **swap is the
exception, not the default** — model it as a per-type boolean, default `false` (matches H-B §4).

**Sources (per row, primary-first):**
- Joby: evtol.news S4 spec (cell 288 Wh/kg / pack 235 Wh/kg); Aviation Week "125 kWh anticipated";
  Joby GEACS charger PDF; Fethi Chebil substack (150 kWh at 200 Wh/kg pack bound). (a/c)
  https://evtol.news/joby-aviation-s4-production-prototype · https://joby-site.cdn.prismic.io/joby-site/5f82ea34-645e-4468-8e3f-14a16e298941_Joby-Charging-GEACS-final.pdf
- Archer: AIN "six 800-volt battery packs"; evtol.travel (~75 kWh, 260 Wh/kg, 10–12 min to 80%);
  Archer press (12 min between sorties). (a/c) https://www.ainonline.com/news-article/2022-11-18/archer-details-motor-and-battery-design-midnight-evtol-air-taxi
- Beta: beta.team/battery (45 kWh nameplate, 832 V max, 400+ kW peak, 115 kW continuous);
  evtol.travel (~220 kWh total). (a/c) https://beta.team/battery
- Lilium: Leeham "2,200 kW and 300 kWh"; air-dynamic "10 packs, 350 kW, ~55 min". (c)
  https://leehamnews.com/2022/07/29/bjorns-corner-sustainable-air-transport-part-30-lilium-jet-vtol/
- Volocopter: volocopter.com VoloCity ("9 batteries, battery swapping enables rapid turnaround");
  aeroautosales (swap 5 min / fast-charge 40 min). (a/c) https://www.volocopter.com/en/solutions/volocity

**Note on Joby's two kWh figures:** Aviation Week's 125 kWh is the older public estimate; the
150 kWh figure is *derived* from NASA-NTRS pack-energy-density bounds. For a scenario JSON, use a
**~125 kWh nameplate with a ±20% band** and flag it (d); the difference matters because charge time
≈ kWh ÷ charger kW.

---

## Q2 — Pad occupancy and separation

Already covered in H-B (merge that dossier's §2–3 with this answer). The R-7-specific placeholder
is `min_gap_min = 6`.

1. **Minimum pad occupancy per movement:** no regulator publishes a *time* minimum — the criteria
   are geometry (FATO/TLOF size) + downwash *velocity-distance* (not time). Occupancy is best
   modeled as `approach + touchdown + energy-transfer (dominant) + clearance + departure`.
   (a) H-B §3–4.

2. **Separation/clearance between successive aircraft on the same pad (`min_gap_min`):**
   **NOT FOUND as a published time.** No FAA/EASA document gives a seconds/minutes figure. The
   regulators use velocity-distance criteria (FAA DCA 34.5 mph threshold; EASA 60 km/h at 2 D
   circle). A **6-minute gap is a reasonable engineering placeholder** but is *not* sourced — keep
   it labeled as inference (d), and if it must be a time, derive it from "downwash settle to below
   threshold" which itself has no published number (H-B §3 "settle time NOT FOUND").

3. **Pads-per-gate / pad-to-stand tug-taxi:** EASA C.320 — aircraft can power-in/push-back **under
   their own power or using a tug**; air-taxi <37 km/h ground effect. No tug required by default.
   (a) H-B §5. Pad-to-stand repositioning time = short (seconds-to-minutes), NOT FOUND as a
   published per-move figure.

---

## Q3 — Schedule slack (announced route block times)

The `ready_by` slack placeholder (65–85 min arrival-to-ready) is **very generous vs. the actual
numbers** — real eVTOL hops are ~10 min with ~10–12 min charge turnaround, so a landed aircraft is
ready again in ~15–25 min, not 65–85. The 65–85 min is conservative *airline-style* slack, defensible
for a first demo but looser than the physics.

| Route | Block time (published) | Source (label) |
|---|---|---|
| Joby/Delta — Manhattan ↔ JFK | **~7 min** flight ("under 10 min") | (a) Joby press https://www.jobyaviation.com/news/joby-brings-electric-air-taxis-to-new-york-city-in-week-long-flight-campaign |
| Joby — Dubai (DXB ↔ Palm Jumeirah) | **~10–12 min** | (a) RTA/Joby/ertico https://ertico.com/rta-and-joby-aviation-complete-first-crewed-electric-aerial-taxi-flight |
| Joby — OAR↔MRY (demonstrated) | **~12 min over 10 nm** (incl. 5 min hold) | (a) Joby https://www.jobyaviation.com/news/joby-achieves-the-first-piloted-evtol-air-taxi-flight-between-two-public-airports |
| Archer/United — ORD ↔ Loop Chicago | **~10 min** | (a) United/Archer/Businesswire https://www.businesswire.com/news/home/20230323005204/en/ |

**What this means for `ready_by`:** block times are 7–12 min, charge turnaround 10–12 min, so
realistic arrival-to-ready is **~20–30 min**. The 65–85 min placeholder is ~3× too long for a
demonstrated-capability scenario. Recommend lowering it to a 25–40 min band and flagging the source
of the specific number, or keep 65–85 only if modeling a *manned* airline-style operation with
security/passenger-processing overhead. This is a Chase decision (demo realism vs. conservatism).

---

## Q4 — Cargo drone charging (placeholders: 8 kWh / 6 kW / opportunity)

| Platform | Battery | Charge vs swap | Practice | Source (label) |
|---|---|---|---|---|
| **Zipline P2** | kWh **NOT FOUND** in public specs | **Charge** (autonomous dock, no swap) | 10 miles in ~10 min, docks and recharges autonomously; 24-mi one-way radius | (a/c) Zipline fact sheet + CNBC https://www.zipline.com/about/zipline-fact-sheet |
| **Matternet M2** | kWh **NOT FOUND** (Amprius Si-anode cells) | **Swap <60 s** | landing station swaps battery + inserts package in <60 s; 2 kg payload | (a) Matternet https://www.matternet.com/our-system-landing-station |
| **Wing** | kWh **NOT FOUND** | **Charge** (no swap) | landing pad doubles as charge pad; charges on landing | (a/c) Wing https://www.facebook.com/Wing/posts/878511180932493/ |

**Corrections to the placeholders:**
- The **8 kWh / 6 kW** placeholders are **NOT FOUND as published figures** — none of the three
  (Zipline P2, Wing, Matternet M2) publishes battery kWh or charge kW. Keep them labeled, or
  derive a defensible range: a 10-mile / 2-kg-class delivery drone with ~10 min endurance carries
  roughly **1–3 kWh** (d, from the 10-min/10-mile energy budget), and docks charge at **~1–6 kW**
  (d). The "opportunity charging" practice is **correct for Zipline P2 and Wing** (charge-in-place),
  but **wrong for Matternet M2** (swap, not charge).
- Cycles/day: **NOT FOUND** as a published figure; Zipline implies near-continuous docking/charging
  between deliveries (24/7 operation), Wing charges between every delivery. No vendor publishes a
  cycles/day number.

---

## Q5 — Certification constraints that shape scheduling

1. **Post-flight inspection interval:** **NOT FOUND as an eVTOL-specific published number.**
   Conventional aviation uses 100-hour/annual/progressive inspection (14 CFR §91.409), but that is
   for certified fixed/rotor wing, not a published eVTOL turnaround inspection cadence. No OEM
   publishes a per-flight or per-turnaround inspection interval. Keep any inspection dwell as a
   labeled placeholder. (a) 14 CFR §91.409 — https://www.ecfr.gov/current/title-14/chapter-I/subchapter-F/part-91/subpart-E

2. **Battery temperature limits before fast charge / cold-soak after altitude:** **NOT FOUND as a
   published per-OEM number.** The regulatory frame is (i) FAA Special Condition (each cell must
   maintain safe temp/pressure — DRS-25-815-SC) and (ii) AC 20-184 (battery testing/installation
   guidance), both of which require thermal management but do **not** publish a "minimum battery
   temperature before fast charge" or a "cold-soak after altitude" dwell. eVTOL batteries are
   certified for ~2,000 fast-charge cycles and require high-power discharge + fast-charge
   capability, but the *specific* pre-charge thermal gate is OEM-proprietary. **Recommendation:**
   model a per-type `min_charge_temp_c` and `cold_soak_min` as calibration parameters (d), default
   conservative, and mark NOT FOUND — do not invent a universal value. (a/c)
   AC 20-184 — https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentid/1027106
   (c) aviationtoday.com "up to 2,000 fast charging cycles"

3. **Duty-cycle limits on pads:** **NOT FOUND.** No FAA/EASA document publishes a per-pad
   operations/hour ceiling beyond the throughput planning figures (NASA ConOps 80–120 ops/hr peak,
   UML-4). Pad duty cycle is bounded by charge time + downwash exclusion, not a regulatory number.
   (a) NASA ConOps (see H-B §4).

---

## Scenario JSON replacement summary (what to edit, with the sourced value)

| Placeholder (current) | Sourced value | Confidence |
|---|---|---|
| eVTOL battery kWh | Joby ~125 (±20%) / Archer ~75 / Beta ~220 / Lilium ~300 | (a/c) — per-type |
| eVTOL charge kW on pad | 300 (Joby) / 800V (Archer) / 350 (Lilium) / 115 cont (Beta) | (a/c) |
| Turnaround (charge) | 10–12 min (Joby/Archer) to ~50–55 min (Beta/Lilium) | (a/c) |
| Swap | Volocopter only, ~5 min; others charge | (a) |
| `min_gap_min = 6` | keep as labeled inference — no published time | NOT FOUND |
| `ready_by` 65–85 min | 20–40 min is defensible (7–12 min block + 10–12 min charge) | (a) + (d) |
| Cargo 8 kWh / 6 kW | NOT FOUND — keep labeled; ~1–3 kWh / ~1–6 kW defensible (d) | NOT FOUND |
| Cargo "opportunity charging" | correct for Zipline P2 + Wing; **swap for Matternet** | (a) |

---

## Open items

1. **Exact battery kWh for Joby S4** — Aviation Week (125) vs derived NASA-NTRS (150) conflict; no
   OEM-published nameplate. Use 125 ±20% and flag.
2. **Matternet M2 / Zipline P2 / Wing battery kWh + charge kW** — none published; cargo-drone
   energy numbers remain the weakest-sourced part of the scenario.
3. **`min_gap_min` and `ready_by`** — no regulator publishes either as a time; both are modeling
   calls. Flag for Chase (demo realism vs. conservatism).
4. **Post-flight inspection cadence and pre-charge thermal gate for eVTOL** — no published number;
   keep as per-type calibration params labeled NOT FOUND.
5. **Per-airframe D/RD (rotor diameter / controlling dimension)** — the pad-sizing rules in H-B are
   in multiples of D/RD; actual meters need each airframe's span, which changes pre-certification.
   Re-verify before finalizing pad geometry.
