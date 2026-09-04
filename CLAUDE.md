# CLAUDE.md — OTTO-Q BUILD TRACK MASTER BRIEF

Commit this file at the root of the canonical repo. Claude Code loads a root CLAUDE.md automatically every session — nothing to attach. Chase starts a session with one command: **"Run 1"**, **"Run 2"**, **"Run 3"**, or **"Run 4"**. The agent reads Parts 1–3 fully, then executes only the named run.

**Ground truth note:** Part 3 was verified against the live Supabase Management API on 2026-08-18 and against the Hermes agent's own credential attestation. It supersedes any older audit, memory, README, or AGENTS.md that describes OTTO-Q as "a threshold engine with cuOpt as a comment" — that description is stale, and AGENTS.md is known to mislabel the databases (Part 3). The standing instruction that follows: **verify, consolidate, extend — never rebuild what exists.**

## RUN INDEX

| Run | Name | Phases | Gate |
|-----|------|--------|------|
| 1 | MAP | C1 Topology → C2 Moat & Modularity | none — run first |
| 2 | CORE | C3 Schema → C4 Solver Truth → C5 Policies → C6 KPIs | Run 1 complete |
| 3 | PROVE | C7 Twin Hardening → C8 Site Alpha → C9 Recall | Run 2 complete |
| 4 | EDGE | C10 Adapters → C11 Conformance | Run 3 complete; C10 needs docs/research/H1; C11 verdict needs H2 + H3 |

---

# PART 1 — OPERATING RULES

These override any default behavior.

**1. Execute only the named run, phase by phase, in order.** Do not start other runs. If a phase requires an artifact from an earlier run that does not exist, stop and say so.

**2. Resumability contract.** On starting a run, first check which phase deliverables already exist in the repo (each phase names its deliverable). Resume after the last completed phase — never redo completed work. **Commit at the end of every phase** with message `run<N>/<phase-id>: <deliverable>` so a dead session costs one phase, not a run.

**3. THE RESEARCH FIREWALL.** You have no web access and never attempt web research, fetching, or browsing. Hermes (a separate cloud research agent) does all external research and delivers findings by opening PRs into `docs/research/**`; merged files there are your only external facts, alongside this brief. When information is missing:
   - Write `docs/research/requests/R-<n>-<slug>.md` with precise, answerable questions (field names, units, versions — never "tell me about X") and commit it. Hermes polls that folder at the start of its sessions.
   - Then proceed with labeled assumptions (`ASSUMPTION — pending R-<n>`) or park the step and continue the run.
   - If a needed H-file exists only in an unmerged PR, say so and pause that phase.
   - Never guess silently. Never browse.

**4. Token discipline, including subagents.** Read only what the phase needs; no drive-by refactors, no speculative abstractions. You MAY spawn parallel subagents **only** for genuinely independent, read-heavy enumeration (e.g., per-repo scans in C1) — never for build or migration phases, and never more than needed. Subagents multiply cost; the default is sequential.

**5. Verify, consolidate, extend.** Before building anything, check whether it exists — in the repo AND in the otto-q-core database (Part 3). Duplicating an existing capability is a failure. Wrapping, formalizing, and extending an existing capability is the job.

**6. Standing product rules:**
   - **cuOpt claims must be ledger-backed.** cuOpt is live (Part 3); `cuopt_invocation_log` exists precisely to make "never invoked" distinguishable from "invoked N times, abstained M." Any cuOpt statement — docs, decks, comments — is quantified from that ledger. Unquantified claims are forbidden in both directions.
   - **Assignment plus verification, always.** Already embodied: `ottoq_stall_bookings` makes double-booking physically impossible via EXCLUDE constraint; `space_conflict_ledger` records every calendar claim overruled by physical reality. Never remove either side.
   - **No number ships without a run ID.** Already a design principle: `ottoq_run_archives` holds the reproducibility key (scenario + seed + policy + depot); `ottoq_decision_snapshots` is the content-hashed anti-cheat substrate. Extend this machinery; never route around it.
   - **No work-side features.** No ride dispatch, pick assignment, haul-cycle optimization, or mission planning. The Recall Decision is the only touchpoint with the work side.
   - **Kernel purity.** Sector-specific code lives only inside adapters. If sector logic must leak into the kernel, that is a platform-thesis finding: stop, document prominently, escalate.
   - **Agents propose, solver disposes.** `ottoq_external_proposals` and the cuOpt deferral pattern already implement propose/dispose. No proposer ever writes a final assignment; the decide path disposes.


