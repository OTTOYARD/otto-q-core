# MOAT_AUDIT.md — Moat & Modularity Audit

**Run 1, Phase C2 deliverable.** Compiled 2026-08-18/19 UTC, immediately after C1
(`SYSTEM_TOPOLOGY.md` — read it first; this document assumes its repo inventory, call graph, and
live-DB facts). This is a **coverage map, not an existence check**: Part 3 of CLAUDE.md already
proves the L1–L3 footholds exist; the question answered here is how far each layer extends, what is
partial, and what is absent.

Tagging scheme (from CLAUDE.md C2):
- **Moat layer:** `L1_TELEMETRY` · `L2_SETTLEMENT` · `L3_PROTOCOL` · `L4_KERNEL` · `L5_PHYSICAL` · `INFRA`
- **Modularity:** `KERNEL` (sector-agnostic) · `PACK` (declarative sector data/adapters) ·
  `SECTOR_SPECIFIC` (sector logic in code) · plus `PARKED_ISAAC` and `OUT_OF_KERNEL` (product
  surfaces that are deliberately not OTTO-Q: retail, city intelligence)

The kernel test applied throughout: *could a mining pack and a vertiport pack both use it
unchanged?*

---

## 1. Tag map

### 1.1 otto-q-core — DB object classes (live project `gxdrc…`, 354 public tables + `ottoq`/`twin` schemas)

| Object class (representatives) | Moat | Modularity | Note |
|---|---|---|---|
| `ottoq_events` (HMAC-signed, 20.8k) + signing-key registry, `ottoq_telemetry_packets` (25k), `ottoq_oem_webhook_log`/`_patterns` | L1_TELEMETRY | KERNEL | The signed-event foothold. Event *vocabulary* (~130 types) is robotaxi-flavored → C7 audits against the canonical set. |
| `ottoq_rule_evaluations` (792k), `ai_decision_log`, `decision_fusion_log`, `ottoq_decisions` (1,340), `ottoq_decision_snapshots` (content-hashed) | L1_TELEMETRY | KERNEL | Decision audit trail; anti-cheat substrate. |
| `ottoq_run_archives` (145), `ottoq_ab_runs` (CRN-paired), `ottoq_run_scope_registry` (219 cols), `depot_state_snapshots`, `ottoq_schema_snapshots` | L1_TELEMETRY | KERNEL | Reproducibility spine — "no number ships without a run ID" already has its substrate. |
| `ottoq_visit_cost_attribution`, `tariff_schedules`, `ottoq_depot_tariffs`, `ottoq_fleet_operator_slas` (4 OEM, versioned), `ottoq_sla_violations`/`_sla_conformance_daily` | L2_SETTLEMENT | KERNEL | The L2 foothold: cost attribution + tariffs + versioned multi-tenant terms. **Not yet one signed settlement object** (§2 L2). |
| `ottoq_ocpp_chargers` (90, OCPP 2.0.1), `ottoq_ocpp_messages` (6.9k), `ocpp_sessions`, `ocpp_meter_values` | L3_PROTOCOL | KERNEL | Real protocol substrate, charger-side. |
| `ottoq_rules` (52, versioned, tenant-parameterizable) | L4_KERNEL | KERNEL | Layer 1 of the decision architecture. Rule *parameters* are tenant/sector data → PACK-shaped. |
| Decide path: `ottoq_decide_tick`, `ottoq_cron_tick`, `ottoq_orchestrate-tick` fn family, `ottoq_vehicle_commands`, refusal path (mig 0036), boundary (mig 0039) | L4_KERNEL | KERNEL | The disposer. Plain-language reconstruction owed by C4. |
| Proposers: `cuopt_invocation_log` (255), `ottoq_cuopt_fire_log`, `ottoq_external_proposals`, `ottoq_energy_plan` (MPC bridge) | L4_KERNEL | KERNEL | Propose/dispose embodied. ⚠️ Deferral tables removed by mig `0032` (batch enactment) — doctrine text stale; C4 re-describes. |
| Twin core: `twin.*` (71 fns), `ottoq_sim_runs`/`_scenarios`, variability profiles/catalog, calibration registry (ACN/NYC TLC/CA DMV/NOAA), `ottoq_weather/grid/bess/site_energy` snapshots | L4_KERNEL | KERNEL | The simulation engine + the "prior, not data" calibration layer. `data_source` co-existence pattern intact. |
| `early_recall_log` | L4_KERNEL | KERNEL | Recall Decision exists as concept only → C9. |
| `vehicles`, `ottoq_vehicle_classes` (7), `vehicle_need_profile`, `ottoq_vehicle_wear` | L4_KERNEL | KERNEL (naming PACK-leaky) | Asset/AssetProfile foothold; "vehicle" naming is rename-level sector leakage. |
| `service_definitions` (9), `service_cadence_policy` | L4_KERNEL | **PACK data in a kernel table** | This *is* the robotaxi operation catalog — correct future shape is per-pack catalog-as-data (C3). |
| `stalls` (427), `ottoq_stall_bookings` (EXCLUDE constraint), `space_conflict_ledger`, `ottoq_site_structures` (12), depot layout + geometry guard | L5_PHYSICAL | KERNEL | Assignment-plus-verification embodied. Capabilities as `(asset_class, operation)` pairs absent (C3). |
| Wash/soil/interior logic inside twin fns (`ottoq_decide_wash_triage`, soil gates, cleaning cadence), DCFC/L2 charge modeling, `demate` handling | L4/L5 | **SECTOR_SPECIFIC inside kernel functions** | The main modularity leak: robotaxi operation semantics baked into engine SQL rather than declared in a catalog. Platform-thesis watch item, not yet a violation of the adapter rule (no adapter layer exists yet to violate). |
| `ottoq_fn_backup_*` (13 policy-named), `ottoq_fn_definition_backups`, layout/rule backups | INFRA | KERNEL | Recovery substrate. **Lives only in the DB, not in the repo** — see move #2. |
| Scratch tables (120 named-prefix + `p<N>_*`/`phase<N>_*` families) | INFRA | — | Classified in SYSTEM_TOPOLOGY.md Appendix A. |

