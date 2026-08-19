H3 · 2026-08-18 · Status: final · Sources verified as of 2026-08-18

## FINDINGS

### 1. Drone-in-a-Box Recall & Docking — Confirmed Vendor Captivity
Major vendors like DJI, Percepto, and Skydio lock operators into closed ecosystems with proprietary docking systems. DJI Dock houses and charges the Matrice 30/3D/3TD, enabling automated missions via FlightHub 2 for public safety, inspection, and utility work. Percepto’s AirMax and AirMax OGI platforms autonomously inspect energy infrastructure and mines, with AIM software converting data into actionable insights. Skydio Dock supports the X10 drone for remote operations including Drone as First Responder (DFR), with Skydio Remote Ops orchestrating fleets. Triggers for return include mission completion, battery level, and weather alerts (L1/L3). All implementations restrict third-party drone use, confirming vendor-specific captivity (L1/L3). The Skydio X10 system offers sub-20-second launch readiness after remote command, and DJI’s built-in 5-hour backup battery ensures safe return (L1). Operations depend on human oversight despite automation, with operators planning missions, reviewing data, and maintaining oversight (L3).

### 2. eVTOL Turnaround — Fast Charging Predominates
eVTOL turnaround is dominated by fast charging, with manufacturers like Joby and Beta offering systems to minimize downtime. Archer Aviation uses Beta's fast-charging technology to achieve under 12-minute recharge times to 80% of battery capacity (L1). Joby claims its aircraft can recharge in less time than it takes to unload and load passengers, aiming for under 5 minutes with its proprietary charging interface (L1). Battery swap is used by Volocopter for early operations to extend battery life and avoid degradation from fast charging, but it adds operational complexity and infrastructure costs (L1/L2). The industry-standard target is 10–15 minutes for charging, enabling 10–15 flights per day (L1). Repositioning is accomplished via pushback tugs, scheduled through fleet management platforms (L2). Major battery suppliers like Amprius offer silicon-anode cells that can recharge in 6 minutes to 80% (400 Wh/kg), while Volta’s charging stations target 600 kW output. Standards like SAE AS6968 and Joby’s open charging interface aim to create interoperability, though adoption is limited (L3).

### 3. Vertiport Design & Standards — Operational Protocols Are Unwritten
Design standards for vertiports are well established by FAA and EASA, but operational protocols for scheduling and arbitration are absent. FAA’s Engineering Brief 105A, a supplemental guidance to AC 150/5390-2D, provides recommendations for vertiport geometry, including FATO (Final Approach and Takeoff Area), TLOF (Touchdown and Liftoff Area), and Safety Area, with dimensions based on aircraft reference diameter RD (L3). EASA’s PTS-VPT-DSN specifies design requirements for manned VTOL-capable aircraft under VFR, including obstacle-free volumes, visual aids, lighting, and RFFS standards (L3). Both frameworks define physical infrastructure but remain silent on pad scheduling, turnaround coordination, maintenance scheduling, and multi-operator arbitration (L2/L3). Joby’s universal charging interface and SAE’s AS6968 represent steps toward interoperability, but no standard defines scheduling logic, service bundling, or settlement protocols (L3).

### 4. Key Papers on Vertiport Throughput & Scheduling
Three seminal papers provide frameworks for modeling vertiport operations:

1. **Nagrare & Lieb (2026)**: "Throughput and Capacity Analysis of a Vertiport with Taxing and Parking Levels" (MDPI Aerospace) models a dual-level vertiport with separate landing (taxi level) and charging/parking (parking level). Turnaround time T_turnaround = 2	tol + 2	_sse + 2	_pbd + 2	_taxi + t_bc + t_clear + t_ele + t_r. Battery charging t_bc depends on remaining charge and required reserve (20%). Simulations show that with 6 vertipads and 8 charging stations, peak throughput is 1,000 arrivals/day (OT/h ~ 1.02); saturation begins at 1,200 arrivals/day where service rate drops to 84.5%. This work highlights that delays from charging and vertipad contention dominate capacity (L1/L2).
2. **Han & Song (2026)**: "Rolling horizon optimization of UAM service with shared riding, vertiport-airspace capacity, and recharge" (Transportation Research Part E) develops a MILP model and a Dual-Structure Adaptive Genetic Algorithm (DSAGA) for dynamic routing and scheduling across multiple eVTOLs. It jointly optimizes routing, stopovers, recharging, and airspace capacity, achieving near-optimal results in large-scale scenarios. Sensitivity analysis shows trade-offs between battery capacity, stopover fares, and profitability (L2/L3).
3. **Ko et al. (2025)**: "On-Demand Urban Air Mobility Scheduling with Operational Considerations" integrates routing, charging, parking, and passenger pooling. It formulates the problem as an integrated scheduling framework with battery consumption and vertiport throughput constraints. The model supports real-time rescheduling for on-demand requests, bridging the gap between planning and real-world deployment (L2/L3).