**7. Report every time in Chase's local time.** Chase is in Nashville, TN — US Central (CDT = UTC-5 roughly Mar-Nov, CST = UTC-6 otherwise). Every schedule, deadline, ETA, run time and check-in you state to him is in **CT**, written as e.g. "12:08 PM CT". Add UTC in parentheses only where the distinction matters. This is a reporting rule, not a storage one — the machinery underneath stays UTC and must not be "converted":
   - `pg_cron` evaluates cron expressions in **UTC**. Convert CT to UTC before writing a schedule, and if the conversion crosses midnight shift the day fields too.
   - `now()`, `started_at`, and every timestamptz in the database are UTC. Read them as UTC; convert only when reporting.
   - Never restate a stored UTC timestamp as though it were CT, and never rewrite a working cron schedule just to make it read nicely.

---

# PART 2 — THE KERNEL BRIEF

## 2.1 What OTTO-Q is

A **sector-agnostic return-to-base orchestration kernel** for autonomous physical assets. Every autonomous machine — robotaxi, yard tractor, forklift, haul truck, drone, eVTOL — ends its work cycle with the same four questions: **when do I stop working, where do I go, what do I need, when must I be ready.** OTTO-Q owns those four questions and nothing else.

**OTTO-Q is the pit lane, not the race.** Work-side systems own the mission; OTTO-Q owns the asset from recall until ready-for-work. The single interface between the worlds is the Recall Decision (2.7).

## 2.2 Kernel vs. pack

Everything is exactly one of:
- **KERNEL** — asset-agnostic, never mentions a sector: the flow-shop model, the deterministic decide path and proposers, the RecallDecision interface, KPI and runs machinery, service/settlement objects, the proposals mechanism, the twin core.
- **SECTOR PACK** — declarative data plus adapters: asset profiles, operation catalogs, constraint sets, tariffs, protocol adapters.
- **SECTOR-SPECIFIC CODE** — allowed only inside adapters.

The test: **could a mining pack and a vertiport pack both use it unchanged?** Yes → kernel. No → pack. Packs in order: `robotaxi` (reference), `yard-logistics` (build), `mining` and `vertiport` (paper conformance only; inputs arrive from Hermes H2/H3).

## 2.3 The domain model, mapped to what exists

The site is a **resource-constrained flexible flow shop**, not a queue: N assets each needing an ordered set of operations, M service points with heterogeneous capabilities, a shared site power cap, a required-ready-time per asset.

| Kernel concept | Exists today as | Generalization needed |
|---|---|---|
| Asset | `vehicles` + `ottoq_vehicle_classes` (7 classes) | rename-level; class table is the foothold |
| AssetProfile | `vehicle_need_profile`, `ottoq_vehicle_wear` | formalize energy-curve + duty-cycle refs |
| ServicePoint | `stalls` (427) | capabilities as (asset_class, operation) pairs |
| Job / visit | `ottoq_visit_needs`, `ottoq_vehicle_dispatches`, itineraries/legs | naming + lifecycle doc |
| Booking | `ottoq_stall_bookings` (EXCLUDE constraint) | keep; this is the calendar |
| Operations catalog | `service_definitions` (9), `service_cadence_policy` | per-pack catalogs as data |
| Rules layer | `ottoq_rules` (52, versioned, tenant-parameterizable) + 792k logged evaluations | keep as Layer 1 |
| Multi-tenant terms | `ottoq_fleet_operator_slas` (4 OEM rows, versioned) | the L2 foothold |
| Signed telemetry | `ottoq_events` (20.8k, HMAC-signed), `ottoq_telemetry_packets` (25k) | the L1 foothold |
| Energy | BESS units/snapshots, solar per canopy, grid snapshots, tariff windows, `ottoq_energy_plan` (MPC bridge) | schedule-shaped publication boundary |
| OCPP | `ottoq_ocpp_chargers` (90, OCPP 2.0.1), `ottoq_ocpp_messages` (6.9k), `ocpp_sessions` | the L3 foothold |