### 1.2 otto-q-core — edge functions (27)

| Function(s) | Moat | Modularity |
|---|---|---|
| `otto-q-api` (9.4k-line router) | INFRA (serves L1–L5 reads) | KERNEL |
| `otto-twin-control` | L4_KERNEL | KERNEL |
| `ottoq-orchestrate-tick`, `ottoq-sequence-optimize`, `ottoq-assign-optimize`, `ottoq-wave-admit`, `ottoq-amend`, `ottoq-progress` | L4_KERNEL | KERNEL (op names robotaxi-flavored → PACK data later) |
| `ottoq-cuopt-propose`, `ottoq-cuopt-lp-probe` (retired) | L4_KERNEL | KERNEL |
| `ottoq-energy-mpc` (EC2 bridge), `ottoq-energy-optimize` | L4_KERNEL / L5_PHYSICAL | KERNEL — and the **power-publication boundary in embryo**: today it is an internal planning seam; C10 must encode "schedule-shaped, never real-time device commands" in adapter types |
| `ottoq-orchestrator-agent`, `ottoq-nemotron-copilot`, `ottoq-approval-copilot`, `ottoq-feed-agents`, `ottoq-ottocommand` | L4_KERNEL (advisory ring) | KERNEL — all propose/advise; none dispose. Consistent with "agents propose, solver disposes." |
| `ottoq-ingest` (data_source provenance), `ottoq-twin-ingest` (EIA/NOAA refit), `ottoq-run-blackbox` | L1_TELEMETRY | KERNEL |
| `ottoq-webhook-echo` (HMAC receiver) | L3_PROTOCOL | KERNEL |
| `ottoq-cleaning-cadence` | L4_KERNEL | **SECTOR_SPECIFIC** (robotaxi wash semantics in code) |
| `ottoq-fleet-vehicles`, `ottoq-depot-resources`, `ottoq-jobs-active`, `ottoq-jobs-request`, `ottoq-benchmark-run` | INFRA (cockpit read/write surface) | KERNEL |

### 1.3 Repos / major components

