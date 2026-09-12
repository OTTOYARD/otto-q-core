# V1 DEMO PLAN — prove it works, then fund the rest

**Decided 2026-09-12, 10:40 AM CT, by Chase.** This re-sequences the build. It does not
replace CLAUDE.md's runs; it says which of their deliverables ship in v1, which are
declared "instrumented, not built", and which wait for a funded team. Future sessions
follow this file's order. When it conflicts with BUILD_QUEUE's order, this file wins.

Chase's words, verbatim, so the authority is his and not inferred:

> "Here is our technology that works. It does have these temporary tools that we hope to
> rip out and make proprietary once we have a team ... But at least it works now and
> here's what we plan to do in the future with our research team."
>
> "I at least need to be able to show demos, why our technology is important and
> proprietary, and then explain what next steps would be in the next level of build out
> once our team is funded."

---

## 0. The honest position (measured 2026-09-12, not estimated)

| Layer | Done | What exists | What is missing |
|---|---|---|---|
| Deterministic core | ~80% | 14-atom byte-identical certification; 6 of 7 flagship columns reproduced across 3 days; the 7th convicted to the line, fix drafted (0256) | one carrier to land; then FREEZE |
| Agentic | ~35% | propose/dispose shield, deferral, `h_prop` in the verdict, CP-SAT prototype, declared objective + regimes | **none of it is wired to the engine** — the Python layer has zero production callers |
| Learning | ~10% | every decision carries a run id + hash; `intent/learn.py` refuses to train on twin replays (correctly) | an outcome signal that is not our own decisions replayed — i.e. real depot data |
| Validation / KPIs | ~40% | 5-KPI CLI (run id → KPIs, 50 ms); 2 of 11 objectives computable; second floor drafted (0257) | **the A/B against FIFO/greedy has never been run** — the one number that validates the claim |

**Blended: ~40%.** Not 80. Not 10. The certification work converged; it also consumed
~100% of effort for two weeks while the two layers the pitch needs did not move.

---

## 1. Are we a wrapper? No — and the reason is the pitch

A wrapper adds convenience. This adds **guarantees the vendor cannot make**:

1. **Propose / dispose.** Any solver — cuOpt, CP-SAT, an LLM — may *propose*. A
   deterministic, rules-checked disposer decides, and every proposal is hashed into a
   certified verdict. R-12 established the leading GPU solver cannot promise
   byte-identical output at all; this is the layer that makes such a solver safe to
   trust with a fleet. **Using vendor solvers is not the weakness of the architecture.
   It is its purpose.**
2. **Reproducibility as a product property.** Same inputs → byte-identical outputs across
   fourteen independent streams, verified continuously (CLAUDE.md 2.9a).
3. **The settlement object.** Every completed operation terminates in a signed, tariffed
   ServiceDetailRecord. Nothing standardizes service events in any sector (2.6).
4. **The Recall Decision** — the single, ledgered touchpoint to the work side (2.7).
5. **A twin calibrated from real datasets** (ACN-Data, NYC TLC, CA DMV, NOAA).

**Say in the deck:** *"We use best-in-class solvers as proposers. Our IP is the layer
that constrains, certifies and settles what they propose."*

**Do not say:** "we will rip out the solver." Nobody should rebuild CP-SAT. What becomes
proprietary with funding is **data**: the duration model calibrated on your own fleet,
the learned recall policy, sector packs. That is a better investor story than a rewrite.

---

## 2. What is proprietary, temporary, and next — the deck's three columns

| PROPRIETARY (ours, keep) | TEMPORARY / OFF-THE-SHELF (say so) | NEXT (funded phase) |
|---|---|---|
| propose/dispose shield + 29-rule L1 layer | OR-Tools CP-SAT as proposer (permanent, not temporary) | duration model fitted to real fleet data |
| 14-atom certification + canon matrix | cuOpt / any LLM as proposer | learning loop on real outcomes |
| SDR settlement object | dashboards: Grafana/Metabase over our views — **do not build UI** | sector packs (yard-logistics, mining, vertiport) |
| Recall Decision interface + ledger | OCPP backend: an open-source CSMS if a live charger is ever demoed | OCPI / VDA 5050 adapters (C10) |
| DB-native twin + calibration layer | Supabase / pg_cron as the runtime | pack conformance harness (C11) |
| run-id / content-hash discipline | | Site Alpha multi-tenant sweep (C8) |

---

## 3. The five demos — what each proves, what each needs

Every demo runs from a **run id** and reproduces. No screenshot without one.

| # | Demo | Proves | Status | Needs |
|---|---|---|---|---|
| D1 | **Same inputs, same outputs.** Run a pair; show 14 atoms match byte-for-byte. Change the seed; show they differ. | reproducibility is real | **works today** | freeze the core (Phase 0) |
| D2 | **OTTO-Q vs FIFO vs greedy on the identical world.** Same seed, same depot, same shield; only the policy differs. Throughput + safety published together. | the core claim | **never run** | Phase 1 |
| D3 | **Agents propose, solver disposes.** A proposer submits a schedule; the shield refuses the unsafe parts with reason codes; the accepted parts are hashed into the verdict. | "agentic" is true, not adjacent | plumbing exists; no proposer wired | Phase 2 |
| D4 | **Every completed operation → a settlement record.** Show the SDRs for one run, signed and tariffed. | the moat object | **works today** (179k SDRs); the visit row cannot say "completed" (0181) — show the SDRs, not the row | none for v1 |
| D5 | **A charger dies mid-run; the site re-solves.** Inject a fault; show bookings move; show the event and the recall. | resilience | grid fixture has an injected-fault path; the nine C7 scenarios are partial | Phase 3, if time |

