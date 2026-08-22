Package H-B · 2026-08-22 · Status: final · Sources verified as of 2026-08-22

# H-B — VTOL / Vertiport Turnaround and Traffic

## FINDINGS

**What this package covers.** Low-count, high-impact vertical-lift assets (unmanned VTOL and larger eVTOL) occupy a pad for a long time and need a big footprint around them. Two regulators have published concrete, machine-usable geometry: the FAA's Engineering Brief 105A (Dec 2024) and EASA's Prototype Technical Specifications PTS-VPT-DSN (Mar 2022). Both size every vertiport element as a multiple of a "controlling dimension" (D) or "rotor diameter" (RD) of the design aircraft, which means your scheduler can compute pad geometry from a single per-type input.

**The headline business constraint is energy, not airframe movement.** The two things that actually bind a pad are (1) the recharge time and (2) the downwash/outwash exclusion area around the aircraft. eVTOLs do NOT need a tug to reposition — they hover/air-taxi under their own power (EASA explicitly says "under their own power or using a tug"). So ground-handling equipment is NOT a first-class scheduled resource the way a tug is at a fixed-wing gate. The resource you must schedule is the *charger* (and its kW rating), plus a time/area exclusion for downwash.

**The one number to respect above all:** FAA measured downwash of real prototypes at nearly 100 mph instantaneous (41 ft from pad center) and >60 mph still at 100 ft out. That blows through any compact "safety area" and forces a Downwash Caution Area (DCA) that, in practice, means "no people/equipment/other aircraft in the zone while the asset is on or near the pad." This is the dominant separation driver for a small site, bigger than the painted FATO/TLOF.

**Where the two regulators disagree (and what it means for a model):** FAA sizes TLOF/FATO/Safety Area off *two* dimensions (D for the whole aircraft, RD for just the propulsors, giving a smaller pad). EASA sizes off a single D (FATO = 1.5 D, TLOF = 0.83 D). Both are non-binding guidance, not regulation — flag them as "recommended," not "required." For a scheduler the practical takeaway is: pad size ≈ 1.5–2 × D, and the exclusion zone is set by *downwash velocity*, not by the painted pad.

**Turnaround is dominated by charge time (minutes), not by aircraft handling (seconds).** Primary manufacturer numbers: Archer Midnight ≈10 min charge for a 20-mile hop (later "as little as 12 min between sorties"); Joby's charger (GEACS) charges four isolated battery packs "in a matter of minutes" at up to 300 A per channel at 150–1000 VDC. There is no published regulatory "settle time" in seconds for downwash to dissipate — the criteria are velocity-distance based (FAA 34.5 mph threshold; EASA 2D-circle velocity table), not time-based. Model pad occupancy as: (approach + touchdown + energy-transfer time + clearance + departure), where energy-transfer is the long pole.

---

## FOR CLAUDE CODE

All criteria below are **non-binding design guidance**, not regulation. None are "required by regulation" — the FAA EB is explicitly "voluntary," and the EASA PTS is explicitly "non-binding." Treat everything here as *published doctrine / recommended practice* unless marked otherwise. Every row carries its source; labels: **(a)** primary/official, **(b)** standards body, **(c)** trade press/analyst, **(d)** inference (yours).

### 1. Input parameter: the controlling dimension (D) and rotor diameter (RD)

Two geometries, one per aircraft type in your model. Both are *diameters of circles*, not lengths.

| Field | Definition | Source |
|---|---|---|
| `D` (controlling dimension) | Diameter of the smallest circle enclosing the **entire** VTOL projection on a horizontal plane, takeoff/landing config, rotors turning. FAA: "Controlling Dimension (CD)". EASA: "D". | (a) FAA EB 105A §1.2 — https://www.faa.gov/airports/engineering/engineering_briefs/eb_105a_vertiports ; (a) EASA PTS-VPT-DSN A.020 — https://www.easa.europa.eu/sites/default/files/dfu/PTS-VPT-DSN.pdf |
| `RD` (rotor diameter) | Diameter of the smallest circle enclosing **only the propulsion units** (propellers/rotors/fans) plus landing-gear/surface touch points. May be < D. | (a) FAA EB 105A §1.2 (term 20) |