| Component | Moat | Modularity |
|---|---|---|
| `otto-q-core` repo (baseline, migrations, checks, evidence, drift tooling) | INFRA carrying L1–L5 | KERNEL |
| `otto-q-core-snapshot` | INFRA (dated evidence) | — |
| `ottoyarddepot-sim` — cockpit shell, tabs, hooks | INFRA | KERNEL-adjacent (renderer only draws) |
| `ottoyarddepot-sim` — `src/components/canvas/**`, `src/engine/TwinMotionDriver.ts`, `src/engine/motion/**`, `src/lib/sitePlan.ts` + layout pipeline | L5_PHYSICAL | KERNEL (consumes the playback seam; zero world logic client-side by law) |
| `ottoyarddepot-sim` — `src/lib/ottoChargeArm/**`, `three/ChargingArm.tsx`; `Otto-charge-arm` repo; `public/otto-charge-arm.html` | L5_PHYSICAL | SECTOR_SPECIFIC (EV charge-arm hardware concept; fine — physical layer is allowed to be concrete) |
| `ottoyarddepot-sim` — `isaac/otto_motion.py`, `unreal/*.py`, `unreal/usd/**`, `src/components/photoreal/OmniverseViewer.tsx` | L5_PHYSICAL | **PARKED_ISAAC — tagged in-file this run** (depot-sim commit `run1/C2`). Full quarantine = move #1. |
| `ottoyard-field-ops` (OTTO-PULSE) | INFRA | KERNEL-adjacent cockpit |
| `ottoyard-OTTO-Q` (OrchestrAV) — fleet cockpit half (gxdrc reads) | INFRA | KERNEL-adjacent cockpit |
| `ottoyard-OTTO-Q` — auth/billing/`ottoq_ps_*` retail half + Stripe fns (MVP) | INFRA / L2-retail | **OUT_OF_KERNEL** (OrchestraEV retail concept; a *customer* of a future SDR rail, not the rail) |
| `ottoyard-OTTO-Q` — `intelligence-*` fns + `intelligence_events` pipeline (MVP) | — | **OUT_OF_KERNEL** (city/threat intel = work-side-adjacent context, Hermes's domain; kernel never consumes it today) |
| `ottoq-intelligence` (EC2 LP/MPC) | L4_KERNEL (proposer) | KERNEL (asset-agnostic energy math) |
| `otto-q-workspace`, `ottoyard-agent-context`, `OTTOYARD` | INFRA (docs/governance) | — |

---

## 2. Coverage verdicts by moat layer

### L1_TELEMETRY — **STRONG, deepest layer**
**Exists:** HMAC-signed event stream with key registry; 25k telemetry packets; 792k logged rule
evaluations; content-hashed decision snapshots; 145 reproducible run archives with CRN A/B pairing;
run-scoped purge safety (219-column registry); flight-recorder export (`ottoq-run-blackbox`);
`data_source` sim/real co-existence — the property that makes sim telemetry indistinguishable to
the metrics layer.
**Partial:** event vocabulary is ~130 uncurated types (C7 audits against the canonical set);
migration `0042` deleted 117k NULL-`sim_run_id` events against the "never touch `ottoq_events`"
rule — provenance discipline needs a doctrine ruling; five canonical KPI views not yet unified over
this substrate (C6).
**Absent:** nothing structural. This layer is the moat as it stands today.

### L2_SETTLEMENT — **PARTIAL, the biggest gap-to-leverage ratio**
**Exists:** per-visit cost attribution; two tariff tables; 4 versioned OEM SLAs with violation and
daily-conformance tracking; a *retail* billing rail (Stripe, `ottoq_ps_*`) on the MVP — a separate
product, but proof the org can run money flows.
**Partial:** SDR = cost attribution + signed events **still two objects, not one signed,
tariffed, operator-attributed, asset-class-tagged record per completed operation**. Tariffs are not
keyed by `(asset_class, operation, operator, window)`. SLA terms exist; entitlements
(ServiceToken) do not.
**Absent:** cross-operator settlement flow; service-event tariffs per asset class; any
ServiceSession/SDR/ServiceTariff object as defined in CLAUDE.md 2.6. C3 owns this; every completed
operation must terminate in an SDR *structurally*.

### L3_PROTOCOL — **FOOTHOLD ONLY, charger-side**
**Exists:** OCPP 2.0.1 substrate (90 chargers, 6.9k messages, sessions, meter values); OEM webhook
emulation with calibrated failure modes + a real HMAC-verified webhook receiver.
**Partial:** the OCPI-shaped service-object contract exists only as design (2.6); the power
publication boundary ("forward schedules out, never real-time setpoints") is practiced by the MPC
seam but not encoded in any type or interface; no adapter interface exists, so "adapters translate,
never decide" is unenforceable today.
**Absent:** OCPI field mapping (C10); VDA 5050 adapter (blocked on H1); mining/vertiport stubs;
`ADAPTERS.md`. Nothing standardizes service events in any sector — the claim is intact and
unclaimed; the substrate to claim it from (signed events + sessions + tariffs) is live.

### L4_KERNEL — **STRONG machinery, ZERO pack separation**
**Exists:** all three decision layers live (52 rules → local decide path → proposer ring: cuOpt
255 ledgered invocations, external proposals, energy MPC, four Nemotron advisories + one Anthropic
NL surface — all propose-only); rolling re-solve with previous-feasible retention (cron ticks);
determinism substrate (seeded runs, CRN pairing, seed 424242 fixture discipline); twin core with
real-dataset calibration; refusal path and decide/execute boundary formalized in migrations
0036/0039; `early_recall_log` proves the recall concept.
**Partial:** decide path documented nowhere (reconstruction owed by C4, from live fns + the
`ottoq_fn_backup_*` set that exists only in the DB); CP-SAT decision unmade (C4); Recall Decision
not an interface (C9); KPI/CLI machinery not unified (C6); cuOpt deferral doctrine stale vs.
migration 0032.
**Absent — the platform-thesis risk item:** there is **no kernel/pack boundary anywhere**. The
robotaxi "pack" is not a pack; it is the kernel's own vocabulary (`vehicles`, wash/soil/interior
semantics in engine SQL, 9 ops hard-seeded in `service_definitions`). Nothing yet *violates* the
adapter rule because no adapter layer exists — but every week of new engine SQL deepens the fusion.
C3's catalog-as-data + capability pairs is the first cut.

