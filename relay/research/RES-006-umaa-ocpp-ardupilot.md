# RES-006 — UMAA digest, OCPP simulators, ArduPilot SITL
FOR: CLAUDE-CODE
ANSWERS: R7, R8, R9

TL;DR:
- UMAA latest public release is **6.0** (ICD/IDL dated 6 June 2024, Distro A / unlimited). Sustainment states map to three ICDs: **EO** (energy/power), **SO** (health/availability), **MM** (tasking).
- OCPP charge-point simulation: recommend the Python **`ocpp`** package (`mobilityhouse/ocpp`, MIT, full OCPP 1.6J + 2.0.1) for scripting custom charge sessions; `monta-app/ocpp-emulator` is the turnkey GUI fallback (2.0.1 still marked "under development").
- ArduPilot SITL = `sim_vehicle.py` + MAVProxy (+ Mission Planner/QGroundControl over UDP). Sub-$1k kits: Holybro X500 v2 (Pixhawk 6C $579 / 6X $669) and S500 v2 (6C $519) — all MAVLink-capable.

FINDINGS:

## R7 — UMAA digest (sustainment-interface shape)
**Latest version:** UMAA **6.0**. The ICDs/IDL were released as Distribution Statement D in Dec 2023, then as **Distribution Statement A (public, unlimited) on 6 June 2024** — this is the current publicly-obtainable version. UMAA 3.1 and 5.2.1 are superseded. An **UMAA SDK** (components, example component specs, RAIL Mission Management sim, source) is available in addition to the ICDs [1][2].

**What UMAA is (for shaping a simulated USV adapter, NOT conformance):** a PEO USC PMS 406 initiative for common, modular UMV (USV/UUV) autonomy software, built on **OMG DDS** as the autonomy data bus with Command/Response and Request/Reply flow control. It defines ~8 high-level functions each with an ICD [1][2][4].

**Sustainment-relevant interface areas (verbatim service names from the 6.0 ICDs):**
- **ENERGY** → *Engineering Operations (EO) ICD* (HM&E systems). Services: `BatteryStatus`/`BatterySpecs` (`reportBattery`), `EngineStatus`/`EngineControl`, `FuelTankStatus`/`FuelTankSpecs` (`reportFuelTank`), `GeneratorStatus`/`GeneratorSpecs`, plus `AnchorControl`/`MastControl`/`UVPlatformSpecs`. Enums: `PowerPlantStateEnumType`, `OnOffStatusEnumType`, `IgnitionStateEnumType` [2].
- **HEALTH + AVAILABILITY** → *Support Operations (SO) ICD*. Services: `HealthReport` (`reportHealth`), `LogReport` (`reportLogReport`). The SO overview states it standardizes startup/shutdown, logging, **operational-mode control (operational / simulation / maintenance / training)**, and resource control. Enums: `ErrorCodeEnumType`, `ErrorConditionEnumType`, `LogLevelEnumType`. NOTE: availability/readiness is expressed via `HealthReport` + operational-mode control, not a dedicated "Availability" service [3].
- **TASKING** → *Mission Management (MM) ICD*. Services: `MissionPlanExecutionControl`/`Status` (`reportMissionPlanExecution`), `TaskPlanExecutionControl`/`Status` (`reportTaskPlanExecution`), `MissionPlanTaskControl` (`setMissionPlanTaskAdd/Delete`), `ObjectiveExecutionControl`/`Status`, `ActiveConstraintsControl`, `ConditionalControl` [4].

**Build-agent guidance:** model your simulated USV as a UMAA-shaped component that (1) publishes `BatteryStatus`/`FuelTankStatus`/`EngineStatus` reports over a DDS-style bus (energy), (2) publishes `HealthReport` + an operational-mode state (health/availability), and (3) accepts MM `MissionPlan`/`TaskPlan` execution commands (tasking). This is interface *shape* only — do not claim conformance (that requires the Compliance Spec T0300-BE-IDS-010 Rev 1 [1]).

