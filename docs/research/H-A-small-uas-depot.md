Package H-A · 2026-08-22 · Status: final · Sources verified as of 2026-08-22

## FINDINGS

Small-UAS turnaround at a depot is not one number — it is a **fork between two regimes with a 20–30× gap in the limiting resource.** Either a dock swaps batteries robotically and the binding constraint is *battery inventory*, or it charges in place and the binding constraint is *charger power and pack capacity*. The scheduler must model both, because fielded systems split cleanly down this line.

**The battery-swap camp** (Hextronics Atlas, Airobotics Optimus, Dronehub) turns an aircraft in seconds-to-minutes but burns through a fixed battery stock that must itself be recharged somewhere. **The charge-in-place camp** (DJI Dock 2/3, Heisha, most military field systems) turns an aircraft in 30–120 minutes and is bounded by wall power and charge rate. Our existing Hextronics Atlas anchor (60 s swap / 150 s land-to-launch) holds up and sits at the *fast* end; the realistic range across fielded docks is **2 minutes (swap) to ~120 minutes (charge)**.

**Reserve fraction: 20% is defensible but optimistic at the margins.** The spec-sheet flight times we found (Skydio X10 40 min, Anduril Ghost X 75 min, Red Cat Black Widow 50+ min, Puma 3 AE 3 h) are *best-case* figures — hover in calm air, no payload penalty. Real sortie planning should treat them as a ceiling, not a mean, and a 20% reserve on a best-case ceiling leaves thin margin once wind, temperature, and battery ageing apply. The conservative move is 25–30% reserve against the *spec* number, or 20% against a *derated* number. We flag this for Chase as a modelling decision, not a research gap.

**The launch/recovery cadence question is answered: there is no terminal-separation standard for autonomous small-UAS recovery at an austere point.** FAA UTM provides strategic *airspace* separation concepts, but no authority publishes a terminal ground-separation number (metres or time) between recovering small rotorcraft. What exists is (a) manned wake-turbulence separation (AIM Chapter 7) that does not apply at these aircraft scales, and (b) an academic "well clear" literature that explicitly states *no standard exists*. This confirms our assumption and means **we own the separation model** — it is a physics-and-wind call, not a compliance call. That is an authorship opportunity, and a liability to document.

**Failure modes are the least-exciting, highest-leverage finding.** Wind limits (Teal 2: 18 mph sustained / 25 mph gusts; DJI Dock 3: −30° to +50°C and IP56) and battery cycle life (~400–500 cycles) are *hard* constraints the scheduler must respect, and they vary per platform. A scheduler that schedules a dock's next swap without knowing its battery stock is *below* its cycle floor, or schedules a recovery outside a platform's wind envelope, will produce plans that look optimal and fail in the field.

## FOR CLAUDE CODE

### 1. Turnaround numbers (verified, with source)

| System | Mechanism | Turnaround | Throughput | Battery stock | Power | Source (label) |
|---|---|---|---|---|---|---|
| Hextronics Atlas 300 | robotic swap | **60 s swap / 150 s land-to-launch** (our anchor) | — | **8 batteries**, >2000 cycles, <5 min downtime | — | Hextronics/Drone Nerds Enterprise (c) |
| Airobotics Optimus | robotic arm swap | seconds-scale swap (exact seconds NOT FOUND in public docs) | 24/7 continuous | **up to 11 swappable batteries** | — | American Robotics (c) |
| Dronehub | robotic swap | **2 min swap** | **20–25 missions/day** | — | — | Dronehub blog (c) |
| DJI Dock 2 | charge in place | **32 min charge** | — | 1 aircraft | 28 V DC out | DJI Enterprise specs (b/c) |
| DJI Dock 3 | charge in place | charge time NOT FOUND in snippet | — | 1 aircraft | **max 800 W input**, 100–240 V AC | DJI Enterprise specs (b/c) |
| Heisha V200 (VTOL dock) | charge in place | **~120 min charge** | — | 1 drone | **3500 W working power** | Heisha Tech (c) |
| Percepto Base | charge in place | charge time NOT FOUND | — | 1 aircraft, integral parachute | — | Percepto (c) |

**Decision rule for the scheduler:** classify each service point as `swap` or `charge`. A `swap` point consumes a battery from a bounded stock that regenerates at a separate charge rate; a `charge` point occupies the aircraft for the charge duration. These are different resource graphs and must not be merged into one "turnaround time" field.

### 2. Endurance and reserve (verified)

