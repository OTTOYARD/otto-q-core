Package ID: H7 · 2026-08-22 · Status: final · Sources verified as of 2026-08-22

## FINDINGS

MOAT_AUDIT.md (Run 1 / Phase C2, compiled 2026-08-18/19) is a **coverage map, not an existence
check**. Its verdicts — L1 strong, L2 partial, L3 foothold-only, L4 strong machinery with **zero
pack separation**, L5 robotaxi-shaped — name the *internal* gaps. This H7 map is the external
answer: for every gap that a *browser can help close*, the best published resource and the
fastest closing path. Where a gap is pure build work (schema migration, doctrine, CLI), it is
marked OUT_OF_SCOPE so Claude Code doesn't waste a cycle looking for a paper that doesn't exist.

The four research-relevant gaps, in moat order:

1. **Thin L1 — the cross-platform duration model has priors for only one asset class (L1_TELEMETRY
   "Partial").** The twin's calibration registry (ACN-Data, NYC TLC, CA DMV, NOAA) is entirely
   robotaxi + weather. For industrial trucks, heavy equipment, and aerial assets the energy curves
   and service durations exist in *spec-sheet and standard-test* form — VDI 2198 / ISO 23308-1 for
   industrial trucks, OEM battery-pack specs for haul trucks and eVTOLs — and are captured in the
   H1–H4 operation catalogs (durations already live in those dossiers). What is missing is the
   *physics-grounded charging-curve* prior (SoC → power, per class), which the E-VRP literature
   supplies in reusable form (see kernel section, same primitives).

2. **Thin L3 — OCPI field mapping (C10), VDA 5050 adapter, and any adapter interface are all
   absent (L3_PROTOCOL "FOOTHOLD ONLY").** This is the cheapest gap to close: mature, actively
   maintained, Apache-2.0/MIT open-source reference implementations exist for *all three*
   protocols — EVerest and CitrineOS (OCPP 2.0.1), elumobility/ocpi-python (OCPI 2.3.0/2.2.1),
   coaty vda-5050-lib.js (VDA 5050). None of them knows a service event; all of them demonstrate
   the message-schema and adapter-seam discipline OTTO-Q must copy.

3. **Kernel gaps — the CP-SAT decision is unmade (C4) and the five constraint types that stress
   the kernel have *published, reusable formulations* (L4_KERNEL "Partial" + L5 "Partial").**
   Piecewise charging demand, cooldown gaps, alternative-operation groups, skill-tiered resource
   pools, and padded separation are each solved problems in the operations-research literature with
   named papers and benchmark libraries. One survey — Hartmann & Briskorn (2022) — is the index to
   nearly all of them.

4. **Test infrastructure — benchmark instances/generators (L4 determinism + reproducibility).**
   PSPLIB + ProGen (RCPSP), Taillard/Vallada (flow shop), JSPLib (machine-readable), and the Ghent
   MSLIB sets (multi-skill) are public, versioned, and directly adaptable to the canonical site
   shape.

**The headline finding for Chase:** the *only* thing on the audit's gap list with genuinely no
external resource is the specific business claim itself — "a shared facility power feed treated as
a schedulable cross-fleet constraint" (H1's open question) and "one signed SDR per completed
operation" (C3). The primitives for both exist (capacitated-charging E-VRP; OCPI CDR/Tariff
schema; cumulative-resource RCPSP), but the *combination* is unowned — which is exactly the moat.
Everything else is adopt-or-adapt, on a timescale of days.

---

## FOR CLAUDE CODE

This section is the product. It is keyed **one-to-one** to MOAT_AUDIT.md findings. Verdicts:
**adopt** = use as-is; **adapt** = copy the formulation/interface, re-implement against OTTO-Q's
solver; **build** = nothing exists, write from primitives.

### 0. Mapping index (audit finding → entry)

