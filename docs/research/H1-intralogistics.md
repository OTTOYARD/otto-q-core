H1 · 2026-08-18 · Status: final · Sources verified as of 2026-08-18

## FINDINGS

**VDA 5050 (L4)**: The standard, now at **Version 3.0.0 (March 2026)**, is jointly governed by the **German Association of the Automotive Industry (VDA)** and **VDMA** with academic input from **KIT-IFL**. It provides a comprehensive, **operational**, and **command-capable** interface for dispatching orders (`order`), reporting state (`state`), and managing traffic via a master controller. It precisely defines fields for node sequencing, action execution (`action`, `blockingType`), edge definitions, and corridor management. However, it explicitly **excludes service-side functions**: energy strategy, battery health economics, service events, and cross-fleet settlement are outside its scope. This creates a clear gap for a service orchestration layer.

**MassRobotics vs. VDA 5050 (L4)**: The MassRobotics AMR Interoperability Standard (v1.0, May 2021; v2.0 in development) is **not operational**. It focuses solely on sharing **basic status and location telemetry** (position, speed, state) to enable coexistence. Unlike VDA 5050, it does *not* allow a central system to issue commands, manage orders, or perform task assignment. The two standards are **complementary and non-conflicting**; a vehicle can implement both, using VDA 5050 for command-and-control and MassRobotics for vendor-agnostic telemetry sharing.

**Mixed-Vendor Fleet Orchestration (L2)**: Commercial orchestration is managed by **vendor-agnostic control platforms** such as **KINEXON**, **tracio**, and **openmaind**. These act as a **master controller** on top of individual vendor FMSs, using standards like VDA 5050 to unify communication. They handle **centralized traffic management, deadlocks, and task assignment** across fleets. Regarding charging, these platforms **do not manage or schedule charging opportunistically in a cross-fleet manner**. Charging is primarily handled by vendor-native FMSs, often ignored by the orchestrator, or scheduled in isolation. There is **no commercial precedent for treating a shared facility's power feed as a schedulable, cross-fleet constraint**.

**Opportunity Charging Management (L1/L2)**: Opportunity charging (charging during work gaps like lunch or at staging points) is a widespread practice, enabled by **lithium-based batteries** that support partial charging without degradation. Management is **decentralized**, occurring via vendor-specific FMSs or manual scheduling. The **shared facility power delivery infrastructure (the primary feeder) is not modeled as a resource that can be constrained or scheduled** across fleets in any known commercial system.

**Battery Swap vs. Charge Economics (L2)**: Battery swap offers **faster turnaround (<5 min)** and reduced vehicle cost (pay-per-use model) but requires massive capital expenditure (CAPEX) for battery inventory and swap stations. Charging, especially fast-charging, is less capital-intensive but results in longer vehicle downtime. Swap is economically viable for **high-utilization, tightly managed B2B fleets** (e.g., delivery vehicles, forklifts). The **timing of a swap is an operational decision made by a central dispatch system** (analogous to recall timing) to minimize downtime, based on a vehicle's work schedule and the operator's need for continuous operations.

## FOR CLAUDE CODE

### VDA 5050 Message Capture (Version 3.0.0)

*All schema definitions sourced from the official JSON schemas on GitHub.*


**`/order` (Fleet Control → Robot)**: Command message for task assignment.

```json
{
  "headerId": int,           // Incremental message ID per topic
  "timestamp": "ISO8601",   // e.g., "1991-03-11T11:40:03.123Z"
  "version": "1.3.2",       // Protocol version
  "manufacturer": string,
  "serialNumber": string,
  "orderId": string,          // Unique ID for the order
  "orderUpdateId": int,       // Sequential update counter
  "nodes": [                 // Array of nodes to traverse
    {
      "nodeId": "pumpenhaus_1", // Node identifier
      "sequenceId": 0,         // Order in the sequence
      "released": true,         // Part of base (true) or horizon (false)
      "nodePosition": {        // Optional; may not be used by line-guided robots
        "x": 10.5,             // Position in m, project-specific coordinate system
        "y": 7.3,              // 
        "theta": 3.14,         // Orientation in rad (optional; defines required pose)
        "mapId": "floor1_forklift", // Unique map ID
        "allowedDeviationXY": { // Defines acceptable position deviation (ellipse)
          "a": 0.2,            // Semi-major axis in m
          "b": 0.1,            // Semi-minor axis in m
          "theta": 1.57        // Rotation of the deviation ellipse in rad
        }
      },
      "actions": [             // Actions to perform *on* this node
        {
          "actionId": "uuid-123", // Unique action ID (e.g., UUID)
          "actionType": "loadUnload", // Predefined action name
          "blockingType": "HARD",    // NONE, SOFT, SINGLE, HARD (prevents other actions)
          "actionParameters": [
            {
              "key": "loadId",
              "value": "LID_456"
            }
          ]
        }
      ]
    }
  ],
  "edges": [                 // Directional connections between nodes
    {
      "edgeId": "e_1_to_2",
      "sequenceId": 1,
      "released": true,
      "actions": [               // Actions to perform *during travel* on this edge
        {
          "actionId": "uuid-456",
          "actionType": "driveThroughSpeedGate",
          "blockingType": "SINGLE"
        }
      ],
      "corridor": {              // Safety corridor for deviation
        "leftWidth": 1.2,        // Max deviation in m to the left
        "rightWidth": 1.2,       // Max deviation in m to the right
        "corridorReferencePoint": "CONTOUR" // KINEMATIC_CENTER or CONTOUR
      }
    }
  ]
}
```