### 5. NEUTRALITY FLAG — No Neutral Multi-Operator Orchestration Ecosystem
No known neutral platform orchestrates multiple eVTOL or drone operators at a vertiport with vendor-agnostic scheduling, resource allocation, or settlement logic. Eve Air Mobility’s Urban Air Traffic Management (UATM) software, developed in partnership with Volatus Infrastructure, aims to support traffic management at vertiports and is described as “agnostic” (L2). However, it is bundled with Eve’s eVTOL and infrastructure, not offered as an independent product (L3). Similarly, Joby’s charging interface is open in specification but deployed only within its ecosystem. SAE AS6968 is developing eVTOL charging standards, but no standard covers scheduling or arbitration protocols. The absence of L2/L3 authorship confirms that multi-operator vertiport orchestration remains unowned (L2/L3).

## FOR CLAUDE CODE

### Asset Profiles
| Asset Type | Model/Class | Capacity | Energy | Max Weight | Speed | Footprint | Notes |
|---|---|---|---|---|---|---|---|
| **Cargo Drone** | DJI Matrice 30 | — | 100 Wh/kg | 9 kg | 23 m/s | 0.8 m³ | VTOL, 42-min flight time |
| **Passenger eVTOL** | Joby S4 | 4 + pilot | 275 Wh/kg | 2,400 kg | 200 mph | 11.0 × 8.2 m² | 15-min turnover target |


### Operation Catalog
| Operation | Duration (min) | Resources | Blocking? |
|---|---|---|---|
| Land | 2 | 1 FATO/TLOF | Yes |
| Charge | 10–15 (80%) | 1 Charger (250–600 kW) | Yes (pseud-operation) |
| Swap | 3–5 | 2 Batteries, 1 Technician | Yes (pseud-operation) |
| Inspect | 15–60 | 2 Personnel, Tools | No |
| Reposition | 2–5 | 1 Tug vehicle | No |
| Weather-hold | >10 | — | Yes (— ‐ pseud-operation) |

- **Weather-hold**: triggered by wind>40 kts, precipitation, or visibility<150 m. Resumes on manual override.


### Constraint Set
| Constraint | Description | Applies To|
|---|---|---|
| **Pad Separation** | Minimum 1.5× aircraft diameter (D) between active vertipads (FAA EB 105A, RD-based) | TLOF/FATO, FATO |
| **Tug-As-Resource** | Only N tugs available; repositioning delays if queue forms | Reposition task |
| **Battery Cooling** | 20-min cooldown required before fast charge if >90% SoC on landing | Charge operation |
| **Charger Compatibility** | CCS or Proprietary connector; AS6968 draft standard | Charge operation |
| **Vertipad Exclusive Use** | One vertipad per aircraft during landing and takeoff | Land/Takeoff |


#### Hardest Constraints
1. **Battery Cooling Constraint** — Physical state (temperature) affects scheduling; requires integration of thermal models into the scheduler.
2. **Tug-As-Resource** — Shared mechanical resource; introduces queuing and dependencies across aircraft types.
3. **Charger Compatibility** — Hardware/software handshake adds non-numeric dependencies; charging duration not fully determined by power alone.

## OPEN QUESTIONS
- Is Eve’s UATM software truly API-accessible and deployable at third-party vertiports with non-Eve vehicles?
- Are the FAA and EASA developing operational (not just geometric) guidelines for vertiports?
- How do vertiport operators plan to handle inter-operator arbitration for pad scheduling?
- What real-world data exists on actual eVTOL turnaround times beyond vendor claims?

---
*Sources: FAA EB 105A, EASA PTS-VPT-DSN, Joby, Percepto, Skydio, Eve, MDPI Aerospace 2026, Transportation Research Part E 2026, Vertical Mag, evtol.travel*