Two properties the model always preserves — this is where throughput lives: **concurrency within a service point** (sensor clean, interior reset, data offload, software update run during charging; serializing them gives away most available throughput) and **inter-point moves as scheduled operations** (they have duration, consume path resources, and are where deadlock happens — the `demate_deadlock` function backup shows this has been fought once already).

## 2.4 Robotaxi operation catalog (reference; packs extend as data)

DC fast charge 20–45 min (dominant kW) · L2 charge 2–8 hr · sensor clean 3–8 min (parallel w/ charge) · interior reset 5–15 min (parallel) · exterior wash 8–15 min (separate bay) · data offload 10–40 min (parallel) · software update 15–60 min (parallel) · inspection 10–30 min · tire/mechanical 20–120 min · ADAS calibration 30–90 min · park/stage. Yard-logistics adds: opportunity charging, battery swap, attachment change. Mining (paper): refuel OR recharge as alternative operations, heavy tire ops, component-hour maintenance. Vertiport (paper): charge vs. swap turnaround, reposition with tug-as-resource, weather-hold as blocking pseudo-operation.

## 2.5 The decision architecture (as it actually is)

Three cooperating layers exist today:
1. **Layer 1, deterministic rules** — 52 versioned rules, tenant-parameterizable, every evaluation logged. Inviolable constraints including per-OEM SLAs.
2. **The local decide path** — the tick-driven scheduler embodied in database functions (the `ottoq_fn_backup_*` set names its policies: dcfc_first, night_waves, plug_target_policy, cold_start, stall_watchdog, frozen_target, supersede_churn). This is what disposes.
3. **Proposers** — cuOpt via the `ottoq-cuopt-propose` edge function to the NVIDIA endpoint (255 logged invocations; the deferral table gives an in-flight proposal one-tick right-of-first-refusal before the local path pre-empts), external proposals, and the energy MPC bridge (`ottoq-energy-mpc`, AWS optimizer) whose BESS setpoints the twin follows when `energy_mpc_follow=1`.

Modeling requirements that bite: piecewise charging demand above ~70% SoC; DCFC cooldown as a minimum-gap constraint on the **service point** (18 min in the throughput model); cold-start as a duration modifier in one tested function; multi-term objective with exposed weights (tardiness, energy cost vs. tariff, peak-kW excursion, inter-point moves); rolling re-solve with previous-feasible retention — the site is never without a schedule; determinism under fixed seed.

**CP-SAT's role is a decision, not a mandate.** OR-Tools CP-SAT remains the strongest candidate for the deterministic scheduling core (disjunctive machines + cumulative resources is its home turf; cuOpt's strength is routing/LP-scale). But it enters as either (a) successor to the local decide path or (b) another proposer under the deferral pattern — gated on C4's findings. Do not rip out a working propose/dispose pipeline to install a textbook.

**Power publication boundary:** production interfaces publish forward demand schedules (smart-charging-profile shaped) to site controllers and vendor EMS. Real-time setpoint commands to physical inverters are never issued by OTTO-Q directly; the existing MPC bridge is a planning input inside the twin, and the boundary is encoded in adapter types when C10 lands.

## 2.6 The data contract (OCPI-shaped on purpose)

The EV stack standardized electrons: ISO 15118 (vehicle-to-charger), OCPP (charger-to-backend — already implemented here at 2.0.1), OCPI (operator-to-operator roaming: Locations, Tokens, Sessions, CDRs, Tariffs). **Nothing standardizes service events in any sector.** Our service objects fill that gap:

```
ServiceLocation      <- OCPI Location analogue; (asset_class, operation)
                        capability pairs per point
ServiceToken         <- operator + asset + entitlements
ServiceSession       <- open session for ANY operation, energy or not
ServiceDetailRecord  <- the SDR: CDR analogue for any completed service
                        event — signed, tariffed, operator-attributed,
                        asset-class-tagged. Evolves from
                        ottoq_visit_cost_attribution + the signed event
                        stream; do not invent a parallel object.
ServiceTariff        <- per (asset_class, operation, operator, window);
                        evolves from tariff_schedules/ottoq_depot_tariffs
ServiceProfile       <- the published forward schedule; ChargingProfile
                        analogue extended to non-energy resources
```

**The strategic instruction of the entire build:** a scheduler that logs `assignment(asset, point, t)` builds the commodity layer only. A scheduler that emits an SDR for every completed operation builds the telemetry moat, the settlement rail, and the protocol claim simultaneously, at nearly identical cost. Every completed operation terminates in an SDR, structurally (C3 enforces).

## 2.7 The Recall Decision (kernel primitive)

The single interface to every work-side system, and the one place intelligence touches revenue rather than cost. `early_recall_log` shows the concept exists; C9 formalizes it:

```ts
interface RecallDecision {
  decide(
    asset: AssetState,      // SoC/fuel, faults, component hours, payload
    work: WorkSideSignals,  // mission status, demand forecast, release windows
    site: SiteForecast      // predicted congestion, price windows, availability
  ): { recall_time; target_site; service_bundle: Operation[]; target_ready_time }
}
```

First implementation deliberately naive (thresholds), documented as naive, config-swappable. Work-side refusal (mission overrun) is a first-class event triggering re-solve, never an error.

## 2.8 OTTO-Twin (stays; Isaac parked)

**OTTO-Twin remains the simulation product.** Its engine is the database-native twin that already exists: scenario library, sim runs with virtual clock and time_scale, variability profiles and catalog, per-tick weather/solar/grid modeling, OEM webhook emulation with calibrated failure modes, and — the crown jewel — **calibration from real-world datasets** (ACN-Data, NYC TLC trip records, CA DMV AV reports, NOAA) as fitted quantile grids and cyclical profiles. That calibration layer is exactly the "prior, not data" substrate the duration-model research needs.

**Isaac Sim / Omniverse ("Track B") is parked.** The in-house 3D rendering layer already provides visual detail, consuming twin state. Keep `ottoq_site_structures` (it drives scene geometry for the current renderer and any future OpenUSD reattachment); tag Isaac-specific code `PARKED_ISAAC` and quarantine, don't delete. The twin core exports a playback timeline `(entity_id, event_type, t_start, t_end, from_pose, to_pose)` — the seam the 3D layer renders from and through which Track B can return.

Twin discipline: sim-generated and production rows co-exist in shared tables filtered by `data_source` — preserve that pattern; it is what makes sim and real telemetry indistinguishable to the metrics layer, which is the point.

## 2.9 The five canonical KPIs

Tested views over the existing substrate, identical across every policy and pack:

```sql
-- 1. asset_hours_available_per_day
-- 2. service_point_turns_per_point_per_day
-- 3. peak_site_kw            -- 15-min rolling, matches demand billing
-- 4. touch_events_per_turn   -- human interventions per asset-turn
-- 5. p95_time_to_service     -- recall-complete -> first op active
```

One CLI command: run ID in, all five KPIs out, deterministically. **The credibility rule of the company: no number ships without a run ID.**

---

# PART 3 — SYSTEM MAP (verified 2026-08-18: Supabase Management API + Hermes attestation)

**Three Supabase projects, one organization:**

| Project | Ref | Region | Status | Role |
|---|---|---|---|---|
| otto-q-core | `gxdrcyphqjzjsuhxuqtg` | us-east-1 | ACTIVE | **The engine.** 250+ tables: rules, twin, cuOpt pipeline, energy, OCPP, audit. Created 2026-04. |
| OTTOYARD MVP | `ycsisvozzgmisboumfqc` | us-east-2 | ACTIVE | Original demo backend: 9-city/18-depot/1,020-vehicle demo dataset, UI auth, retail/subscription schema (`ottoq_ps_*` — the OrchestraEV concept), **and Hermes's own pipeline: `intelligence_events` (1,378,574 rows) + `scanner_config` + `fleet_commands`** — confirmed by Hermes as its footprint. Created 2025-07. |
| OTTOYARD Fleet Dashboard | `sovyxwtrqfmizelrammm` | us-east-2 | **INACTIVE** | Paused since ~Aug 2025. Presumed dead wiring; C1 confirms and disposes. |

