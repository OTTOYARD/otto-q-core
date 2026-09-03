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

This section was rewritten twice. Both earlier readings are recorded below,
because the way the claim narrowed is the useful part.

### The finding, stated correctly

Every rule declares `applies_to_actions`. The engine announces a specific set of
action names to the shield probe. **The nine dead rules are scoped to action
names the engine never announces.** They are not broken and not misconfigured —
they are addressed to events that are never raised.

Announced, and evaluating: `task_start` · `stall_assignment` · `redeployment` ·
`release` · `oem_acceptance` · `bess_charge` / `bess_discharge` /
`bess_dispatch` · `visit_progress_check`

Never announced, and therefore unreachable: `vehicle_state_change` ·
`stall_state_change` · `bess_state_change` · `arrival` · `queue_admission` ·
`post_redeployment_staging` · `cost_advisory` · `schedule_optimization` ·
`progression_decision_insert` · the role-gated set (`tech_override`,
`emergency_stop`, `brain_pause`, …) · and probably `task_completion`, which
appears in one live rule that also covers announced actions, so its evaluations
cannot be attributed to it.

The confirmation is exact: of 13 active rules covering `task_start`, **13 of 13
evaluate**. Of the 16 that do not, 7 evaluate — via the other announced actions
above — and the remaining 9 are precisely those with no announced action.

### The part that matters most

`vehicle_state_change`, `stall_state_change` and `bess_state_change` are all in
the unannounced set. The engine changes vehicle, stall and BESS state on every
tick and **never announces a transition to the rules layer.**

So `SM.001.vehicle_transition_validity`, `SM.003.stall_transition_validity` and
`SM.006.bess_transition_validity` — three `block`-severity guards whose entire
job is "is this transition legal" — have never run and cannot run.

The rules layer is wired to *decisions* and not to *state transitions*. That is
a structural gap, not a bug in any one rule, and it is the honest qualifier on
"52 versioned rules, inviolable constraints": the constraint surface covers what
the engine chooses, not what the engine becomes.

### How this claim narrowed — kept deliberately

**First reading (wrong).** "Rules with `log_only` enforcement are never
evaluated." Refuted immediately: one `log_only` rule does evaluate, and six
`block` rules do not.

**Second reading (right conclusion, unsound argument).** "Six rules cannot fire
because no *evaluating* rule shares their action — structural and certain."
The reasoning was circular: which rules evaluate was measured over the same
window as the thing being explained. Then `ottoq_rule_evaluations` turned out to
span only **five days** (2026-08-28 to 2026-09-02, 3.9M rows, 20 distinct
rules), so a rule that fires rarely would read zero for reasons of retention
alone. The conclusion survived; the argument for it did not.

**Third reading (this one).** Settled statically, immune to retention, by asking
which action names the engine actually passes to the probe rather than which
rules happen to have fired lately.

The lesson is the one from `db/checks/0081`: an argument from "what has
happened recently" is worth less than an argument from "what the code can do at
all," and a five-day window is not history.

### Not yet established

Whether each unannounced action *should* be announced. Three of them almost
certainly should — the transition-validity guards are the reason those rules
were written. Others may be legitimately aspirational: `cost_advisory` and
`schedule_optimization` read like hooks for a layer that does not exist yet, and
wiring a rule to an event nobody raises is not obviously better than leaving it
declared and dormant.

What is not defensible is the current state being *invisible*. A rule registered
`active` at `block` severity that cannot fire should say so in the registry, so
the count of rules and the count of enforced constraints stop being the same
number in every report that quotes them.