D1 + D2 + D3 + D4 is a fundable demo. D5 is a bonus.

---

## 4. The plan, with stopping rules

Estimates are in **sessions** (one working session ≈ half a day of build) and carry the
uncertainty my track record has earned. Each phase has a stopping rule so it cannot
become a research program.

### Phase 0 — freeze the deterministic core  (now → round 39, ~1 day)
- Judge round 38 (11:45 AM CT). Apply 0256 → 0257 → 0258. Schedule round 39.
- **Stopping rule:** when all seven flagship columns agree across two consecutive rounds
  once, the core is **v1-certified**. After that, certification is a regression gate that
  runs on its own schedule. **No new instruments. No new atoms.** Open items (G8, G9, G10,
  G12–G14, G26, 4h, 4i) are listed as known and deferred.
- Deliverable: `CERTIFICATION_STATUS.md` — the matrix, the run ids, the open list. This
  is D1's evidence page.

### Phase 1 — the A/B  (3–5 sessions)  → D2
- Add `p_policy` to the pair rig; both arms tick the identical world; only the policy
  differs. Score both into `ottoq_ab_runs` (the empty instrument, 0145).
- **The shield is held constant** (0146): every arm is evaluated by the same 29 rules, so
  greedy cannot "win" by checking nothing. If routing the baselines through L1 turns out
  to be more than two sessions, fall back to publishing safety and throughput together
  and labelling the baselines as "no safety layer" — and say so on the slide.
- One committed comparison: seed, scenario, depot, run ids, results table.
- **Stopping rule:** one reproducible comparison, byte-identical on re-run. Not a sweep.
- Risk: the number may not flatter us. That is the point of running it before the deck.

### Phase 2 — wire one proposer, then a second  (3–5 sessions)  → D3
- CP-SAT through the existing door: `ottoq_submit_external_proposal` under the deferral
  pattern, registered in `ottoq_certified_proposers`, hashed by `h_prop`. BUILD_QUEUE #4
  already says it: "an adapter + certification, not a design."
- Then an **LLM proposer** as the second source — the showpiece: an LLM proposes, the
  shield refuses the unsafe parts, each refusal is a ledger row with a reason code.
  *(Decision for Chase: this uses an external model API at a small cost per demo. Yes/no.)*
- **Stopping rule:** one certified pair with a proposer active, `h_prop` non-trivial,
  arms byte-identical. One refusal shown with its reason code.

### Phase 3 — package  (2–3 sessions)
- `demo/` — one script per demo, each taking a run id, each re-runnable.
- A Grafana or Metabase board over the existing KPI views. Off the shelf. No UI code.
- The one-page "proprietary / temporary / next" (section 2 of this file) as a slide.
- D5 only if Phases 1–2 finished early.

### Phase 4 — the funded build (not now)
Duration model from real data → learning loop on real outcomes → adapters (C10) →
conformance (C11) → Site Alpha (C8). Each one is a research program and is pitched as
one.

**Total to a fundable demo: roughly 10–14 sessions.** If Phase 1 or 2 runs past its
stopping rule, stop and ship what works rather than deepening.

---

## 5. What changes in how I work

- **"Done" means a run id and a re-run.** Not a passing test I wrote in the same hour.
- No new certification instruments after Phase 0. A blind spot found later is logged in
  BUILD_QUEUE and fixed in Phase 4 unless it breaks D1.
- Every session starts by reading this file's phase and ends by moving the phase
  checklist below. Depth is bounded by the stopping rules, not by curiosity.

## 6. Checklist

- [ ] Phase 0 — round 38 judged; 0256/0257/0258 applied; round 39 scheduled
- [ ] Phase 0 — two consecutive rounds, 7/7 agree; `CERTIFICATION_STATUS.md` written; core FROZEN
- [ ] Phase 1 — `p_policy` in the pair rig; shield held constant; one committed comparison
      *(2026-09-12: rig drafted as `db/migrations/0261` + `db/checks/0185` + `policies/AB_TWIN.md`; the seat is a proposer, so the shield is held constant by construction; applies after round 40 is judged)*
- [ ] Phase 2 — CP-SAT proposer certified; `h_prop` non-trivial in one pair *(2026-09-12: `bridge/` built and tested; `0259` precedence + `0260` fire ledger drafted, apply after round 39; then one live run, then the replay pair)*
- [ ] Phase 2 — LLM proposer (Chase: yes, 2026-09-12); one refusal with reason code *(harness built: `bridge/llm_proposer.py`, 27 tests, priced + capped per run, seated by 0259 as `llm_advisor`; live fire + a shield refusal pending the apply window and an API key on the runner)*
- [ ] Phase 3 — `demo/` scripts D1–D4 run from run ids; dashboard up; slide written
- [ ] Phase 3 — D5 if time