### L5_PHYSICAL — **EXISTS, robotaxi-shaped, data-driven where it matters**
**Exists:** 427 stalls with EXCLUDE-constraint booking calendar + conflict ledger; site structures
driving both geometry guard and scene rendering; full energy plant modeling (BESS units +
degradation, solar per canopy, grid/tariff/DR); charge-arm kinematics; an in-house 3D layer
consuming the twin's playback seam with zero world logic client-side.
**Partial:** service-point capabilities not expressed as `(asset_class, operation)` pairs;
inter-point moves are scheduled ops in the itinerary model but path/deadlock resources are implicit
(the `demate_deadlock` backup shows the fight happened — capture it, move #2).
**Absent:** nothing blocking. PARKED_ISAAC code tagged; quarantine pending (move #1).

### INFRA — **functional, with four hygiene debts**
No CI in any repo but depot-sim; committed anon keys + non-gitignored `.env` (two repos are
public); hardcoded bridge token + plain-HTTP EC2 URL (known FR1 item, restated because public);
drift tooling blind to migrations 0026–0042 (headers) and MIGRATION_LOG 1-row backlog; dead-ref
misrouting in depot-sim's `.env` client (C1 §5.2).

---

## 3. The five highest-leverage moves (ranked by moat impact per engineering hour)

**#1 — Finish the PARKED_ISAAC quarantine (mandated).** In-file tags landed this run
(depot-sim `run1/C2` commit). Full quarantine was **not** low-risk today — `OmniverseViewer.tsx`
is a live lazy import behind the Photoreal toggle, and `unreal/` co-houses the *live* layout-seed
pipeline outputs (`layoutSeed.json`/`sitePlan.json`) that tests and builders read. The finishing
move (~2–4 h, in depot-sim): move `isaac/`, `unreal/*.py`, `unreal/usd/` to `parked/`; leave the
layout-seed JSON where the pipeline writes it (or repoint `scripts/buildLayoutSeed.mjs` + the two
tests in the same commit); leave `OmniverseViewer.tsx` in place behind its flag (it is a stream
consumer, not Isaac code). Moat impact is protective, not additive: it keeps Track B re-attachable
while guaranteeing zero Isaac imports in the C7 playback path.

**#2 — Capture the DB-only IP into the repo (~3–6 h, pure git + SELECT).** Export the 13
`ottoq_fn_backup_*` policy tables + `ottoq_fn_definition_backups` into `db/` as committed files;
backfill `migration-version:` headers on 0026–0042 and regenerate the drift manifest; backfill
MIGRATION_LOG.md from migration headers. This is the cheapest move on the board and it protects
*every other layer*: the decide-path policies (dcfc_first, night_waves, demate_deadlock …) —
the exact material C4 must reconstruct from — currently exist in one live database and nowhere
else, in a project whose own first rule is "if it isn't a committed file, it didn't happen."

**#3 — The SDR unification (C3's core, ~2–4 days).** Fuse `ottoq_visit_cost_attribution` + the
signed event stream into one ServiceDetailRecord per completed operation — signed, tariffed,
operator-attributed, asset-class-tagged — with a trigger making "every completed operation
terminates in an SDR" structural, and tariffs re-keyed `(asset_class, operation, operator,
window)`. This is the strategic instruction of the entire build: at nearly the cost of a schema
migration over existing data, L1 telemetry becomes an L2 settlement rail and the L3 protocol claim
("the CDR for service events, any sector") simultaneously. Highest absolute moat gain of any move.

**#4 — Capability pairs + catalog-as-data (C3's other half, ~1–2 days).** `(asset_class,
operation)` capability pairs on `stalls`; `service_definitions` reframed as the robotaxi pack's
operation catalog (data, not schema); rule parameters marked kernel-vs-pack. This is the first
physical cut of the kernel/pack boundary — until it exists, every conformance claim (C11) and
every "sector-agnostic" sentence is unfalsifiable.

**#5 — The five canonical KPI views + run-ID CLI (C6 pull-forward, ~1–2 days).** The substrate
(decisions, archives, bookings, energy snapshots, SLA conformance, cost attribution) already
exists; the views + one CLI convert it into the credibility rule — *no number ships without a run
ID* — and into the honest, ledger-backed cuOpt sentence C4 owes the deck. Cheap because it is
read-only over what C1 just mapped.

---

*Hermes: this file's existence triggers H7 (resource map) per HERMES.md. The request loop will
find `docs/research/requests/` empty as of this commit — H1 (intralogistics/VDA 5050) remains the
standing pre-Run-4 need.*
