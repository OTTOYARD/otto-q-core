Package ID: H2 · 2026-08-18 · Status: final · Sources verified as of 2026-08-18

## FINDINGS

1. **FMS Landscape and Vendor Alignments (L1/L2):**

   Caterpillar's MineStar Command (L1) enables third-party machine data ingestion into its systems via VIMS Telemetry and Product Link Elite (PLE) streaming, but requires a non-disclosure agreement (NDA) for protocol access [1]. Integration of third-party machines *into* third-party FMS systems using MineStar data is possible, but direct integration into Command for autonomous operation is not supported in practice. Komatsu's FrontRunner AHS, integrated within the Modular Mining DISPATCH lineage (L1), is explicitly designed for OEM agnosticism and interoperability across mixed fleets [2]. Its Modular Ecosystem, built on open APIs, minimizes vendor lock-in [3]. This contrasts with Caterpillar, where integration is limited to data telemetry and health monitoring, not full service or autonomous control.


2. **GMG Interoperability (L3):**
The Global Mining Guidelines Group (GMG) has established a strategic direction focused on mine interoperability through its Interoperability and Functional Safety Acceleration Strategy (IFSAS) [4]. Key alignment principles from 17 mining companies include the necessity of self-describing, open-standard data interfaces and the inalienable requirement that interoperable systems must not compromise existing safety levels [4]. The published *Interoperability Alignment Report* (2019) outlines these principles and the industry's commitment to including interoperability in RFPs and contracts, but it does not specify technical message shapes or publish API contracts, and there is no public documentation addressing service/maintenance/refuel events [4].


3. **Service Event Orchestration for Autonomous Fleets (L1):**
Service events for autonomous haulage fleets (AHS) are managed by a hierarchy driven primarily by OEM-provided FMS with integrated health monitoring [1, 2, 3]. A truck is recalled from the haul cycle based on predictive maintenance logic from health data (e.g., oil analysis via KOWA, tire pressure/temperature via TPMS [1, 5]), predefined hour-based service schedules (e.g., 250-hr, 500-hr, 1,000-hr intervals [6]), or critical fault codes. For refueling and charging, the Komatsu DISPATCH Replenish app uses real-time fuel/charge level data integrated with DISPATCH to intelligently schedule and assign bays [3], while Caterpillar uses Command to direct trucks to service [7]. Tire changes are multi-hour crane operations managed by specialized crews, not automated. Wash and shop bay assignment are manually scheduled by mine planners, not dynamically assigned by the FMS.


4. **Electric Haulage Charging and Scheduling (L1/L2):**
Electric mining trucks use either static charging (stationary swaps or fast charging) or dynamic charging via trolley-assist (trolley lines). ABB’s eMine™ Trolley System, providing over 12MW of DC power, allows trucks to charge in-motion [8]. Komatsu and ABB are jointly developing a Dynamic Energy Transfer system aiming for 40MW galvanic section capability [8, 9]. Trolley-assisted charging dramatically reduces downtime by eliminating the need for dedicated charging stops, thus simplifying service-side scheduling [8]. For trucks not on trolley, service-side scheduling must accommodate dedicated charging/swap windows, creating a significant constraint on fleet availability and bay utilization [10]. ABB's simulation shows that sustaining operations requires trolley coverage on 60% of the uphill haulage path [10].


5. **Safety and Machine Standards (L3):**
The primary standard is ISO 17757, the *Earth-moving machinery and mining — Autonomous and semi-autonomous machine system safety* [11]. It defines safety criteria for the ASAMS (Autonomous or semi-autonomous machine systems), covering hardware, software, and infrastructure, and requires that interoperable systems do not compromise built-in safety features [4, 11]. It emphasizes functional safety throughout the system life cycle [11]. It is not applicable to general remote control (covered by ISO 15817), but its principles extend to the service environment. The withdrawn status of ISO 17757:2017 and the lack of a freely available 2019 revision document a gap in the accessibility of the current standard's full requirements [11].


## FOR CLAUDE CODE

### Paper Mining Pack

**Asset Profiles**

| Asset | Parameters |
| :--- | :--- |
| **Haul Truck** (e.g., Cat 777, Komatsu 930E) | - Dry Weight: 72,000 kg 
  - Payload Capacity: 100,000 kg 
  - Dimensions (LxWxH): 15m x 7.6m x 9.5m 
  - Energy: Diesel (4,300 L) / BEV (up to 1.5 MWh) 
  - Charging: Trolley (up to 40 MW), Fast Charge (2-4 MW) 
  - Service Port Locations: Fuel, DEF, Hydraulic, Brake, Coolant, Batteries |
| **Loader** (e.g., Cat 994) | - Dry Weight: 22,000 kg 
  - Bucket Capacity: 57 m³ 
  - Dimensions (LxWxH): 12.6m x 9.3m x 7.5m 
  - Energy: Diesel (3,500 L) 
  - Service Port Locations: Fuel, DEF, Hydraulic, Brake, Coolant |
| **Dozer** (e.g., Cat D11) | - Dry Weight: 110,000 kg 
  - Blade Capacity: 31.2m³ 
  - Dimensions (LxWxH): 12.6m x 9.3m x 5.4m 
  - Energy: Diesel (3,200 L) 
  - Service Port Locations: Fuel, DEF, Hydraulic, Brake, Coolant |