**otto-q-core highlights (row counts at the pull):** 792,101 rule evaluations · 20,799 HMAC-signed events with signing-key registry · 25,308 telemetry packets · 255 cuOpt invocations logged against the NVIDIA endpoint · 1,340 decisions in the propose/dispose audit trail · 145 archived reproducible runs · 90 OCPP 2.0.1 chargers · 4 versioned OEM SLAs · 7 vehicle classes · 52 deterministic rules · calibration registry spanning ACN-Data / NYC TLC / CA DMV / NOAA · run-scope registry (219 classified columns) driving purge safety.

**REFRESH 2026-09-03 (the line above is the 2026-08-18 pull and is left as the point-in-time record it is).** Sixteen days of twin operation moved most of those counts by one to three orders of magnitude. Anything reasoned from the August figures is stale; anything quoted from them is wrong:

| | 2026-08-18 | 2026-09-03 | factor |
|---|---|---|---|
| rule evaluations | 792,101 | **4,607,065** | 5.8x |
| HMAC-signed events | 20,799 | **2,487,708** | **120x** |
| telemetry packets | 25,308 | **203,194** | 8.0x |
| cuOpt invocations | 255 | **12,478** | **49x** |
| decisions (propose/dispose) | 1,340 | **1,334,905** | **996x** |
| archived reproducible runs | 145 | **762** | 5.3x |
| sim runs | — | 603 | — |
| service detail records | — | 127,122 | — |
| OCPP 2.0.1 chargers | 90 | 94 | +4 |
| versioned OEM SLAs | 4 | 4 | — |
| vehicle classes | 7 | 9 | +2 |

**Two clarifications, not corrections.** "52 deterministic rules" is a ROW count: 29 active plus 23 archived, across **29 distinct rule codes** — the archived rows are superseded versions of the same codes, not 52 separate rules. And rule 6's cuOpt sentence must be re-derived before it is spoken: the ledger now holds 12,478 invocations, not 255, so any claim built on the August figure is off by 49x in the direction that flatters us.

**Why this refresh exists.** `db/checks/0098` records a 22-second KPI view that survived because it scanned a table CLAUDE.md said held 20,799 rows and which actually held 2.49M. Reasoning from a stale ground-truth line is how that happened. Re-measure before quoting; the queries are one `SELECT count(*)` each.

**Agent access map (topology facts C1 documents):** Hermes (cloud agent, Telegram-fronted) holds a GitHub token authenticating as the OTTOYARD user — push + PR proven, **no `issues` scope** (Issues API 403) — and a Supabase Management API token executing SQL as the postgres role across all three projects. By standing policy in HERMES.md, Hermes's database use is **read-only** (its pre-existing `intelligence_events` ingestion excepted); all Hermes deliverables arrive as PRs into `docs/research/**`. Claude Code is the only agent that changes schema or engine state.

**Known hazards:** duplicate table names across projects (`ottoq_events` exists in both core and MVP with different meaning — a client pointed at the wrong ref fails silently); ~100 scratch tables in core's `public` schema (`proof*/cert*/smoke*/fwd*/mig*/build*`) awaiting classification; cross-region split (core us-east-1, MVP us-east-2); **AGENTS.md drift** — the repo's AGENTS.md labels `gxdrc…` "the one database that matters" and calls `ycsis…` "OrchestrAV's legacy database," which conflicts with live naming and contents. Treat AGENTS.md as unreliable until C1 reconciles it.

**Unknowns C1 resolves:** the full repo inventory and which repo calls which project; where the 3D rendering layer lives; which repo is canonical for this CLAUDE.md.