| # | MOAT_AUDIT.md finding | Layer | Entry | Verdict |
|---|---|---|---|---|
| L1-1 | Calibration registry robotaxi+weather only; cross-platform duration model thin for industrial/heavy/aerial | L1_TELEMETRY | §1.1–1.4 | adopt (as priors) |
| L2-1 | SDR = attribution + signed events still two objects; no ServiceSession/SDR/Tariff object | L2_SETTLEMENT | §2 | adapt (OCPI schema) + build |
| L3-1 | OCPI field mapping (C10) absent | L3_PROTOCOL | §3.1 | adopt |
| L3-2 | VDA 5050 adapter absent | L3_PROTOCOL | §3.2 | adopt |
| L3-3 | Power-publication boundary not encoded in any type; no adapter interface; no ADAPTERS.md | L3_PROTOCOL | §3.3 | adapt |
| K-1 | CP-SAT decision unmade (C4); decide path undocumented | L4_KERNEL | §4.0 | adopt |
| K-2 | Piecewise charging demand (energy plan / MPC / charging duration non-linear in SoC) | L4/L5 | §4.1 | adapt |
| K-3 | Cooldown gaps on service points (eVTOL battery cooling; wash/soil gates) | L4/L5 | §4.2 | adapt |
| K-4 | Alternative-operation groups; catalog-as-data; capability `(asset_class, operation)` pairs | L4/L5 | §4.3 | adapt |
| K-5 | Skill-tiered resource pools (technicians, bays by capability) | L4/L5 | §4.4 | adapt |
| K-6 | Separation via padded no-overlap (stall adjacency, pad separation 1.5×D, path/deadlock) | L5_PHYSICAL | §4.5 | adapt |
| T-1 | Determinism/reproducibility substrate needs benchmark instances | L4_KERNEL | §5 | adopt |
| O-1 | INFRA hygiene (CI, keys, tokens, drift manifest) | INFRA | §6 | OUT_OF_SCOPE (build) |
| O-2 | Event vocabulary ~130 uncurated types (C7); KPI views (C6); provenance doctrine (mig 0042) | L1 | §6 | OUT_OF_SCOPE (build) |

---

### 1. Thin L1 — cross-platform energy/duration priors

**Gap:** twin calibration registry covers robotaxi EVs (ACN-Data) + weather only. Need
*prior-not-data* for industrial trucks/AMRs, heavy equipment, aerial. Physics-grounded and
spec-sheet sources; durations already captured in H1–H4 operation catalogs — do not duplicate,
extend the energy curves.

#### 1.1 Industrial trucks / AMRs — energy-consumption test standard (the VDI 2198 family)

- **Source:** VDI 2198 "Type sheets for industrial trucks" (VDI, `vdi.de/en/home/vdi-standards/details/vdi-2198-type-sheets-for-industrial-trucks`); the energy-intensity test cycle it defines (60 fixed work cycles per 3600 s) is the *industry-standard forklift energy benchmark*. Its ISO counterpart is **ISO/DIS 23308-1** "Energy efficiency of industrial trucks — Part 1: General principles" (in DIS at verification; `iso.org/obp/ui#!iso:std:iso:23308:-1:dis:ed-1:v1:en`), which is explicitly "based on the VDI 2198 guideline."
- **Quality:** standards-grade, reproducible, per-truck energy-per-cycle. Not a curve (SoC→power) — it gives steady-state energy intensity, which is the correct *prior mean* for an AMR/forklift energy model; the SoC→power curve shape comes from the Li-ion cell literature (§4.1).
- **Verdict:** **adopt** as the industrial-truck energy prior; pair with vendor Li-ion pack spec sheets (Flux Power, Toyota Forklift opportunity-charging guidance) for C-rate and charge-time ranges.
- **Verified 2026-08-22.**

#### 1.2 Heavy equipment — electric haul-truck energy model

- **Source:** already captured in H2 (Cat 777 / Komatsu 930E profiles; BEV pack up to 1.5 MWh; fast charge 2–4 MW; ABB eMine trolley >12 MW). H7 adds nothing new — the *energy* side is a BEV pack spec + trolley C-rate problem, identical in structure to §4.1's piecewise charging.
- **Quality:** vendor spec + OEM literature (sourced in H2).
- **Verdict:** **adopt** H2 asset profiles as the heavy prior; no new external resource needed beyond the H2 reference list.
- **Verified 2026-08-22** (H2 final, dated 2026-08-18).

#### 1.3 Aerial — eVTOL/drone battery prior

- **Source:** already captured in H3 (Amprius silicon-anode 400 Wh/kg, 6 min to 80%; Joby/Beta/Archer charge targets; SAE AS6968 interoperability draft). The *thermal* constraint (20-min cooldown before fast charge above 90% SoC) is the distinctive aerial prior and maps to §4.2.
- **Verdict:** **adopt** H3 asset profiles; the cooldown becomes a kernel constraint (§4.2), not a data need.
- **Verified 2026-08-22** (H3 final, dated 2026-08-18).

#### 1.4 Robotaxi EVs — the gap is *service-duration*, not charging (ACN-Data already covers charging)