FAA reference-aircraft envelope (the aircraft EB 105A is calibrated to): MTOW ≤ 12,500 lb (5,670 kg); D ≤ 50 ft (15.2 m); ≥3 propulsive units; ≥2 battery systems; electric distributed-electric-propulsion; vertical takeoff/landing from steady hover. (a) FAA EB 105A Table 1-1. If your asset exceeds these, the FAA guidance does not apply without case-by-case coordination.

### 2. Pad sizing — computable rules (multiples of D / RD)

**FAA EB 105A, Table 2-1** (a) — minimum dimensions:

| Element | Rule | Notes |
|---|---|---|
| TLOF (touchdown/lift-off area) | **1 × RD** | load-bearing paved area; if aircraft can't demonstrate "equivalent helicopter landing accuracy," keep 1 RD; future reduced-TLOF needs that demo |
| FATO (final approach/takeoff area) | **2 × RD** | area over which final approach/hover/takeoff happens |
| Safety Area | **2.5 × D** | note: uses full **D**, not RD — surrounding the FATO |

**EASA PTS-VPT-DSN** (a) — minimum dimensions (single-D scheme):

| Element | Rule | Clause |
|---|---|---|
| FATO length | **max(RTOD_V from AFM, 1.5 × D)** | C.210(c)(1) |
| FATO width | **max(AFM procedure width, 1.5 × D)** | C.210(c)(2) |
| Safety Area | extends **≥ max(3 m, 0.25 × D)** beyond the FATO edge | C.220(c) |
| TLOF (ground-level) | **max(0.83 × D, AFM)** | C.260(d) |
| TLOF (elevated vertiport) | must contain a circle of diameter **≥ 1 × D** | C.260(e) |
| Aircraft stand (parking) | circle of diameter **1.2 × D** (or ≥1.2 × overall width) | C.320(e) |
| Air taxi-route width | **2 × overall width** of largest aircraft; air-taxi at < 37 km/h (20 kt) in ground effect | C.310 |

**FAA EB 105A parking position** (a): aircraft max length + max width + a minimum of **0.28 × D**, or at least **10 ft (3 m)** clearance between aircraft and fixed objects. Parking positions that permit hover/air-taxi must be ≥ FATO size.

**Recommendation for the scheduler:** store `D` (and `RD` if known) per aircraft type. Pad footprint = a disk of diameter `2.0 × RD` (FAA) or `1.5 × D` (EASA); the *scheduled exclusion* disk = `2.5 × D` (FAA) — use the largest applicable. These are floor sizes; add the DCA (§3) on top.

### 3. Downwash / outwash — exclusion distances and velocity limits (the real separation driver)

**FAA threshold (governs the DCA).** "Air velocities of approximately **34.5 mph (55.5 kph)** or greater can impact vertiport safety. For vertiport planning purposes, DCAs should be established anywhere that wind velocity can potentially meet or exceed 34.5 mph." Basis: FAA *Rotorwash Analysis Handbook* (1994) — "the majority of rotorwash-related mishaps can be avoided if separation distances are maintained so that impacting rotorwash-generated velocities do not exceed **30 to 40 knots** across the ground." (a) FAA EB 105A §2.5. **Rule:** exclude people/equipment from any zone where downwash ≥ 34.5 mph (55.5 kph). DCA is in effect during any operation creating downwash; use the largest DCA for the largest aircraft at the facility.

**FAA measured reality (DOT/FAA/TC-24/42, 2024)** — for prototype eVTOLs ≤ 7,000 lb (3,175 kg):
- Highest **instantaneous** max: ~**100 mph at 41 ft (12.5 m)** from TLOF center.
- Highest **3-second moving 95th percentile**: **84 mph at 23 ft (7.0 m)**.
- **>60 mph still measured at 100 ft (30.5 m)** from TLOF center.
- EB 105A footnote: velocities **well above 34.5 mph at 126 ft (38.5 m)** for some designs.
(a) DOT/FAA/TC-24/42, "eVTOL Downwash and Outwash Surveys" — https://rosap.ntl.bts.gov/view/dot/79065 (PDF: dot_79065_DS1.pdf). **Rule of thumb for a default DCA radius: ≥ ~40 m (130 ft) for a ≤7,000 lb multi-rotor eVTOL; verify per type.**

