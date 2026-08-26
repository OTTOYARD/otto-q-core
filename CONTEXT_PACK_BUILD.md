# CONTEXT PACK — BUILD BASELINE & TASK SPECS
*Audience: Claude Code (primary). This is the honest state of the codebase and the expanded spec for tasks A0–A9. Where this document and the repo disagree, the repo is reality — update this doc, don't trust it blindly.*

---

## 1. Honest technical baseline (as of late Aug 2026)
**What v1 genuinely is:** a wave-based scheduling engine for EV/AV depot operations — vehicle state machine, furthest-first stall assignment, demand-charge management, DCFC thermal tracking with derating/cooldown. Corrected overnight throughput ceiling ≈118 vehicles (72 DCFC + 46 L2) after thermal and scheduling friction. The energy differentiator: observe fleet telemetry, forecast depot returns, pre-position stall reservations and battery scheduling *before* formal reservations — without ever controlling dispatch.
**Known drift (fix, and never reintroduce):** cuOpt appears only as a code comment — actual orchestration is threshold/rule-based logic; the AI layer calls OpenAI/Anthropic via Supabase edge functions (not Nemotron as some pitch materials claimed); OTTO-Twin is Three.js/React (not Omniverse). Rule going forward: **no external claim the repo can't demonstrate.** AUDIT.md (task A1) is the enforcement mechanism.
**Known security debt:** anon keys previously committed to a then-public repo; JWT verification disabled on the `cuopt-optimize` Supabase edge function. A0 exists because of this.
**Stack facts:** Supabase (Postgres + edge functions) backend; Three.js/React twin; repo now private.

## 2. Architecture doctrine (constraints on every design decision)
1. **Orchestrate, never actuate.** We ingest state and emit directives (when, where, why). No motion, flight, or joint control. Service bays/robotic cells are `DepotResource`s with capacity + duration that receive *work orders* addressed to their own controllers.
2. **Three contracts, one boundary.** `AssetState` in, `TaskDirective` out, `DepotResource` as the substrate. Everything protocol-specific lives in adapters behind one interface; the scheduler must never import a protocol library.
3. **Deterministic core; agents propose, core disposes.** Any LLM/agentic layer suggests; the constraint core decides. No LLM in the decision path of a directive.
4. **Every directive carries a reason code** — machine-readable constraint trace. Explainability is a product requirement (defense reviewers weigh determinism + traceability heavily), and it's also our audit log (A8).
5. **Asset classes are profiles, not types.** A USV is an energy curve + replenishment rates + turnaround task set + mission envelope. Adding a domain must never require touching the core.

## 3. Metric definitions (use everywhere, identically)
- **Sortie regeneration rate:** completed ready-cycles per asset per 24h through the node (recovery → serviced → redeployed counts as one).
- **Turnaround time:** recovery timestamp → ready-for-tasking timestamp, per asset, distribution not just mean.
- **Peak kW / demand:** highest 15-min rolling average at the node; report naive vs. orchestrated.
- **Utilization:** per DepotResource, busy-time / available-time.

## 4. Expanded task specs
**A0 — Security remediation.** Rotate every credential ever committed; purge from git history (filter-repo or equivalent); re-enable JWT verification on `cuopt-optimize`; run Supabase security advisors and fix criticals; add secret-scanning pre-commit hook + CI check. *Done when:* advisors clean of criticals, history purged, hooks in CI, PR summary readable by a non-engineer.
**A1 — Claims-vs-code audit.** Inventory every claim in repo docs/decks; produce AUDIT.md matrix: claim | code reality | gap | fix/remove | owner. Include the drift items in §1 explicitly. *Done when:* Chase can hand AUDIT.md to a diligence engineer without flinching.
**A2 — Canonical schemas.** JSON Schema + typed models for AssetState (id, class, position, energy/fuel state, health flags, availability, current task), TaskDirective (asset, action ∈ {proceed-to, charge, refuel, hold, service, rearm*, offload-data, deploy}, window, location/resource ref, priority, reason_code), DepotResource (type, capacity, service rates, setup/teardown, energy draw). *Rearm is modeled as a generic timed, gated resource task — no weapons logic, no munitions data; it's a duration + safety-interlock flag on a resource.* *Done when:* schemas versioned, documented, round-trip tested.
**A3 — Adapter interface + registry.** Abstract adapter (connect, subscribe→AssetState stream, dispatch(TaskDirective)→ack/nack, health). Registry with capability declaration. A `MockAdapter` proving the boundary. *Done when:* core compiles with zero protocol imports and the mock passes an end-to-end schedule cycle.
**A4 — Simulation harness.** Scenario files (YAML/JSON): fleet mix, arrival distributions, resource set, disturbances (asset failure, resource outage, comms gap). Player feeds adapters; collector emits §3 metrics + naive-baseline comparison (naive = first-come-first-served, no forecasting). Scenarios run in CI as regression. *Done when:* one command reproduces a scenario → metrics report.
**A5 — OCPP adapter.** CSMS-side integration for charger state + smart-charging directives, validated against an open-source charge-point simulator. **Dependency:** file REQ→Hermes (maps to R8) for current simulator recommendation before choosing. *Done when:* simulated charge session scheduled, throttled, and completed end-to-end by OTTO-Q with reason codes logged.
**A6 — MAVLink drone adapter.** Telemetry in (position, battery, state); directives out limited to mission/waypoint upload, hold, return-to-pad. Validate fully in ArduPilot SITL (**REQ→Hermes, R9**). On SITL pass: write `relay/for-chase/BUY-DRONE.md` with one specific sub-$1k COTS recommendation. *Done when:* SITL bird flies a node-assigned recovery→recharge(sim)→redeploy cycle driven by the scheduler.
**A7 — Simulated USV adapter (UMAA-shaped).** Consume the R7 digest (**REQ→Hermes**); emit/consume messages structured like UMAA interfaces relevant to sustainment (energy, health, availability, tasking); write a 2-page conformance-mapping doc (what we mirror, what we don't, why). Full UMAA conformance explicitly out of scope. *Done when:* sim USV completes the same cycle as A6's drone via the same core.
**A8 — Reason-coded audit log.** Persist every directive + constraint trace; minimal viewer (filter by asset/resource/time); export for demos. *Done when:* any directive in a demo can be explained in one click.
**A9 — OTTO-Twin littoral scenario.** Existing Three.js/React twin: littoral node servicing mixed USV/UAS/ground fleet, wired to the A4 harness (twin renders harness state — no separate logic). On-screen: naive vs. orchestrated sortie regen rate, turnaround, peak kW. Screen-capturable for B6. *Also:* backfill the commercial depot twin with the same naive-vs-orchestrated energy numbers — it owes the peak-kW/BESS comparison for investor diligence. *Done when:* a 90-second capture shows the delta unambiguously.

## 5. Sequencing notes
A0→A1 strictly first, in order. A2→A3→A4 next (the spine). A5–A7 parallelizable after A4; file their REQs early so Hermes answers land before you need them. A8 anytime after A2. A9 last. If blocked, take the next unblocked task — never idle, never guess facts.
