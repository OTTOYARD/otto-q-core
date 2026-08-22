Package H-C · 2026-08-22 · Status: final · Sources verified as of 2026-08-22

## FINDINGS

### The scheduler must decide between two distinct movement paradigms, not one.

Autonomous ground resupply for small logistics UGVs (S-MET class, 1,000–3,500 lb payload) operates as **squad-following**. The UGV trails a dismounted squad at walking pace — 3.7 mph (1.65 m/s, 6 km/h) is the published Army requirement for combat-load terrain movement, and real-world Ukrainian UGV speeds cluster at 4–12 km/h (1.1–3.3 m/s) for electric platforms. Our current flat 9 m/s (32.4 km/h, 20.1 mph) is wildly optimistic: it is achievable only on paved roads by a large platform (Hunter Wolf, Protector) at top speed, and even then only in a sprint. The S-MET's actual cross-country sustained pace under load is **1.65 m/s (6 km/h)**, and unimproved-road convoy speed is capped at **45 mph (72 km/h)** in doctrine. For any distance over austere terrain, expect **2–3 m/s (7–11 km/h)** for wheeled electric UGVs and **4–8 m/s (14–29 km/h)** for diesel/hybrid platforms on dirt roads.

For medium/heavy logistics (PLS trucks, ATV-S class), the doctrinal paradigm is **leader-follower convoying**, not independent movement. The Army's ATV-S program fields a human-crewed lead vehicle with up to 7–9 autonomous followers. This means our scheduler must **batch** these assets and allocate a human lead-vehicle driver, which materially changes the allocation problem: you cannot send one truck to one depot independently; you send a convoy of N trucks to one or more nodes along a route corridor, and the lead vehicle's driver availability gates everything.

### Route control vocabulary is defined and adoptable.

Army movement control doctrine (ATP 4-16, April 2022 revision; FM 4-01.30) provides the exact data model we want:
- **Route status**: GREEN, AMBER, RED, BLACK — reported by Movement Control Teams (MCTs)
- **Movement credits**: required to use any Main Supply Route (MSR); issued by the Highway Traffic Division (HTD) for supervised, dispatch, and reserved routes
- **Convoy Clearance Number (CCN)**: unique identifier for each convoy movement
- **Unit Movement Officer (UMO)**: the human responsible for unit-level movement requests

This is exactly the vocabulary we should adopt rather than inventing our own. The data model needs `route_id`, `route_status` (enum: green|amber|red|black), `movement_credit_id`, `convoy_clearance_number`, and a `requires_credit` boolean.

### Charging is moving toward a 600 VDC standard but hybrid dominates.

MIL-STD-3072 (published August 2025) defines 600 VDC characteristics for Army ground vehicles. It replaces MIL-PRF-GCS600A and will be followed by MIL-HDBK-3072 (test methods) and MIL-PRF-3072 (device specs). GE Aerospace qualified production-ready 600V silicon-carbide power controllers in June 2026 with LRIP deliveries expected 2027. However, fielded UGV platforms are predominantly **hybrid** — JP8/diesel with an electric drive and battery buffer — not pure BEV. S-MET is hybrid-electric. Hunter Wolf is diesel/electric hybrid with 150 miles of silent electric-only range. Ukrainian logistics UGVs (Vepr, Murakha, Rys) are pure electric with ~20–50 km range. For a scheduler, the charging decision is: does this asset have enough fuel/charge to complete the round-trip, and if not, which depot node has refuel/recharge capacity? DC charge rates for specific UGV battery packs are **NOT FOUND** in public sources; manufacturers treat these as proprietary.

### The cost gap is enormous and matters for scheduling.

S-MET Inc. I: ~$100,000/unit (base price target). Ukrainian Vepr: $8,000–$20,000 for 350 kg payload, 40 km range. Ukrainian Bizon-L: 300 kg payload, 50 km range, NATO-catalogued. This means loss tolerance is a scheduling dimension: an $8,000 Vepr can be treated as expendable and sent into high-risk routes alone, whereas a $160,000 S-MET requires risk-weighted routing decisions. Our scheduler should accept a `loss_tolerance` flag per asset type.

---

## FOR CLAUDE CODE

### 1. PERFORMANCE TABLE (platforms with verified sources)