- **Source:** ACN-Data (already ingested) is the charging prior. For **service durations** (wash, interior, tire, calibration) there is **no public per-operation dataset**; the operation catalogs in H1–H4 carry sourced duration ranges and are the current best prior.
- **Verdict:** **build** — no published robotaxi service-duration dataset exists; continue carrying sourced ranges in pack catalogs until first-party telemetry lands.
- **Verified 2026-08-22.**

---

### 2. L2 — the SDR unification (C3)

- **Gap:** attribution + signed events are two objects; tariffs not keyed `(asset_class, operation, operator, window)`; no ServiceSession/SDR/Tariff object.
- **External resource:** the OCPI object model — **Session, CDR, Tariff** (`github.com/ocpi/ocpi`) — is the schema to copy shape from (OTTO-Q's `ServiceSession`/`ServiceDetailRecord`/`ServiceTariff` are deliberately OCPI-shaped per the moat stack). Reference implementations: §3.1.
- **Quality:** spec-grade, versioned (2.2.1 current, 3.0.0 draft).
- **Verdict:** **adapt** the OCPI object shape for the schema; **build** the trigger that makes "every completed operation terminates in an SDR" structural. The signed-settlement *combination* is unowned — that is the moat, not a research gap.
- **Verified 2026-08-22.**

---

### 3. Thin L3 — reference implementations

#### 3.1 OCPI

| Repo | What it is | License | Verdict |
|---|---|---|---|
| `ocpi/ocpi` (github.com/ocpi/ocpi) | Canonical protocol spec (EVRoaming Foundation) | spec | **adopt** as field source |
| `elumobility/ocpi-python` | FastAPI + Pydantic v2 impl of OCPI **2.3.0 / 2.2.1 / 2.1.1**, roles CPO/EMSP/PTP | open | **adopt** as schema/mapping reference |
| `TECHS-Technological-Solutions/ocpi` (Py-ocpi) | OCPI schemas + CRUD + central-system adapters | open | study |
| CitrineOS `ocpi-server` module (github.com/citrineos/citrineos-core) | OCPI server alongside a full OCPP 2.0.1 CSMS — shows OCPP↔OCPI coexistence | Apache-2.0 | study |
| Gireve OCPI Implementation Guide (github.com/gireve) | Field-level implementation guidance for 2.1.1 | guide | study |

#### 3.2 OCPP

| Repo | What it is | License | Verdict |
|---|---|---|---|
| **EVerest** (`EVerest/everest`, LF Energy) | Full EV-charging stack: OCPP 1.6 & 2.0.1, ISO 15118-2/-20, IEC 61851, DIN SPEC 70121 | Apache-2.0 | **adopt** as OCPP-side reference |
| **CitrineOS** (`citrineos/citrineos-core`, LF Energy / S44) | Complete OCPP 2.0.1 CSMS (all modules: Core, Adv. Security, Adv. Device Mgmt, ISO 15118, Smart Charging, Reservations, Local Auth List) — TypeScript monorepo, PostgreSQL/PostGIS + RabbitMQ | Apache-2.0 | **adopt** — the richest message/state reference |
| `mobilityhouse/ocpp` | Python OCPP 1.6/2.0.1 JSON library (`pip install ocpp`) | MIT | adopt for tooling |
| `EVerest/libocpp` | C++ OCPP 1.6/2.0.1 library | Apache-2.0 | study |

#### 3.3 VDA 5050

| Repo | What it is | Verdict |
|---|---|---|
| `VDA5050/VDA5050` | Canonical spec (v3.0.0, JSON schemas) | **adopt** as field source (already captured in H1) |
| `coatyio/vda-5050-lib.js` | Universal TypeScript/JS VDA 5050 library (Node + browser) | **adopt** — cleanest message-model reference |
| `cmraaron/libvda5050pp` | Complete C++ VDA 5050 v1.1.0 implementation | study |
| `taherfattahi/vda5050-robot-simulator` | Python multi-AGV VDA 5050 simulator (v2.0.0) | study (also test infra) |
| `tudo-cni/VDA-5050-Traffic-Generator` | Traffic generator for AGV scenarios | study (test infra) |

#### 3.4 Message-schema patterns (for the power-publication boundary / adapter seam)

- **Source:** JSON Schema (`json-schema.org`, 2020-12 dialect current) and AsyncAPI (`asyncapi.com`) are the two canonical schema/contract standards to encode "forward schedules out, never real-time setpoints" as a *typed* boundary. OCPI itself demonstrates the "module of typed objects over a versioned REST/JSON contract" pattern OTTO-Q's `ADAPTERS.md` should follow.
- **Verdict:** **adapt** — define the adapter interface in JSON Schema/AsyncAPI; there is no existing "power-publication boundary" type anywhere (unowned — build the type).
- **Verified 2026-08-22.**

---

### 4. Kernel gaps — best published formulation per constraint type

**Master index (adopt as the reading list):** Hartmann, S. & Briskorn, D. (2022), "An updated
survey of variants and extensions of the resource-constrained project scheduling problem,"
*European Journal of Operational Research* 297(1):1–14. Covers multi-mode, multi-skill, time
lags, and resource generalizations in one place. **Verdict: adopt** as the kernel-formulation map.

#### 4.0 CP-SAT decision (C4) — the solver itself

- **Source:** the decision is a scheduling/assignment problem expressible in CP-SAT. The canonical modelling reference is the Google OR-Tools CP-SAT documentation + the JSPLib/scheduling instances (§5) as validation targets. No single paper is *required* to start — the five constraints below are the model, CP-SAT is the engine already available to the build track.
- **Verdict:** **adopt** OR-Tools CP-SAT (already the org's stated direction); the five sub-constraints below are the formulation work.

#### 4.1 Piecewise charging demand

- **Source (primary):** Froger, Mendoza, Jabali & Laporte (2019), "Improved formulations and algorithmic components for the electric vehicle routing problem with nonlinear charging functions," *Computers & Operations Research*; and Montoya, Guéret, Mendoza & Villegas (2017), "The electric vehicle routing problem with nonlinear charging function," *Transportation Research Part B* 103:87–110. Both model the concave SoC→power charging curve as a **piecewise-linear function** — exactly the "piecewise charging demand" primitive.
- **Extension for the shared-power-cap moat:** Froger, Jabali, Mendoza & Laporte (2022), "The Electric Vehicle Routing Problem with Capacitated Charging Stations," *Transportation Science* (doi:10.1287/trsc.2021.1111) — caps per-station charge capacity, the nearest published thing to a *shared power feed as a schedulable constraint*.
- **Verdict:** **adapt** — copy the piecewise-linear charging-curve + capacitated-station formulation into the energy-MPC / decide path. The *cross-fleet* power cap is **build** (no paper models multi-operator shared feed).

#### 4.2 Cooldown gaps on service points (minimum time-lag / setup)

- **Source (primary):** Allahverdi, Ng, Cheng & Kovalyov (2008), "A survey of scheduling problems with setup times or costs," *EJOR* 187(3):985–1032 — the canonical treatment of sequence-independent/dependent *gaps between jobs on a machine*; combined with the minimum/maximum **time-lag** generalization in Hartmann & Briskorn (2022, §4.0) and Bartusch, Möhring & Radermacher (1988), "Scheduling project networks with resource constraints and time windows," *Annals of Operations Research* 16:201–240.
- **Why it fits:** eVTOL "20-min cooldown before fast charge if >90% SoC" (H3) and wash/soil gates (engine SQL) are precisely "job B cannot start within δ of job A on resource r" — a minimum time-lag / sequence-dependent setup.
- **Verdict:** **adapt** — express cooldown as a minimum time-lag with a SoC-dependent lag value.

#### 4.3 Alternative-operation groups (catalog-as-data / capability pairs)

- **Source (primary):** Brandimarte (1993), "Routing and scheduling in a flexible job shop by tabu search," *Annals of Operations Research* 41:157–183 — the foundational FJSP (each operation can be processed by one of several machines); current review: "The flexible job shop scheduling problem: A review," *EJOR* (2023, `S037722172300382X`). The RCPSP analogue is **multi-mode RCPSP** (each activity has alternative execution modes), covered in Hartmann & Briskorn (2022) and benchmarked in PSPLIB multi-mode sets (§5).
- **Why it fits:** `(asset_class, operation)` capability pairs on stalls — "this bay can serve these operations for these classes" — is literally an FJSP/MMRCPSP eligibility set.
- **Verdict:** **adapt** — encode `service_definitions` as a per-pack operation catalog whose `(asset_class, operation) → resource` eligibility matrix is an FJSP compatibility set.

#### 4.4 Skill-tiered resource pools

- **Source (primary):** Bellenguez-Morineau & Néron (2007), "A Branch-and-Bound method for solving the Multi-Skill Project Scheduling Problem," *RAIRO — Operations Research* 41(2):155–170 (foundational MSRCPSP); Almeida, Correia & Saldanha-da-Gama (2016), "Priority-based heuristics for the multi-skill resource constrained project scheduling problem," *Expert Systems with Applications* 57:91–103 (heuristics + the standard datasets).
- **Datasets:** **MSLIB1–4** + Montoya(2014)/Almeida(2016) sets, published by the UGent OR&S group (`projectmanagement.ugent.be/research/project_scheduling/MSRCPSP`).
- **Verdict:** **adapt** — technicians/bays-as-capability-sets = MSRCPSP skill sets; use MSLIB for the skill-tiered test harness.

#### 4.5 Separation via padded no-overlap (spatial clearance)

- **Source (primary):** Bierwirth & Meisel (2010), "A survey of berth allocation and quay crane scheduling problems in container terminals," *EJOR* 202(3):615–627 — the canonical *continuous time × space* scheduling problem, where jobs (vessels) occupy an interval of a shared 1-D resource (quay) with **minimum separation in time and space**. This is the exact structure of stall adjacency, pad separation (1.5×D, H3), and path/deadlock clearance.
- **Complement:** the `no-overlap` / `diffn` global constraint family in constraint programming (Beldiceanu & Carlsson, "Sweep as a Generic Pruning Technique Applied to the Non-Overlapping Rectangles Constraint," *CP 2001*) for 2-D (stall grid) packing with padding.
- **Verdict:** **adapt** — model inter-point moves as padded no-overlap intervals on a spatial dimension; berth allocation is the closest solved analogue.

---

### 5. Test infrastructure — benchmark instances / generators

| Set | Domain | Source | Verdict |
|---|---|---|---|
| **PSPLIB** (j30/j60/j90/j120 + multi-mode) | RCPSP / MMRCPSP | Kolisch & Sprecher (1996), *EJOR* 96(1):205–216; instances at `om-db.wi.tum.de/psplib` | **adopt** — map jobs→service ops, resources→bays/power |
| **ProGen** | RCPSP instance *generator* | Kolisch, Sprecher & Drexl (1995), *Management Science* 41(10):1693–1703 | **adopt** — regenerate canonical-site-shaped instances |
| **Taillard** (120 instances, 20×5 … 500×20) | permutation flow shop | Taillard (1993), *EJOR* 64(2):278–285 | adopt |
| **VRF** (Vallada–Ruiz–Framinan) | harder flow-shop | Vallada, Ruiz & Framinan (2015), *EJOR* 240(3):666–677 | adopt |
| **JSPLib** | machine-readable JSP/FJSP (Taillard/JSON format) | `scheduleopt.github.io/benchmarks/jsplib` | **adopt** — direct solver input |
| **MSLIB1–4** | multi-skill RCPSP | UGent OR&S (`projectmanagement.ugent.be`) | adopt (pairs with §4.4) |

**Adaptation note:** the canonical site shape (N stalls, M service bays, one power cap, mixed
asset classes) is a *flexible-flow-shop / RCPSP hybrid* — generate instances by ProGen with a
cumulative power resource added, and validate the solver against PSPLIB/Taillard before adding the
OTTO-Q-specific constraints.

---

### 6. OUT_OF_SCOPE — audit findings with no external resource (build, not research)

- **INFRA hygiene debts** (no CI, anon keys, hardcoded tokens, drift manifest, MIGRATION_LOG backlog): pure engineering; no paper closes them.
- **Event vocabulary curation (~130 types, C7)**, **five canonical KPI views (C6)**, **provenance doctrine (mig 0042)**: internal; no external resource.
- **Recall Decision interface (C9)**: concept already proven in-repo (`early_recall_log`); the interface is a C9 build task. No paper needed.

---

## OPEN QUESTIONS

- Does the MassRobotics AMR Interoperability Standard v2.0 (mission-communication API) introduce any scheduling/resource primitive that overlaps the service-side gap? (Carried from H1.)
- Is there any published formulation — beyond Froger et al. (2022) capacitated charging stations — that treats a *multi-operator shared* power feed as a schedulable constraint (vs. single-operator capacity)? H1's open question, restated: the unowned combination is the moat.
- Are the UGent MSLIB and PSPLIB multi-mode sets sufficient to represent *skill-tiered + spatial* resources simultaneously, or does the canonical site shape require a genuinely new generator?
- Does ISO/DIS 23308-1 (industrial-truck energy efficiency) reach FDIS/published status with the VDI 2198 test cycle intact, and does it expose per-truck energy-per-cycle values usable as priors, or only relative labels?