| Platform | Spec flight time | Source (label) | Reserve note |
|---|---|---|---|
| Skydio X10 | **40 min** max flight / 35 min hover | Skydio X10 technical specs (c) | 20% reserve = 8 min |
| Anduril Ghost X | **75 min** (dual battery) | Anduril press (c) | 20% = 15 min |
| Red Cat / Teal Black Widow | **50+ min** | Red Cat (c) | 20% = 10 min |
| AeroVironment Puma 3 AE | **3 h** (PS2500 24.5 Ah pack) | AeroVironment (c) | 20% = 36 min |
| AeroVironment Puma LE | **6.5 h** | AeroVironment (c) | 20% = 78 min |
| AeroVironment RQ-11B Raven | **60–90 min** | USAF fact sheet (a) | 20% = 12–18 min |

**Reserve recommendation for FOR CLAUDE CODE:** keep 20% as the default but treat the spec flight time as a **best-case ceiling**, and store reserve as a per-platform tunable `reserve_frac` with a default of 0.20 and a suggested range 0.20–0.30. Do not hardcode 20% into the kernel; it is pack data.

### 3. Launch / recovery cadence — the finding the scheduler must encode

- **No terminal-separation standard exists** for autonomous small-UAS recovery at an austere point. (Confirmed: FAA UTM covers strategic airspace separation; AIM Ch.7 wake turbulence is for manned aircraft; "Quantifying Well Clear for Autonomous Small UAS" — ResearchGate, IEEE — states no standard exists for well-clear.) Label: (a)/(d) inference — the *absence* is the verified fact.
- **Consequence:** separation is OUR model. Encode it as a physics/wind-driven constraint, not a compliance lookup. Minimum inter-recovery spacing should be a function of rotor diameter D and wind speed — a placeholder field `recovery_separation_m` that we set, with a documented rationale, because no external authority will set it for us.

### 4. Failure modes — hard constraints to add to the constraint set

| Constraint | Value | Source (label) | Where it binds |
|---|---|---|---|
| Wind (Teal 2) | 18 mph (16 kn) sustained, 25 mph (22 kn) gust | Teal Drones specs (c) | launch/recovery gate |
| Temp (DJI Dock 3) | −30° to +50°C | DJI Enterprise (c) | dock availability |
| Temp (Heisha V200) | −40° to +50°C | Heisha (c) | dock availability |
| Ingress (DJI Dock 3) | IP56 | DJI (c) | dust/rain ops |
| Battery cycle life (DJI TB65) | ~400 cycles | user-reported / XTBattery (c) | swap-stock floor |
| Battery cycle life (military LiPo) | ≥500 cycles | XTBattery (c) | swap-stock floor |
| Dust/sand | increases maintenance; US Army documents this for desert ops | Techspray quoting Army (c) | maintenance scheduling |

### 5. Constraints we probably have not thought of

1. **Battery stock is a shared, regenerating resource.** A swap dock can turn 8 aircraft in a row in ~2 min each, then is dead until its chargers refill the stock. The scheduler must track *stock level + refill rate*, not just "swap available."
2. **Precision-landing is a failure mode, not a given.** Autonomous recovery has a non-zero failure rate (docked-landing miss), and a missed landing consumes a re-approach cycle (~seconds-to-minutes). Reserve a re-approach allowance in pad occupancy time.
3. **Thermal derating on fast charge.** Charge rate drops at temperature extremes; the "32 min" charge is nominal, not cold-weather.
4. **One aircraft per dock is a hard cardinality.** Every commercial dock found holds exactly 1 aircraft (DJI Dock 2/3, Heisha, Percepto). Multi-aircraft "nest" capacity is the exception, not the rule — do not assume a pad can stage several aircraft.
5. **Payload swap ≠ battery swap.** Airobotics/Optimus swap *payloads* as well as batteries; a mission mix (ISR sensor vs delivery box) changes what the dock must do and how long it takes. Service bundle must include payload type.

## OPEN QUESTIONS

1. **Exact Airobotics Optimus swap time** — sources confirm robotic-arm swap and "seconds," but no public spec gives the precise figure. Needs a vendor datasheet or demo timing. (NOT FOUND)
2. **DJI Dock 3 charge time** — the Dock 3 specs page did not surface a charge-time number in the snippet; Dock 2 (32 min) is confirmed, Dock 3 needs re-verification.
3. **Military-specific dock systems** — no fielded military autonomous dock spec (cycle time, battery stock) was found in primary .mil sources. This is a real gap: our military segment numbers are currently anchored to commercial docks.
4. **Sortie-generation doctrine for small UAS** — no primary .mil doctrine number for sustained small-UAS sorties/day was found (the "2.0–2.1 strike sorties/day" figure is for manned tactical aircraft). Confirm whether an ATP/FM for small-UAS sortie generation exists before citing any turn rate.
5. **Reserve fraction is a modelling call** — research cannot resolve "20% vs 25% vs 30%"; that is a Chase decision with a cost/availability trade-off. Flagged, not decided.
