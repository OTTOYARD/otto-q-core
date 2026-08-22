# CONFORMANCE_FINDINGS.md — is OTTO-Q a platform, or N products?

**Run 4 · Phase C11 · 2026-08-22.** Instrument: `conformance/`. 43 tests pass.
CLAUDE.md instructs that this document be written *"willing to conclude either
way."* What follows is written to that instruction.

---

## The verdict

> **Platform — provisionally, and with one identified exception that is a genuine
> solver change rather than a missing field.**
>
> Four packs across four unrelated sectors load against a closed spec and schedule
> to zero invariant violations with **zero kernel modification**. That is the
> thesis's central claim and it survived the test.
>
> It is called *provisional* for three specific reasons, each named below. Two are
> gaps in the instrument, not in the kernel. One — vertiport pad separation — is a
> real hole in the kernel's resource model.

| Pack | Status | Loads | Solves | Findings | Unexercised claims |
|---|---|---|---|---|---|
| robotaxi | reference | ✅ | ✅ 504 ops | none | 1 |
| yard-logistics | build | ✅ | ✅ 40 ops | none | 1 |
| mining | paper | ✅ | ✅ 60 ops | none | **5 of 6** |
| vertiport | paper | ✅ | ✅ 48 ops | **2** | 1 |

Zero power-cap violations, zero point overlaps, zero operations on incapable
points, across all four packs. The verifier is not vacuous: it has negative tests
for each of the three invariants, and rejects each when deliberately broken.

---

## 1. The one genuine solver change: **V5 — pad separation**

FAA EB 105A requires a minimum 1.5× aircraft-diameter separation between *active*
vertipads. That is a **pairwise spatial exclusion**: two named points may not be
simultaneously active.

Every resource mechanism the kernel has is either

- **per-point** — `exclusive_occupancy` (the `ottoq_stall_bookings` EXCLUDE
  constraint), or
- **site-wide** — `site_power_cap`.

**Nothing expresses a constraint between two specific points.** No declarative
field fixes this; a pack can declare the pairing, but the scheduler has no notion
of "if A is busy, B must be idle" to enforce it. This is classified
`SOLVER_CHANGE` in the pack file itself, and the classification was written
*before* the harness ran.

**Honest scope of the damage.** This is not a vertiport-only concern. Pairwise
exclusion is the shape of any spatial-interference constraint — adjacent bays that
share a door swing, two lifts that cannot both extend, a crane envelope over two
stalls. The kernel has not needed it yet because robotaxi and yard depots are
modelled as independent points. **It is a real limit of the resource model, and
the first one this project has found that a declarative mechanism cannot close.**

Per CLAUDE.md 2.2 this is a platform-thesis finding, and it is escalated here
rather than absorbed. It does not falsify the thesis — one solver extension across
four sectors is a good ratio — but it is the honest cost of entry to vertiport.

## 2. The one that looks harder than it is: **V4 — battery cooling**

A 20-minute cooldown before fast charge if SoC > 90% on landing. H3 rates this
among the three hardest vertiport constraints.

The kernel already has `min_gap_on_point` — the DCFC cooldown, 18 minutes in the
throughput model (CLAUDE.md 2.5). But that gap is a property of the **point**,
between successive sessions. V4's gap is a property of the **asset**, between its
own landing and its own charge, and is **conditional on SoC**.

Classified `DECLARATIVE`: the shape mirrors one the kernel already implements, and
an asset-side conditional gap looks like a new field plus a check, not a new
scheduling concept. **That classification is a claim, not a result** — it is
recorded as such so a later round can confirm or overturn it.

---

## 3. Where the instrument is weaker than the verdict

Stated plainly, because a verdict is only as good as what produced it.

### 3.1 `movement_as_operation` is claimed by four packs and exercised by none

The harness schedules service operations; it does not schedule the inter-point
moves between them. So the mechanism CLAUDE.md 2.3 calls one of the two places
throughput lives — *"inter-point moves as scheduled operations… where deadlock
happens"* — is **asserted by every pack and tested by nothing here**.

This matters most for **mining C4** (trolley-path dependency), whose entire
conformance argument rests on modelling a trolley segment as a point that a move
consumes. That argument is currently unexercised.

### 3.2 Mining passes on five unexamined claims

Mining reports zero findings, and that number is misleading on its own. **Five of
its six constraints name a mechanism the run never reached**, including the one H2
calls *"anathema to a solver-based kernel"*:

| Constraint | Claims | Exercised? |
|---|---|---|
| C1 clearance before bay entry | `movement_as_operation` | ❌ |
| C3 energy resupply window | `threshold_ladder` | ❌ |
| C4 trolley path dependency | `movement_as_operation` | ❌ |
| C5 multi-threshold maintenance | `threshold_ladder` | ❌ |
| **C6 operator override** | `work_side_refusal` | ❌ |
| C2 exclusive bay use | `exclusive_occupancy` | ✅ |

**C6 is the open question of this phase.** CLAUDE.md 2.7 makes work-side refusal a
first-class event triggering re-solve, and C9 implements `refuse()`. *If* a human
override is a refusal with a human actor, the kernel already bends and H2's
prediction is wrong. *If* the override must additionally invalidate a constraint
the solver treated as hard — keep hauling a truck the rules say must be serviced —
then `work_side_refusal` does not cover it and mining acquires a `SOLVER_CHANGE`
finding of its own.

**The harness cannot currently tell these apart, and the verdict above should be
read knowing that.**

### 3.3 The harness tests expressibility, not throughput

A pack passing here has shown its world is expressible in kernel mechanisms and
admits a feasible schedule. It has **not** shown the production decide path
produces good throughput on it — that is C6/C8's question, measured separately and
on a live twin. The harness's scheduler is deliberately simple (earliest-fit under
kernel mechanisms only), because if a pack cannot be scheduled even by an
unambitious algorithm, the obstacle is the *model*, which is what is under test.
Conflating the two would let a pack pass on the strength of the engine's tuning
rather than the kernel's generality.

---

## 4. What would settle it

In priority order, each a concrete next experiment rather than a direction:

1. **Schedule movements in the harness.** Closes 3.1 and puts mining C4's central
   argument under test. Largest evidence gain per unit of work.
2. **Model an operator override and run it against `refuse()`.** Settles mining C6
   — the single finding most likely to change this verdict.
3. **Attempt a declarative asset-side conditional gap.** Confirms or overturns
   V4's `DECLARATIVE` classification.
4. **Design pairwise point exclusion.** The one acknowledged solver change. Worth
   scoping before it is committed to, since it touches the resource model that the
   determinism work in Run 3 has just been stabilised around.

---

## 5. The result that was not designed for, and is the strongest signal here

Two unrelated sectors independently describe **the same missing capability**.

H1's gap table (intralogistics) lists `Arbitrate Multi-Party Bay Access` — fair,
contractual, signed arbitration of a physical service bay between operators —
owner: **None**. H3's open questions (vertiport) ask: *"How do vertiport operators
plan to handle inter-operator arbitration for pad scheduling?"*

Neither research file was written with the other in view. Both arrive at a hole
that no standard and no product fills, and it is precisely the hole the kernel's
multi-tenant terms (`ottoq_fleet_operator_slas`), signed event stream, and
propose/dispose audit trail are shaped to fill.

**That convergence is not evidence that the kernel is technically general — §1 is
the honest accounting there. It is evidence that the generality is aimed at
something real.** Those are different claims and this document keeps them apart.