**EASA downwash criterion (the "2D circle" the task asked about — VERIFIED).** PTS-VPT-DSN C.230:
- The Aircraft Flight Manual (AFM) reports downwash measured on a **2 D circle** while the aircraft is in a **1-m hover**, no-wind conditions.
- Table C-1 — maximum permitted downwash velocity by area type (if the AFM value on the 2 D circle exceeds the applicable limit, extend the downwash-protection area until the boundary velocity is below the limit):

| Max downwash velocity | Area type |
|---|---|
| **60 km/h** | areas traversed by flight crew, or passengers boarding/leaving an aircraft |
| **60 km/h** | public areas (inside or outside vertiport boundary) where people walk or congregate |
| **80 km/h** | public areas where people are *not* likely to congregate |
| **80 km/h** | any personnel working near an aircraft |
| **80 km/h** | equipment on an apron |
| **50 km/h** | public roads where vehicle speed ≥ 80 km/h |
| **60 km/h** | public roads where vehicle speed < 80 km/h |
| **100 km/h** | buildings and other structures |

(a) EASA PTS-VPT-DSN Table C-1 (adapted from CASA Part 139 MOS 2019). **Rule: near personnel, the EASA downwash limit is 60 km/h (≈37 mph, ≈16.7 m/s) at the 2 D circle; if exceeded, expand the protection area.**

**EASA outwash (radial component).** The VPTTF data-survey letter asks manufacturers to report whether, in a low hover, at the limits of a **cylinder of diameter 2 D** (from the surface up to **1.5 m** height), the maximum measured **radial speed is < 60 km/h** in any wind within the flight envelope (and whether downwash temperature exceeds ambient by >10 °C). (a) EASA PTS-VPT-DSN, data survey. **Rule: outwash ≤ 60 km/h at the 2 D / 1.5-m cylinder is the target for safe ground operation.**

**Settle time: NOT FOUND as a published number.** No FAA or EASA document publishes a time-in-seconds for downwash to dissipate between operations; both regulators use velocity-distance criteria, not time. Helicopter trade sources use a 2–3 × rotor-diameter dissipation rule-of-thumb (c), but this is not a vertiport criterion. **Recommendation:** model downwash as a *spatial* exclusion tied to when the asset is on/near the pad (approach → touchdown → hover → departure), not as a fixed post-departure dwell timer. If you need a hold-down timer, treat it as a calibration parameter and mark it as inference (d).

### 4. Turnaround — energy transfer is the long pole