---

# PART 4 — THE RUNS

## RUN 1 — MAP (findings only; no refactoring)

*Resume rule: if `SYSTEM_TOPOLOGY.md` exists, skip to Phase C2; if `MOAT_AUDIT.md` exists, Run 1 is complete.*

### Phase C1 — System & Repo Topology Audit
1. Enumerate every repo in the OTTOYARD project/org (parallel subagents permitted here, one per repo, read-only). For each: purpose, entry points, env/config references to Supabase refs, deploy targets.
2. Build the call graph: which UI talks to which backend; edge functions per project and their invokers; where the 3D rendering layer lives and what it reads.
3. Classify live vs. dead: confirm the INACTIVE Fleet Dashboard has no live callers; find anything still pointed at MVP that should point at core (the duplicate `ottoq_events` naming makes misrouting silent).
4. Document Hermes's footprint: what writes `intelligence_events`/`scanner_config`/`fleet_commands`, at what cadence, from where.
5. Inventory every Hermes agent file across repos; summarize what each instructs; flag drift versus HERMES.md.
6. **Reconcile AGENTS.md with reality** (correct project names, roles, and the canonical-database claim) and commit the fix.
7. Classify core's ~100 scratch tables: evidence to keep (per the run-scope registry's evidence class) vs. junk to archive/drop; recommend an `evidence` schema move so `public` stops being a lab bench.
8. Declare the canonical repo for this CLAUDE.md.

**Deliverable:** `SYSTEM_TOPOLOGY.md` (+ mermaid diagram + scratch-table appendix). Commit.

### Phase C2 — Moat & Modularity Audit
Coverage map, not existence check — Part 3 proves L1–L3 footholds exist; the question is how far each extends.
1. Tag every file and major function (and core DB object classes) twice: moat layer — `L1_TELEMETRY`, `L2_SETTLEMENT`, `L3_PROTOCOL`, `L4_KERNEL`, `L5_PHYSICAL`, `INFRA` — and modularity class — `KERNEL`, `PACK`, `SECTOR_SPECIFIC`.
2. Tag Isaac/Omniverse code `PARKED_ISAAC`; quarantine to `parked/` if low-risk, else make it recommendation #1.
3. Per moat layer, write the coverage verdict: what exists, what is partial (e.g., SDR = cost attribution + signed events, not yet one signed settlement object), what is absent (e.g., cross-operator settlement flow, service-event tariffs per asset class).

**Deliverable:** `MOAT_AUDIT.md`, ending with the five highest-leverage moves ranked by moat impact per engineering hour. Commit. (Hermes auto-detects this file for its H7 support run.)

## RUN 2 — CORE

*Resume rule: skip any phase whose deliverable exists (`SCHEMA_V2.md` → `SOLVER_STATE.md` → `policies/` comparison run → `metrics/` + `RUNBOOK.md`).*

### Phase C3 — Schema Mapping & Service Objects
Migration path over what exists — not a rewrite, not a parallel schema.
1. Asset/AssetClass/AssetProfile over `vehicles` + `ottoq_vehicle_classes` + need/wear profiles (classify each change: rename, view-wrap, extend).
2. ServicePoint over `stalls` with `(asset_class, operation)` capability pairs; `ottoq_stall_bookings` and its EXCLUDE constraint untouched.
3. The six service objects, each with its OCPI parallel in a comment; SDR evolves from `ottoq_visit_cost_attribution` + the signed event stream into one signed, tariffed, operator-attributed, asset-class-tagged record per completed operation.
4. "Every completed operation terminates in an SDR" made structural (trigger or constraint); register any new run-scoped columns in the run-scope registry or the purge check will rightly refuse.
5. Migration verified on a scratch branch; existing data survives; `data_source` co-existence preserved.

**Deliverable:** `SCHEMA_V2.md` + migration in `migrations/`. Commit.

