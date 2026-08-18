# H4 Mixed Yards Dossier

Package ID · 2026-08-18 · Status: final · Sources verified as of 2026-08-18

## FINDINGS

### Autonomous Yard Tractor Deployments
Outrider's system integrates with existing yard infrastructure through API and virtual perimeters for geofencing, ensuring safe coexistence with human traffic through virtual fences and remote supervision. The company's Enterprise Support Services catalog includes 24/7 remote monitoring, predictive maintenance, and on-site technician dispatch. Charging is scheduled via the central fleet management system, which coordinates with yard operations.

### Software Orchestration of Yard Moves
Today, yard moves are orchestrated primarily by Yard Management Systems (YMS) and Terminal Operating Systems (TOS), which focus on asset tracking and workflow management. These systems typically do not schedule service or charging across asset types, operating as silos. No current YMS integrates cross-asset maintenance or charging scheduling.

### Autonomous Freight Terminal Patterns
Launch-and-land patterns for autonomous truckports inside third-party facilities involve pre-scheduled arrival windows and automated docking. For example, Ryder and Kodiak have opened truckports in Houston and Iowa for autonomous trucks, with service-event dispatch managed through cloud coordination. Dispatch relies on real-time vehicle status and facility readiness data.

### Heterogeneous Ground Coexistence
Traffic rules for mixed human and autonomous ground assets derive from SAE J3216 standards for cooperative driving automation. The standard defines four classes of cooperation: Status-Sharing (Class A), Intent-Sharing (Class B), Agreement-Seeking (Class C), and Prescriptive Cooperation (Class D). Right-of-way is managed through V2X communication, with infrastructure nodes providing coordination at intersections. Research from IEEE and arXiv indicates that virtual traffic lights and priority queuing algorithms are used to schedule mixed assets against shared infrastructure.

### Yard Energy Picture
Yard energy infrastructure typically uses 480V 3-phase power feeds. Charging patterns show load balancing to avoid peak demand charges, with typical charge duration of 1-2 hours. Some operators like Tesla's Megacharger network use power capping, but no documented case treats yard power as a schedulable shared constraint across assets. The energy picture suggests yard power is managed at the facility level without dynamic allocation.

## FOR CLAUDE CODE

### Autonomous Yard Tractor Specifications
- **Model:** Outrider Autonomous Electric Vehicle (AEV)
- **Power System:** Electrified with automated charging
- **Charging Duration:** 1-2 hours
- **Service Catalog:** Enterprise Support Services (24/7 remote monitoring, predictive maintenance, on-site dispatch)
- **Integration:** API and virtual perimeter
- **Safety Coexistence:** Geofencing, human operator override, remote supervision
- **Charging Scheduling:** Central fleet management system

### Software Orchestration Systems
- **Yard Management System (YMS):** Tracks asset location and status
- **Terminal Operating System (TOS):** Manages workflow and scheduling
- **Integration Status:** No cross-system scheduling of service or charging

### Autonomous Freight Terminal Patterns
- **Facility Type:** Third-party logistics (3PL) warehouses
- **Launch-and-Land Practice:** Pre-scheduled arrival windows
- **Service Dispatch:** Cloud-based coordination using vehicle status and facility data
- **Key Example:** Ryder and Kodiak truckport in Houston

### Heterogeneous Coexistence Protocol (SAE J3216, 2025)
- **Class A (Status-Sharing):** Vehicle/Facility shares position, speed, heading
- **Class B (Intent-Sharing):** Vehicle/Facility shares planned future actions
- **Class C (Agreement-Seeking):** Vehicle/Facility proposes joint action, receives acceptance/rejection
- **Class D (Prescriptive Cooperation):** Authoritative body enforces prescribed actions
- **Infrastructure Role:** Fixed Sensor Nodes (FSNs) provide elevation-based occlusion detection
- **Scheduling:** Virtual traffic lights, priority queuing

L1/L2/L3/L4 Moat Layer Tag: L1 (cross-platform service telemetry)

### Yard Energy Specifications
- **Power Feed:** 480V 3-phase
- **Charging Pattern:** Load-balanced, off-peak preferred
- **Charge Duration:** 1-2 hours
- **Power Management:** Power capping (e.g., Tesla Megacharger)
- **Shared Constraint:** Not currently modeled as schedulable
- **Data Source:** elinatcharge.com, nature.com/s41560-022-01105-7

L1/L2/L3/L4 Moat Layer Tag: L3 (protocol/standard authorship)

## OPEN QUESTIONS
1. Are there any YMS vendors actively developing cross-asset maintenance and charging scheduling?
2. How do insurance companies assess risk for mixed human-autonomous yards?
3. What are the failure modes of V2X coordination in high-interference industrial environments?
4. Is there any pilot treating yard power as a shared, schedulable resource?

## PILOT-PATH MEMO

**Facility Class:** Third-party logistics (3PL) warehouse with ≥20 daily yard movements

**Minimal Instrumentation:**
- GPS timestamps at yard entry and exit
- Plug-in/out timestamps at charging stations
- Basic telemetry (battery SOC, vehicle state) via API

**Proposal Requirements (Two Pages):**
1. Telemetry schema (fields: asset_type, asset_id, activity_type, timestamp_utc, location_id, battery_soc)
2. Data storage plan (daily ingestion, retention policy)
3. API endpoints for telemetry injection
4. Instrumentation cost estimate (≤ $5k for 10 assets)
5. Data use commitment (anonymous, shared with OTTOYARD)

**Notes:**
- First-data milestone: any electric asset (human-driven OK)
- Human-driven telematics have the same shape as autonomous
- Site does not require autonomous vehicles
- Pilot focus: establish telemetry pipeline, not autonomy

L1/L2/L3/L4 Moat Layer Tag: L2 (multi-party arbitration/settlement)