| Aircraft / system | Number (unit) | Basis | Source |
|---|---|---|---|
| Archer Midnight | ≈ **10 min** charge for a **~20-mile** hop (back-to-back ops) | manufacturer design target | (a) Archer press release, 2022-11 — https://investors.archer.com/news/news-details/2022/Archer-Unveils-its-Production-Aircraft-Midnight/default.aspx ; (a) SEC filing ex99-1 same text — https://www.sec.gov/Archives/edgar/data/0001824502/000110465922119765/tm2230802d1_ex99-1.htm |
| Archer Midnight (later) | "quick-charge turnarounds of as little as **12 min** between sorties" | manufacturer | (c→a) Archer/FlyArcher statement |
| Archer Midnight | **6 independent battery packs** | manufacturer | (c) Forecast International — https://flightplan.forecastinternational.com/2024/04/04/uam-snapshot-archer-midnight/ |
| Joby GEACS charger | **150–1000 VDC**, up to **300 A per channel**, multiple simultaneous DC channels; "charge four isolated battery packs in a matter of minutes" via two charge ports | manufacturer spec sheet | (a) Joby GEACS — https://joby-site.cdn.prismic.io/joby-site/5f82ea34-645e-4468-8e3f-14a16e298941_Joby-Charging-GEACS-final.pdf |
| Joby peak power (inferred) | up to **~300 kW per channel** (= 1000 V × 300 A), more with parallel channels | derived from spec | (d) inference from GEACS voltage/current |
| eVTOL charging standard | SAE charging standard for light electric aircraft up to **500 kW** (in development ~2024) | standards body | (c) eVTOL.news "Competing Standards" — https://evtol.news/news/competing-standards |
| Megawatt-class charging | 350 kW–2.5 MW to make turnaround competitive with helicopters | analyst | (c) Dataintelo megawatt-charging report |
| Vertiport throughput (planning) | **80–120 operations/hour** peak (NASA UML-4); **40–80 ops/hr** (UML-3) | planning figure | (a) NASA High-Density Automated Vertiport ConOps (2021) — https://ntrs.nasa.gov/api/citations/20210016168/downloads/20210016168_MJohnson_VertiportAtmtnConOpsRprt_final_corrected.pdf |
| Vertiport parking | ~12 aircraft parking capacity at high-service vertiports | planning figure | (a) NASA ConOps (same URL) |