### Phase C4 — Solver Truth & Deterministic Core
1. Quantify cuOpt from `cuopt_invocation_log` + fire log + deferrals + enactment proofs: invocations vs. sql_gate refusals, NVIDIA statuses, abstentions, proposals enacted vs. pre-empted, and the measured outcome delta where the A/B substrate allows. Publish the honest sentence the deck may use.
2. Document the local decide path as a plain-language decision procedure — reconstructed from the live functions and the `ottoq_fn_backup_*` policy set — to hostile-diligence standard.
3. `SOLVER_STATE.md`: the three-layer architecture as-is, with ledger numbers.
4. Recommend and prototype the deterministic-core move: CP-SAT as (a) decide-path successor or (b) additional proposer under the deferral pattern, gated on findings from steps 1–2. Prototype in `solvers/cpsat/` against a reduced canonical scenario, honoring every 2.5 modeling requirement, deterministic under fixed seed.
5. Nothing existing is deleted; the local path remains a named policy regardless.

**Deliverable:** `SOLVER_STATE.md` + running CP-SAT prototype + the ledger-backed cuOpt statement. Commit.

### Phase C5 — Policy Consolidation & Baselines
`ottoq_ab_runs` already pairs OTTO-Q vs FIFO vs greedy under common random numbers, keyed by seed — wrap, don't rebuild.
1. `AssignmentPolicy { name; decide(state, arrivals): Assignment[] }` wrapping: FIFO, greedy, the local decide path ("as-is"), and the C4 CP-SAT prototype. Preserve CRN pairing and seed discipline exactly — the statistical spine of every future claim.
2. `WaymoStagingPolicy`: stub only, PARKED, TODO referencing US 12,545,288 B2. Compiles, refuses to run.
3. One committed four-policy comparison with seed and results table, regenerable byte-for-byte.

**Deliverable:** `policies/` with tests + the committed comparison run. Commit.

### Phase C6 — Canonical KPIs & Reproducibility CLI
1. The five 2.9 views over the existing substrate (decisions, run archives, bookings, energy snapshots, SLA conformance, cost attribution); peak_site_kw on 15-minute rolling windows.
2. Every solver/decide execution lands in the runs machinery keyed `(policy_name, pack_id, scenario_seed, config_hash)` — extend `ottoq_run_archives`, don't invent a parallel table.
3. CLI: run ID in → five KPIs out, deterministic.
4. CI gate: 24-hour seeded comparison; build fails on KPI regression beyond threshold; prove the gate fires once.

**Deliverable:** `metrics/` + `RUNBOOK.md`. Commit.

## RUN 3 — PROVE

*Resume rule: skip phases whose deliverables exist (hardened twin demo run → `sites/site_alpha/` + curve → `recall/`).*

### Phase C7 — OTTO-Twin Core Hardening
Formalize the existing DB-native twin as the kernel's simulation engine. Not a rebuild.
1. Determinism certification: same seed + scenario + policy → byte-identical event stream; extend the existing determinism-proof work into a standing property test.
2. Canonical event vocabulary over `ottoq_events` (audit the 130-type catalog against: arrival, recall_issued, recall_refused, move_start/end, op_start/end, fault, point_blocked/cleared, power_loss/restored, touch_event; register additions properly).
3. Failure scenario library extended to the canonical nine — blocked point, overstay, immobile asset, mid-session charger fault, zone power loss, human path crossing, swap-dock jam, tug unavailable, work-side recall refusal — each a committed data file.
4. Playback timeline export for the 3D layer; versioned schema; zero Isaac imports in the path.
5. Preserve `data_source` co-existence and purge/retention discipline in anything added.

**Deliverable:** hardened twin core + `scenarios/` + a demonstration run flowing end-to-end into the C6 CLI. Commit.

### Phase C8 — Site Alpha & Anti-Correlation
1. Site Alpha as committed config: power_cap 3,000 kW; tenants robotaxi_operator_A (18 assets, overnight-heavy), yard_logistics_B (6 electric yard tractors, daytime waves), amr_fleet_C (24 AMRs, opportunity charging); points 10× DCFC (robotaxi|yard_tractor), 8× L2 (robotaxi), 2× wash (robotaxi|yard_tractor), 1× calibration (robotaxi), 6× AMR pad, 1× swap dock; seeded duty-cycle-shaped arrivals per tenant; classes from `ottoq_vehicle_classes`.
2. Every C7 failure scenario × every C5 policy; degradation charts, each regenerable from its run ID. These charts are the standing answer to reservation-fragility objections — shown, not argued.
3. The anti-correlation sweep: Site Alpha with/without tenant C, and with C phase-shifted; peak site kW and point turns per configuration under CRN pairing. This curve is the shared-infrastructure economics quantified.

