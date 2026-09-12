# R-13 — What objective does a depot-turnaround scheduler actually optimise?

**Filed** 2026-09-09 by Claude Code (build track). **Priority: highest open research item.**
**Blocks** BUILD_QUEUE #4 (G45), and through it #14 (the A/B instrument) and roadmap item B.

## Why this is blocking, stated precisely

Measured against the live `otto-q-core` catalog on 2026-09-09: a search of every
function in `public`, `ottoq` and `twin` for `objective|weight` returns exactly one
match, and it is the energy MPC lookahead. **The scheduling engine has no objective
function.** What it has instead are fixed greedy orders — most-depleted-first,
earliest-deadline-first, shortest-job-first, a deterministic tiebreak.

The consequence is not cosmetic. There is no scalar by which two feasible schedules
can be compared, which means:

* the agent layer has nothing to propose *against* — a proposer can offer an
  assignment and the deterministic path can rule it legal, but neither can say it
  is **better**;
* `ottoq_ab_runs` cannot be made meaningful by fixing the instrument, because the
  quantity it would measure has not been defined;
* CLAUDE.md 2.5 requires "multi-term objective with exposed weights (tardiness,
  energy cost vs. tariff, peak-kW excursion, inter-point moves)" and that
  requirement is currently unmet in the engine. Weights exist only in the CP-SAT
  prototype (`solvers/cpsat/model.py`: tardiness 10/min, on-peak kW-min 1, peak
  excursion 20/kW, move 15) and those four numbers have no cited provenance.

## The tension we need resolved, not just described

`intent/intent_v1.json` deliberately chose **lexicographic ordering over eleven
objectives, never summed into a dollar scale**, and cited R-10 for the reason: no
robotaxi operator publishes a dollar value for a late minute, so a weight would be
"a price on lateness nobody agreed to." Readiness and service completion are
therefore modelled as *floors*, not coefficients.

That is defensible as commander's intent. It is a problem for a solver, which needs
either a scalar or a well-defined lexicographic/ε-constraint procedure. **The
question is whether the field resolves this by (a) hierarchical / lexicographic
optimisation, (b) ε-constraint with a primary objective and the rest as bounds,
(c) goal programming against targets, or (d) simply accepting elicited weights.**

## Questions, each answerable and each needing a source with a date and URL

1. In published **flexible flow-shop / RCPSP** scheduling with due dates and a
   shared renewable resource, what is the standard objective structure? Name the
   canonical formulations (weighted tardiness, makespan, resource levelling) and
   say which are used when deadlines are hard rather than costed.
2. For **EV depot / bus depot charge scheduling** specifically: what objectives
   appear in the literature and in vendor systems, and how is the **15-minute
   demand charge** represented — as a term in the objective, as a hard constraint,
   or as a second-stage problem? A peak is a max over intervals, not a sum, and
   that shape matters to whether it can be a linear objective term at all.
3. When one criterion is a **hard readiness floor** and others are costs, does the
   field use lexicographic optimisation, ε-constraint, or goal programming? What
   does each cost in solver time on problems of our size (~120 assets, ~330 service
   points, 24-hour horizon)?
4. Is there **any published or vendor-stated figure** for the cost of an
   autonomous-fleet asset being unavailable per hour, or late to a required-ready
   time? R-10 found none for robotaxi. Widen it: transit bus, rental fleet,
   heavy-truck depot, last-mile van. A transferable figure with its caveats is more
   useful than another NOT_FOUND, but a clean NOT_FOUND is a real answer here.
5. **Sequence-dependent minimum gaps** (our DCFC cooldown, currently absent from the
   engine entirely — zero catalog matches): how are charger thermal-recovery
   constraints represented in published EV-charging schedulers, and are there
   sourced figures for minimum gap by cabinet class? Our 18-minute figure exists
   only in the CP-SAT prototype and I cannot trace where it came from.

## What we will do with the answer

Design the objective structure for the kernel, then wire it so that (a) the CP-SAT
prototype and the live decide path optimise the *same* declared objective, and
(b) `ottoq_ab_runs` finally has a quantity to compare policies on. Whatever comes
back gets recorded as a Hermes deliverable would be: the claim, the version or date
it applies to, and a URL per claim.

**A weight without a source is exactly what `intent_v1` refused to invent, and this
request exists so we do not quietly invent four of them in the solver instead.**

---

## NARROWING, added 2026-09-12 by Claude Code — read this before answering

The request stands, but two of its questions are now **less open than when it was
filed**, and answering the wrong ones would waste a Hermes run.

What changed is measurement, not the world. The Python layer turns out to already
implement a complete regime-aware lexicographic objective: `intent/intent_v1.json`
declares 11 ranked objectives and 6 regimes, `intent/solve.py` resolves a regime to
a pass sequence, `policies/regime.py` drives the solver from the declared intent,
and `solvers/cpsat/model.py` implements `min_tardy` / `min_peak` / `min_flow` with
ε-constraints and a `rejection_saving_ceiling` that stops a weight set from scoring
better by dropping assets. It is tested, with measured trade-offs
(`policies/test_regime.py`: `grid_peak` → flow 2937 min / peak 150 kW; `rush` →
1676 min / 400 kW). It has **zero production callers** — that is a wiring defect on
our side, not a research question.

**So please DE-PRIORITISE** the "what structure" half: whether to use a weighted sum,
lexicographic ordering, or ε-constraint. We have chosen lexicographic-with-ε and
built it. A one-paragraph sanity check against published practice is useful; a
survey is not.

**And please PRIORITISE these, in this order:**

1. **The weights and the ranking.** Our objectives are ranked by assertion, not by
   evidence. What does an operator of a depot-like facility actually trade off, and
   is there any published or vendor-documented ordering between *asset readiness*,
   *demand-charge exposure*, and *labour/bay occupancy*? A source for the ordering
   matters more to us than a source for any single weight.
2. **Cost of unavailability.** The one number that makes `readiness` rankable
   against `energy_cost` in the same unit. Per asset-hour, for any fleet type with
   a published figure (robotaxi, yard tractor, delivery van — whichever is
   sourceable). Without it the first-ranked objective and the third cannot be
   compared at all.
3. **Demand-charge representation.** Whether practitioners optimise the 15-minute
   rolling peak directly or a proxy, and over what horizon a commitment is made.
4. **DCFC cooldown minimum gap** (unchanged, still needed, BUILD_QUEUE #5).

Every answer still needs the claim, the version or date it applies to, and a URL —
a fact without a URL is not a fact, whoever fetched it (CLAUDE.md Part 1 §3).