## R8 — OCPP charge-point simulators (comparison + ONE recommendation)
License / maintenance / protocol status fetched from the GitHub REST API 2026-08-26 (primary).

| Option | License | Maintenance | OCPP versions | Scripting ease |
|---|---|---|---|---|
| **mobilityhouse/ocpp** (Python) | MIT | v2.1.0 2025-07-16; pushed 2026-07-19; 1036★ | **1.6 (errata v4) + 2.0.1** (Edition 2 FINAL 2022-12-15, Edition 3 errata 2024-11) | Best: write a `ChargePoint` subclass; full control of session flow [5][6] |
| monta-app/ocpp-emulator (Kotlin) | Apache-2.0 | v2.6.0 2026-07-24; pushed 2026-08-25 | 1.6 full; **2.0.1 "under development, not yet fully implemented"** | GUI click-driven (Run V16 / Run V201) [7][8] |
| EVerest/everest (LF Energy) | Apache-2.0 | 2026.02.1 2026-07-16; pushed 2026-08-25 | 1.6J + 2.0.1 (via libocpp; libocpp adds 2.1) | Full-stack; sim module exists but heavy (Docker/C++ config) [9][10] |
| steve-community/steve (Java) | GPL-3.0 | steve-3.14.1 2026-08-12 | 1.2–1.6J only (no 2.0.1) | **Wrong side: it is a CSMS/server, not a charge-point simulator** [11] |
| lorenzodonini/ocpp-go (Go) | MIT | no releases; pushed 2025-08-24 (~1 yr stale) | 1.6+ | Library; stale [12] |
| solidstudiosh/ocpp-virtual-charge-point (Node) | Apache-2.0 | pushed 2026-08-25 | 1.6 | Terminal-based, schema validation [13] |
| SAP/e-mobility-charging-stations-simulator | Apache-2.0 | pushed 2026-08-26 | 1.6 (OCPP-J) | Scaling simulator [14] |

**RECOMMENDATION — `mobilityhouse/ocpp` (Python `ocpp`).** MIT, actively maintained, the de-facto standard (1,036★), and it is the only option with *mature, full* OCPP 2.0.1 support alongside 1.6J, and the lowest-friction path for **scripting deterministic charge sessions** (BootNotification → Authorize → StartTransaction → MeterValues → StopTransaction) as repeatable test fixtures against a CSMS-side adapter [5][6]. Use monta-app/ocpp-emulator only if you want a no-code GUI and can accept its partial 2.0.1 [8].

## R9 — ArduPilot SITL + sub-$1k COTS quadcopter kits
**SITL setup reference (official docs):** clone ArduPilot, then `sim_vehicle.py` builds the SITL binary and launches MAVProxy. Start with `cd ardupilot/ArduCopter && sim_vehicle.py --console --map` (or `-v copter`). Connect Mission Planner / QGroundControl over UDP (default SITL UDP 14550). Canonical pages: "Setting up SITL on Linux", "Copter SITL/MAVProxy Tutorial", "Using SITL" (incl. MAVProxy-free, Mission Planner-only simulation) [15][16][17][18].

**Sub-$1,000 ArduPilot-compatible quadcopter kits** (Holybro Shopify JSON fetched 2026-08-26; all Pixhawk-class = native MAVLink, ArduPilot + PX4):
1. **Holybro X500 v2 Development Kit — Pixhawk 6C** — **$579** (M10 GPS, 433/915 MHz) [19].
2. **Holybro X500 v2 Development Kit — Pixhawk 6X** — **$669** (same frame, higher-spec FC) [19].
3. **Holybro S500 v2 Development Kit — Pixhawk 6C** — **$519** (no-solder, smaller frame) [20].
   Budget alternative: X500 v2 **ARF kit $329** (frame/motors/ESCs, *no* flight controller — add a Pixhawk 6C separately) [21].