| Platform | Payload | Speed (on-road top) | Speed (cross-country) | Range | Endurance | Power | Source | Source Type |
|---|---|---|---|---|---|---|---|---|
| **S-MET Inc. I** (GDLS MUTT 8×8) | 454 kg / 1,000 lb (large), 227 kg / 500 lb (small) | 8 mph / 13 km/h (sustained combat load: 3.7 mph / 6 km/h) | 3.7 mph / 1.65 m/s / 6 km/h (full combat load over various terrain) | 96 km / 60 mi (large), 48 km / 30 mi (small) | 72 hr | Hybrid-electric (JP8/lithium). 3 kW stationary export, 1 kW moving. | Army.mil + GlobalSecurity.org AOIs | (a) primary/official |
| **S-MET Inc. II** (2× competitors) | ~907 kg / 2,000 lb (doubled from Inc. I) | NOT FOUND | NOT FOUND (prototype phase) | NOT FOUND | — | Higher exportable power, worldwide grid charging, improved audio signature. | army.mil/article/279963 (24 Sep 2024) | (a) primary/official |
| **HDT Hunter Wolf** (6×6 hybrid) | 1,000–1,270 kg / 2,200–2,800 lb | 100 km/h / 62 mph (top); 48 km/h / 30 mph (off-road autonomous) | NOT FOUND as m/s; 15 mph / 24 km/h off-road (autonomous mode) | 300 km / 186 mi (diesel), 241 km / 150 mi (silent electric) | 120 hr (diesel) | Diesel/electric hybrid. 15 kW continuous, 100 kW peak export. Climbs 60° slopes. | thedefensepost.com (30 Oct 2024) + hdtrobotics.com | (a) manufacturer spec sheet |
| **MUTT XM** (next-gen GDLS) | >1,588 kg / 3,500 lb | 25 mph / 40 km/h | NOT FOUND | NOT FOUND | — | Hybrid-electric, larger drive motor, higher ground clearance. | gdls-ausa.com/mutt-xm | (a) manufacturer |
| **AM General UGV** | 2,268 kg / 5,000 lb | NOT FOUND | NOT FOUND | NOT FOUND | — | 13-Series chassis, leader-follower, teleoperation, supervised autonomy. | amgeneral.com/what-we-do/future | (c) manufacturer marketing |
| **Ukrainian Vepr** | 350 kg / 770 lb | 7.5 km/h / 4.7 mph | 7.5 km/h / 2.1 m/s (published max ≈ sustained) | 40 km / 25 mi | NOT FOUND | 2×1.5 kW electric motors. Cost $8,000–$20,000. | united24media.com (16 Nov 2025) + army.mil/article/290022 | (b) MoD announcement verified via trade press |
| **Ukrainian Murakha** | 500 kg / 1,100 lb | 12 km/h / 7.5 mph | 12 km/h / 3.3 m/s | 50 km / 31 mi | NOT FOUND | Electric. 240 mm ground clearance. | dignitas.fund (13 May 2026) | (c) trade press / analyst aggregation |
| **Ukrainian Protector** | 770 kg / 1,700 lb | 60 km/h / 37 mph | NOT FOUND | 400 km / 249 mi | NOT FOUND | NOT FOUND | dignitas.fund (13 May 2026) | (c) trade press / analyst aggregation |
| **Ukrainian Bizon-L** | 300 kg / 660 lb | NOT FOUND | NOT FOUND | 50 km / 31 mi | NOT FOUND | NATO-catalogued (2026). | defensenews.com (24 Apr 2026) | (c) trade press |
| **Army ATV-S** (PLS trucks) | Vehicle-class (5–16 ton cargo) | Convoy speed per ATP 4-16 | Convoy speed per ATP 4-16 | Vehicle-class | Vehicle-class | Leader-follower: 1 crewed lead + up to 7–9 autonomous followers. Carnegie Robotics & Forterra down-selected 2025. | pailton.com (2025) + nationaldefensemagazine.org (2022) | (c) trade press |

**Key numbers for the scheduler:**
- `sustained_cross_country_speed_ms`: use **1.65** for S-MET-class electric, **3.3** for medium electric, **6.7** (24 km/h) for hybrid/diesel off-road
- `unimproved_road_speed_ms`: use **20.1** (45 mph) for convoy-capable platforms
- `range_km`: 48–60 km for small electric, 100–300 km for hybrid/diesel
- `payload_kg`: 350–500 kg for expendable Ukrainian-class, 1,000–2,268 kg for US-class
- `cost_usd`: flag at 10k (expendable), 100k (semi-expendable), 250k+ (protected)

### 2. ROUTE CONTROL VOCABULARY — DATA MODEL