**Operation Catalog**
| Operation | Description | Duration Range | Source/Logic |
| :--- | :--- | :--- | :--- |
| `Refuel_Truck` | Fuel and DEF replenishment for a haul truck. | 15 min | [1, 3, 7] FMS schedules based on tank levels; Komatsu Replenish app automates. |
| `Charge_Truck_Static` | Fast-charge a BEV haul truck offline. | 25 - 30 min | [10] ABB and Hitachi specify fast-charge durations. |
| `Change_Wheels_Tire` | Full change of a haul truck tire and wheel assembly. A complex operation requiring crane support, dismounting, new tire prep, remounting, inflation to 110 psi. | 4 - 6 hours | [5] Kal Tire and industry sources cite 4-6 hour standard for ultra-class tires. GATR tool reduces physical strain. |
| `Component_Hour_Maintenance` | Routine maintenance intervals (e.g., oil & filter change, fluid checks, inspections). | 1.5 - 2 hours | [6] Based on Komatsu's 250-hr and 500-hr PM service durations. Task list is extensive but standardized. |
| `Wash_Vehicle` | Thorough cleaning of an asset with a high-pressure washer. | 45 - 75 min | [1, 5] Standard wash duration for large mining equipment, preventing build-up and corrosion. |


**Constraint Set**
A declarative pack must express the following constraints:
- `C1: Asset_Must_Have_Clearance`: A machine must be empty of payload and powered down before entering a service bay.
- `C2: Resource_Sharing_Exclusive_Use`: A service bay, for an operation like tire change, acts as a non-sharable resource for its duration. Another machine cannot enter until the bay is released.
- `C3: Energy_Resupply_Window`: A vehicle's state-of-charge (SoC) or fuel level must be above a threshold (e.g., 20%) to begin a return-to-base cycle, but below a maximum threshold (e.g., 85% for diesel, 90% for batteries) to receive a service, ensuring efficient fleet utilization.


**Three Hardest Constraints (Likeliest Kernel-Breakers)**
1.  **`C4: Dynamic_Charging_Path_Dependency`:** A vehicle on a trolley-assisted electric drive system *must* follow a defined physical path (the trolley line). The vehicle's route is not just an optimal path but a hard constraint tied to infrastructure geometry. This is fundamentally different from any routing constraint in intralogistics or robotaxis. *Expressing this requires an explicit model linking the vehicle's motion plan to a fixed infrastructure network, not just a point-to-point pathfinding graph.*
2.  **`C5: Maintenance_Scheduling_From_Threshold_Ranges`:** Preventive maintenance is scheduled not by a single event (e.g., mileage), but by a combination of component hours, oil analysis (KOWA) results, and real-time health data (TPMS). A recall is triggered when *any one* of multiple thresholds is met. *Expressing this requires a constraint that combines time, distance, and multiple discrete or continuous sensor readings with complex logical operations (OR logic), which is more complex than simple time- or date-based triggers.*
3.  **`C6: Operator-Override_Overrules_System`:** In an emergency or due to operator judgment (e.g., from a central controller in the Komatsu AHS training manual), a human can override a scheduled service event and keep the truck on the hauling cycle [12]. This breaks the idea of the orchestration layer as deterministic. *Expressing this requires a procedural or state-based rule where an external, non-automated event can invalidate a hard constraint, introducing non-determinism that is anathema to a solver-based kernel.*

## OPEN QUESTIONS

- What are the specific API endpoints, message formats (e.g., JSON schema), and authentication methods for integrating third-party service status into the Caterpillar MineStar Health system?
- Is the current version of the ISO 17757:2019 standard freely available, and what are the specific, updated safety requirements it defines for service events?
- What are the exact decision algorithms used by Komatsu's DISPATCH Adapt for AI-powered fleet optimization, and how do they determine when to schedule a service event?

---
[1] Cat Third-Party Machine Integration: https://s7d2.scene7.com/is/content/Caterpillar/CM20210906-21086-162cf 
[2] Komatsu FrontRunner AHS: https://www.komatsu.com/en-us/technology/smart-mining/loading-and-haulage/autonomous-haulage-system 
[3] Komatsu Modular Ecosystem: https://www.komatsu.com/en-us/technology/smart-mining/modular 
[4] GMG Interoperability Alignment Report: https://gmggroup.org/wp-content/uploads/2024/01/IFSAS-Interoperability-Alignment-Report-201900812.pdf 
[5] Kal Tire Autonomous Inspections: https://im-mining.com/advertiser_profile/kal-tire-autonomous-tyre-inspection-stations-generating-value-for-customers/ 
[6] Komatsu Maintenance Schedule: https://heavyvehicleinspection.com/article/best-komatsu-maintenance-schedule-2026 
[7] Cat Command for Hauling: https://www.cat.com/en_US/by-industry/mining/surface-mining/surface-technology/command/command-hauling.html 
[8] ABB Trolley Assist at Copper Mountain: https://new.abb.com/mining/reference-stories/open-pit-mining/trolley-assist-solution-to-meet-copper-mountain-mining-sustainable-development-goals-in-canada 
[9] Komatsu and ABB Dynamic Energy Transfer: https://www.miningreporters.com/noticia/news/2026/05/komatsu-abb-dynamic-energy-transfer-electric-mining-trucks 
[10] ABB Electrifying Haulage: https://www.abb.com/global/en/company/innovation/news/elecrifying-haulage 
[11] ISO 17757: https://www.iso.org/standard/60473.html 
[12] Komatsu AHS Training: https://www.youtube.com/watch?v=9NfmG3RRrYM