SOURCES:
- [1] AUVSI — UMAA program page + doc/IDL/SDK index (primary/official) — https://www.auvsi.org/advocacy/advocacy-initiatives/unmanned-maritime-autonomy-architecture/ (accessed 2026-08-26)
- [2] UMAA EO ICD 6.0, "UMAA-SPEC-EOICD", 6 June 2024, Distro A (primary) — https://www.auvsi.org/wp-content/uploads/2025/03/UMAA-SPEC-EOICD-1.pdf
- [3] UMAA SO ICD 6.0, "UMAA-SPEC-SOICD", 6 June 2024, Distro A (primary) — https://www.auvsi.org/wp-content/uploads/2025/03/UMAA-SPEC-SOICD-v6.0.pdf
- [4] UMAA MM ICD 6.0, "UMAA-SPEC-MMICD", 6 June 2024, Distro A (primary) — https://www.auvsi.org/wp-content/uploads/2025/03/UMAA-SPEC-MMICD-v6.0.pdf
- [5] GitHub API — mobilityhouse/ocpp (primary) — https://github.com/mobilityhouse/ocpp (fetched 2026-08-26)
- [6] mobilityhouse/ocpp README.rst — version support statement (primary) — https://raw.githubusercontent.com/mobilityhouse/ocpp/master/README.rst (fetched 2026-08-26)
- [7] GitHub API — monta-app/ocpp-emulator (primary) — https://github.com/monta-app/ocpp-emulator (fetched 2026-08-26)
- [8] monta-app/ocpp-emulator README.md — "2.0.1 … not yet fully implemented" (primary) — https://raw.githubusercontent.com/monta-app/ocpp-emulator/main/README.md (fetched 2026-08-26)
- [9] GitHub API — EVerest/everest (primary) — https://github.com/EVerest/everest (fetched 2026-08-26)
- [10] GitHub — EVerest/libocpp (primary, archived) — https://github.com/EVerest/libocpp (fetched 2026-08-26)
- [11] GitHub API — steve-community/steve (primary) — https://github.com/steve-community/steve (fetched 2026-08-26)
- [12] GitHub API — lorenzodonini/ocpp-go (primary) — https://github.com/lorenzodonini/ocpp-go (fetched 2026-08-26)
- [13] GitHub API — solidstudiosh/ocpp-virtual-charge-point (primary) — https://github.com/solidstudiosh/ocpp-virtual-charge-point (fetched 2026-08-26)
- [14] GitHub API — SAP/e-mobility-charging-stations-simulator (primary) — https://github.com/SAP/e-mobility-charging-stations-simulator (fetched 2026-08-26)
- [15] ArduPilot — Setting up SITL on Linux (primary/official) — https://ardupilot.org/dev/docs/setting-up-sitl-on-linux.html
- [16] ArduPilot — Copter SITL/MAVProxy Tutorial (primary/official) — https://ardupilot.org/dev/docs/copter-sitl-mavproxy-tutorial.html
- [17] ArduPilot — Using SITL (primary/official) — https://ardupilot.org/dev/docs/using-sitl-for-ardupilot-testing.html
- [18] ArduPilot — MAVProxy docs (primary/official) — https://ardupilot.org/mavproxy/
- [19] Holybro — PX4 Development Kit X500 v2, Shopify JSON variants (primary/vendor) — https://holybro.com/products/px4-development-kit-x500-v2 (fetched 2026-08-26)
- [20] Holybro — S500 v2 Development Kit (primary/vendor) — https://holybro.com/products/s500-v2-development-kit (fetched 2026-08-26)
- [21] Holybro — X500 V2 Kits (ARF/Frame) (primary/vendor) — https://holybro.com/products/x500-v2-kits (fetched 2026-08-26)

CONFIDENCE: **med-high**
- R7 **high**: service/message names read directly from the three 6.0 Distro-A ICD PDFs.
- R8 **high** for license/version/activity (GitHub API + raw READMEs); **med** for "ease of scripting" (design inference, not hands-on run).
- R9 **high** for SITL steps (official docs) and prices (Shopify JSON); **med** for demo suitability (inference).
- Raise it by: (R8) running a scripted 1.6J + 2.0.1 session against the actual CSMS; (R9) confirming kit includes battery/radio/RC + in-stock status; (R7) D-statement site access for Component Definitions v1.0.