**Deliverable:** `sites/site_alpha/` + failure-mode report + the anti-correlation curve, all seeds and run IDs committed. Commit.

### Phase C9 — Recall Decision Primitive
Interface verbatim from 2.7; naive threshold implementation documented as naive; config-swappable with zero call-site changes (prove with a second dummy implementation); every decision emits a recall event record (inputs snapshot, decision, implementation name) into the runs machinery; work-side refusal as a first-class event triggering re-solve, exercised by the C8 refusal scenario.

**Deliverable:** `recall/` with tests + one-page interface doc. Commit.

## RUN 4 — EDGE

*Gate: `docs/research/H1-intralogistics.md` merged for C10; H2 + H3 merged for the C11 verdict (harness builds regardless). Resume rule: skip phases whose deliverables exist.*

### Phase C10 — Adapter Boundary (OCPI + VDA 5050)
Two laws, encoded in interface types so violation is a compile error: adapters translate, never decide; power publication is schedule-shaped, never real-time device commands.
1. `ADAPTERS.md` + the adapter interface.
2. OCPI mapping over the existing OCPP/session substrate: ServiceSession/SDR/ServiceTariff ⇄ OCPI Session/CDR/Tariff, field-by-field.
3. VDA 5050 adapter draft from the H1 capture: their order/state messages ⇄ Job/Operation; OTTO-Q beside a VDA 5050 master controller (master keeps work-side dispatch; OTTO-Q takes asset state, issues recall and service scheduling, returns ready-for-work); handoff sequence documented. Missing fields → request file, mark provisional.
4. Stub `adapters/mining/` and `adapters/vertiport/` with interface contracts only.

**Done when:** OCPI mapping round-trips a synthetic session losslessly; the VDA 5050 draft names every consumed/emitted field or marks it provisional; no adapter contains a scheduling decision. Commit.

### Phase C11 — Pack Conformance Harness & Verdict
The falsification instrument for the platform thesis: a pack is valid iff its declarative files load and solve on the kernel with zero kernel modification.
1. `conformance/`: load pack files, validate against `PACK_SPEC.md`, construct a scenario on the C7 twin, run, verify — no power-cap violation, no point overlap, no operation on an incapable point.
2. Formalize `PACK_SPEC.md`; run robotaxi and yard-logistics packs to passing; accept stub-adapter paper packs.
3. When H2/H3 are merged, run them and write `CONFORMANCE_FINDINGS.md`: every constraint that conformed, every one that didn't, and per failure whether a new declarative mechanism suffices or genuine solver change is required. **This document is the verdict on whether OTTO-Q is a platform or N products. Write it willing to conclude either way.**

**Deliverable:** `conformance/` + `PACK_SPEC.md` + passing built-pack runs + `CONFORMANCE_FINDINGS.md`. Commit.

---

# PART 5 — HANDOFF & SEQUENCING

**Research handoff (fully automated):** Hermes opens PRs into `docs/research/**` (deliverables as `H<#>-<slug>.md`, request answers as `answers/R-<n>-<slug>.md`); Chase merges; merged files are your inputs. You file requests by committing to `docs/research/requests/`; Hermes polls that folder. Treat file presence in the merged tree as the interface; never assume freshness beyond a file's own date stamp.

**Order:** Run 1 → Run 2 → Run 3 → Run 4. Hermes's Run A (sector dossiers) proceeds in parallel from day one so H1–H3 are merged before Run 4 needs them.

The build track's contract with the company, in one line: **every claim traces to a run ID, every completed operation ends in a ServiceDetailRecord, and the kernel never learns what sector it is in.**