**`/state` (Robot → Fleet Control)**: Comprehensive status report.


```json
{
  "headerId": int,
  "timestamp": "ISO8601",
  "version": "1.3.2",      
  "manufacturer": string,
  "serialNumber": string,
  "orderId": string,         // Current or last order ID
  "orderUpdateId": int,      // Acknowledged order update
  "lastNodeId": "node7",     // Most recently traversed node
  "lastNodeSequenceId": 2,
  "driving": true,           // Robot is moving/rotating
  "paused": false,           // Robot is paused (manual or instant action)
  "powerSupply": {           // Battery power status
    "batteryCharge": 85.2,   // % battery level
    "voltage": 48.0,         // V
    "current": -10.1         // A (negative for discharge)
  }, 
  "safetyState": {           // Safety system status
    "activeEmergencyStop": "NONE", // NONE, MANUAL, REMOTE
    "fieldViolation": false  // Protective field violation
  },
  "nodeStates": [            // State of nodes in the current order
    {
      "nodeId": "node7",
      "sequenceId": 2,
      "actionStates": [        // Execution status of actions on this node
        {
          "actionId": "uuid-123",
          "actionState": "COMPLETED" // IDLE, INITIALIZING, RUNNING, COMPLETED, FAILED, RETRIABLE
        }
      ]
    }
  ],
  "edgeStates": [            // State of edges in the current order
    {
      "edgeId": "e_2_to_3",
      "sequenceId": 3,
      "actionStates": [        // Status of actions on this edge
        {
          "actionId": "uuid-456",
          "actionState": "RUNNING"
        }
      ]
    }
  ]
}
```

### Gap Table: Unowned Service Functions (L1/L2/L3)


This table identifies critical service-side functions not covered by any current standard (VDA 5050, MassRobotics) or commercial product.

| Function | Semantics / Constraints | L1 L2 L3 | Owner | Rationale |
| :--- | :--- | :---: | :--- | :--- |
| **`Schedule Cross-Fleet Charging** | All vehicles' charging plans must fit within the facility's power feed capacity (kW), preventing brownouts. Scheduling must be dynamic and based on real-time work schedules `workEnd[i]`, energy `energyNeeded[i]`, and utility tariff `tariff(t)`. | L2 L3 | **None** | VDA 5050 lacks a charging scheduling primitive, and MassRobotics doesn't transmit intent. Fleet orchestrators treat charging as a vendor-internal event. |
| **`Decide Recall Timing** | When a vehicle leaves its current work cycle to perform a service, its start time `serviceStart` and work resumption `workResume` must be optimized. This requires minimizing disruption to `jobSchedule[i]` while ensuring `maintenanceWindow` or `chargingDuration` is met. | L2 L3 | **None** | VDA 5050's `instantAction` can trigger a halt, but the *logic for when* to recall (a high-level arbitration) is not standardized or productized. It is currently ad hoc. |
| **`Arbitrate Multi-Party Bay Access** | Two or more operators must be able to fairly request a physical service bay. The decision must be based on contractual rules `contract[j]`, priority `contractualPriority`, and real-time urgency `currentWorkload`. A verifiable, signed log of the decision is required. | L2 | **None** | No standard defines a cross-operator arbitration message. This is typically solved by operator agreement or first-come-first-served, not a neutral protocol. |
| **`Model Service Session w/ Economics** | A service event (charging, swap, calibration) must be modeled as a `ServiceSession` with a start/end time, `kWhDelivered`, `cost`, and `billingID`. This creates a CDR-like record for settlement, which VDA 5050's `powerSupply.batteryCharge` telemetry alone cannot support. | L1 L2 L3 | **None** | While `state` emits telemetry, there is no defined lifecycle (provision, authorize, start, stop, settle) for a service *session*. This is the moat.
| **`Execute Multi-Tenancy Protocol** | A neutral third party must be able to host services for multiple fleet operators. This requires a protocol to register service providers, authenticate vehicles against their fleet, and securely route `ServiceSession` requests between all three parties. | L3 | **None** | VDA 5050 assumes a single master controller per site. There is no protocol for service-side multi-tenancy, which is a core requirement for a neutral platform. |

## OPEN QUESTIONS

- Are there any research prototypes or academic papers that attempt to model a shared facility power feed as a schedulable constraint?
- Does the upcoming MassRobotics v2.0 standard (mission communication API) introduce any scheduling or resource constraint handling that could overlap with the cross-fleet charging concept?
- What are the specific technical or business reasons that prevent current orchestrators (KINEXON, tracio) from incorporating power feed management into their optimization models? Is it a data access issue or a model limitation?