**Charge vs swap vs fuel:** For *unmanned* VTOL the picture is the same three options. Battery swap exists as a planned offering (Volocopter's VoloPort planned battery swapping + charging alongside pre-flight checks — (a) NASA ConOps §1.x citing Volocopter), and swap is faster than even fast charging (c). Trade-off for the model: **swap** costs a shared swappable-battery inventory + ground crew + storage compliance; **charge** costs pad time (minutes) but no crew. Fuel-based large VTOL (e.g., turbine tiltrotors) is outside the eVTOL corpus and has no published vertiport turnaround number — NOT FOUND.

**Model recommendation (d):** pad occupancy = approach/hover + energy-transfer (dominant) + clearance/departure. Use per-type `charge_minutes` (default 10–12 min) and a `charger_kW` rating; energy-transfer time ≈ (required kWh per hop) / (charger_kW × efficiency). For unmanned assets doing cargo hops of similar length to Archer's 20-mile profile, ~10 min of charging is the realistic floor; add a few minutes for connect/disconnect and clearance.

### 5. Ground handling — IS a tug a scheduled resource? **No (not mandatory).**

- EASA C.320 (a): "certain VTOL-capable aircraft can execute a **power-in/push-back type manoeuvre under their own power or using a tug**, avoiding the need for hover turns." → repositioning is *self-powered by default*; tug is an optional convenience, not a requirement.
- FAA EB 105A §3.0: ground taxiing follows AC 150/5300-13 (Group 1); **hover/air-taxi** is the norm for VTOL repositioning (EASA air taxi-route: <37 km/h, ground effect).
- NASA ConOps: helicopters that *cannot* ground-taxi "may land on a **dolly or a portable landing pad** for ground handling" — i.e., a ground-handling device is only needed for aircraft that physically cannot move themselves.
- All three sources: (a) — EB 105A, PTS-VPT-DSN, NASA ConOps (URLs above).

**Answer for the scheduler:** Ground-handling equipment (tug/dolly) is **NOT a required shared resource** in the general case — model it as optional. The **binding shared resource is the charger/pad** (charger availability + kW, plus the downwash exclusion while occupied). Only add a tug/dolly resource if you model a specific aircraft type that cannot self-air-taxi; flag that as a per-type boolean, default `false`.

### 6. Mixed operations (small UAS + large VTOL at one site)

- **No published FAA/EASA rule requiring small UAS to stop when a VTOL operates** was found. Part 107.35 governs *multiple small UAS under one operator*, not small-UAS-vs-VTOL coexistence — it is not a separation criterion. NOT FOUND for a specific simultaneous small-UAS+VTOL separation number.
- **EASA FATO-to-FATO separation** (C.340): set by safety assessment considering operation type, approach/departure orientation, balked landing, AFM downwash data, and "SAs do not overlap." Reference: **60 m** between two FATOs is a recognized distance for *simultaneous helicopter* landings/takeoffs (non-conflicting courses, MTOW ≤ 3,175 kg). (a) EASA PTS-VPT-DSN C.340.
- **EASA FATO-to-runway/taxiway separation** (C.350, Table C-2) — if simultaneous ops planned, FATO edge to runway/taxiway edge must be at least:

| Aircraft mass band | Min FATO-to-runway/taxiway distance |
|---|---|
| up to <3,175 kg | **60 m** |
| 3,175–<5,760 kg | **120 m** |
| 5,760–<100,000 kg | **180 m** |
| ≥100,000 kg | **250 m** |

(a) EASA PTS-VPT-DSN Table C-2 (primarily wake-turbulence mitigation).
- **FAA vertiport vs runway** (on-airport siting, EB 105A Table 6-1): VTOL ≤12,500 lb — FATO center to runway centerline **500 ft (152 m)** for small/large airplanes, **700 ft (213 m)** for heavy (>300,000 lb). (a) FAA EB 105A Table 6-1. Appendix A: FATO <700 ft from runway centerline needs wake-turbulence mitigation; ≥2,500 ft (762 m) is effectively independent; VTOL must enter ingress/egress ≥500 ft (152 m) above/below runway traffic (1,000 ft under heavy/super).
- **Unmanned cargo VTOL vertiports** have their own standard: **ISO 5491:2023**, "Vertiports — Infrastructure and equipment for VTOL of electrically powered cargo unmanned aircraft systems (UAS)" (type-A micro vertiports, per ISO 5015-2). (b) — https://www.iso.org/standard/81313.html . Full criteria are paywalled; pull them if you need micro-vertiport geometry for small unmanned VTOL.
- **NASA ConOps Use Case 3 (Urban Air Freight)**: "a mix of piloted and highly automated pilotless cargo aircraft operating in the same airspace" at 40–80 ops/hr — confirms mixed manned/unmanned vertical-lift coexistence is a planned operating mode, managed by a Vertiport Automation System (VAS). (a) NASA ConOps (URL above).

**Recommendation (d):** for a single-site mixed small-UAS + VTOL model, enforce (i) physical pad separation ≥ 60 m between a VTOL pad and any other active vertical-lift pad (EASA reference), (ii) downwash exclusion (§3) around the VTOL while occupied, and (iii) treat small UAS as able to continue elsewhere on the site *provided* they stay outside the VTOL's DCA and outside the 2 D / 60 km/h outwash cylinder. No "global stop" rule exists.

---

## OPEN QUESTIONS

1. **Downwash "settle time" in seconds** — no regulator publishes one. If the model needs a post-departure cooldown before the pad clears, it must be calibrated from measured data (DOT/FAA/TC-24/42 gives velocity-vs-distance, not time) or from the specific airframe's AFM. Re-verify if a future FAA/EASA update adds a time criterion.
2. **Unmanned-specific vertiport geometry** — EASA PTS-VPT-DSN and FAA EB 105A are written for *manned* (pilot-on-board) VTOL. For large *unmanned* vertical-lift assets the nearest authority is ISO 5491:2023 (cargo UAS, micro type A). Full ISO criteria are paywalled — worth obtaining before finalizing pad sizing for unmanned airframes.
3. **Per-type D / RD values** — the dossier gives rules in multiples of D/RD; actual meters require each airframe's D/RD (e.g., Joby S4, Archer Midnight spans). These are manufacturer-spec inputs to fetch per type, and they change pre-certification. Flag for re-verification.
4. **Battery-swap standard times** — swap is described qualitatively ("faster than charging") but no authoritative seconds/minutes-per-swap number was found for a specific unmanned VTOL. NOT FOUND.
5. **Everything here is fast-moving:** EB 105A is explicitly a "living document" slated to be replaced by an AC; EASA PTS-VPT-DSN is a "prototype" ahead of RMT.0230 rulemaking. Re-verify both, and the FAA's downwash dataset (which the Technical Center said it would keep updating), before the scheduler ships.
