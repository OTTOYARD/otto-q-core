# R-2 · VDA 5050: version discrepancy + actionType vocabulary

**Answer to:** `docs/research/requests/R-2-vda5050-version-and-action-vocabulary.md`
**Resolved against:** primary VDA 5050 sources — the official spec repo `github.com/VDA5050/VDA5050` (tag/release `3.0.0`, its `json_schemas/` and `VDA5050_EN.md`), and the deprecated schema repo `github.com/VDA5050/vd-m-a-5050` (v1.1 tag). Every version, action spelling, and field verified against these files; "NOT FOUND" = unverifiable from primary sources.

## Answers

### Q1 — Version discrepancy: "3.0.0 (March 2026)" is CORRECT; "1.3.2" is a stale example literal

- **Latest published VDA 5050 version is 3.0.0.** The official spec repo has release `3.0.0` — "VDA 5050 3.0.0" — published **2026-03-18**. H1's prose "Version 3.0.0 (March 2026)" is **real and correct**.
  - Source (primary): https://github.com/VDA5050/VDA5050/releases/tag/3.0.0 ; repo https://github.com/VDA5050/VDA5050
- **"1.3.2" is NOT a published VDA 5050 version.** It appears *only* as the schema `example` value of the header `version` field: `"description": "Version of the protocol [Major].[Minor].[Patch]", "examples": ["1.3.2"]`. The spec markdown repeats it as "(e.g., 1.3.2)". It is a stale literal copied through the schema files — H1's JSON examples simply reproduced the schema's example value verbatim. It is **not** evidence the capture is 1.3.2.
  - Source (primary): https://raw.githubusercontent.com/VDA5050/VDA5050/3.0.0/json_schemas/order.schema ; …/state.schema ; …/instantActions.schema ; spec https://raw.githubusercontent.com/VDA5050/VDA5050/3.0.0/VDA5050_EN.md (title "Version 3.0.0").
- **Published release lineage** (GitHub releases): `2.0.0` (2021-11-25, the "AGV Communication Interface" rewrite), `2.1.0` (2024-08-19), `3.0.0` (2026-03-18). Earlier 1.0/1.1 were the pre-2.0 "AGV interface". The deprecated schema repo states: "The VDA publication of the VDA 5050 2.0 is the same version as the internal 5.0.0" and tags `v1.1` plus internal branches `0.806, 1.0.0, 4.0.0, 5.0.0`.
  - Source (primary): https://github.com/VDA5050/VDA5050/releases ; https://github.com/VDA5050/vd-m-a-5050
- **Wire value:** a 3.0.0-conformant robot sends `"version": "3.0.0"` (Major.Minor.Patch). The adapter's echo-the-string behaviour is safe; the conformance claim must name **3.0.0** (or 2.0.0/2.1.0), never "1.3.2".

#### Did `/order` or `/state` change between the "1.x" schemas and 3.0.0? — Yes; H1's fields are the *current* ones

Comparing the deprecated `v1.1`-tag schemas against the `3.0.0` schemas (primary, field-level):
- **`/state`: `batteryState` → `powerSupply` (RENAMED).** v1.1 required `batteryState`; 3.0.0 requires `powerSupply` (with `batteryCharge`, `charging`, `voltage`, `current`, …). H1 captures `powerSupply.batteryCharge` — i.e. the **current** (2.0+) naming, not 1.x. This alone proves the capture is the 2.0/3.0 line.
- **`/state`: `agvPosition` → `mobileRobotPosition` (RENAMED).** Present in v1.1 props, renamed in 3.0.0.
- **`/state` GAINED:** `instantActionStates` (now **required**), `zoneActionStates`, `edgeRequests`, `zoneRequests`, `maps`, `zoneSets`, `plannedPath`, `intermediatePath`.
- **`/state` `paused` DEMOTED:** required in v1.1, optional (still a property) in 3.0.0.
- **`/order` nodes/edges:** both v1.1 and 3.0.0 use `released` (boolean: `true`=base, `false`=horizon) — no change there. 3.0.0 actions add optional `actionDescriptor` and `retriable`; `blockingType` enum `NONE/SOFT/SINGLE/HARD` and `actionParameters[{key,value}]` are unchanged.
- **Net:** every field H1 captured (`powerSupply`, `released`, `blockingType`, `actionParameters`, `corridor.leftWidth/rightWidth`, `nodePosition.x/y/theta/mapId`) matches 3.0.0. The **only** stale item is the `"version": "1.3.2"` literal. Treat the captured fields as **3.0.0**.
  - Source (primary): https://github.com/VDA5050/vd-m-a-5050 (v1.1 tag `state.schema`/`order.schema`) vs https://github.com/VDA5050/VDA5050 (3.0.0 `json_schemas/state.schema`/`order.schema`)