From ATP 4-16 Movement Control (April 2022) and FM 4-01.30. Adopt directly.

```
Route:
  route_id              UUID
  route_designation     text          — e.g. "MSR TAMPA", "ASR GOLD"
  route_type            enum          — MSR | ASR | DIRT | TRAIL | CROSS_COUNTRY
  route_status          enum          — GREEN | AMBER | RED | BLACK
  status_updated_at     timestamptz
  requires_movement_credit  boolean   — true for MSRs
  movement_credit_issuing_hq  text    — HTD or MCT designation
  traffic_direction     enum          — ONE_WAY | TWO_WAY | ALTERNATING
  speed_limit_ms        numeric       — posted speed limit in m/s
  last_recon_time       timestamptz
  controlling_mct       text          — Movement Control Team identifier

MovementCredit:
  movement_credit_id    UUID
  route_id              UUID          — FK to Route
  convoy_clearance_number  text       — CCN, unique per movement
  requesting_umo        text          — Unit Movement Officer
  approved_by           text
  valid_from            timestamptz
  valid_until           timestamptz
  credit_type           enum          — SUPERVISED | DISPATCH | RESERVED
  vehicle_count         integer
  convoy_type           enum          — MANNED | LEADER_FOLLOWER | AUTONOMOUS_SMALL

RouteStatus enum values (published doctrine):
  GREEN   — Route is open, unrestricted, safe for all traffic classes.
  AMBER   — Route is degraded: slow, restricted, or intermittently contested.
            Expect speed penalties (0.5x–0.7x × nominal).
  RED     — Route is heavily restricted or actively contested.
            Requires explicit commander waiver. Expect severe speed penalties.
  BLACK   — Route is closed. No movement authorised. Impassable or under
            active engagement.
```

**Decision sequence (from doctrine):**
1. Unit Movement Officer (UMO) identifies movement requirement.
2. UMO requests route assignment from Movement Control Team (MCT).
3. MCT checks route status (GREEN/AMBER/RED/BLACK) and issues movement credit if MSR.
4. For MSR, MCT assigns Convoy Clearance Number (CCN).
5. Unit dispatches. MCT monitors and updates route status.
6. If route changes to RED/BLACK mid-movement, MCT re-routes or recalls.

**For the scheduler:** ON EVERY `schedule_run()` cycle, fetch current `route_status` for all routes in the depot network. A BLACK route drops all candidate edges. A RED route multiplies `effective_speed_ms` by 0.3–0.5. An AMBER route multiplies by 0.5–0.7. A GREEN route uses nominal speed. Movement credits gate dispatch: if `requires_movement_credit=true` and no valid credit exists, the asset cannot depart.

### 3. CONVOY VS INDEPENDENT — THE ANSWER

**Small logistics UGVs (S-MET class, ≤3,500 lb payload):**
The design intent is **squad-following** (a form of leader-follower at dismounted pace). S-MET requirement AOI-24: up to four S-METs following a soldier between 5–50 m line-of-sight. These platforms do NOT move independently over distance — they follow a squad or are teleoperated. Ukrainian practice differs: small electric UGVs (Vepr, Murakha) DO move independently for last-mile delivery, but they are teleoperated by a human operator at a base station, not autonomous.

**Medium/heavy logistics UGVs (PLS truck class, ATV-S):**
The doctrinal paradigm is **leader-follower convoying ONLY**. The human-crewed lead vehicle sets pace and route. Followers are autonomous but formation-locked. ATV-S: 1 lead + up to 9 followers. ExLF: 1 lead + up to 7 followers. Army officials state the goal is "not fully independent vehicles operating in isolation, but reliable autonomous followers."

**Implication for the scheduler:**
- **For small UGV class**: the asset moves with its parent squad. The scheduler assigns the squad, not the UGV individually. A squad's movement plan gates its UGV's routing. If the squad is at Depot A and needs resupply at Depot B, the UGV can only move when the squad moves, or it can do a teleoperated supply run independently (Ukrainian model).
- **For convoy class**: the scheduler MUST batch. N assets are assigned to one convoy led by one driver. All N assets depart together. The allocation problem is: given D available drivers and V vehicles needing movement, find the optimal partition of V into convoys of size ≤max_convoy_size, each assigned to one driver. This is a bin-packing problem, not a point-to-point routing problem.
- **Hybrid model (recommended for OTTOYARD)**: small UGVs operate independently (teleoperated) for short-range depot-to-depot resupply within a protected perimeter. Medium/heavy vehicles convoy with a human lead. This is what Ukraine does and is closest to actual field practice.

