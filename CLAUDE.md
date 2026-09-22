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

**3. THE RESEARCH FIREWALL — amended 2026-09-08.** Chase granted direct web access
in session on 2026-09-08 ("Search the web! You have my full permission"). The
firewall is therefore **a provenance rule, not an access rule**, and what it always
protected still holds: *every external fact in this repo carries a source and a date.*

   - **Hermes remains the primary channel and the default.** It produces better
     provenance than ad-hoc searching — see `docs/research/answers/R-12`, which
     answered five questions against NVIDIA's own docs with a version baseline and
     a URL per claim. File a request when the question is broad, when it needs a
     survey, or when it is not blocking.
   - **Direct search is for verification and for narrow, blocking questions** — in
     particular for checking an unsourced claim, whoever made it. `SOLVER_STATE.md`
     §10.2 exists because R-12's one unsourced sentence turned out to be materially
     incomplete, and only a direct check found that.
   - **Anything found by direct search is recorded exactly as a Hermes deliverable
     would be**: the claim, the version or date it applies to, and the source URL.
     A fact without a URL is not a fact, no matter who fetched it.
   - **Never guess silently.** Unchanged, and the whole point.

   **RE-AFFIRMED AND SHARPENED 2026-09-19, in Chase's words, because the agent side of
   this rule kept getting re-litigated from scratch every session.** Two different
   permissions live here and they are NOT the same permission:

   - **WEB SEARCH IS STANDING AND OPEN. Do not ask.** *"You can always do web search
     if needed. Make sure you save that and that doesn't get lost. I don't want you to
     feel like you're on an island with our own information. If you ever need to go
     search for external sources, you can do that on the web."* So: no permission
     request, no "should I look this up", no reasoning from memory about a versioned
     external fact when the answer is one fetch away. The provenance rule above is the
     only condition — claim, version/date, URL.
   - **RESEARCH *AGENTS* STILL STOP FIRST.** *"Maintain the same posture with research
     agents. If needed, you have to let me know first, stop building, and we can
     discuss what it will be needed for and if it's necessary, or if it's more
     important just to test and build line by line."* Fanning out subagents for
     research is what burns token budget, so it is an explicit ask-first action every
     time. Note the asymmetry: **fanning out to BUILD is allowed** (*"If you need to
     fan out and build, do that"*) — it is deep *research* with agents that stops.

   The distinction to hold: one search is free, twelve agents reading the internet is a
   budget decision that belongs to Chase.

When information is missing:
   - Write `docs/research/requests/R-<n>-<slug>.md` with precise, answerable questions (field names, units, versions — never "tell me about X") and commit it. Hermes polls that folder at the start of its sessions.
   - Then proceed with labeled assumptions (`ASSUMPTION — pending R-<n>`) or park the step and continue the run.
   - If a needed H-file exists only in an unmerged PR, say so and pause that phase.
   - Never guess silently. Never browse.

**4. Token discipline, including subagents.** Read only what the phase needs; no drive-by refactors, no speculative abstractions. You MAY spawn parallel subagents **only** for genuinely independent, read-heavy enumeration (e.g., per-repo scans in C1) — never for build or migration phases, and never more than needed. Subagents multiply cost; the default is sequential.

**5. Verify, consolidate, extend.** Before building anything, check whether it exists — in the repo AND in the otto-q-core database (Part 3). Duplicating an existing capability is a failure. Wrapping, formalizing, and extending an existing capability is the job.

**6. Standing product rules:**
   - **cuOpt claims must be ledger-backed.** cuOpt is live (Part 3); `cuopt_invocation_log` exists precisely to make "never invoked" distinguishable from "invoked N times, abstained M." Any cuOpt statement — docs, decks, comments — is quantified from that ledger. Unquantified claims are forbidden in both directions.
     **CORRECTION 2026-09-14 (`db/checks/0220`), and this one is the rule catching its own rule.** Every cuOpt figure this file has carried — **255**, then **12,478**, then **15,346** — is a count of ROWS IN `cuopt_invocation_log`, and that is not a count of invocations. Measured today: the table holds **20,533 rows**, of which **19,995 are `stage='sql_gate'`** — the gate recording that it declined to call anything — and **538 are `stage='edge'`**. Rows carrying an `http_status`, i.e. an actual call to the NVIDIA endpoint, number **16**, for the whole life of the engine. Those 16 calls returned **136 proposals**. The last one was **2026-08-30 04:36:02 UTC**, silent for **15 days**. The row count is still climbing — 2,249 gate rows in the last two days — so a reader who equates rows with invocations concludes cuOpt is busier than ever while it has not placed a call in over two weeks. (This agrees with `SOLVER_STATE.md` §9, which derived 16 calls / 136 proposals; what is new is that the rows grew by ~5,000 since and the calls did not move.)
     **The honest sentence, which is the only one to quote:** *"cuOpt was called sixteen times in this engine's life, returned 136 proposals, and has not been called since 2026-08-30. The 20,533-row ledger is 19,995 gate refusals and 538 edge rows — it measures the gate, not the solver."*
     **CORRECTION 2026-09-14 (`db/checks/0231`) — THE SENTENCE ABOVE IS NO LONGER SAFE TO QUOTE, and the phrase that fails is "in this engine's life."** The ledger it counts is not a permanent record. Measured: `cuopt_invocation_log` is registered in `ottoq_run_scope_registry` with **class `engine`** — "run-scoped working data; must not outlive its run" — and `ottoq_purge_prior_runs` deletes every `class='engine'` table by **registry lookup with dynamic SQL**, never by name (the string `cuopt` does not occur in its source). Its live caller is `ottoq_start_demo_run`. So every demo run deletes prior runs' cuOpt rows.
     **The table's own COMMENT asserts the opposite** — *"Deliberately NOT named ottoq\* so `ottoq_purge_prior_runs` cannot delete prior-run evidence"* — a naming convention relied upon to defeat a mechanism that does not read names. It has never worked. (Note the nightly job is NOT the deleter: cron 625 runs `ottoq_retention_purge_runs`, whose allowlist holds 7 tables and not this one.)
     The damage, measured: `n_tup_ins` **48,897** against `n_tup_del` **63,755**; `max(invocation_id)` 48,897 with **28,262 allocated ids absent**; and the decisive independent witness — the earliest surviving `called_at` is **2026-08-02**, while sibling table `ottoq_cuopt_fire_log` still holds firings from **2026-07-18**, fifteen days earlier. (28,262 is ids absent, not rows deleted: `nextval` is non-transactional and `cuopt_log_gate`'s INSERT sits in an exception handler, so an aborted insert burns an id too. `n_tup_del` is what proves the deletion.)
     **SAY INSTEAD:** *"Sixteen calls to the NVIDIA endpoint survive in the invocation ledger, the last on 2026-08-30. The true lifetime count is at least sixteen and is not recoverable from this table — it is registered as run-scoped engine data and the demo-run purge has deleted from it, leaving 28,262 allocated ids absent and no surviving row older than 2026-08-02, while `ottoq_cuopt_fire_log` still holds firings from 2026-07-18."*
     **CORRECTION 2026-09-19 (`db/checks/0247`, fixed by `0340`/`0341`) — THE SENTENCE ABOVE IS NOW WRONG BY 499 CALLS, IN THE DIRECTION THAT UNDERSTATES US, AND cuOpt IS NOT DARK.** Measured today: `cuopt_invocation_log` holds **27,340 rows of which 515 carry an `http_status`**, and that column is set only from `nvidiaStatuses` in `ottoq-cuopt-propose`, so each one is a real call to `optimize.api.nvidia.com`. All 515 returned 200. **507 answered with `source='cuopt'` for 2,738 proposals**; 8 returned `solved_but_zero_proposals`. The most recent call is **2026-09-17 12:42:07 UTC**, not 2026-08-30 — the endpoint came back to life on 2026-09-16 under `edge:v26-agent-chain` (485 of the 515 calls). "Sixteen calls, the last on 2026-08-30" was true when written and has been quoted past its evidence.
     **AND THE UNDERLYING FRAGILITY IS NOW FIXED RATHER THAN DESCRIBED.** The reason that sentence had to hedge — the ledger is `class='engine'` and the demo-run purge deletes it — is closed by `0340`: `public.ottoq_model_call_ledger` is an append-only, `class='evidence'` ledger with **deliberately no FK to `ottoq_sim_runs`** (the registry's own check (b) requires an FK of `engine`/`stamp` only, and an enforcing FK on evidence can only block the purge or, as CASCADE, erase what check (c) forbids erasing). It carries one row per external model or solver call — cuOpt, Nemotron, CP-SAT, the Anthropic advisor — filled by two error-swallowing capture triggers plus a backfill of the 515 surviving NVIDIA calls and 1,161 intelligence decisions. No chain-of-thought is stored.
     **SO STOP QUOTING A SENTENCE AND READ THE VIEW.** `SELECT * FROM public.ottoq_intelligence_ledger` computes the rule-6 answer per provider, and its five outcome classes are asserted to sum to its call count — the check `0340`'s first view lacked, which is why that view silently reported 515 of 1,676 rows and bucketed the other 1,161 nowhere (`0341`). As of 2026-09-19 it reads: **nvidia_cuopt 515 calls / 515 reaching NVIDIA / 507 answered / 2,738 proposals, last 2026-09-17 12:42 UTC · nvidia_nemotron 1,120 calls, last 2026-09-17 12:44 UTC · cpsat_service 41 calls, last 2026-09-14 09:23 UTC.** Re-derive; never quote this paragraph's numbers without re-running it.
     **AND TWO THINGS THAT VIEW MAKES VISIBLE FOR THE FIRST TIME, both of which are product findings rather than hygiene.** (a) **G62 — the agent is on average exactly one tick late.** Nemotron's mean latency over 1,120 calls is **30,394 ms** with a maximum of **180,743 ms**, against a 30-second beat, and **433 of 1,120 calls (39%) took longer than one tick**. That is the mechanism behind the 721 `deterministic_fallback` decisions sitting beside 729 `nemotron` ones: an advisory agent cannot be a synchronous dependency of a 30-second tick.
     **CORRECTION 2026-09-22 (`db/migrations/0417`) — THOSE THREE FIGURES ARE ALL `source_kind='backfill'`, A DEAD ERA, AND THEY HAVE BEEN READING AS CURRENT.** `0417` groups the ledger by source kind, and every one of the 1,120 backfill rows is `no_handoff` — they predate the handoff detail entirely — with mean latency exactly the **30,394 ms** quoted above. The **live** engine reads **3,383 calls, mean 19,723 ms, p95 66,566 ms, and 634 (18.7%) over one tick.** Pooling the two source kinds would have raised the live mean by 2.6 seconds; the sentence above does the equivalent by quoting one era as the engine's latency. **Never quote an agent latency without its source kind.**
     **AND THE LATENESS COSTS THE WAIT, NOT THE ANSWER, which reverses the build order `db/checks/0323` §5 specified.** The provenance was always in the ledger and had never been subtracted: `tick_seq` is the tick advice was computed from, `detail->'solver_handoff'->'receipt'->>'tick_seq'` the tick it was applied at. Differenced, advice is applied a mean of **4.70 ticks** late (p95 17, max 59; 415 of 640 more than one tick) — and it disagrees with the next fresh advice in **1 of 638 applied calls (0.16%)**, while the agent's own modal objective would have been wrong on **33.07%**. So the agent carries real signal and lateness destroys almost none of it. `0323` §5's step 3 — a validity window refusing stale advice — would therefore discard correct advice in roughly 409 of 410 cases, and its claim that step 4 (decouple the beat) is gated on step 3 fails: a continuously-running agent deposits *correct* advice faster. **Step 4 is the win; step 3 survives as a monitor, not a gate.** **The bounded form, which is the only one to quote:** *"the tick blocks a mean of 19.7 seconds of its 30-second beat on advice a mean of 4.7 ticks stale, which differs from fresh advice 0.16% of the time against a 33.07% floor — so the cost is the wait, not the answer."* That tolerance is a property of a **three-valued site-wide** objective changing on 1.64% of consecutive ticks; if the agent's output ever widens, re-derive from `public.ottoq_agent_advice_staleness` before building on it. (b) **`agent_calls_with_no_l1_rules` = 1,120 of 1,120.** Every Nemotron call in the ledger carries an empty `rule_results`, so the one path where an AI changes engine state is still the one path the L1 shield does not gate — now countable from evidence that survives its run.

     **AND NOTE WHICH DIRECTION THIS CUTS.** Rule 6 forbids unquantified cuOpt claims *in both directions*. A purged ledger makes the LOW direction unquantifiable too: "cuOpt has barely been used" is now exactly as unsupported as "cuOpt is heavily used." The fix — reclassifying the ledger to `evidence`, and deleting the false comment — belongs in the cuOpt cut window, because prior-run rows surviving would expose any unscoped cuOpt reader (the 0145/0146 class), and that audit happens there anyway.
     **And a warning attached to cutting it.** Of the eight database functions named `cuopt*`, **five are not cuOpt**: they are the propose/dispose deferral machinery, which carries a cuOpt name for historical reasons and is **load-bearing for the CP-SAT proposer** (`ottoq_proposer_precedence` declares `holds_tick` for `cuopt`, `cuopt_fallback`, `forward_lex` and `llm_advisor`; `ottoq_agentic_arm` writes `cuopt_first_refusal_max_defers=1` on every armed run). Cutting "everything cuopt" by name would remove the CP-SAT proposer's right of first refusal. `db/checks/0220` has the safe order.
   - **Assignment plus verification, always.** Already embodied: `ottoq_stall_bookings` makes double-booking physically impossible via EXCLUDE constraint; `space_conflict_ledger` records every calendar claim overruled by physical reality. Never remove either side.
   - **No number ships without a run ID.** Already a design principle: `ottoq_run_archives` holds the reproducibility key (scenario + seed + policy + depot); `ottoq_decision_snapshots` is the content-hashed anti-cheat substrate. Extend this machinery; never route around it.
     **CORRECTION 2026-09-14 (`db/checks/0216`, fixed by `0280`), because this sentence is quoted outward.** `ottoq_decision_snapshots` was **not** a content-hashed anti-cheat substrate when this line was written, and had never been one. Measured: a certification pair that **passed all fourteen atoms** (seed 171717 / busy_day / 48 ticks, both arms `validation_status='passed'`) disagreed with **itself** on `content_hash` at **44 of 48 ticks**. The cause separates cleanly — the 4 agreeing ticks are exactly the ticks with zero active charging sessions — because `ottoq_capture_decision_snapshot` digested the whole frame, the frame's `sessions` block carried `ocpp_sessions.id` both as a hashed value *and* as the array's `ORDER BY` key, and that column defaults to `uuid_generate_v4()`. A hash that moves on a fresh random id cannot distinguish an edit from noise, so it could detect no tampering at all. Third instance of the class, after `0137` (the world fingerprint hashed a write timestamp) and `0139` (the end-state fingerprint made id-blind).
     **Fixed 2026-09-14 by migration `0280`** (applied `20260914043322`): the digest now runs over `public.ottoq_frame_hash_payload`, which drops the minted session id and re-sorts sessions on `(stall_id, vehicle_id, started_at)`; `ottoq_assert_snapshot_integrity` moved in the same file so writer and verifier stay one algorithm, switching on a new nullable `hash_algo` column (`NULL` = the original raw-frame digest, never backfilled) so every legacy row keeps verifying under the algorithm that actually wrote it. Recomputed over the two arms' **stored** frames, that pair now agrees **48 of 48**, with no residual — so the session id was the whole cause.
     **What may and may not be said today.** SAY: "the decision frame's content hash is id-blind, and the pair that exposed the defect agrees on 48 of 48 ticks under it." DO NOT yet say the substrate is deterministic in general: that is one pair, and per 2.9a's blind-spot promotion doctrine `content_hash` stays **out** of the fourteen enforced atoms until a flagship round promotes it. The fourteen-atom claim itself was never affected — `content_hash` is not one of the fourteen, which is exactly why a passing pair could hide this.
   - **No work-side features.** No ride dispatch, pick assignment, haul-cycle optimization, or mission planning. The Recall Decision is the only touchpoint with the work side.
   - **Kernel purity.** Sector-specific code lives only inside adapters. If sector logic must leak into the kernel, that is a platform-thesis finding: stop, document prominently, escalate.
   - **Agents propose, solver disposes.** `ottoq_external_proposals` and the cuOpt deferral pattern already implement propose/dispose. No proposer ever writes a final assignment; the decide path disposes.


**7. Report every time in Chase's local time.** Chase is in Nashville, TN — US Central (CDT = UTC-5 roughly Mar-Nov, CST = UTC-6 otherwise). Every schedule, deadline, ETA, run time and check-in you state to him is in **CT**, written as e.g. "12:08 PM CT". Add UTC in parentheses only where the distinction matters. This is a reporting rule, not a storage one — the machinery underneath stays UTC and must not be "converted":
   - `pg_cron` evaluates cron expressions in **UTC**. Convert CT to UTC before writing a schedule, and if the conversion crosses midnight shift the day fields too.
   - `now()`, `started_at`, and every timestamptz in the database are UTC. Read them as UTC; convert only when reporting.
   - Never restate a stored UTC timestamp as though it were CT, and never rewrite a working cron schedule just to make it read nicely.

**8. ONE SITE. THE TWIN DEPOT, AND NOTHING ELSE — added 2026-09-19 in Chase's words, and it overrides Part 4 where they conflict.**

   *"The only depot, installs and chargers and staging spaces I ever want you to test
   against is Otto-twin depot. I don't wanna do multiple depot with 200 stalls. I wanna
   start with that depot and see effectively if OTTO-Q functions first. If it does, then
   we will see potentially how many vehicles at one time we can comfortably stage and
   sort an orchestrate through there. That's the ultimate goal. We are nowhere near that
   yet. We still need to test and validate everything. Just letting you know, do not test
   or validate across multiple sites. Only use the simulation twin Depot as the test site."*

   **The site is `11111111-1111-1111-1111-111111111111`, "OTTOYARD Nashville Flagship"** —
   158 stalls (113 staging, 30 L2, 10 DCFC, 3 wash bay, 2 service bay), 8 sim runs, the
   only depot that has ever hosted one but the retired P2 fixture. Four other depots exist
   in `depots` and **none of them is a test target**: `22222222-…` "OTTOYARD Benchmark
   (CRN A/B)" carries 160 stalls and has hosted **zero** runs, and three fixtures carry
   1–10 stalls between them.

   - **Every measurement predicated on a depot carries `depot_id = '11111111-…'`.** A
     stall, vehicle, booking, session or occupancy count without that predicate is not a
     weaker number, it is a number about a different question. `db/checks/0250` is the
     retraction that produced this rule: an unscoped stall census reported 36 L2 stalls
     available when the site under test had **4**, and the "no capacity wall" conclusion
     drawn from it was wrong — every refused proposal on the live run was asking for one
     of the two stall types at 87% and 80% occupancy. Same defect class as 0145 / 0146 /
     0229.
   - **This supersedes Phase C8's "Site Alpha"** (§C8.1's three-tenant, 28-point config)
     as a *build target*. Its power cap, capability pairs and anti-correlation sweep stay
     in the brief as the design of the eventual multi-tenant config; they are not what
     gets run. The anti-correlation curve needs tenants, not sites — so it can still be
     expressed on the twin depot by phase-shifting tenant demand within it, and that is
     the only form of it to build.
   - **And it collides with 2.5's forced decomposition, which is the more interesting
     conflict.** 2.5 gives CP-SAT the inside of a site and cuOpt the routing of recalls
     *between* sites "at 18-depot scale." On one depot there is no inter-site layer, so
     cuOpt has no routing problem to solve and its present contribution is whatever it
     does as a stall-assignment proposer — currently, on the live run, 1 enacted against
     7 refused and 11 superseded (`0250` §2–3). Do not quote 2.5's inter-site sentence as
     a live architecture. It is a plan gated on a second site existing.
   - **The goal, in Chase's framing, is depth not breadth:** prove OTTO-Q functions on this
     one depot, then find how many vehicles it can stage, sort and orchestrate at once. A
     result from a second site does not advance that and is not evidence about it.

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
| ^ **CORRECTION 2026-09-12 (`db/checks/0178`)** | The order above reads as though the first were the catalog. Measured: **`service_cadence_policy` is the live one** — 15 services, each with a `lane`, all active, read by 8 routines, and it covers **15 of the 16 `svc` values the engine's own work atoms actually use**. `service_definitions` is a **fallback** consulted by one bridge (`ottoq_svc_to_stall_type`, whose own comment calls it "the catalogue table named in the brief"), it holds **27 rows / 9 distinct codes** (the "(9)" above is the distinct count, not the row count), and it overlaps the atom vocabulary on **exactly one** code, `exterior_wash`. | The extension point C11 aims at is `service_cadence_policy`. One service, `perimeter_walkaround`, was declared in **neither** — derived 108 times per run, required of none, performed never. **All three clauses are now stale (`db/checks/0277`, fixed by `0383`): it IS required (25 `must_do` atoms), it IS now performable, and it IS now declared — `service_cadence_policy` holds 16 services and `ottoq_assert_service_vocabulary()` returns an empty `undeclared` for the first time.** |
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
   **CORRECTION 2026-09-13 (`db/checks/0192`), because this number is quoted outward:** 52 is the ROW count (29 active codes plus 23 archived versions), and of the 29 active codes the shield actually evaluates **20**, at **four** probe points — `task_start` (2,701,143 evaluations), `stall_assignment` (544,413), `redeployment` (90,244), `bess_dispatch` (2,222). The other nine have evaluator functions that exist and are callable, and no caller: they are invariants over transitions and outcomes (vehicle/stall/BESS state-machine legality, role gating including `emergency_stop`, audit note on override, physical presence at completion, queue depth at arrival), and a gate placed where something STARTS cannot check one. Six of the nine are `critical`. The honest sentence is "twenty of twenty-nine declared rules, at four decision points, every evaluation logged"; tracked as G44.
   **RE-DERIVED 2026-09-20 (`db/checks/0273`), AS Part 3's refresh instructed, and the sentence above is now WRONG IN OUR FAVOUR — which is the direction to be most careful about.** Measured on the twin depot: **53 rule rows / 30 distinct codes, all 30 active, and every archived row a superseded version of a still-active code (0 archive-only codes)**. Of those 30, **21 are evaluated, at SIX probe points, not four**: `task_start` (13 codes), `stall_assignment` (5), **`charge_session_start` (5)**, `redeployment` (6), **`policy_write` (1)**, `bess_dispatch` (1). **`0192` missed `charge_session_start` and `policy_write`, and the first is not marginal** — 5 codes and 4,475 evaluations, more traffic than `redeployment` and `bess_dispatch` combined. **And the omission was already contradicted inside this repo**: `FINDINGS.md` G89 states EN.001 caps aggregate charging *"at `stall_assignment` and `charge_session_start`"*, so one file documented the fifth probe while another counted four. A cross-file consistency failure, not a measurement error. **THE SENTENCE TO QUOTE:** *"twenty-one of thirty declared rules, at six decision points, every evaluation logged."* **The nine unevaluated codes are the same nine, and six are still `critical`** — HW.006 physical presence, SM.001/003/006 state-machine legality, SM.004 role gating, SM.005 audit note on override, SLA.002 queue depth, TW.002, TW.004 — so `0192`'s diagnosis stands unchanged: these are invariants over *transitions and outcomes*, and a gate placed where something STARTS cannot check one. G44 is unchanged and still open; only the arithmetic around it moved, because the one code added since 09-08 IS evaluated. **AND 21 OF 30 IS A WIRING COUNT, NOT A PROTECTION COUNT.** "Evaluated" means "has at least one logged evaluation", which is weaker than "binds": per `db/checks/0263` §1, four of the five codes at `stall_assignment` are charge-specific and cannot judge a parking hold, and the fifth, `HW.004.stall_single_vehicle`, says in its own description that it is enforced by a partial unique index rather than by the probe. So 21 of 30 is the **optimistic bound**, and any phrasing implying 21 rules actively prevent something overstates it. **Never quote the per-probe evaluation counts without their moment** — `ottoq_rule_evaluations` is `class='engine'`, and 2.5's 2,701,143 for `task_start` against today's 137,787 is the purge, not a loss of coverage.
   **RE-DERIVED AGAIN 2026-09-22 (`db/checks/0321`, confirmed independently by `0323`): it is NINE probe points, not six, and the sentence to quote changes accordingly.** Measured: `task_start` (13 codes), `vehicle_state_change` (1), `stall_state_change` (1), `stall_assignment` (5), `charge_session_start` (5), `redeployment` (6), `bess_dispatch` (1), `policy_write` (1), `bess_state_change` (1). **The three every previous census missed are the row-level state-change triggers** — `ottoq_vehicles_state_change`, `ottoq_stalls_state_change`, `ottoq_bess_units_state_change` — which probe from inside a trigger rather than from a decide-path caller, which is why walking the decide path never found them. They are not marginal: **44,117 evaluations between them, more than `stall_assignment` and `charge_session_start` combined.** **DO NOT read this as coverage improving** — it is the same shield measured more completely, the three new points carry ONE code each, and `0263`'s finding stands unchanged that four of `stall_assignment`'s five codes cannot judge a parking hold. **And `agent_calls_with_no_l1_rules = 4,248 of 4,248` must stop being quoted as "the one path where an AI changes engine state is the one path the shield does not gate" (`db/checks/0323`): it counts the agent choosing an assignment OBJECTIVE, which is a ranking preference that cannot move a vehicle or book a stall, and whose every output is disposed by the kernel. The paths where the agent DOES change state are its six dial writes, judged at `policy_write` (557 evaluations) and clamped to the declared envelope since `0414`.**
   **CORRECTED AND RE-UNITED 2026-09-22 (`db/checks/0326` §6). THIS PARAGRAPH CONTRADICTED ITSELF, AND THE WHOLE CODE-LEVEL COUNT IS THE WRONG UNIT.** Two statements above cannot both be true: `0273`'s *"twenty-one of thirty declared rules"* with *"the nine unevaluated codes are the same nine"*, and `0321`'s nine probe points. **The three probe points `0321` added carry exactly `SM.001`, `SM.003` and `SM.006` — three of that nine — so adding the probes necessarily moved the count, and only the probes were propagated.** Measured today: **24 of 30 codes at nine probe points, six unevaluated, THREE of them critical** (HW.006, SM.004, SM.005), not six. That moves in the flattering direction, which is the direction to state most carefully.
   **AND THE SENTENCE TO QUOTE IS NO LONGER A CODE COUNT AT ALL, because the code count roughly doubles the real coverage.** A code scores as "evaluated" if **any one** of the action contexts it declares is probed, so a rule declaring five contexts and probed at one counts as fully wired. On the (code, context) pair — the unit that actually decides whether a rule judges a given decision — it is **34 of 69 pairs, 49%**, against 31 declared action contexts of which only **9** are probed and **22 never are** (with **zero** orphan probes, so every probe is one a rule asked for). **THE SENTENCE: *"the shield probes 34 of the 69 (code, context) pairs its own rules declare — 49% — at nine of 31 declared decision points, and shields 12,478 of 12,871 enacted decisions on the live run, 96.9%, with 27 rows in a real gap."*** This is what 2.5's own caveat — *"21 of 30 is a wiring count, not a protection count"* — was reaching for without a number; it is now measured, so quote the pair and retire the code count.
   **BOTH HALVES OR NEITHER, and the second half was nearly left out.** `public.ottoq_assert_shield_coverage(run)` already measures a third unit — enacted decision **rows** — and reads 96.9% shielded, 393 unshielded of which 305 are gated downstream, 61 merely record a fact, and only **27 (0.2%) are a real GAP** (one branch, `gate_intake_no_charge`, space/movement ungated, written by `ottoq_decide_tick`). **49% on its own argues for a conclusion the pair does not support** — precisely the failure `db/migrations/0417` §2 names. **And the reconciliation is sharper than either figure:** the 22 unprobed contexts are mostly actions this engine never takes — SM.004's seven are human/UI actions with no DB path, and `oem_acceptance`, `release` and `power_increase` rename transitions the engine reaches through `redeployment` and `charge_session_start`, where those same codes already fire. An unprobed context for an action nobody performs costs nothing. **`task_completion` is the exception, and that is exactly why HW.006's absence is a live defect and SM.004's is not: the test that separates a harmless declaration gap from a real one is not the count, it is whether the engine performs the action.**
   **The sharpest single instance, because it is not a marginal rule:** `task_completion` is declared by **five** codes — `HW.003.sensor_liveness`, `HW.006`, `SLA.003.max_visit_duration`, `SM.002.task_transition_validity`, `TW.002` — nothing probes it, and **three of the five still count as "evaluated" because they fire at `task_start`. So the engine checks sensor liveness before work begins and never after it finishes, and scores that as covered.** A census that can only see a code with no probe at all is blind to a code missing one of the probes it asked for.
   **Finally, retire the "no caller" frame** (`0326` §6(a)): the claim that the unwired codes *"have evaluator functions that exist and are callable, and no caller"* was measuring the search. A static scan for an evaluator's name returns **zero callers for SM.001, SM.003 and SM.006 too**, and those fire 947, 924 and 14 times — the shield reads `evaluator_function` out of `ottoq_rules` and invokes it with dynamic SQL through `ottoq_evaluate_rule_core`, so the name is in no caller's source. **A static caller search can never find a rule's wiring.**
2. **The local decide path** — the tick-driven scheduler embodied in database functions (the `ottoq_fn_backup_*` set names its policies: dcfc_first, night_waves, plug_target_policy, cold_start, stall_watchdog, frozen_target, supersede_churn). This is what disposes.
3. **Proposers** — cuOpt via the `ottoq-cuopt-propose` edge function to the NVIDIA endpoint (255 logged invocations; the deferral table gives an in-flight proposal one-tick right-of-first-refusal before the local path pre-empts), external proposals, and the energy MPC bridge (`ottoq-energy-mpc`, AWS optimizer) whose BESS setpoints the twin follows when `energy_mpc_follow=1`.

Modeling requirements that bite: piecewise charging demand above ~70% SoC; DCFC cooldown as a minimum-gap constraint on the **service point** (18 min in the throughput model); cold-start as a duration modifier in one tested function; multi-term objective with exposed weights (tardiness, energy cost vs. tariff, peak-kW excursion, inter-point moves); rolling re-solve with previous-feasible retention — the site is never without a schedule; determinism under fixed seed.

**CP-SAT's role — GATE CLOSED 2026-09-08 by C4's findings (`SOLVER_STATE.md` §10).** This paragraph previously read that "cuOpt's strength is routing/LP-scale" and left the choice open. The vendor documentation settles it more sharply, and the softer wording should not be quoted any more:

   - **The site layer is not expressible in cuOpt at all.** Against cuOpt 26.08, all four load-bearing constructs of 2.3 are absent — cumulative resource (the site power cap), disjunctive machine (one stall, no overlap), sequence-dependent gap (DCFC cooldown), and any scheduling solver family. cuOpt is routing + convex LP/QP + a **beta** MILP that NVIDIA states cannot yet prove optimality. Warm start is cuOpt-to-cuOpt only, so the matheuristic bridge is closed too. Sourced in `docs/research/answers/R-12`.
   - **So the decomposition is FORCED, not chosen:** CP-SAT schedules *inside* a site; cuOpt, if used, routes recalls *between* sites (the `target_site` of 2.7, at 18-depot scale). Each gets the problem shape it is actually built for.
   - **cuOpt can never sit inside the certified deterministic path.** Its routing solver documents no seed and no determinism parameter at all; its MIP determinism mode is labelled experimental and "does not yet guarantee fully deterministic results in all scenarios." That is not an argument against propose/dispose — **it is the argument for it.** A nondeterministic proposer behind an inviolable deterministic shield, its proposals hashed into the verdict (`h_prop`), is the only safe way to consume a solver that cannot promise reproducibility.
   - **CP-SAT is *determinizable*, not deterministic**, and the difference is four pins that must be asserted, not assumed: pin the OR-Tools version (9.4 and 9.5 both shipped nondeterministic results even single-worker); use `max_deterministic_time`, never `max_time_in_seconds` (a wall clock inside a certified path is G15's defect class); pin `num_workers` or `interleave_batch_size`; and keep a determinism canary in CI that would have caught 9.4/9.5.

Still true, and still the governing instruction: **do not rip out a working propose/dispose pipeline to install a textbook.** The local path remains a named policy regardless (C4 step 5).

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

**2.9a — What the build grew that this brief did not name (added 2026-09-08).** "No number ships without a run ID" is now the *floor*, not the ceiling. What actually got built is a standing reproducibility apparatus, and it is a moat layer in its own right:

   - a **fourteen-atom byte-identical verdict** over every pair (fingerprint, commands, decisions, events, bookings, energy, proposals, deferrals, calibration, rules, recalls, SDRs, tick count, end state);
   - a **canon matrix** with per-column streaks, a recert floor derived from migration lineage, and `forces_recert` classification, so a change that *should* invalidate a canon does, and one that should not, does not;
   - the **blind-spot promotion doctrine** — an atom is added MEASURED first and ENFORCED only after a flagship round shows the arms agree (0139 / 0206 / 0217 / 0225);
   - a refusal to call a column green when the comparison is narrower than the enforcement (G25/G28).

Why this belongs in the brief rather than in a check file: **R-12 established that the leading GPU solver in this space cannot promise byte-identical output at all.** "Same inputs, byte-identical outputs, verified continuously, across fourteen independent atoms" is therefore not hygiene — it is a claim most of the field cannot make, and it is what makes every KPI above worth quoting. Treat reproducibility as a product property, not a test practice.

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

**REFRESH 2026-09-08 (the 09-03 table above is left as the point-in-time record it is, exactly as the 08-18 line was).** Five more days of twin operation. The interesting number is the one that went **down**:

| | 2026-09-03 | 2026-09-08 09:58 UTC | |
|---|---|---|---|
| rule evaluations | 4,607,065 | **5,464,682** | 1.19x |
| HMAC-signed events | 2,487,708 | **2,231,792** | **0.90x — down** |
| telemetry packets | 203,194 | **272,919** | 1.34x |
| cuOpt invocations | 12,478 | **15,346** | 1.23x |
| decisions (propose/dispose) | 1,334,905 | **1,650,636** | 1.24x |
| archived reproducible runs | 762 | **946** | 1.24x |
| sim runs | 603 | **787** | 1.31x |
| service detail records | 127,122 | **179,423** | 1.41x |
| OCPP 2.0.1 chargers | 94 | 94 | — |
| versioned OEM SLAs | 4 | 4 | — |
| vehicle classes | 9 | 9 | — |

`ottoq_events` is **smaller** than it was on 09-03. The nightly retention purge is doing its
job — `pg_stat_user_tables` records 9,419,289 inserts against 9,195,864 deletes on that table
over its life — so 2,487,708 was a high-water mark, not a floor, and any claim of the form
"N million signed events" is a claim about a moment. Cite the run, not the table.

**Counts CLAUDE.md did not previously carry, and one it carried wrongly:**

| | value | note |
|---|---|---|
| stall bookings | **783,276** | the calendar; 53% of every disk block this database has ever read (`db/checks/0127`) |
| recall decisions | **13,406** | the C9 ledger, live since 0206 |
| run-scope registry | **223** classified columns | 219 at the 08-18 pull |
| deterministic rules | **52** rows / **29** codes | unchanged; the 09-03 clarification still holds |
| **stalls** | **330** | **CLAUDE.md 2.3 says 427. It is 330 today** — 232 staging, 64 L2, 22 DCFC, 7 wash bay, 5 service bay. The figure went down between the pulls; what removed them is not established here, so 2.3's number is marked stale rather than explained. |
| vehicles | **226** | not previously carried |

**And the cuOpt sentence has moved again**: 15,346 invocations, up from the 15,250 that
`SOLVER_STATE.md` §9 derived earlier the same day. §9 is dated and stands as the derivation;
what it shows is that this ledger grows by roughly a hundred rows an hour, so a cuOpt number
quoted without its timestamp is already wrong. §9's finding — that the NVIDIA endpoint itself
has not been called since 2026-08-30 — is the part that matters and is unaffected.

**Two clarifications, not corrections.** "52 deterministic rules" is a ROW count: 29 active plus 23 archived, across **29 distinct rule codes** — the archived rows are superseded versions of the same codes, not 52 separate rules. And rule 6's cuOpt sentence must be re-derived before it is spoken: the ledger now holds 12,478 invocations, not 255, so any claim built on the August figure is off by 49x in the direction that flatters us.

**Why this refresh exists.** `db/checks/0098` records a 22-second KPI view that survived because it scanned a table CLAUDE.md said held 20,799 rows and which actually held 2.49M. Reasoning from a stale ground-truth line is how that happened. Re-measure before quoting; the queries are one `SELECT count(*)` each.

**REFRESH 2026-09-20 05:01 UTC — AND THIS ONE IS A LESSON RATHER THAN A TABLE, BECAUSE EVERY FIGURE ABOVE JUST FELL BY ONE TO TWO ORDERS OF MAGNITUDE.** A single demo run started at 04:08 UTC purged **352,673 rows** and deleted one prior run. Measured immediately afterwards:

| | 2026-09-08 | 2026-09-20 05:01 | |
|---|---|---|---|
| rule evaluations | 5,464,682 | **74,719** | 0.014x |
| HMAC-signed events | 2,231,792 | **34,761** | 0.016x |
| telemetry packets | 272,919 | **17,724** | 0.065x |
| `cuopt_invocation_log` rows | 15,346 | **957** | 0.062x |
| decisions | 1,650,636 | **9,125** | 0.006x |
| sim runs | 787 | **9** | 0.011x |
| service detail records | 179,423 | **491** | 0.003x |
| stall bookings | 783,276 | **1,245** | 0.002x |
| archived reproducible runs | 946 | **1,396** | **1.48x — up** |

**Nothing broke. This is `ottoq_purge_prior_runs` doing exactly what it is for.** Every table that fell is registered `class='engine'` in `ottoq_run_scope_registry` — run-scoped working data that must not outlive its run — and `ottoq_run_archives` is the one that ROSE, because it is the durable reproducibility key. **So the standing instruction is stronger than "re-measure before quoting": these are not slow-moving totals that drift, they are per-run working sets that a colleague starting a demo can take to near zero between your measurement and your sentence.** Cite the run, never the table.

**AND THE SHARPEST DEMONSTRATION THIS FILE HAS OF WHY `0340` EXISTS, measured in the same minute.** Rule 6's cuOpt sentence is derived from calls carrying an `http_status`:

| | rows | calls to NVIDIA |
|---|---|---|
| `cuopt_invocation_log` (`class='engine'`) | 957 | **14** |
| `public.ottoq_model_call_ledger` (`class='evidence'`) | 3,502 | **865** |

**The invocation log lost 851 of its 865 NVIDIA calls in tonight's purge. The evidence ledger kept every one.** `SOLVER_STATE.md` §13 quotes 865 because it reads the ledger; anyone reading `cuopt_invocation_log` today gets **14** and would conclude cuOpt is nearly dark. That is the 0231 fragility, closed by 0340, observed rather than argued. **Read `public.ottoq_intelligence_ledger`. Never `cuopt_invocation_log`.** The same now holds for proposal outcomes: `ottoq_proposal_disposition_ledger` (0364, `class='evidence'`) held **128** rows through the purge while `ottoq_external_proposals` lost its 24.

**Two counts that are structural rather than run-scoped, and one correction:**

| | value | note |
|---|---|---|
| stalls, ALL depots | **330** | unchanged since 09-08; 2.3's "427" remains stale |
| **stalls, the twin depot** | **158** | **the only number rule 8 makes relevant** — 113 staging, 30 L2, 10 DCFC, 3 wash bay, 2 service bay |
| vehicles | **226** | unchanged |
| vehicle classes | **9** | unchanged |
| OCPP chargers | **94** all depots / **45** the twin depot | of the twin's 45, **6 were `Faulted`** at this reading and ~**13.8% of charger-time** is lost to faults on a busy_day run (`db/checks/0264` §3) — so **effective charge capacity is about 86% of nameplate, continuously, by design** |
| deterministic rules | **53** rows / **30** codes | was 52/29; one code added since 09-08. The "twenty of twenty-nine at four probe points" sentence in 2.5 needs re-deriving before it is spoken again |
| run-scope registry | **229** classified columns | 223 at the 09-08 pull |

**CORRECTION to 2.3's `perimeter_walkaround` note, and it is the one that matters operationally.** That note says the service is *"derived 108 times per run, required of none, performed never."* **The middle clause is false.** Measured 2026-09-20: **75 atoms, 0 done, and 25 of them `must_do`** — mandatory, never completed, and declared in neither `service_cadence_policy` nor `service_definitions`. Its `perimeter_hold` bookings held **98 of the twin depot's 113 staging stalls** at an average **248-minute** window on a run whose whole life is 540 sim-minutes, while **258 `twin.staging_overflow`** events fired. The cause is traced end to end in `db/checks/0261`: a producer, two observers that say yes for 90% of arrivals, and **no executor anywhere in the engine** — so the hold cannot clear on completion and clears on expiry instead. **This is G86 and it is an open product decision, not a bug to route around.**

**G86 IS NOW CLOSED (`db/checks/0277`, fixed by `db/migrations/0383`), AND THE SENTENCE ABOVE IS HALF RETRACTED — the staging-stall clause was a prefix match and must not be quoted again.** `perimeter_hold` is named for the depot's perimeter **RING**; `perimeter_walkaround` is a walk around a **VEHICLE's** perimeter. `ottoq.ottoq_book_hold_stall` picks the purpose on dwell duration alone — `v_purpose := CASE WHEN v_is_long THEN 'perimeter_hold' ELSE 'temp_hold' END` — and every one of those 82–98 bookings carries **`need_atom IS NULL`**, because a parking hold serves no service atom. **No function in the database mentions both strings**, which is the one-query check that settles it: the two sets of functions are disjoint. The walkaround's own bookings are **fourteen `purpose='service'` rows on two service-bay stalls**. So the long staging holds are long-dwell parking, which is what staging stalls are for, and **closing G86 frees no staging stalls** — the 258 overflow events remain an open question about staging capacity under dwell.

**What was actually wrong is one word, and the executor was never missing.** `twin.ottoq_sim_advance_visit_atoms` completes **any** atom whose `status='in_progress'` and `ends_at` has passed, names no service and needs no bay. The gate is the START side, `ottoq_start_concurrent_atoms`, which admits `concurrency IN ('cabin','exterior','digital')` — and derive wrote the walkaround as **`concurrency='hold'`, a seventh class with exactly one member.** Measured: cabin 75 of 127 done, gate 33 of 98, anchor 28 of 67, bay 23 of 64, digital 2 of 5, exterior 1 of 2, and **`hold` 0 of 63, not one ever reaching `in_progress`.** Every class completes except the orphan. The engine had already said so twice in machine-readable form — `ottoq_atom_retirable_set()` excluded it, so `ottoq_atoms_guard` demoted 39 of 63 to `must_do:false` with `guard_reason='svc_not_retirable'`, and `ottoq_assert_service_vocabulary()` named it as the only undeclared service. **`0383` derives it as `exterior` beside `sensor_clean`** (event-raised, performed at the vehicle, `lane_stalls=NULL`), adds it to the retirable set and declares it. Proven end to end on a rolled-back probe: derived `exterior`/`must_do:true` with no demotion, started in place, `ends_at` exactly the declared 12 minutes, `done`. **And it costs a real technician:** `exterior` sits inside the starter's `general_tech` subtraction (**10** at the twin depot, one vehicle each), so 63 atoms cannot all start at once — `digital` is the branch exempt from that pool and would have completed 63 walkarounds with nobody walking, which is why it was not used. **Take from this the general lesson, not the specific fix: a service name and a booking purpose that share a prefix are not the same mechanism, and the check is one query — does any function mention both?**

**AND A RULE FOR EVERY AVAILABILITY NUMBER, earned three times in one night.** A stall is offerable only as the **intersection of three gates**: the pointer (`stalls.reserved_by` / `current_vehicle_id` / `status`), the CALENDAR (`ottoq_stall_bookings` in `held`/`active`/`done`/`interrupted` overlapping the window), and, for `dcfc`/`l2`, the **OCPP charger not being `Faulted`** (0372). **Neither of the first two dominates:** measured on the twin depot in one moment, DCFC read 0 pointer-free against 10 calendar-free, L2 read 3 against 1, and staging read 59 against 12. Whichever single gate you quote, some stall type makes it look generous — the same defect shape `db/checks/0250` established for depot scope. CP-SAT is what caught it: it declined a frame our own pointer census called four-free, and all four were faulted.
**AND THE CALENDAR GATE HAS A CLOCK, WHICH IS THE NINTH INSTANCE OF THAT BUG CLASS AND THE WORST-BEHAVED (`db/checks/0326` §1).** `ottoq_stall_bookings.during` is a `tstzrange` in **SIM** time; `now()` is REAL. On a live run the two were **four hours apart** (real 07:16:41, sim 11:25:08), and computing the calendar gate against `now()` reports **every stall type 100% free — an empty depot, on a run holding 116 vehicles**: dcfc 10 of 10 instead of 2, l2 30 of 30 instead of 4, staging 113 of 113 instead of 54. It does not shift a number, it makes the gate answer yes to everything. Proof the column is sim and not real: `min(lower(during))` equals `min(booked_at_sim)` **to the microsecond** for `temp_hold`, `charge_l2` and `charge_dcfc`, while `booked_at` is hours off. **So every calendar predicate is written against the sim clock, and `now()` never appears in one.** (The sentence above was checked and survives: its *"L2 read 3 against 1"* would have read 30 under the wrong clock, so that measurement was in the right domain.)
**AND A FOURTH GATE-FAILURE SHAPE, this one INSIDE the pointer (`0326` §2, G121).** The three pointer fields can disagree with each other: exactly three stalls in the twin depot carry `status='available'` **together with** a live `current_vehicle_id` and `reserved_by`, all three `dcfc`, all three pointing at a vehicle that is physically **in a bay** — persistent across ticks, not a race. **Nothing will clear them:** `ottoq_release_vacated_spaces` phase (b) can clear a pointer but is bay-scoped by design (*"Never dcfc/l2/staging"*), and `ottoq_release_departed_spaces` (0329) reaches non-bay stalls but is **calendar-only** and inert (catalog default 0; its one stored row is run-scoped to a run purged on 09-15). So three of the ten fast chargers — the depot's scarcest resource, which `0250` shows is what refused proposals are asking for — are held by nobody, and **`HW.006`, the rule that names this defect and prescribes its repair, has never been evaluated once** because nothing probes `task_completion` (G122).

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
**CORRECTION 2026-09-08 (`db/checks/0145`), because this phase was about to be planned on a false premise.** This section used to say `ottoq_ab_runs` "already pairs OTTO-Q vs FIFO vs greedy under common random numbers, keyed by seed — wrap, don't rebuild." **It does not, and never has.** Measured: 68 rows, **one** policy (`otto_q`), **one** seed, 31 "groups" that each contain a single row, nothing written since 2026-08-24, and **no function anywhere in the database writes the table.** The schema is good — `ab_group_id`, seed, policy, scenario, ticks and twenty outcome columns — but it is a well-shaped *empty instrument*, not a working one. Wrap nothing; there is nothing there to wrap.

**What does exist, under another name, is the hard half.** `ottoq_determinism_pair` already runs two arms in one transaction on an identical seed, scenario, depot and sim-clock start, and proves them byte-identical across fourteen atoms. **That is a common-random-numbers engine**, built while proving determinism. And the twin's RNG is *stateless and content-addressed* — `twin.ottoq_sim_seeded_random(seed, salt)` is a pure hash with no sequence to fall out of step, keyed on **(seed, entity, sim-seconds-since-this-run's-own-start)** rather than run id or wall clock (hardened by 0052). **So CRN survives policy variation by construction, and Part B needs no new RNG.**

**AND A SECOND CORRECTION, `db/checks/0146` — the baselines do not pay the shield.** Measured: `ottoq_decide_tick` (otto_q) evaluates the 52-rule L1 shield and books through the stall calendar. **`ottoq_fifo_tick`, `ottoq_greedy_tick`, `ottoq_baseline_fifo` and greedy's two twin delegates evaluate no rules at all**, and three of them never touch the calendar. Run the comparison as it stands and greedy plausibly wins on `throughput_per_hr` — because it checks nothing. That number would be arithmetically correct, would carry a run ID, and would be worthless. **A run ID makes a number reproducible; it does not make it meaningful.**

The architectural point is larger than this phase: **the L1 shield is not part of the policy, it is part of the problem definition.** A policy chooses among feasible actions; the shield defines which actions are feasible. Swapping the policy must not swap the constraint set, exactly as it must not swap the seed. So the shield sits on the *hold-constant* side of the A/B, and C5 must either route every arm through the same L1 evaluation, or publish safety and throughput only ever together, and relabel the baselines as what they are — dispatch with no safety layer, not "OTTO-Q without the clever part."

The real gap is therefore narrow: give the pair rig a `p_policy`, score both arms into `ottoq_ab_runs`, and invert the verdict — the determinism pair passes when the arms are *identical*; the A/B pair passes when the arms are identical **on the world** and differ **only on what the policy decided**. That last assertion has no precedent in the existing rig and is the one genuinely new thing to build.
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