### Q2 — The predefined action vocabulary (3.0.0)

- **There is one vocabulary, not two.** The field is always named `actionType` — in `/order` (node/edge `actions[]`), in `/instantActions` (`actions[].actionType`), and in zone actions. There is **no field literally named "instantActionType"** in the schemas. Each predefined action carries a *scope* column (instant / node / edge / zone) that determines where it may be used.
  - Source (primary): https://raw.githubusercontent.com/VDA5050/VDA5050/3.0.0/json_schemas/instantActions.schema ; …/order.schema ; spec "Table 4 — Predefined actions and their scope", https://raw.githubusercontent.com/VDA5050/VDA5050/3.0.0/VDA5050_EN.md (§6.2.3)
- **`actionType` is a free-form string in the schema (no JSON enum).** The predefined set lives only in the spec text (Table 4). The complete 3.0.0 list (29 actions):

`startPause`, `stopPause`, `startHibernation`, `stopHibernation`, `shutdown`, `startCharging`, `stopCharging`, `initializePosition`, `enableMap`, `downloadMap`, `deleteMap`, `downloadZoneSet`, `enableZoneSet`, `deleteZoneSet`, `clearInstantActions`, `clearZoneActions`, `stateRequest`, `logReport`, `pick`, `drop`, `detectObject`, `finePositioning`, `waitForTrigger`, `trigger`, `retry`, `skipRetry`, `cancelOrder`, `factsheetRequest`, `updateCertificate`

- **Instant-only (scope instant=yes, node/edge/zone=no):** `startPause`, `stopPause`, `startHibernation`, `stopHibernation`, `shutdown`, `clearInstantActions`, `stateRequest`, `logReport`, `retry`, `skipRetry`, `cancelOrder`, `factsheetRequest`, `updateCertificate`, `trigger`.
- **Node/edge (order) actions:** `pick`, `drop`, `finePositioning`, `waitForTrigger`, `detectObject`, and (also instant-capable) `startCharging`, `stopCharging`, `initializePosition`, `enableMap`, `enableZoneSet`, `clearZoneActions`.
- **Mandatory on every robot:** `cancelOrder`, `startPause`, `stopPause` (spec §6.2.3).
- **Correction to the request's examples:** there is **no** predefined action `startOrder` (starting an order = sending `/order`; the counterpart is `cancelOrder`), and **no** `loadUnload` or `driveThroughSpeedGate` in 3.0.0 (load handling is `pick`/`drop`). Those two H1 examples are NOT among the predefined 3.0.0 actions.

#### Q2a — Standard charging action: `startCharging` / `stopCharging` (YES, they are standard)

- **Exact spelling:** `startCharging` (counter-action `stopCharging`). Both are predefined in Table 4.
- **Scope:** instant = yes, node = yes, edge = no, zone = no.
- **actionParameters:** none required (`parameters` column = "–"). There is **no** battery-swap action — `batterySwap` is NOT in the predefined set (NOT FOUND).
- **Semantics:** `startCharging` "Activates the charging process. Charging can be done on a charging spot (mobile robot stopped) or on a charging lane (while driving). Protection against overcharging is the responsibility of the mobile robot." Linked state: `powerSupply.charging` (boolean) — robot reports `charging: true` when started, `false` when stopped.
- **Related:** `detectObject` (param `objectType`) can detect a "charging spot" (its description lists "load, charging spot, free parking position").
- **Implication for the adapter:** `charge_dcfc`/`charge_l2`/`opportunity_charge` should map to the **standard `startCharging`**, not `ottoq.startCharging`. `battery_swap` and `inspection` have no standard action and should stay custom-namespaced.
  - Source (primary): https://raw.githubusercontent.com/VDA5050/VDA5050/3.0.0/VDA5050_EN.md §6.2.3.1 (Table 4 rows `startCharging`/`stopCharging`/`detectObject`); §6.2.3.2 (Table 5).

### Q3 — Vendor/custom action naming: no prefix/registry convention; the factsheet is the mechanism

- The spec: "If there is no way to map some action to one of the actions of the following section, the mobile robot manufacturer can define additional actions that shall be used by fleet control."
- **No reverse-DNS/prefix convention is mandated.** `actionType` is a free-form string; any non-predefined string is technically acceptable.
- **The discovery mechanism is the factsheet:** `mobileRobotActions[]` (in `/factsheet`) declares each supported `actionType` ("Unique type of action corresponding to action.actionType", "This includes standard actions specified in VDA5050 and manufacturer-specific actions") plus `actionScopes` (`INSTANT/NODE/EDGE/ZONE`), `actionParameters`, `blockingTypes`, `pauseAllowed`, `cancelAllowed`. Fleet control reads the factsheet to learn which action names (standard + vendor) a robot supports.
  - Source (primary): https://raw.githubusercontent.com/VDA5050/VDA5050/3.0.0/VDA5050_EN.md §6.2.3 ("manufacturer can define additional actions") and §7.10 / factsheet `mobileRobotActions`.

