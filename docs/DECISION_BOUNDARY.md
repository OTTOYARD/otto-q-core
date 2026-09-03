# Where decisions live: deterministic core vs. agentic layer

Chase, 2026-09-02: *"Non-urgent cleaning or inspection could occur during the
overnight turnaround. Vehicles all return home each night for full charge,
cleaning, inspections, and service. Those non-urgent events can be queued by
OTTO-Q for that timing, unless it determines it is necessary before then, or
during another daily stop when depot reservations are available. You decide
whether that should be deterministic or agentic, and all other decisions with
where they belong."*

This is the standing answer. It is a rule for placing **any** future decision,
not just this one.

---

## The rule

> **The deterministic core decides what is ALLOWED and what MUST happen.
> The agentic layer decides what is WORTH doing among the allowed.**

Everything follows from that, and it is not a style preference — it is what
makes the system certifiable. The deterministic core is the part we can prove
reproduces byte-for-byte from a seed. Anything we put in it, we can defend. The
moment a decision that can strand an asset or breach a constraint moves into a
layer we cannot replay, the certification stops meaning anything.

Corollary, already the house rule (CLAUDE.md 6): **agents propose, the solver
disposes.** The agentic layer never writes a final assignment. It emits a
proposal; the deterministic path enacts it or refuses it, and the refusal is
recorded.

### Deterministic core owns

- **Safety and legality.** Anything whose violation is a defect: power caps,
  double-booking, incompatible asset/point pairing, state-machine validity.
- **Obligation.** Every need carries a window — a not-before and a must-by. The
  must-by is deterministic and non-negotiable.
- **Escalation.** The predicate that promotes non-urgent work to urgent
  (component hours, wear thresholds, SLA jeopardy, safety) is a rule, evaluated
  every tick, logged every time.
- **The opportunistic fill.** If an asset is on site, a compatible point is
  free, and nothing urgent is waiting, take it. Deliberately greedy and dumb —
  it is a safety valve, not a strategy.
- **Anything that can strand an asset.**

### Agentic layer owns

- **Which** deferrable work to pull forward into a daytime gap, given a forecast
  of tonight's load. This is prediction: *"tonight is tight, do this wash now."*
- **Ordering within the overnight window** to flatten peak kW or ride a cheap
  tariff.
- **Estimating** overnight capacity against expected demand.
- Anything where being wrong costs efficiency, never safety and never an asset.

### The test, when it is not obvious

Ask: **if this decision were made badly, would an asset be stranded, a
constraint breached, or a number unreproducible?**

- Yes → deterministic. No exceptions.
- No, it would just be *suboptimal* → agentic.

A second, sharper form: **could you write the correct answer down in advance
without knowing the future?** If yes it is a rule. If it needs a forecast, it is
a proposal.

---

## Applied to the overnight turnaround

| decision | lives | why |
|---|---|---|
| Non-urgent work targets the overnight window by default | **deterministic** | A written-down default, no forecast needed |
| A need's must-by (cadence, wear, SLA) | **deterministic** | Violating it is a defect |
| Promoting work to urgent when a threshold trips | **deterministic** | Rule; must fire every tick, logged |
| Taking a free compatible point during a daytime stop | **deterministic** | Greedy safety valve; only when nothing urgent waits |
| *Choosing which* deferrable jobs to pull into a scarce daytime gap | **agentic** | Needs tonight's forecast; being wrong costs efficiency only |
| Sequencing the overnight wave for cost/peak | **agentic** | Optimization over an already-legal set |
| Overriding a must-by | **neither** | Nothing may do this |

The last row matters. There must be no path — deterministic or agentic — that
moves a must-by. If the overnight window cannot absorb the work, the correct
behaviour is to escalate and report, not to quietly slip the obligation.

---

## What already exists (verified 2026-09-02, not assumed)

The architecture Chase described is already present in outline. Checked live
rather than taken from documentation:

| piece | state |
|---|---|
| `ottoq_is_depot_night` | live, 2 callers |
| `ottoq_is_overnight_holdout` | live, 2 callers |
| `twin.ottoq_sim_overnight_service_drain` | live, 2 callers |
| `service_cadence_policy` | 15 rows |
| `ottoq_plan_overnight_wave` | **0 callers** |
| `ottoq_wave_plan` | **0 rows** |
| `TW.002.overnight_staging` rule | active, evaluator exists, **0 evaluations** |

So the night *predicate* is wired and the twin *drains* overnight, but the
**wave planner is orphaned** and the rule that would encode the overnight
staging policy **has never been evaluated**.

The deterministic slot for Chase's model already exists and is empty. The build
is to fill it, not to invent a parallel mechanism (CLAUDE.md 5: verify,
consolidate, extend).

---

## The larger finding this surfaced

Nine of twenty-nine **active** rules have never been evaluated. Six are
`block` severity — the class CLAUDE.md 2.5 calls "inviolable constraints."

**Class A — cannot fire: the action is never probed.** No live rule shares
their action, so the engine never asks about it.

`SM.001.vehicle_transition_validity` (block) · `SM.003.stall_transition_validity`
(block) · `SM.006.bess_transition_validity` (block) ·
`SM.004.role_gated_actions` (block) · `SM.005.audit_note_required_on_overrides`
(block) · `TW.004.tariff_window`

**Class B — should have fired and did not.** Their action *is* probed and other
rules on the same action evaluate 219,236 times each.

`HW.006.physical_presence_verification` (block, `task_completion`) ·
`TW.002.overnight_staging` (`task_completion`) ·
`SLA.002.max_queue_depth` (`arrival`)

Class A is structural and certain: the actions are absent from the probe
surface. Class B is not yet explained — the rule is filtered out after the
action matches, and **retention has not been excluded** as an alternative
(evaluations are purged on a 90-day window, so a rule that last fired outside it
would also read zero). Do not treat Class B as convicted until that is checked.

Either way: a rule registered `active` with a `block` enforcement that has never
run is not a constraint. It is documentation. The count of rules is not the
measure of Layer 1 — the count of rules that *evaluate* is, and those differ by
nine.