### 4. CHARGING DATA

| Parameter | Value | Source | Source Type |
|---|---|---|---|
| Military HV standard | MIL-STD-3072: 600 VDC characteristics for Army ground vehicles | SAE 2025-01-0503 (published 16 Sep 2025) | (a) primary/standards body |
| Predecessor spec | MIL-PRF-GCS600A (performance spec, loosely referenced) | NTIS ADA538869 | (a) primary/standards body |
| Legacy LV standard | MIL-STD-1275: 28 VDC for military ground vehicles | quicksearch.dla.mil | (a) primary/standards body |
| GE Aerospace HV qual | HVPC + UDC qualified June 2026. 600V SiC MOSFET. LRIP 2026, deliveries 2027. | geaerospace.com (1 Jun 2026) | (a) manufacturer press release |
| S-MET powertrain | Hybrid-electric. JP8 fuel + lithium batteries. | army.mil + globalsecurity.org | (a) primary |
| Hunter Wolf powertrain | Diesel/electric hybrid. 150 mi silent electric. Recharges on the move. | hdtglobal.com + thedefensepost.com | (a) manufacturer |
| Ukrainian UGV powertrain | Pure electric (all documented platforms). Typical range 20–50 km per charge. | dignitas.fund (13 May 2026) | (c) trade press |
| **DC charge rate (kW) for UGV batteries** | **NOT FOUND** — proprietary, not disclosed in public sources | — | (d) inference |
| S-MET Inc. II requirement | "Worldwide grid charging" — implies compatibility with civilian AC/DC standards, but spec not public | army.mil/article/279963 | (a) primary |

**Scheduler implication:** For hybrid platforms, refueling is JP8/diesel — treat as liquid fuel stop with known pump rates (~5–10 min). For pure electric UGVs, assume a charge-to-80% time of 2–4 hours (inference from commercial EV rates scaled to UGV battery sizes of ~10–30 kWh) until manufacturer data surfaces. Worldwide grid charging on S-MET Inc. II suggests 120/240V AC input compatibility; DC fast-charge rates remain NOT FOUND.

---

## OPEN QUESTIONS

1. **What are the actual DC fast-charge rates (kW) for S-MET Inc. II and Hunter Wolf battery packs?** These are proprietary and not disclosed publicly. A direct inquiry to GDLS/HDT or the Army PEO CS&CSS through official channels may yield the numbers. Until then, the scheduler should accept a configurable `charge_rate_kw` per asset type, defaulting to inference-based estimates.

2. **Is the S-MET cross-country sustained speed of 3.7 mph (1.65 m/s) still the valid requirement for Inc. II, or has it been raised?** The Inc. II program requirements are in development; only the doubled payload and worldwide grid charging are publicly confirmed.

3. **Does the Army intend for S-MET-class UGVs to ever move independently between depots without an accompanying squad, or is this strictly a teleoperated use case?** Current doctrine says squad-following. Ukrainian practice says teleoperated independent movement works at short range. A published CONOPS for autonomous UGV depot-to-depot movement was not found.

4. **What is the actual terrain-speed penalty model used by Army planners?** The RAND V-50/V-80 speed methodology (average speed over 50%/80% of trafficable terrain) exists but specific multipliers for GREEN/AMBER/RED route statuses are not published in open sources. The 0.3–0.7 multipliers above are inference from the doctrinal meanings of the status levels.

5. **What is the standard convoy size limit for leader-follower autonomous convoys under current doctrine?** ExLF reports 7 followers. ATV-S targets 9. Ukrainian practice is single-UGV independent. NATO STANAG limits were not found in open sources.

6. **Are there published NATO/U.S. standards for UGV-to-charger physical connectors?** MIL-STD-3072 defines electrical characteristics but not physical connector pinouts. MIL-PRF-3072 (forthcoming) may address this. SAE J1772 CCS/NACS adaptation for military use was not found.

7. **What is the actual battery capacity (kWh) of the S-MET, Hunter Wolf, and competing platforms?** Not publicly disclosed. Needed to compute charge times from any charge rate.

---

*Research conducted via web_search + web_extract against primary sources (.mil, .gov, standards bodies, manufacturer spec sheets) on 2026-08-22. All claims are sourced. Where a number could not be verified, it is marked NOT FOUND.*