### Q4 — Unrecognised `actionType`: rejected LOUDLY, not silently (confirms the adapter's reasoning)

- **Unrecognised action in an `/order`:** "1. The mobile robot shall not take over the new order in its internal buffer. 2. The mobile robot shall report an error of type **`INVALID_ORDER_ACTION`** with level **`WARNING`** and the erroneous fields as errorReferences. 3. The warning shall be reported until the mobile robot has accepted a new order." (§6.1.4.3). Error table: `INVALID_ORDER_ACTION` — "Receival of an order containing unsupported actions." A field the robot can't *use* (but action type is known) → `UNSUPPORTED_PARAMETER` (CRITICAL).
- **Unrecognised `instantAction`:** "the mobile robot shall report an **`INVALID_INSTANT_ACTION`** error with level **`WARNING`** and the `actionId` of the `instantAction` as `errorReference`." (§6.2.1). In the action state machine an instantAction unknown to the robot lands in **FAILED**.
- **Conclusion:** unrecognised actions fail loudly (order rejected + named error). This **confirms** the adapter's safety direction — a custom `ottoq.*` action will be rejected loudly by a conforming robot rather than silently ignored. But since `startCharging`/`stopCharging` *are* standard, OTTO-Q's charge operations should use the standard names (collision-free and correct), reserving the `ottoq.` namespace for the genuinely non-standard operations (`batterySwap`, `presentForInspection`, `park`), which must also be declared in the robot's factsheet to be accepted.
  - Source (primary): https://raw.githubusercontent.com/VDA5050/VDA5050/3.0.0/VDA5050_EN.md §6.1.4.3, §6.2.1, §6.6.9, and error table (§7 errorType enum).

### Q5 — Does a VDA 5050 master expose the robot `/state` to a third party? NOT a standardized path; MQTT pub/sub makes a tap possible

- The spec defines a **two-party** interface: topic `state` is "Published by **mobile robot**, Subscribed by **fleet control**" (the master). There is **no third-party role** and **no defined "forward /state" behaviour** in the spec.
- However, VDA 5050 rides on **MQTT pub/sub**: "Participants in the MQTT network subscribe to these topics and receive information that concerns them." So a third party **can** subscribe directly to the robots' `state` topics on the same broker (a broker-level *tap*) without the master's involvement. The spec does **not** define the master *relaying* state onward.
- **Answer for the handoff step 3** ("master → OTTO-Q: /state forwarded, or tapped"): the *forwarded-by-master* form is a **custom/integration** path, not standard. The standard-compatible forms are (a) OTTO-Q subscribes to the `state` MQTT topic(s) directly, or (b) a vendor-specific relay. Leave step 3 marked `[integration]`; (a) is the only standards-native option.
  - Source (primary): https://raw.githubusercontent.com/VDA5050/VDA5050/3.0.0/VDA5050_EN.md §4 ("Topic name | Published by | Subscribed by" table; MQTT participant note).

## Open items

- **Precisely enumerate the `/order` top-level required-vs-optional diff between v1.1 and 3.0.0.** The v1.1 `order.schema` in the deprecated repo is not strict JSON (fails a JSON parse), so only its `released` field and the `/state` diff above were verified field-by-field. The `/state` rename (`batteryState`→`powerSupply`, `agvPosition`→`mobileRobotPosition`) is the substantive, verified change.
- **The "1.3.2" literal's origin** is unexplained by the spec (it is not a published version). It is documented here as a stale schema `example`; no primary source links "1.3.2" to any release.
- **vda5050.com** was not independently checked; the authoritative version source used here is the VDA 5050 GitHub org (spec repo releases), whose homepage points to https://www.vda.de/vda-5050.

## Sources (primary)

- Spec repo + releases: https://github.com/VDA5050/VDA5050 · https://github.com/VDA5050/VDA5050/releases
- 3.0.0 spec text: https://raw.githubusercontent.com/VDA5050/VDA5050/3.0.0/VDA5050_EN.md
- 3.0.0 schemas: https://raw.githubusercontent.com/VDA5050/VDA5050/3.0.0/json_schemas/{order,state,instantActions,factsheet}.schema
- Deprecated 1.x schema repo: https://github.com/VDA5050/vd-m-a-5050 (README + v1.1 tag)
